local addonName, NS = ...
NS.Slash = NS.Slash or {}
local Sl = NS.Slash

local function tag()
  return NS.PREFIX .. " "
end

-- Confirm dialogs for destructive actions. Registered once; in-game only.
if type(StaticPopupDialogs) == "table" then
  StaticPopupDialogs["KA0S_LOOTHISTORY_PURGE"] = {
    text = "Delete ALL Ka0s Loot History records? This cannot be undone.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
      if NS.Database and NS.Database.Purge then NS.Database:Purge() end
      print(tag() .. "history purged.")
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
end

-- Full reset: wipe history AND restore every setting to its default.
function Sl:ResetEverything()
  if NS.Database and NS.Database.Purge then NS.Database:Purge() end
  Sl:CliResetAll()   -- resets settings + prints the confirmation line
  if NS.Panel and NS.Panel.Refresh then NS.Panel:Refresh() end
end

function Sl:Register()
  NS.addon:RegisterChatCommand("lh", function(input) Sl:OnSlash(input) end)
  NS.addon:RegisterChatCommand("loothistory", function(input) Sl:OnSlash(input) end)
end

-- Bare `/lh` prints the help index (Ka0s standard §7.4). Window display is explicit:
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
  print(tag() .. "unknown command '" .. tostring(verb) .. "'")
  Sl:PrintHelp()
end

-- Help index generated from NS.COMMANDS (Ka0s standard §7.4): a version/alias header,
-- then one prefixed row per command — gold command, em-dash, white description.
function Sl:PrintHelp()
  print(tag() .. "v" .. (NS.version or "") ..
    " slash commands (|cffffff00/loothistory|r is an alias for |cffffff00/lh|r):")
  for _, cmd in ipairs(NS.COMMANDS) do
    print(tag() .. ("|cffffff00/lh %s|r — |cffffffff%s|r"):format(cmd.name, cmd.desc))
  end
end

-- --- Schema-driven CLI (basic; full coercion/validation in Milestone 5) ---

function Sl:CliGet(arg)
  local path = arg and strtrim and strtrim(arg) or arg
  if not path or path == "" then return Sl:CliList() end
  local v = NS.Schema:Get(path)
  print(tag() .. path .. " = " .. tostring(v))
end

function Sl:CliSet(arg)
  local path, raw = tostring(arg or ""):match("^(%S+)%s+(.+)$")
  if not path then
    print(tag() .. "usage: /lh set <path> <value>")
    return
  end
  local row = NS.Schema:FindRow(path)
  if not row then
    print(tag() .. "unknown setting: " .. path)
    return
  end
  local value = raw
  if row.type == "number" then
    value = tonumber(raw)
    if not value then print(tag() .. "expected a number"); return end
  elseif row.type == "boolean" then
    value = (raw == "true" or raw == "1" or raw == "on" or raw == "yes")
  end
  local ok, err = NS.Schema:Set(path, value)
  if ok then
    print(tag() .. path .. " = " .. tostring(value))
  else
    print(tag() .. "error: " .. tostring(err))
  end
end

function Sl:CliList()
  print(tag() .. "settings:")
  for _, row in ipairs(NS.Schema.Schema) do
    print(string.format("  %s = %s", row.path, tostring(NS.Schema:Get(row.path))))
  end
end

function Sl:CliReset(arg)
  local path = arg and tostring(arg):match("^%S+") or nil
  if not path then print(tag() .. "usage: /lh reset <path>"); return end
  local def = NS.Schema:Default(path)
  if def == nil then print(tag() .. "unknown setting: " .. path); return end
  NS.Schema:Set(path, def)
  print(tag() .. path .. " reset to " .. tostring(def))
end

function Sl:CliResetAll()
  for _, row in ipairs(NS.Schema.Schema) do
    NS.Schema:Set(row.path, row.default)
  end
  print(tag() .. "all settings reset to defaults")
end
