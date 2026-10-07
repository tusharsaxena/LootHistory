local _, NS = ...
NS.Compat = NS.Compat or {}
local Compat = NS.Compat

-- Retail-only addon: no game-flavor branching. Every varying/deprecated API is gated by a
-- direct C_*/global presence check below, so a shim degrades to nil/false when its API is
-- absent — never by reading a game-flavor project id.

-- Fold U+00A0, the no-break space, to an ordinary space.
--
-- It is a space to the player and nothing at all to Lua. `%s` is a byte-wise ASCII class and the
-- no-break space is the two bytes \194\160 in UTF-8, so every pattern in this addon that trims,
-- splits or strips on `%s` walks straight past one. Blizzard's string tables and the client's own
-- tooltip builder use it freely — it is how a phrase is kept from wrapping mid-line — so this is
-- ordinary client text, not a corruption.
--
-- Folding the pair BEFORE the pattern work, rather than widening each class to `[ \194\160]`:
-- a class of those two bytes also matches the \160 that legitimately ENDS a multi-byte character
-- (à is \195\160, and one CJK codepoint in sixty-four ends the same way), so an end-anchored trim
-- built that way can saw the last character of a koKR or zhCN name in half. Matching the pair
-- exactly cannot. It also fixes the interior occurrences an edge trim never sees, which is the
-- half that actually matters here: both call sites compare a WHOLE localized phrase.
function Compat.FoldNBSP(s)
  return (s:gsub("\194\160", " "))
end

-- Active M+ keystone level (nil if no keystone active or the API is absent). Guarded by
-- C_ChallengeMode presence — degrades to nil when the challenge-mode API is unavailable.
function Compat.GetActiveKeystoneLevel()
  if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
    return (C_ChallengeMode.GetActiveKeystoneInfo())
  end
  return nil
end

-- Is the player inside a party (5-player dungeon) instance? The Mythic+ keystone context lives only
-- as long as this is true. Guarded by IsInInstance presence -- degrades to false when it is absent.
function Compat.InPartyInstance()
  if type(IsInInstance) ~= "function" then return false end
  local inInst, kind = IsInInstance()
  return (inInst and kind == "party") and true or false
end

-- Hook the "use a bag item" path. Opening a container item pushes its contents straight to bags
-- with no LOOT_OPENED / source GUID, so attribution needs a stamp from here. Calls fn(bag, slot)
-- after each use. Retail routes through C_Container; older clients expose a global.
function Compat.HookUseContainerItem(fn)
  if C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", fn)
  elseif type(UseContainerItem) == "function" then
    hooksecurefunc("UseContainerItem", fn)
  end
end

-- Does the bag item at (bag, slot) have openable loot (a container / lockbox)? False when unknown
-- or the API is absent — so a non-container item (potion, gear) never mis-stamps as CONTAINER.
function Compat.ContainerItemHasLoot(bag, slot)
  local get = C_Container and C_Container.GetContainerItemInfo
  if get then
    local info = get(bag, slot)
    if info and info.hasLoot then return true end
  end
  return false
end

-- Hook the quest-reward turn-in. GetQuestReward is the client call that triggers the server
-- turn-in, so a stamp here lands before the reward items push (the QUEST_TURNED_IN *event* can
-- fire after the reward loot line and miss it). Calls fn() after each turn-in.
function Compat.HookGetQuestReward(fn)
  if type(GetQuestReward) == "function" then
    hooksecurefunc("GetQuestReward", fn)
  end
end

-- The quest ID of the quest currently open in the quest frame (nil / 0 when none).
function Compat.CurrentQuestID()
  if type(GetQuestID) == "function" then return GetQuestID() end
  return nil
end

-- Is the cursor holding a spell awaiting a target (e.g. Disenchant/Enchant about to be applied
-- to a bag item)? Used to tell "opening a container" apart from "applying a spell to an item",
-- both of which route through UseContainerItem. False when the API is absent.
function Compat.IsSpellTargeting()
  return type(SpellIsTargeting) == "function" and SpellIsTargeting() or false
end

-- Localized spell name for a spell id (nil if unavailable). Lets attribution detect deconstruct
-- casts by name family across the many milling/prospecting/Mass variants.
--
-- LibKa0s-Compat-1.0's member, one value. Its ladder is C_Spell.GetSpellName, then
-- C_Spell.GetSpellInfo(id).name, then the legacy global's first return. A nil or "" answer falls
-- through to the next rung, and a secret answer is returned untouched. A non-number, non-string id
-- answers nil and asks no rung. It stays a FIELD on NS.Compat, because the call sites read it here
-- and tests/test_attribution.lua replaces it at runtime.
--
-- With the library absent: the reader stub, which answers the absent table's value, nil
-- (LibKa0s docs/api/Compat/version-1-docs.md, "Readers: the stub answers the absent value").
-- Attribution already treats nil as "not cached yet", so a degraded install loses the name-family
-- match for unlisted deconstruct variants and nothing raises. Re-implementing the top rung here
-- would re-create the copy this major exists to remove.
local CompatLib = LibStub and LibStub("LibKa0s-Compat-1.0", true)
Compat.GetSpellName = CompatLib and CompatLib.GetSpellName or function() return nil end

-- Sender + subject for an inbox mail row (nil when the API is absent).
function Compat.GetMailHeader(mailIndex)
  if type(GetInboxHeaderInfo) == "function" and mailIndex then
    local _, _, sender, subject = GetInboxHeaderInfo(mailIndex)
    return sender, subject
  end
  return nil, nil
end

-- Is this inbox mail from the Auction House? Locale-independent: matches the AH sender name
-- (AUCTION_HOUSE global) or an AH mail subject prefix (won / expired / canceled / invoice,
-- built from the localized *_MAIL_SUBJECT globals). Rebuilt per call — mail-take is infrequent.
local AH_SUBJECT_GLOBALS = {
  "AUCTION_WON_MAIL_SUBJECT", "AUCTION_EXPIRED_MAIL_SUBJECT",
  "AUCTION_REMOVED_MAIL_SUBJECT", "AUCTION_INVOICE_MAIL_SUBJECT",
}
function Compat.IsAuctionHouseMail(sender, subject)
  if sender and sender ~= "" and type(AUCTION_HOUSE) == "string" and sender == AUCTION_HOUSE then
    return true
  end
  if subject and subject ~= "" then
    for _, name in ipairs(AH_SUBJECT_GLOBALS) do
      local g = _G[name]
      if type(g) == "string" then
        local prefix = g:match("^(.-)%%s") or g   -- "Auction won: %s" → "Auction won: "
        if prefix ~= "" and subject:sub(1, #prefix) == prefix then return true end
      end
    end
  end
  return false
end

-- GUID kinds that carry a creature/npc id in field 6 of the dash-split GUID. Exposed as the
-- single source of truth; the attribution engine reads it to distinguish KILL from CONTAINER.
Compat.UNIT_KINDS = { Creature = true, Vehicle = true, Pet = true, Vignette = true }

-- Decode a WoW GUID → kind ("Creature"/"GameObject"/"Item"/...) and, for unit kinds,
-- the npcID (field 6). Non-unit kinds return nil for the id.
function Compat.DecodeGUID(guid)
  if not guid then return nil end
  local kind = strsplit("-", guid)
  local npcID
  if Compat.UNIT_KINDS[kind] then
    npcID = tonumber((select(6, strsplit("-", guid))))
  end
  return kind, npcID
end

-- Resilient item info for an item link. Returns itemID, itemName, quality, classID, falling
-- back to the link's own display data when the item is not yet cached (GetItemInfo returns nil).
-- classID is the locale-independent item class (Enum.ItemClass.*); nil when uncached/unknown.
--
-- THE GUESS IS THIS ADDON'S POLICY AND STAYS HERE. Only the color primitive under it moved
-- into LibKa0s-Item-1.0 (core/ItemSetup.lua): a browsable capture log would rather show an
-- approximate row than lose the drop, where BankLedger's gate refuses an uncached item outright.
function Compat.GetItemInfo(link)
  local itemID, classID
  if C_Item and C_Item.GetItemInfoInstant then
    local _
    itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
  end
  local name, _, quality
  if C_Item and C_Item.GetItemInfo then
    name, _, quality = C_Item.GetItemInfo(link)
  end
  name = name or (link and link:match("%[(.-)%]"))
  quality = quality or NS.Item.QualityFromLink(link)
  return itemID, name, quality, classID
end

-- Scan an item link's tooltip for warbound text.
-- Returns "WARBAND_UE" (warbound until equipped), "WARBAND", or nil. Retail-only (C_TooltipInfo).
--
-- Blizzard retired the separate "Account Bound" wording in 11.0 when Warbands landed — every
-- ITEM_*ACCOUNTBOUND* global now reads *Warbound* — so the two states a tooltip can express are
-- warbound and warbound-until-equipped. Each has two wordings: the "Binds to Warband…" form while
-- the item is still transferable, and the bare "Warbound…" form once it sits in a character's bags.
--
-- Detection is two steps per line, and NOT "match the longer global first". The two
-- `…_UNTIL_EQUIP` globals are not dependable at runtime — a live client can hand back nil for
-- them — so keying the equip-limited state on those globals alone silently degrades every
-- warbound-until-equipped drop to plain warbound (both wordings contain the shorter one). So:
-- decide *whether* the line is warbound from any of the six globals, then decide *which* state
-- from the "until equipped" qualifier, globals-first with a literal fallback. Literals are safe
-- here — this addon is English-only (CLAUDE.md) — and only ever widen what the globals catch.
-- A bind line is a WHOLE line — matching a substring anywhere in the tooltip is what broke this:
-- "Warbound Cache of Void-Touched Armaments: Boots" is an item NAME, and a `find` for "warbound"
-- hits it on line 1, classifying the item as plain warbound before the real bind line is ever
-- reached. So the six wordings are matched as complete lines (trimmed, case-insensitive), with one
-- deliberate exception: a line *starting* with "binds to warband" also counts, because no item name
-- opens that way, and that keeps a trailing-suffix variant of that family from being missed.
local WARBAND_ANY_GLOBALS = {
  "ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP", -- "Binds to Warband until equipped"
  "ITEM_ACCOUNTBOUND_UNTIL_EQUIP",    -- "Warbound until equipped"
  "ITEM_BIND_TO_BNETACCOUNT",         -- "Binds to Warband"
  "ITEM_BIND_TO_ACCOUNT",             -- "Binds to Warband"
  "ITEM_BNETACCOUNTBOUND",            -- "Warbound"
  "ITEM_ACCOUNTBOUND",                -- "Warbound"
}
local WARBAND_UE_GLOBALS = {
  "ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP",
  "ITEM_ACCOUNTBOUND_UNTIL_EQUIP",
}
-- Whole-line wordings, lower-cased. The globals cover these too when the client exposes them;
-- these are the fallback for the ones it leaves nil (English-only addon, see CLAUDE.md).
local WARBAND_LINES = {
  ["binds to warband until equipped"] = "WARBAND_UE",
  ["warbound until equipped"]         = "WARBAND_UE",
  ["binds to warband"]                = "WARBAND",
  ["warbound"]                        = "WARBAND",
}
local BIND_TO_WARBAND_PREFIX = "binds to warband"
local UE_LITERAL = "until equipped"

local function lineIsAny(text, globals)
  for _, name in ipairs(globals) do
    local s = _G[name]
    if s and s ~= "" and text == s then return true end
  end
  return false
end

local function isWarbandLine(text, lower)
  if lineIsAny(text, WARBAND_ANY_GLOBALS) then return true end
  if WARBAND_LINES[lower] then return true end
  return lower:sub(1, #BIND_TO_WARBAND_PREFIX) == BIND_TO_WARBAND_PREFIX
end

-- Returns state, readable. `readable` says whether the tooltip was actually built — a caller can't
-- tell "not warbound" from "the client hasn't built this tooltip yet" from a nil state alone, and
-- for the items whose bind type lies (below) the tooltip is the ONLY witness, so that difference
-- decides whether a repair pass retries the row or considers it settled.
--
-- An uncached item does NOT yield an empty tooltip: it yields a perfectly readable one that says
-- RETRIEVING_ITEM_INFO ("Retrieving item information") and nothing else. Counting that as readable
-- is how a repair pass "settles" every row while learning nothing — so it is excluded explicitly.
function Compat.ScanBound(link)
  if not (link and C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil, false end
  local data = C_TooltipInfo.GetHyperlink(link)
  if not (data and data.lines) then return nil, false end
  local retrieving = RETRIEVING_ITEM_INFO
  local readable = false
  for _, line in ipairs(data.lines) do
    local text = line.leftText
    if text and text ~= "" and not (retrieving and retrieving ~= "" and text:find(retrieving, 1, true)) then
      readable = true
      local lower = Compat.FoldNBSP(text:lower()):gsub("^%s+", ""):gsub("%s+$", "")
      if isWarbandLine(text, lower) then
        if lineIsAny(text, WARBAND_UE_GLOBALS) or lower:find(UE_LITERAL, 1, true) then
          return "WARBAND_UE", true
        end
        return "WARBAND", true
      end
    end
  end
  return nil, readable
end

-- Bind state from `C_Item.GetItemInfo`'s 14th return (`Enum.ItemBind`). A corroborating signal,
-- NOT the authority: it is locale-free and needs no tooltip, but Blizzard does not keep it honest
-- for warbound items — item 278014, a cache whose tooltip reads "Binds to Warband until equipped",
-- reports 2 (OnEquip) here. So a warbound answer from this is trustworthy, but its silence proves
-- nothing, and the tooltip is the only witness for those items (see docs/midnight-quirks.md).
-- 11.0 added the three account values; 5 and 6 are Blizzard's own Unused1/Unused2.
local BIND_STATE = {
  [1] = "BOP",        -- OnAcquire
  [2] = "BOE",        -- OnEquip
  [3] = "BOE",        -- OnUse
  [4] = "BOP",        -- Quest
  [7] = "WARBAND",    -- ToWoWAccount
  [8] = "WARBAND",    -- ToBnetAccount           ("Binds to Warband")
  [9] = "WARBAND_UE", -- ToBnetAccountUntilEquipped ("Binds to Warband until equipped")
}
function Compat.BindState(bindType)
  return bindType and BIND_STATE[bindType] or nil
end

-- The more specific of two bind verdicts. The two sources disagree in one direction only — one of
-- them sees warbound and the other doesn't — so rank by specificity and take the winner rather than
-- letting call order decide. Never demotes a warbound answer to BOE/BOP.
local BOUND_SPECIFICITY = { WARBAND_UE = 3, WARBAND = 2 }
function Compat.BestBound(a, b)
  if not a then return b end
  if not b then return a end
  local ra = BOUND_SPECIFICITY[a] or 1
  local rb = BOUND_SPECIFICITY[b] or 1
  return rb > ra and b or a
end

-- Bind state for a stored row, from both signals merged by BestBound. Returns state, settled —
-- `settled` is true once the tooltip was readable, which is what a caller must wait for: the bind
-- type answering "BOE" is not evidence that a row ISN'T warbound. `link` is optional; pass it when
-- the record has one, since the tooltip needs a link.
function Compat.ItemBindState(item, link)
  if not item then return nil, false end
  local typed, cached
  if C_Item and C_Item.GetItemInfo then
    local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(item)
    typed, cached = Compat.BindState(bindType), name ~= nil
  end
  -- A row may hold only an id, and the tooltip needs a link — "item:<id>" is a valid hyperlink for
  -- GetHyperlink, so an id-only row is still witnessable rather than permanently unsettled.
  local hyperlink = link or (type(item) == "number" and ("item:" .. item)) or item
  local scanned, readable = Compat.ScanBound(hyperlink)
  -- Settled needs BOTH: the item data cached (so `typed` means something) and a real tooltip (so
  -- the absence of a warbound line means something). Either alone has already fooled this addon.
  return Compat.BestBound(typed, scanned), (readable and cached) or false
end

-- Capture-time extras for a looted item. Returns:
--   ilvl        effective item level (equippable weapons/armor only; nil otherwise)
--   bound       nil(unbound) | "BOE" | "BOP" | "WARBAND" | "WARBAND_UE"
--   sellPrice   vendor sell price in copper (per unit)
--   itemType    top-level type ("Armor", "Weapon", "Tradegoods", …)
--   itemSubType finer subtype ("Cloth", "Sword", "Cooking", …)
local ITEMCLASS_WEAPON, ITEMCLASS_ARMOR = 2, 4  -- Enum.ItemClass.Weapon / .Armor
function Compat.GetItemExtras(link)
  if not link then return nil, nil, nil, nil, nil end
  local ilvl, bound, sellPrice, itemType, itemSubType

  local classID, equipLoc
  if C_Item and C_Item.GetItemInfoInstant then
    local _, _, _, eLoc, _, cID = C_Item.GetItemInfoInstant(link)
    classID, equipLoc = cID, eLoc
  end

  local bindType
  if C_Item and C_Item.GetItemInfo then
    local _, itemLevel
    _, _, _, itemLevel, _, itemType, itemSubType, _, _, _, sellPrice, _, _, bindType =
      C_Item.GetItemInfo(link)
    -- ilvl only for real gear; reagents/consumables carry a meaningless itemLevel.
    if (classID == ITEMCLASS_WEAPON or classID == ITEMCLASS_ARMOR)
      and equipLoc and equipLoc ~= "" then
      ilvl = (C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)) or itemLevel
    end
  end

  -- Both signals, most-specific wins (BestBound). Neither is reliable alone: GetItemInfo answers
  -- nothing at all for an uncached item, and the tooltip can be unreadable or word the state in a
  -- form whose global the client left nil. Whichever one *does* see warbound is believed.
  local scanned = Compat.ScanBound(link)   -- drop the `readable` flag: capture stores what it has
  bound = Compat.BestBound(Compat.BindState(bindType), scanned)

  return ilvl, bound, sellPrice, itemType, itemSubType
end

-- Currency id parsed from a |Hcurrency:ID:...|h link. Locale-independent; nil when absent.
function Compat.CurrencyLinkID(link)
  if not link then return nil end
  return tonumber(link:match("|?H?currency:(%d+)"))
end

-- Resolve a currency link to id, name, iconFileID. Id + name come from the link itself (so this
-- works headlessly / before the client caches the currency); C_CurrencyInfo enriches name + icon
-- when present. icon is nil when the API is absent.
function Compat.GetCurrencyInfoFromLink(link)
  local id = Compat.CurrencyLinkID(link)
  local name = link and link:match("%[(.-)%]")
  local icon
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink then
    local info = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
    if info then
      name = info.name or name
      icon = info.iconFileID
    end
  end
  return id, name, icon
end

-- currencyID -> category (the currency window's expansion/type header, e.g. "The War Within").
-- Built by walking the currency list and tracking the most recent header, then cached. A miss
-- rebuilds the cache once and looks again, so a currency first discovered mid-session (routine at a
-- season start) still resolves; currencyCategoryMissed remembers each id that missed, so an id that
-- is truly absent costs at most one list walk -- until the list itself changes. A different
-- GetCurrencyListSize, or the client's bulk refresh (Compat.CurrencyListChanged, called on a nil-id
-- CURRENCY_DISPLAY_UPDATE), drops the cache and the memo, so an id that missed and is listed LATER
-- still resolves. nil when the API is absent or the id isn't in the list. Known gap:
-- GetCurrencyListInfo enumerates only the children of EXPANDED headers, so a currency under a
-- header the player collapsed in the Currency tab is still missed. This deliberately does not call
-- C_CurrencyInfo.ExpandCurrencyList from a loot handler: that would rewrite the player's Currency
-- tab. See docs/midnight-quirks.md "Currency category". currencyListed (id -> list name) is the same
-- walk's set of listed ids, which Compat.ListedCurrencyID tests a chat line against.
local currencyCategoryCache, currencyListed, currencyListSize
local currencyCategoryMissed = {}
local function listSize()
  local api = C_CurrencyInfo
  return (api and api.GetCurrencyListSize and api.GetCurrencyListSize()) or 0
end
local function buildCurrencyCategoryCache()
  currencyCategoryCache, currencyListed, currencyListSize = {}, {}, listSize()
  local api = C_CurrencyInfo
  if not (api and api.GetCurrencyListInfo and api.GetCurrencyListLink) then return end
  local header
  for i = 1, currencyListSize do
    local info = api.GetCurrencyListInfo(i)
    if info then
      if info.isHeader then
        header = info.name
      else
        local id = Compat.CurrencyLinkID(api.GetCurrencyListLink(i))
        if id then
          currencyListed[id] = info.name or true
          if header then currencyCategoryCache[id] = header end
        end
      end
    end
  end
end
function Compat.CurrencyListChanged()
  currencyCategoryCache = nil
  for k in pairs(currencyCategoryMissed) do currencyCategoryMissed[k] = nil end
end
-- The cache, fresh enough to answer for `currencyID`: rebuilt when absent or when the list changed
-- size, and once more on an id's first miss.
local function currencyCacheFor(currencyID)
  if currencyCategoryCache and listSize() ~= currencyListSize then Compat.CurrencyListChanged() end
  if not currencyCategoryCache then buildCurrencyCategoryCache() end
  if currencyListed[currencyID] == nil and not currencyCategoryMissed[currencyID] then
    currencyCategoryMissed[currencyID] = true
    buildCurrencyCategoryCache()
  end
end
function Compat.CurrencyCategory(currencyID)
  if not currencyID then return nil end
  currencyCacheFor(currencyID)
  return currencyCategoryCache[currencyID]
end

-- The currency id a chat currency line should record under, or nil to drop it. The chat link can
-- name a HIDDEN tracking currency the token list never shows (owner report 2026-10-06: "Nebulous
-- Voidcore" arrived as both hidden 3513 and listed 3418), and a row under that id is a duplicate no
-- holdings delta ever claims. `id` stands when it is listed, or held in the current character's or
-- the warband's stored currency baseline (which covers a currency under a collapsed header);
-- otherwise exactly one listed or held currency of the same name is the one it stands for; anything
-- else is nil.
local function heldCurrency(holder)
  local e = NS.Holdings and NS.Holdings.Get and NS.Holdings:Get(holder)
  return e and e.currency
end
function Compat.ListedCurrencyID(id, name)
  if not id then return nil end
  currencyCacheFor(id)
  local mine = heldCurrency(NS.Util.PlayerKey())
  local warband = heldCurrency(NS.Constants.WARBAND_HOLDER)
  if currencyListed[id] ~= nil or (mine and mine[id] ~= nil) or (warband and warband[id] ~= nil) then
    return id
  end
  if not name then return nil end
  local twin
  local function consider(cid, cname)
    if cid == twin then return true end
    if cname == true or cname == nil then cname = Compat.CurrencyName(cid) end
    if cname ~= name then return true end
    if twin then twin = false; return false end   -- a second match: ambiguous
    twin = cid
    return true
  end
  for cid, cname in pairs(currencyListed) do if not consider(cid, cname) then return nil end end
  for _, held in ipairs({ mine or {}, warband or {} }) do
    for cid in pairs(held) do if not consider(cid, currencyListed[cid]) then return nil end end
  end
  return twin or nil
end

-- Quality tier (Enum.ItemQuality) for a currency id, from C_CurrencyInfo; nil when uncached/absent.
-- Colors the currency name + fills the Quality column, and drives the v3->v4 backfill migration.
function Compat.CurrencyQuality(currencyID)
  if not currencyID then return nil end
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if info then return info.quality end
  end
  return nil
end

-- Localized currency name for a currency id, from C_CurrencyInfo; nil when uncached/absent. The
-- holdings search names currency rows from this, so it must not throw headless.
function Compat.CurrencyName(currencyID)
  if not currencyID then return nil end
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if info then return info.name end
  end
  return nil
end

-- Localized item type + subtype ("Armor", "Cloth") for an item id or link; nil, nil when the item
-- is not cached or the API is absent. Kept apart from GetItemInfo, whose four-value shape other
-- callers depend on.
function Compat.GetItemTypeInfo(idOrLink)
  if idOrLink and C_Item and C_Item.GetItemInfo then
    local results = { C_Item.GetItemInfo(idOrLink) }
    return results[6], results[7]
  end
  return nil, nil
end

-- Per-unit vendor sell price (copper) for an item id or link; nil when the item is not cached, the
-- API is absent, or it cannot be sold. The holdings tab values a stack from this beside the picked
-- auction price -- through here, not GetItemExtras, which also scans the tooltip for bind state.
function Compat.GetItemSellPrice(idOrLink)
  if idOrLink and C_Item and C_Item.GetItemInfo then
    local results = { C_Item.GetItemInfo(idOrLink) }
    return results[11]
  end
  return nil
end

-- Item level of a piece of gear (a weapon or armor with an equip slot) for an item id or link; nil
-- for anything else, as GetItemExtras answers, but without its tooltip scan for bind state. The
-- holdings tab's iLvl column reads it once per held item per refresh.
function Compat.GearItemLevel(idOrLink)
  if not (idOrLink and C_Item and C_Item.GetItemInfoInstant) then return nil end
  local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(idOrLink)
  if not ((classID == ITEMCLASS_WEAPON or classID == ITEMCLASS_ARMOR) and equipLoc and equipLoc ~= "") then
    return nil
  end
  local ilvl = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(idOrLink)
  if not ilvl and C_Item.GetItemInfo then ilvl = select(4, C_Item.GetItemInfo(idOrLink)) end
  return ilvl
end

-- GameTooltip, presence-gated: each Show* answers false (and draws nothing) when the tooltip or the
-- method it needs is missing, so a hover never errors on a client or harness without them.
local function tooltip(method)
  local tt = GameTooltip
  if type(tt) ~= "table" or (method and type(tt[method]) ~= "function") then return nil end
  return tt
end

function Compat.ShowItemTooltip(owner, link, anchor)
  local tt = tooltip("SetHyperlink")
  if not (tt and link) then return false end
  tt:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  tt:SetHyperlink(link)
  tt:Show()
  return true
end

function Compat.ShowCurrencyTooltip(owner, currencyID, anchor)
  local tt = tooltip("SetCurrencyByID")
  if not (tt and currencyID) then return false end
  tt:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  tt:SetCurrencyByID(currencyID)
  tt:Show()
  return true
end

-- A plain tooltip: a gold title, then an optional wrapped body line.
function Compat.ShowTextTooltip(owner, title, body, anchor)
  local tt = tooltip("AddLine")
  if not (tt and title) then return false end
  tt:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  tt:AddLine(title, 1, 0.82, 0)
  if body and body ~= "" then tt:AddLine(body, 0.9, 0.9, 0.9, true) end
  tt:Show()
  return true
end

-- An amount tooltip (BankLedger's gold-row shape): a colored title, one "label .... value" double
-- line, then an optional gray hint. `rgb` is the title color ({ r, g, b }); nil = header gold.
function Compat.ShowAmountTooltip(owner, title, rgb, label, value, hint, anchor)
  local tt = tooltip("AddDoubleLine")
  if not (tt and title) then return false end
  rgb = rgb or { 1, 0.82, 0 }
  tt:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  tt:AddLine(title, rgb[1], rgb[2], rgb[3])
  tt:AddDoubleLine(label or "", value or "", 0.9, 0.9, 0.9, 1, 1, 1)
  if hint and hint ~= "" then tt:AddLine(hint, 0.5, 0.5, 0.5) end
  tt:Show()
  return true
end

-- A title over several "label .... value" lines, each pair in its row's color (the Timeline strip's
-- Gained / Lost / Net). `rows` is { { label, text, color = { r, g, b } }, ... }; nil color = white.
function Compat.ShowLinesTooltip(owner, title, rows, anchor)
  local tt = tooltip("AddDoubleLine")
  if not (tt and title) then return false end
  tt:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  tt:AddLine(title, 1, 0.82, 0)
  for _, r in ipairs(rows or {}) do
    local c = r.color or { 1, 1, 1 }
    tt:AddDoubleLine(r.label or "", r.text or "", c[1], c[2], c[3], c[1], c[2], c[3])
  end
  tt:Show()
  return true
end

-- Plain lines, each in its own color (test mode's History rows, which carry no item link): `lines`
-- is { { text, r, g, b }, ... }, the first being the title; a nil color reads white.
function Compat.ShowTintedTooltip(owner, lines, anchor)
  local tt = tooltip("AddLine")
  if not (tt and lines and lines[1]) then return false end
  tt:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  for _, l in ipairs(lines) do tt:AddLine(l[1] or "", l[2] or 1, l[3] or 1, l[4] or 1) end
  tt:Show()
  return true
end

function Compat.HideTooltip()
  local tt = tooltip("Hide")
  if tt then tt:Hide() end
end

-- Bound state for a currency, from C_CurrencyInfo: "WARBAND" for a Warband-transferable currency
-- (the tooltip's "Warband Transferable" = `isAccountTransferable`), else "BOP" (currencies are
-- otherwise soulbound). Returns nil when the API can't resolve the id (headless / uncached) so callers
-- leave the Bound cell unset rather than mislabel. Drives the currency bound glyph at capture + the
-- v4->v5 backfill migration.
function Compat.CurrencyBound(currencyID)
  if not currencyID then return nil end
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if info then return info.isAccountTransferable and "WARBAND" or "BOP" end
  end
  return nil
end

-- ── Holdings reads (timeline ledger, spec §3) ─────────────────────────────────────────────────
function Compat.GetContainerNumSlots(bagID)
  local fn = C_Container and C_Container.GetContainerNumSlots
  return fn and (fn(bagID) or 0) or 0
end

function Compat.GetContainerSlot(bagID, slot)
  local fn = C_Container and C_Container.GetContainerItemInfo
  if not fn then return nil end
  local info = fn(bagID, slot)
  if not info or not info.itemID then return nil end
  return { itemID = info.itemID, link = info.hyperlink, count = info.stackCount or 1 }
end

-- Purse money as the player owns it: copper on the cursor or staged in an open trade window is
-- still theirs (BagSync events.lua's formula).
function Compat.GetMoney()
  if type(GetMoney) ~= "function" then return 0 end
  local cursor = type(GetCursorMoney) == "function" and GetCursorMoney() or 0
  local trade = type(GetPlayerTradeMoney) == "function" and GetPlayerTradeMoney() or 0
  return (GetMoney() or 0) - (cursor or 0) - (trade or 0)
end

function Compat.GetWarbandMoney()
  local fn = C_Bank and C_Bank.FetchDepositedMoney
  local t = Enum and Enum.BankType and Enum.BankType.Account
  if type(fn) ~= "function" or t == nil then return nil end
  return fn(t)
end

function Compat.GetInventoryItem(slot)
  if type(GetInventoryItemID) ~= "function" then return nil end
  local id = GetInventoryItemID("player", slot)
  if not id then return nil end
  return id, type(GetInventoryItemLink) == "function" and GetInventoryItemLink("player", slot) or nil
end

function Compat.BagInventorySlot(bagID)
  local fn = C_Container and C_Container.ContainerIDToInventoryID
  return fn and fn(bagID) or nil
end

function Compat.InteractionType(name)
  local e = Enum and Enum.PlayerInteractionType
  return e and e[name] or nil
end

-- The Reconciler's combat gate. The LOCKDOWN flag and not UnitAffectingCombat on purpose: this
-- decides whether a scan may run (events-frames-taint-§2), not whether something is displayed, and
-- the deferred work resumes on the PLAYER_REGEN_ENABLED edge that clears it. Read at call time.
function Compat.InCombatLockdown()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- The player's class token ("MAGE"), stamped on a holder's meta for the class-colored name.
function Compat.PlayerClassFile()
  if type(UnitClass) ~= "function" then return nil end
  local _, classFile = UnitClass("player")
  return classFile
end

-- Every currency the character has, with its quantity. The client's list hides the children of a
-- collapsed header, so collapsed headers are expanded for the walk and collapsed again after,
-- last-to-first so indices stay valid (BagSync scanner.lua does the same).
function Compat.ListCurrencies()
  local CI = C_CurrencyInfo
  if not (CI and CI.GetCurrencyListSize and CI.GetCurrencyListInfo and CI.GetCurrencyListLink) then return {} end
  local expanded = {}
  local i = 1
  while i <= CI.GetCurrencyListSize() do
    local info = CI.GetCurrencyListInfo(i)
    if info and info.isHeader and not info.isHeaderExpanded and CI.ExpandCurrencyList then
      CI.ExpandCurrencyList(i, true); expanded[#expanded + 1] = i
    end
    i = i + 1
  end
  local out = {}
  for j = 1, CI.GetCurrencyListSize() do
    local info = CI.GetCurrencyListInfo(j)
    if info and not info.isHeader then
      local id = Compat.CurrencyLinkID(CI.GetCurrencyListLink(j))
      if id then out[#out + 1] = { id = id, quantity = info.quantity or 0, accountWide = info.isAccountWide == true } end
    end
  end
  for k = #expanded, 1, -1 do CI.ExpandCurrencyList(expanded[k], false) end
  return out
end

-- ── Ledger capture (timeline ledger Phase 2) ─────────────────────────────────────────────────

-- hooksecurefunc, presence-gated. A missing target (renamed between builds, absent on a flavor)
-- returns false and installs nothing; the hook BODY must gate itself on NS.IsStoodDown (there is
-- no un-hook — slash-commands-§7's carve-out).
function Compat.HookSecure(name, fn)
  if type(hooksecurefunc) ~= "function" or type(_G[name]) ~= "function" then return false end
  hooksecurefunc(name, fn)
  return true
end

function Compat.HookSecureMember(tbl, member, fn)
  if type(hooksecurefunc) ~= "function" or type(tbl) ~= "table" or type(tbl[member]) ~= "function" then
    return false
  end
  hooksecurefunc(tbl, member, fn)
  return true
end

-- Consumable = Enum.ItemClass.Consumable (0), locale-independent.
function Compat.IsConsumable(itemID)
  local fn = C_Item and C_Item.GetItemInfoInstant
  if not (fn and itemID) then return false end
  local classID = select(6, fn(itemID))
  return classID == 0
end

function Compat.CurrencyIsAccountWide(id)
  local fn = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
  local info = fn and fn(id)
  return info ~= nil and info.isAccountWide == true
end

local function enumName(enum, value)
  if type(enum) ~= "table" or value == nil then return nil end
  for name, v in pairs(enum) do if v == value then return name end end
  return nil
end

-- CURRENCY_DISPLAY_UPDATE's 4th/5th args, as the Enum MEMBER NAME (C.CURRENCY_SOURCE_REASON keys).
function Compat.CurrencySourceName(gainSource, destroyReason, change)
  local E = Enum or {}
  if (change or 0) > 0 then return enumName(E.CurrencySource, gainSource) end
  if (change or 0) < 0 then return enumName(E.CurrencyDestroyReason, destroyReason) end
  return nil
end

local function addCount(counts, links, id, n, link)
  if not id or not n or n <= 0 then return end
  counts[id] = (counts[id] or 0) + n
  if link and not links[id] then links[id] = link end
end

-- Every attachment in the inbox the client has loaded (readable only while the mailbox is open).
function Compat.ScanInbox()
  local counts, links = {}, {}
  if type(GetInboxNumItems) ~= "function" or type(GetInboxItem) ~= "function" then return counts, links end
  local maxA = ATTACHMENTS_MAX_RECEIVE or 16
  for i = 1, (GetInboxNumItems() or 0) do
    for a = 1, maxA do
      local _, itemID, _, count = GetInboxItem(i, a)
      if itemID then
        addCount(counts, links, itemID, count or 1, type(GetInboxItemLink) == "function" and GetInboxItemLink(i, a) or nil)
      end
    end
  end
  return counts, links
end

-- What is staged in the Send Mail frame right now (read from the SendMail post-hook).
function Compat.ReadSendMail()
  local items = {}
  if type(GetSendMailItem) == "function" then
    for slot = 1, (ATTACHMENTS_MAX_SEND or 12) do
      local _, itemID, _, count = GetSendMailItem(slot)
      if itemID then items[itemID] = (items[itemID] or 0) + (count or 1) end
    end
  end
  local money = type(GetSendMailMoney) == "function" and (GetSendMailMoney() or 0) or 0
  return items, money
end

-- Active owned auctions (sold-but-uncollected ones have left the player's escrow already).
function Compat.ScanOwnedAuctions()
  local counts, links = {}, {}
  local AH = C_AuctionHouse
  if not (AH and AH.GetNumOwnedAuctions and AH.GetOwnedAuctionInfo) then return counts, links end
  local active = (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Active) or 0
  for i = 1, (AH.GetNumOwnedAuctions() or 0) do
    local a = AH.GetOwnedAuctionInfo(i)
    if a and a.status == active and a.itemKey then
      addCount(counts, links, a.itemKey.itemID, a.quantity or 1, a.itemLink)
    end
  end
  return counts, links
end

function Compat.ItemLocationID(loc)
  local fn = C_Item and C_Item.GetItemID
  return (fn and loc) and fn(loc) or nil
end

-- Auction-house mail subject -> kind, item name. Built from the localized global strings, so it
-- follows the client language (the same rule as Compat.IsAuctionHouseMail).
local AH_SUBJECTS
local function ahSubjects()
  if AH_SUBJECTS then return AH_SUBJECTS end
  AH_SUBJECTS = {}
  for kind, g in pairs({ sold = AUCTION_SOLD_MAIL_SUBJECT, expired = AUCTION_EXPIRED_MAIL_SUBJECT,
                         cancelled = AUCTION_REMOVED_MAIL_SUBJECT, won = AUCTION_WON_MAIL_SUBJECT }) do
    if type(g) == "string" then
      local p = g:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1"):gsub("%%%%s", "(.+)")
      AH_SUBJECTS[#AH_SUBJECTS + 1] = { kind = kind, pattern = "^" .. p .. "$" }
    end
  end
  return AH_SUBJECTS
end

function Compat.AuctionMailKind(subject)
  if type(subject) ~= "string" then return nil end
  for _, s in ipairs(ahSubjects()) do
    local name = subject:match(s.pattern)
    if name then return s.kind, name end
  end
  return nil
end

-- The trade partner as a holder key. UnitName("NPC") is the open trade's other party.
function Compat.TradeTargetKey()
  if type(UnitName) ~= "function" then return nil end
  local name, realm = UnitName("NPC")
  if not name or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  realm = (realm and realm ~= "") and realm
    or (type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName()) or nil
  return realm and (name .. "-" .. realm) or name
end

-- The newest warband currency transfer this character made (CURRENCY_TRANSFER_LOG_UPDATE). Field
-- names are the 11.x CurrencyTransferTransaction shape as recalled; smoke LED-P2-13 verifies them.
function Compat.LatestCurrencyTransfer()
  local fn = C_CurrencyInfo and C_CurrencyInfo.FetchCurrencyTransferTransactions
  local list = fn and fn()
  if type(list) ~= "table" or #list == 0 then return nil end
  local t = list[#list]
  local to = t.destinationCharacterName
  if to and not to:find("-", 1, true) and type(GetNormalizedRealmName) == "function" then
    local realm = GetNormalizedRealmName()                 -- nil early in login: never a bare "Name-"
    if realm and realm ~= "" then to = to .. "-" .. realm end
  end
  return { currencyID = t.currencyType, quantity = t.quantityTransferred, toKey = to }
end
