#!/usr/bin/env bash
# picker.sh: runs inside the floating Rex pane that the fzf_url action opens.
# The action already read the scrollback, extracted the URLs, and wrote them
# to the file in $1. Enter opens the selection, ctrl-y copies it, and tab
# selects more than one. The pane closes when this script exits.
# Must stay compatible with macOS /bin/bash 3.2.
#
# Environment, set by init.lua from the setup() options:
#   FZF_URL_OPENER       command that opens a URL (default: open or xdg-open)
#   FZF_URL_COPY_CMD     command that copies stdin to the clipboard
#   FZF_URL_FZF_OPTIONS  extra fzf options
#   FZF_URL_SOURCE_BLOCK the pane that ran the action
set -u

# Rex doesn't give focus back to the pane that ran the action when a floating
# pane closes, so do it on every exit. Rex sets REX_BIN_DIR in its panes.
refocus() {
    [[ -n "${FZF_URL_SOURCE_BLOCK:-}" ]] &&
        "${REX_BIN_DIR:+$REX_BIN_DIR/}rex" focus "$FZF_URL_SOURCE_BLOCK" >/dev/null 2>&1
}
trap refocus EXIT

# No `set -e`: a pane that closes without a message is hard to debug.
# Failures print a message and pause so the user can read it.
fail() {
    printf 'fzf-url: %s\n' "$1" >&2
    sleep 2
    exit 1
}

command -v fzf >/dev/null 2>&1 || fail "fzf not found in PATH"

url_file="${1:-}"
[[ -n "$url_file" && -f "$url_file" ]] || fail "no URL list file"
urls=$(cat "$url_file")
rm -f "$url_file"
[[ -z "$urls" ]] && exit 0

# Draw fzf from the top of the pane, as tall as its content: one row per URL
# plus 5 rows for the prompt, the help text, two border lines, and the bottom
# padding. The pane can be a row taller than that, and the extra row is then
# at the bottom, below the padding.
# The app sets the size of a new pane shortly after it opens. Until then the
# terminal has the default size of 80x24. fzf draws in place with --height,
# so lines that it draws before the resize stay on the screen. So wait for
# the resize, for at most half a second.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
    [[ "$(stty size 2>/dev/null)" != "24 80" ]] && break
    sleep 0.02
done

count=$(printf '%s\n' "$urls" | wc -l | tr -d ' ')
height=$((count + 5))
lines=$(tput lines 2>/dev/null || echo "$height")
[[ "$height" -gt "$lines" ]] && height=$lines

# fzf options ported from junegunn/tmux-fzf-url's fzf-url.rb. --expect
# reports the pressed key (ctrl-y, or empty for Enter) on the first output
# line. The selections follow.
# $FZF_URL_FZF_OPTIONS is intentionally unquoted: word-splitting is the point.
# shellcheck disable=SC2086
selection=$(printf '%s\n' "$urls" | fzf \
    --multi --no-margin --no-padding --wrap \
    --expect ctrl-y --style default \
    --header 'Enter: Open URL / CTRL-Y: Copy to clipboard' \
    --header-border top --header-first \
    --highlight-line --info inline-right \
    --padding 0,1,1,1 \
    --height "$height" \
    ${FZF_URL_FZF_OPTIONS:-}) || exit 0

key=$(printf '%s\n' "$selection" | head -n 1)
chosen=$(printf '%s\n' "$selection" | tail -n +2)
[[ -z "$chosen" ]] && exit 0

get_copy_cmd() {
    if [[ -n "${FZF_URL_COPY_CMD:-}" ]]; then echo "$FZF_URL_COPY_CMD"
    elif command -v pbcopy >/dev/null 2>&1; then echo "pbcopy"
    elif [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null 2>&1; then echo "wl-copy"
    elif [[ -n "${DISPLAY:-}" ]] && command -v xclip >/dev/null 2>&1; then echo "xclip -selection clipboard"
    elif [[ -n "${DISPLAY:-}" ]] && command -v xsel >/dev/null 2>&1; then echo "xsel --clipboard --input"
    fi
}

# The pane closes when this script exits, so openers other than macOS
# `open` are detached with nohup to outlive it.
open_url() {
    if [[ -n "${FZF_URL_OPENER:-}" ]]; then nohup $FZF_URL_OPENER "$1" >/dev/null 2>&1 &
    elif command -v open >/dev/null 2>&1; then open "$1"
    elif command -v xdg-open >/dev/null 2>&1; then nohup xdg-open "$1" >/dev/null 2>&1 &
    elif [[ -n "${BROWSER:-}" ]]; then nohup "$BROWSER" "$1" >/dev/null 2>&1 &
    else fail "no opener found (open/xdg-open/\$BROWSER)"
    fi
}

if [[ "$key" == "ctrl-y" ]]; then
    cmd=$(get_copy_cmd)
    [[ -z "$cmd" ]] && fail "no clipboard tool found (pbcopy/wl-copy/xclip/xsel)"
    printf '%s' "$chosen" | $cmd
else
    while IFS= read -r url; do
        [[ -n "$url" ]] && open_url "$url"
    done <<< "$chosen"
    wait
fi
