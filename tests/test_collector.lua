local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local LINK = "|cffa335ee|Hitem:211296::::::::80:::::|h[Vial of Fun]|h|r"

test("Collector: BuildRecord populates every field", function()
  local ctx = { source = "KILL", sourceName = "Ovi'nax",
                sourceDetail = { npcID = 214506 }, confidence = "CERTAIN" }
  local env = { ts = 1000, char = "Ka0z-Realm", itemID = 211296, itemName = "Vial of Fun",
                quality = 4, itemLevel = 489, bound = "WARBOUND",
                zone = "Nerub-ar Palace", mapID = 2657, subzone = "The Hive" }
  local r = NS.Collector:BuildRecord(LINK, 3, ctx, env)
  assertEqual(r.ts, 1000)
  assertEqual(r.itemLevel, 489)
  assertEqual(r.bound, "WARBOUND")
  assertEqual(r.char, "Ka0z-Realm")
  assertEqual(r.itemID, 211296)
  assertEqual(r.itemLink, LINK)
  assertEqual(r.itemName, "Vial of Fun")
  assertEqual(r.quality, 4)
  assertEqual(r.quantity, 3)
  assertEqual(r.source, "KILL")
  assertEqual(r.sourceName, "Ovi'nax")
  assertEqual(r.sourceDetail.npcID, 214506)
  assertEqual(r.zone, "Nerub-ar Palace")
  assertEqual(r.mapID, 2657)
  assertEqual(r.subzone, "The Hive")
  assertEqual(r.confidence, "CERTAIN")
end)

test("Collector: ShouldRecord passes at/above threshold", function()
  local cfg = { qualityThreshold = 2, excludedSources = {} }
  assertTrue(NS.Collector:ShouldRecord(2, "KILL", cfg))
  assertTrue(NS.Collector:ShouldRecord(4, "KILL", cfg))
end)

test("Collector: ShouldRecord rejects below threshold", function()
  local cfg = { qualityThreshold = 2, excludedSources = {} }
  assertFalse(NS.Collector:ShouldRecord(1, "KILL", cfg))
  assertFalse(NS.Collector:ShouldRecord(0, "KILL", cfg))
end)

test("Collector: ShouldRecord rejects excluded source", function()
  local cfg = { qualityThreshold = 2, excludedSources = { VENDOR = true } }
  assertFalse(NS.Collector:ShouldRecord(4, "VENDOR", cfg))
  assertTrue(NS.Collector:ShouldRecord(4, "KILL", cfg))
end)

test("Collector: ShouldRecord treats nil quality as 0", function()
  local cfg = { qualityThreshold = 1, excludedSources = {} }
  assertFalse(NS.Collector:ShouldRecord(nil, "KILL", cfg))
end)

test("Collector: end-to-end writes an attributed record", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.State.lootContext = nil
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", "Ovi'nax", { npcID = 214506 }, "CERTAIN")

  local before = NS.Database:Count()
  local msg = string.format(mocks.LOOT_ITEM_SELF, LINK)
  NS.Collector:OnChatMsgLoot(nil, msg)

  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.source, "KILL")
  assertEqual(r.sourceName, "Ovi'nax")
  assertEqual(r.confidence, "CERTAIN")
  assertEqual(r.itemID, 211296)
  assertEqual(r.quality, 4)
  assertEqual(r.quantity, 1)
  assertEqual(r.zone, "Testville")
  assertEqual(r.mapID, 2657)
end)

test("Collector: end-to-end drops loot below the quality threshold", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.qualityThreshold = 5   -- Legendary+; mock item is quality 4
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", "Ovi'nax", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before)

  NS.db.global.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)
