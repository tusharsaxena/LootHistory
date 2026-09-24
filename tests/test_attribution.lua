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

-- The family match is pattern work over client text, and client text contains U+00A0. Lua's `%s`
-- is a byte-wise ASCII class that never matches the no-break space's \194\160, so both halves of
-- seedToken -- the `dropLast` suffix strip and the trim -- silently no-op on a name that uses one.
test("Attribution: a no-break space in a localized spell name does not break the family match", function()
  local A = NS.Attribution
  local orig = NS.Compat.GetSpellName

  -- A stray pad on one entry of the client's string table. The trim leaves it, so the token is
  -- "prospection\194\160" and no cast written with an ordinary space can contain it.
  NS.Compat.GetSpellName = function(id)
    local n = { [13262] = "Désenchanter", [51005] = "Broyage", [31252] = "Prospection\194\160",
                [434926] = "Broyage de masse Mycoflore",
                [225904] = "Prospection de masse Ardoise" }
    return n[id]
  end
  assertEqual(A:DeconstructSource(990020, "Prospection algarienne"), "PROSPECTING")

  -- The no-break space as the JOINER, which is what breaks `dropLast`: "%s+%S+%s*$" needs an ASCII
  -- space to anchor the final word on, finds none, and strips nothing -- so the stem the seed exists
  -- to produce is never produced and the whole per-ore family stops attributing. Only the dropLast
  -- seed resolves here, so nothing else can carry the match.
  NS.Compat.GetSpellName = function(id)
    if id == 225904 then return "Prospection\194\160de\194\160masse\194\160Ardoise" end
    return nil
  end
  assertEqual(A:DeconstructSource(990021, "Prospection\194\160de\194\160masse\194\160Aqirite"), "PROSPECTING")

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

-- ── The keystone context's lifetime ──────────────────────────────────────────────────────────
--
-- State.keystone turns every GameObject loot into MPLUS. It is kept through completion so the
-- reward chest still records as MPLUS, and it must go when the player leaves the party instance or
-- the key resets; otherwise every herb, ore node and world chest for the rest of the session is
-- persisted as MPLUS with a keystone level. Each case puts the client context, C_ChallengeMode and
-- the keystone back on the way out, whether the body passed or threw.
local function withKeystoneEnv(ctx, activeLevel, body)
  local savedCtx, savedCM, savedKey = mocks.__context, mocks.C_ChallengeMode, NS.State.keystone
  local c = {}
  for k, v in pairs(savedCtx) do c[k] = v end
  for k, v in pairs(ctx) do c[k] = v end
  mocks.__context = c
  mocks.C_ChallengeMode = (activeLevel ~= nil)
    and { GetActiveKeystoneInfo = function() return activeLevel end } or nil
  local ok, err = pcall(body)
  mocks.__context, mocks.C_ChallengeMode, NS.State.keystone = savedCtx, savedCM, savedKey
  if not ok then error(err, 0) end
end

test("Attribution: leaving the party instance clears the keystone, so later objects are CONTAINER",
function()
  withKeystoneEnv({ inInstance = false, instanceType = "none" }, nil, function()
    NS.State.keystone = { level = 12 }
    NS.Attribution:OnZoneChanged()
    assertEqual(NS.State.keystone, nil, "the keystone survived leaving the instance")
    assertEqual(NS.Attribution:ResolveLootSource(OBJECT, NS.State), "CONTAINER")
  end)
end)

test("Attribution: a zone change inside the party instance keeps the keystone (MPLUS 12)", function()
  withKeystoneEnv({ inInstance = true, instanceType = "party" }, nil, function()
    NS.State.keystone = { level = 12 }
    NS.Attribution:OnZoneChanged()
    local source, detail = NS.Attribution:ResolveLootSource(OBJECT, NS.State)
    assertEqual(source, "MPLUS")
    assertEqual(detail.keystoneLevel, 12)
  end)
end)

test("Attribution: CHALLENGE_MODE_RESET clears the keystone", function()
  withKeystoneEnv({ inInstance = true, instanceType = "party" }, nil, function()
    NS.State.keystone = { level = 12 }
    NS.Attribution:OnChallengeModeReset()
    assertEqual(NS.State.keystone, nil, "the keystone survived CHALLENGE_MODE_RESET")
  end)
end)

test("Attribution: a completion-time keystone level of 0 does not overwrite the started level",
function()
  withKeystoneEnv({ inInstance = true, instanceType = "party" }, 0, function()
    NS.State.keystone = { level = 12 }
    NS.Attribution:OnChallengeModeCompleted()
    assertEqual(NS.State.keystone.level, 12)
  end)
end)

test("Attribution: zoning back into an active key re-arms the keystone at its level", function()
  withKeystoneEnv({ inInstance = true, instanceType = "party" }, 15, function()
    NS.State.keystone = nil
    NS.Attribution:OnZoneChanged()
    assertTrue(NS.State.keystone ~= nil, "re-entry to an active key left no keystone context")
    assertEqual(NS.State.keystone.level, 15)
  end)
end)

-- ── Enable(): the wiring, not the handlers ───────────────────────────────────────────────────
--
-- Every case above hand-feeds an event straight to a stamper. Not one of them proves the stamper
-- is ever REACHED in the client. `Attribution:Enable` is what registers the nine bus events, the
-- player-only UNIT_SPELLCAST_SUCCEEDED frame and the five read-side hooks, and it had zero test
-- callers: a mistyped event name or a dropped hooksecurefunc would have left every case above
-- green while the attribution engine received nothing at all. testing-§8 asks the addon's own
-- suite to own exactly this — integration over this addon's wiring, not a re-test of the library.
--
-- The three merchant/mail globals and GetQuestReward are absent from the mock and the kit's
-- hooksecurefunc is a no-op, so the hook branches are dead unless the case supplies both. Every
-- one of those substitutions lands on the SHARED mock table, and Enable() latches and registers on
-- the SHARED addon object, so the whole thing runs inside a wrapper that puts all of it back on
-- the way out whether the body passed, failed or threw. Restoring on the last line of the body
-- instead would put nothing back on a failure — tests/_kit/framework.lua pcalls the body — and the
-- next suite would run against a half-stubbed client with nine stray registrations on the bus.

-- Sorted: this asserts the SET Enable registers, and the registration order carries no meaning.
local ENABLE_EVENTS = {
  "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET", "CHALLENGE_MODE_START", "ENCOUNTER_END",
  "ENCOUNTER_START", "LOOT_OPENED", "QUEST_TURNED_IN", "TRADE_ACCEPT_UPDATE",
  "ZONE_CHANGED_NEW_AREA",
}
-- In Enable()'s own order: three globals hooked inline, then core/Compat.lua's two seams.
local ENABLE_HOOKS = {
  "BuyMerchantItem", "TakeInboxItem", "AutoLootMailItem", "UseContainerItem", "GetQuestReward",
}

local STUBBED = { "CreateFrame", "hooksecurefunc", "BuyMerchantItem", "TakeInboxItem",
                  "AutoLootMailItem", "GetQuestReward", "C_Container" }

local function withClientStubs(body)
  local saved = {}
  for _, key in ipairs(STUBBED) do saved[key] = mocks[key] end

  local rec = { frames = {}, hooks = {}, before = {} }
  for event in pairs(NS.addon.__events) do rec.before[event] = true end

  mocks.CreateFrame = function(...)
    local f = saved.CreateFrame(...)
    rec.frames[#rec.frames + 1] = f
    return f
  end
  -- Both call shapes: hooksecurefunc("Name", fn) for a global, hooksecurefunc(tbl, "Name", fn) for
  -- a table member, which is how core/Compat.lua reaches C_Container.UseContainerItem.
  mocks.hooksecurefunc = function(a, b)
    rec.hooks[#rec.hooks + 1] = (type(a) == "table") and tostring(b) or tostring(a)
  end
  mocks.BuyMerchantItem  = function() end
  mocks.TakeInboxItem    = function() end
  mocks.AutoLootMailItem = function() end
  mocks.GetQuestReward   = function() end
  local container = {}
  for k, v in pairs(saved.C_Container or {}) do container[k] = v end
  container.UseContainerItem = function() end
  mocks.C_Container = container

  local ok, err = pcall(body, rec)

  for _, key in ipairs(STUBBED) do mocks[key] = saved[key] end
  for event in pairs(NS.addon.__events) do
    if not rec.before[event] then NS.addon:UnregisterEvent(event) end
  end
  NS.Attribution._enabled = false
  if not ok then error(err, 0) end
end

test("Attribution: Enable registers nine bus events, the player-only cast frame and five hooks",
function()
  withClientStubs(function(rec)
    NS.Attribution:Enable()

    local added = {}
    for event in pairs(NS.addon.__events) do
      if not rec.before[event] then added[#added + 1] = event end
    end
    table.sort(added)
    assertEqual(table.concat(added, ","), table.concat(ENABLE_EVENTS, ","),
      "Enable registered a different event set than the peripheral stampers need")

    assertEqual(table.concat(rec.hooks, ","), table.concat(ENABLE_HOOKS, ","),
      "Enable installed a different read-side hook set")

    -- UNIT_SPELLCAST_SUCCEEDED must NOT arrive on the bus: a bare RegisterEvent delivers every
    -- nameplate's cast in a raid, which is the whole reason for the dedicated frame.
    assertTrue(NS.addon.__events["UNIT_SPELLCAST_SUCCEEDED"] == nil,
      "UNIT_SPELLCAST_SUCCEEDED was registered on the shared bus — that is the raid-wide firehose")
    assertEqual(#rec.frames, 1, "Enable built " .. #rec.frames .. " frame(s); it needs exactly the "
      .. "one that carries the unit-filtered cast event")
    local units = rec.frames[1] and rec.frames[1].__unitEvents["UNIT_SPELLCAST_SUCCEEDED"]
    assertTrue(units ~= nil, "the cast frame never called RegisterUnitEvent for "
      .. "UNIT_SPELLCAST_SUCCEEDED")
    assertEqual(table.concat(units or {}, ","), "player",
      "the cast frame's unit filter is no longer player-only")
    assertTrue(rec.frames[1]:GetScript("OnEvent") ~= nil,
      "the cast frame registered its event but has no OnEvent handler to receive it")

    -- The latch. OnEnable can run more than once across a session; a second Enable that re-ran
    -- would double every registration and stack a second copy of every hook.
    local frames, hooks = #rec.frames, #rec.hooks
    NS.Attribution:Enable()
    assertEqual(#rec.frames, frames, "a second Enable() built another cast frame")
    assertEqual(#rec.hooks, hooks, "a second Enable() installed the read-side hooks again")
  end)
end)
