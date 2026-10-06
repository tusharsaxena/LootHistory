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

-- ── Phase 2: classification, holder pairing, claims, coalescing, hold ───────────────────────
local assertFalse = T.assertFalse
local L = function() return NS.Ledger end

test("Ledger: ClassifyItems pairs a bag-to-bank deposit into one MOVE, no net", function()
  local moves, net = L().ClassifyItems(
    { bags = { [7] = 5 }, bank = { [7] = 0 } },
    { bags = { [7] = 0 }, bank = { [7] = 5 } })
  assertEqual(#moves, 1)
  assertEqual(moves[1].id, 7); assertEqual(moves[1].qty, 5)
  assertEqual(moves[1].from, "bags"); assertEqual(moves[1].to, "bank")
  assertEqual(next(net), nil)
end)

test("Ledger: ClassifyItems keeps the unpaired remainder as net change", function()
  local moves, net = L().ClassifyItems(
    { bags = { [7] = 5 }, bank = {} },
    { bags = { [7] = 1 }, bank = { [7] = 3 } })
  assertEqual(moves[1].qty, 3)
  assertEqual(net[7], -1)              -- 4 left the bags, 3 landed: 1 is a loss
end)

test("Ledger: ClassifyItems ignores containers not rescanned on both sides", function()
  local moves, net = L().ClassifyItems({ bags = { [7] = 5 } }, { bags = { [7] = 2 }, bank = { [7] = 3 } })
  assertEqual(#moves, 0)
  assertEqual(net[7], -3)              -- bank had no baseline: never inferred
end)

test("Ledger: mail taken is a gain unless it was own-origin", function()
  local before = { bags = {}, mail = { [9] = 4 } }
  local after  = { bags = { [9] = 4 }, mail = {} }
  local moves, net = L().ClassifyItems(before, after, { mail = { [9] = 1 } })
  assertEqual(#moves, 1); assertEqual(moves[1].qty, 1); assertEqual(moves[1].from, "mail")
  assertEqual(net[9], 3)
end)

test("Ledger: escrow arrivals and auction exits never become net", function()
  local _, net, arrivals, exits = L().ClassifyItems(
    { mail = {}, auctions = { [3] = 2 } },
    { mail = { [5] = 1 }, auctions = {} })
  assertEqual(next(net), nil)
  assertEqual(arrivals.mail[5], 1)
  assertEqual(exits[3], 2)
end)

test("Ledger: posting bags to auctions is a MOVE", function()
  local moves, net = L().ClassifyItems({ bags = { [3] = 2 }, auctions = {} }, { bags = {}, auctions = { [3] = 2 } })
  assertEqual(moves[1].to, "auctions"); assertEqual(next(net), nil)
end)

test("Ledger: PairHolders turns a warband deposit into one pair and clears both nets", function()
  local me, wb = { ["i:7"] = -2, g = -500 }, { ["i:7"] = 2, g = 300 }
  local pairs_ = L().PairHolders("A-Realm", me, "§warband", wb)
  assertEqual(#pairs_, 2)
  assertEqual(pairs_[1].key, "g"); assertEqual(pairs_[1].qty, 300)
  assertEqual(pairs_[1].from, "A-Realm"); assertEqual(pairs_[1].to, "§warband")
  assertEqual(pairs_[2].key, "i:7"); assertEqual(pairs_[2].qty, 2)
  assertEqual(me.g, -200); assertEqual(me["i:7"], nil); assertEqual(wb.g, nil)
end)

test("Ledger: PairHolders leaves same-sign changes alone", function()
  local me, wb = { g = 10 }, { g = 5 }
  assertEqual(#L().PairHolders("A", me, "§warband", wb), 0)
  assertEqual(me.g, 10); assertEqual(wb.g, 5)
end)

test("Ledger: claims consume fully, partially, and expire", function()
  local claims, rowA, rowB = {}, {}, {}
  L().PostClaim(claims, "i:7", 3, rowA, 100)
  assertEqual(L().ClaimAvailable(claims, "i:7", 101), 3)
  local rest, matched = L().ConsumeClaim(claims, "i:7", 5, 101)
  assertEqual(rest, 2); assertTrue(matched[1] == rowA)
  assertEqual(claims["i:7"], nil)
  L().PostClaim(claims, "g", 50, rowB, 100)
  rest = L().ConsumeClaim(claims, "g", 20, 101)
  assertEqual(rest, 0); assertEqual(L().ClaimAvailable(claims, "g", 101), 30)
  assertEqual(L().ClaimAvailable(claims, "g", 100 + L().CLAIM_TTL + 1), 0)   -- expired
  L().PruneClaims(claims, 200)
  assertEqual(claims.g, nil)
end)

test("Ledger: a late claim is still consumed inside its TTL", function()
  local claims, row = {}, {}
  L().PostClaim(claims, "c:3008", 10, row, 50)
  local rest, matched = L().ConsumeClaim(claims, "c:3008", 10, 54)
  assertEqual(rest, 0); assertTrue(matched[1] == row)
end)

test("Ledger: coalesce key and the 60 s amend window", function()
  local k1 = L().CoalesceKey("A", "i:7", "OUT", "CONSUME")
  assertEqual(k1, L().CoalesceKey("A", "i:7", "OUT", "CONSUME"))
  assertTrue(k1 ~= L().CoalesceKey("A", "i:7", "OUT", "SELL"))
  assertTrue(L().CoalesceKey("A", "i:7", "MOVE", "TRANSFER", "bags>bank")
    ~= L().CoalesceKey("A", "i:7", "MOVE", "TRANSFER", "bank>bags"))
  assertTrue(L().Amendable({ ts = 1000 }, 1059))
  assertFalse(L().Amendable({ ts = 1000 }, 1060))
  assertFalse(L().Amendable(nil, 1000))
end)

test("Ledger: ShouldHold — one-sided waits 6 s, unclaimed gain waits 1.5 s", function()
  local H = L().ShouldHold
  assertFalse(H(false, false, nil, 0))
  assertTrue(H(true, false, nil, 10)); assertTrue(H(true, false, 10, 15.9)); assertFalse(H(true, false, 10, 16))
  assertTrue(H(false, true, 10, 11)); assertFalse(H(false, true, 10, 11.5))
end)

test("Ledger: Signed applies DirSign", function()
  assertEqual(L().Signed("IN", 4), 4); assertEqual(L().Signed("OUT", 4), -4); assertEqual(L().Signed("MOVE", 4), 0)
end)
