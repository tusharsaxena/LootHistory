local _, NS = ...
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
  -- The History window is a positionable display, so it ships a test mode and this is its switch:
  -- a session-only `Test mode` checkbox on its own line below Lock frame / Debug console
  -- (options-ui-§15, preview-mode; LibKa0s compose minor 6). Verbatim, like the console path.
  testModePath     = "state.testMode",
  -- THE MINIMAP BUTTON (launcher-§3, LibKa0s compose minor 7). VERBATIM and unprefixed, like the
  -- two session paths above -- but for a different reason: those live outside the store entirely,
  -- and this one lives in the GLOBAL store, which is where launcher-§3 fixes LibDBIcon's own table.
  -- This addon has no profile at all and every schema path already resolves against `NS.db.global`,
  -- so the verbatim path is simply `minimap.hide` and the `settings.` prefix above must not reach it.
  --
  -- THE ROW SAYS SHOWN AND THE STORED KEY SAYS HIDDEN. The composer emits a stored bool defaulting
  -- to `true` labelled "Minimap button"; LibDBIcon owns the `hide` boolean underneath. The two
  -- accessors stamped below are the whole of that inversion, and they are the only ones: Schema:Get
  -- and Schema:Set are this addon's single write seam (options-ui-§1) and both honor a row's own
  -- get/set, so the panel checkbox, `/lh set`, `/lh reset` and `/lh resetall` all invert once.
  --
  -- It REPLACES the "Hide minimap button" checkbox that used to sit on General > Interface under a
  -- `Minimap` subheading. Same stored key, same table, opposite sense, canonical position.
  minimapPath      = "minimap.hide",
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
    -- Session-only too, and off at every load. `false` is what lets a reset end it: the row walk
    -- behind `/lh resetall` restores each row to this value (options-ui-§15).
    testMode = false,
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
  -- THE INVERSION, and it lives HERE rather than as a branch inside Schema:Set, because that is
  -- where every other row's behaviour is bound and because a path literal compared inside the seam
  -- is a second place to remember this row exists. Schema:Get already prefers `row.get`; Schema:Set
  -- prefers `row.set` over its own WritePath for a stored row, which is the one line the seam grew
  -- for this (see the comment there).
  --
  -- The row's boolean is SHOWN. LibDBIcon's key is HIDDEN. ONE boolean is stored -- `minimap.hide`,
  -- the library's own, which it writes too when the player uses the button's menu -- and never a
  -- `minimap.show` beside it, which would be a copy free to disagree (launcher-§3, anti-pattern #81).
  --
  -- `SetShown` writes `hide` a second time with the same value. That is the library's documented
  -- shape and it is deliberate: a caller that drives the button from somewhere else does not have
  -- to remember the inversion. The write above it is what keeps the store right on an install with
  -- no LibKa0s at all, where `NS.Launcher` is nil and there is nothing to call.
  ["minimap.hide"] = {
    widget = "CheckBox",
    get = function()
      local mm = NS.db and NS.db.global and NS.db.global.minimap
      return not (mm and mm.hide)
    end,
    set = function(shown)
      local mm = NS.db and NS.db.global and NS.db.global.minimap
      if mm then mm.hide = not shown end
      if NS.Launcher then NS.Launcher:SetShown(shown) end
    end,
  },
  -- Session-only as well: its value IS BrowserTable.testMode, never a stored key. The set switches
  -- only when the value differs and goes through BrowserTable:SetTestMode, the one switch the box,
  -- `/lh test` and the combat start share; that refreshes the panel on every start and stop, so a
  -- refused start (window not allowed on screen, or in combat) redraws the box unticked.
  ["state.testMode"] = {
    widget = "CheckBox",
    tooltip = "Fill the History window and Insights with a sample loot history, so you can see "
      .. "and place the window before you have loot of your own. Never saved. Combat ends it. "
      .. "The same as /lh test.",
    get = function() return NS.BrowserTable ~= nil and NS.BrowserTable.testMode == true end,
    set = function(v)
      local BT = NS.BrowserTable
      if not (BT and BT.SetTestMode) then return end
      if (v and true or false) ~= (BT.testMode == true) then BT:SetTestMode(v) end
    end,
  },
})

--- The closing button pair's `afterGroup` hook, handed to settings/Panel.lua under the group name
--- the composer used. The GROUP NAME IS THE HOOK KEY: renaming the group detaches the hook and
--- nothing errors, which is why neither end spells the literal twice.
S.MASTER_GROUP     = O.MASTER_GROUP or "Master controls"
S.MasterAfterGroup = MASTER_AFTER_GROUP

local ROWS = {
  -- ── General ▸ Capture ──
  -- What gets recorded. The addon-wide master switch over all of it is NOT here any more: it is
  -- `settings.enabled`, and it moved to the Master controls tab where options-ui-§15 puts it.
  --
  -- CALLED Capture, AND IT WAS CALLED Collection. Ka0s Bank Ledger names the same subject Capture
  -- and its retention tab History; the two addons keep the same shape of record and a player
  -- compares their panels directly, so one subject now carries one name across both. A tab name is
  -- a `group` and never a stored path, so this was a rename and owed no migration
  -- (options-ui-§15).
  --
  -- Row order drives the two-column panel pairing, so declaration order IS the layout: the quality
  -- gate pairs with "Record currency" on the first line, "Exclude quest items" opens the second,
  -- and the wide source picker lands under both from `afterGroup`.
  { path = "settings.qualityThreshold", default = G.settings.qualityThreshold, type = "number", widget = "Dropdown",
    page = "General", group = "Capture", label = "Minimum quality", values = C.QUALITY_OPTIONS,
    tooltip = "Only record items at or above this quality.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "quality") end
    end },

  { path = "settings.recordCurrency", default = G.settings.recordCurrency, type = "bool", widget = "CheckBox",
    page = "General", group = "Capture", label = "Record currency",
    tooltip = "Record looted currency (Valorstones, crests, etc.) as Type=Currency rows. " ..
      "Obeys the per-source mute list; ignores the minimum-quality filter.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "currency") end
    end },

  { path = "settings.excludeQuestItems", default = G.settings.excludeQuestItems, type = "bool", widget = "CheckBox",
    page = "General", group = "Capture", label = "Exclude quest items",
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
    page = "General", group = "Capture", label = "Record data from", values = C.SOURCE_OPTIONS,
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
  -- How much room the History window's own furniture takes. The addon-WIDE size and opacity are
  -- the Master controls tab's `settings.scale` and `settings.alpha`; `settings.windowScale` below
  -- is the History window's own scale and multiplies on top of them (options-ui-§15). The two size
  -- sliders pair on one line so a reader compares them across rather than down.
  --
  -- THE SUBSECTION HEADINGS ARE GONE, and their reason went with the row that caused them. The tab
  -- carried `Window` and `Minimap` because its three rows were two SUBJECTS: two that sized the
  -- History window and one that governed the minimap button, a different surface entirely
  -- (options-ui-§7). The minimap row is the Master controls tab's "Minimap button" now, where
  -- launcher-§3 and options-ui-§15 put it, so what is left is two rows of ONE subject -- and a lone
  -- `Window` heading over a tab whose every row is about the window repeats the tab's own name,
  -- which §7 forbids in as many words.
  { path = "settings.windowScale", default = G.settings.windowScale, type = "number",
    min = 0.6, max = 1.6, step = 0.05, widget = "Slider",
    -- `step` is not decoration. `SetSliderValues(min, max, row.step or 1)` means a row with no
    -- step declares a step of ONE — on a 0.6..1.6 range that is a slider a player can only drag
    -- to its two ends. Stored values are untouched: the commit path snaps against `row.step or 0`
    -- (no snap when absent), so every scale ever saved is still reachable and still legal.
    fmt = "%.2fx",  -- scale → "1.00x" in slash list/get (slash-commands-§5 value formatting)
    page = "General", group = "Interface", label = "Window scale",
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
    page = "General", group = "Interface", label = "Row height",
    tooltip = "Height of one row in the History table, in pixels. Lower fits more on screen.",
    onChange = function()
      if NS.BrowserTable and NS.BrowserTable.Bind then NS.BrowserTable:Bind() end
    end },

  -- ── General ▸ History ──
  -- What is kept and how to get rid of it. Last SCHEMA tab because it is the one a player sets once
  -- and leaves; the Filters tab that follows it on the strip declares no rows at all. Called
  -- History to match Ka0s Bank Ledger's tab of the same name and the same job — it was
  -- Maintenance, which named the chore rather than the subject. ONE stored row, and it is the sanctioned exemption from the two-controls-per-tab rule:
  -- the rest of the tab is bespoke — the live storage readout and "Purge history…" — controls with
  -- no path, which no partition test can count. tests/test_schema.lua exempts it BY NAME.
  -- ("Reset Everything" used to be the third; it is the Master controls tab's "Reset all settings"
  -- button now, which is where options-ui-§15 puts the global reset.)
  { path = "settings.retentionDays", default = G.settings.retentionDays, type = "number", widget = "Dropdown",
    page = "General", group = "History", label = "Keep history for", values = C.RETENTION_OPTIONS,
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

-- debug-logging-§10: a bulk reset through this seam is ONE [Set] line, never one per row. The
-- library brackets the walk it owns here (Slash minor 8's CliResetAll, which the Defaults button and
-- `/lh resetall` both reach) with the descriptor's bulkBegin/bulkEnd, and between the two the
-- per-row line in S:Set is muted. Validation, the write and each row's onChange still run per row.
--
-- N is counted HERE, not taken from bulkEnd's `count`. The library counts every row whose
-- applyDefault returned, which includes a row already at its default; §10's N is the rows the act
-- actually wrote, so a bracketed write is tallied only when it changes the stored value.
--
-- Depth-counted, with one tally across every level: a host act that opens its own bracket around
-- the library's still logs one line, when the depth returns to 0, and none at all if any level
-- reported a whole-profile reset (that line is the profile-event handler's).
--
-- A walk that raised part-way still logs its one line, and the line says so: any level handed a
-- non-nil `err` appends ` (stopped by an error)`, so the count is not read as a finished reset.
local bulkDepth, bulkWritten, bulkProfileReset, bulkFailed = 0, 0, false, false

--- Stored-value equality: scalars by value, the set-valued rows key by key. Public because
--- Sl:ResetEverything counts the rows its wipe changes with the same test the tally uses.
function S.SameValue(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not S.SameValue(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

--- The descriptor's `bulkBegin(act, scope)`: mute the per-row [Set] line until the matching BulkEnd.
--- The outermost level starts a fresh tally.
function S.BulkBegin()
  if bulkDepth == 0 then bulkWritten, bulkProfileReset, bulkFailed = 0, false, false end
  bulkDepth = bulkDepth + 1
end

--- The descriptor's `bulkEnd(act, scope, count, err, info)`. Closes one level; the outermost logs
--- the act once as `[Set] <act> <scope>: N rows`, N the tally above (`count` is deliberately not
--- read), with ` (stopped by an error)` appended if any level got an `err`. The library calls it
--- even when a row raised, and re-raises after it returns, so the mute cannot stick; re-raising is
--- the caller's job, not this one's. `info.profileReset` silences the line; this addon has no
--- profile and Slash never sets it. Unpaired (depth already 0) it muted nothing, so it logs nothing.
function S.BulkEnd(act, scope, _, err, info)
  if bulkDepth == 0 then return end
  if info and info.profileReset then bulkProfileReset = true end
  if err ~= nil then bulkFailed = true end
  bulkDepth = bulkDepth - 1
  if bulkDepth > 0 or bulkProfileReset then return end
  if NS.State and NS.State.debug and NS.Debug then
    NS.Debug("Set", "%s %s: %d rows%s", tostring(act), tostring(scope), bulkWritten,
      bulkFailed and " (stopped by an error)" or "")
  end
end

--- The rows NO BULK RESET may reach (launcher-§3, standard v2.54.0). Named ONCE, as data.
---
--- `minimap.hide` is a PER-INSTALLATION DISPLAY PREFERENCE, in the same class as the button
--- POSITION LibDBIcon keeps in the very same table -- not a configuration value a reset is meant to
--- walk back. Nobody has ever wanted *reset my settings* to mean *and put the button back on my
--- minimap*. §3 used to DERIVE that from scope (the table is global, *Reset all settings* is a
--- profile reset), and the derivation does not survive contact with THIS addon, twice over:
---
---   * this addon HAS NO PROFILE. Everything it stores is `db.global`, so the reset the rule
---     pointed at is the wholesale `wipeGlobal` in settings/Slash.lua -- which merges
---     `defaults/Global.lua`'s `minimap = { hide = false }` straight back over a hidden button.
---   * the General page's own **Defaults** button routes to `P:RestoreDefaults` ->
---     `Sl:CliResetAll` -> the library's row walk (settings/Panel.lua), which hands EVERY schema
---     row to `applyDefault`. It reached this row whatever the scope argument said.
---
--- So the exemption is stated as a PROPERTY, and both resets honor it: the walk below skips the row
--- while a bulk bracket is open, and `wipeGlobal` carries the stored value across its wipe.
S.RESET_EXEMPT = { ["minimap.hide"] = true }

--- The descriptor's `applyDefault(row)` -- for BOTH majors (settings/Slash.lua and
--- settings/OptionsSetup.lua hand this one function to each).
---
--- ONE place, because there are two reset walks and there must not be two policies. The veto is
--- scoped to a BULK act: `bulkDepth` is above zero for `/lh resetall` and for the page's Defaults
--- button (both reach the library's bracketed walk), and zero for `/lh reset minimap.hide`, which
--- is the player naming the row and must still work. A page-scoped walk through the Options major
--- opens the same bracket under its own scope, so it is covered without being named.
function S:ApplyDefault(row)
  if bulkDepth > 0 and S.RESET_EXEMPT[row.path] then return end
  S:Set(row.path, S:Default(row.path))
end

-- Single write seam. Panel widgets and slash `set` both route through here.
function S:Set(path, value)
  local row = S:FindRow(path)
  if not row then return false, "unknown path: " .. tostring(path) end
  if row.validate and not row.validate(value) then return false, "invalid value" end
  -- Inside a bulk bracket the per-row line is muted and the write is tallied instead, but only
  -- when it changes what is stored: §10's N is the rows the act actually wrote.
  local muted = bulkDepth > 0
  local before
  if muted then before = S:Get(path) end
  if row.sessionOnly then
    -- Session-only rows (e.g. state.debugConsole) never touch db.global; the row's set() applies it.
    if row.set then row.set(value) end
  elseif row.set then
    -- A STORED row that carries a set of its own, because the value the ROW holds and the value
    -- the STORE holds are not the same boolean. `minimap.hide` is the only one today: the row says
    -- SHOWN and LibDBIcon's key says HIDDEN (launcher-§3), so a straight WritePath of the row's
    -- value would store the inverse and the checkbox would read back the opposite of what was
    -- ticked. The row's set does the inversion, the write and the live Show/Hide in one place; the
    -- validate, the tally, the [Set] line and the onChange around it are untouched, which is what
    -- keeps this the single write seam rather than a way around it.
    row.set(value)
  else
    S:WritePath(NS.db.global, path, deepcopy(value))
  end
  if muted then
    if not S.SameValue(before, value) then bulkWritten = bulkWritten + 1 end
  elseif NS.State and NS.State.debug and NS.Debug then
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
--
-- ── THE DISABLED ADDON REFUSES A FEATURE VERB (slash-commands-§2, standard v2.54.0) ────────────
--
-- ONE GATE, AT THE ONE SEAM EVERY VERB PASSES THROUGH, and that seam is the TABLE rather than the
-- dispatcher. A guard pasted into each handler is a dozen places to forget and the next verb added
-- forgets it by default; a guard inside `Sl:OnSlash` would be one place but the WRONG one, because
-- this addon has two dispatchers — the library's, and the positional walk settings/Slash.lua falls
-- back to with no LibKa0s — and only the entries here are common to both. Wrapping the handlers as
-- the table is built gates every route into a verb, including the settings landing page's rows and
-- the suite's direct `byName.show("")` calls, and a verb declared tomorrow is gated by default.
--
-- The LIVE SET is named once, as data, and it is §2's list verbatim. It is the list from the other
-- side: a player must be able to READ AND REPAIR SETTINGS and REACH THE PANEL while the addon is
-- off — which is exactly when they are most likely to need to — and `enable` above all, or the
-- pair is one-way. `debug` and `perf` are diagnostics rather than features: the usual reason to
-- reach for either is that the addon is misbehaving. `perf` is listed although this addon does not
-- register it (performance-§12, ARCHITECTURE.md → Documented deviations): the verb stays reserved
-- here as everywhere, so re-arming the harness later is a registration and never a rename.
--
-- Everything NOT in the set is a feature verb — show/hide/toggle/test/purge, which draw, preview
-- and destroy — and answers one tagged line naming `/lh enable`, having done nothing else.
local LIVE_WHILE_DISABLED = {
  help = true, config = true, version = true, enable = true, disable = true,
  debug = true, perf = true,
  get = true, set = true, list = true, reset = true, resetall = true,
}

--- Read through the READ seam, never `db.global.settings.enabled` directly, so the verbs and the
--- Master controls checkbox can never answer from two places. Guarded because the table exists only
--- after `NS:InitDB`, and a verb reached before that is not a disabled addon — it is an unbuilt one.
local function addonIsOff()
  if not (NS.db and NS.db.global) then return false end
  return S:Get("settings.enabled") == false
end

--- Wrap every feature verb's handler once, as the table is built. The triple keeps its `name` and
--- `description`, so the help index, the landing page and every count over NS.COMMANDS are
--- untouched — only what the handler DOES changes, and only while the addon is off.
local function gateFeatureVerbs(commands)
  for _, entry in ipairs(commands) do
    local verb, run = entry[1], entry[3]
    if not LIVE_WHILE_DISABLED[verb] then
      entry[3] = function(rest)
        -- One line, and `return` before anything else: no partial work, no side effect, no second
        -- line. A case that only checks the message would pass over a verb that printed and acted.
        if addonIsOff() then return print(NS.L.SLASH_DISABLED_VERB:format(verb)) end
        return run(rest)
      end
    end
  end
  return commands
end

NS.COMMANDS = gateFeatureVerbs{
  { "show",     "Open the window",       function() NS.Browser:Show() end },
  { "hide",     "Close the window",      function() NS.Browser:Hide() end },
  { "toggle",   "Toggle the window",     function() NS.Browser:Toggle() end },
  { "config",   "Open settings",         function() if NS.Panel then NS.Panel:Open() end end },
  -- THE TWO RESERVED VERBS (slash-commands-§2). ALIASES, never a second switch: each is literally
  -- `/lh set settings.enabled <bool>` with the path filled in -- the same stored path the Master
  -- controls "Enable Loot History" checkbox writes, through the same single write seam
  -- (Schema:Set), so the row's onChange fires and the SettingsChanged fan-out reaches the Collector
  -- whichever surface was used. They hold NO state of their own: no second key, no session flag,
  -- no NS.enabled local, so the checkbox and the verbs can never show the player two answers.
  --
  -- Delegated to CliSet rather than calling Schema:Set with a hand-written acknowledgment, and that
  -- is the point rather than a shortcut. §2 sanctions the long form as "the same write by its long
  -- name"; routing the short form through it means the confirmation line is slash-commands-§5's
  -- `set` shape by construction, re-read from the store rather than echoed back, and there is no
  -- second spelling of this write anywhere in the addon to drift from.
  --
  -- THE DISPATCHER SURVIVES THE DISABLED STATE, which is what stops the pair being one-way. Nothing
  -- in this addon gates dispatch on `settings.enabled`: Sl:Register runs from OnInitialize
  -- unconditionally, the chat command is never unregistered, and the only reader of the flag is
  -- modules/Collector.lua's capture gate. So `/lh`, `/lh enable`, `/lh help`, `/lh config` and
  -- `/lh version` all answer with the addon off. tests/test_slash.lua pins it.
  { "enable",   "Enable the addon",      function() NS.Slash:CliSet("settings.enabled true") end },
  { "disable",  "Disable the addon",     function() NS.Slash:CliSet("settings.enabled false") end },
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
      -- The same switch as the Master controls `Test mode` box. A refused start prints its own one
      -- line, so this one prints only when the mode actually switched.
      local BT = NS.BrowserTable
      if not (BT and BT.ToggleTestMode) then return end
      local on, switched = BT:ToggleTestMode()
      if switched then print("test mode " .. (on and "on" or "off")) end
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
