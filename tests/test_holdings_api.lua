local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- The public API, v1 (#34, spec section 8): modules/HoldingsAPI.lua. After test_disabled, which
-- leaves the whole addon brought up, because availability reads the latch and the relay is a live
-- bus receiver. Every case restores the saved store it seeds; the live arm leaves CallbackHandler
-- registered on the mock's LibStub (nothing else here resolves it) and unregisters its owners.

local A = function() return NS.HoldingsAPI end
local api = function() return NS.API.v1 end
local C = NS.Constants
local ME, WB = T.ME, C.WARBAND_HOLDER
local ANN, BOB = T.nameKey("Ann"), T.nameKey("Bob")
local NOW = 1000000

local NAMES = { "CurrencyCount", "HolderInfo", "Holders", "Holdings", "IsAvailable", "ItemCount", "Money",
                "RegisterCallback", "Scanned", "UnregisterCallback", "Version" }

-- A small account: Ann with items in two containers, a currency, gold and an escrow; Bob with mail;
-- the warband with tabs and gold. The logged-in character holds nothing stored.
local function seed()
  local H = NS.Holdings
  H:ApplyContainer(ANN, "bags", { [7] = 3 }, { [7] = "L7" }, NOW)
  H:ApplyContainer(ANN, "bank", { [7] = 10, [9] = 1 }, {}, NOW)
  H:ApplyCurrency(ANN, { [300] = 40 }, NOW)
  H:ApplyMoney(ANN, 5000, NOW)
  H:NoteBankSlots(ANN, { 28 })
  H:Escrow(ANN)
  local ann = H:Get(ANN)
  ann.meta.classFile, ann.meta.lastSeen = "MAGE", NOW
  H:ApplyContainer(BOB, "mail", { [7] = 20 }, {}, NOW)
  H:ApplyContainer(WB, "tabs", { [7] = 50 }, {}, NOW)
  H:ApplyMoney(WB, 900, NOW)
end

--- Run `fn` over a seeded saved store, live client reads stubbed quiet; everything is put back.
local function with(fn)
  local g, Cp = NS.db.global, NS.Compat
  local savedStore = g.holdings
  local saved = { Cp.LiveItemCounts, Cp.CurrencyQuantity, Cp.GetMoney, Cp.GetWarbandMoney }
  Cp.LiveItemCounts = function() return nil, nil, nil end
  Cp.CurrencyQuantity = function() return nil end
  Cp.GetMoney = function() return 77 end
  Cp.GetWarbandMoney = function() return nil end
  g.holdings = {}
  NS.HoldingsTally:Invalidate()
  seed()
  local ok, err = pcall(fn)
  Cp.LiveItemCounts, Cp.CurrencyQuantity, Cp.GetMoney, Cp.GetWarbandMoney = saved[1], saved[2], saved[3], saved[4]
  g.holdings = savedStore
  NS.HoldingsTally:Invalidate()
  if not ok then error(err, 0) end
end

local function keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = tostring(k) end
  table.sort(out)
  return table.concat(out, ",")
end

-- A stable rendering of any value, for "unchanged" comparisons.
local function dump(v)
  if type(v) ~= "table" then return tostring(v) end
  local ks = {}
  for k in pairs(v) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(ks) do out[#out + 1] = tostring(k) .. "=" .. dump(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

-- Every table reachable from `t`, into `set`.
local function tablesOf(t, set)
  set = set or {}
  if type(t) ~= "table" or set[t] then return set end
  set[t] = true
  for k, v in pairs(t) do tablesOf(k, set); tablesOf(v, set) end
  return set
end

-- ── shape ─────────────────────────────────────────────────────────────────────────────────────

test("HoldingsAPI: the file publishes _G.LootHistory holding exactly API, its NS.API, holding exactly v1", function()
  -- Loaded fresh rather than read off the session: a suite that re-loads the whole TOC into its own
  -- namespace (test_envsetup) republishes the global for that instance, exactly as a second load
  -- would in the client. The session's global is put back afterwards.
  local before = rawget(_G, "LootHistory")
  local ns = { Constants = NS.Constants, HoldingsTally = NS.HoldingsTally }
  local ok, err = pcall(function()
    T.Loader.load("modules/HoldingsAPI.lua", ns, T.mocks)
    local g = rawget(_G, "LootHistory")
    assertTrue(type(g) == "table", "_G.LootHistory is published at file load")
    assertEqual(keys(g), "API")
    assertTrue(rawequal(g.API, ns.API), "the API key is the namespace's NS.API itself")
    assertEqual(keys(ns.API), "v1")
    assertFalse(rawequal(g, ns), "never the namespace")
    assertEqual(keys(ns.API.v1), table.concat(NAMES, ","), "the eleven functions, on the degraded arm too")
  end)
  rawset(_G, "LootHistory", { API = NS.API })
  if not ok then error(err, 0) end
  assertTrue(type(before) == "table", "the session published one too")
end)

test("HoldingsAPI: v1 holds exactly the eleven functions, and Version() is 1", function()
  assertEqual(keys(api()), table.concat(NAMES, ","))
  for _, name in ipairs(NAMES) do assertEqual(type(api()[name]), "function", name) end
  assertEqual(api().Version(), 1)
  assertEqual(C.API_VERSION, 1)
end)

-- ── return shapes ─────────────────────────────────────────────────────────────────────────────

test("HoldingsAPI: Holders lists the characters ascending and the warband last", function()
  with(function()
    assertTrue(api().IsAvailable())
    assertEqual(table.concat(api().Holders(), ","), ANN .. "," .. BOB .. "," .. WB)
    assertFalse(rawequal(api().Holders(), api().Holders()), "a new array each call")
  end)
end)

test("HoldingsAPI: HolderInfo for a character, the warband, an unknown holder and a bad argument", function()
  with(function()
    local info = api().HolderInfo(ANN)
    assertEqual(info.class, "MAGE"); assertEqual(info.lastSeen, NOW)
    assertFalse(info.isWarband); assertFalse(info.isCurrent)
    assertEqual(info.partial, false, "no genesis, so never partial")
    if T.forever then
      assertEqual(info.name, ANN); assertEqual(info.realm, nil)
    else
      assertEqual(info.name, "Ann"); assertEqual(info.realm, "Realm")
    end
    local wb = api().HolderInfo(WB)
    assertEqual(wb.name, C.ACCOUNT.holder); assertEqual(wb.realm, nil); assertTrue(wb.isWarband)
    assertEqual(api().HolderInfo("Nobody-Realm"), nil)
    assertEqual(api().HolderInfo(42), nil)
    assertEqual(api().HolderInfo(nil), nil)
    NS.Holdings:MarkGenesis(BOB, NOW)                     -- genesis with the bank never read
    assertEqual(api().HolderInfo(BOB).partial, true)
  end)
end)

test("HoldingsAPI: HolderInfo marks the logged-in character current", function()
  with(function()
    NS.Holdings:ApplyContainer(ME, "bags", { [7] = 1 }, {}, NOW)
    assertTrue(api().HolderInfo(ME).isCurrent)
  end)
end)

test("HoldingsAPI: ItemCount splits per holder and container, nonzero only; bad and unheld ids", function()
  with(function()
    local total, per = api().ItemCount(7)
    assertEqual(total, 83)
    assertEqual(dump(per[ANN]), "{bags=3,bank=10}")
    assertEqual(dump(per[BOB]), "{mail=20}")
    assertEqual(dump(per[WB]), "{tabs=50}")
    assertEqual(per[ME], nil, "a holder with nothing is absent")
    local t0, p0 = api().ItemCount(123456)
    assertEqual(t0, 0); assertEqual(next(p0), nil)
    local tn, pn = api().ItemCount("7")
    assertEqual(tn, nil); assertEqual(next(pn), nil)
  end)
end)

test("HoldingsAPI: ItemCount for the logged-in character equals the tally's live overlay", function()
  with(function()
    NS.Compat.LiveItemCounts = function() return 4, nil, nil end
    local _, per = api().ItemCount(7)
    local _, rows, n = NS.HoldingsTally:Item(7)
    local mine
    for i = 1, n do if rows[i].holder == ME then mine = rows[i] end end
    assertEqual(per[ME].bags, 4)
    assertEqual(dump(per[ME]), dump(mine.containers))
  end)
end)

test("HoldingsAPI: CurrencyCount per holder; bad and unheld ids", function()
  with(function()
    local total, per = api().CurrencyCount(300)
    assertEqual(total, 40); assertEqual(dump(per), "{" .. ANN .. "=40}")
    local t0, p0 = api().CurrencyCount(999)
    assertEqual(t0, 0); assertEqual(next(p0), nil)
    local tn, pn = api().CurrencyCount({})
    assertEqual(tn, nil); assertEqual(next(pn), nil)
  end)
end)

test("HoldingsAPI: Money is live for me and the warband where answered, stored otherwise; nil sums all", function()
  with(function()
    assertEqual(api().Money(ME), 77)
    assertEqual(api().Money(ANN), 5000)
    assertEqual(api().Money(BOB), 0)
    assertEqual(api().Money(WB), 900, "stored while the client answers nil")
    assertEqual(api().Money(), 77 + 5000 + 0 + 900)
    NS.Compat.GetWarbandMoney = function() return 1200 end
    assertEqual(api().Money(WB), 1200)
    assertEqual(api().Money(), 77 + 5000 + 0 + 1200)
    assertEqual(api().Money("Nobody-Realm"), nil)
    assertEqual(api().Money(5), nil)
  end)
end)

test("HoldingsAPI: while a simulation runs, Money reads the real purse and deposit, never the sim's", function()
  -- red under: moneyOf calling the wrapped NS.Compat.GetMoney / GetWarbandMoney straight, which a
  -- /lh sim session answers from the simulated world (modules/SimWorld.lua's providers).
  with(function()
    local Cp, seam, active = NS.Compat, NS.SimSeam, NS.Sim.IsActive
    local bypass = false
    Cp.GetMoney = function() return bypass and 77 or 31337 end
    Cp.GetWarbandMoney = function() return bypass and 1200 or 4242 end
    NS.SimSeam = { Live = function(_, fn, ...)
      bypass = true
      local ok, v = pcall(fn, ...)
      bypass = false
      if not ok then error(v, 0) end
      return v
    end }
    NS.Sim.IsActive = function() return true end
    local ok, err = pcall(function()
      assertEqual(api().Money(ME), 77, "the real purse")
      assertEqual(api().Money(WB), 1200, "the real deposit")
      assertEqual(api().Money(), 77 + 5000 + 0 + 1200)
    end)
    NS.SimSeam, NS.Sim.IsActive = seam, active
    if not ok then error(err, 0) end
    assertEqual(api().Money(ME), 31337, "idle, the member is called straight")
  end)
end)

test("HoldingsAPI: Holdings is the stored snapshot, without escrow or bankSlots", function()
  with(function()
    local h = api().Holdings(ANN)
    assertEqual(keys(h), "currency,items,links,meta,money,scanned")
    assertEqual(dump(h.items), "{7={bags=3,bank=10},9={bank=1}}")
    assertEqual(dump(h.currency), "{300=40}")
    assertEqual(h.money, 5000)
    assertEqual(h.links[7], "L7")
    assertEqual(h.scanned.bags, NOW); assertEqual(h.scanned.currency, NOW)
    assertEqual(h.meta.classFile, "MAGE"); assertEqual(h.meta.bankSlots, nil)
    assertEqual(h.escrow, nil)
    assertEqual(api().Holdings("Nobody-Realm"), nil); assertEqual(api().Holdings(false), nil)
  end)
end)

test("HoldingsAPI: Scanned copies e.scanned; nil for unknown", function()
  with(function()
    local s = api().Scanned(ANN)
    assertEqual(s.bank, NOW); assertEqual(s.money, NOW)
    assertFalse(rawequal(s, NS.db.global.holdings[ANN].scanned))
    assertEqual(api().Scanned("Nobody-Realm"), nil)
  end)
end)

-- ── every answer is a copy ────────────────────────────────────────────────────────────────────

test("HoldingsAPI: no answer is or holds a store table, and writing into one changes nothing", function()
  with(function()
    local storeTables = tablesOf(NS.db.global.holdings)
    local before = dump(NS.db.global.holdings)
    local function answers()
      local _, ic = api().ItemCount(7)
      local _, cc = api().CurrencyCount(300)
      return { api().Holders(), api().HolderInfo(ANN), ic, cc, api().Holdings(ANN), api().Scanned(ANN),
               api().Holdings(WB) }
    end
    local first = answers()
    local firstDump = dump(first)
    for t in pairs(tablesOf(first)) do
      assertFalse(storeTables[t], "an answer reaches a table of db.global.holdings")
    end
    for t in pairs(tablesOf(first)) do
      if t ~= first then
        for k in pairs(t) do t[k] = nil end
        t.poison = true
      end
    end
    assertEqual(dump(NS.db.global.holdings), before, "the store is unchanged")
    assertEqual(dump(answers()), firstDump, "the next answers are unchanged")
  end)
end)

-- ── availability ──────────────────────────────────────────────────────────────────────────────

local function assertEmpty(why)
  assertFalse(api().IsAvailable(), why)
  assertEqual(api().Version(), 1, why)
  assertEqual(next(api().Holders()), nil, why)
  assertEqual(api().HolderInfo(ANN), nil, why)
  local t, per = api().ItemCount(7)
  assertEqual(t, nil, why); assertEqual(next(per), nil, why)
  local ct, cper = api().CurrencyCount(300)
  assertEqual(ct, nil, why); assertEqual(next(cper), nil, why)
  assertEqual(api().Money(), nil, why); assertEqual(api().Money(ANN), nil, why)
  assertEqual(api().Holdings(ANN), nil, why); assertEqual(api().Scanned(ANN), nil, why)
end

test("HoldingsAPI: trackLedger off answers empty; on again, the answers come back", function()
  with(function()
    NS.Schema:Set("settings.trackLedger", false)
    local ok, err = pcall(assertEmpty, "trackLedger off")
    NS.Schema:Set("settings.trackLedger", true)
    if not ok then error(err, 0) end
    assertTrue(api().IsAvailable())
    assertEqual((api().ItemCount(7)), 83)
  end)
end)

test("HoldingsAPI: settings.enabled false answers empty, and the global survives", function()
  with(function()
    local global = rawget(_G, "LootHistory")
    NS.Schema:Set("settings.enabled", false)
    local ok, err = pcall(function()
      assertTrue(NS.IsStoodDown())
      assertEmpty("disabled")
      assertTrue(rawequal(rawget(_G, "LootHistory"), global), "the global is setup: it stays")
    end)
    NS.Schema:Set("settings.enabled", true)
    if not ok then error(err, 0) end
    assertTrue(api().IsAvailable())
  end)
end)

test("HoldingsAPI: a perf capture's hold answers empty", function()
  with(function()
    NS.Lifecycle:Hold(NS.HOLD_PERF)
    local ok, err = pcall(assertEmpty, "perf hold")
    NS.Lifecycle:Release(NS.HOLD_PERF)
    if not ok then error(err, 0) end
    assertTrue(api().IsAvailable())
  end)
end)

-- ── the callback relay ────────────────────────────────────────────────────────────────────────

test("HoldingsAPI: degraded arm -- without CallbackHandler both registrations answer false", function()
  assertEqual(T.mocks.LibStub("CallbackHandler-1.0", true), nil, "the headless default has no CallbackHandler")
  assertEqual(A()._registry, nil)
  local owner = {}
  local ok, r = pcall(api().RegisterCallback, owner, "HoldingsChanged", function() end)
  assertTrue(ok, tostring(r)); assertEqual(r, false)
  local ok2, r2 = pcall(api().UnregisterCallback, owner, "HoldingsChanged")
  assertTrue(ok2, tostring(r2)); assertEqual(r2, false)
  assertFalse(A()._BindCallbacks(), "binding still finds nothing")
end)

-- Load the real CallbackHandler through the mock LibStub's NewLibrary. securecallfunction is the
-- client's; it is planted for the load (the library captures it as an upvalue) and taken back out.
local function loadCallbackHandler()
  if T.mocks.LibStub("CallbackHandler-1.0", true) then return end
  T.mocks.securecallfunction = function(fn, ...) return fn(...) end
  local ok, err = pcall(T.Loader.load, "libs/CallbackHandler-1.0/CallbackHandler-1.0.lua", {}, T.mocks)
  T.mocks.securecallfunction = nil
  if not ok then error(err, 0) end
end

--- Run `fn(log)` with an owner registered on HoldingsChanged; `log` gets "event:holder" per call.
local function listening(fn)
  loadCallbackHandler()
  assertTrue(A()._BindCallbacks(), "the live arm binds")
  local owner, log = {}, {}
  api().RegisterCallback(owner, "HoldingsChanged", function(event, holder)
    log[#log + 1] = tostring(event) .. ":" .. tostring(holder)
  end)
  local ok, err = pcall(fn, log)
  api().UnregisterCallback(owner, "HoldingsChanged")
  if not ok then error(err, 0) end
end

test("HoldingsAPI: live arm -- a registration hears ('HoldingsChanged', holder) on ForgetHolder", function()
  with(function()
    listening(function(log)
      assertTrue(NS.Reconciler:ForgetHolder(BOB))
      assertEqual(table.concat(log, ","), "HoldingsChanged:" .. BOB)
    end)
  end)
end)

-- The bus walks its targets in hash order, so the tally's own receiver may run after the relay.
-- With the tally's target down, only the relay can have wiped the cache.
local function tallyDown(fn)
  local Tl = NS.HoldingsTally
  local wasUp = Tl.__ev ~= nil
  Tl:Disable()
  local ok, err = pcall(fn)
  if wasUp then Tl:Enable() end
  if not ok then error(err, 0) end
end

test("HoldingsAPI: live arm -- a re-query inside HoldingsChanged sees the new store", function()
  -- red under: onHoldingsChanged firing before Tally:Invalidate, so ItemCount inside the callback
  -- reads the pre-flush cached entry and still lists the holder ForgetHolder just removed.
  with(function()
    loadCallbackHandler()
    assertTrue(A()._BindCallbacks())
    tallyDown(function()
      local _, before = api().ItemCount(7)
      assertTrue(before[BOB] ~= nil, "Bob's mail is in the warmed cache")
      local owner, seen = {}, nil
      api().RegisterCallback(owner, "HoldingsChanged", function()
        local _, per = api().ItemCount(7)
        seen = per
      end)
      local ok, err = pcall(NS.Reconciler.ForgetHolder, NS.Reconciler, BOB)
      api().UnregisterCallback(owner, "HoldingsChanged")
      if not ok then error(err, 0) end
      assertTrue(seen ~= nil, "the callback ran")
      assertEqual(seen[BOB], nil, "the forgotten holder is gone inside the callback")
      assertTrue(seen[ANN] ~= nil, "the others are still there")
    end)
  end)
end)

test("HoldingsAPI: live arm -- an availability flip wipes the tally before it fires", function()
  with(function()
    loadCallbackHandler()
    assertTrue(A()._BindCallbacks())
    tallyDown(function()
      local owner, gens = {}, {}
      api().RegisterCallback(owner, "HoldingsChanged", function() gens[#gens + 1] = NS.HoldingsTally._gen end)
      local g0 = NS.HoldingsTally._gen
      local ok, err = pcall(function()
        NS.Schema:Set("settings.trackLedger", false)
        NS.Schema:Set("settings.trackLedger", true)
      end)
      api().UnregisterCallback(owner, "HoldingsChanged")
      if not ok then error(err, 0) end
      assertEqual(#gens, 2)
      assertTrue(gens[1] > g0 and gens[2] > gens[1], "each fire follows its own wipe")
    end)
  end)
end)

test("HoldingsAPI: live arm -- a Reconciler flush relays each changed holder", function()
  local m = T.mocks
  local saved = { m.__bags, m.__bagSlots, NS.db.global.history }
  local hist = {}
  for i, row in ipairs(NS.db.global.history or {}) do hist[i] = row end
  with(function()
    listening(function(log)
      m.__bags, m.__bagSlots = { [0] = { [1] = { itemID = 5, link = "L5", count = 2 } } }, { [0] = 1 }
      NS.Reconciler:MarkDirty("bags", 0)
      NS.Reconciler:Flush()
      assertEqual(table.concat(log, ","), "HoldingsChanged:" .. ME)
    end)
  end)
  m.__bags, m.__bagSlots = saved[1], saved[2]
  local h = NS.db.global.history
  if h then
    for i = #h, 1, -1 do h[i] = nil end
    for i, row in ipairs(hist) do h[i] = row end
  end
end)

test("HoldingsAPI: live arm -- nothing is relayed during an active simulation", function()
  with(function()
    listening(function(log)
      local orig = NS.Sim.IsActive
      NS.Sim.IsActive = function() return true end
      local ok, err = pcall(NS.Reconciler.AnnounceHolders, NS.Reconciler, { ANN })
      NS.Sim.IsActive = orig
      if not ok then error(err, 0) end
      assertEqual(#log, 0)
      NS.Reconciler:AnnounceHolders({ ANN })
      assertEqual(table.concat(log, ","), "HoldingsChanged:" .. ANN)
    end)
  end)
end)

test("HoldingsAPI: live arm -- nil on a trackLedger flip, and once each on Disable and Enable", function()
  with(function()
    listening(function(log)
      NS.Schema:Set("settings.trackLedger", false)
      NS.Schema:Set("settings.trackLedger", false)            -- no flip, no fire
      NS.Schema:Set("settings.trackLedger", true)
      assertEqual(table.concat(log, ","), "HoldingsChanged:nil,HoldingsChanged:nil")
      for i = #log, 1, -1 do log[i] = nil end
      A():Disable()
      assertEqual(A().__ev, nil, "the target is gone after Disable")
      NS.Reconciler:AnnounceHolders({ ANN })                   -- the relay is down
      A():Enable()
      assertTrue(A().__ev ~= nil, "the target is back after Enable")
      assertEqual(table.concat(log, ","), "HoldingsChanged:nil,HoldingsChanged:nil")
    end)
  end)
end)

test("HoldingsAPI: live arm -- nothing after UnregisterCallback; a method name is called on its owner", function()
  loadCallbackHandler()
  A()._BindCallbacks()
  local got = {}
  local owner = { OnChanged = function(self, event, holder) got[#got + 1] = { self, event, holder } end }
  api().RegisterCallback(owner, "HoldingsChanged", "OnChanged")
  NS.Reconciler:AnnounceHolders({ ANN })
  api().UnregisterCallback(owner, "HoldingsChanged")
  NS.Reconciler:AnnounceHolders({ ANN })
  assertEqual(#got, 1)
  assertTrue(got[1][1] == owner); assertEqual(got[1][2], "HoldingsChanged"); assertEqual(got[1][3], ANN)
end)

test("HoldingsAPI: live arm -- the relay never sends on the bus", function()
  with(function()
    listening(function(log)
      local sent, orig = {}, NS.bus.SendMessage
      NS.bus.SendMessage = function(bus, msg, ...)
        sent[#sent + 1] = msg
        return orig(bus, msg, ...)
      end
      local ok, err = pcall(function()
        NS.Reconciler:AnnounceHolders({ ANN })
        NS.Schema:Set("settings.trackLedger", false)
        NS.Schema:Set("settings.trackLedger", true)
      end)
      NS.bus.SendMessage = orig
      if not ok then error(err, 0) end
      assertEqual(#log, 3, "the relay fired three times")
      assertEqual(table.concat(sent, ","), table.concat({ NS.MSG.HOLDINGS_CHANGED, NS.MSG.SETTINGS_CHANGED,
                                                          NS.MSG.SETTINGS_CHANGED }, ","),
        "only the Reconciler's send and the two settings rows' sends")
    end)
  end)
end)

test("HoldingsAPI: the private target is registered while up and owns its two messages", function()
  assertTrue(A().__ev ~= nil, "up after test_disabled")
  assertFalse(rawequal(A().__ev, NS.HoldingsTally.__ev), "its own target")
  A():Disable()
  assertEqual(A().__ev, nil)
  A():Enable()
  assertTrue(A().__ev ~= nil)
end)
