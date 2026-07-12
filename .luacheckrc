std = "lua51"
max_line_length = false
codes = true
exclude_files = { "libs/", "reviews/", "_dev/", "tests/" }
ignore = {
  "212/self",       -- unused argument self
  "212/event",      -- unused argument event
  "211/addonName",  -- mandated `local addonName, NS = ...` header; not every file uses addonName
}
read_globals = {
  "_G", "LibStub", "CreateFrame", "UIParent", "GetTime", "time", "date",
  "UnitName", "UnitGUID", "UnitClass", "GetRealmName", "GetNormalizedRealmName",
  "RAID_CLASS_COLORS", "CLASS_ICON_TCOORDS", "StaticPopup_Show", "YES", "NO",
  "GameFontHighlightSmall", "GetCoinTextureString", "BreakUpLargeNumbers",
  "GetZoneText", "GetSubZoneText", "GetMinimapZoneText",
  "C_Map", "C_Item", "C_Timer", "C_ChallengeMode", "C_AuctionHouse", "C_TooltipInfo", "C_Texture",
  "C_Container", "UseContainerItem", "C_Spell", "GetSpellInfo",
  "ITEM_ACCOUNTBOUND_UNTIL_EQUIP", "ITEM_BNETACCOUNTBOUND", "ITEM_BIND_TO_BNETACCOUNT",
  "ITEM_ACCOUNTBOUND", "ITEM_SOULBOUND",
  "GetLootSourceInfo", "GetNumLootItems", "GetInboxHeaderInfo", "TakeInboxItem", "AutoLootMailItem",
  "GetQuestReward", "GetQuestID",
  "BuyMerchantItem", "GetMerchantItemLink", "GetTitleText", "AUCTION_HOUSE",
  "WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CLASSIC",
  "InCombatLockdown", "hooksecurefunc", "strsplit", "strjoin", "strtrim", "SpellIsTargeting",
  "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown",
  "CombatLogGetCurrentEventInfo", "GetDetailedItemLevelInfo",
  "GameTooltip", "ChatEdit_InsertLink", "ChatFrame_OpenChat",
  "FauxScrollFrame_Update", "FauxScrollFrame_GetOffset", "FauxScrollFrame_OnVerticalScroll",
  "CreateAtlasMarkup", "CreateTextureMarkup",
  "ITEM_QUALITY_COLORS", "UISpecialFrames", "PlaySound", "STANDARD_TEXT_FONT",
  "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
  "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
  "Settings", "CreateColor", "tinsert", "tremove", "wipe", "select",
}
globals = {
  "LootHistoryDB",     -- the SavedVariables write target
  "StaticPopupDialogs", -- we register a purge-confirm dialog
}
