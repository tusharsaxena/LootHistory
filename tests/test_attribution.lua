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

test("Attribution: DeconstructSource resolves enumerated ids locale-independently", function()
  local A = NS.Attribution
  -- Id-first: every enumerated spell attributes regardless of the (localized) name.
  assertEqual(A:DeconstructSource(13262, "Disenchant"), "DISENCHANT")
  assertEqual(A:DeconstructSource(289991, "Disenchanting"), "DISENCHANT")
  assertEqual(A:DeconstructSource(51005, "Milling"), "MILLING")
  assertEqual(A:DeconstructSource(382981, "Dragon Isles Milling"), "MILLING")
  assertEqual(A:DeconstructSource(434926, "Mass Mill Mycobloom"), "MILLING")
  assertEqual(A:DeconstructSource(31252, "Prospecting"), "PROSPECTING")
  assertEqual(A:DeconstructSource(434018, "Algari Prospecting"), "PROSPECTING")
  assertEqual(A:DeconstructSource(225904, "Mass Prospect Felslate"), "PROSPECTING")
  -- Unknown id + no name (headless GetSpellName) → no match.
  assertEqual(A:DeconstructSource(12345, "Fireball"), nil)
  assertEqual(A:DeconstructSource(1269575, nil), "MILLING")   -- id fallback, name unavailable
  assertEqual(A:DeconstructSource(374627, nil), "PROSPECTING")
  assertEqual(A:DeconstructSource(99999, nil), nil)
end)

-- Un-enumerated per-herb/expansion variants are matched by their *localized* name family, resolved
-- from seed spellIDs via C_Spell — proving the check follows the client locale and never depends on
-- an English literal (Ka0s Standard localization-§4 / anti-pattern #37). GetSpellName is stubbed to
-- return the locale-specific seed names the live client would.
test("Attribution: DeconstructSource matches un-enumerated variants by localized name family", function()
  local A = NS.Attribution
  local orig = NS.Compat.GetSpellName

  -- enUS client: seed names give the "Milling"/"Prospecting" word and the "Mass Mill/Prospect" stem.
  NS.Compat.GetSpellName = function(id)
    local n = { [13262] = "Disenchant", [51005] = "Milling", [31252] = "Prospecting",
                [434926] = "Mass Mill Mycobloom", [225904] = "Mass Prospect Felslate" }
    return n[id]
  end
  assertEqual(A:DeconstructSource(990001, "Mass Mill Arthran"), "MILLING")        -- unknown id, "Mass Mill" stem
  assertEqual(A:DeconstructSource(990002, "Mass Prospect Aqirite"), "PROSPECTING")-- unknown id, "Mass Prospect" stem
  assertEqual(A:DeconstructSource(990003, "Khaz Algar Milling"), "MILLING")       -- embeds "Milling"
  assertEqual(A:DeconstructSource(990004, "Fireball"), nil)                       -- no family word

  -- deDE client: the same code follows the localized seed names — no enUS literal is ever compared.
  NS.Compat.GetSpellName = function(id)
    local n = { [13262] = "Entzaubern", [51005] = "Mahlen", [31252] = "Prospektieren",
                [434926] = "Mahlen von Mycobloom", [225904] = "Prospektieren von Felslit" }
    return n[id]
  end
  assertEqual(A:DeconstructSource(990010, "Entzaubern"), "DISENCHANT")
  assertEqual(A:DeconstructSource(990011, "Dracheninsel-Mahlen"), "MILLING")      -- embeds "Mahlen"
  assertEqual(A:DeconstructSource(990012, "Algari-Prospektieren"), "PROSPECTING") -- embeds "Prospektieren"
  assertEqual(A:DeconstructSource(990013, "Feuerball"), nil)

  NS.Compat.GetSpellName = orig
end)

-- The handler fires on every player cast, so a repeated spell (a combat rotation) must resolve
-- from the per-spellID memo, not re-run GetSpellName + the name-family loop each time.
test("Attribution: OnSpellSucceeded memoizes the lookup — a repeated spell skips re-resolution", function()
  resetContext()
  local A = NS.Attribution
  local orig = NS.Compat.GetSpellName
  local calls = {}
  local names = { [13262] = "Disenchant", [51005] = "Milling", [31252] = "Prospecting",
                  [434926] = "Mass Mill Mycobloom", [225904] = "Mass Prospect Felslate",
                  [990300] = "Fireball" }   -- a non-deconstruct cast; seeds resolve, so its miss caches
  NS.Compat.GetSpellName = function(id) calls[id] = (calls[id] or 0) + 1; return names[id] end

  A:OnSpellSucceeded(nil, "player", "c", 990300)          -- first sight: resolves + caches the negative
  assertEqual(A:Consume(), "OTHER")
  local firstLookups = calls[990300]
  assertTrue(firstLookups >= 1, "cast name is looked up on first sight")

  resetContext()
  A:OnSpellSucceeded(nil, "player", "c", 990300)          -- repeats must hit the cache...
  A:OnSpellSucceeded(nil, "player", "c", 990300)
  assertEqual(A:Consume(), "OTHER")
  assertEqual(calls[990300], firstLookups, "memoized: no extra GetSpellName for a repeated spell")

  NS.Compat.GetSpellName = orig
end)

-- A conclusive result is frozen: once a spellID resolved to a source, later name changes (or a
-- transiently uncached name) can't flip it. Guards the memo against a false negative freezing in.
test("Attribution: a memoized deconstruct source survives a later name change", function()
  resetContext()
  local A = NS.Attribution
  local orig = NS.Compat.GetSpellName
  local castName = "Mass Mill Arthran"                    -- matches the MILLING name family
  NS.Compat.GetSpellName = function(id)
    if id == 990400 then return castName end
    local n = { [13262] = "Disenchant", [51005] = "Milling", [31252] = "Prospecting",
                [434926] = "Mass Mill Mycobloom", [225904] = "Mass Prospect Felslate" }
    return n[id]
  end

  A:OnSpellSucceeded(nil, "player", "c", 990400)          -- caches MILLING (name-family hit is conclusive)
  assertEqual(A:Consume(), "MILLING")

  castName = "Fireball"                                   -- would NOT match if re-resolved
  resetContext()
  A:OnSpellSucceeded(nil, "player", "c", 990400)
  assertEqual(A:Consume(), "MILLING", "positive result is memoized, not recomputed")

  NS.Compat.GetSpellName = orig
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
