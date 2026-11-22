local _, NS = ...
-- core/CompatClient.lua — which client this is, and who the character is on it (clients-§3,
-- forever-quirks-§4; the WoW Forever port, Ka0sAddonsCommonTasks
-- docs/2026-11-22-LOOTHISTORY_BANKLEDGER_FOREVER_PORT/00_DESIGN.md, "Client routing").
--
-- WHY HERE. The client questions (IsForever, IsRetail, ClientKey, ForClient) and the character-name
-- readers (RegionalNames, UnitCharacterName, CharacterKey, RealmKey) are LibKa0s-Compat-1.0
-- members. This file routes them onto NS.Compat, each with the stub a degraded install (libs/
-- missing) answers instead, so no other file asks which client it is on or how a name is spelled.
-- The stubs below are the ONE place outside the library that reads a WOW_PROJECT_* constant or
-- RegionalUniqueNamesEnabled, and ClientBuild the one that reads GetBuildInfo;
-- tests/test_compat_routing.lua fails any other file that does.
--
-- THE RULES are core/Compat.lua's: globals read bare at call time, never captured at load; a
-- secret answer is never concatenated or compared; a missing API or library answers its documented
-- absent value, never a raise (ForClient's unknown token is the one deliberate raise, on every
-- client, so a typo in a declaration cannot ship silently). Feature presence is a declaration read
-- through ForClient (clients-§4), never feature detection.
--
-- LOAD-BEARING POSITION: straight after core/Compat.lua (whose NS.Compat it adds to) and straight
-- before core/SimSeam.lua, which wraps every NS.Compat member at file load; below the seam these
-- members would escape the wrap.

NS.Compat = NS.Compat or {}
local Compat = NS.Compat
local CompatLib = LibStub and LibStub("LibKa0s-Compat-1.0", true)

-- ── The client ──────────────────────────────────────────────────────────────────────────────
-- The stub is the library's body, both constants read bare at call time; the nil guard keeps a
-- client with neither constant from reading as Forever (WOW_PROJECT_CAMELOT is nil on Retail).

local function isForeverStub()
  return WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
end

local function isRetailStub()
  return WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and not isForeverStub()
end

local function clientKeyStub()
  if isForeverStub() then return "forever" end
  if isRetailStub() then return "retail" end
  return nil
end

local CLIENT_TOKENS = { retail = true, forever = true, both = true }

local function forClientStub(clients)
  if clients == nil or clients == "both" then return true end
  if type(clients) ~= "table" then error('ForClient: unknown client "' .. tostring(clients) .. '"', 2) end
  local key, hit = clientKeyStub(), false
  for _, token in ipairs(clients) do
    if not CLIENT_TOKENS[token] then error('ForClient: unknown client "' .. tostring(token) .. '"', 2) end
    hit = hit or token == "both" or token == key
  end
  return hit
end

-- Whether this is a WoW Forever client. Exactly one boolean.
Compat.IsForever = CompatLib and CompatLib.IsForever or isForeverStub

-- Whether this is a Retail client (the mainline project id and NOT Forever). Exactly one boolean.
Compat.IsRetail = CompatLib and CompatLib.IsRetail or isRetailStub

-- The client's key: "retail", "forever", or nil when the project constants say neither. The key
-- every per-client table in this addon is picked by, once (clients-§5).
Compat.ClientKey = CompatLib and CompatLib.ClientKey or clientKeyStub

-- Whether a `clients` declaration (nil, "both", or an array of "retail" / "forever" / "both")
-- includes this client; nil means both (clients-§4). An unknown token raises on any client.
Compat.ForClient = CompatLib and CompatLib.ForClient or forClientStub

-- ── The character ───────────────────────────────────────────────────────────────────────────

local function isSecret(v)
  if CompatLib and CompatLib.IsSecret then return CompatLib.IsSecret(v) end
  return issecretvalue ~= nil and issecretvalue(v) and true or false
end

-- A plain (non-secret), non-empty string, or nil.
local function plainString(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

-- Whether character names are unique per region (true on WoW Forever): a character is then its
-- first name and surname together and carries no realm. False where RegionalUniqueNamesEnabled is
-- absent. One boolean.
Compat.RegionalNames = CompatLib and CompatLib.RegionalNames or function()
  return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true
end

-- A unit's whole character name and its realm: "Traxex Silentshot" and a nil realm with regional
-- names (WoW Forever, where UnitName's second value is the SURNAME); UnitName's name and realm
-- otherwise (the realm nil on the player's own). With the library absent, UnitName's first value,
-- and its second as the realm only without regional names: never a surname read as a realm. The
-- name is nil for no unit, a secret or ""; the realm nil for a secret or "".
function Compat.UnitCharacterName(unit)
  local read = CompatLib and CompatLib.UnitCharacterName or UnitName
  if not (unit and read) then return nil end
  local name, realm = read(unit)
  name = plainString(name)
  if not name then return nil end
  realm = plainString(realm)
  if not CompatLib and Compat.RegionalNames() then realm = nil end
  return name, realm
end

-- The player's character key, the one AceDB-3.0 40 keys profiles by: "First Surname" with regional
-- names, "Name - Realm" otherwise. Nil until the client can answer, for a secret, and with the
-- library absent (no rung is re-implemented here).
function Compat.CharacterKey()
  if not (CompatLib and CompatLib.CharacterKey) then return nil end
  return plainString(CompatLib.CharacterKey())
end

-- The player's realm key, the one AceDB-3.0 40 keys realm data by: the ruleset ("Hardcore",
-- "RP-PvP", "RP", "PvP" or "PvE") with regional names, otherwise the realm's name. Nil until the
-- client can answer, for a secret, and with the library absent.
function Compat.RealmKey()
  if not (CompatLib and CompatLib.RealmKey) then return nil end
  return plainString(CompatLib.RealmKey())
end

-- The client's version and build as it names them ("1.60.1", "71037"), or nil without
-- GetBuildInfo. A STAMP for a record that has to say which build answered it (the probe verbs,
-- modules/Probe.lua, ruling R4), never a test: clients-§3 bans choosing behavior by a build or an
-- interface number, and ClientKey() is the one client question.
function Compat.ClientBuild()
  if type(GetBuildInfo) ~= "function" then return nil end
  local version, build = GetBuildInfo()
  return plainString(version), plainString(build)
end
