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

function Sl:Register()
  NS.addon:RegisterChatCommand("lh", function(input) Sl:OnSlash(input) end)
  NS.addon:RegisterChatCommand("loothistory", function(input) Sl:OnSlash(input) end)
end

-- Bare `/lh` prints the help index (slash-commands-§4). Window display is explicit:
-- `/lh toggle` or `/lh show|hide`. Only the verb is lower-cased; `rest` keeps its case
-- so schema paths survive `/lh set <path> <value>`.
function Sl:OnSlash(input)
  if input == nil or input:match("^%s*$") then
    return Sl:PrintHelp()
  end
  local verb, rest = input:match("^(%S+)%s*(.-)$")
  verb = verb and verb:lower()
  for _, cmd in ipairs(NS.COMMANDS) do
    if cmd.name == verb then return cmd.fn(rest) end
  end
  print("unknown command '" .. tostring(verb) .. "'")
  Sl:PrintHelp()
end

-- Help index generated from NS.COMMANDS (slash-commands-§4): a version/alias header,
-- then one prefixed row per command — gold command, em-dash, white description.
function Sl:PrintHelp()
  print("v" .. (NS.version or "") ..
    " slash commands (|cffffff00/loothistory|r is an alias for |cffffff00/lh|r)")
  for _, cmd in ipairs(NS.COMMANDS) do
    print(("|cffffff00/lh %s|r — |cffffffff%s|r"):format(cmd.name, cmd.desc))
  end
end

-- --- Schema-driven CLI: list / get / set / version (slash-commands-§5 output format) ---

-- Shared value formatter for list/get/set so the three can never diverge. Type-aware and
-- schema-driven: a row's optional `fmt` formats numbers (e.g. windowScale "%.2fx" → "1.00x");
-- booleans render true/false; a table setting (the excludedSources set) renders as a sorted
-- {a, b} of its present keys, or "(none)" when empty. Enums stay raw (their stored value).
function Sl.FormatSchemaValue(row, v)
  if v == nil then return "nil" end
  if row and row.fmt and type(v) == "number" then return row.fmt:format(v) end
  if row and row.type == "boolean" then return v and "true" or "false" end
  if row and row.type == "table" then
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k, on in pairs(v) do if on then keys[#keys + 1] = tostring(k) end end
    table.sort(keys)
    if #keys == 0 then return "(none)" end
    return "{" .. table.concat(keys, ", ") .. "}"
  end
  return tostring(v)
end

-- Shared coloured `key = value` line — gold key, white value, ` = ` left default — reused by the
-- list rows and the get/set echo so the colouring can't drift (slash-commands-§5).
function Sl.FormatKV(path, valueStr)
  return ("|cffffff00%s|r = |cffffffff%s|r"):format(tostring(path), tostring(valueStr))
end

-- Declared group order for `/lh list` (slash-commands-§5 "stable, declared page order"). LootHistory
-- is a single-panel addon, so its schema groups (the panel section headers) stand in for the
-- standard's `[page]` headers; any group not named here is appended in first-seen order.
local LIST_GROUP_ORDER = { "Master Controls", "Data Collection" }

-- Build the `/lh list` lines (tag-less content; CliList prints each through NS.Print, which
-- prepends the cyan tag) as a pure array, so the output shape is unit-testable without capturing
-- chat. Header green, [group] headers azure, value rows via FormatKV — two-space indent on group
-- headers, four-space on value rows (slash-commands-§5).
function Sl:BuildListLines()
  local lines = { "|cff33ff99Available settings|r" }

  local byGroup, seenOrder = {}, {}
  for _, row in ipairs(NS.Schema.Schema) do
    local g = row.group or "?"
    if not byGroup[g] then byGroup[g] = {}; seenOrder[#seenOrder + 1] = g end
    byGroup[g][#byGroup[g] + 1] = row
  end

  local emitted = {}
  local function emit(g)
    if emitted[g] or not byGroup[g] then return end
    emitted[g] = true
    lines[#lines + 1] = "  |cff3399ff[" .. g .. "]|r"
    for _, row in ipairs(byGroup[g]) do
      local v = NS.Schema:Get(row.path)
      lines[#lines + 1] = "    " .. Sl.FormatKV(row.path, Sl.FormatSchemaValue(row, v))
    end
  end

  for _, g in ipairs(LIST_GROUP_ORDER) do emit(g) end
  for _, g in ipairs(seenOrder) do emit(g) end
  return lines
end

function Sl:CliList()
  for _, line in ipairs(Sl:BuildListLines()) do print(line) end
end

function Sl:CliGet(arg)
  local path = (strtrim and strtrim(tostring(arg or "")) or tostring(arg or "")):match("^(%S+)")
  if not path then
    print("Usage: /lh get <path>")
    return
  end
  local row = NS.Schema:FindRow(path)
  if not row then
    print("Setting not found: " .. path)
    return
  end
  print(Sl.FormatKV(path, Sl.FormatSchemaValue(row, NS.Schema:Get(path))))
end

function Sl:CliSet(arg)
  local path, raw = tostring(arg or ""):match("^(%S+)%s+(.+)$")
  if not path then
    print("Usage: /lh set <path> <value>  (try /lh list)")
    return
  end
  local row = NS.Schema:FindRow(path)
  if not row then
    print("Setting not found: " .. path)
    return
  end
  local value = raw
  if row.type == "number" then
    value = tonumber(raw)
    if not value then print("expected a number"); return end
  elseif row.type == "boolean" then
    value = (raw == "true" or raw == "1" or raw == "on" or raw == "yes")
  end
  local ok, err = NS.Schema:Set(path, value)
  if ok then
    -- Read back the stored value so the echo reflects any clamping/coercion (slash-commands-§5).
    print(Sl.FormatKV(path, Sl.FormatSchemaValue(row, NS.Schema:Get(path))))
  else
    print("error: " .. tostring(err))
  end
end

-- `/lh version` → the canonical single-line version answer every Ka0s addon shares
-- (slash-commands-§3). Read from the TOC metadata so it can't drift from the packaged manifest,
-- with the in-code constant as fallback.
function Sl:CliVersion()
  local v = (NS.Compat and NS.Compat.GetAddOnMetadata and NS.Compat.GetAddOnMetadata(NS.name, "Version"))
    or NS.version or "?"
  print("v" .. tostring(v))
end

function Sl:CliReset(arg)
  local path = arg and tostring(arg):match("^%S+") or nil
  if not path then print("usage: /lh reset <path>"); return end
  local row = NS.Schema:FindRow(path)
  local def = NS.Schema:Default(path)
  if not row or def == nil then print("unknown setting: " .. path); return end
  NS.Schema:Set(path, def)
  -- Echo through the shared formatter so a table default (excludedSources) reads "(none)", not a
  -- raw "table: 0x..." pointer (slash-commands-§5 value formatting).
  print(path .. " reset to " .. Sl.FormatSchemaValue(row, def))
end

-- Reset every user setting to its default. Covers the schema rows AND the two item-id filter lists
-- (blacklist/whitelist) — the lists are user-configured settings even though they are a storage
-- carve-out (no Schema widget). Non-destructive: history, savedView and window geometry are left
-- untouched (the destructive Sl:ResetEverything handles those).
function Sl:CliResetAll()
  for _, row in ipairs(NS.Schema.Schema) do
    NS.Schema:Set(row.path, row.default)
  end
  if NS.Filters and NS.Filters.ClearAll then NS.Filters:ClearAll() end
  print("all settings reset to defaults")
end
