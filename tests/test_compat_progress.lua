-- tests/test_compat_progress.lua — core/CompatProgress.lua's reputation and appearance reads
-- (rep/appearance spec §3.2): FactionSnapshot, ListFactions, AppearanceSource and IsNewLook, on
-- tests/mock_progress.lua's double, installed per case and uninstalled after it. A secret is the
-- kit's secret double (T.secret), with issecretvalue planted on the mock for the case.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local PM = dofile("tests/mock_progress.lua")

local NIL = {}
local function with(t, fields, fn)
  local saved = {}
  for k, v in pairs(fields) do
    saved[k] = { v = rawget(t, k) }
    if v == NIL then rawset(t, k, nil) else rawset(t, k, v) end
  end
  local ok, err = pcall(fn)
  for k, s in pairs(saved) do rawset(t, k, s.v) end
  if not ok then error(err, 0) end
end

-- The double for `fn`, uninstalled after it whatever happened. The standing labels are real
-- globals (Compat reads them by name through _G), planted for the case.
local function withDouble(fn)
  local h = PM.install(M)
  local ok, err = pcall(with, _G, { FACTION_STANDING_LABEL4 = "Neutral", FACTION_STANDING_LABEL5 = "Friendly" },
    function() fn(h) end)
  h.uninstall()
  if not ok then error(err, 0) end
end

local function withSecrets(fn)
  with(M, { issecretvalue = function(v) return T.isSecret(v) end }, fn)
end

local C = function() return NS.Compat end

local function snap(id) return { C().FactionSnapshot(id) } end

-- ── FactionSnapshot ─────────────────────────────────────────────────────────────────────────

test("Compat progress: FactionSnapshot reads a base faction's absolute standing and its label", function()
  withDouble(function(h)
    h.faction(72, { name = "Stormwind", reaction = 5, standing = 3000 })
    local s = snap(72)
    assertEqual(s[1], "Stormwind"); assertEqual(s[2], "base"); assertEqual(s[3], 5); assertEqual(s[4], 3000)
    assertEqual(s[5], nil, "no threshold for a base faction"); assertEqual(s[6], nil, "no paragon")
    assertEqual(s[7], false); assertEqual(s[8], "Friendly")
  end)
end)

test("Compat progress: FactionSnapshot genders the label through GetText where the client has it", function()
  withDouble(function(h)
    h.faction(72, { name = "Stormwind", reaction = 5, standing = 3000 })
    local seen
    with(M, { GetText = function(key, sex) seen = key .. "/" .. tostring(sex); return "Amicale" end,
              UnitSex = function() return 3 end }, function()
      assertEqual(snap(72)[8], "Amicale")
    end)
    assertEqual(seen, "FACTION_STANDING_LABEL5/3")
  end)
end)

test("Compat progress: FactionSnapshot reads renown as level, earned and threshold", function()
  withDouble(function(h)
    h.faction(2590, { kind = "renown", name = "Council of Dornogal", level = 10, earned = 500, threshold = 2500,
      accountWide = true })
    local s = snap(2590)
    assertEqual(s[1], "Council of Dornogal"); assertEqual(s[2], "renown"); assertEqual(s[3], 10)
    assertEqual(s[4], 500); assertEqual(s[5], 2500); assertEqual(s[7], true, "a warband faction")
    assertEqual(s[8], "Renown 10")
  end)
end)

test("Compat progress: FactionSnapshot reads friendship and guild standings", function()
  withDouble(function(h)
    h.faction(2640, { kind = "friendship", name = "Brann Bronzebeard", standing = 4200, friendRank = 3,
      friendText = "Buddy" })
    h.faction(1168, { kind = "guild", name = "Guild", reaction = 4, standing = 700 })
    local f = snap(2640)
    assertEqual(f[2], "friendship"); assertEqual(f[3], 3); assertEqual(f[4], 4200); assertEqual(f[8], "Buddy")
    local g = snap(1168)
    assertEqual(g[2], "guild"); assertEqual(g[3], 4); assertEqual(g[4], 700); assertEqual(g[8], "Neutral")
  end)
end)

test("Compat progress: FactionSnapshot answers paragon's cumulative value and labels it Paragon", function()
  withDouble(function(h)
    h.faction(2590, { kind = "renown", name = "Council of Dornogal", level = 25, earned = 0, threshold = 2500,
      paragon = 12500 })
    local s = snap(2590)
    assertEqual(s[6], 12500); assertEqual(s[8], "Paragon")
  end)
end)

test("Compat progress: FactionSnapshot answers base where the renown and friendship reads are absent", function()
  -- WoW Forever's shape (clients-§3): an API gap inside reputation, never a declaration
  withDouble(function(h)
    h.faction(72, { kind = "renown", name = "Stormwind", reaction = 5, standing = 3000, level = 3 })
    h.R.IsMajorFaction, h.G.GetFriendshipReputation, h.R.GetGuildFactionData = nil, nil, nil
    h.R.IsFactionParagonForCurrentPlayer, h.R.IsAccountWideReputation = nil, nil
    local s = snap(72)
    assertEqual(s[2], "base"); assertEqual(s[4], 3000); assertEqual(s[6], nil); assertEqual(s[7], false)
  end)
end)

test("Compat progress: FactionSnapshot answers all nil for an unknown, secret or unreadable faction", function()
  withDouble(function(h)
    h.faction(72, { name = "Stormwind", reaction = 5, standing = 3000 })
    assertEqual(C().FactionSnapshot(999), nil, "unknown")
    assertEqual(C().FactionSnapshot("72"), nil, "not a number")
    withSecrets(function()
      assertEqual(C().FactionSnapshot(T.secret(72)), nil, "a secret id")
      h.factions[72].standing = T.secret(3000)
      assertEqual(C().FactionSnapshot(72), nil, "a secret standing")
      h.factions[72].standing, h.factions[72].name = 3000, T.secret("Stormwind")
      assertEqual(C().FactionSnapshot(72), nil, "a secret name")
      h.factions[72].name, h.factions[72].paragon = "Stormwind", T.secret(5)
      assertEqual(C().FactionSnapshot(72), nil, "a secret paragon value")
    end)
  end)
end)

-- ── ListFactions ────────────────────────────────────────────────────────────────────────────

test("Compat progress: ListFactions expands collapsed headers and collapses them again, last first", function()
  withDouble(function(h)
    h.faction(72, { name = "Stormwind", reaction = 5, standing = 3000 })
    h.faction(21, { name = "Booty Bay", reaction = 4, standing = 1500 })
    h.faction(2590, { kind = "renown", name = "Council of Dornogal", level = 10, earned = 500, threshold = 2500 })
    h.faction(469, { name = "Alliance", reaction = 6, standing = 9000 })
    h.list = {
      { id = 1, header = true, collapsed = true, depth = 0 },     -- Classic, shut
      { id = 469, header = true, collapsed = true, withRep = true, depth = 1 },  -- Alliance: a header with a bar, shut
      { id = 72, depth = 2 },
      { id = 21, depth = 1 },
      { id = 2, header = true, depth = 0 },                       -- The War Within, open
      { id = 2590, depth = 1 },
    }
    local list = C().ListFactions()
    local ids = {}
    for _, r in ipairs(list) do ids[#ids + 1] = r.id end
    assertEqual(table.concat(ids, ","), "469,72,21,2590", "every faction, headers with no bar skipped")
    assertEqual(list[2].name, "Stormwind"); assertEqual(list[2].repType, "base"); assertEqual(list[2].standing, 3000)
    assertEqual(list[4].repType, "renown"); assertEqual(list[4].threshold, 2500); assertEqual(list[4].label, "Renown 10")
    assertEqual(table.concat(h.calls, " "), "expand:1@1 expand:469@2 collapse:469@2 collapse:1@1",
      "opened forward, shut in reverse")
    assertTrue(h.list[1].collapsed and h.list[2].collapsed, "the player's headers are as they were")
    assertFalse(h.list[5].collapsed == true, "an open header is left open")
  end)
end)

test("Compat progress: ListFactions answers {} without the list API and never expands without ExpandFactionHeader",
function()
  withDouble(function(h)
    h.faction(72, { name = "Stormwind", reaction = 5, standing = 3000 })
    h.list = { { id = 1, header = true, collapsed = true }, { id = 72, depth = 1 } }
    h.R.ExpandFactionHeader = nil
    assertEqual(#C().ListFactions(), 0, "the shut header hides its only faction")
    assertEqual(#h.calls, 0)
    h.R.GetNumFactions = nil
    assertEqual(#C().ListFactions(), 0, "no list API, empty list")
  end)
end)

test("Compat progress: ListFactions shows hidden legacy reputations for the walk and hides them again",
function()
  -- red under: a walk that reads the list as filtered, which leaves every legacy faction unseeded
  -- (its first change each session dropped), or one that leaves the player's filter flipped.
  withDouble(function(h)
    h.faction(72, { name = "Stormwind", reaction = 5, standing = 3000 })
    h.faction(21, { name = "Booty Bay", reaction = 4, standing = 1500 })
    h.list = { { id = 1, header = true, collapsed = true, depth = 0, legacy = true }, { id = 21, depth = 1, legacy = true },
               { id = 2, header = true, depth = 0 }, { id = 72, depth = 1 } }
    h.legacyShown = false
    local ids = {}
    for _, r in ipairs(C().ListFactions()) do ids[#ids + 1] = r.id end
    assertEqual(table.concat(ids, ","), "21,72", "the legacy faction is walked")
    assertEqual(table.concat(h.calls, " "), "legacy:true expand:1@1 collapse:1@1 legacy:false",
      "shown first, hidden again after the headers are shut")
    assertFalse(h.legacyShown, "the player's filter is as it was")
    h.calls = {}
    h.legacyShown = true
    C().ListFactions()
    assertEqual(table.concat(h.calls, " "), "expand:1@1 collapse:1@1", "a shown filter is left alone")
    h.R.SetLegacyReputationsShown, h.legacyShown, h.calls = nil, false, {}
    assertEqual(#C().ListFactions(), 1, "without the setter the filtered list is walked as it is")
  end)
end)

-- ── AppearanceSource / IsNewLook ────────────────────────────────────────────────────────────

test("Compat progress: AppearanceSource reads the source's item, link, name, quality, visual and subtype", function()
  withDouble(function(h)
    local link = "|cff1eff00|Hitem:2589::::::::|h[Linen Cloth]|h|r"
    h.source(77, { itemID = 2589, name = "Linen Cloth", quality = 2, visualID = 9, link = link })
    with(M.C_Item, { GetItemInfoInstant = function() return 2589, "Armor", "Cloth" end }, function()
      local itemID, l, name, q, visual, sub = C().AppearanceSource(77)
      assertEqual(itemID, 2589); assertEqual(l, link); assertEqual(name, "Linen Cloth")
      assertEqual(q, 2); assertEqual(visual, 9); assertEqual(sub, "Cloth")
      h.positional = true
      assertEqual(select(2, C().AppearanceSource(77)), link, "the older positional shape: the link is sixth")
      h.sources[77].link = ""
      assertEqual(select(2, C().AppearanceSource(77)), nil, "an empty link reads as nil")
    end)
    assertEqual(C().AppearanceSource(78), nil, "an unknown source")
    h.TC.GetSourceInfo = nil
    assertEqual(C().AppearanceSource(77), nil, "no API")
  end)
end)

test("Compat progress: AppearanceSource guards a secret name or link", function()
  withDouble(function(h)
    h.source(77, { itemID = 2589, name = "Linen Cloth", quality = 2, visualID = 9, link = "x" })
    withSecrets(function()
      h.sources[77].name, h.sources[77].link = T.secret("Linen Cloth"), T.secret("x")
      local itemID, l, name = C().AppearanceSource(77)
      assertEqual(itemID, 2589); assertEqual(l, nil); assertEqual(name, nil)
      assertEqual(C().AppearanceSource(T.secret(77)), nil, "a secret source id")
    end)
  end)
end)

test("Compat progress: IsNewLook is true only when no other source of the visual is collected", function()
  withDouble(function(h)
    h.source(77, { visualID = 9, collected = true })
    h.source(78, { visualID = 9, collected = false })
    h.source(80, { visualID = 10, collected = true })
    assertTrue(C().IsNewLook(9, 77), "the other source of 9 is not collected")
    h.sources[78].collected = true
    assertFalse(C().IsNewLook(9, 77), "another source of 9 is known")
    h.TC.PlayerKnowsSource = nil
    assertFalse(C().IsNewLook(9, 77), "GetSourceInfo's isCollected answers without PlayerKnowsSource")
    h.sources[78].collected = false
    assertTrue(C().IsNewLook(9, 77))
    h.TC.GetAllAppearanceSources = nil
    assertFalse(C().IsNewLook(9, 77), "a missing API answers false")
  end)
end)
