local _, NS = ...

-- modules/SimScenario.lua: the simulator's six scenarios and its ledger gate (LootHistory#37;
-- req-lh-sim.md §7, OWNER_SCOPE C.12).
--
-- ── WHAT A SCENARIO IS ───────────────────────────────────────────────────────────────────────
--
-- A def in NS.SimHost.SCENARIOS (filled in place here; LibKa0s-Sim-1.0 reads it at call time):
-- a label, a fixture (the world modules/SimWorld.lua seeds) and a `timeline(def, opts)` that answers
-- the steps. The timeline is PURE: it reads only the def and builds fresh step tables each call
-- (the library stamps ranAt, detail and index onto a step that ran, and previews a timeline while
-- idle), so nothing in it touches the world, the clock or the client.
--
-- A step is a host table: `kind`, `label`, `tip` (the lines the panel shows: what the step
-- injects) and `calls`, a list of { op, args... }. Host.Play walks the calls through OPS below,
-- each of which resolves its fixture keys against the session world at play time and calls a
-- driver (modules/SimDrivers.lua) or changes the world and fires the bursts the client would.
-- Nothing here writes a source, a reason or a row: if a simulated row reads AH_SOLD,
-- Ledger.PickReason decided it.
--
-- ── THE GATE ─────────────────────────────────────────────────────────────────────────────────
--
-- Host.Gate is the library's `gate`, read before every Step, every Run tick and the panel's
-- click-ahead. It is closed while the Reconciler has work in flight -- a flush fuse waiting out
-- its 0.35 s debounce (R._pending), a settle hold (R._holdSince: a gain waiting 1.5 s for its chat
-- claim, a one-sided change at a bank, mailbox or auction house waiting up to 6 s,
-- core/Ledger.lua's CLAIM_WAIT and SETTLE_TIMEOUT) or a flush combat deferred (R.deferred) -- so
-- a step never lands on a half-classified change, and every scenario ends on a settled ledger.
-- One carve-out: a flush deferred while the SIMULATED world is in combat waits on the regen edge,
-- which only the timeline's own next step delivers, so it does not close the gate (closing it would
-- wait forever on the step it is holding back).

NS.SimHost = NS.SimHost or {}
local Host = NS.SimHost
local L = NS.L
local World = Host.World
local D = Host.Drivers

local SC = Host.SCENARIOS or { names = {}, defs = {} }
Host.SCENARIOS = SC

-- ── fixture ───────────────────────────────────────────────────────────────────────────────────

--- Items only the scenarios use, by key (World.Spec reads the world's own `items` first). `junk`
--- is a poor-quality drop below the default collection threshold; `dust` is an enchanting
--- material (The War Within's Storm Dust); `potion` a combat consumable (its Algari Healing
--- Potion). Real ids, so the live item reads answer for them.
Host.SCENARIO_ITEMS = {
  junk   = { id = 4865, name = "Ruined Pelt", quality = 0, level = 1 },
  dust   = { id = 219946, name = "Storm Dust", quality = 1, level = 80 },
  potion = { id = 211880, name = "Algari Healing Potion", quality = 1, level = 80 },
}

-- The default fixture plus what the scenarios act on: a gear piece and dust in the bags (to
-- disenchant, post and deposit) and potions to drink in combat.
local function scenarioFixture()
  local f = {}
  for k, v in pairs(World.FIXTURE) do f[k] = v end
  f.items = Host.SCENARIO_ITEMS
  f.bags = { { "herb", 10, 20 }, { "ore", 10, 20 }, { "cache", 1, 1 }, { "trinket", 1, 1 },
             { "dust", 4, 8 }, { "potion", 3, 3 } }
  return f
end

-- The situation the key runs in, and the bosses and chest it meets. Illustrative ids: nothing
-- resolves them live, they only ride into the rows' details (npcID, encounterID, mapID).
local KEY = {
  mapID = 2649, level = 10, zone = "Priory of the Sacred Flame", subzone = "Nave", chest = 455000,
  bosses = {
    { encounter = 2847, npc = 207946, name = "Captain Dailcry" },
    { encounter = 2835, npc = 207939, name = "Baron Braunpyke" },
  },
}
local OPEN_WORLD = { party = false, keystone = false, zone = "Silvermoon City", subzone = "The Bazaar",
  mapID = 2393 }

-- ── ops (play time: resolve keys against the world, then drive) ──────────────────────────────

local function world() return Host.world end

-- The first bag slot holding `key`: bagID, slot.
local function slotOf(where, key)
  local w = world()
  local spec = World.Spec(w, key)
  return World.Find(w, where, spec and spec.id)
end

-- The index of the first mail carrying `key`.
local function mailWith(key)
  local w = world()
  local id = World.Spec(w, key).id
  for i, m in ipairs(w.inbox) do
    for _, att in ipairs(m.items) do if att.itemID == id then return i end end
  end
  return nil
end

local function mailWithMoney()
  for i, m in ipairs(world().inbox) do if (m.money or 0) > 0 then return i end end
  return nil
end

local function altKey() return Host.alt end

-- The owned auction of `key`.
local function auctionOf(key)
  local w = world()
  local id = World.Spec(w, key).id
  for i, a in ipairs(w.owned) do if a.itemID == id and a.status == "active" then return i end end
  return nil
end

local OPS = {}

function OPS.loot(key, qty, opts) return D.Loot(key, qty, opts) end
function OPS.line(key, qty, form) return D.LootLine(key, qty, form) end
function OPS.rollWon(key) return D.RollWon(key) end
function OPS.money(copper) return D.Money(copper) end
function OPS.currency(id, qty) return D.Currency(id, qty) end
function OPS.lootOpened(kind, id, n) return D.LootOpened(kind, id, n) end
function OPS.lootClosed() return D.LootClosed() end
function OPS.zone(fields) return D.Zone(fields) end
function OPS.keyStart(mapID, level) return D.KeyStart(mapID, level) end
function OPS.keyCompleted() return D.KeyCompleted() end
function OPS.encounterStart(id, name) return D.EncounterStart(id, name, 8, 5) end
function OPS.encounterEnd(id, name) return D.EncounterEnd(id, name, 8, 5, true) end
function OPS.combat(on) return D.Combat(on) end
function OPS.open(name) return D.Open(name) end
function OPS.close(name) return D.Close(name) end
function OPS.cast(spell) return D.Cast(D.SPELLS[spell] or spell) end
function OPS.repair(cost) return D.Repair(cost) end
function OPS.buy(index, key, qty, price) return D.Buy(index, key, qty, price) end
function OPS.warbandGold(copper) return D.WarbandGold(copper) end
function OPS.auctionBuy(key, qty, price) return D.AuctionBuy(key, qty, price) end
function OPS.questReward(questID, choice, copper) return D.QuestReward(questID, choice, 1000, copper) end

--- Use a bag item: `effect` as D.UseItem takes it (sell, consume).
function OPS.use(key, effect)
  local bagID, slot = slotOf("bags", key)
  if not bagID then return 0 end
  return D.UseItem(bagID, slot, effect)
end

function OPS.destroy(key)
  local bagID, slot = slotOf("bags", key)
  if not bagID then return 0 end
  return D.Destroy(bagID, slot)
end

--- Move the first stack of `key` from `from` into `to` (bags, bank or tabs).
function OPS.move(key, from, to)
  local bagID, slot = slotOf(from, key)
  if not bagID then return 0 end
  return D.Move(bagID, slot, to)
end

--- `qty` of `key` leaves the bags with no client call of its own (a disenchant's target, a traded
--- item): the world, then the bag burst.
function OPS.remove(key, qty)
  local w = world()
  local _, bags = World.RemoveItem(w, "bags", World.Spec(w, key).id, qty)
  return D.Bags(bags)
end

--- `qty` of `key` arrives in the bags with no line of its own (a traded item).
function OPS.receive(key, qty)
  local bagID = World.AddItem(world(), "bags", key, qty)
  return D.Bags({ bagID })
end

function OPS.post(key, qty, deposit)
  local bagID, slot = slotOf("bags", key)
  if not bagID then return 0 end
  return D.Post(bagID, slot, qty, deposit)
end

--- While the player is away: the auction of `key` sells (the payout is mailed) or expires (the item
--- is mailed back). The client says nothing until the auction house or the mailbox is next open.
function OPS.auctionSoldAway(key, copper)
  local i = auctionOf(key)
  if i then World.SellAuction(world(), i, copper) end
  return 0
end

function OPS.auctionExpiredAway(key)
  local i = auctionOf(key)
  if i then World.ExpireAuction(world(), i) end
  return 0
end

function OPS.takeMailMoney()
  local i = mailWithMoney()
  if not i then return 0 end
  return D.TakeMailMoney(i)
end

function OPS.takeMailItem(key)
  local i = mailWith(key)
  if not i then return 0 end
  return D.TakeMailItem(i, 1)
end

--- Send the first stack of `key` and `money` copper to the session's own alt.
function OPS.sendAlt(key, money)
  local bagID, slot = slotOf("bags", key)
  local name = altKey():match("^([^%-]+)")
  return D.Send(name, bagID and { { bagID, slot } } or {}, money)
end

function OPS.trade(target)
  return D.TradeAccept(target == "@alt" and altKey() or target)
end

function OPS.currencyTransfer(id, qty)
  return D.CurrencyTransfer(id, qty, altKey())
end

--- Play one step: every call in order. Answers the number of handlers its events reached.
function Host.Play(step)
  local n = 0
  for _, call in ipairs(step.calls or {}) do
    local op = OPS[call[1]]
    if not op then error("SimScenario: unknown op '" .. tostring(call[1]) .. "'", 0) end
    n = n + (op(unpack(call, 2)) or 0)
  end
  return n
end

-- ── the gate ──────────────────────────────────────────────────────────────────────────────────

--- Open (true) when the Reconciler has nothing in flight, else false and the line to print.
function Host.Gate()
  local R = NS.Reconciler
  local w = Host.world
  local deferred = R.deferred and not (w and w.combat)
  if R._pending or R._holdSince or deferred then
    return false, L["The ledger is still settling: the next step waits for it."]
  end
  return true
end

-- ── the scenarios (req-lh-sim §7) ────────────────────────────────────────────────────────────

local CREST = World.FIXTURE.currencies[1][1]
local B1, B2 = KEY.bosses[1], KEY.bosses[2]
local NPC = { id = 219000, name = "Rookery Bat" }

-- Each step: kind, label, tip (what it injects), calls.
local function step(kind, label, tip, calls) return { kind = kind, label = label, tip = tip, calls = calls } end

local STEPS = {}

STEPS.loot = {
  step("kill", L["Kill: %s"]:format(NPC.name),
    { L["LOOT_OPENED (Creature GUID)"], L["Two CHAT_MSG_LOOT lines, one before its bag burst and one after"],
      L["A poor item under the threshold, then CHAT_MSG_MONEY"] },
    { { "lootOpened", "Creature", NPC.id, 4 }, { "loot", "herb", 1 }, { "loot", "ore", 3, { bagsFirst = true } },
      { "loot", "junk", 1 }, { "money", 12345 }, { "lootClosed" } }),
  step("container", L["Lockbox: open %s"]:format(World.ITEMS.cache.name),
    { L["hook:UseContainerItem on a lootable slot"], L["Two pushed CHAT_MSG_LOOT lines"] },
    { { "use", "cache" }, { "loot", "herb", 2, { form = "pushed" } }, { "loot", "dust", 1, { form = "pushed" } } }),
  step("quest", L["Quest: turn in"],
    { L["hook:GetQuestReward, QUEST_TURNED_IN with money"], L["The reward's pushed CHAT_MSG_LOOT line"] },
    { { "questReward", 84000, 2, 9000 }, { "loot", "trinket", 1, { form = "pushed" } } }),
}

STEPS.key = {
  step("zone", L["Enter: %s"]:format(KEY.zone), { L["ZONE_CHANGED_NEW_AREA into a party instance"] },
    { { "zone", { party = true, zone = KEY.zone, subzone = KEY.subzone, mapID = KEY.mapID } } }),
  step("keyStart", L["Key: start +%d"]:format(KEY.level), { L["CHALLENGE_MODE_START"] },
    { { "keyStart", KEY.mapID, KEY.level } }),
  step("pull", L["Pull: %s"]:format(B1.name),
    { L["Combat on, ENCOUNTER_START"], L["A potion drunk in combat: the flush waits for the regen edge"] },
    { { "combat", true }, { "encounterStart", B1.encounter, B1.name }, { "use", "potion", { consume = 1 } } }),
  step("kill", L["Kill: %s"]:format(B1.name),
    { L["ENCOUNTER_END (success), PLAYER_REGEN_ENABLED"], L["LOOT_OPENED (Creature GUID), CHAT_MSG_LOOT"] },
    { { "encounterEnd", B1.encounter, B1.name }, { "combat", false }, { "lootOpened", "Creature", B1.npc, 1 },
      { "loot", "trinket", 1 }, { "lootClosed" } }),
  step("pull", L["Pull: %s"]:format(B2.name), { L["Combat on, ENCOUNTER_START"] },
    { { "combat", true }, { "encounterStart", B2.encounter, B2.name }, { "use", "potion", { consume = 1 } } }),
  step("kill", L["Kill: %s"]:format(B2.name),
    { L["ENCOUNTER_END (success), PLAYER_REGEN_ENABLED"], L["LOOT_OPENED (Creature GUID), CHAT_MSG_LOOT"] },
    { { "encounterEnd", B2.encounter, B2.name }, { "combat", false }, { "lootOpened", "Creature", B2.npc, 1 },
      { "loot", "ore", 2 }, { "lootClosed" } }),
  step("keyDone", L["Key: completed"], { L["CHALLENGE_MODE_COMPLETED"] }, { { "keyCompleted" } }),
  step("chest", L["Chest: end of the key"],
    { L["LOOT_OPENED (GameObject GUID), CHAT_MSG_LOOT"], L["CHAT_MSG_CURRENCY, CURRENCY_DISPLAY_UPDATE"] },
    { { "lootOpened", "GameObject", KEY.chest, 2 }, { "loot", "herb", 3 }, { "currency", CREST, 15 },
      { "lootClosed" } }),
  step("bonus", L["Bonus roll"], { L["A bonus-roll CHAT_MSG_LOOT line"] },
    { { "loot", "trinket", 1, { form = "bonus" } } }),
  step("roll", L["Roll: won"], { L["LOOT_ROLL_YOU_WON, then the item's CHAT_MSG_LOOT line"] },
    { { "rollWon", "dust" }, { "loot", "dust", 2 } }),
  step("zone", L["Leave the dungeon"], { L["ZONE_CHANGED_NEW_AREA out of the instance"] },
    { { "zone", OPEN_WORLD } }),
}

STEPS.vendor = {
  step("open", L["Merchant: open"], { L["PLAYER_INTERACTION_MANAGER_FRAME_SHOW (Merchant)"] }, { { "open", "Merchant" } }),
  step("sell", L["Merchant: sell 3"], { L["hook:UseContainerItem, then the bags and the purse"] },
    { { "use", "herb", { consume = 3, sell = 450 } } }),
  step("buy", L["Merchant: buy"], { L["hook:BuyMerchantItem, then a pushed CHAT_MSG_LOOT line"] },
    { { "buy", 1, "potion", 2, 2500 }, { "line", "potion", 2, "pushed" } }),
  step("destroy", L["Destroy: %s"]:format(World.ITEMS.cache.name), { L["hook:DeleteCursorItem, the bag burst"] },
    { { "destroy", "cache" } }),
  step("repair", L["Merchant: repair"], { L["hook:RepairAllItems, PLAYER_MONEY"] }, { { "repair", 18000 } }),
  step("close", L["Merchant: close"], { L["PLAYER_INTERACTION_MANAGER_FRAME_HIDE (Merchant)"] }, { { "close", "Merchant" } }),
  step("disenchant", L["Disenchant: %s"]:format(World.ITEMS.trinket.name),
    { L["UNIT_SPELLCAST_SUCCEEDED (Disenchant), LOOT_OPENED (Item GUID)"],
      L["The materials' CHAT_MSG_LOOT line, the item leaving the bags"] },
    { { "cast", "disenchant" }, { "lootOpened", "Item", World.ITEMS.trinket.id, 1 }, { "loot", "dust", 3 },
      { "remove", "trinket", 1 }, { "lootClosed" } }),
}

STEPS.ah = {
  step("mailbox", L["Mailbox: check"], { L["MailInfo SHOW and HIDE: the mailbox's first read"] },
    { { "open", "MailInfo" }, { "close", "MailInfo" } }),
  step("open", L["Auction House: open"], { L["Auctioneer SHOW, OWNED_AUCTIONS_UPDATED"] }, { { "open", "Auctioneer" } }),
  step("post", L["Auction House: post 3"], { L["hook:PostItem with a deposit, three times"] },
    { { "post", "herb", 5, 300 }, { "post", "ore", 4, 200 }, { "post", "trinket", 1, 1500 } }),
  step("bid", L["Auction House: buy"], { L["hook:PlaceBid, PLAYER_MONEY"] }, { { "auctionBuy", "dust", 2, 7000 } }),
  step("close", L["Auction House: close"], { L["Auctioneer HIDE"] }, { { "close", "Auctioneer" } }),
  step("away", L["Later: one sold, one expired"],
    { L["Auctioneer SHOW: one auction sold, one expired, one still listed"] },
    { { "auctionSoldAway", "herb", 60000 }, { "auctionExpiredAway", "ore" }, { "open", "Auctioneer" } }),
  step("close", L["Auction House: close"], { L["Auctioneer HIDE"] }, { { "close", "Auctioneer" } }),
  step("mailbox", L["Mailbox: open"], { L["MailInfo SHOW, MAIL_INBOX_UPDATE"] }, { { "open", "MailInfo" } }),
  step("money", L["Mailbox: take the sale money"], { L["hook:TakeInboxMoney, PLAYER_MONEY"] }, { { "takeMailMoney" } }),
  step("items", L["Mailbox: take the won and the expired item"], { L["hook:TakeInboxItem twice, the bag burst"] },
    { { "takeMailItem", "dust" }, { "takeMailItem", "ore" } }),
  step("close", L["Mailbox: close"], { L["MailInfo HIDE"] }, { { "close", "MailInfo" } }),
}

STEPS.bank = {
  step("open", L["Bank: open"], { L["Banker SHOW: the bank's first read"] }, { { "open", "Banker" } }),
  step("deposit", L["Bank: deposit 2 stacks"], { L["BAG_UPDATE, PLAYERBANKSLOTS_CHANGED, twice"] },
    { { "move", "herb", "bags", "bank" }, { "move", "dust", "bags", "bank" } }),
  step("warband", L["Warband bank: open"], { L["AccountBanker SHOW"] }, { { "open", "AccountBanker" } }),
  step("deposit", L["Warband bank: deposit"],
    { L["A stack into a warband tab"], L["Gold into the warband bank: PLAYER_MONEY, ACCOUNT_MONEY"] },
    { { "move", "ore", "bags", "tabs" }, { "warbandGold", 250000 } }),
  step("withdraw", L["Warband bank: withdraw 1"], { L["A stack out of a warband tab, the bag burst"] },
    { { "move", "herb", "tabs", "bags" } }),
  step("close", L["Bank: close"], { L["AccountBanker and Banker HIDE"] },
    { { "close", "AccountBanker" }, { "close", "Banker" } }),
}

STEPS.social = {
  step("mailbox", L["Mailbox: open"], { L["MailInfo SHOW, MAIL_INBOX_UPDATE"] }, { { "open", "MailInfo" } }),
  step("send", L["Mail: send to your alt"], { L["hook:SendMail, MAIL_SEND_SUCCESS, the bag burst"] },
    { { "sendAlt", "ore", 50000 } }),
  step("close", L["Mailbox: close"], { L["MailInfo HIDE"] }, { { "close", "MailInfo" } }),
  step("trade", L["Trade: with your alt"], { L["TRADE_ACCEPT_UPDATE (1, 1), the bags both ways"] },
    { { "trade", "@alt" }, { "remove", "herb", 2 }, { "receive", "potion", 1 } }),
  step("trade", L["Trade: with a stranger"], { L["TRADE_ACCEPT_UPDATE (1, 1), the bags both ways"] },
    { { "trade", "Stranger-Realm" }, { "remove", "dust", 1 }, { "receive", "herb", 4 } }),
  step("transfer", L["Currency: transfer to your alt"],
    { L["CURRENCY_DISPLAY_UPDATE, CURRENCY_TRANSFER_LOG_UPDATE"] }, { { "currencyTransfer", CREST, 20 } }),
}

local function copyCall(call)
  local out = {}
  for i, v in ipairs(call) do
    if type(v) == "table" then
      local t = {}
      for k, x in pairs(v) do t[k] = x end
      out[i] = t
    else
      out[i] = v
    end
  end
  return out
end

--- The library's `timeline(def, opts)`: fresh step tables from the def's template, every call.
local function timeline(def)
  local out = {}
  for i, s in ipairs(def.steps) do
    local tip, calls = {}, {}
    for j, line in ipairs(s.tip or {}) do tip[j] = line end
    for j, call in ipairs(s.calls) do calls[j] = copyCall(call) end
    out[i] = { kind = s.kind, label = s.label, tip = tip, calls = calls }
  end
  return out
end

local LABELS = {
  loot = L["Open world: kill, lockbox, quest"], key = L["Mythic+ key"], vendor = L["Merchant and disenchant"],
  ah = L["Auction House day"], bank = L["Bank and warband bank"], social = L["Mail, trade and transfer"],
}

for _, name in ipairs({ "loot", "key", "vendor", "ah", "bank", "social" }) do
  if not SC.defs[name] then
    SC.names[#SC.names + 1] = name
    SC.defs[name] = { label = LABELS[name], fixture = scenarioFixture(), steps = STEPS[name], timeline = timeline }
  end
end
