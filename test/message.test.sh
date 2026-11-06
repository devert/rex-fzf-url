#!/usr/bin/env bash
# Tests for message.sh. Must run under macOS /bin/bash 3.2.
#
# A fake rex program logs the focus call. An open FIFO with no data stands
# in for a pane where nobody presses a key.
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/test/harness.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAKE=$TMP/bin
mkdir -p "$FAKE"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"$LOG"\nexit "${FAKE_REX_EXIT:-0}"\n' >"$FAKE/rex"
chmod +x "$FAKE/rex"

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

# run [VAR=value ...] -- [ARG ...]: run message.sh with input from $input,
# a fresh log, and a fake rex. Sets $out, $status, and $secs, the time it
# took. An alarm stops message.sh after 5 seconds, so that a script that
# never times out fails the checks instead of hanging the test.
run() {
  local vars=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do vars+=("$1"); shift; done
  shift
  LOG=$TMP/log.$RANDOM
  local start
  start=$(now)
  out=$(env -i PATH=/bin:/usr/bin LOG="$LOG" REX_BIN_DIR="$FAKE" ${vars[@]+"${vars[@]}"} \
    perl -e 'alarm 5; exec @ARGV' /bin/bash "$DIR/bin/message.sh" "$@" <"$input")
  status=$?
  secs=$(perl -e "printf '%.2f', $(now) - $start")
}

# between <low> <high>: print yes when $secs is in [low, high), else $secs.
between() { perl -e "print $secs >= $1 && $secs < $2 ? 'yes' : '$secs'"; }

log() { [[ -f "$LOG" ]] && cat "$LOG"; }

hide=$'\033[?25l'

# A key press ends the message at once.
input=$TMP/key
printf 'x' >"$input"

run -- "No URLs found." block:9
check_eq "shows the message after hiding the cursor" "$hide No URLs found." "$out"
check_eq "exits 0" "0" "$status"
check_eq "a key ends it at once" "yes" "$(between 0 0.5)"
check_eq "focus goes back to the pane" "focus block:9" "$(log)"

run --
check_eq "no message shows only the space" "$hide " "$out"
check_eq "no pane, no focus call" "" "$(log)"
check_eq "no pane, exits 0" "0" "$status"

run FAKE_REX_EXIT=1 -- "No URLs found." block:9
check_eq "exits 0 when focus fails" "0" "$status"

# With no key, the message stays for one second. Keep the FIFO open for
# writing on fd 3, so that read waits instead of seeing the end of input.
input=$TMP/fifo
mkfifo "$input"
exec 3<>"$input"
run -- "No URLs found." block:9
exec 3>&-
check_eq "with no key, it waits one second" "yes" "$(between 0.9 1.6)"
check_eq "with no key, focus goes back after the wait" "focus block:9" "$(log)"

finish
