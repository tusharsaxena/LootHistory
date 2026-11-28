local _, NS = ...
NS.Constants = NS.Constants or {}
local C = NS.Constants

-- ── The client's features (clients-§4, §5) ───────────────────────────────────────────────────
-- The Retail-only features (the WoW Forever port, Ka0sAddonsCommonTasks
-- docs/2026-11-22-LOOTHISTORY_BANKLEDGER_FOREVER_PORT/00_DESIGN.md, rulings R1 and R2), each declared
-- with the clients it serves and gated where it registers by C.FEATURE, its ForClient answer read once.
-- `mythicPlus` is the keystone: the MPLUS source (C.SOURCE_CLIENTS below), the keystone context and
-- its four events (modules/Attribution.lua), the Insights keystone breakdown (Database:Stats'
-- byKeystone, core/Database.lua) and the simulator's `key` scenario (modules/SimScenario.lua).
-- `warbandBank` is the warband bank's tabs and gold: the Reconciler's `tabs` and `warbandMoney`
-- parts and their two events (modules/Reconciler.lua), the tab ids (C.WARBAND_TAB_IDS below), the
-- char <-> warband pairing and its two reasons (C.SOURCE_CLIENTS below), the Holdings tab's Warband
-- split (modules/HoldingsTab.lua), the holdings tooltip's warband-bank mark, live count and wording
-- (modules/HoldingsTip.lua, modules/HoldingsTally.lua, core/Compat.lua LiveItemCounts,
-- settings/Schema.lua) and the simulator's warband steps (modules/SimScenario.lua). The
-- account holder itself (`§warband`) serves both clients: WoW Forever has account-wide currencies,
-- and the holder reads "Account" there (C.ACCOUNT below).
-- `appearances` is transmog collection as History rows (rep/appearance spec, D7): the two
-- TRANSMOG_COLLECTION_SOURCE_ADDED / _REMOVED event rows (modules/Appearance.lua), the Record
-- appearances switch row (settings/Schema.lua), test mode's appearance rows
-- (modules/BrowserTableTestData.lua) and the simulator's appearance step (modules/SimDrivers.lua,
-- modules/SimScenario.lua). WoW Forever exposes C_TransmogCollection, so the API's presence is not
-- the gate: the declaration is.
C.FEATURE_CLIENTS = {
  warbandBank = { "retail" },
  mythicPlus = { "retail" },
  appearances = { "retail" },
}
C.FEATURE = {}
for name, clients in pairs(C.FEATURE_CLIENTS) do C.FEATURE[name] = NS.Compat.ForClient(clients) end

-- The account's own words, one set per client picked once by ClientKey() (clients-§5; ruling R2):
-- Retail calls it the Warband, WoW Forever the Account (its tooltips read "Binds to Account",
-- ITEM_BIND_TO_ACCOUNT). Only what a player reads changes: the stored keys (the `§warband` holder,
-- the WARBAND / WARBAND_UE bound states) are the same on both. Both sets are published, as
-- C.ACCOUNT_WORDS, for the suites' golden snapshots, which were cut under Retail's.
C.ACCOUNT_WORDS = {
  retail = { holder = "Warband", bound = "Warbound", boundUE = "Warbound Until Equipped",
             boundUEShort = "Warbound (UE)" },
  forever = { holder = "Account", bound = "Account Bound", boundUE = "Account Bound Until Equipped",
              boundUEShort = "Account Bound (UE)" },
}
C.ACCOUNT = C.ACCOUNT_WORDS[NS.Compat.ClientKey() == "forever" and "forever" or "retail"]

-- The Wowhead item page each client's ids resolve on, picked once by ClientKey() (clients-§5;
-- ruling R7): WoW Forever's items live under /forever/, Retail's at the root. modules/Export.lua
-- builds the History CSV's wowheadLink on it. Both are published for the suites.
C.WOWHEAD_ITEM_BASES = {
  retail = "https://www.wowhead.com/item=",
  forever = "https://www.wowhead.com/forever/item=",
}
C.WOWHEAD_ITEM_BASE = C.WOWHEAD_ITEM_BASES[NS.Compat.ClientKey() == "forever" and "forever" or "retail"]

-- How a character key reads to a player, per client (the port's D6, core/Util.lua PlayerKey): Retail
-- keys a character "Name-Realm", WoW Forever by its two-word name and surname with no realm. The
-- History Character column's tooltip names it (modules/BrowserTable.lua).
C.CHARACTER_FORMS = { retail = "Name-Realm", forever = "name and surname" }
C.CHARACTER_FORM = C.CHARACTER_FORMS[NS.Compat.ClientKey() == "forever" and "forever" or "retail"]

-- Source enum. Values are the stored string keys (stable — do not RENAME; they are the export
-- contract). Extending it is fine (additive/forward-compatible): DISENCHANT/MILLING/PROSPECTING
-- are first-class deconstruct sources so the Source column reads the ability, not a generic "Craft".
C.SourceType = {
  KILL = "KILL", CONTAINER = "CONTAINER", MAIL = "MAIL", TRADE = "TRADE",
  AH = "AH", QUEST = "QUEST", VENDOR = "VENDOR", CRAFT = "CRAFT",
  ROLL = "ROLL", BONUS_ROLL = "BONUS_ROLL", MPLUS = "MPLUS", OTHER = "OTHER",
  DISENCHANT = "DISENCHANT", MILLING = "MILLING", PROSPECTING = "PROSPECTING",
  REFUND = "REFUND",
  -- Ledger reasons (timeline-ledger spec §4.1/§5.4), APPENDED in 2026-10: `source` now carries the
  -- reason for gains AND losses. Stored strings and export contract like every member above.
  SELL = "SELL", BUY = "BUY", REPAIR = "REPAIR", MAIL_SEND = "MAIL_SEND", TRADE_GIVE = "TRADE_GIVE",
  AH_POST_FEE = "AH_POST_FEE", AH_SOLD = "AH_SOLD", AH_BUY = "AH_BUY", DESTROY = "DESTROY",
  CONSUME = "CONSUME", CRAFT_REAGENT = "CRAFT_REAGENT", DECONSTRUCT = "DECONSTRUCT",
  GUILD_DEPOSIT = "GUILD_DEPOSIT", GUILD_WITHDRAW = "GUILD_WITHDRAW", TRAINING = "TRAINING",
  TRAVEL = "TRAVEL", TRANSFER = "TRANSFER", UNTRACKED = "UNTRACKED",
  -- Holder moves (timeline-ledger Phase 7, owner decision 2026-10-06), APPENDED: a move between two
  -- DIFFERENT holders is an OUT on the sender and an IN on the receiver, both under one of these.
  -- TRANSFER stays the reason of a move inside one holder (bags <-> bank, a post).
  WARBAND_DEPOSIT = "WARBAND_DEPOSIT", WARBAND_WITHDRAW = "WARBAND_WITHDRAW", ALT_MAIL = "ALT_MAIL",
  ALT_TRADE = "ALT_TRADE", CURRENCY_TRANSFER = "CURRENCY_TRANSFER",
  -- APPENDED 2026-11-27 (the owner: "This was caught by fishing, any way to capture that?"): a loot
  -- window the client marks as fishing loot (IsFishingLoot), on both clients.
  FISHING = "FISHING",
  -- APPENDED 2026-11-28 (farm mode #39, ruling F1): a GameObject loot window opened within
  -- GATHERING_TTL of a Herb Gathering or Mining cast (modules/Attribution.lua's noteGathering), on
  -- both clients. Herbs and ore read Gathering instead of Container, and farm mode counts the nodes.
  GATHERING = "GATHERING",
}

-- Display order for grouping/analytics (most to least "interesting").
C.SourceOrder = {
  "KILL", "CONTAINER", "MPLUS", "BONUS_ROLL", "ROLL", "QUEST",
  "TRADE", "MAIL", "AH", "VENDOR",
  "DISENCHANT", "MILLING", "PROSPECTING", "CRAFT", "REFUND", "OTHER",
  -- Ledger reasons, appended (append-only display order; the gain sources above keep their slots).
  "SELL", "BUY", "REPAIR", "MAIL_SEND", "TRADE_GIVE", "AH_POST_FEE", "AH_SOLD", "AH_BUY",
  "DESTROY", "CONSUME", "CRAFT_REAGENT", "DECONSTRUCT", "GUILD_DEPOSIT", "GUILD_WITHDRAW",
  "TRAINING", "TRAVEL", "TRANSFER", "UNTRACKED",
  "WARBAND_DEPOSIT", "WARBAND_WITHDRAW", "ALT_MAIL", "ALT_TRADE", "CURRENCY_TRANSFER",
  "FISHING", "GATHERING",
}

-- Short human labels for the UI.
C.SourceLabel = {
  KILL = "Kill", CONTAINER = "Container", MPLUS = "Mythic+", BONUS_ROLL = "Bonus Roll",
  ROLL = "Roll", QUEST = "Quest",
  TRADE = "Trade", MAIL = "Mail", AH = "Auction House", VENDOR = "Vendor", CRAFT = "Craft",
  DISENCHANT = "Disenchant", MILLING = "Milling", PROSPECTING = "Prospecting",
  REFUND = "Refund", OTHER = "Other",
  SELL = "Sell", BUY = "Buy", REPAIR = "Repair", MAIL_SEND = "Mail Sent", TRADE_GIVE = "Trade Given",
  AH_POST_FEE = "AH Deposit", AH_SOLD = "AH Sold", AH_BUY = "AH Bought", DESTROY = "Destroyed",
  CONSUME = "Consumed", CRAFT_REAGENT = "Crafting Reagent", DECONSTRUCT = "Deconstructed",
  GUILD_DEPOSIT = "Guild Deposit", GUILD_WITHDRAW = "Guild Withdraw", TRAINING = "Training",
  TRAVEL = "Travel", TRANSFER = "Transfer", UNTRACKED = "Untracked",
  WARBAND_DEPOSIT = "Warband Deposit", WARBAND_WITHDRAW = "Warband Withdraw", ALT_MAIL = "Alt Mail",
  ALT_TRADE = "Alt Trade", CURRENCY_TRANSFER = "Currency Transfer",
  FISHING = "Fishing", GATHERING = "Gathering",
}

-- Sources with a live capture path today — every enum member now has one, so all are offered in the
-- mute list. BONUS_ROLL / CRAFT / REFUND are attributed straight from their own self-identifying loot
-- lines ("bonus loot" / "You create" / "You are refunded"); ROLL is stamped from the roll-won line
-- ("You won:") just before the item's receive line; deconstruct abilities stamp their own source; AH
-- is stamped from Auction-House mail. The SourceType enum stays whole (export contract).
C.SOURCE_IMPLEMENTED = {
  KILL = true, CONTAINER = true, MPLUS = true, QUEST = true, VENDOR = true,
  MAIL = true, TRADE = true, AH = true, BONUS_ROLL = true, ROLL = true, OTHER = true,
  DISENCHANT = true, MILLING = true, PROSPECTING = true, CRAFT = true, REFUND = true,
  SELL = true, BUY = true, REPAIR = true, MAIL_SEND = true, TRADE_GIVE = true, AH_POST_FEE = true,
  AH_SOLD = true, AH_BUY = true, DESTROY = true, CONSUME = true, CRAFT_REAGENT = true,
  DECONSTRUCT = true, GUILD_DEPOSIT = true, GUILD_WITHDRAW = true, TRAINING = true, TRAVEL = true,
  TRANSFER = true, UNTRACKED = true,
  WARBAND_DEPOSIT = true, WARBAND_WITHDRAW = true, ALT_MAIL = true, ALT_TRADE = true, CURRENCY_TRANSFER = true,
  FISHING = true, GATHERING = true,
}

-- The reasons only the LEDGER writes (holdings diffs, timeline-ledger spec §5.4). They have live
-- paths (so SOURCE_IMPLEMENTED stays total) but they are NOT capture mutes: the mute list gates the
-- rich chat record (Collector), and no chat line carries one of these -- except ALT_TRADE, which an
-- own alt's trade stamps on the gain side too (Attribution:OnTradeAcceptUpdate), so a TRADE mute
-- does not silence a trade between two own characters.
C.LEDGER_REASON = {
  SELL = true, BUY = true, REPAIR = true, MAIL_SEND = true, TRADE_GIVE = true, AH_POST_FEE = true,
  AH_SOLD = true, AH_BUY = true, DESTROY = true, CONSUME = true, CRAFT_REAGENT = true,
  DECONSTRUCT = true, GUILD_DEPOSIT = true, GUILD_WITHDRAW = true, TRAINING = true, TRAVEL = true,
  TRANSFER = true, UNTRACKED = true,
  WARBAND_DEPOSIT = true, WARBAND_WITHDRAW = true, ALT_MAIL = true, ALT_TRADE = true, CURRENCY_TRANSFER = true,
}

-- The sources one client lacks (clients-§4), each declared with the clients it serves. A source
-- ForClient refuses is ABSENT on this client: it is kept out of SourceOrder, SOURCE_IMPLEMENTED and
-- LEDGER_REASON, so no filter, mute list or sample offers it, and C.SOURCE_ABSENT names it.
-- SourceType and SourceLabel stay whole: they are the export contract, and a stored row keeps its
-- key and a label (a client may word one its own way, C.SOURCE_LABEL_WORDS below). The two warband directions are the warband bank's (C.FEATURE.warbandBank), MPLUS
-- the keystone's (C.FEATURE.mythicPlus). The rest are content WoW Forever does not have (ruling R2):
-- no bonus-roll coins and no Milling or Prospecting. Disenchant, which it has, stays a source (its
-- seed is modules/Attribution.lua's, per client), and the DECONSTRUCT reason serves both clients
-- (owner ruling F1): on WoW Forever it is a disenchanted item's loss alone, worded below.
local RETAIL = { "retail" }
C.SOURCE_CLIENTS = {
  WARBAND_DEPOSIT = C.FEATURE_CLIENTS.warbandBank, WARBAND_WITHDRAW = C.FEATURE_CLIENTS.warbandBank,
  MPLUS = C.FEATURE_CLIENTS.mythicPlus,
  BONUS_ROLL = RETAIL, MILLING = RETAIL, PROSPECTING = RETAIL,
}
-- The labels one client words its own way, picked once by ClientKey() (clients-§5; owner ruling
-- F1): WoW Forever's only deconstruct is Disenchant (spell 13262), so its DECONSTRUCT loss reads
-- "Disenchanted". Only the label moves: the stored key is DECONSTRUCT on both clients. A label is
-- also Group by Source's key and the Source filter's only text, so it never repeats another key's:
-- "Disenchant" is the DISENCHANT gain source's (the materials), "Disenchanted" the item's loss.
C.SOURCE_LABEL_WORDS = { forever = { DECONSTRUCT = "Disenchanted" } }
for s, label in pairs(C.SOURCE_LABEL_WORDS[NS.Compat.ClientKey()] or {}) do C.SourceLabel[s] = label end
C.SOURCE_ABSENT = {}
for s, clients in pairs(C.SOURCE_CLIENTS) do
  if not NS.Compat.ForClient(clients) then C.SOURCE_ABSENT[s] = true end
end
do
  local order = {}
  for _, s in ipairs(C.SourceOrder) do if not C.SOURCE_ABSENT[s] then order[#order + 1] = s end end
  C.SourceOrder = order
  for s in pairs(C.SOURCE_ABSENT) do C.SOURCE_IMPLEMENTED[s], C.LEDGER_REASON[s] = nil, nil end
end

-- Attribution confidence.
C.Confidence = { CERTAIN = "CERTAIN", INFERRED = "INFERRED" }

-- Item class id for Quest-type items (Enum.ItemClass.Questitem). Locale-independent; the
-- collector's optional quest-item filter gates on this, never the localized itemType string.
C.ITEMCLASS_QUEST = 12

-- The itemType string used for currency records (they reuse the item Type/SubType columns). Real
-- items never carry this GetItemInfo type, so it doubles as a display label and a Type-filter value.
C.CURRENCY_TYPE = "Currency"
-- The same for reputation and appearance rows (rep/appearance spec §2.3): their Type column and
-- Type-filter value. No GetItemInfo type is spelled either way.
C.REPUTATION_TYPE = "Reputation"
C.APPEARANCE_TYPE = "Appearance"
-- Reputation capture's timings, in seconds: consecutive same-direction changes of one faction from
-- one source inside REP_COALESCE grow the last row (the Reconciler's coalescing span), and a
-- baseline seed put off by combat retries after REP_SEED_RETRY.
C.REP_COALESCE = 60
C.REP_SEED_RETRY = 5

-- ── Ledger enums (timeline-ledger spec §3/§4.1) ──────────────────────────────────────────────
-- Stored strings, part of the export contract: never rename a member, only append.
C.Dir  = { IN = "IN", OUT = "OUT", MOVE = "MOVE" }
C.Kind = { ITEM = "ITEM", CURRENCY = "CURRENCY", GOLD = "GOLD", REPUTATION = "REPUTATION", APPEARANCE = "APPEARANCE" }
-- Where a holder keeps a thing. Values are the column keys inside db.global.holdings[h].items[id].
C.Container = {
  BAGS = "bags", EQUIPPED = "equipped", BANK = "bank",
  MAIL = "mail", AUCTIONS = "auctions", TABS = "tabs",
}
-- The virtual holder for the warband bank, warband gold and account-wide currencies. `§` marks a
-- system key (BagSync's convention): code that means "characters" skips keys starting with it.
-- On WoW Forever, which has no warband bank, it holds the account-wide currencies alone and reads
-- "Account" (C.ACCOUNT.holder).
C.WARBAND_HOLDER = "§warband"

-- ── The gain feed (#38, toast spec §4) ───────────────────────────────────────────────────────
-- What a GAIN payload's `kind` says. The first five equal the C.Kind strings; XP and SKILL are never
-- record kinds (D8), so they are not in C.Kind.
C.GainKind = { ITEM = "ITEM", GOLD = "GOLD", CURRENCY = "CURRENCY", REPUTATION = "REPUTATION",
               APPEARANCE = "APPEARANCE", XP = "XP", SKILL = "SKILL" }
-- The three fixed toast feeds (T15), in settings order, and the settings leaf of each kind toggle
-- (settings.toasts.feeds[fid].kinds[leaf]) mapped to its GainKind.
C.TOAST_FEEDS = { "main", "progress", "extra" }
C.TOAST_KIND_KEYS = { item = "ITEM", money = "GOLD", currency = "CURRENCY", reputation = "REPUTATION",
                      appearance = "APPEARANCE", xp = "XP", skill = "SKILL" }
-- The vanilla profession skill lines (WoW Forever's skill-up allowlist, T14): First Aid 129,
-- Blacksmithing 164, Leatherworking 165, Alchemy 171, Herbalism 182, Cooking 185, Mining 186,
-- Tailoring 197, Engineering 202, Enchanting 333, Fishing 356, Skinning 393. A small static fixture,
-- not tools/seeds data; /lh debug probe lists the client's skill lines against it (FOREVER-T3).
C.PROFESSION_SKILL_LINES = { [129] = 1, [164] = 1, [165] = 1, [171] = 1, [182] = 1, [185] = 1, [186] = 1,
                             [197] = 1, [202] = 1, [333] = 1, [356] = 1, [393] = 1 }

-- The toast feeds' host constants (#38, toast spec §4.3, §8). The schema loads before any feed exists
-- and must load without LibKa0s-Feed-1.0, so it reads these, never the major; tests/test_toast_model.lua
-- pins SLOTS, NUDGE_MAX and SHOWN_MAX equal to NS.FeedLib's.
C.TOAST_FEED_LABEL = { main = "Main feed", progress = "Progress feed", extra = "Third feed" }
C.TOAST_SLOTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
C.TOAST_NUDGE_MAX = 600     -- = LibKa0s-Feed-1.0 NUDGE_MAX; the nudge sliders' range, either way
C.TOAST_SHOWN_MAX = 10      -- = Feed SHOWN_MAX; the "Shown at once" slider's top
C.TOAST_COUNT_SETTLE = 0.5  -- motion.settle: one more content call this long after the paint (client-quirks-§3)
C.TOAST_SOUND_GAP = 1       -- s: at most one highlight sound per feed in this long (toast spec §8.3)
-- The kind colors' owner tokens (toast spec §8.4), keyed by the feed's `colors.<key>` leaf. The
-- names carry this owner's namespace, `lh.`, never a library token family (LibKa0s-Skin-1.0's owner
-- token rule). Their Ka0s Default values are registered in core/SkinSetup.lua.
C.TOAST_TOKENS = { xp = "lh.toast.xp", rep = "lh.toast.rep", skill = "lh.toast.skill" }
-- The upgrade rule's slots (toast spec §7.4, T13): an equip location's inventory slots. A two-slot
-- location compares against the lower equipped item level. The ranged locations sit in slot 18 on
-- WoW Forever (its ranged slot) and in the main hand on Retail, which has no slot 18 item.
C.EQUIP_LOC_SLOTS = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 } }
do
  local ranged = NS.Compat.ClientKey() == "forever" and 18 or 16
  C.EQUIP_LOC_SLOTS.INVTYPE_RANGED, C.EQUIP_LOC_SLOTS.INVTYPE_RANGEDRIGHT = { ranged }, { ranged }
end
-- The armor subclass each class wears on Retail (1 cloth, 2 leather, 3 mail, 4 plate), the upgrade
-- rule's armor gate. WoW Forever classes change armor type at level 40, so there the equipped
-- piece's subclass is the reference instead (T13).
C.CLASS_ARMOR = { WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4, HUNTER = 3, SHAMAN = 3, EVOKER = 3, ROGUE = 2,
                  DRUID = 2, MONK = 2, DEMONHUNTER = 2, PRIEST = 1, MAGE = 1, WARLOCK = 1 }
-- The icon of a kind that has no item or currency icon of its own (game art, toast spec §7.4).
C.TOAST_KIND_ICON = {
  GOLD       = "Interface\\Icons\\INV_Misc_Coin_01",
  REPUTATION = "Interface\\Icons\\Achievement_Reputation_01",
  APPEARANCE = "Interface\\Icons\\INV_Chest_Cloth_17",
  XP         = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
  SKILL      = "Interface\\Icons\\INV_Misc_Book_09",
}
C.TOAST_ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
-- The Toasts page's value lists (toast spec §9.3), each the array form { { value, text } } in the
-- order the dropdown draws. Stored values are the Feed's own words (slots, sides, enter) or this
-- addon's (grow, price, background type); no getter maps them but grow (M.LayoutFor).
C.TOAST_SLOT_LABEL = { TOPLEFT = "Top left", TOP = "Top center", TOPRIGHT = "Top right", LEFT = "Middle left",
  CENTER = "Center", RIGHT = "Middle right", BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom center",
  BOTTOMRIGHT = "Bottom right" }
C.TOAST_SLOT_OPTIONS = {}
for _, slot in ipairs(C.TOAST_SLOTS) do
  C.TOAST_SLOT_OPTIONS[#C.TOAST_SLOT_OPTIONS + 1] = { value = slot, text = C.TOAST_SLOT_LABEL[slot] }
end
-- The growth direction a slot pick sets (a top slot grows down, every other one up).
C.TOAST_SLOT_GROW = { TOPLEFT = "down", TOP = "down", TOPRIGHT = "down", LEFT = "up", CENTER = "up",
  RIGHT = "up", BOTTOMLEFT = "up", BOTTOM = "up", BOTTOMRIGHT = "up" }
C.TOAST_GROW_OPTIONS = { { value = "up", text = "Up" }, { value = "down", text = "Down" } }
C.TOAST_SIDE_OPTIONS = { { value = "left", text = "Left" }, { value = "right", text = "Right" } }
C.TOAST_PRICE_OPTIONS = { { value = "none", text = "None" }, { value = "vendor", text = "Vendor" },
  { value = "ah", text = "AH" }, { value = "both", text = "Vendor and AH" }, { value = "highest", text = "Highest" } }
-- The Feed's enter vocabulary (LibKa0s-Feed-1.0 motion.enter), in the order the dropdown draws.
C.TOAST_ENTER_OPTIONS = { { value = "none", text = "None" }, { value = "fade", text = "Fade" },
  { value = "right", text = "Slide from the right" }, { value = "left", text = "Slide from the left" },
  { value = "up", text = "Slide up" }, { value = "down", text = "Slide down" } }
C.TOAST_BG_TYPE_OPTIONS = { { value = "none", text = "None" }, { value = "solid", text = "Solid" },
  { value = "gradient", text = "Gradient" }, { value = "texture", text = "Texture" } }
-- The Blizzard alert events toast hiding unregisters from AlertFrame (toast spec §10.2). Each is
-- registered in AlertFrameMixin:OnLoad on both clients (docs/ARCHITECTURE.md Taint notes cites the
-- lines); one AlertFrame has not registered is skipped by Compat.SuppressAlertEvents. SHOW_LOOT_TOAST
-- carries the money alert too (its typeIdentifier "money").
C.BLIZZ_ALERT_EVENTS = { "SHOW_LOOT_TOAST", "SHOW_LOOT_TOAST_UPGRADE", "SHOW_LOOT_TOAST_LEGENDARY_LOOTED" }

-- ── Farm mode (#39, farm spec docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §4.4) ──
-- The session engine's constants (modules/FarmModel.lua pure, modules/Farm.lua runtime). Seconds
-- unless named otherwise. STALE_SEC (F5): an open session last seen longer ago than this is finished
-- as stale on load. INTENT_TTL: how long a logout intent stamp holds (the 20 s logout countdown, with
-- room). LOG_CAP/LOG_BATCH: the packed log keeps LOG_CAP lines, trimmed in LOG_BATCH steps while open.
-- MOB_RING: the corpse GUIDs remembered across a reload. MIN_RATE_SEC: no per-hour rate below it.
C.FARM = {
  STALE_SEC = 1800, INTENT_TTL = 30, IDLE_TICK = 30,
  LOG_CAP = 2000, LOG_BATCH = 100, MOB_RING = 256, MIN_RATE_SEC = 60,
  PRICE_DELAY = 1, PRICE_BATCH = 20,
  -- The OUT gold reasons a session counts as its costs (D19, §5.6).
  COST_REASONS = { REPAIR = true, BUY = true, AH_POST_FEE = true },
  -- The item, money and currency gain sources a session counts (F4, §5.5). OTHER counts only from a
  -- chat line (FarmModel.ApplyGain); every ledger reason, vendor, mail, AH and trade never does.
  GAIN_SOURCES = { KILL = true, CONTAINER = true, MPLUS = true, GATHERING = true, FISHING = true,
                   QUEST = true, BONUS_ROLL = true, ROLL = true, OTHER = true },
  EPIC_FLOOR = 4,               -- the panel's "Epic+ drops" line
  -- The set Farm hands GainFeed:SetFarm while a session is live (§2): every C.GainKind. One table,
  -- never mutated; Recompute masks APPEARANCE by C.FEATURE.appearances itself.
  GAIN_KINDS = { ITEM = true, GOLD = true, CURRENCY = true, REPUTATION = true, APPEARANCE = true,
                 XP = true, SKILL = true },
}

-- The holdings tally's cache bound (#34, modules/HoldingsTally.lua): past this many cached things,
-- items and currencies together, both maps are wiped before the next insert, so a long AH browse
-- keeps memory bounded.
C.TIP_CACHE_MAX = 128

-- The public API's version (#34, modules/HoldingsAPI.lua; public-api): `LootHistory.API.v1.Version()`
-- answers it, always. Semver-stable; a break ships as `v2` beside `v1`.
C.API_VERSION = 1

-- The holdings tooltip's container marks (#34, D4: containers are icons and a count, never words).
-- Game-icons (CC BY 3.0) from the LibKa0s catalog, each declared on CLAUDE.md's `LibKa0s icons:` line
-- and vendored under libs/LibKa0s/media/icons/game-icons/. `tabs` is drawn only where
-- C.FEATURE.warbandBank (modules/HoldingsTip.lua ORDER). White art, tinted from gtip tokens at draw.
C.TIP_ICONS = {
  [C.Container.BAGS] = "gi:knapsack", [C.Container.EQUIPPED] = "gi:chest-armor",
  [C.Container.BANK] = "gi:bank", [C.Container.MAIL] = "gi:envelope",
  [C.Container.AUCTIONS] = "gi:gavel", [C.Container.TABS] = "gi:locked-chest",
}
-- Drawn when the catalog answers nil (library-stack-§8); present on both clients.
C.TIP_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
C.TIP_ICON_SIZE = 12

-- settings.tooltip.modifier: the key the block waits for ("none" = always). The ordered-array shape
-- the dropdown rows read (`text`, not `label`).
C.TOOLTIP_MODIFIER_OPTIONS = {
  { value = "none",  text = "None" },
  { value = "shift", text = "Shift" },
  { value = "ctrl",  text = "Ctrl" },
  { value = "alt",   text = "Alt" },
}

-- Direction display (History column, Insights, Timeline). Cosmetic only — never stored. The colors
-- are the skin's sem.good / sem.bad / sem.neutral (LH-04, modules/LedgerFormat.lua), whose Ka0s
-- Default values are BankLedger's (core/Constants.lua DirectionRGB: .35,.80,.45 / 1,.33,.33 /
-- .62,.62,.66), so a gain/loss reads the same in both addons.
C.DirOrder = { "IN", "OUT", "MOVE" }
C.DirLabel = { IN = "Gain", OUT = "Loss", MOVE = "Transfer" }
-- TEXT glyphs: most skin faces have none of them and draw a box, so any FontString showing one
-- MUST use C.FONT_MONO (the LibKa0s JetBrains Mono face). U+25B2, U+25BC, U+2194 as UTF-8 escapes.
-- MOVE was U+21C4 until the skin fonts and feedback run (ruling D-19): no shipped face draws it,
-- JetBrains Mono included, so every Transfer row drew a box; U+2194 is in JetBrains Mono.
C.DirGlyph = { IN = "\226\150\178", OUT = "\226\150\188", MOVE = "\226\134\148" } -- glyph: mono
-- Gold rows (kind GOLD): the Type value they carry. Their quantity is drawn in the skin's sem.gold,
-- a pale gold (1, .86, .55) on Ka0s Default.
C.GOLD_TYPE = "Gold"
-- Seconds a tradeskill craft keeps reagent losses attributed to CRAFT_REAGENT (a cast is 1-3 s; a
-- queued "craft all" re-arms it per CraftRecipe call).
C.CRAFT_TTL = 6

-- The monospace face used by the debug console and the export copy box. WoW ships no monospace
-- font object, so one has to come from somewhere; as of LibKa0s v1.10 it comes from the LIBRARY
-- payload rather than from this addon's own media/, which is why media/fonts/ is gone and the
-- ratified per-addon exception that used to be defended here is retired. core/MediaSetup.lua
-- publishes the seam and MUST load before this file (its TOC line says so).
--
-- THE FALLBACK IS A REAL CLIENT FONT, deliberately. SetFont accepts a path to a file that is not
-- there, fails to load it, and the text simply does not draw -- so a degraded install falls back
-- to STANDARD_TEXT_FONT (proportional, but present) rather than to a dead path.
C.FONT_MONO_NAME = "JetBrains Mono"
C.FONT_MONO = NS.MediaFont and NS.MediaFont(C.FONT_MONO_NAME) or _G.STANDARD_TEXT_FONT

-- Seconds a stamped loot context stays fresh before CHAT_MSG_LOOT falls back to OTHER.
C.CONTEXT_TTL = 1.5
-- A loot window outlives that stamp: its lines can land seconds after it opened (the WoW Forever probe
-- of 2026-11-23 read two). It covers one line per slot while it is open, for LOOT_LINE_GRACE seconds
-- after it closes (autoloot closes first), and never longer than LOOT_WINDOW_MAX.
C.LOOT_LINE_GRACE = 5
-- Seconds a Fishing cast keeps the next loot window a catch (modules/Attribution.lua's noteFishing): the
-- channel's 21 s and the click on the bobber, with room.
C.FISHING_TTL = 30
C.LOOT_WINDOW_MAX = 120
-- Seconds a Herb Gathering or Mining cast keeps the next GameObject loot window a node (farm spec F1,
-- modules/Attribution.lua's noteGathering): the cast completes as the window opens, so a short one.
C.GATHERING_TTL = 5
-- A container opened from the bags delivers in waves with no window (a clam's meat after its pearl).
C.CONTAINER_TTL = 4

-- Seconds a WON encounter's context outlives ENCOUNTER_END. The boss corpse is looted after
-- ENCOUNTER_END fires, so clearing the context there would strip encounterID / difficulty from
-- every piece of boss loot. Trash KILL loot inside the same window also carries the id; that is
-- accepted. A wipe clears the context outright (modules/Attribution.lua OnEncounterEnd).
C.ENCOUNTER_GRACE = 60

-- ── Schema enum option tables ────────────────────────────────────────────────────────────────
-- The four `*_OPTIONS` tables below are the ordered-array enum shape BOTH LibKa0s majors read off a
-- schema row's `values`: an array of { value =, text = }, where POSITION is the display order.
-- `text` rather than `label` is load-bearing — `LibKa0s-Slash-1.0`'s parser and
-- `LibKa0s-Options-1.0`'s dropdown maker both fall back to `tostring(item.value)` when `text` is
-- absent, so a row named the old way renders every entry as its raw stored value with nothing to
-- say it went wrong.

-- Minimum-quality options for the collector threshold (WoW item-quality ids). The gate is a
-- monotonic "quality >= threshold" (Collector:gateReason). The ladder runs Poor(0)..Legendary(5),
-- then Heirloom(7) appended by explicit user choice. NOTE Heirloom's id (7) sits ABOVE Legendary,
-- so selecting it floors capture at 7 — i.e. only Heirlooms/Tokens, gating out Epics/Legendaries.
-- This is intentional, not a bug: leave it (ratified exception, see docs/common-tasks.md).
-- Artifact(6)/Token(8) stay omitted. Only the quality name is quality-colored (the History
-- Browser's ITEM_QUALITY_COLORS tint); " and above" stays default.
-- rrggbb fallback for headless builds where ITEM_QUALITY_COLORS is absent (color is cosmetic there).
local QUALITY_HEX_FALLBACK = {
  [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee",
  [5] = "ff8000", [7] = "e6cc80",
}
local function qualityHex(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c and c.hex then return c.hex:sub(-6) end
  return QUALITY_HEX_FALLBACK[q]
end
C.QUALITY_OPTIONS = {}
for _, q in ipairs({ 0, 1, 2, 3, 4, 5, 7 }) do
  C.QUALITY_OPTIONS[#C.QUALITY_OPTIONS + 1] = {
    value = q,
    text = ("|cff%s%s|r and above"):format(qualityHex(q), NS.Item.QualityLabel(q)),
  }
end

-- Retention presets; 0 is "Always" (keep everything: cleanup disabled).
C.RETENTION_OPTIONS = {
  { value = 7,   text = "7 days" },
  { value = 14,  text = "14 days" },
  { value = 30,  text = "30 days" },
  { value = 60,  text = "60 days" },
  { value = 90,  text = "90 days" },
  { value = 180, text = "180 days" },
  { value = 365, text = "365 days" },
  { value = 0,   text = "Always" },
}

-- How long the Timeline's daily rollup is kept (settings.rollupRetentionDays). Longer floors than the
-- raw history's: the rollup is the long-term record, one small cell per changed thing per day.
C.ROLLUP_RETENTION_OPTIONS = {
  { value = 90,  text = "90 days" },
  { value = 180, text = "180 days" },
  { value = 365, text = "1 year" },
  { value = 730, text = "2 years" },
  { value = 0,   text = "Always" },
}

-- Per-source mute options, derived from the source order. Only sources with a live capture path
-- (SOURCE_IMPLEMENTED) are offered — an unreachable bucket would be a dead checkbox in the panel.
C.SOURCE_OPTIONS = {}
for _, s in ipairs(C.SourceOrder) do
  if C.SOURCE_IMPLEMENTED[s] and not C.LEDGER_REASON[s] then
    C.SOURCE_OPTIONS[#C.SOURCE_OPTIONS + 1] = { value = s, text = C.SourceLabel[s] }
  end
end

-- Human-readable provider names, keyed by AUCTION_KEYS' provider id.
C.AUCTION_PROVIDER_NAMES = { auctionator = "Auctionator", tsm = "Tradeskill Master", oribos = "Oribos Exchange" }

-- Every AH price data point the addon can capture. tag = provider..":"..key. Drives the capture
-- menu, GatherAll's fetch loop, the CSV sub-columns, and the priority defaults. `data` is a short
-- column/label form; `desc` is the settings-panel tooltip explaining what the number means.
C.AUCTION_KEYS = {
  { provider="auctionator", key="minbuyout",            label="Auctionator \226\128\148 Min buyout",        data="Min Buyout",            desc="The lowest current buyout on your realm's auction house, from Auctionator's last scan." },
  { provider="tsm",         key="dbmarket",             label="TSM \226\128\148 Market value",               data="Market Value",          desc="TSM's smoothed market value for your realm (roughly a 14-day average) \226\128\148 its best 'what's it worth' number." },
  { provider="tsm",         key="dbminbuyout",          label="TSM \226\128\148 Min buyout",                 data="Min Buyout",            desc="The lowest buyout on your realm from TSM's most recent scan." },
  { provider="tsm",         key="dbregionmarketavg",    label="TSM \226\128\148 Region market avg",          data="Region Market Avg",     desc="Average market value across your whole region (from the TSM Desktop App) \226\128\148 wide coverage even for items you never scanned." },
  { provider="tsm",         key="dbregionminbuyoutavg", label="TSM \226\128\148 Region min-buyout avg",      data="Region Min-Buyout Avg", desc="Average of the lowest buyouts across your region." },
  { provider="tsm",         key="dbhistorical",         label="TSM \226\128\148 Historical",                 data="Historical",            desc="TSM's long-term historical average for your realm (roughly 60\226\128\14890 days)." },
  { provider="tsm",         key="dbrecent",             label="TSM \226\128\148 Recent",                     data="Recent",                desc="The value from TSM's most recent realm scan (more volatile than market value)." },
  { provider="tsm",         key="dbregionhistorical",   label="TSM \226\128\148 Region historical",          data="Region Historical",     desc="TSM's long-term historical average across your region." },
  { provider="tsm",         key="dbregionsaleavg",      label="TSM \226\128\148 Region sale avg",            data="Region Sale Avg",       desc="The average price items actually SOLD for across your region (realized sales, not listings)." },
  { provider="oribos",      key="market",               label="OribosExchange \226\128\148 Market",         data="Market",                desc="OribosExchange's realm market value, from its imported region/realm dataset." },
  { provider="oribos",      key="region",               label="OribosExchange \226\128\148 Region",         data="Region",                desc="OribosExchange's region-wide market value." },
}
-- Capture checklist options for the settings panel MultiCheck row (value = "provider:key" tag).
C.AUCTION_CAPTURE_OPTIONS = {}
for i, k in ipairs(C.AUCTION_KEYS) do
  C.AUCTION_CAPTURE_OPTIONS[i] = { value = k.provider .. ":" .. k.key, text = k.label }
end
-- Curated defaults (which keys are captured, and the selection priority order).
C.AUCTION_CAPTURE_DEFAULT = {
  ["auctionator:minbuyout"] = true, ["tsm:dbmarket"] = true, ["tsm:dbminbuyout"] = true,
  ["tsm:dbregionmarketavg"] = true, ["tsm:dbregionminbuyoutavg"] = true,
  ["oribos:market"] = true, ["oribos:region"] = true,
}
C.AUCTION_PRIORITY_DEFAULT = {
  -- default-collected (in AUCTION_CAPTURE_DEFAULT) first
  "tsm:dbmarket", "auctionator:minbuyout", "oribos:market",
  "tsm:dbminbuyout", "tsm:dbregionmarketavg", "tsm:dbregionminbuyoutavg", "oribos:region",
  -- default-uncollected last
  "tsm:dbhistorical", "tsm:dbrecent", "tsm:dbregionhistorical", "tsm:dbregionsaleavg",
}

-- Convenience aliases.
NS.SourceType = C.SourceType
NS.Confidence = C.Confidence

-- How long the RecordAdded repaint waits before running (issue #27).
--
-- Short enough that the window is never visibly stale — a fifth of a second is below the
-- threshold at which a list that repaints after a loot line reads as laggy — and long enough that
-- every drop of a multi-item boss kill lands inside one window. The work being collapsed is
-- roughly nine full-history passes, so the saving on a big history is the whole point; the cost is
-- that the browser can be up to this far behind the data and never further.
NS.Constants.RECORD_ADDED_COALESCE = 0.2

-- ── The bus message names (architecture-§4) ────────────────────────────────────────────────────
--
-- Every `Ka0s_LootHistory_*` name is declared HERE, once, and every SendMessage / RegisterMessage
-- in the addon names the constant, never the literal. A misspelled literal is an error nowhere: a
-- sender that types one sends a message nobody receives, a receiver that types one waits for a
-- message nobody sends, and nothing goes red. This addon has no core/Bus.lua, so the table lives
-- here, which is where architecture-§4 puts it for that case.
--
-- STRICT on the live path. LibKa0s-Bus-1.0's `Catalog` checks the names once at load (the
-- `Ka0s_<Addon>_` prefix, a PascalCase `<Event>`, no two keys on one wire name) and answers a copy
-- whose read of an undeclared key RAISES, so `NS.MSG.RECORD_ADDDED` fails at the call site for a
-- sender as well as a receiver. Only `Catalog` is used: this addon's receivers are untracked on
-- purpose (`NS.NewBusTarget`, core/LootHistory.lua), so it builds no stand-down record and never
-- calls the major's `New`.
--
-- The wire strings are the contract every receiver depends on and they did not change when the
-- constants arrived; tests/test_constants.lua pins each one by driving its real sender.
local MSG = {
  -- Sender: core/Database.lua `Database:Add` and `Database:Amend`. Payload: (record, index) — a row
  -- was added OR grew in place (60 s coalescing). Receivers repaint; none may count it as one more.
  RECORD_ADDED     = "Ka0s_LootHistory_RecordAdded",
  -- Sender: core/Database.lua (Delete, PruneOld, Purge, FireHistoryChanged, RepairBoundStates).
  -- Payload: none.
  HISTORY_CHANGED  = "Ka0s_LootHistory_HistoryChanged",
  -- Sender: settings/Schema.lua, the rows' onChange handlers. Payload: the reason string.
  SETTINGS_CHANGED = "Ka0s_LootHistory_SettingsChanged",
  -- Sender: modules/Reconciler.lua `Flush`. Payload: (holder) — once per holder whose holdings moved.
  HOLDINGS_CHANGED = "Ka0s_LootHistory_HoldingsChanged",
  -- Sender: modules/GainFeed.lua `GainFeed:Send`, ONLY. Payload: (gain) -- a reused scratch table, valid
  -- only during the synchronous send; a receiver copies what it keeps. Fired for every gain the addon
  -- observes, BEFORE the capture filters (#38 D6). Receivers: NS.Toasts (#38), NS.Farm (#39).
  GAIN             = "Ka0s_LootHistory_Gain",
}

-- ── Container id groups (LibKa0s-Compat-1.0 minor 6, LibKa0s#101; K101-LH-02) ──────────────────
-- NS.Compat.ContainerGroups() (core/CompatClient.lua) is the collection's one copy, shared with
-- BankLedger and OutfitterReborn. It derives the ids BY MEMBER NAME from Enum.BagIndex, never by
-- number (Blizzard renumbers between builds, and 12.0.7 also carries the type constants
-- Characterbanktab = -2 and Accountbanktab = -3), through anchored, case-sensitive patterns, one row
-- per client picked by ClientKey() (clients-§5). The rows differ in two places: the Keyring (-1) is a
-- bag on WoW Forever only (ruling R5; Retail's -1 was the legacy bank container before 11.2), and the
-- account bank is declared on Retail only (R1). The pattern rows are published as
-- NS.Compat.CONTAINER_PATTERNS_BY_CLIENT for the suites. Read once, at file load.
-- With no Enum.BagIndex the library answers its documented fallback: the bags 0..5 (the backpack, the
-- four bags and the reagent bag), and no bank or account bank.
local GROUPS = NS.Compat.ContainerGroups()
C.BAG_IDS         = GROUPS.bags
C.BANK_IDS        = GROUPS.bank
-- The warband tabs only where the warband bank is a feature (C.FEATURE.warbandBank): on WoW Forever
-- the client numbers AccountBankTab_1..9 (15..23) but the bank is not there, and the library's
-- Forever row declares none either.
C.WARBAND_TAB_IDS = C.FEATURE.warbandBank and GROUPS.accountBank or {}

C.EQUIP_SLOTS = {}
for s = (INVSLOT_FIRST_EQUIPPED or 1), (INVSLOT_LAST_EQUIPPED or 19) do C.EQUIP_SLOTS[#C.EQUIP_SLOTS + 1] = s end

local Bus = LibStub and LibStub("LibKa0s-Bus-1.0", true)
if not Bus then
  -- Degraded: the payload is missing. The names are still declared once and still used everywhere;
  -- what is lost is only the strictness, so a mistyped key reads nil instead of raising. `New` is
  -- not stubbed because nothing here calls it (tests/test_surface_parity.lua names it in `ignore`).
  Bus = { Catalog = function(_, messages) return messages end }
end
-- NS.BusLib has no shipped reader, on purpose: it is how tests/test_surface_parity.lua reaches the
-- degraded stub above to hold it against LibKa0s-Bus-1.0. Removing it blinds that parity case.
NS.BusLib = Bus
NS.MSG = Bus.Catalog((...), MSG)

-- CURRENCY_DISPLAY_UPDATE's gainSource / destroyReason, mapped BY ENUM MEMBER NAME
-- (Enum.CurrencySource / Enum.CurrencyDestroyReason, reverse-looked-up in core/Compat.lua) to a
-- ledger reason. By name, never by number: the numbers are not documented as stable. A member not
-- listed maps to nil and the reason falls through to the context stamps. The names below are the
-- 12.x members as recalled; docs/smoke-tests.md LED-P2-14 verifies them in the client.
C.CURRENCY_SOURCE_REASON = {
  gain = {
    QuestReward = "QUEST", Vendor = "VENDOR", Trade = "TRADE", ItemRefund = "REFUND",
    GuildBankWithdrawal = "GUILD_WITHDRAW", AccountTransfer = "TRANSFER",
  },
  loss = {
    Vendor = "BUY", Trade = "TRADE_GIVE", FulfillCraftingOrder = "CRAFT_REAGENT",
    ConcentrationCast = "CRAFT_REAGENT", AccountTransfer = "TRANSFER", Spell = "CONSUME",
  },
}

-- The Timeline's geometry (timeline-ledger spec §8.1). Its colors are the skin's (LH-04,
-- modules/TimelineModel.lua): the Total chart.total (the gold accent), the warband sem.warband (its
-- own hue, so it never reads as a class), any other holder chart.otherLine, the ledgerSince marker
-- chart.marker, and gains and losses sem.good / sem.bad, the History Direction column's (spec §7).
C.TIMELINE = {
  TOTAL_W = 2.5,
  LINE_W  = 2,
  PX_PER_POINT = 6,    -- chart point spacing: fewer, longer segments read smoother
}

-- ── Frame layering (frame-layering-§5) ───────────────────────────────────────────────────────
-- The addon's ONE layers table: every SetFrameStrata in core/, modules/ and settings/ reads it, and
-- the keys are frame-layering-§1's tier keys, so "the window tier" is spelled as in every Ka0s addon.
--
-- The whole stack, bottom to top, the tiers this addon borrows included:
--   MEDIUM             LibDBIcon minimap button (the library's, fixed).
--   HIGH     WINDOW    the History window, toplevel and clamped; every pane, table, chart and strip
--                      in it inherits. Shares HIGH with Blizzard's Settings panel; both are
--                      toplevel, so the last one clicked is on top. Peer: the library's first-run
--                      skin picker (OptionsSkinPicker), HIGH and toplevel too, which the eye's
--                      History window would cover; core/SkinSetup.lua raises it after the eye.
--   HIGH               the toast feed containers (#38), LibKa0s-Feed-1.0's STRATA (T5, not toplevel,
--                      clamped, library-owned); the addon sets no strata or level on a toast frame.
--   DIALOG   MODAL     the Export modal, toplevel and clamped. Peers by the library's and Blizzard's
--                      choice: the debug console, perf panel and sim panel (toplevel from LibKa0s
--                      v1.77.0) and the StaticPopup confirmations.
--   FULLSCREEN         the library's CopyWindow (the export output), one strata over the modal that
--                      opens it. The addon sets no CHILD strata of its own.
--   FULLSCREEN_DIALOG POPUP  the History / Holdings row context menu, clamped, dismissed by
--                      GLOBAL_MOUSE_DOWN (no click catcher), closed with its window. Peers: the
--                      library's dropdown menu, the Search autocomplete and the IdList suggestions.
--   TOOLTIP            GameTooltip and the library's reorder drag ghost.
--
-- LEVEL is empty on purpose: the addon writes no frame level of its own. Every child takes the
-- client's parent + 1, and the library's bands are the only explicit ones in its map -- the resize
-- grip at window + 10, the reorder drop line at + 20 and the reorder box at - 1 -- so a window's
-- own content stays at or below + 8 (frame-layering-§3).
C.LAYERS = {
  STRATA = {
    WINDOW = "HIGH",
    MODAL  = "DIALOG",
    POPUP  = "FULLSCREEN_DIALOG",
  },
  LEVEL = {},
}
