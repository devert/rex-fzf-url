-- Tests for init.lua. Run with luajit or lua 5.1 or later:
--
--   luajit test/init.test.lua
--
-- A fake rex global stands in for Rex. Each group of tests loads a fresh
-- copy of init.lua.

local dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/harness.lua")

-- Call fn with init.lua, loaded with a fresh rex global made of fields.
local function with_rex(fields, fn)
  rex = fields
  return fn(dofile(dir .. "/../init.lua"))
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

local text, old_server, calls

local function is_cont(byte) return byte ~= nil and byte >= 0x80 and byte < 0xC0 end

-- Return the part of text from byte from (1-based), at most max bytes, that
-- does not end in the middle of a character.
local function part(from, max)
  local last = math.min(#text, from + max - 1)
  while last >= from and is_cont(text:byte(last + 1)) do last = last - 1 end
  return text:sub(from, last)
end

local function fake_call(_, method, args)
  calls[#calls + 1] = method
  if method == "format" then
    local content = part(1, args.max_bytes)
    local r = { content = content }
    if #content < #text then r.id = 7 end
    if not old_server then r.total, r.eof = #text, #content == #text end
    return r
  elseif method == "blob_read" then
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
  old_server = opts.old_server
  H.eq(name, read_scrollback("block:1", limit), expected)
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

H.done()
