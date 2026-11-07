-- Tests for bin/measure.lua. Run with luajit or lua 5.1 or later:
--
--   luajit test/measure.test.lua
--
-- A fake rex global gives the arguments, the size method, and sleep. The
-- script writes a real cache file in a temporary path.

local dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/harness.lua")
local size = dofile(dir .. "/../lib/popup-size.lua")

-- Return a path for a cache file that does not exist yet.
local function new_path()
  local path = os.tmpname()
  os.remove(path)
  return path
end

local function read(path)
  local f = io.open(path)
  if f == nil then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

-- Run measure.lua with args. replies is a list of what the size method
-- returns, one for each call. The last reply repeats. Return the number of
-- size calls and sleeps.
local function measure(args, replies)
  local calls, sleeps = 0, 0
  rex = {
    args = args,
    block = { call = function(_, method, a)
      assert(method == "size" and a.block_id == args.block)
      calls = calls + 1
      return replies[math.min(calls, #replies)]
    end },
    sleep = function() sleeps = sleeps + 1 end,
  }
  dofile(dir .. "/../bin/measure.lua")
  return calls, sleeps
end

-- A size reply where the app (client 2) owns the popup and wants 80x20.
-- Another client comes after it, so taking the last size is wrong.
local other = { client_id = 1, columns = 100, rows = 30 }
local owned = { owner = 2, desired = { { client_id = 2, columns = 80, rows = 20 }, other } }

local function args(path, spec)
  return { block = "block:5", cache = path, spec = spec or "window:1 abc123 0.500000 0.400000" }
end

------------------------------------------------------------------------
-- Bad arguments: no size call, and no cache file.

local path = new_path()
for name, a in pairs({
  ["no block"] = { cache = path, spec = "window:1 k 0.5 0.4" },
  ["no cache path"] = { block = "block:5", spec = "window:1 k 0.5 0.4" },
  ["no spec"] = { block = "block:5", cache = path },
  ["a spec that is not a string"] = { block = "block:5", cache = path, spec = 3 },
  ["a spec with three fields"] = { block = "block:5", cache = path, spec = "window:1 k 0.5" },
  ["a spec with a width that is not a number"] = { block = "block:5", cache = path, spec = "window:1 k x 0.4" },
}) do
  local calls = measure(a, { owned })
  H.ok(name .. ": no size call", calls == 0, calls .. " calls")
  H.eq(name .. ": no cache file", read(path), nil)
end

------------------------------------------------------------------------
-- The size method fails: stop, and write nothing.

local calls = measure(args(path), { nil })
H.eq("size fails: one call", calls, 1)
H.eq("size fails: no cache file", read(path), nil)

------------------------------------------------------------------------
-- The app owns the popup at once: save the ranges for the owner's size.

calls = measure(args(path), { owned })
H.eq("owned at once: one call", calls, 1)
local cache = size.load(path)
local e = cache["window:1"]
local cl, ch = size.floating_range(80, 0.5)
local rl, rh = size.floating_range(20, 0.4)
H.ok("owned at once: saves the owner's size",
  e ~= nil and e.key == "abc123"
    and math.abs(e.cols[1] - cl) < 1e-6 and math.abs(e.cols[2] - ch) < 1e-6
    and math.abs(e.rows[1] - rl) < 1e-6 and math.abs(e.rows[2] - rh) < 1e-6,
  read(path))
os.remove(path)

------------------------------------------------------------------------
-- No owner at first: wait, then save.

local sleeps
calls, sleeps = measure(args(path), { { desired = owned.desired }, { desired = owned.desired }, owned })
H.ok("owner later: waits", calls == 3 and sleeps == 2, calls .. " calls, " .. sleeps .. " sleeps")
H.ok("owner later: saves", size.load(path)["window:1"] ~= nil)
os.remove(path)

-- An owner with no desired size counts as no owner yet.
calls, sleeps = measure(args(path), { { owner = 2, desired = { other } }, owned })
H.ok("owner with no size: waits", calls == 2 and sleeps == 1, calls .. " calls, " .. sleeps .. " sleeps")
os.remove(path)

-- No owner for one second: give up, and write nothing.
calls, sleeps = measure(args(path), { { desired = owned.desired } })
H.ok("never owned: gives up after 100 tries", calls == 100 and sleeps == 100,
  calls .. " calls, " .. sleeps .. " sleeps")
H.eq("never owned: no cache file", read(path), nil)

------------------------------------------------------------------------
-- The cache file already holds entries.

-- An overlapping range for the same layout narrows the entry. The entry of
-- another window stays.
size.save(path, {
  ["window:1"] = { key = "abc123", cols = { cl + 0.5, ch + 5 }, rows = { rl - 5, rh - 0.5 } },
  ["window:2"] = { key = "other", cols = { 1, 2 }, rows = { 3, 4 } },
})
measure(args(path), { owned })
cache = size.load(path)
e = cache["window:1"]
H.ok("merge narrows to the overlap",
  math.abs(e.cols[1] - (cl + 0.5)) < 1e-6 and math.abs(e.cols[2] - ch) < 1e-6
    and math.abs(e.rows[1] - rl) < 1e-6 and math.abs(e.rows[2] - (rh - 0.5)) < 1e-6,
  read(path))
H.ok("merge keeps other windows", cache["window:2"] ~= nil and cache["window:2"].key == "other")

-- A new layout replaces the entry.
measure(args(path, "window:1 def456 0.500000 0.400000"), { owned })
e = size.load(path)["window:1"]
H.ok("a new layout replaces the entry", e.key == "def456" and math.abs(e.cols[1] - cl) < 1e-6, read(path))
os.remove(path)

H.done()
