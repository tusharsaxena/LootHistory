local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local function resetContext()
  NS.State.lootContext = nil
  mocks.__now = 0
end

test("Attribution: Consume returns stamped context within TTL", function()
  resetContext()
  NS.Attribution:Stamp("KILL", { npcID = 214506 }, "CERTAIN")
  local source, detail, confidence = NS.Attribution:Consume()
  assertEqual(source, "KILL")
  assertEqual(detail.npcID, 214506)
  assertEqual(confidence, "CERTAIN")
end)

test("Attribution: Stamp defaults confidence to CERTAIN", function()
  resetContext()
  NS.Attribution:Stamp("CONTAINER")
  local _, _, confidence = NS.Attribution:Consume()
  assertEqual(confidence, "CERTAIN")
end)

test("Attribution: Consume falls back to OTHER/INFERRED past TTL", function()
  resetContext()
  NS.Attribution:Stamp("KILL")
  mocks.__now = NS.Constants.CONTEXT_TTL + 1
  local source, detail, confidence = NS.Attribution:Consume()
  assertEqual(source, "OTHER")
  assertEqual(detail, nil)
  assertEqual(confidence, "INFERRED")
end)

test("Attribution: Consume with no stamp → OTHER/INFERRED", function()
  resetContext()
  local source, _, confidence = NS.Attribution:Consume()
  assertEqual(source, "OTHER")
  assertEqual(confidence, "INFERRED")
end)

test("Attribution: context survives repeated Consume (multi-line loot)", function()
  resetContext()
  NS.Attribution:Stamp("MPLUS", { keystoneLevel = 12 })
  local s1 = NS.Attribution:Consume()
  local s2 = NS.Attribution:Consume()
  assertEqual(s1, "MPLUS")
  assertEqual(s2, "MPLUS")
end)

local CREATURE = "Creature-0-3299-2549-11-214506-000136DF91"
local OBJECT   = "GameObject-0-3299-2549-11-221102-00003ABCDE"
local ITEMGUID = "Item-970-0-40000012ABCDEF00"

test("Attribution: ResolveLootSource creature → KILL + npcID", function()
  local source, detail = NS.Attribution:ResolveLootSource(CREATURE, {})
  assertEqual(source, "KILL")
  assertEqual(detail.npcID, 214506)
end)

test("Attribution: ResolveLootSource creature in encounter → KILL + encounter detail", function()
  local state = { encounter = { id = 2902, name = "Ovi'nax", difficulty = 16 } }
  local source, detail = NS.Attribution:ResolveLootSource(CREATURE, state)
  assertEqual(source, "KILL")
  assertEqual(detail.npcID, 214506)
  assertEqual(detail.encounterID, 2902)
  assertEqual(detail.difficulty, 16)
end)

test("Attribution: ResolveLootSource GameObject in keystone → MPLUS + level", function()
  local state = { keystone = { level = 12 } }
  local source, detail = NS.Attribution:ResolveLootSource(OBJECT, state)
  assertEqual(source, "MPLUS")
  assertEqual(detail.keystoneLevel, 12)
end)

test("Attribution: ResolveLootSource GameObject otherwise → CONTAINER", function()
  local source = NS.Attribution:ResolveLootSource(OBJECT, {})
  assertEqual(source, "CONTAINER")
end)

test("Attribution: ResolveLootSource Item GUID → CONTAINER", function()
  local source = NS.Attribution:ResolveLootSource(ITEMGUID, {})
  assertEqual(source, "CONTAINER")
end)

-- Opening a container item from bags pushes its contents with no LOOT_OPENED / GUID, so the
-- UseContainerItem hook stamps CONTAINER — but only when the used item actually has loot.
test("Attribution: opening a lootable bag item stamps CONTAINER", function()
  resetContext()
  local orig = NS.Compat.ContainerItemHasLoot
  NS.Compat.ContainerItemHasLoot = function() return true end
  NS.Attribution:OnContainerItemUse(0, 1)
  NS.Compat.ContainerItemHasLoot = orig
  assertEqual(NS.Attribution:Consume(), "CONTAINER")
end)

test("Attribution: using a non-lootable bag item does not stamp", function()
  resetContext()
  local orig = NS.Compat.ContainerItemHasLoot
  NS.Compat.ContainerItemHasLoot = function() return false end
  NS.Attribution:OnContainerItemUse(0, 1)
  NS.Compat.ContainerItemHasLoot = orig
  assertEqual(NS.Attribution:Consume(), "OTHER")  -- no fresh context → fallback
end)

-- Clicking a bag item as a spell target (Disenchant/Enchant) routes through UseContainerItem too;
-- the pending-spell guard must keep that from being read as opening a container.
test("Attribution: applying a pending spell to a bag item does not stamp CONTAINER", function()
  resetContext()
  local origHas, origTgt = NS.Compat.ContainerItemHasLoot, NS.Compat.IsSpellTargeting
  NS.Compat.ContainerItemHasLoot = function() return true end
  NS.Compat.IsSpellTargeting = function() return true end
  NS.Attribution:OnContainerItemUse(0, 1)
  NS.Compat.ContainerItemHasLoot, NS.Compat.IsSpellTargeting = origHas, origTgt
  assertEqual(NS.Attribution:Consume(), "OTHER")
end)

test("Attribution: deconstruct spells map to their own source", function()
  resetContext()
  NS.Attribution:OnSpellSucceeded(nil, "player", "c", 13262) -- Disenchant
  assertEqual(NS.Attribution:Consume(), "DISENCHANT")
  resetContext()
  NS.Attribution:OnSpellSucceeded(nil, "player", "c", 51005) -- Milling (generic)
  assertEqual(NS.Attribution:Consume(), "MILLING")
  resetContext()
  NS.Attribution:OnSpellSucceeded(nil, "player", "c", 31252) -- Prospecting (generic)
  assertEqual(NS.Attribution:Consume(), "PROSPECTING")
end)

test("Attribution: DeconstructSource matches ability families by name", function()
  local A = NS.Attribution
  assertEqual(A:DeconstructSource(13262, "Disenchant"), "DISENCHANT")
  assertEqual(A:DeconstructSource(289991, "Disenchanting"), "DISENCHANT")
  assertEqual(A:DeconstructSource(51005, "Milling"), "MILLING")
  assertEqual(A:DeconstructSource(382981, "Dragon Isles Milling"), "MILLING")
  assertEqual(A:DeconstructSource(434926, "Mass Mill Mycobloom"), "MILLING")  -- not in the id table
  assertEqual(A:DeconstructSource(31252, "Prospecting"), "PROSPECTING")
  assertEqual(A:DeconstructSource(434018, "Algari Prospecting"), "PROSPECTING")
  assertEqual(A:DeconstructSource(225904, "Mass Prospect Felslate"), "PROSPECTING") -- not in the id table
  assertEqual(A:DeconstructSource(12345, "Fireball"), nil)
  -- id fallback when the name is unavailable (uncached / non-enUS)
  assertEqual(A:DeconstructSource(1269575, nil), "MILLING")
  assertEqual(A:DeconstructSource(374627, nil), "PROSPECTING")
  assertEqual(A:DeconstructSource(99999, nil), nil)
end)

test("Attribution: deconstruct's own loot window does not clobber its source", function()
  resetContext()
  NS.Attribution:OnSpellSucceeded(nil, "player", "c", 13262)  -- stamp DISENCHANT
  -- The mats arrive via a LOOT_OPENED window with an Item source GUID (→ CONTAINER); it must not
  -- overwrite the fresher, more specific deconstruct stamp.
  local oNum, oSrc = mocks.GetNumLootItems, mocks.GetLootSourceInfo
  mocks.GetNumLootItems = function() return 1 end
  mocks.GetLootSourceInfo = function() return "Item-3725-0-40000009EFF76790" end
  NS.Attribution:OnLootOpened()
  mocks.GetNumLootItems, mocks.GetLootSourceInfo = oNum, oSrc
  assertEqual(NS.Attribution:Consume(), "DISENCHANT")
end)

test("OnLootOpened logs ONE coalesced summary, not one line per slot", function()
  resetContext()
  local oNum, oSrc = mocks.GetNumLootItems, mocks.GetLootSourceInfo
  mocks.GetNumLootItems = function() return 5 end
  mocks.GetLootSourceInfo = function() return "Creature-0-0-0-0-31146-000000AAAA" end
  NS.State.debug = true
  local before = #NS.DebugLog.buffer
  NS.Attribution:OnLootOpened()
  local added, openLine = 0, nil
  for i = before + 1, #NS.DebugLog.buffer do
    if NS.DebugLog.buffer[i]:find("[Open]", 1, true) then
      added = added + 1
      openLine = NS.DebugLog.buffer[i]
    end
  end
  assertEqual(added, 1, "exactly one [Open] line for a 5-slot window")
  -- Stamp() logs its own [Attr] line right after, so check the [Open] line itself rather than
  -- the buffer's absolute-last entry.
  assertTrue(openLine ~= nil and openLine:find("5 slots ->", 1, true) ~= nil,
    "the summary reports the slot count")
  NS.State.debug = false
  mocks.GetNumLootItems, mocks.GetLootSourceInfo = oNum, oSrc
end)

test("Attribution: an unrelated player spell does not stamp a source", function()
  resetContext()
  NS.Attribution:OnSpellSucceeded(nil, "player", "cast-1", 999999)
  assertEqual(NS.Attribution:Consume(), "OTHER")
end)

test("Attribution: Auction-House mail stamps AH, ordinary mail stamps MAIL", function()
  local oGet, oIs = NS.Compat.GetMailHeader, NS.Compat.IsAuctionHouseMail
  resetContext()
  NS.Compat.GetMailHeader = function() return "Auction House", "Auction won: Sword" end
  NS.Compat.IsAuctionHouseMail = function() return true end
  NS.Attribution:StampMail(1)
  assertEqual(NS.Attribution:Consume(), "AH")
  resetContext()
  NS.Compat.GetMailHeader = function() return "Bob", "hi" end
  NS.Compat.IsAuctionHouseMail = function() return false end
  NS.Attribution:StampMail(1)
  assertEqual(NS.Attribution:Consume(), "MAIL")
  NS.Compat.GetMailHeader, NS.Compat.IsAuctionHouseMail = oGet, oIs
end)

-- Quest rewards must be stamped from the GetQuestReward hook (client call, before the server
-- pushes the reward loot); QUEST_TURNED_IN alone can fire after the reward line and miss it.
test("Attribution: taking a quest reward stamps QUEST", function()
  resetContext()
  NS.Attribution:StampQuestReward()
  assertEqual(NS.Attribution:Consume(), "QUEST")
end)
