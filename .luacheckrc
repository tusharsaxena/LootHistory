std = "lua51"
max_line_length = false
codes = true
-- libs/ holds vendored code, including libs/LibKa0s/, whose upstream is the LibKa0s repo and
-- which is linted there rather than here. tests/_kit/ is that same fact one level down: it is a
-- byte copy of the library's testkit/, linted in LibKa0s as source, so linting the copy as well
-- would report every finding twice and would let the copy drift green while the original went red
-- -- the one state tests/test_vendor_sync.lua exists to forbid. Everything else under tests/ is
-- this repo's own and is linted (lint.md).
-- Under docs/ only the FROZEN evidence bundles are excluded. A blanket docs/ exclude would
-- silently drop any Lua a future doc directory carries out of the gate.
exclude_files = { "libs/", "docs/audits/", "docs/reviews/", "_dev/", "tests/_kit/" }

-- NO TOP-LEVEL `ignore`, and none is coming back (lint.md, `M4-11`). This file carried
-- `ignore = { "212/self", "212/event", "211/addonName" }` until `M4c-06`. A top-level ignore reaches
-- EVERY linted file -- 58 of them when it was removed -- so it silenced those codes in every file
-- that has no business producing them as well as in the thirteen that earn them, and that reads as
-- coverage while providing none.
-- Removing the three lines reported ONE HUNDRED AND TEN findings. EIGHTEEN were real and are fixed
-- in the source rather than moved into a narrower suppression: seventeen files opened
-- `local addonName, NS = ...` over a folder name they never read and now open `local _, NS = ...`,
-- and `modules/Filters.lua`'s `F:_notify` took a `reason` its body never looked at from five call
-- sites that each passed one. The third entry, `212/event`, was silencing NOTHING -- not one
-- warning in the tree bore that name -- so it is simply gone. The 93 that remain are all one code
-- and one name, `212/self`, and they are below in per-file stanzas.
-- tests/test_lintconfig.lua is what keeps the blanket from re-entering.
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
  "InCombatLockdown", "UnitAffectingCombat", "IsInInstance", "hooksecurefunc", "strsplit", "strjoin", "strtrim", "SpellIsTargeting",
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
    -- The spell-name ladder's rungs, planted by tests/test_compat.lua's GetSpellName cases.
    "_G.C_Spell", "_G.GetSpellInfo",
  },
}

-- ---------------------------------------------------------------------------
-- The narrowed 212s (lint.md, `M4c-06`)
-- ---------------------------------------------------------------------------
--
-- Every stanza below names ONE file, and every entry names the code AND the variable, in luacheck's
-- `<code>/<variable>` form. Note precisely what changed, because the blanket this replaced ALSO
-- named its variables: the difference is SCOPE, not spelling. These thirteen stanzas answer for
-- thirteen files, so an unused `self` in any of the other 46 still reports, and so does an unused
-- argument under any other name anywhere at all.
--
-- Measured rather than assumed, and measured on that axis: an unused `self` and an unread
-- `addonName` header planted in core/Util.lua -- a file no stanza names -- both report under this
-- config, while the same tree re-linted with the old blanket (`luacheck --config <the blanket> .`)
-- comes back 0 warnings / 0 errors. A dead argument under a NEW name reported under both configs;
-- claiming otherwise would have been a measurement this tree never produced.
--
-- What every entry has in common: the receiver is decided by the CALL SITE, not by the body. Each
-- of these files opens `NS.<Module> = NS.<Module> or {}` and takes a file-scope upvalue on it
-- (`local B = NS.Browser`, `local Database = NS.Database`, ...), so a method that needs its own
-- module reaches it through that upvalue and never through `self`. The methods are published on
-- `NS` and every caller in the repository invokes them with a colon -- verified, there is not one
-- dot-call of any of these 85 names -- so the receiver arrives whether the body wants it or not.
-- Dropping it would mean rewriting every call site of a published surface that
-- tests/test_surface_parity.lua pins by name, which is a different change from this one.

-- The AceAddon object's own lifecycle hooks. AceAddon calls `addon:OnInitialize()` itself, and
-- `OnEnterWorld` is registered on the AceEvent mixin the same object carries.
files["core/LootHistory.lua"] = { ignore = { "212/self" } }

-- The published module tables. Each reads its own state through the file's upvalue rather than the
-- receiver: Database through `local Database`, Browser through `local B`, and so on.
files["core/Database.lua"]        = { ignore = { "212/self" } }
files["modules/Attribution.lua"]  = { ignore = { "212/self" } }
files["modules/AuctionPrice.lua"] = { ignore = { "212/self" } }
files["modules/Browser.lua"]      = { ignore = { "212/self" } }
files["modules/BrowserTable.lua"] = { ignore = { "212/self" } }
files["modules/Collector.lua"]    = { ignore = { "212/self" } }
files["modules/Export.lua"]       = { ignore = { "212/self" } }
files["modules/Filters.lua"]      = { ignore = { "212/self" } }
files["settings/Panel.lua"]       = { ignore = { "212/self" } }
files["settings/Schema.lua"]      = { ignore = { "212/self" } }
files["settings/Slash.lua"]       = { ignore = { "212/self" } }

-- The mock stands in for client APIs, so its stubs copy the real signatures whether the stub body
-- uses them or not -- a mock that quietly narrows a signature is a mock that lets a caller pass
-- headless and fail in the client. These six are frame and font-string measurement stubs the
-- harness hands back from `CreateFrame`, called as `frame:GetWidth()` by the code under test.
files["tests/wow_mock.lua"] = { ignore = { "212/self" } }
