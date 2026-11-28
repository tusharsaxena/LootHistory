local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local H = dofile("tests/sim_support.lua").new(T)

-- The simulator's saved-data invariant (LootHistory#37; Ka0sAddonsCommonTasks req-lh-sim.md §4 and §11.3, the host
-- contract's H4): a whole session of every scenario, played to the end and stopped, leaves the
-- saved stores -- NS.db.global.history, .holdings, .daily and .farm (#39) -- byte-identical to what they were
-- before it started. Every capture-path write resolved to the session's own stores; the maintenance
-- paths that read NS.db.global directly (the storage figures, the retention count) went on reading
-- the saved ones the whole time. This slot runs after tests/test_sim_e2e.lua, with the whole addon
-- brought up.

local function snapshot()
  local g = NS.db.global
  return { history = H.serialize(g.history or {}), holdings = H.serialize(g.holdings or {}),
           daily = H.serialize(g.daily or {}), farm = H.serialize(g.farm or {}) }
end

-- Something real in each saved store, so "unchanged" is a claim about data and not about nothing.
-- Answers the undo, which takes out only what it added.
local REAL, DAY = "Realalt-Realm", "2026-01-01"
local function seedLive()
  local g = NS.db.global
  if #(g.history or {}) == 0 then T.seedDatabase() end
  g.holdings, g.daily, g.farm = g.holdings or {}, g.daily or {}, g.farm or {}
  local addH, addD, addF = g.holdings[REAL] == nil, g.daily[DAY] == nil, g.farm[REAL] == nil
  if addH then
    g.holdings[REAL] = { meta = { genesis = 1 }, scanned = {}, items = { [2589] = { bags = 7 } },
      currency = {}, links = {} }
  end
  if addD then g.daily[DAY] = { [REAL] = { g = { c = 100 } } } end
  if addF then
    g.farm[REAL] = { nextId = 2, sessions = { { v = 1, id = 1, name = "Isle of Dorn", startedAt = 1795000000,
      endedAt = 1795003600, activeSec = 3000, log = { "10|m|500|KILL" }, totals = { money = 500, vendor = 0,
      ah = 0, costs = 0 } } } }
  end
  return function()
    if addH then g.holdings[REAL] = nil end
    if addD then g.daily[DAY] = nil end
    if addF then g.farm[REAL] = nil end
  end
end

-- The `key` scenario is the keystone's (R2): a declared skip on WoW Forever.
for _, name in ipairs({ "loot", "key", "vendor", "ah", "bank", "social" }) do
  test(("SimStore: %s: the saved history, holdings, daily and farm are byte-identical before start and after stop"):format(name),
  function()
    local unseed = seedLive()
    local before = snapshot()
    local liveCount = #NS.db.global.history
    local ok, sessionRows = pcall(H.run, name, "run", function(rows)
      -- Mid-session: the capture path wrote the session, and the maintenance paths read the saved store.
      assertTrue(NS.Database:History() == NS.SimStores.history, name .. ": the history accessor is the session's")
      assertTrue(NS.Holdings:Store() == NS.SimStores.holdings, name .. ": Holdings:Store is the session's")
      assertTrue(NS.Rollup:Store() == NS.SimStores.daily, name .. ": Rollup:Store is the session's")
      assertEqual(NS.Database:StorageStats().count, liveCount, name .. ": StorageStats counts the saved history")
      -- A cutoff a day ahead counts every row of the store it reads: the saved one, not the session's.
      assertEqual(NS.Database:CountOlderThan(-1), liveCount, name .. ": CountOlderThan reads the saved history")
      assertEqual(#NS.db.global.history, liveCount, name .. ": no row reached the saved history")
      assertTrue(next(NS.SimStores.daily) ~= nil, name .. ": the session's rows reached the session's daily")
      return #rows
    end)
    if not ok then unseed(); error(sessionRows, 0) end
    assertTrue(sessionRows > 0, name .. ": the session wrote rows")
    local after = snapshot()
    assertEqual(after.history, before.history, name .. ": db.global.history")
    assertEqual(after.holdings, before.holdings, name .. ": db.global.holdings")
    assertEqual(after.daily, before.daily, name .. ": db.global.daily")
    assertEqual(after.farm, before.farm, name .. ": db.global.farm")
    assertEqual(NS.SimStores.history, nil, name .. ": the session stores are released")
    assertTrue(NS.Database:History() == NS.db.global.history, name .. ": the accessors read the saved store again")
    unseed()
  end, name == "key" and T.RETAIL_ONLY or nil)
end

test("SimStore: a farm session opened during a simulation tallies into SimStores.farm only, released at stop", function()
  -- #39, farm spec §12.2: `/lh farm start` during a sim opens a simulated session, every write
  -- resolves to the session store, and the stop drops it unsaved.
  local unseed = seedLive()
  local before = snapshot().farm
  local ok, lines = pcall(H.run, "loot", "step", function()
    local F, me = NS.Farm, NS.Util.PlayerKey()
    local s = F:Active()
    assertTrue(s ~= nil, "the sim farm session is open")
    assertTrue(NS.SimStores.farm[me].active == s, "and it lives in the session store")
    assertTrue(NS.db.global.farm[me] == nil or NS.db.global.farm[me].active == nil, "never in the saved one")
    assertTrue(F._live == true, "the session is registered")
    return #s.log
  end, { afterStep = function(i) if i == 1 then NS.Farm:Start() end end })
  if not ok then unseed(); error(lines, 0) end
  assertTrue(lines > 0, "the scenario's gains tallied into the sim session")
  assertEqual(snapshot().farm, before, "db.global.farm is byte-identical")
  assertEqual(NS.SimStores.farm, nil, "the session store is released")
  assertTrue(NS.Farm._live == nil, "the released session left nothing registered")
  unseed()
end)
