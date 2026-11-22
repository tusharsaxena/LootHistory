-- testkit/mock_client.lua -- the kit's client profiles: which game client the mock set pretends to be.
--
-- There are exactly two. `retail` is the default and is the LIVE Retail shape: `WOW_PROJECT_ID` is
-- 1 (`WOW_PROJECT_MAINLINE`) and `WOW_PROJECT_CAMELOT` is nil, because the constant does not exist
-- on Retail. `forever` is WoW Forever (client 1.60.1, build 70790, interface 16001), where
-- `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT == 18`.
--
-- A third "neither constant exists" client is deliberately NOT a profile. A case that wants it sets
-- the mocks directly, so the unusual shape is visible in the case that needs it.
--
-- `Loader` applies the profile once to every mock set it builds an environment for, so a suite sees
-- the profile without asking. `KA0S_KIT_CLIENT=forever lua tests/run.lua` runs the whole suite
-- under Forever; an unknown value raises rather than falling back to retail, because a typo that
-- silently ran the default would report green for a profile that never ran.
--
-- THE CONTAINER AND BANK SHAPE (kit revision 60, LibKa0s#101). Each profile also carries its client's
-- `Enum.BagIndex`, as BagIndexConstantsDocumentation.lua lists it, `Enum.BankType` (Character 0,
-- Guild 1, Account 2 on both) and `C_Bank.CanViewBank`. Retail 12.1.5 has 20 BagIndex members: six
-- character bank tabs (6..11) and five account bank tabs (12..16). WoW Forever 1.60.1 has 27: nine of
-- each (6..14 and 15..23). Both carry Keyring -1, Backpack 0, Bag_1..4, ReagentBag 5 and the two type
-- constants Characterbanktab -2 and Accountbanktab -3. `CanViewBank` answers true for the character
-- bank on both, and for the account bank on Retail only (Forever has no warband bank); Guild and any
-- other number answer false, and a non-number raises the client's usage error.
--
-- A CONSUMER'S OWN MOCK WINS, global by global. The profile installs an `Enum` carrying `BagIndex`
-- and `BankType` only when neither the mock set nor the real global table has an `Enum`, and a
-- `C_Bank` only when neither has a `C_Bank`. An `Enum` or a `C_Bank` the consumer built is never
-- touched, not even to add a member it left out: a set whose `Enum.BagIndex` a case cleared before
-- the environment was built is testing exactly that absence. What the profile installed it
-- remembers by identity, so applying a second profile replaces its own tables (inside its own
-- `Enum`, only the members it put there, so a `BindingSet` that `mock_bindings.lua` merged in stays)
-- and never one a consumer put in their place. Every apply builds fresh tables, so a case that
-- mutates them cannot reach another mock set.

local MockClient = {}

local BANK_TYPE = { Character = 0, Guild = 1, Account = 2 }

local PROFILES = {
  retail = {
    consts = { WOW_PROJECT_ID = 1, WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CAMELOT = false },
    build  = { "12.1.5", "70783", "Nov  3 2026", 120105 },
    absent = { "SetDesaturation" },
    bankTabs = { character = 6, account = 5 },
    canView  = { [BANK_TYPE.Character] = true, [BANK_TYPE.Account] = true },
  },
  forever = {
    consts = { WOW_PROJECT_ID = 18, WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CAMELOT = 18 },
    build  = { "1.60.1", "70790", "Nov  3 2026", 16001 },
    absent = { "GetSpecialization", "GetSpecializationInfo", "GetActiveSpecGroup", "GetTalentInfo",
               "SetDesaturation" },
    bankTabs = { character = 9, account = 9 },
    canView  = { [BANK_TYPE.Character] = true, [BANK_TYPE.Account] = false },
  },
}

local active

-- The tables an apply installed, by identity. Weak-keyed: a dropped mock set takes them with it.
local installed = setmetatable({}, { __mode = "k" })

local function own(t)
  installed[t] = true
  return t
end

local function bagIndexFor(tabs)
  local e = {
    Accountbanktab = -3, Characterbanktab = -2, Keyring = -1,
    Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5,
  }
  for i = 1, tabs.character do e["CharacterBankTab_" .. i] = 5 + i end
  for i = 1, tabs.account do e["AccountBankTab_" .. i] = 5 + tabs.character + i end
  return e
end

local function bankFor(canView)
  return {
    CanViewBank = function(bankType)
      if type(bankType) ~= "number" then
        error("Usage: local canViewBank = C_Bank.CanViewBank(bankType)", 2)
      end
      return canView[bankType] == true
    end,
  }
end

-- A global the profile may write: absent from the set and from `_G`, or one an earlier apply put there.
local function ours(mocks, key)
  local current = mocks[key]
  if current == nil then return rawget(_G, key) == nil end
  return installed[current] == true
end

-- Inside the profile's own `Enum`: a member it put there, or one nobody has.
local function fillable(current) return current == nil or installed[current] == true end

local function applyContainers(mocks, profile)
  if ours(mocks, "Enum") then
    local enum = mocks.Enum or own({})
    mocks.Enum = enum
    if fillable(enum.BagIndex) then enum.BagIndex = own(bagIndexFor(profile.bankTabs)) end
    if fillable(enum.BankType) then
      local bankType = {}
      for k, v in pairs(BANK_TYPE) do bankType[k] = v end
      enum.BankType = own(bankType)
    end
  end
  if ours(mocks, "C_Bank") then mocks.C_Bank = own(bankFor(profile.canView)) end
end

local function resolve(name)
  name = name or os.getenv("KA0S_KIT_CLIENT") or "retail"
  if not PROFILES[name] then
    error('MockClient: unknown client profile "' .. tostring(name) .. '" (expected "retail" or "forever")', 3)
  end
  return name
end

--- Stamp the profile `name` (default: `KA0S_KIT_CLIENT`, else "retail") onto the mock set `mocks`.
--- Returns the resolved name. An unknown name raises.
function MockClient.apply(mocks, name)
  name = resolve(name)
  local profile = PROFILES[name]
  for key, value in pairs(profile.consts) do
    if value == false then mocks[key] = nil else mocks[key] = value end
  end
  local build = profile.build
  mocks.GetBuildInfo = function() return build[1], build[2], build[3], build[4] end
  for _, key in ipairs(profile.absent) do mocks[key] = nil end
  applyContainers(mocks, profile)
  active = name
  return name
end

--- The profile last applied, or the one a fresh apply would choose. "retail" | "forever".
function MockClient.current()
  return active or resolve(nil)
end

return MockClient
