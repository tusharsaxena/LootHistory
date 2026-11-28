local _, NS = ...
NS.FarmTestData = NS.FarmTestData or {}
local FTD = NS.FarmTestData

-- modules/FarmTestData.lua — test mode's farm half (#39, farm spec §12.3): `FTD.Build(now)` answers a
-- session-only store in db.global.farm's shape, six finished sessions over the History sample's
-- characters (BrowserTable.TestSample.charKey), which modules/TestData.lua's TD.Publish puts in
-- NS.State.testFarm. The Farm tab and the sessions list read it through Farm:ActiveStore(); no write
-- path ever sees it (Farm:Rename and Farm:Delete refuse a test row), and the panel never shows it.
--
-- The sessions: Isle of Dorn three times, the Ringing Deeps twice and Hallowfall once, each zone with
-- one best session (FarmModel.BestPerZone at AH, gross). The three newest reproduce the mockup's
-- "Saved sessions" rows (mockups.html, #39): today 1:12 for 1,466g (1,221g/h), two days back 0:48
-- for 792g (990g/h), three days back 2:05 for 1,750g (840g/h). Each carries 40 log lines.
--
-- Deterministic: the History sample's PRNG under a fixed seed, never math.random, so two builds for
-- one `now` are equal. Read at call time only; it binds nothing at load.

local GOLD = 10000
local SEED = 0x0FA4E5ED
local LOG_LINES = 40
local ITEMS_PER = 4
local SOURCES = { "KILL", "GATHERING", "CONTAINER", "KILL" }

-- class, days back, start hour and minute, zone (then a second zone and its seconds), active and
-- paused seconds, the AH gross total in whole gold.
FTD.SESSIONS = {
  { cls = "MAGE", days = 0, hour = 19, min = 2, zone = "Isle of Dorn", zone2 = "Ringing Deeps", sec2 = 1320,
    active = 4320, paused = 1020, gold = 1466 },
  { cls = "WARRIOR", days = 2, hour = 20, min = 15, zone = "Ringing Deeps", active = 2880, paused = 300, gold = 792 },
  { cls = "MAGE", days = 3, hour = 18, min = 40, zone = "Isle of Dorn", active = 7500, paused = 600, gold = 1750 },
  { cls = "ROGUE", days = 5, hour = 21, min = 5, zone = "Isle of Dorn", active = 3600, paused = 0, gold = 700 },
  { cls = "PRIEST", days = 6, hour = 17, min = 30, zone = "Ringing Deeps", active = 3000, paused = 240, gold = 600 },
  { cls = "WARRIOR", days = 8, hour = 19, min = 45, zone = "Hallowfall", zone2 = "Isle of Dorn", sec2 = 600,
    active = 5400, paused = 900, gold = 1100 },
}

local function sample() return NS.BrowserTable.TestSample end

-- `days` back from `now`'s calendar day, at hour:min local time.
local function startOf(now, spec)
  local d = date("*t", now)
  return time({ year = d.year, month = d.month, day = d.day - spec.days, hour = spec.hour, min = spec.min })
end

-- Four distinct sample items, each a plain item link under the History sample's name and quality.
local function pickItems(rng)
  local names, picked, out = sample().itemNames, {}, {}
  while #out < ITEMS_PER do
    local idBase = rng(#names)
    if not picked[idBase] then
      picked[idBase] = true
      local id = sample().idBase + idBase
      local d = NS.TestData and NS.TestData.Describe and NS.TestData.Describe("i:" .. id)
      out[#out + 1] = { id = id, name = names[idBase], q = d and d.quality or 1 }
    end
  end
  return out
end

-- The items fill about seventy percent of the target and the money the rest, to the copper; the last
-- item has no AH price, so the AH total counts its vendor price (F8).
local function fillGains(rng, s, target, picks)
  local share, itemsAH = math.floor(target * 0.7 / #picks), 0
  for i, p in ipairs(picks) do
    local qty = 1 + rng(40)
    local unit = math.floor(share / qty)
    local vu = math.max(1, math.floor(unit * (5 + rng(25)) / 100))
    local it = { link = ("|Hitem:%d|h[%s]|h"):format(p.id, p.name), q = p.q, qty = qty, src = { [SOURCES[i]] = qty } }
    if i < #picks then it.vu, it.au = vu, unit else it.vu = unit end
    s.items[p.id] = it
    itemsAH = itemsAH + qty * unit
    s.activity.items = s.activity.items + qty
    s.activity.quality[p.q] = (s.activity.quality[p.q] or 0) + qty
  end
  local money = target - itemsAH
  local kill = math.floor(money * 0.7)
  s.money = { KILL = kill, CONTAINER = money - kill }
  s.costs = { REPAIR = rng(15) * GOLD, BUY = rng(10) * GOLD }
end

-- LOG_LINES lines over the active span: item and money gains, a quest, and the move to the second zone.
local function fillLog(rng, s, spec, picks)
  local step = math.floor(spec.active / LOG_LINES)
  for i = 1, LOG_LINES do
    local t, roll = i * step, rng(10)
    if i == LOG_LINES / 2 and spec.zone2 then
      s.log[i] = NS.FarmModel.Pack(t, "z", spec.zone2)
    elseif roll <= 6 then
      local p = picks[rng(#picks)]
      s.log[i] = NS.FarmModel.Pack(t, "i", p.id, rng(5), SOURCES[1 + (p.id % #SOURCES)])
    elseif roll <= 9 then
      s.log[i] = NS.FarmModel.Pack(t, "m", rng(400) * 100, "KILL")
    else
      s.log[i] = NS.FarmModel.Pack(t, "q", 80000 + rng(999), "Sample quest")
    end
  end
end

local function zoneTime(s, spec)
  local second = spec.zone2 and spec.sec2 or 0
  s.zoneSec, s.zoneOrder = { [spec.zone] = spec.active - second }, { spec.zone }
  if spec.zone2 then
    s.zoneSec[spec.zone2], s.zoneOrder[2] = second, spec.zone2
  end
end

local function activity(rng, s)
  local a = s.activity
  a.mobs, a.nodes, a.quests, a.containers = 20 + rng(80), rng(90), rng(6), rng(4)
  a.xp, a.deaths = rng(50) * 1000, rng(3) - 1
end

-- One finished session from its spec, closed the way FarmModel.Close leaves one.
local function session(rng, now, spec, id)
  local FM = NS.FarmModel
  local start = startOf(now, spec)
  local s = FM.New(start, id, sample().charKey(spec.cls), spec.cls, spec.zone)
  local picks = pickItems(rng)
  fillGains(rng, s, spec.gold * GOLD, picks)
  fillLog(rng, s, spec, picks)
  zoneTime(s, spec)
  activity(rng, s)
  s.activeSec = spec.active
  s.endedAt, s.endReason = start + spec.active + spec.paused, "manual"
  s.primaryZone, s.name = spec.zone, spec.zone
  s.zone = spec.zone2 or spec.zone
  s.totals = FM.Totals(s)
  s.runningSince, s.mobRing, s.mobPos, s.lastSeen = nil, nil, nil, nil
  return s
end

--- The sample farm store for `now`: { [charKey] = { sessions (oldest first), nextId } }.
function FTD.Build(now)
  local rng = sample().rng(SEED)
  local store = {}
  for i = #FTD.SESSIONS, 1, -1 do   -- oldest first, so each character's list is in finish order
    local spec = FTD.SESSIONS[i]
    local key = sample().charKey(spec.cls)
    local mine = store[key]
    if not mine then
      mine = { sessions = {}, nextId = 1 }
      store[key] = mine
    end
    mine.sessions[#mine.sessions + 1] = session(rng, now, spec, mine.nextId)
    mine.nextId = mine.nextId + 1
  end
  return store
end
