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

-- The insets measured in Rex for macOS, for columns and for rows. The model
-- must hold for each.
local insets = {
  cols = { 2.03, 2.075, 2.105, 2.115, 2.147, 2.162 },
  rows = { 1.63, 1.65, 1.665 },
}

-- Tiled panes measured in Rex for macOS: the window size W in floating
-- pane cells, a fraction of the window, the cells of the pane, and true for
-- rows. Each range must hold W. Where a measurement gave a range of W, both
-- ends are here.
for _, m in ipairs({
  { 52.049, 1, 49, true }, { 41.190, 1, 38, true }, { 41.190, 1 / 3, 11, true },
  { 155.649, 1, 153 }, { 155.649, 0.5, 75 }, { 127.361, 1, 125 }, { 127.361, 0.5, 61 },
  -- 1100x700 points with the sidebar hidden.
  { 113.64, 1, 112 }, { 114.28, 1, 112 }, { 113.64, 0.5, 54 }, { 114.28, 0.5, 54 },
  { 31.25, 1, 31, true }, { 31.75, 1, 31, true }, { 31.25, 0.5, 14, true }, { 31.75, 0.5, 14, true },
  -- 1100x700 points with the sidebar shown.
  { 89.44, 1, 87 }, { 90.09, 1, 87 }, { 89.44, 0.5, 42 }, { 90.09, 0.5, 42 },
  { 32.75, 1, 31, true }, { 33.88, 1, 31, true }, { 32.75, 0.5, 14, true }, { 33.88, 0.5, 14, true },
  -- 1728x1083 points with the sidebar hidden.
  { 180.00, 0.5, 87 }, { 180.56, 0.5, 87 },
  { 50.01, 1, 49, true }, { 50.72, 1, 49, true }, { 50.01, 0.5, 23, true }, { 50.72, 0.5, 23, true },
  -- Other window sizes with the sidebar shown.
  { 68.19, 1, 66 }, { 68.84, 1, 66 }, { 27.21, 1, 25, true }, { 28.36, 1, 25, true },
  { 94.59, 1, 92 }, { 95.23, 1, 92 }, { 34.48, 1, 32, true }, { 35.09, 1, 32, true },
  { 47.62, 1, 45, true }, { 48.38, 1, 45, true },
  -- Rex 0.1.0-preview.21, 154x38 cells in a full tiled pane.
  { 156.84, 1, 154 }, { 156.91, 1, 154 }, { 40.24, 1, 38, true }, { 40.29, 1, 38, true },
  -- Rex 0.1.0-preview.21 with the sidebar hidden: 38 rows, 28 rows in a
  -- small window, and 38 rows at full screen.
  { 38.91, 1, 38, true }, { 39.02, 1, 38, true }, { 28.815, 1, 28, true }, { 28.88, 1, 28, true },
  { 40.28, 1, 38, true }, { 40.32, 1, 38, true },
}) do
  local low, high = size.tiled_range(m[3], m[2], m[4] == true)
  check(string.format("tiled range for %d %s at %.2f holds %.3f", m[3], m[4] and "rows" or "columns", m[2], m[1]),
    low <= m[1] and m[1] < high, string.format("range %.2f %.2f", low, high))
end

-- Floating panes measured in Rex for macOS: W, the fraction where the pane
-- first gets n columns, and n. A fraction just below or at the edge must
-- give a range that holds W.
for _, m in ipairs({
  { 155.649, 0.20576, 30 }, { 155.649, 0.59767, 91 }, { 127.361, 0.21282, 25 }, { 127.361, 0.60540, 75 },
}) do
  local low, high = size.floating_range(m[3], m[2], false)
  check(string.format("floating range for %d columns at %.5f holds %.3f", m[3], m[2], m[1]),
    low <= m[1] and m[1] < high, string.format("range %.3f %.3f", low, high))
  low, high = size.floating_range(m[3] - 1, m[2] - 0.0002, false)
  check(string.format("floating range for %d columns below %.5f holds %.3f", m[3] - 1, m[2], m[1]),
    low <= m[1] and m[1] < high, string.format("range %.3f %.3f", low, high))
end

-- Floating panes measured in Rex 0.1.0-preview.21 at four window sizes:
-- the range of W in columns and in rows that fits all the panes, and
-- samples of the fraction of the window, and the columns and rows that the
-- pane got. Each range must hold both ends of W.
for _, win in ipairs({
  { name = "154x38, sidebar shown", cols = { 156.84, 156.91 }, rows = { 40.24, 40.29 }, panes = {
    { 0.100, 13, 2 }, { 0.198, 28, 6 }, { 0.303, 45, 10 }, { 0.408, 61, 14 }, { 0.513, 78, 19 },
    { 0.618, 94, 23 }, { 0.723, 111, 27 }, { 0.828, 127, 31 }, { 0.933, 144, 35 }, { 1, 154, 38 },
  } },
  { name = "sidebar hidden", cols = { 180.025, 180.35 }, rows = { 38.91, 39.02 }, panes = {
    { 0.10, 15, 2 }, { 0.25, 42, 8 }, { 0.40, 70, 13 }, { 0.55, 97, 19 }, { 0.70, 124, 25 },
    { 0.85, 151, 31 }, { 1, 178, 37 },
  } },
  { name = "small, sidebar hidden", cols = { 116.075, 116.17 }, rows = { 28.815, 28.88 }, panes = {
    { 0.10, 9, 1 }, { 0.25, 26, 5 }, { 0.40, 44, 9 }, { 0.55, 61, 14 }, { 0.70, 79, 18 },
    { 0.85, 96, 22 }, { 1, 114, 27 },
  } },
  { name = "full screen", cols = { 180.025, 180.35 }, rows = { 40.28, 40.32 }, panes = {
    { 0.10, 15, 2 }, { 0.25, 42, 8 }, { 0.40, 70, 14 }, { 0.55, 97, 20 }, { 0.70, 124, 26 },
    { 0.85, 151, 32 }, { 1, 178, 38 },
  } },
}) do
  for _, m in ipairs(win.panes) do
    local low, high = size.floating_range(m[2], m[1], false)
    check(string.format("%s: floating range for %d columns at %.3f", win.name, m[2], m[1]),
      low <= win.cols[1] and win.cols[2] < high, string.format("range %.3f %.3f", low, high))
    low, high = size.floating_range(m[3], m[1], true)
    check(string.format("%s: floating range for %d rows at %.3f", win.name, m[3], m[1]),
      low <= win.rows[1] and win.rows[2] < high, string.format("range %.3f %.3f", low, high))
  end
end

-- A floating pane's range holds every window size that gives its cells.
for _, dir in ipairs({ "cols", "rows" }) do
  for _, w in ipairs({ 40, 50.3, 61.9, 154 }) do
    for _, f in ipairs({ 0.1, 0.25, 0.4 }) do
      for _, k in ipairs(insets[dir]) do
        local low, high = size.floating_range(app_cells(f, w, k), f, dir == "rows")
        check(string.format("floating range at %.2f holds %.1f %s with inset %.3f", f, w, dir, k),
          low <= w and w < high)
      end
    end
  end
end

check("intersect overlaps", select(1, size.intersect(1, 5, 3, 8)) == 3)
check("intersect apart gives nil", size.intersect(1, 2, 3, 4) == nil)

-- For every window size in the range and every inset, the pane gets at
-- least n cells, and no more extra cells than the width of the range and
-- the spread of the insets allow. The fewest cells that it returns are
-- never more than the pane gets.
for _, dir in ipairs({ "cols", "rows" }) do
  for _, r in ipairs({ { 51.5, 52.5 }, { 48, 54 }, { 47.77, 52.08 }, { 150, 158 }, { 155.2, 156.1 } }) do
    for _, n in ipairs({ 2, 7, 9, 20, 30 }) do
      local f, start = size.fraction(n, r[1], r[2], 1, dir == "rows")
      local spread = size.inset[dir].high - size.inset[dir].low
      local most = n + 1 + math.ceil((n + 3) * (r[2] / r[1] - 1) + spread)
      local worst = 0
      for i = 0, 100 do
        local w = r[1] + (r[2] - r[1]) * i / 101
        for _, k in ipairs(insets[dir]) do
          local got = app_cells(f, w, k)
          if got < n or got > most or start > got then worst = got end
        end
      end
      check(string.format("fraction for %d %s in %.2f-%.2f", n, dir, r[1], r[2]), worst == 0,
        "bad cell count " .. worst)
    end
  end
end

-- A narrow range gives exactly n cells for each inset.
for _, dir in ipairs({ "cols", "rows" }) do
  local f = size.fraction(7, 51.9, 52.2, 1, dir == "rows")
  local exact = true
  for _, k in ipairs(insets[dir]) do
    if app_cells(f, 51.9, k) ~= 7 or app_cells(f, 52.19, k) ~= 7 then exact = false end
  end
  check("narrow range is exact for " .. dir, exact)
end

-- At the window measured in Rex 0.1.0-preview.21, a pane gets exactly the
-- rows it asks for, with no extra row at the bottom.
for _, n in ipairs({ 1, 5, 8, 12, 20, 30 }) do
  local f = size.fraction(n, 40.24, 40.29, 1, true)
  local got = math.floor(f * 40.26 - 1.65)
  check(string.format("measured window gives %d rows", n), got == n, "got " .. got)
end

-- Over the limit, the pane gets the most cells that fit, and the same count
-- for every window size in the range.
local f = size.fraction(40, 51.9, 52.2, 0.4)
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

-- A pane that spans the window allows 1.5 to 3.5 columns more, and 0.1 to
-- 3.5 rows more.
local low, high = size.tiled_range(80, 1, false)
check("tiled range for a full pane: columns", low == 81.5 and high == 83.5)
low, high = size.tiled_range(30, 1, true)
check("tiled range for a full pane: rows", math.abs(low - 30.1) < 1e-9 and high == 33.5)

check("load of a missing file is empty", next(size.load(os.tmpname() .. ".none")) == nil)
check("load of no path is empty", next(size.load(nil)) == nil)

local path = os.tmpname()
size.save(path, back)
local loaded = size.load(path)
os.remove(path)
check("save and load round trip",
  loaded["window:1"].key == "k2" and loaded["window:2"].cols[1] == 1 and loaded["window:1"].rows[1] == 30)

H.done()
