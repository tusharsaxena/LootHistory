local addonName, NS = ...
NS.Slash = NS.Slash or {}
local Sl = NS.Slash

local function tag()
  return "|cff33ff99" .. addonName .. "|r "
end

-- Confirm dialog for /lh purge (destructive). Registered once; in-game only.
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
end

function Sl:Register()
  NS.addon:RegisterChatCommand("lh", function(input) Sl:OnSlash(input) end)
  NS.addon:RegisterChatCommand("loothistory", function(input) Sl:OnSlash(input) end)
end

-- DEVIATION (docs/REQUIREMENTS §8): empty input toggles the window rather than printing help.
function Sl:OnSlash(input)
  if input == nil or input:match("^%s*$") then
    return NS.Browser:Toggle()
  end
  local verb, rest = input:match("^(%S+)%s*(.-)$")
  verb = verb and verb:lower()
  for _, cmd in ipairs(NS.COMMANDS) do
    if cmd.name == verb then return cmd.fn(rest) end
  end
  Sl:PrintHelp()
end

function Sl:PrintHelp()
  print(tag() .. "commands:")
  for _, cmd in ipairs(NS.COMMANDS) do
    print(string.format("  /lh %s - %s", cmd.name, cmd.desc))
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
