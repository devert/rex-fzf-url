#!/usr/bin/env bash
# run.sh: run every test file, and exit 1 when one fails.
# Must stay compatible with macOS /bin/bash 3.2.
set -u

cd "$(dirname "$0")/.." || exit 1

lua=$(command -v luajit || command -v lua) || { echo "run.sh: luajit or lua not found" >&2; exit 1; }

failed=0
for t in test/*.test.lua test/*.test.sh; do
  printf '%s: ' "$t"
  case $t in
    *.lua) "$lua" "$t" ;;
    *.sh) /bin/bash "$t" ;;
  esac || failed=1
done

exit $failed
