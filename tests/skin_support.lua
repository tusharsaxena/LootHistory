-- tests/skin_support.lua: the skin a switch case switches to (tests/test_skin_table.lua,
-- tests/test_skin_insights.lua).
--
-- Loaded with dofile (it registers no case of its own). A switch case proves a repaint only for a
-- token whose value moves, and since LibKa0s v1.78.0's fourth round no shipped skin moves every
-- token these cases compare: Azeroth went dark and took Ka0s Default's semantic, quality and chart
-- colors, and no other skin sets its own. So the cases switch to SWITCH, a test-only skin: Azeroth's
-- own tokens, with every color Ka0s Default would still draw inverted, so each compared token moves
-- whichever way a later round retunes the shipped skins. Registered on first use under a key no
-- shipped skin takes; a second registration replaces the first. It also parts menu.text from
-- text.body, which no shipped skin does, so a row menu reading the wrong one fails a case.
--
-- Two models for the CheckButton cases: the kit's frames answer every capitalized call with the
-- frame and its hooksecurefunc is a no-op, so a tick that never follows SetChecked passes there.

local M = {}

M.KEY = "lh-switch"

local function invert(c)
  return { 1 - c[1], 1 - c[2], 1 - c[3], c[4] }
end

local function isColor(v)
  return type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number"
    and type(v[3]) == "number"
end

local function same(a, b)
  for i = 1, 4 do
    if (a[i] or 1) ~= (b[i] or 1) then return false end
  end
  return true
end

--- Register SWITCH with `Skin` (the LibKa0s-Skin-1.0 major) and answer its key.
function M.key(Skin)
  if not Skin:GetSkin(M.KEY) then
    local base, az = Skin:ResolveSkin(Skin.DEFAULT), Skin:ResolveSkin("azeroth")
    local tokens = {}
    for name, v in pairs(az) do tokens[name] = v end
    for name, v in pairs(base) do
      if isColor(v) and isColor(tokens[name]) and same(v, tokens[name]) then
        tokens[name] = invert(v)
      end
    end
    tokens["menu.text"] = { 0.91, 0.13, 0.57, 1 }
    Skin:RegisterSkin({ key = M.KEY, label = "Switch (test)", tokens = tokens })
  end
  return M.KEY
end

--- Give the kit frame `f` a CheckButton's state: checked and mouse-enabled are stored and answered.
function M.checkButton(f)
  local isChecked, mouse = false, true
  rawset(f, "SetChecked", function(_, on) isChecked = on and true or false end)
  rawset(f, "GetChecked", function() return isChecked end)
  rawset(f, "EnableMouse", function(_, on) mouse = on and true or false end)
  rawset(f, "IsMouseEnabled", function() return mouse end)
  return f
end

--- hooksecurefunc's table-member form, run after the method as in the client. Set it on the mocks
--- for a case: the library and the degraded stub read the global at the call.
function M.hooksecurefunc(frame, method, fn)
  local stock = frame[method]
  rawset(frame, method, function(self, ...)
    stock(self, ...)
    fn(self, ...)
  end)
end

return M
