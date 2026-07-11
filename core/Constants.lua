local addonName, NS = ...
NS.Constants = NS.Constants or {}
local C = NS.Constants

-- Source enum. Values are the stored string keys (stable — do not rename; they are the export contract).
C.SourceType = {
  KILL = "KILL", CONTAINER = "CONTAINER", MAIL = "MAIL", TRADE = "TRADE",
  AH = "AH", QUEST = "QUEST", VENDOR = "VENDOR", CRAFT = "CRAFT",
  ROLL = "ROLL", MPLUS = "MPLUS", OTHER = "OTHER",
}

-- Display order for grouping/analytics (most to least "interesting").
C.SourceOrder = {
  "KILL", "CONTAINER", "MPLUS", "ROLL", "QUEST",
  "TRADE", "MAIL", "AH", "VENDOR", "CRAFT", "OTHER",
}

-- Short human labels for the UI.
C.SourceLabel = {
  KILL = "Kill", CONTAINER = "Container", MPLUS = "Mythic+", ROLL = "Roll", QUEST = "Quest",
  TRADE = "Trade", MAIL = "Mail", AH = "Auction", VENDOR = "Vendor", CRAFT = "Craft", OTHER = "Other",
}

-- Attribution confidence.
C.Confidence = { CERTAIN = "CERTAIN", INFERRED = "INFERRED" }

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

-- Per-source mute options, derived from the source order.
C.SOURCE_OPTIONS = {}
for _, s in ipairs(C.SourceOrder) do
  C.SOURCE_OPTIONS[#C.SOURCE_OPTIONS + 1] = { value = s, label = C.SourceLabel[s] }
end

-- Convenience aliases.
NS.SourceType = C.SourceType
NS.Confidence = C.Confidence
