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
  R().driftPending, R()._readyCheck, R()._bankOpenAt = nil, nil, nil
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

-- R8 (both clients): the bank frame also opens for a CharacterBanker (Enum.PlayerInteractionType 67,
-- BankFrameTemplates registers Banker, CharacterBanker and AccountBanker), so that type arms the
-- bank part exactly as a Banker does: readable while shown, a drift read on open, unreadable on hide.
test("Reconciler: a CharacterBanker interaction makes the bank readable on both clients (R8)", function()
  -- red under: READABLE_ON without a CharacterBanker row, so the bank stays unreadable and dirty.
  reset()
  T.mocks.__bags[6] = { [1] = { itemID = 8, link = "L8", count = 4 } }; T.mocks.__bagSlots[6] = 1
  R():MarkDirty("bank"); R():Flush()
  assertEqual(NS.Holdings:Get(ME()), nil)
  R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", NS.Compat.InteractionType("CharacterBanker"))
  assertTrue(R():IsReadable("bank"), "readable while the CharacterBanker frame is shown")
  assertTrue(R().driftPending, "the visit's first read is a drift read")
  R():Flush()
  assertEqual(NS.Holdings:Get(ME()).items[8].bank, 4)
  R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", NS.Compat.InteractionType("CharacterBanker"))
  assertFalse(R():IsReadable("bank"))
  assertEqual(R().driftPending, nil)
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
  if T.forever then
    -- The warband bank is Retail-only (R1): no warband gold is read, so the account holder has none.
    local w = NS.Holdings:Get("§warband")
    assertEqual(w and w.money, nil, "no warband gold on WoW Forever")
  else
    assertEqual(NS.Holdings:Get("§warband").money, 70)
  end
  T.mocks.__warbandMoney = 0
end)

-- clients-§6: a per-client feature has a case on each profile, present where declared and absent
-- where not. The warband bank (C.FEATURE.warbandBank, ruling R1) is Retail's.
test("Reconciler: the warband bank's parts, events and reads exist only on Retail (R1)", function()
  -- red under: a WoW Forever build that registers ACCOUNT_MONEY or the tab-slot event, arms the
  -- `tabs` / `warbandMoney` parts at a banker, or reads warband gold.
  local rows = {}
  for _, row in ipairs(NS.EVENT_ROWS) do
    if row.owner == "Reconciler" then rows[row.event] = true end
  end
  local onRetail = not T.forever
  assertEqual(rows.ACCOUNT_MONEY == true, onRetail, "the ACCOUNT_MONEY row")
  assertEqual(rows.PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED == true, onRetail, "the tab-slot row")
  assertTrue(rows.PLAYERBANKSLOTS_CHANGED, "the character bank's row serves both clients")
  assertEqual(table.concat(R().BANKER_ARMS.character.parts, ","),
    onRetail and "bank,tabs,warbandMoney" or "bank", "a character banker's parts")
  -- The warband-only banker arms the bank where the warband bank is a feature, and nowhere else.
  local account = R().BANKER_ARMS.account
  assertEqual(account ~= nil, onRetail, "AccountBanker arms the bank on Retail only")
  if account then assertEqual(table.concat(account.parts, ","), "bank,tabs,warbandMoney") end
  T.mocks.__warbandMoney = 70
  assertEqual(R():IsReadable("warbandMoney"), onRetail, "warband gold is read on Retail only")
  T.mocks.__warbandMoney = 0
end)

-- R8 (both clients): the bank readiness guard's view check and its re-read cues.
test("Reconciler: Compat.CanViewCharacterBank answers C_Bank.CanViewBank(Character), nil without it (R8)", function()
  -- red under: no Compat.CanViewCharacterBank member, or one that guesses when the build cannot tell
  -- (LibKa0s-Compat minor 6 is three-valued; R:BankState reads nil as viewable).
  local m = T.mocks
  local saved, savedFn = m.__canViewBank, m.C_Bank.CanViewBank
  local ok, err = pcall(function()
    m.__canViewBank = { [0] = true }
    assertEqual(NS.Compat.CanViewCharacterBank(), true)
    m.__canViewBank = { [0] = false, [2] = true }
    assertEqual(NS.Compat.CanViewCharacterBank(), false, "a warband-only banker hides the character bank")
    m.C_Bank.CanViewBank = nil
    assertEqual(NS.Compat.CanViewCharacterBank(), nil, "a client with no CanViewBank cannot tell")
  end)
  m.__canViewBank, m.C_Bank.CanViewBank = saved, savedFn
  if not ok then error(err, 0) end
end)

test("Reconciler: Compat.NumPurchasedBankTabs(\"Character\") answers FetchNumPurchasedBankTabs(Character), nil without it (R8)", function()
  -- red under: no Compat.NumPurchasedBankTabs member, or one that reads the bank type by number.
  local m = T.mocks
  local savedFn = m.C_Bank.FetchNumPurchasedBankTabs
  local ok, err = pcall(function()
    m.C_Bank.FetchNumPurchasedBankTabs = function(t) return t == 0 and 3 or 1 end
    assertEqual(NS.Compat.NumPurchasedBankTabs("Character"), 3)
    assertEqual(NS.Compat.NumPurchasedBankTabs("Account"), 1)
    m.C_Bank.FetchNumPurchasedBankTabs = function() return "x" end
    assertEqual(NS.Compat.NumPurchasedBankTabs("Character"), nil, "a non-number is no answer")
    m.C_Bank.FetchNumPurchasedBankTabs = nil
    assertEqual(NS.Compat.NumPurchasedBankTabs("Character"), nil, "a client without it answers nil")
  end)
  m.C_Bank.FetchNumPurchasedBankTabs = savedFn
  if not ok then error(err, 0) end
end)

test("Reconciler: BAG_CONTAINER_UPDATE and BANK_TABS_CHANGED re-read an open bank on both clients (R8)", function()
  -- red under: no cue rows, so a bank tab that loads (or a socket that changes) with no BAG_UPDATE
  -- is never looked at again while the bank is open.
  reset()
  local rows = {}
  for _, row in ipairs(NS.EVENT_ROWS) do
    if row.owner == "Reconciler" then rows[row.event] = true end
  end
  for _, ev in ipairs({ "BAG_CONTAINER_UPDATE", "BANK_TABS_CHANGED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE_DELAYED" }) do
    assertTrue(rows[ev], ev .. " is a Reconciler row")
  end
  for _, ev in ipairs({ "BAG_CONTAINER_UPDATE", "BANK_TABS_CHANGED" }) do
    reset()
    R():OnEvent(ev, 0)
    assertEqual(R().dirty.bank, nil, ev .. " with no banker open marks nothing")
    R().readable.bank = true
    R():OnEvent(ev, 0)
    assertTrue(R().dirty.bank, ev .. " at an open bank re-reads the bank")
    assertEqual(R().dirty.tabs == true, not T.forever, ev .. " re-reads the warband tabs where they exist")
  end
  reset()
end)

test("Reconciler: a warband-only banker leaves the character bank unread and dirty (R8)", function()
  -- red under: IsReadable("bank") true at a banker whatever CanViewBank(Character) answers.
  reset()
  local m = T.mocks
  local saved = m.__canViewBank
  m.__canViewBank = { [0] = false, [1] = true, [2] = not T.forever }
  local ok, err = pcall(function()
    m.__bags[6] = { [1] = { itemID = 8, link = "L8", count = 4 } }; m.__bagSlots[6] = 1
    R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", NS.Compat.InteractionType("Banker"))
    assertEqual(R():BankState(), "unviewable")
    assertFalse(R():IsReadable("bank"))
    R():Flush()
    local e = NS.Holdings:Get(ME())
    assertEqual(e and e.items[8], nil, "the character bank is not read")
    assertTrue(R().dirty.bank, "and stays dirty for a banker that shows it")
    R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", NS.Compat.InteractionType("Banker"))
  end)
  m.__canViewBank = saved
  if not ok then error(err, 0) end
  reset()
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

-- LH-11 characterization: what each capture event does to the dirty bits and the flush fuse, and
-- which interaction / currency handler it reaches. Pinned before onEvent became a file-scope
-- handler table; the readable gates on the mailbox and owned-auction events are pinned both ways.
local function routeOf(event, readable, ...)
  reset()
  local r = R()
  r.readable = readable or {}
  r.pendingTransfer = nil
  local fuses, calls = 0, {}
  local savedAfter, savedInter, savedCur = NS.After, r.OnInteraction, r.OnCurrencyUpdate
  NS.After = function() fuses = fuses + 1; return nil end
  r.OnInteraction = function(_, shown, it) calls[#calls + 1] = "inter:" .. tostring(shown) .. ":" .. tostring(it) end
  r.OnCurrencyUpdate = function(_, ...) calls[#calls + 1] = "cur:" .. table.concat({ tostring(select(1, ...)),
    tostring(select(2, ...)), tostring(select(3, ...)), tostring(select(4, ...)) }, ",") end
  local ok, err = pcall(r.OnEvent, r, event, ...)
  NS.After, r.OnInteraction, r.OnCurrencyUpdate = savedAfter, savedInter, savedCur
  assertTrue(ok, tostring(err))
  local keys = {}
  for k, v in pairs(r.dirty) do
    if type(v) == "table" then
      local sub = {}
      for b in pairs(v) do sub[#sub + 1] = tostring(b) end
      table.sort(sub)
      keys[#keys + 1] = k .. "[" .. table.concat(sub, ",") .. "]"
    else keys[#keys + 1] = k end
  end
  table.sort(keys)
  local out = table.concat(keys, " ") .. " | fuse=" .. fuses .. " | " .. table.concat(calls, ";")
  if r.pendingTransfer then out = out .. " | transfer" end
  if r.readable.auctions then out = out .. " | auctions-readable" end
  return out
end

test("Reconciler: every capture event routes to its dirty part, fuse and handler (LH-11)", function()
  local C = NS.Constants
  -- The warband bank's routes are Retail's (R1): on WoW Forever a warband tab id is no part of its
  -- own, and its two events reach no handler.
  local tab = T.bagIndex("AccountBankTab_1")
  local cases = {
    { "BAG_UPDATE", nil, { 0 }, "bags[0] | fuse=0 | " },
    { "BAG_UPDATE", nil, { C.BANK_IDS[1] }, "bank | fuse=0 | " },
    { "BAG_UPDATE", nil, { tab }, T.forever and ("bags[" .. tab .. "] | fuse=0 | ") or "tabs | fuse=0 | " },
    { "BAG_UPDATE", nil, {}, "bags[] | fuse=0 | " },
    { "BAG_UPDATE_DELAYED", nil, {}, " | fuse=1 | " },
    { "PLAYER_EQUIPMENT_CHANGED", nil, {}, "equipped | fuse=1 | " },
    { "PLAYER_MONEY", nil, {}, "money | fuse=1 | " },
    { "ACCOUNT_MONEY", nil, {}, T.forever and " | fuse=0 | " or "warbandMoney | fuse=1 | " },
    { "CURRENCY_DISPLAY_UPDATE", nil, { 7, "x", 3, 4, 5 }, " | fuse=0 | cur:7,3,4,5" },
    { "CURRENCY_TRANSFER_LOG_UPDATE", nil, {}, "currencyDelta | fuse=1 |  | transfer" },
    { "PLAYERBANKSLOTS_CHANGED", nil, {}, "bank | fuse=1 | " },
    { "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", nil, {}, T.forever and " | fuse=0 | " or "tabs | fuse=1 | " },
    { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", nil, { 17 }, " | fuse=0 | inter:true:17" },
    { "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", nil, { 17 }, " | fuse=0 | inter:false:17" },
    { "MAIL_INBOX_UPDATE", nil, {}, " | fuse=0 | " },
    { "MAIL_INBOX_UPDATE", { mail = true }, {}, "mail | fuse=1 | " },
    { "OWNED_AUCTIONS_UPDATED", nil, {}, " | fuse=0 | " },
    { "OWNED_AUCTIONS_UPDATED", { auctionHouse = true }, {}, "auctions | fuse=1 |  | auctions-readable" },
    { "SOME_UNKNOWN_EVENT", nil, { 1 }, " | fuse=0 | " },
  }
  for _, c in ipairs(cases) do
    local a = c[3]
    assertEqual(routeOf(c[1], c[2], a[1], a[2], a[3], a[4], a[5]), c[4], c[1])
  end
  reset()
end)

-- R:ResetState (LootHistory#37, req-lh-sim §3.4): the working state a simulation start and stop
-- must clear, split out of DisableCapture so it can run WITHOUT unregistering. The two fuses are
-- canceled one handle at a time through NS.CancelDeferral, never through NS.CancelDeferrals, which
-- would also take the login deferrals down.
test("Reconciler: ResetState clears every working table and cancels _pending and _recheck but leaves registrations",
  function()
    local r, m = R(), T.mocks
    local ev, settings, enabled = r.__ev, r._settings, r._enabled
    local regs = #m.__registrations()
    local ran = {}
    r._pending = NS.After(60, function() ran[#ran + 1] = "pending" end)
    r._recheck = nil
    r:ScheduleRecheck()
    local pendingH, recheckH = r._pending, r._recheck
    assertEqual(type(pendingH), "table", "the flush fuse must hold its NS.After handle")
    assertEqual(type(recheckH), "table", "the recheck fuse must hold its NS.After handle")
    local bystander = NS.After(60, function() ran[#ran + 1] = "bystander" end)
    r.dirty, r.readable = { bags = { [0] = true }, money = true }, { bank = true }
    r.deferred, r.driftPending = true, true
    r.claims, r.recent, r.reasonMemo = { x = 1 }, { x = 1 }, { x = 1 }
    r.pendingCur, r.curGain, r.curLoss = { [7] = 1 }, { [7] = 1 }, { [7] = 1 }
    r.pendingTransfer, r.loginPending, r._holdSince = true, true, 12

    r:ResetState()

    for _, k in ipairs({ "dirty", "readable", "claims", "recent", "reasonMemo", "pendingCur", "curGain",
                         "curLoss" }) do
      assertEqual(type(r[k]), "table", k .. " must be an empty table, not nil")
      assertEqual(next(r[k]), nil, k .. " survived ResetState")
    end
    for _, k in ipairs({ "deferred", "_pending", "driftPending", "pendingTransfer", "loginPending",
                         "_holdSince", "_recheck" }) do
      assertEqual(r[k], nil, k .. " survived ResetState")
    end
    assertTrue(pendingH.canceled and recheckH.canceled, "both fuses must be canceled, not just forgotten")
    assertFalse(bystander.canceled, "ResetState canceled a deferral that was not its own")
    assertTrue(r.__ev == ev and r._settings == settings and r._enabled == enabled,
      "ResetState must not touch the bus targets or the enabled flag")
    assertEqual(#m.__registrations(), regs, "ResetState changed the registrations")
    m.__fireTimers()
    assertEqual(table.concat(ran, ","), "bystander", "a canceled fuse still woke up")
    reset()
  end)

-- req-lh-sim §4 (LootHistory#37): the 60 s coalescing check reads the row back through
-- Database:History, so during a simulation it finds the row in the session store it was written
-- to. Read straight off db.global.history, the check misses and every write lands as a new row.
test("Reconciler: coalescing reads Database:History (session-aware)", function()
  local r = R()
  local savedRecent = r.recent
  local live = NS.db.global.history
  local liveCount = #live
  local session = {}
  r.recent = {}
  NS.SimStores.history = session
  local ok, err = pcall(function()
    local now = os.time()
    local first = r:Write(ME(), "g", "IN", "LOOT", 100, now)
    local second = r:Write(ME(), "g", "IN", "LOOT", 50, now + 5)
    assertTrue(first ~= nil and second == first, "the second write amends the first row")
    assertEqual(#session, 1, "one coalesced row in the session store")
    assertEqual(session[1].quantity, 150)
  end)
  NS.SimStores.history = nil
  r.recent = savedRecent
  if not ok then error(err, 0) end
  assertTrue(NS.db.global.history == live and #live == liveCount, "the live history was not written")
end)

-- K101-LH-02 (LibKa0s#101): characterization of the bank readiness answers and the banker arming,
-- pinned on the addon's own copies BEFORE they were swapped for LibKa0s-Compat minor 6's readers,
-- and kept green after. Both kit profiles.
test("Reconciler: BankState answers the same outcome for each bank shape (R8, K101-LH-02)", function()
  -- red under: a readiness reader that changes any row below: a warband-only banker read, a
  -- partly loaded visit 2 taken as ready, a first visit short of its bought tabs taken as ready,
  -- a build that cannot tell whether the bank is viewable read as unviewable, or the deadline gone.
  local m = T.mocks
  local savedView, savedViewFn = m.__canViewBank, m.C_Bank.CanViewBank
  local savedFetch, savedNow = m.C_Bank.FetchNumPurchasedBankTabs, m.__now
  local C = NS.Constants
  local tab1, tab2 = C.BANK_IDS[1], C.BANK_IDS[2]
  local function memory(slots) NS.Holdings:NoteBankSlots(ME(), slots) end
  local function slots(a, b) m.__bagSlots[tab1], m.__bagSlots[tab2] = a, b end
  local ok, err = pcall(function()
    reset()
    m.__now = 100
    assertEqual(R():BankState(), nil, "no banker open: no state")
    R().readable.bank, R()._bankOpenAt = true, 100
    -- First visit (no memory). No bought-tab count: the read is taken as it is found.
    m.C_Bank.FetchNumPurchasedBankTabs = nil
    slots(0, 0)
    assertEqual(R():BankState(), "ready", "first visit, no bought-tab count")
    m.C_Bank.FetchNumPurchasedBankTabs = function(t) return t == 0 and 2 or 0 end
    slots(1, 0)
    assertEqual(R():BankState(), "loading", "first visit, fewer containers answer than tabs bought")
    slots(1, 1)
    assertEqual(R():BankState(), "ready", "first visit, every bought tab answers")
    -- Visit 2 (memory kept from the last ready read).
    memory({ [tab1] = 1, [tab2] = 1 })
    slots(1, 0)
    assertEqual(R():BankState(), "loading", "visit 2, a container that had slots answers 0")
    slots(1, 1)
    assertEqual(R():BankState(), "ready", "visit 2, every remembered container answers")
    memory({ [tab1] = 1, [tab2] = 0 })
    slots(1, 0)
    assertEqual(R():BankState(), "ready", "visit 2, a container that never had slots never blocks")
    memory({ [tab1] = 0, [tab2] = 0 })
    slots(0, 0)
    assertEqual(R():BankState(), "ready", "visit 2, a memory of no slots at all: the read is taken")
    -- The deadline: past READY_WAIT a 0 is believed.
    memory({ [tab1] = 1, [tab2] = 1 })
    slots(1, 0)
    m.__now = 100 + R().READY_WAIT
    assertEqual(R():BankState(), "ready", "past the deadline")
    m.__now = 100
    -- Viewability.
    m.__canViewBank = { [0] = false, [1] = true, [2] = not T.forever }
    assertEqual(R():BankState(), "unviewable", "a banker that hides the character bank")
    m.C_Bank.CanViewBank = nil
    slots(1, 1)
    assertEqual(R():BankState(), "ready", "a build that cannot tell is read as viewable")
  end)
  m.__canViewBank, m.C_Bank.CanViewBank = savedView, savedViewFn
  m.C_Bank.FetchNumPurchasedBankTabs, m.__now = savedFetch, savedNow
  reset()
  if not ok then error(err, 0) end
end)

test("Reconciler: each interaction type arms what it arms, per client (R1, R8, K101-LH-02)", function()
  -- red under: a banker kind that arms the wrong flag or parts, AccountBanker arming on WoW
  -- Forever, a non-banker type arming the bank, or a nil type arming anything.
  local onRetail = not T.forever
  local bankParts = onRetail and "bank,tabs,warbandMoney" or "bank"
  local function arms(t)
    reset()
    R().dirty = {}
    R():OnInteraction(true, t)
    local flags, parts = {}, {}
    for k, v in pairs(R().readable) do if v then flags[#flags + 1] = k end end
    for k in pairs(R().dirty) do parts[#parts + 1] = k end
    table.sort(flags); table.sort(parts)
    local drift = R().driftPending == true
    R():OnInteraction(false, t)
    return table.concat(flags, ","), table.concat(parts, ","), drift
  end
  local I = NS.Compat.InteractionType
  local cases = {
    { "Banker",          "bank",                 bankParts, true },
    { "CharacterBanker", "bank",                 bankParts, true },
    { "AccountBanker",   onRetail and "bank" or "", onRetail and bankParts or "", onRetail },
    { "MailInfo",        "mail",                 "mail",    false },
    { "Auctioneer",      "auctionHouse",         "",        false },
    { "Merchant",        "",                     "",        false },
  }
  local ok, err = pcall(function()
    for _, c in ipairs(cases) do
      local flags, parts, drift = arms(I(c[1]))
      assertEqual(flags, c[2], c[1] .. "'s readable flags")
      assertEqual(parts, c[3], c[1] .. "'s dirty parts")
      assertEqual(drift, c[4], c[1] .. " opens a drift visit")
    end
    local flags, parts = arms(nil)
    assertEqual(flags .. "|" .. parts, "|", "a nil type arms nothing")
  end)
  reset()
  if not ok then error(err, 0) end
end)

test("Reconciler: a claim waits out combat, so one loot is one row", function()
  reset()
  local m, r = T.mocks, R()
  local savedNow, savedICL, savedEnabled = m.__now, m.InCombatLockdown, r._enabled
  local savedForce, savedSilent = r.forceReason, r.silent
  local function combat(on)
    m.InCombatLockdown = function() return on end
    rawset(_G, "InCombatLockdown", m.InCombatLockdown)
  end
  r._enabled, r.forceReason, r.silent, r.claims = true, nil, nil, {}
  m.__now = 100
  combat(false)
  r:MarkDirty("bags", 0); r:Flush()
  NS.Holdings:MarkGenesis(ME(), 1)
  local row = { itemID = 17058, quantity = 1, source = "KILL" }
  local before = #NS.db.global.history
  combat(true)
  r:PostClaim(NS.Ledger.ThingKey("ITEM", 17058), 1, row)
  m.__bags[0] = { [1] = { itemID = 17058, link = "L17058", count = 1 } }; m.__bagSlots[0] = 1
  r:MarkDirty("bags", 0); r:Flush()
  m.__now = 110
  combat(false)
  r:OnEvent("PLAYER_REGEN_ENABLED")
  local after = #NS.db.global.history
  m.__now, r._enabled, r.forceReason, r.silent, r.claims = savedNow, savedEnabled, savedForce, savedSilent, {}
  m.InCombatLockdown = savedICL; rawset(_G, "InCombatLockdown", savedICL)
  -- red under: the claim aging out (5 s) while the flush waited for combat to end
  assertEqual(after, before, "a second row for the same loot")
  assertTrue(row.claimed == true, "the chat row took the delta")
end)
