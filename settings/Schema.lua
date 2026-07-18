local addonName, NS = ...
NS.Schema = NS.Schema or {}
local S = NS.Schema
local C = NS.Constants
local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer (events-frames-taint-§8)

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

  -- Session-only row (never persisted): its value is the debug console WINDOW's visibility, not the
  -- NS.State.debug logging flag. get/set route to NS.DebugLog (Show/Hide/IsShown); Schema:Set skips
  -- the db.global write for sessionOnly rows. `soloRow` puts it on its own panel row (below the
  -- Enable / Hide-minimap pair). Mirrors `/lh debug` (no-arg), which toggles the window too.
  { path = "state.debugConsole", sessionOnly = true, default = false, type = "boolean",
    widget = "CheckBox", soloRow = true, group = "Master Controls", label = "Debug console",
    tooltip = "Show or hide the on-screen debug console window. Session-only \226\128\148 resets on reload.",
    get = function() return NS.DebugLog ~= nil and NS.DebugLog:IsShown() end,
    set = function(v)
      if not NS.DebugLog then return end
      if v then NS.DebugLog:Show() else NS.DebugLog:Hide() end
    end },

  { path = "settings.windowScale", default = 1.0, type = "number", min = 0.6, max = 1.6, widget = "Slider",
    fmt = "%.2fx",  -- scale → "1.00x" in slash list/get (slash-commands-§5 value formatting)
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

  -- ── Auction House Price ──  (own settings sub-page; see settings/Panel.lua)
  { path = "settings.auction.enabled", default = true, type = "boolean", widget = "CheckBox",
    group = "Auction House Price", label = "Enable AH pricing",
    tooltip = "Record an auction-house price on each loot, read from installed pricing addons." },
  { path = "settings.auction.tsmSource", default = "dbmarket", type = "string", widget = "Dropdown",
    group = "Auction House Price", label = "TSM price source", options = C.TSM_SOURCE_OPTIONS,
    tooltip = "Which TSM price the cascade requests when it reaches TSM." },

  { path = "settings.auction.auctionator", default = true, type = "boolean", widget = "CheckBox",
    group = "Auction House Price", label = "Use Auctionator",
    tooltip = "Include Auctionator in the price cascade." },
  { path = "settings.auction.priorityAuctionator", default = 1, type = "number", widget = "Dropdown",
    group = "Auction House Price", label = "Auctionator priority", options = C.AUCTION_PRIORITY_OPTIONS,
    tooltip = "Cascade position for Auctionator (1 = probed first)." },

  { path = "settings.auction.tsm", default = true, type = "boolean", widget = "CheckBox",
    group = "Auction House Price", label = "Use TSM",
    tooltip = "Include TradeSkillMaster in the price cascade." },
  { path = "settings.auction.priorityTSM", default = 2, type = "number", widget = "Dropdown",
    group = "Auction House Price", label = "TSM priority", options = C.AUCTION_PRIORITY_OPTIONS,
    tooltip = "Cascade position for TSM (1 = probed first)." },

  { path = "settings.auction.oribos", default = true, type = "boolean", widget = "CheckBox",
    group = "Auction House Price", label = "Use OribosExchange",
    tooltip = "Include OribosExchange in the price cascade." },
  { path = "settings.auction.priorityOribos", default = 3, type = "number", widget = "Dropdown",
    group = "Auction House Price", label = "OribosExchange priority", options = C.AUCTION_PRIORITY_OPTIONS,
    tooltip = "Cascade position for OribosExchange (1 = probed first)." },

}
-- NOTE: the debug LOGGING flag (NS.State.debug) is NOT a schema setting — session-only, set via
-- `/lh debug on|off`, always off after a reload. The debug CONSOLE WINDOW's visibility IS the
-- `state.debugConsole` row above: a session-only schema row (rendered in the panel, driven through
-- Schema:Get/Set) whose value lives in the DebugLog window state and is never written to db.global.

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
  if row.sessionOnly then
    -- Session-only rows (e.g. state.debugConsole) never touch db.global; the row's set() applies it.
    if row.set then row.set(value) end
  else
    S:WritePath(NS.db.global, path, deepcopy(value))
  end
  if NS.State and NS.State.debug and NS.Debug then
    NS.Debug("Set", "%s = %s", tostring(path), tostring(value))
  end
  if row.onChange then row.onChange(value) end
  return true
end

function S:Get(path)
  local row = S:FindRow(path)
  if row and row.get then return row.get() end
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
    -- Session-only rows (state.debugConsole) have no db-backed default to resolve — skip them.
    if not row.sessionOnly and S:ReadPath(g, row.path) == nil and row.default == nil then
      print("schema path missing default: " .. tostring(row.path))
    end
  end
end

-- Slash command table. Dispatch lives in Slash.lua; help is generated from this.
NS.COMMANDS = {
  { name = "show",     desc = "Open the window",       fn = function() NS.Browser:Show() end },
  { name = "hide",     desc = "Close the window",      fn = function() NS.Browser:Hide() end },
  { name = "toggle",   desc = "Toggle the window",     fn = function() NS.Browser:Toggle() end },
  { name = "config",   desc = "Open settings",         fn = function() if NS.Panel then NS.Panel:Open() end end },
  { name = "version",  desc = "Print addon version",   fn = function() NS.Slash:CliVersion() end },
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
      print("test mode " .. (on and "on" or "off"))
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
