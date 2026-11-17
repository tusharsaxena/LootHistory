-- LibKa0s-Role-1.0 -- the player's specialization and the group role it plays, read from the
-- client and answered the same way on Retail and on WoW Forever.
--
-- -- WHY THIS EXISTS ---------------------------------------------------------------------------
--
-- A callout, a filter or a layout that depends on "am I the tank" has to ask the client a
-- different question on each client. On Retail the spec is the answer: every class has two to four
-- specializations and `GetSpecializationInfo` names the role of each. On WoW Forever every class
-- has ONE specialization, so the spec API's role is class-wide and wrong for every hybrid (a
-- Protection warrior and an Arms warrior share it). What tells them apart there is the talent
-- tree: Forever's talents are one C_Traits tree per class whose GROUPS are the classic talent trees
-- (Arms, Fury, Protection), and the group with the most points spent is the role being played.
--
-- The owner ruled (2026-11-10, QuickComms' Forever port, Ka0sAddonsCommonTasks
-- docs/2026-11-10-QUICKCOMMS_FOREVER_EMOTES/inputs/owner-rulings.md R3 and R5) that this read is a
-- reusable LibKa0s module, built once here rather than inside the first addon that needed it, and
-- that the player can override it and the answer is saved per character. CLAUDE.md's register
-- carries the one-consumer promotion.
--
-- -- THE RESOLUTION ORDER (Resolve) --------------------------------------------------------------
--
--   1. `store.override`, the player's own pick, when it is a valid role.
--   2. The role the group assigned (`UnitGroupRolesAssigned("player")`), unless it is NONE.
--   3. WoW Forever only: the talent group with the most points spent in the active spec group,
--      mapped through TALENT_GROUP_ROLE below. A tie for the most points, or zero points, falls
--      through, and so does a class or a group index the seed does not name.
--   4. The spec API's role (`GetSpecializationInfo`'s fifth return; on Retail the usual answer).
--   5. `store.last`, the last role this resolved to, so a read at login before the client answers
--      still has one.
--
-- Every answer from rungs 2 to 4 is written to `store.last` with the spec id it was read under. An
-- override is never written there, so clearing it cannot bring the manual pick back as `"saved"`.
-- The store is the host's per-character table: this module owns no SavedVariables.
--
-- -- THE RULES EVERY MEMBER OBEYS --------------------------------------------------------------
--
--   1. Globals are read BARE and at CALL time, as LibKa0s-Compat-1.0's are, so the headless kit can
--      remove an API after load and watch the ladder move.
--   2. Namespaced rung first, the global second, nil last.
--   3. A value that may be secret is never compared: it is dropped to nil after IsSecret has said
--      so, and only plain numbers and strings reach a comparison or a table key.
--   4. No C function is called with an argument the client documents as non-nilable when the
--      argument is nil; the rung answers nil instead.
--   5. The client question ("is this WoW Forever") is answered only by LibKa0s-Compat-1.0's
--      IsForever, looked up at call time (clients-§3). Without Compat the talent rung is skipped
--      and the spec reads answer nil, because the spec ladder is Compat's.
--   6. No pcall. A client defect raises where it happens instead of reading as silence.
--
-- Depends on LibStub and LibKa0s-Core-1.0 (the floor, no member called), and on
-- LibKa0s-Compat-1.0 at call time with no floor. No addon framework, no frames, no events.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Role-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Role = MINOR

local VALID = { TANK = true, HEALER = true, DAMAGER = true }

-- The classic talent trees in the order Forever's groups are expected to come in (orderIndex),
-- mapped to the role each one plays. MATCHED, NOT CONFIRMED: the order is the classic tree order,
-- and the owner's probe (QuickComms `/qc probe`, which prints Groups()) confirms it on the client.
-- A class not named here (or a group index past its list) makes the talent rung fall through.
local TALENT_GROUP_ROLE = {
  WARRIOR = { "DAMAGER", "DAMAGER", "TANK" },     -- Arms, Fury, Protection
  PALADIN = { "HEALER", "TANK", "DAMAGER" },      -- Holy, Protection, Retribution
  PRIEST  = { "HEALER", "HEALER", "DAMAGER" },     -- Discipline, Holy, Shadow
  SHAMAN  = { "DAMAGER", "DAMAGER", "HEALER" },    -- Elemental, Enhancement, Restoration
  DRUID   = { "DAMAGER", "DAMAGER", "HEALER" },    -- Balance, Feral, Restoration
  HUNTER  = { "DAMAGER", "DAMAGER", "DAMAGER" },   -- Beast Mastery, Marksmanship, Survival
  ROGUE   = { "DAMAGER", "DAMAGER", "DAMAGER" },   -- Assassination, Combat, Subtlety
  MAGE    = { "DAMAGER", "DAMAGER", "DAMAGER" },   -- Arcane, Fire, Frost
  WARLOCK = { "DAMAGER", "DAMAGER", "DAMAGER" },   -- Affliction, Demonology, Destruction
}

--- The seed table, by class file then group index. Read it; a host never writes it.
lib.TALENT_GROUP_ROLE = TALENT_GROUP_ROLE

-- -- plain reads --------------------------------------------------------------------------------

local function compat()
  return LibStub and LibStub("LibKa0s-Compat-1.0", true) or nil
end

local function isSecret(v)
  local c = compat()
  if c and c.IsSecret then return c.IsSecret(v) end
  local fn = issecretvalue
  return fn ~= nil and fn(v) and true or false
end

local function plainNumber(v)
  if type(v) ~= "number" or isSecret(v) then return nil end
  return v
end

local function plainString(v)
  if type(v) ~= "string" or isSecret(v) then return nil end
  if v == "" then return nil end
  return v
end

local function validRole(v)
  v = plainString(v)
  if v and VALID[v] then return v end
  return nil
end

local function isForever()
  local c = compat()
  return c ~= nil and c.IsForever ~= nil and c.IsForever() == true
end

local function playerClassFile()
  if not UnitClass then return nil end
  local _, file = UnitClass("player")
  return plainString(file)
end

-- -- the spec -----------------------------------------------------------------------------------

--- specID, name, role of the active specialization, each plain or nil.
local function readSpec()
  local c = compat()
  if not (c and c.GetSpecialization and c.GetSpecializationInfo) then return nil, nil, nil end
  local index = plainNumber(c.GetSpecialization())
  if not index then return nil, nil, nil end
  local id, name, _, _, role = c.GetSpecializationInfo(index)
  id = plainNumber(id)
  if id and id <= 0 then id = nil end
  return id, plainString(name), validRole(role)
end

--- The player's active specialization: `specID, name`, each plain or nil (exactly two values).
---
--- Read through LibKa0s-Compat-1.0's spec ladder (C_SpecializationInfo first, the globals second).
--- A secret, a zero id or no answer reads as nil; without Compat both are nil.
---
--- @return number|nil specID, string|nil name
function lib.Spec()
  local id, name = readSpec()
  return id, name
end

-- -- the class's specs --------------------------------------------------------------------------

local function classInfo(index)
  if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
    local info = C_CreatureInfo.GetClassInfo(index)
    if not info then return nil, nil end
    return plainString(info.classFile), plainNumber(info.classID)
  end
  if GetClassInfo then
    local _, file, id = GetClassInfo(index)
    return plainString(file), plainNumber(id)
  end
  return nil, nil
end

local function classIDFor(classFile)
  if not GetNumClasses then return nil end
  local count = plainNumber(GetNumClasses())
  if not count then return nil end
  for index = 1, count do
    local file, id = classInfo(index)
    if file == classFile then return id end
  end
  return nil
end

local function numSpecs(classID)
  if C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID then
    return plainNumber(C_SpecializationInfo.GetNumSpecializationsForClassID(classID))
  end
  if GetNumSpecializationsForClassID then
    return plainNumber(GetNumSpecializationsForClassID(classID))
  end
  return nil
end

local function specForClass(classID, index)
  if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForClassID then
    return C_SpecializationInfo.GetSpecializationInfoForClassID(classID, index)
  end
  if GetSpecializationInfoForClassID then
    return GetSpecializationInfoForClassID(classID, index)
  end
  return nil
end

--- The specializations a class has on this client, in the client's index order: an array of
--- `{ id = specID, name = name, role = role }` (role nil when the client names none). Always a
--- new table, empty when the class or the APIs are unknown.
---
--- `classFile` is the class token (`"WARRIOR"`); nil means the player's own class. The class id is
--- found through the client's class list (`C_CreatureInfo.GetClassInfo`, else `GetClassInfo`), and
--- each spec through `GetNumSpecializationsForClassID` / `GetSpecializationInfoForClassID`, the
--- C_SpecializationInfo rung first where it exists. Read at run time, so Forever needs no seed.
---
--- @param classFile string|nil
--- @return table[]
function lib.SpecsForClass(classFile)
  local out = {}
  classFile = classFile == nil and playerClassFile() or plainString(classFile)
  if not classFile then return out end
  local classID = classIDFor(classFile)
  if not classID then return out end
  local count = numSpecs(classID)
  if not count then return out end
  for index = 1, count do
    local id, name, _, _, role = specForClass(classID, index)
    id = plainNumber(id)
    if id and id > 0 then
      out[#out + 1] = { id = id, name = plainString(name), role = validRole(role) }
    end
  end
  return out
end

-- -- the talent groups (WoW Forever) ------------------------------------------------------------

local function activeConfigID()
  local S = C_SpecializationInfo
  if S and S.GetActiveSpecGroup and S.GetCombatConfigIDForSpecGroup then
    local group = plainNumber(S.GetActiveSpecGroup())
    if group then
      local id = plainNumber(S.GetCombatConfigIDForSpecGroup(group))
      if id then return id end
    end
  end
  if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
    return plainNumber(C_ClassTalents.GetActiveConfigID())
  end
  return nil
end

local function treeIDFor(configID)
  if C_Traits and C_Traits.GetConfigInfo then
    local info = C_Traits.GetConfigInfo(configID)
    local id = info and type(info.treeIDs) == "table" and plainNumber(info.treeIDs[1])
    if id then return id end
  end
  if C_ClassTalents and C_ClassTalents.GetTraitTreeForSpec then
    local specID = readSpec()
    if specID then return plainNumber(C_ClassTalents.GetTraitTreeForSpec(specID)) end
  end
  return nil
end

local function spentIn(groupInfo)
  local infos = groupInfo and groupInfo.currencyInfos
  local first = type(infos) == "table" and infos[1] or nil
  return first and plainNumber(first.spent) or 0
end

local function byOrder(a, b)
  if a.order ~= b.order then return a.order < b.order end
  return a.id < b.id
end

--- The groups the tree displays, as `{ id, name, order }` rows, and their ids (two tables).
local function displayedGroups(treeID)
  local rows, ids = {}, {}
  local displays = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
  if type(displays) ~= "table" then return rows, ids end
  for _, display in ipairs(displays) do
    local id = type(display) == "table" and plainNumber(display.groupID)
    if id then
      ids[#ids + 1] = id
      rows[#rows + 1] = { id = id, name = plainString(display.displayName),
        order = plainNumber(display.orderIndex) or #rows + 1 }
    end
  end
  return rows, ids
end

--- groupID -> points spent, for the groups `ids` names in the config.
local function spentByGroup(configID, ids)
  local spent = {}
  local infos = C_Traits.GetGroupCurrencyInfo(configID, ids)
  if type(infos) ~= "table" then return spent end
  for _, info in ipairs(infos) do
    local id = type(info) == "table" and plainNumber(info.traitNodeGroupID)
    if id then spent[id] = spentIn(info) end
  end
  return spent
end

--- The config and tree to read, or nil when this is not Forever or an API or an answer is missing.
local function talentSource()
  if not isForever() then return nil end
  if not (C_Traits and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo) then
    return nil
  end
  local configID = activeConfigID()
  if not configID then return nil end
  local treeID = treeIDFor(configID)
  if not treeID then return nil end
  return configID, treeID
end

--- The talent groups of the active spec group: an array of `{ index, id, name, spent }`, in the
--- groups' display order (`orderIndex`), `index` being the position in that order. Always a new
--- table; empty on a client that is not WoW Forever, and wherever an API or an answer is missing.
---
--- The config is the active spec group's (`C_SpecializationInfo.GetCombatConfigIDForSpecGroup` of
--- `GetActiveSpecGroup()`, else `C_ClassTalents.GetActiveConfigID()`), the tree is the config's
--- first tree (`C_Traits.GetConfigInfo`, else `C_ClassTalents.GetTraitTreeForSpec`), the groups are
--- `C_Traits.GetGroupDisplayInfoByTreeID`, and `spent` is the first currency's `spent` from
--- `C_Traits.GetGroupCurrencyInfo` (0 when the client gives none), as Forever's own talent frame
--- reads them.
---
--- @return table[]
function lib.Groups()
  local configID, treeID = talentSource()
  if not configID then return {} end
  local out, ids = displayedGroups(treeID)
  if #ids == 0 then return out end
  local spent = spentByGroup(configID, ids)
  table.sort(out, byOrder)
  for index, group in ipairs(out) do
    group.index, group.order, group.spent = index, nil, spent[group.id] or 0
  end
  return out
end

--- role, groupName from the talent group with the most points, or nil on a tie, zero or no seed.
local function talentRole()
  local seed = TALENT_GROUP_ROLE[playerClassFile() or ""]
  if not seed then return nil, nil end
  local best, tied
  for _, group in ipairs(lib.Groups()) do
    if group.spent > 0 then
      if not best or group.spent > best.spent then
        best, tied = group, false
      elseif group.spent == best.spent then
        tied = true
      end
    end
  end
  if not best or tied then return nil, nil end
  local role = seed[best.index]
  if not VALID[role or ""] then return nil, nil end
  return role, best.name
end

-- -- resolve ------------------------------------------------------------------------------------

local function assignedRole()
  if not UnitGroupRolesAssigned then return nil end
  return validRole(UnitGroupRolesAssigned("player"))
end

local function remember(store, role, specID)
  if type(store) ~= "table" then return end
  local last = type(store.last) == "table" and store.last or {}
  last.role, last.specID = role, specID
  store.last = last
end

--- The role the player plays: `role, source, detail` (exactly three values).
---
--- `role` is `"TANK"`, `"HEALER"`, `"DAMAGER"` or nil. `source` is `"override"`, `"assigned"`,
--- `"talents"`, `"spec"`, `"saved"` or nil, in that order of precedence (the header's resolution
--- order). `detail` names where the answer came from where there is a name to give: the talent
--- group's name for `"talents"` ("Protection"), the spec's name for `"spec"`, else nil.
---
--- `store` is the host's per-character table (nil is accepted: no override, no saved answer, no
--- write). Every answer from rungs 2 to 4 is written to `store.last` as `{ role = role, specID = id }`;
--- an override and a `"saved"` answer write nothing.
---
--- @param store table|nil
--- @return string|nil role, string|nil source, string|nil detail
function lib.Resolve(store)
  if type(store) ~= "table" then store = nil end
  local specID, specName, specRole = readSpec()
  local role, source, detail
  local override = store and validRole(store.override)
  if override then
    role, source = override, "override"
  else
    local assigned = assignedRole()
    if assigned then
      role, source = assigned, "assigned"
    elseif isForever() then
      role, detail = talentRole()
      if role then source = "talents" end
    end
    if not role and specRole then
      role, source, detail = specRole, "spec", specName
    end
  end
  if role then
    if source ~= "override" then remember(store, role, specID) end
    return role, source, detail
  end
  local last = store and type(store.last) == "table" and validRole(store.last.role)
  if last then return last, "saved", nil end
  return nil, nil, nil
end

--- Set or clear the player's own pick. `role` is `"TANK"`, `"HEALER"`, `"DAMAGER"`, or nil to go
--- back to the automatic answer. Anything else raises at the caller, as does a `store` that is not
--- a table, so a typo cannot sit unnoticed as an override that never applies.
---
--- @param store table
--- @param role string|nil
function lib.SetOverride(store, role)
  if type(store) ~= "table" then
    error("SetOverride: store must be a table", 2)
  end
  if role ~= nil and not (type(role) == "string" and VALID[role]) then
    error('SetOverride: unknown role "' .. tostring(role) .. '"', 2)
  end
  store.override = role
end
