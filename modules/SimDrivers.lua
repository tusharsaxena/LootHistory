local _, NS = ...

-- modules/SimDrivers.lua: the simulator's event and hook drivers (LootHistory#37; req-lh-sim.md
-- §2.3-§2.4).
--
-- ── ONE RULE PER DRIVER ──────────────────────────────────────────────────────────────────────
--
-- A driver changes the world (NS.SimHost.world, modules/SimWorld.lua) FIRST, then fires the
-- client's events through NS.Sim:Fire, with the client's payload shapes, in the client's order.
-- The capture engine is then on its own: the drivers never call Database:Add, Holdings:Apply*,
-- Attribution:Stamp or R:Write, and never write a source, a reason or a row. If a simulated row
-- reads AH_SOLD, Ledger.PickReason decided it.
--
-- The chat lines are formatted from the SAME globals the parser compiles (Util.LootGlobals,
-- Util.CurrencyGlobals, YOU_LOOT_MONEY / LOOT_MONEY_SPLIT with GOLD/SILVER/COPPER_AMOUNT), so a
-- line the client would write is the line a driver writes, in every locale.
--
-- ── HOOKS ────────────────────────────────────────────────────────────────────────────────────
--
-- A hooked client function (the HOOK_ROWS names: buying, mail, auctions, crafting, ...) is NEVER
-- called here; tests/test_sim_seam.lua scans this file for it. A hook driver plays the post-hook
-- the client would run: the world reads as the client shows it when the post-hook runs (a used
-- slot still holds its item, a sent mail is still staged), then Fire("hook:<name>", <the call's
-- arguments>) reaches every hook row through NS.DeliverAll, then the server's answer lands in the
-- world and its events fire (bags, money, mail, auctions).
--
-- Every driver answers the number of handlers its events reached, and 0 with no session.

NS.SimHost = NS.SimHost or {}
local Host = NS.SimHost
local D = Host.Drivers or {}
Host.Drivers = D

local World = Host.World

-- The deconstruct casts the scenarios play (Attribution.DECONSTRUCT's ids).
D.SPELLS = { disenchant = 13262, milling = 51005, prospecting = 31252 }

local lineID = 0

local function fire(event, ...) return NS.Sim:Fire(event, ...) end

-- The world while a session runs, else nil: a driver with no world changes and fires nothing.
local function world()
  if not NS.Sim:IsActive() then return nil end
  return Host.world
end

local function playerName() return (NS.Util.PlayerKey():match("^([^%-]+)")) end

local function playerGUID()
  return type(UnitGUID) == "function" and UnitGUID("player") or "Player-0-00000000"
end

-- The client's seventeen CHAT_MSG_* arguments for a line the player's own client wrote.
local function chat(event, text)
  lineID = lineID + 1
  local name = playerName()
  return fire(event, text, name, "", "", name, "", 0, 0, "", 0, lineID, playerGUID(), 0,
    false, false, false, false)
end

-- Fire each event of `list` ({ event, args... }) in order; answer the handler count.
local function burst(list)
  local n = 0
  for _, ev in ipairs(list) do n = n + fire(unpack(ev)) end
  return n
end

local function bagBurst(bagIDs)
  local list, seen = {}, {}
  for _, bagID in ipairs(bagIDs) do
    if bagID and not seen[bagID] then seen[bagID] = true; list[#list + 1] = { "BAG_UPDATE", bagID } end
  end
  list[#list + 1] = { "BAG_UPDATE_DELAYED" }
  return burst(list)
end

-- ── the line writers ──────────────────────────────────────────────────────────────────────────

-- Util.LootGlobals' positions: 1-5 are the quantity forms, 6-10 the single forms.
local LOOT_FORM = { self = 1, pushed = 2, bonus = 3, created = 4, refund = 5 }

--- A self-loot line for `link` x `qty`, in the `form` the client would use (default "self").
function D.LootText(link, qty, form)
  local g = { NS.Util.LootGlobals() }
  local i = LOOT_FORM[form or "self"] or 1
  if (qty or 1) > 1 then return (g[i] or g[1]):format(link, qty) end
  return (g[i + 5] or g[6]):format(link)
end

--- A self-currency line: CURRENCY_GAINED_MULTIPLE or CURRENCY_GAINED (Util.CurrencyGlobals 3, 5).
function D.CurrencyText(link, qty)
  local g = { NS.Util.CurrencyGlobals() }
  if (qty or 1) > 1 then return g[3]:format(link, qty) end
  return g[5]:format(link)
end

--- "1 Gold, 2 Silver, 3 Copper", any part left out when it is zero.
function D.MoneyString(copper)
  local parts = {}
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then parts[#parts + 1] = GOLD_AMOUNT:format(g) end
  if s > 0 then parts[#parts + 1] = SILVER_AMOUNT:format(s) end
  if c > 0 then parts[#parts + 1] = COPPER_AMOUNT:format(c) end
  return table.concat(parts, ", ")
end

function D.MoneyText(copper, split)
  return ((split and LOOT_MONEY_SPLIT) or YOU_LOOT_MONEY):format(D.MoneyString(copper))
end

--- A GUID of `kind` the client would hand out: Creature-0-…-<npcID>-…, GameObject-…, Item-….
function D.GUID(kind, id)
  if kind == "Item" then return ("Item-3767-0-4000000%08X"):format(id or 1) end
  return ("%s-0-3767-2552-11111-%d-0000ABCDEF"):format(kind, id or 0)
end

-- ── chat drivers ──────────────────────────────────────────────────────────────────────────────

--- The player loots `qty` of `key`: the stack lands in the bags, then CHAT_MSG_LOOT and the bag
--- burst. `opts.form` picks the line ("self", "pushed", "bonus", "created", "refund");
--- `opts.bagsFirst` fires the bag burst before the line, as the client sometimes does.
function D.Loot(key, qty, opts)
  local w = world()
  if not w then return 0 end
  opts = opts or {}
  qty = qty or 1
  local spec = World.Spec(w, key)
  local bagID = World.AddItem(w, "bags", spec, qty)
  local text = D.LootText(World.Link(spec), qty, opts.form)
  if opts.bagsFirst then return bagBurst({ bagID }) + chat("CHAT_MSG_LOOT", text) end
  return chat("CHAT_MSG_LOOT", text) + bagBurst({ bagID })
end

--- A self-loot line alone, for a stack the bags already show: a purchase's pushed line, whose
--- stack D.Buy has put in the bags. `form` as D.Loot takes it.
function D.LootLine(key, qty, form)
  local w = world()
  if not w then return 0 end
  return chat("CHAT_MSG_LOOT", D.LootText(World.Link(World.Spec(w, key)), qty or 1, form))
end

--- "You won: <item>": the roll result only; the item follows on its own loot line (D.Loot).
function D.RollWon(key)
  local w = world()
  if not w then return 0 end
  return chat("CHAT_MSG_LOOT", LOOT_ROLL_YOU_WON:format(World.Link(World.Spec(w, key))))
end

--- `qty` of currency `id`: the world's balance first, then CHAT_MSG_CURRENCY and
--- CURRENCY_DISPLAY_UPDATE(id, quantity, change, gainSource, lostSource).
function D.Currency(id, qty, gainSource)
  local w = world()
  if not w then return 0 end
  local change = World.AddCurrency(w, id, qty)
  local quantity = 0
  for _, c in ipairs(w.currencies) do if c.id == id then quantity = c.quantity end end
  return chat("CHAT_MSG_CURRENCY", D.CurrencyText(World.CurrencyLink(id), qty))
    + fire("CURRENCY_DISPLAY_UPDATE", id, quantity, change, gainSource, nil)
end

--- Looted coin (`split` for a party share): the purse first, then CHAT_MSG_MONEY and PLAYER_MONEY.
function D.Money(copper, split)
  local w = world()
  if not w then return 0 end
  World.AddMoney(w, copper)
  return chat("CHAT_MSG_MONEY", D.MoneyText(copper, split)) + fire("PLAYER_MONEY")
end

-- ── loot window, encounters, keys, zones, casts, quests, trades ──────────────────────────────

--- A loot window over a `kind` source ("Creature", "GameObject", "Item") with `n` slots. The GUID
--- is the provider's (Compat.LootSourceGUID); LOOT_OPENED carries (autoLoot, isFromItem).
function D.LootOpened(kind, id, n)
  local w = world()
  if not w then return 0 end
  World.OpenLoot(w, D.GUID(kind, id), n or 1)
  return fire("LOOT_OPENED", true, kind == "Item")
end

--- The window closes. No capture row listens to LOOT_CLOSED; only the world changes.
function D.LootClosed()
  local w = world()
  if w then World.CloseLoot(w) end
  return 0
end

function D.EncounterStart(id, name, difficulty, size)
  if not world() then return 0 end
  return fire("ENCOUNTER_START", id, name, difficulty, size)
end

function D.EncounterEnd(id, name, difficulty, size, success)
  if not world() then return 0 end
  return fire("ENCOUNTER_END", id, name, difficulty, size, success == false and 0 or 1)
end

--- A keystone starts in a party instance: CHALLENGE_MODE_START(mapID).
function D.KeyStart(mapID, level)
  local w = world()
  if not w then return 0 end
  World.SetInstance(w, { party = true, keystone = level, mapID = mapID })
  return fire("CHALLENGE_MODE_START", mapID)
end

function D.KeyCompleted()
  if not world() then return 0 end
  return fire("CHALLENGE_MODE_COMPLETED")
end

function D.KeyReset(mapID)
  local w = world()
  if not w then return 0 end
  World.SetInstance(w, { keystone = false })
  return fire("CHALLENGE_MODE_RESET", mapID)
end

--- The player changes zone: the situation first (party, keystone, zone, subzone, mapID), then
--- ZONE_CHANGED_NEW_AREA, which carries nothing.
function D.Zone(fields)
  local w = world()
  if not w then return 0 end
  World.SetInstance(w, fields or {})
  return fire("ZONE_CHANGED_NEW_AREA")
end

--- A player cast succeeds: UNIT_SPELLCAST_SUCCEEDED("player", castGUID, spellID).
function D.Cast(spellID)
  if not world() then return 0 end
  return fire("UNIT_SPELLCAST_SUCCEEDED", "player", ("Cast-3-3767-2552-11111-%d-0000ABCDEF"):format(spellID),
    spellID)
end

--- QUEST_TURNED_IN(questID, xp, money); the money reaches the purse first.
function D.QuestTurnedIn(questID, xp, copper)
  local w = world()
  if not w then return 0 end
  if (copper or 0) > 0 then World.AddMoney(w, copper) end
  local n = fire("QUEST_TURNED_IN", questID, xp or 0, copper or 0)
  if (copper or 0) > 0 then n = n + fire("PLAYER_MONEY") end
  return n
end

--- Both sides accept a trade with `target`: TRADE_ACCEPT_UPDATE(1, 1).
function D.TradeAccept(target)
  local w = world()
  if not w then return 0 end
  World.SetTrade(w, target)
  return fire("TRADE_ACCEPT_UPDATE", 1, 1)
end

-- What the client fires once an interaction frame is up: the inbox and the owned list arrive.
local FOLLOW_SHOW = { MailInfo = { "MAIL_INBOX_UPDATE" }, Auctioneer = { "OWNED_AUCTIONS_UPDATED" } }

--- An interaction frame opens: PLAYER_INTERACTION_MANAGER_FRAME_SHOW(type), then what the client
--- sends once it is up. `name` is an Enum.PlayerInteractionType member (Merchant, MailInfo,
--- Auctioneer, Banker, AccountBanker).
function D.Open(name)
  if not world() then return 0 end
  local n = fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", NS.Compat.InteractionType(name))
  for _, ev in ipairs(FOLLOW_SHOW[name] or {}) do n = n + fire(ev) end
  return n
end

function D.Close(name)
  if not world() then return 0 end
  return fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", NS.Compat.InteractionType(name))
end

-- ── bursts ────────────────────────────────────────────────────────────────────────────────────

--- Combat starts (the lockdown the Reconciler defers on) or ends with PLAYER_REGEN_ENABLED.
function D.Combat(on)
  local w = world()
  if not w then return 0 end
  World.SetCombat(w, on)
  if on then return 0 end
  return fire("PLAYER_REGEN_ENABLED")
end

function D.Bags(bagIDs) if not world() then return 0 end return bagBurst(bagIDs or {}) end
function D.Equipment(slot, hasCurrent)
  if not world() then return 0 end
  return fire("PLAYER_EQUIPMENT_CHANGED", slot, hasCurrent ~= false)
end
function D.PlayerMoney() if not world() then return 0 end return fire("PLAYER_MONEY") end
function D.AccountMoney() if not world() then return 0 end return fire("ACCOUNT_MONEY") end
function D.BankSlots(slot) if not world() then return 0 end return fire("PLAYERBANKSLOTS_CHANGED", slot) end
function D.TabSlots(tab) if not world() then return 0 end return fire("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", tab) end
function D.Inbox() if not world() then return 0 end return fire("MAIL_INBOX_UPDATE") end
function D.OwnedAuctions() if not world() then return 0 end return fire("OWNED_AUCTIONS_UPDATED") end

--- A currency moved to another character of the warband: the world's balance and the transfer
--- log first, then CURRENCY_DISPLAY_UPDATE and CURRENCY_TRANSFER_LOG_UPDATE.
function D.CurrencyTransfer(id, qty, toKey, lostSource)
  local w = world()
  if not w then return 0 end
  local change = World.AddCurrency(w, id, -qty)
  World.SetTransfer(w, { currencyID = id, quantity = qty, toKey = toKey })
  local quantity = 0
  for _, c in ipairs(w.currencies) do if c.id == id then quantity = c.quantity end end
  return fire("CURRENCY_DISPLAY_UPDATE", id, quantity, change, nil, lostSource)
    + fire("CURRENCY_TRANSFER_LOG_UPDATE")
end

--- Gold into (positive) or out of the warband bank: both purses, then PLAYER_MONEY, ACCOUNT_MONEY.
function D.WarbandGold(copper)
  local w = world()
  if not w then return 0 end
  World.AddMoney(w, -copper)
  World.SetWarbandMoney(w, w.warbandMoney + copper)
  return fire("PLAYER_MONEY") + fire("ACCOUNT_MONEY")
end

--- Move one stack between containers (bags, bank, tabs), then the slot events the client sends.
function D.Move(bagID, slot, toWhere)
  local w = world()
  if not w then return 0 end
  local toBag = World.MoveSlot(w, bagID, slot, toWhere)
  local n = bagBurst({ bagID, toBag })
  if toWhere == "bank" then n = n + fire("PLAYERBANKSLOTS_CHANGED", slot) end
  if toWhere == "tabs" then n = n + fire("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", toBag) end
  return n
end

-- ── hook drivers (post-hooks; the hooked function itself is never called) ────────────────────

local function hook(name, ...) return fire("hook:" .. name, ...) end

--- Buy `qty` of `key` from merchant slot `index` for `price` copper: the item and the cost land,
--- then hook:BuyMerchantItem(index, qty) (StampVendor, then StampOut BUY), then the bursts.
function D.Buy(index, key, qty, price)
  local w = world()
  if not w then return 0 end
  local bagID = World.AddItem(w, "bags", key, qty or 1)
  World.AddMoney(w, -(price or 0))
  return hook("BuyMerchantItem", index, qty or 1) + bagBurst({ bagID }) + fire("PLAYER_MONEY")
end

--- Buy back buyback slot `index`.
function D.Buyback(index, key, qty, price)
  local w = world()
  if not w then return 0 end
  local bagID = World.AddItem(w, "bags", key, qty or 1)
  World.AddMoney(w, -(price or 0))
  return hook("BuybackItem", index) + bagBurst({ bagID }) + fire("PLAYER_MONEY")
end

--- Use a bag item: hook:UseContainerItem(bag, slot) while the slot still holds it (a merchant
--- sale, a container open, a spell's target), then `effect.sell` copper, `effect.consume` (the
--- stack leaves) and `effect.contents` ({ { key, qty } } pushed into the bags) land.
function D.UseItem(bagID, slot, effect)
  local w = world()
  if not w then return 0 end
  effect = effect or {}
  local n = hook("UseContainerItem", bagID, slot)
  local touched = { bagID }
  if effect.consume ~= false then World.TakeSlot(w, bagID, slot, effect.consume) end
  for _, c in ipairs(effect.contents or {}) do touched[#touched + 1] = World.AddItem(w, "bags", c[1], c[2]) end
  n = n + bagBurst(touched)
  if (effect.sell or 0) > 0 then World.AddMoney(w, effect.sell); n = n + fire("PLAYER_MONEY") end
  return n
end

--- Repair everything for `cost`: the purse, then hook:RepairAllItems(), then PLAYER_MONEY.
function D.Repair(cost)
  local w = world()
  if not w then return 0 end
  World.AddMoney(w, -(cost or 0))
  return hook("RepairAllItems") + fire("PLAYER_MONEY")
end

--- Destroy the stack in one slot: hook:DeleteCursorItem() (the item is on the cursor), then it
--- is gone.
function D.Destroy(bagID, slot)
  local w = world()
  if not w then return 0 end
  local n = hook("DeleteCursorItem")
  World.TakeSlot(w, bagID, slot)
  return n + bagBurst({ bagID })
end

--- Take attachment `a` of mail `index`: hook:TakeInboxItem(index, a) while the mail is there.
function D.TakeMailItem(index, a)
  local w = world()
  if not w then return 0 end
  local n = hook("TakeInboxItem", index, a or 1)
  local bagID = World.TakeMailItem(w, index, a or 1)
  return n + bagBurst({ bagID }) + fire("MAIL_INBOX_UPDATE")
end

--- Take everything from mail `index`: hook:AutoLootMailItem(index), then its items and money.
function D.AutoLootMail(index)
  local w = world()
  if not w then return 0 end
  local n = hook("AutoLootMailItem", index)
  local touched, m = {}, w.inbox[index]
  local copper = m and m.money or 0
  while m and #m.items > 0 and w.inbox[index] == m do touched[#touched + 1] = World.TakeMailItem(w, index, 1) end
  if copper > 0 and w.inbox[index] == m then World.TakeMailMoney(w, index) end
  n = n + bagBurst(touched)
  if copper > 0 then n = n + fire("PLAYER_MONEY") end
  return n + fire("MAIL_INBOX_UPDATE")
end

--- Take the money of mail `index`: hook:TakeInboxMoney(index) while the mail is there.
function D.TakeMailMoney(index)
  local w = world()
  if not w then return 0 end
  local n = hook("TakeInboxMoney", index)
  World.TakeMailMoney(w, index)
  return n + fire("PLAYER_MONEY") + fire("MAIL_INBOX_UPDATE")
end

--- Send a mail. `items` = { { bagID, slot } } staged from the bags, `money` copper. The staged
--- frame reads as the client's while hook:SendMail(recipient, subject, body) runs; then
--- MAIL_SEND_SUCCESS with the bags and purse emptied, or MAIL_FAILED(itemID) with nothing sent.
function D.Send(recipient, items, money, failed)
  local w = world()
  if not w then return 0 end
  local staged = {}
  for _, it in ipairs(items or {}) do
    local e = World.Bag(w, it[1])[it[2]]
    if e then staged[e.itemID] = (staged[e.itemID] or 0) + e.count end
  end
  w.sendMail = { items = staged, money = money or 0 }
  local n = hook("SendMail", recipient, "", "")
  w.sendMail = nil
  if failed then return n + fire("MAIL_FAILED", next(staged)) end
  local touched = {}
  for _, it in ipairs(items or {}) do World.TakeSlot(w, it[1], it[2]); touched[#touched + 1] = it[1] end
  World.AddMoney(w, -(money or 0))
  return n + fire("MAIL_SEND_SUCCESS") + bagBurst(touched) + fire("PLAYER_MONEY")
end

--- Post `qty` from one bag slot for `deposit` copper: hook:PostItem(itemLocation, duration, qty)
--- while the slot holds it (ItemLocationID answers from the world), then the auction, the bag and
--- the deposit land. `commodity` posts through PostCommodity instead.
function D.Post(bagID, slot, qty, deposit, commodity)
  local w = world()
  if not w then return 0 end
  local loc = { bagID = bagID, slotIndex = slot }
  local n = hook(commodity and "PostCommodity" or "PostItem", loc, 1, qty or 1, nil)
  World.PostAuction(w, bagID, slot, qty)
  World.AddMoney(w, -(deposit or 0))
  return n + bagBurst({ bagID }) + fire("PLAYER_MONEY") + fire("OWNED_AUCTIONS_UPDATED")
end

--- Buy at the auction house: hook:PlaceBid(auctionID, price), or a commodity through
--- hook:ConfirmCommoditiesPurchase(itemID, qty); the cost leaves the purse and the item waits in
--- the mailbox.
function D.AuctionBuy(key, qty, price, commodity)
  local w = world()
  if not w then return 0 end
  World.AddMoney(w, -(price or 0))
  local spec = World.Spec(w, key)
  World.AddWonMail(w, spec, qty or 1)
  local n = commodity and hook("ConfirmCommoditiesPurchase", spec.id, qty or 1) or hook("PlaceBid", 1, price or 0)
  return n + fire("PLAYER_MONEY")
end

--- One owned auction sells (payout mailed) or expires (item mailed back), then the owned list.
function D.AuctionSold(index, copper)
  local w = world()
  if not w then return 0 end
  World.SellAuction(w, index, copper)
  return fire("OWNED_AUCTIONS_UPDATED")
end

function D.AuctionExpired(index)
  local w = world()
  if not w then return 0 end
  World.ExpireAuction(w, index)
  return fire("OWNED_AUCTIONS_UPDATED")
end

-- The three crafting entry points' argument shapes (recipeSpellID first, then the count).
local CRAFT = { recipe = "CraftRecipe", salvage = "CraftSalvage", enchant = "CraftEnchant" }

--- Craft: hook:<CraftRecipe|CraftSalvage|CraftEnchant>(recipeSpellID, count), then the reagents
--- ({ { key, qty } }) leave the bags. The product arrives on its own loot line (D.Loot, "created").
function D.Craft(kind, recipeSpellID, reagents)
  local w = world()
  if not w then return 0 end
  local n = hook(CRAFT[kind] or CRAFT.recipe, recipeSpellID, 1)
  local touched = {}
  for _, r in ipairs(reagents or {}) do
    local _, bags = World.RemoveItem(w, "bags", World.Spec(w, r[1]).id, r[2])
    for _, b in ipairs(bags) do touched[#touched + 1] = b end
  end
  return n + bagBurst(touched)
end

--- Take a quest reward: hook:GetQuestReward(choice) while the quest frame shows `questID`, then
--- QUEST_TURNED_IN. The reward items arrive on their own loot lines (D.Loot, "pushed").
function D.QuestReward(questID, choice, xp, copper)
  local w = world()
  if not w then return 0 end
  World.SetQuest(w, questID)
  local n = hook("GetQuestReward", choice or 1)
  World.SetQuest(w, nil)
  return n + D.QuestTurnedIn(questID, xp, copper)
end

--- Which driver plays each hooked function (tests/test_sim_drivers.lua walks HOOK_ROWS by it).
D.HOOK_DRIVER = {
  BuyMerchantItem = "Buy", BuybackItem = "Buyback", UseContainerItem = "UseItem",
  RepairAllItems = "Repair", DeleteCursorItem = "Destroy", TakeInboxItem = "TakeMailItem",
  AutoLootMailItem = "AutoLootMail", TakeInboxMoney = "TakeMailMoney", SendMail = "Send",
  PostItem = "Post", PostCommodity = "Post", PlaceBid = "AuctionBuy",
  ConfirmCommoditiesPurchase = "AuctionBuy", CraftRecipe = "Craft", CraftSalvage = "Craft",
  CraftEnchant = "Craft", GetQuestReward = "QuestReward",
}
