local _, NS = ...
-- core/CompatGain.lua — the gain feed's client reads (#38, toast spec
-- docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §3): experience, profession skills,
-- currency caps, the equip and item-level reads the toast rows use, the mount and look checks, the
-- modified-click and currency-link reads, the icon reads, the sound player and the Blizzard alert
-- suppression. Its own file so core/Compat.lua and its split siblings stay under their layout-§1
-- re-check; the rules are core/Compat.lua's: globals read bare at call time, never captured at load;
-- a secret is never compared, concatenated or indexed; a missing API answers its documented absent
-- value, never a raise.
--
-- LOAD-BEARING POSITION: in the compat family (below core/CompatClient.lua, whose IsSecret every
-- member here asks at call time) and straight before core/SimSeam.lua, which wraps every NS.Compat
-- member at file load, classes ModifiedLinkClick, PlayMediaSound, SuppressAlertEvents and
-- RestoreAlertEvents PURE and GUARDS ListSkillLines; below the seam these members would escape it.

NS.Compat = NS.Compat or {}
local Compat = NS.Compat

-- A plain (non-secret) number, or nil.
local function plainNumber(v)
  if Compat.IsSecret(v) or type(v) ~= "number" then return nil end
  return v
end
-- A plain (non-secret), non-empty string, or nil.
local function plainText(v)
  if Compat.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

-- ── Experience ───────────────────────────────────────────────────────────────────────────────

--- cur, max, level of the player's experience; nil when any read is absent, secret or not a number
--- (Forever's UnitStat family can answer secrets, docs/forever-quirks.md §3). `capped` is true when
--- IsXPUserDisabled() answers true or the level is at GetMaxPlayerLevel().
function Compat.PlayerXP()
  if not (type(UnitXP) == "function" and type(UnitXPMax) == "function" and type(UnitLevel) == "function") then
    return nil
  end
  local cur, max, level = plainNumber(UnitXP("player")), plainNumber(UnitXPMax("player")), plainNumber(UnitLevel("player"))
  if not (cur and max and level) then return nil end
  local capped = type(IsXPUserDisabled) == "function" and IsXPUserDisabled() == true
  if not capped and type(GetMaxPlayerLevel) == "function" then
    local top = plainNumber(GetMaxPlayerLevel())
    capped = top ~= nil and level >= top
  end
  return cur, max, level, capped
end

-- ── Profession skills ────────────────────────────────────────────────────────────────────────

-- Write one profession's entry into `out`, making the entry only the first time it is seen.
local function putSkill(out, line, name, rank, max)
  local e = out[line]
  if not e then e = {}; out[line] = e end
  e.name, e.rank, e.max = name, rank, max
end

--- Retail: the professions GetProfessions() names, each read with GetProfessionInfo(i), whose
--- seventh return is the skill line. No UI state is touched. Fills and answers `out` =
--- { [skillLine] = { name, rank, max } }; nil when the reads are absent.
function Compat.ProfessionSkills(out)
  if not (type(GetProfessions) == "function" and type(GetProfessionInfo) == "function") then return nil end
  local list = { GetProfessions() }
  for i = 1, 6 do
    local index = plainNumber(list[i])
    if index then
      local name, _, rank, max, _, _, line = GetProfessionInfo(index)
      name, rank, max, line = plainText(name), plainNumber(rank), plainNumber(max), plainNumber(line)
      if name and rank and line then putSkill(out, line, name, rank, max) end
    end
  end
  return out
end

-- The profession line a Forever skill-list row counts under: its parent (the vanilla line) when that
-- is a profession, else its own id when that is, else nil (a weapon skill, a language).
local function professionKey(info, lines)
  local parent = plainNumber(info.parentSkillLineID)
  if parent and lines[parent] then return parent end
  local id = plainNumber(info.skillID)
  if id and lines[id] then return id end
  return nil
end

-- One Forever skill-list row, kept when its own or its parent's id is a profession line; a pair
-- keeps the larger rank (T14).
local function keepSkillRow(out, info, lines)
  if type(info) ~= "table" or info.isHeader then return end
  local key, rank = professionKey(info, lines), plainNumber(info.rank)
  if not (key and rank) then return end
  local e = out[key]
  if e and e.seen and (e.rank or 0) >= rank then return end
  putSkill(out, key, plainText(info.name) or plainText(info.skillName), rank, plainNumber(info.maxRank))
  out[key].seen = true
end

--- Forever: walks C_SkillInfo.GetNumSkillLines / GetSkillLineInfo(i), expanding each collapsed header
--- with ExpandSkillHeader and collapsing it again afterwards, last to first (as ListCurrencies does).
--- Keeps only the rows whose skillID or parentSkillLineID is in C.PROFESSION_SKILL_LINES, keyed on the
--- vanilla line. GUARDED by core/SimSeam.lua: the header walk is UI state. Answers `out`, or nil when
--- the API is absent.
function Compat.ListSkillLines(out)
  local SI = C_SkillInfo
  if not (SI and SI.GetNumSkillLines and SI.GetSkillLineInfo) then return nil end
  local lines = NS.Constants.PROFESSION_SKILL_LINES
  for _, e in pairs(out) do e.seen = nil end
  local expanded, i = {}, 1
  while i <= (plainNumber(SI.GetNumSkillLines()) or 0) do
    local info = SI.GetSkillLineInfo(i)
    if type(info) == "table" and info.isHeader and info.isCollapsed and SI.ExpandSkillHeader then
      SI.ExpandSkillHeader(i); expanded[#expanded + 1] = i
    end
    i = i + 1
  end
  for j = 1, plainNumber(SI.GetNumSkillLines()) or 0 do keepSkillRow(out, SI.GetSkillLineInfo(j), lines) end
  if SI.CollapseSkillHeader then
    for k = #expanded, 1, -1 do SI.CollapseSkillHeader(expanded[k]) end
  end
  for _, e in pairs(out) do e.seen = nil end
  return out
end

-- ── Currency, items, mounts, looks ───────────────────────────────────────────────────────────

local function currencyInfo(id)
  local CI = C_CurrencyInfo
  local info = id and CI and CI.GetCurrencyInfo and CI.GetCurrencyInfo(id)
  return type(info) == "table" and info or nil
end

--- quantity, max, earnedTotal, usesEarned for a currency: max is maxQuantity (0 answers nil),
--- usesEarned is useTotalEarnedForMaxQty, earnedTotal is totalEarned. All nil when unreadable.
function Compat.CurrencyCap(id)
  local info = currencyInfo(id)
  if not info then return nil end
  local max = plainNumber(info.maxQuantity)
  if max == 0 then max = nil end
  return plainNumber(info.quantity), max, plainNumber(info.totalEarned), info.useTotalEarnedForMaxQty == true
end

--- C_CurrencyInfo.GetCurrencyInfo(id).iconFileID, a plain number, else nil.
function Compat.CurrencyIcon(id)
  local info = currencyInfo(id)
  return info and plainNumber(info.iconFileID) or nil
end

--- C_CurrencyInfo.GetCurrencyLink(id, 0), for the shift-click on a currency toast; nil when absent.
function Compat.CurrencyLink(id)
  local CI = C_CurrencyInfo
  if not (id and CI and CI.GetCurrencyLink) then return nil end
  return plainText(CI.GetCurrencyLink(id, 0))
end

--- itemEquipLoc, classID, subclassID from C_Item.GetItemInfoInstant(link or id); nil when absent.
function Compat.ItemEquipInfo(linkOrID)
  if not (linkOrID and C_Item and C_Item.GetItemInfoInstant) then return nil end
  local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(linkOrID)
  return plainText(equipLoc), plainNumber(classID), plainNumber(subclassID)
end

--- The effective item level of a link: C_Item.GetDetailedItemLevelInfo, else the global of that name.
function Compat.ItemLevelOf(link)
  if not link then return nil end
  local fn = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
  if type(fn) ~= "function" then return nil end
  return plainNumber(fn(link))
end

--- The link in an equipment slot (GetInventoryItemLink("player", slot)); nil when empty or secret.
function Compat.EquippedLink(slot)
  if type(GetInventoryItemLink) ~= "function" then return nil end
  return plainText(GetInventoryItemLink("player", slot))
end

--- C_Item.GetItemIconByID(itemID), a plain fileID, else nil.
function Compat.ItemIcon(itemID)
  if not (itemID and C_Item and C_Item.GetItemIconByID) then return nil end
  local icon = C_Item.GetItemIconByID(itemID)
  if Compat.IsSecret(icon) then return nil end
  return (type(icon) == "number" or type(icon) == "string") and icon or nil
end

--- True when C_MountJournal.GetMountFromItem(itemID) answers a mount id (both clients).
function Compat.IsMountItem(itemID)
  local MJ = C_MountJournal
  if not (itemID and MJ and MJ.GetMountFromItem) then return false end
  return plainNumber(MJ.GetMountFromItem(itemID)) ~= nil
end

--- Retail only (C.FEATURE.appearances): true when C_TransmogCollection.PlayerHasTransmogByItemInfo
--- answers false for the link; nil on WoW Forever or when it cannot say.
function Compat.IsUncollectedLook(link)
  if not (link and NS.Constants.FEATURE.appearances) then return nil end
  local TC = C_TransmogCollection
  if not (TC and TC.PlayerHasTransmogByItemInfo) then return nil end
  local has = TC.PlayerHasTransmogByItemInfo(link)
  if type(has) ~= "boolean" then return nil end
  return not has
end

-- ── UI actions (PURE: never simulated) ───────────────────────────────────────────────────────

--- HandleModifiedItemClick(link): shift inserts the link in chat, ctrl opens the dressing room.
--- Answers whether the client handled it.
function Compat.ModifiedLinkClick(link)
  if not link or type(HandleModifiedItemClick) ~= "function" then return false end
  return HandleModifiedItemClick(link) == true
end

--- The LibSharedMedia sound `key` ("" or nil is none) played on the Master channel. Answers whether
--- a sound was started.
function Compat.PlayMediaSound(key)
  if not key or key == "" or type(PlaySoundFile) ~= "function" then return false end
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local file = LSM and LSM:Fetch("sound", key, true)
  if not file then return false end
  return PlaySoundFile(file, "Master") and true or false
end

--- AlertFrame event suppression: each name in `events` that AlertFrame has registered is unregistered
--- and recorded in `into`, in order. Answers how many were suppressed.
function Compat.SuppressAlertEvents(events, into)
  local AF = AlertFrame
  if not (AF and AF.IsEventRegistered and AF.UnregisterEvent) then return 0 end
  local n = 0
  for _, name in ipairs(events) do
    if AF:IsEventRegistered(name) then
      AF:UnregisterEvent(name)
      into[#into + 1] = name
      n = n + 1
    end
  end
  return n
end

--- Re-registers exactly the names `into` recorded, in the same order, and wipes it. Answers how many.
function Compat.RestoreAlertEvents(into)
  local AF = AlertFrame
  local n = #into
  if AF and AF.RegisterEvent then
    for i = 1, n do AF:RegisterEvent(into[i]) end
  end
  for i = n, 1, -1 do into[i] = nil end
  return n
end
