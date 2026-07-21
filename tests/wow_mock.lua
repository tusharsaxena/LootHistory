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
  M.__itemClassID = 0   -- overridable per-test item class (Enum.ItemClass); 0 = Consumable
  M.C_Item = {
    GetItemInfoInstant = function() return 211296, nil, nil, nil, nil, M.__itemClassID end,
    GetItemInfo = function(link) return "Item Name", link, 4 end,
  }
  M.GetLootSourceInfo = function() return nil end

  -- Currency API mock. GetCurrencyListSize / GetCurrencyListInfo / GetCurrencyListLink model a tiny
  -- currency window: one expansion header ("The War Within") then two currencies under it, so the
  -- category resolver has headers to walk. GetCurrencyInfoFromLink returns name + icon by id.
  M.__currencyNames = { [3008] = "Valorstones", [2914] = "Weathered Harbinger Crest" }
  M.C_CurrencyInfo = {
    GetCurrencyListSize = function() return 3 end,
    GetCurrencyListInfo = function(i)
      if i == 1 then return { name = "The War Within", isHeader = true } end
      if i == 2 then return { name = M.__currencyNames[3008], isHeader = false } end
      if i == 3 then return { name = M.__currencyNames[2914], isHeader = false } end
      return nil
    end,
    GetCurrencyListLink = function(i)
      if i == 2 then return "|Hcurrency:3008::|h[Valorstones]|h" end
      if i == 3 then return "|Hcurrency:2914::|h[Weathered Harbinger Crest]|h" end
      return nil
    end,
    GetCurrencyInfoFromLink = function(link)
      local id = tonumber(link and link:match("|?H?currency:(%d+)"))
      if not id then return nil end
      return { name = M.__currencyNames[id], iconFileID = 100000 + id }
    end,
    GetCurrencyInfo = function(id)
      local name = M.__currencyNames[id]
      if not name then return nil end
      return { name = name, iconFileID = 100000 + id, quantity = 0 }
    end,
  }

  -- strings
  M.LOOT_ITEM_SELF = "You receive loot: %s."
  M.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
  M.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
  M.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
  -- Bonus-roll self strings carry NO trailing period in live GlobalStrings.lua.
  M.LOOT_ITEM_BONUS_ROLL_SELF = "You receive bonus loot: %s"
  M.LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE = "You receive bonus loot: %sx%d"
  -- Created (crafted) and refunded self strings — these DO carry a trailing period in live GlobalStrings.
  M.LOOT_ITEM_CREATED_SELF = "You create: %s."
  M.LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
  M.LOOT_ITEM_REFUND = "You are refunded: %s."
  M.LOOT_ITEM_REFUND_MULTIPLE = "You are refunded: %sx%d."
  -- Roll-won line ("You won: <item>", no trailing period), used to stamp ROLL context.
  M.LOOT_ROLL_YOU_WON = "You won: %s"
  -- Currency gain strings (CHAT_MSG_CURRENCY). Single has no qty; multiples carry xN, and the
  -- bonus/overflow variants append a parenthetical (the overflow one embeds a second %s = the
  -- currency name, which the parser ignores).
  M.CURRENCY_GAINED = "You receive currency: %s"
  M.CURRENCY_GAINED_MULTIPLE = "You receive currency: %sx%d"
  M.CURRENCY_GAINED_MULTIPLE_BONUS = "You receive currency: %sx%d (Bonus Objective)"
  M.CURRENCY_GAINED_MULTIPLE_OVERFLOW = "You receive currency: %sx%d (You've earned the maximum amount of %s)"
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
  -- Chat sink for NS.Print (core/Util.lua). No-op by default; tests override AddMessage to capture.
  M.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
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
        -- Account-wide addon: created in-game with defaultProfile=true, so the profile is always
        -- the fixed "Default". Mirror that here so the [Init] summary renders a real profile name.
        GetCurrentProfile = function() return "Default" end,
      }
    end,
  }
  -- Message bus modeled on CallbackHandler: callbacks keyed by (event, target). Registering the
  -- same message twice on one target overwrites (only the last survives); SendMessage fires to
  -- every distinct target. This mirrors the real semantics so tests can catch same-target
  -- clobbering — the exact bug that shipped when the bus was a bare no-op mock.
  local msgRegistry = {}
  M.__msgRegistry = msgRegistry
  local function embedBus(obj)
    obj.RegisterMessage = function(self, event, fn)
      msgRegistry[event] = msgRegistry[event] or {}
      msgRegistry[event][self] = fn
    end
    obj.UnregisterMessage = function(self, event)
      if msgRegistry[event] then msgRegistry[event][self] = nil end
    end
    obj.SendMessage = function(_, event, ...)
      local t = msgRegistry[event]
      if not t then return end
      for _, fn in pairs(t) do fn(event, ...) end
    end
    return obj
  end

  libs["AceAddon-3.0"] = {
    NewAddon = function(_, target)
      target = target or {}
      local noop = function() end
      target.RegisterEvent = noop
      target.UnregisterEvent = noop
      target.RegisterChatCommand = noop
      target.ScheduleTimer = function() return {} end
      target.CancelTimer = noop
      return embedBus(target)
    end,
  }
  libs["AceEvent-3.0"] = {
    Embed = function(_, obj)
      obj.RegisterEvent = obj.RegisterEvent or function() end
      obj.UnregisterEvent = obj.UnregisterEvent or function() end
      return embedBus(obj)
    end,
  }
  M.LibStub = setmetatable(
    { GetLibrary = function(_, n) return libs[n] end },
    { __call = function(_, n) return libs[n] end }
  )

  return M
end
