-- measure.lua: bin/wait-resize.sh runs this with `rex do` before the popup
-- prints anything. It doesn't change the popup. It waits for the size that
-- the app asks for the popup in rex.args.block, and prints it as
-- "ROWS COLUMNS", so that wait-resize.sh can wait for the terminal to get
-- that size. With a cache file
-- and a spec, it also saves what that size tells about the window size in
-- the cache file. Later popups in the same window and layout then get
-- bounds that fit their content more closely.
--
-- Arguments: block, and optionally cache (the file) and spec: the window,
-- the key of its layout, and the popup bounds as fractions of the window
-- (w and h).

local here = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/[^/]*$")) or "."
local size = dofile(here .. "/../lib/popup-size.lua")

local terminal = "com.superlogical.terminal"
local block_id, path, spec = rex.args.block, rex.args.cache, rex.args.spec
if block_id == nil then return end

-- The app can ask for the size of the popup a moment after the popup opens.
-- Wait for the size that the owner asks for, for at most half a second, so
-- that the popup doesn't stay blank for long. Other clients can ask for
-- other sizes, but the owner's size is the one that the terminal gets.
local want
for _ = 1, 50 do
  local s = rex.block.call(terminal, "size", { block_id = block_id })
  if s == nil then return end
  if s.owner ~= nil then
    for _, d in ipairs(s.desired or {}) do
      if d.client_id == s.owner then want = d end
    end
    if want ~= nil then break end
  end
  rex.sleep(0.01)
end
if want == nil then return end
print(want.rows .. " " .. want.columns)

if path == nil or type(spec) ~= "string" then return end
local window, key, w, h = spec:match("^(%S+) (%S+) (%S+) (%S+)$")
w, h = tonumber(w), tonumber(h)
if window == nil or w == nil or h == nil then return end

local col_low, col_high = size.floating_range(want.columns, w)
local row_low, row_high = size.floating_range(want.rows, h, true)
local cache = size.load(path)
size.merge(cache, window, key, col_low, col_high, row_low, row_high)
size.save(path, cache)
