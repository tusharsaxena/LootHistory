local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- Characterization of the Insights render path: Analytics:LayoutCharts and the renderers and
-- widget factories behind it, driven headless over fixture histories and snapshotted.
--
-- Written before modules/Analytics.lua was split three ways and LayoutCharts brought under CCN 15
-- (GI-LH-01 / GI-LH-02, LootHistory#32). Nothing else in the suite drew a chart: Analytics:Attach
-- never ran headless, so a section dropped or reordered by the refactor would have passed every
-- case. The golden file, tests/analytics_golden.txt (read by tests/golden.lua), was generated from the pre-split code and is
-- never regenerated to make a refactor pass; a deliberate render change rewrites it in its own
-- commit and says so.
--
-- What is observable through the kit's mock and therefore pinned: every pooled widget's texts,
-- text colors, hover strings, anchor and size (CreateTexture answers the frame itself, so a bar's
-- final size is its fill's, which is how each fraction shows), the last SetColorTexture each frame
-- received (recorded by the wrapper below), every header / divider / strip / panel's shown state
-- and anchor, the empty-state text, and the y cursor LayoutCharts returns.

local A = NS.Analytics
local mocks = T.mocks   -- addon chunks resolve WoW globals here, not in _G (tests/_kit/loader.lua)

-- ── fixtures ──────────────────────────────────────────────────────────────────────────────────
--
-- The histories live in tests/fixture_insights.lua, shared with tests/test_export.lua.

local FX = dofile("tests/fixture_insights.lua")
local richHistory, plainHistory, statsFor = FX.richHistory, FX.plainHistory, FX.statsFor

-- ── the harness: a private Insights instance on a recording mock ──────────────────────────────

local function recordingCreateFrame()
  local base = mocks.CreateFrame
  return function(...)
    local f = base(...)
    rawset(f, "SetColorTexture", function(self, r, g, b, a) self.__ct = { r, g, b, a }; return self end)
    -- A template face has a size in the client (sectionDivider scales it by 1.5); the mock's
    -- FontString answers nil for it, so a templated one is given the client's 12 here.
    local createFS = f.CreateFontString
    rawset(f, "CreateFontString", function(self, name, layer, template)
      local s = createFS(self, name, layer, template)
      if template then s.__fontSize = s.__fontSize or 12 end
      return s
    end)
    return f
  end
end

-- An instance that inherits every method from NS.Analytics but owns its own pane, so the live
-- module (and whatever other suites left on it) is untouched. Enable is stubbed for the build:
-- BuildCharts subscribes the real module to the bus, which is NS.StandUp's job, not this suite's.
local function newInstance()
  local inst = setmetatable({}, { __index = A })
  local savedCF, savedEnable = mocks.CreateFrame, A.Enable
  mocks.CreateFrame = recordingCreateFrame()
  A.Enable = function() end
  local ok, err = pcall(function()
    inst.content = mocks.CreateFrame("Frame")
    inst:BuildCharts(inst.content)
  end)
  mocks.CreateFrame, A.Enable = savedCF, savedEnable
  if not ok then error(err, 0) end
  return inst
end

local function layout(inst, stats)
  local savedCF = mocks.CreateFrame
  local g = NS.db.global
  local savedRP = g.resetPrompt
  g.resetPrompt = nil                       -- the pre-ledger caveat is pinned by its own case
  mocks.CreateFrame = recordingCreateFrame()
  inst.stats = stats
  local ok, y = pcall(inst.LayoutCharts, inst, -100, 780, 8)
  mocks.CreateFrame = savedCF
  g.resetPrompt = savedRP
  if not ok then error(y, 0) end
  return y
end

-- ── the snapshot ──────────────────────────────────────────────────────────────────────────────

local function num(v)
  if type(v) ~= "number" then return tostring(v) end
  local s = ("%.3f"):format(v)
  if s == "-0.000" then s = "0.000" end
  return s
end

local function color(c)
  if type(c) ~= "table" then return "-" end
  return num(c[1]) .. "," .. num(c[2]) .. "," .. num(c[3]) .. (c[4] and ("," .. num(c[4])) or "")
end

local function frameNames(inst)
  local names = { [inst.content] = "content" }
  for _, k in ipairs({ "dayStrip", "valueStrip", "hourStrip", "zonePanel", "itemPanel",
                       "itemValuePanel", "currencyStrip", "lootDivider", "currencyDivider" }) do
    names[inst[k]] = k
  end
  return names
end

local function point(f, names)
  local p = f.__lastPoint and f:__lastPoint()
  if not p then return "pt=-" end
  local rel = p.relativeTo
  local relName
  if type(rel) ~= "table" then relName = num(rel)       -- SetPoint(point, x, y): x lands here
  else relName = names[rel] or (rel == f and "self") or "frame" end
  return ("pt=%s>%s.%s(%s,%s)"):format(tostring(p.point), relName, tostring(p.relativePoint),
    num(p.x), num(p.y))
end

local function fs(label, f)
  if type(f) ~= "table" or not f.__isFontString then return "" end
  return (" %s=%q/%s%s"):format(label, tostring(f.__text), color(f.__color),
    f.__shown and "" or "(hidden)")
end

local function describe(o, names)
  local parts = { (o.__shown and "shown" or "hidden"), point(o, names),
    "w=" .. num(o:GetWidth()), "h=" .. num(o:GetHeight()), "ct=" .. color(o.__ct) }
  for _, k in ipairs({ "_fullLabel", "_fullName", "_full", "_info", "info" }) do
    if o[k] ~= nil then parts[#parts + 1] = k .. "=" .. ("%q"):format(tostring(o[k])) end
  end
  local s = table.concat(parts, " ")
  s = s .. fs("label", o.label) .. fs("value", o.value) .. fs("name", o.name)
    .. fs("count", o.count) .. fs("fs", o.fs) .. fs("axis", o.axis)
  if o.segs then
    for i, seg in ipairs(o.segs) do
      if seg.__shown then
        s = s .. ("\n    seg%d %s w=%s h=%s ct=%s info=%q"):format(i, point(seg, names),
          num(seg:GetWidth()), num(seg:GetHeight()), color(seg.__ct), tostring(seg._info))
      end
    end
  end
  return s
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function snapshot(inst, y)
  local names = frameNames(inst)
  local out = { "y=" .. num(y) }
  for _, k in ipairs(sortedKeys(inst.headers)) do
    local h = inst.headers[k]
    out[#out + 1] = ("header %s %s %s%s"):format(k, h.__shown and "shown" or "hidden", point(h, names),
      fs("text", h))
  end
  for _, k in ipairs({ "lootDivider", "currencyDivider", "dayStrip", "valueStrip", "hourStrip",
                       "zonePanel", "itemPanel", "itemValuePanel", "currencyStrip" }) do
    out[#out + 1] = ("frame %s %s"):format(k, describe(inst[k], names))
  end
  local e = inst.emptyText
  out[#out + 1] = ("emptyText %s %s"):format(e.__shown and "shown" or "hidden", point(e, names))
  for _, k in ipairs(sortedKeys(inst.pool)) do
    local pool = inst.pool[k]
    out[#out + 1] = ("pool %s active=%d free=%d"):format(k, #pool.active, #pool.free)
    for i, o in ipairs(pool.active) do
      out[#out + 1] = ("  %s#%d %s"):format(k, i, describe(o, names))
    end
  end
  return table.concat(out, "\n")
end

local function counts(inst)
  local c = {}
  for k, pool in pairs(inst.pool) do c[k] = { NS.Pool.Counts(pool) } end
  return c
end

-- ── the golden master ─────────────────────────────────────────────────────────────────────────
--
-- tests/golden.lua reads and compares; the snapshots run to some 700 lines.

local assertGolden = dofile("tests/golden.lua").file("tests/analytics_golden.txt")

-- ── cases ─────────────────────────────────────────────────────────────────────────────────────

local rich = statsFor(richHistory())
local plain = statsFor(plainHistory())
local empty = statsFor({})

test("Insights layout: the fixtures exercise the branches they are meant to", function()
  assertTrue(rich.totals.records > 0 and rich.currencyTotals.events > 0, "rich has items and currency")
  local srcCount = 0
  for _ in pairs(rich.bySource) do srcCount = srcCount + 1 end
  assertTrue(srcCount > 9, "rich has more sources than a stacked bar has segments")
  local perChar = 0
  for _ in pairs(rich.charBySource["Alpha-Realm"]) do perChar = perChar + 1 end
  assertTrue(perChar > 9, "one character alone has more than nine sources (the Other collapse)")
  assertEqual(plain.currencyTotals.events, 0, "plain has no currency")
  assertEqual(plain.totals.totalValue, 0, "plain has no value")
  assertEqual(empty.totals.records, 0, "empty is empty")
end)

test("Insights layout: a full pass over items and currency matches the golden snapshot", function()
  local inst = newInstance()
  local y = layout(inst, rich)
  assertGolden("rich", snapshot(inst, y))
end)

test("Insights layout: a second pass re-acquires the same widgets and draws the same thing", function()
  local inst = newInstance()
  local y1 = layout(inst, rich)
  local first, c1 = snapshot(inst, y1), counts(inst)
  local y2 = layout(inst, rich)
  assertEqual(y2, y1, "the y cursor is stable")
  local c2 = counts(inst)
  for k, v in pairs(c1) do
    assertEqual(c2[k][1], v[1], k .. ": free count after the second pass")
    assertEqual(c2[k][2], v[2], k .. ": active count after the second pass")
  end
  assertEqual(snapshot(inst, y2), first, "the second pass draws byte-for-byte what the first did")
end)

test("Insights layout: items with no value and no currency, over a trimmed day range", function()
  local inst = newInstance()
  layout(inst, rich)                       -- dirty every pool first, so this pass recycles
  local y = layout(inst, plain)
  assertGolden("plain", snapshot(inst, y))
end)

test("Insights layout: an empty range hides every chart and shows the empty text", function()
  local inst = newInstance()
  layout(inst, rich)
  local y = layout(inst, empty)
  assertGolden("empty", snapshot(inst, y))
  assertEqual(y, -150, "the empty state reserves 50px under the cursor")
  assertTrue(inst.emptyText.__shown, "the empty text is shown")
end)

test("Insights layout: a nil stats table takes the empty branch too", function()
  local inst = newInstance()
  local y = layout(inst, nil)
  assertEqual(y, -150)
  assertTrue(inst.emptyText.__shown, "the empty text is shown")
end)


test("Insights layout: a range with losses draws the gains-vs-losses section first", function()
  local T1 = 1600000000
  local stats = statsFor({
    { ts = T1, char = "A-Realm", classFile = "MAGE", itemID = 10, itemName = "Sword", quality = 4, source = "KILL", quantity = 1, vendorPrice = 100 },
    { ts = T1, char = "A-Realm", classFile = "MAGE", itemID = 11, itemName = "Potion", quality = 1, source = "CONSUME",
      dir = "OUT", kind = "ITEM", quantity = 5, vendorPrice = 10 },
    { ts = T1, char = "A-Realm", classFile = "MAGE", kind = "GOLD", itemName = "Gold", source = "REPAIR", dir = "OUT", quantity = 300 },
  })
  local inst = newInstance()
  local y = layout(inst, stats)
  local ui = inst.ledgerUI
  assertTrue(ui.divider.__shown, "the GAINS & LOSSES divider is shown")
  assertTrue(ui.headers.reason.__shown)
  assertEqual(#ui.pools.reason.active, 3)                 -- KILL, CONSUME, REPAIR
  assertTrue(inst.lootDivider.__shown, "the LOOT sections still draw for the gain")
  assertTrue(y < -100)
  -- Drawn above LOOT: the divider's anchor y is above the loot divider's.
  assertTrue(ui.divider:__lastPoint().y > inst.lootDivider:__lastPoint().y)
end)

test("Insights layout: losses only — no empty text, no LOOT divider", function()
  local stats = statsFor({
    { ts = 1600000000, char = "A-Realm", classFile = "MAGE", kind = "GOLD", itemName = "Gold", source = "REPAIR", dir = "OUT", quantity = 300 },
  })
  local inst = newInstance()
  layout(inst, stats)
  assertTrue(not inst.emptyText.__shown)
  assertTrue(not inst.lootDivider.__shown)
  assertTrue(inst.ledgerUI.divider.__shown)
end)
