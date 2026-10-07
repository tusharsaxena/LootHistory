-- testkit/mock_lines.lua — Line regions (revision 37).
--
-- LibKa0s v1.69.0 ships a line chart (`LibKa0s-Widgets-1.0`'s `WidgetsLineChart.lua`) that draws
-- every segment, grid rule and crosshair as a `Line` from `Region:CreateLine`. Through revision 36
-- `CreateLine` answered from `mock_base.lua`'s metatable, which hands back the frame itself, so a
-- chart's hundred segments were one object and every endpoint it set was dropped (fidelity rules
-- 1 and 3).
--
-- What is modeled, and the client behavior each one follows:
--
--   * `CreateLine` answers a NEW object per call, recorded in creation order on the frame that
--     made it (`f.__madeLines`), so a suite can count what a render created and see that a second
--     render created nothing.
--   * The two ends are recorded as given (`relativePoint, relativeTo, x, y`) and answered back by
--     `GetStartPoint` / `GetEndPoint`; `ClearAllPoints` forgets both, as it does on a Region.
--   * Thickness, color, texture, alpha and draw layer are recorded.
--   * A new line is SHOWN, as a new region is in the client (and as `mock_base.lua` makes frames).
--
-- What is NOT modeled, deliberately: a Line is not a Frame. It has no scripts, no mouse, no
-- children and no geometry of its own, so any capitalized method this file does not define RAISES,
-- naming itself. A chart that called `SetScript` on a line would fail in the client; it fails here.
--
-- Loaded by `mock_base.lua` from its own folder, like `mock_resize.lua`, and a file of its own for
-- the same reason: `mock_base.lua` sits near `layout-§1`'s 1500-line cap. It answers one function,
-- `decorateFrame(f)`, which every tracked frame passes through as it is made.

local Lines = {}

local LINE_METHODS = {}

function LINE_METHODS:Show() self.__shown = true end
function LINE_METHODS:Hide() self.__shown = false end
function LINE_METHODS:SetShown(v) self.__shown = not not v end
function LINE_METHODS:IsShown() return self.__shown end
function LINE_METHODS:SetStartPoint(relPoint, relTo, x, y) self.__start = { relPoint, relTo, x or 0, y or 0 } end
function LINE_METHODS:SetEndPoint(relPoint, relTo, x, y) self.__end = { relPoint, relTo, x or 0, y or 0 } end
function LINE_METHODS:GetStartPoint()
  local s = self.__start
  if not s then return nil end
  return s[1], s[2], s[3], s[4]
end
function LINE_METHODS:GetEndPoint()
  local e = self.__end
  if not e then return nil end
  return e[1], e[2], e[3], e[4]
end
function LINE_METHODS:ClearAllPoints() self.__start, self.__end = nil, nil end
function LINE_METHODS:SetThickness(t) self.__thickness = t end
function LINE_METHODS:GetThickness() return self.__thickness end
function LINE_METHODS:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a or 1 } end
function LINE_METHODS:SetVertexColor(r, g, b, a) self.__vertex = { r, g, b, a or 1 } end
function LINE_METHODS:SetTexture(path) self.__texture = path end
function LINE_METHODS:SetAlpha(a) self.__alpha = a end
function LINE_METHODS:GetAlpha() return self.__alpha or 1 end
function LINE_METHODS:SetDrawLayer(layer, sub) self.__layer, self.__sublevel = layer, sub end

local LINE_META = {
  __index = function(_, key)
    local m = LINE_METHODS[key]
    if m then return m end
    if type(key) == "string" and key:match("^%u") then
      error("testkit: a Line has no " .. key .. " -- model it in testkit/mock_lines.lua if the "
        .. "client answers it, or stop calling it on a Line", 2)
    end
    return nil
  end,
}

local function newLine(owner, layer, sublevel)
  return setmetatable({
    __owner = owner, __layer = layer, __sublevel = sublevel, __shown = true, __thickness = 1,
  }, LINE_META)
end

--- Give one frame the recording `CreateLine`. Plain field `__madeLines`, so a suite reads it directly.
function Lines.decorateFrame(f)
  f.__madeLines = {}
  function f:CreateLine(_, layer, _, sublevel)
    local l = newLine(self, layer, sublevel)
    self.__madeLines[#self.__madeLines + 1] = l
    return l
  end
end

return Lines
