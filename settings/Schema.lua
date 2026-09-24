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
  -- This addon has no profile at all, so the verbatim path sits beside `settings.` rather than
  -- under it, and the `settings.` prefix above must not reach it.
  --
  -- THE ROW PATH IS `minimap.shown`; THE ONE STORED KEY IS `minimap.hide` (launcher-§3, standard
  -- v2.65.0). The CLI path reads in the row's own sense -- `/lh get minimap.shown` answers whether
  -- the button is shown -- while LibDBIcon owns the `hide` boolean underneath, and no `shown` key is
  -- ever stored (anti-pattern #81). The composer emits a bool defaulting to `true` labeled
  -- "Minimap button". The two accessors stamped below are the whole of that inversion, and they are
  -- the only ones: Schema:Get and Schema:Set are this addon's single write seam (options-ui-§1) and
  -- both honor a row's own get/set, so the panel checkbox, `/lh set`, `/lh reset` and `/lh resetall`
  -- all invert once. A row that owns its storage this way is skipped by Register's defaults check.
  --
  -- It REPLACES the "Hide minimap button" checkbox that used to sit on General > Interface under a
  -- `Minimap` subheading. Same stored key, same table, opposite sense, canonical position.
  minimapPath      = "minimap.shown",
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
  -- page's Defaults handler, where a player asking for "defaults" also got their window recentered
  -- and a player who only wanted it recentered had no way to say so.
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

--- The composer emits DECLARATION; behavior is still the host's.
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
  -- THE ADDON-WIDE SWITCH, and its onChange is where "disabled" stops being a flag somebody reads
  -- and becomes the addon actually standing down (slash-commands-§7). `/lh enable`, `/lh disable`,
  -- `/lh set settings.enabled <bool>` and this checkbox are one write through one seam, so they all
  -- arrive here and there is no second route that skips the latch.
  --
  -- THE LATCH, NOT A BARE STAND-UP: NS.OnEnabledChanged takes or releases the `disabled` HOLD and
  -- lets the latch decide whether that was an edge. A direct StandUp here would resurrect the addon
  -- mid-capture the moment a second hold existed, which is the trap the latch was built for.
  --
  -- The bus message still goes out, and it is not redundant: it is how the hot-path upvalues in
  -- modules/Collector.lua and the Browser's chrome follow a settings write, and `enabled` is a
  -- settings write like any other. It fires SECOND, so a stand-up has rebuilt the subscriptions
  -- before the fan-out reaches them.
  ["settings.enabled"] = {
    widget = "CheckBox",
    onChange = function()
      NS.OnEnabledChanged()
      if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "enabled") end
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
      if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "chrome") end
    end,
  },
  ["settings.alpha"] = {
    widget = "Slider",
    onChange = function()
      if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "chrome") end
    end,
  },
  ["settings.locked"] = {
    widget = "CheckBox",
    onChange = function()
      if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "chrome") end
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
  -- where every other row's behavior is bound and because a path literal compared inside the seam
  -- is a second place to remember this row exists. The seam (LibKa0s-Schema-1.0, and the host stub
  -- below) reads a path row's own `get`, and hands a path row's own `set` the value instead of
  -- writing it at the path, so the inversion happens once for every entry into the seam.
  --
  -- The row's path and boolean are SHOWN (`minimap.shown`). LibDBIcon's key is HIDDEN. ONE boolean
  -- is stored -- `minimap.hide`, the library's own, which it writes too when the player uses the
  -- button's menu -- and no `shown` key is ever stored beside it: the row path names the sense, not
  -- a key, and a stored copy would be free to disagree (launcher-§3, anti-pattern #81).
  --
  -- `SetShown` writes `hide` a second time with the same value. That is the library's documented
  -- shape and it is deliberate: a caller that drives the button from somewhere else does not have
  -- to remember the inversion. The write above it is what keeps the store right on an install with
  -- no LibKa0s at all, where `NS.Launcher` is nil and there is nothing to call.
  ["minimap.shown"] = {
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
      if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "quality") end
    end },

  { path = "settings.recordCurrency", default = G.settings.recordCurrency, type = "bool", widget = "CheckBox",
    page = "General", group = "Capture", label = "Record currency",
    tooltip = "Record looted currency (Valorstones, crests, etc.) as Type=Currency rows. " ..
      "Obeys the per-source mute list; ignores the minimum-quality filter.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "currency") end
    end },

  { path = "settings.excludeQuestItems", default = G.settings.excludeQuestItems, type = "bool", widget = "CheckBox",
    page = "General", group = "Capture", label = "Exclude quest items",
    tooltip = "Skip items of the Quest type (transient quest objects).",
    onChange = function()
      if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "questfilter") end
    end },

  -- Stored as a set of MUTED sources (excludedSources); the panel renders it inverted
  -- (invert=true) as "Record data from" so a checked box means "record this source". It is the
  -- LAST row of its group on purpose: it is full-width and host-drawn from `afterGroup`, which
  -- fires after the group's last row is flushed.
  { path = "settings.excludedSources", default = {}, type = "table", widget = "MultiCheck",
    wide = true, invert = true,
    page = "General", group = "Capture", label = "Record data from", values = C.SOURCE_OPTIONS,
    onChange = function()
      if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "excludes") end
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
    -- Confirm-gated when it would delete anything: S:OnRetentionChanged, below.
    onChange = function(value) S:OnRetentionChanged(value) end },
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

-- ── The seam: LibKa0s-Schema-1.0 (architecture-§5, debug-logging-§10) ──────────────────────────
--
-- The runtime behind these rows is the library's: the row registry, the path walks, the single
-- write seam, the bulk bracket and the boot check. What stays here is the DESCRIPTOR -- where a
-- stored row lives, how a line is logged, which row a sweep spares, this addon's refusal words --
-- and the host's own public names, each a one-line delegate, so no call site moved. The panel, the
-- CLI, both descriptors (settings/OptionsSetup.lua, settings/Slash.lua) and the suites all still
-- call NS.Schema:Set / :Get / :FindRow / :Default / :ApplyDefault / .BulkBegin / .BulkEnd.
--
-- THE ORDER OF ONE WRITE is the library's contract, and it is the order this seam always had:
-- refuse an unknown path; validate; store (a row's own `set` with the value as given; nothing for
-- a bare sessionOnly row; otherwise a deep COPY at the path under db.global, so a reset can never
-- alias the shared default table); inside a bracket, tally; outside one, the `[Set] <path> =
-- <value>` line; then the row's onChange. No `format` is handed over, so the line prints
-- `tostring(value)` exactly as it did, and no `announce`: each row's onChange sends its own
-- SettingsChanged reason.
--
-- A BULK RESET IS ONE LINE (§10): the Defaults button and `/lh resetall` reach the Slash major's
-- bracketed CliResetAll, the per-row line is muted inside the bracket, and the outermost BulkEnd
-- logs `[Set] <act> <scope>: N rows`, N being the rows whose READ-BACK value moved -- never the
-- library's `count`, which includes rows already at their default. A walk that raised part-way
-- still logs its line, marked ` (stopped by an error)`.

--- The rows NO BULK RESET may reach (launcher-§3, standard v2.54.0). Named ONCE, as data.
---
--- The minimap button's visibility is a PER-INSTALLATION DISPLAY PREFERENCE, in the same class
--- as the button POSITION LibDBIcon keeps in the very same table -- not a configuration value a
--- reset is meant to walk back. Nobody has ever wanted *reset my settings* to mean *and put the button back on my
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
--- So the exemption is stated as a PROPERTY, and both resets honor it: the seam's ApplyDefault
--- skips the row while a bulk bracket is open (the descriptor's `resetExempt` below), and
--- `wipeGlobal` carries the stored value across its wipe. ONE table, read by both: a single
--- `/lh reset minimap.shown` opens no bracket, so the player naming the row still resets it.
---
--- A MAP FROM ROW PATH TO STORED PATH (launcher-§3, standard v2.65.0). The row is `minimap.shown`
--- and the one stored key is `minimap.hide`, so the two resets read opposite sides: the KEYS are
--- what the library's `resetExempt` veto and traceSettingsReset test a row's path against, and the
--- VALUES are what wipeGlobal's raw read and write-back carry. No `shown` key is ever stored.
S.RESET_EXEMPT = { ["minimap.shown"] = "minimap.hide" }

-- ── The degradation stub ───────────────────────────────────────────────────────────────────────
--
-- WRITE-COMPLETING AND LOG-SILENT (LibKa0s docs/api/Schema/version-2-docs.md, "The degradation
-- stub"; this stub mirrors Schema minor 2). This major is reached by the feature runtime (core/LifecycleSetup.lua's enable switch,
-- BrowserTable's row height) and by host writers that need no other major (Reset all settings'
-- wipe, below in settings/Slash.lua). So without the library, reads, writes, the row's reaction and
-- the sweep veto all still work. The [Set] line and the bracket's tally are not reproduced, because
-- the degraded DebugLog stub discards every line they would feed.
--
-- Minor 2's three additions, as the library has them:
--   * `writeThrough`: the descriptor's list of paths stored WITHOUT a row. The stub reads the same
--     list at `New`, once, into one synthetic `{ path = , writeThrough = true }` per path. A listed
--     path with no row resolves the root (refusing "nowhere to store" without one) and is stored as
--     a copy, with no validate and no onChange; a path that HAS a row always takes the row, and any
--     other row-less path is still "unknown path". This is what lets `settings.enabled` land on this
--     very load, where the Options stub's MasterControls composer is hollow and emits no row.
--   * `SetMany`: the all-or-nothing batch. Every entry is prepared (row or writeThrough path, then
--     validate, then the root) before anything is stored, and the first refusal answers
--     `false, err, nil, index`; then every store, then every onChange. `opts.act` brackets the
--     stores and reactions, so ApplyDefault's sweep veto sees the batch as a sweep.
--   * The instance id: `Get(path, instanceId)` hands it to `row.get`, and `ApplyDefault(row,
--     instanceId)` forwards it to `Set`. Every row in this addon ignores it.
--
-- THIS IS A DELIBERATE, DOCUMENTED DUPLICATION of the library's seam, trimmed from its reference
-- stub (LibKa0s tests/test_schema.lua, `referenceStub`), with refusals in this addon's own words.
-- It runs only when the payload is missing. One difference from the reference, on purpose:
-- `Validate` is the real resolution walk, silent on a healthy schema, rather than "0, 0, 0 and one
-- line". Before the adoption the degraded boot ran this addon's own check and printed nothing, and
-- a new chat line on every degraded login would be a change the player sees.
-- tests/test_surface_parity.lua pins this stub against a live instance and by name.
local function hostSchemaStub()
  local stubLib = {}
  local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
  end
  function stubLib.SplitPath(path)
    local parts = {}
    if path ~= nil then
      for seg in tostring(path):gmatch("[^%.]+") do parts[#parts + 1] = seg end
    end
    return parts
  end
  local function partsOf(p) return type(p) == "table" and p or stubLib.SplitPath(p) end
  function stubLib.Read(root, p, first)
    local parts, node = partsOf(p), root
    first = first or 1
    if type(root) ~= "table" or #parts < first then return nil end
    for i = first, #parts do
      if type(node) ~= "table" then return nil end
      node = node[parts[i]]
    end
    return node
  end
  function stubLib.Write(root, p, value, first)
    local parts, node = partsOf(p), root
    first = first or 1
    if type(root) ~= "table" or #parts < first then return end
    for i = first, #parts - 1 do
      if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
      node = node[parts[i]]
    end
    node[parts[#parts]] = value
  end
  function stubLib.SameValue(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if not stubLib.SameValue(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
  end

  function stubLib:New(d)
    local R, depth = {}, 0
    local rows = d.rows
    -- writeThrough, read once: a later edit to the descriptor's list changes nothing, as in the
    -- library. The synthetic row has no set, validate or onChange, so `prepare` below needs no
    -- branch of its own for it: it is a stored row that nothing validates and nothing reacts to.
    local through = {}
    for _, p in ipairs(type(d.writeThrough) == "table" and d.writeThrough or {}) do
      if type(p) == "string" and p ~= "" then through[p] = { path = p, writeThrough = true } end
    end
    local function say(line) if type(d.print) == "function" then d.print(line) end end
    function R.AllRows() return rows end
    function R.FindRow(path)
      if type(path) ~= "string" then return nil end
      for _, row in ipairs(rows) do
        if type(row) == "table" and row.path == path then return row end
      end
    end
    function R.AddRows(list, at)
      if type(list) ~= "table" then return 0 end
      at = type(at) == "number" and math.floor(at) or #rows + 1
      if at > #rows + 1 then at = #rows + 1 elseif at < 1 then at = 1 end
      for i, row in ipairs(list) do table.insert(rows, at + i - 1, row) end
      return #list
    end
    function R.Reindex() end
    function R.Get(path, instanceId)
      local row = R.FindRow(path)
      if row and type(row.get) == "function" then return row.get(instanceId) end
      if type(path) ~= "string" or (row and row.sessionOnly) then return nil end
      local root, first = d.resolveRoot()
      if type(root) ~= "table" then return nil end
      return stubLib.Read(root, path, first)
    end
    -- The seam's order without its log and tally: refuse, validate, store, react. `prepare` is
    -- every check before the store, shared with SetMany so a batch refuses on exactly the rules a
    -- single write does (the library's own prepareWrite split). It answers `true, plan` or
    -- `false, err` with nothing called but the row's validate.
    local function prepare(path, value)
      local row = R.FindRow(path) or (type(path) == "string" and through[path]) or nil
      if not row then return false, "unknown path: " .. tostring(path) end
      local stored = type(row.set) ~= "function" and not row.sessionOnly
      local root, first
      if stored then root, first = d.resolveRoot() end
      if type(row.validate) == "function" and not row.validate(value) then
        return false, "invalid value"
      end
      if stored and type(root) ~= "table" then return false, "nowhere to store " .. path end
      return true, { row = row, path = path, value = value, stored = stored, root = root, first = first }
    end
    local function store(p)
      if type(p.row.set) == "function" then
        p.row.set(p.value)
      elseif p.stored then
        stubLib.Write(p.root, p.path, copy(p.value), p.first)
      end
    end
    local function react(p)
      if type(p.row.onChange) == "function" then p.row.onChange(p.value) end
    end
    -- The library's third argument, `instanceId`, is dropped: no row in this addon reads one.
    function R.Set(path, value)
      local ok, plan = prepare(path, value)
      if not ok then return false, plan end
      store(plan)
      react(plan)
      return true
    end
    -- Schema minor 2's all-or-nothing batch, log-silent (version-2-docs.md, "The batch: SetMany").
    -- Phase 1 prepares every entry and refuses with `false, err, nil, index` before any store;
    -- then every store, then every onChange, so a reaction reading a sibling row sees the whole
    -- batch. `opts.act` brackets both, so the sweep veto sees the bracket.
    function R.SetMany(entries, opts)
      if type(entries) ~= "table" then entries = {} end
      if type(opts) ~= "table" then opts = {} end
      local plans = {}
      for i, e in ipairs(entries) do
        local ok, plan = false, "unknown path: " .. tostring(e)
        if type(e) == "table" then ok, plan = prepare(e.path, e.value) end
        if not ok then return false, plan, nil, i end
        plans[i] = plan
      end
      local function commit()
        for _, p in ipairs(plans) do store(p) end
        for _, p in ipairs(plans) do react(p) end
      end
      if opts.act ~= nil then R.BulkRun(opts.act, opts.scope, commit) else commit() end
      return true
    end
    function R.Default(path)
      local row = R.FindRow(path)
      return row and copy(row.default)
    end
    function R.ApplyDefault(row, instanceId)
      if type(row) ~= "table" or type(row.path) ~= "string" or row.default == nil then return false end
      if depth > 0 and d.resetExempt[row.path] then return false end
      return R.Set(row.path, copy(row.default), instanceId)
    end
    -- The bracket keeps its depth, because the sweep veto above reads it; it counts nothing.
    function R.BulkBegin() depth = depth + 1 end
    function R.BulkEnd() if depth > 0 then depth = depth - 1 end end
    function R.BulkRun(act, scope, fn)
      R.BulkBegin(act, scope)
      local ok, err = pcall(fn, { profileReset = false })
      R.BulkEnd(act, scope)
      if not ok then error(err, 0) end
    end
    function R.BulkAdd() end
    function R.InBulk() return depth > 0 end
    function R.CountOffDefault() return 0 end
    function R.ResetCounted(fn) fn() end
    function R.ConsumeResetCount() return nil end
    -- The resolution walk only, in this addon's words (see the header for why it is not silent-0).
    -- A root that is not a table skips the row, as the library's resolvesInDefaults does: that is
    -- defaultsRoot saying the row owns its storage (the Minimap button row, see S:Register).
    function R.Validate(spec)
      local resolved, missing = 0, 0
      for _, row in ipairs(rows) do
        local root, first
        if type(row) == "table" and type(row.path) == "string" and not row.sessionOnly then
          root, first = spec.defaultsRoot(nil, row)
        end
        if type(root) == "table" then
          if stubLib.Read(root, row.path, first) ~= nil then
            resolved = resolved + 1
          else
            missing = missing + 1
            say("schema path does not resolve against defaults/Global.lua: " .. row.path)
          end
        end
      end
      return 0, resolved, missing
    end
    return R
  end
  return stubLib
end

-- The silent flag: a seam whose purpose is to degrade must not raise on the install it degrades on.
local SchemaLib = LibStub and LibStub("LibKa0s-Schema-1.0", true) or hostSchemaStub()
NS.SchemaLib = SchemaLib

--- The runtime instance. Dot-called closures; the host names below are what the addon calls.
local R = SchemaLib:New{
  -- Held by reference, never copied: the Options and Slash descriptors walk this same array.
  rows         = S.Schema,
  -- Every stored path in this addon lives in the ACCOUNT-WIDE store; there is no profile. Answers
  -- `nil, 1` before InitDB, which the seam reads as "nowhere, now" and refuses rather than raising.
  resolveRoot  = function() return NS.db and NS.db.global, 1 end,
  -- Late-bound, so the sink core/DebugLogSetup.lua publishes (and a suite's stand-in) is the one
  -- called, and asked BEFORE a line is formatted, exactly as the old seam's guard was.
  debug        = function(tag, fmt, ...) if NS.Debug then NS.Debug(tag, fmt, ...) end end,
  debugEnabled = function() return NS.State ~= nil and NS.State.debug and NS.Debug ~= nil end,
  -- Validate's line sink. Late-bound, so it survives core/LootHistory.lua's AceConsole reclaim.
  print        = function(line) NS.Print(line) end,
  resetExempt  = S.RESET_EXEMPT,
  -- Paths the seam stores WITHOUT a row (Schema minor 2; options-ui-§1 route (a)). Data only: no
  -- row, label, default or validate. On a full load the Master controls composer declares
  -- `settings.enabled` and a write takes that row (validate, onChange, the latch). On a load where
  -- the Options stub's composer is hollow there is no row, and this list is what lets the host's
  -- enable/disable write still land, raw and with no reaction, instead of "unknown path".
  writeThrough = { "settings.enabled" },
  -- This addon's refusal words, which callers and tests/test_schema.lua read back. A plain table:
  -- the library reads it with rawget, and NS.L here would mask nothing but is still the wrong table.
  L            = { NOT_FOUND = "unknown path: %s", INVALID = "invalid value" },
}
NS.SchemaRuntime = R

-- ── The host's names, bound to the runtime ─────────────────────────────────────────────────────

function S:FindRow(path) return R.FindRow(path) end
function S:Get(path) return R.Get(path) end
function S:Default(path) return R.Default(path) end
-- Single write seam. Panel widgets and slash `set` both route through here.
function S:Set(path, value) return R.Set(path, value) end
--- The descriptor's `applyDefault(row)` for BOTH majors. The sweep veto is the runtime's, reading
--- S.RESET_EXEMPT through `resetExempt`, so the two reset walks share one policy.
function S:ApplyDefault(row) return R.ApplyDefault(row) end
--- The descriptors' `bulkBegin(act, scope)` / `bulkEnd(act, scope, count, err, info)`.
S.BulkBegin = R.BulkBegin
S.BulkEnd   = R.BulkEnd

-- The path primitives, for the one host caller that must go under the seam: Reset all settings'
-- wipe (settings/Slash.lua) carries the exempt row's raw stored value across `wipeGlobal`.
function S:ReadPath(root, path) return SchemaLib.Read(root, path) end
function S:WritePath(root, path, value) SchemaLib.Write(root, path, value) end
--- Stored-value equality, read by Sl:ResetEverything's settings-reset count.
S.SameValue = SchemaLib.SameValue

-- ── Keep history for: confirm before a shorter retention deletes (LootHistory-R-04) ──────────
--
-- The write still goes through Schema:Set first (architecture-§5); what the row's onChange no
-- longer does is prune on the spot. It counts what the new value would drop and, when that is
-- anything, raises KA0S_LOOTHISTORY_PRUNE (settings/Slash.lua) naming the count. Yes prunes. No
-- writes the last CONFIRMED value back through Schema:Set, so the stored retention -- which the
-- login prune (core/LootHistory.lua) reads -- never holds a value the player refused. With no
-- StaticPopup_Show (headless) it prunes at once, as it always did.
--
-- `confirmedRetention` is the stored value the player last agreed to: seeded from the store by
-- SyncRetention (addon:OnInitialize, and Sl:ResetEverything, whose raw wipe fires no onChange),
-- and moved only by a change that deleted nothing or a confirm that was accepted. `restoring`
-- keeps the decline's own write-back from raising a second confirm.
local confirmedRetention, restoring = nil, false

local function retentionLabel(days)
  for _, opt in ipairs(C.RETENTION_OPTIONS) do
    if opt.value == days then return opt.text end
  end
  return tostring(days) .. " days"
end

--- Seed the confirmed retention from the store. Call after anything that writes the row raw.
function S:SyncRetention()
  local s = NS.db and NS.db.global and NS.db.global.settings
  confirmedRetention = s and s.retentionDays
end

--- The row's onChange. Prunes only once the player has confirmed, or when nothing can ask.
function S:OnRetentionChanged(value)
  if restoring then return end
  local n = NS.Database and NS.Database.CountOlderThan and NS.Database:CountOlderThan(value) or 0
  if n == 0 then confirmedRetention = value; return end
  if type(StaticPopup_Show) ~= "function" then
    if NS.Database.PruneOld then NS.Database:PruneOld() end
    confirmedRetention = value
    return
  end
  StaticPopup_Show("KA0S_LOOTHISTORY_PRUNE", retentionLabel(value), n, { days = value })
end

--- Write `days` through the seam without re-entering OnRetentionChanged, then redraw the panel.
local function writeRetentionQuietly(days)
  restoring = true
  local ok, err = pcall(S.Set, S, "settings.retentionDays", days)
  restoring = false
  if not ok then error(err, 0) end
  if NS.Panel and NS.Panel.Refresh then NS.Panel:Refresh() end
end

--- KA0S_LOOTHISTORY_PRUNE's two answers. Accept stores the value the player agreed to (the store
--- may have moved while the popup was open) and prunes to it; decline restores the last confirmed
--- one through the write seam and says so in one line.
function S:ConfirmRetention(days, accepted)
  if accepted then
    local s = NS.db and NS.db.global and NS.db.global.settings
    if s and s.retentionDays ~= days then writeRetentionQuietly(days) end
    if NS.Database and NS.Database.PruneOld then NS.Database:PruneOld() end
    confirmedRetention = days
    return
  end
  local keep = confirmedRetention
  if keep == nil then keep = G.settings.retentionDays end
  writeRetentionQuietly(keep)
  print(("retention kept at %s; no records were deleted."):format(retentionLabel(keep)))
end

--- The row shapes this addon ships. The library's default set is the four Options widget types;
--- `table` is this addon's own set-valued type (the two MultiCheck rows).
local VALIDATE_TYPES = { bool = true, number = true, string = true, color = true, table = true }

-- Boot validation (architecture-§5): every row well-formed (options-ui-§13's `group`, a known
-- `type`, no path declared twice) and every persisted path resolving against the shipped defaults.
-- Returns the number of problems -- 0 on a healthy load -- so a caller, and tests/test_schema.lua,
-- can assert on the result instead of reading chat. A row's own `default` is not evidence that its
-- PATH resolves; only the path is what AceDB and the seam walk, so a typo'd path is reported whether
-- or not the row carries a default.
function S:Register()
  local g = NS.defaults and NS.defaults.global
  -- defaults/Global.lua loads before this file (LootHistory.toc), so `g` is present in any loaded
  -- client; there is nothing to validate against when it is not.
  if not g then return 0 end
  -- A row carrying BOTH its own get and set owns its storage, so there is no defaults entry at its
  -- path to find: `minimap.shown` reads and writes LibDBIcon's `minimap.hide`, and no `shown` key is
  -- declared or stored (launcher-§3, anti-pattern #81). Answering nil makes the library's
  -- resolvesInDefaults answer nil too -- neither resolved nor missing -- and the stub skips it alike.
  local errors, _, missing = R.Validate{
    types = VALIDATE_TYPES,
    defaultsRoot = function(_, row)
      if row and type(row.get) == "function" and type(row.set) == "function" then return nil end
      return g, 1
    end,
  }
  return errors + missing
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
-- ── THE DISABLED ADDON REFUSES A FEATURE VERB (slash-commands-§2, restored at v2.57.0) ─────────
--
-- THE SURFACE IS NOT NARROWED, and that is the ruling rather than an omission. The standard cut the
-- disabled surface to `enable` and `help` at v2.56.0 and REVERSED it at v2.57.0 (LibKa0s v1.41.0,
-- Slash minor 13): while disabled every reserved verb answers normally -- `config` and the bare
-- `/lh` open the panel, `version` prints, `debug` runs, and the whole schema CLI reads and repairs
-- settings, which is precisely when a player most needs it. The case that settled it was the
-- smallest one: `/lh` on a disabled addon returned a refusal instead of the settings panel, which
-- is the one surface a player uses to switch it back on by hand.
--
-- So the ONLY refusal is §2's feature-verb SHOULD, which this addon already adopted and keeps.
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
--
-- THE SET IS THE LIBRARY'S OWN, byte for byte: `lib.LIVE_VERBS` at Slash minor 13 is these twelve.
-- It is restated here rather than read off the library because this table is built at FILE LOAD,
-- before settings/Slash.lua has resolved anything, and because the wrapper below has to gate the
-- LIBRARY-LESS dispatcher too — the one install where there is no `lib.LIVE_VERBS` to ask.
-- tests/test_disabled.lua asserts the two agree, so the restatement cannot drift.
local LIVE_WHILE_DISABLED = {
  help = true, config = true, version = true, enable = true, disable = true,
  debug = true, perf = true,
  get = true, set = true, list = true, reset = true, resetall = true,
}

--- The STORED enable path, and deliberately not `NS.IsStoodDown` — a perf capture is a reason to be
--- inert and never a reason to refuse a verb, so the slash gate asks the switch the player threw.
--- core/LifecycleSetup.lua owns the read; this is the one name the table below calls it by.
local function addonIsOff()
  return NS.AddonIsOff()
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
        --
        -- The WORDING is the collection's and not this addon's (slash-commands-§7): one shape,
        -- built by the library from the brand name and the slash, so eleven addons do not each
        -- spell "disabled" their own way. It is fetched at call time rather than captured, because
        -- this table is built before settings/Slash.lua exists.
        if addonIsOff() then return print(NS.Slash.DisabledLine()) end
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
