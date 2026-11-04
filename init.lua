-- rex-fzf-url: pick a URL from the focused pane's scrollback with fzf.
--
-- Install by cloning this repository into ~/.config/rex/plugins/rex-fzf-url,
-- then add this to ~/.config/rex/init.lua:
--
--   require("plugins.rex-fzf-url").setup{ key = "ctrl+space>u" }
--
-- See README.md for every option.

local M = {}

local terminal = "com.superlogical.terminal"

-- The folder that holds this file, so the helper scripts are found wherever
-- the plugin is installed.
local plugin_dir = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/[^/]*$")) or "."

-- Read the whole screen and scrollback as plain text. Large output arrives in
-- parts, so read the rest with blob_read until it is complete.
local function read_scrollback(block_id)
  local chunk = 512 * 1024
  local r, err = rex.block.call(terminal, "format", {
    block_id = block_id, format = "text", trim = true, unwrap = true, max_bytes = chunk,
  })
  if r == nil then return nil, err end
  local parts = { r.content or "" }
  local offset = #parts[1]
  while r.id ~= nil and not r.eof do
    r, err = rex.block.call(terminal, "blob_read", {
      block_id = block_id, id = r.id, offset = offset, max_bytes = chunk,
    })
    if r == nil then return nil, err end
    if r.data == nil or r.data == "" then break end
    parts[#parts + 1] = r.data
    offset = offset + #r.data
  end
  return table.concat(parts)
end

-- The largest popup, as fractions of the window. With more URLs than fit,
-- the list scrolls. A URL wider than the popup wraps.
local max_width, max_height = 0.6, 0.4

-- Open a floating pane with bounds [x, y, w, h], as fractions of the window
-- that holds block_id.
local function open_popup(block_id, bounds, command)
  local window_id
  local view = rex.session.view{}
  for _, window in ipairs((view and view.windows) or {}) do
    for _, layer in ipairs(window.layers or {}) do
      for _, block in ipairs(layer.blocks or {}) do
        if block.block_id == block_id then window_id = window.window_id end
      end
    end
  end
  return rex.session.new_layer{
    window_id = window_id,
    bounds = bounds,
    focus = true,
    layout = rex.layout.block{
      flavor = "com.superlogical.terminal.shell",
      options = { command = command },
    },
  }
end

-- Return bounds that center w x h fractions of the window, within the
-- size limits.
local function centered(w, h)
  w = math.min(w, max_width)
  h = math.min(h, max_height)
  return { (1 - w) / 2, (1 - h) / 2, w, h }
end

-- Find the rect of a block in a layout, as [x, y, w, h] fractions of the
-- window.
local function find_rect(node, block_id)
  if node == nil then return nil end
  if node.block_id == block_id then return node.rect end
  if node.split ~= nil then
    return find_rect(node.split.before, block_id) or find_rect(node.split.after, block_id)
  end
  return nil
end

-- Return the size of the window that holds block_id, in cells. Rex measures
-- floating pane bounds as fractions of the window, so work out the window
-- size from the block's size and its rect.
local function window_cells(block_id)
  local size = rex.block.call(terminal, "size", { block_id = block_id })
  local view = rex.session.view{}
  if size ~= nil and view ~= nil then
    for _, window in ipairs(view.windows or {}) do
      for _, layer in ipairs(window.layers or {}) do
        local rect = find_rect(layer.layout, block_id)
        if rect ~= nil then
          -- Use the size the app wants for the block. The block's own size
          -- can differ when another client controls it.
          local want = (size.desired and size.desired[1]) or size
          return want.columns / rect[3], want.rows / rect[4]
        end
      end
    end
  end
  return 160, 45
end

-- Return centered bounds for a popup whose terminal is cols x rows cells.
-- The pane border takes about 2 columns and 2 rows. The exact amount depends
-- on rounding, and the app doesn't report a new pane's size until the action
-- returns. So the plugin can't measure it. extra adds cells to the guess, so
-- that a guess that is a little off still fits the content.
local function popup_bounds(block_id, cols, rows, extra)
  local win_cols, win_rows = window_cells(block_id)
  return centered((cols + 2 + extra) / win_cols, (rows + 2 + extra) / win_rows)
end

-- Return bounds for the picker, sized to its content like
-- junegunn/tmux-fzf-url: the longest line + 6 columns, and one row per URL
-- plus 5 rows for the prompt, the help text, two border lines, and the
-- bottom padding row. The guess is one cell large on purpose. picker.sh
-- draws fzf from the top of the pane, so an extra row is at the bottom.
local function picker_bounds(block_id, urls)
  local width = #"Enter: Open URL / CTRL-Y: Copy to clipboard"
  for _, url in ipairs(urls) do
    if #url > width then width = #url end
  end
  return popup_bounds(block_id, width + 6, #urls + 5, 1)
end

-- Show a one-line message, with one empty row below it like the picker, in a
-- small floating pane sized to the message. The pane closes after one
-- second, or when you press a key.
local function show_message(block_id, message)
  open_popup(block_id, popup_bounds(block_id, #message + 2, 2, 0),
    { "bash", plugin_dir .. "/bin/message.sh", message, block_id })
end

local function fail(message)
  error("fzf-url: " .. tostring(message), 0)
end

-- Define the fzf_url action, and bind opts.key to it when it is set.
function M.setup(opts)
  opts = opts or {}

  rex.action{
    name = "fzf_url",
    title = "Find URLs in Pane",
    description = "Pick a URL from the focused pane's scrollback with fzf, then open or copy it.",
    keywords = "url link fzf browser open copy pane scrollback screen",
    run = function(ctx, args)
      if ctx.block_id == nil then fail("no focused pane") end

      local text, err = read_scrollback(ctx.block_id)
      if text == nil then fail(err) end

      local r, exec_err = rex.exec({ "perl", plugin_dir .. "/bin/extract-urls" }, {
        stdin = text,
        timeout = 10,
        env = {
          FZF_URL_EXTRA_PATTERN = opts.extra_pattern or false,
          FZF_URL_EXTRA_SUB = opts.extra_sub or false,
        },
      })
      if r == nil then fail(exec_err) end
      if not r.ok then fail(r.stderr) end

      -- Newest URLs first.
      local urls = {}
      for url in r.stdout:gmatch("[^\n]+") do table.insert(urls, 1, url) end
      if #urls == 0 then
        show_message(ctx.block_id, "No URLs found.")
        return
      end

      local url_file = os.tmpname()
      local f = assert(io.open(url_file, "w"))
      f:write(table.concat(urls, "\n"), "\n")
      f:close()

      -- Terminal options have no env setting, so env(1) passes the options
      -- to the picker.
      local _, layer_err = open_popup(ctx.block_id, picker_bounds(ctx.block_id, urls), {
        "env",
        "FZF_URL_OPENER=" .. (opts.open or ""),
        "FZF_URL_COPY_CMD=" .. (opts.copy_cmd or ""),
        "FZF_URL_FZF_OPTIONS=" .. (opts.fzf_options or ""),
        "FZF_URL_SOURCE_BLOCK=" .. ctx.block_id,
        "bash", plugin_dir .. "/bin/picker.sh", url_file,
      })
      if layer_err ~= nil then
        os.remove(url_file)
        fail(layer_err)
      end
    end,
  }

  if opts.key ~= nil then
    rex.bind(opts.key, "fzf_url")
  end
end

return M
