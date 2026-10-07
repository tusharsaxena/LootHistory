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

-- ── Characterization (LH-13): Search over every filter branch ──────────────────────────────
-- Items, a currency and gold, with stubbed item info so quality and type are known; pins the text
-- match, each set filter (an empty set passes everything; a nil field never passes a non-empty
-- set), the holder filter, the zero-total exclusion and the case-insensitive name order.
test("Holdings: Search filters by text, quality, type and subtype, drops zero totals, sorts by name", function()
  fresh()
  local C = NS.Compat
  local savedInfo, savedType = C.GetItemInfo, C.GetItemTypeInfo
  local info = {
    [1] = { "alpha Ore", 2, "Tradeskill", "Metal" },
    [2] = { "Bravo Blade", 4, "Weapon", "Sword" },
    [3] = { "charlie ore", 3, "Tradeskill", "Metal" },
  }
  local function idOf(x) return tonumber(tostring(x):match("item:(%d+)") or x) end
  C.GetItemInfo = function(x) local r = info[idOf(x)]; return nil, r and r[1], r and r[2] end
  C.GetItemTypeInfo = function(x) local r = info[idOf(x)]; return r and r[3], r and r[4] end
  local ok, err = pcall(function()
    H():ApplyContainer("A-Realm", "bags", { [1] = 2, [2] = 1 }, { [1] = "|Hitem:1|h[alpha Ore]|h" }, 1)
    H():ApplyContainer("B-Realm", "bags", { [3] = 5 }, {}, 1)
    H():ApplyCurrency("A-Realm", { [3008] = 40 }, 1)
    H():ApplyMoney("B-Realm", 100, 1)
    H():ApplyMoney("A-Realm", 0, 1)
    local function keys(filter)
      local out = {}
      for _, r in ipairs(H():Search(filter)) do out[#out + 1] = r.key .. "=" .. r.total end
      return table.concat(out, ",")
    end
    local gold = (_G.GOLD or "Gold")
    local all = keys({})
    assertTrue(all:find("i:1=2", 1, true) and all:find("i:2=1", 1, true) and all:find("i:3=5", 1, true)
      and all:find("c:3008=40", 1, true) and all:find("g=100", 1, true), all)
    assertEqual(keys(nil), all, "a nil filter is the empty filter")
    assertEqual(keys({ text = "" }), all, "an empty text matches everything")
    assertEqual(keys({ text = "ORE" }), "i:1=2,i:3=5")
    assertEqual(keys({ text = gold:lower() }), "g=100")
    assertEqual(keys({ quality = {} }), all, "an empty set passes")
    assertEqual(keys({ quality = { [4] = true } }), "i:2=1,c:3008=40", "gold has no quality")
    assertEqual(keys({ itemType = { Tradeskill = true } }), "i:1=2,i:3=5")
    assertEqual(keys({ itemSubType = { Sword = true } }), "i:2=1")
    assertEqual(keys({ itemType = { Tradeskill = true }, quality = { [3] = true } }), "i:3=5")
    assertEqual(keys({ char = { ["B-Realm"] = true } }), "i:3=5,g=100", "zero-total things are dropped")
    assertEqual(keys({ char = {} }), all, "an empty holder set is no holder filter")
    local r = H():Search({ text = "alpha" })[1]
    assertEqual(r.kind, "ITEM"); assertEqual(r.id, 1); assertEqual(r.name, "alpha Ore")
    assertEqual(r.quality, 2); assertEqual(r.itemType, "Tradeskill"); assertEqual(r.itemSubType, "Metal")
    assertEqual(r.link, "|Hitem:1|h[alpha Ore]|h"); assertEqual(#r.holders, 1)
  end)
  C.GetItemInfo, C.GetItemTypeInfo = savedInfo, savedType
  if not ok then error(err, 0) end
end)
