local _, NS = ...
NS.Analytics = NS.Analytics or {}
local Analytics = NS.Analytics

-- Insights tab: stat/highlight cards + a stack of breakdown sections (source, value, quality,
-- item type, bound type, per-character, time-of-day/week, M+ keystone, confidence) plus top
-- zones/items/value lists, scoped by a date-range selector (see docs/browser.md). Everything
-- is driven off a single Database:Stats(filter) pass; widgets are pooled and re-laid-out on resize.
-- "Value" is vendor value (vendorPrice × quantity), not market price.

-- Everything pure comes from modules/AnalyticsFormat.lua, which loads first: bound once, here, to
-- file-scope locals (docs/common-tasks.md, hot-path upvalues), never looked up per row.
local K, F = Analytics.K, Analytics._fmt
local WHITE, SECTION_GAP, MIN_HEADLINE_SIZE, NEUTRAL = K.WHITE, K.SECTION_GAP, K.MIN_HEADLINE_SIZE, K.NEUTRAL
local SOURCE_COLOR, BOUND_LABEL, BOUND_COLOR = F.SOURCE_COLOR, F.BOUND_LABEL, F.BOUND_COLOR
local BOUND_ORDER, WEEKDAY, starMarkup = F.BOUND_ORDER, F.WEEKDAY, F.starMarkup
local money, shortChar, paletteMap = Analytics._money, Analytics._shortChar, Analytics._paletteMap
local classColor, qualityColor = Analytics._classColor, Analytics._qualityColor
local dayKeyList, shortDay, sortedByCount = Analytics._dayKeyList, Analytics._shortDay, Analytics._sortedByCount

-- Stat / highlight cards, in row order (4 columns per row; `wide` spans 2). `str` cards hold a
-- string (smaller font). Value strings are produced in UpdateCards.
local CARD_DEFS = {
  { key = "records", label = "records" },
  { key = "items",   label = "distinct items" },
  { key = "chars",   label = "characters" },
  { key = "value",   label = "value", str = true, bigStr = true },
  { key = "active",  label = "active days" },
  { key = "epic",    label = "epic+ drops" },
  { key = "best",    label = "best drop (ilvl)" },
  { key = "richest", label = "richest drop", str = true, bigStr = true },
  { key = "span",    label = "date range", str = true, bigStr = true, wide = true },
  { key = "busy",    label = "busiest day", str = true, bigStr = true, wide = true },
  -- The ledger row (timeline-ledger spec §6): value with the row count in the caption, signed.
  { key = "gained", label = "gained", str = true, bigStr = true },
  { key = "lost",   label = "lost",   str = true, bigStr = true },
  { key = "net",    label = "net",    str = true, bigStr = true },
  { key = "moved",  label = "transfers" },
}

-- ── Build ────────────────────────────────────────────────────────────────────────

function Analytics:Attach(pane)
  if self.pane then return end
  self.pane = pane

  -- No range selector here (issue #13): the Insights view is scoped by the browser's shared filter
  -- bar (its Date dropdown + every column filter), so the charts fill the whole pane below.
  local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -26, 4)
  self.scroll = scroll
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  self.content = content
  scroll:SetScript("OnSizeChanged", function() Analytics:Layout() end)

  -- Cards.
  self.cards = {}
  for _, def in ipairs(CARD_DEFS) do
    local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
    card:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                       insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    card:SetBackdropColor(0.1, 0.1, 0.12, 0.85)
    card:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
    -- Plain string cards (date range / busiest day) hold a long value → small font. The `value`
    -- and `richest` cards keep the big headline font (bigStr) and shrink-to-fit in Layout instead.
    local fontTemplate = (def.str and not def.bigStr) and "GameFontNormal" or "GameFontNormalHuge"
    local num = card:CreateFontString(nil, "OVERLAY", fontTemplate)
    if def.bigStr then num:SetWordWrap(false) end
    num:SetPoint("TOP", 0, -9)
    num:SetPoint("LEFT", 2, 0)
    num:SetPoint("RIGHT", -2, 0)
    num:SetJustifyH("CENTER")
    num:SetTextColor(1, 0.82, 0)
    local cl = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cl:SetPoint("BOTTOM", 0, 7)
    cl:SetText(def.label)
    local entry = { frame = card, num = num, bigStr = def.bigStr, caption = cl, captionBase = def.label }
    if def.bigStr then
      local file, size, flags = num:GetFont()
      entry.fontFile, entry.baseSize, entry.fontFlags = file, size, flags
    end
    self.cards[def.key] = entry
  end

  self:BuildCharts(content)
  self:Refresh()
end

-- ── Refresh + layout ──────────────────────────────────────────────────────────────

-- Pure one-line summary for the [Insights] trace.
function Analytics.SummaryLine(scope, count)
  return ("computed range=%s, %s records"):format(tostring(scope), tostring(count))
end

-- The quiet-steady-state gate for the [Insights] summary (debug-logging-§9), the console's
-- DebugChanged under one key. The live refresh runs on every coalesced RecordAdded while the tab is
-- up; under a filter the new loot does not match (or in test mode, never reaches), the recompute is
-- identical and logs nothing. Forgotten by the History window's OnShow, so each open logs its first
-- recompute, and re-armed by the console on a Clear or a fresh `debug on`.
local SUMMARY_KEY = "Insights.summary"

function Analytics.ResetRenderTrace()
  if NS.DebugForget then NS.DebugForget(SUMMARY_KEY) end
end

function Analytics:Refresh()
  if not self.content then return end
  -- Scope by this tab's own filter (P11: every tab keeps its own on the shared bar), read as the
  -- Insights state even when another tab is on the bar; empty filter = the whole (visible) history.
  local filter = (NS.Browser and NS.Browser.CurrentFilter and NS.Browser:CurrentFilter("Insights")) or {}
  local stats = NS.Database:Stats(filter)
  self.stats = stats
  self:UpdateCards(stats)
  self:Layout() -- Layout → LayoutCharts binds the charts off self.stats
  if NS.State.debug and NS.DebugChanged then
    local line = Analytics.SummaryLine(next(filter) and "filtered" or "all", stats.totals.records)
    NS.DebugChanged(SUMMARY_KEY, "Insights", "%s", line)
  end
end

function Analytics:UpdateCards(stats)
  local t = stats.totals
  local dash = "\226\128\148" -- em-dash
  self.cards.records.num:SetText(tostring(t.records))
  self.cards.items.num:SetText(tostring(t.distinctItems))
  self.cards.chars.num:SetText(tostring(t.distinctChars))
  self.cards.value.num:SetText(money(t.totalValue))
  self.cards.active.num:SetText(tostring(t.activeDays))
  self.cards.epic.num:SetText(tostring(t.epicPlus))
  self.cards.best.num:SetText(t.bestDrop and tostring(t.bestDrop.itemLevel) or dash)
  self.cards.richest.num:SetText(t.richestDrop and money(t.richestDrop.value) or dash)
  local span = dash
  if t.firstTs and t.lastTs then
    span = NS.Util.FormatDate(t.firstTs) .. "  \226\128\147  " .. NS.Util.FormatDate(t.lastTs) -- – en-dash
  end
  self.cards.span.num:SetText(span)
  self.cards.busy.num:SetText(t.busiestDay and (t.busiestDay.day .. "  (" .. t.busiestDay.count .. ")") or dash)

  -- The ledger row: signed copper headline, the row count in the caption (" · N").
  local L, LF = stats.ledger or {}, NS.LedgerFormat
  local function cap(key, n) local c = self.cards[key]; c.caption:SetText(c.captionBase .. " \194\183 " .. tostring(n or 0)) end
  self.cards.gained.num:SetText(LF.SignedMoney(L.gainedValue or 0)); cap("gained", L.gainedCount)
  self.cards.lost.num:SetText(LF.SignedMoney(-(L.lostValue or 0)));   cap("lost", L.lostCount)
  self.cards.net.num:SetText(LF.SignedMoney(L.netValue or 0))
  self.cards.net.caption:SetText("net \194\183 " .. LF.SignedCount(L.netCount or 0))
  self.cards.moved.num:SetText(tostring(L.movedCount or 0))
end

-- Position everything top-down given the current content width; set the scroll child height.
function Analytics:Layout()
  if not self.content then return end
  local w = self.scroll:GetWidth()
  if not w or w <= 0 then w = 780 end
  self.content:SetWidth(w)

  local PAD, GAP, COLS = 8, 8, 4
  local colW = math.floor((w - PAD * 2 - GAP * (COLS - 1)) / COLS)
  local cardH = 52
  local col, rowY = 0, -PAD
  for _, def in ipairs(CARD_DEFS) do
    local span = def.wide and 2 or 1
    if col + span > COLS then col = 0; rowY = rowY - cardH - GAP end
    local c = self.cards[def.key]
    c.frame:ClearAllPoints()
    c.frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD + col * (colW + GAP), rowY)
    c.frame:SetSize(colW * span + GAP * (span - 1), cardH)
    if c.bigStr and c.baseSize then
      c.num:SetFont(c.fontFile, c.baseSize, c.fontFlags) -- reset to base, then shrink if it overflows
      local maxW = colW * span + GAP * (span - 1) - 12   -- card inner width (small padding)
      local size = Analytics._fitFontSize(c.num:GetStringWidth(), maxW, c.baseSize, MIN_HEADLINE_SIZE)
      if size < c.baseSize then c.num:SetFont(c.fontFile, size, c.fontFlags) end
    end
    col = col + span
  end

  local y = rowY - cardH - 14
  y = self:LayoutCharts(y, w, PAD)
  self.content:SetHeight(math.max(1, -y + PAD))
end

-- ── Charts ─────────────────────────────────────────────────────────────────────────

-- Build the persistent chart chrome (section headers, strips, list panels, pools) once.
function Analytics:BuildCharts(content)
  -- The section chrome lives in modules/AnalyticsCharts.lua, which loads AFTER this file, so it is
  -- resolved here, at call time and once per build (MultiMeters' Aggregator._identity precedent).
  local C = Analytics._charts
  local sectionHeader, sectionDivider, listPanel = C.sectionHeader, C.sectionDivider, C.listPanel
  self.headers = {
    char    = sectionHeader(content, "Loot By Character"),
    source  = sectionHeader(content, "Loot By Source"),
    charBySource = sectionHeader(content, "Loot By Character \195\151 Source"),
    vsource = sectionHeader(content, "Value By Source"),
    charValueSource = sectionHeader(content, "Value By Character \195\151 Source"),
    quality = sectionHeader(content, "Loot By Quality"),
    charQuality = sectionHeader(content, "Loot By Character \195\151 Quality"),
    itype   = sectionHeader(content, "Loot By Item Type"),
    charType = sectionHeader(content, "Loot By Character \195\151 Item Type"),
    bound   = sectionHeader(content, "Loot By Bound Type"),
    charBound = sectionHeader(content, "Loot By Character \195\151 Bound Type"),
    time    = sectionHeader(content, "Loot Over Time (Per Day)"),
    vtime   = sectionHeader(content, "Value Over Time (Per Day)"),
    hour    = sectionHeader(content, "Loot By Hour Of Day"),
    weekday = sectionHeader(content, "Loot By Weekday"),
    currencyCollected = sectionHeader(content, "Currency Collected"),
    currencySrc   = sectionHeader(content, "Currency By Type \195\151 Source"),
    currencyChar  = sectionHeader(content, "Currency By Character \195\151 Type"),
    currencyTime  = sectionHeader(content, "Currency Over Time (Per Day)"),
  }
  self.lootDivider = sectionDivider(content, "LOOT")
  self.currencyDivider = sectionDivider(content, "CURRENCY")
  self.dayStrip   = CreateFrame("Frame", nil, content)
  self.valueStrip = CreateFrame("Frame", nil, content)
  self.hourStrip  = CreateFrame("Frame", nil, content)
  self.zonePanel  = listPanel(content, "Top Zones")
  self.itemPanel  = listPanel(content, "Top Items By Count")
  self.itemValuePanel = listPanel(content, "Top Items By Value")
  self.currencyStrip = CreateFrame("Frame", nil, content)
  self.emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
  self.emptyText:SetText("No loot in this range.")
  self.emptyText:Hide()
  self.pool = {
    source = NS.Pool.New(), vsource = NS.Pool.New(),
    quality = NS.Pool.New(),
    itype  = NS.Pool.New(), bound   = NS.Pool.New(),
    char   = NS.Pool.New(), day     = NS.Pool.New(),
    vday   = NS.Pool.New(), hour    = NS.Pool.New(),
    weekday = NS.Pool.New(),
    zone    = NS.Pool.New(),
    item   = NS.Pool.New(), itemval = NS.Pool.New(),
    curcollected = NS.Pool.New(), curcollectedleg = NS.Pool.New(),
    cursrc = NS.Pool.New(), curlegend = NS.Pool.New(),
    curchar = NS.Pool.New(), curcharlegend = NS.Pool.New(),
    curday = NS.Pool.New(),
    -- Legends for the single-bar categorical charts.
    sourceleg = NS.Pool.New(), vsourceleg = NS.Pool.New(),
    qualityleg = NS.Pool.New(), itypeleg = NS.Pool.New(),
    boundleg = NS.Pool.New(),
    -- Per-character × category companion stacked bars + their color legends (one pool each).
    chsource = NS.Pool.New(), chsourceleg = NS.Pool.New(),
    chvsource = NS.Pool.New(), chvsourceleg = NS.Pool.New(),
    chquality = NS.Pool.New(), chqualityleg = NS.Pool.New(),
    chtype = NS.Pool.New(), chtypeleg = NS.Pool.New(),
    chbound = NS.Pool.New(), chboundleg = NS.Pool.New(),
  }
  -- The GAINS & LOSSES half (modules/AnalyticsLedger.lua): its own chrome, in self.ledgerUI.
  Analytics._ledger.Build(self, content)

  -- Live-update while the Insights tab is visible (new loot / deletes / prune).
  Analytics:Enable()
end

--- Subscribe the Insights pane to the bus.
---
--- LIFTED OUT of BuildCharts, and the lift is what makes the stand-down reversible rather than
--- cosmetic. The subscription used to be made inline, once, the first time the charts were built --
--- so a stand-down that dropped it had no way back short of rebuilding the pane, and the Insights
--- tab came up live-updating on a disabled addon and dead on a re-enabled one. It is NS.StandUp's
--- to call now, like the other three modules'.
function Analytics:Enable()
  if not NS.bus or self._subscribed then return end
  self._subscribed = true
  local function live()
    if self.pane and self.pane:IsVisible() then Analytics:Refresh() end
  end
  -- Private bus target (never the shared bus-as-self) so these don't clobber the Browser's
  -- RecordAdded/HistoryChanged handlers on the same bus. See NS.NewBusTarget.
  -- No `or NS.bus` tail: NS.NewBusTarget returns nil ONLY when AceEvent-3.0 is unresolvable, and
  -- core/LootHistory.lua:4's NewAddon(NS, addonName, "AceEvent-3.0", …) errors first in exactly
  -- that case, so NS.bus never exists and the `if NS.bus` guard above never opens.
  self.__ev = NS.NewBusTarget()
  -- Coalesced for the same reason the Browser's is (issue #27): `Analytics:Refresh` is another
  -- full-history pass, and it was the ninth one paid per looted item while the Insights tab was
  -- visible. HistoryChanged stays immediate — a delete or a prune is one deliberate action.
  self.__ev:RegisterMessage(NS.MSG.RECORD_ADDED,
    NS.Coalesce(live, NS.Constants.RECORD_ADDED_COALESCE))
  self.__ev:RegisterMessage(NS.MSG.HISTORY_CHANGED, live)
end

--- The stand-down half (slash-commands-§7): the private bus target goes wholesale, and the
--- coalescing repaint trigger goes with it.
function Analytics:Disable()
  if not self._subscribed then return end
  if self.__ev then
    self.__ev:UnregisterAllMessages()
    self.__ev:UnregisterAllEvents()
    self.__ev = nil
  end
  self._subscribed = nil
end

-- ── LayoutCharts, one helper per section ────────────────────────────────────────────────────────
--
-- LayoutCharts was one 300-line function at CCN 86, measured once lizard could see it (kit
-- revision 35's sighted complexity suite; WowAddonStandards#6). It is now a sequence of the
-- section helpers below, each taking the instance and the running y cursor and returning the new
-- one, in the order the sections draw. They are file-local rather than methods so the module's
-- public surface does not grow; the bodies are the old function's, moved (GI-LH-02), and
-- tests/test_analytics_layout.lua's golden snapshots pin that they draw the same thing.

-- Every pool LayoutCharts draws from, released at the top of each pass.
local CHART_POOLS = { "source", "vsource", "quality", "itype", "bound", "char",
                      "day", "vday", "hour", "weekday", "zone", "item", "itemval",
                      "curcollected", "curcollectedleg", "cursrc", "curlegend", "curchar", "curcharlegend", "curday",
                      "sourceleg", "vsourceleg", "qualityleg", "itypeleg", "boundleg",
                      "chsource", "chsourceleg", "chvsource", "chvsourceleg", "chquality", "chqualityleg",
                      "chtype", "chtypeleg", "chbound", "chboundleg" }

local function srcColor(k) return SOURCE_COLOR[k] or NEUTRAL end
local function srcLabel(k) return NS.Constants.SourceLabel[k] or k end
local function countText(t) return tostring(t) end
local function moneyText(t) return money(t) end

-- A full-width divider (LOOT / CURRENCY) anchored across the content at y; returns the new y.
local function placeDivider(self, divider, y, pad)
  divider:ClearAllPoints()
  divider:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
  divider:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -pad, y)
  divider:Show()
  return y - 30
end

-- Loot by character (first chart in the LOOT section) — class-colored, sorted by count desc.
-- byChar registers currency-only characters with count 0 (for class colors elsewhere); skip them.
local function layoutCharacters(self, stats, y, w, pad)
  local rows = {}
  local chRows = {}
  for _, ce in pairs(stats.byChar) do if ce.count > 0 then chRows[#chRows + 1] = ce end end
  table.sort(chRows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.char < b.char
  end)
  local chMax = 1
  for _, ce in ipairs(chRows) do if ce.count > chMax then chMax = ce.count end end
  for _, ce in ipairs(chRows) do
    rows[#rows + 1] = { label = shortChar(ce.char), color = classColor(ce.classFile),
      frac = ce.count / chMax, value = tostring(ce.count) }
  end
  return self:renderBarSection(self.pool.char, self.headers.char, rows, y, w, pad)
end

-- Loot by source — length = share of all records — and its Character × Source companion, whose
-- segment order matches the parent's Y axis (count desc).
local function layoutSources(self, stats, y, w, pad)
  local P, H, total = self.pool, self.headers, stats.totals.records
  local rows = {}
  for _, e in ipairs(sortedByCount(stats.bySource)) do
    rows[#rows + 1] = {
      label = NS.Constants.SourceLabel[e.key] or e.key, color = SOURCE_COLOR[e.key] or NEUTRAL,
      frac = e.count / total, value = string.format("%d  %d%%", e.count, math.floor(e.count / total * 100 + 0.5)),
    }
  end
  y = self:renderBarSection(P.source, H.source, rows, y, w, pad, P.sourceleg)

  local srcOrder = {}
  for _, e in ipairs(sortedByCount(stats.bySource)) do srcOrder[#srcOrder + 1] = e.key end
  return self:renderCharCompanion("chsource", "chsourceleg", H.charBySource, stats.charBySource,
    srcOrder, srcColor, srcLabel, countText, y, w, pad)
end

-- Vendor value by source — length relative to the biggest bucket, ordered by value desc — and its
-- Character × Source companion, in the same order.
local function layoutValueSources(self, stats, y, w, pad)
  local P, H = self.pool, self.headers
  local rows = {}
  local vMax = 1
  for _, v in pairs(stats.valueBySource) do if v > vMax then vMax = v end end
  local vsrc = {}
  for src, v in pairs(stats.valueBySource) do vsrc[#vsrc + 1] = { src = src, v = v } end
  table.sort(vsrc, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.src < b.src end)
  local vsrcOrder = {}
  for _, e in ipairs(vsrc) do
    vsrcOrder[#vsrcOrder + 1] = e.src
    if e.v > 0 then
      rows[#rows + 1] = { label = NS.Constants.SourceLabel[e.src] or e.src,
        color = SOURCE_COLOR[e.src] or NEUTRAL, frac = e.v / vMax, value = money(e.v) }
    end
  end
  y = self:renderBarSection(P.vsource, H.vsource, rows, y, w, pad, P.vsourceleg)

  return self:renderCharCompanion("chvsource", "chvsourceleg", H.charValueSource, stats.charValueBySource,
    vsrcOrder, srcColor, srcLabel, moneyText, y, w, pad)
end

-- Quality distribution — bars in quality order, length relative to the biggest bucket — and its
-- Character × Quality companion, segments colored by item quality (parent order).
local function layoutQualities(self, stats, y, w, pad)
  local P, H = self.pool, self.headers
  local rows = {}
  local qRows, qMax = {}, 1
  for q, c in pairs(stats.byQuality) do qRows[#qRows + 1] = { q = q, c = c }; if c > qMax then qMax = c end end
  table.sort(qRows, function(a, b) return a.q < b.q end)
  for _, e in ipairs(qRows) do
    local col = qualityColor(e.q)
    rows[#rows + 1] = { label = NS.Item.QualityLabel(e.q), labelColor = col, color = col,
      frac = e.c / qMax, value = tostring(e.c) }
  end
  y = self:renderBarSection(P.quality, H.quality, rows, y, w, pad, P.qualityleg)

  local qOrder = {}
  for q = 0, 8 do if stats.byQuality[q] then qOrder[#qOrder + 1] = q end end
  return self:renderCharCompanion("chquality", "chqualityleg", H.charQuality, stats.charByQuality,
    qOrder, function(q) return qualityColor(q) end, function(q) return NS.Item.QualityLabel(q) end,
    countText, y, w, pad)
end

-- Loot by item type — bars colored per type from the standard palette (rank = sort order); the
-- Character × Item Type companion reuses the same map so a type keeps its color across both.
local function layoutItemTypes(self, stats, y, w, pad)
  local P, H, total = self.pool, self.headers, stats.totals.records
  local tyKeys = {}
  for _, e in ipairs(sortedByCount(stats.byType)) do tyKeys[#tyKeys + 1] = e.key end
  local typeColor = paletteMap(tyKeys)
  local rows = {}
  for _, e in ipairs(sortedByCount(stats.byType)) do
    rows[#rows + 1] = { label = e.key, color = typeColor[e.key] or NEUTRAL,
      frac = e.count / total, value = tostring(e.count) }
  end
  y = self:renderBarSection(P.itype, H.itype, rows, y, w, pad, P.itypeleg)

  return self:renderCharCompanion("chtype", "chtypeleg", H.charType, stats.charByType,
    tyKeys, function(k) return typeColor[k] or NEUTRAL end, function(k) return k end,
    countText, y, w, pad)
end

-- Loot by bound type — sorted count desc; the companion reuses this exact order for its segments.
local function layoutBoundTypes(self, stats, y, w, pad)
  local P, H, total = self.pool, self.headers, stats.totals.records
  local rows = {}
  local bRows = {}
  for _, bk in ipairs(BOUND_ORDER) do
    local c = stats.byBound[bk]
    if c then bRows[#bRows + 1] = { bk = bk, c = c } end
  end
  table.sort(bRows, function(a, b) if a.c ~= b.c then return a.c > b.c end return a.bk < b.bk end)
  local boundOrder = {}
  for _, e in ipairs(bRows) do
    boundOrder[#boundOrder + 1] = e.bk
    rows[#rows + 1] = { label = BOUND_LABEL[e.bk] or e.bk, color = BOUND_COLOR[e.bk] or NEUTRAL,
      frac = e.c / total, value = tostring(e.c) }
  end
  y = self:renderBarSection(P.bound, H.bound, rows, y, w, pad, P.boundleg)

  return self:renderCharCompanion("chbound", "chboundleg", H.charBound, stats.charByBound,
    boundOrder, function(k) return BOUND_COLOR[k] or NEUTRAL end,
    function(k) return BOUND_LABEL[k] or k end, countText, y, w, pad)
end

-- Loot over time + vendor value over time — two per-day strips over the same day range — then
-- loot by hour of day, 24 fixed buckets.
local function layoutTimeStrips(self, stats, y, w, pad)
  local P, H = self.pool, self.headers
  local keys = dayKeyList(stats.totals.firstTs, stats.totals.lastTs)
  local dayB, valB = {}, {}
  for _, k in ipairs(keys) do
    local c = stats.byDay[k] or 0
    local v = stats.valueByDay[k] or 0
    local lbl = shortDay(k)
    dayB[#dayB + 1] = { info = k .. ":  " .. c, count = c, label = lbl }
    valB[#valB + 1] = { info = k .. ":  " .. money(v), count = v, label = lbl }
  end
  y = self:renderStrip(P.day, H.time, self.dayStrip, dayB, y, w, pad)
  y = self:renderStrip(P.vday, H.vtime, self.valueStrip, valB, y, w, pad)

  local hourB = {}
  for h = 0, 23 do
    local c = stats.byHour[h] or 0
    hourB[#hourB + 1] = { info = string.format("%02d:00  %d", h, c), count = c, label = string.format("%02d", h) }
  end
  return self:renderStrip(P.hour, H.hour, self.hourStrip, hourB, y, w, pad)
end

-- Loot by weekday — Sun..Sat, each day a unique palette color (Sun=rank 1 … Sat=rank 7).
local function layoutWeekdays(self, stats, y, w, pad)
  local rows = {}
  local wMax = 1
  for _, c in pairs(stats.byWeekday) do if c > wMax then wMax = c end end
  for d = 0, 6 do
    local c = stats.byWeekday[d]
    if c then rows[#rows + 1] = { label = WEEKDAY[d], color = Analytics.paletteColor(d + 1),
      frac = c / wMax, value = tostring(c) } end
  end
  return self:renderBarSection(self.pool.weekday, self.headers.weekday, rows, y, w, pad)
end

-- One ranked-list row per top item, star-marked at epic and above; `right` formats the value
-- column, and `keep` (optional) drops an item from the list.
local function itemListRows(items, right, keep)
  local out = {}
  for i = 1, math.min(10, #items) do
    local it = items[i]
    if not keep or keep(it) then
      local star = ((it.quality or 1) >= 4) and starMarkup() or ""
      out[#out + 1] = { name = star .. (it.itemName or ("item " .. (it.itemID or "?"))),
        nameColor = qualityColor(it.quality or 1), right = right(it) }
    end
  end
  return out
end

local function itemValue(it) return money(it.value) end
local function itemCount(it) return tostring(it.count) end
local function hasValue(it) return (it.value or 0) > 0 end

-- Ranked lists — two half-width columns:
--   left  : Top items by value → Top zones (stacked)
--   right : Top items by count
local function layoutRankedLists(self, stats, y, w, pad)
  local P = self.pool
  local colGap = 12
  local colW = math.floor((w - pad * 2 - colGap) / 2)
  local leftX, rightX = pad, pad + colW + colGap
  local MONEY_W = 110  -- value column wide enough for "Ng Ns Nc" coin strings (no wrapping)

  local valRows = itemListRows(stats.topItemsByValue, itemValue, hasValue)   -- left, top
  local itemRows = itemListRows(stats.topItems, itemCount)                    -- right, top

  -- Top zones (left, below the value list).
  local zoneRows = {}
  for i = 1, math.min(10, #stats.topZones) do
    local z = stats.topZones[i]
    zoneRows[#zoneRows + 1] = { name = z.zone, right = tostring(z.count) }
  end

  local zoneY = y
  if #valRows > 0 then
    local hVal = self:renderListPanel(P.itemval, self.itemValuePanel, valRows, y, colW, leftX, MONEY_W)
    zoneY = y - hVal - SECTION_GAP
  else
    self.itemValuePanel:Hide()
  end
  local hItem = self:renderListPanel(P.item, self.itemPanel, itemRows, y, colW, rightX)
  local hZone = self:renderListPanel(P.zone, self.zonePanel, zoneRows, zoneY, colW, leftX)

  local leftH = (y - zoneY) + hZone -- top of column (y) down to the bottom of the zone panel
  return y - math.max(leftH, hItem) - SECTION_GAP
end

-- The source legend under Currency by Type × Source, ordered by each source's currency total.
local function layoutCurrencySourceLegend(self, stats, y, w, pad)
  local legendRows = {}
  for _, le in ipairs(sortedByCount(stats.currencyBySource or {})) do
    legendRows[#legendRows + 1] = { label = NS.Constants.SourceLabel[le.key] or le.key,
      color = SOURCE_COLOR[le.key] or NEUTRAL }
  end
  return self:renderLegend(self.pool.curlegend, legendRows, y, w, pad)
end

-- Currency by Type × Source: one stacked bar per currency, segments colored by source, then the
-- source legend.
local function layoutCurrencySources(self, stats, y, w, pad)
  local P, H = self.pool, self.headers
  local curMax = 1
  for _, curTotal in pairs(stats.byCurrency) do if curTotal > curMax then curMax = curTotal end end
  local stackRows = {}
  for _, e in ipairs(sortedByCount(stats.byCurrency)) do
    local perSrc = stats.currencySourceMatrix[e.key] or {}
    local order = {}
    for srcKey in pairs(perSrc) do order[#order + 1] = srcKey end
    table.sort(order, function(a, b) return (perSrc[a] or 0) > (perSrc[b] or 0) end)
    local curSegs = {}
    for _, srcKey in ipairs(order) do
      curSegs[#curSegs + 1] = { frac = (perSrc[srcKey] or 0) / curMax, color = SOURCE_COLOR[srcKey] or NEUTRAL,
        tip = (NS.Constants.SourceLabel[srcKey] or srcKey) .. ": " .. (perSrc[srcKey] or 0) }
    end
    stackRows[#stackRows + 1] = { label = e.key, value = tostring(e.count), segments = curSegs }
  end
  y = self:renderStackedBarSection(P.cursrc, H.currencySrc, stackRows, y, w, pad)
  return layoutCurrencySourceLegend(self, stats, y, w, pad)
end

-- The CURRENCY block, under its divider: Currency Collected, Currency by Type × Source, Currency by
-- Character × Type and Currency Over Time.
local function layoutCurrency(self, stats, y, w, pad)
  local P, H = self.pool, self.headers
  y = placeDivider(self, self.currencyDivider, y, pad)

  -- Currency Collected — one bar per currency, colored per currency from the standard palette
  -- (rank = qty order). curColor is shared with Currency by Character × Type so a currency keeps one
  -- color across both charts.
  local curKeys = {}
  for _, e in ipairs(sortedByCount(stats.byCurrency)) do curKeys[#curKeys + 1] = e.key end
  local curColor = paletteMap(curKeys)
  local curMaxCollected = 1
  for _, curTotal in pairs(stats.byCurrency) do if curTotal > curMaxCollected then curMaxCollected = curTotal end end
  local collectedRows = {}
  for _, e in ipairs(sortedByCount(stats.byCurrency)) do
    collectedRows[#collectedRows + 1] = { label = e.key, color = curColor[e.key] or NEUTRAL,
      frac = e.count / curMaxCollected, value = tostring(e.count) }
  end
  y = self:renderBarSection(P.curcollected, H.currencyCollected, collectedRows, y, w, pad, P.curcollectedleg)

  y = layoutCurrencySources(self, stats, y, w, pad)

  -- Currency by Character × Type — one stacked bar per character, segmented by currency (each a
  -- distinct palette color, shared with Currency Collected via curColor). Currencies ordered by
  -- global qty so a given currency keeps a consistent segment position across character rows.
  local ccRows = Analytics._buildCharStackRows(stats.currencyCharMatrix, stats.byChar, curKeys,
    function(cname) return curColor[cname] or NEUTRAL end, countText,
    function(cname) return cname end)
  y = self:renderStackedBarSection(P.curchar, H.currencyChar, ccRows, y, w, pad)

  -- Legend: one swatch per currency, matching the segment colors.
  local curCharLegend = {}
  for _, cname in ipairs(curKeys) do
    curCharLegend[#curCharLegend + 1] = { label = cname, color = curColor[cname] or NEUTRAL }
  end
  y = self:renderLegend(P.curcharlegend, curCharLegend, y, w, pad)

  -- Currency over time (per-day strip of total currency quantity).
  local ckeys = dayKeyList(stats.totals.firstTs, stats.totals.lastTs)
  local curDayB = {}
  for _, k in ipairs(ckeys) do
    local c = stats.currencyByDay[k] or 0
    curDayB[#curDayB + 1] = { info = k .. ":  " .. c, count = c, label = shortDay(k) }
  end
  return self:renderStrip(P.curday, H.currencyTime, self.currencyStrip, curDayB, y, w, pad)
end

local function hideCurrency(self)
  local H = self.headers
  H.currencyCollected:Hide(); H.currencySrc:Hide(); H.currencyChar:Hide(); H.currencyTime:Hide()
  self.currencyStrip:Hide()
  self.currencyDivider:Hide()
end

-- The LOOT sections, in draw order, after the LOOT divider.
local LOOT_SECTIONS = { layoutCharacters, layoutSources, layoutValueSources, layoutQualities,
                        layoutItemTypes, layoutBoundTypes, layoutTimeStrips, layoutWeekdays,
                        layoutRankedLists }

-- Bind + position every chart off self.stats for the given width; return the final y cursor.
function Analytics:LayoutCharts(y, w, pad)
  local stats, P = self.stats, self.pool
  for _, name in ipairs(CHART_POOLS) do
    NS.Pool.ReleaseAll(P[name])
  end

  -- Empty only when the range holds neither a gain nor a loss/transfer: a losses-only range still
  -- draws the GAINS & LOSSES section, with no LOOT sections under it.
  local AL = Analytics._ledger
  local hasLoot = stats and stats.totals.records > 0
  if not stats or (not hasLoot and not AL.HasLedger(stats)) then
    self:HideAllCharts()
    self.emptyText:ClearAllPoints()
    self.emptyText:SetPoint("TOP", self.content, "TOP", 0, y - 10)
    self.emptyText:Show()
    return y - 50
  end
  self.emptyText:Hide()

  -- No gains: hide the LOOT chrome first; AL.Layout below re-shows its own.
  if not hasLoot then self:HideAllCharts() end
  y = AL.Layout(self, stats, y, w, pad)
  if hasLoot then
    y = placeDivider(self, self.lootDivider, y, pad)
    for _, section in ipairs(LOOT_SECTIONS) do
      y = section(self, stats, y, w, pad)
    end
  end

  local ct = stats.currencyTotals or { distinct = 0, events = 0 }
  if ct.events and ct.events > 0 then
    y = layoutCurrency(self, stats, y, w, pad)
  else
    hideCurrency(self)
  end

  return y
end
