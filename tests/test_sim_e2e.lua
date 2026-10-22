local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile("tests/sim_support.lua").new(T)

-- modules/SimScenario.lua end to end (LootHistory#37; req-lh-sim.md §7 and §11.4): the DW-90
-- regression. Each scenario runs the REAL capture engine against the seeded world: the drivers fire
-- the client's events and hook calls, and every source, reason and row below is the engine's own.
--
-- The world is the mock's real SOLO answers (not in a group, not in an instance, out of combat, no
-- keystone, no loot window): only the seam's providers may answer otherwise during a session, so a
-- read that escapes the seam shows up here as a missing or wrong row. The mock's item and currency
-- answers are made the client's own for the fixture's items (tests/sim_support.lua), because the
-- simulated player reads items live.
--
-- Every scenario runs twice, once by repeated `step` and once by `run` while the clock advances,
-- and both must write exactly the rows pinned here: source or reason, direction, quantity, holder
-- and, for a move, its two ends. The quantities are the fixture's draws for seed 7, the session
-- seed every case uses (the same seed always builds the same world). This slot runs after
-- tests/test_sim_drivers.lua, with the whole addon brought up.

local Sim, Host, R = NS.Sim, NS.SimHost, NS.Reconciler
local World = Host.World

local EXPECT = {
  loot = {
    "IN GOLD x12345 KILL @me",
    "IN GOLD x9000 QUEST @me",
    "IN ITEM:219946 x1 CONTAINER @me",
    "IN ITEM:236761 x1 KILL @me",
    "IN ITEM:236761 x2 CONTAINER @me",
    "IN ITEM:237359 x3 KILL @me",
    "IN ITEM:273796 x1 QUEST @me",
    "IN ITEM:4865 x1 KILL @me",
    "OUT ITEM:279287 x1 OTHER @me",
  },
  key = {
    "IN CURRENCY:3444 x15 MPLUS @me",
    "IN ITEM:219946 x2 ROLL @me",
    "IN ITEM:236761 x3 MPLUS @me",
    "IN ITEM:237359 x2 KILL @me",
    "IN ITEM:273796 x1 BONUS_ROLL @me",
    "IN ITEM:273796 x1 KILL @me",
    "OUT ITEM:211880 x2 CONSUME @me",
  },
  vendor = {
    "IN GOLD x450 SELL @me",
    "IN ITEM:211880 x2 VENDOR @me",
    "IN ITEM:219946 x3 DISENCHANT @me",
    "OUT GOLD x18000 REPAIR @me",
    "OUT GOLD x2500 BUY @me",
    "OUT ITEM:236761 x3 SELL @me",
    "OUT ITEM:273796 x1 DECONSTRUCT @me",
    "OUT ITEM:279287 x1 DESTROY @me",
  },
  ah = {
    "IN GOLD x60000 AH_SOLD @me",
    "IN ITEM:219946 x2 AH @me",
    "MOVE ITEM:236761 x5 TRANSFER @me me/bags>me/auctions",
    "MOVE ITEM:237359 x4 TRANSFER @me me/bags>me/auctions",
    "MOVE ITEM:237359 x4 TRANSFER @me me/mail>me/bags",
    "MOVE ITEM:273796 x1 TRANSFER @me me/bags>me/auctions",
    "OUT GOLD x2000 AH_POST_FEE @me",
    "OUT GOLD x7000 AH_BUY @me",
    "OUT ITEM:236761 x5 AH_SOLD @me",
  },
  bank = {
    "IN GOLD x250000 WARBAND_DEPOSIT @§warband me/money>§warband/money",
    "IN ITEM:236761 x55 WARBAND_WITHDRAW @me §warband/tabs>me/bags",
    "IN ITEM:237359 x11 WARBAND_DEPOSIT @§warband me/bags>§warband/tabs",
    "MOVE ITEM:219946 x6 TRANSFER @me me/bags>me/bank",
    "MOVE ITEM:236761 x15 TRANSFER @me me/bags>me/bank",
    "OUT GOLD x250000 WARBAND_DEPOSIT @me me/money>§warband/money",
    "OUT ITEM:236761 x55 WARBAND_WITHDRAW @§warband §warband/tabs>me/bags",
    "OUT ITEM:237359 x11 WARBAND_DEPOSIT @me me/bags>§warband/tabs",
  },
  social = {
    "IN CURRENCY:3444 x20 CURRENCY_TRANSFER @alt me/currency>alt/currency",
    "IN ITEM:211880 x1 ALT_TRADE @me",
    "IN ITEM:236761 x4 TRADE @me",
    "OUT CURRENCY:3444 x20 CURRENCY_TRANSFER @me me/currency>alt/currency",
    "OUT GOLD x50000 ALT_MAIL @me me/money>alt/mail",
    "OUT ITEM:219946 x1 TRADE_GIVE @me",
    "OUT ITEM:236761 x2 ALT_TRADE @me",
    "OUT ITEM:237359 x11 ALT_MAIL @me me/bags>alt/mail",
  },
}

-- What the Collector alone writes with the ledger off: no diff row, no gold, no move.
local EXPECT_NO_LEDGER = {
  loot = {
    "IN ITEM:219946 x1 CONTAINER @me",
    "IN ITEM:236761 x1 KILL @me",
    "IN ITEM:236761 x2 CONTAINER @me",
    "IN ITEM:237359 x3 KILL @me",
    "IN ITEM:273796 x1 QUEST @me",
  },
  key = {
    "IN CURRENCY:3444 x15 MPLUS @me",
    "IN ITEM:219946 x2 ROLL @me",
    "IN ITEM:236761 x3 MPLUS @me",
    "IN ITEM:237359 x2 KILL @me",
    "IN ITEM:273796 x1 BONUS_ROLL @me",
    "IN ITEM:273796 x1 KILL @me",
  },
}

local function assertRows(rows, want, label)
  local exp = {}
  for i, l in ipairs(want) do exp[i] = l end
  table.sort(exp)
  assertEqual(table.concat(H.describeAll(rows), "\n"), table.concat(exp, "\n"), label .. ": the exact rows")
end

-- No change is written twice: a claim left unconsumed would write a gain once from chat and once
-- from the holdings diff. A MOVE may repeat (out to the auction house and back by mail).
local function assertNoDuplicates(rows, label)
  local by = {}
  for _, l in ipairs(H.describeAll(rows)) do
    assertFalse(by[l] ~= nil and not l:find("^MOVE"), label .. ": duplicate row " .. l)
    by[l] = true
  end
end

local function bagCounts(w, where)
  local out = {}
  for _, bag in pairs(w[where]) do
    for _, e in pairs(bag) do out[e.itemID] = (out[e.itemID] or 0) + e.count end
  end
  return out
end

-- One holder's container column against the world's counts, both ways.
local function assertColumn(entry, container, counts, label)
  for id, n in pairs(counts) do
    local row = entry.items[id]
    assertEqual(row and row[container], n, ("%s: %s holds %d of %d"):format(label, container, n, id))
  end
  for id, row in pairs(entry.items) do
    if row[container] then assertEqual(counts[id], row[container], ("%s: %s of %d"):format(label, container, id)) end
  end
end

-- The session holdings say what the world holds: the bags, the purse and the per-character
-- currencies, and the bank and the warband tabs and gold once a banker has read them.
local function assertHoldingsMatchWorld(label)
  local w = Host.world
  local e = NS.Holdings:Get(NS.Util.PlayerKey())
  assertTrue(e ~= nil and e.meta.genesis ~= nil, label .. ": the session holds the player, with a genesis")
  assertColumn(e, "bags", bagCounts(w, "bags"), label)
  if e.scanned.bank then assertColumn(e, "bank", bagCounts(w, "bank"), label) end
  assertEqual(e.money, w.money, label .. ": the purse")
  for _, c in ipairs(w.currencies) do
    if not c.accountWide then assertEqual(e.currency[c.id], c.quantity, label .. ": currency " .. c.id) end
  end
  local we = NS.Holdings:Get(NS.Constants.WARBAND_HOLDER)
  if we and we.scanned.tabs then assertColumn(we, "tabs", bagCounts(w, "tabs"), label) end
  if we and we.scanned.money then assertEqual(we.money, w.warbandMoney, label .. ": the warband gold") end
end

-- The History window under the DEFAULT view (the stock view: this character, the quality floor,
-- every direction) shows every session row of this character at or above the floor, and no other.
local function assertBrowserShows(rows, label)
  NS.Browser:ApplyView(nil)
  local shown, n = {}, 0
  for _, entry in ipairs(NS.BrowserTable:BuildDisplayList()) do
    if entry.kind == "row" then shown[entry.record] = true; n = n + 1 end
  end
  local me, floor = NS.Util.PlayerKey(), NS.db.profile.settings.qualityThreshold or 0
  local want = 0
  for _, r in ipairs(rows) do
    local poor = NS.Util.RowKind(r) == "ITEM" and (r.quality or 0) < floor
    if NS.Util.RowHolder(r) == me and not poor then
      want = want + 1
      assertTrue(shown[r], label .. ": the History window shows " .. H.describe(r))
    end
  end
  assertTrue(want > 0, label .. ": something to show")
  assertEqual(n, want, label .. ": the History window shows exactly this character's rows")
end

local function find(rows, line)
  for _, r in ipairs(rows) do if H.describe(r) == line then return r end end
  error("no row " .. line, 2)
end

-- Per scenario, what the rows' details and the engine's state say once it has run.
local CHECKS = {
  loot = function(rows)
    local junk = find(rows, "IN ITEM:4865 x1 KILL @me")
    assertTrue(junk.claimed == nil and junk.kind == "ITEM",
      "loot: the gated poor item is a Reconciler diff row, never a Collector row")
    for _, line in ipairs({ "IN ITEM:236761 x1 KILL @me", "IN ITEM:237359 x3 KILL @me", "IN GOLD x12345 KILL @me" }) do
      local r = find(rows, line)
      assertTrue(r.claimed, "loot: " .. line .. " is the chat row, claimed by its holdings delta")
      assertEqual(r.sourceDetail and r.sourceDetail.npcID, 219000, "loot: " .. line .. " carries the npcID")
    end
    assertEqual(find(rows, "IN ITEM:273796 x1 QUEST @me").sourceDetail.questID, 84000, "loot: the quest id")
  end,
  key = function(rows)
    for _, line in ipairs({ "IN ITEM:273796 x1 KILL @me", "IN ITEM:237359 x2 KILL @me" }) do
      local d = find(rows, line).sourceDetail
      assertTrue(d and (d.encounterID == 2847 or d.encounterID == 2835) and d.difficulty == 8,
        "key: " .. line .. " carries its encounter")
    end
    for _, line in ipairs({ "IN ITEM:236761 x3 MPLUS @me", "IN CURRENCY:3444 x15 MPLUS @me" }) do
      assertEqual(find(rows, line).sourceDetail.keystoneLevel, 10, "key: " .. line .. " carries the keystone")
    end
    local C = NS.Constants.Confidence.CERTAIN
    assertEqual(find(rows, "IN ITEM:273796 x1 BONUS_ROLL @me").confidence, C, "key: the bonus roll is CERTAIN")
    assertEqual(find(rows, "IN ITEM:219946 x2 ROLL @me").confidence, C, "key: the won roll is CERTAIN")
    assertEqual(NS.State.keystone, nil, "key: the keystone context is cleared after the zone-out")
  end,
  bank = function()
    local we = NS.Holdings:Get(NS.Constants.WARBAND_HOLDER)
    assertTrue(we.meta.genesis ~= nil and we.meta.partial == false, "bank: the warband's genesis, complete once read")
    assertEqual(NS.Holdings:Get(NS.Util.PlayerKey()).meta.partial, false, "bank: the character is complete once read")
  end,
  social = function(rows)
    local alt = NS.Holdings:Get(Host.alt)
    local ore = World.ITEMS.ore.id
    assertEqual(alt.items[ore] and alt.items[ore].mail, 11, "social: the alt's mail is credited the sent stack")
    assertEqual(alt.escrow.mailAlt[ore], 11, "social: ...as alt mail")
    assertEqual(alt.escrow.mailMoney, 50000, "social: and the sent gold")
    local out = find(rows, "OUT CURRENCY:3444 x20 CURRENCY_TRANSFER @me me/currency>alt/currency")
    local into = find(rows, "IN CURRENCY:3444 x20 CURRENCY_TRANSFER @alt me/currency>alt/currency")
    assertTrue(out.pairId ~= nil and out.pairId == into.pairId, "social: the transfer's two rows are one pair")
  end,
}

local function playScenario(name, mode)
  H.run(name, mode, function(rows)
    local label = name .. " by " .. mode
    assertTrue(H.settled(), label .. ": ends on a settled ledger")
    assertTrue(NS.Database:ActiveHistory() == NS.SimStores.history, label .. ": ActiveHistory serves the session log")
    assertTrue(NS.Holdings:ActiveStore() == NS.SimStores.holdings, label .. ": Holdings:ActiveStore serves the session")
    assertRows(rows, EXPECT[name], label)
    assertNoDuplicates(rows, label)
    assertHoldingsMatchWorld(label)
    assertBrowserShows(rows, label)
    if CHECKS[name] then CHECKS[name](rows) end
  end)
end

for _, name in ipairs({ "loot", "key", "vendor", "ah", "bank", "social" }) do
  for _, mode in ipairs({ "step", "run" }) do
    test(("SimScenario: %s by %s writes exactly its rows, no duplicates, holdings as the world"):format(name, mode),
      function() playScenario(name, mode) end)
  end
end

test("SimScenario: the six scenarios, in order, each a pure timeline of labeled, tipped steps", function()
  local sc = Host.SCENARIOS
  assertEqual(table.concat(sc.names, ","), "loot,key,vendor,ah,bank,social")
  for _, name in ipairs(sc.names) do
    local def = sc.defs[name]
    local a, b = def.timeline(def, { scenario = name, seed = 0 }), def.timeline(def, { scenario = name, seed = 1 })
    assertTrue(#a > 0 and #a == #b, name .. ": the same steps whatever the seed")
    assertTrue(a[1] ~= b[1] and a[1].calls ~= b[1].calls, name .. ": fresh step tables every call")
    for i, s in ipairs(a) do
      assertTrue(type(s.kind) == "string" and type(s.label) == "string" and s.label ~= "", name .. " step " .. i)
      assertTrue(type(s.tip) == "table" and #s.tip > 0, name .. " step " .. i .. " says what it injects")
      assertTrue(type(s.calls) == "table" and #s.calls > 0, name .. " step " .. i .. " drives something")
    end
  end
end)

test("SimScenario: key: the potion drunk in combat waits for the regen edge, and the gate stays open", function()
  local deferredSeen = 0
  H.run("key", "step", function(rows) assertRows(rows, EXPECT.key, "key") end, {
    afterStep = function(_, s)
      if s.kind ~= "pull" then return end
      H.advance(1)
      assertTrue(R.deferred == true, "the flush ran in simulated combat and was deferred")
      assertTrue(Host.Gate(), "a deferral the simulated combat holds does not close the gate")
      deferredSeen = deferredSeen + 1
    end,
  })
  assertEqual(deferredSeen, 2, "both pulls deferred their flush")
end)

test("SimScenario: the gate: Step while it is closed prints settling and does not advance; Run polls and resumes",
function()
  H.withClient(function()
    H.withQueue(function()
      H.settle()
      assertTrue(Sim:Start({ scenario = "loot", seed = 7 }))
      local ok, err = pcall(function()
        assertTrue(Sim:Step() ~= nil, "the first step plays")
        assertFalse(Host.Gate(), "the kill's flush fuse holds the gate")
        M.__resetPrinted()
        local played, code = Sim:Step()
        assertEqual(played, nil)
        assertEqual(code, "settling")
        assertEqual(Sim:Status().pos, 1, "the step did not advance")
        local line = table.concat(M.__printed(), " | ")
        assertTrue(line:find("settling", 1, true) ~= nil, "the gate's line printed: " .. line)
        assertTrue(Sim:Run(), "Run starts while the gate is closed")
        assertEqual(Sim:Status().pos, 1, "Run polls without advancing")
        for _ = 1, 400 do
          local st = Sim:Status()
          if st.pos == st.total and not st.playing then break end
          H.advance(0.25)
        end
        assertEqual(Sim:Status().pos, Sim:Status().total, "Run resumed once the ledger settled and played to the end")
      end)
      Sim:Stop("stop")
      H.settle()
      if not ok then error(err, 0) end
    end)
  end)
end)

test("SimScenario: the gate is closed by a pending flush, a settle hold and an out-of-combat deferral", function()
  H.settle()
  assertTrue(Host.Gate(), "nothing in flight: open")
  R._pending = {}
  assertFalse(Host.Gate(), "a flush fuse")
  R._pending, R._holdSince = nil, 1
  local open, line = Host.Gate()
  assertFalse(open, "a settle hold")
  assertTrue(type(line) == "string" and line:find("settling", 1, true) ~= nil, "with its line")
  R._holdSince, R.deferred = nil, true
  assertFalse(Host.Gate(), "a combat deferral with no simulated combat")
  H.settle()
end)

test("SimScenario: with gains and losses off the ledger scenarios refuse, and loot and key run on the Collector",
function()
  H.withQueue(function() NS.Schema:Set("settings.trackLedger", false) end)
  local ok, err = pcall(function()
    for _, name in ipairs({ "vendor", "ah", "bank", "social" }) do
      H.withQueue(function()
        H.settle()
        M.__resetPrinted()
        local started, line = Sim:Start({ scenario = name })
        assertFalse(started, name .. " refuses with the ledger off")
        assertEqual(line, "These steps record through the ledger, so turn on gains and losses first.")
        assertFalse(Sim:IsActive())
      end)
    end
    for _, name in ipairs({ "loot", "key" }) do
      for _, mode in ipairs({ "step", "run" }) do
        H.run(name, mode, function(rows)
          assertRows(rows, EXPECT_NO_LEDGER[name], name .. " by " .. mode .. " with the ledger off")
        end)
      end
    end
  end)
  H.withQueue(function() NS.Schema:Set("settings.trackLedger", true) end)
  H.settle()
  if not ok then error(err, 0) end
end)
