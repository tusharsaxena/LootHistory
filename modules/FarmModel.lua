local _, NS = ...
NS.FarmModel = NS.FarmModel or {}
local M = NS.FarmModel
local C = NS.Constants

-- modules/FarmModel.lua — farm mode's pure session model (#39, farm spec
-- docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §4, §5). PURE: no client read, no store
-- read, no frame, no bus. Every function takes the session table (or the values) it works on and the
-- clock the caller read, so tests/test_farm_model.lua drives each rule with plain tables. The runtime
-- (modules/Farm.lua, M4.1b) owns the store, the events, the deferrals and the messages.
--
--   M.New(now, id, char, classFile, zone)       a fresh open session (§4.2), running from `now`
--   M.Elapsed / PausedSec / Bank / BankZone / Pause / Resume / IdleAt / SetZone      the clock (§5.2)
--   M.PrimaryZone / Close                       Finish's pure half (§5.4)
--   M.Pack / Unpack / Log / TrimLog / TrimCap   the packed log and the two caps (§4.3)
--   M.Totals / Value / PerHour                  the sums and the rates (§5.3, F8)
--   M.ApplyGain / SetPrices / ApplyCost / ApplyCurrencyCost      the tallies (§5.5, §5.6, F4)
--   M.NoteMob / MobSet                          the corpse ring (§5.7)
--   M.BestPerZone                               the sessions list's star (§5.9)
--   M.Clock / Short / Grouped / Signed / RateText / CopperText / DayLabel        display formatters
--
-- Binds NS.Constants at load only (C.FARM, C.SourceType); date() is read at call time.

M.VERSION = 1          -- a session's own shape stamp (`v`); a later reshape migrates by it

local floor, max, min = math.floor, math.max, math.min

local function F() return C.FARM end

-- ── the session ──────────────────────────────────────────────────────────────────────────────

local function newActivity()
  return { mobs = 0, items = 0, nodes = 0, fish = 0, quests = 0, questRewards = 0, containers = 0,
           quality = {}, rep = {}, xp = 0, skill = {}, looks = 0, currency = 0, deaths = 0 }
end

--- A fresh open session, running from `now` in `zone` ("" when unknown). `zoneOrder` keeps the zones
--- in the order first seen, which PrimaryZone's tie rule reads.
function M.New(now, id, char, classFile, zone)
  zone = zone or ""
  local s = {
    v = M.VERSION, id = id, name = "", char = char, classFile = classFile,
    startedAt = now, activeSec = 0, runningSince = now, lastSeen = now,
    zone = zone, zoneSince = now, zoneSec = {}, zoneOrder = {},
    items = {}, money = {}, currencies = {}, costs = {}, costCurrencies = {},
    activity = newActivity(), log = {}, logDropped = 0, mobRing = {}, mobPos = 0,
  }
  if zone ~= "" then s.zoneSec[zone], s.zoneOrder[1] = 0, zone end
  return s
end

-- ── the clock (§5.2) ─────────────────────────────────────────────────────────────────────────

--- Active seconds at `now`: the banked seconds plus the running stretch.
function M.Elapsed(s, now)
  return s.activeSec + (s.runningSince and max(0, now - s.runningSince) or 0)
end

--- A finished session's paused seconds: its wall span less its active seconds.
function M.PausedSec(s)
  return max(0, ((s.endedAt or s.startedAt) - s.startedAt) - s.activeSec)
end

--- Bank the current zone's running seconds up to `at`, and restart its stretch there.
function M.BankZone(s, at)
  if s.runningSince and s.zone ~= "" then
    local from = max(s.zoneSince or s.runningSince, s.runningSince)
    s.zoneSec[s.zone] = (s.zoneSec[s.zone] or 0) + max(0, at - from)
  end
  s.zoneSince = at
end

--- Stop the clock at `at` (never before it started), banking the stretch. A paused session is left.
function M.Bank(s, at)
  if not s.runningSince then return end
  at = max(at, s.runningSince)
  M.BankZone(s, at)
  s.activeSec = s.activeSec + (at - s.runningSince)
  s.runningSince = nil
end

--- Pause for `reason` ("manual"|"idle"|"afk"|"standDown"), the clock banked at `at`; logs `p`.
function M.Pause(s, reason, at)
  M.Bank(s, at)
  s.pauseReason = reason
  M.Log(s, at, "p", reason)
end

--- Start the clock again at `now`; logs `u`.
function M.Resume(s, now)
  s.runningSince, s.zoneSince, s.pauseReason = now, now, nil
  M.Log(s, now, "u")
end

--- Whether the idle rule pauses a running session at `now` with `idleMinutes` (0 = off): answers the
--- time to bank back to (the last gain, or the clock's start with none, F2/D16), else nil.
function M.IdleAt(s, now, idleMinutes)
  if not s.runningSince or not idleMinutes or idleMinutes <= 0 then return nil end
  local last = s.lastGainAt or s.runningSince
  if now - last < idleMinutes * 60 then return nil end
  return max(s.runningSince, last)
end

--- Enter `zone` at `now`: the old zone banked, the new one remembered and logged (`z`). An empty or
--- unchanged zone changes nothing. Answers whether it changed.
function M.SetZone(s, zone, now)
  if not zone or zone == "" or zone == s.zone then return false end
  M.BankZone(s, now)
  s.zone = zone
  if s.zoneSec[zone] == nil then
    s.zoneSec[zone] = 0
    s.zoneOrder[#s.zoneOrder + 1] = zone
  end
  M.Log(s, now, "z", zone)
  return true
end

--- The zone with the most active seconds; a tie goes to the zone seen first. nil with none.
function M.PrimaryZone(s)
  local best, bestSec
  for _, zone in ipairs(s.zoneOrder or {}) do
    local sec = s.zoneSec[zone] or 0
    if not bestSec or sec > bestSec then best, bestSec = zone, sec end
  end
  return best
end

-- The fields a finished session no longer carries (§5.4).
local OPEN_ONLY = { "runningSince", "pauseReason", "resumeOnLoad", "wasRunning", "mobRing", "mobPos", "lastSeen" }

--- Finish's pure half at `at`: the clock banked, then false when the log is empty (F6: the caller
--- discards it). Otherwise the end stamps, the primary zone (else the current zone, else
--- `fallbackZone`, else "Unknown"), the name unless renamed, the totals snapshot, the log trimmed to
--- LOG_CAP and the open-only fields cleared; answers true.
function M.Close(s, reason, at, fallbackZone)
  M.Bank(s, at)
  if #s.log == 0 then return false end
  s.endedAt, s.endReason = at, reason
  local zone = M.PrimaryZone(s)
  if not zone and s.zone ~= "" then zone = s.zone end
  s.primaryZone = zone or fallbackZone or "Unknown"
  if s.name == "" then s.name = s.primaryZone end
  s.totals = M.Totals(s)
  M.TrimLog(s, true)
  for _, k in ipairs(OPEN_ONLY) do s[k] = nil end
  return true
end

-- ── the packed log (§4.3) ────────────────────────────────────────────────────────────────────

-- Each kind's fields: "n" a number, "s" free text.
M.LOG_FIELDS = {
  i = { "n", "n", "s" },      -- itemID, qty, source
  m = { "n", "s" },           -- copper, source
  c = { "n", "n", "s" },      -- currencyID, qty, source
  r = { "n", "n" },           -- factionID, signed delta
  x = { "n" },                -- amount
  s = { "n", "n" },           -- lineID, newLevel
  a = { "n" },                -- itemID or 0
  q = { "n", "s" },           -- questID, title (cut to 60)
  o = { "s", "n", "n", "n" }, -- reason, copper, currencyID or 0, qty or 0
  d = {},                     -- died
  z = { "s" },                -- zone name
  p = { "s" },                -- pause reason
  u = {},                     -- resumed
}
M.TITLE_MAX = 60

-- Cut `s` to at most `n` bytes without splitting a UTF-8 character.
local function cutUTF8(s, n)
  if #s <= n then return s end
  local cut = n
  while cut > 0 do
    local b = s:byte(cut + 1)
    if not b or b < 0x80 or b >= 0xC0 then break end
    cut = cut - 1
  end
  return s:sub(1, cut)
end

local function packField(kind, v)
  if kind == "n" then return tostring(floor(tonumber(v) or 0)) end
  return (tostring(v or ""):gsub("|", "/"))
end

--- One log line: `<t>|<k>|<fields...>`, `t` whole seconds. A `|` inside free text becomes `/`.
function M.Pack(t, k, ...)
  local spec = M.LOG_FIELDS[k]
  local parts = { tostring(floor(t)), k }
  for i = 1, #spec do
    local v = select(i, ...)
    if k == "q" and i == 2 then v = cutUTF8(tostring(v or ""), M.TITLE_MAX) end
    parts[#parts + 1] = packField(spec[i], v)
  end
  return table.concat(parts, "|")
end

--- The line back: t, k, then each field (numbers as numbers). nil for an unknown kind.
function M.Unpack(line)
  local raw = {}
  for part in (line .. "|"):gmatch("([^|]*)|") do raw[#raw + 1] = part end
  local spec = M.LOG_FIELDS[raw[2]]
  if not spec then return nil end
  local out = { tonumber(raw[1]) or 0, raw[2] }
  for i = 1, #spec do
    local v = raw[i + 2]
    if spec[i] == "n" then v = tonumber(v) or 0 else v = v or "" end
    out[i + 2] = v
  end
  return unpack(out, 1, #spec + 2)
end

-- Drop the oldest `n` lines in place, counted in logDropped.
local function dropOldest(s, n)
  local log, len = s.log, #s.log
  for i = 1, len - n do log[i] = log[i + n] end
  for i = len, len - n + 1, -1 do log[i] = nil end
  s.logDropped = (s.logDropped or 0) + n
end

--- The two log trims: while open, past LOG_CAP + LOG_BATCH the oldest LOG_BATCH go; `exact` (Finish)
--- trims to LOG_CAP. Totals never read the log, so a trim changes no total.
function M.TrimLog(s, exact)
  local cap, batch, len = F().LOG_CAP, F().LOG_BATCH, #s.log
  if exact then
    if len > cap then dropOldest(s, len - cap) end
  elseif len > cap + batch then
    dropOldest(s, batch)
  end
end

--- Append one line at `now` (seconds since startedAt, never negative), then the batch trim.
function M.Log(s, now, k, ...)
  s.log[#s.log + 1] = M.Pack(max(0, now - s.startedAt), k, ...)
  M.TrimLog(s)
end

--- The saved-sessions cap: drop the oldest while `keep > 0` and there are more. Answers how many.
function M.TrimCap(sessions, keep)
  local n = (keep and keep > 0) and max(0, #sessions - keep) or 0
  for _ = 1, n do table.remove(sessions, 1) end
  return n
end

-- ── totals and rates (§5.3) ──────────────────────────────────────────────────────────────────

--- { money, vendor, ah, costs } in copper. AH counts the vendor price for an item with no AH price
--- (F8), never Util.RecordValue's max.
function M.Totals(s, out)
  out = out or {}
  local money, vendor, ah, costs = 0, 0, 0, 0
  for _, v in pairs(s.money) do money = money + v end
  for _, it in pairs(s.items) do
    vendor = vendor + it.qty * (it.vu or 0)
    ah = ah + it.qty * (it.au or it.vu or 0)
  end
  for _, v in pairs(s.costs) do costs = costs + v end
  out.money, out.vendor, out.ah, out.costs = money, vendor, ah, costs
  return out
end

--- The value at `measure` ("money"|"vendor"|"ah") and `basis` ("gross"|"net").
function M.Value(t, measure, basis)
  local v = t.money
  if measure ~= "money" then v = v + (t[measure] or 0) end
  if basis == "net" then v = v - t.costs end
  return v
end

--- Per hour, or nil under MIN_RATE_SEC active seconds (drawn "—").
function M.PerHour(value, activeSec)
  if not activeSec or activeSec < F().MIN_RATE_SEC then return nil end
  return value * 3600 / activeSec
end

-- ── tallies (§5.5, §5.6) ─────────────────────────────────────────────────────────────────────

local function add(t, k, n) t[k] = (t[k] or 0) + n end

-- F4: an item, money or currency gain counts from a farm source only, and OTHER only from chat.
local function countsSource(g)
  if not F().GAIN_SOURCES[g.source] then return false end
  return g.source ~= C.SourceType.OTHER or g.origin == "chat"
end

local function questReward(s, g)
  if g.source == C.SourceType.QUEST then s.activity.questRewards = s.activity.questRewards + 1 end
end

local APPLY = {}

function APPLY.ITEM(s, g, now, vu, au)
  local it = s.items[g.id]
  if not it then
    it = { link = g.link, q = g.quality, qty = 0, src = {} }
    s.items[g.id] = it
  end
  if it.vu == nil then it.vu = vu end
  if it.au == nil then it.au = au end
  it.qty = it.qty + g.qty
  add(it.src, g.source, g.qty)
  local a = s.activity
  a.items = a.items + g.qty
  if it.q then add(a.quality, it.q, g.qty) end
  questReward(s, g)
  M.Log(s, now, "i", g.id, g.qty, g.source)
  return true, it.vu == nil and g.id or nil
end

function APPLY.GOLD(s, g, now)
  add(s.money, g.source, g.qty)
  questReward(s, g)
  M.Log(s, now, "m", g.qty, g.source)
  return true
end

function APPLY.CURRENCY(s, g, now)
  local cur = s.currencies[g.id]
  if not cur then cur = { qty = 0, src = {} }; s.currencies[g.id] = cur end
  cur.qty = cur.qty + g.qty
  add(cur.src, g.source, g.qty)
  s.activity.currency = s.activity.currency + g.qty
  questReward(s, g)
  M.Log(s, now, "c", g.id, g.qty, g.source)
  return true
end

function APPLY.REPUTATION(s, g, now)
  local delta = g.dir == "OUT" and -g.qty or g.qty
  local e = s.activity.rep[g.id]
  if not e then e = { name = "", delta = 0 }; s.activity.rep[g.id] = e end
  e.delta, e.name = e.delta + delta, g.name or e.name
  M.Log(s, now, "r", g.id, delta)
  return true
end

function APPLY.XP(s, g, now)
  s.activity.xp = s.activity.xp + g.qty
  M.Log(s, now, "x", g.qty)
  return true
end

function APPLY.SKILL(s, g, now)
  local old, new = g.old or g.new, g.new
  if not new then return false end
  local e = s.activity.skill[g.id]
  if not e then e = { name = "", from = old, to = new }; s.activity.skill[g.id] = e end
  e.from, e.to, e.name = min(e.from, old), max(e.to, new), g.name or e.name
  M.Log(s, now, "s", g.id, new)
  return true
end

function APPLY.APPEARANCE(s, g, now)
  if not g.newLook then return false end
  s.activity.looks = s.activity.looks + 1
  M.Log(s, now, "a", g.itemID or 0)
  return true
end

-- The kinds that carry a thing id, and the three a session counts by source and direction (F4).
local NEEDS_ID = { ITEM = true, CURRENCY = true, REPUTATION = true, SKILL = true }
local BY_SOURCE = { ITEM = true, GOLD = true, CURRENCY = true }

-- Whether `g` is a gain this session tallies at all (before the kind's own rule).
local function admissible(g)
  local apply = APPLY[g.kind]
  if not apply or type(g.qty) ~= "number" or g.qty <= 0 then return nil end
  if NEEDS_ID[g.kind] and g.id == nil then return nil end
  if BY_SOURCE[g.kind] and (g.dir ~= "IN" or not countsSource(g)) then return nil end
  if g.kind == "APPEARANCE" and g.dir ~= "IN" then return nil end
  return apply
end

--- Tally one GAIN payload (§2's fields; `g` is the feed's reused scratch, so nothing of it is kept
--- but values). `vu`/`au` are the caller's per-unit prices for an item gain (from its row), or nil.
--- Answers tallied, and the itemID still needing a price (the caller queues the price pass).
function M.ApplyGain(s, g, now, vu, au)
  local apply = admissible(g)
  if not apply then return false, nil end
  return apply(s, g, now, vu, au)
end

--- Fill an item's missing per-unit prices (the price pass, F7: the first known price stays). Answers
--- whether anything changed.
local function fill(it, key, v)
  if it[key] ~= nil or v == nil then return false end
  it[key] = v
  return true
end

function M.SetPrices(s, itemID, vu, au)
  local it = s.items[itemID]
  if not it then return false end
  local a = fill(it, "vu", vu)
  local b = fill(it, "au", au)
  return a or b
end

--- A cost row's copper `delta` under `reason` (D19); logs `o`. Answers whether it counted.
function M.ApplyCost(s, reason, copper, now)
  if type(copper) ~= "number" or copper <= 0 then return false end
  add(s.costs, reason, copper)
  M.Log(s, now, "o", reason, copper, 0, 0)
  return true
end

--- Currency spent under BUY (no copper value); logs `o`. Answers whether it counted.
function M.ApplyCurrencyCost(s, currencyID, qty, now)
  if currencyID == nil or type(qty) ~= "number" or qty <= 0 then return false end
  add(s.costCurrencies, currencyID, qty)
  M.Log(s, now, "o", C.SourceType.BUY, 0, currencyID, qty)
  return true
end

-- ── the corpse ring (§5.7) ───────────────────────────────────────────────────────────────────

--- Count corpse `guid` once: new to `set`, it is written into the ring (MOB_RING slots, the oldest
--- evicted from `set`) and `mobs` rises. Answers whether it counted.
function M.NoteMob(s, set, guid)
  if set[guid] then return false end
  local ring, size = s.mobRing, F().MOB_RING
  local pos = (s.mobPos % size) + 1
  local old = ring[pos]
  if old then set[old] = nil end
  ring[pos], s.mobPos, set[guid] = guid, s.mobPos + 1, true
  s.activity.mobs = s.activity.mobs + 1
  return true
end

--- The corpse set rebuilt from the ring (a restore after a reload).
function M.MobSet(s, out)
  out = out or {}
  for _, guid in pairs(s.mobRing or {}) do out[guid] = true end
  return out
end

-- ── best per zone (§5.9) ─────────────────────────────────────────────────────────────────────

local function grossRate(s, measure)
  if (s.activeSec or 0) < F().MIN_RATE_SEC then return nil end
  return M.PerHour(M.Value(s.totals or M.Totals(s), measure, "gross"), s.activeSec)
end

-- Whether `s` beats the zone's best so far: a higher rate, a tie to the earlier session.
local function beats(s, rate, best)
  if not best then return true end
  if rate ~= best.rate then return rate > best.rate end
  return s.startedAt < best.s.startedAt
end

--- The ids of each zone's best session at `measure` (gross per hour, eligible from MIN_RATE_SEC
--- active seconds; a tie to the earlier session), as a set.
function M.BestPerZone(sessions, measure)
  local best = {}
  for _, s in ipairs(sessions) do
    local rate, zone = grossRate(s, measure), s.primaryZone
    if rate and zone and beats(s, rate, best[zone]) then best[zone] = { s = s, rate = rate } end
  end
  local ids = {}
  for _, b in pairs(best) do ids[b.s.id] = true end
  return ids
end

-- ── display formatters ───────────────────────────────────────────────────────────────────────

--- Seconds as "hh:mm:ss".
function M.Clock(sec)
  sec = max(0, floor(sec or 0))
  return ("%02d:%02d:%02d"):format(floor(sec / 3600), floor(sec % 3600 / 60), sec % 60)
end

--- Seconds as "h:mm" (the sessions list's Active column).
function M.Short(sec)
  sec = max(0, floor(sec or 0))
  return ("%d:%02d"):format(floor(sec / 3600), floor(sec % 3600 / 60))
end

--- A whole number with thousands grouped by commas ("1,240").
function M.Grouped(n)
  local v = floor((n or 0) + 0.5)
  local digits = tostring(v < 0 and -v or v):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (v < 0 and "-" or "") .. digits
end

--- A signed count: "+1,240", "-30", "0".
function M.Signed(n)
  local v = floor((n or 0) + 0.5)
  return (v > 0 and "+" or "") .. M.Grouped(v)
end

--- A copper-per-hour rate as whole gold ("1,083g"); nil is "—".
function M.RateText(copperPerHour)
  if not copperPerHour then return "\226\128\148" end
  return M.Grouped(floor(copperPerHour / 10000)) .. "g"
end

--- Copper as plain text, "763g 45s" (the non-zero parts; "0c" for none), signed when negative.
function M.CopperText(copper)
  copper = floor(copper or 0)
  local sign = copper < 0 and "-" or ""
  copper = copper < 0 and -copper or copper
  local g, s, c = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = M.Grouped(g) .. "g" end
  if s > 0 then parts[#parts + 1] = ("%02ds"):format(s) end
  if c > 0 then parts[#parts + 1] = ("%02dc"):format(c) end
  if #parts == 0 then return "0c" end
  if g == 0 then parts[1] = parts[1]:gsub("^0", "") end
  return sign .. table.concat(parts, " ")
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

--- An epoch as "27 Nov" (the sessions list's Date column), in the client's local time.
function M.DayLabel(epoch)
  local d = date("*t", epoch)
  return ("%d %s"):format(d.day, MONTHS[d.month])
end
