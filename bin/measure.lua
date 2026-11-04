-- measure.lua: picker.sh runs this with `rex do`, in the background. It
-- doesn't change the popup. It reads the size that the app gives the popup
-- in rex.args.block, and saves what that size tells about the window size in
-- the cache file. The next popup in the same window and layout then gets
-- bounds that fit its content exactly.
--
-- Arguments: block, cache (the file), and spec: the window, the key of its
-- layout, and the popup bounds as fractions of the window (w and h).

local here = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/[^/]*$")) or "."
local size = dofile(here .. "/../lib/popup-size.lua")

local terminal = "com.superlogical.terminal"
local block_id, path, spec = rex.args.block, rex.args.cache, rex.args.spec
if block_id == nil or path == nil or type(spec) ~= "string" then return end
local window, key, w, h = spec:match("^(%S+) (%S+) (%S+) (%S+)$")
w, h = tonumber(w), tonumber(h)
if window == nil or w == nil or h == nil then return end

-- The popup has no owner until the app takes it and asks for its size. Wait
-- for that, for at most one second.
local want
for _ = 1, 100 do
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

local col_low, col_high = size.floating_range(want.columns, w)
local row_low, row_high = size.floating_range(want.rows, h)
local cache = size.load(path)
size.merge(cache, window, key, col_low, col_high, row_low, row_high)
size.save(path, cache)
