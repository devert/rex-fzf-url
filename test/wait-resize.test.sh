#!/usr/bin/env bash
# Tests for wait-resize.sh. Must run under macOS /bin/bash 3.2.
#
# Fake rex, stty, and sleep programs go first in PATH. rex prints the size
# in $FAKE_WANT for `rex do`. stty prints the sizes in the file $STTY, one
# for each call, and then repeats the last one. Each fake logs its calls.
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/test/harness.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAKE=$TMP/bin
mkdir -p "$FAKE"
fake() {
  printf '#!/bin/bash\n%s\n' "$2" >"$FAKE/$1"
  chmod +x "$FAKE/$1"
}
fake rex 'printf "%s\n" "$*" >>"$LOG/rex"; [[ -n "${FAKE_HANG:-}" ]] && exec /bin/sleep 5; printf "%s" "${FAKE_WANT:-}"'
fake sleep 'printf "%s\n" "$*" >>"$LOG/sleep"'
fake stty 'n=$(cat "$LOG/n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n >"$LOG/n"
line=$(sed -n "${n}p" "$STTY"); [[ -n "$line" ]] || line=$(tail -1 "$STTY"); printf "%s\n" "$line"'

# run <sizes> [VAR=value ...] -- [ARG ...]: source wait-resize.sh in a bash
# with fakes, and call wait_resize with the ARGs. sizes is what stty prints
# on each call, separated by commas. Sets $sleeps, the number of sleeps.
run() {
  local sizes=$1
  shift
  local vars=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do vars+=("$1"); shift; done
  shift
  LOG=$(mktemp -d "$TMP/log.XXXX")
  STTY=$LOG/sizes
  printf '%s\n' "$sizes" | tr , '\n' >"$STTY"
  env -i ${BASH_ENV:+BASH_ENV="$BASH_ENV"} PATH="$FAKE:/bin:/usr/bin" LOG="$LOG" STTY="$STTY" \
    REX_BIN_DIR="$FAKE" ${vars[@]+"${vars[@]}"} \
    /bin/bash -c '. "$1/bin/wait-resize.sh"; shift; wait_resize "$@"' _ "$DIR" "$@"
  status=$?
  sleeps=$(cat "$LOG/sleep" 2>/dev/null | wc -l | tr -d ' ')
}

log() { [[ -f "$LOG/$1" ]] && cat "$LOG/$1"; }

# No REX_BLOCK: no measure.lua. Wait for a size other than 80x24 that
# stays the same for 10 checks.
run "24 80,24 80,30 100" --
check_eq "no block: no rex call" "" "$(log rex)"
check_eq "no block: waits until a new size stays the same" "11" "$sleeps"
check_eq "exits 0" "0" "$status"
run "24 80" --
check_eq "no block: gives up after 25 tries" "25" "$sleeps"
check_eq "a timeout exits 1" "1" "$status"
run "30 100" --
check_eq "no block: a size that stays the same from the start" "9" "$sleeps"
# A size in the middle of a resize does not end the wait.
run "24 80,30 100,30 100,40 120" --
check_eq "no block: a size that changes starts the count again" "12" "$sleeps"
check_eq "no block: ends on the last size" "0" "$status"
# No terminal: nothing to wait for.
run "" --
check_eq "no terminal: no wait" "0" "$sleeps"
check_eq "no terminal: exits 0" "0" "$status"

# With REX_BLOCK, wait for the size that measure.lua prints.
run "24 80,30 100" REX_BLOCK=block:7 FAKE_WANT="30 100" --
check_eq "runs measure.lua with the block" "do $DIR/bin/measure.lua block=block:7" "$(log rex)"
check_eq "waits for the wanted size" "1" "$sleeps"
run "24 80" REX_BLOCK=block:7 FAKE_WANT="24 80" --
check_eq "a wanted size of 80x24 needs no wait" "0" "$sleeps"
run "24 80" REX_BLOCK=block:7 FAKE_WANT="30 101" --
check_eq "gives up on the wanted size after 25 tries" "25" "$sleeps"
check_eq "a timeout on the wanted size exits 1" "1" "$status"
# The terminal can settle on another size, as when the window changes size.
run "24 80,30 100" REX_BLOCK=block:7 FAKE_WANT="30 101" --
check_eq "another size that stays the same ends the wait" "10" "$sleeps"
check_eq "another size that stays the same exits 0" "0" "$status"
run "24 80,30 100,24 80,30 100,30 99" REX_BLOCK=block:7 FAKE_WANT="30 101" --
check_eq "a size that changes starts the count again" "13" "$sleeps"
# A resize during the last sleep is still found.
run "$(printf '24 80,%.0s' $(seq 25))30 100" REX_BLOCK=block:7 FAKE_WANT="30 100" --
check_eq "checks once more after the last sleep" "0" "$status"
check_eq "the last check needs no more sleep" "25" "$sleeps"

# measure.lua prints no size, or something else: wait as with no block.
run "24 80,30 100" REX_BLOCK=block:7 FAKE_WANT="" --
check_eq "no size printed: waits for a size that stays the same" "10" "$sleeps"
run "24 80,30 100" REX_BLOCK=block:7 FAKE_WANT="error" --
check_eq "not a size: waits for a size that stays the same" "10" "$sleeps"

# A `rex do` that hangs is stopped after one second, and the wait goes on
# as when measure.lua prints no size.
start=$SECONDS
run "24 80,30 100" REX_BLOCK=block:7 FAKE_WANT="30 101" FAKE_HANG=1 --
check_eq "a hung rex do is stopped" "yes" "$([[ $((SECONDS - start)) -lt 4 ]] && echo yes || echo no)"
check_eq "a hung rex do: waits for a size that stays the same" "10" "$sleeps"
check_eq "a hung rex do: exits 0" "0" "$status"

# The cache and the spec go on to measure.lua only when both are set.
run "30 100" REX_BLOCK=block:7 FAKE_WANT="30 100" -- /tmp/cache "window:1 k 0.5 0.4"
check_eq "passes the cache and the spec" \
  "do $DIR/bin/measure.lua block=block:7 cache=/tmp/cache spec=window:1 k 0.5 0.4" "$(log rex)"
run "30 100" REX_BLOCK=block:7 FAKE_WANT="30 100" -- /tmp/cache ""
check_eq "no spec: passes only the block" "do $DIR/bin/measure.lua block=block:7" "$(log rex)"

finish
