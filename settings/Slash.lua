local _, NS = ...
NS.Slash = NS.Slash or {}
local Sl = NS.Slash
local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer (events-frames-taint-§8)

-- Confirm dialogs for destructive actions. Registered once; in-game only.
if type(StaticPopupDialogs) == "table" then
  StaticPopupDialogs["KA0S_LOOTHISTORY_PURGE"] = {
    text = "Delete ALL Ka0s Loot History records? This cannot be undone.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
      if NS.Database and NS.Database.Purge then NS.Database:Purge() end
      print("history purged.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
  }
  -- The "Keep history for" confirm (settings/Schema.lua, S:OnRetentionChanged): raised only when
  -- a shorter retention would delete records. %s = the new retention's label, %s = the count.
  -- No is not a mere dismissal: it writes the previous retention back, so nothing is deleted at
  -- the next login either.
  StaticPopupDialogs["KA0S_LOOTHISTORY_PRUNE"] = {
    text = "Shorten 'Keep history for' to %s? %s older records will be deleted. This cannot be undone.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data) NS.Schema:ConfirmRetention(data.days, true) end,
    -- StaticPopup_Show cancels a visible KA0S_LOOTHISTORY_PRUNE with reason "override" before it
    -- re-shows it for a newer value. That is not the player's No, so it restores nothing.
    OnCancel = function(_, data, reason)
      if reason == "override" then return end
      NS.Schema:ConfirmRetention(data.days, false)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
  }
  StaticPopupDialogs["KA0S_LOOTHISTORY_RESETALL"] = {
    -- THE COLLECTION'S SECOND CANONICAL WORDING (options-ui-§12), verbatim: the one for an addon
    -- with no profile. The first one closes with "your other profiles are not affected", which is a
    -- promise this addon cannot keep -- it has none.
    text = "Reset this addon to its defaults? Everything you have configured or recorded is discarded, for every character on this account — this cannot be undone.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function() Sl:ResetEverything() end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
  }
  -- Bulk-clear confirms for the two item-id filter lists (issue #14). Non-destructive: clearing a
  -- list only empties its id-set — stored history is never touched (filtering is point-in-time, so
  -- there are no hidden rows to reconcile). The Filters panel refreshes itself via the
  -- HistoryChanged listener fired by Filters:ClearList, so OnAccept only has to clear and report.
  StaticPopupDialogs["KA0S_LOOTHISTORY_CLEAR_BLACKLIST"] = {
    text = "Clear ALL item ids from the blacklist? Future loots of them will be recorded again; your existing history is unaffected.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
      local n = (NS.Filters and NS.Filters.ClearList and NS.Filters:ClearList("blacklist")) or 0
      NS.Format("blacklist cleared (%d %s).", n, n == 1 and "id" or "ids")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
  }
  StaticPopupDialogs["KA0S_LOOTHISTORY_CLEAR_WHITELIST"] = {
    text = "Clear ALL item ids from the whitelist?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
      local n = (NS.Filters and NS.Filters.ClearList and NS.Filters:ClearList("whitelist")) or 0
      NS.Format("whitelist cleared (%d %s).", n, n == 1 and "id" or "ids")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
  }
  StaticPopupDialogs["KA0S_LOOTHISTORY_CLEAR_CURRENCY"] = {
    text = "Clear ALL currency ids from the blacklist? Future loots of them will be recorded again; your existing history is unaffected.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
      local n = (NS.Filters and NS.Filters.ClearList and NS.Filters:ClearList("currencyBlacklist")) or 0
      NS.Format("currency blacklist cleared (%d %s).", n, n == 1 and "id" or "ids")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
  }
  -- The Filters subcategory's top-right "Defaults" button (options-ui-§5) clears BOTH lists in one
  -- action — their default state is empty. Non-destructive like the per-list clears: stored history
  -- is never touched. The panel refreshes itself via the HistoryChanged listener Filters:ClearAll fires.
  StaticPopupDialogs["KA0S_LOOTHISTORY_CLEAR_FILTERS"] = {
    text = "Reset all loot filters to defaults (clear the item blacklist, whitelist, AND the currency blacklist)? Your existing history is unaffected.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
      local n = (NS.Filters and NS.Filters.ClearAll and NS.Filters:ClearAll()) or 0
      NS.Format("filters reset (%d %s cleared).", n, n == 1 and "id" or "ids")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
  }
end

-- Full reset (the panel's confirm-gated "Reset Everything" button, NOT the `/lh resetall` verb,
-- which is settings + id-lists only): wipe history AND restore every persisted piece of
-- account state to its stock shape. CliResetAll covers the schema settings + the filter lists; this
-- adds the two view/window carve-outs that the non-destructive resets deliberately leave alone —
-- savedView (back to stock) and the window geometry (recentered) — so "Reset ALL" is truly total.
--- The global reset (options-ui-§12), in the shape that rule takes for an addon with
--- NO PROFILE.
---
--- Everything this addon stores is account-wide: `NS.defaults.global` carries the
--- history, the three filter lists AND the settings, and there is no `profile`
--- section at all (docs/schema.md). `db:ResetProfile()` -- which is what the rule
--- asks of an addon that has one -- would be a no-op here, so the rule translates:
--- empty the account-wide store wholesale and merge the declared defaults back, so
--- what comes back is indistinguishable from a fresh install.
---
--- WIPED IN PLACE, and NOT key by key. `NS.db.global` is held by modules from load,
--- so replacing the table would leave every holder on a stale one. And a
--- hand-written list of keys to clear fails exactly the way a row-by-row schema
--- sweep fails -- one release later, when something new is stored beside the ones
--- the list names -- which is what this function used to be: a purge, a schema
--- walk and a filter-list clear, three enumerations that between them happened to
--- cover the whole table. AceDB ships no `ResetGlobal`, so it is written here.
---
--- The view state lives in `refreshAfterReset` below. It is not stored data: the Browser's
--- sort/filter view and its frame are rebuilt from what is now an empty store.
---
--- Empty `g` in place and merge the declared defaults back. Returns how many recorded
--- history rows the wipe discarded, for the debug trace (debug-logging-§8).
---
--- ONE ROW IS CARRIED ACROSS THE WIPE (launcher-§3, standard v2.54.0). This is the reset the rule
--- says the minimap button's visibility must survive, and before this carve-out it did not: the
--- merge puts `defaults/Global.lua`'s `minimap = { hide = false }` back, so a player who had hidden
--- the button found it on their minimap again after asking for their SETTINGS to be reset. The
--- exempt set is `NS.Schema.RESET_EXEMPT`, declared there and read here, so the two resets cannot
--- disagree about which row it is. It maps ROW path to STORED path (launcher-§3, standard v2.65.0):
--- the row is `minimap.shown`, the one stored key is `minimap.hide`, and no `shown` key is ever
--- stored, so this wipe carries the map's VALUES. Read and written RAW, through ReadPath/WritePath
--- rather than Schema:Get/Set: the value is being put back exactly as it was, and a write through
--- the seam inside this function would fire an onChange and a second [Set] line in a reset that
--- logs exactly one.
local function wipeGlobal(g)
  local removed = type(g.history) == "table" and #g.history or 0
  local S = NS.Schema
  local kept = {}
  for _, storedPath in pairs(S.RESET_EXEMPT) do kept[storedPath] = S:ReadPath(g, storedPath) end
  for k in pairs(g) do g[k] = nil end
  -- Copied, never merged by reference: a store sharing a table with NS.defaults rewrites the
  -- declared default on its next write.
  for k, v in pairs(NS.Util.DeepCopy(NS.defaults.global)) do g[k] = v end
  for path, v in pairs(kept) do
    if v ~= nil then S:WritePath(g, path, v) end
  end
  return removed
end

--- debug-logging-§10: the wipe replaces every stored setting, and that is logged ONCE, as a [Set]
--- line worded by the act. This addon has no profile, so this is its form of the profile handler's
--- `reset profile '<name>' to defaults (N rows)` (options-ui-§12): wholesale replacement, not a walk
--- through the helper, so the write seam never runs and there is no per-row line to mute. N is the
--- stored rows the wipe actually changes: a row already at its default is not counted, and neither
--- is a session-only row (the console toggle), which lives outside db.global. So it is read BEFORE
--- the wipe, while the old values are still there. Worded apart from the [Data] line's "reset-all"
--- on purpose: that line is the separate debug-logging-§8 trace of the history purge.
local function traceSettingsReset(g)
  if not (NS.State and NS.State.debug and NS.Debug) then return end
  local S, n = NS.Schema, 0
  for _, row in ipairs(S and S.Schema or {}) do
    -- Read in the ROW's own sense, not the store's. They are the same for every row but one:
    -- the row `minimap.shown` says SHOWN while its one stored key, `minimap.hide`, says HIDDEN
    -- (launcher-§3), and no `shown` key is stored, so a raw ReadPath at the row's path finds nothing
    -- and the row would be counted on every reset, whether or not the wipe changes it. The
    -- exemption test below is keyed by that ROW path. `row.get` reads the live `db.global`, which is
    -- the same table `g` is: wipeGlobal empties it IN PLACE, and this runs before it.
    local current
    if row.get then current = row.get() else current = S:ReadPath(g, row.path) end
    -- An EXEMPT row is carried across the wipe (launcher-§3), so it is never one of the rows the
    -- act changed and counting it would overstate N by one for every player who hid the button.
    if not row.sessionOnly and not S.RESET_EXEMPT[row.path]
       and not S.SameValue(current, row.default) then
      n = n + 1
    end
  end
  NS.Debug("Set", "reset account-wide settings to defaults (%d rows)", n)
end

--- The post-wipe repaint, lifted out of `Sl:ResetEverything` so that function stays under the
--- complexity ceiling the release gate enforces (`performance-§10`). It is a fan-out of guarded
--- calls and nothing else. Each target is optional because a reset can land before a module has
--- built its frame, and none of them touch stored data: the Browser's sort/filter view and its
--- frame are rebuilt from what is now an empty store.
local function refreshAfterReset()
  if NS.Browser then
    if NS.Browser.ResetView then NS.Browser:ResetView(true) end   -- silent: one line above is enough
    if NS.Browser.ResetWindow then NS.Browser:ResetWindow() end
  end
  -- `minimap` is a new table now; LibDBIcon must be pointed at it or the next drag is lost. The
  -- call moved out of NS.Browser with the rest of the launcher (core/LauncherSetup.lua).
  if NS.RefreshLauncher then NS.RefreshLauncher() end
  if NS.Panel and NS.Panel.Refresh then NS.Panel:Refresh() end
end

function Sl:ResetEverything()
  local db = NS.db
  if db and db.global then
    traceSettingsReset(db.global)
    local removed = wipeGlobal(db.global)
    -- The raw wipe fires no onChange, so the confirmed retention is re-read from the store here.
    if NS.Schema and NS.Schema.SyncRetention then NS.Schema:SyncRetention() end
    if NS.State.debug and NS.Debug then
      NS.Debug("Data", "reset-all removed %s rows", tostring(removed))
    end
  end
  -- Test mode is a session-only row, so the wipe above never reaches it, and options-ui-§15 says
  -- Reset all settings ends it. Switched directly rather than written through Schema:Set, which
  -- would log a per-row [Set] line inside a reset that logs exactly one.
  if NS.BrowserTable and NS.BrowserTable.testMode and NS.BrowserTable.SetTestMode then
    NS.BrowserTable:SetTestMode(false)
  end
  if NS.Database and NS.Database.FireHistoryChanged then NS.Database:FireHistoryChanged() end
  print("this addon reset to defaults.")
  refreshAfterReset()
end


-- ── LibKa0s-Slash-1.0 seam ─────────────────────────────────────────────────────────────────────
--
-- The dispatcher, the help renderer, the landing rows, the schema CLI and the type-aware value
-- parser are all the library's now. What stays here is what is genuinely this addon's: the confirm
-- popups above, the total-reset composition above, the chat-command registration, and the two
-- adapters below (`FormatSchemaValue` for the set-valued rows the library has no type for, and the
-- filter-list half of `resetall`).

local lib = LibStub and LibStub("LibKa0s-Slash-1.0", true)

--- The ONE refusal line's template (slash-commands-§7), on BOTH paths so the Slash surface-parity
--- case stays symmetric. With the library present it IS `lib.DISABLED_LINE_FORMAT`; without it,
--- this literal is the one library string slash-commands-§1 lets a stub carry verbatim, and
--- tests/test_slash_degraded.lua pins it byte for byte against the live library
--- (Kit.assertLibraryConstant).
Sl.DISABLED_LINE_FORMAT = lib and lib.DISABLED_LINE_FORMAT
  or "%s is disabled \226\128\148 enable it with |cFFFFFF00%s|r"

-- Type-aware value formatter for the two rows the library cannot render on its own.
--
-- `type = "table"` is not one of the library's four types, so `lib.FormatValue` falls through to
-- Core's SafeToString — which probes table.concat, fails, and answers "<secret>". That would tell a
-- user that `settings.excludedSources` is combat-protected. Slash **minor 5**'s `format` hook is the
-- supported answer to exactly this (it was added for BankLedger's muted-store set), so the branch
-- lives here and everything else is handed straight back to the library. Kept as a public member
-- because the descriptor's `format` hook below is handed it by name, and the suite pins its output.
function Sl.FormatSchemaValue(row, v)
  if v == nil then return "nil" end
  if row and row.type == "table" then
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k, on in pairs(v) do if on then keys[#keys + 1] = tostring(k) end end
    table.sort(keys)
    if #keys == 0 then return lib and lib.STRINGS.NONE or "(none)" end
    return "{" .. table.concat(keys, ", ") .. "}"
  end
  -- Everything else — bool, number (through the row's `fmt`), string — is the library's, so the
  -- CLI and the settings panel cannot render the same value two ways.
  if lib then return lib.FormatValue(row, v) end
  return tostring(v)
end

if not lib then
  -- Degrade, not error. `/lh` is registered unconditionally (Sl:Register below runs from
  -- OnInitialize whatever the install looks like), so every verb the dispatcher would have owned
  -- has to answer with an honest line rather than a nil-index error. The seven host verbs in
  -- NS.COMMANDS still DISPATCH — they never went through the library — so they are walked here by
  -- the same positional walk the library does. Dispatching is not the same as working: `config`
  -- dispatches into a handler that lands on the Options stub and declines, which is why the help
  -- list below subtracts it and why the set doing the subtracting is not named after the library.
  local function unavailable()
    NS.Print(NS.LIBKA0S_MISSING .. ", so the slash command interface is unavailable.")
  end
  Sl.FormatKV = function(path, valueStr)
    return ("|cFFFFFF00%s|r = |cFFFFFFFF%s|r"):format(tostring(path), tostring(valueStr))
  end
  --- The ONE refusal line (slash-commands-§7), rendered from Sl.DISABLED_LINE_FORMAT above with
  --- the SAME arguments the library passes (libs/LibKa0s/Slash.lua's DisabledLine: the brand name
  --- and `slash .. " enable"`), so the line matches the live one byte for byte, not just its
  --- template. `/lh enable` works on this path too (Sl.CliSet below), so the way back in it names
  --- is one the player can actually take.
  Sl.DisabledLine = function()
    return Sl.DISABLED_LINE_FORMAT:format(NS.BRAND, "/lh enable")
  end
  -- The verbs NOT to offer here, which is not the same set as the verbs that went through the
  -- library — and the old name, LIBRARY_OWNED, is what got it wrong. `config` never went through
  -- the library: its handler is host-owned and sits in NS.COMMANDS beside show/hide/toggle. But it
  -- calls NS.Panel:Open, which reaches O.OpenOptionsPanel, which on this path is
  -- settings/OptionsSetup.lua's stub that prints "the settings panel is unavailable" and opens
  -- nothing. slash-commands-§1 asks this list for what still WORKS, so advertising a verb that
  -- then declines is worse than omitting it. Everything not named here is host-owned AND still
  -- works, which is why the degraded help is rendered by SUBTRACTION rather than from a second
  -- hand-typed list that would drift the day a verb is added — the same reason the dispatch below
  -- walks NS.COMMANDS instead of naming verbs. The price of subtraction is that a new verb is
  -- offered by default, so one that leans on the library has to be added here when it is declared;
  -- tests/test_slash_degraded.lua's help cases are what say so out loud.
  --
  -- `help` is here for the other reason: it answers fine on this path (Sl.PrintHelp below is what
  -- is printing) and is omitted only because naming "help" inside help output is noise. Two
  -- reasons, one verdict, so one set carries both.
  -- `enable` / `disable` are NOT here: they work on this path. Both delegate to CliSet, and the
  -- degraded CliSet below writes exactly one path, `settings.enabled`, through the seam's
  -- writeThrough list (settings/Schema.lua; options-ui-§1 route (a)) -- the Options composer is
  -- the stub, so there is no row, and writeThrough is what stores the value anyway. `set` stays
  -- here, because only that one path writes: advertising it would promise the whole schema CLI.
  local UNAVAILABLE_WITHOUT_LIB = {
    version = true, get = true, set = true, list = true,
    reset = true, resetall = true, help = true, config = true,
  }
  -- Gold command, em dash, white description — the shape lib.FormatRow renders, kept in step with
  -- Sl.FormatKV above, which re-states lib.FormatKV's for the same reason: the library is not there
  -- to ask, and a degraded install must still look like this addon.
  local function formatRow(command, description)
    return ("|cFFFFFF00%s|r \226\128\148 |cFFFFFFFF%s|r")
      :format(tostring(command), tostring(description))
  end
  Sl.LandingRows = function() return {} end
  Sl.BuildListLines = function() return {} end
  --- slash-commands-§3: a bare `/lh` renders this help on a library-less install (see OnSlash
  --- below), so it has to list what still works rather than answering "unavailable" — the one line
  --- a user has to reach for when nothing else responds cannot be the line that tells them to give up.
  Sl.HelpHeader = function()
    return NS.LIBKA0S_MISSING .. ", so only these commands are available:"
  end
  Sl.HelpRows = function()
    local rows = {}
    for _, entry in ipairs(NS.COMMANDS) do
      if not UNAVAILABLE_WITHOUT_LIB[entry[1]] then
        rows[#rows + 1] = "  " .. formatRow("/lh " .. entry[1], entry[2])
      end
    end
    return rows
  end
  Sl.PrintHelp = function()
    NS.Print(Sl.HelpHeader())
    for _, row in ipairs(Sl.HelpRows()) do NS.Print(row) end
  end
  Sl.CliList, Sl.CliGet, Sl.CliReset, Sl.CliVersion = unavailable, unavailable,
    unavailable, unavailable
  --- The enable path only, which is what `/lh enable` and `/lh disable` delegate to. The row-less
  --- write lands through the seam's writeThrough list, which runs no onChange, so the reaction the
  --- Master controls row would have run (the latch, then the bus) is called here by the same name
  --- the row's onChange calls it by. The ack is the `set` shape, re-read from the store.
  Sl.CliSet = function(_, rest)
    local path, value = tostring(rest or ""):match("^%s*(%S+)%s+(%S+)%s*$")
    if path ~= "settings.enabled" or (value ~= "true" and value ~= "false") then
      return unavailable()
    end
    if NS.Schema:Set(path, value == "true") ~= true then return unavailable() end
    NS.Schema.OnEnabledWritten()
    NS.Print(Sl.FormatKV(path, tostring(NS.Schema:Get(path))))
  end
  --- The three id lists have one writer that needs no library (NS.Filters), so they ARE reset here,
  --- and the line says so with the count: a bare "unavailable" would hide that three lists were
  --- just emptied. The schema rows need the library's walk, which is the second clause.
  Sl.CliResetAll = function()
    local n = NS.Filters and NS.Filters.ClearAll and NS.Filters:ClearAll() or 0
    NS.Format("filters reset (%d %s cleared); other settings need the LibKa0s library.",
      n, n == 1 and "id" or "ids")
  end
  function Sl:OnSlash(input)
    local raw = (input or ""):match("^%s*(.-)%s*$") or ""
    -- Bare `/lh` mirrors the library's Slash minor 11 (slash-commands-§3): run the registered
    -- `config` verb with "", and print help when there is none. The lookup goes through the same
    -- UNAVAILABLE_WITHOUT_LIB set the help list does, because on this path `config` is registered
    -- but cannot answer: its handler reaches the Options stub, which declines. So a bare `/lh`
    -- here still prints the help list of what works. Running `config` anyway would print the
    -- "unavailable" line alone, which blacks out the whole command surface in the one install
    -- where the user most needs to be told which commands survived.
    if raw == "" then
      for _, entry in ipairs(NS.COMMANDS) do
        if entry[1] == "config" and not UNAVAILABLE_WITHOUT_LIB[entry[1]] then return entry[3]("") end
      end
      return Sl.PrintHelp()
    end
    local verb = raw:match("^(%S+)")
    local rest = raw:match("^%S+%s*(.-)$") or ""
    for _, entry in ipairs(NS.COMMANDS) do
      if entry[1] == (verb or ""):lower() then return entry[3](rest) end
    end
    unavailable()
  end
  function Sl:Register()
    NS.addon:RegisterChatCommand("lh", function(input) Sl:OnSlash(input) end)
    NS.addon:RegisterChatCommand("loothistory", function(input) Sl:OnSlash(input) end)
  end
  return
end

-- Re-exported so this file and the degraded stub above expose ONE key/value formatter under the same
-- name, and so the suite — the only other reader — pins that one shape. Gold key, white value, no
-- trailing colon; identical to what this file used to own, but in the library's UPPER-case hex.
Sl.FormatKV = lib.FormatKV

local Dispatcher = lib:New({
  slash        = "/lh",
  slashAliases = { "/loothistory" },
  commands     = NS.COMMANDS,

  -- Late-bound, so it survives core/LootHistory.lua's AceConsole reclaim of NS.Print.
  print = function(line) NS.Print(line) end,

  -- Read from the TOC metadata so it cannot drift from the packaged manifest, with the in-code
  -- constant as the fallback (slash-commands-§3). Both rungs live in core/EnvSetup.lua now.
  version = function()
    return NS.Version()
  end,

  -- The schema CLI, wired to this addon's single write seam. Every `set` a user types takes the
  -- same path a panel click does: validate -> write -> onChange -> debug line.
  get          = function(path) return NS.Schema:Get(path) end,
  -- Returns the seam's answer (Slash minor 15): a validate refusal comes back as `false, err`, and
  -- CliSet prints INVALID with the reason instead of echoing the unchanged value as if it landed.
  set          = function(path, v) return NS.Schema:Set(path, v) end,
  findRow      = function(path) return NS.Schema:FindRow(path) end,
  allRows      = function() return NS.Schema.Schema end,
  -- ONE reset policy, shared with the Options descriptor (settings/OptionsSetup.lua). It carries
  -- launcher-§3's one-row veto, which is what stops `/lh resetall` AND the General page's Defaults
  -- button — both of which arrive here, through Sl:CliResetAll — un-hiding the minimap button. A
  -- single `/lh reset minimap.shown` still resets it: that is the player naming the row, by its
  -- row path (the stored key underneath stays LibDBIcon's `minimap.hide`).
  -- A statement, deliberately, where `set` above returns: since Slash minor 15 an answer of
  -- exactly false makes CliReset print NO_DEFAULT, and the reset-exempt veto is a skip rather
  -- than a missing default. Answering nothing keeps every reset on the echo path.
  applyDefault = function(row) NS.Schema:ApplyDefault(row) end,

  -- Slash minor 8's bulk bracket around CliResetAll's row walk (debug-logging-§10). The seam mutes
  -- its per-row [Set] line inside it and logs `[Set] reset all: N rows` once at the end. Not handed
  -- to the Options descriptor: nothing here calls O.RestoreDefaults or O.RestoreAllDefaults (the
  -- General page's Defaults click and the Blizzard footer both route to P:RestoreDefaults, here).
  bulkBegin    = function(act, scope) NS.Schema.BulkBegin(act, scope) end,
  bulkEnd      = function(...) NS.Schema.BulkEnd(...) end,

  -- `/lh list` groups by the panel section header. The library's default is `row.page`, which this
  -- addon has no concept of — it is a single-panel addon, so its schema `group` values ARE the
  -- headings, and using them keeps the listing in the same order and under the same names the
  -- settings panel shows.
  groupKey = function(row) return row.group or "?" end,

  -- The set-valued rows, per the note on FormatSchemaValue above.
  format = function(row, v) return Sl.FormatSchemaValue(row, v) end,

  -- ── the disabled gate (Slash minor 12, restored to its present shape at 13) ──────────────
  --
  -- Asked at DISPATCH TIME and never cached, so the command after an `enable` works. It reads the
  -- STORED switch, not the latch: a perf capture is a reason to be inert and never a reason to
  -- refuse a verb.
  --
  -- NO `liveVerbs`, AND THAT IS DELIBERATE. The library's default at minor 16 is the standard's
  -- thirteen reserved verbs -- help, config, version, enable, disable, debug, perf, diagnostics,
  -- get, set, list, reset, resetall -- and the bare `/lh` runs `config` in either state, which opens the panel. An
  -- earlier pass narrowed that set to `enable` and `help`; the owner tested it, found `/lh` on a
  -- disabled addon answering a refusal instead of opening the one surface the addon can be
  -- switched back on from, and reversed it (standard v2.57.0). Passing a narrowed set here would
  -- re-introduce exactly that, so this addon passes none and takes the library's.
  --
  -- What is left refused is §2's feature-verb SHOULD -- show/hide/toggle/test/purge -- and this
  -- addon gates those at the COMMANDS table (settings/Schema.lua), which is the one seam BOTH its
  -- dispatchers pass through. The two gates print the same string, because both build it here.
  isEnabled = function() return not NS.AddonIsOff() end,
  brandName = NS.BRAND,
})

-- ── the surface the rest of the addon calls ────────────────────────────────────────────────────
--
-- Bound onto NS.Slash by name rather than replacing it, because ~20 call sites across the schema
-- table, the settings panel and the suite already reach for `NS.Slash:CliList()` and friends.

Sl.OnSlash        = function(_, msg)  return Dispatcher:OnSlash(msg)  end
Sl.PrintHelp      = function()        return Dispatcher:PrintHelp()   end
Sl.HelpHeader     = function()        return Dispatcher:HelpHeader()  end
Sl.HelpRows       = function()        return Dispatcher:HelpRows()    end
Sl.BuildListLines = function()        return Dispatcher:BuildListLines() end
Sl.CliList        = function()        return Dispatcher:CliList()     end
Sl.CliGet         = function(_, rest) return Dispatcher:CliGet(rest)  end
Sl.CliSet         = function(_, rest) return Dispatcher:CliSet(rest)  end
Sl.CliReset       = function(_, rest) return Dispatcher:CliReset(rest) end
Sl.CliVersion     = function()        return Dispatcher:CliVersion()  end
--- The ONE refusal line, from the library, for every surface that prints it: the COMMANDS-table
--- gate in settings/Schema.lua, the one call site left since Launcher minor 4 (LibKa0s v1.58.0,
--- launcher-§2) retired the launcher's refused left-click. It never writes the wording itself --
--- slash-commands-§7 makes it the collection's rather than the addon's, and a second call site
--- spelling it again is how eleven addons ended up with eleven refusals.
Sl.DisabledLine   = function()        return Dispatcher:DisabledLine() end

--- The settings landing page's command rows: the same rows as the chat help, in the same colors
--- and spacing, without the two-space indent a chat line needs to sit under a header.
---
--- CONVERGENCE. settings/Panel.lua used to carry its own formatter for this — double spaces around
--- the em dash, the dash explicitly white-wrapped, the description bare — divergent from the chat
--- help two files away for no reason anyone recorded. Both now render through lib.FormatRow.
function Sl:LandingRows() return Dispatcher:LandingRows() end

--- Reset every user setting to its default.
---
--- Wraps rather than re-exports, because the three id filter lists carry no schema row (they are
--- an architecture-§5 structural registry, written only through NS.Filters), so the library's
--- row walk cannot see them. Cleared FIRST so the library's acknowledgment is the last line
--- printed and reads as the summary of everything that happened.
function Sl:CliResetAll()
  if NS.Filters and NS.Filters.ClearAll then NS.Filters:ClearAll() end
  Dispatcher:CliResetAll()
end

function Sl:Register()
  NS.addon:RegisterChatCommand("lh", function(input) Sl:OnSlash(input) end)
  NS.addon:RegisterChatCommand("loothistory", function(input) Sl:OnSlash(input) end)
end
