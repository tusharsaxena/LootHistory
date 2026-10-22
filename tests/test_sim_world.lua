local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- modules/SimWorld.lua (LootHistory#37; req-lh-sim.md §2.1-§2.2): the simulator's seeded world and
-- the seam's providers over it. A world is built from a fixture and a seed and reads no real bag;
-- the providers answer from it while a session runs and leave the client's answer alone otherwise;
-- each key has one provider, and a second registration raises (OWNER_SCOPE C.8).
--
-- This slot runs after tests/test_sim_session.lua, with the whole addon brought up. The cases that
-- need a session register a test-only scenario and always stop it.

local Sim, Host, R, A = NS.Sim, NS.SimHost, NS.Reconciler, NS.Attribution
local World = Host.World

-- req-lh-sim §2.2's provider table, in its order.
local REQ_KEYS = {
  "GetContainerNumSlots", "GetContainerSlot", "GetInventoryItem", "GetMoney", "GetWarbandMoney",
  "ListCurrencies", "ScanInbox", "GetMailHeader", "ReadSendMail", "ScanOwnedAuctions", "ItemLocationID",
  "ContainerItemHasLoot", "IsSpellTargeting", "CurrentQuestID", "GetActiveKeystoneLevel", "InPartyInstance",
  "InCombatLockdown", "TradeTargetKey", "LatestCurrencyTransfer", "NumLootItems", "LootSourceGUID", "Zone",
  "PlayerMapID",
}

-- A stable text for any value, tables walked with sorted keys.
local function ser(v)
  if type(v) ~= "table" then return type(v) == "string" and ("%q"):format(v) or tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. ser(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

local function pack(...) return { n = select("#", ...), ... } end

local function withSession(body)
  local sc = Host.SCENARIOS
  sc.names[#sc.names + 1] = "lhworld"
  sc.defs.lhworld = { label = "World", timeline = function() return { { kind = "noop", label = "Noop" } } end }
  NS.State.cleanupDone, NS.State.loginSettled = true, true
  R:ResetState(); A:ResetContexts()
  M.__inCombat = false
  M.__context.inGroup, M.__context.inInstance = false, false
  local ok, err = pcall(body)
  Sim:Stop("stop")
  sc.defs.lhworld = nil
  for i = #sc.names, 1, -1 do if sc.names[i] == "lhworld" then table.remove(sc.names, i) end end
  R:ResetState(); A:ResetContexts()
  if not ok then error(err, 0) end
end

test("SimWorld: the fixture world is deterministic for a seed", function()
  local a, b = World.New(nil, 42), World.New(nil, 42)
  assertEqual(ser(a), ser(b), "one fixture and one seed build one world")
  local c = World.New(nil, 7)
  assertTrue(ser(a) ~= ser(c), "another seed draws other counts and purses")
  assertEqual(a.seed, 42)
  local bag0 = NS.Constants.BAG_IDS[1]
  assertTrue(next(a.bags[bag0]) ~= nil, "the bags are stocked from the fixture")
  assertTrue(a.equipped[13] ~= nil and a.equipped[13].itemID == World.ITEMS.trinket.id, "the fixture's worn trinket")
  assertTrue(#a.currencies == 2, "the fixture's currencies")
end)

test("SimWorld: a world never mirrors the player's real bags", function()
  local slots, info = M.__bagSlots, M.C_Container.GetContainerItemInfo
  M.__bagSlots = { [0] = 4 }
  M.C_Container.GetContainerItemInfo = function() return { itemID = 999999, hyperlink = "real", stackCount = 9 } end
  local ok, err = pcall(function()
    local w = World.New(nil, 42)
    for _, where in ipairs({ "bags", "bank", "tabs" }) do
      for _, bag in pairs(w[where]) do
        for _, e in pairs(bag) do assertTrue(e.itemID ~= 999999, "a real bag item leaked into the world") end
      end
    end
    assertEqual(ser(w), ser(World.New(nil, 42)), "the real bags change nothing")
  end)
  M.__bagSlots, M.C_Container.GetContainerItemInfo = slots, info
  if not ok then error(err, 0) end
end)

test("SimWorld: a fixture link carries bonus ids Item.BonusIDsFromLink reads", function()
  local spec = World.ITEMS.trinket
  local link = World.Link(spec)
  assertEqual(table.concat(NS.Item.BonusIDsFromLink(link), ","), table.concat(spec.bonus, ","))
  assertEqual(NS.Item.ItemIDFromLink(link), spec.id)
  assertEqual(#NS.Item.BonusIDsFromLink(World.Link(World.ITEMS.herb)), 0, "no bonus ids, none read")
  assertTrue(link:find("^|cffa335ee|Hitem:273796::::::::90::::4:") ~= nil, "the itemString shape: " .. link)
end)

-- The add-on targets Midnight (the TOC's ## Interface 120xxx), so the fixture's ids are Midnight's:
-- an id from an older expansion still answers the live reads, but prices and names from the wrong
-- expansion make a simulated history no player of this client would see (LH-11 review).
test("SimWorld: the fixture is Midnight's: items, currencies and the situation", function()
  local ids = {}
  for key, s in pairs(World.ITEMS) do ids[key] = s.id end
  assertEqual(ids.herb, 236761, "Tranquility Bloom")
  assertEqual(ids.ore, 237359, "Refulgent Copper Ore")
  assertEqual(ids.trinket, 273796, "Vile Vial of Volatile Venom")
  assertEqual(ids.cache, 279287, "Corroded Pouch")
  local F = World.FIXTURE
  assertEqual(F.currencies[1][1], 3444, "Champion Mistcrest, per character")
  assertFalse(F.currencies[1][4])
  assertEqual(F.currencies[2][1], 3316, "Voidlight Marl, warband-wide")
  assertTrue(F.currencies[2][4])
  assertEqual(F.instance.zone, "Silvermoon City")
  assertEqual(F.instance.mapID, 2393)
end)

test("SimWorld: the uncached fixture link falls back to the link's own name and color", function()
  local spec
  for _, s in pairs(World.ITEMS) do if s.uncached then spec = s end end
  assertTrue(spec ~= nil, "one fixture item is the uncached one")
  local saved = M.C_Item.GetItemInfo
  M.C_Item.GetItemInfo = function() return nil end
  local ok, err = pcall(function()
    local _, name, quality = NS.Compat.GetItemInfo(World.Link(spec))
    assertEqual(name, spec.name, "the name is the link's")
    assertEqual(quality, spec.quality, "the quality is the link color's")
  end)
  M.C_Item.GetItemInfo = saved
  if not ok then error(err, 0) end
end)

test("SimWorld: the mutation helpers move stacks, money, mail and auctions", function()
  local w = World.New(nil, 1)
  local herb = World.ITEMS.herb.id
  local bagID, slot, e = World.Find(w, "bags", herb)
  local before = e.count
  World.AddItem(w, "bags", "herb", 3)
  assertEqual(e.count, before + 3, "a stack of the same id grows")
  assertEqual(World.RemoveItem(w, "bags", herb, 2), 2)
  assertEqual(e.count, before + 1)
  local toBag = World.MoveSlot(w, bagID, slot, "bank")
  assertEqual(World.Bag(w, bagID)[slot], nil, "the stack left its slot")
  assertTrue(World.Bag(w, toBag) ~= nil and World.Find(w, "bank", herb) ~= nil, "and landed in the bank")
  local money = w.money
  World.AddMoney(w, -100)
  assertEqual(w.money, money - 100)
  local cid, q0 = w.currencies[1].id, w.currencies[1].quantity
  assertEqual(World.SetCurrency(w, cid, q0 + 10), 10, "SetCurrency answers the change")
  assertEqual(World.AddCurrency(w, cid, -4), -4)
  assertEqual(w.currencies[1].quantity, q0 + 6)
  local oreBag, oreSlot = World.Find(w, "bags", World.ITEMS.ore.id)
  local idx, took = World.PostAuction(w, oreBag, oreSlot, 1)
  assertEqual(took.count, 1)
  assertEqual(w.owned[idx].status, "active")
  local mail = World.SellAuction(w, idx, 5000)
  assertEqual(w.owned[idx].status, "sold", "a sold auction leaves the active list")
  assertEqual(w.inbox[mail].money, 5000)
  assertEqual(World.TakeMailMoney(w, mail), 5000)
  local m2 = World.AddWonMail(w, "trinket", 1)
  local items = #w.inbox[m2].items
  assertEqual(items, 1)
  assertTrue(World.TakeMailItem(w, m2, 1) ~= nil, "the attachment lands in the bags")
  World.OpenLoot(w, "Creature-0-1-2-3-4-5", 2)
  assertEqual(w.loot.n, 2); World.CloseLoot(w); assertEqual(w.loot, nil)
  World.SetInstance(w, { party = true, keystone = 10 })
  assertEqual(w.instance.keystone, 10)
  World.SetInstance(w, { keystone = false })
  assertEqual(w.instance.keystone, nil, "false clears a field")
end)

-- The arguments each provided key is read with, and what the session world below answers.
local ARGS = {
  GetContainerNumSlots = { 0 }, GetContainerSlot = { 0, 1 }, GetInventoryItem = { 13 },
  GetMailHeader = { 1 }, ItemLocationID = { { bagID = 0, slotIndex = 1 } }, ContainerItemHasLoot = { 0, 1 },
  LootSourceGUID = { 1 },
}

local function shapeWorld(w)
  w.sizes[0] = 3
  w.bags[0] = { [1] = { itemID = 210796, link = "L1", count = 7, hasLoot = true } }
  w.equipped[13] = { itemID = 219915, link = "L2" }
  w.money, w.warbandMoney = 12345, 67890
  w.currencies = { { id = 3008, quantity = 5, accountWide = false } }
  w.inbox = { { sender = "Simalt-Realm", subject = "Hi", money = 0, items = { { itemID = 210930, link = "L3", count = 2 } } } }
  w.sendMail = { items = { [210796] = 4 }, money = 99 }
  w.owned = { { itemID = 210930, link = "L3", quantity = 3, status = "active" },
              { itemID = 210796, link = "L1", quantity = 1, status = "sold" } }
  w.targeting, w.combat, w.quest = true, true, { id = 4242 }
  w.instance = { party = true, keystone = 12, zone = "Z", subzone = "S", mapID = 77 }
  w.trade = { target = "Simalt-Realm" }
  w.transfer = { currencyID = 3008, quantity = 1, toKey = "Simalt-Realm" }
  w.loot = { guid = "Creature-0-3767-2552-11111-1234-0000ABCDEF", n = 2 }
end

local WORLD_ANSWERS = {
  GetContainerNumSlots = "{1=3,n=1}",
  GetContainerSlot = '{1={count=7,itemID=210796,link="L1"},n=1}',
  GetInventoryItem = '{1=219915,2="L2",n=2}',
  GetMoney = "{1=12345,n=1}", GetWarbandMoney = "{1=67890,n=1}",
  ListCurrencies = "{1={1={accountWide=false,id=3008,quantity=5}},n=1}",
  ScanInbox = '{1={210930=2},2={210930="L3"},n=2}',
  GetMailHeader = '{1="Simalt-Realm",2="Hi",n=2}',
  ReadSendMail = "{1={210796=4},2=99,n=2}",
  ScanOwnedAuctions = '{1={210930=3},2={210930="L3"},n=2}',
  ItemLocationID = "{1=210796,n=1}", ContainerItemHasLoot = "{1=true,n=1}",
  IsSpellTargeting = "{1=true,n=1}", CurrentQuestID = "{1=4242,n=1}",
  GetActiveKeystoneLevel = "{1=12,n=1}", InPartyInstance = "{1=true,n=1}", InCombatLockdown = "{1=true,n=1}",
  TradeTargetKey = '{1="Simalt-Realm",n=1}',
  LatestCurrencyTransfer = '{1={currencyID=3008,quantity=1,toKey="Simalt-Realm"},n=1}',
  NumLootItems = "{1=2,n=1}", LootSourceGUID = '{1="Creature-0-3767-2552-11111-1234-0000ABCDEF",n=1}',
  Zone = '{1="Z",2="S",n=2}', PlayerMapID = "{1=77,n=1}",
}

local function answers()
  local out = {}
  for _, key in ipairs(REQ_KEYS) do
    out[key] = ser(pack(NS.Compat[key](unpack(ARGS[key] or {}))))
  end
  return out
end

test("SimWorld: every provider answers from the world while active and live when idle", function()
  local provided = {}
  for _, k in ipairs(World.PROVIDED) do provided[#provided + 1] = k end
  assertEqual(table.concat(provided, ","), table.concat(REQ_KEYS, ","), "exactly req §2.2's providers, in order")
  local idle = answers()
  withSession(function()
    assertTrue(Sim:Start({ scenario = "lhworld", seed = 5 }))
    shapeWorld(Host.world)
    local active = answers()
    for _, key in ipairs(REQ_KEYS) do
      assertEqual(active[key], WORLD_ANSWERS[key], key .. " answers from the world")
    end
    local live = NS.SimSeam:Live(answers)
    for _, key in ipairs(REQ_KEYS) do
      if key ~= "ListCurrencies" then assertEqual(live[key], idle[key], key .. " answers live inside Live") end
    end
  end)
  local after = answers()
  for _, key in ipairs(REQ_KEYS) do assertEqual(after[key], idle[key], key .. " answers live again once idle") end
end)

test("SimWorld: the item, spell and currency reads and the three world rules have no provider", function()
  local provided = {}
  for _, k in ipairs(World.PROVIDED) do provided[k] = true end
  for _, key in ipairs({ "GetItemInfo", "GetItemExtras", "ScanBound", "GetSpellName", "CurrencyName",
                         "PlayerClassFile", "InInstance", "InGroup", "PlayerInCombat" }) do
    assertFalse(provided[key], key .. " answers live: no provider")
  end
end)

test("SimWorld: SetProvider twice for one key raises", function()
  for _, key in ipairs(World.PROVIDED) do
    local ok, err = pcall(NS.SimSeam.SetProvider, NS.SimSeam, key, function() end)
    assertFalse(ok, key .. ": a second provider must raise")
    assertTrue(tostring(err) ~= "", key .. " raised with a message")
  end
end)

test("SimWorld: a start seeds the session world from the fixture and the session seed", function()
  withSession(function()
    assertTrue(Sim:Start({ scenario = "lhworld", seed = 42 }))
    assertEqual(ser(Host.world), ser(World.New(nil, 42)), "prepare builds World.New(def.fixture, seed)")
    assertEqual(NS.Compat.GetMoney(), Host.world.money, "the purse answers from the world")
    local holder = NS.SimStores.holdings[NS.Util.PlayerKey()]
    assertTrue(holder ~= nil, "the session genesis scanned the world")
    assertEqual(#NS.SimStores.history, 0, "and wrote no row")
  end)
  assertEqual(Host.world, nil, "the stop drops the world")
end)
