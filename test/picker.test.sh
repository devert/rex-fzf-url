#!/usr/bin/env bash
# Tests for picker.sh. Must run under macOS /bin/bash 3.2.
#
# Fake fzf, open, pbcopy, xclip, sleep, stty, and rex programs go first in PATH.
# The rest of PATH is /bin only, so the real open and pbcopy in /usr/bin are
# not found. Each fake writes what it got to a log in $LOG.
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/test/harness.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAKE=$TMP/bin
NOFZF=$TMP/nofzf
mkdir -p "$FAKE" "$NOFZF"

# fake <name> <body>: write a fake program into $FAKE.
fake() {
  printf '#!/bin/bash\n%s\n' "$2" >"$FAKE/$1"
  chmod +x "$FAKE/$1"
}

# fzf logs its arguments and input, then prints $FAKE_FZF_OUTPUT (with
# backslash escapes) and exits with $FAKE_FZF_EXIT.
fake fzf 'printf "%s\n" "$@" >"$LOG/fzf.args"; cat >"$LOG/fzf.in"; printf "%b" "${FAKE_FZF_OUTPUT:-}"; exit "${FAKE_FZF_EXIT:-0}"'
fake open 'printf "%s\n" "$*" >>"$LOG/open"'
fake myopen 'printf "%s\n" "$*" >>"$LOG/myopen"'
# envopen logs the URL, HOME, and PATH that it gets.
fake envopen 'printf "%s\n" "$*" "$HOME" "$PATH" >>"$LOG/envopen"'
fake pbcopy 'printf "[%s]" "$*" >>"$LOG/pbcopy"; cat >>"$LOG/pbcopy"'
fake xclip 'printf "[%s]" "$*" >>"$LOG/xclip"; cat >>"$LOG/xclip"'
fake xdg-open 'printf "%s\n" "$*" >>"$LOG/xdg-open"'
fake browser 'printf "%s\n" "$*" >>"$LOG/browser"'
fake sleep 'printf "%s\n" "$*" >>"$LOG/sleep"'
# stty prints the pane size in $FAKE_STTY.
fake stty 'printf "%s\n" "${FAKE_STTY:-}"'
fake rex 'printf "%s\n" "$*" >>"$LOG/rex"'
ln -s /usr/bin/nohup "$FAKE/nohup"
for p in sleep rex; do ln -s "$FAKE/$p" "$NOFZF/$p"; done

# picker <file> [VAR=value ...]: run picker.sh on file, with a fresh log.
# Sets $status to its exit status, and $err to the lines of its stderr that
# start with "fzf-url:".
# Under kcov (test/run.sh --coverage), BASH_ENV turns on tracing in each
# bash, and bash 3.2 writes the trace to stderr. So keep BASH_ENV, and pass
# stderr on to kcov after the run.
picker() {
  local file=$1
  shift
  LOG=$(mktemp -d "$TMP/log.XXXX")
  env -i ${BASH_ENV:+BASH_ENV="$BASH_ENV"} HOME="$HOME" PATH="$FAKE:/bin" LOG="$LOG" \
    REX_BIN_DIR="$FAKE" FZF_URL_SOURCE_BLOCK=block:9 FZF_URL_EXTRA_PATH= "$@" \
    /bin/bash "$DIR/bin/picker.sh" "$file" >/dev/null 2>"$TMP/stderr"
  status=$?
  err=$(grep '^fzf-url:' "$TMP/stderr")
  if [[ -n "${BASH_ENV:-}" ]]; then grep -v '^fzf-url:' "$TMP/stderr" >&2; fi
}

# run <urls> [VAR=value ...]: run picker.sh on a URL file that holds urls.
# Also sets $url_file to the URL file.
run() {
  local urls=$1
  shift
  url_file=$TMP/urls
  printf '%s\n' "$urls" >"$url_file"
  picker "$url_file" "$@"
}

# log <name>: print a log file, or nothing when it doesn't exist.
log() { [[ -f "$LOG/$1" ]] && cat "$LOG/$1"; }

two=$'https://a.example.com\nhttps://b.example.com'
three=$'https://a.example.com\nhttps://b.example.com\nhttps://c.example.com'

run "$two" FAKE_FZF_OUTPUT='\nhttps://b.example.com\n'
check_eq "enter opens the URL" "https://b.example.com" "$(log open)"
check_eq "enter exits 0" "0" "$status"
check_eq "fzf gets the URLs" "$two" "$(log fzf.in)"
check_eq "the URL file is removed" "no" "$([[ -e "$url_file" ]] && echo yes || echo no)"
check_eq "focus goes back to the source pane" "focus block:9" "$(log rex)"

run "$two" FAKE_FZF_OUTPUT='\nhttps://a.example.com\nhttps://b.example.com\n'
check_eq "enter opens each selected URL" "$two" "$(log open)"

run "$two" FAKE_FZF_OUTPUT='\nhttps://a.example.com\n' FZF_URL_OPEN_CMD='myopen --new'
check_eq "open_cmd is used, with its arguments" "--new https://a.example.com" "$(log myopen)"
check_eq "open_cmd replaces open" "" "$(log open)"

run "$two" FAKE_FZF_OUTPUT='ctrl-y\nhttps://a.example.com\nhttps://b.example.com\n'
check_eq "ctrl-y copies the selection" "[]$two" "$(log pbcopy)"
check_eq "ctrl-y opens nothing" "" "$(log open)"

run "$two" FAKE_FZF_OUTPUT='ctrl-y\nhttps://a.example.com\n' FZF_URL_COPY_CMD='xclip -in'
check_eq "copy_cmd is used, with its arguments" "[-in]https://a.example.com" "$(log xclip)"
check_eq "copy_cmd replaces pbcopy" "" "$(log pbcopy)"

# Without pbcopy, use xclip when DISPLAY is set.
mv "$FAKE/pbcopy" "$TMP/pbcopy"
run "$two" FAKE_FZF_OUTPUT='ctrl-y\nhttps://a.example.com\n' DISPLAY=:0
check_eq "xclip is the fallback with DISPLAY" "[-selection clipboard]https://a.example.com" "$(log xclip)"

run "$two" FAKE_FZF_OUTPUT='ctrl-y\nhttps://a.example.com\n'
check_eq "no clipboard tool fails" "1" "$status"
check_eq "no clipboard tool message" "fzf-url: no clipboard tool found (pbcopy/wl-copy/xclip/xsel)" "$err"
check_eq "focus goes back after a failure" "focus block:9" "$(log rex)"
mv "$TMP/pbcopy" "$FAKE/pbcopy"

run "$two" FAKE_FZF_EXIT=130
check_eq "escape exits 0" "0" "$status"
check_eq "escape opens nothing" "" "$(log open)"

run "$two" FAKE_FZF_OUTPUT='\n' FAKE_FZF_EXIT=1
check_eq "enter with no match exits 0" "0" "$status"
check_eq "enter with no match opens nothing" "" "$(log open)"

run "$two" FAKE_FZF_EXIT=2
check_eq "fzf error fails" "1" "$status"
check_eq "fzf error message" "fzf-url: fzf failed with exit status 2" "$err"

# Without HOME, the picker gets HOME from the user database and exports it.
# No PATH: bash sets a default PATH that ends in `.`. The picker drops the
# `.` and exports the rest, so nohup finds the opener.
LOG=$(mktemp -d "$TMP/log.XXXX")
printf '%s\n' "$two" >"$TMP/urls"
env -i ${BASH_ENV:+BASH_ENV="$BASH_ENV"} LOG="$LOG" FZF_URL_EXTRA_PATH="$FAKE" \
  FZF_URL_OPEN_CMD=envopen FAKE_FZF_OUTPUT='\nhttps://a.example.com\n' \
  /bin/bash "$DIR/bin/picker.sh" "$TMP/urls" >/dev/null 2>"$TMP/stderr"
check_eq "no HOME or PATH exits 0" "0" "$?"
check_eq "no PATH: open_cmd found in an install folder" "https://a.example.com" "$(log envopen | sed -n 1p)"
check_eq "no HOME: the opener gets HOME" "$(cd ~ && pwd)" "$(log envopen | sed -n 2p)"
check_eq "no PATH: the opener gets no . in PATH" "/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:$FAKE" "$(log envopen | sed -n 3p)"

# The fzf height comes from init.lua. fzf itself limits it to the pane
# height. Without one, or when the pane never got its size, fzf uses the
# whole screen.
height() { log fzf.args | grep -A1 -x -- --height | tail -1; }
run "$three" FZF_URL_HEIGHT=7
check_eq "height comes from FZF_URL_HEIGHT" "7" "$(height)"
run "$three"
check_eq "no height: no --height" "" "$(height)"
run "$three" FZF_URL_HEIGHT=7 FAKE_STTY="24 80"
check_eq "no resize: no --height" "" "$(height)"

# URLs that can wrap get their extra rows at the columns of the pane. At 30
# columns, a row holds 26 characters, and each next row 24.
run "$three" FZF_URL_HEIGHT=7 FZF_URL_WRAP="4 2 26 27 50 51" FAKE_STTY="20 30"
check_eq "wrapped URLs add their extra rows" "11" "$(height)"
run "$three" FZF_URL_HEIGHT=7 FZF_URL_WRAP="4 2 26 27 50 51" FAKE_STTY="20 60"
check_eq "a wider pane wraps fewer rows" "7" "$(height)"
run "$three" FZF_URL_HEIGHT=7 FZF_URL_WRAP="4 2 50" FAKE_STTY="20 5"
check_eq "a pane narrower than the layout keeps 3 text columns" "54" "$(height)"
# A "w" marks a URL with a wide character, which can lose one column on
# each row. At 40 columns, a 70-column URL then takes 2 extra rows, not 1.
run "$three" FZF_URL_HEIGHT=5 FZF_URL_WRAP="4 2 70" FAKE_STTY="20 40"
check_eq "a URL without wide characters" "6" "$(height)"
run "$three" FZF_URL_HEIGHT=5 FZF_URL_WRAP="4 2 70w" FAKE_STTY="20 40"
check_eq "a URL with a wide character loses a column on each row" "7" "$(height)"
run "$three" FZF_URL_HEIGHT=5 FZF_URL_WRAP="4 2 36w" FAKE_STTY="20 40"
check_eq "a URL with a wide character that fits takes one row" "5" "$(height)"
run "$three" FZF_URL_HEIGHT=7 FZF_URL_WRAP="4 2 3w" FAKE_STTY="20 5"
check_eq "a narrow pane keeps one column for each next row" "7" "$(height)"
run "$three" FZF_URL_HEIGHT=7 FZF_URL_WRAP="4 2 50w" FAKE_STTY="20 5"
check_eq "a narrow pane with a wide character loses a column on its first row" "55" "$(height)"
run "$three" FZF_URL_HEIGHT=7 FZF_URL_WRAP="4 2 50x" FAKE_STTY="20 30"
check_eq "a bad wrap mark: no --height" "" "$(height)"
run "$three" FZF_URL_HEIGHT=7 FZF_URL_WRAP="x 2 50" FAKE_STTY="20 30"
check_eq "a bad layout value: no --height" "" "$(height)"
run "$three" FZF_URL_HEIGHT=7 FZF_URL_WRAP="4 2 x" FAKE_STTY="20 30"
check_eq "a bad wrap width: no --height" "" "$(height)"
run "$three" FZF_URL_HEIGHT=7 FZF_URL_WRAP="4 2" FAKE_STTY="20 30"
check_eq "no wrap widths: no --height" "" "$(height)"
run "$three" FZF_URL_HEIGHT=x
check_eq "a bad height: no --height" "" "$(height)"

# The help text comes from init.lua.
header() { log fzf.args | grep -A1 -x -- --header | tail -1; }
run "$three" FZF_URL_HEADER='Enter: Open'
check_eq "header comes from FZF_URL_HEADER" "Enter: Open" "$(header)"

run "$two" FZF_URL_FZF_OPTIONS='--exact --reverse'
check_eq "fzf_options are split into words" $'--exact\n--reverse' "$(log fzf.args | tail -2)"

run "$two" FZF_DEFAULT_OPTS='--border --margin=2 --padding=2'
check_eq "no border when FZF_DEFAULT_OPTS sets one" "--no-border" "$(log fzf.args | grep -x -- --no-border)"
check_eq "no margin when FZF_DEFAULT_OPTS sets one" "--no-margin" "$(log fzf.args | grep -x -- --no-margin)"
check_eq "no padding when FZF_DEFAULT_OPTS sets one" "--no-padding" "$(log fzf.args | grep -x -- --no-padding)"

# Without open, use xdg-open, then $BROWSER.
mv "$FAKE/open" "$TMP/open"
run "$two" FAKE_FZF_OUTPUT='\nhttps://a.example.com\n'
check_eq "xdg-open is the fallback" "https://a.example.com" "$(log xdg-open)"
mv "$FAKE/xdg-open" "$TMP/xdg-open"
run "$two" FAKE_FZF_OUTPUT='\nhttps://a.example.com\n' BROWSER=browser
check_eq "\$BROWSER is the last fallback" "https://a.example.com" "$(log browser)"
run "$two" FAKE_FZF_OUTPUT='\nhttps://a.example.com\n'
check_eq "no opener fails" "1" "$status"
check_eq "no opener message" 'fzf-url: no opener found (open/xdg-open/$BROWSER)' "$err"
mv "$TMP/open" "$TMP/xdg-open" "$FAKE/"

# The picker waits for the resize with bin/wait-resize.sh (see
# wait-resize.test.sh). It passes the cache and the measure spec on.
run "$two" REX_BLOCK=block:7 FZF_URL_CACHE=/tmp/cache FZF_URL_MEASURE="window:1 k 0.5 0.4"
check_eq "measure.lua gets the cache and the spec" \
  "do $DIR/bin/measure.lua block=block:7 cache=/tmp/cache spec=window:1 k 0.5 0.4" "$(grep '^do ' "$LOG/rex")"
run "$two" REX_BLOCK=block:7
check_eq "no measure spec, measure.lua gets only the block" \
  "do $DIR/bin/measure.lua block=block:7" "$(grep '^do ' "$LOG/rex")"

# The help text has a default, for an init.lua that does not set it yet.
run "$three"
check_eq "header has a default" "Enter: Open URL / CTRL-Y: Copy to clipboard" "$(header)"

run "$two" PATH="$NOFZF:/bin"
check_eq "no fzf fails" "1" "$status"
check_eq "no fzf message" "fzf-url: fzf not found. Set fzf_path in setup() to the full path of fzf." "$err"
check_eq "no fzf removes the URL file" "no" "$([[ -e "$url_file" ]] && echo yes || echo no)"

# An empty FZF_URL_EXTRA_PATH or PATH must not add the current folder to PATH.
mkdir -p "$TMP/cwd"
cp "$FAKE/fzf" "$TMP/cwd/fzf"
cd "$TMP/cwd" || exit 1
run "$two" PATH="$NOFZF:/bin"
check_eq "empty extra path does not search the current folder" "1" "$status"
run "$two" PATH= FZF_URL_EXTRA_PATH="$NOFZF:/bin"
check_eq "empty PATH does not search the current folder" "1" "$status"
run "$two" PATH=".:$NOFZF:/bin"
check_eq "a . in PATH does not search the current folder" "1" "$status"
mkdir -p "$TMP/cwd/sub"
cp "$FAKE/fzf" "$TMP/cwd/sub/fzf"
run "$two" PATH="sub:$NOFZF:/bin"
check_eq "a relative part in PATH is not searched" "1" "$status"
cd "$DIR" || exit 1

# Without fzf in PATH, find it in the usual install folders, after PATH.
run "$two" PATH="$NOFZF:/bin" FZF_URL_EXTRA_PATH="$TMP/missing:$FAKE"
check_eq "fzf in an install folder is used" "0" "$status"
check_eq "fzf in an install folder gets the URLs" "$two" "$(log fzf.in)"

# fzf_path replaces fzf in PATH. A leading ~ is the home folder.
mkdir -p "$TMP/home/apps"
cp "$FAKE/fzf" "$TMP/home/apps/myfzf"
run "$two" PATH="$NOFZF:/bin" FZF_URL_FZF_PATH="$TMP/home/apps/myfzf"
check_eq "fzf_path is used" "$two" "$(log fzf.in)"
run "$two" PATH="$NOFZF:/bin" HOME="$TMP/home" FZF_URL_FZF_PATH="~/apps/myfzf"
check_eq "fzf_path expands ~" "$two" "$(log fzf.in)"
run "$two" FZF_URL_FZF_PATH="$TMP/home/apps"
check_eq "fzf_path that is a folder fails" "1" "$status"
check_eq "fzf_path that is a folder message" \
  "fzf-url: fzf_path is not an executable file: $TMP/home/apps" "$err"
run "$two" FZF_URL_FZF_PATH="apps/myfzf"
check_eq "relative fzf_path fails" "1" "$status"
check_eq "relative fzf_path message" "fzf-url: fzf_path must start with / or ~/: apps/myfzf" "$err"
run "$two" FZF_URL_FZF_PATH="$TMP/nothing"
check_eq "fzf_path that is missing fails" "1" "$status"
check_eq "fzf_path that is missing does not run fzf" "" "$(log fzf.in)"
check_eq "fzf_path that is missing removes the URL file" "no" "$([[ -e "$url_file" ]] && echo yes || echo no)"

# Only `~` and `~/` are the home folder. `~name` is left as it is.
mkdir -p "$TMP/home/foo"
cp "$FAKE/fzf" "$TMP/home/foo/fzf"
run "$two" PATH="$NOFZF:/bin" HOME="$TMP/home/" FZF_URL_FZF_PATH="~foo/fzf"
check_eq "fzf_path with ~name is not expanded" "1" "$status"
check_eq "fzf_path with ~name message" "fzf-url: fzf_path must start with / or ~/: ~foo/fzf" "$err"

# A name without a slash is found in PATH.
run "$two" PATH="$NOFZF:/bin" FZF_URL_EXTRA_PATH="$TMP/home/apps" FZF_URL_FZF_PATH="myfzf"
check_eq "fzf_path name in PATH is used" "$two" "$(log fzf.in)"
run "$two" PATH="$NOFZF:/bin" FZF_URL_FZF_PATH="nofzf"
check_eq "fzf_path name not in PATH fails" "1" "$status"
check_eq "fzf_path name not in PATH message" "fzf-url: fzf_path not found in PATH: nofzf" "$err"

picker "$TMP/none"
check_eq "a missing URL file fails" "1" "$status"
check_eq "a missing URL file message" "fzf-url: no URL list file" "$err"

# A failure before fzf starts waits for the pane size first, so that the
# message is not broken by the resize. It does not wait again on exit.
run "$two" PATH="$NOFZF:/bin" REX_BLOCK=block:7
check_eq "an early failure waits for the pane size, then focuses" \
  "do $DIR/bin/measure.lua block=block:7
focus block:9" "$(log rex)"
run "$two" FAKE_FZF_EXIT=2 REX_BLOCK=block:7
check_eq "a late failure does not wait for the size again" "1" "$(grep -c '^do ' "$LOG/rex")"

finish
