-- tests/test_itemsources.lua — the History table's item tooltip, and what ForeverDB adds to it.
--
-- SF-LH-02 (Ka0sAddonsCommonTasks docs/2026-11-25-SEEDS_AND_FOREVERDB, LibKa0s#105). The first
-- case is the CHARACTERIZATION written before the feature: an item row's hover, call for call, as
-- it stands with no ForeverDB. Every case after it must leave that sequence alone wherever the
-- feature is off, absent or on Retail.

local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

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

local function hover(record)
  local BT = NS.BrowserTable
  local row = BT:BuildRow()
  BT:BindRow(row, dataEntry(record), 1)
  return recordTooltip(function() row:GetScript("OnEnter")(row) end)
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

-- Run `fn(fake)` with the fake installed under `opts` (client "forever" unless it says otherwise) and
-- the adapter's session answer forgotten on both sides, so no case leaks a cached Available() into
-- the next. The setting is put back too.
local function withForeverDB(opts, fn)
  local lib = T.mocks.LibStub("LibKa0s-ForeverDB-1.0", true)
  opts.client = opts.client or "forever"
  lib.__reset()
  local fake = FDBK.install(T.mocks, opts)
  local saved = NS.Schema:Get(NS.ItemSources.PATH)
  local ok, err = pcall(fn, fake)
  NS.Schema:Set(NS.ItemSources.PATH, saved)
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
end)

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
end)

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
end)

test("ItemSources: an item ForeverDB names no source for adds nothing", function()
  withForeverDB({ preset = "present" }, function()
    assertEqual(NS.ItemSources.Lines(IDS.pebble), nil)
    local calls = hover({ itemName = "Fixture Pebble", itemLink = "|Hitem:" .. IDS.pebble .. "|h[Fixture Pebble]|h",
      itemID = IDS.pebble, quantity = 1 })
    assertEqual(#calls, 4, table.concat(calls, " "))
  end)
end)

test("ItemSources: the row's id is read from its link when the record carries none", function()
  withForeverDB({ preset = "present" }, function()
    local calls = hover({ itemName = "Fixture Blade", itemLink = BLADE, quantity = 1 })
    assertEqual(calls[3], "AddLine(Drops from)", table.concat(calls, " "))
  end)
end)

test("ItemSources: missing, failing to load or reshaped, the hover is exactly as before", function()
  for _, preset in ipairs({ "missing", "loadfails", "reshaped" }) do
    withForeverDB({ preset = preset }, function(fake)
      assertEqual(table.concat(hover(BLADE_ROW), " "), UNCHANGED, preset)
      assertEqual(NS.ItemSources.Active(), false, preset)
      assertTrue(fake.loads <= 1, preset .. ": at most the one load attempt")
    end)
  end
end)

test("ItemSources: with the setting off, nothing is added and nothing loads", function()
  withForeverDB({ preset = "present" }, function(fake)
    NS.Schema:Set(NS.ItemSources.PATH, false)
    assertEqual(table.concat(hover(BLADE_ROW), " "), UNCHANGED)
    assertEqual(fake.loads, 0)
  end)
end)

test("ItemSources: on Retail the hover is exactly as before and ForeverDB is never asked", function()
  withForeverDB({ preset = "present", client = "retail" }, function(fake)
    assertEqual(table.concat(hover(BLADE_ROW), " "), UNCHANGED)
    assertEqual(NS.ItemSources.Active(), false)
    assertEqual(fake.loads, 0, "the Retail client never loads it")
  end)
end)

test("ItemSources: the addon's load asked ForeverDB nothing", function()
  -- The suites before this one loaded the whole addon and brought it up with no fake installed;
  -- nothing in the shipped code may have reached the adapter's Available() on its own, or the
  -- session answer would already be cached here.
  local src = T.Loader.readFile("modules/ItemSources.lua") .. T.Loader.readFile("core/ForeverDBSetup.lua")
    .. T.Loader.readFile("modules/BrowserTable.lua")
  local code = src:gsub("%-%-[^\n]*", "")
  assertTrue(code:find("LoadAddOn", 1, true) == nil, "only the adapter loads ForeverDB")
  assertTrue(code:find("_G.ForeverDB", 1, true) == nil and code:find("ForeverDB%.[a-z]") == nil,
    "nothing here reads the ForeverDB global's tables")
  withForeverDB({ preset = "present" }, function(fake)
    assertEqual(fake.loads, 0)
    assertEqual(NS.ForeverDB.IsLoaded(), false, "IsLoaded never loads")
    assertEqual(fake.loads, 0)
  end)
end)

test("ItemSources: chances read as percentages, an unknown rate as ?", function()
  local C = NS.ItemSources.ChanceText
  assertEqual(C(0.25), "25.0%")
  assertEqual(C(1), "100.0%")
  assertEqual(C(0.005), "0.50%")
  assertEqual(C(nil), "?")
end)

test("ItemSources: the setting sits with the History window rows, on by default, Forever only", function()
  local row = NS.Schema:FindRow(NS.ItemSources.PATH)
  assertTrue(row ~= nil, "the row exists")
  assertEqual(row.type, "bool")
  assertEqual(row.default, true)
  assertEqual(NS.defaults.profile.settings.itemSources, true)
  assertEqual(row.group, "Interface"); assertEqual(row.subgroup, "History window")
  assertTrue(row.tooltip:find("needs the ForeverDB addon", 1, true) ~= nil, "the row says it needs ForeverDB")
  assertTrue(row.tooltip:find("WoW Forever only", 1, true) ~= nil)
  withForeverDB({ preset = "missing", client = "retail" }, function()
    assertEqual(row.disabledIf(row), true, "drawn disabled on Retail")
  end)
  withForeverDB({ preset = "missing", client = "forever" }, function()
    assertEqual(row.disabledIf(row), false, "drawn live on WoW Forever, installed or not")
  end)
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
