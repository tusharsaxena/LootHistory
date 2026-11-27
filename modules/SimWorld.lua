local _, NS = ...

-- modules/SimWorld.lua: the simulator's invented world and the seam's providers over it
-- (LootHistory#37; Ka0sAddonsCommonTasks req-lh-sim.md §2.1-§2.2).
--
-- ── THE WORLD ────────────────────────────────────────────────────────────────────────────────
--
-- One table per session, NS.SimHost.world, built by World.New when modules/Sim.lua's prepare runs
-- and dropped by its stop. It is the client as the capture engine reads it:
--
--   bags, bank, tabs   [bagID][slot] = { itemID, link, count, hasLoot }   (C.BAG_IDS, C.BANK_IDS,
--                      C.WARBAND_TAB_IDS); sizes[bagID] is each container's slot count
--   equipped[slot]     { itemID, link }        money, warbandMoney   copper
--   currencies         { { id, quantity, accountWide } }
--   inbox[i]           { sender, subject, money, items = { { itemID, link, count } } }
--   sendMail           { items = { [itemID] = n }, money } or nil (the staged Send Mail frame)
--   owned[i]           { itemID, link, quantity, status = "active" | "sold" }
--   loot               { guid, n } or nil (the open loot window)
--   instance           { party, keystone, zone, subzone, mapID }
--   combat, targeting  booleans     trade { target }, quest { id }, transfer { currencyID,
--                                   quantity, toKey }, each nil when absent
--   factions[id]       { name, repType, rank, standing, threshold, accountWide, label }, walked in
--                      factionOrder (rep-appearance spec §3.8)
--   appearances[src]   { item, visualID, collected } (Retail: C.FEATURE.appearances), the item a
--                      fixture key
--
-- It is SEEDED, never mirrored: World.New reads no real bag, so a run is deterministic for its
-- seed and never shows the player's own items inside a simulated history. The items and currencies
-- are real ids of the client running (Midnight, 12.0.x, on Retail; 1.x on WoW Forever, picked once
-- by ClientKey(), clients-§5), so the live item reads (GetItemInfo,
-- ScanBound, the AH price providers) answer for real; one fixture link carries bonus ids
-- (Item.BonusIDsFromLink, LH-02's adoption) and one is the item least likely to be cached, whose
-- rows fall back to the link's own name and color (Compat.GetItemInfo).
--
-- ── THE PROVIDERS ────────────────────────────────────────────────────────────────────────────
--
-- Registered once, at file load, through NS.SimSeam:SetProvider (a second registration for a key
-- raises, OWNER_SCOPE C.8), for exactly the world reads of req §2.2: World.PROVIDED lists them. A
-- provider runs only while a session is active (the seam's rule) and answers from the world. The
-- item, spell and currency reads and PlayerClassFile have no provider: the simulated player is the
-- real player, so live is right. InInstance, InGroup and PlayerInCombat have none either: only the
-- refusal and the automatic stop read them, through NS.SimSeam:Live.
--
-- Nothing here calls the capture engine or writes a row: the drivers (modules/SimDrivers.lua)
-- change this world and fire the client's events, and the engine decides the rest.

NS.SimHost = NS.SimHost or {}
local Host = NS.SimHost
local World = Host.World or {}
Host.World = World

-- ── fixture ───────────────────────────────────────────────────────────────────────────────────

-- Item quality -> link color (ITEM_QUALITY_COLORS' hex, written out: the link is built here).
local QUALITY_HEX = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }

-- The client, picked once at file load (clients-§5): the items, currencies, worn slot, situation
-- and the kill below are each client's own.
local CLIENT = NS.Compat.ClientKey() == "forever" and "forever" or "retail"
Host.SIM_CLIENT = CLIENT

--- The fixture's items, by key, one set per client, the ids taken from the owner's own captures.
--- Retail's are Midnight's (12.0.x), WoW Forever's 1.x's (its SavedVariables, 2026-11-22: there a
--- link carries the one bonus id 3524). `bonus` makes a link carry bonus ids; `uncached` marks the
--- one the client is least likely to have cached; `hasLoot` an openable one. `level` is the link's
--- level field (the player's: 90 on Retail, 60 on Forever). `trinket` is the key of the epic piece
--- the scenarios loot, disenchant and post, whatever slot it is worn in (FIXTURE.equipped).
local ITEM_SETS = {
  retail = {
    herb    = { id = 236761, name = "Tranquility Bloom", quality = 1, level = 90 },
    ore     = { id = 237359, name = "Refulgent Copper Ore", quality = 1, level = 90 },
    trinket = { id = 273796, name = "Vile Vial of Volatile Venom", quality = 4, level = 90,
                bonus = { 12843, 13440, 6652, 12699 } },
    cache   = { id = 279287, name = "Corroded Pouch", quality = 2, level = 90,
                hasLoot = true, uncached = true },
  },
  forever = {
    herb    = { id = 2449, name = "Earthroot", quality = 1, level = 60 },
    ore     = { id = 2770, name = "Copper Ore", quality = 1, level = 60 },
    trinket = { id = 19149, name = "Lava Belt", quality = 4, level = 60, bonus = { 3524 } },
    cache   = { id = 248683, name = "Waylaid Crate: Apprentice Ore", quality = 1, level = 60,
                hasLoot = true, uncached = true },
  },
}
World.ITEMS = ITEM_SETS[CLIENT]

--- The default fixture, one per client. A scenario def may carry its own as `def.fixture`;
--- `{ min, max }` pairs are drawn from the session seed. Retail's currencies are Champion Mistcrest
--- (per character) and Voidlight Marl (warband-wide), its situation Silvermoon City; WoW Forever's
--- are Honor Points and Merchant's Favor (the owner's own, both per character until a probe shows
--- either is account-wide), its situation Stormwind City (uiMapID 1453, as the client reported it),
--- and its epic is a belt, worn at the waist (slot 6).
--- The factions (rep-appearance spec §3.8): { id, name, repType, rank, standing, threshold,
--- accountWide }. Retail's are Stormwind and Booty Bay (base standings, absolute) and the Council of
--- Dornogal (renown: the level's earned reputation and its threshold, warband-wide); WoW Forever
--- answers base standings only, so its world holds the first two. The appearances are Retail's: two
--- sources of one visual on the fixture's own items, neither collected, so the first one collected is
--- a new look and the second is not. Fixtures like the items, not tools/seeds data.
local FIXTURES = {
  retail = {
    equipped = { [13] = "trinket" },
    currencies = { { 3444, 100, 400, false }, { 3316, 500, 1500, true } },
    instance = { zone = "Silvermoon City", subzone = "The Bazaar", mapID = 2393 },
    factions = { { 72, "Stormwind", "base", 5, 3000 }, { 21, "Booty Bay", "base", 4, 1500 },
                 { 2590, "Council of Dornogal", "renown", 10, 500, 2500, true } },
    appearances = { { 900001, "trinket", 800001 }, { 900002, "cache", 800001 } },
  },
  forever = {
    equipped = { [6] = "trinket" },
    currencies = { { 1792, 50, 400, false }, { 3402, 20, 200, false } },
    instance = { zone = "Stormwind City", subzone = "Trade District", mapID = 1453 },
    factions = { { 72, "Stormwind", "base", 5, 3000 }, { 21, "Booty Bay", "base", 4, 1500 } },
  },
}
World.FIXTURE = {
  slots = { bags = 16, bank = 28 },
  money = { 1500000, 2500000 },
  bags = { { "herb", 5, 20 }, { "ore", 5, 20 }, { "cache", 1, 1 } },
  bank = { { "ore", 20, 40 } },
}
-- The warband bank's tabs and gold only where it is a feature (C.FEATURE.warbandBank, clients-§4):
-- WoW Forever's world has neither, as its client has no warband bank.
if NS.Constants.FEATURE.warbandBank then
  World.FIXTURE.slots.tabs = 98
  World.FIXTURE.warbandMoney = { 5000000, 9000000 }
  World.FIXTURE.tabs = { { "herb", 20, 60 } }
end
for k, v in pairs(FIXTURES[CLIENT]) do World.FIXTURE[k] = v end

--- The creature the loot scenario kills and `/lh sim loot` loots, per client. Illustrative: nothing
--- resolves it live, it only rides into the rows' details (npcID) and the step's label.
World.KILL_NPC = ({ retail = { id = 219000, name = "Rookery Bat" }, forever = { id = 38, name = "Defias Thug" } })[CLIENT]

-- Park-Miller: exact in a double, so a seed answers the same sequence on every client.
local function newRng(seed)
  local state = (math.floor(tonumber(seed) or 1) % 2147483646) + 1
  return function(lo, hi)
    state = (state * 16807) % 2147483647
    if not lo then return state end
    return lo + (state % (hi - lo + 1))
  end
end

--- The fixture item for `key` (a fixture key, or an item id the fixture does not name).
function World.Spec(w, key)
  if type(key) == "table" then return key end
  local own = w and w.items and w.items[key]
  if own then return own end
  if World.ITEMS[key] then return World.ITEMS[key] end
  if type(key) == "number" then return { id = key, name = "item " .. key, quality = 1, level = 1 } end
  return nil
end

--- `|cffXXXXXX|Hitem:<id>::::::::<lvl>::::<nBonus>:<bonus…>|h[Name]|h|r` for a fixture item.
--- The bonus count is the itemString's field 13 (Item.BonusIDsFromLink's walk).
function World.Link(spec)
  local bonus = spec.bonus or {}
  local tail = #bonus > 0 and (#bonus .. ":" .. table.concat(bonus, ":")) or ""
  return ("|cff%s|Hitem:%d::::::::%d::::%s|h[%s]|h|r"):format(QUALITY_HEX[spec.quality or 1] or "ffffff",
    spec.id, spec.level or 1, tail, spec.name)
end

--- `|cffXXXXXX|Hcurrency:<id>:<qty>|h[Name]|h|r`, named by the live client when it can.
function World.CurrencyLink(id)
  local name = NS.Compat.CurrencyName(id) or ("currency " .. id)
  return ("|cffa335ee|Hcurrency:%d:0|h[%s]|h|r"):format(id, name)
end

-- ── containers ────────────────────────────────────────────────────────────────────────────────

local function idsOf(where)
  local C = NS.Constants
  if where == "bank" then return C.BANK_IDS end
  if where == "tabs" then return C.WARBAND_TAB_IDS end
  return C.BAG_IDS
end

--- The slot table of `bagID` in whichever container holds it, or nil.
function World.Bag(w, bagID)
  return w.bags[bagID] or w.bank[bagID] or w.tabs[bagID]
end

--- The first stack of `itemID` in `where` ("bags", "bank" or "tabs"): bagID, slot, entry.
function World.Find(w, where, itemID)
  for _, bagID in ipairs(idsOf(where)) do
    local bag = w[where][bagID]
    for slot = 1, (w.sizes[bagID] or 0) do
      local e = bag and bag[slot]
      if e and e.itemID == itemID then return bagID, slot, e end
    end
  end
  return nil
end

local function firstEmpty(w, where)
  for _, bagID in ipairs(idsOf(where)) do
    local bag = w[where][bagID]
    for slot = 1, (w.sizes[bagID] or 0) do
      if bag and bag[slot] == nil then return bagID, slot end
    end
  end
  return nil
end

-- Put a stack into `where`: onto the first stack of its id, else into the first empty slot.
local function place(w, where, e)
  local bagID, slot, held = World.Find(w, where, e.itemID)
  if held then held.count = held.count + e.count; return bagID, slot end
  bagID, slot = firstEmpty(w, where)
  if not bagID then return nil end
  w[where][bagID][slot] = { itemID = e.itemID, link = e.link, count = e.count, hasLoot = e.hasLoot == true }
  return bagID, slot
end

--- Add `count` of an item to `where`: onto its first stack, else into the first empty slot.
--- Answers the bagID and slot, or nil when the container is full.
function World.AddItem(w, where, key, count)
  local spec = World.Spec(w, key)
  return place(w, where, { itemID = spec.id, link = World.Link(spec), count = count or 1, hasLoot = spec.hasLoot })
end

--- Take `count` (default the whole stack) from one slot. Answers a copy of what was taken.
function World.TakeSlot(w, bagID, slot, count)
  local bag = World.Bag(w, bagID)
  local e = bag and bag[slot]
  if not e then return nil end
  local n = math.min(count or e.count, e.count)
  e.count = e.count - n
  if e.count <= 0 then bag[slot] = nil end
  return { itemID = e.itemID, link = e.link, count = n, hasLoot = e.hasLoot }
end

--- Remove up to `count` of `itemID` from `where`, stack by stack. Answers the count removed and
--- the bagIDs it touched.
function World.RemoveItem(w, where, itemID, count)
  local left, touched = count or 1, {}
  while left > 0 do
    local bagID, slot = World.Find(w, where, itemID)
    if not bagID then break end
    local took = World.TakeSlot(w, bagID, slot, left)
    left = left - took.count
    touched[#touched + 1] = bagID
  end
  return (count or 1) - left, touched
end

--- Move one whole stack into `toWhere`. Answers the destination bagID and slot.
function World.MoveSlot(w, bagID, slot, toWhere)
  local e = World.TakeSlot(w, bagID, slot)
  if not e then return nil end
  return place(w, toWhere, e)
end

-- ── money, currencies, situation ─────────────────────────────────────────────────────────────

function World.SetMoney(w, copper) w.money = math.max(0, copper) end
function World.AddMoney(w, delta) w.money = math.max(0, (w.money or 0) + delta) end
function World.SetWarbandMoney(w, copper) w.warbandMoney = math.max(0, copper) end

local function currencyRow(w, id)
  for _, c in ipairs(w.currencies) do if c.id == id then return c end end
  return nil
end

--- Set a currency's quantity, adding the row when the world has none. Answers the change.
function World.SetCurrency(w, id, quantity, accountWide)
  local c = currencyRow(w, id)
  if not c then
    c = { id = id, quantity = 0, accountWide = accountWide == true }
    w.currencies[#w.currencies + 1] = c
  end
  local change = quantity - c.quantity
  c.quantity = quantity
  return change
end

function World.AddCurrency(w, id, delta)
  local c = currencyRow(w, id)
  return World.SetCurrency(w, id, math.max(0, (c and c.quantity or 0) + delta), c and c.accountWide)
end

-- ── reputation and appearances (rep-appearance spec §3.8) ────────────────────────────────────

-- The base reaction bands on the absolute standing scale, lowest first: { floor, rank, label }. A
-- small static table: the world's own labels, as its item names are its own.
local REP_BASE_BANDS = {
  { -42000, 1, "Hated" }, { -6000, 2, "Hostile" }, { -3000, 3, "Unfriendly" }, { 0, 4, "Neutral" },
  { 3000, 5, "Friendly" }, { 9000, 6, "Honored" }, { 21000, 7, "Revered" }, { 42000, 8, "Exalted" },
}
World.REP_BASE_BANDS = REP_BASE_BANDS

local function baseBand(standing)
  local rank, label = 1, REP_BASE_BANDS[1][3]
  for _, b in ipairs(REP_BASE_BANDS) do
    if standing >= b[1] then rank, label = b[2], b[3] end
  end
  return rank, label
end

local function labelOf(f)
  if f.repType == "renown" then return ("Renown %d"):format(f.rank) end
  local _, label = baseBand(f.standing)
  return label
end

--- Add a faction to the world, at the end of the walk order.
function World.AddFaction(w, id, name, repType, rank, standing, threshold, accountWide)
  local f = { name = name, repType = repType, rank = rank, standing = standing, threshold = threshold,
    accountWide = accountWide == true or nil }
  if repType ~= "renown" then f.rank = baseBand(standing) end
  f.label = labelOf(f)
  if not w.factions[id] then w.factionOrder[#w.factionOrder + 1] = id end
  w.factions[id] = f
  return f
end

--- Move a faction's standing by `delta`. A base or friendship faction is absolute: its rank and label
--- follow the bands. A renown faction raises its level on overflow and keeps the remainder (renown
--- never falls). Answers the faction, or nil when the world has none of that id.
function World.AddReputation(w, id, delta)
  local f = w.factions[id]
  if not f then return nil end
  f.standing = f.standing + delta
  if f.repType == "renown" then
    f.standing = math.max(0, f.standing)
    while f.threshold and f.threshold > 0 and f.standing >= f.threshold do
      f.standing, f.rank = f.standing - f.threshold, f.rank + 1
    end
  else
    f.rank = baseBand(f.standing)
  end
  f.label = labelOf(f)
  return f
end

--- Mark an appearance source collected (or not). Answers the source, or nil when the world has none.
function World.SetAppearance(w, sourceID, collected)
  local a = w.appearances[sourceID]
  if a then a.collected = collected == true end
  return a
end

function World.OpenLoot(w, guid, n) w.loot = { guid = guid, n = n or 1 } end
function World.CloseLoot(w) w.loot = nil end
function World.SetCombat(w, on) w.combat = on == true end
function World.SetTargeting(w, on) w.targeting = on == true end
function World.SetTrade(w, target) w.trade = target and { target = target } or nil end
function World.SetQuest(w, id) w.quest = id and { id = id } or nil end
function World.SetTransfer(w, t) w.transfer = t end

--- Merge `fields` into the situation (party, keystone, zone, subzone, mapID). `false` clears a
--- field, so a keystone can end.
function World.SetInstance(w, fields)
  for k, v in pairs(fields) do
    if v == false and k ~= "party" then w.instance[k] = nil else w.instance[k] = v end
  end
end

-- ── mail and auctions ─────────────────────────────────────────────────────────────────────────

local function ahSender() return type(AUCTION_HOUSE) == "string" and AUCTION_HOUSE or "Auction House" end

local function ahSubject(global, name)
  return (type(global) == "string" and global or "%s"):format(name)
end

--- Append a mail and answer its index.
function World.AddMail(w, mail)
  mail.items, mail.money = mail.items or {}, mail.money or 0
  w.inbox[#w.inbox + 1] = mail
  return #w.inbox
end

local function dropEmptyMail(w, index)
  local m = w.inbox[index]
  if m and #m.items == 0 and (m.money or 0) == 0 then table.remove(w.inbox, index) end
end

--- Move attachment `a` of mail `index` into the bags. Answers the bagID it landed in.
function World.TakeMailItem(w, index, a)
  local m = w.inbox[index]
  local att = m and m.items[a]
  if not att then return nil end
  table.remove(m.items, a)
  local bagID = place(w, "bags", { itemID = att.itemID, link = att.link, count = att.count or 1 })
  dropEmptyMail(w, index)
  return bagID
end

--- Move the money of mail `index` into the purse. Answers the copper taken.
function World.TakeMailMoney(w, index)
  local m = w.inbox[index]
  local copper = m and m.money or 0
  if copper <= 0 then return 0 end
  m.money = 0
  World.AddMoney(w, copper)
  dropEmptyMail(w, index)
  return copper
end

--- Post `qty` from one bag slot. Answers the owned index and what was posted.
function World.PostAuction(w, bagID, slot, qty)
  local took = World.TakeSlot(w, bagID, slot, qty)
  if not took then return nil end
  w.owned[#w.owned + 1] = { itemID = took.itemID, link = took.link, quantity = took.count, status = "active" }
  return #w.owned, took
end

--- An owned auction sells: it leaves the active list and its payout arrives by mail.
function World.SellAuction(w, index, copper)
  local a = w.owned[index]
  if not a then return nil end
  a.status = "sold"
  return World.AddMail(w, { sender = ahSender(), money = copper or 0,
    subject = ahSubject(AUCTION_SOLD_MAIL_SUBJECT, a.link:match("%[(.-)%]") or "?") })
end

--- An owned auction expires: it leaves the list and the item comes back by mail.
function World.ExpireAuction(w, index)
  local a = table.remove(w.owned, index)
  if not a then return nil end
  return World.AddMail(w, { sender = ahSender(),
    subject = ahSubject(AUCTION_EXPIRED_MAIL_SUBJECT, a.link:match("%[(.-)%]") or "?"),
    items = { { itemID = a.itemID, link = a.link, count = a.quantity } } })
end

--- A won auction's item, waiting in the mailbox.
function World.AddWonMail(w, key, count)
  local spec = World.Spec(w, key)
  return World.AddMail(w, { sender = ahSender(), subject = ahSubject(AUCTION_WON_MAIL_SUBJECT, spec.name),
    items = { { itemID = spec.id, link = World.Link(spec), count = count or 1 } } })
end

-- ── building one ─────────────────────────────────────────────────────────────────────────────

local function draw(rng, pair)
  if type(pair) == "number" then return pair end
  return rng(pair[1], pair[2] or pair[1])
end

local function emptyWorld(fixture, seed)
  local inst = fixture.instance or {}
  return {
    seed = seed, items = fixture.items, bags = {}, bank = {}, tabs = {}, sizes = {}, equipped = {},
    money = 0, warbandMoney = 0, currencies = {}, inbox = {}, owned = {},
    factions = {}, factionOrder = {}, appearances = {},
    instance = { party = false, zone = inst.zone or "", subzone = inst.subzone or "", mapID = inst.mapID },
    combat = false, targeting = false,
  }
end

local function sizeContainers(w, slots)
  for _, where in ipairs({ "bags", "bank", "tabs" }) do
    for _, bagID in ipairs(idsOf(where)) do
      w[where][bagID] = {}
      w.sizes[bagID] = slots[where] or 0
    end
  end
end

local function stock(w, rng, where, list)
  for _, row in ipairs(list or {}) do World.AddItem(w, where, row[1], rng(row[2], row[3] or row[2])) end
end

-- The factions, and where appearances are a feature (C.FEATURE.appearances) the appearance sources,
-- from the fixture or else the default one. Neither draws from the seed.
local function seedProgress(w, fixture)
  for _, f in ipairs(fixture.factions or World.FIXTURE.factions or {}) do World.AddFaction(w, unpack(f)) end
  if not NS.Constants.FEATURE.appearances then return end
  for _, a in ipairs(fixture.appearances or World.FIXTURE.appearances or {}) do
    w.appearances[a[1]] = { item = a[2], visualID = a[3], collected = false }
  end
end

--- A fresh world for `fixture` (default World.FIXTURE) and `seed`: the same pair always builds the
--- same world. Reads nothing from the client but the item specs' own data.
function World.New(fixture, seed)
  fixture = fixture or World.FIXTURE
  local rng = newRng(seed)
  local w = emptyWorld(fixture, seed)
  sizeContainers(w, fixture.slots or World.FIXTURE.slots)
  w.money = draw(rng, fixture.money or 0)
  w.warbandMoney = draw(rng, fixture.warbandMoney or 0)
  for _, where in ipairs({ "bags", "bank", "tabs" }) do stock(w, rng, where, fixture[where]) end
  for slot, key in pairs(fixture.equipped or {}) do
    local spec = World.Spec(w, key)
    w.equipped[slot] = { itemID = spec.id, link = World.Link(spec) }
  end
  for _, c in ipairs(fixture.currencies or {}) do World.SetCurrency(w, c[1], rng(c[2], c[3] or c[2]), c[4]) end
  seedProgress(w, fixture)
  return w
end

-- ── the providers (req-lh-sim §2.2) ──────────────────────────────────────────────────────────

local function addCount(counts, links, id, n, link)
  counts[id] = (counts[id] or 0) + n
  if link and not links[id] then links[id] = link end
end

local function scanInbox(w)
  local counts, links = {}, {}
  for _, m in ipairs(w.inbox) do
    for _, att in ipairs(m.items) do addCount(counts, links, att.itemID, att.count or 1, att.link) end
  end
  return counts, links
end

local function scanOwned(w)
  local counts, links = {}, {}
  for _, a in ipairs(w.owned) do
    if a.status == "active" then addCount(counts, links, a.itemID, a.quantity or 1, a.link) end
  end
  return counts, links
end

local function readSendMail(w)
  local s, items = w.sendMail, {}
  if not s then return items, 0 end
  for id, n in pairs(s.items or {}) do items[id] = n end
  return items, s.money or 0
end

local function containerSlot(w, bagID, slot)
  local bag = World.Bag(w, bagID)
  local e = bag and bag[slot]
  if not e then return nil end
  return { itemID = e.itemID, link = e.link, count = e.count }
end

local function listCurrencies(w)
  local out = {}
  for i, c in ipairs(w.currencies or {}) do
    out[i] = { id = c.id, quantity = c.quantity, accountWide = c.accountWide == true }
  end
  return out
end

local function inventoryItem(w, slot)
  local e = w.equipped[slot]
  if not e then return nil end
  return e.itemID, e.link
end

local function lootSourceGUID(w, slot)
  local l = w.loot
  if l and slot and slot >= 1 and slot <= l.n then return l.guid end
  return nil
end

local function itemLocationID(w, loc)
  if type(loc) ~= "table" then return nil end
  local e = containerSlot(w, loc.bagID, loc.slotIndex)
  return e and e.itemID or nil
end

local function latestTransfer(w)
  local t = w.transfer
  if not t then return nil end
  return { currencyID = t.currencyID, quantity = t.quantity, toKey = t.toKey }
end

local function slotHasLoot(w, bag, slot)
  local b = World.Bag(w, bag)
  return (b and b[slot] and b[slot].hasLoot) == true
end

-- Compat.FactionSnapshot's values for a world faction, or nothing.
local function factionSnapshot(w, id)
  local f = w.factions[id]
  if not f then return nil end
  return f.name, f.repType, f.rank, f.standing, f.threshold, f.paragon, f.accountWide, f.label
end

-- Compat.ListFactions' rows, in the world's walk order. The GUARDED fallback is never reached.
local function listFactions(w)
  local out = {}
  for _, id in ipairs(w.factionOrder) do
    local f = w.factions[id]
    out[#out + 1] = { id = id, name = f.name, repType = f.repType, rank = f.rank, standing = f.standing,
      threshold = f.threshold, paragon = f.paragon, accountWide = f.accountWide, label = f.label }
  end
  return out
end

-- Compat.AppearanceSource's values for a world source: its fixture item, its link and its visual.
local function appearanceSource(w, sourceID)
  local a = w.appearances[sourceID]
  local spec = a and World.Spec(w, a.item)
  if not spec then return nil end
  return spec.id, World.Link(spec), spec.name, spec.quality, a.visualID, nil
end

-- Compat.IsNewLook: true when no other world source of the visual is collected.
local function isNewLook(w, visualID, sourceID)
  for id, a in pairs(w.appearances) do
    if id ~= sourceID and a.visualID == visualID and a.collected then return false end
  end
  return true
end

-- Each fn(world, ...) answers what the client would; the order is req §2.2's.
local PROVIDERS = {
  { "GetContainerNumSlots", function(w, bagID) return w.sizes[bagID] or 0 end },
  { "GetContainerSlot", containerSlot },
  { "GetInventoryItem", inventoryItem },
  { "GetMoney", function(w) return w.money end },
  { "GetWarbandMoney", function(w) return w.warbandMoney end },
  { "ListCurrencies", listCurrencies },
  { "ScanInbox", scanInbox },
  { "GetMailHeader", function(w, i) local m = w.inbox[i]; if m then return m.sender, m.subject end return nil, nil end },
  { "ReadSendMail", readSendMail },
  { "ScanOwnedAuctions", scanOwned },
  { "ItemLocationID", itemLocationID },
  { "ContainerItemHasLoot", slotHasLoot },
  { "IsSpellTargeting", function(w) return w.targeting == true end },
  { "CurrentQuestID", function(w) return w.quest and w.quest.id or nil end },
  { "GetActiveKeystoneLevel", function(w) return w.instance.keystone end },
  { "InPartyInstance", function(w) return w.instance.party == true end },
  { "InCombatLockdown", function(w) return w.combat == true end },
  { "TradeTargetKey", function(w) return w.trade and w.trade.target or nil end },
  { "LatestCurrencyTransfer", latestTransfer },
  { "NumLootItems", function(w) return w.loot and w.loot.n or 0 end },
  { "LootSourceGUID", lootSourceGUID },
  { "Zone", function(w) return w.instance.zone or "", w.instance.subzone or "" end },
  { "PlayerMapID", function(w) return w.instance.mapID end },
  -- The bank readiness guard's view check (ruling R8, the WoW Forever port): the simulated banker
  -- shows the character bank (unless a case sets w.canViewBank = false), whatever the real client
  -- answers away from a bank.
  { "CanViewCharacterBank", function(w) return w.canViewBank ~= false end },
  -- The guard's first-visit tab count: unknown in the world, so a simulated first visit is never
  -- held by the real account's purchased tabs.
  { "NumPurchasedBankTabs", function() return nil end },
  -- Reputation (both clients) and appearances (Retail only, C.FEATURE.appearances), rep-appearance
  -- spec §3.8: the world's factions and sources, never the player's.
  { "FactionSnapshot", factionSnapshot },
  { "ListFactions", listFactions },
}
if NS.Constants.FEATURE.appearances then
  PROVIDERS[#PROVIDERS + 1] = { "AppearanceSource", appearanceSource }
  PROVIDERS[#PROVIDERS + 1] = { "IsNewLook", isNewLook }
end

--- The provided keys, in registration order.
World.PROVIDED = {}

-- With no world (never, while a session is active, but cheap to be sure) the guarded or live
-- answer stands.
for _, p in ipairs(PROVIDERS) do
  local key, fn = p[1], p[2]
  World.PROVIDED[#World.PROVIDED + 1] = key
  NS.SimSeam:SetProvider(key, function(fallback, ...)
    local w = Host.world
    if not w then return fallback(...) end
    return fn(w, ...)
  end)
end
