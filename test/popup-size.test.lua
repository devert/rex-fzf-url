-- Tests for lib/popup-size.lua. Run with luajit or lua 5.1 or later:
--
--   luajit test/popup-size.test.lua

local dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/harness.lua")
local size = dofile(dir .. "/../lib/popup-size.lua")
local check = H.ok

-- The cells that the app gives a floating pane that is a fraction f of a
-- window of w cells. round() rounds halves up.
local function app_cells(f, w) return math.floor(f * w + 0.5) - 2 end

-- Tiled panes measured in Rex for macOS, in a window of 50 rows: a fraction
-- of the window and the rows of the pane. Each range must hold 50.
for _, m in ipairs({ { 1, 50 }, { 0.7, 34 }, { 0.57, 27 }, { 0.43, 20 }, { 0.29, 13 },
  { 0.82, 40 }, { 0.18, 7 }, { 0.5, 23 }, { 1 / 3, 15 } }) do
  local low, high = size.tiled_range(m[2], m[1], 3)
  check(string.format("tiled range for %d rows at %.2f holds 50", m[2], m[1]),
    low <= 50 and 50 < high, string.format("range %.2f %.2f", low, high))
end

-- Tiled panes measured in a window of about 153.9 columns, the nested ones
-- included.
for _, m in ipairs({ { 0.5, 75 }, { 0.25, 36 }, { 0.395, 57 }, { 0.105, 14 },
  { 0.185, 26 }, { 0.315, 46 }, { 0.33, 48 }, { 0.17, 23 } }) do
  local low, high = size.tiled_range(m[2], m[1], 4)
  check(string.format("tiled range for %d columns at %.3f holds 153.9", m[2], m[1]),
    low <= 153.9 and 153.9 < high, string.format("range %.2f %.2f", low, high))
end

-- A floating pane's range holds every window size that gives its cells.
for _, w in ipairs({ 40, 50.3, 61.9, 154 }) do
  for _, f in ipairs({ 0.1, 0.25, 0.4 }) do
    local low, high = size.floating_range(app_cells(f, w), f)
    check(string.format("floating range at %.2f holds %.1f", f, w), low <= w and w < high)
  end
end

check("intersect overlaps", select(1, size.intersect(1, 5, 3, 8)) == 3)
check("intersect apart gives nil", size.intersect(1, 2, 3, 4) == nil)

-- For every window size in the range, the pane gets at least n cells, and
-- no more extra cells than the width of the range allows. The starting size
-- is n, and never more than the pane gets.
for _, r in ipairs({ { 49.5, 50.5 }, { 48, 54 }, { 47.77, 52.08 }, { 150, 158 }, { 153.75, 154.5 } }) do
  for _, n in ipairs({ 2, 7, 9, 20, 30 }) do
    local f, start = size.fraction(n, r[1], r[2], 1)
    local most = n + 1 + math.ceil((n + 2) * (r[2] / r[1] - 1))
    local worst = 0
    for i = 0, 100 do
      local w = r[1] + (r[2] - r[1]) * i / 101
      local got = app_cells(f, w)
      if got < n or got > most or start ~= n or start > got then worst = got end
    end
    check(string.format("fraction for %d cells in %.2f-%.2f", n, r[1], r[2]), worst == 0,
      "bad cell count " .. worst)
  end
end

-- A narrow range gives exactly n cells.
local f = size.fraction(7, 49.5, 50.5, 1)
check("narrow range is exact", app_cells(f, 49.5) == 7 and app_cells(f, 50.49) == 7)

-- Over the limit, the pane gets the most cells that fit, and the same count
-- for every window size in the range.
f = size.fraction(40, 49.5, 50.5, 0.4)
check("limit holds", f <= 0.4)
check("limit gives one count", app_cells(f, 49.5) == app_cells(f, 50.49),
  app_cells(f, 49.5) .. " and " .. app_cells(f, 50.49))

check("hash is stable", size.hash("abc") == size.hash("abc") and size.hash("abc") ~= size.hash("abd"))

-- The cache keeps the overlap of ranges for the same layout, and starts over
-- when the layout changes or the ranges don't overlap.
local cache = {}
size.merge(cache, "window:1", "k1", 150, 158, 48, 54)
size.merge(cache, "window:1", "k1", 152, 160, 47, 51)
check("merge keeps overlap", cache["window:1"].cols[1] == 152 and cache["window:1"].rows[2] == 51)
size.merge(cache, "window:1", "k2", 100, 101, 30, 31)
check("merge replaces a new layout", cache["window:1"].key == "k2" and cache["window:1"].cols[1] == 100)
size.merge(cache, "window:1", "k2", 120, 121, 30, 31)
check("merge replaces ranges that don't overlap", cache["window:1"].cols[1] == 120)
size.merge(cache, "window:2", "k3", 1, 2, 3, 4)

local back = size.parse(size.format(cache))
check("format and parse round trip",
  back["window:1"].key == "k2" and back["window:2"].rows[2] == 4 and back["window:1"].cols[2] == 121)
check("parse skips bad lines", next(size.parse("junk\nwindow:1 k 1 2 x 4\n")) == nil)

H.done()
