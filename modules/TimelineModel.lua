local _, NS = ...
NS.TimelineModel = NS.TimelineModel or {}
local TM = NS.TimelineModel

-- The Timeline's model (timeline-ledger spec §8.1): everything the tab draws, computed without a
-- frame. The view (modules/Timeline.lua) only paints what Build returns, so every rule the spec states
-- -- carry-forward, genesis start, the line cap, the Character filter, dashed partial stretches, the
-- ledgerSince marker, intraday points for Today / 7 d -- is pinned headless in tests/test_timeline.lua.
--
-- Daily points sit at each day's local midnight and carry that day's CLOSE (the balance at the end of
-- the day as far as the addon saw). A day with no cell carries the previous close forward.

local DAY = 86400
local MAX_DAYS = 4000         -- an 11-year "All" is the ceiling of one day walk
TM.TOTAL = "__total"

local function C() return NS.Constants.TIMELINE end

-- ── days ──

function TM.DayStart(day)
  local y, m, d = day:match("^(%d+)-(%d+)-(%d+)$")
  return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0, min = 0, sec = 0 })
end

-- +26 h rides over a 25-hour daylight-saving day without skipping or repeating a date.
function TM.NextDay(day) return NS.Ledger.DayKey(TM.DayStart(day) + DAY + 7200) end

function TM.SortedDays(daily)
  local out = {}
  for k in pairs(daily or {}) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local function closeOn(daily, day, holder, key)
  local d = daily[day]
  local cell = d and d[holder] and d[holder][key]
  return cell and cell.c
end

function TM.CloseBefore(daily, days, holder, key, day)
  for i = #days, 1, -1 do
    if days[i] < day then
      local c = closeOn(daily, days[i], holder, key)
      if c ~= nil then return c end
    end
  end
  return nil
end

function TM.DailySeries(daily, days, holder, key, fromDay, toDay, genesisDay)
  local day = (genesisDay and genesisDay > fromDay) and genesisDay or fromDay
  local carry = TM.CloseBefore(daily, days, holder, key, day)
  local pts, n = {}, 0
  while day <= toDay and n < MAX_DAYS do
    local c = closeOn(daily, day, holder, key)
    if c ~= nil then carry = c end
    if carry ~= nil then pts[#pts + 1] = { x = TM.DayStart(day), y = carry } end
    day, n = TM.NextDay(day), n + 1
  end
  return pts
end

-- ── series arithmetic ──

function TM.ValueAt(points, x)
  local lo, hi, ans = 1, #points, nil
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if points[mid].x <= x then ans, lo = points[mid].y, mid + 1 else hi = mid - 1 end
  end
  return ans
end

function TM.TotalSeries(list)
  local xs, seen = {}, {}
  for _, pts in ipairs(list) do
    for _, pt in ipairs(pts) do
      if not seen[pt.x] then seen[pt.x] = true; xs[#xs + 1] = pt.x end
    end
  end
  table.sort(xs)
  local out = {}
  for _, x in ipairs(xs) do
    local sum = 0
    for _, pts in ipairs(list) do sum = sum + (TM.ValueAt(pts, x) or 0) end
    out[#out + 1] = { x = x, y = sum }
  end
  return out
end

-- ── who gets a line ──

function TM.RankHolders(latest, candidates, allowed, cap)
  if allowed and next(allowed) == nil then allowed = nil end
  local list = {}
  for _, h in ipairs(candidates) do
    if not allowed or allowed[h] then list[#list + 1] = h end
  end
  table.sort(list, function(a, b)
    local va, vb = latest[a] or 0, latest[b] or 0
    if va ~= vb then return va > vb end
    return a < b
  end)
  for i = #list, (cap or #list) + 1, -1 do list[i] = nil end
  return list
end

function TM.Latest(key)
  local _, rows = NS.Holdings:Total(key)
  local m = {}
  for _, r in ipairs(rows) do m[r.holder] = r.count end
  return m
end

function TM.Meta(holder)
  local e = NS.Holdings:Get(holder)
  return (e and e.meta) or {}
end

local function candidates(daily, days, key, fromDay, toDay, latest)
  local set, out = {}, {}
  for h in pairs(latest) do set[h] = true end
  for _, d in ipairs(days) do
    if d >= fromDay and d <= toDay then
      for h, things in pairs(daily[d]) do if things[key] then set[h] = true end end
    end
  end
  for h in pairs(set) do out[#out + 1] = h end
  table.sort(out)
  return out
end

-- ── intraday (Today / 7 d) ──

local function sideOf(path) return path and path:match("^(.-)/") end

function TM.RowDelta(r, holder)
  if NS.Util.RowHolder(r) ~= holder then return 0 end
  local dir, q = NS.Util.RowDir(r), r.quantity or 0
  if dir == "IN" then return q end
  if dir == "OUT" then return -q end
  local fromH, toH = sideOf(r.from), sideOf(r.to)
  if fromH == toH then return 0 end
  if toH == holder then return q end
  if fromH == holder then return -q end
  return 0
end

-- Rebuilt backwards from the balance the holder has NOW, undoing each row of this thing newest first,
-- so it needs no stored snapshot. Two checks keep it honest: the balance it arrives at for `from` must
-- not be negative, and must equal the rollup's close before that day when there is one. Either failing
-- answers nil and the caller draws daily points instead (plan "Phase 2 contract", item 4).
function TM.IntradaySeries(history, holder, key, from, now, current, anchor)
  local bal, pts = current, { { x = now, y = current } }
  for i = #history, 1, -1 do
    local r = history[i]
    if (r.ts or 0) < from then break end
    if NS.Ledger.RowThingKey(r) == key then
      local d = TM.RowDelta(r, holder)
      if d ~= 0 then
        pts[#pts + 1] = { x = r.ts, y = bal }
        bal = bal - d
        pts[#pts + 1] = { x = r.ts, y = bal }
      end
    end
  end
  if bal < 0 or (anchor ~= nil and anchor ~= bal) then return nil end
  pts[#pts + 1] = { x = from, y = bal }
  local out = {}
  for i = #pts, 1, -1 do out[#out + 1] = pts[i] end
  return out
end

function TM.IntradayOK(range, from, now, retentionDays, ledgerSince)
  if range ~= "today" and range ~= "7d" then return false end
  if retentionDays and retentionDays > 0 and from < now - retentionDays * DAY then return false end
  return ledgerSince ~= nil and from >= ledgerSince
end

-- ── decorations ──

function TM.Flows(daily, days, holders, key, fromDay, toDay)
  local set, out = {}, {}
  for _, h in ipairs(holders) do set[h] = true end
  for _, d in ipairs(days) do
    if d >= fromDay and d <= toDay then
      local i, o = 0, 0
      for h, things in pairs(daily[d]) do
        local cell = set[h] and things[key]
        if cell then i, o = i + (cell.i or 0), o + (cell.o or 0) end
      end
      if i > 0 or o > 0 then out[#out + 1] = { x = TM.DayStart(d), day = d, i = i, o = o } end
    end
  end
  return out
end

function TM.DashRange(meta, now)
  if not meta.genesis then return nil, nil end
  if meta.completeAt then return meta.genesis, meta.completeAt end
  if meta.partial then return meta.genesis, now end
  return nil, nil
end

function TM.Label(holder)
  if holder == TM.TOTAL then return "Total" end
  return NS.LedgerFormat.HolderLabel(holder)   -- "Warband" for the warband (Phase 2)
end

function TM.Color(holder, meta)
  if holder == NS.Constants.WARBAND_HOLDER then return C().WARBAND end
  local cc = meta and meta.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[meta.classFile]
  if cc then return { cc.r, cc.g, cc.b, 1 } end
  return C().OTHER
end

function TM.FormatValue(kind, v)
  v = v or 0
  if kind == "GOLD" then
    if v == 0 then return "0" end
    return NS.Util.FormatMoney(v)
  end
  return tostring(math.floor(v + 0.5))
end

function TM.Suggest(text, things, limit)
  local t, out = (text or ""):lower(), {}
  for _, th in ipairs(things) do
    if t == "" or th.name:lower():find(t, 1, true) then out[#out + 1] = th end
  end
  table.sort(out, function(a, b)
    if (a.key == "g") ~= (b.key == "g") then return a.key == "g" end
    if (a.total or 0) ~= (b.total or 0) then return (a.total or 0) > (b.total or 0) end
    return a.name < b.name
  end)
  for i = #out, (limit or 8) + 1, -1 do out[i] = nil end
  return out
end

-- ── Build ──

local function window(p)
  local days = TM.SortedDays(p.daily)
  local from = p.from
  if not from then
    from = p.ledgerSince or p.now
    if days[1] then from = math.min(from, TM.DayStart(days[1])) end
  end
  local fromDay = NS.Ledger.DayKey(from)
  return { days = days, from = TM.DayStart(fromDay), fromDay = fromDay, toDay = NS.Ledger.DayKey(p.now) }
end

local function holderSeries(p, w, h, key, pts)
  local meta = TM.Meta(h)
  local dashFrom, dashTo = TM.DashRange(meta, p.now)
  if not pts then
    local gDay = meta.genesis and NS.Ledger.DayKey(meta.genesis) or nil
    pts = TM.DailySeries(p.daily, w.days, h, key, w.fromDay, w.toDay, gDay)
  end
  return { holder = h, label = TM.Label(h), color = TM.Color(h, meta), thickness = C().LINE_W,
    points = pts, dashFrom = dashFrom, dashTo = dashTo }
end

-- All shown holders intraday, or none: mixing event-time points with midnight points would make the
-- Total sum two different clocks.
local function tryIntraday(p, w, shown, key)
  if not TM.IntradayOK(p.range, w.from, p.now, p.retentionDays, p.ledgerSince) then return nil end
  local out = {}
  for _, h in ipairs(shown) do
    local meta = TM.Meta(h)
    local start = math.max(w.from, meta.genesis or w.from)
    local anchor = TM.CloseBefore(p.daily, w.days, h, key, w.fromDay)
    local pts = TM.IntradaySeries(p.history or {}, h, key, start, p.now, w.latest[h] or 0, anchor)
    if not pts then return nil end
    out[h] = pts
  end
  return out
end

local function hoverDays(w)
  local xs, day, n = {}, w.fromDay, 0
  while day <= w.toDay and n < MAX_DAYS do
    xs[#xs + 1] = TM.DayStart(day)
    day, n = TM.NextDay(day), n + 1
  end
  return xs
end

local function markers(p, xMin, xMax)
  local out = {}
  local s = p.ledgerSince
  if s and s >= xMin and s <= xMax then out[1] = { x = s, dashed = true, color = C().MARKER } end
  return out
end

function TM.Build(p)
  local key = p.thing or "g"
  local kind = NS.Ledger.ParseThingKey(key) or "GOLD"
  local w = window(p)
  w.latest = TM.Latest(key)
  local shown = TM.RankHolders(w.latest, candidates(p.daily, w.days, key, w.fromDay, w.toDay, w.latest),
    p.allowed, p.maxLines or 8)
  local intra = tryIntraday(p, w, shown, key)
  local series, lists = {}, {}
  for _, h in ipairs(shown) do
    local s = holderSeries(p, w, h, key, intra and intra[h])
    series[#series + 1] = s
    lists[#lists + 1] = s.points
  end
  series[#series + 1] = { holder = TM.TOTAL, label = "Total", color = C().TOTAL, thickness = C().TOTAL_W,
    points = TM.TotalSeries(lists) }
  local xMin = w.from
  local xMax = intra and p.now or math.max(TM.DayStart(w.toDay), xMin + DAY)
  local flows = TM.Flows(p.daily, w.days, shown, key, w.fromDay, w.toDay)
  local flowByX = {}
  for _, f in ipairs(flows) do flowByX[f.x] = f end
  return { key = key, kind = kind, title = NS.Holdings:Describe(key).name, mode = intra and "intraday" or "daily",
    now = p.now, xMin = xMin, xMax = xMax, series = series, flows = flows, flowByX = flowByX,
    hoverXs = hoverDays(w), markers = markers(p, xMin, xMax) }
end

function TM.HoverLines(m, i)
  local x = m and m.hoverXs[i]
  if not x then return nil end
  local xEnd = math.min(x + DAY - 1, m.now)
  local out = { title = date("%d %b %Y", x), rows = {} }
  for _, s in ipairs(m.series) do
    local v = TM.ValueAt(s.points, xEnd)
    if v ~= nil then out.rows[#out.rows + 1] = { label = s.label, text = TM.FormatValue(m.kind, v), color = s.color } end
  end
  local f = m.flowByX[x]
  out.gain = TM.FormatValue(m.kind, f and f.i or 0)
  out.loss = TM.FormatValue(m.kind, f and f.o or 0)
  return out
end

function TM.ChartData(m)
  local scale = (m.kind == "GOLD") and (1 / 10000) or 1
  local series = {}
  for i, s in ipairs(m.series) do
    local pts = {}
    for j, pt in ipairs(s.points) do pts[j] = { x = pt.x, y = pt.y * scale } end
    series[i] = { points = pts, color = s.color, thickness = s.thickness, dashFrom = s.dashFrom, dashTo = s.dashTo }
  end
  return { xMin = m.xMin, xMax = m.xMax, integer = m.kind ~= "GOLD", series = series,
    markers = m.markers, hoverXs = m.hoverXs }
end
