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

-- ScanBound against the six live warbound tooltip strings. Blizzard retired the distinct
-- "Account Bound" wording in 11.0: every one of these globals now says Warbound, and the
-- "Binds to Warband…" forms are what a still-transferable item actually shows (issue: warbound
-- loot was landing as ACCOUNT because "Binds to Warband" was in the account list).
local function withTooltip(lineText, fn)
  local savedTI = _G.C_TooltipInfo
  _G.C_TooltipInfo = { GetHyperlink = function() return { lines = { { leftText = lineText } } } end }
  local ok, err = pcall(fn)
  _G.C_TooltipInfo = savedTI
  if not ok then error(err, 0) end
end

local WARBAND_WORDING = {
  ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP = "Binds to Warband until equipped",
  ITEM_BIND_TO_BNETACCOUNT         = "Binds to Warband",
  ITEM_BIND_TO_ACCOUNT             = "Binds to Warband",
  ITEM_ACCOUNTBOUND_UNTIL_EQUIP    = "Warbound until equipped",
  ITEM_BNETACCOUNTBOUND            = "Warbound",
  ITEM_ACCOUNTBOUND                = "Warbound",
}
local function withWarbandGlobals(fn)
  local saved = {}
  for name, value in pairs(WARBAND_WORDING) do saved[name] = _G[name]; _G[name] = value end
  local ok, err = pcall(fn)
  for name in pairs(WARBAND_WORDING) do _G[name] = saved[name] end
  if not ok then error(err, 0) end
end

test("Compat: an item NAME containing 'Warbound' is not a bind line", function()
  -- "Warbound Cache of Void-Touched Armaments: Boots" is line 1 of the tooltip. A substring match
  -- classified the item off its own title and never reached the real binding line below it.
  local savedTI = _G.C_TooltipInfo
  _G.C_TooltipInfo = { GetHyperlink = function()
    return { lines = {
      { leftText = "Warbound Cache of Void-Touched Armaments: Boots" },
      { leftText = "Item Level 259" },
      { leftText = "Binds to Warband until equipped" },
    } }
  end }
  assertEqual(NS.Compat.ScanBound("[Cache]"), "WARBAND_UE")
  -- And a name that merely mentions it, with no bind line at all, is not warbound.
  _G.C_TooltipInfo = { GetHyperlink = function()
    return { lines = { { leftText = "Warbound Cache of Void-Touched Armaments" } } }
  end }
  assertEqual(NS.Compat.ScanBound("[Cache]"), nil)
  _G.C_TooltipInfo = savedTI
end)

test("Compat: ScanBound separates warbound from warbound-until-equipped", function()
  withWarbandGlobals(function()
    local CASES = {
      -- The "…until equipped" wordings must win over their own prefixes ("Warbound" /
      -- "Binds to Warband"), which a plain find() would otherwise match first.
      { "Binds to Warband until equipped", "WARBAND_UE" },
      { "Warbound until equipped",         "WARBAND_UE" },
      { "Binds to Warband",                "WARBAND" },
      { "Warbound",                        "WARBAND" },
      { "Binds when picked up",            nil },  -- BOP is bindType's job, not the scanner's
    }
    for _, case in ipairs(CASES) do
      withTooltip(case[1], function()
        assertEqual(NS.Compat.ScanBound("[Item]"), case[2], case[1])
      end)
    end
  end)
end)

test("Compat: ScanBound still splits UE when the …_UNTIL_EQUIP globals are nil", function()
  -- A live client can hand back nil for those two globals. Keying the UE state on them alone
  -- degraded every warbound-until-equipped drop to plain WARBAND (the shorter wording is a
  -- prefix of the longer), so the qualifier has a literal fallback. English-only addon.
  withWarbandGlobals(function()
    _G.ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP, _G.ITEM_ACCOUNTBOUND_UNTIL_EQUIP = nil, nil
    withTooltip("Binds to Warband until equipped", function()
      assertEqual(NS.Compat.ScanBound("[Item]"), "WARBAND_UE")
    end)
    withTooltip("Warbound until equipped", function()
      assertEqual(NS.Compat.ScanBound("[Item]"), "WARBAND_UE")
    end)
    withTooltip("Binds to Warband", function()
      assertEqual(NS.Compat.ScanBound("[Item]"), "WARBAND")
    end)
  end)
end)

test("Compat: ScanBound reads warbound wording with every global absent", function()
  -- Same idea one step further: no globals at all (the mock's own state). The literals carry it.
  withTooltip("Binds to Warband until equipped", function()
    assertEqual(NS.Compat.ScanBound("[Item]"), "WARBAND_UE")
  end)
  withTooltip("Warbound", function()
    assertEqual(NS.Compat.ScanBound("[Item]"), "WARBAND")
  end)
  withTooltip("Binds when equipped", function()
    assertEqual(NS.Compat.ScanBound("[Item]"), nil)
  end)
end)

test("Compat: BindState maps every Enum.ItemBind value to a bind token", function()
  local B = NS.Compat.BindState
  assertEqual(B(1), "BOP")          -- OnAcquire
  assertEqual(B(4), "BOP")          -- Quest
  assertEqual(B(2), "BOE")          -- OnEquip
  assertEqual(B(3), "BOE")          -- OnUse
  assertEqual(B(7), "WARBAND")      -- ToWoWAccount
  assertEqual(B(8), "WARBAND")      -- ToBnetAccount
  assertEqual(B(9), "WARBAND_UE")   -- ToBnetAccountUntilEquipped
  assertEqual(B(0), nil)            -- None -> unbound
  assertEqual(B(5), nil)            -- Blizzard's own Unused1/Unused2
  assertEqual(B(6), nil)
  assertEqual(B(nil), nil)
end)

test("Compat: GetItemExtras reads the bind state off bindType when it names one", function()
  T.mocks.__itemBindTypes["[Cache]"] = 9
  local _, bound = NS.Compat.GetItemExtras("[Cache]")
  assertEqual(bound, "WARBAND_UE")
  T.mocks.__itemBindTypes["[Cache]"] = 8
  local _, plain = NS.Compat.GetItemExtras("[Cache]")
  assertEqual(plain, "WARBAND")
  T.mocks.__itemBindTypes["[Cache]"] = nil
end)

test("Compat: GetItemExtras believes the tooltip when bindType understates it", function()
  -- Real case (item 278014): a cache whose tooltip reads "Binds to Warband until equipped" reports
  -- bindType 2 (OnEquip). Trusting the bind type alone files it as plain BoE.
  local savedTI = _G.C_TooltipInfo
  _G.C_TooltipInfo = { GetHyperlink = function()
    return { lines = { { leftText = "Binds to Warband until equipped" } } }
  end }
  T.mocks.__itemBindTypes["[Cache]"] = 2
  local _, bound = NS.Compat.GetItemExtras("[Cache]")
  assertEqual(bound, "WARBAND_UE")
  T.mocks.__itemBindTypes["[Cache]"] = nil
  _G.C_TooltipInfo = savedTI
end)

test("Compat: an uncached item's 'Retrieving item information' tooltip is NOT readable", function()
  -- The trap that made two repair passes clear themselves having learned nothing: an uncached item
  -- doesn't give an empty tooltip, it gives a perfectly legible one that says only this.
  local savedTI, savedR = _G.C_TooltipInfo, _G.RETRIEVING_ITEM_INFO
  _G.RETRIEVING_ITEM_INFO = "Retrieving item information"
  _G.C_TooltipInfo = { GetHyperlink = function()
    return { lines = { { leftText = "Retrieving item information" } } }
  end }
  local state, readable = NS.Compat.ScanBound("[Cold]")
  assertEqual(state, nil)
  assertFalse(readable, "a retrieving-placeholder tooltip must not settle a row")
  _G.C_TooltipInfo, _G.RETRIEVING_ITEM_INFO = savedTI, savedR
end)

test("Compat: ItemBindState isn't settled until the item data is cached too", function()
  local savedTI = _G.C_TooltipInfo
  _G.C_TooltipInfo = { GetHyperlink = function()
    return { lines = { { leftText = "Binds when equipped" } } }
  end }
  -- The mock's GetItemInfo always names the item, so drop it to model an uncached one.
  local savedGet = T.mocks.C_Item.GetItemInfo
  T.mocks.C_Item.GetItemInfo = function() return nil end
  local _, settled = NS.Compat.ItemBindState(4242)
  assertFalse(settled, "readable tooltip, but the bind type can't be read yet")
  T.mocks.C_Item.GetItemInfo = savedGet
  local _, settled2 = NS.Compat.ItemBindState(4242)
  assertTrue(settled2)
  _G.C_TooltipInfo = savedTI
end)

test("Compat: ScanBound reports whether the tooltip was readable at all", function()
  -- nil state means two different things — "not warbound" and "the client hasn't built this
  -- tooltip yet" — and the repair job must not confuse them.
  local savedTI = _G.C_TooltipInfo
  _G.C_TooltipInfo = { GetHyperlink = function() return { lines = { { leftText = "" } } } end }
  local state, readable = NS.Compat.ScanBound("[Cold]")
  assertEqual(state, nil)
  assertFalse(readable)
  _G.C_TooltipInfo = { GetHyperlink = function()
    return { lines = { { leftText = "Binds when equipped" } } }
  end }
  local state2, readable2 = NS.Compat.ScanBound("[Warm]")
  assertEqual(state2, nil)
  assertTrue(readable2, "readable, and it simply isn't warbound")
  _G.C_TooltipInfo = savedTI
end)

test("Compat: GetItemExtras falls back to the tooltip when the item isn't cached", function()
  -- GetItemInfo answers nothing at all for an uncached item — bindType included.
  local savedTI = _G.C_TooltipInfo
  _G.C_TooltipInfo = { GetHyperlink = function()
    return { lines = { { leftText = "Binds to Warband until equipped" } } }
  end }
  local _, bound = NS.Compat.GetItemExtras("[Uncached]")
  assertEqual(bound, "WARBAND_UE")
  _G.C_TooltipInfo = savedTI
end)

test("Compat: ItemBindState resolves an id, nil when the client can't answer", function()
  T.mocks.__itemBindTypes[278015] = 9
  assertEqual(NS.Compat.ItemBindState(278015), "WARBAND_UE")
  assertEqual(NS.Compat.ItemBindState(999999), nil)   -- not cached -> caller retries
  assertEqual(NS.Compat.ItemBindState(nil), nil)
  T.mocks.__itemBindTypes[278015] = nil
end)

test("Compat: ItemBindState takes the tooltip's verdict when bindType has none", function()
  -- A record may have only a link, or the bind type may not name the state — the second opinion
  -- must still land, and must not be lost because the id lookup came back empty.
  local savedTI = _G.C_TooltipInfo
  _G.C_TooltipInfo = { GetHyperlink = function()
    return { lines = { { leftText = "Binds to Warband until equipped" } } }
  end }
  assertEqual(NS.Compat.ItemBindState(999999, "[Cache]"), "WARBAND_UE")
  assertEqual(NS.Compat.ItemBindState("[Cache]"), "WARBAND_UE")   -- link as the item itself
  _G.C_TooltipInfo = savedTI
end)

test("Compat: BestBound keeps the more specific verdict, never demotes warbound", function()
  local best = NS.Compat.BestBound
  assertEqual(best("BOE", "WARBAND_UE"), "WARBAND_UE")  -- bindType said BOE, tooltip saw UE
  assertEqual(best("WARBAND_UE", "BOE"), "WARBAND_UE")  -- and the other way round
  assertEqual(best("WARBAND", "WARBAND_UE"), "WARBAND_UE")
  assertEqual(best("WARBAND_UE", "WARBAND"), "WARBAND_UE")
  assertEqual(best("BOP", nil), "BOP")
  assertEqual(best(nil, "BOE"), "BOE")
  assertEqual(best(nil, nil), nil)
  assertEqual(best("BOP", "BOE"), "BOP")               -- neither warbound: first stands
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

test("Compat: CurrencyLinkID parses the id from a currency link", function()
  assertEqual(NS.Compat.CurrencyLinkID("|cffffffff|Hcurrency:3008::|h[Valorstones]|h|r"), 3008)
  assertEqual(NS.Compat.CurrencyLinkID("|Hitem:12345::|h[Nope]|h"), nil)
  assertEqual(NS.Compat.CurrencyLinkID(nil), nil)
end)

test("Compat: GetCurrencyInfoFromLink returns id, name, icon", function()
  local id, name, icon = NS.Compat.GetCurrencyInfoFromLink("|Hcurrency:3008::|h[Valorstones]|h")
  assertEqual(id, 3008)
  assertEqual(name, "Valorstones")
  assertEqual(icon, 100000 + 3008)
end)

test("Compat: CurrencyCategory resolves a currency to its list header", function()
  assertEqual(NS.Compat.CurrencyCategory(3008), "The War Within")
  assertEqual(NS.Compat.CurrencyCategory(2914), "The War Within")
  assertEqual(NS.Compat.CurrencyCategory(999999), nil)   -- unknown id -> nil
end)

test("Compat: CurrencyName resolves via C_CurrencyInfo, nil when unknown", function()
  assertEqual(NS.Compat.CurrencyName(3008), "Valorstones")
  assertEqual(NS.Compat.CurrencyName(999999), nil)
  assertEqual(NS.Compat.CurrencyName(nil), nil)
end)

test("Compat: CurrencyQuality returns the tier, nil when unknown", function()
  assertEqual(NS.Compat.CurrencyQuality(3008), 4)
  assertEqual(NS.Compat.CurrencyQuality(999999), nil)
  assertEqual(NS.Compat.CurrencyQuality(nil), nil)
end)

test("Compat: CurrencyBound is WARBAND when transferable, else BOP, nil when unknown", function()
  assertEqual(NS.Compat.CurrencyBound(3008), "WARBAND")   -- Warband-transferable (mock)
  assertEqual(NS.Compat.CurrencyBound(2914), "BOP")       -- not transferable -> soulbound
  assertEqual(NS.Compat.CurrencyBound(999999), nil)       -- unresolved id -> nil
  assertEqual(NS.Compat.CurrencyBound(nil), nil)
end)
