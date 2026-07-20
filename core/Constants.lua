local addonName, NS = ...
NS.Constants = NS.Constants or {}
local C = NS.Constants

-- Source enum. Values are the stored string keys (stable — do not RENAME; they are the export
-- contract). Extending it is fine (additive/forward-compatible): DISENCHANT/MILLING/PROSPECTING
-- are first-class deconstruct sources so the Source column reads the ability, not a generic "Craft".
C.SourceType = {
  KILL = "KILL", CONTAINER = "CONTAINER", MAIL = "MAIL", TRADE = "TRADE",
  AH = "AH", QUEST = "QUEST", VENDOR = "VENDOR", CRAFT = "CRAFT",
  ROLL = "ROLL", MPLUS = "MPLUS", OTHER = "OTHER",
  DISENCHANT = "DISENCHANT", MILLING = "MILLING", PROSPECTING = "PROSPECTING",
}

-- Display order for grouping/analytics (most to least "interesting").
C.SourceOrder = {
  "KILL", "CONTAINER", "MPLUS", "ROLL", "QUEST",
  "TRADE", "MAIL", "AH", "VENDOR",
  "DISENCHANT", "MILLING", "PROSPECTING", "CRAFT", "OTHER",
}

-- Short human labels for the UI.
C.SourceLabel = {
  KILL = "Kill", CONTAINER = "Container", MPLUS = "Mythic+", ROLL = "Roll", QUEST = "Quest",
  TRADE = "Trade", MAIL = "Mail", AH = "Auction House", VENDOR = "Vendor", CRAFT = "Craft",
  DISENCHANT = "Disenchant", MILLING = "Milling", PROSPECTING = "Prospecting", OTHER = "Other",
}

-- Sources with a live capture path today. ROLL and CRAFT have no stamper yet (ROLL is specified in
-- docs/attribution.md; CRAFT is reserved for broad recipe crafting — a TODO), so they are hidden
-- from the mute list until wired. Deconstruct abilities stamp their own source; AH is stamped from
-- Auction-House mail. The SourceType enum stays whole (export contract); only the option lists scope.
C.SOURCE_IMPLEMENTED = {
  KILL = true, CONTAINER = true, MPLUS = true, QUEST = true, VENDOR = true,
  MAIL = true, TRADE = true, AH = true, OTHER = true,
  DISENCHANT = true, MILLING = true, PROSPECTING = true,
}

-- Attribution confidence.
C.Confidence = { CERTAIN = "CERTAIN", INFERRED = "INFERRED" }

-- Item class id for Quest-type items (Enum.ItemClass.Questitem). Locale-independent; the
-- collector's optional quest-item filter gates on this, never the localized itemType string.
C.ITEMCLASS_QUEST = 12

-- Vendored monospace font (JetBrains Mono, OFL) used by the debug console and copy boxes. Path is
-- the in-game addon-relative form; the file lives at media/fonts/ in the repo. This is a ratified
-- exception to the Blizzard-default-only media rule — WoW ships no monospace font object. See the
-- "Media" section in docs/conventions.md.
C.FONT_MONO = "Interface\\AddOns\\LootHistory\\media\\fonts\\JetBrainsMono-Regular.ttf"

-- Seconds a stamped loot context stays fresh before CHAT_MSG_LOOT falls back to OTHER.
C.CONTEXT_TTL = 1.5

-- Minimum-quality options for the collector threshold (WoW item-quality ids). The gate is a
-- monotonic "quality >= threshold" (Collector:gateReason). The ladder runs Poor(0)..Legendary(5),
-- then Heirloom(7) appended by explicit user choice. NOTE Heirloom's id (7) sits ABOVE Legendary,
-- so selecting it floors capture at 7 — i.e. only Heirlooms/Tokens, gating out Epics/Legendaries.
-- This is intentional, not a bug: leave it (ratified exception, see docs/conventions.md).
-- Artifact(6)/Token(8) stay omitted. Only the quality name is quality-coloured (the History
-- Browser's ITEM_QUALITY_COLORS tint); " and above" stays default.
-- rrggbb fallback for headless builds where ITEM_QUALITY_COLORS is absent (colour is cosmetic there).
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
    label = ("|cff%s%s|r and above"):format(qualityHex(q), NS.Compat.QualityLabel(q)),
  }
end

-- Retention presets; 0 means "Never" (cleanup disabled).
C.RETENTION_OPTIONS = {
  { value = 7,   label = "7 days" },
  { value = 14,  label = "14 days" },
  { value = 30,  label = "30 days" },
  { value = 60,  label = "60 days" },
  { value = 90,  label = "90 days" },
  { value = 180, label = "180 days" },
  { value = 365, label = "365 days" },
  { value = 0,   label = "Always" },
}

-- Per-source mute options, derived from the source order. Only sources with a live capture path
-- (SOURCE_IMPLEMENTED) are offered — an unreachable bucket would be a dead checkbox in the panel.
C.SOURCE_OPTIONS = {}
for _, s in ipairs(C.SourceOrder) do
  if C.SOURCE_IMPLEMENTED[s] then
    C.SOURCE_OPTIONS[#C.SOURCE_OPTIONS + 1] = { value = s, label = C.SourceLabel[s] }
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
  C.AUCTION_CAPTURE_OPTIONS[i] = { value = k.provider .. ":" .. k.key, label = k.label }
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
