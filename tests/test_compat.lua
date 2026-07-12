local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

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

test("Compat: API-absent guards degrade to nil/false with no flavor flag", function()
  -- The mock omits C_Container / C_TooltipInfo / SpellIsTargeting / C_Spell / GetSpellInfo /
  -- GetInboxHeaderInfo / GetQuestID — mirroring an API that isn't present. Every shim must
  -- degrade via a direct API-presence check (the Retail-only idiom), NOT via a WOW_PROJECT
  -- game-flavor flag. This is the guarantee LH-10 locks in.
  assertFalse(NS.Compat.ContainerItemHasLoot(0, 1))      -- C_Container absent
  assertFalse(NS.Compat.IsSpellTargeting())              -- SpellIsTargeting absent
  assertEqual(NS.Compat.ScanBound("[Item]"), nil)        -- C_TooltipInfo absent
  assertEqual(NS.Compat.GetSpellName(13262), nil)        -- C_Spell + GetSpellInfo absent
  assertEqual(NS.Compat.CurrentQuestID(), nil)           -- GetQuestID absent
  local sender, subject = NS.Compat.GetMailHeader(1)     -- GetInboxHeaderInfo absent
  assertEqual(sender, nil)
  assertEqual(subject, nil)
end)

test("Compat: no game-flavor flags exposed (Retail-only addon)", function()
  -- LH-10: IsRetail/IsClassic removed — feature code must not branch on game flavor.
  assertEqual(NS.Compat.IsRetail, nil)
  assertEqual(NS.Compat.IsClassic, nil)
end)

test("Compat: IsAuctionHouseMail matches AH sender + won-subject", function()
  local oHouse, oSubj = _G.AUCTION_HOUSE, _G.AUCTION_WON_MAIL_SUBJECT
  _G.AUCTION_HOUSE = "Auction House"
  _G.AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
  assertTrue(NS.Compat.IsAuctionHouseMail("Auction House", "whatever"))     -- sender match
  assertTrue(NS.Compat.IsAuctionHouseMail("SomeNPC", "Auction won: Evercore Shade")) -- subject match
  assertFalse(NS.Compat.IsAuctionHouseMail("Bob", "Hey there"))             -- neither
  assertFalse(NS.Compat.IsAuctionHouseMail(nil, nil))
  _G.AUCTION_HOUSE, _G.AUCTION_WON_MAIL_SUBJECT = oHouse, oSubj
end)

test("Compat: QualityLabel names qualities", function()
  assertEqual(NS.Compat.QualityLabel(0), "Poor")
  assertEqual(NS.Compat.QualityLabel(2), "Uncommon")
  assertEqual(NS.Compat.QualityLabel(4), "Epic")
  assertEqual(NS.Compat.QualityLabel(nil), "Poor")
end)

test("Compat: GetItemInfo surfaces the item class id", function()
  T.mocks.__itemClassID = 12
  local _, _, _, classID = NS.Compat.GetItemInfo("|cffffffff|Hitem:1::::::::80:::::|h[X]|h|r")
  assertEqual(classID, 12)
  T.mocks.__itemClassID = 0   -- restore default
end)
