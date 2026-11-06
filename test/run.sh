#!/usr/bin/env bash
# run.sh: run every test file, and exit 1 when one fails.
# Must stay compatible with macOS /bin/bash 3.2.
#
#   test/run.sh             run the tests
#   test/run.sh --coverage  also write coverage reports, with luacov for the
#                           Lua code, Devel::Cover for bin/extract-urls, and
#                           kcov for the bash scripts
#   test/run.sh --open      the same as --coverage, then also write the HTML
#                           reports and open them in the browser
#
# Coverage needs luacov and luacov-html in lua_modules/, Devel::Cover in
# local/, and kcov. To install them, run test/install-coverage-tools.sh.
set -u

cd "$(dirname "$0")/.." || exit 1

coverage=
html=
for a in "$@"; do
  case $a in
    --coverage) coverage=1 ;;
    --open) coverage=1 html=1 ;;
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

failed=0
for t in test/*.test.lua test/*.test.sh; do
  printf '%s: ' "$t"
  case $t in
    *.lua) "$lua" "${lua_flags[@]+"${lua_flags[@]}"}" "$t" ;;
    *.sh)
      if [[ -n "$coverage" ]]; then
        # kcov runs the test with /bin/bash, and traces every bash script
        # that the test starts. bash 3.2 gives a command that spans lines
        # the number of its last line, so kcov never sees a hit on the
        # first line of the fzf call in picker.sh. That line is not counted.
        # kcov prints the trace lines that it can't read to stderr, so drop
        # them. The test results go to stdout.
        kcov --include-path="$PWD/bin" --exclude-line='selection=$(printf' kcov "$t" 2>/dev/null
      else
        /bin/bash "$t"
      fi ;;
  esac || failed=1
done

if [[ -n "$coverage" ]]; then
  unset PERL5OPT
  echo
  luacov && sed -n '/^Summary/,$p' luacov.report.out
  echo
  cover -silent cover_db -report text 2>/dev/null | sed -n '/^File/,/^Total/p'
  echo
  perl -MJSON::PP -0777 -ne '
    my $d = decode_json($_);
    printf "%-20s %5s %7s %8s\n", "File", "Hits", "Lines", "Coverage";
    for my $f (sort { $a->{file} cmp $b->{file} } @{ $d->{files} }) {
      (my $name = $f->{file}) =~ s{.*/(bin/)}{$1};
      printf "%-20s %5d %7d %7s%%\n", $name, $f->{covered_lines}, $f->{total_lines}, $f->{percent_covered};
    }
    printf "%-20s %5d %7d %7s%%\n", "Total", $d->{covered_lines}, $d->{total_lines}, $d->{percent_covered};
  ' kcov/kcov-merged/coverage.json
  echo
  if [[ -n "$html" ]]; then
    # luacov-html has the same module name as the HTML reporter that comes
    # with luacov, so luarocks installed it under a renamed path. Put that
    # path first. LUA_CPATH finds LuaFileSystem, which luacov-html needs.
    html_path=$(echo "$PWD"/lua_modules/share/lua/5.1/luacov_html_*-luacov)
    LUA_PATH="${html_path%luacov}?.lua;$LUA_PATH" LUA_CPATH="$PWD/lua_modules/lib/lua/5.1/?.so;;" \
      "$lua" -e 'require("luacov.runner").run_report(".luacov-html")'
    cover -silent cover_db >/dev/null 2>&1
    # test/coverage.html has a link to each report, so only one page opens.
    echo "HTML reports: test/coverage.html"
    opener=$(command -v open || command -v xdg-open)
    [[ -n "$opener" ]] && "$opener" test/coverage.html
  else
    echo "For HTML reports, run: test/run.sh --open"
  fi
fi

exit $failed
