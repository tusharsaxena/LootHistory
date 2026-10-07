local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- modules/Reconciler.lua (timeline-ledger spec §5.2): events only mark parts dirty, Flush reads what
-- is currently readable into db.global.holdings, and combat defers every read to the regen edge.
-- Every case drives OnEvent / MarkDirty / Flush directly: the module is not stood up in this slot
-- (only tests/test_disabled.lua brings the whole addon up), so the registrations are not involved.

local R = function() return NS.Reconciler end
local ME = function() return NS.Util.PlayerKey() end

local function reset()
  NS.db.global.holdings = {}
  local m = T.mocks
  m.__bags, m.__bagSlots, m.__inventory, m.__money, m.__warbandMoney = {}, {}, {}, 0, 0
  R().dirty, R().readable, R().deferred = {}, {}, nil
end

local function captureChanged(fn)
  local got, orig = {}, NS.bus.SendMessage
  NS.bus.SendMessage = function(_, msg, a) if msg == NS.MSG.HOLDINGS_CHANGED then got[#got + 1] = a end end
  local ok, err = pcall(fn)
  NS.bus.SendMessage = orig
  if not ok then error(err, 0) end
  return got
end

test("Reconciler: BAG_UPDATE only marks dirty; BAG_UPDATE_DELAYED flushes", function()
  reset()
  T.mocks.__bags[0] = { [1] = { itemID = 5, link = "L5", count = 2 } }; T.mocks.__bagSlots[0] = 1
  R():OnEvent("BAG_UPDATE", 0)
  assertTrue(R().dirty.bags ~= nil)
  assertEqual(NS.Holdings:Get(ME()), nil)
  local changed = captureChanged(function() R():OnEvent("BAG_UPDATE_DELAYED"); R():Flush() end)
  assertEqual(NS.Holdings:Get(ME()).items[5].bags, 2)
  assertEqual(changed[1], ME())
end)

test("Reconciler: bag flush never touches bank column", function()
  reset()
  NS.Holdings:ApplyContainer(ME(), "bank", { [5] = 10 }, {}, 1)
  R():MarkDirty("bags", 0); R():Flush()
  assertEqual(NS.Holdings:Get(ME()).items[5].bank, 10)
end)

test("Reconciler: bank is unreadable until the banker interaction shows", function()
  reset()
  T.mocks.__bags[6] = { [1] = { itemID = 8, link = "L8", count = 4 } }; T.mocks.__bagSlots[6] = 1
  R():MarkDirty("bank"); R():Flush()
  assertEqual(NS.Holdings:Get(ME()), nil)
  R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", NS.Compat.InteractionType("Banker"))
  R():Flush()
  assertEqual(NS.Holdings:Get(ME()).items[8].bank, 4)
  R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", NS.Compat.InteractionType("Banker"))
  assertFalse(R():IsReadable("bank"))
end)

test("Reconciler: combat defers every scan to PLAYER_REGEN_ENABLED", function()
  reset()
  local m = T.mocks
  local savedICL = m.InCombatLockdown
  m.InCombatLockdown = function() return true end; rawset(_G, "InCombatLockdown", m.InCombatLockdown)
  m.__money = 500
  for _ = 1, 20 do R():OnEvent("PLAYER_MONEY"); R():OnEvent("BAG_UPDATE", 0); R():OnEvent("BAG_UPDATE_DELAYED") end
  R():Flush()
  assertEqual(NS.Holdings:Get(ME()), nil)
  assertTrue(R().deferred)
  m.InCombatLockdown = savedICL; rawset(_G, "InCombatLockdown", savedICL)
  local changed = captureChanged(function() R():OnEvent("PLAYER_REGEN_ENABLED") end)
  assertEqual(NS.Holdings:Get(ME()).money, 500)
  assertEqual(#changed, 1)
end)

test("Reconciler: LoginScan seeds genesis, partial until bank seen", function()
  reset()
  T.mocks.__money, T.mocks.__warbandMoney = 100, 70
  R():LoginScan()
  local e = NS.Holdings:Get(ME())
  assertTrue(e.meta.genesis ~= nil); assertTrue(e.meta.partial)
  assertEqual(NS.Holdings:Get("§warband").money, 70)
  T.mocks.__warbandMoney = 0
end)

test("Reconciler: account-wide currency lands on the warband holder", function()
  reset()
  local saved = T.mocks.__currencyList
  T.mocks.__currencyList = { { id = 2032, quantity = 5, accountWide = true }, { id = 3008, quantity = 9 } }
  local ok, err = pcall(function() R():MarkDirty("currency"); R():Flush() end)
  T.mocks.__currencyList = saved
  assertTrue(ok, tostring(err))
  assertEqual(NS.Holdings:Get("§warband").currency[2032], 5)
  assertEqual(NS.Holdings:Get(ME()).currency[3008], 9)
end)

-- Adapted from the plan's snippet: this suite's slot has never stood the module up, so the case
-- brings it up itself, asserts both edges of the setting, and leaves it down again for the suites
-- after it (tests/test_disabled.lua counts every live registration).
test("Reconciler: trackLedger off unregisters, on registers again", function()
  reset()
  NS.Schema:Set("settings.trackLedger", true)
  R():Enable()
  assertTrue(R().__ev ~= nil, "Enable registers the capture events while trackLedger is on")
  NS.Schema:Set("settings.trackLedger", false)
  assertEqual(R().__ev, nil, "unticking trackLedger unregisters the capture events")
  assertFalse(R()._enabled == true)
  assertTrue(R()._settings ~= nil, "but the module keeps listening for the setting coming back")
  NS.Schema:Set("settings.trackLedger", true)
  assertTrue(R().__ev ~= nil, "ticking it again registers them again")
  R():Disable()
  assertEqual(R().__ev, nil); assertEqual(R()._settings, nil)
end)
