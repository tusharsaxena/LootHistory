local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- The Holdings tab (timeline-ledger spec §8.2). BuildModel carries every decision and is pure, so
-- most of this suite never touches a frame; the last case opens the window to pin that the pooled
-- rows are recycled rather than reallocated on refresh.

local function seed()
  NS.db.global.holdings = {}
  NS.Holdings:ApplyContainer("A-Realm", "bags", { [7] = 2 }, { [7] = "|Hitem:7|h[Apple]|h" }, 100)
  NS.Holdings:ApplyContainer("B-Realm", "bank", { [7] = 9 }, {}, 50)
  NS.Holdings:ApplyMoney("A-Realm", 10000, 100)
end

test("HoldingsTab: model lists things collapsed by default", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({}, {}, "name")
  local things = 0
  for _, l in ipairs(lines) do if l.kind == "thing" then things = things + 1 else error("holder line while collapsed") end end
  assertEqual(things, 2)   -- Apple + Gold
end)

test("HoldingsTab: expanding a thing adds one line per holder", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({}, { ["i:7"] = true }, "total")
  assertEqual(lines[1].key, "g")            -- total sort: gold 10000 first
  local holders = 0
  for _, l in ipairs(lines) do if l.kind == "holder" then holders = holders + 1 end end
  assertEqual(holders, 2)
end)

test("HoldingsTab: character filter narrows holders", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({ char = { ["B-Realm"] = true } }, { ["i:7"] = true }, "name")
  for _, l in ipairs(lines) do
    if l.kind == "holder" then assertEqual(l.holder, "B-Realm") end
    if l.kind == "thing" then assertTrue(l.key ~= "g") end   -- B has no gold
  end
end)

test("HoldingsTab: container and age formatting", function()
  assertEqual(NS.HoldingsTab.FormatContainers({ tabs = 100, bags = 12, bank = 40 }), "Bags 12 · Bank 40 · Warband 100")
  assertEqual(NS.HoldingsTab.FormatAge(1000, 1030), "now")
  assertEqual(NS.HoldingsTab.FormatAge(1000, 1000 + 3 * 3600), "3 h")
  assertEqual(NS.HoldingsTab.FormatAge(1000, 1000 + 2 * 86400), "2 d")
end)

test("HoldingsTab: tab is registered after History and Insights", function()
  local names = NS.Browser:Tabs()
  assertEqual(names[#names], "Holdings")
end)

test("HoldingsTab: attach builds rows and recycles them on refresh", function()
  -- Adapted from the plan's snippet: the window is closed again on every path, because a browser
  -- left on screen keeps repainting under the panel suites that run next and skews their counts.
  -- The pool's free/active split is also pinned, since an equal row count alone passes a refresh
  -- that allocates a fresh frame per line every time. The window opens scoped to the logged-in
  -- character (Mock-Realm), who holds nothing in this seed, so the scope is widened for the case
  -- and put back after.
  seed()
  local savedChar = NS.Browser:CurrentFilter().char
  local ok, err = pcall(function()
    NS.Browser:Show(); NS.Browser:SetCharSet(nil); NS.Browser:SelectTab("Holdings")
    local first = NS.HoldingsTab:VisibleRowCount()
    local _, active = NS.Pool.Counts(NS.HoldingsTab.rows)
    NS.HoldingsTab:Refresh()
    assertEqual(NS.HoldingsTab:VisibleRowCount(), first)
    assertTrue(first >= 2)
    local free2, active2 = NS.Pool.Counts(NS.HoldingsTab.rows)
    assertEqual(active2, active); assertEqual(free2, 0, "a refresh re-acquired every released row")
  end)
  NS.Browser:SetCharSet(savedChar); NS.Browser:SelectTab("History"); NS.Browser:Hide()
  if not ok then error(err, 0) end
end)
