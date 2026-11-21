-- tests/test_compat_client.lua — core/CompatClient.lua: which client this is, and who the
-- character is on it (clients-§3, forever-quirks-§4; the WoW Forever port, LH-01).
--
-- The client questions (IsForever, IsRetail, ClientKey, ForClient) and the character-name readers
-- (RegionalNames, UnitCharacterName, CharacterKey, RealmKey) are LibKa0s-Compat-1.0 members routed
-- through NS.Compat, each with the stub a degraded install (libs/ missing) answers instead. Every
-- case runs under the active kit profile (KA0S_KIT_CLIENT, retail by default) and asserts the
-- profile's own answer, so the same suite proves both clients (clients-§6).
--
-- Regional names are not part of either kit profile yet (the Forever-shaped mock is LH-02), so the
-- cases that need them plant RegionalUniqueNamesEnabled on the mock set themselves and put it back.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local loadDegraded = dofile("tests/degraded_env.lua")
local lib = M.LibStub("LibKa0s-Compat-1.0", true)

local PROFILE = T.Loader.MockClient.current()

-- Plant `fields` on the mock set `m` for the length of `fn`, then put every one back. NIL plants nil.
local NIL = {}
local function with(m, fields, fn)
  local saved = {}
  for k, v in pairs(fields) do
    saved[k] = { v = rawget(m, k) }
    if v == NIL then m[k] = nil else m[k] = v end
  end
  local ok, err = pcall(fn)
  for k, s in pairs(saved) do m[k] = s.v end
  if not ok then error(err, 0) end
end

local REGIONAL = { RegionalUniqueNamesEnabled = function() return true end }
local function surnamed(unit) if unit then return "Traxex", "Silentshot" end end

-- ── The client ──────────────────────────────────────────────────────────────────────────────

test("CompatClient: the client questions answer the active profile, as the library does", function()
  assertTrue(lib ~= nil, "LibKa0s-Compat-1.0 is vendored and loaded")
  local C = NS.Compat
  for _, name in ipairs({ "IsForever", "IsRetail", "ClientKey", "ForClient" }) do
    assertEqual(type(C[name]), "function", "NS.Compat." .. name .. " is routed")
  end
  assertEqual(C.ClientKey(), PROFILE, "ClientKey is the kit profile")
  assertEqual(C.ClientKey(), lib.ClientKey())
  assertEqual(C.IsForever(), PROFILE == "forever")
  assertEqual(C.IsRetail(), PROFILE == "retail")
  assertEqual(select("#", C.IsForever()), 1, "exactly one boolean")
end)

test("CompatClient: ForClient reads a declaration for this client; nil and both mean both", function()
  local C = NS.Compat
  assertTrue(C.ForClient(nil)); assertTrue(C.ForClient("both"))
  assertEqual(C.ForClient({ "retail" }), PROFILE == "retail")
  assertEqual(C.ForClient({ "forever" }), PROFILE == "forever")
  assertTrue(C.ForClient({ "retail", "forever" })); assertTrue(C.ForClient({ "both" }))
  local ok, err = pcall(C.ForClient, { "classic" })
  assertFalse(ok, "an unknown token raises on every client")
  assertTrue(tostring(err):find("unknown client", 1, true) ~= nil, tostring(err))
end)

test("CompatClient: a degraded install answers the same client through its own stubs", function()
  local ns, _, m = loadDegraded()
  local C = ns.Compat
  assertEqual(C.ClientKey(), PROFILE)
  assertEqual(C.IsForever(), PROFILE == "forever"); assertEqual(C.IsRetail(), PROFILE == "retail")
  assertEqual(C.ForClient({ "forever" }), PROFILE == "forever")
  assertTrue(C.ForClient(nil))
  assertFalse((pcall(C.ForClient, { "classic" })), "the stub raises on an unknown token too")
  assertFalse((pcall(C.ForClient, "retail")), "a bare string other than both raises")
  -- Neither project constant: an unknown client, never read as Forever.
  with(m, { WOW_PROJECT_ID = NIL, WOW_PROJECT_MAINLINE = NIL, WOW_PROJECT_CAMELOT = NIL }, function()
    assertEqual(C.ClientKey(), nil)
    assertFalse(C.IsForever()); assertFalse(C.IsRetail())
    assertFalse(C.ForClient({ "retail" })); assertTrue(C.ForClient("both"))
  end)
end)

-- ── The character ───────────────────────────────────────────────────────────────────────────

test("CompatClient: RegionalNames reads RegionalUniqueNamesEnabled, false where it is absent", function()
  for _, env in ipairs({ { NS.Compat, M, "live" }, { nil, nil, "degraded" } }) do
    local C, m = env[1], env[2]
    if not C then local ns, _, dm = loadDegraded(); C, m = ns.Compat, dm end
    assertFalse(C.RegionalNames(), env[3] .. ": absent reads false")
    with(m, REGIONAL, function() assertTrue(C.RegionalNames(), env[3] .. ": enabled") end)
    with(m, { RegionalUniqueNamesEnabled = function() return false end }, function()
      assertFalse(C.RegionalNames(), env[3] .. ": disabled")
    end)
  end
end)

test("CompatClient: UnitCharacterName joins first name and surname, and never reads a surname as a realm", function()
  local C = NS.Compat
  with(M, { UnitName = surnamed }, function()
    local name, realm = C.UnitCharacterName("NPC")
    assertEqual(name, "Traxex"); assertEqual(realm, "Silentshot", "Retail: the second value is the realm")
    with(M, REGIONAL, function()
      name, realm = C.UnitCharacterName("NPC")
      assertEqual(name, "Traxex Silentshot"); assertEqual(realm, nil)
    end)
  end)
  with(M, { UnitName = function() return "Mock", "" end }, function()
    local name, realm = C.UnitCharacterName("player")
    assertEqual(name, "Mock"); assertEqual(realm, nil, "an empty realm reads nil")
  end)
  with(M, { UnitName = function() return "" end }, function()
    assertEqual(C.UnitCharacterName("target"), nil, "an empty name is no name")
  end)
  assertEqual(C.UnitCharacterName(nil), nil)
end)

test("CompatClient: the degraded UnitCharacterName keeps the name and drops a surname", function()
  local ns, _, m = loadDegraded()
  local C = ns.Compat
  with(m, { UnitName = surnamed }, function()
    local name, realm = C.UnitCharacterName("NPC")
    assertEqual(name, "Traxex"); assertEqual(realm, "Silentshot")
    with(m, REGIONAL, function()
      name, realm = C.UnitCharacterName("NPC")
      assertEqual(name, "Traxex"); assertEqual(realm, nil, "never the surname as a realm")
    end)
  end)
end)

test("CompatClient: CharacterKey and RealmKey are AceDB's keys; nil on a degraded install", function()
  local C = NS.Compat
  assertEqual(C.CharacterKey(), "Mock - Realm", "Retail: Name - Realm")
  assertEqual(C.RealmKey(), "Realm")
  with(M, { UnitName = surnamed }, function()
    with(M, REGIONAL, function()
      assertEqual(C.CharacterKey(), "Traxex Silentshot")
      assertEqual(C.RealmKey(), "Realm", "no C_GameRules: the realm name")
      with(M, {
        C_GameRules = { IsGameRuleActive = function(rule) return rule == 3 end },
        Enum = setmetatable({ GameRule = { HardcoreRuleset = 1, RPRuleset = 2, PvPRuleset = 3 } },
          { __index = M.Enum }),
      }, function()
        assertEqual(C.RealmKey(), "PvP", "regional names: the ruleset")
      end)
    end)
  end)
  with(M, { UnitName = function() return nil end }, function()
    assertEqual(C.CharacterKey(), nil, "nil until the client can answer")
  end)
  local ns = loadDegraded()
  assertEqual(ns.Compat.CharacterKey(), nil); assertEqual(ns.Compat.RealmKey(), nil)
end)
