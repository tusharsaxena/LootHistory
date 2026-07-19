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

-- Minimum-quality options for the collector threshold (WoW item-quality ids).
C.QUALITY_OPTIONS = {
  { value = 0, label = "Poor (grey) and above" },
  { value = 1, label = "Common (white) and above" },
  { value = 2, label = "Uncommon (green) and above" },
  { value = 3, label = "Rare (blue) and above" },
  { value = 4, label = "Epic (purple) and above" },
  { value = 5, label = "Legendary (orange) and above" },
}

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

-- Auction cascade priority slots (1 = probed first).
C.AUCTION_PRIORITY_OPTIONS = {
  { value = 1, label = "1st" }, { value = 2, label = "2nd" }, { value = 3, label = "3rd" },
}
-- TSM price sources exposed to GetCustomPriceValue (see docs/ai-export-guideline.md / TSM docs).
C.TSM_SOURCE_OPTIONS = {
  { value = "dbmarket",          label = "Market value (dbmarket)" },
  { value = "dbminbuyout",       label = "Min buyout (dbminbuyout)" },
  { value = "dbregionmarketavg", label = "Region market avg (dbregionmarketavg)" },
  { value = "dbhistorical",      label = "Historical (dbhistorical)" },
}

-- Every AH price data point the addon can capture. tag = provider..":"..key. Drives the capture
-- menu, GatherAll's fetch loop, the CSV sub-columns, and the priority defaults.
C.AUCTION_KEYS = {
  { provider = "auctionator", key = "minbuyout",            label = "Auctionator \226\128\148 Min buyout" },
  { provider = "tsm",         key = "dbmarket",             label = "TSM \226\128\148 Market value" },
  { provider = "tsm",         key = "dbminbuyout",          label = "TSM \226\128\148 Min buyout" },
  { provider = "tsm",         key = "dbregionmarketavg",    label = "TSM \226\128\148 Region market avg" },
  { provider = "tsm",         key = "dbregionminbuyoutavg", label = "TSM \226\128\148 Region min-buyout avg" },
  { provider = "tsm",         key = "dbhistorical",         label = "TSM \226\128\148 Historical" },
  { provider = "tsm",         key = "dbrecent",             label = "TSM \226\128\148 Recent" },
  { provider = "tsm",         key = "dbregionhistorical",   label = "TSM \226\128\148 Region historical" },
  { provider = "tsm",         key = "dbregionsaleavg",      label = "TSM \226\128\148 Region sale avg" },
  { provider = "oribos",      key = "market",               label = "OribosExchange \226\128\148 Market" },
  { provider = "oribos",      key = "region",               label = "OribosExchange \226\128\148 Region" },
}
-- Curated defaults (which keys are captured, and the selection priority order).
C.AUCTION_CAPTURE_DEFAULT = {
  ["auctionator:minbuyout"] = true, ["tsm:dbmarket"] = true, ["tsm:dbminbuyout"] = true,
  ["tsm:dbregionmarketavg"] = true, ["tsm:dbregionminbuyoutavg"] = true,
  ["oribos:market"] = true, ["oribos:region"] = true,
}
C.AUCTION_PRIORITY_DEFAULT = {
  "tsm:dbmarket", "auctionator:minbuyout", "oribos:market",
  "tsm:dbminbuyout", "tsm:dbregionmarketavg", "tsm:dbregionminbuyoutavg", "oribos:region",
}

-- Convenience aliases.
NS.SourceType = C.SourceType
NS.Confidence = C.Confidence
