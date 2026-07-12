local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual = T.test, T.assertEqual

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

test("Attribution: disenchant/mill/prospect spell stamps CRAFT", function()
  resetContext()
  NS.Attribution:OnSpellSucceeded(nil, "player", "cast-1", 13262) -- Disenchant
  assertEqual(NS.Attribution:Consume(), "CRAFT")
end)

test("Attribution: an unrelated player spell does not stamp CRAFT", function()
  resetContext()
  NS.Attribution:OnSpellSucceeded(nil, "player", "cast-1", 999999)
  assertEqual(NS.Attribution:Consume(), "OTHER")
end)

-- Quest rewards must be stamped from the GetQuestReward hook (client call, before the server
-- pushes the reward loot); QUEST_TURNED_IN alone can fire after the reward line and miss it.
test("Attribution: taking a quest reward stamps QUEST", function()
  resetContext()
  NS.Attribution:StampQuestReward()
  assertEqual(NS.Attribution:Consume(), "QUEST")
end)
