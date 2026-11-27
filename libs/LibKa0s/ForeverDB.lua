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
-- names, and its layout is its own. The reading lives here once (LibKa0s#105): one place knows the
-- row positions, one place decides when the 12 MB load happens, and one place answers plainly when
-- the addon is absent, disabled, old or reshaped. Three Ka0s addons read it at first; from v1.116.0
-- Drop Watcher is the only one (Skill Master and Outfitter Reborn stopped in that run). Minor 2 adds
-- the lookups Drop Watcher's Item Search makes: SearchItems (by name), QuestsForItem, RewardFrom,
-- StartsQuest and SkinnedFrom. Minor 3 adds Object, an object's name, so a host names an object
-- source rather than drawing its id. Minor 4 fills the spots the base `spm` slice lacks: Spots reads
-- ForeverDB_Full's `spz` when that addon is loaded, then `spm`, then the base `spw` world
-- coordinates converted to map positions by WorldToMap over ForeverDB's own `umaa` and `zbord`
-- tables, and answers which table it came from; VendorPriceAt and VendorPrice read `vendx` prices
-- beside `vp`; FullStatus, LoadFull and FullCost load ForeverDB_Full on a host's demand.
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
--      ONLY caller of C_AddOns.LoadAddOn("ForeverDB"), once a session. ForeverDB_Full loads only
--      when a host calls LoadFull(), its one caller of C_AddOns.LoadAddOn("ForeverDB_Full"), never
--      in combat. Nothing loads at file load or at login. IsLoaded(), Status() and FullStatus()
--      never load: they are the diagnostics' reads.
--   2. WoW Forever only. "Is this WoW Forever" is answered by LibKa0s-Compat-1.0's IsForever,
--      looked up at call time (clients-§3); without Compat the answer is "not Forever". On any other
--      client every lookup answers nil and Available() answers false, "client".
--   3. Globals are read BARE and at CALL time (ForeverDB, ForeverDBFull, C_AddOns,
--      InCombatLockdown, debugprofilestop), never captured at load and
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
-- ForeverDB's base addon and, from minor 4, ForeverDB_Full's `spz` once a host has loaded it;
-- ForeverDB_Locales is not read.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-ForeverDB-1.0", 4
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.ForeverDB = MINOR

local ADDON = "ForeverDB"
local FULL  = "ForeverDB_Full"
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

--- Whether the client knows the addon (`name`, default ForeverDB), without loading it.
local function exists(A, name)
  name = name or ADDON
  if not A then return false end
  if A.DoesAddOnExist then return A.DoesAddOnExist(name) == true end
  if A.GetAddOnInfo then
    local known, _, _, _, reason = A.GetAddOnInfo(name)
    return known ~= nil and reason ~= "MISSING"
  end
  return false
end

local function loadedNow(A, name)
  if not (A and A.IsAddOnLoaded) then return false end
  return A.IsAddOnLoaded(name or ADDON) and true or false
end

local function tocVersion(A)
  if not (A and A.GetAddOnMetadata) then return nil end
  return str(A.GetAddOnMetadata(ADDON, "Version"))
end

-- -- Available ----------------------------------------------------------------------------------

local cached   -- { ok, reason } once Available() has answered; cleared only by __reset
local fullCached, fullCost   -- LoadFull()'s kept { ok, reason } and its measured { kb, ms } (minor 4)
-- The session indexes (minor 2), each built on its first use from the table it names and kept with
-- that table, so a database the client swapped in is indexed afresh: `nameIndex` for SearchItems
-- ({ src = item, ids, names, lens }), `questIndex` for QuestsForItem ({ src = qx, byItem }).
local nameIndex, questIndex
-- Minor 4: `geoIndex` is WorldToMap's parsed `umaa` + `zbord` ({ src, zb, byContinent }), and
-- `spwMemo` Spots' converted `spw` answers ({ src, geo, byKey }), each kept with the tables it was
-- built from.
local geoIndex, spwMemo

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

--- What the diagnostics report prints: a new table `{ present, loaded, version, build, hash, full,
--- fullCost }`. `present` (the client knows the addon) and `loaded` are booleans; `version` is the
--- TOC Version, read without loading and only when `present`; `build` and `hash` are the
--- database's `meta` fields, only when it is loaded and its global is a table. `full` (minor 4) is
--- FullStatus()'s answer, and `fullCost` a new copy of FullCost()'s, nil before this library loaded
--- ForeverDB_Full. Never loads anything, and is not gated on the client.
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
  out.full, out.fullCost = lib.FullStatus(), lib.FullCost()
  return out
end

--- Forget the cached answer and the session indexes, so the next Available() asks again. For
--- tests; a host never calls it.
function lib.__reset()
  cached, nameIndex, questIndex = nil, nil, nil
  fullCached, fullCost, geoIndex, spwMemo = nil, nil, nil, nil
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

--- An object (a chest, a herb, a vein, a crate): a new table `{ id, name }`, or nil (minor 3).
---
--- From `obj[id] = { name, ... }`; the positions past the name are not read in this version. A row
--- that is not a table, or whose name is not a string, is no answer: an object's one fact here is
--- its name, so a host that would draw "Object <id>" leaves the source out instead.
---
--- @param objectID number
--- @return table|nil
function lib.Object(objectID)
  objectID = id(objectID)
  if not objectID then return nil end
  local r = row("obj", objectID)
  if not r then return nil end
  local name = str(r[1])
  if not name then return nil end
  return { id = objectID, name = name }
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

--- A price in copper, or nil: a number that is not negative.
local function copper(v)
  v = num(v)
  if v and v >= 0 then return v end
  return nil
end

--- What one vendor asks for one item: `price, origin` (copper; exactly two values), or nil, nil
--- (minor 4).
---
--- From `vendx[npc][item].p` (origin `"vendx"`), else `vp[npc][item][1]` (origin `"vp"`). A price
--- that is not a number, or is negative, is no answer from that table.
---
--- @param npcID number
--- @param itemID number
--- @return number|nil price, string|nil origin
function lib.VendorPriceAt(npcID, itemID)
  npcID, itemID = id(npcID), id(itemID)
  if not (npcID and itemID) then return nil, nil end
  local vx = row("vendx", npcID)
  local r = vx and vx[itemID]
  local price = type(r) == "table" and copper(r.p)
  if price then return price, "vendx" end
  local vp = row("vp", npcID)
  r = vp and vp[itemID]
  price = type(r) == "table" and copper(r[1])
  if price then return price, "vp" end
  return nil, nil
end

--- The lowest price any vendor was seen asking for an item: `price, npcID` (copper; exactly two
--- values), or nil when ForeverDB has no price for it.
---
--- Reads `vend[item]` for the vendors and, for each one, VendorPriceAt's price (`vendx`, then
--- `vp`; from minor 4, so the answer can be lower than minor 3's); the first vendor in `vend`'s
--- order wins a tie.
---
--- @param itemID number
--- @return number|nil price, number|nil npcID
function lib.VendorPrice(itemID)
  itemID = id(itemID)
  if not itemID then return nil, nil end
  local vendors = row("vend", itemID)
  if not vendors then return nil, nil end
  local best, bestNpc
  for _, npc in ipairs(vendors) do
    local price = id(npc) and lib.VendorPriceAt(npc, itemID)
    if price and (not best or price < best) then best, bestNpc = price, npc end
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

--- One `spm`-shaped row (`{ [uiMap] = { x, y, x, y, ... } }`) as a new `{ [uiMap] = points }`,
--- nil when no map has a usable point.
local function mapSpots(maps)
  if type(maps) ~= "table" then return nil end
  local out, any = {}, false
  for mapID, coords in pairs(maps) do
    local points = id(mapID) and type(coords) == "table" and mapPoints(coords)
    if points then out[mapID], any = points, true end
  end
  if not any then return nil end
  return out
end

--- Row `key` of ForeverDB_Full's table `name`, when the global and both are tables (minor 4).
local function fullRow(name, key)
  local F = ForeverDBFull
  if type(F) ~= "table" then return nil end
  local t = F[name]
  local r = type(t) == "table" and t[key]
  if type(r) == "table" then return r end
  return nil
end

-- -- minor 4: world coordinates to map positions ------------------------------------------------

-- `umaa` positions: 1 the uiMap, 2 the continent, 3 the area id, then the bounds read here by name
-- (10 and 13, the Z bounds, are not read).
local UMAA_MAP, UMAA_CONT, UMAA_AREA = 1, 2, 3
local UMAA_BOUNDS = { UMINX = 4, UMINY = 5, UMAXX = 6, UMAXY = 7, MINX = 8, MINY = 9, MAXX = 11, MAXY = 12 }

--- A continent number (0 is one), or nil.
local function continentOf(v)
  v = num(v)
  if v and v >= 0 and v == math.floor(v) then return v end
  return nil
end

--- One `zbord` polygon (a flat `{ x, y, ... }` on 0..1000, three points or more) as
--- `{ pts, minX, minY, maxX, maxY }`, or nil when it is short or holds a value that is no number.
local function polygon(flat)
  if type(flat) ~= "table" or #flat < 6 then return nil end
  local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
  for i = 1, #flat - 1, 2 do
    local x, y = num(flat[i]), num(flat[i + 1])
    if not (x and y) then return nil end
    if x < minX then minX = x end
    if x > maxX then maxX = x end
    if y < minY then minY = y end
    if y > maxY then maxY = y end
  end
  return { pts = flat, minX = minX, minY = minY, maxX = maxX, maxY = maxY }
end

--- The polygons of `zbord[areaID]` for `continent`, or nil when it has none usable.
local function zonePolygons(zbord, areaID, continent)
  local z = zbord and areaID and zbord[areaID]
  if type(z) ~= "table" or type(z.m) ~= "table" then return nil end
  local c = num(z.c)
  if c and c ~= continent then return nil end
  local out = {}
  for _, flat in ipairs(z.m) do out[#out + 1] = polygon(flat) end
  if #out == 0 then return nil end
  return out
end

--- A `umaa` row's eight bounds by name, or nil when any one is not a number.
local function bounds(r)
  local u = {}
  for key, at in pairs(UMAA_BOUNDS) do
    u[key] = num(r[at])
    if u[key] == nil then return nil end
  end
  return u
end

--- One `umaa` row as a region, or nil when any field the conversion needs is malformed.
local function region(r, zbord)
  if type(r) ~= "table" then return nil end
  local u, mapID, cont = bounds(r), id(r[UMAA_MAP]), continentOf(r[UMAA_CONT])
  if not (u and mapID and cont) then return nil end
  if u.MAXX <= u.MINX or u.MAXY <= u.MINY or u.UMAXX <= u.UMINX or u.UMAXY <= u.UMINY then return nil end
  local area = num(r[UMAA_AREA])
  return {
    map = mapID, cont = cont, uMinX = u.UMINX, uMinY = u.UMINY, uMaxX = u.UMAXX, uMaxY = u.UMAXY,
    minX = u.MINX, minY = u.MINY, maxX = u.MAXX, maxY = u.MAXY,
    size = (u.MAXX - u.MINX) * (u.MAXY - u.MINY), polys = zonePolygons(zbord, area, cont),
  }
end

local function bySize(a, b)
  if a.size ~= b.size then return a.size < b.size end
  return a.map < b.map
end

--- The parsed `umaa` + `zbord`, built once per pair of tables: each continent's regions, smallest
--- first. Nil when ForeverDB is unavailable or has no `umaa`.
local function geoIndexFor()
  local umaa = tbl("umaa")
  if not umaa then return nil end
  local zbord = tbl("zbord")
  if geoIndex and geoIndex.src == umaa and geoIndex.zb == zbord then return geoIndex end
  local byContinent = {}
  for _, r in pairs(umaa) do
    local reg = region(r, zbord)
    if reg then
      local list = byContinent[reg.cont] or {}
      byContinent[reg.cont] = list
      list[#list + 1] = reg
    end
  end
  for _, list in pairs(byContinent) do table.sort(list, bySize) end
  geoIndex = { src = umaa, zb = zbord, byContinent = byContinent }
  return geoIndex
end

--- Even-odd point in polygon over a flat `{ x, y, ... }`.
local function inside(pts, px, py)
  local n, hit = #pts - #pts % 2, false
  local jx, jy = pts[n - 1], pts[n]
  for i = 1, n - 1, 2 do
    local ix, iy = pts[i], pts[i + 1]
    if (iy > py) ~= (jy > py) and px < (jx - ix) * (py - iy) / (jy - iy) + ix then hit = not hit end
    jx, jy = ix, iy
  end
  return hit
end

--- Whether any of `polys` holds the point (bounding box first).
local function inAny(polys, px, py)
  for _, p in ipairs(polys) do
    if px >= p.minX and px <= p.maxX and py >= p.minY and py <= p.maxY and inside(p.pts, px, py) then
      return true
    end
  end
  return false
end

--- The point's position on `reg`'s map, x and y on the map's 0..1 (world Y runs east to west and
--- world X south to north, so both are read from the region's max edge).
local function project(reg, wx, wy)
  local u = (reg.maxY - wy) / (reg.maxY - reg.minY)
  local v = (reg.maxX - wx) / (reg.maxX - reg.minX)
  return reg.uMinX + u * (reg.uMaxX - reg.uMinX), reg.uMinY + v * (reg.uMaxY - reg.uMinY)
end

local function holds(reg, wx, wy)
  return wx >= reg.minX and wx <= reg.maxX and wy >= reg.minY and wy <= reg.maxY
end

--- Where a world position lands on a map: `uiMapID, x, y` (x and y on 0..1), or nil (minor 4).
---
--- Pure: reads ForeverDB's `umaa` (one row per map assignment: `{ uiMap, continent, areaID,
--- uiMinX, uiMinY, uiMaxX, uiMaxY, minX, minY, minZ, maxX, maxY, maxZ }`) and `zbord[areaID] =
--- { c = continent, m = { polygon, ... } }` (each polygon a flat `{ x, y, ... }` on the zone's
--- 0..1000 map scale), and no client map API. Of the `umaa` rows on `continent` whose world region
--- holds the point, the smallest whose `zbord` polygon holds the converted point (even-odd) wins;
--- else the smallest with no `zbord` entry (normally the continent's own map); else nil. A
--- malformed row or polygon is skipped.
---
--- @param continent number
--- @param worldX number
--- @param worldY number
--- @return number|nil uiMapID, number|nil x, number|nil y
function lib.WorldToMap(continent, worldX, worldY)
  continent, worldX, worldY = continentOf(continent), num(worldX), num(worldY)
  if not (continent and worldX and worldY) then return nil end
  local geo = geoIndexFor()
  local list = geo and geo.byContinent[continent]
  if not list then return nil end
  local fbMap, fbX, fbY
  for _, reg in ipairs(list) do
    if holds(reg, worldX, worldY) then
      local x, y = project(reg, worldX, worldY)
      if reg.polys then
        if inAny(reg.polys, x * COORD_SCALE, y * COORD_SCALE) then return reg.map, x, y end
      elseif not fbMap then
        fbMap, fbX, fbY = reg.map, x, y
      end
    end
  end
  return fbMap, fbX, fbY
end

--- One `spw` entry (`{ { continent, worldX, worldY, worldX, worldY, ... }, ... }`) converted point
--- by point and grouped by map, or false when no point converts.
local function convertRuns(runs)
  local out, any = {}, false
  for _, run in ipairs(runs) do
    local list = type(run) == "table" and run or {}
    for i = 2, #list - 1, 2 do
      local mapID, x, y = lib.WorldToMap(list[1], list[i], list[i + 1])
      if mapID and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        local points = out[mapID] or {}
        out[mapID], any = points, true
        points[#points + 1] = { x = x, y = y }
      end
    end
  end
  return any and out or false
end

--- A deep copy of a `{ [map] = { { x, y }, ... } }` answer.
local function copySpots(spots)
  local out = {}
  for mapID, points in pairs(spots) do
    local list = {}
    for i, p in ipairs(points) do list[i] = { x = p.x, y = p.y } end
    out[mapID] = list
  end
  return out
end

--- `spw[key]` converted, memoized per key for the session with the `spw` and geometry it was
--- built from; a fresh copy each call, or nil.
local function worldSpots(key)
  local spw = tbl("spw")
  local runs = spw and spw[key]
  if type(runs) ~= "table" then return nil end
  local geo = geoIndexFor()
  if not geo then return nil end
  if not (spwMemo and spwMemo.src == spw and spwMemo.geo == geo) then
    spwMemo = { src = spw, geo = geo, byKey = {} }
  end
  local got = spwMemo.byKey[key]
  if got == nil then
    got = convertRuns(runs)
    spwMemo.byKey[key] = got
  end
  if not got then return nil end
  return copySpots(got)
end

--- Where a creature or an object stands: a new table `{ [uiMapID] = { { x, y }, ... } }` with x and
--- y on 0..1, and the table it came from, `origin` (`"spz"`, `"spm"` or `"spw"`; minor 4); nil
--- when ForeverDB has no spot for it.
---
--- `kind` is `"npc"` or `"object"`; anything else is no answer. The key is `"c<id>"` or
--- `"o<id>"`, read in this order: ForeverDB_Full's `spz` when that addon is loaded (the shape of
--- `spm`); `spm[key] = { [uiMap] = { x, y, x, y, ... } }` on 0..1000, each pair over 1000 and a pair
--- with either value outside 0..1000 skipped; then `spw[key]`, world coordinates converted point by
--- point through WorldToMap and grouped by the map each lands on (a point on no map skipped),
--- memoized per key for the session and copied out fresh.
---
--- @param kind string
--- @param sourceID number
--- @return table|nil spots, string|nil origin
function lib.Spots(kind, sourceID)
  local prefix = type(kind) == "string" and PREFIX[kind]
  sourceID = id(sourceID)
  if not (prefix and sourceID) or not lib.Available() then return nil end
  local key = prefix .. sourceID
  local out = mapSpots(fullRow("spz", key))
  if out then return out, "spz" end
  out = mapSpots(row("spm", key))
  if out then return out, "spm" end
  out = worldSpots(key)
  if out then return out, "spw" end
  return nil
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

-- -- minor 2: Item Search's lookups -------------------------------------------------------------

local SEARCH_LIMIT = 50   -- SearchItems' default row count
local SEARCH_MIN   = 2    -- the shortest query SearchItems answers
local OBJECTIVES   = 10   -- qx's item-objectives position
local PRE_A, PRE_B = 3, 4 -- qx's two prequest positions

--- `{ id, title, level }` for a quest, a new table; title and level nil when `quest` has no row.
local function questBrief(questID)
  local r = row("quest", questID)
  return { id = questID, title = r and str(r[1]) or nil, level = r and num(r[2]) or nil }
end

--- The name index over `item`, built once per item table: parallel arrays of ids, lower-cased
--- names and name lengths, in id order. Nil when ForeverDB is unavailable.
local function nameIndexFor()
  local items = tbl("item")
  if not items then return nil end
  if nameIndex and nameIndex.src == items then return nameIndex end
  local order = {}
  for itemID, r in pairs(items) do
    if id(itemID) and type(r) == "table" and str(r[1]) then order[#order + 1] = itemID end
  end
  table.sort(order)
  local names, lens = {}, {}
  for i, itemID in ipairs(order) do
    local name = items[itemID][1]
    names[i], lens[i] = name:lower(), #name
  end
  nameIndex = { src = items, ids = order, names = names, lens = lens }
  return nameIndex
end

--- One search row, a new table read off `item` at answer time, or nil when the row is gone.
local function searchRow(itemID)
  local r = row("item", itemID)
  if not (r and str(r[1])) then return nil end
  return { id = itemID, name = r[1], quality = num(r[2]), icon = num(r[8]), requiredLevel = num(r[3]) }
end

local function searchLimit(limit)
  limit = num(limit)
  if limit and limit >= 1 then return math.floor(limit) end
  return SEARCH_LIMIT
end

--- The index positions whose name holds `needle` (plain find), prefix matches first, then
--- shorter names, then id (the index is in id order, so the position breaks the tie).
local function matches(index, needle)
  local hits, prefix = {}, {}
  for i = 1, #index.ids do
    local at = index.names[i]:find(needle, 1, true)
    if at then hits[#hits + 1] = i; prefix[i] = at == 1 end
  end
  table.sort(hits, function(a, b)
    if prefix[a] ~= prefix[b] then return prefix[a] end
    if index.lens[a] ~= index.lens[b] then return index.lens[a] < index.lens[b] end
    return a < b
  end)
  return hits
end

--- Items whose name contains `query`: a new array of at most `limit` (default 50) new rows
--- `{ id, name, quality, icon, requiredLevel }`, `{}` when nothing matches or ForeverDB is
--- unavailable.
---
--- Case-insensitive and plain (no patterns); `query` is trimmed, and under two characters answers
--- `{}`. Prefix matches come first, then shorter names, then id. A `query` of digits alone also
--- matches the item with that id, first. The first call builds a lower-cased name index over
--- `item`, kept for the session; later calls only scan it.
---
--- @param query string
--- @param limit number|nil
--- @return table
function lib.SearchItems(query, limit)
  local out = {}
  if type(query) ~= "string" then return out end
  query = query:match("^%s*(.-)%s*$")
  if #query < SEARCH_MIN then return out end
  local index = nameIndexFor()
  if not index then return out end
  limit = searchLimit(limit)
  local exact = query:find("^%d+$") and id(tonumber(query)) or nil
  local first = exact and searchRow(exact)
  if first then out[1] = first end
  for _, i in ipairs(matches(index, query:lower())) do
    if #out >= limit then break end
    local itemID = index.ids[i]
    if itemID ~= exact then out[#out + 1] = searchRow(itemID) end
  end
  return out
end

--- The item -> quests index over `qx`'s item objectives, built once per qx table: each item's
--- quest ids, ascending and without repeats. Nil when ForeverDB is unavailable.
local function questIndexFor()
  local qx = tbl("qx")
  if not qx then return nil end
  if questIndex and questIndex.src == qx then return questIndex end
  local byItem = {}
  for questID, r in pairs(qx) do
    local list = id(questID) and type(r) == "table" and r[OBJECTIVES]
    for _, itemID in ipairs(type(list) == "table" and list or {}) do
      itemID = id(itemID)
      if itemID then
        local quests = byItem[itemID] or {}
        byItem[itemID] = quests
        if quests[#quests] ~= questID then quests[#quests + 1] = questID end
      end
    end
  end
  for _, quests in pairs(byItem) do table.sort(quests) end
  questIndex = { src = qx, byItem = byItem }
  return questIndex
end

--- A race or class mask, or nil when it is absent, not a number, or 0 (any).
local function mask(v)
  v = num(v)
  if v and v > 0 then return v end
  return nil
end

--- qx fields 3 and 4 merged into one new array of quest ids, in order, without repeats.
local function preQuests(r)
  local out, seen = {}, {}
  for _, field in ipairs({ r[PRE_A], r[PRE_B] }) do
    for _, q in ipairs(type(field) == "table" and field or {}) do
      q = id(q)
      if q and not seen[q] then seen[q], out[#out + 1] = true, q end
    end
  end
  return out
end

--- Quests with the item among their objectives: a new array, by quest id, of new rows
--- `{ id, title, level, minLevel, races, classes, preQuests }`; `{}` when none or ForeverDB is
--- unavailable.
---
--- From `qx[quest]`: field 10 the item objectives, fields 1 and 2 the race and class masks (nil
--- means any; a 0 reads as nil), fields 3 and 4 the prequests (merged into `preQuests`, possibly
--- empty). `title`, `level` and `minLevel` are `quest[id]`'s, nil when it has no row. The first call
--- builds the item -> quests index over `qx`, kept for the session.
---
--- @param itemID number
--- @return table
function lib.QuestsForItem(itemID)
  local out = {}
  itemID = id(itemID)
  local index = itemID and questIndexFor()
  if not index then return out end
  for _, questID in ipairs(index.byItem[itemID] or {}) do
    local r, q = row("qx", questID), row("quest", questID)
    if r then
      out[#out + 1] = {
        id = questID, title = q and str(q[1]) or nil, level = q and num(q[2]) or nil,
        minLevel = q and num(q[3]) or nil, races = mask(r[1]), classes = mask(r[2]),
        preQuests = preQuests(r),
      }
    end
  end
  return out
end

--- Quests that reward the item: a new array of new `{ id, title, level }`, in `rew`'s order
--- without repeats; `{}` when none or ForeverDB is unavailable.
---
--- @param itemID number
--- @return table
function lib.RewardFrom(itemID)
  local out, seen = {}, {}
  itemID = id(itemID)
  if not itemID then return out end
  for _, q in ipairs(row("rew", itemID) or {}) do
    q = id(q)
    if q and not seen[q] then seen[q], out[#out + 1] = true, questBrief(q) end
  end
  return out
end

--- The quest the item starts: a new `{ id, title, level }`, or nil (from `start[item]`).
---
--- @param itemID number
--- @return table|nil
function lib.StartsQuest(itemID)
  itemID = id(itemID)
  if not itemID then return nil end
  local starts = tbl("start")
  local questID = starts and id(starts[itemID])
  if not questID then return nil end
  return questBrief(questID)
end

--- The creatures the item is skinned from: a new array of new `{ id, name, chance }`, the most
--- likely first as ItemSources sorts (an unknown rate last, then id); `{}` when none or ForeverDB
--- is unavailable.
---
--- From the flat `skin[item] = { npcId, chancePer10000, ... }`; `chance` is 0..1, nil where the
--- database says 0 (the rate unknown) or anything outside 0..10000; `name` is `npc[id]`'s, or nil.
---
--- @param itemID number
--- @return table
function lib.SkinnedFrom(itemID)
  itemID = id(itemID)
  if not itemID then return {} end
  local out = sources("skin", itemID)
  for _, src in ipairs(out) do
    local r = row("npc", src.id)
    src.name = r and str(r[1]) or nil
  end
  return out
end

-- -- minor 4: ForeverDB_Full, on a host's demand ----------------------------------------------

--- Whether the client says a LoadOnDemand addon cannot load now, and why: nil when it can, else
--- `"missing"`, `"base"` (a dependency is missing or disabled) or `"disabled"`.
local function fullRefusal(A)
  if not exists(A, FULL) then return "missing" end
  if not A.GetAddOnInfo then return nil end
  local _, _, _, loadable, reason = A.GetAddOnInfo(FULL)
  if loadable or reason == nil or reason == "DEMAND_LOADED" then return nil end
  if reason == "MISSING" then return "missing" end
  if type(reason) == "string" and reason:find("^DEP_") then return "base" end
  return "disabled"
end

--- Whether ForeverDB_Full could be loaded, without loading anything (minor 4): `"loaded"` (its
--- global is a table), `"available"` (installed and loadable), `"missing"`, `"disabled"`,
--- `"client"` (not WoW Forever) or `"base"` (the base ForeverDB is not available: not installed,
--- a dependency the client reports missing or disabled, or an Available() that already answered
--- false). Never loads anything, never calls Available().
---
--- @return string
function lib.FullStatus()
  if not isForever() then return "client" end
  local A = addons()
  if loadedNow(A, FULL) and type(ForeverDBFull) == "table" then return "loaded" end
  local refusal = fullRefusal(A)
  if refusal == "missing" then return "missing" end
  if refusal == "base" or not exists(A) or (cached and not cached[1]) then return "base" end
  return refusal or "available"
end

--- The one load of ForeverDB_Full, measured: `ok, reason`.
local function loadFull(A)
  local kb0 = collectgarbage("count")
  local clock = debugprofilestop
  local t0 = type(clock) == "function" and clock() or nil
  local loaded, reason = A.LoadAddOn(FULL)
  if not loaded then return false, str(reason) or "failed" end
  local ms = t0 and clock() - t0 or nil
  fullCost = { kb = math.max(0, collectgarbage("count") - kb0), ms = ms }
  if type(ForeverDBFull) ~= "table" then return false, "reshaped" end
  return true, nil
end

--- Load ForeverDB_Full, the complete database (some 20 MB): `ok, reason` (exactly two values;
--- minor 4).
---
--- The ONLY caller of `C_AddOns.LoadAddOn("ForeverDB_Full")`. It refuses, without caching, with
--- `"combat"` while InCombatLockdown() answers true, so a later call can try again; then with
--- `"client"` off WoW Forever, `"base"` unless Available() answers true (that call may load the base
--- addon), and `"missing"` or `"disabled"` as FullStatus() reports. Otherwise it loads once a
--- session (nothing, when another addon already loaded it) and keeps the answer: `true, nil`, the
--- client's load reason, or `"reshaped"` when `ForeverDBFull` is still not a table. A load it made
--- is measured for FullCost(): `collectgarbage("count")` before and after, and `debugprofilestop()`
--- when the client has it. When to call it is the host's policy, never this library's.
---
--- @return boolean ok, string|nil reason
function lib.LoadFull()
  if fullCached then return fullCached[1], fullCached[2] end
  local combat = InCombatLockdown
  if type(combat) == "function" and combat() then return false, "combat" end
  if not isForever() then return false, "client" end
  if not lib.Available() then return false, "base" end
  local status = lib.FullStatus()
  if status ~= "loaded" and status ~= "available" then return false, status end
  local ok, reason = true, nil
  if status ~= "loaded" then ok, reason = loadFull(addons()) end
  fullCached = { ok, reason }
  return ok, reason
end

--- What this library's load of ForeverDB_Full cost: a new `{ kb = n, ms = n | nil }` (the Lua heap
--- it added, in KB, and the time, in ms, when the client has `debugprofilestop`), or nil before
--- LoadFull() loaded it (minor 4).
---
--- @return table|nil
function lib.FullCost()
  if not fullCost then return nil end
  return { kb = fullCost.kb, ms = fullCost.ms }
end
