local addonName, NS = ...
NS.Schema = NS.Schema or {}
local S = NS.Schema
local C = NS.Constants

-- One row per setting. Drives AceDB defaults, panel widgets, and slash get/set/list/reset.
-- Paths resolve against NS.db.global (account-wide), not .profile.
-- `group` names the panel section header; row order within a group drives the
-- two-column pairing. `wide` forces a full-width row (see settings/Panel.lua).
S.Schema = {
  -- ── Master Controls ──
  { path = "settings.enabled", default = true, type = "boolean", widget = "CheckBox",
    group = "Master Controls", label = "Enable collection",
    tooltip = "Master switch for recording looted items.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "enabled") end
    end },

  { path = "minimap.hide", default = false, type = "boolean", widget = "CheckBox",
    group = "Master Controls", label = "Hide minimap button",
    tooltip = "Hide the LootHistory minimap button.",
    onChange = function(v)
      if NS.Browser and NS.Browser.SetMinimapHidden then NS.Browser:SetMinimapHidden(v) end
    end },

  { path = "settings.windowScale", default = 1.0, type = "number", min = 0.6, max = 1.6, widget = "Slider",
    group = "Master Controls", label = "Window scale",
    tooltip = "Scale of the History browser window.",
    onChange = function(v)
      if NS.Browser and NS.Browser.SetScale then NS.Browser:SetScale(v) end
    end },

  -- ── Data Collection ──
  { path = "settings.qualityThreshold", default = 1, type = "number", widget = "Dropdown",
    group = "Data Collection", label = "Minimum quality", options = C.QUALITY_OPTIONS,
    tooltip = "Only record items at or above this quality.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "quality") end
    end },

  { path = "settings.excludeQuestItems", default = true, type = "boolean", widget = "CheckBox",
    group = "Data Collection", label = "Exclude quest items",
    tooltip = "Skip items of the Quest type (transient quest objects).",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "questfilter") end
    end },

  { path = "settings.retentionDays", default = 30, type = "number", widget = "Dropdown",
    group = "Data Collection", label = "Keep history for", options = C.RETENTION_OPTIONS,
    tooltip = "Automatically drop records older than this. 'Never' keeps everything.",
    onChange = function()
      if NS.Database and NS.Database.PruneOld then NS.Database:PruneOld() end
    end },

  -- Stored as a set of MUTED sources (excludedSources); the panel renders it inverted
  -- (invert=true) as "Record data from" so a checked box means "record this source".
  { path = "settings.excludedSources", default = {}, type = "table", widget = "MultiCheck",
    wide = true, invert = true,
    group = "Data Collection", label = "Record data from", options = C.SOURCE_OPTIONS,
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "excludes") end
    end },

}
-- NOTE: debug is intentionally NOT a Schema setting. It is a session-only flag (NS.State.debug)
-- tied to the debug console's visibility; toggled by `/lh debug`, always off after a reload.

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

-- Deep-copy table values so the write-path never stores (or hands out) a live reference to a
-- schema `default` table. Without this, `S:Set(path, row.default)` on a reset would alias the DB
-- to the shared default table (e.g. settings.excludedSources = {}), so any in-place mutation of
-- the stored set would silently poison the default for the rest of the session.
local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = deepcopy(val) end
  return out
end

-- Single write seam. Panel widgets and slash `set` both route through here.
function S:Set(path, value)
  local row = S:FindRow(path)
  if not row then return false, "unknown path: " .. tostring(path) end
  if row.validate and not row.validate(value) then return false, "invalid value" end
  S:WritePath(NS.db.global, path, deepcopy(value))
  if row.onChange then row.onChange(value) end
  return true
end

function S:Get(path)
  return S:ReadPath(NS.db.global, path)
end

function S:Default(path)
  local row = S:FindRow(path)
  return row and deepcopy(row.default)
end

-- Boot validation: every schema path must resolve against the defaults table.
function S:Register()
  local g = NS.defaults and NS.defaults.global
  if not g then return end
  for _, row in ipairs(S.Schema) do
    if S:ReadPath(g, row.path) == nil and row.default == nil then
      print(NS.PREFIX .. " schema path missing default: " .. tostring(row.path))
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
  { name = "debug",    desc = "Toggle window; 'on'/'off' set logging",  fn = function(rest)
      -- `/lh debug` toggles the window only (state untouched); `/lh debug on|off` sets the
      -- session-only logging flag via the DebugLog seam. Logging runs even with the window closed.
      local arg = rest and tostring(rest):lower():match("^%s*(%S*)") or ""
      if not NS.DebugLog then return end
      if arg == "on" then NS.DebugLog:SetEnabled(true)
      elseif arg == "off" then NS.DebugLog:SetEnabled(false)
      else NS.DebugLog:Toggle() end
    end },
  { name = "test", desc = "Toggle a synthetic preview dataset (table + Insights)", fn = function()
      local on = NS.BrowserTable and NS.BrowserTable.ToggleTestMode and NS.BrowserTable:ToggleTestMode()
      print(NS.PREFIX .. " test mode " .. (on and "on" or "off"))
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
