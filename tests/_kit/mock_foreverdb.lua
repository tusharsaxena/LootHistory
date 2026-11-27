-- testkit/mock_foreverdb.lua -- the kit's opt-in fake of ForeverDB, the WoW Forever data addon that
-- LibKa0s-ForeverDB-1.0 reads (revision 61, LibKa0s#105). Revision 63 adds the rows Item Search's
-- lookups read (ForeverDB minor 2): `qx`, `rew`, `start` and `skin`, three more quests and five more
-- items, all invented like the rest. Revision 64 adds the `obj` rows ForeverDB minor 3's Object reads:
-- two objects that share a name, one with no name and one whose row is not a table, and one more
-- item (the relic) that drops from all four, so a host can prove it merges by name and drops the
-- nameless. Revision 65 adds what ForeverDB minor 4 reads: an invented continent in `umaa` (its own
-- map and two overlapping zone maps) with `zbord` polygons for the two zones, `spw` world
-- coordinates for one more creature (the wanderer, which has no `spm` row) with points in each
-- zone, in the overlap and on the continent map alone, a `vendx` price, and a fake ForeverDB_Full
-- (opts.full) whose load installs `ForeverDBFull` with an `spz` row that differs from that
-- creature's `spm` row. Every earlier row is unchanged.
--
-- Returns a MODULE. Its installer is called on a finished mock and returns a HANDLE:
--
--   local FDB = dofile("tests/_kit/mock_foreverdb.lua")
--   local fdb = FDB.install(M, { preset = "present", client = "forever" })
--   ...                                   -- a case: the first adapter lookup loads it
--   assertEqual(fdb.loads, 1)             -- how many times LoadAddOn("ForeverDB") ran
--   fdb.restore()                         -- C_AddOns, ForeverDB and the constants put back
--
-- WHY. ForeverDB is a LoadOnDemand addon: its global does not exist until something calls
-- `C_AddOns.LoadAddOn("ForeverDB")`, and the adapter promises to make that call only from its own
-- `Available()`, only once, and never at file load. A suite can only prove that against a fake that
-- counts the load and hands the global over AT the load, never before it. OPT-IN and a file of its
-- own, as mock_screen.lua is, because most suites never ask.
--
-- THE DATA IS INVENTED, every row (LICENSING). ForeverDB's data is GPL-3.0 and this kit is MIT and
-- vendored into every consumer, so no row of the real database may appear here or in any fixture
-- built on this file. What is copied is the SHAPE only: the table names, the positional layout of a
-- row, the key forms ("c<id>" for a creature and "o<id>" for an object), the 0..10000 drop-chance
-- scale (0 = rate unknown) and the 0..1000 map-coordinate scale, as ForeverDB's README documents
-- them. Every id is in 990000..990999 and every map id in 9901..9909, ranges no row of ForeverDB
-- v2026.11.24.46 uses, and the one continent number is 99, which no `umaa` row of v2026.11.25.48
-- carries; every name, polygon and world coordinate is made up.
--
-- PRESETS (opts.preset, default "present"):
--   "present"    installed; LoadAddOn answers true and puts the database on M.ForeverDB.
--   "missing"    not installed: DoesAddOnExist answers false, GetAddOnInfo's reason is "MISSING",
--                LoadAddOn answers false, "MISSING".
--   "loadfails"  installed, but LoadAddOn answers false, opts.reason (default "DISABLED").
--   "reshaped"   installed and loads, but M.ForeverDB is opts.value (default the string
--                "ForeverDB"), not a table.
--
-- OTHER OPTIONS:
--   opts.data     the database the load installs (default FDB.fixture(), a fresh copy).
--   opts.loaded   true: the addon is already loaded when the case starts (another addon loaded it),
--                 so IsAddOnLoaded answers true and M.ForeverDB is set; `loads` starts at 0.
--   opts.version  the TOC Version GetAddOnMetadata answers (default FDB.VERSION).
--   opts.client   "forever" or "retail": also sets WOW_PROJECT_ID / WOW_PROJECT_MAINLINE /
--                 WOW_PROJECT_CAMELOT on M, so a case means the same under both kit profiles;
--                 restore() puts them back. nil leaves the profile's constants alone.
--   opts.full     the ForeverDB_Full fake (revision 65), a preset of its own: nil (the default)
--                 leaves that name to the mock's own C_AddOns, as before revision 65; "missing" (not
--                 installed); "present" (installed and LoadOnDemand: GetAddOnInfo answers loadable,
--                 "DEMAND_LOADED", and LoadAddOn puts the Full database on M.ForeverDBFull);
--                 "disabled" (GetAddOnInfo answers not loadable, "DISABLED", and so does LoadAddOn);
--                 "loadfails" (loadable, but LoadAddOn answers false, opts.fullReason, default
--                 "CORRUPT"); "reshaped" (loads, but M.ForeverDBFull is the string "ForeverDBFull").
--   opts.fullData    the Full database the load installs (default FDB.fullFixture()).
--   opts.fullLoaded  true: another addon already loaded ForeverDB_Full when the case starts.
--   opts.onFullLoad  called inside LoadAddOn("ForeverDB_Full") before the global is set, so a case
--                    can advance the mock's clock or heap reading the load is measured with.
--
-- WHAT IS INSTALLED. M.C_AddOns is REPLACED by a new table that keeps every member the mock already
-- had (the consumer's own GetAddOnMetadata answers for every other addon) and adds, for the name
-- "ForeverDB" only: DoesAddOnExist, GetAddOnInfo (name, title, notes, loadable, reason, security),
-- IsAddOnLoaded (loadedOrLoading, loaded), LoadAddOn (loaded, reason) and GetAddOnMetadata. Any
-- other name falls through to what the mock had, or answers as an addon that does not exist.
--
-- THE HANDLE:
--   fdb.loads        LoadAddOn("ForeverDB") calls so far.
--   fdb.data         the database table the load installs (nil for "missing" and "loadfails").
--   fdb.preset       the preset in force.
--   fdb.loadNow()    another addon loads it now: M.ForeverDB is set, IsAddOnLoaded answers true,
--                    `loads` does not move.
--   fdb.fullLoads    LoadAddOn("ForeverDB_Full") calls so far (revision 65; 0 without opts.full).
--   fdb.fullData     the Full database that load installs (nil unless "present" or "reshaped").
--   fdb.restore()    puts back M.C_AddOns, M.ForeverDB, M.ForeverDBFull and, with opts.client, the
--                    constants.

local FDB = {}

local NAME = "ForeverDB"

--- The TOC Version the fake answers by default. Invented, in ForeverDB's own `YYYY.MM.DD.N` form.
FDB.VERSION = "2099.01.01.1"

--- The invented ids the fixture uses, by role, so a case names them rather than retyping numbers.
FDB.IDS = {
  gnoll      = 990001,   -- a creature: drops the blade, gives and ends the errand, has spots
  kobold     = 990002,   -- a creature: drops the blade at an unknown rate, no subname
  vendor     = 990003,   -- a creature: sells the blade (the dearer price), both factions
  trainer    = 990004,   -- a creature: trains two spells, sells the blade (the cheaper price)
  blade      = 990101,   -- an item with every kind of source; rewarded by the errand
  pebble     = 990102,   -- an item with no source at all
  coffer     = 990103,   -- a container item the blade comes out of
  leather    = 990104,   -- an item skinned from two creatures, an objective of two quests
  hide       = 990105,   -- an item skinned at an unknown rate, an objective of the errand
  shard      = 990106,   -- "Bladed Fixture Shard": a name that STARTS with "blade"
  cloak      = 990107,   -- "Fixture Bladeweave Cloak": a longer name holding "blade"
  letter     = 990108,   -- an item that starts the summons
  relic      = 990109,   -- "Strongbox Relic": drops from the two strongboxes, the husk and the scrap
  wanderer   = 990005,   -- a creature with spw world coordinates and no spm row (revision 65)
  errand     = 990201,   -- a quest
  hunt       = 990202,   -- a quest: needs the leather, after the errand and the summons
  summons    = 990203,   -- a quest the letter starts; no qx row
  crate      = 990301,   -- an object: drops the blade, gives the errand, has spots
  boxA       = 990302,   -- an object, "Fixture Strongbox": drops the relic, has spots on mapA
  boxB       = 990303,   -- an object, "Fixture Strongbox" too: drops the relic, has spots on mapB
  husk       = 990304,   -- an object whose row has no name: drops the relic
  scrap      = 990305,   -- an object whose row is not a table: drops the relic
  mapA       = 9901,
  mapB       = 9902,
  -- revision 65: an invented continent and its maps (umaa / zbord / spw)
  continent  = 99,       -- the continent number spw and umaa carry
  mapCont    = 9903,     -- the continent's own map: no zbord entry
  mapNorth   = 9904,     -- a zone map, world X 0..1000 and Y -500..500, with a zbord polygon
  mapSouth   = 9905,     -- a zone map, world X -600..200 and Y -500..500 (overlapping the north)
  areaNorth  = 990501,   -- the north zone's area id (umaa position 3, the zbord key)
  areaSouth  = 990502,
}

local PRESETS = { present = true, missing = true, loadfails = true, reshaped = true }
FDB.PRESETS = { "present", "missing", "loadfails", "reshaped" }

local FULL = "ForeverDB_Full"
local FULL_PRESETS = { present = true, missing = true, disabled = true, loadfails = true, reshaped = true }
FDB.FULL_PRESETS = { "present", "missing", "disabled", "loadfails", "reshaped" }

--- A fresh copy of the invented ForeverDB_Full database (revision 65): its `spz` holds the gnoll
--- on mapB (where its spm row says mapA) and the vendor, which has no spm row.
function FDB.fullFixture()
  local I = FDB.IDS
  return {
    meta = { build = "2099-01-01", counts = { spz = 2 } },
    -- spz["c<id>" | "o<id>"] = { [uiMap] = { x, y, x, y, ... } } on 0..1000, spm's shape
    spz = {
      ["c" .. I.gnoll]  = { [I.mapB] = { 600, 700 } },
      ["c" .. I.vendor] = { [I.mapA] = { 250, 500, 260, 510 } },
    },
  }
end

--- A fresh copy of the invented database, in ForeverDB's real shape (rows positional).
function FDB.fixture()
  local I = FDB.IDS
  local D = {}
  D.meta = {
    build = "2099-01-01",
    hash = "0123456789abcdef",
    counts = { npc = 5, item = 9, quest = 3, obj = 5 },
    sourceList = { { name = "fixture", title = "Invented kit fixture" } },
  }
  -- npc[id] = { name, subname, minLevel, maxLevel, rank }
  D.npc = {
    [I.gnoll]   = { "Fixture Gnoll", "Invented Pack", 10, 12, 1 },
    [I.kobold]  = { "Fixture Kobold", nil, 5, 6, 0 },
    [I.vendor]  = { "Fixture Vendor", "Invented Goods", 30, 30, 0 },
    [I.trainer] = { "Fixture Trainer", "Invented Trainer", 40, 40, 0 },
    [I.wanderer] = { "Fixture Wanderer", nil, 20, 22, 0 },
  }
  -- nfac[npc] = "A" | "H" | "AH"
  D.nfac = { [I.vendor] = "AH", [I.trainer] = "A", [I.gnoll] = "H" }
  -- item[id] = { name, quality, reqLevel, itemLevel, class, subclass, inventoryType, icon, ... }
  D.item = {
    [I.blade]  = { "Fixture Blade", 2, 10, 15, 2, 7, 13, 9990001, 1535, 0, 0, -1 },
    [I.pebble] = { "Fixture Pebble", 0, 0, nil, 15, 0, 0, 9990002 },
    [I.coffer] = { "Fixture Coffer", 1, 0, 5, 15, 0, 0, 9990003 },
    [I.leather] = { "Fixture Leather", 1, 0, 10, 7, 6, 0, 9990004 },
    [I.hide]    = { "Fixture Hide", 1, 0, 20, 7, 6, 0, 9990005 },
    [I.shard]   = { "Bladed Fixture Shard", 3, 20, 25, 15, 0, 0, 9990006 },
    [I.cloak]   = { "Fixture Bladeweave Cloak", 4, 30, 35, 4, 1, 16, 9990007 },
    [I.letter]  = { "Fixture Letter", 1, 0, 1, 12, 0, 0, 9990008 },
    [I.relic]   = { "Strongbox Relic", 2, 0, 12, 15, 0, 0, 9990009 },
  }
  -- quest[id] = { title, level, minLevel }; qg / qe[quest] = { "c<id>" | "o<id>", ... }
  D.quest = {
    [I.errand]  = { "Fixture Errand", 12, 8 },
    [I.hunt]    = { "Fixture Hunt", 14, 10 },
    [I.summons] = { "Fixture Summons", 15, 12 },
  }
  -- qx[quest] = { raceMask, classMask, preQuestsA, preQuestsB, ..., [10] = { itemId, ... }, ... }
  -- (a mask of 0 or nil means any; the positions between 4 and 10 are not read)
  D.qx = {
    [I.errand] = { 5, nil, nil, nil, nil, nil, nil, nil, nil, { I.leather, I.hide }, 12, 8 },
    [I.hunt]   = { 0, 9, { I.errand }, { I.summons, I.errand }, nil, nil, nil, nil, nil, { I.leather } },
  }
  -- rew[item] = { questId, ... }; start[item] = questId
  D.rew = { [I.blade] = { I.errand }, [I.cloak] = { I.hunt, I.errand } }
  D.start = { [I.letter] = I.summons }
  D.qg = { [I.errand] = { "c" .. I.gnoll, "o" .. I.crate } }
  D.qe = { [I.errand] = { "c" .. I.vendor } }
  -- drop / odrop / idrop[item] = { sourceId, chancePer10000, ... } (flat pairs; 0 = rate unknown)
  D.drop  = { [I.blade] = { I.gnoll, 2500, I.kobold, 0 } }
  D.odrop = {
    [I.blade] = { I.crate, 10000 },
    [I.relic] = { I.boxA, 4000, I.boxB, 6000, I.husk, 9000, I.scrap, 8000 },
  }
  D.idrop = { [I.blade] = { I.coffer, 500 } }
  -- vend[item] = { npcId, ... }; vp[npc] = { [item] = { price, seen } }
  D.vend = { [I.blade] = { I.vendor, I.trainer } }
  D.vp = {
    [I.vendor]  = { [I.blade] = { 1500, 3 } },
    [I.trainer] = { [I.blade] = { 1200, 1 } },
  }
  -- vendx[npc] = { [item] = { p = price, s = stock, r = { requirement, ... } } } (revision 65); the
  -- vendor's vendx price is dearer than the trainer's vp one, so VendorPrice's answer is unchanged
  D.vendx = { [I.vendor] = { [I.blade] = { p = 1400, s = 5 } } }
  -- world[item] = the minimum level of a world drop
  D.world = { [I.blade] = 8 }
  -- obj[id] = { name, ... } (the husk's row carries no name; the scrap's is not a table)
  D.obj = {
    [I.crate] = { "Fixture Crate" },
    [I.boxA]  = { "Fixture Strongbox" },
    [I.boxB]  = { "Fixture Strongbox" },
    [I.husk]  = { nil, 1 },
    [I.scrap] = "Fixture Scrap",
  }
  -- spm["c<id>" | "o<id>"] = { [uiMap] = { x, y, x, y, ... } } on 0..1000
  D.spm = {
    ["c" .. I.gnoll] = { [I.mapA] = { 500, 250, 123, 877 } },
    ["o" .. I.crate] = { [I.mapB] = { 1000, 0 } },
    ["o" .. I.boxA]  = { [I.mapA] = { 100, 200 } },
    ["o" .. I.boxB]  = { [I.mapB] = { 300, 400 } },
  }
  -- umaa[assignment] = { uiMap, continent, areaID, uiMinX, uiMinY, uiMaxX, uiMaxY, minX, minY, minZ,
  -- maxX, maxY, maxZ } (revision 65): the invented continent's map and two zones that overlap at
  -- world X 0..200
  D.umaa = {
    [990401] = { I.mapCont, I.continent, 0, 0, 0, 1, 1, -1000, -1000, -1000000, 1000, 1000, 1000000 },
    [990402] = { I.mapNorth, I.continent, I.areaNorth, 0, 0, 1, 1, 0, -500, -1000000, 1000, 500, 1000000 },
    [990403] = { I.mapSouth, I.continent, I.areaSouth, 0, 0, 1, 1, -600, -500, -1000000, 200, 500, 1000000 },
  }
  -- zbord[areaID] = { c = continent, m = { { x, y, x, y, ... }, ... } } on the zone's 0..1000 map
  -- scale: the north zone's polygon leaves out its southern tenth (map y above 900), the south
  -- zone's its northern quarter (map y below 250)
  D.zbord = {
    [I.areaNorth] = { c = I.continent, m = { { 0, 0, 1000, 0, 1000, 900, 0, 900 } } },
    [I.areaSouth] = { c = I.continent, m = { { 0, 250, 1000, 250, 1000, 1000, 0, 1000 } } },
  }
  -- spw["c<id>" | "o<id>"] = { { continent, worldX, worldY, worldX, worldY, ... }, ... } (revision
  -- 65). The wanderer's run: one point in the north zone alone (600, -250), one in the south alone
  -- (-300, 250), one in the overlap that only the north polygon holds (150, 0), one in the overlap
  -- that neither polygon holds, so the continent map takes it (50, 0), and one off every region
  -- (5000, 0); then a run on a continent no umaa row names. The gnoll's spw point sits under its
  -- spm row, which wins.
  D.spw = {
    ["c" .. I.wanderer] = {
      { I.continent, 600, -250, -300, 250, 150, 0, 50, 0, 5000, 0 },
      { 7, 10, 10 },
    },
    ["c" .. I.gnoll] = { { I.continent, -900, 900 } },
  }
  -- skin[item] = { npcId, chancePer10000, ... } (flat pairs; 0 = rate unknown)
  D.skin = { [I.leather] = { I.gnoll, 2500, I.kobold, 7500 }, [I.hide] = { I.gnoll, 0 } }
  -- trn[npc] = { [spellName] = { cost, level, ?, ? } }
  D.trn = {
    [I.trainer] = {
      ["Fixture Strike"] = { 100, 10, nil, 1 },
      ["Fixture Ward"]   = { 1000, 20, nil, 2 },
    },
  }
  return D
end

local function shallow(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

--- The preset's facts: whether the addon exists, whether its load fails and with what reason.
local function stateOf(opts)
  local preset = opts.preset or "present"
  if not PRESETS[preset] then error("mock_foreverdb: unknown preset " .. tostring(preset), 3) end
  return {
    preset = preset, exists = preset ~= "missing", loadFails = preset == "loadfails",
    reason = opts.reason or "DISABLED", version = opts.version or FDB.VERSION, loaded = false,
  }
end

--- What a load installs: the database for "present", the non-table for "reshaped", else nil.
local function dataOf(st, opts)
  if st.preset == "present" then return opts.data or FDB.fixture() end
  if st.preset == "reshaped" then
    if opts.value == nil then return NAME end
    return opts.value
  end
  return nil
end

--- GetAddOnInfo's answer for ForeverDB: name, title, notes, loadable, reason, security.
local function infoOf(st)
  if not st.exists then return NAME, nil, nil, false, "MISSING", "INSECURE" end
  if st.loadFails then return NAME, NAME, "Invented kit fixture.", false, st.reason, "INSECURE" end
  return NAME, NAME, "Invented kit fixture.", true, nil, "INSECURE"
end

--- GetAddOnMetadata's answer for ForeverDB.
local function metadataOf(st, field)
  if not st.exists then return nil end
  if field == "Version" then return st.version end
  if field == "Title" then return NAME end
  return nil
end

--- The Full fake's facts (revision 65), or nil when opts.full leaves the name to the mock.
local function fullStateOf(opts)
  local preset = opts.full
  if preset == nil then return nil end
  if not FULL_PRESETS[preset] then error("mock_foreverdb: unknown full preset " .. tostring(preset), 3) end
  return {
    preset = preset, exists = preset ~= "missing", disabled = preset == "disabled",
    loadFails = preset == "loadfails", reason = opts.fullReason or "CORRUPT", loaded = false,
  }
end

--- What the Full load installs: the Full database for "present", the non-table for "reshaped".
local function fullDataOf(fs, opts)
  if fs and fs.preset == "present" then return opts.fullData or FDB.fullFixture() end
  if fs and fs.preset == "reshaped" then return "ForeverDBFull" end
  return nil
end

--- GetAddOnInfo's answer for ForeverDB_Full.
local function fullInfoOf(fs)
  if not fs.exists then return FULL, nil, nil, false, "MISSING", "INSECURE" end
  if fs.loaded then return FULL, "ForeverDB (Full)", "Invented kit fixture.", true, nil, "INSECURE" end
  if fs.disabled then return FULL, "ForeverDB (Full)", "Invented kit fixture.", false, "DISABLED", "INSECURE" end
  return FULL, "ForeverDB (Full)", "Invented kit fixture.", true, "DEMAND_LOADED", "INSECURE"
end

--- LoadAddOn("ForeverDB_Full") on the fake: counted, then the preset's answer.
local function loadFullOn(fs, h, putFull)
  h.fullLoads = h.fullLoads + 1
  if not fs.exists then return false, "MISSING" end
  if fs.disabled then return false, "DISABLED" end
  if fs.loadFails then return false, fs.reason end
  putFull(true)
  return true, nil
end

--- `base`'s answer for a name neither fake owns.
local function fallThrough(base, member, name, ...)
  if base[member] then return base[member](name, ...) end
  if member == "GetAddOnInfo" then return name, nil, nil, false, "MISSING", "INSECURE" end
  if member == "IsAddOnLoaded" then return false, false end
  if member == "LoadAddOn" then return false, "MISSING" end
  if member == "DoesAddOnExist" then return false end
  return nil
end

--- A new C_AddOns: `base`'s members, plus ForeverDB's answers from `st` and, with `fs`,
--- ForeverDB_Full's. `put` is the load, `putFull` the Full load.
local function addOnsFor(base, st, h, put, fs, putFull)
  local A = shallow(base)
  local full = fs and FULL or nil
  function A.DoesAddOnExist(name)
    if name == NAME then return st.exists end
    if name == full then return fs.exists end
    return fallThrough(base, "DoesAddOnExist", name)
  end
  function A.GetAddOnInfo(name)
    if name == NAME then return infoOf(st) end
    if name == full then return fullInfoOf(fs) end
    return fallThrough(base, "GetAddOnInfo", name)
  end
  function A.IsAddOnLoaded(name)
    if name == NAME then return st.loaded, st.loaded end
    if name == full then return fs.loaded, fs.loaded end
    return fallThrough(base, "IsAddOnLoaded", name)
  end
  function A.LoadAddOn(name)
    if name == full then return loadFullOn(fs, h, putFull) end
    if name ~= NAME then return fallThrough(base, "LoadAddOn", name) end
    h.loads = h.loads + 1
    if not st.exists then return false, "MISSING" end
    if st.loadFails then return false, st.reason end
    put()
    return true, nil
  end
  function A.GetAddOnMetadata(name, field)
    if name == NAME then return metadataOf(st, field) end
    if name == full then return fs.exists and field == "Version" and FDB.VERSION or nil end
    return fallThrough(base, "GetAddOnMetadata", name, field)
  end
  return A
end

local PROJECT = { "WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CAMELOT" }

--- Set the project constants for `client` ("forever" | "retail") on M; answers what was there.
local function applyClient(M, client)
  if client == nil then return nil end
  if client ~= "forever" and client ~= "retail" then
    error("mock_foreverdb: unknown client " .. tostring(client), 3)
  end
  local saved = {}
  for _, key in ipairs(PROJECT) do saved[key] = M[key] end
  local forever = client == "forever"
  M.WOW_PROJECT_MAINLINE = 1
  M.WOW_PROJECT_ID = forever and 18 or 1
  M.WOW_PROJECT_CAMELOT = forever and 18 or nil
  return saved
end

--- Install the fake on mock `M`; see the header for `opts` and the handle.
function FDB.install(M, opts)
  opts = opts or {}
  local st = stateOf(opts)
  local fs = fullStateOf(opts)
  local h = { loads = 0, preset = st.preset, data = dataOf(st, opts), fullLoads = 0,
    fullData = fullDataOf(fs, opts) }
  local saved = { C_AddOns = M.C_AddOns, ForeverDB = M.ForeverDB, ForeverDBFull = M.ForeverDBFull }
  local loadable = st.exists and not st.loadFails
  local function put() st.loaded = true; M.ForeverDB = h.data end
  local function putFull(measured)
    if measured and opts.onFullLoad then opts.onFullLoad() end
    fs.loaded = true; M.ForeverDBFull = h.fullData
  end

  M.C_AddOns = addOnsFor(M.C_AddOns or {}, st, h, put, fs, putFull)
  M.ForeverDB, M.ForeverDBFull = nil, nil
  local constants = applyClient(M, opts.client)
  if opts.loaded and loadable then put() end
  if opts.fullLoaded and fs and fs.exists and not (fs.disabled or fs.loadFails) then putFull(false) end

  function h.loadNow()
    if loadable then put() end
  end

  function h.restore()
    M.C_AddOns, M.ForeverDB, M.ForeverDBFull = saved.C_AddOns, saved.ForeverDB, saved.ForeverDBFull
    if constants then
      for _, key in ipairs(PROJECT) do M[key] = constants[key] end
    end
  end

  return h
end

return FDB
