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
