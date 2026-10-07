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
  NS.db.profile.settings.qualityThreshold = 1
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

-- events-frames-taint-§7: the loot hot path must not allocate a gate-config table per line. Spy
-- ShouldRecord's cfg argument across two loot lines for different items: the same table both
-- times, carrying the second line's item id at the second call.
test("Collector: OnChatMsgLoot reuses one gate-config table across loot lines", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.Collector:RefreshUpvalues()
  local LINK2 = "|cffa335ee|Hitem:211297::::::::80:::::|h[Vial of More Fun]|h|r"
  local savedGet, savedShould = NS.Compat.GetItemInfo, NS.Collector.ShouldRecord
  NS.Compat.GetItemInfo = function(link)
    return (link == LINK2) and 211297 or 211296, "X", 4, 0
  end
  local seen, ids = {}, {}
  NS.Collector.ShouldRecord = function(_, _, _, _, cfg)
    seen[#seen + 1] = cfg
    ids[#ids + 1] = cfg.itemID
    return false, "quality"   -- drop, so no record is written
  end
  local ok, err = pcall(function()
    NS.Attribution:Stamp("KILL", nil, "CERTAIN")
    NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
    NS.Attribution:Stamp("KILL", nil, "CERTAIN")
    NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK2))
  end)
  NS.Compat.GetItemInfo, NS.Collector.ShouldRecord = savedGet, savedShould
  assertTrue(ok, tostring(err))
  assertEqual(#seen, 2)
  assertTrue(rawequal(seen[1], seen[2]))
  assertEqual(ids[1], 211296)
  assertEqual(ids[2], 211297)
  assertEqual(seen[2].itemID, 211297)
end)

test("Collector: whitelist records below threshold as a plain point-in-time row", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.profile.settings.qualityThreshold = 5   -- mock item is quality 4 -> would drop
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

  NS.db.profile.settings.qualityThreshold = 2   -- restore
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
  NS.db.profile.settings.qualityThreshold = 1
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

  NS.db.profile.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: end-to-end attributes a created line to CRAFT, overriding context", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.profile.settings.qualityThreshold = 1
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", { npcID = 999 }, "CERTAIN")   -- stale, unrelated context

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_CREATED_SELF, LINK))
  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.source, "CRAFT")
  assertEqual(r.sourceDetail, nil)
  assertEqual(r.confidence, "CERTAIN")

  NS.db.profile.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: end-to-end attributes a refund line to REFUND", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.State.lootContext = nil
  NS.db.profile.settings.qualityThreshold = 1
  NS.Collector:RefreshUpvalues()

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_REFUND, LINK))
  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.source, "REFUND")
  assertEqual(r.confidence, "CERTAIN")

  NS.db.profile.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: a roll-won line writes no record but stamps ROLL for the receive line", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.profile.settings.qualityThreshold = 1
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

  NS.db.profile.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

local CURRENCY_LINK = "|cffffffff|Hcurrency:3008::|h[Valorstones]|h|r"

test("Collector: end-to-end records a currency line as Type=Currency", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.State.lootContext = nil
  NS.db.profile.settings.qualityThreshold = 5   -- high: proves currency ignores the quality gate
  NS.db.profile.settings.recordCurrency = true
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
  assertEqual(r.quality, 4)         -- currency quality now stored at capture (from C_CurrencyInfo mock)
  assertEqual(r.bound, "WARBAND")   -- 3008 is Warband-transferable -> bound stored at capture

  NS.db.profile.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: recordCurrency off drops currency", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.profile.settings.recordCurrency = false
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("MPLUS", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED, CURRENCY_LINK))
  assertEqual(NS.Database:Count(), before)

  NS.db.profile.settings.recordCurrency = true   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: a muted source drops its currency too", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.profile.settings.recordCurrency = true
  NS.db.profile.settings.excludedSources = { MPLUS = true }
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("MPLUS", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED, CURRENCY_LINK))
  assertEqual(NS.Database:Count(), before)

  NS.db.profile.settings.excludedSources = {}   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: a blacklisted currency is dropped, records after un-blacklisting", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.profile.settings.recordCurrency = true
  NS.db.profile.currencyBlacklist = {}
  NS.Filters:AddCurrencyBlacklist(3008)     -- the mock currency id
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("MPLUS", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED, CURRENCY_LINK))
  assertEqual(NS.Database:Count(), before)   -- blacklisted -> dropped

  NS.Filters:RemoveCurrencyBlacklist(3008)
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED, CURRENCY_LINK))
  assertEqual(NS.Database:Count(), before + 1)
end)

test("Collector: a currency refund line records as Type=Currency, source REFUND", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.State.lootContext = nil
  NS.db.profile.settings.recordCurrency = true
  NS.db.profile.settings.excludedSources = {}
  NS.Collector:RefreshUpvalues()
  -- The purchase left a fresh VENDOR stamp; the self-identifying refund line must override it
  -- (CERTAIN), not inherit VENDOR.
  NS.Attribution:Stamp("VENDOR", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.LOOT_ITEM_REFUND_MULTIPLE, CURRENCY_LINK, 100))
  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.itemType, "Currency")
  assertEqual(r.currencyID, 3008)
  assertEqual(r.quantity, 100)
  assertEqual(r.source, "REFUND")
  assertEqual(r.confidence, "CERTAIN")
end)

test("Collector: a muted REFUND source drops the refunded currency", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.profile.settings.recordCurrency = true
  NS.db.profile.settings.excludedSources = { REFUND = true }
  NS.Collector:RefreshUpvalues()

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.LOOT_ITEM_REFUND, CURRENCY_LINK))
  assertEqual(NS.Database:Count(), before)

  NS.db.profile.settings.excludedSources = {}   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: end-to-end drops loot below the quality threshold", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.profile.settings.qualityThreshold = 5   -- Legendary+; mock item is quality 4
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before)

  NS.db.profile.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: end-to-end drops quest items when the filter is on", function()
  local mocks = T.mocks
  mocks.__now = 0
  mocks.__itemClassID = NS.Constants.ITEMCLASS_QUEST
  NS.db.profile.settings.excludeQuestItems = true
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before)   -- quest item dropped

  -- restore: filter off, non-quest class → records again
  NS.db.profile.settings.excludeQuestItems = false
  mocks.__itemClassID = 0
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before + 1)
end)

test("Schema: excludeQuestItems row exists, defaults true, settable", function()
  assertEqual(NS.Schema:Default("settings.excludeQuestItems"), true)
  assertEqual(NS.defaults.profile.settings.excludeQuestItems, true)
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
  NS.db.profile.settings.qualityThreshold = 1
  NS.db.profile.settings.excludeQuestItems = true    -- start ON: a stale cached flag would drop the item
  NS.Collector._enabled = nil                       -- allow (re-)enable in the harness
  NS.Collector:Enable()                             -- collector caches excludeQuestItems = true

  -- A competing consumer registers the SAME message on the shared bus, exactly as B:Enable does.
  local browserGot = false
  NS.bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function() browserGot = true end)

  -- Broadcast the change the way Schema:Set does (DB already written to false).
  NS.db.profile.settings.excludeQuestItems = false
  NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "questfilter")

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
  NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "test")

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

-- ── OnChatMsgLoot's debug lines (characterization) ────────────────────────────────────────────
--
-- Pinned before Collector:OnChatMsgLoot, CCN 20 once lizard could see it, had its source
-- resolution and its debug lines moved into helpers (GI-LH-02). The record itself is pinned by the
-- end-to-end cases above; these pin the exact [Drop], [Loot] and [AHPrice] lines, with logging on
-- and off. The mock's GetItemInfo names every item "Item Name" and its GetItemExtras gives no item
-- level, which is what the lines below carry.

local function withDebugSpy(fn)
  local lines = {}
  local savedDebug, savedFlag = NS.Debug, NS.State.debug
  local savedGather, savedPick = NS.AuctionPrice.GatherAll, NS.AuctionPrice.Pick
  NS.Debug = function(tag, fmt, ...)
    local args = { ... }
    for i = 1, select("#", ...) do args[i] = tostring(args[i]) end
    lines[#lines + 1] = "[" .. tag .. "] " .. fmt:format(unpack(args))
  end
  local ok, err = pcall(fn, lines)
  NS.Debug, NS.State.debug = savedDebug, savedFlag
  NS.AuctionPrice.GatherAll, NS.AuctionPrice.Pick = savedGather, savedPick
  NS.db.profile.settings.qualityThreshold = 2
  NS.Collector:RefreshUpvalues()
  if not ok then error(err, 0) end
  return lines
end

test("Collector: a recorded loot line logs [Loot] and [AHPrice], prices sorted, the pick named", function()
  local mocks = T.mocks
  mocks.__now = 0
  local lines = withDebugSpy(function()
    NS.State.debug = true
    NS.Collector:RefreshUpvalues()
    NS.AuctionPrice.GatherAll = function()
      return { tsm = { dbmarket = 120, dbminbuyout = 90 }, auctionator = { minbuyout = 80 } }
    end
    NS.AuctionPrice.Pick = function() return 120, "tsm:dbmarket" end
    NS.Attribution:Stamp("KILL", nil, "CERTAIN")
    NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  end)
  local loot, price
  for _, l in ipairs(lines) do
    if l:find("^%[Loot%]") then loot = l end
    if l:find("^%[AHPrice%]") then price = l end
  end
  assertEqual(loot, "[Loot] Item Name q4 ilvl=- src=KILL conf=CERTAIN")
  assertEqual(price, "[AHPrice] Item Name | gathered: auctionator:minbuyout=80 tsm:dbmarket=120 "
    .. "tsm:dbminbuyout=90 | pick: 120(tsm:dbmarket)")
end)

test("Collector: with no price gathered the [AHPrice] line says none and picks nothing", function()
  local mocks = T.mocks
  mocks.__now = 0
  local lines = withDebugSpy(function()
    NS.State.debug = true
    NS.Collector:RefreshUpvalues()
    NS.AuctionPrice.GatherAll = function() return nil end
    NS.AuctionPrice.Pick = function() return nil, nil end
    NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_BONUS_ROLL_SELF, LINK))
  end)
  local price, loot
  for _, l in ipairs(lines) do
    if l:find("^%[AHPrice%]") then price = l end
    if l:find("^%[Loot%]") then loot = l end
  end
  assertEqual(loot, "[Loot] Item Name q4 ilvl=- src=BONUS_ROLL conf=CERTAIN")
  assertEqual(price, "[AHPrice] Item Name | gathered: none | pick: -(-)")
end)

test("Collector: a refused loot line logs one [Drop] line naming the reason, and nothing else", function()
  local mocks = T.mocks
  mocks.__now = 0
  local lines = withDebugSpy(function()
    NS.State.debug = true
    NS.db.profile.settings.qualityThreshold = 5
    NS.Collector:RefreshUpvalues()
    NS.Attribution:Stamp("KILL", nil, "CERTAIN")
    NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  end)
  local drops, other = {}, 0
  for _, l in ipairs(lines) do
    if l:find("^%[Drop%]") then drops[#drops + 1] = l
    elseif l:find("^%[Loot%]") or l:find("^%[AHPrice%]") then other = other + 1 end
  end
  assertEqual(#drops, 1)
  assertEqual(drops[1], "[Drop] Item Name q4 class=0 src=KILL reason=quality")
  assertEqual(other, 0, "a refused line writes no [Loot] or [AHPrice] line")
end)

test("Collector: with logging off a loot line calls the debug sink not at all", function()
  local mocks = T.mocks
  mocks.__now = 0
  local before = NS.Database:Count()
  local lines = withDebugSpy(function()
    NS.State.debug = false
    NS.Collector:RefreshUpvalues()
    NS.Attribution:Stamp("KILL", nil, "CERTAIN")
    NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  end)
  assertEqual(NS.Database:Count(), before + 1, "the record is still written")
  local mine = 0
  for _, l in ipairs(lines) do
    if l:find("^%[Loot%]") or l:find("^%[AHPrice%]") or l:find("^%[Drop%]") then mine = mine + 1 end
  end
  assertEqual(mine, 0)
end)


-- ── Ledger claims and gold (timeline-ledger spec §5.3, §5.4) ──────────────────

local function claimsReset()
  NS.Reconciler.claims = {}
  NS.Reconciler._enabled = true
end

test("Collector: a recorded loot line claims its stack for the holdings diff", function()
  local mocks = T.mocks
  mocks.__now = 0
  claimsReset()
  NS.db.profile.settings.qualityThreshold = 1
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF_MULTIPLE, LINK, 3))
  local list = NS.Reconciler.claims["i:211296"]
  assertTrue(list ~= nil, "no claim posted")
  assertEqual(list[1].qty, 3)
  assertTrue(list[1].row == NS.Database:History()[NS.Database:Count()])
  NS.Reconciler.claims = {}
end)

test("Collector: a gated-out loot line claims nothing", function()
  local mocks = T.mocks
  claimsReset()
  NS.db.profile.settings.qualityThreshold = 5
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Reconciler.claims["i:211296"], nil)
  NS.db.profile.settings.qualityThreshold = 1
  NS.Collector:RefreshUpvalues()
end)

test("Collector: a recorded currency line claims its amount", function()
  local mocks = T.mocks
  claimsReset()
  NS.db.profile.settings.recordCurrency = true
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED_MULTIPLE, CURRENCY_LINK, 25))
  assertEqual(NS.Reconciler.claims["c:3008"][1].qty, 25)
  NS.Reconciler.claims = {}
end)

test("Collector: CHAT_MSG_MONEY writes a GOLD gain and claims it", function()
  claimsReset()
  NS.db.profile.settings.recordGold, NS.db.profile.settings.trackLedger = true, true
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", { npcID = 5 }, "CERTAIN")
  local before = NS.Database:Count()
  NS.Collector:OnChatMsgMoney(nil, "You loot 1 Gold, 2 Silver, 3 Copper")
  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.kind, "GOLD"); assertEqual(r.dir, "IN"); assertEqual(r.quantity, 10203)
  assertEqual(r.itemName, "Gold"); assertEqual(r.itemType, "Gold"); assertEqual(r.source, "KILL")
  assertEqual(r.holder, NS.Util.PlayerKey())
  assertEqual(NS.Reconciler.claims.g[1].qty, 10203)
  NS.Reconciler.claims = {}
end)

test("Collector: CHAT_MSG_MONEY with recordGold or trackLedger off writes nothing", function()
  claimsReset()
  local s = NS.db.profile.settings
  s.recordGold = false; NS.Collector:RefreshUpvalues()
  local before = NS.Database:Count()
  NS.Collector:OnChatMsgMoney(nil, "You loot 5 Copper")
  s.recordGold, s.trackLedger = true, false; NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgMoney(nil, "You loot 5 Copper")
  assertEqual(NS.Database:Count(), before)
  assertEqual(NS.Reconciler.claims.g, nil)
  s.trackLedger = true; NS.Collector:RefreshUpvalues()
end)

-- ── Hidden and tracking currencies (P7 Task 0) ───────────────────────────────────────────────
-- A chat currency link can name a HIDDEN tracking currency the token list never shows (owner report
-- 2026-10-06: "Nebulous Voidcore" as hidden 3513 and listed 3418). The chat row and its claim go to
-- the listed same-name twin, or nowhere; the holdings diff stays list-only either way.
local S = dofile("tests/ledger_support.lua")
local VOIDCORE = "Nebulous Voidcore"
local HIDDEN, LISTED = 3513, 3418

local function voidcoreCase(name, body)
  S.case(name, function()
    local m = T.mocks
    local savedList, savedNames = m.__currencyList, m.__currencyNames
    m.__currencyNames = setmetatable({ [HIDDEN] = VOIDCORE, [LISTED] = VOIDCORE }, { __index = savedNames })
    local ok, err = pcall(function()
      S.reset()
      NS.db.profile.settings.recordCurrency = true
      NS.db.profile.currencyBlacklist = {}
      NS.Collector:RefreshUpvalues()
      body(m)
    end)
    m.__currencyList, m.__currencyNames = savedList, savedNames
    NS.Compat.CurrencyListChanged()
    if not ok then error(err, 0) end
  end)
end

local function currencyGenesis(m, list)
  m.__currencyList = list
  NS.Compat.CurrencyListChanged()
  local r = S.R()
  for _, p in ipairs({ "bags", "equipped", "money", "currency" }) do r:MarkDirty(p) end
  r.silent = true; r:Flush(); r.silent = nil
  NS.Holdings:MarkGenesis(S.me(), m.__epoch)
end

local function chatCurrency(m, id, qty)
  local link = "|cffffffff|Hcurrency:" .. id .. "::|h[" .. VOIDCORE .. "]|h|r"
  NS.Collector:OnChatMsgCurrency(nil, string.format(m.CURRENCY_GAINED_MULTIPLE, link, qty))
end

local function currencyRows()
  local out = {}
  for _, r in ipairs(S.H()) do if r.itemType == "Currency" then out[#out + 1] = r end end
  return out
end

voidcoreCase("Collector+Reconciler: a hidden currency with a listed twin records once, under the twin, claimed", function(m)
  currencyGenesis(m, { { header = true, name = "Midnight" },
    { id = LISTED, name = VOIDCORE, quantity = 10 }, { id = 3008, name = "Valorstones", quantity = 5 } })
  chatCurrency(m, HIDDEN, 1)
  assertEqual(NS.Reconciler.claims["c:" .. HIDDEN], nil)
  assertEqual(NS.Reconciler.claims["c:" .. LISTED][1].qty, 1)
  m.__currencyList[2].quantity = 11
  S.R():OnEvent("CURRENCY_DISPLAY_UPDATE", HIDDEN, 1, 1, nil, nil)
  S.R():OnEvent("CURRENCY_DISPLAY_UPDATE", LISTED, 11, 1, nil, nil)
  S.R():Flush()
  m.__now = 110; S.R():Flush()                          -- past any claim wait: no OTHER diff row
  local rows = currencyRows()
  assertEqual(#rows, 1)
  assertEqual(rows[1].currencyID, LISTED); assertEqual(rows[1].itemSubType, "Midnight")
  assertTrue(rows[1].claimed); assertEqual(rows[1].dir, "IN")
  assertEqual(NS.Holdings:Get(S.me()).currency[HIDDEN], nil)
end)

voidcoreCase("Collector: a hidden currency with no listed twin records nothing and claims nothing", function(m)
  currencyGenesis(m, { { header = true, name = "Midnight" }, { id = 3008, name = "Valorstones", quantity = 5 } })
  chatCurrency(m, HIDDEN, 1)
  S.R():OnEvent("CURRENCY_DISPLAY_UPDATE", HIDDEN, 1, 1, nil, nil)
  S.R():Flush(); m.__now = 110; S.R():Flush()
  assertEqual(#currencyRows(), 0)
  assertEqual(next(NS.Reconciler.claims), nil)
  assertEqual(NS.Holdings:Get(S.me()).currency[HIDDEN], nil)
end)

voidcoreCase("Collector+Reconciler: a new listed currency already in the list records one claimed chat row", function(m)
  currencyGenesis(m, { { header = true, name = "Midnight" }, { id = 3008, name = "Valorstones", quantity = 5 } })
  m.__currencyList[3] = { id = LISTED, name = VOIDCORE, quantity = 1 }   -- listed before the chat line
  chatCurrency(m, LISTED, 1)
  S.R():OnEvent("CURRENCY_DISPLAY_UPDATE", LISTED, 1, 1, nil, nil)
  S.R():Flush(); m.__now = 110; S.R():Flush()
  local rows = currencyRows()
  assertEqual(#rows, 1); assertEqual(rows[1].currencyID, LISTED); assertTrue(rows[1].claimed)
  assertEqual(NS.Holdings:Get(S.me()).currency[LISTED], 1)
end)

-- Final review: with the ledger off there is no current baseline and no diff to fall back on, so a
-- currency the list walk misses (under a collapsed header) and the stale baseline lacks keeps the
-- link's id rather than going unrecorded.
voidcoreCase("Collector: with trackLedger off an unlisted, unheld currency with no twin records one chat row", function(m)
  currencyGenesis(m, { { header = true, name = "Midnight" }, { id = 3008, name = "Valorstones", quantity = 5 } })
  local s = NS.db.profile.settings
  s.trackLedger = false; NS.Collector:RefreshUpvalues()
  local ok, err = pcall(chatCurrency, m, LISTED, 1)
  s.trackLedger = true; NS.Collector:RefreshUpvalues()
  if not ok then error(err, 0) end
  local rows = currencyRows()
  assertEqual(#rows, 1)
  assertEqual(rows[1].currencyID, LISTED); assertEqual(rows[1].quantity, 1)
end)

voidcoreCase("Collector+Reconciler: a new currency not yet listed at chat time gets one diff row after the rescan", function(m)
  currencyGenesis(m, { { header = true, name = "Midnight" }, { id = 3008, name = "Valorstones", quantity = 5 } })
  chatCurrency(m, LISTED, 1)
  assertEqual(#currencyRows(), 0)
  assertEqual(next(NS.Reconciler.claims), nil)
  m.__currencyList[3] = { id = LISTED, name = VOIDCORE, quantity = 1 }
  S.R():OnEvent("CURRENCY_DISPLAY_UPDATE", LISTED, 1, 1, nil, nil)
  S.R():Flush(); m.__now = 110; S.R():Flush()
  local rows = currencyRows()
  assertEqual(#rows, 1)
  assertEqual(rows[1].currencyID, LISTED); assertEqual(rows[1].dir, "IN"); assertEqual(rows[1].claimed, nil)
end)

-- ── Characterization (LH-13): every currencyLine branch names itself in the debug log ─────────
-- Pins the [Drop] reason of each guard in order, the direct-source (refund) path, the attributed
-- path and the [Currency] line, so the guard ladder can be split without moving a single line.
test("Collector: each currency-line guard logs its own [Drop] reason, a recorded line logs [Currency]", function()
  local mocks, s, C = T.mocks, NS.db.profile.settings, NS.Compat
  mocks.__now = 0
  local savedInfo, savedListed = C.GetCurrencyInfoFromLink, C.ListedCurrencyID
  local savedTrack = s.trackLedger
  local gained = string.format(mocks.CURRENCY_GAINED_MULTIPLE, CURRENCY_LINK, 7)
  local before = NS.Database:Count()
  local ok, err = pcall(function()
    local lines = withDebugSpy(function()
      NS.State.debug = true
      NS.db.profile.currencyBlacklist = {}
      s.excludedSources, s.trackLedger = {}, true
      NS.Collector:OnChatMsgCurrency(nil, "You receive nothing of note.")          -- not ours: silent
      s.recordCurrency = false; NS.Collector:RefreshUpvalues()
      NS.Collector:OnChatMsgCurrency(nil, gained)                                  -- recordCurrency-off
      s.recordCurrency = true; NS.Collector:RefreshUpvalues()
      C.GetCurrencyInfoFromLink = function() return nil end
      NS.Collector:OnChatMsgCurrency(nil, gained)                                  -- unresolved-link
      C.GetCurrencyInfoFromLink = savedInfo
      C.ListedCurrencyID = function() return nil end
      NS.Collector:OnChatMsgCurrency(nil, gained)                                  -- unlisted
      s.trackLedger = false; NS.Collector:RefreshUpvalues()
      NS.Attribution:Stamp("MPLUS", nil, "CERTAIN")
      NS.Collector:OnChatMsgCurrency(nil, gained)                                  -- ledger off: kept
      s.trackLedger = true; NS.Collector:RefreshUpvalues()
      C.ListedCurrencyID = savedListed
      NS.Filters:AddCurrencyBlacklist(3008); NS.Collector:RefreshUpvalues()
      NS.Collector:OnChatMsgCurrency(nil, gained)                                  -- blacklist
      NS.Filters:RemoveCurrencyBlacklist(3008)
      s.excludedSources = { MPLUS = true }; NS.Collector:RefreshUpvalues()
      NS.Attribution:Stamp("MPLUS", nil, "CERTAIN")
      NS.Collector:OnChatMsgCurrency(nil, gained)                                  -- muted source
      s.excludedSources = {}; NS.Collector:RefreshUpvalues()
      NS.Attribution:Stamp("VENDOR", nil, "CERTAIN")
      NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.LOOT_ITEM_REFUND_MULTIPLE, CURRENCY_LINK, 3))
    end)
    local mine = {}
    for _, l in ipairs(lines) do
      if l:find("^%[Drop%]") or l:find("^%[Currency%]") then mine[#mine + 1] = l end
    end
    assertEqual(table.concat(mine, "\n"), table.concat({
      "[Drop] currency line reason=recordCurrency-off",
      "[Drop] currency line reason=unresolved-link",
      "[Drop] currency line reason=unlisted",
      "[Currency] Valorstones x7 id=3008 src=MPLUS conf=CERTAIN",
      "[Drop] currency Valorstones id=3008 reason=blacklist",
      "[Drop] currency Valorstones src=MPLUS reason=source",
      "[Currency] Valorstones x3 id=3008 src=REFUND conf=CERTAIN",
    }, "\n"))
    assertEqual(NS.Database:Count(), before + 2, "only the ledger-off line and the refund record")
  end)
  C.GetCurrencyInfoFromLink, C.ListedCurrencyID = savedInfo, savedListed
  s.trackLedger, s.excludedSources, s.recordCurrency = savedTrack, {}, true
  NS.Collector:RefreshUpvalues()
  if not ok then error(err, 0) end
end)
