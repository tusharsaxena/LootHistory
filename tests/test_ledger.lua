local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("Ledger: ThingKey round-trips for every kind", function()
  local L, K = NS.Ledger, NS.Constants.Kind
  assertEqual(L.ThingKey(K.GOLD), "g")
  assertEqual(L.ThingKey(K.CURRENCY, 3008), "c:3008")
  assertEqual(L.ThingKey(K.ITEM, 211296), "i:211296")
  local k, id = L.ParseThingKey("c:3008"); assertEqual(k, K.CURRENCY); assertEqual(id, 3008)
  k, id = L.ParseThingKey("i:211296");     assertEqual(k, K.ITEM);     assertEqual(id, 211296)
  k, id = L.ParseThingKey("g");            assertEqual(k, K.GOLD);     assertEqual(id, nil)
  assertEqual(L.ParseThingKey("x:1"), nil)
end)

test("Ledger: Diff reports signed deltas, sorted, zeros omitted", function()
  local d = NS.Ledger.Diff({ [5] = 3, [2] = 10, [9] = 1 }, { [5] = 3, [2] = 4, [7] = 6 })
  assertEqual(#d, 3)
  assertEqual(d[1].key, 2); assertEqual(d[1].delta, -6)
  assertEqual(d[2].key, 7); assertEqual(d[2].delta, 6)
  assertEqual(d[3].key, 9); assertEqual(d[3].delta, -1)
end)

test("Ledger: Diff treats nil maps as empty", function()
  assertEqual(#NS.Ledger.Diff(nil, nil), 0)
  local d = NS.Ledger.Diff(nil, { [1] = 2 })
  assertEqual(d[1].key, 1); assertEqual(d[1].delta, 2)
end)

test("Ledger: DirSign totals", function()
  local s = NS.Ledger.DirSign
  assertEqual(s.IN, 1); assertEqual(s.OUT, -1); assertEqual(s.MOVE, 0)
end)

test("Util: row accessors give legacy defaults", function()
  local U = NS.Util
  local legacyItem = { itemID = 1, char = "A-Realm" }
  local legacyCur  = { currencyID = 3008, char = "A-Realm" }
  assertEqual(U.RowDir(legacyItem), "IN")
  assertEqual(U.RowKind(legacyItem), "ITEM")
  assertEqual(U.RowKind(legacyCur), "CURRENCY")
  assertEqual(U.RowHolder(legacyItem), "A-Realm")
  local gold = { kind = "GOLD", dir = "OUT", holder = "§warband", char = "A-Realm" }
  assertEqual(U.RowDir(gold), "OUT"); assertEqual(U.RowKind(gold), "GOLD")
  assertEqual(U.RowHolder(gold), "§warband")
end)

test("Constants: ledger enums and warband key", function()
  local C = NS.Constants
  assertEqual(C.WARBAND_HOLDER, "§warband")
  assertEqual(C.Container.TABS, "tabs")
  assertTrue(C.Dir.MOVE == "MOVE" and C.Kind.GOLD == "GOLD")
end)
