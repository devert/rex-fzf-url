-- Tests for lib/popup-size.lua. Run with luajit or lua 5.1 or later:
--
--   luajit test/popup-size.test.lua

local dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local H = dofile(dir .. "/harness.lua")
local size = dofile(dir .. "/../lib/popup-size.lua")
local check = H.ok

-- The cells that the app gives a floating pane that is a fraction f of a
-- window of w cells, with an inset of k cells.
local function app_cells(f, w, k) return math.floor(f * w - (k or 2.1)) end

-- The insets measured in Rex for macOS. The model must hold for each.
local insets = { 2.03, 2.105, 2.147, 2.162 }

-- Tiled panes measured in Rex for macOS: the window size W in floating
-- pane cells, a fraction of the window, and the cells of the pane. Each
-- range must hold W.
for _, m in ipairs({
  { 52.049, 1, 49 }, { 41.190, 1, 38 }, { 41.190, 1 / 3, 11 },
  { 155.649, 1, 153 }, { 155.649, 0.5, 75 }, { 127.361, 1, 125 }, { 127.361, 0.5, 61 },
}) do
  local low, high = size.tiled_range(m[3], m[2])
  check(string.format("tiled range for %d cells at %.2f holds %.3f", m[3], m[2], m[1]),
    low <= m[1] and m[1] < high, string.format("range %.2f %.2f", low, high))
end

-- Floating panes measured in Rex for macOS: W, the fraction where the pane
-- first gets n cells, and n. A fraction just below or at the edge must give
-- a range that holds W.
for _, m in ipairs({
  { 52.049, 0.21416, 9 }, { 52.049, 0.59842, 29 }, { 41.190, 0.22243, 7 }, { 41.190, 0.58660, 22 },
  { 155.649, 0.20576, 30 }, { 155.649, 0.59767, 91 }, { 127.361, 0.21282, 25 }, { 127.361, 0.60540, 75 },
}) do
  local low, high = size.floating_range(m[3], m[2])
  check(string.format("floating range for %d cells at %.5f holds %.3f", m[3], m[2], m[1]),
    low <= m[1] and m[1] < high, string.format("range %.3f %.3f", low, high))
  low, high = size.floating_range(m[3] - 1, m[2] - 0.0002)
  check(string.format("floating range for %d cells below %.5f holds %.3f", m[3] - 1, m[2], m[1]),
    low <= m[1] and m[1] < high, string.format("range %.3f %.3f", low, high))
end

-- A floating pane's range holds every window size that gives its cells.
for _, w in ipairs({ 40, 50.3, 61.9, 154 }) do
  for _, f in ipairs({ 0.1, 0.25, 0.4 }) do
    for _, k in ipairs(insets) do
      local low, high = size.floating_range(app_cells(f, w, k), f)
      check(string.format("floating range at %.2f holds %.1f with inset %.3f", f, w, k), low <= w and w < high)
    end
  end
end

check("intersect overlaps", select(1, size.intersect(1, 5, 3, 8)) == 3)
check("intersect apart gives nil", size.intersect(1, 2, 3, 4) == nil)

-- For every window size in the range and every inset, the pane gets at
-- least n cells, and no more extra cells than the width of the range and
-- the spread of the insets allow. The starting size is never more than the
-- pane gets.
for _, r in ipairs({ { 51.5, 52.5 }, { 48, 54 }, { 47.77, 52.08 }, { 150, 158 }, { 155.2, 156.1 } }) do
  for _, n in ipairs({ 2, 7, 9, 20, 30 }) do
    local f, start = size.fraction(n, r[1], r[2], 1)
    local spread = size.inset_high - size.inset_low
    local most = n + 1 + math.ceil((n + 3) * (r[2] / r[1] - 1) + spread)
    local worst = 0
    for i = 0, 100 do
      local w = r[1] + (r[2] - r[1]) * i / 101
      for _, k in ipairs(insets) do
        local got = app_cells(f, w, k)
        if got < n or got > most or start > got then worst = got end
      end
    end
    check(string.format("fraction for %d cells in %.2f-%.2f", n, r[1], r[2]), worst == 0,
      "bad cell count " .. worst)
  end
end

-- A narrow range gives exactly n cells for each inset.
local f = size.fraction(7, 51.9, 52.2, 1)
local exact = true
for _, k in ipairs(insets) do
  if app_cells(f, 51.9, k) ~= 7 or app_cells(f, 52.19, k) ~= 7 then exact = false end
end
check("narrow range is exact", exact)

-- Over the limit, the pane gets the most cells that fit, and the same count
-- for every window size in the range.
f = size.fraction(40, 51.9, 52.2, 0.4)
check("limit holds", f <= 0.4)
check("limit gives one count", app_cells(f, 51.9) == app_cells(f, 52.19),
  app_cells(f, 51.9) .. " and " .. app_cells(f, 52.19))

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

-- A pane that spans the window allows 2.2 to 3.4 cells more.
local low, high = size.tiled_range(80, 1)
check("tiled range for a full pane", low == 82.2 and high == 83.4)

check("load of a missing file is empty", next(size.load(os.tmpname() .. ".none")) == nil)
check("load of no path is empty", next(size.load(nil)) == nil)

local path = os.tmpname()
size.save(path, back)
local loaded = size.load(path)
os.remove(path)
check("save and load round trip",
  loaded["window:1"].key == "k2" and loaded["window:2"].cols[1] == 1 and loaded["window:1"].rows[1] == 30)

H.done()
