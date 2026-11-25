-- tests/test_itemsources.lua — the History table's item tooltip, and what ForeverDB adds to it.
--
-- SF-LH-02 (Ka0sAddonsCommonTasks docs/2026-11-25-SEEDS_AND_FOREVERDB, LibKa0s#105). The first
-- case is the CHARACTERIZATION written before the feature: an item row's hover, call for call, as
-- it stands with no ForeverDB. Every case after it must leave that sequence alone wherever the
-- feature is off, absent or on Retail.
--
-- The feature is WoW Forever only (C.FEATURE.itemSources, clients-§4), read once at file load from
-- the kit profile: the cases that need it are declared skips on Retail (T.FOREVER_ONLY), and the
-- per-client case asserts each profile's own shape, present on WoW Forever and absent on Retail.

local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local FOREVER_ONLY = T.FOREVER_ONLY
local function C_FEATURE() return NS.Constants.FEATURE end

local function dataEntry(rec) return { kind = "row", record = rec } end

-- Record GameTooltip's calls, each as `Method(arg1[,arg2])`, for the length of `fn`.
local TT_METHODS = { "SetOwner", "SetHyperlink", "SetCurrencyByID", "AddLine", "AddDoubleLine", "Show", "Hide" }
local function recordTooltip(fn)
  local tt, calls, saved = T.mocks.GameTooltip, {}, {}
  for _, m in ipairs(TT_METHODS) do
    saved[m] = rawget(tt, m)
    tt[m] = function(_, a, b)
      -- SetOwner's argument is the row frame, whose tostring changes from run to run.
      if m == "SetOwner" then a = "row" end
      calls[#calls + 1] = m .. "(" .. tostring(a) .. (m == "AddDoubleLine" and ("," .. tostring(b)) or "") .. ")"
      return tt
    end
  end
  local ok, err = pcall(fn)
  for _, m in ipairs(TT_METHODS) do tt[m] = saved[m] end
  if not ok then error(err, 0) end
  return calls
end

-- ONE row frame for the whole suite, built on the first hover and re-bound for each: the mock
-- never frees a frame, so a row built per hover is retained for the rest of the run.
local ROW
local function hover(record)
  local BT = NS.BrowserTable
  ROW = ROW or BT:BuildRow()
  BT:BindRow(ROW, dataEntry(record), 1)
  return recordTooltip(function() ROW:GetScript("OnEnter")(ROW) end)
end

local APPLE = "|Hitem:7|h[Apple]|h"
local HINT = "AddLine(Shift-click to link \194\183 right-click for options)"

test("ItemSources: characterization, an item row's hover with no ForeverDB, call for call", function()
  local calls = hover({ itemName = "Apple", itemLink = APPLE, itemID = 7, quantity = 1 })
  assertEqual(table.concat(calls, " "), "SetOwner(row) SetHyperlink(" .. APPLE .. ") " .. HINT .. " Show(nil)")
  calls = hover({ itemName = "Apple", itemLink = APPLE, itemID = 7, quantity = 1, confidence = "INFERRED" })
  assertEqual(calls[3], "AddLine(Source inferred (uncertain).)")
  assertEqual(calls[4], HINT)
  assertEqual(#calls, 5)
end)

-- ── what ForeverDB adds (on the kit's fake, mock_foreverdb.lua: invented rows in ForeverDB's shape) ──

local FDBK = dofile("tests/_kit/mock_foreverdb.lua")
local IDS = FDBK.IDS
local BLADE = "|Hitem:" .. IDS.blade .. "|h[Fixture Blade]|h"
local BLADE_ROW = { itemName = "Fixture Blade", itemLink = BLADE, itemID = IDS.blade, quantity = 1 }
local UNCHANGED = "SetOwner(row) SetHyperlink(" .. BLADE .. ") " .. HINT .. " Show(nil)"

-- Run `fn(fake)` with the fake installed under `opts` (on the profile's own client) and the
-- adapter's session answer forgotten on both sides, so no case leaks a cached Available() into the
-- next. The setting is put back too, where it exists (WoW Forever).
local function withForeverDB(opts, fn)
  local lib = T.mocks.LibStub("LibKa0s-ForeverDB-1.0", true)
  local feature = NS.Constants.FEATURE.itemSources
  lib.__reset()
  local fake = FDBK.install(T.mocks, opts)
  local saved = feature and NS.Schema:Get(NS.ItemSources.PATH)
  local ok, err = pcall(fn, fake)
  if feature then NS.Schema:Set(NS.ItemSources.PATH, saved) end
  fake.restore()
  lib.__reset()
  if not ok then error(err, 0) end
end

test("ItemSources: on WoW Forever with ForeverDB, the hover adds Drops from and Sold by", function()
  withForeverDB({ preset = "present" }, function(fake)
    assertEqual(fake.loads, 0, "nothing loads before the first hover")
    local calls = hover(BLADE_ROW)
    assertEqual(fake.loads, 1, "the first hover is what loads ForeverDB")
    local money = NS.Util.FormatMoney(1200)
    assertEqual(table.concat(calls, " "), table.concat({
      "SetOwner(row)", "SetHyperlink(" .. BLADE .. ")",
      "AddLine(Drops from)",
      "AddDoubleLine(  Fixture Gnoll,25.0%)",
      "AddDoubleLine(  Fixture Kobold,?)",
      "AddDoubleLine(Sold by Fixture Trainer," .. money .. ")",
      HINT, "Show(nil)" }, " "),
      "the creatures most likely first, the unknown rate last, the cheaper vendor")
    hover(BLADE_ROW)
    assertEqual(fake.loads, 1, "one load a session")
  end)
end, FOREVER_ONLY)

test("ItemSources: the lines' colors are the skin's tooltip tokens", function()
  withForeverDB({ preset = "present" }, function()
    local got = {}
    local tip = {
      AddLine = function(_, text, r, g, b) got[#got + 1] = { text, r, g, b } end,
      AddDoubleLine = function(_, l, v, lr, lg, lb, rr, rg, rb) got[#got + 1] = { l, lr, lg, lb, v, rr, rg, rb } end,
    }
    assertEqual(NS.ItemSources.AddTo(tip, IDS.blade), 4)
    local function same(line, from, token)
      local r, g, b = NS.SkinColor(token)
      return line[from] == r and line[from + 1] == g and line[from + 2] == b
    end
    assertTrue(same(got[1], 2, "gtip.title"), "Drops from is a heading")
    assertTrue(same(got[2], 2, "gtip.body") and same(got[2], 6, "gtip.value"), "a source, its chance a value")
    assertTrue(same(got[4], 2, "gtip.title") and same(got[4], 6, "gtip.value"), "Sold by, its price a value")
  end)
end, FOREVER_ONLY)

test("ItemSources: the top three, then how many more; a vendor with no price seen; unknown names", function()
  local data = FDBK.fixture()
  data.drop[IDS.blade] = { IDS.kobold, 0, 990901, 100, IDS.gnoll, 2500, 990902, 50, 990903, 9000 }
  data.vend[IDS.blade] = { IDS.vendor }
  data.vp = {}
  withForeverDB({ preset = "present", data = data }, function()
    local lines = NS.ItemSources.Lines(IDS.blade)
    local text = {}
    for i, l in ipairs(lines) do text[i] = l[1] .. "=" .. tostring(l[2]) end
    assertEqual(table.concat(text, " | "), table.concat({
      "Drops from=nil", "  #990903=90.0%", "  Fixture Gnoll=25.0%", "  #990901=1.0%",
      "  and 2 more=nil", "Sold by Fixture Vendor=nil" }, " | "))
  end)
end, FOREVER_ONLY)

test("ItemSources: an item ForeverDB names no source for adds nothing", function()
  withForeverDB({ preset = "present" }, function()
    assertEqual(NS.ItemSources.Lines(IDS.pebble), nil)
    local calls = hover({ itemName = "Fixture Pebble", itemLink = "|Hitem:" .. IDS.pebble .. "|h[Fixture Pebble]|h",
      itemID = IDS.pebble, quantity = 1 })
    assertEqual(#calls, 4, table.concat(calls, " "))
  end)
end, FOREVER_ONLY)

test("ItemSources: the row's id is read from its link when the record carries none", function()
  withForeverDB({ preset = "present" }, function()
    local calls = hover({ itemName = "Fixture Blade", itemLink = BLADE, quantity = 1 })
    assertEqual(calls[3], "AddLine(Drops from)", table.concat(calls, " "))
  end)
end, FOREVER_ONLY)

test("ItemSources: missing, failing to load or reshaped, the hover is exactly as before", function()
  for _, preset in ipairs({ "missing", "loadfails", "reshaped" }) do
    withForeverDB({ preset = preset }, function(fake)
      assertEqual(table.concat(hover(BLADE_ROW), " "), UNCHANGED, preset)
      assertEqual(NS.ItemSources.Active(), false, preset)
      -- A missing addon is answered without a LoadAddOn call; the other two make the one attempt.
      if preset == "missing" then
        assertEqual(fake.loads, 0, preset .. ": nothing to load")
      else
        assertTrue(fake.loads <= 1, preset .. ": at most the one load attempt")
      end
    end)
  end
end, FOREVER_ONLY)

test("ItemSources: with the setting off, nothing is added and nothing loads", function()
  withForeverDB({ preset = "present" }, function(fake)
    NS.Schema:Set(NS.ItemSources.PATH, false)
    assertEqual(table.concat(hover(BLADE_ROW), " "), UNCHANGED)
    assertEqual(fake.loads, 0)
  end)
end, FOREVER_ONLY)

test("ItemSources: on Retail the hover is exactly as before and ForeverDB is never asked", function()
  -- red under: IS.Active() asking the client at hover rather than the declared feature, or a Retail
  -- hover that reaches the adapter
  withForeverDB({ preset = "present" }, function(fake)
    assertEqual(table.concat(hover(BLADE_ROW), " "), UNCHANGED)
    assertEqual(NS.ItemSources.Active(), false)
    assertEqual(fake.loads, 0, "the Retail client never loads it")
  end)
end, (T.forever and "Retail's half of the per-client shape: on WoW Forever the feature is present, "
  .. "which the hover cases assert" or nil))

test("ItemSources: the addon's load asked ForeverDB nothing", function()
  -- tests/run.lua loads every addon file and runs the lifecycle kick (OnInitialize's steps) with
  -- the kit's fake INSTALLED and not loaded, and records what that cost. red under: a file-load or
  -- login-time Available(), NS.ItemSources.Active() or Lines() call
  local boot = T.bootForeverDB
  assertTrue(type(boot) == "table", "tests/run.lua publishes the boot record")
  assertEqual(boot.loads, 0, "the file load and OnInitialize loaded nothing")
  assertEqual(boot.loaded, false, "ForeverDB was still unloaded after OnInitialize")
  -- Then the rest of the boot, with the fake installed and NO reset: OnEnable (NS.StandUp, every
  -- module's Enable) and the world-entry event, taken back down after.
  local fake = FDBK.install(T.mocks, { preset = "present" })
  local ok, err = pcall(function()
    NS.addon:OnEnable()
    T.mocks.__fireEvent("PLAYER_ENTERING_WORLD", true, false)
    assertEqual(fake.loads, 0, "OnEnable and the world entry loaded nothing")
    assertEqual(NS.ForeverDB.IsLoaded(), false, "IsLoaded never loads")
    if T.forever then
      -- And the session answer was not cached by any of it: the first hover is what loads it.
      hover(BLADE_ROW)
      assertEqual(fake.loads, 1, "the first hover still makes the session's one load")
    end
  end)
  NS.StandDown()
  fake.restore()
  T.mocks.LibStub("LibKa0s-ForeverDB-1.0").__reset()
  if not ok then error(err, 0) end
  local src = T.Loader.readFile("modules/ItemSources.lua") .. T.Loader.readFile("core/ForeverDBSetup.lua")
    .. T.Loader.readFile("modules/BrowserTable.lua")
  local code = src:gsub("%-%-[^\n]*", "")
  assertTrue(code:find("LoadAddOn", 1, true) == nil, "only the adapter loads ForeverDB")
  assertTrue(code:find("_G.ForeverDB", 1, true) == nil and code:find("ForeverDB%.[a-z]") == nil,
    "nothing here reads the ForeverDB global's tables")
end)

test("ItemSources: chances read as percentages, an unknown rate as ?", function()
  local C = NS.ItemSources.ChanceText
  assertEqual(C(0.25), "25.0%")
  assertEqual(C(1), "100.0%")
  assertEqual(C(0.005), "0.50%")
  assertEqual(C(nil), "?")
end)

test("ItemSources: the setting is WoW Forever's alone: its row sits with the History window rows there, absent on Retail", function()
  -- clients-§4: a one-client feature is absent on the other client, never drawn disabled. red under:
  -- the row registered on Retail (hidden, grayed out or disabled), or a disabledIf on it anywhere
  local row = NS.Schema:FindRow(NS.ItemSources.PATH)
  assertEqual(C_FEATURE().itemSources, T.forever == true, "the feature is declared WoW Forever's")
  if not T.forever then
    assertEqual(row, nil, "no row on Retail")
    assertEqual(NS.defaults.profile.settings.itemSources, nil, "no default on Retail")
    return
  end
  assertTrue(row ~= nil, "the row exists on WoW Forever")
  assertEqual(row.type, "bool")
  assertEqual(row.default, true)
  assertEqual(NS.defaults.profile.settings.itemSources, true)
  assertEqual(row.group, "Interface"); assertEqual(row.subgroup, "History window")
  assertEqual(row.disabledIf, nil, "never drawn disabled")
  assertTrue(row.tooltip:find("Needs the ForeverDB addon", 1, true) ~= nil, "the row says it needs ForeverDB")
end)

test("ItemSources: the TOC and .pkgmeta name ForeverDB as optional, never required", function()
  local toc = T.Loader.readFile("LootHistory.toc")
  local opt = toc:match("## OptionalDeps:([^\r\n]*)")
  assertTrue(opt ~= nil and opt:find("ForeverDB", 1, true) ~= nil, "OptionalDeps names ForeverDB")
  assertTrue(toc:find("## Dependencies:", 1, true) == nil and toc:find("## RequiredDeps:", 1, true) == nil,
    "nothing is required")
  local pkg = T.Loader.readFile(".pkgmeta")
  assertTrue(pkg:find("optional%-dependencies:%s*[\r\n]+%s*%- forever%-db") ~= nil, ".pkgmeta lists forever-db")
  assertTrue(pkg:find("required-dependencies", 1, true) == nil)
end)
