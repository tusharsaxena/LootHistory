local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- Per-tab filter views (timeline-ledger Phase 11, owner decision 2026-10-07). Every browser tab
-- keeps its OWN live filter state on the one shared bar and its OWN saved view
-- (profile.savedViews[tab]); Save, Reset and Clear act on the active tab alone; schema v14 split the
-- single savedView into the four slots. Every window case runs through `case`, which puts back the
-- saved views, the holdings store, both tables' group and sort, History's bar state and the session
-- parked states, and closes the window, so test order never matters. The Insights pane is built
-- with Analytics:Attach stubbed: its charts never draw headless (tests/test_analytics_layout.lua
-- drives them on a private instance), and only the tab's filter state is under test here.

local B = NS.Browser
local TABS = { "History", "Insights", "Timeline", "Holdings" }

-- A stable text form of any value, keys sorted, for whole-table comparisons.
local function ser(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. ser(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function case(name, fn)
  test(name, function()
    local p, g, BT, HT = NS.db.profile, NS.db.global, NS.BrowserTable, NS.HoldingsTab
    local views, holdings = NS.Util.DeepCopy(p.savedViews), g.holdings
    local vis = p.settings.visibility
    local bt = { BT.groupBy, BT.sortKey, BT.sortAsc, BT.groupAsc }
    local ht = { HT.groupBy, HT.sortKey, HT.sortAsc }
    local attach = NS.Analytics.Attach
    NS.Analytics.Attach = function() end
    p.settings.visibility = "always"
    B:Show(); B:SelectTab("History")
    local histView, histChar = B:CaptureView(), B._setToFilter(B.activeFilter.char) or {}
    B._forgetLive()
    local ok, err = pcall(fn)
    B:SelectTab("History")
    B:ApplyView(histView, histChar)
    B._forgetLive(); B:Hide()
    NS.Analytics.Attach = attach
    BT.groupBy, BT.sortKey, BT.sortAsc, BT.groupAsc = bt[1], bt[2], bt[3], bt[4]
    HT.groupBy, HT.sortKey, HT.sortAsc = ht[1], ht[2], ht[3]
    p.savedViews, g.holdings, p.settings.visibility = views, holdings, vis
    if not ok then error(err, 0) end
  end)
end

-- A filter's text form with the Date range's resolved `from` set aside: a re-applied range is
-- resolved again against the clock, so it can move on by a second between two reads.
local function serFilter(f)
  assertTrue(f.from == nil or type(f.from) == "number")
  local from = f.from ~= nil
  f.from = nil
  return ser(f) .. (from and "+from" or "")
end

-- Drive a multi-select dropdown as a click would: the selection, then its onMultiSelect.
local function pick(key, set)
  local dd = B._dd[key]
  dd:SetSelected(set)
  dd.onMultiSelect(dd._selected)
end

local function seedHoldings()
  NS.db.global.holdings = {}
  NS.Holdings:ApplyContainer("A-Realm", "bags", { [7] = 2 }, { [7] = "|Hitem:7|h[Apple]|h" }, 100)
  NS.Holdings:ApplyContainer("B-Realm", "bank", { [7] = 9 }, {}, 50)
  NS.Holdings:ApplyMoney("A-Realm", 10000, 100)
end

-- ── Review Focus 1: Save / Reset / Clear touch only the active tab ────────────────────────────

case("Views: Save on each tab writes only that tab's slot", function()
  NS.db.profile.savedViews = nil
  for _, tab in ipairs(TABS) do
    B:SelectTab(tab)
    B:SetSearchText("s-" .. tab)
    local before = {}
    for _, other in ipairs(TABS) do
      before[other] = ser(NS.db.profile.savedViews and NS.db.profile.savedViews[other])
    end
    B:SaveView()
    local after = NS.db.profile.savedViews
    assertEqual(after[tab].search, "s-" .. tab, tab .. " saved its own search")
    for _, other in ipairs(TABS) do
      if other ~= tab then
        assertEqual(ser(after[other]), before[other], tab .. "'s Save left " .. other .. "'s slot alone")
      end
    end
  end
  for _, tab in ipairs(TABS) do
    assertEqual(NS.db.profile.savedViews[tab].search, "s-" .. tab, tab .. " kept its own slot")
  end
end)

case("Views: Reset and Clear on one tab change only that tab's live state and no saved slot", function()
  NS.db.profile.savedViews = nil
  for _, tab in ipairs(TABS) do
    B:SelectTab(tab); B:SetSearchText("saved-" .. tab); B:SaveView()
  end
  for _, tab in ipairs(TABS) do
    B:SelectTab(tab); B:SetSearchText("live-" .. tab)
  end
  local saved = ser(NS.db.profile.savedViews)
  for _, tab in ipairs(TABS) do
    B:SelectTab(tab)
    B:ResetView(true)
    assertEqual(B._search:GetText(), "saved-" .. tab, tab .. " Reset restores its saved view")
    assertEqual(B:CurrentFilter().text, "saved-" .. tab)
    for _, other in ipairs(TABS) do
      if other ~= tab then
        assertEqual(B:CurrentFilter(other).text, "live-" .. other, other .. " untouched by " .. tab .. "'s Reset")
      end
    end
    B:SetSearchText("live-" .. tab)   -- back to the live text, so the next tab's check is exact
  end
  local cleared = {}
  for _, tab in ipairs(TABS) do
    B:SelectTab(tab)
    B:ClearFilters()
    cleared[tab] = true
    assertEqual(B._search:GetText(), "", tab .. " Clear goes to stock")
    for _, other in ipairs(TABS) do
      if not cleared[other] then
        assertEqual(B:CurrentFilter(other).text, "live-" .. other, other .. " untouched by " .. tab .. "'s Clear")
      end
    end
  end
  assertEqual(ser(NS.db.profile.savedViews), saved, "Reset and Clear never write a saved view")
end)

case("Views: a tab with no saved view resets to its own stock view", function()
  NS.db.profile.savedViews = { History = { search = "kept", date = "all" } }
  B:SelectTab("Insights")
  B:SetSearchText("typed")
  B:ResetView(true)
  assertEqual(B._search:GetText(), "", "Insights has no saved view: stock")
  B:SelectTab("History")
  B:ResetView(true)
  assertEqual(B._search:GetText(), "kept", "History's saved view is its own")
end)

-- ── Review Focus 4: the reported bug, on the Holdings view itself ─────────────────────────────

case("Views: Holdings Save, Reset and Clear take effect on the Holdings view", function()
  local HT, BT = NS.HoldingsTab, NS.BrowserTable
  seedHoldings()
  NS.db.profile.savedViews = nil
  B:SelectTab("History")
  BT:SetGroupBy("zone"); B._dd.group:SelectValue("zone")
  B:SelectTab("Holdings"); B:SetCharSet(nil)
  B._dd.group.onSelect("char")
  HT:SetSort("total")
  pick("quality", { [4] = true })
  B:SaveView()
  local slot = NS.db.profile.savedViews.Holdings
  assertEqual(slot.groupBy, "char"); assertEqual(slot.sortKey, "total"); assertEqual(slot.sortAsc, false)
  assertTrue(slot.quality[4], "the Holdings filters are in its view")
  assertEqual(NS.db.profile.savedViews.History, nil, "Save on Holdings wrote no History slot")

  B._dd.group.onSelect("none"); HT:SetSort("name"); pick("quality", {})
  B:ResetView(true)
  assertEqual(HT.groupBy, "char", "Reset regroups the Holdings view")
  assertEqual(HT.sortKey, "total"); assertEqual(HT.sortAsc, false)
  assertEqual(B._dd.group._value, "char", "and the Group dropdown reads it")
  assertTrue(B.activeFilter.quality and B.activeFilter.quality[4], "and its filter is back")
  B:SetCharSet(nil)   -- Reset scopes to the logged-in character, who holds nothing in this seed
  local lines = HT:Rows()
  assertTrue(#lines > 0 and lines[1].line.kind == "header", "the repainted view is grouped")

  B:ClearFilters()
  assertEqual(HT.groupBy, "none", "Clear ungroups the Holdings view")
  assertEqual(HT.sortKey, "name"); assertEqual(HT.sortAsc, true, "Holdings' stock sort is Name, A to Z")
  assertEqual(B.activeFilter.quality, nil)
  assertEqual(NS.db.profile.savedViews.Holdings.groupBy, "char", "Clear keeps the saved view")
  assertEqual(BT.groupBy, "zone", "nothing on Holdings moved History's table")
end)

case("Views: a view from another tab applies to Holdings as None, sorted by Name", function()
  local HT = NS.HoldingsTab
  B:SelectTab("Holdings")
  B:ApplyView({ groupBy = "zone", sortKey = "date", sortAsc = false, date = "all" }, "all")
  assertEqual(HT.groupBy, "none"); assertEqual(HT.sortKey, "name"); assertEqual(HT.sortAsc, true)
  B:ApplyView({ groupBy = "type", sortKey = "total", date = "all" }, "all")
  assertEqual(HT.groupBy, "type"); assertEqual(HT.sortKey, "total")
  assertEqual(HT.sortAsc, false, "a numeric column with no stored direction starts descending")
end)

-- ── Review Focus 2: tab switches restore each tab's live state exactly ───────────────────────

case("Views: switching tabs back and forth restores each tab's own live state exactly", function()
  seedHoldings()
  local me = NS.Util.PlayerKey()
  B:SelectTab("History")
  pick("quality", { [3] = true, [4] = true }); pick("source", { KILL = true })
  B._dd.date:SelectValue("7d"); B._dd.date.onSelect("7d")
  B:SetSearchText("axe"); B:SetCharSet({ [me] = true })
  local hist = serFilter(B:CurrentFilter())
  local histView = ser(B:CaptureView())

  B:SelectTab("Holdings")
  assertEqual(B._search:GetText(), "", "Holdings does not wear History's search")
  assertEqual(B.activeFilter.quality, nil, "nor its quality")
  pick("quality", { [2] = true }); B:SetSearchText("ore"); B:SetCharSet({ ["B-Realm"] = true })
  B._dd.group.onSelect("type")
  local hold = serFilter(B:CurrentFilter())

  B:SelectTab("Timeline"); B:SetSearchText("Gold")
  B:SelectTab("History")
  assertEqual(serFilter(B:CurrentFilter()), hist, "History's filter is back exactly")
  assertEqual(ser(B:CaptureView()), histView, "and so is its view, sets and search included")
  assertTrue(B._dd.quality._selected[3] and B._dd.quality._selected[4], "the dropdown shows it")
  assertTrue(B._dd.char._selected[me])
  assertEqual(B:DateRange(), "7d")

  B:SelectTab("Holdings")
  assertEqual(serFilter(B:CurrentFilter()), hold, "Holdings' filter is back exactly")
  assertEqual(B._search:GetText(), "ore"); assertTrue(B._dd.char._selected["B-Realm"])
  assertEqual(NS.HoldingsTab.groupBy, "type"); assertEqual(B._dd.group._value, "type")
  B:SelectTab("Timeline")
  assertEqual(B._search:GetText(), "Gold")
end)

case("Views: Insights reads its own filter, even while another tab is on the bar", function()
  B:SelectTab("Insights"); pick("source", { KILL = true })
  B:SelectTab("History"); B:SetSearchText("axe")
  local f = B:CurrentFilter("Insights")
  assertTrue(f.source and f.source.KILL, "Insights' own source pick")
  assertEqual(f.text, nil, "History's search is not Insights'")
  assertEqual(B:CurrentFilter("History").text, "axe")
end)

case("Views: a tab never shown opens on its saved view, scoped to the current player", function()
  NS.db.profile.savedViews = { Insights = { search = "fresh", date = "all" } }
  local f = B:CurrentFilter("Insights")
  assertEqual(f.text, "fresh")
  assertTrue(f.char and f.char[NS.Util.PlayerKey()], "the session default scope")
  B:SelectTab("Insights")
  assertEqual(B._search:GetText(), "fresh")
end)

case("Views: a profile adopt forgets every tab's parked state", function()
  B:SelectTab("Insights"); B:SetSearchText("parked")
  B:SelectTab("History")
  NS.db.profile.savedViews = nil
  B:AdoptProfile()
  assertEqual(B:CurrentFilter("Insights").text, nil, "Insights opens on the new profile's view")
end)

case("Views: test mode never writes a saved view", function()
  NS.db.profile.savedViews = nil
  local BT = NS.BrowserTable
  local was = BT.testMode
  BT.testMode = true
  local ok, err = pcall(function() B:SaveView() end)
  BT.testMode = was
  if not ok then error(err, 0) end
  assertEqual(NS.db.profile.savedViews, nil, "Save in test mode stores nothing")
end)

case("Views: Clear on the Timeline keeps the remembered thing", function()
  NS.db.profile.savedViews = nil
  local thing = NS.Timeline.thing
  local ok, err = pcall(function()
    B:SelectTab("Timeline")
    NS.Timeline:SetThing("g", true)
    B:SetSearchText("Gold")
    B:ClearFilters()
    assertEqual(B._search:GetText(), "", "the filters went to stock")
    assertEqual(NS.Timeline:Thing(), "g", "the charted thing stayed")
    assertEqual(B:ViewField("timelineThing", "Timeline"), "g", "and stays remembered")
  end)
  NS.Timeline.thing = thing
  if not ok then error(err, 0) end
end)

-- ── Review Focus 3: the v13 -> v14 migration ───────────────────────────────────────────────

--- Run the real runner against `db`, with the harness's own db put back however it ends. Answers
--- the v13 -> v14 [Migrate] row count.
local function migrate(db)
  local real, savedDebug, savedFlag = NS.db, NS.Debug, NS.State.debug
  local n
  NS.Debug = function(tag, fmt, ...)
    n = tonumber((tag .. " " .. fmt:format(...)):match("^Migrate v13 %-> v14, (%d+) rows")) or n
  end
  NS.State.debug = true
  NS.db = db
  local ok, err = pcall(NS.RunMigrations, NS)
  NS.db, NS.Debug, NS.State.debug = real, savedDebug, savedFlag
  if not ok then error(err, 0) end
  return n
end

test("Migrate v13->v14: a profile's saved view becomes four identical per-tab views, the old key goes", function()
  -- red under: no v14 step, a step that aliases one table into every slot, or one that keeps savedView.
  local view = { groupBy = "zone", quality = { [4] = true }, search = "axe", timelineThing = "g" }
  local sv = {
    global = { schemaVersion = 13, history = {} },
    profiles = {
      Default = { savedView = NS.Util.DeepCopy(view) },
      Raid    = { settings = { qualityThreshold = 3 } },
      Kept    = { savedView = { groupBy = "day" }, savedViews = { History = { groupBy = "source" } } },
    },
  }
  local n = migrate({ global = sv.global, sv = sv })
  assertEqual(sv.global.schemaVersion, 14)
  assertEqual(n, 2, "the two profiles with a saved view")
  local d = sv.profiles.Default
  assertEqual(d.savedView, nil, "the single view is retired")
  for _, tab in ipairs(TABS) do
    assertEqual(ser(d.savedViews[tab]), ser(view), tab .. " starts exactly where the player was")
  end
  assertTrue(d.savedViews.History ~= d.savedViews.Holdings, "copies, never one shared table")
  assertTrue(d.savedViews.History.quality ~= d.savedViews.Insights.quality, "deep copies")
  assertEqual(sv.profiles.Raid.savedViews, nil, "a profile with no saved view gains none")
  assertEqual(sv.profiles.Kept.savedViews.History.groupBy, "source", "a slot already there is kept")
  assertEqual(sv.profiles.Kept.savedViews.Insights.groupBy, "day")
  assertEqual(sv.profiles.Kept.savedView, nil)
end)

test("Migrate v13->v14: a second run changes nothing", function()
  local sv = {
    global = { schemaVersion = 13, history = {} },
    profiles = { Default = { savedView = { groupBy = "zone" } }, Empty = {} },
  }
  migrate({ global = sv.global, sv = sv })
  local after = ser(sv.profiles)
  sv.global.schemaVersion = 13
  assertEqual(migrate({ global = sv.global, sv = sv }), 0, "the re-run touched no profile")
  assertEqual(ser(sv.profiles), after)
  assertEqual(sv.profiles.Empty.savedViews, nil)
end)

test("Migrate v13->v14: a corrupt (non-table) saved view is dropped, and no slot is made of it", function()
  local sv = { global = { schemaVersion = 13, history = {} }, profiles = { Default = { savedView = "garbage" } } }
  migrate({ global = sv.global, sv = sv })
  assertEqual(sv.profiles.Default.savedView, nil)
  assertEqual(sv.profiles.Default.savedViews, nil)
end)
