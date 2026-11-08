# AGENTS.md

This file gives guidance to coding agents that work in this repository.

## What this is

A Rex terminal plugin. It collects URLs from the focused pane's scrollback and lists them with fzf in a floating pane. Enter opens a URL, and Ctrl+Y copies it. Users install it by cloning into `~/.config/rex/plugins/rex-fzf-url` and calling `require("plugins.rex-fzf-url").setup{...}` from their Rex `init.lua`. `README.md` documents every `setup` option. When an option changes, update the README.

## Commands

```sh
test/run.sh                    # run all tests, exit 1 on failure
luajit test/init.test.lua      # one Lua test file
/bin/bash test/picker.test.sh  # one bash test file
test/run.sh --coverage         # tests plus luacov, Devel::Cover, kcov reports
test/run.sh --open             # same, then open test/coverage.html
test/install-coverage-tools.sh # one-time install of coverage tools (Homebrew)
rex config reload              # reload the plugin in a running Rex
```

The tests do not need Rex. Lua tests replace the `rex` global with a fake table. Bash tests put fake `fzf`, `rex`, clipboard, and opener programs on `PATH`. Each source file has one test file named `<source name>.test.lua` or `.test.sh`. `run.sh` finds tests by that pattern. Each test file must end by printing `N passed, M failed` as its last line (use `H.done()` from `test/harness.lua` or `finish` from `test/harness.sh`), because `run.sh` parses it.

## Compatibility constraints

- Rex runs plugins with plain Lua 5.1. Tests run under LuaJIT, so `test/harness.lua` removes `bit`, `jit`, `ffi`, and similar to catch LuaJIT-only code. Do not use `goto` (the harness cannot catch it).
- All bash scripts must work with macOS `/bin/bash` 3.2 (no associative arrays, no `mapfile`, no `${var,,}`).
- Only tested on macOS.

## Architecture

The flow spans Lua inside Rex and shell scripts inside a popup pane:

1. `init.lua` `setup()` registers the `fzf_url` action (and binds `opts.key`). On run, `read_scrollback` reads the pane text via `rex.block.call(terminal, "format"/"blob_read")`, keeping only the newest `max_scrollback` bytes and trimming to whole lines and whole UTF-8 characters.
2. The text is piped to `bin/extract-urls.pl` with `rex.exec`. It strips ANSI/OSC escapes. Then it matches one alternation per line: URL, git remote, `www.`, IPv4, and quoted `'user/repo'`. User `extra_patterns` arrive as `REGEX URL` argument pairs. Order of the alternation matters: an earlier match consumes its text.
3. `init.lua` reverses the list (newest first), writes it to a temp file, and opens a floating layer running `bin/picker.sh` (or `bin/message.sh` for "No URLs found."). Terminal options have no env field, so settings pass as `env FZF_URL_*=... bash picker.sh <file>`.
4. `bin/picker.sh` runs fzf and opens or copies the selection. When a floating pane closes, Rex does not refocus the source pane. So both scripts call `rex focus` on exit.

### Popup sizing

Most of the complexity is in sizing the popup to fit its content. Rex places floating panes by fractions of the window but does not report the window size in cells.

- `lib/popup-size.lua` holds the math and the empirically measured insets (see its header comment for the measurements). It tracks a range `[low, high)` of possible window sizes and picks bounds that fit every size in the range.
- `locate()` in `init.lua` narrows that range from the size and rect of each tiled pane. If the layout key matches a cached measurement, it merges that too.
- `bin/picker.sh` runs `bin/measure.lua` in the background via `rex do`. It reads the real size of the popup and saves a tighter range to `$TMPDIR/rex-fzf-url-$USER.sizes`. The next popup in that window then fits exactly.
- The popup terminal starts at the smallest size it can get. The terminal reflows when it narrows, but not when it widens. `list_rows` accounts for fzf wrapping long URLs.

`init.lua` exports internals as `M._*` for the tests only.

## Demo

`demo/` records `docs/demo.webp` with `demo/record.sh` against a live Rex app. See `demo/README.md`. In `demo/.zshrc` fake output, avoid quoted `'user/repo'` text, because the extractor turns it into a GitHub URL.
