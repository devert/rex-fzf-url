# rex-fzf-url

A [Rex](https://www.superlogical.com/rex) plugin that finds all URLs in the scrollback of the focused pane and displays them in a floating pane picker with [fzf](https://github.com/junegunn/fzf). You select a URL and the plugin opens it in your browser or copies it to the clipboard. Inspired by [junegunn/tmux-fzf-url](https://github.com/junegunn/tmux-fzf-url).

- Enter opens the selected URL and closes the picker.
- Ctrl+Y copies the selected URL to the clipboard.
- Tab selects more than one URL.

The picker opens in a floating pane in the middle of the window. The pane size fits the list of URLs, up to 60% of the window width and 40% of the window height. If there are more URLs than fit, the list scrolls. If a URL is wider than the pane, it wraps. The newest URLs are at the bottom, next to the prompt.

The plugin finds these types of text:

- `http`, `https`, `ftp`, and `file` URLs.
- Git remotes such as `git@github.com:user/repo.git`. The plugin changes them to `https` URLs.
- Domains that start with `www.`.
- IPv4 addresses, with an optional port and path.
- GitHub names in quotes, such as `'user/repo'`.

## Requirements

- Rex.
- `fzf` in the `PATH` of your login shell.
- `perl` and `bash`. macOS includes both.

## Install

Clone the repository into a `plugins` folder in your Rex configuration folder:

```sh
git clone https://github.com/devert/rex-fzf-url.git ~/.config/rex/plugins/rex-fzf-url
```

If you set `XDG_CONFIG_HOME`, your Rex configuration folder is `$XDG_CONFIG_HOME/rex`. Clone the repository into `$XDG_CONFIG_HOME/rex/plugins/rex-fzf-url`, and use `$XDG_CONFIG_HOME/rex/init.lua` in the next step.

Add this line to `~/.config/rex/init.lua`:

```lua
require("plugins.rex-fzf-url").setup{ key = "ctrl+space>u" }
```

Load the changed configuration:

```sh
rex config reload
```

The `key` option binds a key to the picker. `ctrl+space>u` means that you press Ctrl+Space, then U. If you do not set `key`, the plugin binds no key. You can then bind the `fzf_url` action yourself:

```lua
require("plugins.rex-fzf-url").setup{}
rex.bind("cmd+shift+u", "fzf_url")
```

You can also start the picker from the command palette. Search for "Open URL from Scrollback".

## Options

All options are optional.

```lua
require("plugins.rex-fzf-url").setup{
  key = "ctrl+space>u",           -- the key that opens the picker
  open = "open -a Firefox",       -- the command that opens a URL
  copy_cmd = "pbcopy",            -- the command that copies to the clipboard
  fzf_options = "--no-wrap",      -- more fzf options
  extra_pattern = "JIRA-\\d+",    -- one more Perl regex to find
  extra_sub = "https://jira.example.com/browse/$0",  -- the URL for each match
}
```

If you do not set `open`, the plugin uses `open` on macOS and `xdg-open` on Linux. If you do not set `copy_cmd`, the plugin uses the first one of `pbcopy`, `wl-copy`, `xclip`, and `xsel` that it finds.

In `extra_sub`, `$0` is the full match, and `$1` to `$9` are the capture groups.

## Limits

The plugin reads the scrollback as plain text. If a program shows a link with a label instead of the URL (an OSC 8 hyperlink), the plugin does not find that link.

If the scrollback contains no URLs, a small pane shows "No URLs found." The pane closes after one second, or when you press a key.

## Tests

```sh
test/extract-urls.test.sh
```

## Credits and license

MIT. The look and layout of the picker come from [junegunn/tmux-fzf-url](https://github.com/junegunn/tmux-fzf-url) (MIT). The URL patterns come from [wfxr/tmux-fzf-url](https://github.com/wfxr/tmux-fzf-url) (MIT). The Perl script is adapted from [kaar/herdr-fzf-url](https://github.com/kaar/herdr-fzf-url) (MIT).
