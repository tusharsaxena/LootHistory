local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local LINK = "|cffa335ee|Hitem:211296::::::::80:::::|h[Vial of Fun]|h|r"

test("Collector: BuildRecord populates every field", function()
  local ctx = { source = "KILL", sourceDetail = { npcID = 214506 }, confidence = "CERTAIN" }
  local env = { ts = 1000, char = "Ka0z-Realm", itemID = 211296, itemName = "Vial of Fun",
                quality = 4, itemLevel = 489, bound = "WARBAND",
                zone = "Nerub-ar Palace", mapID = 2657, subzone = "The Hive" }
  local r = NS.Collector:BuildRecord(LINK, 3, ctx, env)
  assertEqual(r.ts, 1000)
  assertEqual(r.itemLevel, 489)
  assertEqual(r.bound, "WARBAND")
  assertEqual(r.char, "Ka0z-Realm")
  assertEqual(r.itemID, 211296)
  assertEqual(r.itemLink, LINK)
  assertEqual(r.itemName, "Vial of Fun")
  assertEqual(r.quality, 4)
  assertEqual(r.quantity, 3)
  assertEqual(r.source, "KILL")
  assertEqual(r.sourceDetail.npcID, 214506)
  assertEqual(r.zone, "Nerub-ar Palace")
  assertEqual(r.mapID, 2657)
  assertEqual(r.subzone, "The Hive")
  assertEqual(r.confidence, "CERTAIN")
end)

test("Collector: ShouldRecord passes at/above threshold", function()
  local cfg = { qualityThreshold = 2, excludedSources = {} }
  assertTrue(NS.Collector:ShouldRecord(2, "KILL", 0, cfg))
  assertTrue(NS.Collector:ShouldRecord(4, "KILL", 0, cfg))
end)

test("Collector: ShouldRecord rejects below threshold", function()
  local cfg = { qualityThreshold = 2, excludedSources = {} }
  assertFalse(NS.Collector:ShouldRecord(1, "KILL", 0, cfg))
  assertFalse(NS.Collector:ShouldRecord(0, "KILL", 0, cfg))
end)

test("Collector: ShouldRecord rejects excluded source", function()
  local cfg = { qualityThreshold = 2, excludedSources = { VENDOR = true } }
  assertFalse(NS.Collector:ShouldRecord(4, "VENDOR", 0, cfg))
  assertTrue(NS.Collector:ShouldRecord(4, "KILL", 0, cfg))
end)

test("Collector: ShouldRecord treats nil quality as 0", function()
  local cfg = { qualityThreshold = 1, excludedSources = {} }
  assertFalse(NS.Collector:ShouldRecord(nil, "KILL", 0, cfg))
end)

test("Collector: ShouldRecord drops quest items when excludeQuestItems on", function()
  local cfg = { qualityThreshold = 1, excludedSources = {}, excludeQuestItems = true }
  assertFalse(NS.Collector:ShouldRecord(4, "KILL", NS.Constants.ITEMCLASS_QUEST, cfg))
end)

test("Collector: ShouldRecord keeps quest items when excludeQuestItems off", function()
  local cfg = { qualityThreshold = 1, excludedSources = {}, excludeQuestItems = false }
  assertTrue(NS.Collector:ShouldRecord(4, "KILL", NS.Constants.ITEMCLASS_QUEST, cfg))
end)

test("Collector: ShouldRecord unaffected for non-quest class when filter on", function()
  local cfg = { qualityThreshold = 1, excludedSources = {}, excludeQuestItems = true }
  assertTrue(NS.Collector:ShouldRecord(4, "KILL", 0, cfg))
end)

test("Collector: ShouldRecord reports the drop reason", function()
  local ok, reason = NS.Collector:ShouldRecord(0, "KILL", 0,
    { qualityThreshold = 1, excludedSources = {}, excludeQuestItems = false })
  assertFalse(ok); assertEqual(reason, "quality")

  ok, reason = NS.Collector:ShouldRecord(4, "VENDOR", 0,
    { qualityThreshold = 1, excludedSources = { VENDOR = true }, excludeQuestItems = false })
  assertFalse(ok); assertEqual(reason, "source")

  ok, reason = NS.Collector:ShouldRecord(4, "KILL", NS.Constants.ITEMCLASS_QUEST,
    { qualityThreshold = 1, excludedSources = {}, excludeQuestItems = true })
  assertFalse(ok); assertEqual(reason, "quest")
end)

test("Collector: ShouldRecord whitelist forces a below-threshold item to record", function()
  local cfg = { qualityThreshold = 5, excludedSources = {}, itemID = 42, whitelist = { [42] = true } }
  assertTrue(NS.Collector:ShouldRecord(0, "KILL", 0, cfg))   -- quality 0 < threshold 5, but whitelisted
end)

test("Collector: ShouldRecord whitelist forces a muted-source item to record", function()
  local cfg = { qualityThreshold = 1, excludedSources = { VENDOR = true },
                itemID = 42, whitelist = { [42] = true } }
  assertTrue(NS.Collector:ShouldRecord(4, "VENDOR", 0, cfg))
end)

test("Collector: ShouldRecord blacklist drops a passing item with reason 'blacklist'", function()
  local cfg = { qualityThreshold = 1, excludedSources = {}, itemID = 42, blacklist = { [42] = true } }
  local ok, reason = NS.Collector:ShouldRecord(4, "KILL", 0, cfg)
  assertFalse(ok); assertEqual(reason, "blacklist")
end)

test("Collector: ShouldRecord flags a whitelist rescue but not a normal pass", function()
  -- Below threshold + whitelisted → passes, and reports "whitelist" (the caller flags the row).
  local ok, why = NS.Collector:ShouldRecord(0, "KILL", 0,
    { qualityThreshold = 5, excludedSources = {}, itemID = 42, whitelist = { [42] = true } })
  assertTrue(ok); assertEqual(why, "whitelist")
  -- Passes the gate on its own while also whitelisted → no "whitelist" flag (not a rescue).
  ok, why = NS.Collector:ShouldRecord(4, "KILL", 0,
    { qualityThreshold = 1, excludedSources = {}, itemID = 42, whitelist = { [42] = true } })
  assertTrue(ok); assertEqual(why, nil)
end)

test("Collector: ShouldRecord id lists ignore other item ids", function()
  local cfg = { qualityThreshold = 1, excludedSources = {}, itemID = 99,
                blacklist = { [42] = true }, whitelist = { [7] = true } }
  assertTrue(NS.Collector:ShouldRecord(4, "KILL", 0, cfg))
end)

test("Collector: end-to-end drops a blacklisted item, records after un-blacklisting", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.qualityThreshold = 1
  NS.Filters:AddBlacklist(211296)   -- the mock item id
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before)   -- blacklisted → dropped

  NS.Filters:RemoveBlacklist(211296)
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before + 1)
end)

test("Collector: whitelist records below threshold as a plain point-in-time row", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.qualityThreshold = 5   -- mock item is quality 4 -> would drop
  NS.Filters:AddWhitelist(211296)
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before + 1)   -- whitelisted -> recorded despite the gate

  -- Point-in-time: the row carries NO viaWhitelist annotation.
  local row = NS.Database:History()[NS.Database:Count()]
  assertTrue(row.viaWhitelist == nil)

  -- Removing the id from the whitelist does NOT hide or delete the already-recorded row.
  NS.Filters:RemoveWhitelist(211296)
  assertEqual(NS.Database:Count(), before + 1)                 -- still stored
  assertEqual(#NS.Database:ActiveHistory(), before + 1)        -- still visible

  NS.db.global.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
  NS.Database:Purge()                          -- clean up the synthetic row
end)

test("Collector: end-to-end writes an attributed record", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.State.lootContext = nil
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", { npcID = 214506 }, "CERTAIN")

  local before = NS.Database:Count()
  local msg = string.format(mocks.LOOT_ITEM_SELF, LINK)
  NS.Collector:OnChatMsgLoot(nil, msg)

  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.source, "KILL")
  assertEqual(r.sourceDetail.npcID, 214506)
  assertEqual(r.confidence, "CERTAIN")
  assertEqual(r.itemID, 211296)
  assertEqual(r.quality, 4)
  assertEqual(r.quantity, 1)
  assertEqual(r.zone, "Testville")
  assertEqual(r.mapID, 2657)
end)

test("Collector: end-to-end attributes a bonus-roll line to BONUS_ROLL, overriding context", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.qualityThreshold = 1
  NS.Collector:RefreshUpvalues()
  -- A fresh, unrelated KILL context is present: the bonus-roll line must NOT inherit it — the loot
  -- string itself is the authoritative "this is a bonus roll" signal.
  NS.Attribution:Stamp("KILL", { npcID = 999 }, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_BONUS_ROLL_SELF, LINK))
  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.source, "BONUS_ROLL")
  assertEqual(r.sourceDetail, nil)
  assertEqual(r.confidence, "CERTAIN")
  assertEqual(r.itemID, 211296)

  NS.db.global.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: end-to-end attributes a created line to CRAFT, overriding context", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.qualityThreshold = 1
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", { npcID = 999 }, "CERTAIN")   -- stale, unrelated context

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_CREATED_SELF, LINK))
  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.source, "CRAFT")
  assertEqual(r.sourceDetail, nil)
  assertEqual(r.confidence, "CERTAIN")

  NS.db.global.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: end-to-end attributes a refund line to REFUND", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.State.lootContext = nil
  NS.db.global.settings.qualityThreshold = 1
  NS.Collector:RefreshUpvalues()

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_REFUND, LINK))
  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.source, "REFUND")
  assertEqual(r.confidence, "CERTAIN")

  NS.db.global.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: a roll-won line writes no record but stamps ROLL for the receive line", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.qualityThreshold = 1
  NS.Collector:RefreshUpvalues()
  -- A stale KILL context is present; the roll-won stamp must supersede it for the receive line.
  NS.Attribution:Stamp("KILL", { npcID = 999 }, "CERTAIN")

  local before = NS.Database:Count()
  -- 1) The roll-won announcement itself records nothing.
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ROLL_YOU_WON, LINK))
  assertEqual(NS.Database:Count(), before)

  -- 2) The item's own receive line arrives next and consumes the ROLL context.
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.source, "ROLL")
  assertEqual(r.confidence, "CERTAIN")

  NS.db.global.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

local CURRENCY_LINK = "|cffffffff|Hcurrency:3008::|h[Valorstones]|h|r"

test("Collector: end-to-end records a currency line as Type=Currency", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.State.lootContext = nil
  NS.db.global.settings.qualityThreshold = 5   -- high: proves currency ignores the quality gate
  NS.db.global.settings.recordCurrency = true
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("MPLUS", { keystoneLevel = 12 }, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED_MULTIPLE, CURRENCY_LINK, 45))
  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.itemType, "Currency")
  assertEqual(r.currencyID, 3008)
  assertEqual(r.itemName, "Valorstones")
  assertEqual(r.quantity, 45)
  assertEqual(r.source, "MPLUS")
  assertEqual(r.confidence, "CERTAIN")
  assertEqual(r.itemID, nil)
  assertEqual(r.quality, nil)

  NS.db.global.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: recordCurrency off drops currency", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.recordCurrency = false
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("MPLUS", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED, CURRENCY_LINK))
  assertEqual(NS.Database:Count(), before)

  NS.db.global.settings.recordCurrency = true   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: a muted source drops its currency too", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.recordCurrency = true
  NS.db.global.settings.excludedSources = { MPLUS = true }
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("MPLUS", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED, CURRENCY_LINK))
  assertEqual(NS.Database:Count(), before)

  NS.db.global.settings.excludedSources = {}   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: end-to-end drops loot below the quality threshold", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.qualityThreshold = 5   -- Legendary+; mock item is quality 4
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before)

  NS.db.global.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: end-to-end drops quest items when the filter is on", function()
  local mocks = T.mocks
  mocks.__now = 0
  mocks.__itemClassID = NS.Constants.ITEMCLASS_QUEST
  NS.db.global.settings.excludeQuestItems = true
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before)   -- quest item dropped

  -- restore: filter off, non-quest class → records again
  NS.db.global.settings.excludeQuestItems = false
  mocks.__itemClassID = 0
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before + 1)
end)

test("Schema: excludeQuestItems row exists, defaults true, settable", function()
  assertEqual(NS.Schema:Default("settings.excludeQuestItems"), true)
  assertEqual(NS.defaults.global.settings.excludeQuestItems, true)
  assertTrue(NS.Schema:Set("settings.excludeQuestItems", false))
  assertEqual(NS.Schema:Get("settings.excludeQuestItems"), false)
  NS.Schema:Set("settings.excludeQuestItems", true)   -- restore to default
end)

-- Regression for the bus-clobber bug: the Collector and another consumer (the Browser) both
-- subscribe to SettingsChanged. CallbackHandler keys callbacks by (message, target), so if both
-- register on the shared bus-as-self the second clobbers the first and the collector never
-- refreshes on a live setting change (only a /reload fixed it). Private bus targets fix it.
test("Collector: live SettingsChanged refreshes the collector alongside another bus consumer", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.qualityThreshold = 1
  NS.db.global.settings.excludeQuestItems = true    -- start ON: a stale cached flag would drop the item
  NS.Collector._enabled = nil                       -- allow (re-)enable in the harness
  NS.Collector:Enable()                             -- collector caches excludeQuestItems = true

  -- A competing consumer registers the SAME message on the shared bus, exactly as B:Enable does.
  local browserGot = false
  NS.bus:RegisterMessage("Ka0s_LootHistory_SettingsChanged", function() browserGot = true end)

  -- Broadcast the change the way Schema:Set does (DB already written to false).
  NS.db.global.settings.excludeQuestItems = false
  NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "questfilter")

  assertTrue(browserGot)                            -- the competing consumer still receives it

  -- The collector must have refreshed to false: a quest-class item now records rather than drops.
  mocks.__itemClassID = NS.Constants.ITEMCLASS_QUEST
  NS.Attribution:Stamp("KILL", nil, "CERTAIN")
  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before + 1)
  mocks.__itemClassID = 0
end)

test("Collector SettingsChanged does not emit a redundant [Cfg] echo", function()
  NS.Collector._enabled = nil                       -- allow (re-)enable in the harness
  NS.Collector:Enable()                             -- registers the SettingsChanged handler

  -- Spy on RefreshUpvalues so the test independently proves the handler actually ran,
  -- rather than relying on the absence of a [Cfg] line (which is trivially true if the
  -- handler never fires at all, e.g. a future regression drops the RegisterMessage).
  local called = false
  local realRefreshUpvalues = NS.Collector.RefreshUpvalues
  NS.Collector.RefreshUpvalues = function(self, ...)
    called = true
    return realRefreshUpvalues(self, ...)
  end

  NS.State.debug = true
  local before = #NS.DebugLog.buffer
  NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "test")

  NS.Collector.RefreshUpvalues = realRefreshUpvalues
  NS.State.debug = false

  assertTrue(called, "SettingsChanged handler must call RefreshUpvalues")
  for i = before + 1, #NS.DebugLog.buffer do
    assertTrue(NS.DebugLog.buffer[i]:find("[Cfg]", 1, true) == nil,
      "no [Cfg] line after a settings change")
  end
end)

test("Collector: BuildRecord stores the auctionPrice map, no priceSource", function()
  local rec = NS.Collector:BuildRecord("[L]", 1, { source = "KILL", confidence = "CERTAIN" },
    { ts = 1, vendorPrice = 10, auctionPrice = { tsm = { dbmarket = 500 } } })
  assertEqual(rec.auctionPrice.tsm.dbmarket, 500)
  assertEqual(rec.priceSource, nil)
  assertEqual(rec.vendorPrice, 10)
end)
