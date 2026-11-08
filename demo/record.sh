#!/usr/bin/env bash
# record.sh: record the README demo as docs/demo.webp.
#
# Run it from a Rex pane:
#
#   brew install ffmpeg webp jq
#   demo/record.sh
#
# The script opens a demo session, shows it in the Rex app, and records the
# Rex window while it types commands and uses the plugin. Then it shows your
# session again and converts the video to an animated WebP.
#
# Every step is lossless. demo/capture.swift records the area of the Rex
# window with ScreenCaptureKit, at the full Retina size, in sRGB colors, with
# transparent corners. A window on top of Rex goes into the recording. ffmpeg stores the frames with QuickTime Animation, and
# img2webp writes a lossless WebP. The first run compiles capture.swift,
# which takes about 30 seconds, and keeps the program for the next runs.
#
# Make the Rex window about 1000x700 points first. Do not use the keyboard or
# mouse while it records (about 30 seconds).
# The first run asks for Screen Recording permission for Rex.
# The demo copies a URL, so the script saves your clipboard text and puts it
# back at the end.
#
# The keys that the script presses do not come from the keyboard, so the
# WebP shows each key name in a caption at the bottom of the window.
# osascript draws each caption as an image, and ffmpeg puts it on the video.
#
# Environment:
#   REX_DEMO_WIDTH   width of the WebP in pixels (default: the window width
#                    in screen pixels, which is two times the width in points
#                    on a Retina screen)
#   REX_DEMO_FPS     frames per second of the WebP (default: 25)
#   REX_DEMO_CLIENT  the Rex app client to use (default: the first app)
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
out="$repo/docs/demo.webp"
fps=${REX_DEMO_FPS:-25}

die() { printf 'record.sh: %s\n' "$1" >&2; exit 1; }

for cmd in rex jq ffmpeg ffprobe img2webp osascript perl swiftc shasum; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not found (brew install ffmpeg webp jq, and xcode-select --install for swiftc)"
done
[[ -n "${REX_SESSION:-}" && -n "${REX_BLOCK:-}" ]] || die "run this script from a Rex pane"

now() { perl -MTime::HiRes=time -e 'printf "%.2f\n", time'; }

# Compile capture.swift once for each version of the file.
cache="${XDG_CACHE_HOME:-$HOME/.cache}/rex-fzf-url-demo"
capture="$cache/capture-$(shasum -a 256 "$repo/demo/capture.swift" | cut -c1-12)"
if [[ ! -x "$capture" ]]; then
    printf "Compiling demo/capture.swift. This takes about 30 seconds.\n" >&2
    mkdir -p "$cache"
    swiftc -O -o "$capture.tmp" "$repo/demo/capture.swift" || die "capture.swift did not compile"
    mv "$capture.tmp" "$capture"
fi

client=${REX_DEMO_CLIENT:-$(rex client ls --json |
    jq -er '[.clients[] | select(.info.kind == "app")][0].client_id')} ||
    die "no Rex app is connected"
home_window=$(rex block inspect "$REX_BLOCK" --json | jq -er '.block.window_id')

# The demo shell starts in this folder. Rex shows the path of the folder in
# the title of the pane, so the path is short and has no private names.
demo_dir=/tmp/acme-app
made_demo_dir=
if [[ ! -e "$demo_dir" ]]; then
    mkdir "$demo_dir"
    made_demo_dir=1
elif [[ ! -d "$demo_dir" || -n "$(ls -A "$demo_dir")" ]]; then
    die "$demo_dir exists and is not an empty folder. Remove it, and then run the script again"
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/rex-fzf-url-demo.XXXXXX")
saved_clip=$(pbpaste 2>/dev/null || true)
demo_session=

cleanup() {
    status=$?
    [[ -n "${rec_pid:-}" ]] && kill -INT "$rec_pid" 2>/dev/null || true
    [[ -n "${enc_pid:-}" ]] && wait "$enc_pid" 2>/dev/null || true
    rex -C "$client" do session.select session_id="$REX_SESSION" \
        window_id="$home_window" >/dev/null 2>&1 || true
    [[ -n "$demo_session" ]] && rex kill "$demo_session" >/dev/null 2>&1 || true
    printf '%s' "$saved_clip" | pbcopy
    rm -rf "$work"
    [[ -n "$made_demo_dir" ]] && rmdir "$demo_dir" 2>/dev/null || true
    exit "$status"
}
trap cleanup EXIT

# Run the demo shell with demo/.zshrc as its only configuration.
created=$(rex new fzf-url-demo --window demo -c "$demo_dir" --shell=none --json -- \
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

# Show the name of a key in a caption, from now until one second later. The
# captions go on the video after the recording.
caption() {
    printf '%s\t%s\n' "$(perl -e "printf '%.2f', $(now) - $start")" "$1" >>"$work/captions.tsv"
}

rex -C "$client" do session.select session_id="$demo_session" >/dev/null
# Rex shows a message at the bottom of the window when it switches to the
# demo session. Wait until the message is gone before the recording starts.
sleep 4

# Find the Rex window on screen: the largest normal window of the app. The
# result is the window number and its size in points.
read -r window_id win_w win_h < <(osascript -l JavaScript -e '
ObjC.import("CoreGraphics");
const list = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(
    $.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements,
    $.kCGNullWindowID)));
const w = list
    .filter(w => /^Rex/.test(w.kCGWindowOwnerName) && w.kCGWindowLayer === 0)
    .sort((a, b) => b.kCGWindowBounds.Width * b.kCGWindowBounds.Height
                  - a.kCGWindowBounds.Width * a.kCGWindowBounds.Height)[0];
const b = w.kCGWindowBounds;
[w.kCGWindowNumber, Math.round(b.Width), Math.round(b.Height)].join(" ");
') || true
[[ -n "${window_id:-}" ]] || die "the Rex window was not found"
printf 'Recording the Rex window (%sx%s points). Do not use the keyboard or mouse.\n' \
    "$win_w" "$win_h" >&2

# capture writes raw frames into a FIFO, and ffmpeg stores them losslessly
# with QuickTime Animation (qtrle). That codec keeps the transparent corners
# and stores only the lines that change, so it keeps up at full size.
mkfifo "$work/frames.fifo"
# capture opens the FIFO for reading and writing, so the open does not wait
# for ffmpeg, which starts when the frame size is known.
"$capture" "$window_id" "$fps" 1<>"$work/frames.fifo" 2>"$work/capture.log" &
rec_pid=$!
size_known() { grep -q '^size ' "$work/capture.log" 2>/dev/null; }
wait_for 10 size_known ||
    die "capture did not start (check the Screen Recording permission for Rex): $(cat "$work/capture.log")"
size=$(sed -n 's/^size //p' "$work/capture.log")
ffmpeg -nostdin -loglevel error -f rawvideo -pixel_format bgra -video_size "$size" \
    -framerate "$fps" -i "$work/frames.fifo" -t 60 -c:v qtrle -y "$work/demo.mov" &
enc_pid=$!
recording() { grep -q '^ready' "$work/capture.log" 2>/dev/null; }
wait_for 10 recording || die "capture did not write a frame: $(cat "$work/capture.log")"
start=$(now)
width=${REX_DEMO_WIDTH:-${size%x*}}
sleep 1.5

# Open the plugin while the pane has no URLs. It shows "No URLs found." in a
# small pane that closes after one second.
caption "Ctrl+Space, U"
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
caption "Ctrl+Space, U"
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
caption "Tab"
key "$picker" tab
sleep 0.8
caption "Ctrl+U"
key "$picker" ctrl+u
sleep 0.8
key "$picker" up
sleep 0.5
key "$picker" up
sleep 0.5
caption "Tab"
key "$picker" tab
sleep 1.5
caption "Ctrl+Y"
key "$picker" ctrl+y
wait_for 5 no_popup || die "the picker did not close"
sleep 0.8

type_text "$pane" "pbpaste"
sleep 0.3
key "$pane" enter
sleep 2.5
end=$(now)

# Stop the recording. When capture stops, the FIFO closes, and ffmpeg
# writes the end of the file.
kill -INT "$rec_pid" 2>/dev/null || true
wait "$rec_pid" 2>/dev/null || true
rec_pid=
wait "$enc_pid" || die "ffmpeg did not save the video"
enc_pid=
[[ -s "$work/demo.mov" ]] || die "ffmpeg made no video"

# Show your session again before the conversion, which takes a moment.
rex -C "$client" do session.select session_id="$REX_SESSION" window_id="$home_window" >/dev/null || true

length=$(perl -e "printf '%.2f', $end - $start")
mkdir -p "$work/frames" "$(dirname "$out")"

# Draw each caption as a PNG image: the key name in bold white text on a
# dark box with round corners. The box is 5.5% of the video height.
cat >"$work/caption.js" <<'EOF'
ObjC.import("AppKit");
function run(argv) {
  const text = argv[0], out = argv[1], h = Number(argv[2]);
  const pad = h * 0.45;
  const attrs = $.NSMutableDictionary.alloc.init;
  attrs.setObjectForKey($.NSFont.boldSystemFontOfSize(h * 0.5), $("NSFont"));
  attrs.setObjectForKey($.NSColor.whiteColor, $("NSColor"));
  const str = $.NSString.alloc.initWithUTF8String(text);
  const size = str.sizeWithAttributes(attrs);
  const w = Math.ceil(size.width + 2 * pad);
  const rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, w, h, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0);
  $.NSGraphicsContext.saveGraphicsState;
  $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep));
  $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.1, 0.1, 0.1, 0.85).setFill;
  $.NSBezierPath.bezierPathWithRoundedRectXRadiusYRadius($.NSMakeRect(0, 0, w, h), h * 0.25, h * 0.25).fill;
  str.drawAtPointWithAttributes($.NSMakePoint(pad, (h - size.height) / 2), attrs);
  $.NSGraphicsContext.restoreGraphicsState;
  rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $()).writeToFileAtomically(out, true);
}
EOF
video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
    -of csv=p=0 "$work/demo.mov")
caption_height=$(perl -e "printf '%d', $video_height * 0.055")

# Put each caption on the video from its time until one second later, or
# until the next caption starts. The frames stay RGBA from start to end, so
# no step reduces the color detail or drops the transparent corners.
inputs=(-i "$work/demo.mov")
filter="[0:v]format=rgba[v0]"
n=0
times=()
labels=()
while IFS=$'\t' read -r t label; do
    times+=("$t")
    labels+=("$label")
done <"$work/captions.tsv"
for ((i = 0; i < ${#times[@]}; i++)); do
    t=${times[i]}
    next=${times[i + 1]:-$length}
    stop=$(perl -e "my \$s = $t + 1; my \$n = $next - 0.05; printf '%.2f', \$s < \$n ? \$s : \$n")
    osascript -l JavaScript "$work/caption.js" "${labels[i]}" "$work/caption-$i.png" "$caption_height"
    inputs+=(-i "$work/caption-$i.png")
    n=$((i + 1))
    filter+=";[v$i][$n:v]overlay=x=(W-w)/2:y=H-h-H*0.08:format=rgb:enable='between(t,$t,$stop)'[v$n]"
done
filter+=";[v$n]fps=$fps"
[[ "$width" != "${size%x*}" ]] && filter+=",scale=$width:-2:flags=lanczos"
filter+="[out]"
ffmpeg -nostdin -loglevel error "${inputs[@]}" -t "$length" -filter_complex "$filter" \
    -map '[out]' -pix_fmt rgba "$work/frames/%04d.png"

# img2webp stores only the part of each frame that changed, so the frames
# where nothing moves add almost nothing to the file.
delay=$(perl -e "printf '%d', 1000 / $fps + 0.5")
(cd "$work/frames" && img2webp -loop 0 -lossless -m 4 -d "$delay" *.png -o "$out" >/dev/null)

printf 'Wrote %s (%s)\n' "$out" "$(du -h "$out" | cut -f1)"
printf 'In the README, show it %s pixels wide: <img src="docs/demo.webp" width="%s">\n' \
    "$win_w" "$win_w" >&2
