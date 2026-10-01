local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- Characterization of the Insights render path: Analytics:LayoutCharts and the renderers and
-- widget factories behind it, driven headless over fixture histories and snapshotted.
--
-- Written before modules/Analytics.lua was split three ways and LayoutCharts brought under CCN 15
-- (GI-LH-01 / GI-LH-02, LootHistory#32). Nothing else in the suite drew a chart: Analytics:Attach
-- never ran headless, so a section dropped or reordered by the refactor would have passed every
-- case. The golden file, tests/analytics_golden.txt, was generated from the pre-split code and is
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
-- Timestamps sit at 12:00 UTC, so a day key is the same date in every timezone from UTC-11 to
-- UTC+11. byHour and byWeekday are overwritten with fixed buckets after Stats, so the hour and
-- weekday charts do not depend on the machine's timezone either.

local DAY = 86400
local NOON = 1600000000 - (1600000000 % DAY) + 12 * 3600

local SOURCES = { "KILL", "CONTAINER", "MPLUS", "ROLL", "BONUS_ROLL", "QUEST", "TRADE", "MAIL",
                  "AH", "VENDOR", "CRAFT", "DISENCHANT" }
local TYPES = { "Armor", "Weapon", "Consumable", "Tradeskill", "Recipe", "Gem", "Miscellaneous" }
local BOUNDS = { "BOP", "BOE", "WARBAND", "WARBAND_UE", nil }

local function richHistory()
  local h = {}
  local chars = { { "Alpha-Realm", "WARRIOR" }, { "Beta-Realm", "MAGE" }, { "Gamma-Realm", "PRIEST" } }
  for i = 1, 40 do
    local c = chars[(i % 3) + 1]
    h[#h + 1] = {
      ts = NOON + (i % 9) * DAY, char = c[1], classFile = c[2],
      itemID = 100 + (i % 14), itemName = "Item " .. (i % 14),
      quality = i % 6, itemLevel = 400 + i, bound = BOUNDS[(i % 5) + 1],
      itemType = TYPES[(i % 7) + 1], vendorPrice = (i % 4 == 0) and 0 or i * 1234,
      quantity = (i % 3) + 1, source = SOURCES[(math.floor(i / 3) % 12) + 1],
      zone = (i % 2 == 0) and "Valley" or ((i % 3 == 0) and "Cavern" or "Spire"),
    }
  end
  -- Currency, including a character who looted only currency (byChar count 0).
  for i = 1, 8 do
    h[#h + 1] = {
      ts = NOON + (i % 4) * DAY, char = (i % 2 == 0) and "Delta-Realm" or "Alpha-Realm",
      classFile = (i % 2 == 0) and "ROGUE" or "WARRIOR",
      currencyID = 3000 + (i % 3), itemName = "Coin " .. (i % 3), quantity = i * 5,
      source = SOURCES[(i % 4) + 1], zone = "Valley",
    }
  end
  return h
end

-- Items only, every value zero: the Value By Source section and the Top Items By Value panel
-- draw nothing, and the CURRENCY section takes its hidden branch. Spread over 70 days, so the
-- per-day strips trim to the 60 most recent.
local function plainHistory()
  local h = {}
  for i = 1, 12 do
    h[#h + 1] = {
      ts = NOON + (i - 1) * 6 * DAY, char = "Solo-Realm", classFile = "HUNTER",
      itemID = 500 + (i % 3), itemName = "Plain " .. (i % 3), quality = 1 + (i % 2),
      itemType = "Junk", vendorPrice = 0, source = (i % 2 == 0) and "KILL" or "QUEST",
    }
  end
  return h
end

local FIXED_HOURS = { [0] = 2, [7] = 5, [13] = 9, [22] = 1 }
local FIXED_WEEKDAYS = { [0] = 3, [2] = 7, [5] = 4 }

local function statsFor(history)
  local saved = NS.db.global.history
  NS.db.global.history = history
  local savedTest = NS.State.testRecords
  NS.State.testRecords = nil
  local stats = NS.Database:Stats({})
  NS.db.global.history = saved
  NS.State.testRecords = savedTest
  if stats.totals.records > 0 then
    stats.byHour, stats.byWeekday = FIXED_HOURS, FIXED_WEEKDAYS
  end
  return stats
end

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
  mocks.CreateFrame = recordingCreateFrame()
  inst.stats = stats
  local ok, y = pcall(inst.LayoutCharts, inst, -100, 780, 8)
  mocks.CreateFrame = savedCF
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

-- Plain text rather than a Lua module: the snapshots run to some 1,700 lines, past layout-§1's
-- 1500-line cap for a .lua file. Sections open with `== <name> ==`; CR is stripped on read
-- because the working tree is CRLF (.gitattributes).
local GOLDEN_PATH = "tests/analytics_golden.txt"

local function readGolden()
  local f = io.open(GOLDEN_PATH, "rb")
  if not f then return {} end
  local body = f:read("*a"):gsub("\r", "")
  f:close()
  local out, name, lines = {}, nil, nil
  for line in (body .. "\n"):gmatch("(.-)\n") do
    local header = line:match("^== (.-) ==$")
    if header then
      if name then out[name] = table.concat(lines, "\n") end
      name, lines = header, {}
    elseif name then
      lines[#lines + 1] = line
    end
  end
  if name then
    while lines[#lines] == "" do lines[#lines] = nil end
    out[name] = table.concat(lines, "\n")
  end
  return out
end

local golden = readGolden()

-- Set LH_WRITE_ANALYTICS_GOLDEN=1 to print the current snapshots in golden-file form instead of
-- comparing them; a deliberate render change rewrites the file from that output in its own commit.
local WRITE = os.getenv("LH_WRITE_ANALYTICS_GOLDEN") == "1"

local function firstDiff(a, b)
  local la, lb = {}, {}
  for line in (a .. "\n"):gmatch("(.-)\n") do la[#la + 1] = line end
  for line in (b .. "\n"):gmatch("(.-)\n") do lb[#lb + 1] = line end
  for i = 1, math.max(#la, #lb) do
    if la[i] ~= lb[i] then
      return ("line %d:\n  want: %s\n  got:  %s"):format(i, tostring(la[i]), tostring(lb[i]))
    end
  end
  return "no difference"
end

local function assertGolden(key, got)
  if WRITE then
    print(("-- GOLDEN BEGIN\n== %s ==\n%s\n-- GOLDEN END"):format(key, got))
    return
  end
  local want = golden[key]
  assertTrue(want ~= nil, "no golden snapshot named " .. key .. " in " .. GOLDEN_PATH)
  assertTrue(want == got, key .. " differs from the golden snapshot at " .. firstDiff(want, got))
end

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

