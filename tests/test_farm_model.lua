-- tests/test_farm_model.lua — modules/FarmModel.lua, farm mode's pure session model (#39, farm spec
-- docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §4.3, §5.2, §5.3, §5.5, §5.6, §5.9, §13):
-- the clock, zone banking, Finish's pure half, the packed log and its trims, the saved-sessions cap,
-- totals and rates (with the mockup's goldens), the gain and cost tallies and their source rule, the
-- corpse ring, the best-per-zone star and the display formatters. Plain tables only: no client, no
-- store, no bus.

local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local FM = function() return NS.FarmModel end
local T0 = 1795000000

local function new(zone) return FM().New(T0, 7, "Charone-Realm", "MAGE", zone or "Isle of Dorn") end

-- A GAIN payload as the feed fills it (§2), only the fields a case names.
local function gain(kind, fields)
  local g = { kind = kind, dir = "IN", origin = "chat", sim = false }
  for k, v in pairs(fields) do g[k] = v end
  return g
end

local function kinds(s)
  local out = {}
  for _, line in ipairs(s.log) do out[#out + 1] = select(2, FM().Unpack(line)) end
  return table.concat(out, "")
end

-- ── the session and the clock ────────────────────────────────────────────────────────────────

test("FarmModel New: a running v1 session with empty lines and its first zone", function()
  local s = new()
  assertEqual(s.v, 1, "the shape stamp")
  assertEqual(FM().VERSION, 1)
  assertEqual(s.runningSince, T0); assertEqual(s.activeSec, 0); assertEqual(s.lastSeen, T0)
  assertEqual(s.name, ""); assertEqual(s.zoneSec["Isle of Dorn"], 0); assertEqual(s.zoneOrder[1], "Isle of Dorn")
  assertEqual(#s.log, 0); assertEqual(s.logDropped, 0); assertEqual(s.mobPos, 0)
  assertEqual(s.activity.mobs + s.activity.items + s.activity.looks + s.activity.deaths, 0)
  assertEqual(next(new("").zoneSec), nil, "an unknown zone is not a zone")
end)

test("FarmModel clock: Elapsed, Bank, Pause and Resume bank only running seconds", function()
  local s = new()
  assertEqual(FM().Elapsed(s, T0 + 100), 100)
  FM().Pause(s, "manual", T0 + 100)
  assertEqual(s.runningSince, nil); assertEqual(s.activeSec, 100); assertEqual(s.pauseReason, "manual")
  assertEqual(FM().Elapsed(s, T0 + 500), 100, "a paused clock stands still")
  FM().Bank(s, T0 + 900)
  assertEqual(s.activeSec, 100, "banking a paused session changes nothing")
  FM().Resume(s, T0 + 600)
  assertEqual(s.pauseReason, nil); assertEqual(s.runningSince, T0 + 600)
  assertEqual(FM().Elapsed(s, T0 + 650), 150)
  FM().Bank(s, T0 + 550)
  assertEqual(s.activeSec, 100, "a bank before the clock started banks nothing")
  assertEqual(kinds(s), "pu", "pause and resume are logged")
  local _, _, reason = FM().Unpack(s.log[1])
  assertEqual(reason, "manual")
end)

test("FarmModel IdleAt: banks to the last gain, to the clock's start with none, off at 0", function()
  local s = new()
  assertEqual(FM().IdleAt(s, T0 + 299, 5), nil, "not idle yet")
  assertEqual(FM().IdleAt(s, T0 + 300, 5), T0, "no gain: back to runningSince")
  s.lastGainAt = T0 + 120
  assertEqual(FM().IdleAt(s, T0 + 419, 5), nil)
  assertEqual(FM().IdleAt(s, T0 + 420, 5), T0 + 120, "back to the last gain")
  assertEqual(FM().IdleAt(s, T0 + 9999, 0), nil, "0 = off")
  FM().Pause(s, "idle", FM().IdleAt(s, T0 + 420, 5))
  assertEqual(s.activeSec, 120, "the idle span leaves the clock (D16)")
  assertEqual(FM().IdleAt(s, T0 + 9999, 5), nil, "a paused session is never idle-paused")
  local afk = new()
  FM().Pause(afk, "afk", T0 + 42)
  assertEqual(afk.activeSec, 42, "an AFK pause banks to the moment AFK set (F3)")
end)

test("FarmModel IdleAt: a resume restarts the idle span, so an old gain does not pause at once", function()
  -- red under: IdleAt reading `lastGainAt or runningSince`, where a gain from before an idle pause
  -- and a later Resume answered idle on the very next tick and banked zero seconds.
  local s = new()
  s.lastGainAt = T0 + 60
  FM().Pause(s, "idle", FM().IdleAt(s, T0 + 360, 5))
  FM().Resume(s, T0 + 2000)
  assertEqual(FM().IdleAt(s, T0 + 2030, 5), nil, "30 s after the resume is not idle")
  assertEqual(FM().IdleAt(s, T0 + 2300, 5), T0 + 2000, "idle again 5 min after the resume")
end)

test("FarmModel zones: banked only while running, an empty or unchanged zone ignored", function()
  local s = new()
  assertFalse(FM().SetZone(s, "", T0 + 10), "empty is no change")
  assertFalse(FM().SetZone(s, "Isle of Dorn", T0 + 10), "unchanged is no change")
  assertTrue(FM().SetZone(s, "Ringing Deeps", T0 + 100))
  assertEqual(s.zoneSec["Isle of Dorn"], 100)
  FM().Pause(s, "manual", T0 + 160)
  assertEqual(s.zoneSec["Ringing Deeps"], 60)
  FM().SetZone(s, "Hallowfall", T0 + 400)
  assertEqual(s.zoneSec["Ringing Deeps"], 60, "paused seconds are no zone's")
  FM().Resume(s, T0 + 500)
  FM().Bank(s, T0 + 530)
  assertEqual(s.zoneSec.Hallowfall, 30)
  assertEqual(table.concat(s.zoneOrder, ","), "Isle of Dorn,Ringing Deeps,Hallowfall")
  assertTrue(kinds(s):find("z", 1, true) ~= nil, "a zone change is logged")
end)

test("FarmModel PrimaryZone: the most active seconds, a tie to the zone seen first", function()
  local s = new()
  s.zoneSec = { ["Isle of Dorn"] = 50, ["Ringing Deeps"] = 80, Hallowfall = 80 }
  s.zoneOrder = { "Isle of Dorn", "Ringing Deeps", "Hallowfall" }
  assertEqual(FM().PrimaryZone(s), "Ringing Deeps")
  s.zoneOrder = { "Isle of Dorn", "Hallowfall", "Ringing Deeps" }
  assertEqual(FM().PrimaryZone(s), "Hallowfall", "the tie goes to the first seen")
  assertEqual(FM().PrimaryZone(new("")), nil)
end)

test("FarmModel Close: an empty log is discarded (F6); otherwise stamped, named, totaled, trimmed", function()
  local s = new()
  assertFalse(FM().Close(s, "manual", T0 + 60), "nothing gained: the caller discards it")
  assertEqual(s.activeSec, 60, "the clock was banked first")
  s = new()
  FM().ApplyGain(s, gain("GOLD", { qty = 500, source = "KILL" }), T0 + 10)
  for i = 1, 2050 do s.log[#s.log + 1] = FM().Pack(i, "d") end
  s.resumeOnLoad, s.wasRunning = true, true
  assertTrue(FM().Close(s, "logout", T0 + 600, "Somewhere"))
  assertEqual(s.endedAt, T0 + 600); assertEqual(s.endReason, "logout")
  assertEqual(s.primaryZone, "Isle of Dorn"); assertEqual(s.name, "Isle of Dorn")
  assertEqual(s.totals.money, 500)
  assertEqual(#s.log, 2000, "trimmed to LOG_CAP")
  assertEqual(s.logDropped, 51)
  for _, k in ipairs({ "runningSince", "pauseReason", "resumeOnLoad", "wasRunning", "mobRing", "mobPos", "lastSeen" }) do
    assertEqual(s[k], nil, k .. " is open-only")
  end
  assertEqual(FM().PausedSec(s), 0)
  local r = new("")
  r.name = "My run"
  FM().ApplyGain(r, gain("XP", { qty = 5 }), T0 + 1)
  FM().Close(r, "stale", T0 + 30, "Somewhere")
  assertEqual(r.primaryZone, "Somewhere"); assertEqual(r.name, "My run", "a renamed session keeps its name")
  local u = new("")
  FM().ApplyGain(u, gain("XP", { qty = 5 }), T0 + 1)
  FM().Close(u, "stale", T0 + 30)
  assertEqual(u.primaryZone, "Unknown")
end)

-- ── the packed log ───────────────────────────────────────────────────────────────────────────

test("FarmModel Pack/Unpack: every kind round-trips, `|` in free text becomes `/`", function()
  local cases = {
    { "i", 210930, 5, "GATHERING" }, { "m", 31200, "KILL" }, { "c", 3008, 40, "KILL" },
    { "r", 2590, -250 }, { "x", 18400 }, { "s", 2873, 57 }, { "a", 0 },
    { "q", 82000, "A Glint of Ore" }, { "o", "REPAIR", 90000, 0, 0 }, { "d" }, { "z", "Isle of Dorn" },
    { "p", "idle" }, { "u" },
  }
  assertEqual(#cases, 13, "all thirteen kinds")
  for _, c in ipairs(cases) do
    local line = FM().Pack(2512, unpack(c))
    local back = { FM().Unpack(line) }
    assertEqual(back[1], 2512, c[1] .. " t")
    for i = 1, #c do assertEqual(back[i + 1], c[i], c[1] .. " field " .. i) end
    assertEqual(#back, #c + 1, c[1] .. " field count")
  end
  assertEqual(FM().Pack(3, "z", "Dorn|Deeps"), "3|z|Dorn/Deeps", "a | is sanitized")
  assertEqual(FM().Pack(2512.9, "i", 210930, 5, "GATHERING"), "2512|i|210930|5|GATHERING", "the spec's line")
  assertEqual(FM().Unpack("1|?|x"), nil, "an unknown kind")
  local long = string.rep("a", 59) .. "\195\169xyz"      -- 59 ASCII then a two-byte é
  local _, _, _, title = FM().Unpack(FM().Pack(0, "q", 1, long))
  assertEqual(title, string.rep("a", 59), "cut to 60 bytes without splitting a character")
end)

test("FarmModel TrimLog: batches of 100 past 2100 while open (2101 -> 2001), exactly 2000 at Finish", function()
  local s = new()
  for i = 1, 2100 do FM().Log(s, T0 + i, "d") end
  assertEqual(#s.log, 2100, "no trim at the threshold")
  FM().Log(s, T0 + 2101, "d")
  assertEqual(#s.log, 2001); assertEqual(s.logDropped, 100)
  assertEqual((FM().Unpack(s.log[1])), 101, "the oldest went")
  assertEqual((FM().Unpack(s.log[#s.log])), 2101, "the newest stayed")
  FM().TrimLog(s, true)
  assertEqual(#s.log, 2000); assertEqual(s.logDropped, 101)
  FM().Log(s, T0 - 50, "d")
  assertEqual((FM().Unpack(s.log[#s.log])), 0, "a stamp before the start reads 0")
end)

test("FarmModel TrimCap: drops the oldest past keep; keep 0 keeps all", function()
  local list = {}
  for i = 1, 103 do list[i] = { id = i } end
  assertEqual(FM().TrimCap(list, 100), 3)
  assertEqual(#list, 100); assertEqual(list[1].id, 4, "oldest first")
  assertEqual(FM().TrimCap(list, 0), 0); assertEqual(#list, 100)
  assertEqual(FM().TrimCap(list, 100), 0)
end)

-- ── totals and rates ─────────────────────────────────────────────────────────────────────────

-- The mockup's running session (mockups.html:518-537): money 152g40s, vendor 38g12s, AH 611g05s,
-- costs 14g20s, elapsed 42:17. Item Y has no AH price, so its vendor price stands in (F8).
local function golden()
  local s = new()
  s.money = { KILL = 1400000, CONTAINER = 124000 }
  s.items = { [1] = { qty = 1, vu = 300000, au = 6029300, src = {} }, [2] = { qty = 1, vu = 81200, src = {} } }
  s.costs = { REPAIR = 90000, BUY = 52000 }
  return s, 2537
end

test("FarmModel Totals: money, vendor, AH with the vendor fallback (F8), costs", function()
  local t = FM().Totals((golden()))
  assertEqual(t.money, 1524000); assertEqual(t.vendor, 381200); assertEqual(t.ah, 6110500); assertEqual(t.costs, 142000)
  local out = {}
  assertTrue(FM().Totals((golden()), out) == out, "fills the table it is handed")
end)

test("FarmModel goldens: the mockup's headline, sub-line and gold-per-hour table", function()
  local s, sec = golden()
  local t, Fm = FM().Totals(s), FM()
  assertEqual(Fm.CopperText(Fm.Value(t, "ah", "gross")), "763g 45s")
  assertEqual(Fm.RateText(Fm.PerHour(Fm.Value(t, "ah", "gross"), sec)), "1,083g")
  assertEqual(Fm.CopperText(Fm.Value(t, "ah", "net")), "749g 25s")
  assertEqual(Fm.RateText(Fm.PerHour(Fm.Value(t, "ah", "net"), sec)), "1,063g")
  local grid = {}
  for _, measure in ipairs({ "money", "vendor", "ah" }) do
    for _, basis in ipairs({ "gross", "net" }) do
      grid[#grid + 1] = Fm.RateText(Fm.PerHour(Fm.Value(t, measure, basis), sec))
    end
  end
  assertEqual(table.concat(grid, " "), "216g 196g 270g 250g 1,083g 1,063g")
  assertEqual(Fm.Clock(sec), "00:42:17")
  assertEqual(Fm.CopperText(t.vendor), "38g 12s"); assertEqual(Fm.CopperText(t.ah), "611g 05s")
  assertEqual(Fm.CopperText(-t.costs), "-14g 20s")
end)

test("FarmModel Value and PerHour: three measures, gross or net; no rate under 60 s", function()
  local t = { money = 100, vendor = 20, ah = 50, costs = 30 }
  assertEqual(FM().Value(t, "money", "gross"), 100); assertEqual(FM().Value(t, "vendor", "gross"), 120)
  assertEqual(FM().Value(t, "ah", "gross"), 150); assertEqual(FM().Value(t, "money", "net"), 70)
  assertEqual(FM().Value(t, "vendor", "net"), 90); assertEqual(FM().Value(t, "ah", "net"), 120)
  assertEqual(FM().PerHour(100, 59), nil); assertEqual(FM().PerHour(100, 60), 6000)
  assertEqual(FM().RateText(nil), "\226\128\148", "a nil rate shows an em dash")
end)

-- ── gains and costs ──────────────────────────────────────────────────────────────────────────

test("FarmModel ApplyGain: the source rule (F4): farm sources count, VENDOR/MAIL/AH and diff OTHER never", function()
  local s = new()
  local function try(fields) return (FM().ApplyGain(s, gain("ITEM", fields), T0 + 1)) end
  local item = { id = 210930, qty = 1, quality = 1, link = "L" }
  local function from(src, origin)
    local f = { source = src, origin = origin or "chat" }
    for k, v in pairs(item) do f[k] = v end
    return f
  end
  for _, src in ipairs({ "KILL", "CONTAINER", "MPLUS", "GATHERING", "FISHING", "QUEST", "BONUS_ROLL", "ROLL" }) do
    assertTrue(try(from(src)), src .. " counts")
  end
  for _, src in ipairs({ "VENDOR", "MAIL", "AH", "TRADE", "CRAFT", "DECONSTRUCT", "UNTRACKED", "TRANSFER" }) do
    assertFalse(try(from(src)), src .. " does not count")
  end
  assertTrue(try(from("OTHER", "chat")), "a chat OTHER counts")
  assertFalse(try(from("OTHER", "diff")), "a diff OTHER never does")
  local loss = from("KILL")
  loss.dir = "OUT"
  assertFalse(try(loss), "a loss never (costs come from the OUT rows)")
  local g = gain("GOLD", { qty = 100, source = "AH" })
  assertFalse((FM().ApplyGain(s, g, T0)), "money from the AH is not farm money")
  g = gain("CURRENCY", { id = 3008, qty = 4, source = "MAIL" })
  assertFalse((FM().ApplyGain(s, g, T0)))
  assertFalse((FM().ApplyGain(s, gain("ITEM", { qty = 1, source = "KILL" }), T0)), "no item id")
  assertFalse((FM().ApplyGain(s, gain("GOLD", { qty = 0, source = "KILL" }), T0)), "nothing gained")
  assertFalse((FM().ApplyGain(s, gain("BOGUS", { qty = 1 }), T0)), "an unknown kind")
end)

test("FarmModel ApplyGain: items tally quantity, sources, quality and the price need", function()
  local s = new()
  local ok, need = FM().ApplyGain(s, gain("ITEM", { id = 210930, qty = 5, quality = 1, link = "L", source = "GATHERING" }), T0 + 4)
  assertTrue(ok); assertEqual(need, 210930, "no row prices: the caller queues a price pass")
  ok, need = FM().ApplyGain(s, gain("ITEM", { id = 210930, qty = 3, quality = 1, source = "KILL" }), T0 + 5, 176, 21000)
  assertTrue(ok); assertEqual(need, nil, "the row's prices filled it")
  local it = s.items[210930]
  assertEqual(it.qty, 8); assertEqual(it.src.GATHERING, 5); assertEqual(it.src.KILL, 3)
  assertEqual(it.vu, 176); assertEqual(it.au, 21000); assertEqual(it.link, "L"); assertEqual(it.q, 1)
  FM().ApplyGain(s, gain("ITEM", { id = 210930, qty = 1, source = "KILL" }), T0 + 6, 999, 999)
  assertEqual(it.vu, 176, "the first known price stays (F7)")
  assertEqual(s.activity.items, 9); assertEqual(s.activity.quality[1], 9)
  assertFalse(FM().SetPrices(s, 210930, 1, 1), "nothing missing")
  FM().ApplyGain(s, gain("ITEM", { id = 5, qty = 1, quality = 4, source = "KILL" }), T0 + 7)
  assertTrue(FM().SetPrices(s, 5, 100, nil)); assertEqual(s.items[5].vu, 100); assertEqual(s.items[5].au, nil)
  assertFalse(FM().SetPrices(s, 6, 1, 1), "no such item")
  assertEqual(kinds(s), "iiii")
end)

test("FarmModel ApplyGain: money keyed by source (id is nil), currencies, and questRewards for QUEST", function()
  local s = new()
  FM().ApplyGain(s, gain("GOLD", { qty = 31200, source = "KILL", name = "Gold" }), T0)
  FM().ApplyGain(s, gain("GOLD", { qty = 800, source = "QUEST" }), T0)
  FM().ApplyGain(s, gain("ITEM", { id = 1, qty = 1, source = "QUEST" }), T0)
  FM().ApplyGain(s, gain("CURRENCY", { id = 3008, qty = 40, source = "QUEST" }), T0)
  FM().ApplyGain(s, gain("CURRENCY", { id = 3008, qty = 2, source = "KILL" }), T0)
  assertEqual(s.money.KILL, 31200); assertEqual(s.money.QUEST, 800)
  assertEqual(s.currencies[3008].qty, 42); assertEqual(s.currencies[3008].src.QUEST, 40)
  assertEqual(s.activity.currency, 42)
  assertEqual(s.activity.questRewards, 3, "one per QUEST item, money and currency line")
  assertEqual(kinds(s), "mmicc")
end)

test("FarmModel ApplyGain: reputation sums signed (dir OUT subtracts), XP, skill from/to, newLook only", function()
  local s = new()
  FM().ApplyGain(s, gain("REPUTATION", { id = 2590, qty = 250, name = "Council" }), T0)
  FM().ApplyGain(s, gain("REPUTATION", { id = 2590, qty = 75, dir = "OUT", source = "VENDOR" }), T0)
  assertEqual(s.activity.rep[2590].delta, 175); assertEqual(s.activity.rep[2590].name, "Council")
  local _, _, _, signed = FM().Unpack(s.log[2])
  assertEqual(signed, -75, "the log keeps the sign")
  FM().ApplyGain(s, gain("XP", { qty = 18400, source = "OTHER", origin = "event" }), T0)
  assertEqual(s.activity.xp, 18400, "XP counts from any source")
  FM().ApplyGain(s, gain("SKILL", { id = 2873, old = 50, new = 52, qty = 2, name = "Khaz Algar Mining" }), T0)
  FM().ApplyGain(s, gain("SKILL", { id = 2873, old = 52, new = 55, qty = 3 }), T0)
  local sk = s.activity.skill[2873]
  assertEqual(sk.from .. ".." .. sk.to, "50..55"); assertEqual(sk.name, "Khaz Algar Mining")
  assertFalse((FM().ApplyGain(s, gain("APPEARANCE", { id = 9, itemID = 7, qty = 1, newLook = false }), T0)), "a known look")
  assertTrue((FM().ApplyGain(s, gain("APPEARANCE", { id = 9, itemID = 7, qty = 1, newLook = true }), T0)))
  assertEqual(s.activity.looks, 1)
  assertEqual(kinds(s), "rrxssa")
end)

test("FarmModel costs: copper by reason and currency spent, each logged; nothing for no amount", function()
  local s = new()
  assertTrue(FM().ApplyCost(s, "REPAIR", 90000, T0 + 1))
  FM().ApplyCost(s, "REPAIR", 10000, T0 + 2)
  FM().ApplyCost(s, "BUY", 5000, T0 + 3)
  assertFalse(FM().ApplyCost(s, "BUY", 0, T0 + 3))
  assertTrue(FM().ApplyCurrencyCost(s, 3008, 20, T0 + 4))
  assertFalse(FM().ApplyCurrencyCost(s, nil, 20, T0 + 4))
  assertEqual(s.costs.REPAIR, 100000); assertEqual(s.costs.BUY, 5000); assertEqual(s.costCurrencies[3008], 20)
  assertEqual(FM().Totals(s).costs, 105000)
  local _, k, reason, copper, cid, qty = FM().Unpack(s.log[4])
  assertEqual(table.concat({ k, reason, copper, cid, qty }, ","), "o,BUY,0,3008,20")
end)

-- ── the corpse ring ──────────────────────────────────────────────────────────────────────────

test("FarmModel NoteMob: each corpse once, the ring evicts the oldest at 257, MobSet rebuilds", function()
  local s, set = new(), {}
  assertTrue(FM().NoteMob(s, set, "Creature-1"))
  assertFalse(FM().NoteMob(s, set, "Creature-1"), "the same corpse (a skinning window) adds nothing")
  for i = 2, 256 do FM().NoteMob(s, set, "Creature-" .. i) end
  assertEqual(s.activity.mobs, 256); assertTrue(set["Creature-1"])
  FM().NoteMob(s, set, "Creature-257")
  assertEqual(set["Creature-1"], nil, "the 257th evicts the first")
  assertEqual(s.mobRing[1], "Creature-257"); assertEqual(s.activity.mobs, 257)
  assertTrue(FM().NoteMob(s, set, "Creature-1"), "an evicted corpse counts again")
  local rebuilt, n = FM().MobSet(s), 0
  for _ in pairs(rebuilt) do n = n + 1 end
  assertEqual(n, 256); assertTrue(rebuilt["Creature-257"])
end)

-- ── best per zone ────────────────────────────────────────────────────────────────────────────

test("FarmModel BestPerZone: the best gross rate per zone, 60 s eligible, a tie to the earlier", function()
  local function done(id, zone, sec, money, startedAt)
    return { id = id, primaryZone = zone, activeSec = sec, startedAt = startedAt or id,
             totals = { money = money, vendor = 0, ah = 0, costs = 0 } }
  end
  local list = {
    done(1, "Isle of Dorn", 3600, 1000), done(2, "Isle of Dorn", 1800, 1000),
    done(3, "Ringing Deeps", 3600, 500), done(4, "Ringing Deeps", 3600, 500),
    done(5, "Hallowfall", 59, 999999), done(6, "Hallowfall", 600, 10),
  }
  local ids = FM().BestPerZone(list, "money")
  local got = {}
  for id in pairs(ids) do got[#got + 1] = id end
  table.sort(got)
  assertEqual(table.concat(got, ","), "2,3,6", "2 out-rates 1; 3 ties 4 and is earlier; 5 is under a minute")
end)

-- ── activity lines (§6) ─────────────────────────────────────────────────────────────────────

local ALL_ON = { mobs = true, items = true, nodes = true, fish = true, quests = true, questRewards = true,
  containers = true, quality = true, rep = true, xp = true, skill = true, looks = true, currency = true,
  deaths = true }

test("FarmModel activity: the fourteen lines in §6 order, sums for quality, rep and skill", function()
  local s = new()
  local a = s.activity
  a.mobs, a.deaths, a.xp, a.currency = 58, 2, 18400, 40
  a.quality[3], a.quality[4], a.quality[5] = 9, 2, 1
  a.rep[1] = { name = "A", delta = 1500 }; a.rep[2] = { name = "B", delta = -260 }
  a.skill[1] = { name = "Mining", from = 10, to = 14 }; a.skill[2] = { name = "Herb", from = 3, to = 4 }
  local got = {}
  for i, line in ipairs(FM().ActivityLines(a, ALL_ON, false)) do got[i] = line.key .. "=" .. line.text end
  local want = { "mobs=58", "items=0", "nodes=0", "fish=0", "quests=0", "questRewards=0", "containers=0",
    "quality=3", "rep=+1,240", "xp=+18,400", "skill=5" }
  if NS.Constants.FEATURE.appearances then want[#want + 1] = "looks=0" end
  want[#want + 1] = "currency=40"; want[#want + 1] = "deaths=2"
  assertEqual(table.concat(got, ","), table.concat(want, ","), "looks only where the client has appearances")
  assertEqual(FM().ActivityValue(a, "quality"), 3, "Epic+ is quality 4 and up")
end)

test("FarmModel activity: a line off is skipped, hideZero drops the zeros, nil enabled draws none", function()
  local a = new().activity
  a.mobs, a.items = 3, 0
  local lines = FM().ActivityLines(a, { mobs = true, items = true, deaths = false }, false)
  assertEqual(#lines, 2)
  lines = FM().ActivityLines(a, { mobs = true, items = true }, true, lines)
  assertEqual(#lines, 1, "the out table is reused and cleared")
  assertEqual(lines[1].label, "Mobs looted")
  assertEqual(#FM().ActivityLines(a, nil, false), 0)
end)

-- ── formatters ───────────────────────────────────────────────────────────────────────────────

test("FarmModel formatters: clock, h:mm, grouped and signed counts, copper text, day label", function()
  assertEqual(FM().Clock(0), "00:00:00"); assertEqual(FM().Clock(3725), "01:02:05")
  assertEqual(FM().Short(2537), "0:42"); assertEqual(FM().Short(7260), "2:01")
  assertEqual(FM().Grouped(1240), "1,240"); assertEqual(FM().Grouped(1234567), "1,234,567"); assertEqual(FM().Grouped(-1000), "-1,000")
  assertEqual(FM().Signed(1240), "+1,240"); assertEqual(FM().Signed(-30), "-30"); assertEqual(FM().Signed(0), "0")
  assertEqual(FM().CopperText(0), "0c"); assertEqual(FM().CopperText(5500), "55s"); assertEqual(FM().CopperText(31207), "3g 12s 07c")
  assertEqual(FM().CopperText(12345678), "1,234g 56s 78c")
  local t = os.time({ year = 2026, month = 11, day = 27, hour = 12 })
  assertEqual(FM().DayLabel(t), "27 Nov")
end)
