std = "lua51"
max_line_length = false
codes = true
-- libs/ holds vendored code, including libs/LibKa0s/, whose upstream is the LibKa0s repo and
-- which is linted there rather than here. tests/_kit/ is that same fact one level down: it is a
-- byte copy of the library's testkit/, linted in LibKa0s as source, so linting the copy as well
-- would report every finding twice and would let the copy drift green while the original went red
-- -- the one state tests/test_vendor_sync.lua exists to forbid. Everything else under tests/ is
-- this repo's own and is linted (lint-§1).
-- Under docs/ only the FROZEN evidence bundles are excluded. A blanket docs/ exclude would
-- silently drop any Lua a future doc directory carries out of the gate.
exclude_files = { "libs/", "docs/audits/", "docs/reviews/", "_dev/", "tests/_kit/" }
ignore = {
  "212/self",       -- unused argument self
  "212/event",      -- unused argument event
  "211/addonName",  -- mandated `local addonName, NS = ...` header; not every file uses addonName
}
read_globals = {
  "_G", "LibStub", "CreateFrame", "UIParent", "GetTime", "time", "date", "DEFAULT_CHAT_FRAME",
  "UnitName", "UnitGUID", "UnitClass", "GetRealmName", "GetNormalizedRealmName",
  "RAID_CLASS_COLORS", "CLASS_ICON_TCOORDS", "StaticPopup_Show", "YES", "NO",
  "GameFontHighlightSmall", "GetCoinTextureString", "BreakUpLargeNumbers",
  "GetZoneText", "GetSubZoneText", "GetMinimapZoneText",
  "C_Map", "C_Item", "C_Timer", "C_ChallengeMode", "C_AuctionHouse", "C_TooltipInfo", "C_Texture",
  "C_CurrencyInfo",
  "C_Container", "UseContainerItem", "C_Spell", "GetSpellInfo",
  "C_AddOns", "GetAddOnMetadata",
  "Auctionator", "TSM_API", "OEMarketInfo",   -- third-party AH-pricing addon globals (presence-gated)
  "ITEM_ACCOUNTBOUND_UNTIL_EQUIP", "ITEM_BNETACCOUNTBOUND", "ITEM_BIND_TO_BNETACCOUNT",
  "ITEM_ACCOUNTBOUND", "ITEM_SOULBOUND", "RETRIEVING_ITEM_INFO",
  "GetLootSourceInfo", "GetNumLootItems", "GetInboxHeaderInfo", "TakeInboxItem", "AutoLootMailItem",
  "GetQuestReward", "GetQuestID",
  "BuyMerchantItem", "GetMerchantItemLink", "GetTitleText", "AUCTION_HOUSE",
  "InCombatLockdown", "hooksecurefunc", "strsplit", "strjoin", "strtrim", "SpellIsTargeting",
  "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown",
  "CombatLogGetCurrentEventInfo", "GetDetailedItemLevelInfo",
  "GameTooltip", "GetCursorPosition", "ChatEdit_InsertLink", "ChatFrame_OpenChat",
  "FauxScrollFrame_Update", "FauxScrollFrame_GetOffset", "FauxScrollFrame_OnVerticalScroll",
  "CreateAtlasMarkup", "CreateTextureMarkup",
  "ITEM_QUALITY_COLORS", "UISpecialFrames", "PlaySound", "STANDARD_TEXT_FONT",
  "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
  "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
  "LOOT_ITEM_BONUS_ROLL_SELF", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
  "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_CREATED_SELF_MULTIPLE",
  "LOOT_ITEM_REFUND", "LOOT_ITEM_REFUND_MULTIPLE", "LOOT_ROLL_YOU_WON",
  "CURRENCY_GAINED", "CURRENCY_GAINED_MULTIPLE",
  "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED_MULTIPLE_OVERFLOW",
  "Settings", "CreateColor", "tinsert", "tremove", "wipe", "select",
}
globals = {
  "LootHistoryDB",     -- the SavedVariables write target
  "StaticPopupDialogs", -- we register a purge-confirm dialog
}

-- The harness publishes its exposed table as _G.LH_TEST, written at tests/run.lua:103 and read
-- by every suite file. `globals` rather than `read_globals` because tests/run.lua is the writer,
-- and declared HERE rather than at the top level on purpose: a name granted at the top level is
-- granted to core/, modules/ and settings/ as much as to a suite. Scoped like this, a shipped
-- file that ASSIGNS any of these names is red (W122) while a suite is green -- verified both
-- ways. Note what that does and does not buy: `_G` itself is a read_globals entry with no field
-- list, so a shipped file READING _G.LH_TEST still passes. Closing that would mean dropping bare
-- `_G` and enumerating every field the shipped tree reads through it, which is a different
-- change from this one.
files["tests/"] = {
  globals = {
    "_G.LH_TEST",
    -- Client globals the suites PLANT and restore to stand a scenario up: a tooltip payload, the
    -- AH frame name Compat sniffs for, the retrieving-item sentinel and the two warband bind
    -- strings whose nil case Compat has a literal fallback for. They are named as fields of _G
    -- rather than bare because a suite plants them THROUGH _G, and they are writable only here:
    -- above they stay read-only, which is what shipped code is allowed to do with them.
    "_G.C_TooltipInfo", "_G.RETRIEVING_ITEM_INFO", "_G.AUCTION_HOUSE",
    "_G.AUCTION_WON_MAIL_SUBJECT",
    "_G.ITEM_ACCOUNTBOUND_UNTIL_EQUIP", "_G.ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP",
  },
}
