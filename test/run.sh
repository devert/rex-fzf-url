#!/usr/bin/env bash
# run.sh: run every test file, and exit 1 when one fails.
# Must stay compatible with macOS /bin/bash 3.2.
#
#   test/run.sh             run the tests
#   test/run.sh --coverage  also write coverage reports, with luacov for the
#                           Lua code, Devel::Cover for bin/extract-urls.pl, and
#                           kcov for the bash scripts, and print the file://
#                           URL of the page that links to the HTML reports
#   test/run.sh --open      the same as --coverage, then also open that page
#                           in the browser
#
# Coverage needs luacov and luacov-html in lua_modules/, Devel::Cover in
# local/, and kcov. To install them, run test/install-coverage-tools.sh.
set -u

cd "$(dirname "$0")/.." || exit 1

coverage=
open=
for a in "$@"; do
  case $a in
    --coverage) coverage=1 ;;
    --open) coverage=1 open=1 ;;
    *) echo "run.sh: unknown option $a" >&2; exit 1 ;;
  esac
done

lua=$(command -v luajit || command -v lua) || { echo "run.sh: luajit or lua not found" >&2; exit 1; }
lua_flags=()
if [[ -n "$coverage" ]]; then
  if [[ ! -x lua_modules/bin/luacov || ! -x local/bin/cover ]] || ! command -v kcov >/dev/null; then
    echo "run.sh: coverage tools not found. To install them, run: test/install-coverage-tools.sh" >&2
    exit 1
  fi
  rm -rf luacov.stats.out luacov.report.out luacov-html cover_db kcov
  export LUA_PATH="$PWD/lua_modules/share/lua/5.1/?.lua;$PWD/lua_modules/share/lua/5.1/?/init.lua;;"
  export PERL5LIB="$PWD/local/lib/perl5${PERL5LIB:+:$PERL5LIB}"
  PATH="$PWD/lua_modules/bin:$PWD/local/bin:$PATH"
  lua_flags=(-lluacov)
  export PERL5OPT="-MDevel::Cover=-silent,1,-db,$PWD/cover_db"
fi

# Colors show only on a terminal, and not when NO_COLOR is set.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  bold=$'\033[1m' dim=$'\033[90m' green=$'\033[32m' red=$'\033[31m' reset=$'\033[0m'
else
  bold= dim= green= red= reset=
fi

# spin <label> <command> [arg ...]: run the command, and set $out to its
# output and $status to its exit status. On a terminal, show a spinner and
# the label while the command runs.
spin_file=$(mktemp)
spin_pid=
trap 'rm -f "$spin_file"' EXIT
trap '[[ -n "$spin_pid" ]] && kill "$spin_pid" 2>/dev/null; [[ -t 1 ]] && printf "\r\033[K\033[?25h"; exit 130' INT TERM
frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
spin() {
  local label=$1 i=0
  shift
  if [[ ! -t 1 ]]; then
    out=$("$@" 2>&1)
    status=$?
    return
  fi
  "$@" >"$spin_file" 2>&1 &
  spin_pid=$!
  printf '\033[?25l'
  while kill -0 "$spin_pid" 2>/dev/null; do
    printf '\r  %s%s%s %s' "$green" "${frames[i % 10]}" "$reset" "$label"
    i=$((i + 1))
    sleep 0.08
  done
  wait "$spin_pid"
  status=$?
  spin_pid=
  printf '\r\033[K\033[?25h'
  out=$(cat "$spin_file")
}

# run_test <file>: run one test file.
run_test() {
  case $1 in
    *.lua) "$lua" "${lua_flags[@]+"${lua_flags[@]}"}" "$1" ;;
    *.sh)
      if [[ -n "$coverage" ]]; then
        # kcov runs the test with /bin/bash, and traces every bash script
        # that the test starts. bash 3.2 gives a command that spans lines
        # the number of its last line, so kcov never sees a hit on the
        # first line of the fzf call in picker.sh. That line is not counted.
        # kcov prints the trace lines that it can't read to stderr, so drop
        # them. The test results go to stdout.
        kcov --include-path="$PWD/bin" --exclude-line='selection=$(printf' kcov "$1" 2>/dev/null
      else
        /bin/bash "$1"
      fi ;;
  esac
}

# make_reports: write the reports that the coverage summary reads, and the
# HTML reports.
make_reports() {
  luacov || return
  cover -silent cover_db -report json >/dev/null || return
  # luacov-html has the same module name as the HTML reporter that comes
  # with luacov, so luarocks installed it under a renamed path. Put that
  # path first. LUA_CPATH finds LuaFileSystem, which luacov-html needs.
  local html_path
  html_path=$(echo "$PWD"/lua_modules/share/lua/5.1/luacov_html_*-luacov)
  LUA_PATH="${html_path%luacov}?.lua;$LUA_PATH" LUA_CPATH="$PWD/lua_modules/lib/lua/5.1/?.so;;" \
    "$lua" -e 'require("luacov.runner").run_report(".luacov-html")' || return
  cover -silent cover_db >/dev/null
}

printf '%sTests%s\n' "$bold" "$reset"
failed=0
for t in test/*.test.lua test/*.test.sh; do
  spin "${t#test/}" run_test "$t"
  # The last line of the output holds the counts. The lines before it tell
  # about the checks that failed.
  counts=${out##*$'\n'}
  details=
  [[ "$out" == *$'\n'* ]] && details=${out%$'\n'*}
  if [[ ! "$counts" =~ ^[0-9]+\ passed,\ [0-9]+\ failed$ ]]; then
    counts="did not finish"
    details=$out
  fi
  if [[ $status -eq 0 ]]; then
    printf '  %s✓%s %-24s %4s passed\n' "$green" "$reset" "${t#test/}" "${counts%% *}"
  else
    failed=1
    printf '  %s✗ %-24s %s%s\n' "$red" "${t#test/}" "$counts" "$reset"
    [[ -n "$details" ]] && printf '%s\n' "$details" | sed 's/^/      /'
  fi
done

if [[ -n "$coverage" ]]; then
  unset PERL5OPT
  echo
  spin "Making the coverage reports" make_reports
  if [[ $status -ne 0 ]]; then
    printf '%srun.sh: the coverage reports failed%s\n%s\n' "$red" "$reset" "$out" >&2
    exit 1
  fi
  perl test/coverage-summary.pl
  echo
  # test/coverage.html has a link to each report, so only one page opens.
  # Print it as a file:// URL, so that the terminal can open it on a click
  # and rex-fzf-url can find it. Encode the spaces, or the URL ends at the
  # first one.
  url="file://${PWD// /%20}/test/coverage.html"
  printf '%sHTML reports: %s%s\n' "$dim" "$url" "$reset"
  if [[ -n "$open" ]]; then
    opener=$(command -v open || command -v xdg-open)
    [[ -n "$opener" ]] && "$opener" "$url"
  else
    printf '%sTo open them in the browser, run: test/run.sh --open%s\n' "$dim" "$reset"
  fi
fi

exit $failed
