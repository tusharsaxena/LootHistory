-- testkit/mock_foreverdb.lua -- the kit's opt-in fake of ForeverDB, the WoW Forever data addon that
-- LibKa0s-ForeverDB-1.0 reads (revision 61, LibKa0s#105).
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
-- v2026.11.24.46 uses; every name is made up.
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
--   fdb.restore()    puts back M.C_AddOns, M.ForeverDB and, with opts.client, the constants.

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
  blade      = 990101,   -- an item with every kind of source
  pebble     = 990102,   -- an item with no source at all
  coffer     = 990103,   -- a container item the blade comes out of
  errand     = 990201,   -- a quest
  crate      = 990301,   -- an object: drops the blade, gives the errand, has spots
  mapA       = 9901,
  mapB       = 9902,
}

local PRESETS = { present = true, missing = true, loadfails = true, reshaped = true }
FDB.PRESETS = { "present", "missing", "loadfails", "reshaped" }

--- A fresh copy of the invented database, in ForeverDB's real shape (rows positional).
function FDB.fixture()
  local I = FDB.IDS
  local D = {}
  D.meta = {
    build = "2099-01-01",
    hash = "0123456789abcdef",
    counts = { npc = 4, item = 3, quest = 1, obj = 1 },
    sourceList = { { name = "fixture", title = "Invented kit fixture" } },
  }
  -- npc[id] = { name, subname, minLevel, maxLevel, rank }
  D.npc = {
    [I.gnoll]   = { "Fixture Gnoll", "Invented Pack", 10, 12, 1 },
    [I.kobold]  = { "Fixture Kobold", nil, 5, 6, 0 },
    [I.vendor]  = { "Fixture Vendor", "Invented Goods", 30, 30, 0 },
    [I.trainer] = { "Fixture Trainer", "Invented Trainer", 40, 40, 0 },
  }
  -- nfac[npc] = "A" | "H" | "AH"
  D.nfac = { [I.vendor] = "AH", [I.trainer] = "A", [I.gnoll] = "H" }
  -- item[id] = { name, quality, reqLevel, itemLevel, class, subclass, inventoryType, icon, ... }
  D.item = {
    [I.blade]  = { "Fixture Blade", 2, 10, 15, 2, 7, 13, 9990001, 1535, 0, 0, -1 },
    [I.pebble] = { "Fixture Pebble", 0, 0, nil, 15, 0, 0, 9990002 },
    [I.coffer] = { "Fixture Coffer", 1, 0, 5, 15, 0, 0, 9990003 },
  }
  -- quest[id] = { title, level, minLevel }; qg / qe[quest] = { "c<id>" | "o<id>", ... }
  D.quest = { [I.errand] = { "Fixture Errand", 12, 8 } }
  D.qg = { [I.errand] = { "c" .. I.gnoll, "o" .. I.crate } }
  D.qe = { [I.errand] = { "c" .. I.vendor } }
  -- drop / odrop / idrop[item] = { sourceId, chancePer10000, ... } (flat pairs; 0 = rate unknown)
  D.drop  = { [I.blade] = { I.gnoll, 2500, I.kobold, 0 } }
  D.odrop = { [I.blade] = { I.crate, 10000 } }
  D.idrop = { [I.blade] = { I.coffer, 500 } }
  -- vend[item] = { npcId, ... }; vp[npc] = { [item] = { price, seen } }
  D.vend = { [I.blade] = { I.vendor, I.trainer } }
  D.vp = {
    [I.vendor]  = { [I.blade] = { 1500, 3 } },
    [I.trainer] = { [I.blade] = { 1200, 1 } },
  }
  -- world[item] = the minimum level of a world drop
  D.world = { [I.blade] = 8 }
  -- obj[id] = { name }
  D.obj = { [I.crate] = { "Fixture Crate" } }
  -- spm["c<id>" | "o<id>"] = { [uiMap] = { x, y, x, y, ... } } on 0..1000
  D.spm = {
    ["c" .. I.gnoll] = { [I.mapA] = { 500, 250, 123, 877 } },
    ["o" .. I.crate] = { [I.mapB] = { 1000, 0 } },
  }
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

--- A new C_AddOns: `base`'s members, plus ForeverDB's answers from `st`. `put` is the load.
local function addOnsFor(base, st, h, put)
  local A = shallow(base)
  function A.DoesAddOnExist(name)
    if name == NAME then return st.exists end
    if base.DoesAddOnExist then return base.DoesAddOnExist(name) end
    return false
  end
  function A.GetAddOnInfo(name)
    if name == NAME then return infoOf(st) end
    if base.GetAddOnInfo then return base.GetAddOnInfo(name) end
    return name, nil, nil, false, "MISSING", "INSECURE"
  end
  function A.IsAddOnLoaded(name)
    if name == NAME then return st.loaded, st.loaded end
    if base.IsAddOnLoaded then return base.IsAddOnLoaded(name) end
    return false, false
  end
  function A.LoadAddOn(name)
    if name ~= NAME then
      if base.LoadAddOn then return base.LoadAddOn(name) end
      return false, "MISSING"
    end
    h.loads = h.loads + 1
    if not st.exists then return false, "MISSING" end
    if st.loadFails then return false, st.reason end
    put()
    return true, nil
  end
  function A.GetAddOnMetadata(name, field)
    if name == NAME then return metadataOf(st, field) end
    if base.GetAddOnMetadata then return base.GetAddOnMetadata(name, field) end
    return nil
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
  local h = { loads = 0, preset = st.preset, data = dataOf(st, opts) }
  local saved = { C_AddOns = M.C_AddOns, ForeverDB = M.ForeverDB }
  local loadable = st.exists and not st.loadFails
  local function put() st.loaded = true; M.ForeverDB = h.data end

  M.C_AddOns = addOnsFor(M.C_AddOns or {}, st, h, put)
  M.ForeverDB = nil
  local constants = applyClient(M, opts.client)
  if opts.loaded and loadable then put() end

  function h.loadNow()
    if loadable then put() end
  end

  function h.restore()
    M.C_AddOns, M.ForeverDB = saved.C_AddOns, saved.ForeverDB
    if constants then
      for _, key in ipairs(PROJECT) do M[key] = constants[key] end
    end
  end

  return h
end

return FDB
