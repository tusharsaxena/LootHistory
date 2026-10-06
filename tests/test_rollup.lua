local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- The daily rollup writer (modules/Rollup.lua): closes arrive from NS.Holdings' write methods, in /
-- out tallies from NS.Database's write hook. Every case leaves shared state as it found it: the
-- holdings and daily stores are put back at the end of the suite, and so is the write hook (the
-- harness does not stand the addon up before test_disabled, so the hook is normally off here).

local savedDaily, savedHoldings = NS.db.global.daily, NS.db.global.holdings
local hookAtEntry = NS.Rollup and NS.Rollup._hook

local T0 = os.time({ year = 2026, month = 10, day = 3, hour = 12 })
local function day(ts) return os.date("%Y-%m-%d", ts) end
local function reset() NS.db.global.daily, NS.db.global.holdings = {}, {} end
local function cell(ts, holder, key)
  local d = NS.db.global.daily[day(ts)]
  return d and d[holder] and d[holder][key]
end

test("Rollup: a holdings change writes that day's close for the thing that moved", function()
  reset()
  NS.Holdings:ApplyContainer("A-R", "bags", { [7] = 5 }, {}, T0)
  NS.Holdings:ApplyContainer("A-R", "bank", { [7] = 10 }, {}, T0 + 60)
  assertEqual(cell(T0, "A-R", "i:7").c, 15, "close = total across containers, after the write")
end)

test("Rollup: an unchanged thing writes no cell", function()
  reset()
  NS.Holdings:ApplyContainer("A-R", "bags", { [7] = 5, [8] = 1 }, {}, T0)
  NS.db.global.daily = {}
  NS.Holdings:ApplyContainer("A-R", "bags", { [7] = 4, [8] = 1 }, {}, T0 + 86400)
  assertEqual(cell(T0 + 86400, "A-R", "i:7").c, 4)
  assertEqual(cell(T0 + 86400, "A-R", "i:8"), nil)
end)

test("Rollup: a thing leaving every container closes at 0", function()
  reset()
  NS.Holdings:ApplyContainer("A-R", "bags", { [7] = 5 }, {}, T0)
  NS.Holdings:ApplyContainer("A-R", "bags", {}, {}, T0 + 5)
  assertEqual(cell(T0, "A-R", "i:7").c, 0)
end)

test("Rollup: currency and money changes write closes", function()
  reset()
  NS.Holdings:ApplyCurrency("A-R", { [3008] = 40, [2245] = 1 }, T0)
  NS.Holdings:ApplyCurrency("A-R", { [3008] = 55 }, T0 + 1)
  NS.Holdings:ApplyMoney("A-R", 12345, T0 + 2)
  assertEqual(cell(T0, "A-R", "c:3008").c, 55)
  assertEqual(cell(T0, "A-R", "c:2245").c, 0, "a currency that left the map closes at 0")
  assertEqual(cell(T0, "A-R", "g").c, 12345)
end)

test("Rollup: the write hook tallies gains and losses; transfers tally nothing", function()
  reset()
  local R = NS.Rollup
  R:OnWrite({ ts = T0, dir = "IN", kind = "GOLD", holder = "A-R", quantity = 500 }, 500, true)
  R:OnWrite({ ts = T0, dir = "OUT", kind = "GOLD", holder = "A-R", quantity = 200 }, 200, true)
  R:OnWrite({ ts = T0, dir = "MOVE", kind = "GOLD", holder = "A-R", quantity = 999,
    from = "A-R/money", to = "§warband/money" }, 999, true)
  R:OnWrite({ ts = T0, itemID = 7, quantity = 3, char = "A-R" }, 3, true)   -- a legacy-shaped chat row
  assertEqual(cell(T0, "A-R", "g").i, 500); assertEqual(cell(T0, "A-R", "g").o, 200)
  assertEqual(cell(T0, "A-R", "i:7").i, 3)
end)

test("Rollup: an amend tallies only its delta, on the day it happens", function()
  reset()
  if not NS.Rollup._hook then NS.Rollup:Enable() end
  local h = NS.db.global.history
  local n = #h
  local now = os.time()   -- the addon's `time` is the mock's os.time; suites see no `time` global
  local idx = NS.Database:Add({ ts = now, dir = "OUT", kind = "ITEM", itemID = 9, holder = "A-R", quantity = 2 })
  NS.Database:Amend(idx, 3)
  assertEqual(cell(now, "A-R", "i:9").o, 5, "2 from the row plus 3 from the amend -- never 2 + 5")
  for i = #h, n + 1, -1 do h[i] = nil end
end)

test("Rollup: the gate container's first scan after genesis ends the partial window", function()
  reset()
  NS.Holdings:ApplyContainer("A-R", "bags", { [7] = 1 }, {}, T0)
  NS.Holdings:MarkGenesis("A-R", T0)
  assertTrue(NS.Holdings:Get("A-R").meta.partial)
  NS.Holdings:ApplyContainer("A-R", "bank", { [7] = 2 }, {}, T0 + 500)
  local m = NS.Holdings:Get("A-R").meta
  assertFalse(m.partial); assertEqual(m.completeAt, T0 + 500)
  NS.Holdings:ApplyContainer("A-R", "bank", { [7] = 3 }, {}, T0 + 900)
  assertEqual(NS.Holdings:Get("A-R").meta.completeAt, T0 + 500, "set once")
end)

test("Rollup: the warband's gate is its tabs", function()
  reset()
  NS.Holdings:ApplyMoney("§warband", 10, T0)
  NS.Holdings:MarkGenesis("§warband", T0)
  NS.Holdings:ApplyContainer("§warband", "tabs", { [7] = 1 }, {}, T0 + 10)
  assertEqual(NS.Holdings:Get("§warband").meta.completeAt, T0 + 10)
end)

test("Rollup: wired through the write hook - Database:Add reaches the tally", function()
  reset()
  if not NS.Rollup._hook then NS.Rollup:Enable() end
  local h = NS.db.global.history
  local n = #h
  NS.Database:Add({ ts = T0, dir = "IN", kind = "GOLD", holder = "A-R", quantity = 9, itemName = "Gold" })
  assertEqual(cell(T0, "A-R", "g").i, 9)
  h[n + 1] = nil
end)

test("Rollup: Keys indexes every thing in the rollup and learns new ones", function()
  reset()
  NS.Rollup._keys = nil
  NS.Holdings:ApplyMoney("A-R", 1, T0)
  local k = NS.Rollup:Keys()
  assertTrue(k.g)
  NS.Holdings:ApplyCurrency("A-R", { [3008] = 1 }, T0)
  assertTrue(NS.Rollup:Keys()["c:3008"], "a new key joins the cached index")
end)

test("Rollup: escrow and currency credits write closes too (Phase 2's direct holdings writes)", function()
  reset()
  NS.Holdings:ApplyContainer("Alt-R", "bags", { [7] = 1 }, {}, T0)
  NS.Holdings:ApplyCurrency("Alt-R", { [3008] = 10 }, T0)
  NS.db.global.daily = {}
  NS.Holdings:CreditEscrow("Alt-R", "mail", 7, 4)
  NS.Holdings:CreditCurrency("Alt-R", 3008, 5)
  local today = os.time()
  assertEqual(cell(today, "Alt-R", "i:7").c, 5)
  assertEqual(cell(today, "Alt-R", "c:3008").c, 15)
end)

test("Rollup: Disable removes the write hook", function()
  reset()
  NS.Rollup:Disable()
  local h = NS.db.global.history
  local n = #h
  NS.Database:Add({ ts = T0, dir = "IN", kind = "GOLD", holder = "A-R", quantity = 9 })
  assertEqual(cell(T0, "A-R", "g"), nil)
  h[n + 1] = nil
  NS.Rollup:Enable()
end)

test("Rollup: ForgetHolder drops every cell of that holder", function()
  reset()
  NS.Holdings:ApplyMoney("A-R", 1, T0); NS.Holdings:ApplyMoney("B-R", 2, T0)
  assertEqual(NS.Rollup:ForgetHolder("A-R"), 1)
  assertEqual(cell(T0, "A-R", "g"), nil); assertEqual(cell(T0, "B-R", "g").c, 2)
end)

test("Holdings: Describe names a thing by key, Gold included", function()
  reset()
  assertEqual(NS.Holdings:Describe("g").name, "Gold")
  NS.Holdings:ApplyContainer("A-R", "bags", { [7] = 1 }, { [7] = "|Hitem:7|h[Apple]|h" }, T0)
  assertTrue(type(NS.Holdings:Describe("i:7").name) == "string")
end)

-- ── retention, the login prune and the one-time seed ─────────────────────────────────────────

test("Rollup: Prune with Always (0) keeps every day", function()
  reset()
  NS.db.global.daily = { ["2020-01-01"] = { ["A-R"] = { g = { c = 1 } } } }
  NS.db.global.rollupRetentionDays = 0
  assertEqual(NS.Rollup:Prune(T0), 0)
  assertTrue(NS.db.global.daily["2020-01-01"] ~= nil)
end)

test("Rollup: Prune drops days past the retention and carries their closes", function()
  reset()
  NS.db.global.daily = {
    [day(T0 - 400 * 86400)] = { ["A-R"] = { g = { c = 5 } } },
    [day(T0 - 10 * 86400)] = { ["A-R"] = { ["i:7"] = { c = 1 } } },
  }
  NS.db.global.rollupRetentionDays = 365
  assertEqual(NS.Rollup:Prune(T0), 1)
  local cutoff = day(T0 - 365 * 86400)
  assertEqual(NS.db.global.daily[cutoff]["A-R"].g.c, 5)
  NS.db.global.rollupRetentionDays = 0
end)

test("Rollup: SeedOnce writes today's close for every held thing, once per account", function()
  reset()
  NS.db.global.rollupSeeded = nil
  NS.db.global.holdings = { ["A-R"] = { meta = {}, scanned = {}, links = {},
    items = { [7] = { bags = 2, bank = 3 } }, currency = { [3008] = 4 }, money = 99 } }
  local n = NS.Rollup:SeedOnce(T0)
  assertEqual(n, 3)
  assertEqual(cell(T0, "A-R", "i:7").c, 5); assertEqual(cell(T0, "A-R", "c:3008").c, 4)
  assertEqual(cell(T0, "A-R", "g").c, 99)
  assertEqual(NS.db.global.rollupSeeded, T0)
  assertEqual(NS.Rollup:SeedOnce(T0 + 86400), 0, "the second call is a no-op")
  NS.db.global.rollupSeeded = nil
end)

test("Rollup: SeedOnce never overwrites a close already written today", function()
  reset()
  NS.db.global.rollupSeeded = nil
  NS.db.global.holdings = { ["A-R"] = { meta = {}, scanned = {}, links = {}, items = {}, currency = {}, money = 99 } }
  NS.Rollup:NoteClose("A-R", "g", T0, 42)
  NS.Rollup:SeedOnce(T0)
  assertEqual(cell(T0, "A-R", "g").c, 42)
  NS.db.global.rollupSeeded = nil
end)

test("Schema: rollupRetentionDays is account-wide, defaults to Always and is reset-exempt", function()
  local S = NS.Schema
  local row = S:FindRow("settings.rollupRetentionDays")
  assertTrue(row ~= nil)
  assertEqual(row.default, 0); assertEqual(row.group, "History")
  S:Set("settings.rollupRetentionDays", 365)
  assertEqual(NS.db.global.rollupRetentionDays, 365)
  assertEqual(NS.db.profile.settings.rollupRetentionDays, nil, "never stored per profile")
  assertEqual(S.RESET_EXEMPT["settings.rollupRetentionDays"], "rollupRetentionDays")
  S:Set("settings.rollupRetentionDays", 0)
end)

-- The v13 step's rebuild (core/Ledger.lua RecomputeFlows): a touched cell's tallies are re-summed
-- from the rows, so a stale tally is replaced, not added to; MOVE rows count nothing.
test("Rollup: RecomputeFlows rebuilds only the touched cells from IN / OUT rows, closes untouched", function()
  -- red under: a rebuild that adds to the stored tally instead of replacing it (i would read 9).
  local D = day(T0)
  local daily = { [D] = { ["A-R"] = { ["i:7"] = { c = 3, i = 4, o = 2 }, ["g"] = { i = 50 } } } }
  local rows = {
    { ts = T0, holder = "A-R", dir = "IN", kind = "ITEM", itemID = 7, quantity = 5 },
    { ts = T0 + 1, holder = "A-R", dir = "MOVE", kind = "ITEM", itemID = 7, quantity = 8 },
    { ts = T0 + 2, holder = "B-R", dir = "OUT", kind = "ITEM", itemID = 7, quantity = 1 },
    { ts = T0 + 86400, holder = "A-R", dir = "OUT", kind = "ITEM", itemID = 7, quantity = 6 },
  }
  local n = NS.Ledger.RecomputeFlows(daily, rows, { [D] = { ["A-R"] = { ["i:7"] = true } } })
  assertEqual(n, 1)
  local c = daily[D]["A-R"]["i:7"]
  assertEqual(c.i, 5); assertEqual(c.o, nil); assertEqual(c.c, 3)
  assertEqual(daily[D]["A-R"].g.i, 50, "an untouched thing keeps its tally")
  assertEqual(daily[day(T0 + 86400)], nil, "another day is not written")
end)

-- Not a behavior case: puts the stores, the key index and the write hook back the way this suite
-- found them, so the suites after it see no rollup state of this file's making.
test("Rollup: the suite restores the shared state it changed", function()
  NS.db.global.daily, NS.db.global.holdings = savedDaily, savedHoldings
  NS.Rollup._keys = nil
  if hookAtEntry then
    if not NS.Rollup._hook then NS.Rollup:Enable() end
  else
    NS.Rollup:Disable()
  end
  assertEqual(NS.Rollup._hook ~= nil, hookAtEntry ~= nil and hookAtEntry ~= false)
end)
