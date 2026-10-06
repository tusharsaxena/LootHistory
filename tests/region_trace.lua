-- Shared by tests/test_timelinetab.lua and tests/test_analytics_layout.lua (smoke LED-9): "does
-- anything a tab draws stay on screen once its pane is hidden?" The kit's mock cannot answer that
-- on its own. Its IsVisible reads only the frame's OWN shown flag, this repo's CreateFrame drops the
-- parent argument (tests/wow_mock.lua), and CreateTexture hands back the frame itself. So while a
-- traced block runs, every CreateFrame, CreateFontString, CreateTexture and CreateLine is recorded
-- with the region that owns it, a texture becomes an object of its own, and R.Visible walks the
-- recorded parents the way the client's IsVisible does: a region is visible only while it and every
-- ancestor is shown. A region parented outside the traced tree (the browser window, UIParent, or no
-- parent at all, which the client reads as UIParent) ends the walk as visible, which is the leak
-- this exists to catch.
local T = _G.LH_TEST
local m = T.mocks
local R = {}

local function owner(o) return rawget(o, "__traceParent") or rawget(o, "__owner") end

--- Run `fn` with region creation traced; returns every region made, in creation order.
function R.Trace(fn)
  local made, base = {}, m.CreateFrame
  local function record(o, parent)
    o.__traceParent = parent
    made[#made + 1] = o
    return o
  end
  local function decorate(f)
    local createFS, createLine = f.CreateFontString, rawget(f, "CreateLine")
    rawset(f, "CreateFontString", function(self, ...) return record(createFS(self, ...), self) end)
    rawset(f, "CreateTexture", function(self) return record(m.__stubFrame(), self) end)
    if createLine then
      rawset(f, "CreateLine", function(self, ...) return record(createLine(self, ...), self) end)
    end
  end
  m.CreateFrame = function(frameType, name, parent, ...)
    local f = base(frameType, name, parent, ...)
    decorate(f)
    return record(f, parent or m.UIParent)
  end
  local ok, err = pcall(fn)
  m.CreateFrame = base
  if not ok then error(err, 0) end
  return made
end

--- The client's IsVisible over the traced parents: shown, and every recorded ancestor shown.
function R.Visible(o)
  while o do
    if rawget(o, "__shown") == false then return false end
    o = owner(o)
  end
  return true
end

-- One line per region for a failure message: what it is and, for a FontString, what it says.
local function describe(o)
  if rawget(o, "__isFontString") then return ("FontString %q"):format(tostring(rawget(o, "__text"))) end
  if rawget(o, "__owner") then return "Line" end
  return "Frame or Texture"
end

--- The regions in `made` that are still visible: with the tab's pane hidden, there should be none.
function R.Leaks(made)
  local out = {}
  for _, o in ipairs(made) do if R.Visible(o) then out[#out + 1] = describe(o) end end
  return out
end

--- How many FontStrings in `made` are visible and carry text (the "did it draw anything" check).
function R.ShownText(made)
  local n = 0
  for _, o in ipairs(made) do
    if rawget(o, "__isFontString") and R.Visible(o) and (rawget(o, "__text") or "") ~= "" then n = n + 1 end
  end
  return n
end

return R
