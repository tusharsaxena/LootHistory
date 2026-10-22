local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- modules/SimDrivers.lua (LootHistory#37; req-lh-sim.md §2.3-§2.4): the event and hook drivers.
-- Each changes the world first and then fires the client's events, with the client's payload
-- shapes, through NS.Sim:Fire; a hook driver reaches the HOOK_ROWS fns through deliver and never
-- calls the hooked client function. The chat lines are written from the parser's own globals, so
-- every one parses.
--
-- This slot runs after tests/test_sim_world.lua, with the whole addon brought up. Every case runs
-- inside a test-only session and stops it.

local Sim, Host, R, A, U = NS.Sim, NS.SimHost, NS.Reconciler, NS.Attribution, NS.Util
local D, World = Host.Drivers, Host.World
-- The fixture's per-character currency (Champion Mistcrest), whatever id it carries.
local CREST = World.FIXTURE.currencies[1][1]

-- Run body(record) in a session. record is the list of { event, args = {n, ...}, seen } the deliver
-- received, `seen` being snap(event) taken when the event reached it.
local function withSession(body, snap)
  local sc = Host.SCENARIOS
  sc.names[#sc.names + 1] = "lhdrive"
  sc.defs.lhdrive = { label = "Drive", timeline = function() return { { kind = "noop", label = "Noop" } } end }
  NS.State.cleanupDone, NS.State.loginSettled = true, true
  R:ResetState(); A:ResetContexts()
  M.__inCombat = false
  M.__context.inGroup, M.__context.inInstance = false, false
  local record, saved = {}, NS.DeliverAll
  local ok, err = pcall(function()
    assertTrue(Sim:Start({ scenario = "lhdrive", seed = 11 }), "the test session starts")
    NS.DeliverAll = function(event, ...)
      record[#record + 1] = { event = event, args = { n = select("#", ...), ... }, seen = snap and snap(event) }
      return saved(event, ...)
    end
    body(record)
  end)
  NS.DeliverAll = saved
  Sim:Stop("stop")
  sc.defs.lhdrive = nil
  for i = #sc.names, 1, -1 do if sc.names[i] == "lhdrive" then table.remove(sc.names, i) end end
  R:ResetState(); A:ResetContexts()
  if not ok then error(err, 0) end
end

local function first(record, event)
  for _, r in ipairs(record) do if r.event == event then return r end end
  return nil
end

local function bagCount(itemID)
  local n = 0
  for _, where in ipairs({ "bags" }) do
    for _, bag in pairs(Host.world[where]) do
      for _, e in pairs(bag) do if e.itemID == itemID then n = n + e.count end end
    end
  end
  return n
end

test("SimDrivers: a loot driver produces a line ParseSelfLoot accepts", function()
  withSession(function(record)
    for _, form in ipairs({ "self", "pushed", "bonus" }) do
      for _, qty in ipairs({ 1, 4 }) do
        D.Loot("trinket", qty, { form = form })
        local r
        for i = #record, 1, -1 do if record[i].event == "CHAT_MSG_LOOT" then r = record[i]; break end end
        assertEqual(r.event, "CHAT_MSG_LOOT")
        assertEqual(r.args.n, 17, "the client's seventeen chat arguments")
        local link, n, source = U.ParseSelfLoot(r.args[1])
        assertEqual(link, World.Link(World.ITEMS.trinket), form .. " x" .. qty .. ": the link parses back")
        assertEqual(n, qty, form .. " x" .. qty .. ": the quantity parses back")
        assertEqual(source, form == "bonus" and "BONUS_ROLL" or nil)
        assertEqual(r.args[2], U.PlayerKey():match("^([^%-]+)"), "the player's own name")
        assertEqual(r.args[12], M.UnitGUID and M.UnitGUID("player") or "Player-0-00000000", "the player's GUID")
      end
    end
    D.RollWon("trinket")
    assertEqual(U.ParseRollWon(record[#record].args[1]), World.Link(World.ITEMS.trinket), "the roll-won line parses")
  end)
end)

test("SimDrivers: the currency and money lines parse", function()
  withSession(function(record)
    D.Currency(CREST, 25)
    local r = first(record, "CHAT_MSG_CURRENCY")
    assertEqual(r.args.n, 17)
    local link, qty = U.ParseSelfCurrency(r.args[1])
    assertEqual(NS.Compat.CurrencyLinkID(link), CREST)
    assertEqual(qty, 25)
    D.Currency(CREST, 1)
    assertTrue(U.ParseSelfCurrency(record[#record - 1].args[1]) ~= nil, "a single currency line parses")
    for _, copper in ipairs({ 1, 99, 10000, 123456, 5000000 }) do
      for _, split in ipairs({ false, true }) do
        D.Money(copper, split)
        local m = record[#record - 1]
        assertEqual(m.event, "CHAT_MSG_MONEY")
        assertEqual(U.ParseSelfMoney(m.args[1]), copper, ("%d%s parses back"):format(copper, split and " (split)" or ""))
      end
    end
  end)
end)

-- One row per driver: how to play it, the event to watch, and what the world must already show
-- when that event is delivered.
local MUTATES = {
  { "Loot", function() D.Loot("ore", 3) end, "CHAT_MSG_LOOT",
    function(s, s0) return s.ore == s0.ore + 3 end },
  { "Loot bagsFirst", function() D.Loot("ore", 2, { bagsFirst = true }) end, "BAG_UPDATE",
    function(s, s0) return s.ore == s0.ore + 2 end },
  { "Currency", function() D.Currency(CREST, 7) end, "CHAT_MSG_CURRENCY",
    function(s, s0) return s.crest == s0.crest + 7 end },
  { "Money", function() D.Money(4321) end, "CHAT_MSG_MONEY", function(s, s0) return s.money == s0.money + 4321 end },
  { "LootOpened", function() D.LootOpened("Creature", 1234, 2) end, "LOOT_OPENED",
    function(s) return s.loot == 2 end },
  { "KeyStart", function() D.KeyStart(2649, 10) end, "CHALLENGE_MODE_START", function(s) return s.key == 10 end },
  { "KeyReset", function() D.KeyStart(2649, 10); D.KeyReset(2649) end, "CHALLENGE_MODE_RESET",
    function(s) return s.key == nil end },
  { "Zone", function() D.Zone({ zone = "Elsewhere", party = false }) end, "ZONE_CHANGED_NEW_AREA",
    function(s) return s.zone == "Elsewhere" end },
  { "QuestTurnedIn", function() D.QuestTurnedIn(80000, 10, 500) end, "QUEST_TURNED_IN",
    function(s, s0) return s.money == s0.money + 500 end },
  { "TradeAccept", function() D.TradeAccept("Simalt-Realm") end, "TRADE_ACCEPT_UPDATE",
    function(s) return s.trade == "Simalt-Realm" end },
  { "Combat off", function() D.Combat(true); D.Combat(false) end, "PLAYER_REGEN_ENABLED",
    function(s) return s.combat == false end },
  { "WarbandGold", function() D.WarbandGold(1000) end, "ACCOUNT_MONEY",
    function(s, s0) return s.money == s0.money - 1000 and s.warband == s0.warband + 1000 end },
  { "CurrencyTransfer", function() D.CurrencyTransfer(CREST, 2, "Simalt-Realm") end, "CURRENCY_TRANSFER_LOG_UPDATE",
    function(s, s0) return s.crest == s0.crest - 2 and s.transfer == 2 end },
  { "Buy", function() D.Buy(1, "herb", 2, 300) end, "hook:BuyMerchantItem",
    function(s, s0) return s.herb == s0.herb + 2 and s.money == s0.money - 300 end },
  { "Repair", function() D.Repair(700) end, "hook:RepairAllItems", function(s, s0) return s.money == s0.money - 700 end },
  { "TakeMailMoney", function() World.AddMail(Host.world, { sender = "X", subject = "S", money = 900 }); D.TakeMailMoney(#Host.world.inbox) end,
    "PLAYER_MONEY", function(s, s0) return s.money == s0.money + 900 end },
}

local function snapshot()
  local w = Host.world
  local crest = 0
  for _, c in ipairs(w.currencies) do if c.id == CREST then crest = c.quantity end end
  return { ore = bagCount(World.ITEMS.ore.id), herb = bagCount(World.ITEMS.herb.id), money = w.money,
    warband = w.warbandMoney, crest = crest, loot = w.loot and w.loot.n, key = w.instance.keystone,
    zone = w.instance.zone, trade = w.trade and w.trade.target, combat = w.combat,
    transfer = w.transfer and w.transfer.quantity }
end

test("SimDrivers: each driver mutates the world before it fires", function()
  for _, row in ipairs(MUTATES) do
    local name, play, event, check = row[1], row[2], row[3], row[4]
    withSession(function(record)
      local s0 = snapshot()
      play()
      local r
      for i = #record, 1, -1 do if record[i].event == event then r = record[i]; break end end
      assertTrue(r ~= nil, name .. ": " .. event .. " was fired")
      assertTrue(check(r.seen, s0), name .. ": the world had changed when " .. event .. " was delivered")
    end, function() return snapshot() end)
  end
end)

test("SimDrivers: a hook driver shows the client's pre-call world to the post-hook", function()
  withSession(function(record)
    local w = Host.world
    local bagID, slot = World.Find(w, "bags", World.ITEMS.cache.id)
    D.UseItem(bagID, slot, { contents = { { "herb", 2 } } })
    local use = first(record, "hook:UseContainerItem")
    assertEqual(use.args[1], bagID); assertEqual(use.args[2], slot)
    assertEqual(use.seen, true, "the used slot still held its lootable item")
    assertEqual(World.Bag(w, bagID)[slot], nil, "the container is gone afterwards")
    assertEqual(NS.State.lootContext and NS.State.lootContext.source, NS.Constants.SourceType.CONTAINER,
      "the real hook body stamped CONTAINER from the provider's hasLoot")
  end, function(event)
    if event ~= "hook:UseContainerItem" then return nil end
    local bagID, slot = World.Find(Host.world, "bags", World.ITEMS.cache.id)
    return bagID ~= nil and NS.Compat.ContainerItemHasLoot(bagID, slot)
  end)
  withSession(function(record)
    local w = Host.world
    local bagID, slot = World.Find(w, "bags", World.ITEMS.ore.id)
    D.Send("Simalt-Realm", { { bagID, slot } }, 100)
    local send = first(record, "hook:SendMail")
    assertEqual(send.args[1], "Simalt-Realm")
    assertTrue(send.seen ~= nil and send.seen > 0, "the attachment was staged when the post-hook read it")
    assertTrue(first(record, "MAIL_SEND_SUCCESS") ~= nil)
    assertEqual(w.sendMail, nil, "the frame is empty once sent")
  end, function(event)
    if event ~= "hook:SendMail" then return nil end
    local items = NS.Compat.ReadSendMail()
    return items[World.ITEMS.ore.id]
  end)
  withSession(function(record)
    local w = Host.world
    local bagID, slot = World.Find(w, "bags", World.ITEMS.ore.id)
    D.Post(bagID, slot, 1, 50)
    local post = first(record, "hook:PostItem")
    assertEqual(post.seen, World.ITEMS.ore.id, "ItemLocationID read the posted item from the world")
    assertTrue(NS.State.pendingPost[World.ITEMS.ore.id] ~= nil, "the real hook body booked the post")
    assertEqual(#w.owned, 1)
  end, function(event)
    if event ~= "hook:PostItem" then return nil end
    local bagID, slot = World.Find(Host.world, "bags", World.ITEMS.ore.id)
    return NS.Compat.ItemLocationID({ bagID = bagID, slotIndex = slot })
  end)
end)

-- Drive one hooked function by its driver, with arguments a fresh session world can serve.
local function driveHook(name)
  local w = Host.world
  local driver = D.HOOK_DRIVER[name]
  local bagID, slot = World.Find(w, "bags", World.ITEMS.ore.id)
  local mail = World.AddMail(w, { sender = "X", subject = "S", money = 10,
    items = { { itemID = 210796, link = World.Link(World.ITEMS.herb), count = 1 } } })
  local plays = {
    Buy = function() D.Buy(1, "herb", 1, 10) end, Buyback = function() D.Buyback(1, "herb", 1, 10) end,
    UseItem = function() D.UseItem(bagID, slot) end, Repair = function() D.Repair(10) end,
    Destroy = function() D.Destroy(bagID, slot) end, TakeMailItem = function() D.TakeMailItem(mail, 1) end,
    AutoLootMail = function() D.AutoLootMail(mail) end, TakeMailMoney = function() D.TakeMailMoney(mail) end,
    Send = function() D.Send("Simalt-Realm", { { bagID, slot } }, 0) end,
    Post = function() D.Post(bagID, slot, 1, 10, name == "PostCommodity") end,
    AuctionBuy = function() D.AuctionBuy("herb", 1, 10, name == "ConfirmCommoditiesPurchase") end,
    Craft = function()
      local kind = ({ CraftRecipe = "recipe", CraftSalvage = "salvage", CraftEnchant = "enchant" })[name]
      D.Craft(kind, 450000, { { "ore", 1 } })
    end,
    QuestReward = function() D.QuestReward(80000, 1) end,
  }
  assertTrue(plays[driver] ~= nil, name .. " has a driver: " .. tostring(driver))
  plays[driver]()
end

test("SimDrivers: hook drivers reach the HOOK_ROWS fns through deliver", function()
  local names, seen = {}, {}
  for _, row in ipairs(NS.HOOK_ROWS) do
    if not seen[row.name] then seen[row.name] = true; names[#names + 1] = row.name end
  end
  assertEqual(#names, 17, "seventeen hooked functions (BuyMerchantItem has two rows)")
  for _, name in ipairs(names) do
    local hits, saved = {}, {}
    for i, row in ipairs(NS.HOOK_ROWS) do
      saved[i] = row.fn
      row.fn = function(...) hits[#hits + 1] = row.owner .. ":" .. row.name; return saved[i](...) end
    end
    local ok, err = pcall(withSession, function(record)
      driveHook(name)
      assertTrue(first(record, "hook:" .. name) ~= nil, name .. ": hook:" .. name .. " went through deliver")
    end)
    for i, row in ipairs(NS.HOOK_ROWS) do row.fn = saved[i] end
    if not ok then error(err, 0) end
    local want = 0
    for _, row in ipairs(NS.HOOK_ROWS) do if row.name == name then want = want + 1 end end
    local got = 0
    for _, h in ipairs(hits) do if h:match(":(.+)$") == name then got = got + 1 end end
    assertEqual(got, want, name .. ": every row for it ran")
  end
end)

test("SimDrivers: LOOT_OPENED carries the provider GUID kind (Creature/GameObject/Item)", function()
  local S = NS.Constants.SourceType
  for _, case in ipairs({ { "Creature", 219000, S.KILL }, { "GameObject", 500000, S.CONTAINER },
                          { "Item", 42, S.CONTAINER } }) do
    local kind, id, source = case[1], case[2], case[3]
    withSession(function(record)
      D.LootOpened(kind, id, 3)
      local r = first(record, "LOOT_OPENED")
      assertEqual(r.args.n, 2, kind .. ": LOOT_OPENED(autoLoot, isFromItem)")
      assertEqual(r.args[2], kind == "Item", kind .. ": isFromItem")
      assertEqual(NS.Compat.NumLootItems(), 3)
      local guid = NS.Compat.LootSourceGUID(1)
      assertEqual(guid:match("^(%a+)%-"), kind, kind .. ": the provider's GUID kind")
      assertEqual(NS.Compat.DecodeGUID(guid), kind)
      assertEqual(NS.State.lootContext and NS.State.lootContext.source, source, kind .. ": the engine resolved it")
      if kind == "Creature" then
        assertEqual(NS.State.lootContext.detail and NS.State.lootContext.detail.npcID, id, "the npcID rides the GUID")
      end
      D.LootClosed()
      assertEqual(NS.Compat.NumLootItems(), 0)
    end)
  end
end)

test("SimDrivers: with no session a driver changes nothing and fires nothing", function()
  assertFalse(Sim:IsActive())
  assertEqual(D.Loot("ore", 1), 0)
  assertEqual(D.Buy(1, "herb", 1, 10), 0)
  assertEqual(D.LootOpened("Creature", 1, 1), 0)
  assertEqual(Host.world, nil)
end)
