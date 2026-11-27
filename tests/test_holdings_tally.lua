local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- The holdings tally (#34, spec section 5): modules/HoldingsTally.lua over the saved store, with the
-- live overlay for the logged-in character and the warband bank. The client reads it composes are
-- stubbed on NS.Compat per case (they are WRAPPED Compat members, read at call time), and the
-- Reconciler's IsReadable on NS.Reconciler.

local TL = function() return NS.HoldingsTally end
local H = function() return NS.Holdings end
local ME, WB = T.ME, NS.Constants.WARBAND_HOLDER
local ANN, BOB = T.nameKey("Ann"), T.nameKey("Bob")
local NOW, DAY = 1000000, 86400
local WARBAND_BANK = NS.Constants.FEATURE.warbandBank

--- Run `fn` with `stubs` in place: keys "live" (bags, bank, account, worn), "quantity", "accountWide",
--- "readable" ({ [part] = bool }). Everything is restored, the cache wiped, and the store reset.
--- The harness does not stand the addon up (tests/run.lua), so the tally is brought up for the case
--- and taken back down after it when it was down before.
local function with(stubs, fn)
  local C, R = NS.Compat, NS.Reconciler
  local wasUp = TL().__ev ~= nil
  TL():Enable()
  local saved = { C.LiveItemCounts, C.CurrencyQuantity, C.CurrencyIsAccountWide, R.IsReadable }
  local live = stubs.live or {}
  C.LiveItemCounts = function() return live[1], live[2], live[3], live[4] end
  C.CurrencyQuantity = function() return stubs.quantity end
  C.CurrencyIsAccountWide = function() return stubs.accountWide == true end
  R.IsReadable = function(_, part) return (stubs.readable or {})[part] == true end
  TL():Invalidate()
  local ok, err = pcall(fn)
  C.LiveItemCounts, C.CurrencyQuantity, C.CurrencyIsAccountWide, R.IsReadable = saved[1], saved[2], saved[3], saved[4]
  TL():Invalidate()
  if not wasUp then TL():Disable() end
  NS.db.global.holdings = {}
  if not ok then error(err, 0) end
end

local function fresh() NS.db.global.holdings = {} end

local function put(holder, container, counts, ts, classFile)
  H():ApplyContainer(holder, container, counts, {}, ts or NOW)
  if classFile then H():Get(holder).meta.classFile = classFile end
end

--- The rows as "holder=count" in order.
local function order(rows, n)
  local out = {}
  for i = 1, n do out[#out + 1] = rows[i].holder .. "=" .. rows[i].count end
  return table.concat(out, ",")
end

local function rowOf(rows, n, holder)
  for i = 1, n do if rows[i].holder == holder then return rows[i] end end
  return nil
end

-- ── counts, splits and order ──────────────────────────────────────────────────────────────────

test("HoldingsTally: three characters and the warband, per holder, per container, warband last", function()
  fresh()
  put(ANN, "bags", { [7] = 3 }, NOW, "MAGE"); put(ANN, "bank", { [7] = 10 })
  put(BOB, "mail", { [7] = 20 }, NOW, "PRIEST")
  put(T.nameKey("Cid"), "bags", { [8] = 1 })                 -- holds something else: dropped
  put(WB, "tabs", { [7] = 50 })
  with({}, function()
    local total, rows, n = TL():Item(7, NOW)
    assertEqual(order(rows, n), BOB .. "=20," .. ANN .. "=13," .. WB .. "=50")
    assertEqual(total, 83)
    local ann = rowOf(rows, n, ANN)
    assertEqual(ann.containers.bags, 3); assertEqual(ann.containers.bank, 10)
    assertEqual(ann.containers.mail, nil)
    assertEqual(ann.classFile, "MAGE")
    assertTrue(rowOf(rows, n, WB).isWarband)
    assertFalse(ann.isMe)
  end)
end)

test("HoldingsTally: equal counts sort by holder; a zero holder is dropped, me included", function()
  fresh()
  put(BOB, "bags", { [7] = 4 }); put(ANN, "bags", { [7] = 4 })
  with({ live = { 0, 0, 0 } }, function()
    local _, rows, n = TL():Item(7, NOW)
    assertEqual(order(rows, n), ANN .. "=4," .. BOB .. "=4")
  end)
end)

test("HoldingsTally: a base itemID in the store matches the tooltip's id", function()
  fresh()
  put(ANN, "bags", { [19019] = 1 })
  with({}, function()
    local total = TL():Item(19019, NOW)
    assertEqual(total, 1)
  end)
end)

test("HoldingsTally: a non-number id answers nothing", function()
  fresh()
  with({}, function()
    local total, _, n = TL():Item("7", NOW)
    assertEqual(total, 0); assertEqual(n, 0)
    total, _, n = TL():Currency(nil, NOW)
    assertEqual(total, 0); assertEqual(n, 0)
  end)
end)

-- ── the live overlay ──────────────────────────────────────────────────────────────────────────

test("HoldingsTally: my bags come from LiveItemCounts, even with nothing stored", function()
  fresh()
  with({ live = { 6, nil, nil } }, function()
    local total, rows, n = TL():Item(7, NOW)
    assertEqual(total, 6); assertEqual(n, 1)
    assertTrue(rows[1].isMe); assertEqual(rows[1].holder, ME)
    assertEqual(rows[1].containers.bags, 6)
  end)
end)

test("HoldingsTally: my bank reads live at the banker", function()
  fresh()
  put(ME, "bank", { [7] = 5 })
  with({ live = { 0, 0, nil }, readable = { bank = true } }, function()
    local total = TL():Item(7, NOW)
    assertEqual(total, 0, "at the banker a live 0 is authoritative")
  end)
end)

test("HoldingsTally: zero-suspect -- live 0 with stored 5 away from the bank reads 5", function()
  fresh()
  put(ME, "bank", { [7] = 5 })
  with({ live = { 0, 0, nil } }, function()
    local _, rows = TL():Item(7, NOW)
    assertEqual(rows[1].containers.bank, 5)
  end)
end)

test("HoldingsTally: live 7 with stored 5 away from the bank reads 7", function()
  fresh()
  put(ME, "bank", { [7] = 5 })
  with({ live = { 0, 7, nil } }, function()
    local _, rows = TL():Item(7, NOW)
    assertEqual(rows[1].containers.bank, 7)
  end)
end)

test("HoldingsTally: a nil live part falls back to the store", function()
  fresh()
  put(ME, "bags", { [7] = 2 }); put(ME, "bank", { [7] = 3 })
  with({ live = { nil, nil, nil } }, function()
    local _, rows = TL():Item(7, NOW)
    assertEqual(rows[1].containers.bags, 2); assertEqual(rows[1].containers.bank, 3)
  end)
end)

test("HoldingsTally: with no live worn count equipped is stored; mail and auctions always are", function()
  fresh()
  put(ME, "equipped", { [7] = 1 }); put(ME, "mail", { [7] = 2 }); put(ME, "auctions", { [7] = 3 })
  with({ live = { 0, 0, 0 }, readable = { bank = true } }, function()
    local total, rows = TL():Item(7, NOW)
    assertEqual(total, 6)
    assertEqual(rows[1].containers.equipped, 1); assertEqual(rows[1].containers.mail, 2)
    assertEqual(rows[1].containers.auctions, 3)
  end)
end)

test("HoldingsTally: my equipped count is live, so a swap never undercounts or doubles", function()
  -- red under: EQUIPPED read from the store for me while bags read live -- equipping the only copy
  -- drops live bags to 0 while stored equipped is still 0 until the next flush (all of combat).
  fresh()
  put(ME, "bags", { [7] = 1 })
  with({ live = { 0, nil, nil, 1 } }, function()
    local total, rows, n = TL():Item(7, NOW)
    assertEqual(total, 1, "just equipped: the copy is still counted"); assertEqual(n, 1)
    assertEqual(rows[1].containers.equipped, 1); assertEqual(rows[1].containers.bags, nil)
  end)
  fresh()
  put(ME, "equipped", { [7] = 1 })
  with({ live = { 1, nil, nil, 0 } }, function()
    local total, rows = TL():Item(7, NOW)
    assertEqual(total, 1, "just unequipped: never counted twice")
    assertEqual(rows[1].containers.bags, 1); assertEqual(rows[1].containers.equipped, nil)
  end)
end)

test("HoldingsTally: a live count handed in is used, and the client is not read again", function()
  fresh()
  with({ live = { 99, nil, nil, 99 } }, function()
    local reads, orig = 0, NS.Compat.LiveItemCounts
    NS.Compat.LiveItemCounts = function(...) reads = reads + 1; return orig(...) end
    local total, rows = TL():Item(7, NOW, { bags = 2, worn = 1 })
    NS.Compat.LiveItemCounts = orig
    assertEqual(reads, 0, "the caller's read stands")
    assertEqual(total, 3); assertEqual(rows[1].containers.bags, 2); assertEqual(rows[1].containers.equipped, 1)
  end)
end)

test("HoldingsTally: while a simulation runs no bank reads as authoritative", function()
  -- red under: a /lh sim bank step marks the simulated bank readable, so the real client's 0 at the
  -- bank (not loaded this session) would wipe the stored count.
  fresh()
  put(ME, "bank", { [7] = 5 })
  with({ live = { 0, 0, nil, 0 }, readable = { bank = true, tabs = true } }, function()
    local orig = NS.Sim.IsActive
    NS.Sim.IsActive = function() return true end
    local ok, res = pcall(function()
      assertFalse(TL().Readable("bank")); assertFalse(TL().Readable("tabs"))
      local _, rows = TL():Item(7, NOW)
      return rows[1].containers.bank
    end)
    NS.Sim.IsActive = orig
    if not ok then error(res, 0) end
    assertEqual(res, 5, "the zero-suspect rule keeps the stored bank")
    assertTrue(TL().Readable("bank"), "idle again, the banker's answer is authoritative")
  end)
end)

test("HoldingsTally: another holder's counts are never overlaid", function()
  fresh()
  put(ANN, "bags", { [7] = 2 }); put(ANN, "bank", { [7] = 3 })
  with({ live = { 40, 40, 40 }, readable = { bank = true, tabs = true } }, function()
    local _, rows, n = TL():Item(7, NOW)
    local ann = rowOf(rows, n, ANN)
    assertEqual(ann.containers.bags, 2); assertEqual(ann.containers.bank, 3)
  end)
end)

test("HoldingsTally: the warband tabs are overlaid live on Retail", function()
  fresh()
  put(WB, "tabs", { [7] = 5 })
  with({ live = { 0, 0, 9 } }, function()
    local _, rows, n = TL():Item(7, NOW)
    assertEqual(rowOf(rows, n, WB).containers.tabs, 9)
  end)
  put(WB, "tabs", { [7] = 5 })
  with({ live = { 0, 0, 0 } }, function()
    local _, rows, n = TL():Item(7, NOW)
    assertEqual(rowOf(rows, n, WB).containers.tabs, 5, "zero-suspect: away from the bank the store wins")
  end)
  with({ live = { 0, 0, 4 } }, function()
    local _, rows, n = TL():Item(7, NOW)
    assertEqual(rowOf(rows, n, WB).count, 4, "a warband with nothing stored is lifted by the live read")
  end)
end, T.RETAIL_ONLY)

test("HoldingsTally: on WoW Forever the warband is never overlaid and never lifted", function()
  assertFalse(WARBAND_BANK, "the warband bank is not a Forever feature")
  fresh()
  put(WB, "tabs", { [7] = 5 })
  with({ live = { 0, 0, 9 } }, function()
    local _, rows, n = TL():Item(7, NOW)
    assertEqual(rowOf(rows, n, WB).containers.tabs, 5)
  end)
  with({ live = { 0, 0, 9 } }, function()
    local total, _, n = TL():Item(7, NOW)
    assertEqual(total, 0); assertEqual(n, 0)
  end)
end, (not T.forever) and "WoW Forever-only case (clients-§6): Retail runs the warband overlay case" or nil)

test("HoldingsTally: _resolve is the zero-suspect rule", function()
  local r = TL()._resolve
  assertEqual(select(1, r(nil, 5, true)), 5); assertTrue(select(2, r(nil, 5, true)))
  assertEqual(select(1, r(0, 5, true)), 0); assertFalse(select(2, r(0, 5, true)))
  assertEqual(select(1, r(0, 5, false)), 5); assertTrue(select(2, r(0, 5, false)))
  assertEqual(select(1, r(0, nil, false)), 0)
  assertEqual(select(1, r(7, 5, false)), 7); assertFalse(select(2, r(7, 5, false)))
end)

-- ── currencies ────────────────────────────────────────────────────────────────────────────────

test("HoldingsTally: a character currency goes live on me", function()
  fresh()
  H():ApplyCurrency(ME, { [3008] = 10 }, NOW); H():ApplyCurrency(ANN, { [3008] = 4 }, NOW)
  with({ quantity = 25 }, function()
    local total, rows, n = TL():Currency(3008, NOW)
    assertEqual(order(rows, n), ME .. "=25," .. ANN .. "=4")
    assertEqual(total, 29)
    assertEqual(rows[1].containers, nil)
  end)
end)

test("HoldingsTally: an account-wide currency goes live on the warband", function()
  fresh()
  H():ApplyCurrency(WB, { [2032] = 3 }, NOW)
  with({ quantity = 8, accountWide = true }, function()
    local total, rows, n = TL():Currency(2032, NOW)
    assertEqual(n, 1); assertEqual(rows[1].holder, WB); assertEqual(total, 8)
  end)
end)

test("HoldingsTally: a currency with no live answer keeps the stored count", function()
  fresh()
  H():ApplyCurrency(ME, { [3008] = 10 }, NOW)
  with({ quantity = nil }, function()
    assertEqual((TL():Currency(3008, NOW)), 10)
  end)
end)

-- ── staleness ─────────────────────────────────────────────────────────────────────────────────

test("HoldingsTally: a stored container three days old is stale, and reads 3 d", function()
  fresh()
  put(ANN, "bags", { [7] = 1 }, NOW); put(ANN, "bank", { [7] = 2 }, NOW - 3 * DAY)
  with({}, function()
    local _, rows = TL():Item(7, NOW)
    assertEqual(rows[1].staleContainer, "bank"); assertEqual(rows[1].staleAt, NOW - 3 * DAY)
    assertEqual(NS.HoldingsTab.FormatAge(rows[1].staleAt, NOW), "3 d")
  end)
end)

test("HoldingsTally: a live-overlaid container is never stale", function()
  fresh()
  put(ME, "bags", { [7] = 1 }, NOW - 5 * DAY); put(ME, "bank", { [7] = 2 }, NOW - 5 * DAY)
  with({ live = { 1, 2, nil } }, function()
    local _, rows = TL():Item(7, NOW)
    assertEqual(rows[1].staleContainer, nil); assertEqual(rows[1].staleAt, nil)
  end)
end)

test("HoldingsTally: a never-scanned container is not reported", function()
  fresh()
  put(ANN, "bags", { [7] = 1 }, NOW)
  H():Get(ANN).scanned.bags = nil
  with({}, function()
    local _, rows = TL():Item(7, NOW)
    assertEqual(rows[1].staleContainer, nil)
  end)
end)

test("HoldingsTally: with two stale containers the oldest wins", function()
  fresh()
  put(ANN, "bags", { [7] = 1 }, NOW - 2 * DAY); put(ANN, "mail", { [7] = 1 }, NOW - 4 * DAY)
  with({}, function()
    local _, rows = TL():Item(7, NOW)
    assertEqual(rows[1].staleContainer, "mail"); assertEqual(rows[1].staleAt, NOW - 4 * DAY)
  end)
end)

test("HoldingsTally: just under a day is not stale", function()
  fresh()
  put(ANN, "bags", { [7] = 1 }, NOW - DAY + 1)
  with({}, function()
    local _, rows = TL():Item(7, NOW)
    assertEqual(rows[1].staleAt, nil)
  end)
end)

test("HoldingsTally: a stored currency a day old is stale; the live holder never is", function()
  fresh()
  H():ApplyCurrency(ME, { [3008] = 10 }, NOW - 3 * DAY); H():ApplyCurrency(ANN, { [3008] = 4 }, NOW - 2 * DAY)
  with({ quantity = 12 }, function()
    local _, rows, n = TL():Currency(3008, NOW)
    assertEqual(rowOf(rows, n, ME).staleAt, nil)
    assertEqual(rowOf(rows, n, ANN).staleAt, NOW - 2 * DAY)
    assertEqual(rowOf(rows, n, ANN).staleContainer, nil)
  end)
end)

-- ── the cache ─────────────────────────────────────────────────────────────────────────────────

test("HoldingsTally: a second call reuses the same entry; output rows are pooled", function()
  fresh()
  put(ANN, "bags", { [7] = 1 })
  with({}, function()
    local e1 = TL():ItemEntry(7)
    local _, rows1 = TL():Item(7, NOW)
    local first = rows1[1]
    local _, rows2 = TL():Item(7, NOW)
    assertTrue(TL():ItemEntry(7) == e1, "a hit answers the same entry")
    assertTrue(rows1 == rows2 and rows2[1] == first, "the scratch array and its rows are reused")
  end)
end)

test("HoldingsTally: the entry copies the store's counts, never aliasing them", function()
  fresh()
  put(ANN, "bags", { [7] = 1 })
  with({}, function()
    local e = TL():ItemEntry(7)
    for _, row in ipairs(e.rows) do
      if row.holder == ANN then assertFalse(row.stored == H():Get(ANN).items[7]) end
    end
  end)
end)

test("HoldingsTally: HOLDINGS_CHANGED wipes the cache", function()
  fresh()
  put(ANN, "bags", { [7] = 1 })
  with({}, function()
    local e1 = TL():ItemEntry(7)
    put(ANN, "bags", { [7] = 9 })
    assertEqual((TL():Item(7, NOW)), 1, "the cached entry answers until the change is announced")
    NS.bus:SendMessage(NS.MSG.HOLDINGS_CHANGED, ANN)
    assertFalse(TL():ItemEntry(7) == e1)
    assertEqual((TL():Item(7, NOW)), 9)
  end)
end)

test("HoldingsTally: SETTINGS_CHANGED wipes the cache for ledger and profile only", function()
  fresh()
  with({}, function()
    local e1 = TL():ItemEntry(7)
    NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "quality")
    assertTrue(TL():ItemEntry(7) == e1, "another reason leaves it")
    NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "ledger")
    local e2 = TL():ItemEntry(7)
    assertFalse(e2 == e1, "ledger wipes it")
    NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "profile")
    assertFalse(TL():ItemEntry(7) == e2, "profile wipes it")
  end)
end)

test("HoldingsTally: the cap of C.TIP_CACHE_MAX wipes both maps before the next insert", function()
  fresh()
  assertEqual(NS.Constants.TIP_CACHE_MAX, 128)
  with({}, function()
    local first = TL():CurrencyEntry(1)
    for id = 1, 127 do TL():ItemEntry(id) end
    assertEqual(TL()._size, 128)
    assertTrue(TL():CurrencyEntry(1) == first, "at the cap, still cached")
    TL():ItemEntry(500)
    assertEqual(TL()._size, 1)
    assertEqual(TL()._items[1], nil); assertEqual(TL()._currencies[1], nil)
  end)
end)

test("HoldingsTally: Disable wipes the cache and drops the target; Enable brings it back", function()
  fresh()
  with({}, function()
    assertTrue(TL().__ev ~= nil, "registered while up")
    local e1 = TL():ItemEntry(7)
    TL():Disable()
    assertEqual(TL().__ev, nil)
    assertFalse(TL():ItemEntry(7) == e1)
    TL():Enable()
    assertTrue(TL().__ev ~= nil)
  end)
end)

-- ── the saved store only ──────────────────────────────────────────────────────────────────────

test("HoldingsTally: test mode and a sim store never reach the tally", function()
  fresh()
  put(ANN, "bags", { [7] = 2 })
  local sample = { [BOB] = { meta = {}, scanned = {}, items = { [7] = { bags = 99 } }, currency = {}, links = {} } }
  with({}, function()
    local off = order(select(2, TL():Item(7, NOW)), select(3, TL():Item(7, NOW)))
    local prev = NS.State.testHoldings
    NS.State.testHoldings, NS.SimStores.holdings = sample, sample
    TL():Invalidate()
    local ok, err = pcall(function()
      local _, rows, n = TL():Item(7, NOW)
      assertEqual(order(rows, n), off)
    end)
    NS.State.testHoldings, NS.SimStores.holdings = prev, nil
    if not ok then error(err, 0) end
  end)
end)
