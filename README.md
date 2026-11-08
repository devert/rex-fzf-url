# rex-fzf-url

A [Rex](https://www.superlogical.com/rex) plugin that lets you open or copy a URL from your terminal output.

The plugin collects every URL in the focused pane, even ones that scrolled off screen. It lists them with [fzf](https://github.com/junegunn/fzf) in a floating pane. Pick one to open it in your browser or copy it to the clipboard.

## Use

Press the key that you set in the install steps. Then use these keys in the list:

- `Enter` opens the selected URL.
- `Ctrl+Y` copies the selected URL to the clipboard.
- `Tab` selects more than one URL.

You can also open the list from the Rex command palette. Search for "Find URLs in Pane".

## Requirements

- [Rex](https://www.superlogical.com/rex)
- [fzf](https://github.com/junegunn/fzf), in the `PATH` of your login shell (the shell that starts in new panes)
- [perl](https://www.perl.org) and [bash](https://www.gnu.org/software/bash/) (macOS includes both)

## Install

1. Clone the repository into the `plugins` folder of your Rex configuration:

   ```sh
   git clone https://github.com/devert/rex-fzf-url.git ~/.config/rex/plugins/rex-fzf-url
   ```

2. Add this line to `~/.config/rex/init.lua`:

   ```lua
   require("plugins.rex-fzf-url").setup({ key = "ctrl+space>u" })
   ```

   To open the list, press Ctrl+Space, then U. You can set `key` to any key combination that Rex accepts.

3. Load the new configuration:

   ```sh
   rex config reload
   ```

If you set `XDG_CONFIG_HOME`, use `$XDG_CONFIG_HOME/rex` in place of `~/.config/rex` in steps 1 and 2.

## Configuration

Every configuration value is optional. Pass the ones that you want to `setup`:

```lua
require("plugins.rex-fzf-url").setup({
  key = "ctrl+space>u",
  max_width = 0.8,
})
```

### `key`

The key that opens the list, such as `"ctrl+space>u"`.

**Default**: none. The plugin does not bind a key, but you can open the list from the command palette.

### `open_cmd`

The command that opens a URL, such as `"open -a Firefox"`.

**Default**: the first of these commands that the plugin finds: `open`, `xdg-open`, and `$BROWSER`.

### `copy_cmd`

The command that copies text to the clipboard, such as `"pbcopy"`.

**Default**: the first of these commands that the plugin finds: `pbcopy`, `wl-copy`, `xclip -selection clipboard`, and `xsel --clipboard --input`.

### `fzf_options`

Extra flags for fzf. For example, `"--no-wrap"` stops long URLs from wrapping.

**Default**: none.

### `max_width` and `max_height`

The largest size of the floating pane, as a fraction of the window. A value must be more than 0 and at most 1, or the plugin ignores it. The pane fits its list of URLs and grows up to these limits. A longer list scrolls, and a longer URL wraps.

**Default**: `max_width = 0.6` and `max_height = 0.4`.

### `max_scrollback`

The most text to read from the pane, in bytes. A large scrollback makes the list open more slowly. If the pane has more text than this value, the plugin reads only the newest lines that fit. The newest URLs are at the top of the list, so the lost URLs are the oldest ones. To find older URLs, set a larger value, such as `4 * 1024 * 1024` for 4 MB.

**Default**: `512 * 1024` (512 KB). That is about 6,000 lines of 80 characters.

### `extra_patterns`

A list of your own kinds of text to find in the pane and show as URLs. For example, the plugin can show the issue name `ENG-123` as a link to that issue in Linear. Each item in the list is a table with two values:

- `regex` is a Perl regular expression (a text pattern) that matches the text.
- `url` is the URL that the plugin builds from each match. In `url`, `$0` is the matched text. `$1` to `$9` are the capture groups, which are the parts of the regex in parentheses.

```lua
extra_patterns = {
  { regex = [[ENG-\d+]], url = "https://linear.app/your-workspace/issue/$0" },
  { regex = [[PR #(\d+)]], url = "https://github.com/your-org/your-repo/pull/$1" },
},
```

The `regex` value must use Perl syntax, such as `\d` for a digit and `\.` for a period. In a Lua string with quotes, you must write each backslash two times (`"ENG-\\d+"`). A Lua long string, such as `[[ENG-\d+]]`, keeps the backslashes as you write them.

If a `regex` is not valid Perl, the plugin finds no URLs and stops with the error from Perl, such as `Unmatched ( in regex`.

**Default**: none.

## License

MIT. Based on [junegunn/tmux-fzf-url](https://github.com/junegunn/tmux-fzf-url), [wfxr/tmux-fzf-url](https://github.com/wfxr/tmux-fzf-url), and [kaar/herdr-fzf-url](https://github.com/kaar/herdr-fzf-url), all MIT.
