local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local C = NS.Constants

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- ── The source enum and its derived tables ─────────────────────────────────────

test("Constants: every SourceType value equals its key (the stable stored form)", function()
  -- The stored string IS the export contract; a key/value drift would silently rewrite CSVs.
  for k, v in pairs(C.SourceType) do assertEqual(v, k, "SourceType." .. k) end
end)

-- A source this client lacks (C.SOURCE_CLIENTS, clients-§4) is ABSENT: still a SourceType member
-- with its label (the export contract), never in the order, the implemented list or the reasons.
test("Constants: every SourceType member this client serves appears in the display order", function()
  local inOrder = {}
  for _, s in ipairs(C.SourceOrder) do inOrder[s] = true end
  for k in pairs(C.SourceType) do
    if C.SOURCE_ABSENT[k] then
      assertFalse(inOrder[k], k .. " is absent on this client yet in SourceOrder")
    else
      assertTrue(inOrder[k], k .. " is missing from SourceOrder")
    end
  end
end)

test("Constants: GATHERING is a gain source on both clients, never a ledger reason (farm mode #39, F1)", function()
  -- red under: GATHERING missing from a source table, or listed as a ledger-only reason (it would
  -- drop out of the mute list and read as a holdings diff).
  local inOrder = {}
  for _, s in ipairs(C.SourceOrder) do inOrder[s] = true end
  assertEqual(C.SourceType.GATHERING, "GATHERING")
  assertTrue(inOrder.GATHERING, "in SourceOrder")
  assertEqual(C.SourceLabel.GATHERING, "Gathering")
  assertTrue(C.SOURCE_IMPLEMENTED.GATHERING, "implemented")
  assertEqual(C.LEDGER_REASON.GATHERING, nil, "not a ledger reason")
  assertEqual(C.SOURCE_ABSENT.GATHERING, nil, "on both clients")
  assertEqual(C.GATHERING_TTL, 5)
end)

test("Constants: C.FARM carries the spec's numbers, a gain-source set and all seven gain kinds (#39)", function()
  local F = C.FARM
  assertEqual(table.concat({ F.STALE_SEC, F.INTENT_TTL, F.IDLE_TICK, F.LOG_CAP, F.LOG_BATCH, F.MOB_RING,
    F.MIN_RATE_SEC, F.PRICE_DELAY, F.PRICE_BATCH, F.PRICE_TRIES, F.EPIC_FLOOR }, ","), "1800,30,30,2000,100,256,60,1,20,5,4")
  local kinds, n = {}, 0
  for k in pairs(C.GainKind) do kinds[#kinds + 1] = k end
  for k, v in pairs(F.GAIN_KINDS) do n = n + 1; assertTrue(v == true and C.GainKind[k] == k, k .. " is a GainKind") end
  assertEqual(n, #kinds, "every C.GainKind is in the farm set")
  for src in pairs(F.GAIN_SOURCES) do assertTrue(C.SourceType[src] == src, src .. " is a source") end
  for _, src in ipairs({ "VENDOR", "MAIL", "AH", "TRADE", "CRAFT" }) do assertEqual(F.GAIN_SOURCES[src], nil, src) end
  for reason in pairs(F.COST_REASONS) do assertTrue(C.LEDGER_REASON[reason] == true, reason .. " is a ledger reason") end
end)

test("Constants: the warband bank is Retail-only (R1), its two reasons absent on WoW Forever", function()
  -- red under: a WoW Forever build that still declares the warband bank, or still offers its reasons.
  assertEqual(C.FEATURE.warbandBank, not T.forever)
  local inOrder = {}
  for _, s in ipairs(C.SourceOrder) do inOrder[s] = true end
  for _, s in ipairs({ "WARBAND_DEPOSIT", "WARBAND_WITHDRAW" }) do
    assertEqual(C.SOURCE_ABSENT[s] == true, T.forever, s .. " absent")
    assertEqual(inOrder[s] == true, not T.forever, s .. " in SourceOrder")
    assertEqual(C.SOURCE_IMPLEMENTED[s] == true, not T.forever, s .. " implemented")
    assertEqual(C.LEDGER_REASON[s] == true, not T.forever, s .. " a ledger reason")
    assertEqual(C.SourceType[s], s, s .. " stays a SourceType member (the export contract)")
    assertTrue(type(C.SourceLabel[s]) == "string", s .. " keeps its label")
  end
  local absent = 0
  for _ in pairs(C.SOURCE_ABSENT) do absent = absent + 1 end
  if not T.forever then assertEqual(absent, 0, "Retail lacks no source") end
end)

-- Ruling R2: the keystone (MPLUS) and the content WoW Forever does not have -- bonus rolls, Milling
-- and Prospecting -- are Retail's. Disenchant serves both, and so does the DECONSTRUCT reason (F1).
local R2_SOURCES = { "MPLUS", "BONUS_ROLL", "MILLING", "PROSPECTING" }

test("Constants: Mythic+, bonus roll, Milling and Prospecting are Retail-only (R2)", function()
  -- red under: a WoW Forever build that still declares the keystone, or still offers one of these
  -- in a filter, the mute list or the reasons; or a Retail build that lost one.
  assertEqual(C.FEATURE.mythicPlus, not T.forever)
  local inOrder, offered = {}, {}
  for _, s in ipairs(C.SourceOrder) do inOrder[s] = true end
  for _, o in ipairs(C.SOURCE_OPTIONS) do offered[o.value] = true end
  for _, s in ipairs(R2_SOURCES) do
    assertEqual(C.SOURCE_ABSENT[s] == true, T.forever, s .. " absent")
    assertEqual(inOrder[s] == true, not T.forever, s .. " in SourceOrder")
    assertEqual(C.SOURCE_IMPLEMENTED[s] == true, not T.forever, s .. " implemented")
    assertEqual(C.SourceType[s], s, s .. " stays a SourceType member (the export contract)")
    assertTrue(type(C.SourceLabel[s]) == "string", s .. " keeps its label")
  end
  for _, s in ipairs(R2_SOURCES) do
    assertEqual(offered[s] == true, not T.forever, s .. " offered as a capture mute")
  end
  assertTrue(inOrder.DISENCHANT and offered.DISENCHANT, "Disenchant serves both clients")
end)

-- Owner ruling F1 (K101-FU-01): a disenchanted item's loss keeps its reason on WoW Forever. The
-- stored key is DECONSTRUCT on both clients; only its label is the client's, "Disenchanted" on WoW
-- Forever (whose one deconstruct is Disenchant 13262) and "Deconstructed" on Retail, unchanged.
test("Constants: the DECONSTRUCT reason serves both clients, labeled Disenchanted on WoW Forever (F1)", function()
  -- red under: a WoW Forever build that drops the reason again (R2's first shape), or a Retail
  -- build whose label moved
  local inOrder, offered = {}, {}
  for _, s in ipairs(C.SourceOrder) do inOrder[s] = true end
  for _, o in ipairs(C.SOURCE_OPTIONS) do offered[o.value] = true end
  assertEqual(C.SourceType.DECONSTRUCT, "DECONSTRUCT", "the stored key is the same on both")
  assertFalse(C.SOURCE_ABSENT.DECONSTRUCT == true, "DECONSTRUCT absent")
  assertTrue(inOrder.DECONSTRUCT, "DECONSTRUCT in SourceOrder")
  assertTrue(C.SOURCE_IMPLEMENTED.DECONSTRUCT, "DECONSTRUCT implemented")
  assertTrue(C.LEDGER_REASON.DECONSTRUCT, "DECONSTRUCT a ledger reason")
  assertFalse(offered.DECONSTRUCT == true, "a ledger reason is never a capture mute")
  assertEqual(C.SourceLabel.DECONSTRUCT, T.forever and "Disenchanted" or "Deconstructed")
  assertEqual(C.SourceLabel.DISENCHANT, "Disenchant", "the gain source keeps its label")
end)

-- Group by Source keys its groups on the label (modules/BrowserTableGroup.lua), and the Source
-- filter and the Insights legends name a key by it, so two keys sharing a label merge two groups
-- and show two filter entries no one can tell apart. K101-FU-01 review: Forever's DECONSTRUCT read
-- "Disenchant", the DISENCHANT gain source's own label.
test("Constants: no two source keys share a label, on either client", function()
  -- red under: a client wording that reuses another key's label (Forever's DECONSTRUCT = "Disenchant")
  local owner = {}
  for key in pairs(C.SourceType) do
    local label = C.SourceLabel[key]
    assertTrue(type(label) == "string", key .. " has a label")
    assertEqual(owner[label], nil, label .. " labels both " .. tostring(owner[label]) .. " and " .. key)
    owner[label] = key
  end
end)

test("Constants: the account's words are the client's (R2): Warband on Retail, Account on WoW Forever", function()
  if T.forever then
    assertEqual(C.ACCOUNT.holder, "Account")
    assertEqual(C.ACCOUNT.bound, "Account Bound")
    assertEqual(C.ACCOUNT.boundUE, "Account Bound Until Equipped")
    assertEqual(C.ACCOUNT.boundUEShort, "Account Bound (UE)")
  else
    assertEqual(C.ACCOUNT.holder, "Warband")
    assertEqual(C.ACCOUNT.bound, "Warbound")
    assertEqual(C.ACCOUNT.boundUE, "Warbound Until Equipped")
    assertEqual(C.ACCOUNT.boundUEShort, "Warbound (UE)")
  end
  assertEqual(C.WARBAND_HOLDER, "§warband", "the stored holder key is the same on both")
end)

test("Constants: the Wowhead item base is the client's (R7): /forever/ on WoW Forever, the root on Retail", function()
  -- red under: a WoW Forever build whose History CSV links its items to Retail's Wowhead pages.
  assertEqual(C.WOWHEAD_ITEM_BASES.retail, "https://www.wowhead.com/item=")
  assertEqual(C.WOWHEAD_ITEM_BASES.forever, "https://www.wowhead.com/forever/item=")
  assertEqual(C.WOWHEAD_ITEM_BASE, C.WOWHEAD_ITEM_BASES[T.forever and "forever" or "retail"])
end)

test("Constants: a character key's form is the client's (D6): Name-Realm on Retail, a two-word name on WoW Forever", function()
  assertEqual(C.CHARACTER_FORMS.retail, "Name-Realm")
  assertEqual(C.CHARACTER_FORMS.forever, "name and surname")
  assertEqual(C.CHARACTER_FORM, C.CHARACTER_FORMS[T.forever and "forever" or "retail"])
end)

test("Constants: the display order lists no source twice and invents none", function()
  local seen = {}
  for _, s in ipairs(C.SourceOrder) do
    assertFalse(seen[s], s .. " appears twice in SourceOrder")
    assertTrue(C.SourceType[s] ~= nil, s .. " is not a SourceType member")
    seen[s] = true
  end
  assertEqual(#C.SourceOrder, count(C.SourceType) - count(C.SOURCE_ABSENT))
end)

test("Constants: every SourceType member has a non-empty display label", function()
  for k in pairs(C.SourceType) do
    local label = C.SourceLabel[k]
    assertTrue(type(label) == "string" and label ~= "", k .. " has no label")
  end
end)

test("Constants: SourceLabel carries no label for a non-source key", function()
  for k in pairs(C.SourceLabel) do
    assertTrue(C.SourceType[k] ~= nil, k .. " is labeled but is not a source")
  end
end)

test("Constants: the deconstruct abilities are first-class sources, not folded into CRAFT", function()
  -- The Source column must read the ability, so each has its own enum member and its own label.
  for _, s in ipairs({ "DISENCHANT", "MILLING", "PROSPECTING" }) do
    assertEqual(C.SourceType[s], s)
    assertFalse(C.SourceLabel[s] == C.SourceLabel.CRAFT, s .. " must not read as Craft")
  end
end)

test("Constants: every source has a live capture path (SOURCE_IMPLEMENTED is total)", function()
  for k in pairs(C.SourceType) do
    if not C.SOURCE_ABSENT[k] then assertTrue(C.SOURCE_IMPLEMENTED[k], k .. " is not marked implemented") end
  end
end)

test("Constants: SOURCE_IMPLEMENTED claims nothing outside the enum", function()
  for k in pairs(C.SOURCE_IMPLEMENTED) do
    assertTrue(C.SourceType[k] ~= nil, k .. " is implemented but is not a source")
  end
end)

test("Constants: the mute options are the implemented sources, in display order", function()
  local i = 0
  for _, s in ipairs(C.SourceOrder) do
    if C.SOURCE_IMPLEMENTED[s] and not C.LEDGER_REASON[s] then
      i = i + 1
      assertEqual(C.SOURCE_OPTIONS[i].value, s, "mute option " .. i .. " out of order")
      assertEqual(C.SOURCE_OPTIONS[i].text, C.SourceLabel[s])
    end
  end
  assertEqual(#C.SOURCE_OPTIONS, i, "no extra mute options")
end)

-- ── Confidence + capture constants ─────────────────────────────────────────────

test("Constants: the confidence enum is exactly CERTAIN/INFERRED, key == value", function()
  assertEqual(C.Confidence.CERTAIN, "CERTAIN")
  assertEqual(C.Confidence.INFERRED, "INFERRED")
  assertEqual(count(C.Confidence), 2)
end)

test("Constants: the aliases point at the very same enum tables", function()
  assertEqual(NS.SourceType, C.SourceType)
  assertEqual(NS.Confidence, C.Confidence)
end)

test("Constants: the quest item class is the locale-independent numeric id 12", function()
  assertEqual(C.ITEMCLASS_QUEST, 12)
end)

test("Constants: the context TTL is a short positive window", function()
  assertTrue(type(C.CONTEXT_TTL) == "number")
  assertTrue(C.CONTEXT_TTL > 0 and C.CONTEXT_TTL <= 5, "a stale context must expire quickly")
end)

test("Constants: the mono font is the face the library ships, not one of ours", function()
  -- It used to live under this addon's own media/fonts/. It now arrives with the LibKa0s payload,
  -- so the assertion that matters is not a literal path but that FONT_MONO is exactly what the
  -- seam answers for FONT_MONO_NAME: a hand-typed path that drifted from the vendored one would
  -- load nothing and raise nothing.
  assertEqual(C.FONT_MONO, NS.MediaFont(C.FONT_MONO_NAME))
  assertTrue(C.FONT_MONO:sub(-4) == ".ttf")
end)

-- ── Threshold + retention option lists ─────────────────────────────────────────

test("Constants: the quality ladder is Poor..Legendary then Heirloom, skipping 6 and 8", function()
  -- Ratified exception: Heirloom(7) sits above Legendary on purpose. Artifact(6)/Token(8) are out.
  local values = {}
  for i, o in ipairs(C.QUALITY_OPTIONS) do values[i] = o.value end
  assertEqual(#values, 7)
  for i, want in ipairs({ 0, 1, 2, 3, 4, 5, 7 }) do assertEqual(values[i], want) end
end)

test("Constants: every quality option carries a colored '<name> and above' text", function()
  for _, o in ipairs(C.QUALITY_OPTIONS) do
    assertTrue(type(o.value) == "number", "value is the quality id")
    assertTrue(o.text:find("|cff", 1, true) == 1, "the quality name is color-wrapped")
    assertTrue(o.text:find(" and above", 1, true) ~= nil, "the threshold reads 'and above'")
    assertTrue(o.text:find("|r", 1, true) ~= nil, "the color is closed")
  end
end)

test("Constants: the retention presets ascend and end on 'Always' (0 = disabled)", function()
  local last = C.RETENTION_OPTIONS[#C.RETENTION_OPTIONS]
  assertEqual(last.value, 0)
  assertEqual(last.text, "Always")
  for i = 2, #C.RETENTION_OPTIONS - 1 do
    assertTrue(C.RETENTION_OPTIONS[i].value > C.RETENTION_OPTIONS[i - 1].value,
      "day presets ascend")
  end
end)

-- ── Auction-price key catalog ────────────────────────────────────────────────

test("Constants: every auction key is fully described", function()
  for _, k in ipairs(C.AUCTION_KEYS) do
    local tag = k.provider .. ":" .. k.key
    for _, field in ipairs({ "provider", "key", "label", "data", "desc" }) do
      assertTrue(type(k[field]) == "string" and k[field] ~= "", tag .. " lacks " .. field)
    end
  end
end)

test("Constants: auction tags are unique", function()
  local seen = {}
  for _, k in ipairs(C.AUCTION_KEYS) do
    local tag = k.provider .. ":" .. k.key
    assertFalse(seen[tag], tag .. " is listed twice")
    seen[tag] = true
  end
end)

test("Constants: every auction provider has a human-readable name", function()
  for _, k in ipairs(C.AUCTION_KEYS) do
    assertTrue(C.AUCTION_PROVIDER_NAMES[k.provider] ~= nil,
      "no display name for provider " .. k.provider)
  end
end)

test("Constants: the capture options mirror AUCTION_KEYS one-for-one, in order", function()
  assertEqual(#C.AUCTION_CAPTURE_OPTIONS, #C.AUCTION_KEYS)
  for i, k in ipairs(C.AUCTION_KEYS) do
    assertEqual(C.AUCTION_CAPTURE_OPTIONS[i].value, k.provider .. ":" .. k.key)
    assertEqual(C.AUCTION_CAPTURE_OPTIONS[i].text, k.label)
  end
end)

test("Constants: the priority cascade covers every auction key exactly once", function()
  -- A key missing from the cascade could never be picked; a duplicate would shadow itself.
  local seen = {}
  for _, tag in ipairs(C.AUCTION_PRIORITY_DEFAULT) do
    assertFalse(seen[tag], tag .. " appears twice in the priority default")
    seen[tag] = true
  end
  for _, k in ipairs(C.AUCTION_KEYS) do
    local tag = k.provider .. ":" .. k.key
    assertTrue(seen[tag], tag .. " is missing from the priority default")
  end
  assertEqual(#C.AUCTION_PRIORITY_DEFAULT, #C.AUCTION_KEYS)
end)

test("Constants: the default-captured keys all sort ahead of the uncaptured ones", function()
  -- The cascade is curated so a captured price is always reachable before an uncaptured one.
  local sawUncaptured = false
  for _, tag in ipairs(C.AUCTION_PRIORITY_DEFAULT) do
    if C.AUCTION_CAPTURE_DEFAULT[tag] then
      assertFalse(sawUncaptured, tag .. " is captured but ranks below an uncaptured key")
    else
      sawUncaptured = true
    end
  end
end)

test("Constants: every default-captured tag is a real auction key", function()
  local valid = {}
  for _, k in ipairs(C.AUCTION_KEYS) do valid[k.provider .. ":" .. k.key] = true end
  for tag in pairs(C.AUCTION_CAPTURE_DEFAULT) do
    assertTrue(valid[tag], tag .. " is captured by default but is not a known key")
  end
end)

test("Constants: the currency pseudo-type is the reserved 'Currency' string", function()
  assertEqual(C.CURRENCY_TYPE, "Currency")
end)

-- ── The bus message names (architecture-§4) ────────────────────────────────────────────────────
--
-- Characterization, written BEFORE the names moved into NS.MSG: every wire name a real sender puts
-- on the bus, and the payload beside it, driven through the sender itself rather than read off a
-- table. The constants are an implementation of the declare-once rule; these strings are the
-- contract every receiver in another file depends on, so they are pinned as literals here.

--- Every SendMessage the bus sees while `fn` runs, as { msg, a, b }.
local function busSends(fn)
  local sent, orig = {}, NS.bus.SendMessage
  NS.bus.SendMessage = function(_, msg, a, b) sent[#sent + 1] = { msg = msg, a = a, b = b } end
  local ok, err = pcall(fn)
  NS.bus.SendMessage = orig
  if not ok then error(err, 0) end
  return sent
end

test("bus: Database:Add sends RecordAdded with the record and its index", function()
  -- On a scratch history, restored before asserting: later suites count the real one.
  local g = NS.db.global
  local saved = g.history
  g.history = {}
  local rec = { itemID = 424242 }
  local sent = busSends(function() NS.Database:Add(rec) end)
  local stored = NS.Database:Count()
  g.history = saved
  assertEqual(#sent, 1)
  assertEqual(sent[1].msg, "Ka0s_LootHistory_RecordAdded")
  assertTrue(sent[1].a == rec, "the payload is the stored record itself")
  assertEqual(sent[1].b, stored)
end)

test("bus: Database:FireHistoryChanged sends HistoryChanged with no payload", function()
  local sent = busSends(function() NS.Database:FireHistoryChanged() end)
  assertEqual(#sent, 1)
  assertEqual(sent[1].msg, "Ka0s_LootHistory_HistoryChanged")
  assertEqual(sent[1].a, nil)
end)

test("bus: a settings write sends SettingsChanged with its reason", function()
  local S = NS.Schema
  for _, case in ipairs({
    { "settings.qualityThreshold", 4, "quality" },
    { "settings.scale", 1.25, "chrome" },
  }) do
    local path, value, reason = case[1], case[2], case[3]
    local sent = busSends(function() S:Set(path, value) end)
    S:Set(path, S:Default(path))
    assertEqual(#sent, 1, path .. " sends exactly one message")
    assertEqual(sent[1].msg, "Ka0s_LootHistory_SettingsChanged", path)
    assertEqual(sent[1].a, reason, path)
  end
end)

test("bus: Reconciler:Flush sends HoldingsChanged once per holder that moved", function()
  -- On a scratch holdings store, restored before asserting: later suites read the real one.
  local g, m, Rc = NS.db.global, T.mocks, NS.Reconciler
  local saved, savedMoney = g.holdings, m.__money
  g.holdings, m.__money = {}, 4242
  Rc.dirty, Rc.deferred = {}, nil
  local sent = busSends(function() Rc:MarkDirty("money"); Rc:Flush() end)
  g.holdings, m.__money = saved, savedMoney
  assertEqual(#sent, 1)
  assertEqual(sent[1].msg, "Ka0s_LootHistory_HoldingsChanged")
  assertEqual(sent[1].a, NS.Util.PlayerKey())
end)

test("bus: NS.MSG declares exactly the six wire names", function()
  local want = {
    RECORD_ADDED     = "Ka0s_LootHistory_RecordAdded",
    HISTORY_CHANGED  = "Ka0s_LootHistory_HistoryChanged",
    SETTINGS_CHANGED = "Ka0s_LootHistory_SettingsChanged",
    HOLDINGS_CHANGED = "Ka0s_LootHistory_HoldingsChanged",
    GAIN             = "Ka0s_LootHistory_Gain",
    FARM_CHANGED     = "Ka0s_LootHistory_FarmChanged",
  }
  local n = 0
  for k, v in pairs(NS.MSG) do
    n = n + 1
    assertEqual(v, want[k], "NS.MSG." .. tostring(k))
  end
  assertEqual(n, 6, "no seventh key")
end)

test("bus: a farm session's start and finish send Ka0s_LootHistory_FarmChanged with their reason", function()
  -- Through the real sender (modules/Farm.lua's Farm:Changed, reached by Start and FinishVerb), on a
  -- scratch farm store put back before asserting. The session logs nothing, so the finish discards it.
  -- The gain feed is not enabled this early: SetFarm's Recompute would leave it wanting what the
  -- toast feeds want, so its three tables are put back too.
  local g, cf, GF = NS.db.global, T.mocks.DEFAULT_CHAT_FRAME, NS.GainFeed
  local saved, savedAdd = g.farm, cf.AddMessage
  local function copy(t) local o = {}; for k, v in pairs(t) do o[k] = v end; return o end
  local wants, toastWants, on = copy(GF.wants), copy(GF.toastWants), GF.on
  g.farm, cf.AddMessage = {}, function() end
  local sent = busSends(function()
    NS.Farm:Start()
    NS.Farm:FinishVerb()
  end)
  g.farm, cf.AddMessage = saved, savedAdd
  for k, v in pairs(wants) do GF.wants[k] = v end
  for k, v in pairs(toastWants) do GF.toastWants[k] = v end
  GF.on = on
  local farm = {}
  for _, s in ipairs(sent) do
    if s.msg == "Ka0s_LootHistory_FarmChanged" then farm[#farm + 1] = s.a end
  end
  assertEqual(table.concat(farm, ","), "start,finish")
  assertEqual(NS.Farm._live, nil, "the discarded session left nothing registered")
end)

test("bus: GainFeed:Send fires Ka0s_LootHistory_Gain with the scratch payload", function()
  local sent, orig = {}, NS.bus.SendMessage
  NS.bus.SendMessage = function(_, msg, a) sent[#sent + 1] = { msg = msg, a = a } end
  local ok, err = pcall(function()
    local g = NS.GainFeed:Begin("GOLD")
    g.qty = 5
    NS.GainFeed:Send(g)
  end)
  NS.bus.SendMessage = orig
  if not ok then error(err, 0) end
  assertEqual(#sent, 1)
  assertEqual(sent[1].msg, "Ka0s_LootHistory_Gain")
  assertEqual(sent[1].a.kind, "GOLD"); assertEqual(sent[1].a.qty, 5)
end)

test("bus: NS.MSG is the library's strict catalog, so a mistyped key raises", function()
  -- red under: a plain table, where `NS.MSG.RECORD_ADED` reads nil and a sender passes a nil name
  -- to SendMessage, which CallbackHandler drops without a word.
  assertTrue(T.mocks.LibStub("LibKa0s-Bus-1.0", true) ~= nil, "the live load has the major")
  assertTrue(NS.BusLib == T.mocks.LibStub("LibKa0s-Bus-1.0", true), "and core/Constants.lua uses it")
  local ok, err = pcall(function() return NS.MSG.RECORD_ADED end)
  assertFalse(ok, "reading an undeclared key must raise")
  assertTrue(tostring(err):find("RECORD_ADED", 1, true) ~= nil, "and name the key: " .. tostring(err))
end)

test("bus: no addon file but core/Constants.lua types a Ka0s_LootHistory_ literal", function()
  -- architecture-§4: each name is declared once and every call site names the constant. The file
  -- list is the TOC's own, so a file added tomorrow is scanned without being named here.
  local offenders = {}
  for _, path in ipairs(T.addonFiles) do
    if path ~= "core/Constants.lua" then
      local src = T.Loader.readFile(path)
      local n = 0
      for line in src:gmatch("[^\r\n]+") do
        n = n + 1
        if not line:match("^%s*%-%-") and line:find('"Ka0s_LootHistory_', 1, true) then
          offenders[#offenders + 1] = path .. ":" .. n
        end
      end
    end
  end
  assertEqual(#offenders, 0, "literal message names: " .. table.concat(offenders, ", "))
end)

test("bus: the degraded build declares the same names, without the library", function()
  local ns = dofile("tests/degraded_env.lua")()
  assertTrue(ns.BusLib ~= nil and ns.BusLib.Catalog ~= nil, "the stub is in place")
  for k, v in pairs(NS.MSG) do
    assertEqual(ns.MSG[k], v, "degraded NS.MSG." .. k)
  end
end)

local LEDGER_KEYS = { "SELL", "BUY", "REPAIR", "MAIL_SEND", "TRADE_GIVE", "AH_POST_FEE", "AH_SOLD",
  "AH_BUY", "DESTROY", "CONSUME", "CRAFT_REAGENT", "DECONSTRUCT", "GUILD_DEPOSIT", "GUILD_WITHDRAW",
  "TRAINING", "TRAVEL", "TRANSFER", "UNTRACKED",
  -- Phase 7 (2026-10-06): a move between two holders is a loss + gain under the action's reason.
  "WARBAND_DEPOSIT", "WARBAND_WITHDRAW", "ALT_MAIL", "ALT_TRADE", "CURRENCY_TRANSFER" }

-- The ledger keys this client serves, in their order (C.SOURCE_ABSENT left out).
local function served(list)
  local out = {}
  for _, k in ipairs(list) do if not C.SOURCE_ABSENT[k] then out[#out + 1] = k end end
  return out
end

test("Constants: ledger reasons are appended SourceType members with labels", function()
  for _, k in ipairs(LEDGER_KEYS) do
    assertEqual(C.SourceType[k], k)
    assertEqual(C.LEDGER_REASON[k] == true, not C.SOURCE_ABSENT[k], k .. " in LEDGER_REASON")
    assertTrue(type(C.SourceLabel[k]) == "string" and C.SourceLabel[k] ~= "", k .. " has no label")
  end
  local n = 0; for _ in pairs(C.LEDGER_REASON) do n = n + 1 end
  assertEqual(n, #served(LEDGER_KEYS))
end)

test("Constants: existing sources keep their order positions (append-only)", function()
  local legacy = served({ "KILL", "CONTAINER", "MPLUS", "BONUS_ROLL", "ROLL", "QUEST", "TRADE", "MAIL", "AH",
    "VENDOR", "DISENCHANT", "MILLING", "PROSPECTING", "CRAFT", "REFUND", "OTHER" })
  for i, s in ipairs(legacy) do assertEqual(C.SourceOrder[i], s) end
  for i, s in ipairs(served(LEDGER_KEYS)) do assertEqual(C.SourceOrder[#legacy + i], s) end
end)

test("Constants: no ledger reason is offered as a capture mute", function()
  for _, o in ipairs(C.SOURCE_OPTIONS) do assertFalse(C.LEDGER_REASON[o.value], o.value) end
end)

-- The direction colors are the skin's since LH-04 (tests/test_ledgerformat.lua pins them).
test("Constants: direction glyphs and labels", function()
  for _, d in ipairs(C.DirOrder) do
    assertTrue(type(C.DirGlyph[d]) == "string" and #C.DirGlyph[d] >= 3, "glyph is a multibyte char")
    assertTrue(type(C.DirLabel[d]) == "string")
  end
  assertEqual(C.GOLD_TYPE, "Gold")
end)

-- The holdings tooltip (#34): the modifier dropdown's ordered-array shape, and the six container
-- marks, one per C.Container value, each a Game-icons name (D4).
test("Constants: TOOLTIP_MODIFIER_OPTIONS is the ordered value/text array", function()
  local got = {}
  for i, o in ipairs(C.TOOLTIP_MODIFIER_OPTIONS) do
    assertEqual(o.label, nil, "entry " .. i .. " uses `text`, not `label`")
    got[i] = o.value .. "=" .. o.text
  end
  assertEqual(table.concat(got, ","), "none=None,shift=Shift,ctrl=Ctrl,alt=Alt")
end)

test("Constants: TIP_ICONS names one Game-icons mark per container", function()
  assertEqual(count(C.TIP_ICONS), count(C.Container))
  for _, c in pairs(C.Container) do assertTrue(C.TIP_ICONS[c] ~= nil, c .. " has no mark") end
  assertEqual(C.TIP_ICONS.bags, "gi:knapsack"); assertEqual(C.TIP_ICONS.equipped, "gi:chest-armor")
  assertEqual(C.TIP_ICONS.bank, "gi:bank"); assertEqual(C.TIP_ICONS.mail, "gi:envelope")
  assertEqual(C.TIP_ICONS.auctions, "gi:gavel"); assertEqual(C.TIP_ICONS.tabs, "gi:locked-chest")
  assertEqual(C.TIP_ICON_SIZE, 12)
  assertTrue(C.TIP_ICON_FALLBACK:lower():find("^interface\\icons\\") ~= nil, "a Blizzard icon fallback")
end)
