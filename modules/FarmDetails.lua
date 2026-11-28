local addonName, NS = ...
-- luacheck: ignore 212/self
NS.FarmDetails = NS.FarmDetails or {}
local FD = NS.FarmDetails
local FarmModel = NS.FarmModel  -- load-time upvalue: modules/FarmModel.lua loads above
local FarmList = NS.FarmList    -- load-time upvalue: modules/FarmList.lua loads above
local C = NS.Constants
local L = NS.L

-- modules/FarmDetails.lua — a farm session's two reading windows (#39, farm spec
-- docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §7.3, §7.4; mockups #39 "Details window"
-- and "Summary at Finish").
--
--   LootHistoryFarmDetails   six tabs (Items, Money, Currencies, Costs, Activity, Log), each one
--                            FarmList; resizable, the size ticks relaying the columns only and the
--                            rebind and the save running once, on release; the Log binds only the
--                            visible slice of up to 2000 lines
--   LootHistoryFarmSummary   the finished session at a glance: meta line, headline, sub-totals,
--                            activity, top earners, by source; Details · Close
--
-- Both are SECONDARY WINDOWS (standalone-windows): more than one surface opens them (the panel, the
-- Finish verb and, from M4.4, the Farm tab and the sessions list), so neither is a companion and
-- each carries settings and close. Both sit on C.LAYERS.STRATA.WINDOW (HIGH, frame-layering-§1 T4,
-- the History window's tier), toplevel and clamped, and refuse to show while stood down or while
-- General visibility hides the addon's windows.
--
-- A window shows a session REFERENCE, { store = "live"|"sim"|"test", char, id }, with id nil for
-- the character's open session (FD.Ref, FD.Resolve). The Details window re-reads on FARM_CHANGED
-- (coalesced 0.25 s); one showing the open session follows it into the saved list when it finishes,
-- and either window closes when its session is gone (deleted, discarded, a simulation's store
-- released). `settings.farm.details` ({ point, x, y, w, h }) is the Details window's named
-- non-setting state (§4.5); this file is its only writer.

local DEFAULT_W, DEFAULT_H, MIN_W, MIN_H = 640, 420, 480, 300
local SUMMARY_W = 380
local TITLE_H, TAB_H, TAB_W, PAD, NOTE_H = 30, 26, 90, 10, 18
local COALESCE = 0.25
local BTN_W, BTN_H = 72, 20
local TOP_N = 3

FD.TABS = { "Items", "Money", "Currencies", "Costs", "Activity", "Log" }

-- The reasons a SAVED session's window can be touched by (an open session's moves on every one).
local SAVED_REASONS = { finish = true, rename = true, delete = true, store = true }
local PAUSE_WORDS = { manual = "manual", idle = "idle", afk = "AFK", standDown = "addon disabled" }
local COST_ORDER = { "REPAIR", "BUY", "AH_POST_FEE" }
local COST_WORDS = { REPAIR = "repairs", BUY = "buys", AH_POST_FEE = "AH deposits" }

local details, summary   -- the two frames, built on first show

local function debug(fmt, ...)
  if NS.State.debug and NS.Debug then NS.Debug("UI", fmt, ...) end
end

local function settings() return (NS.db and NS.db.profile and NS.db.profile.settings) or {} end
local function farmSettings() return settings().farm or {} end

local function tint(fs, token)
  local r, g, b = NS.SkinColor(token)
  if r then fs:SetTextColor(r, g, b) end
end

-- Costs need ledger capture (§5.6): OUT gold rows exist only with both switches on.
local function costsTracked()
  local s = settings()
  return s.trackLedger ~= false and s.recordGold ~= false
end

-- ── the session reference ────────────────────────────────────────────────────────────────────

local function storeKind() return (NS.SimStores and NS.SimStores.farm) and "sim" or "live" end

--- A full reference from a partial one: the store the session lists read now (a simulation's while
--- one runs, else the saved one), this character, and `id` (nil: the open session).
function FD.Ref(ref)
  ref = ref or {}
  return { store = ref.store or storeKind(), char = ref.char or NS.Util.PlayerKey(), id = ref.id }
end

local function storeOf(kind)
  if kind == "test" then return NS.State and NS.State.testFarm end
  if kind == "sim" then return NS.SimStores and NS.SimStores.farm end
  return NS.Farm:LiveStore()
end

--- The session `ref` names, or nil when it is gone. A read: it creates nothing.
function FD.Resolve(ref)
  local store = ref and storeOf(ref.store)
  local mine = store and store[ref.char]
  if not mine then return nil end
  if ref.id == nil then return mine.active end
  for _, s in ipairs(mine.sessions or {}) do
    if s.id == ref.id then return s end
  end
  return nil
end

-- ── names, prices and words (pure over the session) ──────────────────────────────────────────

local function linkName(link) return type(link) == "string" and link:match("%[(.-)%]") or nil end

local function itemName(s, id)
  local it = s.items and s.items[id]
  return (it and linkName(it.link)) or ("item " .. tostring(id))
end

local function currencyName(id)
  return (NS.Compat.CurrencyName and NS.Compat.CurrencyName(id)) or ("currency " .. tostring(id))
end

local function sourceLabel(src) return L[C.SourceLabel[src] or tostring(src or "")] end

-- The key with the largest count; a tie goes to the key that sorts first.
local function largest(counts)
  local best, n
  for k, v in pairs(counts or {}) do
    if not n or v > n or (v == n and tostring(k) < tostring(best)) then best, n = k, v end
  end
  return best
end

--- An item's per-unit value at `measure`: none for money, the vendor price, or the AH price with
--- the vendor price standing in (F8).
function FD.UnitAt(it, measure)
  if measure == "vendor" then return it.vu end
  if measure == "ah" then return it.au or it.vu end
  return nil
end

local function perUnit(v) return v and FarmModel.CopperText(v) or L["n/a"] end

-- Whole gold, rounded, for the ranked lists ("445g"); under a gold the copper text.
local function goldText(copper)
  if math.abs(copper) < 10000 then return FarmModel.CopperText(copper) end
  return FarmModel.Grouped(copper / 10000) .. "g"
end

-- Seconds as "1 h 12 m" (or "17 m" under an hour).
local function duration(sec)
  sec = math.max(0, math.floor(sec or 0))
  local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
  if h > 0 then return ("%d h %d m"):format(h, m) end
  return ("%d m"):format(m)
end

local function measureOf() return farmSettings().headlineValue or "ah" end

-- ── the six tabs' rows (pure over the session) ───────────────────────────────────────────────

--- Items: one entry per item, with both per-unit prices, both totals and the largest source.
function FD.ItemRows(s)
  local out = {}
  for id, it in pairs(s.items or {}) do
    out[#out + 1] = { id = id, link = it.link, q = it.q, name = linkName(it.link) or ("item " .. id),
      qty = it.qty, vu = it.vu, au = it.au, vendor = it.qty * (it.vu or 0),
      ah = it.qty * (it.au or it.vu or 0), source = largest(it.src) }
  end
  return out
end

--- Money: one entry per source, with its share of the money looted.
function FD.MoneyRows(s)
  local out, total = {}, 0
  for _, v in pairs(s.money or {}) do total = total + v end
  for src, v in pairs(s.money or {}) do
    out[#out + 1] = { source = src, amount = v, share = total > 0 and v / total or 0 }
  end
  return out
end

--- Currencies: one entry per currency, with its largest source.
function FD.CurrencyRows(s)
  local out = {}
  for id, cur in pairs(s.currencies or {}) do
    out[#out + 1] = { id = id, name = currencyName(id), qty = cur.qty, source = largest(cur.src) }
  end
  return out
end

local function byDesc(field)
  return function(a, b)
    if a[field] ~= b[field] then return a[field] > b[field] end
    return a.label < b.label
  end
end

--- Costs: the copper costs by reason, largest first, then the currency spent, largest first.
function FD.CostRows(s)
  local copper, cur = {}, {}
  for reason, v in pairs(s.costs or {}) do
    copper[#copper + 1] = { label = sourceLabel(reason), amount = v, text = "-" .. FarmModel.CopperText(v), bad = true }
  end
  for id, qty in pairs(s.costCurrencies or {}) do
    cur[#cur + 1] = { label = currencyName(id), amount = qty, text = "x" .. FarmModel.Grouped(qty), id = id }
  end
  table.sort(copper, byDesc("amount"))
  table.sort(cur, byDesc("amount"))
  for _, e in ipairs(cur) do copper[#copper + 1] = e end
  return copper
end

local function sortedPairs(t, value)
  local out = {}
  for k, v in pairs(t or {}) do out[#out + 1] = { k = k, v = v, n = value(v) } end
  table.sort(out, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return tostring(a.k) < tostring(b.k)
  end)
  return out
end

-- How a breakdown ranks its lines: by count, by the size of a reputation swing, by skill points
-- gained, by quantity.
local function plainCount(v) return v end
local function repWeight(v) return math.abs(v.delta or 0) end
local function skillWeight(v) return (v.to or 0) - (v.from or 0) end
local function currencyWeight(v) return v.qty end

local BREAKDOWNS = {
  { key = "quality", heading = "Drops by quality", rows = function(s)
      local out = {}
      for _, p in ipairs(sortedPairs(s.activity.quality, plainCount)) do
        out[#out + 1] = { label = NS.Item.QualityLabel(p.k), text = FarmModel.Grouped(p.v), q = p.k }
      end
      return out
    end },
  { key = "rep", heading = "Reputation by faction", rows = function(s)
      local out = {}
      for _, p in ipairs(sortedPairs(s.activity.rep, repWeight)) do
        local name = (p.v.name ~= "" and p.v.name) or ("faction " .. tostring(p.k))
        out[#out + 1] = { label = name, text = FarmModel.Signed(p.v.delta) }
      end
      return out
    end },
  { key = "skill", heading = "Skill-ups by profession", rows = function(s)
      local out = {}
      for _, p in ipairs(sortedPairs(s.activity.skill, skillWeight)) do
        local name = (p.v.name ~= "" and p.v.name) or ("skill " .. tostring(p.k))
        out[#out + 1] = { label = name, text = ("%d to %d"):format(p.v.from or 0, p.v.to or 0) }
      end
      return out
    end },
  { key = "currency", heading = "Currencies by kind", rows = function(s)
      local out = {}
      for _, p in ipairs(sortedPairs(s.currencies, currencyWeight)) do
        out[#out + 1] = { label = currencyName(p.k), text = FarmModel.Grouped(p.v.qty) }
      end
      return out
    end },
}

--- Activity: every enabled line (§6, zero lines included), then the breakdowns of the enabled
--- quality, reputation, skill and currency lines, each a heading and its indented lines.
function FD.ActivityRows(s, enabled)
  local out = {}
  for _, line in ipairs(FarmModel.ActivityLines(s.activity, enabled, false)) do
    out[#out + 1] = { label = L[line.label], text = line.text }
  end
  for _, b in ipairs(BREAKDOWNS) do
    local rows = (enabled and enabled[b.key]) and b.rows(s) or {}
    if #rows > 0 then
      out[#out + 1] = { label = L[b.heading], text = "", heading = true }
      for _, e in ipairs(rows) do
        e.label, e.indent = "    " .. e.label, true
        out[#out + 1] = e
      end
    end
  end
  return out
end

-- ── the Log (§4.3): one line decoded per bound row ───────────────────────────────────────────

local LOG = {}
function LOG.i(s, m, id, qty, src)
  local it = s.items and s.items[id]
  local unit = it and FD.UnitAt(it, m)
  return itemName(s, id) .. " x" .. FarmModel.Grouped(qty), unit and FarmModel.CopperText(qty * unit) or "",
    sourceLabel(src)
end
function LOG.m(_, _, copper, src)
  return FarmModel.CopperText(copper) .. " " .. L["looted"], FarmModel.CopperText(copper), sourceLabel(src)
end
function LOG.c(_, _, id, qty, src)
  return currencyName(id) .. " x" .. FarmModel.Grouped(qty), "", sourceLabel(src)
end
function LOG.r(s, _, id, delta)
  local e = s.activity and s.activity.rep[id]
  local name = (e and e.name ~= "" and e.name) or ("faction " .. tostring(id))
  return name .. " " .. FarmModel.Signed(delta), "", ""
end
function LOG.x(_, _, n) return L["Experience"] .. " " .. FarmModel.Signed(n), "", "" end
function LOG.s(s, _, id, level)
  local e = s.activity and s.activity.skill[id]
  local name = (e and e.name ~= "" and e.name) or ("skill " .. tostring(id))
  return name .. " " .. tostring(level), "", ""
end
function LOG.a(s, _, id)
  return L["New appearance"] .. ": " .. (id > 0 and itemName(s, id) or L["Unknown"]), "", ""
end
function LOG.q(_, _, id, title)
  if title == "" then title = "quest " .. tostring(id) end
  return L["Quest turned in"] .. ": " .. title, "", sourceLabel(C.SourceType.QUEST)
end
function LOG.o(_, _, reason, copper, currencyID, qty)
  local what = sourceLabel(reason)
  if currencyID > 0 then
    return what .. ": " .. currencyName(currencyID) .. " x" .. FarmModel.Grouped(qty), "", L["Cost"]
  end
  return what, "-" .. FarmModel.CopperText(copper), L["Cost"]
end
function LOG.d() return L["Died"], "", "" end
function LOG.z(_, _, zone) return L["Entered"] .. " " .. zone, "", "" end
function LOG.p(_, _, reason) return L["Paused"] .. " (" .. (PAUSE_WORDS[reason] or reason) .. ")", "", "" end
function LOG.u() return L["Resumed"], "", "" end

--- One packed line as the Log tab shows it: time ("hh:mm:ss" since the start), what, value and
--- source, with the item and money values at `measure`. nil for a line of an unknown kind.
local function decodeLine(s, measure, t, k, ...)
  if not (t and LOG[k]) then return nil end
  local what, value, source = LOG[k](s, measure, ...)
  return FarmModel.Clock(t), what, value, source, k
end

function FD.LogEntry(s, line, measure) return decodeLine(s, measure, FarmModel.Unpack(line)) end

-- The Log's rows are the packed strings themselves, newest first, in one reused array; a row's four
-- cells decode its line once (the last line decoded is memoized), so a bind costs one screen of
-- decodes whatever the log's length.
local logCtx = { s = nil, measure = "ah", line = nil, cells = {} }

local function logCells(line)
  if logCtx.line ~= line then
    local c = logCtx.cells
    c[1], c[2], c[3], c[4], c[5] = FD.LogEntry(logCtx.s, line, logCtx.measure)
    logCtx.line = line
  end
  return logCtx.cells
end

local function logRows(s, out)
  for i = #out, 1, -1 do out[i] = nil end
  local log = s.log or {}
  for i = #log, 1, -1 do out[#out + 1] = log[i] end
  return out
end

-- ── the list specs ───────────────────────────────────────────────────────────────────────────

local function qualityColor(q) if q ~= nil then return NS.QualityColor(q) end end
local function bad() return NS.SkinColor("sem.bad") end
local function headingColor() return NS.SkinColor("text.heading") end

local function itemEnter(e, row)
  if e.link then NS.Compat.ShowItemTooltip(row, e.link, "body") end
end

local function currencyEnter(e, row)
  if e.id then NS.Compat.ShowCurrencyTooltip(row, e.id, "body") end
end

local SPECS = {}
SPECS.Items = { sortKey = "ah", sortAsc = false, onEnter = itemEnter, empty = "No items yet.", columns = {
  { key = "name", label = "Item", text = function(e) return e.name end, color = function(e) return qualityColor(e.q) end,
    defaultAsc = true },
  { key = "qty", label = "Qty", width = 40, align = "RIGHT", text = function(e) return FarmModel.Grouped(e.qty) end,
    sort = function(e) return e.qty end },
  { key = "vu", label = "Vendor/u", width = 64, align = "RIGHT", text = function(e) return perUnit(e.vu) end,
    sort = function(e) return e.vu or -1 end },
  { key = "vendor", label = "Vendor", width = 66, align = "RIGHT",
    text = function(e) return FarmModel.CopperText(e.vendor) end, sort = function(e) return e.vendor end },
  { key = "au", label = "AH/u", width = 64, align = "RIGHT", text = function(e) return perUnit(e.au) end,
    sort = function(e) return e.au or -1 end },
  { key = "ah", label = "AH", width = 70, align = "RIGHT", text = function(e) return FarmModel.CopperText(e.ah) end,
    sort = function(e) return e.ah end },
  { key = "source", label = "Source", width = 76, text = function(e) return sourceLabel(e.source) end, defaultAsc = true },
} }
SPECS.Money = { sortKey = "amount", sortAsc = false, empty = "No money looted yet.", columns = {
  { key = "source", label = "Source", text = function(e) return sourceLabel(e.source) end, defaultAsc = true },
  { key = "amount", label = "Amount", width = 110, align = "RIGHT",
    text = function(e) return FarmModel.CopperText(e.amount) end, sort = function(e) return e.amount end },
  { key = "share", label = "Share", width = 70, align = "RIGHT",
    text = function(e) return ("%d%%"):format(math.floor(e.share * 100 + 0.5)) end, sort = function(e) return e.share end },
} }
SPECS.Currencies = { sortKey = "qty", sortAsc = false, onEnter = currencyEnter, empty = "No currencies yet.", columns = {
  { key = "name", label = "Currency", text = function(e) return e.name end, defaultAsc = true },
  { key = "qty", label = "Qty", width = 80, align = "RIGHT", text = function(e) return FarmModel.Grouped(e.qty) end,
    sort = function(e) return e.qty end },
  { key = "source", label = "Source", width = 100, text = function(e) return sourceLabel(e.source) end, defaultAsc = true },
} }
SPECS.Costs = { sortable = false, onEnter = currencyEnter, empty = "No costs yet.", columns = {
  { key = "label", label = "Reason", text = function(e) return e.label end },
  { key = "text", label = "Amount", width = 120, align = "RIGHT", text = function(e) return e.text end,
    color = function(e) if e.bad then return bad() end end },
} }
SPECS.Activity = { sortable = false, empty = "No activity lines are turned on.", columns = {
  { key = "label", label = "Line", text = function(e) return e.label end,
    color = function(e)
      if e.heading then return headingColor() end
      return qualityColor(e.q)
    end },
  { key = "text", label = "Value", width = 120, align = "RIGHT", text = function(e) return e.text end },
} }
SPECS.Log = { sortable = false, empty = "Nothing logged yet.", columns = {
  { key = "t", label = "Time", width = 70, text = function(line) return logCells(line)[1] or "" end },
  { key = "what", label = "What", text = function(line) return logCells(line)[2] or "" end },
  { key = "value", label = "Value", width = 90, align = "RIGHT", text = function(line) return logCells(line)[3] or "" end,
    color = function(line) if logCells(line)[5] == "o" then return bad() end end },
  { key = "source", label = "Source", width = 80, text = function(line) return logCells(line)[4] or "" end },
} }

local ROWS = {
  Items = FD.ItemRows, Money = FD.MoneyRows, Currencies = FD.CurrencyRows, Costs = FD.CostRows,
  Activity = function(s) return FD.ActivityRows(s, farmSettings().activity) end,
}

-- ── the window frame (both windows) ──────────────────────────────────────────────────────────

local function makeText(parent, template, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  NS.Skin.Font(fs)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function stripOffset(f)
  for _, strip in ipairs({ f.simStrip, f.testStrip }) do
    if strip and strip:IsShown() and strip.BodyOffset then return strip:BodyOffset() or 0 end
  end
  return 0
end

-- The mode strips follow the shown session's store: the cyan simulation band for a simulation's
-- session, the amber test band for a test-mode sample (preview-mode).
local function paintStrips(f, ref)
  if f.simStrip then f.simStrip:SetShown(ref ~= nil and ref.store == "sim") end
  if f.testStrip then f.testStrip:SetShown(ref ~= nil and ref.store == "test") end
end

local function titleBar(f, onMoved, onClose)
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(TITLE_H)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  -- Lock frame (options-ui-§15) gates the drag, as on the History window.
  bar:SetScript("OnDragStart", function()
    if NS.Browser:IsLocked() then return end
    f:StartMoving()
  end)
  bar:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    if onMoved then onMoved() end
  end)
  f.titleBar = bar
  local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("CENTER")
  f.title = title
  NS.Skin.TitleBar(bar)
  -- A secondary window: settings and close (not a companion; standalone-windows).
  local marks = NS.Browser:MakeTitleMarks(bar, f, onClose, nil, nil)
  NS.Skin.Header(f, { title = title, right = marks, bars = { bar } })
end

-- One window on the read tier (frame-layering-§1 T4 WINDOW, HIGH), toplevel, clamped and movable.
local function buildWindow(name, w, h, hooks)
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  f:SetSize(w, h)
  f:SetFrameStrata(C.LAYERS.STRATA.WINDOW)
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  titleBar(f, hooks.onMoved, hooks.onClose)
  f.simStrip = NS.Browser.MakeSimStrip(f, hooks.relayout)
  f.testStrip = NS.Browser.MakeTestModeStrip and NS.Browser.MakeTestModeStrip(f, hooks.relayout)
  if f.simStrip then f.simStrip:Hide() end
  if f.testStrip then f.testStrip:Hide() end
  f:HookScript("OnHide", function()
    NS.CloseMenu()
    debug("%s hidden", name)
  end)
  NS.Browser:ApplySkin(f, nil, { noTopBar = true })
  NS.Browser:ApplyChrome(f)
  f:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
  return f
end

-- Every show path's two refusals: silently while stood down (the verb gate already spoke), with a
-- line while General visibility hides the addon's windows.
local function showAllowed(what)
  if NS.IsStoodDown() then
    debug("%s refused: stood down", what)
    return false
  end
  if not NS.Browser:VisibilityAllows() then
    debug("%s refused: visibility", what)
    NS.Print("the farm windows are hidden by the General visibility setting.")
    return false
  end
  return true
end

-- ── the Details window ───────────────────────────────────────────────────────────────────────

local function detailsState()
  local s = settings()
  s.farm = s.farm or {}
  s.farm.details = s.farm.details or {}
  return s.farm.details
end

local function saveGeometry()
  local point, _, _, x, y = details:GetPoint(1)
  local d = detailsState()
  d.point, d.x, d.y = point, x, y
  d.w, d.h = math.floor(details:GetWidth() + 0.5), math.floor(details:GetHeight() + 0.5)
end

local function restoreGeometry()
  local d = detailsState()
  details:SetSize(math.max(MIN_W, d.w or DEFAULT_W), math.max(MIN_H, d.h or DEFAULT_H))
  details:ClearAllPoints()
  if d.point then
    details:SetPoint(d.point, UIParent, d.point, d.x or 0, d.y or 0)
  else
    details:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

--- Place the tab strip and the content under the title (and a mode strip, while one shows).
function FD:LayoutDetails()
  local f = details
  if not f then return end
  local top = TITLE_H + stripOffset(f)
  f.tabStrip:ClearAllPoints()
  f.tabStrip:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(top + 2))
  f.tabStrip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(top + 2))
  f.host:ClearAllPoints()
  f.host:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(top + TAB_H + 8))
  f.host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD + NOTE_H)
end

local function buildTabs(f)
  local strip = CreateFrame("Frame", nil, f)
  strip:SetHeight(TAB_H)
  f.tabStrip, f.tabs = strip, {}
  for i, name in ipairs(FD.TABS) do
    local tab = CreateFrame("Button", nil, strip)
    tab:SetSize(TAB_W, TAB_H)
    tab:SetPoint("LEFT", strip, "LEFT", (i - 1) * (TAB_W + 4), 0)
    tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.label:SetPoint("CENTER")
    tab.label:SetText(L[name])
    tab:SetScript("OnClick", function() FD:SelectTab(name) end)
    NS.Skin.Tab(tab, { text = tab.label, selected = i == 1 })
    f.tabs[name] = tab
  end
  f.host = CreateFrame("Frame", nil, f)
  f.panes, f.lists = {}, {}
  f.note = makeText(f, "GameFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
  f.note:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD + 20), PAD)
end

-- The tab's list, built on its first selection.
local function listFor(name)
  local f = details
  if f.lists[name] then return f.lists[name] end
  local pane = CreateFrame("Frame", nil, f.host)
  pane:SetAllPoints(f.host)
  local spec = {}
  for k, v in pairs(SPECS[name]) do spec[k] = v end
  spec.empty = L[spec.empty]
  spec.columns = {}
  for i, col in ipairs(SPECS[name].columns) do
    local c = {}
    for k, v in pairs(col) do c[k] = v end
    c.label = L[col.label]
    spec.columns[i] = c
  end
  f.panes[name] = pane
  f.lists[name] = FarmList.New(pane, spec)
  return f.lists[name]
end

local function ensureDetails()
  if details then return details end
  details = buildWindow("LootHistoryFarmDetails", DEFAULT_W, DEFAULT_H, {
    onMoved = function() saveGeometry() end,
    onClose = function() FD:Hide() end,
    relayout = function() FD:LayoutDetails() end,
  })
  local f = details
  f.tab = FD.TABS[1]
  buildTabs(f)
  -- The corner grip through the seam (Core.MakeResizable). Lock frame gates it (canResize, read at
  -- every press). A size tick is only the cheap relayout below; the save and the full rebind run
  -- once, on release (onResizeStop), never per OnSizeChanged.
  NS.MakeResizable(f, {
    owner = addonName,
    minWidth = MIN_W,
    minHeight = MIN_H,
    canResize = function() return not NS.Browser:IsLocked() end,
    onResizeStop = function()
      saveGeometry()
      FD:Rebind()
    end,
  })
  f:HookScript("OnSizeChanged", function() FD:RelayoutShown() end)
  restoreGeometry()
  FD:LayoutDetails()
  return f
end

--- The size tick's whole job: the shown list's column widths (no rebind, no save).
function FD:RelayoutShown()
  local list = details and details.lists[details.tab]
  if list then list:Relayout() end
end

--- The release's rebind: the shown list's visible slice at the new height.
function FD:Rebind()
  local list = details and details.lists[details.tab]
  if list then list:Bind() end
end

local function detailsTitle(ref, s)
  if ref.id == nil then return L["Farm session: details"] end
  return L["Session details"] .. ": " .. (s.name ~= "" and s.name or L["Unknown"])
end

local function paintNote(f, s)
  local text
  if f.tab == "Costs" and not costsTracked() then
    text = L["Costs come from the loss rows History records. Needs Track holdings and losses and Record gold (General > Capture)."]
  elseif f.tab == "Log" and (s.logDropped or 0) > 0 then
    text = (L["Showing the most recent %s lines."]):format(FarmModel.Grouped(C.FARM.LOG_CAP))
  end
  f.note:SetText(text or "")
  f.note:SetShown(text ~= nil)
end

-- Bind the shown tab's rows for session `s`.
local function bindTab(f, s)
  local list = listFor(f.tab)
  for name, pane in pairs(f.panes) do pane:SetShown(name == f.tab) end
  if f.tab == "Log" then
    logCtx.s, logCtx.measure, logCtx.line = s, measureOf(), nil
    f.logRows = logRows(s, f.logRows or {})
    list:SetData(f.logRows)
  else
    list:SetData(ROWS[f.tab](s))
  end
  paintNote(f, s)
end

-- An open-session window whose session just finished follows it into the saved list; answers the
-- session to show, or nil when it is gone (discarded, deleted, a released simulation store).
local function follow(f)
  local s = FD.Resolve(f.ref)
  if s then
    if f.ref.id == nil then f.lastId = s.id end
    return s
  end
  if f.ref.id == nil and f.lastId then
    f.ref.id = f.lastId
    return FD.Resolve(f.ref)
  end
  return nil
end

--- Repaint the Details window for its reference: the title, the strips and the shown tab. A window
--- whose session is gone closes.
function FD:Refresh()
  local f = details
  if not (f and f.ref) then return end
  local s = follow(f)
  if not s then
    debug("farm details closed: its session is gone")
    return self:Hide()
  end
  f.title:SetText(detailsTitle(f.ref, s))
  paintStrips(f, f.ref)
  self:LayoutDetails()
  bindTab(f, s)
end

--- Switch the Details window to tab `name`.
function FD:SelectTab(name)
  local f = details
  if not (f and SPECS[name]) then return end
  f.tab = name
  for _, t in ipairs(FD.TABS) do NS.Skin.SetTabSelection(f.tabs[t], t == name) end
  self:Refresh()
end

--- Open the Details window on `ref` (nil: this character's open session), replacing what it shows.
function FD:Open(ref)
  if not showAllowed("farm details") then return end
  ref = FD.Ref(ref)
  if not FD.Resolve(ref) then
    debug("farm details refused: no such session")
    return NS.Print("no farm session to show.")
  end
  local f = ensureDetails()
  f.ref, f.lastId = ref, nil
  f:Show()
  self:Refresh()
  debug("farm details shown (%s, %s)", ref.store, tostring(ref.id or "open"))
end

--- The Details window's reference and frame (test seams), nil before its first show.
function FD:DetailsWindow() return details end

-- ── the summary window ───────────────────────────────────────────────────────────────────────

local function charName(char) return (tostring(char or ""):match("^(.-)%-") or tostring(char or "")) end

local function zonesBySeconds(s)
  local order, out = {}, {}
  for i, z in ipairs(s.zoneOrder or {}) do order[z] = i end
  for z in pairs(s.zoneSec or {}) do out[#out + 1] = z end
  table.sort(out, function(a, b)
    local sa, sb = s.zoneSec[a] or 0, s.zoneSec[b] or 0
    if sa ~= sb then return sa > sb end
    return (order[a] or math.huge) < (order[b] or math.huge)
  end)
  return out
end

--- The meta line: "27 Nov 2026 · 19:02 to 20:31 · 1 h 12 m active (17 m paused) · Charone · zones".
function FD.MetaLine(s)
  local ended = s.endedAt or s.startedAt
  local parts = {
    FarmModel.DayLabel(s.startedAt) .. " " .. date("%Y", s.startedAt),
    date("%H:%M", s.startedAt) .. " " .. L["to"] .. " " .. date("%H:%M", ended),
    ("%s %s (%s %s)"):format(duration(s.activeSec), L["active"], duration(FarmModel.PausedSec(s)), L["paused"]),
    charName(s.char),
  }
  local zones = zonesBySeconds(s)
  if #zones > 0 then parts[#parts + 1] = table.concat(zones, ", ") end
  return table.concat(parts, " \194\183 ")
end

--- The Costs line's label: "Costs (repairs 9g, buys 11g)", each non-zero reason in a fixed order.
function FD.CostsLabel(s)
  local parts = {}
  for _, reason in ipairs(COST_ORDER) do
    local v = s.costs and s.costs[reason]
    if v and v > 0 then parts[#parts + 1] = L[COST_WORDS[reason]] .. " " .. goldText(v) end
  end
  if #parts == 0 then return L["Costs"] end
  return L["Costs"] .. " (" .. table.concat(parts, ", ") .. ")"
end

-- The item measure the ranked lists use: the headline's, or AH under the money measure (which
-- values no item).
local function itemMeasure(measure) return measure == "money" and "ah" or measure end

--- Top earners: the TOP_N items by value at the measure, { name, q, value }, "<name> x<qty>" (the
--- quantity only past one, as the mockup draws it).
function FD.TopEarners(s, measure)
  local m, out = itemMeasure(measure), {}
  for id, it in pairs(s.items or {}) do
    local v = it.qty * (FD.UnitAt(it, m) or 0)
    local name = itemName(s, id)
    if it.qty > 1 then name = name .. " x" .. FarmModel.Grouped(it.qty) end
    out[#out + 1] = { name = name, q = it.q, value = v }
  end
  table.sort(out, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return a.name < b.name
  end)
  for i = #out, TOP_N + 1, -1 do out[i] = nil end
  return out
end

-- Whole percents that sum to 100 (largest remainder), for `values` over `total`.
local function percents(values, total)
  local pct, rest, sum = {}, {}, 0
  for i, v in ipairs(values) do
    local exact = total > 0 and v * 100 / total or 0
    pct[i] = math.floor(exact)
    rest[#rest + 1] = { i = i, r = exact - pct[i] }
    sum = sum + pct[i]
  end
  table.sort(rest, function(a, b)
    if a.r ~= b.r then return a.r > b.r end
    return a.i < b.i
  end)
  for j = 1, (total > 0 and math.max(0, 100 - sum) or 0) do
    local e = rest[j]
    if e then pct[e.i] = pct[e.i] + 1 end
  end
  return pct
end

--- By source: every source's value at the measure (its items' share and its money), the TOP_N
--- largest as { label, value, pct }, the percents of the whole (largest remainder over all sources).
function FD.BySource(s, measure)
  local m, by = itemMeasure(measure), {}
  for _, it in pairs(s.items or {}) do
    local unit = FD.UnitAt(it, m) or 0
    for src, n in pairs(it.src or {}) do by[src] = (by[src] or 0) + n * unit end
  end
  for src, v in pairs(s.money or {}) do by[src] = (by[src] or 0) + v end
  local list, values, total = {}, {}, 0
  for src, v in pairs(by) do list[#list + 1] = { src = src, value = v } end
  table.sort(list, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return a.src < b.src
  end)
  for i, e in ipairs(list) do values[i] = e.value; total = total + e.value end
  local pct = percents(values, total)
  local out = {}
  for i = 1, math.min(TOP_N, #list) do
    out[i] = { label = sourceLabel(list[i].src), value = list[i].value, pct = pct[i] }
  end
  return out
end

--- Everything the summary draws for finished session `s`, as text (the golden the suite pins).
function FD.SummaryModel(s)
  local fs = farmSettings()
  local measure, basis = fs.headlineValue or "ah", fs.headlineBasis or "gross"
  local t = NS.Farm:Totals(s)
  local other = basis == "net" and "gross" or "net"
  local n = { measure = measure, basis = basis, other = other, totals = t, elapsed = s.activeSec,
    value = FarmModel.Value(t, measure, basis), otherValue = FarmModel.Value(t, measure, other) }
  n.rate = FarmModel.PerHour(n.value, s.activeSec)
  n.otherRate = FarmModel.PerHour(n.otherValue, s.activeSec)
  local tracked = costsTracked()
  return {
    meta = FD.MetaLine(s),
    value = FarmModel.CopperText(n.value),
    rate = FarmModel.RateText(n.rate) .. "/h",
    sub = NS.FarmPanel.SubLine(n),
    money = FarmModel.CopperText(t.money),
    items = FarmModel.CopperText(t.vendor) .. " / " .. FarmModel.CopperText(t.ah),
    costsLabel = tracked and FD.CostsLabel(s) or L["Costs"],
    costs = tracked and (t.costs > 0 and "-" .. goldText(t.costs) or FarmModel.CopperText(0))
      or L["n/a (needs ledger capture)"],
    costsTracked = tracked,
    activity = FarmModel.ActivityLines(s.activity, fs.activity, true),
    top = FD.TopEarners(s, measure),
    sources = FD.BySource(s, measure),
  }
end

local function summaryKV(f, count)
  local out = {}
  for i = 1, count do out[i] = { k = makeText(f), v = makeText(f, nil, "RIGHT") } end
  return out
end

local function buildSummaryBody(f)
  f.meta = makeText(f, "GameFontHighlightSmall")
  f.meta:SetWordWrap(true)
  f.value = makeText(f, "GameFontNormalHuge")
  f.rate = makeText(f, "GameFontHighlight", "RIGHT")
  f.sub = makeText(f)
  f.kv = summaryKV(f, 3)
  f.kv[1].k:SetText(L["Money looted"])
  f.kv[2].k:SetText(L["Items, vendor / AH"])
  f.actHead = makeText(f, "GameFontNormal")
  f.actHead:SetText(L["Activity"])
  f.act = summaryKV(f, #FarmModel.ACTIVITY)
  f.topHead = makeText(f, "GameFontNormal")
  f.topHead:SetText(L["Top earners"])
  f.top = summaryKV(f, TOP_N)
  f.srcHead = makeText(f, "GameFontNormal")
  f.srcHead:SetText(L["By source"])
  f.src = summaryKV(f, TOP_N)
  f.footer = NS.MakeFooter(f)
  f.buttons = {
    details = NS.Browser.MakeFlatButton(f.footer, L["Details"], BTN_W, BTN_H, function() FD:SummaryDetails() end),
    close = NS.Browser.MakeFlatButton(f.footer, L["Close"], BTN_W, BTN_H, function() FD:HideSummary() end),
  }
  f.buttons.details:SetPoint("LEFT", f.footer, "LEFT", 8, 0)
  f.buttons.close:SetPoint("LEFT", f.buttons.details, "RIGHT", 6, 0)
end

local function ensureSummary()
  if summary then return summary end
  summary = buildWindow("LootHistoryFarmSummary", SUMMARY_W, 300, {
    onClose = function() FD:HideSummary() end,
    relayout = function() FD:LayoutSummary() end,
  })
  summary:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  buildSummaryBody(summary)
  return summary
end

local function put(f, fs, y, right, x)
  fs:ClearAllPoints()
  if right then
    fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(x or PAD + 2), -y)
  else
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", x or PAD + 2, -y)
  end
  fs:Show()
end

-- One kv block: a heading (or none), then `n` shown pairs, one per row; the rest hidden.
local function layoutBlock(f, head, pairsList, n, y)
  if head then
    if n == 0 then head:Hide(); return y end
    put(f, head, y)
    y = y + 18
  end
  for i, p in ipairs(pairsList) do
    p.k:SetShown(i <= n); p.v:SetShown(i <= n)
    if i <= n then
      put(f, p.k, y); put(f, p.v, y, true)
      y = y + 15
    end
  end
  return y + 6
end

-- The activity block: two columns, as on the panel.
local function layoutActivity(f, n, y)
  if n == 0 then
    f.actHead:Hide()
    for _, p in ipairs(f.act) do p.k:Hide(); p.v:Hide() end
    return y
  end
  put(f, f.actHead, y)
  y = y + 18
  local colW = (SUMMARY_W - 2 * PAD) / 2
  for i, p in ipairs(f.act) do
    p.k:SetShown(i <= n); p.v:SetShown(i <= n)
    if i <= n then
      local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
      local x = PAD + 2 + col * colW
      put(f, p.k, y + row * 15, false, x)
      put(f, p.v, y + row * 15, true, SUMMARY_W - x - colW + 12)
    end
  end
  return y + math.ceil(n / 2) * 15 + 6
end

--- Place the summary's blocks for what it shows and size it to them.
function FD:LayoutSummary()
  local f = summary
  if not (f and f.model) then return end
  local m = f.model
  f.meta:SetWidth(SUMMARY_W - 2 * PAD)
  local y = TITLE_H + stripOffset(f) + 8
  put(f, f.meta, y)
  y = y + 30
  put(f, f.value, y); put(f, f.rate, y + 6, true)
  y = y + 28
  put(f, f.sub, y)
  y = layoutBlock(f, nil, f.kv, 3, y + 20)
  y = layoutActivity(f, #m.activity, y)
  y = layoutBlock(f, f.topHead, f.top, #m.top, y)
  y = layoutBlock(f, f.srcHead, f.src, #m.sources, y)
  f:SetHeight(y + 8 + NS.FooterHeight())
end

local function paintSummary(f, m)
  f.meta:SetText(m.meta); tint(f.meta, "text.muted")
  f.value:SetText(m.value); tint(f.value, "sem.gold")
  f.rate:SetText(m.rate); tint(f.rate, "text.body")
  f.sub:SetText(m.sub); tint(f.sub, "text.muted")
  f.kv[1].v:SetText(m.money)
  f.kv[2].v:SetText(m.items)
  f.kv[3].k:SetText(m.costsLabel)
  f.kv[3].v:SetText(m.costs)
  for _, p in ipairs(f.kv) do tint(p.k, "text.muted"); tint(p.v, "text.body") end
  tint(f.kv[3].v, m.costsTracked and "sem.bad" or "text.disabled")
  for i, line in ipairs(m.activity) do
    f.act[i].k:SetText(L[line.label]); tint(f.act[i].k, "text.muted")
    f.act[i].v:SetText(line.text); tint(f.act[i].v, "text.body")
  end
  for i, e in ipairs(m.top) do
    f.top[i].k:SetText(e.name)
    local r, g, b = qualityColor(e.q)
    if r then f.top[i].k:SetTextColor(r, g, b) else tint(f.top[i].k, "text.body") end
    f.top[i].v:SetText(goldText(e.value)); tint(f.top[i].v, "text.body")
  end
  for i, e in ipairs(m.sources) do
    f.src[i].k:SetText(e.label); tint(f.src[i].k, "text.body")
    f.src[i].v:SetText(goldText(e.value) .. " \194\183 " .. e.pct .. "%"); tint(f.src[i].v, "text.body")
  end
  for _, h in ipairs({ f.actHead, f.topHead, f.srcHead }) do tint(h, "text.heading") end
end

--- Repaint the summary for its reference; a summary whose session is gone closes.
function FD:RefreshSummary()
  local f = summary
  if not (f and f.ref) then return end
  local s = FD.Resolve(f.ref)
  if not s then
    debug("farm summary closed: its session is gone")
    return self:HideSummary()
  end
  f.model = FD.SummaryModel(s)
  f.title:SetText(L["Session summary"] .. ": " .. (s.name ~= "" and s.name or L["Unknown"]))
  paintStrips(f, f.ref)
  paintSummary(f, f.model)
  self:LayoutSummary()
end

--- Open the summary on finished session `ref` (Finish, and from M4.4 a row click).
function FD:OpenSummary(ref)
  if not showAllowed("farm summary") then return end
  ref = FD.Ref(ref)
  local s = FD.Resolve(ref)
  if not (s and s.endedAt) then
    debug("farm summary refused: no finished session")
    return
  end
  local f = ensureSummary()
  f.ref = ref
  f:Show()
  self:RefreshSummary()
  debug("farm summary shown (%s, #%s)", ref.store, tostring(ref.id))
end

--- The summary's Details button: the same session's full record.
function FD:SummaryDetails()
  if summary and summary.ref then self:Open(summary.ref) end
end

--- The summary frame (a test seam), nil before its first show.
function FD:SummaryWindow() return summary end

-- ── show, hide, the master rows ──────────────────────────────────────────────────────────────

function FD:HideSummary()
  if summary then summary:Hide() end
end

--- Hide both windows (their close marks, the stand-down's Hide step).
function FD:Hide()
  if details then details:Hide() end
  self:HideSummary()
end

function FD:IsShown() return details ~= nil and details:IsShown() end

--- A visibility edge (`inCombat`, as B:VisibilityAllows takes) or a settings change: a window the
--- setting no longer allows goes. Only ever hides, as on the History window.
function FD:ApplyVisibility(inCombat)
  if NS.Browser:VisibilityAllows(inCombat) then return end
  if (details and details:IsShown()) or (summary and summary:IsShown()) then
    debug("farm windows hidden by visibility")
    self:Hide()
  end
end

--- The master rows moved (B:OnSettingsChanged): chrome and visibility.
function FD:OnChromeChanged()
  for _, f in ipairs({ details, summary }) do
    if f then NS.Browser:ApplyChrome(f) end
  end
  self:ApplyVisibility()
end

--- The profile adopt path (B:AdoptProfile): the Details window's geometry from the new profile.
function FD:AdoptProfile()
  if not details then return end
  restoreGeometry()
  self:OnChromeChanged()
end

-- ── the bus (lifecycle steps, core/LifecycleSetup.lua) ───────────────────────────────────────

local function onChanged(_, reason)
  if details and details:IsShown() and details.ref
      and (details.ref.id == nil or SAVED_REASONS[reason]) and FD._refresh then
    FD._refresh()
  end
  if summary and summary:IsShown() and SAVED_REASONS[reason] and FD._refreshSummary then
    FD._refreshSummary()
  end
end

local function onSettings()
  if details and details:IsShown() and FD._refresh then FD._refresh() end
  if summary and summary:IsShown() and FD._refreshSummary then FD._refreshSummary() end
end

--- Stand-up: the windows' own bus target, FARM_CHANGED and SETTINGS_CHANGED, both coalesced.
function FD:Enable()
  if self.__ev or not NS.bus then return end
  self._refresh = NS.Coalesce(function() FD:Refresh() end, COALESCE)
  self._refreshSummary = NS.Coalesce(function() FD:RefreshSummary() end, COALESCE)
  self.__ev = NS.NewBusTarget()
  self.__ev:RegisterMessage(NS.MSG.FARM_CHANGED, onChanged)
  self.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED, onSettings)
end

--- Stand-down: the bus target goes (the windows themselves go in the Hide step).
function FD:Disable()
  if not self.__ev then return end
  self.__ev:UnregisterAllMessages()
  self.__ev = nil
  self._refresh, self._refreshSummary = nil, nil
end
