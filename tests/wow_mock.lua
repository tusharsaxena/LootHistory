-- Minimal WoW-API mock set for headless unit tests. Returns a builder so each run gets
-- a fresh, isolated environment. Only what the addon touches at load/test time is stubbed.

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = deepcopy(v) end
  return r
end

-- A universal frame stub: any method call is a no-op that returns the frame itself. WoW frame
-- API methods are always PascalCase (SetPoint, CreateTexture, HookScript, ...), so only those
-- keys get a no-op function; any other (lowercase/custom) field access misses through to nil,
-- letting addon code do `if not f.someCustomField then f.someCustomField = ... end` safely.
local function stubFrame()
  local f = {}
  setmetatable(f, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then
      return function() return f end
    end
    return nil
  end })
  return f
end

return function()
  local M = {}

  -- time / misc
  M.__now = 0
  M.time = os.time
  M.date = os.date
  M.GetTime = function() return M.__now end
  M.WOW_PROJECT_ID = 1
  M.WOW_PROJECT_MAINLINE = 1
  M.WOW_PROJECT_CLASSIC = 2

  -- player / world
  M.UnitName = function() return "Mock" end
  M.UnitClass = function() return "Mage", "MAGE", 8 end
  M.GetRealmName = function() return "Realm" end
  M.GetNormalizedRealmName = function() return "Realm" end
  M.GetZoneText = function() return "Testville" end
  M.GetSubZoneText = function() return "" end
  M.InCombatLockdown = function() return false end
  M.C_Map = { GetBestMapForUnit = function() return 2657 end }
  M.C_Timer = { After = function() end }
  M.C_Item = {
    GetItemInfoInstant = function() return 211296 end,
    GetItemInfo = function(link) return "Item Name", link, 4 end,
  }
  M.GetLootSourceInfo = function() return nil end

  -- strings
  M.LOOT_ITEM_SELF = "You receive loot: %s."
  M.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
  M.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
  M.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
  M.ITEM_QUALITY_COLORS = setmetatable({}, {
    __index = function() return { r = 1, g = 1, b = 1, hex = "ffffffff" } end,
  })
  M.strtrim = function(s) return (tostring(s):gsub("^%s*(.-)%s*$", "%1")) end
  M.strsplit = function(sep, s)
    local parts = {}
    for p in string.gmatch(s, "([^" .. sep .. "]+)") do parts[#parts + 1] = p end
    return unpack(parts)
  end

  -- UI
  M.UIParent = stubFrame()
  M.CreateFrame = function() return stubFrame() end
  M.UISpecialFrames = {}
  M.Settings = {
    RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
  }

  -- LibStub + Ace library mocks
  local libs = {}
  libs["AceDB-3.0"] = {
    New = function(_, _name, defaults)
      return {
        global = deepcopy(defaults and defaults.global or {}),
        profile = deepcopy(defaults and defaults.profile or {}),
      }
    end,
  }
  libs["AceAddon-3.0"] = {
    NewAddon = function(_, target)
      target = target or {}
      local noop = function() end
      target.RegisterEvent = noop
      target.UnregisterEvent = noop
      target.RegisterChatCommand = noop
      target.RegisterMessage = noop
      target.SendMessage = noop
      target.ScheduleTimer = function() return {} end
      target.CancelTimer = noop
      return target
    end,
  }
  M.LibStub = setmetatable(
    { GetLibrary = function(_, n) return libs[n] end },
    { __call = function(_, n) return libs[n] end }
  )

  return M
end
