local addonName, NS = ...
NS.Schema = NS.Schema or {}
local S = NS.Schema
local C = NS.Constants
local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer (events-frames-taint-§8)

-- The LibKa0s-Options-1.0 instance, for its SCHEMA COMPOSERS only -- no widget, no AceGUI, no
-- state: O.MasterControls is a pure function returning an array of ordinary rows (options-ui-§15).
-- settings/OptionsSetup.lua is listed ABOVE this file in LootHistory.toc precisely so it is here,
-- and on a degraded install it is the no-op stub, whose MasterControls answers no rows at all --
-- which is the same shape every other member of that stub takes (see settings/OptionsSetup.lua).
local O = NS.Options

-- ONE declaration site per shipped value (savedvariables-§2). A row's `default` READS the
-- account-wide declaration in defaults/Global.lua rather than restating the literal — the same move
-- `settings.auction.capture` already makes against core/Constants.lua. Two literals for one value is
-- exactly how the AH cascade drifted (LH-R-01); tests/test_schema.lua's "shipped default equals the
-- schema's declared default" case can only catch a drift while two things exist to compare, and it
-- now has nothing to diverge from on these rows. defaults/Global.lua loads before this file
-- (LootHistory.toc), and every value read here is a scalar, so no row aliases the shipped table.
local G = NS.defaults.global

-- One row per setting. Drives AceDB defaults, panel widgets, and slash get/set/list/reset.
-- Paths resolve against NS.db.global (account-wide), not .profile.
--
-- ── page, group, path: three different questions (options-ui-§13) ──────────────────────────────
-- `page`  names the canvas SUBCATEGORY the row is edited on. There is exactly ONE now — "General"
--         — because R6 deprecated the Filters and AH Price sub-pages into it. It is what the
--         descriptor's `rowsForPage` matches on (settings/OptionsSetup.lua).
-- `group` names the TAB within that page. settings/Panel.lua partitions the page's rows by group
--         IN DECLARATION ORDER, so the order of this array is the order of the strip and a group's
--         rows MUST be contiguous — a row filed under a group the page has already left would draw
--         its tab a second time.
-- `subgroup` names a SUBSECTION heading inside a tab, for a tab that mixes control types
--         (options-ui-§7). Unlike a group heading it is NOT suppressed under a strip.
-- `path`  is where the value is STORED, and it is allowed to disagree with both. Nothing below
--         moved paths when the tabs were designed: renaming a stored key migrates every saved
--         profile for something nobody can see.
-- Row order within a group drives the two-column pairing (consecutive rows pair two per line), and
-- `solo` breaks a row onto its own line. `wide` forces a full-width row (see settings/Panel.lua).
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
-- ── The Master controls tab (options-ui-§15) ───────────────────────────────────────────────────
--
-- COMPOSED, never hand-written. `O.MasterControls` emits the canonical eight in the canonical
-- order from one declaration, which is what stops nine addons drifting into nine orders; the tab
-- name is the literal `Master controls` and it is simultaneously the rows' `group`, the strip's
-- first label and the `afterGroup` key the closing button pair hangs off (settings/Panel.lua).
--
-- NOT `frameless`. `grep -rn "SetMovable(true)" core modules` finds two frames -- the History
-- window (modules/Browser.lua) and the export modal (modules/Export.lua) -- so every frame-only
-- row applies and none may be omitted.
--
-- `defaults` is passed for the same reason every row below reads `G.<path>`: ONE declaration site
-- per shipped value (savedvariables-§2). Without it the composer's own literals would be a second
-- copy of five defaults, and tests/test_schema.lua's shipped-equals-declared case would have
-- nothing left to compare.
local MASTER_ROWS, MASTER_AFTER_GROUP = O.MasterControls{
  prefix           = "settings.",
  page             = "General",
  addonName        = "Loot History",
  debugConsolePath = "state.debugConsole",
  defaults = {
    enabled    = G.settings.enabled,
    visibility = G.settings.visibility,
    scale      = G.settings.scale,
    alpha      = G.settings.alpha,
    locked     = G.settings.locked,
    -- Session-only, so there is nothing in defaults/Global.lua to read it from: the console is
    -- closed at every load and "closed" is `false`. Declared all the same, because a row with no
    -- default is a row `/lh reset` cannot restore and a `Schema:Default` that answers nil.
    debugConsole = false,
  },
  -- Its own button now, over the window geometry carve-out. It used to be folded into the General
  -- page's Defaults handler, where a player asking for "defaults" also got their window recentred
  -- and a player who only wanted it recentred had no way to say so.
  onResetPosition = function()
    if NS.Browser and NS.Browser.ResetWindow then NS.Browser:ResetWindow() end
  end,
  -- options-ui-§12's global reset, verbatim: the confirm-gated total reset this addon already
  -- shipped as the Maintenance tab's "Reset Everything" button. Same popup, same wording, same
  -- blast radius -- only the label and the tab moved, and both moved because the standard names
  -- them.
  onResetAll = function()
    if type(StaticPopup_Show) == "function" then
      StaticPopup_Show("KA0S_LOOTHISTORY_RESETALL")
    elseif NS.Slash and NS.Slash.ResetEverything then
      NS.Slash:ResetEverything()
    end
  end,
}

--- The composer emits DECLARATION; behaviour is still the host's.
---
--- Stamped onto the emitted rows by path rather than typed into a second hand-written copy of the
--- block, which is the whole point of composing it: `onChange` (this addon's side-effect hook),
--- `widget` (declarative, read by docs and the row inventory), `fmt` (how the slash CLI prints a
--- value) and the two session-only accessors are fields the library's composer knows nothing
--- about. A path the composer did not emit -- because a future `omit` dropped it -- simply finds
--- no row and stamps nothing.
local function stamp(rows, extras)
  for _, row in ipairs(rows) do
    local add = extras[row.path]
    if add then for k, v in pairs(add) do row[k] = v end end
  end
  return rows
end

stamp(MASTER_ROWS, {
  ["settings.enabled"] = {
    widget = "CheckBox",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "enabled") end
    end,
  },
  ["settings.visibility"] = {
    widget = "Dropdown",
    onChange = function()
      if NS.Browser and NS.Browser.ApplyVisibility then NS.Browser:ApplyVisibility() end
    end,
  },
  ["settings.scale"] = {
    widget = "Slider", fmt = "%.2fx",   -- scale → "1.00x" in slash list/get (slash-commands-§5)
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "chrome") end
    end,
  },
  ["settings.alpha"] = {
    widget = "Slider",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "chrome") end
    end,
  },
  ["settings.locked"] = {
    widget = "CheckBox",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "chrome") end
    end,
  },
  -- Session-only (never persisted): its value is the debug console WINDOW's visibility, not the
  -- NS.State.debug logging flag. get/set route to NS.DebugLog (Show/Hide/IsShown); Schema:Set skips
  -- the db.global write for sessionOnly rows. Mirrors `/lh debug` (no-arg), which toggles the
  -- window too. The composer declares the row and marks it sessionOnly; WHERE the value lives is
  -- this addon's, so the two accessors are stamped here.
  ["state.debugConsole"] = {
    widget = "CheckBox",
    get = function() return NS.DebugLog ~= nil and NS.DebugLog:IsShown() end,
    set = function(v)
      if not NS.DebugLog then return end
      if v then NS.DebugLog:Show() else NS.DebugLog:Hide() end
    end,
  },
})

--- The closing button pair's `afterGroup` hook, handed to settings/Panel.lua under the group name
--- the composer used. The GROUP NAME IS THE HOOK KEY: renaming the group detaches the hook and
--- nothing errors, which is why neither end spells the literal twice.
S.MASTER_GROUP     = O.MASTER_GROUP or "Master controls"
S.MasterAfterGroup = MASTER_AFTER_GROUP

local ROWS = {
  -- ── General ▸ Collection ──
  -- What gets recorded. The addon-wide master switch over all of it is NOT here any more: it is
  -- `settings.enabled`, and it moved to the Master controls tab where options-ui-§15 puts it.
  --
  -- Row order drives the two-column panel pairing, so declaration order IS the layout: the quality
  -- gate pairs with "Record currency" on the first line, "Exclude quest items" opens the second,
  -- and the wide source picker lands under both from `afterGroup`.
  { path = "settings.qualityThreshold", default = G.settings.qualityThreshold, type = "number", widget = "Dropdown",
    page = "General", group = "Collection", label = "Minimum quality", values = C.QUALITY_OPTIONS,
    tooltip = "Only record items at or above this quality.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "quality") end
    end },

  { path = "settings.recordCurrency", default = G.settings.recordCurrency, type = "bool", widget = "CheckBox",
    page = "General", group = "Collection", label = "Record currency",
    tooltip = "Record looted currency (Valorstones, crests, etc.) as Type=Currency rows. " ..
      "Obeys the per-source mute list; ignores the minimum-quality filter.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "currency") end
    end },

  { path = "settings.excludeQuestItems", default = G.settings.excludeQuestItems, type = "bool", widget = "CheckBox",
    page = "General", group = "Collection", label = "Exclude quest items",
    tooltip = "Skip items of the Quest type (transient quest objects).",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "questfilter") end
    end },

  -- Stored as a set of MUTED sources (excludedSources); the panel renders it inverted
  -- (invert=true) as "Record data from" so a checked box means "record this source". It is the
  -- LAST row of its group on purpose: it is full-width and host-drawn from `afterGroup`, which
  -- fires after the group's last row is flushed.
  { path = "settings.excludedSources", default = {}, type = "table", widget = "MultiCheck",
    wide = true, invert = true,
    page = "General", group = "Collection", label = "Record data from", values = C.SOURCE_OPTIONS,
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "excludes") end
    end },

  -- ── General ▸ AH Price ──
  -- Was its own canvas sub-page until R6 deprecated it into General (options-ui-§13: a Ka0s page
  -- is a strip, and three sub-pages of two tabs each is three strips a player has to find). It is
  -- a TAB now, and the tab body is still the pooled price table settings/Panel.lua draws.
  --
  -- The tab mixes a plain toggle with an eleven-row reorder table, so it carries SUBSECTION
  -- headings (options-ui-§7): both are declared by a row, never drawn by the builder, which is
  -- what keeps the tab list derivable from `group` alone.
  { path = "settings.auction.enabled", default = G.settings.auction.enabled, type = "bool",
    widget = "CheckBox",
    page = "General", group = "AH Price", subgroup = "Pricing", label = "Enable AH pricing",
    tooltip = "Gather auction-house prices at loot time from installed pricing addons." },
  -- skipRender: the tab renders this as the unified price table's per-row Enabled checkboxes
  -- (settings/Panel.lua buildAuctionTable) — `capture` is now the single collect+rank flag, not
  -- just "record". The row stays schema-backed so its default resolves and the slash CLI can still
  -- read/write it. widget/options are retained so the CLI can present it as a checklist.
  --
  -- It is also the row that DECLARES the "Price sources" heading. `startSubgroup` runs before the
  -- `skipRender` check, so a row that draws no widget still opens its subsection — which is how
  -- the table below it gets a heading without a builder drawing one (options-ui-§7).
  { path = "settings.auction.capture", default = NS.Constants.AUCTION_CAPTURE_DEFAULT, type = "table",
    widget = "MultiCheck", wide = true, skipRender = true,
    page = "General", group = "AH Price", subgroup = "Price sources",
    label = "Collect & rank these prices",
    values = NS.Constants.AUCTION_CAPTURE_OPTIONS },

  -- ── General ▸ Interface ──
  -- How much room the History window's own furniture takes, and whether the minimap button is
  -- there. The addon-WIDE size and opacity are the Master controls tab's `settings.scale` and
  -- `settings.alpha`; `settings.windowScale` below is the History window's own scale and
  -- multiplies on top of them (options-ui-§15). The two size sliders pair on one line so a reader
  -- compares them across rather than down, and the minimap toggle opens the next.
  --
  -- THE TAB CARRIES SUBSECTION HEADINGS, and the merge was considered rather than defaulted into
  -- (options-ui-§7). Its three rows are two SUBJECTS, not one: the first two size the History
  -- window, the third governs the minimap button, a different surface entirely that the window's
  -- scale and row height have no bearing on. §7's test is "a tab that mixes control types", and
  -- its own reasoning is about subjects under one label — "a player scanning it has no way to tell
  -- where one ends" — which is exactly the failure here, so `Window` and `Minimap` are declared by
  -- the rows the way `Pricing` / `Price sources` are on the AH Price tab. The tab is NOT split in
  -- two: a one-row tab for the minimap button is the second tab level §7 forbids faking, and the
  -- strip is already six wide. Neither name repeats the tab's own (§7 forbids that too).
  { path = "settings.windowScale", default = G.settings.windowScale, type = "number",
    min = 0.6, max = 1.6, step = 0.05, widget = "Slider",
    -- `step` is not decoration. `SetSliderValues(min, max, row.step or 1)` means a row with no
    -- step declares a step of ONE — on a 0.6..1.6 range that is a slider a player can only drag
    -- to its two ends. Stored values are untouched: the commit path snaps against `row.step or 0`
    -- (no snap when absent), so every scale ever saved is still reachable and still legal.
    fmt = "%.2fx",  -- scale → "1.00x" in slash list/get (slash-commands-§5 value formatting)
    page = "General", group = "Interface", subgroup = "Window", label = "Window scale",
    tooltip = "Scale of the History browser window.",
    onChange = function(v)
      if NS.Browser and NS.Browser.SetScale then NS.Browser:SetScale(v) end
    end },

  -- Promoted from `local ROW_H = 18` in modules/BrowserTable.lua. The default IS the literal it
  -- replaced, so a player who never touches it sees the table drawn exactly as it always was.
  -- Clamped on read (BrowserTable.rowHeight), because this arrives from SavedVariables and a
  -- hand-edited 400 is a table with one row on it rather than an error.
  { path = "settings.rowHeight", default = G.settings.rowHeight, type = "number",
    min = 14, max = 28, step = 1, widget = "Slider",
    fmt = "%dpx",
    page = "General", group = "Interface", subgroup = "Window", label = "Row height",
    tooltip = "Height of one row in the History table, in pixels. Lower fits more on screen.",
    onChange = function()
      if NS.BrowserTable and NS.BrowserTable.Bind then NS.BrowserTable:Bind() end
    end },

  { path = "minimap.hide", default = false, type = "bool", widget = "CheckBox",
    page = "General", group = "Interface", subgroup = "Minimap", label = "Hide minimap button",
    tooltip = "Hide the LootHistory minimap button.",
    onChange = function(v)
      if NS.Browser and NS.Browser.SetMinimapHidden then NS.Browser:SetMinimapHidden(v) end
    end },

  -- ── General ▸ Maintenance ──
  -- What is kept and how to get rid of it. Last tab because it is the one a player sets once and
  -- leaves. ONE stored row, and it is the sanctioned exemption from the two-controls-per-tab rule:
  -- the rest of the tab is bespoke — the live storage readout and "Purge history…" — controls with
  -- no path, which no partition test can count. tests/test_schema.lua exempts it BY NAME.
  -- ("Reset Everything" used to be the third; it is the Master controls tab's "Reset all settings"
  -- button now, which is where options-ui-§15 puts the global reset.)
  { path = "settings.retentionDays", default = G.settings.retentionDays, type = "number", widget = "Dropdown",
    page = "General", group = "Maintenance", label = "Keep history for", values = C.RETENTION_OPTIONS,
    tooltip = "Automatically drop records older than this. 'Never' keeps everything.",
    onChange = function()
      if NS.Database and NS.Database.PruneOld then NS.Database:PruneOld() end
    end },
}

-- ONE array, Master controls first. The composed block is spliced at the HEAD rather than declared
-- among the rows below because its group has to be the page's FIRST — the strip's order IS this
-- array's order (options-ui-§13/§15).
S.Schema = {}
for _, row in ipairs(MASTER_ROWS) do S.Schema[#S.Schema + 1] = row end
for _, row in ipairs(ROWS)        do S.Schema[#S.Schema + 1] = row end

-- NOTE: `settings.auction.priority` (the ordered cascade selection list) is a carve-out array —
-- NOT a schema row — managed directly by the settings panel UI (R6). See docs/schema.md.
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

-- Boot validation (architecture-§5): every persisted schema path must resolve against the shipped
-- defaults table. Returns the number of rows that did not — 0 on a healthy load — so a caller, and
-- tests/test_schema.lua, can assert on the result instead of reading chat.
--
-- The condition used to carry an `and row.default == nil` conjunct, which made the whole check
-- structurally dead: every shipped row declares a non-nil default (two of them declare `false`), so
-- the print could never fire and the one thing this exists to catch — a typo'd path — was reported
-- by nothing. A row's own `default` is not evidence that its PATH resolves; the two are independent
-- facts, and only the path is what AceDB and Schema:Get/Set walk. A typo'd path is now reported
-- whether or not the row carries a default.
function S:Register()
  local g = NS.defaults and NS.defaults.global
  -- defaults/Global.lua loads before this file (LootHistory.toc), so `g` is present in any loaded
  -- client; there is nothing to validate against when it is not.
  if not g then return 0 end
  local unresolved = 0
  for _, row in ipairs(S.Schema) do
    -- Session-only rows (state.debugConsole) have no db-backed path to resolve — skip them.
    if not row.sessionOnly and S:ReadPath(g, row.path) == nil then
      unresolved = unresolved + 1
      print("schema path does not resolve against defaults/Global.lua: " .. tostring(row.path))
    end
  end
  return unresolved
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
