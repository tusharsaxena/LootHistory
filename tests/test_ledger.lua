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

local function ctx(t)
  t.now = t.now or 100
  t.scopes = t.scopes or {}
  return t
end

test("Ledger: PickReason — forced wins (login drift)", function()
  assertEqual(L().PickReason("ITEM", "OUT", ctx({ forced = "UNTRACKED", scopes = { merchant = true } })), "UNTRACKED")
end)

test("Ledger: PickReason — a fresh outbound stamp beats scopes, filtered by kind/dir", function()
  local c = ctx({ out = { reason = "REPAIR", expires = 101, kinds = { GOLD = true }, dirs = { OUT = true } },
                  scopes = { merchant = true } })
  assertEqual(L().PickReason("GOLD", "OUT", c), "REPAIR")
  assertEqual(L().PickReason("ITEM", "OUT", c), "SELL")        -- stamp is gold-only
  c.out.expires = 99
  assertEqual(L().PickReason("GOLD", "OUT", c), "BUY")         -- stale stamp: merchant scope
end)

test("Ledger: PickReason — merchant scope", function()
  local c = ctx({ scopes = { merchant = true } })
  assertEqual(L().PickReason("ITEM", "OUT", c), "SELL")
  assertEqual(L().PickReason("GOLD", "IN", c), "SELL")
  assertEqual(L().PickReason("GOLD", "OUT", c), "BUY")
  assertEqual(L().PickReason("ITEM", "IN", c), "VENDOR")
end)

test("Ledger: PickReason — guild bank is outside the account", function()
  local c = ctx({ scopes = { guildBank = true, merchant = true } })
  assertEqual(L().PickReason("ITEM", "OUT", c), "GUILD_DEPOSIT")
  assertEqual(L().PickReason("GOLD", "IN", c), "GUILD_WITHDRAW")
end)

test("Ledger: PickReason — gold-out scopes", function()
  assertEqual(L().PickReason("GOLD", "OUT", ctx({ scopes = { trainer = true } })), "TRAINING")
  assertEqual(L().PickReason("GOLD", "OUT", ctx({ scopes = { taxi = true } })), "TRAVEL")
  assertEqual(L().PickReason("GOLD", "OUT", ctx({ scopes = { auction = true } })), "AH_POST_FEE")
  assertEqual(L().PickReason("GOLD", "OUT", ctx({ scopes = { mailbox = true } })), "MAIL_SEND")
end)

test("Ledger: PickReason — item losses by inference", function()
  assertEqual(L().PickReason("ITEM", "OUT", ctx({ loot = { source = "DISENCHANT", expires = 101 } })), "DECONSTRUCT")
  assertEqual(L().PickReason("ITEM", "OUT", ctx({ craftUntil = 105 })), "CRAFT_REAGENT")
  assertEqual(L().PickReason("ITEM", "OUT", ctx({ consumable = true })), "CONSUME")
  assertEqual(L().PickReason("ITEM", "OUT", ctx({})), "OTHER")
end)

test("Ledger: PickReason — gains read the inbound loot stamp, then mailbox/AH scope", function()
  assertEqual(L().PickReason("ITEM", "IN", ctx({ loot = { source = "KILL", expires = 101 } })), "KILL")
  assertEqual(L().PickReason("ITEM", "IN", ctx({ scopes = { mailbox = true } })), "MAIL")
  assertEqual(L().PickReason("ITEM", "IN", ctx({ scopes = { auction = true } })), "AH")
  assertEqual(L().PickReason("CURRENCY", "IN", ctx({})), "OTHER")
end)

test("Ledger: PickReason — currency source names map before scopes", function()
  assertEqual(L().PickReason("CURRENCY", "OUT", ctx({ currencySrc = "CRAFT_REAGENT", scopes = { merchant = true } })),
    "CRAFT_REAGENT")
end)

test("Ledger: CurrencyReason maps known enum member names, nil otherwise", function()
  assertEqual(L().CurrencyReason("Vendor", "OUT"), "BUY")
  assertEqual(L().CurrencyReason("QuestReward", "IN"), "QUEST")
  assertEqual(L().CurrencyReason("AccountTransfer", "OUT"), "TRANSFER")
  assertEqual(L().CurrencyReason("NoSuchMember", "IN"), nil)
  assertEqual(L().CurrencyReason(nil, "IN"), nil)
end)

-- ── daily rollup cells (timeline ledger P3, spec §4.3) ───────────────────────────────────────

test("Ledger: DayKey is the local calendar day and sorts chronologically", function()
  local late = os.time({ year = 2026, month = 10, day = 6, hour = 23, min = 59 })
  assertEqual(NS.Ledger.DayKey(late), "2026-10-06")
  assertTrue(NS.Ledger.DayKey(late) < NS.Ledger.DayKey(late + 120), "string order is day order")
end)

test("Ledger: RowThingKey covers items, currencies, gold and legacy rows", function()
  local LG = NS.Ledger
  assertEqual(LG.RowThingKey({ itemID = 7 }), "i:7")                       -- legacy loot row
  assertEqual(LG.RowThingKey({ currencyID = 3008 }), "c:3008")
  assertEqual(LG.RowThingKey({ kind = "GOLD", quantity = 5 }), "g")
  assertEqual(LG.RowThingKey({ kind = "ITEM" }), nil)                       -- no id, no thing
end)

test("Ledger: RollupClose overwrites the day's close; RollupFlow accumulates by direction", function()
  local d, LG = {}, NS.Ledger
  LG.RollupClose(d, "2026-10-06", "A-R", "g", 100)
  LG.RollupClose(d, "2026-10-06", "A-R", "g", 120)
  LG.RollupFlow(d, "2026-10-06", "A-R", "g", "IN", 30)
  LG.RollupFlow(d, "2026-10-06", "A-R", "g", "IN", 5)
  LG.RollupFlow(d, "2026-10-06", "A-R", "g", "OUT", 10)
  local c = d["2026-10-06"]["A-R"].g
  assertEqual(c.c, 120); assertEqual(c.i, 35); assertEqual(c.o, 10)
end)

test("Ledger: a MOVE or a zero flow creates no cell (the rollup stays sparse)", function()
  local d = {}
  NS.Ledger.RollupFlow(d, "2026-10-06", "A-R", "g", "MOVE", 99)
  NS.Ledger.RollupFlow(d, "2026-10-06", "A-R", "g", "IN", 0)
  assertEqual(next(d), nil)
end)

test("Ledger: PruneDaily drops old days and folds each thing's last close onto the cutoff day", function()
  -- Review Focus 3
  local d = {
    ["2026-01-01"] = { ["A-R"] = { g = { c = 10, i = 10 }, ["i:7"] = { c = 3 } } },
    ["2026-02-01"] = { ["A-R"] = { g = { c = 40 } } },
    ["2026-06-01"] = { ["A-R"] = { ["i:7"] = { c = 9 } } },
  }
  assertEqual(NS.Ledger.PruneDaily(d, "2026-05-01"), 2)
  assertEqual(d["2026-01-01"], nil); assertEqual(d["2026-02-01"], nil)
  assertEqual(d["2026-05-01"]["A-R"].g.c, 40, "the newest pruned close is the one carried")
  assertEqual(d["2026-05-01"]["A-R"].g.i, nil, "flows are history, not state: never carried")
  assertEqual(d["2026-05-01"]["A-R"]["i:7"].c, 3, "carried to the cutoff even though June has a close")
  assertEqual(d["2026-06-01"]["A-R"]["i:7"].c, 9, "days at or after the cutoff are untouched")
end)

test("Ledger: PruneDaily never overwrites a close already on the cutoff day", function()
  local d = {
    ["2026-01-01"] = { ["A-R"] = { g = { c = 10 } } },
    ["2026-05-01"] = { ["A-R"] = { g = { c = 77, o = 3 } } },
  }
  NS.Ledger.PruneDaily(d, "2026-05-01")
  assertEqual(d["2026-05-01"]["A-R"].g.c, 77); assertEqual(d["2026-05-01"]["A-R"].g.o, 3)
end)

test("Ledger: PruneDaily with nothing old is a no-op", function()
  local d = { ["2026-06-01"] = { ["A-R"] = { g = { c = 1 } } } }
  assertEqual(NS.Ledger.PruneDaily(d, "2026-05-01"), 0)
  assertEqual(d["2026-05-01"], nil)
end)

test("Ledger: ForgetHolderDaily removes a holder's cells and days it leaves empty", function()
  local d = {
    ["2026-10-01"] = { ["A-R"] = { g = { c = 1 }, ["i:7"] = { c = 2 } } },
    ["2026-10-02"] = { ["A-R"] = { g = { c = 3 } }, ["B-R"] = { g = { c = 4 } } },
  }
  assertEqual(NS.Ledger.ForgetHolderDaily(d, "A-R"), 3)
  assertEqual(d["2026-10-01"], nil)
  assertEqual(d["2026-10-02"]["A-R"], nil); assertEqual(d["2026-10-02"]["B-R"].g.c, 4)
end)
