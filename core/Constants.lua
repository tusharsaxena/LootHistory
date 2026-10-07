local _, NS = ...
NS.Constants = NS.Constants or {}
local C = NS.Constants

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

-- Attribution confidence.
C.Confidence = { CERTAIN = "CERTAIN", INFERRED = "INFERRED" }

-- Item class id for Quest-type items (Enum.ItemClass.Questitem). Locale-independent; the
-- collector's optional quest-item filter gates on this, never the localized itemType string.
C.ITEMCLASS_QUEST = 12

-- The itemType string used for currency records (they reuse the item Type/SubType columns). Real
-- items never carry this GetItemInfo type, so it doubles as a display label and a Type-filter value.
C.CURRENCY_TYPE = "Currency"

-- ── Ledger enums (timeline-ledger spec §3/§4.1) ──────────────────────────────────────────────
-- Stored strings, part of the export contract: never rename a member, only append.
C.Dir  = { IN = "IN", OUT = "OUT", MOVE = "MOVE" }
C.Kind = { ITEM = "ITEM", CURRENCY = "CURRENCY", GOLD = "GOLD" }
-- Where a holder keeps a thing. Values are the column keys inside db.global.holdings[h].items[id].
C.Container = {
  BAGS = "bags", EQUIPPED = "equipped", BANK = "bank",
  MAIL = "mail", AUCTIONS = "auctions", TABS = "tabs",
}
-- The virtual holder for the warband bank, warband gold and account-wide currencies. `§` marks a
-- system key (BagSync's convention): code that means "characters" skips keys starting with it.
C.WARBAND_HOLDER = "§warband"

-- Direction display (History column, Insights, Timeline). Cosmetic only — never stored. Colors are
-- BankLedger's (core/Constants.lua DirectionRGB) so a gain/loss reads the same in both addons.
C.DirOrder = { "IN", "OUT", "MOVE" }
C.DirLabel = { IN = "Gain", OUT = "Loss", MOVE = "Transfer" }
C.DirRGB = {
  IN   = { 0.35, 0.80, 0.45 },
  OUT  = { 1.00, 0.33, 0.33 },
  MOVE = { 0.62, 0.62, 0.66 },
}
-- TEXT glyphs: the default font has none of them and draws a box, so any FontString showing one
-- MUST use C.FONT_MONO (the LibKa0s JetBrains Mono face). U+25B2, U+25BC, U+21C4 as UTF-8 escapes.
C.DirGlyph = { IN = "\226\150\178", OUT = "\226\150\188", MOVE = "\226\135\132" }
-- Gold rows (kind GOLD): the Type value they carry, and the pale gold their quantity is drawn in.
C.GOLD_TYPE = "Gold"
C.GOLD_RGB = { 1.00, 0.86, 0.55 }
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

-- Retention presets; 0 means "Never" (cleanup disabled).
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
}

-- ── Container id groups (copied from BankLedger core/Constants.lua, which paid for the lesson) ──
-- Derived BY MEMBER NAME from Enum.BagIndex, never by number: Blizzard renumbers between builds,
-- and 12.0.7 also carries type constants (Characterbanktab = -2, Accountbanktab = -3) a loose
-- pattern would scoop up. Anchored, case-sensitive patterns only.
local GROUP_PATTERNS = {
  BAGS = { "^Backpack$", "^Bag_%d+$", "^ReagentBag$" },
  BANK = { "^Bank$", "^BankBag_%d+$", "^CharacterBankTab_%d+$" },
  TABS = { "^AccountBankTab_%d+$" },
}
local function idsMatching(patterns)
  local seen, ids = {}, {}
  local members = Enum and Enum.BagIndex
  if type(members) == "table" then
    for name, value in pairs(members) do
      if type(value) == "number" then
        for _, pattern in ipairs(patterns) do
          if name:match(pattern) and not seen[value] then seen[value] = true; ids[#ids + 1] = value; break end
        end
      end
    end
  end
  table.sort(ids)
  return ids
end
C.BAG_IDS         = idsMatching(GROUP_PATTERNS.BAGS)
C.BANK_IDS        = idsMatching(GROUP_PATTERNS.BANK)
C.WARBAND_TAB_IDS = idsMatching(GROUP_PATTERNS.TABS)
-- No numeric fallback when Enum.BagIndex is absent: the groups degrade to EMPTY (compat-layer
-- degrade-to-nothing), so a build without the enum scans no container rather than guessing ids
-- Blizzard has renumbered before. Holdings then simply has no bag column for that build.

C.EQUIP_SLOTS = {}
for s = (INVSLOT_FIRST_EQUIPPED or 1), (INVSLOT_LAST_EQUIPPED or 19) do C.EQUIP_SLOTS[#C.EQUIP_SLOTS + 1] = s end

local Bus = LibStub and LibStub("LibKa0s-Bus-1.0", true)
if not Bus then
  -- Degraded: the payload is missing. The names are still declared once and still used everywhere;
  -- what is lost is only the strictness, so a mistyped key reads nil instead of raising. `New` is
  -- not stubbed because nothing here calls it (tests/test_surface_parity.lua names it in `ignore`).
  Bus = { Catalog = function(_, messages) return messages end }
end
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

-- The Timeline's look (timeline-ledger spec §8.1). Total is the gold accent; the warband has its own
-- hue so it never reads as a class; gains/losses ARE the History Direction column's (C.DirRGB,
-- spec §7), so this block must stay below C.DirRGB in this file.
C.TIMELINE = {
  TOTAL   = { 1, 0.82, 0, 1 },
  WARBAND = { 0.25, 0.75, 0.95, 1 },
  OTHER   = { 0.7, 0.7, 0.72, 1 },
  MARKER  = { 0.8, 0.8, 0.8, 0.6 },
  GAIN    = C.DirRGB.IN,     -- Phase 2's direction colors: one definition
  LOSS    = C.DirRGB.OUT,
  TOTAL_W = 2.5,
  LINE_W  = 2,
  PX_PER_POINT = 6,    -- chart point spacing: fewer, longer segments read smoother
}
