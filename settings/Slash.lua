local addonName, NS = ...
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
      print(("blacklist cleared (%d %s)."):format(n, n == 1 and "id" or "ids"))
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
      print(("whitelist cleared (%d %s)."):format(n, n == 1 and "id" or "ids"))
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
      print(("currency blacklist cleared (%d %s)."):format(n, n == 1 and "id" or "ids"))
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
      print(("filters reset (%d %s cleared)."):format(n, n == 1 and "id" or "ids"))
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
--- The view state that follows is not stored data: the Browser's sort/filter view
--- and its frame are rebuilt from what is now an empty store.
function Sl:ResetEverything()
  local db = NS.db
  if db and db.global then
    local g = db.global
    for k in pairs(g) do g[k] = nil end
    for k, v in pairs(NS.Util and NS.Util.DeepCopy and NS.Util.DeepCopy(NS.defaults.global)
                      or NS.defaults.global) do
      g[k] = v
    end
  end
  if NS.Database and NS.Database.FireHistoryChanged then NS.Database:FireHistoryChanged() end
  print("this addon reset to defaults.")
  if NS.Browser then
    if NS.Browser.ResetView then NS.Browser:ResetView(true) end   -- silent: one line above is enough
    if NS.Browser.ResetWindow then NS.Browser:ResetWindow() end
  end
  if NS.Panel and NS.Panel.Refresh then NS.Panel:Refresh() end
end


-- ── LibKa0s-Slash-1.0 seam ─────────────────────────────────────────────────────────────────────
--
-- The dispatcher, the help renderer, the landing rows, the schema CLI and the type-aware value
-- parser are all the library's now. What stays here is what is genuinely this addon's: the confirm
-- popups above, the total-reset composition above, the chat-command registration, and the two
-- adapters below (`FormatSchemaValue` for the set-valued rows the library has no type for, and the
-- filter-list half of `resetall`).

local lib = LibStub and LibStub("LibKa0s-Slash-1.0", true)

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
  -- NS.COMMANDS are unaffected — they never went through the library — so they are dispatched here
  -- by the same positional walk the library does.
  local function unavailable()
    NS.Print(NS.LIBKA0S_MISSING .. ", so the slash command interface is unavailable.")
  end
  Sl.FormatKV = function(path, valueStr)
    return ("|cFFFFFF00%s|r = |cFFFFFFFF%s|r"):format(tostring(path), tostring(valueStr))
  end
  -- The verbs that went THROUGH the library, and only those. Everything else in NS.COMMANDS is
  -- host-owned and still works on this path (slash-commands-§1), so the degraded help is rendered
  -- by SUBTRACTION rather than from a second hand-typed list that would drift the day a verb is
  -- added — the same reason the dispatch below walks NS.COMMANDS instead of naming verbs.
  local LIBRARY_OWNED = {
    version = true, get = true, set = true, list = true,
    reset = true, resetall = true, help = true,
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
  --- slash-commands-§3: a bare `/lh` renders help on EVERY install, so it has to list what still
  --- works rather than answering "unavailable" — the one line a user has to reach for when nothing
  --- else responds cannot be the line that tells them to give up.
  Sl.HelpHeader = function()
    return NS.LIBKA0S_MISSING .. ", so only these commands are available:"
  end
  Sl.HelpRows = function()
    local rows = {}
    for _, entry in ipairs(NS.COMMANDS) do
      if not LIBRARY_OWNED[entry[1]] then
        rows[#rows + 1] = "  " .. formatRow("/lh " .. entry[1], entry[2])
      end
    end
    return rows
  end
  Sl.PrintHelp = function()
    NS.Print(Sl.HelpHeader())
    for _, row in ipairs(Sl.HelpRows()) do NS.Print(row) end
  end
  Sl.CliList, Sl.CliGet, Sl.CliSet, Sl.CliReset, Sl.CliVersion = unavailable, unavailable,
    unavailable, unavailable, unavailable
  Sl.CliResetAll = function()
    if NS.Filters and NS.Filters.ClearAll then NS.Filters:ClearAll() end
    unavailable()
  end
  function Sl:OnSlash(input)
    local raw = (input or ""):match("^%s*(.-)%s*$") or ""
    -- Bare `/lh` is help on both paths. It used to fall through the verb walk to `unavailable()`,
    -- which is the worst of the three answers: it blacks out the whole command surface in the one
    -- install where the user most needs to be told which commands survived.
    if raw == "" then return Sl.PrintHelp() end
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
  set          = function(path, v) NS.Schema:Set(path, v) end,
  findRow      = function(path) return NS.Schema:FindRow(path) end,
  allRows      = function() return NS.Schema.Schema end,
  applyDefault = function(row) NS.Schema:Set(row.path, NS.Schema:Default(row.path)) end,

  -- `/lh list` groups by the panel section header. The library's default is `row.page`, which this
  -- addon has no concept of — it is a single-panel addon, so its schema `group` values ARE the
  -- headings, and using them keeps the listing in the same order and under the same names the
  -- settings panel shows.
  groupKey = function(row) return row.group or "?" end,

  -- The set-valued rows, per the note on FormatSchemaValue above.
  format = function(row, v) return Sl.FormatSchemaValue(row, v) end,
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

--- The settings landing page's command rows: the same rows as the chat help, in the same colors
--- and spacing, without the two-space indent a chat line needs to sit under a header.
---
--- CONVERGENCE. settings/Panel.lua used to carry its own formatter for this — double spaces around
--- the em dash, the dash explicitly white-wrapped, the description bare — divergent from the chat
--- help two files away for no reason anyone recorded. Both now render through lib.FormatRow.
function Sl:LandingRows() return Dispatcher:LandingRows() end

--- Reset every user setting to its default.
---
--- Wraps rather than re-exports, because the two item-id filter lists are user-configured settings
--- that carry no schema row (they are a storage carve-out managed by NS.Filters), so the library's
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
