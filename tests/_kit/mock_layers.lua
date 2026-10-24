-- testkit/mock_layers.lua — the kit's opt-in frame-layer recorder (revision 42): strata, level,
-- toplevel, clamp and parent alpha, answered back, for a suite that asserts where a window sits.
--
-- Returns an INSTALLER, called on a finished mock, which returns its RESTORE:
--
--   local M = base()
--   local restore = dofile("tests/_kit/mock_layers.lua")(M)
--   ...                                    -- every frame M.CreateFrame builds now records layers
--   restore()                              -- M.CreateFrame is the base's again
--
-- WHY. Through revision 41 the base answered every capitalized method it does not define with the
-- frame (mock_base.lua's metatable): GetFrameLevel and GetParent handed back the frame itself, and
-- SetFrameStrata, SetToplevel and SetClampedToScreen stored nothing, so "this window is DIALOG and
-- clamped" was a sentence no suite could assert. OPT-IN, and a file of its own, because mock_base.lua
-- sits close to layout-§1's cap and most suites never ask.
--
-- WHAT IS WRAPPED. M.CreateFrame, so every frame created AFTER install carries the methods, and
-- M.UIParent when it is a table (restore() puts its previous fields back). Frames built before the
-- install, and frames the base builds for itself (GameTooltip, the Ace fakes' frames), stay plain.
-- Code that cached `local CreateFrame = CreateFrame` at load time keeps the function it cached, so
-- install before loading the code under test when it does that.
--
-- THE METHODS are rawset on each frame:
--
--   SetFrameStrata(s) / GetFrameStrata()      own, else the nearest ancestor's, else "MEDIUM"; `s`
--                                             must be one of the client's eight names, and an
--                                             unknown one raises naming itself
--   SetFixedFrameStrata(b) / HasFixedFrameStrata()
--   SetFrameLevel(n) / GetFrameLevel()        own explicit level, else the parent's level + 1; a
--                                             frame with no parent is level 0
--   SetFixedFrameLevel(b) / HasFixedFrameLevel()
--   SetToplevel(b) / IsToplevel()
--   SetClampedToScreen(b) / IsClampedToScreen()
--   Raise() / Lower()                         counted in __raised / __lowered; the level is not moved
--   SetIgnoreParentAlpha(b) / IsIgnoringParentAlpha()
--   SetParent(p) / GetParent()                over the `__parent` M.CreateFrame recorded; SetParent
--                                             drops an explicit level, because the client re-derives
--                                             it from the new parent (XS-18)
--
-- Inheritance is read through the parents' raw fields, so a plain parent (built before the install)
-- still answers MEDIUM / 0 rather than the frame its metatable would hand back.
--
-- THE SURVEY. M.__layers(frame) -> { strata, level, toplevel, clamped, fixedStrata,
-- ignoreParentAlpha, raised }.
--
-- SPYING. A suite that spies on one of these methods by rawset restores it by re-assigning the
-- function it saved, NOT by rawsetting nil: the base's restore idiom (mock_base.lua's geometry
-- comment) would erase the recorder, and the frame would answer from the metatable again.

local STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true,
                 FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }

local METHODS = { "SetFrameStrata", "GetFrameStrata", "SetFixedFrameStrata", "HasFixedFrameStrata",
                  "SetFrameLevel", "GetFrameLevel", "SetFixedFrameLevel", "HasFixedFrameLevel",
                  "SetToplevel", "IsToplevel", "SetClampedToScreen", "IsClampedToScreen", "Raise",
                  "Lower", "SetIgnoreParentAlpha", "IsIgnoringParentAlpha", "SetParent", "GetParent" }

local function parentOf(f)
  local p = rawget(f, "__parent")
  if type(p) == "table" then return p end
  return nil
end

local function strataOf(f)
  local cur = f
  while cur do
    local s = rawget(cur, "__strata")
    if s then return s end
    cur = parentOf(cur)
  end
  return "MEDIUM"
end

local function levelOf(f)
  local own = rawget(f, "__level")
  if own then return own end
  local p = parentOf(f)
  if p then return levelOf(p) + 1 end
  return 0
end

local function flag(f, field) return rawget(f, field) == true end

local function install(f)
  rawset(f, "SetFrameStrata", function(self, s)
    if not STRATA[s] then error("mock_layers: unknown frame strata " .. tostring(s), 2) end
    rawset(self, "__strata", s)
  end)
  rawset(f, "GetFrameStrata", function(self) return strataOf(self) end)
  rawset(f, "SetFixedFrameStrata", function(self, b) rawset(self, "__fixedStrata", b and true or false) end)
  rawset(f, "HasFixedFrameStrata", function(self) return flag(self, "__fixedStrata") end)
  rawset(f, "SetFrameLevel", function(self, n) rawset(self, "__level", n) end)
  rawset(f, "GetFrameLevel", function(self) return levelOf(self) end)
  rawset(f, "SetFixedFrameLevel", function(self, b) rawset(self, "__fixedLevel", b and true or false) end)
  rawset(f, "HasFixedFrameLevel", function(self) return flag(self, "__fixedLevel") end)
  rawset(f, "SetToplevel", function(self, b) rawset(self, "__toplevel", b and true or false) end)
  rawset(f, "IsToplevel", function(self) return flag(self, "__toplevel") end)
  rawset(f, "SetClampedToScreen", function(self, b) rawset(self, "__clamped", b and true or false) end)
  rawset(f, "IsClampedToScreen", function(self) return flag(self, "__clamped") end)
  rawset(f, "Raise", function(self) rawset(self, "__raised", (rawget(self, "__raised") or 0) + 1) end)
  rawset(f, "Lower", function(self) rawset(self, "__lowered", (rawget(self, "__lowered") or 0) + 1) end)
  rawset(f, "SetIgnoreParentAlpha", function(self, b)
    rawset(self, "__ignoreParentAlpha", b and true or false)
  end)
  rawset(f, "IsIgnoringParentAlpha", function(self) return flag(self, "__ignoreParentAlpha") end)
  rawset(f, "SetParent", function(self, p)
    rawset(self, "__parent", p)
    rawset(self, "__level", nil)
  end)
  rawset(f, "GetParent", function(self) return rawget(self, "__parent") end)
  return f
end

return function(M)
  local prevCreate = M.CreateFrame
  M.CreateFrame = function(...)
    local f = prevCreate(...)
    if type(f) == "table" then install(f) end
    return f
  end

  local ui, saved = M.UIParent, nil
  if type(ui) == "table" then
    saved = {}
    for _, name in ipairs(METHODS) do saved[name] = rawget(ui, name) end
    install(ui)
  end

  function M.__layers(f)
    return {
      strata = strataOf(f),
      level = levelOf(f),
      toplevel = flag(f, "__toplevel"),
      clamped = flag(f, "__clamped"),
      fixedStrata = flag(f, "__fixedStrata"),
      ignoreParentAlpha = flag(f, "__ignoreParentAlpha"),
      raised = rawget(f, "__raised") or 0,
    }
  end

  return function()
    M.CreateFrame = prevCreate
    if saved then
      for _, name in ipairs(METHODS) do rawset(ui, name, saved[name]) end
    end
  end
end
