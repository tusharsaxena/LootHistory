local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local H = dofile("tests/sim_support.lua").new(T)

-- The simulator's saved-data invariant (LootHistory#37; req-lh-sim.md §4 and §11.3, the host
-- contract's H4): a whole session of every scenario, played to the end and stopped, leaves the
-- saved stores -- NS.db.global.history, .holdings and .daily -- byte-identical to what they were
-- before it started. Every capture-path write resolved to the session's own stores; the maintenance
-- paths that read NS.db.global directly (the storage figures, the retention count) went on reading
-- the saved ones the whole time. This slot runs after tests/test_sim_e2e.lua, with the whole addon
-- brought up.

local function snapshot()
  local g = NS.db.global
  return { history = H.serialize(g.history or {}), holdings = H.serialize(g.holdings or {}),
           daily = H.serialize(g.daily or {}) }
end

-- Something real in each saved store, so "unchanged" is a claim about data and not about nothing.
-- Answers the undo, which takes out only what it added.
local REAL, DAY = "Realalt-Realm", "2026-01-01"
local function seedLive()
  local g = NS.db.global
  if #(g.history or {}) == 0 then T.seedDatabase() end
  g.holdings, g.daily = g.holdings or {}, g.daily or {}
  local addH, addD = g.holdings[REAL] == nil, g.daily[DAY] == nil
  if addH then
    g.holdings[REAL] = { meta = { genesis = 1 }, scanned = {}, items = { [2589] = { bags = 7 } },
      currency = {}, links = {} }
  end
  if addD then g.daily[DAY] = { [REAL] = { g = { c = 100 } } } end
  return function()
    if addH then g.holdings[REAL] = nil end
    if addD then g.daily[DAY] = nil end
  end
end

for _, name in ipairs({ "loot", "key", "vendor", "ah", "bank", "social" }) do
  test(("SimStore: %s: the saved history, holdings and daily are byte-identical before start and after stop"):format(name),
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
    assertEqual(NS.SimStores.history, nil, name .. ": the session stores are released")
    assertTrue(NS.Database:History() == NS.db.global.history, name .. ": the accessors read the saved store again")
    unseed()
  end)
end
