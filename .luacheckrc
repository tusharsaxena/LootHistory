std = "lua51"
max_line_length = false
codes = true
exclude_files = { "libs/", "reviews/", "_dev/", "tests/" }
ignore = {
  "212/self",   -- unused argument self
  "212/event",  -- unused argument event
}
read_globals = {
  "_G", "LibStub", "CreateFrame", "UIParent", "GetTime", "time", "date",
  "UnitName", "UnitGUID", "GetRealmName", "GetNormalizedRealmName",
  "GetZoneText", "GetSubZoneText", "GetMinimapZoneText",
  "C_Map", "C_Item", "C_Timer", "C_ChallengeMode", "C_AuctionHouse",
  "GetLootSourceInfo", "GetInboxHeaderInfo", "TakeInboxItem", "AutoLootMailItem",
  "BuyMerchantItem", "GetMerchantItemLink",
  "WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CLASSIC",
  "InCombatLockdown", "hooksecurefunc", "strsplit", "strjoin", "strtrim",
  "GameTooltip", "ChatEdit_InsertLink", "ChatFrame_OpenChat",
  "ITEM_QUALITY_COLORS", "UISpecialFrames", "PlaySound",
  "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
  "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
  "Settings", "CreateColor", "tinsert", "tremove", "wipe", "select",
}
globals = {
  "LootHistoryDB",  -- the SavedVariables write target
}
