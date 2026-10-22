local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- core/SimSeam.lua (LootHistory#37, LibKa0s#54): LibKa0s-Sim-1.0's answer seam over NS.Compat.
--
-- The seam wraps every NS.Compat function member but the PURE ones at file load, straight after
-- core/Compat.lua (H2). While a simulation runs, a wrapped member answers through its provider; a
-- GUARDED member never reaches the client at all. A member that escapes the wrap (added after the
-- seam was made, or replaced by assignment) is what Unwrapped() lists, and this suite asserts that
-- list is empty once the whole addon has loaded.
--
-- This slot runs after tests/test_dispatch.lua, with the whole addon loaded and brought up, so a
-- suite before it that swapped a Compat member and failed to put the wrapper back shows here too.

local Sim = M.LibStub("LibKa0s-Sim-1.0", true)
local loadDegraded = dofile("tests/degraded_env.lua")

-- Every function member of NS.Compat, classified by hand. A new member fails the snapshot case
-- until it is classified here, which is the point: whether it answers for nobody (pure), must never
-- reach the client while a simulation runs (guarded), or is wrapped (answered live until a provider
-- is set) is a decision, and a member that slips in unclassified is one nobody made.
local CLASSIFIED = {
  -- pure: text and parse helpers, the tooltip family and the four hook installers (req-lh-sim §2.2)
  FoldNBSP = "pure", IsAuctionHouseMail = "pure", DecodeGUID = "pure", BindState = "pure",
  BestBound = "pure", CurrencyLinkID = "pure", AuctionMailKind = "pure", CurrencySourceName = "pure",
  InteractionType = "pure",
  ShowItemTooltip = "pure", ShowCurrencyTooltip = "pure", ShowTextTooltip = "pure",
  ShowAmountTooltip = "pure", ShowLinesTooltip = "pure", ShowTintedTooltip = "pure", HideTooltip = "pure",
  HookUseContainerItem = "pure", HookGetQuestReward = "pure", HookSecure = "pure", HookSecureMember = "pure",
  -- guarded: the one member that changes client state (it expands and collapses currency headers)
  ListCurrencies = "guarded",
  -- wrapped: answered live until a provider is set
  GetActiveKeystoneLevel = "wrapped", InPartyInstance = "wrapped", NumLootItems = "wrapped",
  LootSourceGUID = "wrapped", Zone = "wrapped", PlayerMapID = "wrapped", InInstance = "wrapped",
  InGroup = "wrapped", PlayerInCombat = "wrapped", ContainerItemHasLoot = "wrapped",
  CurrentQuestID = "wrapped", IsSpellTargeting = "wrapped", GetSpellName = "wrapped",
  GetMailHeader = "wrapped", GetItemInfo = "wrapped", ScanBound = "wrapped", ItemBindState = "wrapped",
  GetItemExtras = "wrapped", GetCurrencyInfoFromLink = "wrapped", CurrencyListChanged = "wrapped",
  CurrencyCategory = "wrapped", ListedCurrencyID = "wrapped", CurrencyQuality = "wrapped",
  CurrencyName = "wrapped", GetItemTypeInfo = "wrapped", GetItemSellPrice = "wrapped",
  GearItemLevel = "wrapped", CurrencyBound = "wrapped", GetContainerNumSlots = "wrapped",
  GetContainerSlot = "wrapped", GetMoney = "wrapped", GetWarbandMoney = "wrapped",
  GetInventoryItem = "wrapped", BagInventorySlot = "wrapped", InCombatLockdown = "wrapped",
  PlayerClassFile = "wrapped", IsConsumable = "wrapped", CurrencyIsAccountWide = "wrapped",
  ScanInbox = "wrapped", ReadSendMail = "wrapped", ScanOwnedAuctions = "wrapped",
  ItemLocationID = "wrapped", TradeTargetKey = "wrapped", LatestCurrencyTransfer = "wrapped",
}

local function sortedKeys(t, want)
  local out = {}
  for k, v in pairs(t) do if want == nil or v == want then out[#out + 1] = k end end
  table.sort(out)
  return out
end

local function functionMembers()
  local out = {}
  for k, v in pairs(NS.Compat) do if type(v) == "function" then out[k] = true end end
  return out
end

test("SimSeam: NS.SimSeam is the library's seam over NS.Compat, with the host table beside it", function()
  assertTrue(Sim ~= nil, "LibKa0s-Sim-1.0 is loaded headless")
  assertTrue(type(NS.SimSeam) == "table", "core/SimSeam.lua publishes NS.SimSeam")
  for _, m in ipairs({ "SetProvider", "Live", "Keys", "Unwrapped" }) do
    assertTrue(type(NS.SimSeam[m]) == "function", "the seam carries " .. m)
  end
  assertTrue(type(NS.SimHost) == "table", "the host keeps its own table (OWNER_SCOPE C.4)")
end)

test("SimSeam: every non-PURE function member of NS.Compat is wrapped and Unwrapped() is empty after the whole addon loads",
function()
  assertEqual(#NS.SimSeam:Unwrapped(), 0, "every Compat member is wrapped or pure: "
    .. table.concat(NS.SimSeam:Unwrapped(), ", "))
  local keys = {}
  for _, k in ipairs(NS.SimSeam:Keys()) do keys[k] = true end
  for k in pairs(functionMembers()) do
    if CLASSIFIED[k] == "pure" then
      assertFalse(keys[k], k .. " is pure and must not be wrapped")
    else
      assertTrue(keys[k], k .. " is not pure and must be wrapped")
    end
  end
end)

test("SimSeam: a member snapshot: a new Compat member must be classified", function()
  local live, missing, stale = functionMembers(), {}, {}
  for k in pairs(live) do if not CLASSIFIED[k] then missing[#missing + 1] = k end end
  for k in pairs(CLASSIFIED) do if not live[k] then stale[#stale + 1] = k end end
  table.sort(missing); table.sort(stale)
  assertEqual(table.concat(missing, ", "), "", "NS.Compat members nobody classified (pure, guarded or wrapped)")
  assertEqual(table.concat(stale, ", "), "", "classified names NS.Compat no longer has")
  assertEqual(table.concat(sortedKeys(CLASSIFIED, "guarded"), ","), "ListCurrencies",
    "ListCurrencies is the only member that changes client state")
end)

test("SimSeam: the seam is idle with no session: every wrapped member answers live", function()
  local saved = M.__context.inGroup
  M.__context.inGroup = true
  local ok, err = pcall(function()
    assertTrue(NS.Compat.InGroup(), "an idle seam answers the client")
  end)
  M.__context.inGroup = saved
  if not ok then error(err, 0) end
end)

-- ── the degradation stubs (H9) ──────────────────────────────────────────────────────────────

-- A live session on a probe seam of its own, so the instance surface is the library's real one
-- without binding NS.SimSeam (one seam binds one session, and modules/Sim.lua owns that bind).
local function probeInstance()
  local seam = Sim:NewSeam({ Probe = function() end }, { name = "LootHistoryProbe" })
  return Sim:New({
    name = "LootHistoryProbe", seam = seam, slash = "/probe sim",
    deliver = function() return 0 end, isStoodDown = function() return false end,
    scenarios = { names = {}, defs = {} },
    prepare = function(_, _, _, ready) ready() end, play = function() end,
  }), seam
end

test("SimSeam: the degraded stub carries the instance surface (LibKa0s-Sim-1.0)", function()
  assertTrue(type(NS.SimHost.NewSimStub) == "function", "core/SimSeam.lua publishes the session stub factory")
  local live = probeInstance()
  local stub = NS.SimHost.NewSimStub(function() end)
  local restore = T.setSurfaceSource({ ["LibKa0s-Sim-1.0"] = live })
  local ok, err = pcall(T.assertSurfaceParity, stub, "LibKa0s-Sim-1.0", {})
  T.setSurfaceSource(restore)
  if not ok then error(err, 0) end
  T.assertSurfaceParity(live, stub, "Sim instance vs host stub", {})
  T.assertSurfaceParity(stub, live, "host stub carries nothing the instance lacks", {})
end)

test("SimSeam: the seam stub carries the live seam surface, both ways", function()
  local _, probeSeam = probeInstance()
  local stub = NS.SimHost.NewSeamStub()
  T.assertSurfaceParity(NS.SimSeam, stub, "NS.SimSeam vs host seam stub", {})
  T.assertSurfaceParity(probeSeam, stub, "a probe seam vs host seam stub", {})
  T.assertSurfaceParity(stub, NS.SimSeam, "host seam stub carries nothing the seam lacks", {})
end)

test("SimSeam: the session stub is inert and says the library is needed", function()
  local said = {}
  local stub = NS.SimHost.NewSimStub(function(line) said[#said + 1] = line end)
  assertFalse(stub:IsActive()); assertFalse(stub:IsDelivering()); assertFalse(stub:IsPanelShown())
  assertEqual(stub:Fire("CHAT_MSG_LOOT"), 0)
  assertEqual(stub:DeliverForCleanup("BAG_UPDATE"), 0)
  assertEqual(stub:After(1, function() end), nil)
  local ok, line = stub:Start({ scenario = "loot" })
  assertFalse(ok)
  assertEqual(line, "The simulator needs LibKa0s-Sim-1.0.")
  local vok, code = stub:RunVerb("start loot")
  assertFalse(vok); assertEqual(code, "absent")
  assertEqual(table.concat(said, "|"), "The simulator needs LibKa0s-Sim-1.0.|The simulator needs LibKa0s-Sim-1.0.")
  assertFalse(stub:Stop("stop"))
  assertFalse(stub:Status().active)
  assertEqual(stub:Session(), nil)
  assertEqual(#stub:Steps(), 0); assertEqual(#stub:PanelRows(), 0)
  local n, why = stub:Step()
  assertEqual(n, nil); assertEqual(why, "absent")
  local seam = NS.SimHost.NewSeamStub()
  assertEqual(select("#", seam:Live(function(a, b) return a, nil, b end, 1, 2)), 3, "Live keeps nil holes")
  assertEqual(#seam:Keys(), 0); assertEqual(#seam:Unwrapped(), 0)
end)

test("SimSeam: degraded (no LibKa0s): NS.SimSeam is the inert stub and Compat is not wrapped", function()
  local ns = loadDegraded()
  assertTrue(type(ns.SimSeam) == "table", "a degraded load still publishes NS.SimSeam")
  T.assertSurfaceParity(NS.SimSeam, ns.SimSeam, "live seam vs degraded load's seam", {})
  assertEqual(#ns.SimSeam:Keys(), 0, "the stub wraps nothing")
  assertEqual(ns.SimSeam:Live(function(x) return x end, 7), 7, "Live calls fn")
end)
