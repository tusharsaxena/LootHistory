local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue =
  T.test, T.assertEqual, T.assertTrue

local function resetContext()
  NS.State.lootContext = nil
  mocks.__now = 0
end

test("Attribution: Consume returns stamped context within TTL", function()
  resetContext()
  NS.Attribution:Stamp("KILL", "Broodtwister", { npcID = 214506 }, "CERTAIN")
  local source, name, detail, confidence = NS.Attribution:Consume()
  assertEqual(source, "KILL")
  assertEqual(name, "Broodtwister")
  assertEqual(detail.npcID, 214506)
  assertEqual(confidence, "CERTAIN")
end)

test("Attribution: Stamp defaults confidence to CERTAIN", function()
  resetContext()
  NS.Attribution:Stamp("CONTAINER", "Lockbox")
  local _, _, _, confidence = NS.Attribution:Consume()
  assertEqual(confidence, "CERTAIN")
end)

test("Attribution: Consume falls back to OTHER/INFERRED past TTL", function()
  resetContext()
  NS.Attribution:Stamp("KILL", "Broodtwister")
  mocks.__now = NS.Constants.CONTEXT_TTL + 1
  local source, name, detail, confidence = NS.Attribution:Consume()
  assertEqual(source, "OTHER")
  assertEqual(name, nil)
  assertEqual(detail, nil)
  assertEqual(confidence, "INFERRED")
end)

test("Attribution: Consume with no stamp → OTHER/INFERRED", function()
  resetContext()
  local source, _, _, confidence = NS.Attribution:Consume()
  assertEqual(source, "OTHER")
  assertEqual(confidence, "INFERRED")
end)

test("Attribution: context survives repeated Consume (multi-line loot)", function()
  resetContext()
  NS.Attribution:Stamp("MPLUS", "Great Vault", { keystoneLevel = 12 })
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
  local state = { keystone = { level = 12, mapID = 2657 } }
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
