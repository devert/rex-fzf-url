-- popup-size.lua: work out the bounds of a floating pane that holds a
-- terminal of a given size. init.lua and bin/measure.lua load this file.
--
-- Rex places a floating pane with bounds that are fractions of the window,
-- but it doesn't report the size of the window in cells. A floating pane
-- that is a fraction f of a window W cells wide is floor(f * W - inset)
-- cells wide, as its border and padding take about inset cells. The same
-- goes for the height. So the plugin keeps a range [low, high) of possible
-- window sizes for each direction, and picks bounds that fit every size in
-- the range.
--
-- The numbers below come from Rex for macOS (app 0.1.0, build 1853), at two
-- window sizes: 153x49 and 125x38 cells in a full tiled pane. The inset
-- measured 2.03 to 2.16 cells. W is in the cells that floating panes use,
-- and it is about 3 cells more than a full tiled pane gets.
--
-- Later measurements at 9 window sizes, from 900x580 to 1728x1083 points,
-- with the sidebar shown and hidden, found the same inset. But with the
-- sidebar hidden, W in rows is about 2 rows less, and a full tiled pane
-- keeps its rows. W in rows is then only 0.25 to 1.7 rows more than a full
-- tiled pane gets. The plugin can't see the sidebar, so the ranges below
-- hold both cases.
--
-- Rex 0.1.0-preview.21 (November 2026) pads the bottom of a floating pane
-- less. Floating panes from 0.1 to 1.0 of the window, at four window sizes
-- from 116x29 to 180x40 cells of W, with the sidebar shown and hidden,
-- found a column inset of 2.01 to 2.14 cells, as before, but a row inset of
-- only 1.62 to 1.685 rows. A full tiled pane got 0.8 to 2.3 rows less than
-- W, within the range below.

local M = {}

-- The smallest and largest inset of a floating pane, with a margin, for
-- columns and for rows.
M.inset = {
  cols = { low = 1.95, high = 2.25 },
  rows = { low = 1.5, high = 1.8 },
}

-- Return the inset table for rows when rows is true, else for columns.
local function inset(rows)
  return rows and M.inset.rows or M.inset.cols
end

-- Return the range of window sizes that a tiled pane of n cells allows, when
-- the pane is a fraction f of the window. rows is true for a height, and
-- false for a width. A pane that spans the window has 1.64 to 3.25 columns
-- less than W, and 0.25 to 3.38 rows less. Other panes lose 1.6 to 3.3
-- cells of f * W to padding and to the dividers between panes. All ranges
-- have a margin.
function M.tiled_range(n, f, rows)
  if f >= 0.999 then
    if rows then return n + 0.1, n + 3.5 end
    return n + 1.5, n + 3.5
  end
  return (n + 1.5) / f, (n + 4) / f
end

-- Return the range of window sizes that a floating pane of n cells allows,
-- when the pane is a fraction f of the window. rows is true for a height,
-- and false for a width.
function M.floating_range(n, f, rows)
  local k = inset(rows)
  return (n + k.low) / f, (n + 1 + k.high) / f
end

-- Return the overlap of two ranges, or nil when they don't overlap.
function M.intersect(low1, high1, low2, high2)
  local low, high = math.max(low1, low2), math.min(high1, high2)
  if low >= high then return nil end
  return low, high
end

-- Return the fraction of the window for a floating pane of n cells. Use the
-- middle of the fractions that give n cells for every window size in
-- [low, high) and every inset. When no fraction does that, use the smallest
-- one that gives at least n cells. A cell too many is better than a cell
-- too few, as fzf would then hide a URL.
local function fit(n, low, high, k)
  local small, large = (n + k.high) / low, (n + 1 + k.low) / high
  if small < large then return (small + large) / 2 end
  return (n + k.high + 0.02) / low
end

-- Return the fraction of the window for a floating pane of n cells, and the
-- fewest cells that the pane can then get. When n cells take more than max,
-- use the most cells that fit in max, so that the size of the pane is still
-- known. rows is true for a height, and false for a width.
function M.fraction(n, low, high, max, rows)
  local k = inset(rows)
  local f = fit(n, low, high, k)
  while f > max and n > 1 do
    n = n - 1
    f = fit(n, low, high, k)
  end
  f = math.min(f, max)
  return f, math.max(1, math.floor(f * low - k.high))
end

-- Return a short hash of a string, to use in a cache key.
function M.hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return string.format("%08x", h)
end

-- The cache holds the ranges that earlier popups measured, one line for
-- each window: the window, the key of its layout, and the ranges for the
-- columns and the rows. Return them as a table by window.
function M.parse(text)
  local cache = {}
  for line in (text or ""):gmatch("[^\n]+") do
    local window, key, a, b, c, d = line:match("^(%S+) (%S+) (%S+) (%S+) (%S+) (%S+)$")
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if window ~= nil and a ~= nil and b ~= nil and c ~= nil and d ~= nil then
      cache[window] = { key = key, cols = { a, b }, rows = { c, d } }
    end
  end
  return cache
end

-- Return the text of a cache table, the reverse of parse.
function M.format(cache)
  local lines = {}
  for window, e in pairs(cache) do
    lines[#lines + 1] = string.format("%s %s %.6f %.6f %.6f %.6f",
      window, e.key, e.cols[1], e.cols[2], e.rows[1], e.rows[2])
  end
  table.sort(lines)
  return table.concat(lines, "\n") .. "\n"
end

-- Add a measured range to the cache entry of a window. Keep the overlap
-- with what the entry holds for the same layout. Replace the entry when the
-- layout changed, or when the ranges don't overlap, as the window then
-- changed size.
function M.merge(cache, window, key, col_low, col_high, row_low, row_high)
  local e = cache[window]
  if e ~= nil and e.key == key then
    local cl, ch = M.intersect(e.cols[1], e.cols[2], col_low, col_high)
    local rl, rh = M.intersect(e.rows[1], e.rows[2], row_low, row_high)
    if cl ~= nil and rl ~= nil then
      col_low, col_high, row_low, row_high = cl, ch, rl, rh
    end
  end
  cache[window] = { key = key, cols = { col_low, col_high }, rows = { row_low, row_high } }
end

-- Return the cache table in the file at path. A missing file gives an empty
-- table.
function M.load(path)
  local f = path and io.open(path, "r")
  if f == nil then return {} end
  local text = f:read("*a")
  f:close()
  return M.parse(text)
end

-- Write the cache table to the file at path. Write a new file, then rename
-- it, so a reader never sees half a file.
function M.save(path, cache)
  local tmp = path .. "." .. tostring(os.time()) .. tostring(math.random(1000000))
  local f = io.open(tmp, "w")
  if f == nil then return end
  f:write(M.format(cache))
  f:close()
  os.rename(tmp, path)
end

return M
