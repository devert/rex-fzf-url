-- Tests for read_scrollback in init.lua. Run with luajit or lua 5.1 or
-- later:
--
--   luajit test/read-scrollback.test.lua
--
-- A fake terminal stands in for Rex. It acts like the real one: a part never
-- ends in the middle of a character, and an offset in the middle of a
-- character gives a replacement character for each byte left of it.

local dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."

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

rex = { block = { call = fake_call } }
local read_scrollback = dofile(dir .. "/../init.lua")._read_scrollback

local pass, fail = 0, 0

local function check(name, input, limit, expected, opts)
  text, calls = input, {}
  old_server = opts and opts.old_server
  local got = read_scrollback("block:1", limit)
  if got == expected then
    pass = pass + 1
  else
    fail = fail + 1
    print(string.format("FAIL %s\n  expected: %q\n  got:      %q", name, expected, tostring(got)))
  end
  if opts and opts.calls and #calls ~= opts.calls then
    fail = fail + 1
    print(string.format("FAIL %s: expected %d calls, got %d", name, opts.calls, #calls))
  end
end

-- Make n lines of the form "line 1 https://example.com/1".
local function lines(n)
  local t = {}
  for i = 1, n do t[i] = "line " .. i .. " https://example.com/" .. i end
  return table.concat(t, "\n")
end

local small = lines(10)
check("short text is read in one call", small, 1000, small, { calls = 1 })

local medium = lines(5000)
check("text under the limit is read whole", medium, #medium, medium)
check("text under the limit, old server", medium, 100, medium, { old_server = true })

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

check("long text keeps the newest lines", medium, 1000, tail(medium, 1000))
check("limit at a line start keeps that line", "aaaa\nbbbb\ncccc", 9, "bbbb\ncccc")
check("limit one byte into a line drops it", "aaaa\nbbbb\ncccc", 8, "cccc")
check("limit at the newline keeps the next line", "aaaa\nbbbb\ncccc", 10, "bbbb\ncccc")
check("limit of the whole text but one byte", "aaaa\nbbbb", 8, "bbbb")

-- é is 2 bytes and 𝄞 is 4 bytes. Put the cut inside them.
local wide = "ééééé\n𝄞𝄞𝄞 https://a.example.com/𝄞\nlast é https://b.example.com"
for limit = 1, #wide - 1 do
  check("multibyte cut at " .. limit, wide, limit, tail(wide, limit))
end

check("a line longer than the limit is kept in part",
  "x https://example.com/" .. string.rep("a", 100), 10, string.rep("a", 10))

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
