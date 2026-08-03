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
    text = "Reset ALL Ka0s Loot History settings AND delete ALL recorded history? This cannot be undone.",
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

-- Full reset (the confirm-gated "Reset All"): wipe history AND restore every persisted piece of
-- account state to its stock shape. CliResetAll covers the schema settings + the filter lists; this
-- adds the two view/window carve-outs that the non-destructive resets deliberately leave alone —
-- savedView (back to stock) and the window geometry (recentered) — so "Reset ALL" is truly total.
function Sl:ResetEverything()
  if NS.Database and NS.Database.Purge then NS.Database:Purge() end
  Sl:CliResetAll()   -- resets settings + filter lists + prints the confirmation line
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
-- because settings/Panel.lua and the suite both read it.
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
  Sl.HelpRows, Sl.LandingRows = function() return {} end, function() return {} end
  Sl.BuildListLines = function() return {} end
  Sl.PrintHelp = unavailable
  Sl.CliList, Sl.CliGet, Sl.CliSet, Sl.CliReset, Sl.CliVersion = unavailable, unavailable,
    unavailable, unavailable, unavailable
  Sl.CliResetAll = function()
    if NS.Filters and NS.Filters.ClearAll then NS.Filters:ClearAll() end
    unavailable()
  end
  function Sl:OnSlash(input)
    local verb = input and input:match("^(%S+)")
    local rest = input and input:match("^%S+%s*(.-)$") or ""
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

-- Re-exported so settings/Panel.lua and the suite reach ONE key/value formatter. Gold key, white
-- value, no trailing colon — identical in shape to what this file used to own, with the hex digits
-- now in the library's upper case.
Sl.FormatKV = lib.FormatKV

local Dispatcher = lib:New({
  slash        = "/lh",
  slashAliases = { "/loothistory" },
  commands     = NS.COMMANDS,

  -- Late-bound, so it survives core/LootHistory.lua's AceConsole reclaim of NS.Print.
  print = function(line) NS.Print(line) end,

  -- Read from the TOC metadata so it cannot drift from the packaged manifest, with the in-code
  -- constant as the fallback (slash-commands-§3).
  version = function()
    return (NS.Compat and NS.Compat.GetAddOnMetadata and NS.Compat.GetAddOnMetadata(NS.name, "Version"))
      or NS.version or "?"
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
