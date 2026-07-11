local addonName, NS = ...
NS.Schema = NS.Schema or {}
local S = NS.Schema
local C = NS.Constants

-- One row per setting. Drives AceDB defaults, panel widgets, and slash get/set/list/reset.
-- Paths resolve against NS.db.global (account-wide), not .profile.
S.Schema = {
  { path = "settings.enabled", default = true, type = "boolean", widget = "CheckBox",
    label = "Enable collection" },

  { path = "settings.qualityThreshold", default = 0, type = "number", widget = "Dropdown",
    label = "Minimum quality", options = C.QUALITY_OPTIONS,
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "quality") end
    end },

  { path = "settings.retentionDays", default = 30, type = "number", widget = "Dropdown",
    label = "Keep history for", options = C.RETENTION_OPTIONS,
    onChange = function()
      if NS.Database and NS.Database.PruneOld then NS.Database:PruneOld() end
    end },

  { path = "settings.excludedSources", default = {}, type = "table", widget = "MultiCheck",
    label = "Don't record from", options = C.SOURCE_OPTIONS },

  { path = "minimap.hide", default = false, type = "boolean", widget = "CheckBox",
    label = "Hide minimap button",
    onChange = function(v)
      if NS.Browser and NS.Browser.SetMinimapHidden then NS.Browser:SetMinimapHidden(v) end
    end },

  { path = "settings.windowScale", default = 1.0, type = "number", min = 0.6, max = 1.6, widget = "Slider",
    label = "Window scale",
    onChange = function(v)
      if NS.Browser and NS.Browser.SetScale then NS.Browser:SetScale(v) end
    end },

  { path = "debug", default = false, type = "boolean", widget = "CheckBox",
    label = "Debug logging" },
}

function S:FindRow(path)
  for _, row in ipairs(S.Schema) do
    if row.path == path then return row end
  end
  return nil
end

function S:ReadPath(root, path)
  local node = root
  for _, key in ipairs(NS.Util.SplitPath(path)) do
    if type(node) ~= "table" then return nil end
    node = node[key]
  end
  return node
end

function S:WritePath(root, path, value)
  local parts = NS.Util.SplitPath(path)
  local node = root
  for i = 1, #parts - 1 do
    local key = parts[i]
    if type(node[key]) ~= "table" then node[key] = {} end
    node = node[key]
  end
  node[parts[#parts]] = value
end

-- Single write seam. Panel widgets and slash `set` both route through here.
function S:Set(path, value)
  local row = S:FindRow(path)
  if not row then return false, "unknown path: " .. tostring(path) end
  if row.validate and not row.validate(value) then return false, "invalid value" end
  S:WritePath(NS.db.global, path, value)
  if row.onChange then row.onChange(value) end
  return true
end

function S:Get(path)
  return S:ReadPath(NS.db.global, path)
end

function S:Default(path)
  local row = S:FindRow(path)
  return row and row.default
end

-- Boot validation: every schema path must resolve against the defaults table.
function S:Register()
  local g = NS.defaults and NS.defaults.global
  if not g then return end
  for _, row in ipairs(S.Schema) do
    if S:ReadPath(g, row.path) == nil and row.default == nil then
      print("|cff33ff99" .. addonName .. "|r schema path missing default: " .. tostring(row.path))
    end
  end
end

-- Slash command table. Dispatch lives in Slash.lua; help is generated from this.
NS.COMMANDS = {
  { name = "show",     desc = "Open the window",       fn = function() NS.Browser:Show() end },
  { name = "hide",     desc = "Close the window",      fn = function() NS.Browser:Hide() end },
  { name = "toggle",   desc = "Toggle the window",     fn = function() NS.Browser:Toggle() end },
  { name = "config",   desc = "Open settings",         fn = function() if NS.Panel then NS.Panel:Open() end end },
  { name = "get",      desc = "Get a setting value",   fn = function(a) NS.Slash:CliGet(a) end },
  { name = "set",      desc = "Set a setting value",   fn = function(a) NS.Slash:CliSet(a) end },
  { name = "list",     desc = "List all settings",     fn = function() NS.Slash:CliList() end },
  { name = "reset",    desc = "Reset one setting",     fn = function(a) NS.Slash:CliReset(a) end },
  { name = "resetall", desc = "Reset all settings",    fn = function() NS.Slash:CliResetAll() end },
  { name = "debug",    desc = "Toggle the debug console",  fn = function()
      NS.db.global.debug = not NS.db.global.debug
      if NS.DebugLog then
        if NS.db.global.debug then NS.DebugLog:Show() else NS.DebugLog:Hide() end
      end
      print("|cff33ff99" .. addonName .. "|r debug " .. (NS.db.global.debug and "on" or "off"))
      if NS.Debug then NS.Debug("debug logging enabled") end
    end },
  { name = "test", desc = "Toggle a preview of every bound type", fn = function()
      local on = NS.BrowserTable and NS.BrowserTable.ToggleTestMode and NS.BrowserTable:ToggleTestMode()
      print("|cff33ff99" .. addonName .. "|r test mode " .. (on and "on" or "off"))
    end },
  { name = "purge", desc = "Delete ALL loot history (asks to confirm)", fn = function()
      if type(StaticPopup_Show) == "function" then
        StaticPopup_Show("KA0S_LOOTHISTORY_PURGE")
      elseif NS.Database and NS.Database.Purge then
        NS.Database:Purge()
      end
    end },
  { name = "help",     desc = "Show this help",        fn = function() NS.Slash:PrintHelp() end },
}
