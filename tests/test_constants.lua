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

test("Constants: every SourceType member appears in the display order", function()
  local inOrder = {}
  for _, s in ipairs(C.SourceOrder) do inOrder[s] = true end
  for k in pairs(C.SourceType) do
    assertTrue(inOrder[k], k .. " is missing from SourceOrder")
  end
end)

test("Constants: the display order lists no source twice and invents none", function()
  local seen = {}
  for _, s in ipairs(C.SourceOrder) do
    assertFalse(seen[s], s .. " appears twice in SourceOrder")
    assertTrue(C.SourceType[s] ~= nil, s .. " is not a SourceType member")
    seen[s] = true
  end
  assertEqual(#C.SourceOrder, count(C.SourceType))
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
    assertTrue(C.SOURCE_IMPLEMENTED[k], k .. " is not marked implemented")
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
    if C.SOURCE_IMPLEMENTED[s] then
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

test("bus: NS.MSG declares exactly the three wire names", function()
  local want = {
    RECORD_ADDED     = "Ka0s_LootHistory_RecordAdded",
    HISTORY_CHANGED  = "Ka0s_LootHistory_HistoryChanged",
    SETTINGS_CHANGED = "Ka0s_LootHistory_SettingsChanged",
  }
  local n = 0
  for k, v in pairs(NS.MSG) do
    n = n + 1
    assertEqual(v, want[k], "NS.MSG." .. tostring(k))
  end
  assertEqual(n, 3, "no fourth key")
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
