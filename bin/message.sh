#!/usr/bin/env bash
# message.sh: runs inside the small floating pane that shows a message, such
# as "No URLs found." The pane closes after one second, or when you press a
# key. Then the script gives focus back to the pane in $2, because Rex
# doesn't do that when a floating pane closes.
# Must stay compatible with macOS /bin/bash 3.2.
set -u

# Print after the app resizes the pane, so that the message is on the one
# row that the pane keeps, and the one second starts then.
. "${0%/*}/wait-resize.sh"
wait_resize

printf '\033[?25l %s' "${1:-}"
read -rsn1 -t 1
[[ -n "${2:-}" ]] && "${REX_BIN_DIR:+$REX_BIN_DIR/}rex" focus "$2" >/dev/null 2>&1
exit 0
