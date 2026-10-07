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
  local savedTest, savedViews = NS.State.testRecords, NS.Util.DeepCopy(NS.db.profile.savedViews)
  local savedFilter, savedDd = B.activeFilter, B._dd
  NS.State.testRecords = records
  local ok, err = pcall(fn)
  NS.State.testRecords, NS.db.profile.savedViews = savedTest, savedViews
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
  assertTrue(minW >= B:ToolbarSpan() + 8 + 120 + 12, "the two dropdown rows + a minimum Export must fit")
end)

test("Browser: Export reaches the bar's right edge at minimum width, never below its floor", function()
  -- Export is row 2's last control, so it ends where the bar does at min width (12 = the pane
  -- margins) and keeps its 120px base however the row scales (B:LayoutFilterBar).
  local L = B._filterBarLayout(B._filterWidths(function() return 0 end), B:MinWidth() - 12)
  assertEqual(L.x.export + L.w.export, B:MinWidth() - 12)
  assertTrue(L.w.export >= 120, "Export stays clickable at any window size")
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
    NS.db.profile.savedViews = nil
    assertEqual(B._savedViewOrStock(), B._stockView)
  end)
end)

test("Browser: a saved view wins over stock", function()
  withFixture(FIXTURE, function()
    NS.db.profile.savedViews = { History = { groupBy = "zone", sortKey = "ilvl" } }
    assertEqual(B._savedViewOrStock().groupBy, "zone")
    assertEqual(B._savedViewOrStock("Insights"), B._stockView, "a tab's saved view is its own")
  end)
end)

test("Browser: a corrupt (non-table) saved view degrades to stock rather than erroring", function()
  withFixture(FIXTURE, function()
    NS.db.profile.savedViews = { History = "garbage" }
    assertEqual(B._savedViewOrStock(), B._stockView)
    NS.db.profile.savedViews = "garbage"
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

test("Browser.SaveView stores the tab's view; ResetView restores it; ClearFilters goes to stock", function()
  -- P11: Reset no longer drops the saved view; Clear is the way back to stock, and keeps it.
  withFixture(FIXTURE, function()
    B._dd = nil
    B:ApplyView({ groupBy = "zone", date = "all" }, "all")
    B:SaveView()
    assertEqual(NS.db.profile.savedViews.History.groupBy, "zone")
    B:ApplyView({ groupBy = "source", date = "all" }, "all")
    B:ResetView(true)
    assertEqual(NS.BrowserTable.groupBy, "zone", "reset restores the saved view")
    B:ClearFilters()
    assertEqual(NS.BrowserTable.groupBy, "none", "clear goes to stock")
    assertEqual(NS.db.profile.savedViews.History.groupBy, "zone", "and keeps the saved view")
  end)
end)

test("Browser: History offers Group: Type & SubType right after Type, and a saved view keeps it", function()
  local vals, label = {}, nil
  for _, o in ipairs(B._groupOptions) do
    vals[#vals + 1] = o.value
    if o.value == "typesub" then label = o.label end
  end
  assertTrue(table.concat(vals, ","):find("type,typesub,source", 1, true) ~= nil, table.concat(vals, ","))
  assertEqual(label, "Group: Type & SubType")
  withFixture(FIXTURE, function()
    B._dd = nil
    B:ApplyView({ groupBy = "typesub", date = "all" }, "all")
    assertEqual(NS.BrowserTable.groupBy, "typesub")
    B:SaveView()
    assertEqual(NS.db.profile.savedViews.History.groupBy, "typesub")
    B:ApplyView({ groupBy = "zone", date = "all" }, "all")
    B:ApplyView(B._savedViewOrStock(), "all")
    assertEqual(NS.BrowserTable.groupBy, "typesub", "the saved view brings the grouping back")
    B:ClearFilters()
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
  local saved = NS.db.profile.settings.window
  NS.db.profile.settings.window = { x = 100, y = 200, width = 1400 }
  B:ResetWindow()
  assertEqual(next(NS.db.profile.settings.window), nil)
  NS.db.profile.settings.window = saved
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

  for _ = 1, 12 do NS.bus:SendMessage(NS.MSG.RECORD_ADDED, {}, 1) end
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

  NS.bus:SendMessage(NS.MSG.HISTORY_CHANGED)
  assertEqual(ran, 1, "a deliberate change repaints at once, with no timer in the way")

  B.OnHistoryChanged = real
end)

-- ── Master controls: the addon-wide chrome (options-ui-§15) ───────────────────
--
-- Four settings arrived on the Master controls tab that this addon had never had: General
-- visibility, Master scale, Master alpha and Lock frame. A setting that is DECLARED and not
-- HONORED is worse than one that is absent, so each is pinned against the code that reads it
-- rather than against the schema that declares it.

local function withSettings(patch, fn)
  local s = NS.db.profile.settings
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
  -- boolean can only ever answer two of the four), or reading InCombatLockdown() for the
  -- nil-argument case -- the lockdown stays false below, so only a UnitAffectingCombat read
  -- answers the second half (events-frames-taint-§2).
  local realCombat = T.mocks.__inCombat
  local function combat(v) T.mocks.__inCombat = v end

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

  T.mocks.__inCombat = realCombat
  -- An unset value is "always", so a profile from before the row existed still opens its window.
  withSettings({ visibility = nil }, function() assertTrue(B:VisibilityAllows()) end)
end)

test("browser: Show refuses while the visibility setting forbids it, and says why", function()
  -- The window is opened on demand, so honoring the setting means REFUSING — and a silent refusal
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
    -- red under: registering them on NS.bus (the kit records events per target on `__events`, so
    -- B.__ev's table stays empty and the case goes red), or dropping the registration.
    -- Each recorded handler is fired the way CallbackHandler fires a function ref (kit revision 16).
    B:Enable()
    local events = B.__ev and B.__ev.__events
    assertTrue(events ~= nil, "the Browser has no private event target")
    local ran, real = 0, B.ApplyVisibility
    B.ApplyVisibility = function() ran = ran + 1 end
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
      local handler = events[event]
      assertEqual(type(handler), "function", event .. " is not registered on B.__ev")
      handler(event)
    end
    B.ApplyVisibility = real
    assertEqual(ran, 2, "both transitions re-apply the setting")
  end)

--- Show the window under `patch` with the player's combat flag at `inCombat`, fire `event` through
--- the kit's event bus and answer whether the window is still up. The flag does not move across the
--- edge: both cases pin the argument the handler passes, not a state read that could lag it. Always
--- leaves the window closed and the flag as it was.
local function shownAfterEdge(patch, inCombat, event)
  local realCombat = T.mocks.__inCombat
  local shown
  withSettings(patch, function()
    B:Enable()
    T.mocks.__inCombat = inCombat
    B:Show()
    local f = B:GetWindow()
    assertTrue(f ~= nil and f:IsShown(), "the window did not open before the edge")
    T.mocks.__fire(event)
    shown = f:IsShown() and true or false
    B:Hide()
  end)
  T.mocks.__inCombat = realCombat
  return shown
end

test("browser: 'Only out of combat' hides the window at the pull, before lockdown engages", function()
  -- PLAYER_REGEN_DISABLED fires BEFORE InCombatLockdown() turns true (events-frames-taint-§2), so
  -- the lockdown and the player's combat flag both stay false here: the edge itself is the state.
  -- red under: VisibilityAllows reading InCombatLockdown() (or UnitAffectingCombat) at the edge
  -- instead of taking the `true` the PLAYER_REGEN_DISABLED handler passes.
  assertFalse(shownAfterEdge({ visibility = "outOfCombat" }, false, "PLAYER_REGEN_DISABLED"),
    "'Only out of combat' left the window up at the pull")
end)

test("browser: 'Only in combat' hides the window when combat ends", function()
  -- The mirror edge: the player's combat flag still reads true when PLAYER_REGEN_ENABLED lands, so
  -- only the `false` the handler passes decides.
  -- red under: the PLAYER_REGEN_ENABLED handler calling ApplyVisibility() with no argument.
  assertFalse(shownAfterEdge({ visibility = "inCombat" }, true, "PLAYER_REGEN_ENABLED"),
    "'Only in combat' left the window up after combat ended")
end)

test("browser: Lock frame gates the resize grip as well as the title-bar drag", function()
  -- Lock frame stops the window being dragged OR resized: a locked window that still resizes from
  -- its corner grip, and persists the new size on release, is not locked.
  -- red under: the grip's OnMouseDown calling frame:StartSizing without asking B:IsLocked().
  withSettings({ visibility = "always" }, function()
    B:Show()
    local f = B:GetWindow()
    local calls = 0
    rawset(f, "StartSizing", function() calls = calls + 1 end)
    local down = f.resizeGrip:GetScript("OnMouseDown")
    local ok, err = pcall(function()
      withSettings({ locked = true }, function() down() end)
      assertEqual(calls, 0, "a locked window must not start sizing")
      withSettings({ locked = false }, function() down() end)
      assertEqual(calls, 1, "an unlocked window still resizes from its grip")
    end)
    rawset(f, "StartSizing", nil)
    B:Hide()
    if not ok then error(err, 0) end
  end)
end)

-- ── The resize grip (#33) ──────────────────────────────────────────────────────
-- Pinned before the grip moved onto Core.MakeResizable, so the move is proven to keep what the
-- player sees: the floor, the save on release, and one table refresh per drag rather than per step.

-- Opens the window, runs `fn(f)` with settings.window and the frame's armed geometry put back
-- afterwards, so neither a saved size nor a dragged one outlives the case.
local function withGripWindow(fn)
  withSettings({ visibility = "always", locked = false }, function()
    local s = NS.db.profile.settings
    local savedWindow = s.window
    B:Show()
    local f = B:GetWindow()
    local gw, gh = f:GetWidth(), f:GetHeight()
    local ok, err = pcall(fn, f)
    f:SetSize(gw, gh)
    s.window = savedWindow
    B:Hide()
    if not ok then error(err, 0) end
  end)
end

local function dragGrip(f)
  f.resizeGrip:__fire("OnMouseDown", "LeftButton")
  f.resizeGrip:__fire("OnMouseUp", "LeftButton")
end

test("browser: the History window resizes down to B:MinWidth() x SKIN.minH", function()
  -- The floor is every column's width by the minimum height, not the 700px the window opens at.
  -- red under: a resizable helper handed no minHeight, which defaults the floor to the current size.
  withGripWindow(function(f)
    assertTrue(f.__resizable, "the History window must be resizable")
    local b = f.__resizeBounds
    assertTrue(b ~= nil, "the History window must be bounded")
    assertEqual(b[1], B:MinWidth())
    assertEqual(b[2], B.SKIN.minH)
  end)
end)

test("browser: releasing the resize grip persists the window geometry", function()
  -- red under: the save left off the grip's release, so a dragged size is lost at /reload.
  withGripWindow(function(f)
    f:SetSize(1300, 520)  -- the size the drag reached (the mock's StartSizing moves nothing)
    local stops = f.__stopCount
    dragGrip(f)
    local w = NS.db.profile.settings.window
    assertTrue(w ~= nil, "the release must save settings.window")
    assertEqual(w.w, 1300)
    assertEqual(w.h, 520)
    assertEqual(f.__stopCount, stops + 1, "the release must stop the sizing")
  end)
end)

test("browser: a resize refreshes the table once, on release, not per size step", function()
  -- A full BuildDisplayList per OnSizeChanged would run every frame of a drag, and on every open.
  -- red under: SaveWindow and BrowserTable:Refresh wired as the grip's onResize.
  local BT = NS.BrowserTable
  local stock = BT.Refresh
  local refreshes = 0
  BT.Refresh = function() refreshes = refreshes + 1 end
  local ok, err = pcall(withGripWindow, function(f)
    NS.db.profile.settings.window = nil
    refreshes = 0  -- opening the window refreshes the table; only the drag is counted
    f:SetSize(1200, 500)
    for _ = 1, 3 do f:__fire("OnSizeChanged", 1200, 500) end
    assertEqual(refreshes, 0, "a size step must not refresh the table")
    assertEqual(NS.db.profile.settings.window, nil, "a size step must not save the window")
    dragGrip(f)
    assertEqual(refreshes, 1, "the release refreshes the table exactly once")
  end)
  BT.Refresh = stock
  if not ok then error(err, 0) end
end)

test("browser: a locked grip starts no sizing and its release saves nothing", function()
  -- Core.MakeResizable's canResize (LibKa0s#41): a refused press leaves the release inert. Until
  -- #33 the hand-rolled release was ungated and re-saved the unchanged geometry after a locked
  -- press; that write is gone on purpose (CA-LH-01, design D3.4).
  -- red under: canResize not passed, or the save hooked onto the grip's OnMouseUp ungated.
  withGripWindow(function(f)
    local sizing, stops = f.__sizingCount, f.__stopCount
    withSettings({ locked = true }, function()
      NS.db.profile.settings.window = nil
      dragGrip(f)
    end)
    assertEqual(f.__sizingCount, sizing, "a locked window must not start sizing")
    assertEqual(f.__stopCount, stops, "a refused press leaves nothing to stop")
    assertEqual(NS.db.profile.settings.window, nil, "a locked release must not save the window")
  end)
end)

-- Builds a grip through the seam on a fresh frame with every Button the build makes recording its
-- art, so the corner can be read back (the kit's stub answers the frame for any setter).
local function seamGrip(makeResizable, mocks, opts)
  local stock = mocks.CreateFrame
  mocks.CreateFrame = function(kind, ...)
    local made = stock(kind, ...)
    if kind == "Button" then
      rawset(made, "SetNormalTexture", function(self, p) self.__normalArt = p end)
      rawset(made, "SetHighlightTexture", function(self, p) self.__highlightArt = p end)
    end
    return made
  end
  local f = stock("Frame")
  f:SetSize(1116, 700)
  local ok, grip = pcall(makeResizable, f, opts)
  mocks.CreateFrame = stock
  if not ok then error(grip, 0) end
  return f, grip
end

test("browser: the resize grip is the Blizzard chat size grabber", function()
  -- Held through the move onto Core.MakeResizable (#33): the corner every window in the
  -- collection wears, 16px, not the catalog's `resize` mark (docs/common-tasks.md).
  local f, grip = seamGrip(NS.MakeResizable, T.mocks, {})
  assertTrue(grip ~= nil and f.resizeGrip == grip, "the seam must answer the grip it keeps")
  assertEqual(grip.__normalArt, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  assertEqual(grip.__highlightArt, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  assertEqual(grip:GetWidth(), 16)
  assertEqual(grip:GetHeight(), 16)
end)

test("browser: the History grip is Core.MakeResizable, not a hand-rolled copy", function()
  -- red under: NS.MakeResizable wrapping or re-implementing the library on a working install, or
  -- modules/Browser.lua sizing the window itself again.
  local lib = T.mocks.LibStub("LibKa0s-Core-1.0", true)
  assertTrue(lib ~= nil and NS.MakeResizable == lib.MakeResizable,
    "NS.MakeResizable must be Core.MakeResizable by reference")
  local src = T.Loader.readFile("modules/Browser.lua")
  assertTrue(src:find("NS.MakeResizable(frame, {", 1, true) ~= nil,
    "modules/Browser.lua must build its grip through the seam")
  assertTrue(src:find("StartSizing(", 1, true) == nil and src:find("SizeGrabber", 1, true) == nil,
    "no grip may be hand-rolled in modules/Browser.lua; the degraded one lives in core/CoreSetup.lua")
  assertTrue(src:find("onResize =", 1, true) == nil,
    "the save must not ride opts.onResize, which runs on every size step")
end)


-- ── Tab registry (timeline-ledger spec §8.0) ──────────────────────────────────────
-- The pane strip is a registry each owning module adds a spec to, not a hard-coded pair. History
-- and Insights register inside Browser.lua itself, so they always lead in order.

test("Browser: tab registry orders History, Insights, then registered tabs", function()
  local names = NS.Browser:Tabs()
  assertEqual(names[1], "History"); assertEqual(names[2], "Insights")
end)

test("Browser: a registered tab builds lazily and refreshes on select", function()
  -- Registered AFTER the window may already exist (earlier cases opened it), so this also pins the
  -- late path: the pane and tab button are created on the fly.
  -- red under: SelectTab looping a fixed TABS list, or rebuilding a built pane on every select.
  local built, refreshed = 0, 0
  local before = #NS.Browser:Tabs()   -- later modules (Holdings) register their own tabs too
  NS.Browser:RegisterTab{ name = "ZTest", order = 99,
    build = function() built = built + 1 end, refresh = function() refreshed = refreshed + 1 end }
  local ok, err = pcall(withSettings, { visibility = "always" }, function()
    NS.Browser:Show()
    NS.Browser:SelectTab("ZTest"); NS.Browser:SelectTab("History"); NS.Browser:SelectTab("ZTest")
    assertEqual(built, 1); assertEqual(refreshed, 2)
    assertEqual(NS.Browser:ActiveTab(), "ZTest")
    NS.Browser:SelectTab("History")
    NS.Browser:Hide()
  end)
  NS.Browser:_UnregisterTabForTest("ZTest")
  if not ok then error(err, 0) end
  assertEqual(#NS.Browser:Tabs(), before, "the test tab must leave no trace")
end)

-- ── Ledger direction + the minimum-quality view floor ──────────────────────────
-- Each case parks the settings it flips and puts them back, so test order never matters.

test("Browser: the stock view shows gains and losses, transfers per setting", function()
  local s = NS.db.profile.settings
  local savedShow = s.showTransfers
  withFixture(FIXTURE, function()
    B._dd = nil
    s.showTransfers = false
    B:ApplyView(B._stockView, "all")
    local f = B:CurrentFilter()
    assertTrue(f.dir.IN and f.dir.OUT); assertEqual(f.dir.MOVE, nil)
    s.showTransfers = true
    B:ApplyView(B._stockView, "all")
    assertTrue(B:CurrentFilter().dir.MOVE)
    s.showTransfers = false
    B:ApplyView({ dir = {}, date = "all" }, "all")
    assertEqual(B:CurrentFilter().dir, nil, "a saved empty set is All")
  end)
  s.showTransfers = savedShow
end)

test("Browser: the default view floors items at the minimum-quality setting", function()
  local p = NS.db.profile
  local savedT, savedWl = p.settings.qualityThreshold, p.whitelist
  withFixture(FIXTURE, function()
    B._dd = nil
    p.settings.qualityThreshold = 2
    p.whitelist = { [42] = true }
    B:ApplyView(B._stockView, "all")
    local f = B:CurrentFilter()
    assertEqual(f.minQuality, 2); assertTrue(f.minQualityExempt[42])
    B:ApplyView({ quality = { [0] = true }, date = "all" }, "all")
    assertEqual(B:CurrentFilter().minQuality, nil, "an explicit quality selection replaces the floor")
  end)
  p.settings.qualityThreshold, p.whitelist = savedT, savedWl
end)

test("Browser: the Quality 'all' option names the floor", function()
  local s = NS.db.profile.settings
  local savedT = s.qualityThreshold
  withFixture(FIXTURE, function()
    s.qualityThreshold = 2
    local all = B._options.quality()[1]
    assertEqual(all.value, "all")
    assertEqual(all.label, "Quality: " .. NS.Item.QualityLabel(2) .. "+")
    s.qualityThreshold = 0
    assertEqual(B._options.quality()[1].label, "Quality: All")
  end)
  s.qualityThreshold = savedT
end)

test("Browser: group options offer Direction and Holder", function()
  local seen = {}
  for _, o in ipairs(B._groupOptions) do seen[o.value] = true end
  assertTrue(seen.dir and seen.holder)
end)

-- ── timeline ledger P3: date options, per-tab filters, holders, the remembered pick ────────────
-- Every case that opens the window does it under visibility "always" (withSettings) and leaves
-- History selected; savedView and global.holdings are parked and put back.

test("Browser: date options offer 90 days and 1 year after 30 days", function()
  local vals = {}
  for _, o in ipairs(NS.Browser._dateOptions) do vals[#vals + 1] = o.value end
  assertEqual(table.concat(vals, ","), "all,today,7d,30d,90d,1y")
end)

test("Browser: _filterHonored - no set honors everything, a set honors only its keys", function()
  local f = NS.Browser._filterHonored
  assertTrue(f(nil, "bound")); assertTrue(f({}, "bound"))
  assertTrue(f({ filters = { date = true } }, "date"))
  assertFalse(f({ filters = { date = true } }, "bound"))
  assertFalse(f({ filters = { date = true } }, "search"))
end)

test("Browser: a tab grays the controls it does not honor, and History restores them", function()
  NS.Browser:RegisterTab{ name = "ZGray", order = 98, filters = { date = true }, build = function() end }
  local ok, err = pcall(withSettings, { visibility = "always" }, function()
    NS.Browser:Show()
    NS.Browser:SelectTab("ZGray")
    local dd = NS.Browser._dd
    assertTrue(dd.date:IsEnabled())
    assertFalse(dd.bound:IsEnabled()); assertFalse(dd.char:IsEnabled()); assertFalse(dd.group:IsEnabled())
    assertFalse(NS.Browser._search:IsEnabled()); assertFalse(NS.Browser._exportBtn:IsEnabled())
    assertTrue(dd.bound:IsShown(), "grayed, never hidden: the bar does not reflow between tabs")
    NS.Browser:SelectTab("History")
    assertTrue(dd.bound:IsEnabled()); assertTrue(NS.Browser._search:IsEnabled())
    assertTrue(NS.Browser._exportBtn:IsEnabled())
  end)
  NS.Browser:SelectTab("History")
  NS.Browser:_UnregisterTabForTest("ZGray")
  NS.Browser:Hide()
  if not ok then error(err, 0) end
end)

test("Browser: the Holdings tab grays Date, Source, Bound and Zone, and keeps Group live", function()
  local ok, err = pcall(withSettings, { visibility = "always" }, function()
    NS.Browser:Show(); NS.Browser:SelectTab("Holdings")
    local dd = NS.Browser._dd
    for _, k in ipairs({ "date", "source", "bound", "zone", "dir" }) do
      assertFalse(dd[k]:IsEnabled(), k .. " is not a Holdings filter")
    end
    for _, k in ipairs({ "quality", "type", "subtype", "char", "group" }) do
      assertTrue(dd[k]:IsEnabled(), k .. " is a Holdings filter")
    end
  end)
  NS.Browser:SelectTab("History")
  NS.Browser:Hide()
  if not ok then error(err, 0) end
end)

test("Browser: a holders tab lists holders, with the warband as Warband", function()
  local savedHoldings = NS.db.global.holdings
  NS.db.global.holdings = {}
  local ok, err = pcall(function()
    local W = NS.Constants.WARBAND_HOLDER
    NS.Holdings:ApplyMoney(W, 5, 1)
    NS.Holdings:ApplyMoney("Alt-Realm", 5, 1)
    local labels = {}
    for _, o in ipairs(NS.Browser._options.char(true)) do labels[o.value] = o.label end
    assertTrue(labels[W] ~= nil and labels[W]:find("Warband", 1, true) ~= nil)
    assertTrue(labels["Alt-Realm"] ~= nil)
    assertTrue(labels["current"] ~= nil, "the Current preset stays")
  end)
  NS.db.global.holdings = savedHoldings
  if not ok then error(err, 0) end
end)

test("Browser: a holder picked on Holdings stays on Holdings; History keeps its own Character scope", function()
  -- One Character control, two option sources. The warband is a holder and never a history row, so
  -- carried to History it would filter every row out under a raw-key label. Since P11 each tab keeps
  -- its own Character scope, so the pick never reaches History at all.
  local g = NS.db.global
  local savedHoldings, savedHistory = g.holdings, g.history
  local savedChar = B.activeFilter and B.activeFilter.char
  local W = NS.Constants.WARBAND_HOLDER
  g.holdings = {}
  g.history = {
    { ts = 100, itemID = 1, quality = 2, source = "KILL", char = "Alt-Realm" },
    { ts = 200, itemID = 2, quality = 2, source = "KILL", char = "Alt-Realm" },
  }
  local ok, err = pcall(withSettings, { visibility = "always" }, function()
    NS.Holdings:ApplyMoney(W, 5, 1)
    B:Show(); B:SelectTab("History")
    B:SetCharSet(nil)
    B:SelectTab("Holdings")
    B:SetCharSet({ [W] = true })
    assertTrue(B.activeFilter.char[W], "a Holdings pick")
    B:SelectTab("History")
    local char = B.activeFilter.char
    assertTrue(char == nil or not char[W], "History's own scope comes back, without the warband")
    assertFalse(NS.Browser._dd.char._selected[W], "and the dropdown follows")
    local rows = NS.Database:QueryList(NS.BrowserTable:CurrentRecords(), NS.BrowserTable.filter)
    assertEqual(#rows, 2, "the filter does not hide every row")
    B:SelectTab("Holdings")
    assertTrue(B.activeFilter.char and B.activeFilter.char[W], "Holdings keeps its pick")
    B:SetCharSet(nil)
  end)
  B:SelectTab("History")
  B:SetCharSet(savedChar)
  B:Hide()
  g.holdings, g.history = savedHoldings, savedHistory
  if not ok then error(err, 0) end
end)

test("Browser: SetViewField remembers a field with no Save, from a copy of the stock view", function()
  local p = NS.db.profile
  local saved = p.savedViews
  p.savedViews = nil
  local ok, err = pcall(function()
    NS.Browser:SetViewField("timelineThing", "c:3008", "Timeline")
    assertEqual(NS.Browser:ViewField("timelineThing", "Timeline"), "c:3008")
    local slot = p.savedViews.Timeline
    assertEqual(slot.groupBy, NS.Browser._stockView.groupBy, "everything else is stock")
    assertTrue(slot ~= NS.Browser._stockView, "a copy, never the stock table itself")
    assertEqual(NS.Browser._stockView.timelineThing, nil)
    assertEqual(p.savedViews.History, nil, "only the named tab's view is written")
  end)
  p.savedViews = saved
  if not ok then error(err, 0) end
end)

test("Browser: CaptureView on the Timeline keeps its remembered pick", function()
  local p = NS.db.profile
  local saved = NS.Util.DeepCopy(p.savedViews)
  p.savedViews = nil
  local ok, err = pcall(withSettings, { visibility = "always" }, function()
    NS.Browser:Show(); NS.Browser:SelectTab("Timeline")
    NS.Browser:SetViewField("timelineThing", "i:7", "Timeline")
    assertEqual(NS.Browser:CaptureView().timelineThing, "i:7")
    NS.Browser:SelectTab("History")
    assertEqual(NS.Browser:CaptureView().timelineThing, nil, "History's view carries no Timeline field")
  end)
  NS.Browser:SelectTab("History"); NS.Browser:Hide()
  p.savedViews = saved
  if not ok then error(err, 0) end
end)

test("Browser: DateRange reads the Date dropdown, all when there is none", function()
  local ok, err = pcall(withSettings, { visibility = "always" }, function()
    NS.Browser:Show()
    NS.Browser._dd.date:SelectValue("90d")
    assertEqual(NS.Browser:DateRange(), "90d")
    NS.Browser._dd.date:SelectValue("all")
    assertEqual(NS.Browser:DateRange(), "all")
  end)
  NS.Browser:Hide()
  if not ok then error(err, 0) end
end)

-- ── One-line filter controls (timeline-ledger P4 Task 1) ───────────────────────────────────────
-- Owner feedback: "Direction: 2 selected" and "Quality: Common+" wrapped onto a second line inside
-- their dropdowns. Each control is now as wide as the widest label it can show, its label never
-- wraps, Direction and Bound share one width, and the window floor is what the two rows need.

local FILTER_DD = { "group", "dir", "date", "bound", "quality", "type", "subtype", "source", "zone",
                    "char" }
local ROW2_DD = { "date", "bound", "quality", "type", "subtype", "source", "zone", "char" }

test("filter bar: every dropdown label is one non-wrapping line", function()
  -- red under: the library's collapsed label left at the client default, which wraps.
  withGripWindow(function()
    for _, k in ipairs(FILTER_DD) do
      local fs = B._dd[k].text
      assertEqual(fs:GetWordWrap(), false, k .. ": the label must not word-wrap")
      assertEqual(fs:GetMaxLines(), 1, k .. ": the label is one line")
    end
  end)
end)

test("filter bar: Direction and Bound are the same width", function()
  -- red under: the fixed 104 / 96 widths the bar was built with.
  withGripWindow(function()
    assertEqual(B._dd.dir:GetWidth(), B._dd.bound:GetWidth())
    -- The mock's CreateTexture hands back the frame itself, so the library's 12px arrow lands on the
    -- dropdown's own size; only a width set AFTER the build (the fit pass) reads back here.
    assertTrue(B._dd.dir:GetWidth() >= 104, "Direction keeps at least its shipped width")
  end)
end)

test("filter bar: each width covers the widest label that control can show", function()
  -- A 6px-per-character measurer stands in for the client's font metrics, which the mock answers 0.
  -- red under: widths that ignore the labels (the old fixed table).
  local function measure(_, text) return #text * 6 end
  local w, pad = B._filterWidths(measure), B._DD_PAD
  local function covers(key, label)
    assertTrue(w[key] >= #label * 6 + pad, key .. " must fit '" .. label .. "'")
  end
  covers("dir", "Direction: 3 selected")
  covers("bound", "Warbound Until Equipped")
  covers("quality", "Quality: " .. NS.Item.QualityLabel(2) .. "+")
  covers("quality", "Quality: 9 selected")
  covers("char", "Character: Current")
  covers("group", "Group: Character")
  covers("source", "Source: All")
  assertEqual(w.dir, w.bound, "Direction and Bound share the larger width")
  assertEqual(w.group, w.date, "Group stays aligned over the Date dropdown below it")
  -- Never narrower than the widths the bar shipped with, even when the font measures nothing.
  local floor = B._filterWidths(function() return 0 end)
  for _, k in ipairs(FILTER_DD) do assertTrue(w[k] >= floor[k], k .. " never shrinks below its floor") end
end)

test("filter bar: the window floor fits both rows at the built widths", function()
  withGripWindow(function()
    local dd, gap, margins = B._dd, 8, 12
    local row2 = 0
    for _, k in ipairs(ROW2_DD) do row2 = row2 + dd[k]:GetWidth() end
    row2 = row2 + (#ROW2_DD - 1) * gap + gap + B._exportBtn:GetWidth()
    assertTrue(B._minW >= row2 + margins, "row 2 (eight dropdowns + Export) must fit the floor")
    local row1 = dd.group:GetWidth() + gap + dd.dir:GetWidth() + gap + B._SEARCH_MIN
      + gap + B._exportBtn:GetWidth()   -- the Save/Reset/Clear cluster spans Export's width
    assertTrue(B._minW >= row1 + margins, "row 1 (Group, Direction, Search, the cluster) must fit")
    assertEqual(B._minW, B:MinWidth(), "the frame floor is the measured toolbar floor")
  end)
end)

test("filter bar: a saved window narrower than the floor is widened on restore", function()
  -- An older build saved a smaller size; restoring it must clamp to the new minimum.
  withGripWindow(function(f)
    NS.db.profile.settings.window = { point = "CENTER", x = 0, y = 0, w = 600, h = 200 }
    B:AdoptProfile()
    assertEqual(f:GetWidth(), B._minW)
    assertEqual(f:GetHeight(), B.SKIN.minH)
  end)
end)

-- ── The filter bar fills the window (timeline-ledger P6 Task 3) ────────────────────────────────
-- Owner feedback: the controls stopped ~120px short of the right border while the left gap was
-- ~6px. Row 2 (eight dropdowns + Export) now spans the bar exactly: every control keeps its
-- measured base width b_i and is scaled by ONE ratio r = A / sum(b_i), A = the bar width less the
-- inter-control gaps, floored at 1; Export takes the rounding remainder. Row 1 sits on row 2's grid.

local LAYOUT_ROW2 = { "date", "bound", "quality", "type", "subtype", "source", "zone", "char",
                      "export" }
local function sixPx(_, text) return #text * 6 end

-- The bar width at which row 2 exactly fits its base widths (r == 1).
local function baseBarWidth(widths)
  local L = B._filterBarLayout(widths, 0)
  local sum = 0
  for _, k in ipairs(LAYOUT_ROW2) do sum = sum + L.base[k] end
  return sum + (#LAYOUT_ROW2 - 1) * B._FILTER_GAP
end

local function rightEdge(L) return L.x.export + L.w.export end

test("filter bar layout: at the base width r == 1 and row 2 ends at the bar's right edge", function()
  -- red under: the static Export that stopped short of the right border.
  local widths = B._filterWidths(sixPx)
  local barW = baseBarWidth(widths)
  local L = B._filterBarLayout(widths, barW)
  assertEqual(L.r, 1)
  for _, k in ipairs(LAYOUT_ROW2) do assertEqual(L.w[k], L.base[k], k .. " keeps its base width") end
  assertEqual(L.x.date, 0, "row 2 starts at the bar's left edge (the window's left margin)")
  assertEqual(rightEdge(L), barW, "row 2 ends at the bar's right edge: right gap == left gap")
  assertEqual(L.base.export, 120, "Export's base width is its 120px floor")
end)

test("filter bar layout: a wider window scales every control by the same ratio", function()
  local widths = B._filterWidths(sixPx)
  local barW = baseBarWidth(widths) + 300
  local L = B._filterBarLayout(widths, barW)
  local gaps, sum = (#LAYOUT_ROW2 - 1) * B._FILTER_GAP, 0
  for _, k in ipairs(LAYOUT_ROW2) do sum = sum + L.base[k] end
  local r = (barW - gaps) / sum
  assertTrue(math.abs(L.r - r) < 1e-9, "r = available / sum of base widths")
  assertTrue(L.r > 1, "the controls grow")
  for i, k in ipairs(LAYOUT_ROW2) do
    if i < #LAYOUT_ROW2 then
      assertEqual(L.w[k], math.floor(L.base[k] * r), k .. " is floor(b * r)")
    else
      assertTrue(L.w[k] >= math.floor(L.base[k] * r), "Export takes the rounding remainder")
      assertTrue(L.w[k] - L.base[k] * r < #LAYOUT_ROW2, "the remainder is only rounding")
    end
  end
  -- Each control starts one gap after the previous one ends; row 2 ends exactly at the right edge.
  for i = 2, #LAYOUT_ROW2 do
    local p, k = LAYOUT_ROW2[i - 1], LAYOUT_ROW2[i]
    assertEqual(L.x[k], L.x[p] + L.w[p] + B._FILTER_GAP, k .. " sits one gap after " .. p)
  end
  assertEqual(L.x.date, 0)
  assertEqual(rightEdge(L), barW, "right gap == left gap at any width")
end)

test("filter bar layout: row 1 sits on row 2's grid", function()
  local widths = B._filterWidths(sixPx)
  for _, extra in ipairs({ 0, 300, 457 }) do
    local L = B._filterBarLayout(widths, baseBarWidth(widths) + extra)
    local G = B._FILTER_GAP
    assertEqual(L.x.group, L.x.date); assertEqual(L.w.group, L.w.date)
    assertEqual(L.x.dir, L.x.bound); assertEqual(L.w.dir, L.w.bound)
    -- Save · Reset · Clear span exactly Export's x-range, gaps G, the three widths equal (the
    -- left-most absorbs at most 2px of rounding).
    assertEqual(L.x.save, L.x.export)
    assertEqual(L.x.reset, L.x.save + L.w.save + G)
    assertEqual(L.x.clear, L.x.reset + L.w.reset + G)
    assertEqual(L.x.clear + L.w.clear, rightEdge(L), "the cluster ends where Export ends")
    assertEqual(L.w.reset, L.w.clear)
    assertTrue(L.w.save - L.w.clear >= 0 and L.w.save - L.w.clear <= 2, "three equal buttons")
    -- The search box fills between Direction and the cluster.
    assertEqual(L.x.search, L.x.dir + L.w.dir + G)
    assertEqual(L.x.search + L.w.search, L.x.save - G)
    assertTrue(L.w.search >= B._SEARCH_MIN, "the search box keeps its minimum")
  end
end)

test("filter bar layout: a bar narrower than the base never shrinks a control", function()
  local widths = B._filterWidths(sixPx)
  local L = B._filterBarLayout(widths, baseBarWidth(widths) - 200)
  assertEqual(L.r, 1)
  for _, k in ipairs(LAYOUT_ROW2) do assertEqual(L.w[k], L.base[k], k .. " stays at its base") end
end)

-- A fresh bar built into a scratch host, with every FontString measuring 6px a character (the
-- mock's font measures 0), so the base widths are real measurements. The window's singleton bar
-- state is put back afterwards.
local function withMeasuredBar(fn)
  local saved = {}
  local KEYS = { "_dd", "_search", "_onSearchText", "_autocomplete", "_exportBtn", "_ddWidths", "_bar", "_barCtl",
                 "_barW" }
  for _, k in ipairs(KEYS) do saved[k] = B[k] end
  local mocks = T.mocks
  local realCreateFrame = mocks.CreateFrame
  mocks.CreateFrame = function(...)
    local f = realCreateFrame(...)
    local realCFS = f.CreateFontString
    f.CreateFontString = function(self, ...)
      local fs = realCFS(self, ...)
      fs.GetUnboundedStringWidth = function(s) return #(s:GetText() or "") * 6 end
      return fs
    end
    return f
  end
  local ok, err = pcall(function()
    local host = realCreateFrame("Frame")
    B:BuildFilterBar(host)
    mocks.CreateFrame = realCreateFrame
    fn(host)
  end)
  mocks.CreateFrame = realCreateFrame
  for _, k in ipairs(KEYS) do B[k] = saved[k] end
  if not ok then error(err, 0) end
end

local function placed(ctl)
  local p = ctl:__lastPoint()
  return p.x, ctl:GetWidth(), p
end

test("filter bar: the built bar fills the bar width at the base width and 300px wider", function()
  withMeasuredBar(function(host)
    local widths = B._ddWidths
    assertTrue(widths.char > 146, "the scratch build measured its labels (6px a character)")
    for _, extra in ipairs({ 0, 300 }) do
      local barW = baseBarWidth(widths) + extra
      B:LayoutFilterBar(barW)
      local L = B._filterBarLayout(widths, barW)
      local ctl = { group = B._dd.group, dir = B._dd.dir, search = B._search,
                    export = B._exportBtn }
      for _, k in ipairs(LAYOUT_ROW2) do ctl[k] = ctl[k] or B._dd[k] end
      for k, c in pairs(ctl) do
        local x, w, p = placed(c)
        assertEqual(p.point, "TOPLEFT", k .. " is anchored by its top-left corner")
        assertEqual(p.relativeTo, host, k .. " is anchored to the bar itself")
        assertEqual(x, L.x[k], k .. " x at +" .. extra)
        assertEqual(w, L.w[k], k .. " width at +" .. extra)
      end
      local ex, ew = placed(B._exportBtn)
      assertEqual(ex + ew, barW, "Export ends at the bar's right edge at +" .. extra)
      local dx = placed(B._dd.date)
      assertEqual(dx, 0, "Date starts at the bar's left edge")
      if extra == 0 then assertEqual(L.r, 1) end
    end
  end)
end)

test("filter bar: resizing the window re-lays the bar out to its new width", function()
  -- red under: a bar laid out once at build time, which leaves the gap on the right as it widens.
  withGripWindow(function(f)
    local w = B._minW + 300
    f:SetSize(w, B.SKIN.minH)
    f:__fire("OnSizeChanged", w, B.SKIN.minH)
    local ex, ew = placed(B._exportBtn)
    assertEqual(ex + ew, w - 12, "row 2 ends 6px in from the right border, as it starts on the left")
    assertEqual((placed(B._dd.date)), 0)
    local cx, cw = placed(B._barCtl.clear)
    assertEqual(cx + cw, w - 12, "the Save/Reset/Clear cluster ends there too")
  end)
end)

-- ── Timeline ledger Phase 7: the Character filter matches the row's holder (Review Focus 4) ──────
test("Browser: Character Current shows the character's half of a warband move, Warband the other", function()
  local W = NS.Constants.WARBAND_HOLDER
  local me = NS.Util.PlayerKey()
  local rows = {
    { ts = 100, char = me, holder = W, dir = "OUT", kind = "GOLD", itemName = "Gold", quantity = 500,
      source = "WARBAND_WITHDRAW", from = W .. "/tabs", to = me .. "/bags", pairId = "100:1" },
    { ts = 100, char = me, holder = me, dir = "IN", kind = "GOLD", itemName = "Gold", quantity = 500,
      source = "WARBAND_WITHDRAW", from = W .. "/tabs", to = me .. "/bags", pairId = "100:1" },
  }
  withFixture(rows, function()
    -- The list offers the Warband, under the name a player reads.
    local labels = {}
    for _, o in ipairs(NS.Browser._options.char(false)) do labels[o.value] = o.label end
    assertEqual(labels[W], "Warband")
    assertTrue(labels[me] ~= nil)
    -- "Character: Current" is the set { [me] = true }.
    local mine = NS.Database:Query({ char = { [me] = true } })
    assertEqual(#mine, 1); assertEqual(mine[1].holder, me); assertEqual(mine[1].dir, "IN")
    local wb = NS.Database:Query({ char = { [W] = true } })
    assertEqual(#wb, 1); assertEqual(wb[1].holder, W); assertEqual(wb[1].dir, "OUT")
    assertEqual(#NS.Database:Query({}), 2, "Character: All shows both halves")
  end)
end)
