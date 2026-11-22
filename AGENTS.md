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

The tests do not need Rex. Lua tests replace the `rex` global with a fake table. Bash tests put fake `fzf`, `rex`, clipboard, and opener programs on `PATH`. The layout tests at the end of `test/init.test.lua` are the exception: they run `bin/picker.sh` with real fzf in a detached tmux session, and check the `layout` values in `init.lua` against the screen. They skip when tmux or fzf is missing. If you change the fzf options in `picker.sh`, update `layout` until these tests pass. Each source file has one test file named `<source name>.test.lua` or `.test.sh`. `run.sh` finds tests by that pattern. Each test file must end by printing `N passed, M failed` as its last line (use `H.done()` from `test/harness.lua` or `finish` from `test/harness.sh`), because `run.sh` parses it.

## Test coverage

Each source file must have 100% line coverage. `test/run.sh --coverage` prints a Coverage table with one row for each file. The script does not fail when a file has less than 100%, so you must read the table.

1. After each change to a source file or a test file, run `test/run.sh --coverage`. Plain `test/run.sh` does not measure coverage.
2. Make sure that each row in the Coverage table shows 100.0%.
3. If a row shows less than 100.0%, open `test/coverage.html` and find the lines with no hits. Add tests for those lines.
4. If no test can reach a line, tell the user. Do not remove the line or skip these steps unless the user approves.
5. Do not say that a change is done until each row shows 100.0%.

If `run.sh` says that the coverage tools are not found, tell the user. To install them, the user runs `test/install-coverage-tools.sh`.

Two bash patterns hide covered lines from kcov:

- kcov reads the trace that bash 3.2 writes to stderr. If you send the stderr of a `{ ... }` group, a subshell, or a function body to `/dev/null`, kcov sees no hits on the lines inside it. Put `2>/dev/null` on each command instead.
- If a command spans more than one line, bash 3.2 reports only the number of its last line. kcov then sees no hit on its first line. Keep each command on one line. The fzf call in `bin/picker.sh` is the one exception, and `run.sh` leaves its first line out of the count.

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
- `bin/picker.sh` calls `wait_resize` from `bin/wait-resize.sh`, which runs `bin/measure.lua` via `rex do` before fzf starts. It reads the size that the owner of the popup asks for, and saves a tighter range to `$TMPDIR/rex-fzf-url-$USER.v2.sizes`. Later popups in that window then fit more closely. Each popup narrows the range, so wide popups can need a few popups before they fit exactly. When a change to `lib/popup-size.lua` makes saved ranges wrong, increase the version in that file name in `init.lua`.
- `init.lua` does not give the popup a starting size. The app creates and owns the popup, and the terminal uses the size that its owner asks for. With a starting size, the terminal keeps that size and does not fit the pane. So the terminal starts at 80x24. `bin/picker.sh` and `bin/message.sh` call `wait_resize`, which waits until the terminal has the size that `measure.lua` prints, before they draw anything. `list_rows` counts the rows that fzf uses when it wraps long URLs, at the fewest columns that the pane can get, to size the pane. The pane can get more columns, so `picker.sh` counts the wrapped rows again at its real width for `--height` (`FZF_URL_HEIGHT` plus `FZF_URL_WRAP`). Keep the two counts the same. `wait_resize` stops `rex do` after one second, so a busy app can't leave the popup blank.

`init.lua` exports internals as `M._*` for the tests only.

## Demo

`demo/` records `docs/demo.webp` with `demo/record.sh` against a live Rex app. See `demo/README.md`. In `demo/.zshrc` fake output, avoid quoted `'user/repo'` text, because the extractor turns it into a GitHub URL.
