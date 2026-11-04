# rex-fzf-url

A [Rex](https://www.superlogical.com/rex) plugin that lets you open or copy a URL from your terminal output.

The plugin finds the URLs in the focused pane, including the text that scrolled out of view. It shows them in an [fzf](https://github.com/junegunn/fzf) list in a floating pane. The floating pane opens in the center of the window, over all other panes. You select a URL, and the plugin opens it in your browser or copies it to the clipboard.

## Use

Press the key that you set in the install steps. Then use these keys in the list:

- **Enter** opens the selected URL.
- **Ctrl+Y** copies the selected URL to the clipboard.
- **Tab** selects more than one URL.

You can also open the list from the Rex command palette. Search for "Find URLs in Pane".

## Requirements

- [Rex](https://www.superlogical.com/rex)
- [`fzf`](https://github.com/junegunn/fzf), in the `PATH` of your login shell (the shell that starts in new panes)
- [`perl`](https://www.perl.org) and [`bash`](https://www.gnu.org/software/bash/) (macOS includes both)

## Install

1. Clone the repository into the `plugins` folder of your Rex configuration:

   ```sh
   git clone https://github.com/devert/rex-fzf-url.git ~/.config/rex/plugins/rex-fzf-url
   ```

2. Add this line to `~/.config/rex/init.lua`:

   ```lua
   require("plugins.rex-fzf-url").setup{ key = "ctrl+space>u" }
   ```

   With this key, you press Ctrl+Space, then U, to open the list. You can set `key` to any key combination that Rex accepts.

3. Load the new configuration:

   ```sh
   rex config reload
   ```

If you set `XDG_CONFIG_HOME`, use `$XDG_CONFIG_HOME/rex` in place of `~/.config/rex` in steps 1 and 2.

## Configuration

You do not have to set any of these values:

```lua
require("plugins.rex-fzf-url").setup{
  key = "ctrl+space>u",           -- the key that opens the list
  open = "open -a Firefox",       -- the command that opens a URL
  copy_cmd = "pbcopy",            -- the command that copies to the clipboard
  fzf_options = "--no-wrap",      -- extra flags for fzf, such as "--no-wrap" to stop long URLs from wrapping
  extra_pattern = "ENG-\\d+",     -- one extra pattern to find, such as issue names like ENG-123 (a Perl regex, only one is allowed)
  extra_sub = "https://linear.app/your-workspace/issue/$0",  -- turn each match into a URL ($0 is the matched text)
}
```

To find your own kind of text, set `extra_pattern` to a Perl regex (a text pattern) and `extra_sub` to the URL to build from each match.

If you do not set `open` or `copy_cmd`, the plugin uses the default command for your system.

## License

MIT. Based on [junegunn/tmux-fzf-url](https://github.com/junegunn/tmux-fzf-url), [wfxr/tmux-fzf-url](https://github.com/wfxr/tmux-fzf-url), and [kaar/herdr-fzf-url](https://github.com/kaar/herdr-fzf-url), all MIT.
