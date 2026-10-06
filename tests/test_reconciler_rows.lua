local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- modules/Reconciler.lua, Phase 2 (timeline-ledger spec §5.1-§5.5): a flush scans, plans rows
-- against the stored baseline, then holds or commits. These cases pin the rows it writes: moves,
-- one-sided holds, reasons, claims, coalescing and the per-kind gates. Like tests/test_reconciler.lua
-- they drive OnEvent / MarkDirty / Flush directly; the module is not stood up in this slot.

local m = T.mocks
local R = function() return NS.Reconciler end
local ME
local function H() return NS.db.global.history end

-- Every case runs on a frozen wall clock (row ts, the 60 s coalescing window) and restores the
-- shared mock on the way out whether the body passed or threw.
local function case(name, body)
  test(name, function()
    local savedTime, savedICL = m.time, m.InCombatLockdown
    local savedList, savedWide, savedXfer = m.__currencyList, m.__currencyAccountWide, m.__currencyTransfers
    local savedClass, savedEnabled = m.__itemClassID, R()._enabled
    m.__epoch, m.__now = 5000, 100
    m.time = function() return m.__epoch end
    local ok, err = pcall(body)
    m.time, m.InCombatLockdown = savedTime, savedICL
    m.__itemClassID, R()._enabled = savedClass, savedEnabled
    m.__currencyList, m.__currencyAccountWide, m.__currencyTransfers = savedList, savedWide, savedXfer
    if not ok then error(err, 0) end
  end)
end

local function setBag(bagID, slots)
  m.__bags[bagID] = slots
  local n = 0; for s in pairs(slots) do if s > n then n = s end end
  m.__bagSlots[bagID] = n
end

local function reset()
  ME = NS.Util.PlayerKey()
  NS.db.global.history, NS.db.global.holdings = {}, {}
  m.__bags, m.__bagSlots, m.__inventory, m.__money, m.__warbandMoney = {}, {}, {}, 0, 0
  m.__itemClassID = 4                                     -- not consumable unless a case says so
  NS.db.profile.blacklist = {}
  NS.db.profile.settings.recordGold = true
  local r = R()
  r.dirty, r.readable, r.deferred, r._holdSince = {}, {}, nil, nil
  r.claims, r.recent, r.reasonMemo = {}, {}, {}
  r._pending, r._recheck = nil, nil                       -- a stale fuse from another case never suppresses scheduling
  r.pendingCur, r.curGain, r.curLoss, r.pendingTransfer, r.loginPending = {}, {}, {}, nil, nil
  r._enabled = true
  NS.State.outContext, NS.State.lootContext = nil, nil
  for k in pairs(NS.State.scopes) do NS.State.scopes[k] = nil end
end

-- Seed the stored baseline for the carried parts and stamp genesis, writing nothing.
local function genesis()
  for _, p in ipairs({ "bags", "equipped", "money" }) do R():MarkDirty(p) end
  R().silent = true; R():Flush(); R().silent = nil
  NS.Holdings:MarkGenesis(ME, m.__epoch)
end

local function openBank(kind)
  R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", NS.Compat.InteractionType(kind or "Banker"))
end

case("Reconciler: bag to bank deposit writes one MOVE and no gain or loss", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 5 } })
  genesis()
  openBank(); setBag(6, {}); R():Flush()                  -- the bank's first scan is its own genesis
  assertEqual(#H(), 0)
  setBag(0, {}); setBag(6, { [1] = { itemID = 7, link = "L7", count = 5 } })
  R():MarkDirty("bags"); R():MarkDirty("bank"); R():Flush()
  assertEqual(#H(), 1)
  local r = H()[1]
  assertEqual(r.dir, "MOVE"); assertEqual(r.source, "TRANSFER"); assertEqual(r.quantity, 5)
  assertEqual(r.from, ME .. "/bags"); assertEqual(r.to, ME .. "/bank")
  assertEqual(r.holder, ME); assertEqual(r.kind, "ITEM"); assertEqual(r.itemID, 7)
end)

case("Reconciler: a one-sided change at an open bank is held, then paired", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 2 } })
  genesis()
  openBank(); setBag(6, {}); R():Flush()
  setBag(0, {})                                           -- bags update first ...
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 0); assertTrue(R()._holdSince ~= nil)
  m.__now = 102
  setBag(6, { [1] = { itemID = 7, link = "L7", count = 2 } })   -- ... the bank a round-trip later
  R():MarkDirty("bank"); R():Flush()
  assertEqual(#H(), 1); assertEqual(H()[1].dir, "MOVE")
  assertEqual(NS.Holdings:Get(ME).items[7].bank, 2)
end)

case("Reconciler: vendor sale writes item OUT SELL and gold IN SELL", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 1 } }); m.__money = 1000
  genesis()
  NS.Attribution:SetScope("merchant", true)
  setBag(0, {}); m.__money = 1500
  R():MarkDirty("bags"); R():MarkDirty("money"); R():Flush()
  assertEqual(#H(), 0)                                    -- the gold gain waits for a claim
  m.__now = 102; R():Flush()
  assertEqual(#H(), 2)
  local byKind = {}
  for _, r in ipairs(H()) do byKind[r.kind] = r end
  assertEqual(byKind.ITEM.dir, "OUT"); assertEqual(byKind.ITEM.source, "SELL")
  assertEqual(byKind.GOLD.dir, "IN"); assertEqual(byKind.GOLD.source, "SELL"); assertEqual(byKind.GOLD.quantity, 500)
  assertEqual(byKind.GOLD.itemName, "Gold")
end)

case("Reconciler: combat potion burst lands as one CONSUME row and coalesces", function()
  reset()
  m.__itemClassID = 0
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 10 } })
  genesis()
  local scans, base = 0, NS.Scanner.ScanContainers
  NS.Scanner.ScanContainers = function(...) scans = scans + 1; return base(...) end
  m.InCombatLockdown = function() return true end
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 5 } })
  for _ = 1, 20 do R():OnEvent("BAG_UPDATE", 0); R():OnEvent("BAG_UPDATE_DELAYED") end
  R():Flush()
  assertEqual(scans, 0); assertEqual(#H(), 0)
  m.InCombatLockdown = function() return false end
  R():OnEvent("PLAYER_REGEN_ENABLED")
  assertEqual(#H(), 1)
  assertEqual(H()[1].source, "CONSUME"); assertEqual(H()[1].quantity, 5); assertEqual(H()[1].dir, "OUT")
  m.__epoch = m.__epoch + 30
  setBag(0, {})
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 1); assertEqual(H()[1].quantity, 10)  -- amended, not appended
  m.__epoch = m.__epoch + 61
  NS.Scanner.ScanContainers = base
end)

case("Reconciler: rows after the 60 s window append", function()
  reset()
  m.__itemClassID = 0
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 3 } })
  genesis()
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 2 } }); R():MarkDirty("bags"); R():Flush()
  m.__epoch = m.__epoch + 60
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 1 } }); R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 2)
end)

case("Reconciler: a warband deposit is a MOVE pair, one row per holder", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 2 } })
  genesis()
  openBank("AccountBanker"); setBag(12, {}); R():Flush()
  NS.Holdings:MarkGenesis(NS.Constants.WARBAND_HOLDER, m.__epoch)
  setBag(0, {}); setBag(12, { [1] = { itemID = 7, link = "L7", count = 2 } })
  R():MarkDirty("bags"); R():MarkDirty("tabs"); R():Flush()
  assertEqual(#H(), 2)
  local holders = {}
  for _, r in ipairs(H()) do
    assertEqual(r.dir, "MOVE"); assertEqual(r.from, ME .. "/bags"); assertEqual(r.to, "§warband/tabs")
    holders[r.holder] = true
  end
  assertTrue(holders[ME] and holders["§warband"])
end)

case("Reconciler: a posted claim absorbs the gain and stamps the chat row", function()
  reset()
  genesis()
  local chatRow = { itemID = 7, quantity = 3 }
  R():PostClaim("i:7", 3, chatRow)
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 3 } })
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 0)
  assertTrue(chatRow.claimed); assertEqual(chatRow.dir, "IN"); assertEqual(chatRow.holder, ME)
  assertEqual(chatRow.kind, "ITEM")
end)

case("Reconciler: blacklisted items never get a row but holdings still count them", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 4 } })
  genesis()
  NS.db.profile.blacklist = { [7] = true }
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 1 } })
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 0)
  assertEqual(NS.Holdings:Get(ME).items[7].bags, 1)
end)

case("Reconciler: recordGold off suppresses gold rows only", function()
  reset()
  m.__money = 100
  genesis()
  NS.db.profile.settings.recordGold = false
  NS.Attribution:SetScope("merchant", true)
  m.__money = 50
  R():MarkDirty("money"); R():Flush()
  assertEqual(#H(), 0)
  assertEqual(NS.Holdings:Get(ME).money, 50)
end)

case("Reconciler: no genesis, no rows", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 4 } })
  R():MarkDirty("bags"); R():Flush()
  setBag(0, {})
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 0)
end)

case("Reconciler: an unexplained loss with no stamp is OTHER", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 1 } })
  genesis()
  setBag(0, {})
  R():MarkDirty("bags"); R():Flush()
  assertEqual(H()[1].source, "OTHER"); assertEqual(H()[1].confidence, "INFERRED")
end)

-- The chat path and the holdings diff together (Task 8): a chat row claims its gain, so the diff
-- never writes the same stack twice, whichever side lands first.
local LINK = "|cffa335ee|Hitem:211296::::::::80:::::|h[Vial of Fun]|h|r"

local function chatLoot(qty)
  NS.db.profile.settings.qualityThreshold = 1
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgLoot(nil, string.format(m.LOOT_ITEM_SELF_MULTIPLE, LINK, qty))
end

case("Collector+Reconciler: a looted stack is counted once, chat first", function()
  reset()
  genesis()
  chatLoot(3)
  setBag(0, { [1] = { itemID = 211296, link = LINK, count = 3 } })
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 1)
  assertTrue(H()[1].claimed); assertEqual(H()[1].dir, "IN")
  assertEqual(NS.Holdings:Get(ME).items[211296].bags, 3)
end)

case("Collector+Reconciler: a looted stack is counted once, delta first", function()
  reset()
  genesis()
  setBag(0, { [1] = { itemID = 211296, link = LINK, count = 3 } })
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 0)                                    -- held: waiting for the claim
  m.__now = 100.4
  chatLoot(3)
  R():Flush()
  assertEqual(#H(), 1); assertTrue(H()[1].claimed)
end)

case("Collector+Reconciler: a partial claim leaves the remainder as a diff row", function()
  reset()
  genesis()
  chatLoot(2)
  setBag(0, { [1] = { itemID = 211296, link = LINK, count = 5 } })
  R():MarkDirty("bags"); R():Flush()                      -- 3 unclaimed: held
  m.__now = 102; R():Flush()
  assertEqual(#H(), 2)
  assertEqual(H()[2].quantity, 3); assertEqual(H()[2].dir, "IN"); assertTrue(H()[2].claimed == nil)
end)

case("Collector+Reconciler: looted gold is counted once", function()
  reset()
  m.__money = 0
  genesis()
  NS.db.profile.settings.trackLedger = true
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgMoney(nil, "You loot 45 Copper")
  m.__money = 45
  R():MarkDirty("money"); R():Flush()
  assertEqual(#H(), 1); assertEqual(H()[1].kind, "GOLD"); assertTrue(H()[1].claimed)
end)

-- ── Task 9: currency deltas, account transfers, login and resume reconcile (spec §5.2, §5.6) ──

local function genesisWithCurrency(list)
  m.__currencyList = list
  for _, p in ipairs({ "bags", "equipped", "money", "currency" }) do R():MarkDirty(p) end
  R().silent = true; R():Flush(); R().silent = nil
  NS.Holdings:MarkGenesis(ME, m.__epoch)
  if NS.Holdings:Get("§warband") then NS.Holdings:MarkGenesis("§warband", m.__epoch) end
end

case("Reconciler: first login is genesis and writes nothing", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 4 } }); m.__money = 900
  R():LoginScan()
  assertEqual(#H(), 0)
  local e = NS.Holdings:Get(ME)
  assertTrue(e.meta.genesis ~= nil); assertEqual(e.items[7].bags, 4); assertEqual(e.money, 900)
end)

case("Reconciler: login drift writes UNTRACKED rows, no holds, claims untouched", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 4 } }); m.__money = 900
  R():LoginScan()
  R():PostClaim("i:7", 2, {})
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 6 } }); m.__money = 400
  R():LoginScan()
  assertEqual(#H(), 2)
  for _, r in ipairs(H()) do assertEqual(r.source, "UNTRACKED"); assertEqual(r.confidence, "INFERRED") end
  assertEqual(NS.Ledger.ClaimAvailable(R().claims, "i:7", m.__now), 2)
end)

case("Reconciler: a login in combat waits for regen", function()
  reset()
  m.InCombatLockdown = function() return true end
  R():LoginScan()
  assertEqual(NS.Holdings:Get(ME), nil); assertTrue(R().loginPending)
  m.InCombatLockdown = function() return false end
  R():OnEvent("PLAYER_REGEN_ENABLED")
  assertTrue(NS.Holdings:Get(ME).meta.genesis ~= nil)
end)

case("Reconciler: a currency spend from the event args is an OUT with its mapped reason", function()
  reset()
  genesisWithCurrency({ { id = 3008, quantity = 50 } })
  R():OnEvent("CURRENCY_DISPLAY_UPDATE", 3008, 40, -10, nil, m.Enum.CurrencyDestroyReason.Vendor)
  R():Flush()
  assertEqual(#H(), 1)
  local r = H()[1]
  assertEqual(r.kind, "CURRENCY"); assertEqual(r.currencyID, 3008); assertEqual(r.dir, "OUT")
  assertEqual(r.quantity, 10); assertEqual(r.source, "BUY")
  assertEqual(NS.Holdings:Get(ME).currency[3008], 40)
end)

case("Reconciler: currency events in combat accumulate, one row after regen", function()
  reset()
  genesisWithCurrency({ { id = 3008, quantity = 50 } })
  m.InCombatLockdown = function() return true end
  for _ = 1, 5 do R():OnEvent("CURRENCY_DISPLAY_UPDATE", 3008, nil, -2, nil, m.Enum.CurrencyDestroyReason.Spell) end
  R():Flush()
  assertEqual(#H(), 0)
  m.InCombatLockdown = function() return false end
  R():OnEvent("PLAYER_REGEN_ENABLED")
  assertEqual(#H(), 1); assertEqual(H()[1].quantity, 10); assertEqual(H()[1].source, "CONSUME")
end)

case("Reconciler: an account-wide currency change lands on the warband holder", function()
  reset()
  m.__currencyAccountWide = { [2032] = true }
  genesisWithCurrency({ { id = 2032, quantity = 5, accountWide = true } })
  R():OnEvent("CURRENCY_DISPLAY_UPDATE", 2032, 3, -2, nil, nil)
  R():Flush()
  assertEqual(H()[1].holder, "§warband")
  assertEqual(NS.Holdings:Get("§warband").currency[2032], 3)
  m.__currencyAccountWide = {}
end)

case("Reconciler: an account currency transfer to an own alt is a MOVE pair and credits the alt", function()
  reset()
  genesisWithCurrency({ { id = 3008, quantity = 50 } })
  NS.db.global.holdings["Alt-Realm"] = { meta = { genesis = 1 }, scanned = { currency = 1 },
    items = {}, currency = {}, links = {} }
  m.__currencyTransfers = { { currencyType = 3008, quantityTransferred = 10, destinationCharacterName = "Alt" } }
  R():OnEvent("CURRENCY_TRANSFER_LOG_UPDATE")
  R():OnEvent("CURRENCY_DISPLAY_UPDATE", 3008, 38, -12, nil, m.Enum.CurrencyDestroyReason.AccountTransfer)
  R():Flush()
  local moves, outs = 0, 0
  for _, r in ipairs(H()) do
    if r.dir == "MOVE" then moves = moves + 1; assertEqual(r.to, "Alt-Realm/currency") end
    if r.dir == "OUT" then outs = outs + 1; assertEqual(r.quantity, 2); assertEqual(r.source, "TRANSFER") end
  end
  assertEqual(moves, 2); assertEqual(outs, 1)               -- 10 moved, 2 was the transfer fee
  assertEqual(NS.db.global.holdings["Alt-Realm"].currency[3008], 10)
  m.__currencyTransfers = {}
end)

-- Adapted from the plan's snippet: the mock's C_Timer queues rather than runs, so the resume
-- deferral is captured and called by hand; and the case ends on Disable (not DisableCapture) so the
-- `_settings` target Enable created is torn down for tests/test_disabled.lua's survey.
case("Reconciler: changes made while stood down land as UNTRACKED on resume", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 1 } })
  R():LoginScan()
  R():DisableCapture()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 3 } })
  local savedAfter, fn = NS.After, nil
  NS.After = function(_, f) fn = f end
  R():Enable()
  NS.After = savedAfter
  fn()
  assertEqual(#H(), 1); assertEqual(H()[1].source, "UNTRACKED"); assertEqual(H()[1].quantity, 2)
  R():Disable()
end)

-- Final-review fix: CURRENCY_DISPLAY_UPDATE also fires for hidden and tracking currencies the token
-- list never shows. Folding one would write an IN now and an UNTRACKED OUT at the next full rescan.
case("Reconciler: a hidden currency's delta writes nothing, and the next login rescan writes nothing", function()
  reset()
  genesisWithCurrency({ { id = 3008, quantity = 50 } })
  R():OnEvent("CURRENCY_DISPLAY_UPDATE", 9999, 5, 5, 1, nil)
  R():Flush()
  m.__now = 108; R():Flush()                               -- past any settle hold
  assertEqual(#H(), 0)
  assertEqual(NS.Holdings:Get(ME).currency[9999], nil)
  assertEqual(NS.Holdings:Get(ME).currency[3008], 50)
  R():LoginScan()
  assertEqual(#H(), 0)
end)

-- Bank drift (P4 Task 4): the bank and the warband tabs are only readable at a banker, so what
-- changed there while the addon was not watching (disabled, or another PC) surfaces on the FIRST
-- read of the next visit. That read is a drift pass for those parts: UNTRACKED, no hold, no pairing.
local function closeBank(kind)
  R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", NS.Compat.InteractionType(kind or "Banker"))
end

local function rowsBy(holder, id)
  local out = {}
  for _, r in ipairs(H()) do if r.holder == holder and r.itemID == id then out[#out + 1] = r end end
  return out
end

case("Reconciler: bank drift since the last visit is UNTRACKED on the first read of the next", function()
  reset()
  m.__itemClassID = 0                                     -- consumable: a bag loss would read CONSUME
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 4 } })
  genesis()
  setBag(6, { [1] = { itemID = 7, link = "L7", count = 5 } })
  openBank(); R():Flush(); closeBank()                    -- the bank's baseline
  assertEqual(#H(), 0)
  setBag(6, { [1] = { itemID = 7, link = "L7", count = 2 }, [2] = { itemID = 8, link = "L8", count = 1 } })
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 3 } }); R():MarkDirty("bags")
  m.__now = 200
  openBank(); R():Flush()
  assertEqual(#H(), 2)                                    -- exactly the bank's difference
  local out7, in8 = rowsBy(ME, 7)[1], rowsBy(ME, 8)[1]
  assertEqual(out7.dir, "OUT"); assertEqual(out7.quantity, 3); assertEqual(out7.source, "UNTRACKED")
  assertEqual(in8.dir, "IN"); assertEqual(in8.quantity, 1); assertEqual(in8.source, "UNTRACKED")
  assertEqual(#rowsBy(ME, 191), 0)                        -- the bags change is normal capture: held ...
  m.__now = 210; R():Flush()
  local bag = rowsBy(ME, 191)
  assertEqual(#bag, 1); assertEqual(bag[1].source, "CONSUME") -- ... then classified as usual
  assertEqual(NS.Holdings:Get(ME).items[7].bank, 2)
  -- A deposit later in the same visit is ordinary capture: a MOVE, not drift.
  m.__now = 220
  setBag(0, {}); setBag(6, { [1] = { itemID = 7, link = "L7", count = 2 }, [2] = { itemID = 8, link = "L8", count = 1 },
    [3] = { itemID = 191, link = "L191", count = 3 } })
  R():MarkDirty("bags"); R():MarkDirty("bank"); R():Flush()
  local moved = rowsBy(ME, 191)
  assertEqual(#moved, 2); assertEqual(moved[2].dir, "MOVE"); assertEqual(moved[2].source, "TRANSFER")
  assertEqual(#H(), 4)
end)

-- Review fix: the drift pass sets the currency delta aside, so it must not clear the currency
-- accumulators either; the normal pass that follows still writes the change with its own reason,
-- and an account transfer pending in the same flush keeps its MOVE pair and the alt's credit.
case("Reconciler: a currency delta pending when the banker opens survives the drift pass", function()
  reset()
  genesisWithCurrency({ { id = 3008, quantity = 50 } })
  setBag(6, { [1] = { itemID = 7, link = "L7", count = 5 } })
  openBank(); R():Flush(); closeBank()                    -- the bank's baseline
  setBag(6, { [1] = { itemID = 7, link = "L7", count = 4 } })
  m.__now = 200
  R():OnEvent("CURRENCY_DISPLAY_UPDATE", 3008, 40, -10, nil, m.Enum.CurrencyDestroyReason.Vendor)
  openBank(); R():Flush()
  assertEqual(#H(), 2)
  assertEqual(rowsBy(ME, 7)[1].source, "UNTRACKED")
  local cur
  for _, r in ipairs(H()) do if r.kind == "CURRENCY" then cur = r end end
  assertEqual(cur.dir, "OUT"); assertEqual(cur.quantity, 10); assertEqual(cur.source, "BUY")
  assertEqual(NS.Holdings:Get(ME).currency[3008], 40)
  closeBank()
  -- A pending account transfer flushed with the opening read keeps its MOVE pair and the credit.
  NS.db.global.holdings["Alt-Realm"] = { meta = { genesis = 1 }, scanned = { currency = 1 },
    items = {}, currency = {}, links = {} }
  m.__currencyTransfers = { { currencyType = 3008, quantityTransferred = 10, destinationCharacterName = "Alt" } }
  setBag(6, { [1] = { itemID = 7, link = "L7", count = 3 } })
  m.__now = 300
  R():OnEvent("CURRENCY_TRANSFER_LOG_UPDATE")
  R():OnEvent("CURRENCY_DISPLAY_UPDATE", 3008, 28, -12, nil, m.Enum.CurrencyDestroyReason.AccountTransfer)
  openBank(); R():Flush()
  local moves, outs = 0, 0
  for i = 3, #H() do
    local r = H()[i]
    if r.kind == "CURRENCY" and r.dir == "MOVE" then moves = moves + 1 end
    if r.kind == "CURRENCY" and r.dir == "OUT" then
      outs = outs + 1; assertEqual(r.quantity, 2); assertEqual(r.source, "TRANSFER")
    end
  end
  assertEqual(moves, 2); assertEqual(outs, 1)
  assertEqual(NS.db.global.holdings["Alt-Realm"].currency[3008], 10)
  assertEqual(NS.Holdings:Get(ME).currency[3008], 28)
  m.__currencyTransfers = {}
end)

case("Reconciler: a bank never read before is a silent first read that ends partial", function()
  reset()
  genesis()
  assertTrue(NS.Holdings:Get(ME).meta.partial)
  setBag(6, { [1] = { itemID = 7, link = "L7", count = 5 } })
  openBank(); R():Flush()
  assertEqual(#H(), 0)
  local e = NS.Holdings:Get(ME)
  assertEqual(e.meta.partial, false); assertEqual(e.items[7].bank, 5)
end)

case("Reconciler: warband tab and gold drift lands UNTRACKED on the warband, never paired", function()
  reset()
  m.__warbandMoney = 1000
  genesis()
  setBag(6, { [1] = { itemID = 7, link = "L7", count = 5 } }); setBag(12, {})
  openBank(); R():Flush(); closeBank()                    -- first reads: silent for both holders
  assertEqual(#H(), 0); assertEqual(NS.Holdings:Get("§warband").meta.partial, false)
  -- Elsewhere: 5 of item 7 moved bank -> warband tab, and the warband gained 500 gold.
  setBag(6, {}); setBag(12, { [1] = { itemID = 7, link = "L7", count = 5 } }); m.__warbandMoney = 1500
  m.__now = 200
  openBank(); R():Flush()
  assertEqual(#H(), 3)
  for _, r in ipairs(H()) do assertEqual(r.source, "UNTRACKED"); assertTrue(r.dir ~= "MOVE") end
  assertEqual(rowsBy(ME, 7)[1].dir, "OUT"); assertEqual(rowsBy("§warband", 7)[1].dir, "IN")
  local gold
  for _, r in ipairs(H()) do if r.kind == "GOLD" then gold = r end end
  assertEqual(gold.holder, "§warband"); assertEqual(gold.dir, "IN"); assertEqual(gold.quantity, 500)
  closeBank()
  -- The warband-only banker opens the same drift read.
  setBag(12, { [1] = { itemID = 7, link = "L7", count = 4 } })
  m.__now = 300
  openBank("AccountBanker"); R():Flush()
  assertEqual(#H(), 4); assertEqual(H()[4].source, "UNTRACKED"); assertEqual(H()[4].holder, "§warband")
end)

-- Final-review fix: a combat login deferred to the regen edge, with a banker opened in the same
-- combat, runs the bank drift pass first; the login's own UNTRACKED must survive it.
case("Reconciler: a deferred login with the banker open keeps its bags drift UNTRACKED", function()
  reset()
  m.__itemClassID = 0                                     -- consumable: a normal pass would hold it
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 4 } })
  setBag(6, { [1] = { itemID = 7, link = "L7", count = 5 } })
  R():LoginScan()                                         -- first login: genesis
  openBank(); R():Flush(); closeBank()                    -- the bank's baseline
  assertEqual(#H(), 0)
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 3 } })
  setBag(6, { [1] = { itemID = 7, link = "L7", count = 4 } })
  m.__now = 200
  m.InCombatLockdown = function() return true end
  R():LoginScan(); openBank()
  assertTrue(R().loginPending); assertTrue(R().driftPending)
  m.InCombatLockdown = function() return false end
  R():OnEvent("PLAYER_REGEN_ENABLED")
  assertEqual(#H(), 2)
  local bag, bank = rowsBy(ME, 191)[1], rowsBy(ME, 7)[1]
  assertEqual(bag.dir, "OUT"); assertEqual(bag.quantity, 1); assertEqual(bag.source, "UNTRACKED")
  assertEqual(bank.dir, "OUT"); assertEqual(bank.quantity, 1); assertEqual(bank.source, "UNTRACKED")
  assertEqual(R().forceReason, nil)
end)
