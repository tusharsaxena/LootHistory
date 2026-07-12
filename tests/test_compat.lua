local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue =
  T.test, T.assertEqual, T.assertTrue

test("Compat: DecodeGUID creature → kind + npcID", function()
  local kind, npcID = NS.Compat.DecodeGUID("Creature-0-3299-2549-11-214506-000136DF91")
  assertEqual(kind, "Creature")
  assertEqual(npcID, 214506)
end)

test("Compat: DecodeGUID GameObject → kind, no npcID", function()
  local kind, npcID = NS.Compat.DecodeGUID("GameObject-0-3299-2549-11-221102-00003ABCDE")
  assertEqual(kind, "GameObject")
  assertEqual(npcID, nil)
end)

test("Compat: DecodeGUID Item → kind, no npcID", function()
  local kind, npcID = NS.Compat.DecodeGUID("Item-970-0-40000012ABCDEF00")
  assertEqual(kind, "Item")
  assertEqual(npcID, nil)
end)

test("Compat: DecodeGUID Vehicle/Pet count as unit kinds", function()
  local _, vID = NS.Compat.DecodeGUID("Vehicle-0-3299-2549-11-198888-000136DF91")
  assertEqual(vID, 198888)
  local _, pID = NS.Compat.DecodeGUID("Pet-0-3299-2549-11-165189-000136DF91")
  assertEqual(pID, 165189)
end)

test("Compat: DecodeGUID nil-safe", function()
  assertEqual(NS.Compat.DecodeGUID(nil), nil)
end)

test("Compat: GetActiveKeystoneLevel nil when API absent (headless)", function()
  -- No C_ChallengeMode in the mock → the firewall wrapper degrades to nil, not an error.
  assertEqual(NS.Compat.GetActiveKeystoneLevel(), nil)
end)

test("Compat: QualityLabel names qualities", function()
  assertEqual(NS.Compat.QualityLabel(0), "Poor")
  assertEqual(NS.Compat.QualityLabel(2), "Uncommon")
  assertEqual(NS.Compat.QualityLabel(4), "Epic")
  assertEqual(NS.Compat.QualityLabel(nil), "Poor")
end)
