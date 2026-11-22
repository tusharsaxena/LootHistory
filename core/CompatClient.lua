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
-- otherwise (the realm nil on the player's own). With the library absent the stub is the library's
-- body: with regional names the second value is joined on as the surname (the bare first name when
-- there is none), never read as a realm, so a degraded install keys a character as the library
-- does. The name is nil for no unit, a secret or ""; the realm nil for a secret or "".
function Compat.UnitCharacterName(unit)
  local read = CompatLib and CompatLib.UnitCharacterName or UnitName
  if not (unit and read) then return nil end
  local name, realm = read(unit)
  name = plainString(name)
  if not name then return nil end
  realm = plainString(realm)
  if not CompatLib and Compat.RegionalNames() then
    if realm then name = name .. " " .. realm end
    realm = nil
  end
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

-- ── Containers and the bank (Compat minor 6, LibKa0s#101; K101-LH-02) ───────────────────────
-- The container groups and the bank readiness reads are the library's: one copy for BankLedger,
-- LootHistory and OutfitterReborn, which had drifted apart (Ka0sAddonsCommonTasks
-- docs/2026-11-22-LIBKA0S_101_CONTAINER_READER/). The deadline (R.READY_WAIT) and the readiness
-- memory (holdings meta.bankSlots) stay in modules/Reconciler.lua.
--
-- THE STUBS ARE THE LIBRARY'S BODIES, as the client stubs above are (K101-LH-REV): a degraded install
-- (libs/ missing) still scans the real bags (the Keyring on Forever, R5), arms and reads the bank, and
-- waits for a partly loaded one, as it did before the library held these reads. A stub that degraded
-- to nothing left the bank unarmed, so every deposit read as an UNTRACKED loss, and dropped the
-- Keyring, so a key moved onto it did too. tests/test_compat_client.lua pins each stub against the
-- library on both kit profiles, so the two copies cannot drift apart unseen.

local BAG_PATTERNS     = { "^Backpack$", "^Bag_%d+$", "^ReagentBag$" }
local KEYRING_PATTERNS = { "^Backpack$", "^Bag_%d+$", "^ReagentBag$", "^Keyring$" }
local BANK_PATTERNS    = { "^Bank$", "^BankBag_%d+$", "^CharacterBankTab_%d+$" }
local STUB_PATTERNS = {
  retail  = { bags = BAG_PATTERNS,     bank = BANK_PATTERNS, accountBank = { "^AccountBankTab_%d+$" } },
  forever = { bags = KEYRING_PATTERNS, bank = BANK_PATTERNS, accountBank = {} },
}
local STUB_NO_CLIENT = { bags = BAG_PATTERNS, bank = BANK_PATTERNS, accountBank = {} }
local STUB_BAGS = { 0, 1, 2, 3, 4, 5 }

local function idsMatching(members, patterns)
  local seen, ids = {}, {}
  if type(members) ~= "table" then return ids end
  for name, value in pairs(members) do
    if type(name) == "string" and type(value) == "number" and not seen[value] then
      for _, pattern in ipairs(patterns) do
        if name:find(pattern) then
          seen[value] = true
          ids[#ids + 1] = value
          break
        end
      end
    end
  end
  table.sort(ids)
  return ids
end

-- The container ids of each group on this client, { bags, bank, accountBank }, each sorted and
-- de-duplicated, matched by anchored Enum.BagIndex member names. Fresh tables on every call.
Compat.ContainerGroups = CompatLib and CompatLib.ContainerGroups or function()
  local row = STUB_PATTERNS[Compat.ClientKey()] or STUB_NO_CLIENT
  local members = Enum and Enum.BagIndex
  local bags = idsMatching(members, row.bags)
  if #bags == 0 then
    for i, id in ipairs(STUB_BAGS) do bags[i] = id end
  end
  return { bags = bags, bank = idsMatching(members, row.bank), accountBank = idsMatching(members, row.accountBank) }
end

-- The pattern rows, one per client, published for the suites (a copy: writing to it changes nothing).
Compat.CONTAINER_PATTERNS_BY_CLIENT = CompatLib and CompatLib.CONTAINER_PATTERNS_BY_CLIENT or {}

-- Whether this banker shows the character bank: true, false, or nil when the build cannot tell (no
-- C_Bank.CanViewBank, no Enum.BankType.Character, or a secret). THREE-VALUED: the caller reads nil as
-- viewable (R:BankState compares with false, the lead's call 3). A present API's own answer is
-- normalized to a boolean, as the library does.
Compat.CanViewCharacterBank = CompatLib and CompatLib.CanViewCharacterBank or function()
  local fn = C_Bank and C_Bank.CanViewBank
  local bankType = Enum and Enum.BankType and Enum.BankType.Character
  if not fn or bankType == nil then return nil end
  local answer = fn(bankType)
  if isSecret(answer) then return nil end
  return answer and true or false
end

-- How many tabs the account bought for a bank type named as Enum.BankType names it ("Character",
-- "Account"), or nil where the API, the member or a plain number answer is absent.
Compat.NumPurchasedBankTabs = CompatLib and CompatLib.NumPurchasedBankTabs or function(bankTypeName)
  if type(bankTypeName) ~= "string" then return nil end
  local fn = C_Bank and C_Bank.FetchNumPurchasedBankTabs
  local bankType = Enum and Enum.BankType and Enum.BankType[bankTypeName]
  if not fn or bankType == nil then return nil end
  local n = fn(bankType)
  if isSecret(n) or type(n) ~= "number" then return nil end
  return n
end

local STUB_BANKER_KINDS = {
  { name = "Banker",          kind = "character" },
  { name = "CharacterBanker", kind = "character" },
  { name = "AccountBanker",   kind = "account" },
}

-- "character" for a Banker or CharacterBanker interaction type, "account" for an AccountBanker, nil
-- otherwise. What each kind arms is the Reconciler's call (the account bank is Retail's alone, R1).
Compat.BankerKind = CompatLib and CompatLib.BankerKind or function(interactionType)
  if isSecret(interactionType) or type(interactionType) ~= "number" then return nil end
  local types = Enum and Enum.PlayerInteractionType
  if type(types) ~= "table" then return nil end
  for _, entry in ipairs(STUB_BANKER_KINDS) do
    local value = types[entry.name]
    if value ~= nil and value == interactionType then return entry.kind end
  end
  return nil
end

local function positive(n) return type(n) == "number" and n > 0 end

local function remembersSlots(memory)
  if type(memory) ~= "table" then return false end
  for _, slots in pairs(memory) do
    if positive(slots) then return true end
  end
  return false
end

-- Pure: the bank container ids not ready yet (a remembered container now at 0 slots), the short
-- marker on a first visit with fewer containers answering than `purchased`, or nil when ready.
Compat.UnreadyBankContainers = CompatLib and CompatLib.UnreadyBankContainers or function(shape, memory, purchased)
  if type(shape) ~= "table" then shape = {} end
  if remembersSlots(memory) then
    local out
    for id, slots in pairs(shape) do
      if type(id) == "number" and slots == 0 and positive(memory[id]) then
        out = out or {}
        out[#out + 1] = id
      end
    end
    if out then table.sort(out) end
    return out
  end
  if type(purchased) ~= "number" then return nil end
  local answering = 0
  for _, slots in pairs(shape) do
    if positive(slots) then answering = answering + 1 end
  end
  if answering < purchased then return { short = true, answering = answering, purchased = purchased } end
  return nil
end
