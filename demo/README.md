# Demo recording

This folder holds the files that record `docs/demo.webp`, the animation in the main README. An animated WebP plays and loops like a GIF, but it keeps every color without loss.

The folder has three files:

- `record.sh` opens a demo session in Rex and uses the plugin while it records the Rex window. Then it converts the video to an animated WebP.
- `capture.swift` is the program that records the window. It uses ScreenCaptureKit, the screen recording API of macOS. The script compiles it at the first run.
- `.zshrc` is the shell configuration for the demo pane. It defines fake `git` and `npm` commands that print fixed sample output, so every recording shows the same URLs.

## Why the recording is lossless

A GIF has at most 256 colors in a frame. The soft shadow of a floating pane has more colors than that, so a GIF shows bands and stale pixels in the shadow. A video codec such as H.264 also blurs colored text.

Every step of this recording is lossless:

- `capture.swift` records the window at the full Retina size, in sRGB colors.
- `ffmpeg` stores the frames with the QuickTime Animation codec, which is lossless.
- `img2webp` writes a lossless WebP.

The ffmpeg screen input (`avfoundation`) is not used, because it makes the colors darker than they are on the screen.

## Requirements

- macOS. The script uses `osascript`, and `capture.swift` uses ScreenCaptureKit.
- The Swift compiler `swiftc`. To install it, run `xcode-select --install`.
- The Rex app for macOS, build 1853 or later, with this plugin installed and loaded. See the install steps in the main README. An earlier build does not add padding at the bottom of a floating pane, so the picker in the recording has the wrong size.
- `fzf`, `jq`, `ffmpeg`, and `webp`. The `ffmpeg` formula also installs `ffprobe`, and the `webp` formula installs `img2webp`.

To install the tools with Homebrew, run:

```sh
brew install fzf jq ffmpeg webp
```

To make sure that Rex loaded the plugin, run this command. It must print a line for `fzf_url`.

```sh
rex actions | grep fzf_url
```

## Prepare the window

1. Resize the Rex window to 1000 x 700 points. GitHub shows the README in a column of about 880 pixels, so a wider window gives smaller text.
2. Hide anything in the Rex window that you do not want in the recording. If the tab bar or the names of your other sessions show, they go into the recording.
3. Move other windows away from the Rex window. The script records the area of the screen that the window covers, so a window on top of Rex goes into the recording.
4. Turn on Do Not Disturb in macOS. If a notification shows during the recording, it goes into the recording.

To resize the window to 1000 x 700 points without the mouse, run this command. macOS can ask you to give Rex the Accessibility permission.

```sh
osascript -e 'tell application "System Events" to set size of front window of (first process whose name starts with "Rex") to {1000, 700}'
```

## Record the demo

1. Open a pane in the Rex window, and go to the root folder of this repository.
2. Run the script:

   ```sh
   demo/record.sh
   ```

3. If macOS asks for the Screen Recording permission for Rex, give the permission. If macOS tells you to quit and open Rex again, do that, and then run the script again.
4. Do not use the keyboard or the mouse until the script prints `Wrote .../docs/demo.webp`. The recording takes about 30 seconds, and the conversion to WebP takes about 20 seconds more.

The first run compiles `capture.swift`, which takes about 30 seconds more. The script keeps the program in `~/.cache/rex-fzf-url-demo`. If `capture.swift` changes, the script compiles it again.

When the recording stops, the script shows your session again and deletes the demo session. It also puts back the text that was in your clipboard before the demo. It does not keep images or files that were in the clipboard. If the script fails, it also does these steps.

## How the window is recorded

macOS puts a screen sharing badge over the window buttons of a window that a program records alone. So `capture.swift` records the display, cut to the area of the Rex window.

A recording of the display has no transparent corners. Before the recording starts, `capture.swift` takes one screenshot of the Rex window alone, which gives the round shape of the window. Each frame then gets the pixels at the edge of that shape from the screenshot. The corners outside the window are transparent, so the WebP looks correct on a light and on a dark GitHub page.

The screenshot also shows the badge for a short time. `capture.swift` waits two seconds before the recording starts, so the badge is gone.

## What the demo shows

The demo shell starts in the folder `/tmp/acme-app`, because Rex shows the path of that folder in the title of the pane. The script makes the folder and deletes it at the end.

First, the script opens the plugin while the demo pane has no URLs, as the key binding does. The plugin shows `No URLs found.` in a small pane that closes after one second. Then the demo pane runs `git push` and `npm run dev`, which print four URLs.

The script opens the plugin again, and it shows the URL list. It moves the selection up and down. Then it types `pull` to filter the list, and marks the pull request URL with `Tab`. It clears the filter with `Ctrl+U`, moves up to the local Vite URL, and marks it with `Tab`. Then it copies both URLs with `Ctrl+Y`. At the end, the demo pane runs `pbpaste` to show the two copied URLs, one on each line.

The script presses the keys without the keyboard, so the recording shows a caption at the bottom of the window for each key: `Cmd+U` (the key binding from the main README), `Tab`, `Ctrl+U`, and `Ctrl+Y`. Each caption shows for one second. The script uses `osascript` to draw each caption as an image, and `ffmpeg` to put it on the video. The captions are not on the screen while the script records.

## Look at the result

To play the WebP, open it in Safari:

```sh
open -a Safari docs/demo.webp
```

Make sure that the text is easy to read and that the recording shows no private information.

## Configuration

To change the recording, set these environment variables before the script name:

- `REX_DEMO_WIDTH` is the width of the WebP in pixels. The default is the width of the window in screen pixels. On a Retina screen, that is two times the width in points.
- `REX_DEMO_FPS` is the number of frames per second. The default is 25, so each frame shows for exactly 40 milliseconds.
- `REX_DEMO_CLIENT` is the Rex app to use, as a client label or ID from `rex client ls`. The default is the first Rex app that is connected.

For example, this command makes a WebP that is 1600 pixels wide, with 20 frames per second:

```sh
REX_DEMO_WIDTH=1600 REX_DEMO_FPS=20 demo/record.sh
```

## Change the demo

To change the output in the demo pane, edit the `git` and `npm` functions in `.zshrc`. Do not put text such as `'origin/main'` in the output. The plugin reads a quoted `'user/repo'` as a GitHub shorthand and adds a URL for it to the list.

To change the commands and the keys, edit the part of `record.sh` between the line `start=$(now)` and the line `end=$(now)`.

## Troubleshooting

If the script stops with `/tmp/acme-app exists and is not an empty folder`, a file or another folder uses that name. Move it or delete it, and then run the script again.

If the script stops with `capture.swift did not compile`, install the Swift compiler with `xcode-select --install`. Then run the script again.

If the script stops with `capture did not start`, give Rex the Screen Recording permission. You find it in `System Settings > Privacy & Security > Screen Recording`. Then run the script again.

If the script stops with `the picker did not open`, Rex did not load the plugin. Run `rex config reload`, and then run the script again.

If the script stops with `run this script from a Rex pane`, open a pane in the Rex app, and run the script there.

If the script stops with `the Rex window was not found`, the Rex window is minimized or on a different desktop. Show the window, and then run the script again.

## The recording in the main README

The main `README.md` shows the recording with this line. If you change the size of the window, change the `width` value to the new width in points. The `width` attribute shows the WebP at the size of the window in points, so the text is sharp on a Retina screen.

```html
<img src="docs/demo.webp" width="1000" alt="Demo of rex-fzf-url">
```
