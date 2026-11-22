-- tests/test_compat_client.lua — core/CompatClient.lua: which client this is, and who the
-- character is on it (clients-§3, forever-quirks-§4; the WoW Forever port, LH-01).
--
-- The client questions (IsForever, IsRetail, ClientKey, ForClient) and the character-name readers
-- (RegionalNames, UnitCharacterName, CharacterKey, RealmKey) are LibKa0s-Compat-1.0 members routed
-- through NS.Compat, each with the stub a degraded install (libs/ missing) answers instead. Every
-- case runs under the active kit profile (KA0S_KIT_CLIENT, retail by default) and asserts the
-- profile's own answer, so the same suite proves both clients (clients-§6).
--
-- Regional names follow the mock's client shape (tests/wow_mock.lua): the Forever mock answers
-- RegionalUniqueNamesEnabled() true and UnitName "Mock", "Mockley"; the Retail mock has no
-- RegionalUniqueNamesEnabled and no surname. A case that needs the other shape plants it on the mock
-- set itself and puts it back.

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
local UNREGIONAL = { RegionalUniqueNamesEnabled = NIL }
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
    assertEqual(C.RegionalNames(), PROFILE == "forever", env[3] .. ": the profile's own answer")
    with(m, UNREGIONAL, function() assertFalse(C.RegionalNames(), env[3] .. ": absent reads false") end)
    with(m, REGIONAL, function() assertTrue(C.RegionalNames(), env[3] .. ": enabled") end)
    with(m, { RegionalUniqueNamesEnabled = function() return false end }, function()
      assertFalse(C.RegionalNames(), env[3] .. ": disabled")
    end)
  end
end)

test("CompatClient: UnitCharacterName answers the profile's own player", function()
  local name, realm = NS.Compat.UnitCharacterName("player")
  if PROFILE == "forever" then
    assertEqual(name, "Mock Mockley", "Forever: first name and surname"); assertEqual(realm, nil)
  else
    assertEqual(name, "Mock", "Retail: the name"); assertEqual(realm, nil, "the player's own realm")
  end
end)

test("CompatClient: UnitCharacterName joins first name and surname, and never reads a surname as a realm", function()
  local C = NS.Compat
  with(M, { UnitName = surnamed }, function()
    with(M, UNREGIONAL, function()
      local name, realm = C.UnitCharacterName("NPC")
      assertEqual(name, "Traxex"); assertEqual(realm, "Silentshot", "Retail: the second value is the realm")
    end)
    with(M, REGIONAL, function()
      local name, realm = C.UnitCharacterName("NPC")
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

-- LH-REV: the degraded stub is the library's body, so a degraded install keys a regional-names
-- character by its whole two-word name too, never the bare first name two alts can share.
test("CompatClient: the degraded UnitCharacterName joins a surname, and never reads it as a realm", function()
  -- red under: the stub dropping the surname, so PlayerKey answers "Traxex" on a degraded install.
  local ns, _, m = loadDegraded()
  local C = ns.Compat
  with(m, { UnitName = surnamed }, function()
    with(m, UNREGIONAL, function()
      local name, realm = C.UnitCharacterName("NPC")
      assertEqual(name, "Traxex"); assertEqual(realm, "Silentshot")
    end)
    with(m, REGIONAL, function()
      local name, realm = C.UnitCharacterName("NPC")
      assertEqual(name, "Traxex Silentshot"); assertEqual(realm, nil, "never the surname as a realm")
      assertEqual(ns.Util.PlayerKey(), "Traxex Silentshot", "the degraded key is the whole name")
    end)
    with(m, { UnitName = function() return "Traxex", "" end }, function()
      with(m, REGIONAL, function() assertEqual(C.UnitCharacterName("NPC"), "Traxex", "no surname: the name") end)
    end)
  end)
end)

test("CompatClient: CharacterKey and RealmKey are AceDB's keys; nil on a degraded install", function()
  local C = NS.Compat
  if PROFILE == "forever" then
    assertEqual(C.CharacterKey(), "Mock Mockley", "Forever: first name and surname")
  else
    assertEqual(C.CharacterKey(), "Mock - Realm", "Retail: Name - Realm")
  end
  assertEqual(C.RealmKey(), "Realm", "no C_GameRules in the mock: the realm name on either client")
  with(M, UNREGIONAL, function() assertEqual(C.CharacterKey(), "Mock - Realm", "without regional names") end)
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

-- ── Containers and the bank (Compat minor 6, LibKa0s#101; K101-LH-REV) ───────────────────────
-- The degraded stubs are the library's bodies, as the client stubs are: a degraded install still
-- scans the real bags (the Keyring on Forever), arms and reads the bank, and waits for a partly
-- loaded one. Stubs that degraded to nothing made every deposit read as an UNTRACKED loss.

local function sameList(a, b, what)
  assertEqual(#a, #b, what .. ": count")
  for i = 1, #a do assertEqual(a[i], b[i], what .. "[" .. i .. "]") end
end

test("CompatClient: a degraded install reads the container groups and the bank as the library does", function()
  -- red under: the stubs answering bags 0..5, no bank, no banker kind and every bank read nil.
  local ns, _, m = loadDegraded()
  local C, D = NS.Compat, ns.Compat
  local want, got = lib.ContainerGroups(), D.ContainerGroups()
  for _, group in ipairs({ "bags", "bank", "accountBank" }) do sameList(got[group], want[group], group) end
  assertTrue(#got.bank > 0, "the degraded install reads the bank")
  if PROFILE == "forever" then
    assertEqual(got.bags[1], -1, "the Keyring is a bag on Forever")
    assertEqual(#got.accountBank, 0, "no warband bank on Forever (R1)")
  end
  sameList(ns.Constants.BAG_IDS, NS.Constants.BAG_IDS, "C.BAG_IDS"); sameList(ns.Constants.BANK_IDS, NS.Constants.BANK_IDS, "C.BANK_IDS")
  sameList(ns.Constants.WARBAND_TAB_IDS, NS.Constants.WARBAND_TAB_IDS, "C.WARBAND_TAB_IDS")
  for _, name in ipairs({ "Banker", "CharacterBanker", "AccountBanker", "MailInfo" }) do
    local t = m.Enum.PlayerInteractionType[name]
    if t ~= nil then assertEqual(D.BankerKind(t), C.BankerKind(t), "BankerKind " .. name) end
  end
  assertEqual(D.BankerKind(m.Enum.PlayerInteractionType.Banker), "character")
  assertEqual(D.BankerKind(nil), nil); assertEqual(D.BankerKind("Banker"), nil)
  assertEqual(D.CanViewCharacterBank(), C.CanViewCharacterBank(), "CanViewCharacterBank")
  assertEqual(D.NumPurchasedBankTabs("Character"), C.NumPurchasedBankTabs("Character"))
  assertEqual(D.NumPurchasedBankTabs(7), nil, "a non-string name answers nil")
  -- UnreadyBankContainers: the three arms (a memory, a first visit with a count, neither).
  sameList(D.UnreadyBankContainers({ [6] = 28, [7] = 0, [8] = 0 }, { [6] = 28, [7] = 28 }), { 7 }, "memory")
  assertEqual(D.UnreadyBankContainers({ [6] = 28, [7] = 28 }, { [6] = 28, [7] = 28 }), nil, "ready")
  local short = D.UnreadyBankContainers({ [6] = 28, [7] = 0 }, nil, 2)
  assertTrue(short and short.short, "a first visit short of the bought tabs waits")
  assertEqual(#short, 0, "the marker has no array part")
  assertEqual(D.UnreadyBankContainers({ [6] = 28, [7] = 0 }, nil, nil), nil, "no memory, no count: ready")
  assertEqual(D.UnreadyBankContainers({ [6] = 0 }, { [6] = 0 }, 1).short, true, "a memory of no slots is none")
end)

-- ── The build stamp (the probe verbs, LH-13) ─────────────────────────────────────────────────

test("CompatClient: ClientBuild answers GetBuildInfo's version and build, nil without it", function()
  -- red under: ClientBuild missing, or answering the interface number (a stamp, never a test).
  local C = NS.Compat
  local version, build = M.GetBuildInfo()
  local v, b = C.ClientBuild()
  assertEqual(v, version); assertEqual(b, build)
  assertEqual(v, PROFILE == "forever" and "1.60.1" or "12.1.5", "the profile's own version")
  with(M, { GetBuildInfo = NIL }, function() assertEqual(C.ClientBuild(), nil) end)
  local ns, _, m = loadDegraded()
  local dv, db = ns.Compat.ClientBuild()
  assertEqual(dv, version); assertEqual(db, build)
  with(m, { GetBuildInfo = NIL }, function() assertEqual(ns.Compat.ClientBuild(), nil) end)
end)
