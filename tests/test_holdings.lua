local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function fresh() NS.db.global.holdings = {} end
local H = function() return NS.Holdings end

test("Holdings: ApplyContainer replaces one column and keeps others", function()
  fresh()
  H():ApplyContainer("A-Realm", "bags", { [1] = 5, [2] = 1 }, {}, 100)
  H():ApplyContainer("A-Realm", "bank", { [1] = 10 }, {}, 100)
  assertTrue(H():ApplyContainer("A-Realm", "bags", { [1] = 4 }, {}, 200))
  local e = H():Get("A-Realm")
  assertEqual(e.items[1].bags, 4)
  assertEqual(e.items[1].bank, 10)
  assertEqual(e.items[2], nil)               -- item 2 left bags and has no other column
  assertEqual(e.scanned.bags, 200); assertEqual(e.scanned.bank, 100)
end)

test("Holdings: unchanged container reports no change", function()
  fresh()
  H():ApplyContainer("A-Realm", "bags", { [1] = 5 }, {}, 100)
  assertFalse(H():ApplyContainer("A-Realm", "bags", { [1] = 5 }, {}, 150))
end)

test("Holdings: Total sums holders and warband, sorted by count", function()
  fresh()
  H():ApplyContainer("A-Realm", "bags", { [7] = 2 }, {}, 1)
  H():ApplyContainer("B-Realm", "bank", { [7] = 9 }, {}, 1)
  H():ApplyContainer("§warband", "tabs", { [7] = 4 }, {}, 1)
  local total, rows = H():Total("i:7")
  assertEqual(total, 15)
  assertEqual(rows[1].holder, "B-Realm"); assertEqual(rows[1].count, 9)
  assertEqual(rows[3].holder, "A-Realm")
end)

test("Holdings: gold and currency totals", function()
  fresh()
  H():ApplyMoney("A-Realm", 100, 1); H():ApplyMoney("§warband", 50, 1)
  H():ApplyCurrency("A-Realm", { [3008] = 40 }, 1)
  assertEqual((H():Total("g")), 150)
  assertEqual((H():Total("c:3008")), 40)
end)

test("Holdings: genesis is set once; partial until bank seen", function()
  fresh()
  H():ApplyContainer("A-Realm", "bags", { [1] = 1 }, {}, 10)
  H():MarkGenesis("A-Realm", 10)
  H():MarkGenesis("A-Realm", 99)
  local e = H():Get("A-Realm")
  assertEqual(e.meta.genesis, 10); assertTrue(e.meta.partial)
  H():ApplyContainer("A-Realm", "bank", {}, {}, 20)
  H():MarkGenesis("A-Realm", 20)
  assertFalse(e.meta.partial)
end)

test("Holdings: Holders lists characters then warband", function()
  fresh()
  H():ApplyMoney("§warband", 1, 1); H():ApplyMoney("Zed-Realm", 1, 1); H():ApplyMoney("Abe-Realm", 1, 1)
  assertEqual(table.concat(H():Holders(), ","), "Abe-Realm,Zed-Realm,§warband")
end)

test("Holdings: Search keeps uncached items and filters by holder", function()
  fresh()
  H():ApplyContainer("A-Realm", "bags", { [42] = 3 }, {}, 1)          -- no link: uncached
  H():ApplyContainer("B-Realm", "bags", { [43] = 1 }, { [43] = "|Hitem:43|h[Herb]|h" }, 1)
  local all = H():Search({})
  local keys = {}; for _, r in ipairs(all) do keys[r.key] = r end
  assertTrue(keys["i:42"] ~= nil)
  assertTrue(type(keys["i:42"].name) == "string" and #keys["i:42"].name > 0)
  local onlyB = H():Search({ char = { ["B-Realm"] = true } })
  for _, r in ipairs(onlyB) do assertTrue(r.key ~= "i:42") end
end)

test("Holdings: ForgetHolder drops the entry", function()
  fresh()
  H():ApplyMoney("A-Realm", 1, 1)
  assertTrue(H():ForgetHolder("A-Realm"))
  assertEqual(H():Get("A-Realm"), nil)
end)
