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
H.ok("default limits", d[1] == 0.8 and d[2] == 0.4 and d[3] == 512 * 1024,
  table.concat(d, " "))

local l = limits_after{ max_width = 0.6, max_height = 1, max_scrollback = 1000.7 }
H.ok("valid limits are used", l[1] == 0.6 and l[2] == 1 and l[3] == 1000, table.concat(l, " "))

-- Too low, too high, and not a number.
for _, bad in ipairs({ 0, 1.5, "0.5" }) do
  l = limits_after{ max_width = bad, max_height = bad }
  H.ok("max_width and max_height ignore " .. tostring(bad), l[1] == 0.8 and l[2] == 0.4,
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
-- { columns, rows }.
local function run_locate(block_id, windows, sizes)
  return with_rex({
    session = { view = function() return { windows = windows } end },
    block = { call = function(_, method, args)
      assert(method == "size")
      local s = sizes[args.block_id]
      if s == nil then return nil end
      if s.old then return { columns = s[1], rows = s[2] } end
      -- With other, another client comes first and wants another size.
      if s.other then
        return { owner = 2, desired = { { client_id = 1, columns = 99, rows = 99 },
          { client_id = 2, columns = s[1], rows = s[2] } } }
      end
      return { desired = { { columns = s[1], rows = s[2] } } }
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
local w = run_locate("block:1", one, { ["block:1"] = { 150, 40 } })
H.eq("one pane: window", w.window_id, "window:1")
range_is("one pane: columns", w.cols, 151.5, 153.5)
range_is("one pane: rows", w.rows, 40.1, 43.5)

w = run_locate("block:1", one, { ["block:1"] = { 150, 40, old = true } })
range_is("a server with no desired size", w.cols, 151.5, 153.5)

w = run_locate("block:1", one, { ["block:1"] = { 150, 40, other = true } })
range_is("another client: the owner's columns", w.cols, 151.5, 153.5)
range_is("another client: the owner's rows", w.rows, 40.1, 43.5)

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
range_is("two panes: rows", w.rows, 40.1, 43.5)

-- The block is in a floating layer. The tiled layer still gives the size.
local floating = { { window_id = "window:1", layers = {
  { kind = "tiled", layout = leaf("block:1", 0, 0, 1, 1) },
  { kind = "floating", layout = leaf("block:5", 0.2, 0.2, 0.6, 0.6) },
} } }
w = run_locate("block:5", floating, { ["block:1"] = { 150, 40 }, ["block:5"] = { 80, 20 } })
H.eq("floating block: window", w.window_id, "window:1")
range_is("floating block: tiled columns", w.cols, 151.5, 153.5)

-- Only the window that holds the block counts.
local windows = {
  { window_id = "window:1", layers = { { kind = "tiled", layout = leaf("block:1", 0, 0, 1, 1) } } },
  { window_id = "window:2", layers = { { kind = "tiled", layout = leaf("block:2", 0, 0, 1, 1) } } },
}
w = run_locate("block:2", windows, { ["block:1"] = { 150, 40 }, ["block:2"] = { 100, 30 } })
H.eq("second window", w.window_id, "window:2")
range_is("second window: columns", w.cols, 101.5, 103.5)

-- The layout key changes with the layout.
local key = run_locate("block:1", two, two_sizes).key
H.eq("key is stable", run_locate("block:1", two, two_sizes).key, key)
H.ok("key changes with sizes",
  run_locate("block:1", two, { ["block:1"] = { 74, 40 }, ["block:2"] = { 76, 40 } }).key ~= key)

-- A cache entry for the same layout narrows the range.
fake_cache = { ["window:1"] = { key = key, cols = { 155, 156 }, rows = { 42.5, 43.6 } } }
w = run_locate("block:1", two, two_sizes)
range_is("cache narrows columns", w.cols, 155, 156)
range_is("cache narrows rows", w.rows, 42.5, 43.5)

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
local where = { cols = { 149.5, 150.5 }, rows = { 39.5, 40.5 } }

local b = P._popup_bounds(where, 50, 10)
local fw = real_size.fraction(50, 149.5, 150.5, 0.8)
local fh = real_size.fraction(10, 39.5, 40.5, 0.4, true)
H.ok("popup bounds are centered",
  near(b[1], (1 - fw) / 2) and near(b[2], (1 - fh) / 2) and near(b[3], fw) and near(b[4], fh))

b = P._popup_bounds(where, 400, 100)
H.ok("popup stays within the limits", b[3] <= 0.8 and b[4] <= 0.4, b[3] .. " " .. b[4])

-- The longest line gets 3 blank columns on each side. The header is 43
-- characters, so short URLs give 43 + 6 columns.
local function same_bounds(name, b1, b2)
  H.ok(name, near(b1[3], b2[3]) and near(b1[4], b2[4]),
    string.format("%.4f %.4f and %.4f %.4f", b1[3], b1[4], b2[3], b2[4]))
end
same_bounds("picker with short URLs fits the header",
  P._picker_bounds(where, { "https://a.example.com", "https://b.example.com" }), P._popup_bounds(where, 49, 6))
local long = "https://example.com/" .. string.rep("x", 60)
same_bounds("picker fits a 44-character URL",
  P._picker_bounds(where, { string.rep("x", 44) }), P._popup_bounds(where, 50, 5))
same_bounds("picker fits the longest URL",
  P._picker_bounds(where, { "https://a.example.com", long }), P._popup_bounds(where, #long + 6, 6))
H.eq("picker height with no wrap", select(2, P._picker_bounds(where, { "https://a.example.com", long })), 6)

-- fzf puts cols - 4 characters on the first row of a URL, and 2 fewer on
-- each next row. These counts come from fzf 0.75 at 30 and 40 columns.
local pr = "https://github.com/acme/acme-app/pull/new/fix-login-redirect"
local a120 = "https://example.com/" .. string.rep("a", 100)
H.eq("list rows: short URLs", P._list_rows({ "https://a.example.com", "http://localhost:5173/" }, 40), 2)
H.eq("list rows: a URL that fits exactly", P._list_rows({ string.rep("x", 36) }, 40), 1)
H.eq("list rows: a URL one character too long", P._list_rows({ string.rep("x", 37) }, 40), 2)
H.eq("list rows: 60 characters at 30 columns", P._list_rows({ pr }, 30), 3)
H.eq("list rows: 60 characters at 40 columns", P._list_rows({ pr }, 40), 2)
H.eq("list rows: 120 characters at 30 columns", P._list_rows({ a120 }, 30), 5)
H.eq("list rows: 120 characters at 40 columns", P._list_rows({ a120, pr, "http://localhost:5173/" }, 40), 7)

-- When max_width makes the pane narrower than the longest URL, the picker
-- gets a row for each wrapped part, counted at the fewest columns that the
-- pane can get.
local narrow = { cols = { 79.5, 80.5 }, rows = { 39.5, 40.5 } }
local nb, nheight = P._picker_bounds(narrow, { pr, "http://localhost:5173/" })
local nrows = nheight - 4
local least_cols = select(2, real_size.fraction(#pr + 6, 79.5, 80.5, 0.8))
H.eq("narrow picker: list rows", nrows, P._list_rows({ pr, "http://localhost:5173/" }, least_cols))
H.ok("narrow picker: a URL wraps", nrows > 2, tostring(nrows))
same_bounds("narrow picker: height fits the wrapped rows", nb, P._popup_bounds(narrow, #pr + 6, nrows + 4))

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
        if fake.layer_err then return nil, fake.layer_err end
        return fake.layer or { block_ids = { "block:popup" .. #log.layers } }
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

local def, log = action{ key = "cmd+u" }
H.eq("key is bound", log.binds[1], "cmd+u fzf_url")
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
H.eq("message popup has no starting size", log.layers[1].layout.options.size, nil)

-- URLs: the picker gets them newest first, and the options.
def, log = action({ open_cmd = "firefox", copy_cmd = "xclip", fzf_path = "/opt/fzf", fzf_options = "--exact" },
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
H.eq("picker gets fzf_path", env(cmd, "FZF_URL_FZF_PATH"), "/opt/fzf")
H.eq("picker gets fzf_options", env(cmd, "FZF_URL_FZF_OPTIONS"), "--exact")
H.eq("picker gets the source block", env(cmd, "FZF_URL_SOURCE_BLOCK"), "block:1")
H.eq("picker gets the fzf height", env(cmd, "FZF_URL_HEIGHT"), "7")
H.eq("picker gets the help text", env(cmd, "FZF_URL_HEADER"), "Enter: Open URL / CTRL-Y: Copy to clipboard")
H.eq("picker popup has no starting size", log.layers[1].layout.options.size, nil)
H.eq("picker gets no starting rows", env(cmd, "FZF_URL_ROWS"), nil)
H.ok("picker gets the measure spec", (env(cmd, "FZF_URL_MEASURE") or ""):match("^window:1 %x+ [%d.]+ [%d.]+$"),
  env(cmd, "FZF_URL_MEASURE"))

def, log = action({}, { exec = { ok = true, stdout = "https://a.example.com\n" } })
def.run({ block_id = "block:1" }, {})
H.eq("unset options pass empty values", env(command(log), "FZF_URL_OPEN_CMD"), "")
os.remove(command(log)[#command(log)])

-- Options that are not strings fail in setup, not on every run.
H.raises("open_cmd that is not a string", "fzf-url: open_cmd must be a string", action, { open_cmd = {} })
H.raises("copy_cmd that is not a string", "fzf-url: copy_cmd must be a string", action, { copy_cmd = 1 })
H.raises("fzf_path that is not a string", "fzf-url: fzf_path must be a string", action, { fzf_path = true })
H.raises("fzf_options that is not a string", "fzf-url: fzf_options must be a string", action,
  { fzf_options = { "--exact" } })

-- The URL file is removed when the popup fails to open.
def, log = action({}, { exec = { ok = true, stdout = "https://a.example.com\n" }, layer_err = "no window" })
H.raises("popup fails to open", "fzf-url: no window", def.run, { block_id = "block:1" }, {})
cmd = command(log)
H.eq("URL file is removed when the popup fails", io.open(cmd[#cmd]), nil)

------------------------------------------------------------------------
-- The layout values against real fzf
--
-- Run bin/picker.sh with real fzf in a detached tmux session of a set
-- size, and read the screen. This catches an fzf version or a change to the
-- fzf options in picker.sh that draws the picker differently from what the
-- layout table in init.lua says. Skip it when tmux or fzf is missing.

local function sh(cmd)
  local r = os.execute(cmd)
  return r == 0 or r == true
end

-- Quote s for the shell.
local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

-- The number of characters in a UTF-8 string.
local function chars(s) return select(2, s:gsub("[^\128-\191]", "")) end

-- Run picker.sh on urls in a tmux pane of cols x rows. Return the lines of
-- the screen, without blank space at the end of each line.
local function screen(urls, cols, rows, height)
  local file = os.tmpname()
  local f = assert(io.open(file, "w"))
  f:write(table.concat(urls, "\n"), "\n")
  f:close()
  -- A socket path of the test's own, so that it can remove the socket file,
  -- which kill-server leaves behind.
  local socket = os.tmpname()
  os.remove(socket)
  local tmux = "tmux -S " .. q(socket) .. " -f /dev/null "
  -- Clear the fzf options of the user, which change the layout. Clear
  -- REX_BLOCK, so that the picker does not wait for the size of the Rex pane
  -- that runs the tests.
  sh(tmux .. "new-session -d -x " .. cols .. " -y " .. rows .. " " .. q(table.concat({
    "env", "FZF_URL_HEADER=" .. q(P._layout.help), "FZF_URL_HEIGHT=" .. height,
    "FZF_DEFAULT_OPTS=", "FZF_DEFAULT_OPTS_FILE=", "REX_BLOCK=", "/bin/bash", q(dir .. "/../bin/picker.sh"), q(file),
  }, " ")))
  local text = ""
  for _ = 1, 50 do
    local p = io.popen(tmux .. "capture-pane -p 2>/dev/null")
    text = p:read("*a")
    p:close()
    if text:find("%d+/%d+") then break end -- the match count, as in 3/3
    sh("sleep 0.05")
  end
  sh(tmux .. "kill-server 2>/dev/null")
  os.remove(socket)
  os.remove(file)
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = (line:gsub("%s+$", "")) end
  -- When tmux or fzf fails, the capture is empty. Pad the screen with blank
  -- lines, so that the checks fail instead of the test file stopping.
  for i = #lines + 1, rows do lines[i] = "" end
  return lines
end

-- Return the number of rows with text above the first separator line: the
-- URL rows. The list area can have blank rows above them.
local function url_rows(lines)
  local n = 0
  for _, line in ipairs(lines) do
    if line:find("^%s*\226\148\128") then break end -- a line of box-drawing dashes
    if line:find("%S") then n = n + 1 end
  end
  return n
end

if not (sh("command -v tmux >/dev/null 2>&1") and sh("command -v fzf >/dev/null 2>&1")) then
  print("skip: the layout tests need tmux and fzf")
else
  local L = P._layout
  local side = L.side_cols

  -- Short URLs: the help text is the longest line.
  local urls = { "https://a.example.com/one", "https://b.example.com/two", "https://c.example.com" }
  local cols = #L.help + 2 * side
  local height = P._list_rows(urls, cols) + L.extra_rows
  local lines = screen(urls, cols, height, height)
  H.eq("layout: fzf uses the rows of the list plus extra_rows", lines[height]:match("%S") ~= nil, true)
  H.eq("layout: the URLs fill the list rows", url_rows(lines), #urls)
  H.eq("layout: the help text is the last row and is not cut off",
    lines[height], string.rep(" ", side) .. L.help)
  H.eq("layout: the help text has side_cols blank columns on the right",
    cols - chars(lines[height]), side)

  -- A URL longer than the help text: it is the longest line.
  local long = "https://example.com/" .. string.rep("a", 50)
  cols = #long + 2 * side
  height = P._list_rows({ long }, cols) + L.extra_rows
  lines = screen({ long }, cols, height, height)
  H.eq("layout: a URL that is the longest line fits on one row", url_rows(lines), 1)
  H.eq("layout: the longest URL has side_cols blank columns on the right", cols - chars(lines[1]), side)
  H.eq("layout: the longest URL starts after side_cols columns", lines[1]:sub(-#long), long)

  -- URLs at the wrap width and longer: list_rows counts the rows that fzf
  -- uses, which tests url_cols and wrap_cols.
  cols = 40
  for _, n in ipairs({ cols - L.url_cols, cols - L.url_cols + 1, 100 }) do
    local url = "https://example.com/" .. string.rep("b", n - 20)
    local want = P._list_rows({ url }, cols)
    height = want + L.extra_rows
    lines = screen({ url }, cols, height, height)
    H.eq("layout: a " .. n .. "-character URL at " .. cols .. " columns takes " .. want .. " rows",
      url_rows(lines), want)
  end
end

H.done()
