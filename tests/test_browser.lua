local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local B = NS.Browser

-- A small, deliberately messy dataset: unsorted labels, a blank type, two characters on the same
-- realm, a missing zone name and a repeated map — enough to pin ordering, de-duplication and the
-- "skip the empties" rules of every option builder.
local FIXTURE = {
  { ts = 1000, char = "Ka0z-Realm",  classFile = "MAGE",    source = "VENDOR",
    itemType = "Armor",  itemSubType = "Cloth", quality = 2, bound = "BOP",
    mapID = 2, zone = "Valdrakken", itemName = "Robe" },
  { ts = 2000, char = "Alt-Realm",   classFile = "WARRIOR", source = "KILL",
    itemType = "Weapon", itemSubType = "Axes",  quality = 4, bound = "BOE",
    mapID = 1, zone = "Amirdrassil", itemName = "Axe" },
  { ts = 3000, char = "Ka0z-Realm",  classFile = "MAGE",    source = "KILL",
    itemType = "",       itemSubType = "",      quality = 0, bound = nil,
    mapID = 7, zone = "Amirdrassil", itemName = "Rag" },   -- same zone name, a second floor's map id
  { ts = 4000, char = "Nomad-Other", classFile = nil,       source = "AH",
    itemType = "Consumable", itemSubType = "Potion", quality = 1, bound = "WARBAND",
    mapID = 3, zone = nil, itemName = "Flask" },
}

-- Every option builder and the view helpers read the live dataset / db, so each case runs inside
-- a park-and-restore. Test order must never matter.
local function withFixture(records, fn)
  local savedTest, savedView = NS.State.testRecords, NS.db.global.savedView
  local savedFilter, savedDd = B.activeFilter, B._dd
  NS.State.testRecords = records
  local ok, err = pcall(fn)
  NS.State.testRecords, NS.db.global.savedView = savedTest, savedView
  B.activeFilter, B._dd = savedFilter, savedDd
  if not ok then error(err, 0) end
end

local function valuesOf(opts)
  local out = {}
  for i, o in ipairs(opts) do out[i] = o.value end
  return out
end

local function labelsOf(opts)
  local out = {}
  for i, o in ipairs(opts) do out[i] = o.label end
  return out
end

-- ── Toolbar geometry ───────────────────────────────────────────────────────────

test("Browser.MinWidth is wide enough for both the columns and the toolbar", function()
  -- The window floor is the wider of the two constraints; neither may be clipped.
  local minW = B:MinWidth()
  assertTrue(minW >= NS.BrowserTable:MinFrameWidth(), "the columns must fit")
  assertTrue(minW >= 1116, "the two dropdown rows + a minimum Export must fit")
end)

test("Browser.ExportWidth exactly consumes the bar remainder at minimum width", function()
  -- Export fills from the Character dropdown's right edge to the bar's right edge at min width.
  -- 976 = the dropdown span, +8 gap, 12 = the pane margins.
  assertEqual(B:ExportWidth(), math.max(120, (B:MinWidth() - 12) - (976 + 8)))
end)

test("Browser.ExportWidth never falls below its floor", function()
  assertTrue(B:ExportWidth() >= 120, "Export stays clickable at any window size")
end)

-- ── setToFilter: dropdown selection → query filter ─────────────────────────────

test("Browser.setToFilter turns a selection set into a filter value", function()
  local f = B._setToFilter({ KILL = true, AH = true })
  assertEqual(f.KILL, true)
  assertEqual(f.AH, true)
end)

test("Browser.setToFilter maps an empty selection to nil (no filter at all)", function()
  -- nil, not {} — QueryList treats an empty table as "match nothing selected" would be wrong.
  assertEqual(B._setToFilter({}), nil)
  assertEqual(B._setToFilter(nil), nil)
  assertEqual(B._setToFilter("all"), nil)
end)

test("Browser.setToFilter copies rather than aliases the live selection", function()
  local live = { KILL = true }
  local f = B._setToFilter(live)
  live.AH = true   -- a later dropdown toggle must not reach the applied filter
  assertEqual(f.AH, nil)
  assertEqual(f.KILL, true)
end)

-- ── asSet: stored view field → selection set ───────────────────────────────────

test("Browser.asSet passes a stored set through, dropping the false entries", function()
  local s = B._asSet({ KILL = true, AH = false })
  assertEqual(s.KILL, true)
  assertEqual(s.AH, nil, "an unselected entry is absent, not false")
end)

test("Browser.asSet promotes the legacy scalar form to a one-entry set", function()
  -- Pre-multi-select saved views stored a single value; they must still load.
  assertEqual(B._asSet("KILL").KILL, true)
  assertEqual(B._asSet(4)[4], true)
end)

test("Browser.asSet maps the 'all' sentinel and nil to an empty set", function()
  assertEqual(next(B._asSet("all")), nil)
  assertEqual(next(B._asSet(nil)), nil)
end)

test("Browser.asSet round-trips through setToFilter for the stock (unfiltered) view", function()
  assertEqual(B._setToFilter(B._asSet("all")), nil, "stock 'all' must apply no filter")
end)

-- ── withAll: option-list assembly ──────────────────────────────────────────────

test("Browser.withAll sorts by label and keeps the All sentinel first", function()
  local opts = B._withAll("Source: All", {
    { value = "z", label = "Zebra" }, { value = "a", label = "Apple" },
  })
  assertEqual(opts[1].value, "all")
  assertEqual(opts[1].label, "Source: All")
  assertEqual(opts[2].label, "Apple")
  assertEqual(opts[3].label, "Zebra")
end)

test("Browser.withAll on an empty dataset still offers the All sentinel", function()
  local opts = B._withAll("Zone: All", {})
  assertEqual(#opts, 1)
  assertEqual(opts[1].value, "all")
end)

-- ── Data-driven option builders ────────────────────────────────────────────────

test("Browser: source options are the distinct sources, human-labeled, All first", function()
  withFixture(FIXTURE, function()
    local opts = B._options.source()
    assertEqual(opts[1].value, "all")
    -- Sorted by LABEL, so "Auction House" precedes "Kill" precedes "Vendor".
    assertEqual(labelsOf(opts)[2], "Auction House")
    assertEqual(labelsOf(opts)[3], "Kill")
    assertEqual(labelsOf(opts)[4], "Vendor")
    assertEqual(#opts, 4, "KILL appears twice in the data but only once in the menu")
  end)
end)

test("Browser: type options skip the blank itemType", function()
  withFixture(FIXTURE, function()
    local opts = B._options.itemType()
    for _, o in ipairs(opts) do
      assertTrue(o.value ~= "", "an empty type would be an unselectable menu row")
    end
    assertEqual(#opts, 4)   -- All + Armor/Weapon/Consumable
  end)
end)

test("Browser: subtype options skip the blank itemSubType", function()
  withFixture(FIXTURE, function()
    local opts = B._options.itemSubType()
    assertEqual(#opts, 4)   -- All + Cloth/Axes/Potion
    for _, o in ipairs(opts) do assertTrue(o.value ~= "") end
  end)
end)

test("Browser: zone options are keyed by name, so one zone lists once per name", function()
  withFixture(FIXTURE, function()
    local opts = B._options.zone()
    -- Amirdrassil is recorded under two map ids (a dungeon's floors each carry their own UiMapID);
    -- keying by name is what stops it listing twice. All + Amirdrassil + Valdrakken + Unknown.
    assertEqual(#opts, 4)
    local byValue = {}
    for _, o in ipairs(opts) do byValue[o.value] = o.label end
    -- The query filters on the zone NAME, so the value must be the name, not a map id.
    assertEqual(byValue["Amirdrassil"], "Amirdrassil")
    assertEqual(byValue["Valdrakken"], "Valdrakken")
  end)
end)

test("Browser: zones with no recorded name share one 'Unknown' bucket", function()
  withFixture(FIXTURE, function()
    local byValue = {}
    for _, o in ipairs(B._options.zone()) do byValue[o.value] = o.label end
    assertEqual(byValue[""], "Unknown")
  end)
end)

test("Browser: quality options run in quality order, not label order", function()
  withFixture(FIXTURE, function()
    local vals = valuesOf(B._options.quality())
    assertEqual(vals[1], "all")
    -- Poor(0) → Common(1) → Uncommon(2) → Epic(4); alphabetical would scramble these.
    assertEqual(vals[2], 0); assertEqual(vals[3], 1)
    assertEqual(vals[4], 2); assertEqual(vals[5], 4)
    assertEqual(#vals, 5, "Rare(3) is absent from the data, so absent from the menu")
  end)
end)

test("Browser: quality options carry the quality tint", function()
  withFixture(FIXTURE, function()
    local opts = B._options.quality()
    assertTrue(opts[2].color ~= nil, "each real quality is color-tinted")
    assertEqual(opts[1].color, nil, "the All sentinel is not tinted")
  end)
end)

test("Browser: bound options follow the fixed binding order, not data order", function()
  withFixture(FIXTURE, function()
    local vals = valuesOf(B._options.bound())
    -- Data order is BOP, BOE, NONE, WARBAND; the menu must read the logical ladder.
    assertEqual(vals[1], "all")
    assertEqual(vals[2], "NONE"); assertEqual(vals[3], "BOE")
    assertEqual(vals[4], "BOP");  assertEqual(vals[5], "WARBAND")
    assertEqual(#vals, 5, "WARBAND_UE is absent from the data, so absent from the menu")
  end)
end)

test("Browser: an unbound record surfaces as the NONE sentinel", function()
  withFixture({ { ts = 1, char = "A-R", source = "KILL", bound = nil } }, function()
    local opts = B._options.bound()
    assertEqual(opts[2].value, "NONE")
    assertEqual(opts[2].label, "Not Bound")
  end)
end)

test("Browser: character options list each looter once, All then Current first", function()
  withFixture(FIXTURE, function()
    local vals = valuesOf(B._options.char())
    assertEqual(vals[1], "all")
    assertEqual(vals[2], "current", "the Current preset sits directly under All")
    assertEqual(#vals, 5, "Ka0z is looted twice but lists once")
  end)
end)

test("Browser: character options carry the class color, and the icon folded into the label",
  function()
    -- LibKa0s-Widgets-1.0 has no `icon` field on an option -- deliberately, because it MEASURES
    -- inline markup in a label. So the class icon is prefixed onto the label string and the
    -- unclassed character's label is the bare name.
    withFixture(FIXTURE, function()
      local byValue = {}
      for _, o in ipairs(B._options.char()) do byValue[o.value] = o end
      assertTrue(byValue["Ka0z-Realm"].color ~= nil, "a known class is color-tinted")
      assertEqual(byValue["Ka0z-Realm"].icon, nil, "no option may carry an `icon` field")
      assertTrue(byValue["Ka0z-Realm"].label:find("Ka0z%-Realm$") ~= nil,
        "the name ends the label, behind its markup: " .. byValue["Ka0z-Realm"].label)
      assertTrue(#byValue["Ka0z-Realm"].label > #"Ka0z-Realm",
        "a known class prefixes inline icon markup onto the label")
      assertEqual(byValue["Nomad-Other"].color, nil, "an unknown class stays untinted")
      assertEqual(byValue["Nomad-Other"].label, "Nomad-Other", "and its label is the bare name")
    end)
  end)

test("Browser: the Current preset lights up only for exactly the logged-in character", function()
  withFixture(FIXTURE, function()
    local preset
    for _, o in ipairs(B._options.char()) do if o.value == "current" then preset = o end end
    local me = NS.Util.PlayerKey()
    assertTrue(preset.isActive({ _selected = { [me] = true } }), "exactly {me} is the preset")
    assertFalse(preset.isActive({ _selected = { [me] = true, ["Alt-Realm"] = true } }),
      "me plus someone else is not the preset")
    assertFalse(preset.isActive({ _selected = { ["Alt-Realm"] = true } }))
    assertFalse(preset.isActive({ _selected = {} }))
  end)
end)

-- ── Saved view ─────────────────────────────────────────────────────────────────

test("Browser: the stock view filters nothing and sorts newest-first", function()
  local v = B._stockView
  assertEqual(v.groupBy, "none")
  assertEqual(v.sortKey, "date")
  assertFalse(v.sortAsc, "the default table reads newest loot first")
  for _, k in ipairs({ "quality", "source", "itemType", "itemSubType", "zone", "bound", "date" }) do
    assertEqual(v[k], "all", k .. " must start unfiltered")
  end
  assertEqual(v.search, "")
end)

test("Browser: with no saved view, Clear falls back to the stock view", function()
  withFixture(FIXTURE, function()
    NS.db.global.savedView = nil
    assertEqual(B._savedViewOrStock(), B._stockView)
  end)
end)

test("Browser: a saved view wins over stock", function()
  withFixture(FIXTURE, function()
    NS.db.global.savedView = { groupBy = "zone", sortKey = "ilvl" }
    assertEqual(B._savedViewOrStock().groupBy, "zone")
  end)
end)

test("Browser: a corrupt (non-table) saved view degrades to stock rather than erroring", function()
  withFixture(FIXTURE, function()
    NS.db.global.savedView = "garbage"
    assertEqual(B._savedViewOrStock(), B._stockView)
  end)
end)

-- ── Applying and capturing a view ──────────────────────────────────────────────

test("Browser.ApplyView pushes the view's group and sort onto the table", function()
  withFixture(FIXTURE, function()
    B._dd = nil   -- headless: no dropdown widgets, the filter path must still resolve
    B:ApplyView({ groupBy = "zone", sortKey = "ilvl", sortAsc = true, date = "all" }, "all")
    assertEqual(NS.BrowserTable.groupBy, "zone")
    assertEqual(NS.BrowserTable.sortKey, "ilvl")
    assertTrue(NS.BrowserTable.sortAsc)
    B:ApplyView(B._stockView, "all")   -- restore the shared table state
  end)
end)

test("Browser.ApplyView resolves each stored set into the active filter", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    B:ApplyView({ source = { KILL = true }, quality = { [4] = true }, date = "all" }, "all")
    local f = B:CurrentFilter()
    assertEqual(f.source.KILL, true)
    assertEqual(f.quality[4], true)
    assertEqual(f.itemType, nil, "an unset field applies no filter")
    B:ApplyView(B._stockView, "all")
  end)
end)

test("Browser.ApplyView turns a date range into an absolute lower bound", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    B:ApplyView({ date = "7d" }, "all")
    local f = B:CurrentFilter()
    assertTrue(type(f.from) == "number", "the range key is resolved to a timestamp")
    assertTrue(f.from <= os.time(), "the lower bound is in the past")
    B:ApplyView(B._stockView, "all")
    assertEqual(B:CurrentFilter().from, nil, "'all' clears the bound")
  end)
end)

test("Browser.ApplyView carries the search text into the filter", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    B:ApplyView({ date = "all", search = "axe" }, "all")
    assertEqual(B:CurrentFilter().text, "axe")
    B:ApplyView(B._stockView, "all")
    assertEqual(B:CurrentFilter().text, nil)
  end)
end)

test("Browser.ApplyView scopes to the current player by default, not to everyone", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    B:ApplyView(B._stockView)   -- no scope argument = the per-session default
    assertEqual(B:CurrentFilter().char[NS.Util.PlayerKey()], true)
    B:ApplyView(B._stockView, "all")
    assertEqual(B:CurrentFilter().char, nil, "'all' scope applies no character filter")
  end)
end)

test("Browser.ApplyView discards whatever the previous view filtered", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    B:ApplyView({ source = { KILL = true }, date = "all" }, "all")
    B:ApplyView({ quality = { [4] = true }, date = "all" }, "all")
    assertEqual(B:CurrentFilter().source, nil, "the old source filter must not linger")
    assertEqual(B:CurrentFilter().quality[4], true)
    B:ApplyView(B._stockView, "all")
  end)
end)

test("Browser.SetCharSet drives the char filter, and an empty set clears it", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    B:SetCharSet({ ["Alt-Realm"] = true })
    assertEqual(B:CurrentFilter().char["Alt-Realm"], true)
    B:SetCharSet({})
    assertEqual(B:CurrentFilter().char, nil, "no selection = every character")
  end)
end)

test("Browser.CurrentFilter hands out a copy, not the live filter", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    B:ApplyView({ source = { KILL = true }, date = "all" }, "all")
    local f = B:CurrentFilter()
    f.source = nil
    assertTrue(B:CurrentFilter().source ~= nil, "mutating the copy must not disarm the filter")
    B:ApplyView(B._stockView, "all")
  end)
end)

test("Browser.CaptureView records the table's group and sort state", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    B:ApplyView({ groupBy = "source", sortKey = "qty", sortAsc = true, date = "all" }, "all")
    local v = B:CaptureView()
    assertEqual(v.groupBy, "source")
    assertEqual(v.sortKey, "qty")
    assertTrue(v.sortAsc)
    B:ApplyView(B._stockView, "all")
  end)
end)

test("Browser.CaptureView stores unset column filters as empty sets, never nil", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    local v = B:CaptureView()
    for _, k in ipairs({ "quality", "source", "itemType", "itemSubType", "zone", "bound" }) do
      assertEqual(type(v[k]), "table", k .. " is a set even when nothing is selected")
      assertEqual(next(v[k]), nil)
    end
  end)
end)

test("Browser.CaptureView omits the character scope (it is session-only)", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    B:SetCharSet({ ["Alt-Realm"] = true })
    assertEqual(B:CaptureView().char, nil, "a saved view must not pin a character")
    B:ApplyView(B._stockView, "all")
  end)
end)

test("Browser.SaveView then ResetView clears the stored default", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    B:ApplyView({ groupBy = "zone", date = "all" }, "all")
    B:SaveView()
    assertEqual(NS.db.global.savedView.groupBy, "zone")
    B:ResetView(true)
    assertEqual(NS.db.global.savedView, nil, "reset drops back to stock")
    assertEqual(NS.BrowserTable.groupBy, "none")
  end)
end)

-- ── Menu row highlight ─────────────────────────────────────────────────────────
-- WHICH ROW LIGHTS UP GOLD is no longer this file's decision: the popup, its pooled rows and the
-- highlight rule all belong to LibKa0s-Widgets-1.0 now, so `B._optionSelected` is gone along with
-- the widget it served. The rule is pinned where it can be pinned honestly — against a REAL row
-- the library painted — in tests/test_widgets.lua.

-- ── Multi-select collapsed label ───────────────────────────────────────────────
-- UpdateMultiLabel is a per-dropdown method built by the shared factory, so the only way to reach
-- it is to build a real dropdown. `dd.text` is the collapsed button's own FontString and the mock
-- models it as a distinct object with a readable text, which is the one seam onto that label.
--
-- REACHED ONLY THROUGH THE PUBLISHED SURFACE. The option list and the selection go in through
-- SetOptions/SetSelected rather than by writing `_options` and `_selected` directly: `_selected` is
-- documented as host-readable but is the library's to write, and `_options` is not on the
-- host-writable list at all. Both setters refresh the label themselves, so UpdateMultiLabel is
-- called explicitly here only to keep this helper honest about what it is pinning.
local function labelFor(opts, selected)
  local dd = NS.MakeDropdown(nil, 100)
  dd:SetMulti(true)
  dd:SetOptions(opts)
  dd:SetSelected(selected)
  dd:UpdateMultiLabel()
  return dd.text:GetText()
end

local QUALITY_OPTS = {
  { value = "all", label = "Quality: All" },
  { value = 2, label = "Uncommon" },
  { value = 4, label = "Epic" },
}

test("Browser: an empty multi-select reads as the All sentinel's own label", function()
  assertEqual(labelFor(QUALITY_OPTS, {}), "Quality: All")
end)

test("Browser: a dropdown with no options at all still labels itself All", function()
  assertEqual(labelFor(nil, {}), "All")
end)

test("Browser: one selected value reads as that option's label", function()
  assertEqual(labelFor(QUALITY_OPTS, { [4] = true }), "Epic")
end)

test("Browser: a selected value with no option row falls back to its raw value", function()
  -- Data-driven option lists only offer what the dataset contains, so a saved selection can
  -- outlive its row. It must still read sensibly and still count.
  assertEqual(labelFor(QUALITY_OPTS, { [7] = true }), "7")
end)

test("Browser: several selected values collapse to '<Prefix>: N selected'", function()
  -- The prefix is the part of the All label before its colon.
  assertEqual(labelFor(QUALITY_OPTS, { [2] = true, [4] = true }), "Quality: 2 selected")
end)

test("Browser: a colon-less All label is used whole as the count prefix", function()
  local opts = { { value = "all", label = "All" }, { value = "a", label = "A" } }
  assertEqual(labelFor(opts, { a = true, b = true }), "All: 2 selected")
end)

test("Browser: an off-list selection still counts toward the summary", function()
  assertEqual(labelFor(QUALITY_OPTS, { [2] = true, [9] = true }), "Quality: 2 selected")
end)

test("Browser: an active preset option names the whole selection, beating the count", function()
  -- Checked first and short-circuiting: the Character dropdown's "Current" preset must hold its
  -- label even when the selected character has no row in the current option list.
  local opts = {
    { value = "all", label = "Character: All" },
    { value = "current", label = "Character: Current", isActive = function() return true end },
  }
  assertEqual(labelFor(opts, { ["Ka0z-Realm"] = true, ["Alt-Realm"] = true }), "Character: Current")
end)

test("Browser: a preset that reports itself inactive does not name the selection", function()
  local opts = {
    { value = "all", label = "Character: All" },
    { value = "current", label = "Character: Current", isActive = function() return false end },
  }
  assertEqual(labelFor(opts, {}), "Character: All")
end)

test("Browser.ResetWindow empties the persisted geometry carve-out", function()
  local saved = NS.db.global.settings.window
  NS.db.global.settings.window = { x = 100, y = 200, width = 1400 }
  B:ResetWindow()
  assertEqual(next(NS.db.global.settings.window), nil)
  NS.db.global.settings.window = saved
end)

-- ── the RecordAdded repaint is coalesced (issue #27) ────────────────────────────────────────
--
-- The helper is unit-tested in test_util.lua; this is the assertion that the FAN-OUT actually
-- collapses, which is the thing that was wrong. `OnHistoryChanged` is a BrowserTable rebuild,
-- seven dropdown builders each scanning the whole dataset, and a StorageStats byte estimate —
-- and `Database:Add` fires RecordAdded once per looted item, mid-pull.

test("browser: a burst of RecordAdded collapses to ONE OnHistoryChanged", function()
  assertTrue(NS.bus ~= nil, "the bus exists, so Enable's subscription really was reached")
  B:Enable()

  local ran, real = 0, B.OnHistoryChanged
  B.OnHistoryChanged = function() ran = ran + 1 end

  for _ = 1, 12 do NS.bus:SendMessage("Ka0s_LootHistory_RecordAdded", {}, 1) end
  assertEqual(ran, 0, "nothing repaints synchronously on the loot path")
  T.mocks.__fireTimers()
  assertEqual(ran, 1, "twelve drops cost one repaint — this was twelve before the fix")

  B.OnHistoryChanged = real
end)

test("browser: HistoryChanged still repaints immediately", function()
  -- The other half of the fix, and the one a careless coalescer would have broken: a delete, a
  -- prune or a blacklist edit is one deliberate user action and must not wait on a timer.
  B:Enable()

  local ran, real = 0, B.OnHistoryChanged
  B.OnHistoryChanged = function() ran = ran + 1 end

  NS.bus:SendMessage("Ka0s_LootHistory_HistoryChanged")
  assertEqual(ran, 1, "a deliberate change repaints at once, with no timer in the way")

  B.OnHistoryChanged = real
end)

-- ── Master controls: the addon-wide chrome (options-ui-§15) ───────────────────
--
-- Four settings arrived on the Master controls tab that this addon had never had: General
-- visibility, Master scale, Master alpha and Lock frame. A setting that is DECLARED and not
-- HONOURED is worse than one that is absent, so each is pinned against the code that reads it
-- rather than against the schema that declares it.

local function withSettings(patch, fn)
  local s = NS.db.global.settings
  local saved = {}
  for k, v in pairs(patch) do saved[k] = s[k]; s[k] = v end
  local ok, err = pcall(fn)
  for k in pairs(patch) do s[k] = saved[k] end
  if not ok then error(err) end
end

--- A frame that records what was scaled and faded onto it. The kit's stub answers the frame itself
--- for any capitalized call, so the setters have to be rawset — and rawset back to nil after, or
--- the recorder outlives the case.
local function recordingFrame()
  local f = T.mocks.CreateFrame("Frame")
  rawset(f, "SetScale", function(_, v) f.__scale = v end)
  rawset(f, "SetAlpha", function(_, v) f.__alpha = v end)
  return f
end

test("browser: master scale MULTIPLIES the per-window scale, it does not replace it", function()
  -- options-ui-§15: where an addon's frames are per-instance, the master rows are the addon-wide
  -- ones and the per-instance scale stays on the instance — "the two are different settings and
  -- MUST NOT be conflated". `settings.windowScale` is the History window's own; `settings.scale`
  -- is every frame's.
  -- red under: writing `f:SetScale(windowScale)` or `f:SetScale(master)` alone — either one drops
  -- a setting the panel still shows.
  withSettings({ scale = 2.0, alpha = 0.5 }, function()
    local f = recordingFrame()
    B:ApplyChrome(f, 1.25)
    T.assertNear(f.__scale, 2.5, 1e-9, "2.0 master x 1.25 window")
    T.assertNear(f.__alpha, 0.5, 1e-9)

    -- A frame with no per-window scale of its own (the export modal) takes the master alone.
    local g = recordingFrame()
    B:ApplyChrome(g, nil)
    T.assertNear(g.__scale, 2.0, 1e-9)
  end)
end)

test("browser: an absent master scale/alpha falls back to the shipped 1.0, never to nil", function()
  -- SetScale(nil) raises in the client. The read has to answer a number for a profile written
  -- before these keys existed.
  withSettings({ scale = nil, alpha = nil, locked = nil }, function()
    local scale, alpha, locked = B:MasterChrome()
    assertEqual(scale, 1.0); assertEqual(alpha, 1.0); assertEqual(locked, false)
  end)
end)

test("browser: Lock frame is what the drag handler asks, and it is addon-wide", function()
  -- red under: gating on anything else, or forgetting the export modal — modules/Export.lua asks
  -- NS.Browser:IsLocked() for its own title bar, so ONE setting locks both frames.
  withSettings({ locked = true }, function() assertTrue(B:IsLocked()) end)
  withSettings({ locked = false }, function() assertFalse(B:IsLocked()) end)
end)

test("browser: General visibility answers all four modes against the combat state", function()
  -- red under: treating the row as a boolean (which is exactly what options-ui-§15 forbids: a
  -- boolean can only ever answer two of the four).
  local realCombat = T.mocks.InCombatLockdown
  local function combat(v) T.mocks.InCombatLockdown = function() return v end end

  combat(false)
  withSettings({ visibility = "always" },      function() assertTrue(B:VisibilityAllows()) end)
  withSettings({ visibility = "never" },       function() assertFalse(B:VisibilityAllows()) end)
  withSettings({ visibility = "inCombat" },    function() assertFalse(B:VisibilityAllows()) end)
  withSettings({ visibility = "outOfCombat" }, function() assertTrue(B:VisibilityAllows()) end)

  combat(true)
  withSettings({ visibility = "always" },      function() assertTrue(B:VisibilityAllows()) end)
  withSettings({ visibility = "never" },       function() assertFalse(B:VisibilityAllows()) end)
  withSettings({ visibility = "inCombat" },    function() assertTrue(B:VisibilityAllows()) end)
  withSettings({ visibility = "outOfCombat" }, function() assertFalse(B:VisibilityAllows()) end)

  T.mocks.InCombatLockdown = realCombat
  -- An unset value is "always", so a profile from before the row existed still opens its window.
  withSettings({ visibility = nil }, function() assertTrue(B:VisibilityAllows()) end)
end)

test("browser: Show refuses while the visibility setting forbids it, and says why", function()
  -- The window is opened on demand, so honouring the setting means REFUSING — and a silent refusal
  -- reads as a broken slash command.
  -- red under: dropping the guard from B:Show, or from B:Toggle (which routes through it).
  local lines = {}
  local cf = T.mocks.DEFAULT_CHAT_FRAME
  local oldAdd = cf.AddMessage
  cf.AddMessage = function(_, msg) lines[#lines + 1] = msg end
  withSettings({ visibility = "never" }, function()
    B:Show()
    B:Toggle()
  end)
  cf.AddMessage = oldAdd
  assertEqual(#lines, 2, "both entry points refuse")
  assertTrue(lines[1]:find("visibility", 1, true) ~= nil,
    "the refusal must name the setting: " .. tostring(lines[1]))
  assertTrue(B:GetWindow() == nil, "a refused open must not build the window either")
end)

test("browser: a combat transition re-applies visibility through the private event target",
  function()
    -- The two events are registered on B.__ev (never the shared bus-as-self), and ApplyVisibility
    -- only ever HIDES: "Only in combat" is a permission, not an instruction to pop a browser over
    -- a pull.
    -- red under: registering them on NS.bus (they would clobber nothing, but the mock's fan-out
    -- below reaches only the private targets, so the case goes red), or dropping the registration.
    B:Enable()
    local ran, real = 0, B.ApplyVisibility
    B.ApplyVisibility = function() ran = ran + 1 end
    assertTrue(T.mocks.__fireAceEvent("PLAYER_REGEN_DISABLED") >= 1, "nothing registered the event")
    T.mocks.__fireAceEvent("PLAYER_REGEN_ENABLED")
    B.ApplyVisibility = real
    assertEqual(ran, 2, "both transitions re-apply the setting")
  end)
