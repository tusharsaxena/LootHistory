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
    -- THE COLLECTION'S FIRST CANONICAL WORDING (options-ui-§12), verbatim: the one for an addon
    -- with a `profile` section. This addon has both scopes, and §12 is explicit about that case:
    -- the reset is the PROFILE reset, and the account-wide loot history is not settings -- it is
    -- cleared only by its own separately confirmed act, `/lh purge` (KA0S_LOOTHISTORY_PURGE above).
    text = "Reset this profile to the addon's defaults? Everything you have configured or added in it is discarded — your other profiles are not affected.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function() Sl:CliResetAll() end,
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
  -- The one-time timeline-ledger reset recommendation (spec 9.2). Esc/close decides nothing, so it
  -- is asked again next session (the persisted db.global.resetPromptPending carries it there); only
  -- Keep and a confirmed Reset store a choice, and both retire the marker.
  StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET"] = {
    text = "|cffffd100Loot History has become a full ledger.|r\n\n" ..
      "It now tracks what every character and your warband holds, and will track gains AND losses " ..
      "of items, currencies and gold.\n\n" ..
      "|cffffd100Recommended: start a fresh history.|r Your %d existing records only ever captured " ..
      "gains. Mixed with the new data, any period before today would show income with no spending, " ..
      "so net totals and Insights for those dates overstate what you kept.\n\n" ..
      "|cffffd100If you keep it:|r nothing is lost and older loot stays browsable, but net and loss " ..
      "figures are only accurate from today; ranges that include older dates carry a warning.\n\n" ..
      "|cffffd100If you reset:|r older loot records are deleted permanently. Settings, filters and " ..
      "profiles are kept. Choose Export first for a copy.",
    button1 = "Reset history", button2 = "Keep history", button3 = "Export first",
    OnAccept = function() StaticPopup_Show("KA0S_LOOTHISTORY_LEDGER_RESET_CONFIRM", #NS.db.global.history) end,
    -- button2 reports reason "clicked"; Esc hides through OnHide and never reaches here, and a
    -- re-show reports "override"/"timeout". Only the deliberate click is a decision.
    OnCancel = function(_, _, reason)
      if reason == "clicked" then
        NS.db.global.resetPrompt, NS.db.global.resetPromptPending = "kept", nil
        print("keeping your loot history.")
      end
    end,
    OnAlt = function()
      NS._ledgerResetAfterExport = true
      if NS.Browser then NS.Browser:Show(); NS.Browser:SelectTab("History"); NS.Browser:OpenExport() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
  }
  StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET_CONFIRM"] = {
    text = "Delete %d loot records permanently? This cannot be undone.",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function()
      local g = NS.db.global
      if NS.Database and NS.Database.Purge then NS.Database:Purge() end
      g.resetPrompt, g.resetPromptPending, g.ledgerSince = "reset", nil, time()
      print("history reset; the ledger starts now.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
  }
end

--- True iff the one-time reset recommendation is due: armed by the v11 migration step (an upgrade
--- from before the ledger with history in it, persisted as `resetPromptPending` so an Esc on one
--- login is asked again on the next), history still worth resetting, and no choice stored yet.
function NS.ShouldOfferLedgerReset(g)
  return g ~= nil and g.resetPrompt == nil and g.resetPromptPending == true
    and type(g.history) == "table" and #g.history > 0
end

-- The one-shot PLAYER_REGEN_ENABLED target that holds the offer back through combat. Module-level
-- so a second call does not stack a second one and NS.StandDown can drop it.
local offerTarget

--- Drop a held offer. Called from NS.StandDown: a prompt must not appear from a game event while off.
--- The "Export first" re-ask goes with it: StandDown hides the export window AFTER this runs, and
--- that window's OnHide would otherwise show the popup on an addon that was just switched off. The
--- persisted pending marker is untouched, so the question still comes back on a later login.
function NS.DropLedgerResetOffer()
  if offerTarget then offerTarget:UnregisterAllEvents(); offerTarget = nil end
  NS._ledgerResetAfterExport = nil
end

function NS.OfferLedgerReset()
  local g = NS.db and NS.db.global
  if not NS.ShouldOfferLedgerReset(g) then return end
  if NS.Compat.InCombatLockdown() then
    if offerTarget then return end
    offerTarget = NS.NewBusTarget()
    if not offerTarget then return end
    NS.SafeRegisterEvent(offerTarget, "PLAYER_REGEN_ENABLED", function()
      NS.DropLedgerResetOffer()
      NS.OfferLedgerReset()
    end, NS.RejectedEvents)
    return
  end
  if type(StaticPopup_Show) == "function" then StaticPopup_Show("KA0S_LOOTHISTORY_LEDGER_RESET", #g.history) end
end

-- ── LibKa0s-Slash-1.0 seam ─────────────────────────────────────────────────────────────────────
--
-- The dispatcher, the help renderer, the landing rows, the schema CLI and the type-aware value
-- parser are all the library's now. What stays here is what is genuinely this addon's: the confirm
-- popups above, the chat-command registration, the adapter below (`FormatSchemaValue` for the
-- set-valued rows the library has no type for), and `resetall`, which is the profile reset rather
-- than the library's row walk (options-ui-§12).

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

--- `/lh holdings <query>`: the top ten account-wide holdings whose name contains the query.
function Sl:Holdings(query)
  query = query or ""
  local rows = NS.Holdings and NS.Holdings:Search({ text = query }) or {}
  if #rows == 0 then print("no holdings match '" .. query .. "'."); return end
  for i = 1, math.min(10, #rows) do
    local r = rows[i]
    local total = r.key == "g" and NS.Util.FormatMoney(r.total) or tostring(r.total)
    print(("%s: %s"):format(r.name, total))
  end
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
  -- `diagnostics` is here for `config`'s reason: it still DISPATCHES (its row is host-owned, and
  -- the debug word reaches the same call), but the report is written into the LibKa0s console, so
  -- on this path it lands on the DebugLog stub, which prints the collection's library-absent line
  -- (debug-logging-§14) and writes nothing. Answering is not working, so help does not offer it.
  -- `resetall` is NOT here either: it is the profile reset, and AceDB is vendored beside this
  -- addon rather than inside LibKa0s, so Sl.CliResetAll below runs it in full.
  -- `profile` IS here: the verb is the library's (Slash minor 17), so on this path its row reaches
  -- Sl.CliProfile below, which only says the library is missing.
  local UNAVAILABLE_WITHOUT_LIB = {
    version = true, get = true, set = true, list = true,
    reset = true, help = true, config = true, diagnostics = true, profile = true,
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
  --- The profile verb's two members (Slash minor 17), because the live dispatcher has both
  --- (slash-commands-§1). Route (b): with no library there is no dispatcher to switch through, so
  --- each prints the collection's library-absent line for `/lh profile` and switches nothing.
  local function profileUnavailable()
    NS.Print(NS.L["%s is unavailable: the LibKa0s library did not load."]:format("/lh profile"))
  end
  Sl.CliProfile = function() profileUnavailable() end
  Sl.ProfileSwitch = function() profileUnavailable(); return false end
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
  --- options-ui-§12's global reset works on this path too: the act is AceDB's, not the library's.
  --- The session-only rows are restored first, through the seam as the library's walk does, and
  --- then S.ResetProfile resets the active profile, whose OnProfileReset reaches the adopt path
  --- (core/LootHistory.lua). The loot history is account-wide and untouched.
  Sl.CliResetAll = function()
    for _, row in ipairs(NS.Schema.Schema) do
      if not NS.Schema.VetoedFromResetAll(row) then NS.Schema:ApplyDefault(row) end
    end
    NS.Schema.ResetProfile()
    NS.Print("settings reset to defaults.")
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

--- `lib.LIVE_VERBS` plus the one host verb this addon keeps live while disabled (see `liveVerbs`
--- below). Copied, so the library's table is never written.
local function liveVerbs()
  local verbs = {}
  for i, verb in ipairs(lib.LIVE_VERBS) do verbs[i] = verb end
  verbs[#verbs + 1] = "profile"
  return verbs
end

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
  -- launcher-§3's one-row veto for any bulk bracket. `/lh resetall` no longer walks the rows (it is
  -- the profile reset, Sl:CliResetAll below), so what reaches this is `/lh reset <path>`: a single
  -- `/lh reset minimap.shown` still resets the button, because that is the player naming the row,
  -- by its row path (the stored key underneath stays LibDBIcon's `minimap.hide`).
  -- A statement, deliberately, where `set` above returns: since Slash minor 15 an answer of
  -- exactly false makes CliReset print NO_DEFAULT, and the reset-exempt veto is a skip rather
  -- than a missing default. Answering nothing keeps every reset on the echo path.
  applyDefault = function(row) NS.Schema:ApplyDefault(row) end,

  -- Slash minor 8's bulk bracket around the library's CliResetAll row walk (debug-logging-§10). This
  -- addon's `resetall` does not reach that walk any more (Sl:CliResetAll below), but the bracket is
  -- the same pair the Options descriptor takes, so a library walk that ever does run is one line.
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
  -- `liveVerbs` IS THE LIBRARY'S SET PLUS `profile`, and nothing else. `lib.LIVE_VERBS` at minor
  -- 17 is the standard's thirteen reserved verbs -- help, config, version, enable, disable, debug,
  -- perf, diagnostics, get, set, list, reset, resetall -- and the bare `/lh` runs `config` in either
  -- state, which opens the panel. An earlier pass narrowed that set to `enable` and `help`; the
  -- owner tested it, found `/lh` on a disabled addon answering a refusal instead of opening the one
  -- surface the addon can be switched back on from, and reversed it (standard v2.57.0). So the set
  -- is built FROM the library's rather than typed out, and only widened: `profile` is a host verb
  -- (not reserved, not in LIVE_VERBS), kept live because `settings.enabled` is profile-scoped and
  -- the profile a disabled player switches to may be the one where the addon is on.
  --
  -- What is left refused is §2's feature-verb SHOULD -- show/hide/toggle/test/purge -- and this
  -- addon gates those at the COMMANDS table (settings/Schema.lua), which is the one seam BOTH its
  -- dispatchers pass through. The two gates print the same string, because both build it here.
  isEnabled = function() return not NS.AddonIsOff() end,
  brandName = NS.BRAND,
  liveVerbs = liveVerbs(),

  -- The profile verb's store (Slash minor 17), asked at call time: NS.db is built at
  -- OnInitialize, after this file ran. The library switches through AceDB's SetProfile, whose
  -- OnProfileChanged reaches the adopt path (core/LootHistory.lua), which logs the one line.
  profiles = function() return NS.db end,

  -- The host's gated sink (Slash minor 18). Every refusal the dispatcher decides -- the disabled
  -- gate, an unknown verb, a get/set/reset usage, not-found, parse or write refusal, a reset with
  -- no default, the profile verb's refusals -- writes one `[Cmd] refused <verb>: <guard>` line here
  -- after its chat line (debug-logging-§4, §8). Late-bound: NS.Debug may be a suite's stand-in.
  debug = function(tag, message) if NS.Debug then NS.Debug(tag, message) end end,
})

-- ── the surface the rest of the addon calls ────────────────────────────────────────────────────
--
-- Bound onto NS.Slash by name rather than replacing it, because ~20 call sites across the schema
-- table, the settings panel and the suite already reach for `NS.Slash:CliList()` and friends.

-- No host [Cmd] line here any more: the disabled gate's refusal is the dispatcher's own line through
-- the `debug` sink above (Slash minor 18), so a copy that re-read the gate's facts would log the
-- one refusal twice (debug-logging-§4, "The library's own lines").
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
Sl.CliProfile     = function(_, rest) return Dispatcher:CliProfile(rest) end
Sl.ProfileSwitch  = function(_, name) return Dispatcher:ProfileSwitch(name) end
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

--- The global reset (options-ui-§12): ONE act behind three controls -- `/lh resetall`, the General
--- page's Defaults button (P:RestoreDefaults) and the Master controls' Reset all settings, whose
--- confirm (KA0S_LOOTHISTORY_RESETALL above) calls this on Yes.
---
--- The act is the library's O.RestoreAllDefaults over a descriptor that supplies `resetProfile`
--- (settings/OptionsSetup.lua): the session-only rows -- the debug console and test mode -- are
--- restored row by row, then `db:ResetProfile()` empties the active profile, and every panel
--- refreshes. The profile holds every setting, the three id lists, the AH cascade, the saved view
--- and the window geometry, so all of them come back as a fresh profile has them; no other profile
--- and not the profile list is touched. The loot history is account-wide and never reached:
--- clearing it is `/lh purge`, a separately confirmed act.
---
--- Not the library's own CliResetAll, whose row walk is the shape §12 forbids for an AceDB host.
--- The acknowledgment is the library's string, so the line reads as it always did.
function Sl:CliResetAll()
  NS.Options.RestoreAllDefaults()
  NS.Print(Dispatcher:Text("RESET_ALL"))
end

function Sl:Register()
  NS.addon:RegisterChatCommand("lh", function(input) Sl:OnSlash(input) end)
  NS.addon:RegisterChatCommand("loothistory", function(input) Sl:OnSlash(input) end)
end
