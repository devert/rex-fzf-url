-- Tests for init.lua. Run with luajit or lua 5.1 or later:
--
--   luajit test/init.test.lua
--
-- A fake rex global stands in for Rex. Each group of tests loads a fresh
-- copy of init.lua, so options that setup sets don't carry over.

local dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/harness.lua")
local real_size = dofile(dir .. "/../lib/popup-size.lua")

-- The cache that locate reads, by window. init.lua loads lib/popup-size.lua
-- with dofile, so wrap dofile to give it a load that returns this table,
-- and never the real cache file.
local fake_cache = {}
local real_dofile = dofile
dofile = function(path)
  local m = real_dofile(path)
  if path:match("popup%-size%.lua$") then
    local copy = {}
    for k, v in pairs(m) do copy[k] = v end
    copy.load = function() return fake_cache end
    return copy
  end
  return m
end

local function load_init()
  return real_dofile(dir .. "/../init.lua")
end

-- Call fn with a fresh rex global made of the given fields.
local function with_rex(fields, fn)
  rex = fields
  return fn(load_init())
end

------------------------------------------------------------------------
-- extra_args

local M = with_rex({}, function(m) return m end)
local extra_args = M._extra_args

local function check_args(name, list, expected)
  H.eq(name, table.concat(extra_args(list), "|"), table.concat(expected, "|"))
end

check_args("no extra_patterns gives no arguments", nil, {})
check_args("an empty list gives no arguments", {}, {})
check_args("two entries give four arguments in list order", {
  { regex = [[ENG-\d+]], url = "https://linear.app/x/issue/$0" },
  { regex = [[PR #(\d+)]], url = "https://github.com/o/r/pull/$1" },
}, {
  [[ENG-\d+]], "https://linear.app/x/issue/$0",
  [[PR #(\d+)]], "https://github.com/o/r/pull/$1",
})
check_args("an entry with no url gives an empty url", { { regex = "abc-\\d+" } }, { "abc-\\d+", "" })

H.raises("extra_patterns that is not a list",
  "fzf-url: extra_patterns must be a list", extra_args, "ENG-\\d+")
H.raises("an entry with no regex",
  "fzf-url: extra_patterns[2] needs a regex string", extra_args, { { regex = "a", url = "u" }, { url = "u" } })
H.raises("an entry with an empty regex",
  "fzf-url: extra_patterns[1] needs a regex string", extra_args, { { regex = "", url = "u" } })
H.raises("a url that is not a string",
  "fzf-url: extra_patterns[1].url must be a string", extra_args, { { regex = "a", url = 3 } })

------------------------------------------------------------------------
-- read_scrollback
--
-- The fake terminal acts like the real one: a part never ends in the middle
-- of a character, and an offset in the middle of a character gives a
-- replacement character for each byte left of it.

local text, old_server, calls, fail_at, empty_at

local function is_cont(byte) return byte ~= nil and byte >= 0x80 and byte < 0xC0 end

-- Return the part of text from byte from (1-based), at most max bytes, that
-- does not end in the middle of a character.
local function part(from, max)
  local last = math.min(#text, from + max - 1)
  while last >= from and is_cont(text:byte(last + 1)) do last = last - 1 end
  return text:sub(from, last)
end

-- fail_at and empty_at name a call by its number: that call fails, or sends
-- no data.
local function fake_call(_, method, args)
  calls[#calls + 1] = method
  if #calls == fail_at then return nil, method .. " failed" end
  if method == "format" then
    local content = part(1, args.max_bytes)
    local r = { content = content }
    if #content < #text then r.id = 7 end
    if not old_server then r.total, r.eof = #text, #content == #text end
    return r
  elseif method == "blob_read" then
    if #calls == empty_at then return { id = args.id, data = "", eof = false } end
    local from = args.offset + 1
    local lead = ""
    while is_cont(text:byte(from)) do
      lead = lead .. "\239\191\189"
      from = from + 1
    end
    local data = lead .. part(from, args.max_bytes)
    local r = { id = args.id, data = data }
    if not old_server then r.total, r.eof = #text, from + #data - #lead > #text end
    return r
  end
  error("unexpected method " .. method)
end

local read_scrollback = with_rex({ block = { call = fake_call } }, function(m) return m._read_scrollback end)

local function check_read(name, input, limit, expected, opts)
  opts = opts or {}
  text, calls = input, {}
  old_server, fail_at, empty_at = opts.old_server, opts.fail_at, opts.empty_at
  local got, err = read_scrollback("block:1", limit)
  if opts.err then
    H.ok(name, got == nil and err == opts.err, string.format("got %q, %q", tostring(got), tostring(err)))
  else
    H.eq(name, got, expected)
  end
  if opts.calls then H.eq(name .. ": call count", #calls, opts.calls) end
end

-- Make n lines of the form "line 1 https://example.com/1".
local function lines(n)
  local t = {}
  for i = 1, n do t[i] = "line " .. i .. " https://example.com/" .. i end
  return table.concat(t, "\n")
end

local small = lines(10)
check_read("short text is read in one call", small, 1000, small, { calls = 1 })

local medium = lines(5000)
check_read("text under the limit is read whole", medium, #medium, medium)
check_read("text under the limit, old server", medium, 100, medium, { old_server = true })

-- Keep only the lines that fit completely in the last limit bytes.
local function tail(s, limit)
  local cut = #s - limit
  if cut <= 0 then return s end
  if s:sub(cut, cut) == "\n" then return s:sub(cut + 1) end
  local newline = s:find("\n", cut + 1, true)
  if newline ~= nil then return s:sub(newline + 1) end
  -- No line starts in the kept text: keep its end from a whole character.
  return (s:sub(cut + 1):gsub("^[\128-\191]+", ""))
end

check_read("long text keeps the newest lines", medium, 1000, tail(medium, 1000))
check_read("limit at a line start keeps that line", "aaaa\nbbbb\ncccc", 9, "bbbb\ncccc")
check_read("limit one byte into a line drops it", "aaaa\nbbbb\ncccc", 8, "cccc")
check_read("limit at the newline keeps the next line", "aaaa\nbbbb\ncccc", 10, "bbbb\ncccc")
check_read("limit of the whole text but one byte", "aaaa\nbbbb", 8, "bbbb")

-- é is 2 bytes and 𝄞 is 4 bytes. Put the cut inside them.
local wide = "ééééé\n𝄞𝄞𝄞 https://a.example.com/𝄞\nlast é https://b.example.com"
for limit = 1, #wide - 1 do
  check_read("multibyte cut at " .. limit, wide, limit, tail(wide, limit))
end

check_read("a line longer than the limit is kept in part",
  "x https://example.com/" .. string.rep("a", 100), 10, string.rep("a", 10))

-- Failures. A big text needs more than one blob_read after format.
local big = lines(100000)
check_read("format fails", small, 1000, nil, { fail_at = 1, err = "format failed" })
check_read("blob_read fails at the start of the kept text", big, 2000000, nil,
  { fail_at = 2, err = "blob_read failed" })
check_read("blob_read fails in a later part", big, 2000000, nil,
  { fail_at = 3, err = "blob_read failed" })
check_read("a part with no data ends the read", medium, #medium, medium:sub(1, 64 * 1024),
  { empty_at = 2, calls = 2 })

------------------------------------------------------------------------
-- setup options

local function limits_after(opts)
  return with_rex({ action = function() end, bind = function() end }, function(m)
    m.setup(opts)
    return { m._limits() }
  end)
end

local d = limits_after(nil)
H.ok("default limits", d[1] == 0.6 and d[2] == 0.4 and d[3] == 512 * 1024,
  table.concat(d, " "))

local l = limits_after{ max_width = 0.8, max_height = 1, max_scrollback = 1000.7 }
H.ok("valid limits are used", l[1] == 0.8 and l[2] == 1 and l[3] == 1000, table.concat(l, " "))

-- Too low, too high, and not a number.
for _, bad in ipairs({ 0, 1.5, "0.5" }) do
  l = limits_after{ max_width = bad, max_height = bad }
  H.ok("max_width and max_height ignore " .. tostring(bad), l[1] == 0.6 and l[2] == 0.4,
    table.concat(l, " "))
end

-- Below 1, and not a number.
for _, bad in ipairs({ 0.5, "1000" }) do
  l = limits_after{ max_scrollback = bad }
  H.eq("max_scrollback ignores " .. tostring(bad), l[3], 512 * 1024)
end

------------------------------------------------------------------------
-- locate

-- Make a leaf of a layout.
local function leaf(id, x, y, w, h) return { block_id = id, rect = { x, y, w, h } } end
local function split(a, b) return { split = { before = a, after = b } } end

-- Run locate for block_id with the given windows, and sizes by block:
-- { columns, rows } and an optional cell size.
local function run_locate(block_id, windows, sizes)
  return with_rex({
    session = { view = function() return { windows = windows } end },
    block = { call = function(_, method, args)
      assert(method == "size")
      local s = sizes[args.block_id]
      if s == nil then return nil end
      if s.old then return { columns = s[1], rows = s[2] } end
      return { desired = { { columns = s[1], rows = s[2] } }, cell_width_px = s.cw, cell_height_px = s.ch }
    end },
  }, function(m) return m._locate(block_id) end)
end

local function near(a, b) return math.abs(a - b) < 1e-9 end
local function range_is(name, got, low, high)
  H.ok(name, near(got[1], low) and near(got[2], high),
    string.format("expected %.4f %.4f, got %.4f %.4f", low, high, got[1], got[2]))
end

fake_cache = {}

local one = { { window_id = "window:1", layers = { { kind = "tiled", layout = leaf("block:1", 0, 0, 1, 1) } } } }
local w = run_locate("block:1", one, { ["block:1"] = { 150, 40, cw = 8, ch = 16 } })
H.eq("one pane: window", w.window_id, "window:1")
range_is("one pane: columns", w.cols, 152.2, 153.4)
range_is("one pane: rows", w.rows, 42.2, 43.4)
H.eq("one pane: cell size", w.cell and w.cell.cell_width_px, 8)

w = run_locate("block:1", one, { ["block:1"] = { 150, 40, old = true } })
range_is("a server with no desired size", w.cols, 152.2, 153.4)

w = run_locate("block:9", one, { ["block:1"] = { 150, 40 } })
H.eq("unknown block: no window", w.window_id, nil)
range_is("unknown block: default columns", w.cols, 160, 161)
range_is("unknown block: default rows", w.rows, 45, 46)

w = run_locate("block:1", one, {})
H.eq("no sizes: window", w.window_id, "window:1")
range_is("no sizes: default columns", w.cols, 160, 161)

-- Two panes side by side. 75 columns at 0.5 allows 153-158, and 76 columns
-- allows 155-160. Both hold, so the window is 155-158.
local two = { { window_id = "window:1", layers = { {
  kind = "tiled", layout = split(leaf("block:1", 0, 0, 0.5, 1), leaf("block:2", 0.5, 0, 0.5, 1)),
} } } }
local two_sizes = { ["block:1"] = { 75, 40 }, ["block:2"] = { 76, 40 } }
w = run_locate("block:1", two, two_sizes)
range_is("two panes: columns overlap", w.cols, 155, 158)
range_is("two panes: rows", w.rows, 42.2, 43.4)

-- The block is in a floating layer. The tiled layer still gives the size.
local floating = { { window_id = "window:1", layers = {
  { kind = "tiled", layout = leaf("block:1", 0, 0, 1, 1) },
  { kind = "floating", layout = leaf("block:5", 0.2, 0.2, 0.6, 0.6) },
} } }
w = run_locate("block:5", floating, { ["block:1"] = { 150, 40 }, ["block:5"] = { 80, 20 } })
H.eq("floating block: window", w.window_id, "window:1")
range_is("floating block: tiled columns", w.cols, 152.2, 153.4)
H.eq("floating block: no cell size from tiled panes", w.cell, nil)

-- Only the window that holds the block counts.
local windows = {
  { window_id = "window:1", layers = { { kind = "tiled", layout = leaf("block:1", 0, 0, 1, 1) } } },
  { window_id = "window:2", layers = { { kind = "tiled", layout = leaf("block:2", 0, 0, 1, 1) } } },
}
w = run_locate("block:2", windows, { ["block:1"] = { 150, 40 }, ["block:2"] = { 100, 30 } })
H.eq("second window", w.window_id, "window:2")
range_is("second window: columns", w.cols, 102.2, 103.4)

-- The layout key changes with the layout.
local key = run_locate("block:1", two, two_sizes).key
H.eq("key is stable", run_locate("block:1", two, two_sizes).key, key)
H.ok("key changes with sizes",
  run_locate("block:1", two, { ["block:1"] = { 74, 40 }, ["block:2"] = { 76, 40 } }).key ~= key)

-- A cache entry for the same layout narrows the range.
fake_cache = { ["window:1"] = { key = key, cols = { 155, 156 }, rows = { 42.5, 43.6 } } }
w = run_locate("block:1", two, two_sizes)
range_is("cache narrows columns", w.cols, 155, 156)
range_is("cache narrows rows", w.rows, 42.5, 43.4)

-- A cache entry that doesn't overlap is newer than the layout, so use it.
fake_cache = { ["window:1"] = { key = key, cols = { 200, 201 }, rows = { 50, 51 } } }
w = run_locate("block:1", two, two_sizes)
range_is("cache with no overlap is used", w.cols, 200, 201)

-- A cache entry for another layout is ignored.
fake_cache = { ["window:1"] = { key = "other", cols = { 155, 156 }, rows = { 40, 40.1 } } }
w = run_locate("block:1", two, two_sizes)
range_is("cache for another layout is ignored", w.cols, 155, 158)
fake_cache = {}

------------------------------------------------------------------------
-- popup_bounds and picker_bounds

local P = with_rex({}, function(m) return m end)
local where = { cols = { 149.5, 150.5 }, rows = { 39.5, 40.5 }, cell = { cell_width_px = 8, cell_height_px = 16 } }

local b, s = P._popup_bounds(where, 50, 10)
local fw, start_cols = real_size.fraction(50, 149.5, 150.5, 0.6)
local fh, start_rows = real_size.fraction(10, 39.5, 40.5, 0.4)
H.ok("popup bounds are centered",
  near(b[1], (1 - fw) / 2) and near(b[2], (1 - fh) / 2) and near(b[3], fw) and near(b[4], fh))
H.ok("popup starting size", s.columns == start_cols and s.rows == start_rows,
  s.columns .. "x" .. s.rows)
H.ok("popup keeps the cell size", s.cell_width_px == 8 and s.cell_height_px == 16)

b = P._popup_bounds(where, 400, 100)
H.ok("popup stays within the limits", b[3] <= 0.6 and b[4] <= 0.4, b[3] .. " " .. b[4])

for _, cell in ipairs({ { cell_width_px = 0, cell_height_px = 16 }, { cell_width_px = 8 } }) do
  s = select(2, P._popup_bounds({ cols = where.cols, rows = where.rows, cell = cell }, 50, 10))
  H.ok("popup skips a cell size that is not complete", s.cell_width_px == nil and s.cell_height_px == nil)
end

-- The header is 43 characters, so short URLs give 43 + 6 columns.
local function same_bounds(name, b1, b2)
  H.ok(name, near(b1[3], b2[3]) and near(b1[4], b2[4]),
    string.format("%.4f %.4f and %.4f %.4f", b1[3], b1[4], b2[3], b2[4]))
end
same_bounds("picker with short URLs fits the header",
  P._picker_bounds(where, { "https://a.example.com", "https://b.example.com" }), P._popup_bounds(where, 49, 6))
local long = "https://example.com/" .. string.rep("x", 60)
same_bounds("picker fits the longest URL",
  P._picker_bounds(where, { "https://a.example.com", long }), P._popup_bounds(where, #long + 6, 6))

------------------------------------------------------------------------
-- The fzf_url action

-- Set up the plugin with opts and a fake Rex. Return the action, and a log
-- of the calls to Rex. fake sets what the fakes return.
local function action(opts, fake)
  fake = fake or {}
  local log = { layers = {}, binds = {} }
  local def
  with_rex({
    action = function(d) def = d end,
    bind = function(k, name) log.binds[#log.binds + 1] = k .. " " .. name end,
    layout = { block = function(spec) return spec end },
    session = {
      view = function() return { windows = one } end,
      new_layer = function(spec)
        log.layers[#log.layers + 1] = spec
        return fake.layer, fake.layer_err
      end,
    },
    block = { call = function(_, method)
      if method == "format" then
        if fake.format_err then return nil, fake.format_err end
        return { content = "scrollback" }
      end
      return { desired = { { columns = 150, rows = 40 } } }
    end },
    exec = function(cmd, o)
      log.exec, log.exec_opts = cmd, o
      if fake.exec_err then return nil, fake.exec_err end
      return fake.exec or { ok = true, stdout = "" }
    end,
  }, function(m) m.setup(opts) end)
  return def, log
end

local function command(log, i) return log.layers[i or 1].layout.options.command end

-- Return the value of the env argument NAME=value in a picker command.
local function env(cmd, name)
  for _, a in ipairs(cmd) do
    local v = a:match("^" .. name .. "=(.*)$")
    if v ~= nil then return v end
  end
end

local def, log = action{ key = "ctrl+space>u" }
H.eq("key is bound", log.binds[1], "ctrl+space>u fzf_url")
_, log = action{}
H.eq("no key, no binding", #log.binds, 0)

def = action{}
H.raises("no focused pane", "fzf-url: no focused pane", def.run, {}, {})
def = action({}, { format_err = "no such block" })
H.raises("scrollback read fails", "fzf-url: no such block", def.run, { block_id = "block:1" }, {})
def = action({}, { exec_err = "timed out" })
H.raises("extract fails to run", "fzf-url: timed out", def.run, { block_id = "block:1" }, {})
def = action({}, { exec = { ok = false, stderr = "bad regex" } })
H.raises("extract exits with an error", "fzf-url: bad regex", def.run, { block_id = "block:1" }, {})

def, log = action{ extra_patterns = { { regex = "ENG-\\d+", url = "u/$0" } } }
def.run({ block_id = "block:1" }, {})
H.ok("extract command has the extra patterns", log.exec[1] == "perl"
  and log.exec[2]:match("/bin/extract%-urls%.pl$") and log.exec[3] == "ENG-\\d+" and log.exec[4] == "u/$0"
  and #log.exec == 4)
H.ok("extract gets the scrollback", log.exec_opts.stdin == "scrollback" and log.exec_opts.timeout == 10)

-- No URLs: a message popup in the window of the block.
H.eq("no URLs opens one popup", #log.layers, 1)
local msg = command(log)
H.ok("no URLs shows the message",
  msg[1] == "bash" and msg[2]:match("/bin/message%.sh$") and msg[3] == "No URLs found." and msg[4] == "block:1")
H.ok("message popup is in the window and has focus",
  log.layers[1].window_id == "window:1" and log.layers[1].focus == true)

-- URLs: the picker gets them newest first, and the options.
def, log = action({ open_cmd = "firefox", copy_cmd = "xclip", fzf_options = "--exact" },
  { exec = { ok = true, stdout = "https://a.example.com\nhttps://b.example.com\nhttps://c.example.com\n" } })
def.run({ block_id = "block:1" }, {})
local cmd = command(log)
local url_file = cmd[#cmd]
local f = io.open(url_file)
local listed = f and f:read("*a")
if f then f:close() end
os.remove(url_file)
H.eq("picker gets URLs newest first", listed, "https://c.example.com\nhttps://b.example.com\nhttps://a.example.com\n")
H.ok("picker runs picker.sh", cmd[1] == "env" and cmd[#cmd - 1]:match("/bin/picker%.sh$") and cmd[#cmd - 2] == "bash")
H.eq("picker gets open_cmd", env(cmd, "FZF_URL_OPEN_CMD"), "firefox")
H.eq("picker gets copy_cmd", env(cmd, "FZF_URL_COPY_CMD"), "xclip")
H.eq("picker gets fzf_options", env(cmd, "FZF_URL_FZF_OPTIONS"), "--exact")
H.eq("picker gets the source block", env(cmd, "FZF_URL_SOURCE_BLOCK"), "block:1")
H.eq("picker gets the count", env(cmd, "FZF_URL_COUNT"), "3")
H.eq("picker gets the starting rows", env(cmd, "FZF_URL_ROWS"), tostring(log.layers[1].layout.options.size.rows))
H.ok("picker gets the measure spec", (env(cmd, "FZF_URL_MEASURE") or ""):match("^window:1 %x+ [%d.]+ [%d.]+$"),
  env(cmd, "FZF_URL_MEASURE"))

def, log = action({}, { exec = { ok = true, stdout = "https://a.example.com\n" } })
def.run({ block_id = "block:1" }, {})
H.eq("unset options pass empty values", env(command(log), "FZF_URL_OPEN_CMD"), "")
os.remove(command(log)[#command(log)])

-- The URL file is removed when the popup fails to open.
def, log = action({}, { exec = { ok = true, stdout = "https://a.example.com\n" }, layer_err = "no window" })
H.raises("popup fails to open", "fzf-url: no window", def.run, { block_id = "block:1" }, {})
cmd = command(log)
H.eq("URL file is removed when the popup fails", io.open(cmd[#cmd]), nil)

H.done()
