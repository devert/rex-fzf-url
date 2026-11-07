# Demo recording

This folder holds the script that records `docs/demo.gif`, the animation in the main README. The script `record.sh` opens a demo session in Rex and uses the plugin while macOS records the Rex window. Then it converts the video to a GIF. The file `.zshrc` is the shell configuration for the demo pane. It defines fake `git` and `npm` commands that print fixed sample output, so every recording shows the same URLs.

## Requirements

- macOS. The script uses `screencapture` and `osascript`.
- The Rex app for macOS, build 1853 or later, with this plugin installed and loaded. See the install steps in the main README. An earlier build does not add padding at the bottom of a floating pane, so the picker in the GIF has the wrong size.
- `fzf`, `jq`, `ffmpeg`, and `gifski`.

To install the tools with Homebrew, run:

```sh
brew install fzf jq ffmpeg gifski
```

To make sure that Rex loaded the plugin, run this command. It must print a line for `fzf_url`.

```sh
rex actions | grep fzf_url
```

## Prepare the window

1. Resize the Rex window to about 1100 x 700 points. Drag a corner of the window to change its size. The GIF is at most 1200 pixels wide, so a larger window gives smaller text.
2. Hide anything in the Rex window that you do not want in the GIF. The script records the whole window. If the tab bar or the names of your other sessions show, they go into the GIF.
3. Move other windows away from the Rex window. The script records the area of the screen that the window covers, so a window on top of Rex goes into the GIF.
4. Turn on Do Not Disturb in macOS. If a notification shows during the recording, it goes into the GIF.

## Record the demo

1. Open a pane in the Rex window, and go to the root folder of this repository.
2. Run the script:

   ```sh
   demo/record.sh
   ```

3. If macOS asks for Screen Recording permission for Rex, give the permission. If macOS tells you to quit and open Rex again, do that, and then run the script again.
4. Do not use the keyboard or the mouse until the script prints `Wrote .../docs/demo.gif`. The recording takes about 35 seconds, and the conversion to a GIF takes some more seconds.

When the recording stops, the script shows your session again and deletes the demo session. It also puts back the text that was in your clipboard before the demo. It does not keep images or files that were in the clipboard. If the script fails, it also does these steps.

## What the demo shows

First, the script opens the plugin while the demo pane has no URLs, as the key binding does. The plugin shows `No URLs found.` in a small pane that closes after one second. Then the demo pane runs `git push` and `npm run dev`, which print four URLs. The script opens the plugin again, and it shows the URL list. It moves the selection up and down. Then it types `pull` to filter the list, and marks the pull request URL with `Tab`. It clears the filter with `Ctrl+U`, moves up to the local Vite URL, and marks it with `Tab`. The list then shows both marked URLs. Then it copies both URLs with `Ctrl+Y`. At the end, the demo pane runs `pbpaste` to show the two copied URLs, one on each line.

## Look at the result

To play the GIF, open it in Safari:

```sh
open -a Safari docs/demo.gif
```

Make sure that the text is easy to read and that the GIF shows no private information. If the file is large, record it again with a smaller width or fewer frames per second. A small file makes the README load faster.

## Configuration

To change the GIF, set these environment variables before the script name:

- `REX_DEMO_WIDTH` is the width of the GIF in pixels. The default is the width of the Rex window, at most 1200.
- `REX_DEMO_FPS` is the number of frames per second in the GIF. The default is 15.
- `REX_DEMO_CLIENT` is the Rex app to use, as a client label or ID from `rex client ls`. The default is the first Rex app that is connected.

For example, this command makes a GIF that is 1000 pixels wide, with 12 frames per second:

```sh
REX_DEMO_WIDTH=1000 REX_DEMO_FPS=12 demo/record.sh
```

## Change the demo

To change the output in the demo pane, edit the `git` and `npm` functions in `.zshrc`. Do not put text such as `'origin/main'` in the output. The plugin reads a quoted `'user/repo'` as a GitHub shorthand and adds a URL for it to the list.

To change the commands and the keys, edit the part of `record.sh` between the start of `screencapture` and the `kill -INT` line.

## Troubleshooting

If the script stops with `screencapture made no video`, give Rex the Screen Recording permission. You find it in `System Settings > Privacy & Security > Screen Recording`. Then run the script again.

If the script stops with `the picker did not open`, Rex did not load the plugin. Run `rex config reload`, and then run the script again.

## Add the GIF to the main README

Put this line near the top of the main `README.md`:

```markdown
![Demo](docs/demo.gif)
```
