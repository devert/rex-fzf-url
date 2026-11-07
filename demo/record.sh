#!/usr/bin/env bash
# record.sh: record the README demo as docs/demo.gif.
#
# Run it from a Rex pane:
#
#   brew install ffmpeg gifski
#   demo/record.sh
#
# The script opens a demo session, shows it in the Rex app, and records the
# Rex window with screencapture while it types commands and uses the plugin.
# Then it shows your session again and converts the video to a GIF.
#
# Do not use the keyboard or mouse while it records (about 35 seconds).
# The first run asks for Screen Recording permission for Rex.
# The demo copies a URL, so the script saves your clipboard text and puts it
# back at the end.
#
# For a sharper GIF, make the Rex window smaller first, about 1100x700.
#
# Environment:
#   REX_DEMO_WIDTH   width of the GIF in pixels (default: the window width,
#                    at most 1200)
#   REX_DEMO_FPS     frames per second of the GIF (default: 15)
#   REX_DEMO_CLIENT  the Rex app client to use (default: the first app)
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
out="$repo/docs/demo.gif"
fps=${REX_DEMO_FPS:-15}

die() { printf 'record.sh: %s\n' "$1" >&2; exit 1; }

for cmd in rex jq ffmpeg gifski osascript screencapture perl; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not found (brew install ffmpeg gifski jq)"
done
[[ -n "${REX_SESSION:-}" && -n "${REX_BLOCK:-}" ]] || die "run this script from a Rex pane"

now() { perl -MTime::HiRes=time -e 'printf "%.2f\n", time'; }

client=${REX_DEMO_CLIENT:-$(rex client ls --json |
    jq -er '[.clients[] | select(.info.kind == "app")][0].client_id')} ||
    die "no Rex app is connected"
home_window=$(rex block inspect "$REX_BLOCK" --json | jq -er '.block.window_id')

work=$(mktemp -d "${TMPDIR:-/tmp}/rex-fzf-url-demo.XXXXXX")
saved_clip=$(pbpaste 2>/dev/null || true)
demo_session=

cleanup() {
    status=$?
    [[ -n "${rec_pid:-}" ]] && kill "$rec_pid" 2>/dev/null || true
    rex -C "$client" do session.select session_id="$REX_SESSION" \
        window_id="$home_window" >/dev/null 2>&1 || true
    [[ -n "$demo_session" ]] && rex kill "$demo_session" >/dev/null 2>&1 || true
    printf '%s' "$saved_clip" | pbcopy
    rm -rf "$work"
    exit "$status"
}
trap cleanup EXIT

# Run the demo shell with demo/.zshrc as its only configuration.
created=$(rex new fzf-url-demo --window demo -c "$work" --shell=none --json -- \
    env ZDOTDIR="$repo/demo" zsh -i)
demo_session=$(jq -er '.session_id' <<<"$created")
pane=$(jq -er '.initial_windows[0].block_ids[0]' <<<"$created")

# Wait for the condition in "$@" to pass, for at most $1 seconds.
wait_for() {
    local limit=$1 i=0
    shift
    until "$@"; do
        i=$((i + 1))
        [[ $i -gt $((limit * 10)) ]] && return 1
        sleep 0.1
    done
}
has_prompt() { rex capture -s "$demo_session" -b "$pane" --trim | grep -q '❯'; }
popup() {
    rex session inspect "$demo_session" --json | jq -r '
        .windows[0].layers[] | select(.kind == "floating")
        | [.. | .block_id? // empty][0]' | head -n 1
}
has_popup() { [[ -n "$(popup)" ]]; }
no_popup() { [[ -z "$(popup)" ]]; }

wait_for 5 has_prompt || die "the demo shell did not start"

# Type text one character at a time, like a person.
type_text() {
    local block=$1 text=$2 i
    for ((i = 0; i < ${#text}; i++)); do
        rex send -s "$demo_session" -b "$block" -- "${text:i:1}"
        sleep 0.05
    done
}
key() { rex send-key -s "$demo_session" -b "$1" "${@:2}"; }

rex -C "$client" do session.select session_id="$demo_session" >/dev/null
sleep 1

# Find the Rex window on screen: the largest normal window of the app.
rect=$(osascript -l JavaScript -e '
ObjC.import("CoreGraphics");
const list = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(
    $.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements,
    $.kCGNullWindowID)));
const w = list
    .filter(w => /^Rex/.test(w.kCGWindowOwnerName) && w.kCGWindowLayer === 0)
    .sort((a, b) => b.kCGWindowBounds.Width * b.kCGWindowBounds.Height
                  - a.kCGWindowBounds.Width * a.kCGWindowBounds.Height)[0];
const b = w.kCGWindowBounds;
[b.X, b.Y, b.Width, b.Height].map(Math.round).join(",");
') || die "the Rex window was not found"
window_width=${rect#*,*,}
window_width=${window_width%%,*}
width=${REX_DEMO_WIDTH:-$((window_width < 1200 ? window_width : 1200))}
printf 'Recording the Rex window at %s. Do not use the keyboard or mouse.\n' "$rect" >&2

# Record for at most 60 seconds. The video is cut to the demo length below.
screencapture -v -x -V 60 -R "$rect" "$work/demo.mov" >/dev/null 2>&1 &
rec_pid=$!
start=$(now)
sleep 1.5

# Open the plugin while the pane has no URLs. It shows "No URLs found." in a
# small pane that closes after one second.
rex do -s "$demo_session" -b "$pane" fzf_url >/dev/null
wait_for 5 has_popup || die "the message did not open"
wait_for 5 no_popup || die "the message did not close"
sleep 0.8

type_text "$pane" "git push -u origin fix-login-redirect"
sleep 0.3
key "$pane" enter
sleep 1.2
type_text "$pane" "npm run dev"
sleep 0.3
key "$pane" enter
sleep 1.5

# Open the picker in the demo pane, as the key binding does.
rex do -s "$demo_session" -b "$pane" fzf_url >/dev/null
wait_for 5 has_popup || die "the picker did not open"
picker=$(popup)
sleep 1.2
# The selection starts on the last URL, at the bottom of the list, so move
# up first.
key "$picker" up
sleep 0.5
key "$picker" up
sleep 0.5
key "$picker" down
sleep 0.8
# Mark two URLs with Tab, and copy both of them with Ctrl+Y. Clearing the
# filter moves the selection to the last URL, two rows below localhost.
type_text "$picker" "pull"
sleep 0.8
key "$picker" tab
sleep 0.8
key "$picker" ctrl+u
sleep 0.8
key "$picker" up
sleep 0.5
key "$picker" up
sleep 0.5
key "$picker" tab
sleep 1.5
key "$picker" ctrl+y
wait_for 5 no_popup || die "the picker did not close"
sleep 0.8

type_text "$pane" "pbpaste"
sleep 0.3
key "$pane" enter
sleep 2.5
end=$(now)

# Stop the recording. If screencapture ignores the signal, it stops at the
# 60 second limit.
kill -INT "$rec_pid" 2>/dev/null || true
wait "$rec_pid" 2>/dev/null || true
rec_pid=
[[ -s "$work/demo.mov" ]] || die "screencapture made no video (check the Screen Recording permission for Rex)"

# Show your session again before the conversion, which takes a moment.
rex -C "$client" do session.select session_id="$REX_SESSION" window_id="$home_window" >/dev/null || true

length=$(perl -e "printf '%.2f', $end - $start")
mkdir -p "$work/frames" "$(dirname "$out")"
ffmpeg -loglevel error -i "$work/demo.mov" -t "$length" \
    -vf "fps=$fps,scale=$width:-1:flags=lanczos" "$work/frames/%04d.png"
gifski --quiet --fps "$fps" --width "$width" --quality 90 -o "$out" "$work"/frames/*.png

printf 'Wrote %s (%s)\n' "$out" "$(du -h "$out" | cut -f1)"
