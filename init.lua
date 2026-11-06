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

local popup_size = dofile(plugin_dir .. "/lib/popup-size.lua")

-- The file where bin/measure.lua keeps the window sizes that popups measured.
local cache_path = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")
  .. "/rex-fzf-url-" .. (os.getenv("USER") or "user") .. ".sizes"

-- The most bytes of scrollback to read. setup can change it.
local max_scrollback = 512 * 1024

-- Read the screen and scrollback as plain text: all of it, or only the
-- newest lines when it is longer than limit bytes. Then only the lines that
-- fit completely in the last limit bytes are kept, so that no line starts
-- partway through. Large output arrives in parts, so read the rest with
-- blob_read until it is complete.
local function read_scrollback(block_id, limit)
  -- The terminal makes the whole text, then sends a part of it. format has
  -- no option to send only the end. So ask for a small first part, which
  -- also gives the total size, and then read from where the kept text
  -- starts. 960 KiB is the largest part that blob_read sends.
  local first, chunk = math.min(64 * 1024, limit), 960 * 1024
  local r, err = rex.block.call(terminal, "format", {
    block_id = block_id, format = "text", trim = true, unwrap = true, max_bytes = first,
  })
  if r == nil then return nil, err end
  local parts = { r.content or "" }
  local offset = #parts[1]
  local tail = false
  -- Older servers don't send total, so they always give all of the text.
  if r.id ~= nil and not r.eof and r.total ~= nil and r.total > limit then
    -- Start one byte before the kept text. If that byte ends a line, the
    -- first kept line is complete, and it is not dropped below.
    parts, tail = {}, true
    offset = r.total - limit - 1
    -- An offset in the middle of a character gives a replacement character
    -- (U+FFFD) for each byte that is left of it. A character has at most 4
    -- bytes, so move ahead until the offset is at the start of a character.
    for _ = 1, 4 do
      local next_r
      next_r, err = rex.block.call(terminal, "blob_read", {
        block_id = block_id, id = r.id, offset = offset, max_bytes = chunk,
      })
      if next_r == nil then return nil, err end
      r = next_r
      if (r.data or ""):sub(1, 3) ~= "\239\191\189" then break end
      offset = offset + 1
    end
    parts[1] = r.data or ""
    offset = offset + #parts[1]
  end
  while r.id ~= nil and not r.eof do
    r, err = rex.block.call(terminal, "blob_read", {
      block_id = block_id, id = r.id, offset = offset, max_bytes = chunk,
    })
    if r == nil then return nil, err end
    if r.data == nil or r.data == "" then break end
    parts[#parts + 1] = r.data
    offset = offset + #r.data
  end
  local text = table.concat(parts)
  if tail then
    -- Drop the line that started before the kept text. Keep the end of a
    -- line longer than limit, from the start of a character.
    local newline = text:find("\n", 1, true)
    if newline ~= nil then
      text = text:sub(newline + 1)
    else
      if #text > limit then text = text:sub(-limit) end
      text = (text:gsub("^[\128-\191]+", ""))
    end
  end
  return text
end

-- The largest popup, as fractions of the window. With more URLs than fit,
-- the list scrolls. A URL wider than the popup wraps. setup can change both.
local max_width, max_height = 0.6, 0.4

-- Return value if it is a number above 0 and at most 1, else default.
local function fraction(value, default)
  if type(value) == "number" and value > 0 and value <= 1 then return value end
  return default
end

-- Return the layout leaves under node, as { block_id, rect } tables.
local function leaves(node, out)
  out = out or {}
  if node == nil then return out end
  if node.block_id ~= nil then out[#out + 1] = node end
  if node.split ~= nil then
    leaves(node.split.before, out)
    leaves(node.split.after, out)
  end
  return out
end

-- Return the size of a terminal block: the size the app wants for it, as
-- the block's own size can differ when another client controls it. Also
-- return the whole reply of the size method.
local function block_size(block_id)
  local s = rex.block.call(terminal, "size", { block_id = block_id })
  if s == nil then return nil end
  return (s.desired and s.desired[1]) or s, s
end

-- Return what the popups need to know about block_id: the window that holds
-- it, the range of possible window sizes in cells, a key for the layout of
-- the window, and the cell size in pixels. Rex measures floating pane bounds
-- as fractions of the window, so work out the window size from the size and
-- the rect of each tiled pane in it. An earlier popup can have measured it
-- better (see bin/measure.lua). Take that when the layout is the same.
local function locate(block_id)
  local where = {
    block_id = block_id,
    cols = { 0, math.huge }, rows = { 0, math.huge },
  }
  local view = rex.session.view{}
  local found = {}
  for _, window in ipairs((view and view.windows) or {}) do
    for _, layer in ipairs(window.layers or {}) do
      for _, leaf in ipairs(leaves(layer.layout)) do
        if leaf.block_id == block_id then where.window_id = window.window_id end
      end
    end
    if where.window_id == window.window_id then
      for _, layer in ipairs(window.layers or {}) do
        if layer.kind == "tiled" then found = leaves(layer.layout) end
      end
      break
    end
  end

  local key = {}
  for _, leaf in ipairs(found) do
    local want, s = block_size(leaf.block_id)
    local rect = leaf.rect
    if want ~= nil and type(rect) == "table" and rect[3] > 0 and rect[4] > 0 then
      if leaf.block_id == block_id then where.cell = s end
      key[#key + 1] = string.format("%s %.4f %.4f %d %d", leaf.block_id, rect[3], rect[4], want.columns, want.rows)
      local cl, ch = popup_size.tiled_range(want.columns, rect[3], 4)
      local rl, rh = popup_size.tiled_range(want.rows, rect[4], 3)
      cl, ch = popup_size.intersect(where.cols[1], where.cols[2], cl, ch)
      rl, rh = popup_size.intersect(where.rows[1], where.rows[2], rl, rh)
      if cl ~= nil then where.cols = { cl, ch } end
      if rl ~= nil then where.rows = { rl, rh } end
    end
  end
  where.key = popup_size.hash(table.concat(key, "\n"))

  local cached = where.window_id and popup_size.load(cache_path)[where.window_id]
  if cached ~= nil and cached.key == where.key then
    local cl, ch = popup_size.intersect(where.cols[1], where.cols[2], cached.cols[1], cached.cols[2])
    local rl, rh = popup_size.intersect(where.rows[1], where.rows[2], cached.rows[1], cached.rows[2])
    where.cols = cl and { cl, ch } or cached.cols
    where.rows = rl and { rl, rh } or cached.rows
  end
  if where.cols[2] == math.huge then where.cols = { 160, 161 } end
  if where.rows[2] == math.huge then where.rows = { 45, 46 } end
  return where
end

-- Open a floating pane with bounds [x, y, w, h], as fractions of the window
-- that holds the block. size is the terminal's starting size.
local function open_popup(where, bounds, size, command)
  return rex.session.new_layer{
    window_id = where.window_id,
    bounds = bounds,
    focus = true,
    layout = rex.layout.block{
      flavor = "com.superlogical.terminal.shell",
      options = { command = command, size = size },
    },
  }
end

-- Return centered bounds for a popup whose terminal is cols x rows cells,
-- within the size limits, and a starting size for its terminal.
-- The app sets the size of a new pane a moment after it opens. The bounds
-- give at least cols x rows cells for every window size that the plugin
-- thinks is possible, so the pane never has to change size later.
-- Without a starting size, the terminal starts at 80x24 and the app resizes
-- it a moment later. Lines that fzf draws before the resize then stay on the
-- screen. The starting size is the smallest that the pane can get, because
-- the terminal reflows its lines when it gets narrower, but not when it gets
-- wider.
local function popup_bounds(where, cols, rows)
  local w, start_cols = popup_size.fraction(cols, where.cols[1], where.cols[2], max_width)
  local h, start_rows = popup_size.fraction(rows, where.rows[1], where.rows[2], max_height)
  local bounds = { (1 - w) / 2, (1 - h) / 2, w, h }
  local size = { columns = start_cols, rows = start_rows }
  -- Keep the cell size of the source pane, for programs that draw images.
  local px = where.cell
  if px ~= nil and (px.cell_width_px or 0) > 0 and (px.cell_height_px or 0) > 0 then
    size.cell_width_px, size.cell_height_px = px.cell_width_px, px.cell_height_px
  end
  return bounds, size
end

-- Return bounds for the picker, sized to its content like
-- junegunn/tmux-fzf-url: the longest line + 6 columns, and one row per URL
-- plus 5 rows for the prompt, the help text, two border lines, and the
-- bottom padding row.
local function picker_bounds(where, urls)
  local width = #"Enter: Open URL / CTRL-Y: Copy to clipboard"
  for _, url in ipairs(urls) do
    if #url > width then width = #url end
  end
  return popup_bounds(where, width + 6, #urls + 5)
end

-- Show a one-line message, with one empty row below it like the picker, in a
-- small floating pane sized to the message. The pane closes after one
-- second, or when you press a key.
local function show_message(where, message)
  local bounds, size = popup_bounds(where, #message + 2, 2)
  open_popup(where, bounds, size,
    { "bash", plugin_dir .. "/bin/message.sh", message, where.block_id })
end

local function fail(message)
  error("fzf-url: " .. tostring(message), 0)
end

-- Turn opts.extra_patterns into REGEX URL argument pairs for
-- bin/extract-urls.
local function extra_args(list)
  local args = {}
  if list == nil then return args end
  if type(list) ~= "table" then fail("extra_patterns must be a list") end
  for i, entry in ipairs(list) do
    if type(entry) ~= "table" or type(entry.regex) ~= "string" or entry.regex == "" then
      fail("extra_patterns[" .. i .. "] needs a regex string")
    end
    if entry.url ~= nil and type(entry.url) ~= "string" then
      fail("extra_patterns[" .. i .. "].url must be a string")
    end
    table.insert(args, entry.regex)
    table.insert(args, entry.url or "")
  end
  return args
end

-- Define the fzf_url action, and bind opts.key to it when it is set.
function M.setup(opts)
  opts = opts or {}
  local extract_cmd = { "perl", plugin_dir .. "/bin/extract-urls" }
  for _, arg in ipairs(extra_args(opts.extra_patterns)) do
    table.insert(extract_cmd, arg)
  end
  max_width = fraction(opts.max_width, max_width)
  max_height = fraction(opts.max_height, max_height)
  if type(opts.max_scrollback) == "number" and opts.max_scrollback >= 1 then
    max_scrollback = math.floor(opts.max_scrollback)
  end

  rex.action{
    name = "fzf_url",
    title = "Find URLs in Pane",
    description = "Pick a URL from the focused pane's scrollback with fzf, then open or copy it.",
    keywords = "url link fzf browser open copy pane scrollback screen",
    run = function(ctx, args)
      if ctx.block_id == nil then fail("no focused pane") end

      local text, err = read_scrollback(ctx.block_id, max_scrollback)
      if text == nil then fail(err) end

      local r, exec_err = rex.exec(extract_cmd, { stdin = text, timeout = 10 })
      if r == nil then fail(exec_err) end
      if not r.ok then fail(r.stderr) end

      -- Newest URLs first.
      local urls = {}
      for url in r.stdout:gmatch("[^\n]+") do table.insert(urls, 1, url) end
      local where = locate(ctx.block_id)
      if #urls == 0 then
        show_message(where, "No URLs found.")
        return
      end

      local url_file = os.tmpname()
      local f = assert(io.open(url_file, "w"))
      f:write(table.concat(urls, "\n"), "\n")
      f:close()

      -- Terminal options have no env setting, so env(1) passes the options
      -- to the picker.
      local bounds, size = picker_bounds(where, urls)
      local _, layer_err = open_popup(where, bounds, size, {
        "env",
        "FZF_URL_OPEN_CMD=" .. (opts.open_cmd or ""),
        "FZF_URL_COPY_CMD=" .. (opts.copy_cmd or ""),
        "FZF_URL_FZF_OPTIONS=" .. (opts.fzf_options or ""),
        "FZF_URL_SOURCE_BLOCK=" .. ctx.block_id,
        "FZF_URL_ROWS=" .. size.rows,
        "FZF_URL_COUNT=" .. #urls,
        "FZF_URL_CACHE=" .. cache_path,
        "FZF_URL_MEASURE=" .. string.format("%s %s %.6f %.6f",
          where.window_id or "none", where.key, bounds[3], bounds[4]),
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

-- For the tests.
M._read_scrollback = read_scrollback
M._extra_args = extra_args

return M
