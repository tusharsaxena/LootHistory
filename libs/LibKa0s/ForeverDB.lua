-- LibKa0s-ForeverDB-1.0 -- the one reader of ForeverDB, WoW Forever's community data addon, for
-- every Ka0s addon that wants what the client cannot tell it.
--
-- -- WHY THIS EXISTS ---------------------------------------------------------------------------
--
-- The client knows its own data (DB2) and nothing the server supplies: which creature drops an
-- item and how often, who sells it and for how much, where a creature or an object stands, who
-- gives and ends a quest, what a trainer teaches. On WoW Forever, ForeverDB carries exactly those
-- facts (github.com/foreverfraddons/forever-db: QuestieDB, VMaNGOS, cMaNGOS and pfQuest, merged and
-- cross-checked). It is a LoadOnDemand addon of some 12 MB, positional rows behind short table
-- names, and its layout is its own. Five Ka0s addons want it (Drop Watcher, Loot History, Bank
-- Ledger, Skill Master, Outfitter Reborn), so the reading lives here once: one place knows the row
-- positions, one place decides when the 12 MB load happens, and one place answers plainly when the
-- addon is absent, disabled, old or reshaped (LibKa0s#105).
--
-- ForeverDB is an OPTIONAL runtime dependency. A host lists it in `## OptionalDeps` (and MAY list it
-- under `.pkgmeta`'s `optional-dependencies`), never in `## Dependencies`: no player needs it
-- installed, and a feature that reads it says so where the player sees the feature (WowAddonStandards
-- clients-§11). Its data is GPL-3.0 and this library is MIT, so nothing here or in its tests holds a
-- row of it; the kit's fake (testkit/mock_foreverdb.lua) is invented data in ForeverDB's shape.
--
-- -- THE RULES EVERY MEMBER OBEYS --------------------------------------------------------------
--
--   1. The first lookup is what loads. Every lookup calls Available() first, and Available() is the
--      ONLY caller of C_AddOns.LoadAddOn, once a session. Nothing loads at file load or at login.
--      IsLoaded() and Status() never load: they are the diagnostics' reads.
--   2. WoW Forever only. "Is this WoW Forever" is answered by LibKa0s-Compat-1.0's IsForever,
--      looked up at call time (clients-§3); without Compat the answer is "not Forever". On any other
--      client every lookup answers nil and Available() answers false, "client".
--   3. Globals are read BARE and at CALL time (ForeverDB, C_AddOns), never captured at load and
--      never through the global table, so the headless kit can install and remove them per case.
--   4. No pcall, and no raise on a missing, old or reshaped ForeverDB: defensive type checks
--      instead. A table that is not a table, a row that is not a table, or a field of the wrong type
--      reads as nil (the field) or as no answer (the row).
--   5. Every answer is a FRESH table built here, never one of ForeverDB's own rows, so a caller can
--      keep, sort or edit what it was given without touching the database every addon shares.
--   6. Ids are plain numbers; anything else is no answer.
--
-- Depends on LibStub and LibKa0s-Core-1.0 (the floor, no member called), and on
-- LibKa0s-Compat-1.0 at call time with no floor. No addon framework, no frames, no events. Reads
-- only ForeverDB's base addon in this version: ForeverDB_Full and ForeverDB_Locales are a later
-- minor.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-ForeverDB-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.ForeverDB = MINOR

local ADDON = "ForeverDB"
local CHANCE_SCALE = 10000   -- drop chances are per 10000; 0 means the rate is unknown
local COORD_SCALE  = 1000    -- map coordinates are on 0..1000

-- -- plain reads --------------------------------------------------------------------------------

local function compat()
  return LibStub and LibStub("LibKa0s-Compat-1.0", true) or nil
end

local function isForever()
  local c = compat()
  return c ~= nil and c.IsForever ~= nil and c.IsForever() == true
end

local function num(v)
  if type(v) == "number" and v == v then return v end
  return nil
end

local function str(v)
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

local function id(v)
  v = num(v)
  if v and v > 0 then return v end
  return nil
end

local function addons()
  local A = C_AddOns
  if type(A) == "table" then return A end
  return nil
end

--- Whether the client knows the addon, without loading it.
local function exists(A)
  if not A then return false end
  if A.DoesAddOnExist then return A.DoesAddOnExist(ADDON) == true end
  if A.GetAddOnInfo then
    local name, _, _, _, reason = A.GetAddOnInfo(ADDON)
    return name ~= nil and reason ~= "MISSING"
  end
  return false
end

local function loadedNow(A)
  if not (A and A.IsAddOnLoaded) then return false end
  return A.IsAddOnLoaded(ADDON) and true or false
end

local function tocVersion(A)
  if not (A and A.GetAddOnMetadata) then return nil end
  return str(A.GetAddOnMetadata(ADDON, "Version"))
end

-- -- Available ----------------------------------------------------------------------------------

local cached   -- { ok, reason } once Available() has answered; cleared only by __reset

local function evaluate()
  if not isForever() then return false, "client" end
  local A = addons()
  if not exists(A) then return false, "missing" end
  if not loadedNow(A) then
    if not A.LoadAddOn then return false, "missing" end
    local loaded, reason = A.LoadAddOn(ADDON)
    if not loaded then return false, str(reason) or "failed" end
  end
  if type(ForeverDB) ~= "table" then return false, "reshaped" end
  return true, nil
end

--- Whether ForeverDB can be read: `ok, reason` (exactly two values).
---
--- `true, nil` when it is loaded and its global is a table. Otherwise `false` and the reason:
--- `"client"` (not WoW Forever, through Compat's IsForever; without Compat, not Forever),
--- `"missing"` (the client does not know the addon), the client's own LoadAddOn reason
--- (`"DISABLED"`, `"DEP_MISSING"` and the rest; `"failed"` when it gives none), or `"reshaped"`
--- (it loaded, but `ForeverDB` is not a table).
---
--- The FIRST call does the work and is the one place this library calls
--- `C_AddOns.LoadAddOn("ForeverDB")`, and only when the addon is not already loaded; the answer is
--- kept for the session, so later calls cost nothing and never load again. A load is some 12 MB, so
--- a host makes its first call where the player asked for the feature, never at login.
---
--- @return boolean ok, string|nil reason
function lib.Available()
  if not cached then
    local ok, reason = evaluate()
    cached = { ok, reason }
  end
  return cached[1], cached[2]
end

--- Whether the client has ForeverDB loaded now, by any addon. Never loads anything, and is not
--- gated on the client: it is the diagnostics' read.
---
--- @return boolean
function lib.IsLoaded()
  return loadedNow(addons())
end

--- What the diagnostics report prints: a new table `{ present, loaded, version, build, hash }`.
--- `present` (the client knows the addon) and `loaded` are booleans; `version` is the TOC Version,
--- read without loading and only when `present`; `build` and `hash` are the database's `meta` fields, only when it is
--- loaded and its global is a table. Never loads anything, and is not gated on the client.
---
--- @return table
function lib.Status()
  local A = addons()
  local present = exists(A)
  -- the Version is read only for an addon the client knows: a metadata read of an unknown name is
  -- a call this library has no reason to risk in every Retail diagnostics report.
  local out = { present = present, loaded = loadedNow(A), version = present and tocVersion(A) or nil }
  local D = ForeverDB
  if out.loaded and type(D) == "table" and type(D.meta) == "table" then
    out.build, out.hash = str(D.meta.build), str(D.meta.hash)
  end
  return out
end

--- Forget the cached answer, so the next Available() asks again. For tests; a host never calls it.
function lib.__reset()
  cached = nil
end

-- -- the database ---------------------------------------------------------------------------------

--- ForeverDB's table `name`, or nil when ForeverDB is unavailable or the table is not a table.
local function tbl(name)
  if not lib.Available() then return nil end
  local D = ForeverDB
  if type(D) ~= "table" then return nil end
  local t = D[name]
  if type(t) == "table" then return t end
  return nil
end

--- Row `key` of table `name`, when both are tables.
local function row(name, key)
  local t = tbl(name)
  if not t then return nil end
  local r = t[key]
  if type(r) == "table" then return r end
  return nil
end

local FACTIONS = { A = true, H = true, AH = true }

--- The database's own description: a new table `{ version, build, hash, counts }`, or nil when
--- ForeverDB is unavailable. `version` is the TOC Version; `build` (the build date) and `hash` are
--- `meta`'s; `counts` is a new table of `meta.counts`' numeric entries (table name -> rows). A field
--- the database does not carry is nil.
---
--- @return table|nil
function lib.Meta()
  if not lib.Available() then return nil end
  local out = { version = tocVersion(addons()) }
  local D = ForeverDB
  local meta = type(D) == "table" and D.meta or nil
  if type(meta) == "table" then
    out.build, out.hash = str(meta.build), str(meta.hash)
    if type(meta.counts) == "table" then
      local counts = {}
      for k, v in pairs(meta.counts) do
        if type(k) == "string" and num(v) then counts[k] = v end
      end
      out.counts = counts
    end
  end
  return out
end

--- A creature: a new table `{ id, name, subname, minLevel, maxLevel, rank, faction }`, or nil.
---
--- From `npc[id] = { name, subname, minLevel, maxLevel, rank }`, and `faction` from
--- `nfac[id]` (`"A"`, `"H"` or `"AH"`; nil when ForeverDB names none).
---
--- @param npcID number
--- @return table|nil
function lib.NPC(npcID)
  npcID = id(npcID)
  if not npcID then return nil end
  local r = row("npc", npcID)
  if not r then return nil end
  local fac = tbl("nfac")
  local f = fac and fac[npcID]
  return {
    id = npcID, name = str(r[1]), subname = str(r[2]), minLevel = num(r[3]), maxLevel = num(r[4]),
    rank = num(r[5]), faction = (type(f) == "string" and FACTIONS[f]) and f or nil,
  }
end

--- An item: a new table `{ id, name, quality, requiredLevel, itemLevel, classID, subclassID,
--- inventoryType, icon }`, or nil.
---
--- From `item[id] = { name, quality, reqLevel, itemLevel, class, subclass, inventoryType, icon,
--- ... }`; the positions past the icon are not read in this version.
---
--- @param itemID number
--- @return table|nil
function lib.Item(itemID)
  itemID = id(itemID)
  if not itemID then return nil end
  local r = row("item", itemID)
  if not r then return nil end
  return {
    id = itemID, name = str(r[1]), quality = num(r[2]), requiredLevel = num(r[3]),
    itemLevel = num(r[4]), classID = num(r[5]), subclassID = num(r[6]), inventoryType = num(r[7]),
    icon = num(r[8]),
  }
end

local KINDS = { c = "npc", o = "object" }

--- `{ kind, id }` rows from a `qg` / `qe` list of "c<id>" and "o<id>" strings; others skipped.
local function actors(name, questID)
  local out = {}
  local list = row(name, questID)
  if not list then return out end
  for _, s in ipairs(list) do
    if type(s) == "string" then
      local kind, n = KINDS[s:sub(1, 1)], id(tonumber(s:sub(2)))
      if kind and n then out[#out + 1] = { kind = kind, id = n } end
    end
  end
  return out
end

--- A quest: a new table `{ id, title, level, minLevel, givers, enders }`, or nil.
---
--- From `quest[id] = { title, level, minLevel }`. `givers` and `enders` are arrays (empty when
--- ForeverDB names none) of `{ kind = "npc" | "object", id = n }`, from `qg[id]` and `qe[id]`.
---
--- @param questID number
--- @return table|nil
function lib.Quest(questID)
  questID = id(questID)
  if not questID then return nil end
  local r = row("quest", questID)
  if not r then return nil end
  return {
    id = questID, title = str(r[1]), level = num(r[2]), minLevel = num(r[3]),
    givers = actors("qg", questID), enders = actors("qe", questID),
  }
end

local function byChance(a, b)
  local ca, cb = a.chance or -1, b.chance or -1
  if ca ~= cb then return ca > cb end
  return a.id < b.id
end

--- `{ id, chance }` rows from a flat `{ sourceId, chancePer10000, ... }` list, most likely first.
local function sources(name, itemID)
  local out = {}
  local list = row(name, itemID)
  if not list then return out end
  for i = 1, #list - 1, 2 do
    local src, c = id(list[i]), num(list[i + 1])
    if src then
      out[#out + 1] = { id = src, chance = (c and c > 0 and c <= CHANCE_SCALE) and c / CHANCE_SCALE or nil }
    end
  end
  table.sort(out, byChance)
  return out
end

--- Where an item comes from: a new table `{ creatures, objects, items, vendors, worldMinLevel }`,
--- or nil when ForeverDB names no source at all.
---
--- `creatures` (from `drop`), `objects` (`odrop`) and `items` (`idrop`, the containers it comes
--- out of) are arrays of `{ id = sourceID, chance = 0..1 }`, the most likely first (an unknown
--- rate last, then by id). `chance` is the database's per-10000 figure over 10000, and nil where it
--- says 0 (the rate unknown) or anything outside 0..10000. `vendors` is an array of creature ids
--- (`vend`). `worldMinLevel` is the minimum level of a world drop (`world`), or nil. Every array
--- is present, empty when it has none.
---
--- @param itemID number
--- @return table|nil
function lib.ItemSources(itemID)
  itemID = id(itemID)
  if not itemID or not lib.Available() then return nil end
  local out = {
    creatures = sources("drop", itemID), objects = sources("odrop", itemID),
    items = sources("idrop", itemID), vendors = {},
  }
  for _, n in ipairs(row("vend", itemID) or {}) do
    if id(n) then out.vendors[#out.vendors + 1] = n end
  end
  local world = tbl("world")
  out.worldMinLevel = world and num(world[itemID]) or nil
  if #out.creatures + #out.objects + #out.items + #out.vendors == 0 and not out.worldMinLevel then
    return nil
  end
  return out
end

--- The lowest price any vendor was seen asking for an item: `price, npcID` (copper; exactly two
--- values), or nil when ForeverDB has no price for it.
---
--- Reads `vend[item]` for the vendors and `vp[npc][item] = { price, seen }` for each one's price;
--- the first vendor in `vend`'s order wins a tie.
---
--- @param itemID number
--- @return number|nil price, number|nil npcID
function lib.VendorPrice(itemID)
  itemID = id(itemID)
  if not itemID then return nil, nil end
  local vendors, prices = row("vend", itemID), tbl("vp")
  if not (vendors and prices) then return nil, nil end
  local best, bestNpc
  for _, npc in ipairs(vendors) do
    local byItem = id(npc) and prices[npc]
    local r = type(byItem) == "table" and byItem[itemID]
    local price = type(r) == "table" and num(r[1])
    if price and price >= 0 and (not best or price < best) then best, bestNpc = price, npc end
  end
  return best, bestNpc
end

local PREFIX = { npc = "c", object = "o" }

--- A coordinate on the database's 0..1000 scale, or nil.
local function coord(v)
  v = num(v)
  if v and v >= 0 and v <= COORD_SCALE then return v end
  return nil
end

--- One map's flat `{ x, y, x, y, ... }` list as new `{ x = 0..1, y = 0..1 }` points, a pair with
--- either value off the scale skipped; nil when no pair is usable.
local function mapPoints(coords)
  local points = {}
  for i = 1, #coords - 1, 2 do
    local x, y = coord(coords[i]), coord(coords[i + 1])
    if x and y then points[#points + 1] = { x = x / COORD_SCALE, y = y / COORD_SCALE } end
  end
  if #points == 0 then return nil end
  return points
end

--- Where a creature or an object stands: a new table `{ [uiMapID] = { { x, y }, ... } }` with x and
--- y on 0..1 (the database's 0..1000 over 1000), or nil when ForeverDB has no spot for it.
---
--- `kind` is `"npc"` or `"object"`; anything else is no answer. From
--- `spm["c<id>" | "o<id>"] = { [uiMap] = { x, y, x, y, ... } }`; each point is `{ x = x, y = y }`,
--- and a pair with either value outside 0..1000 is skipped.
---
--- @param kind string
--- @param sourceID number
--- @return table|nil
function lib.Spots(kind, sourceID)
  local prefix = type(kind) == "string" and PREFIX[kind]
  sourceID = id(sourceID)
  if not (prefix and sourceID) then return nil end
  local maps = row("spm", prefix .. sourceID)
  if not maps then return nil end
  local out, any = {}, false
  for mapID, coords in pairs(maps) do
    local points = id(mapID) and type(coords) == "table" and mapPoints(coords)
    if points then out[mapID], any = points, true end
  end
  if not any then return nil end
  return out
end

--- What a trainer teaches: a new table `{ [spellName] = { cost, level } }` (cost in copper, the
--- level the spell needs), or nil when ForeverDB names nothing for that creature.
---
--- From `trn[npc] = { [spellName] = { cost, level, ... } }`; the positions past the level are not
--- read in this version.
---
--- @param npcID number
--- @return table|nil
function lib.TrainerSpells(npcID)
  npcID = id(npcID)
  if not npcID then return nil end
  local spells = row("trn", npcID)
  if not spells then return nil end
  local out, any = {}, false
  for name, r in pairs(spells) do
    if str(name) and type(r) == "table" then
      out[name], any = { cost = num(r[1]), level = num(r[2]) }, true
    end
  end
  if not any then return nil end
  return out
end
