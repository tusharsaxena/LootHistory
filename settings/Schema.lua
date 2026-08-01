local addonName, NS = ...
NS.Schema = NS.Schema or {}
local S = NS.Schema
local C = NS.Constants
local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer (events-frames-taint-§8)

-- One row per setting. Drives AceDB defaults, panel widgets, and slash get/set/list/reset.
-- Paths resolve against NS.db.global (account-wide), not .profile.
-- `group` names the panel section header; row order within a group drives the
-- two-column pairing. `wide` forces a full-width row (see settings/Panel.lua).
--
-- ── The row vocabulary is LibKa0s's ────────────────────────────────────────────────────────────
-- `LibKa0s-Slash-1.0` and `LibKa0s-Options-1.0` read a FIXED set of row fields, and an unmapped one
-- is not an error — it is a row that silently vanishes from a page, or a `set` that answers
-- ERR_TYPE. Four names moved when this addon adopted them, and none of the four would have failed
-- loudly:
--   type = "boolean" -> "bool"       the makers and the parser dispatch on "bool"
--   options          -> values       and each entry's `label` is now `text` (core/Constants.lua)
--   soloRow          -> solo         render alone in the left half of its own line
--   panelSkip        -> skipRender   keep the row in the schema, let the host draw it bespoke
-- `tooltip` deliberately did NOT move: the library reads `tooltip` first and its own `desc` second.
-- `widget`, `wide`, `invert`, `sessionOnly`, `fmt`, `get`, `set` and `onChange` stay this addon's.
S.Schema = {
  -- ── Master Controls ──
  { path = "settings.enabled", default = true, type = "bool", widget = "CheckBox",
    group = "Master Controls", label = "Enable collection",
    tooltip = "Master switch for recording looted items.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "enabled") end
    end },

  { path = "minimap.hide", default = false, type = "bool", widget = "CheckBox",
    group = "Master Controls", label = "Hide minimap button",
    tooltip = "Hide the LootHistory minimap button.",
    onChange = function(v)
      if NS.Browser and NS.Browser.SetMinimapHidden then NS.Browser:SetMinimapHidden(v) end
    end },

  -- Session-only row (never persisted): its value is the debug console WINDOW's visibility, not the
  -- NS.State.debug logging flag. get/set route to NS.DebugLog (Show/Hide/IsShown); Schema:Set skips
  -- the db.global write for sessionOnly rows. `solo` puts it on its own panel row (below the
  -- Enable / Hide-minimap pair). Mirrors `/lh debug` (no-arg), which toggles the window too.
  { path = "state.debugConsole", sessionOnly = true, default = false, type = "bool",
    widget = "CheckBox", solo = true, group = "Master Controls", label = "Debug console",
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
    group = "Data Collection", label = "Minimum quality", values = C.QUALITY_OPTIONS,
    tooltip = "Only record items at or above this quality.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "quality") end
    end },

  -- Row order drives the two-column panel pairing: the two dropdowns (Minimum quality | Keep history
  -- for) pair on the top line, the two checkboxes (Record currency | Exclude quest items) below.
  { path = "settings.retentionDays", default = 30, type = "number", widget = "Dropdown",
    group = "Data Collection", label = "Keep history for", values = C.RETENTION_OPTIONS,
    tooltip = "Automatically drop records older than this. 'Never' keeps everything.",
    onChange = function()
      if NS.Database and NS.Database.PruneOld then NS.Database:PruneOld() end
    end },

  { path = "settings.recordCurrency", default = true, type = "bool", widget = "CheckBox",
    group = "Data Collection", label = "Record currency",
    tooltip = "Record looted currency (Valorstones, crests, etc.) as Type=Currency rows. " ..
      "Obeys the per-source mute list; ignores the minimum-quality filter.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "currency") end
    end },

  { path = "settings.excludeQuestItems", default = true, type = "bool", widget = "CheckBox",
    group = "Data Collection", label = "Exclude quest items",
    tooltip = "Skip items of the Quest type (transient quest objects).",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "questfilter") end
    end },

  -- Stored as a set of MUTED sources (excludedSources); the panel renders it inverted
  -- (invert=true) as "Record data from" so a checked box means "record this source".
  { path = "settings.excludedSources", default = {}, type = "table", widget = "MultiCheck",
    wide = true, invert = true,
    group = "Data Collection", label = "Record data from", values = C.SOURCE_OPTIONS,
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "excludes") end
    end },

  -- ── AH Price ──  (own settings sub-page; see settings/Panel.lua)
  { path = "settings.auction.enabled", default = true, type = "bool", widget = "CheckBox",
    group = "AH Price", label = "Enable AH pricing",
    tooltip = "Gather auction-house prices at loot time from installed pricing addons." },
  -- skipRender: the AH Price sub-page renders this as the unified price table's per-row Enabled
  -- checkboxes (settings/Panel.lua buildAuctionTable) — `capture` is now the single collect+rank
  -- flag, not just "record". The row stays schema-backed so its default resolves and the slash CLI
  -- can still read/write it. widget/options are retained so the CLI can present it as a checklist.
  { path = "settings.auction.capture", default = NS.Constants.AUCTION_CAPTURE_DEFAULT, type = "table",
    widget = "MultiCheck", wide = true, skipRender = true, group = "AH Price", label = "Collect & rank these prices",
    values = NS.Constants.AUCTION_CAPTURE_OPTIONS },

}
-- NOTE: `settings.auction.priority` (the ordered cascade selection list) is a carve-out array —
-- NOT a schema row — managed directly by the settings panel UI (R6). See docs/saved-variables.md.
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

-- Slash command table. Dispatch lives in Slash.lua; the chat help and the settings landing page are
-- both generated from this one table.
--
-- POSITIONAL triples — { name, description, handler } — because that is the shape
-- `LibKa0s-Slash-1.0` reads. The table stays the HOST's and is passed in rather than owned, which is
-- the load-bearing decision in that module: the settings landing page renders these same rows, and
-- if the library owned the table the options major would have to resolve the slash major to read
-- it, which is a real dependency cycle between two majors at load time. Crossing between them as
-- plain data is what keeps them independent.
--
-- The handler takes the rest of the line verbatim (never a `self`), so the seven verbs that are
-- genuinely this addon's — show/hide/toggle/config/debug/test/purge — never leave the host and
-- adopting the library cannot break them.
NS.COMMANDS = {
  { "show",     "Open the window",       function() NS.Browser:Show() end },
  { "hide",     "Close the window",      function() NS.Browser:Hide() end },
  { "toggle",   "Toggle the window",     function() NS.Browser:Toggle() end },
  { "config",   "Open settings",         function() if NS.Panel then NS.Panel:Open() end end },
  { "version",  "Print addon version",   function() NS.Slash:CliVersion() end },
  { "get",      "Get a setting value",   function(a) NS.Slash:CliGet(a) end },
  { "set",      "Set a setting value",   function(a) NS.Slash:CliSet(a) end },
  { "list",     "List all settings",     function() NS.Slash:CliList() end },
  { "reset",    "Reset one setting",     function(a) NS.Slash:CliReset(a) end },
  { "resetall", "Reset all settings",    function() NS.Slash:CliResetAll() end },
  { "debug",    "Toggle window; 'on'/'off' set logging", function(rest)
      -- `/lh debug` toggles the window only (state untouched); `/lh debug on|off` sets the
      -- session-only logging flag via the DebugLog seam. Logging runs even with the window closed.
      local arg = rest and tostring(rest):lower():match("^%s*(%S*)") or ""
      if not NS.DebugLog then return end
      if arg == "on" then NS.DebugLog:SetEnabled(true)
      elseif arg == "off" then NS.DebugLog:SetEnabled(false)
      else NS.DebugLog:Toggle() end
    end },
  { "test", "Toggle a synthetic preview dataset (table + Insights)", function()
      local on = NS.BrowserTable and NS.BrowserTable.ToggleTestMode and NS.BrowserTable:ToggleTestMode()
      print("test mode " .. (on and "on" or "off"))
    end },
  { "purge", "Delete ALL loot history (asks to confirm)", function()
      if type(StaticPopup_Show) == "function" then
        StaticPopup_Show("KA0S_LOOTHISTORY_PURGE")
      elseif NS.Database and NS.Database.Purge then
        NS.Database:Purge()
      end
    end },
  { "help",     "Show this help",        function() NS.Slash:PrintHelp() end },
}
