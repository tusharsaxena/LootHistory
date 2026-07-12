local addonName, NS = ...
NS.Analytics = NS.Analytics or {}
local Analytics = NS.Analytics

-- Insights tab: stat cards + source/quality/time breakdowns + top zones/items, scoped by a
-- date-range selector (see docs/UX_DESIGN §4, docs/TECHNICAL_DESIGN §8). Everything is driven
-- off a single Database:Stats(filter) pass; widgets are pooled and re-laid-out on resize.

local WHITE = "Interface\\Buttons\\WHITE8X8"

local BAR_H, BAR_GAP = 16, 3
local SECTION_GAP = 16
local DAYSTRIP_H = 46
local LIST_ROW_H = 16
local LABELW, VALW = 84, 92   -- fixed label/value columns in a horizontal bar; track fills the rest
local MAX_DAY_BARS = 60        -- cap the per-day strip so long "All" ranges stay readable

-- Per-source bar colours (no such table in Constants; kept local to the chart).
local SOURCE_COLOR = {
  KILL      = { 0.85, 0.35, 0.35 }, CONTAINER = { 0.85, 0.65, 0.30 },
  MPLUS     = { 0.65, 0.45, 0.90 }, ROLL      = { 0.40, 0.75, 0.55 },
  QUEST     = { 0.95, 0.82, 0.35 }, TRADE     = { 0.45, 0.70, 0.95 },
  MAIL      = { 0.60, 0.75, 0.85 }, AH        = { 0.90, 0.55, 0.75 },
  VENDOR    = { 0.70, 0.70, 0.75 }, CRAFT     = { 0.55, 0.80, 0.70 },
  OTHER     = { 0.55, 0.55, 0.60 },
}

-- Gold star before epic+ items in the Top-items list. Uses whichever star atlas exists on this
-- client; falls back to no star (the quality colour still marks it) so it never renders a box.
local STAR_ATLASES = { "PetJournal-FavoritesIcon", "auctionhouse-icon-favorite", "communities-icon-star" }
local resolvedStar
local function starMarkup()
  if resolvedStar ~= nil then return resolvedStar end
  resolvedStar = ""
  if CreateAtlasMarkup and C_Texture and C_Texture.GetAtlasInfo then
    for _, a in ipairs(STAR_ATLASES) do
      if C_Texture.GetAtlasInfo(a) then resolvedStar = CreateAtlasMarkup(a, 12, 12) .. " "; break end
    end
  end
  return resolvedStar
end

-- Simple show/hide object pools shared by the chart widgets.
local function acquire(pool, factory)
  local o = table.remove(pool.free)
  if not o then o = factory() end
  pool.active[#pool.active + 1] = o
  o:Show()
  return o
end
local function releaseAll(pool)
  for _, o in ipairs(pool.active) do o:Hide() end
  wipe(pool.active)
end

-- A horizontal bar row: fixed label (left) + value (right), track + fill between them.
local function makeBar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(BAR_H)
  local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetJustifyH("LEFT")
  bar.label = label
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(1, 1, 1, 0.06)
  bar.track = track
  local fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill = fill
  local value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  value:SetJustifyH("RIGHT")
  bar.value = value
  return bar
end

local function positionBar(bar, content, pad, y, barW, frac)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y)
  bar:SetWidth(barW)
  bar.label:ClearAllPoints(); bar.label:SetPoint("LEFT", 0, 0); bar.label:SetWidth(LABELW)
  bar.value:ClearAllPoints(); bar.value:SetPoint("RIGHT", 0, 0); bar.value:SetWidth(VALW)
  local trackW = math.max(1, barW - LABELW - VALW - 12)
  bar.track:ClearAllPoints(); bar.track:SetPoint("LEFT", LABELW + 6, 0); bar.track:SetSize(trackW, BAR_H - 4)
  bar.fill:ClearAllPoints(); bar.fill:SetPoint("LEFT", bar.track, "LEFT", 0, 0)
  bar.fill:SetSize(math.max(1, trackW * math.min(1, frac)), BAR_H - 4)
end

-- One vertical bar in the per-day strip; hovering shows the day + count.
local function makeDayBar(parent)
  local f = CreateFrame("Frame", nil, parent)
  local fill = f:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("BOTTOM", 0, 0)
  fill:SetColorTexture(0.40, 0.60, 0.95, 0.9)
  f.fill = fill
  f:SetScript("OnEnter", function(self2)
    if not self2.info then return end
    GameTooltip:SetOwner(self2, "ANCHOR_TOP")
    GameTooltip:AddLine(self2.info, 1, 1, 1)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

-- A ranked-list row: name (left, may be quality-coloured) + count (right).
local function makeListRow(parent)
  local r = CreateFrame("Frame", nil, parent)
  r:SetHeight(LIST_ROW_H)
  local name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetJustifyH("LEFT"); name:SetPoint("LEFT", 4, 0); name:SetWordWrap(false)
  r.name = name
  local count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  count:SetJustifyH("RIGHT"); count:SetPoint("RIGHT", -4, 0)
  r.count = count
  return r
end

-- Date-range options for the selector. The range key → `from` timestamp mapping lives in
-- Util.RangeFrom (shared with the Browser date filter).
local RANGES = {
  { value = "today", label = "Today" },
  { value = "7d",    label = "7 days" },
  { value = "30d",   label = "30 days" },
  { value = "all",   label = "All" },
}

-- The four stat cards, left→right.
local CARD_DEFS = {
  { key = "records", label = "records" },
  { key = "items",   label = "distinct items" },
  { key = "chars",   label = "characters" },
  { key = "span",    label = "date range" },
}

Analytics.range = "30d"

-- ── Build ────────────────────────────────────────────────────────────────────────

function Analytics:Attach(pane)
  if self.pane then return end
  self.pane = pane

  -- Range selector (fixed above the scroll).
  local bar = CreateFrame("Frame", nil, pane)
  bar:SetPoint("TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", 0, 0)
  bar:SetHeight(22)
  local lbl = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lbl:SetPoint("LEFT", 2, 0)
  lbl:SetText("Range:")
  lbl:SetTextColor(0.8, 0.8, 0.82)

  self.rangeButtons = {}
  local x = 48
  for _, r in ipairs(RANGES) do
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(58, 20)
    b:SetPoint("LEFT", x, 0)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    fs:SetText(r.label)
    b.fs = fs
    b:SetScript("OnClick", function() Analytics:SetRange(r.value) end)
    self.rangeButtons[r.value] = b
    x = x + 62
  end

  -- Scrollable content host.
  local scroll = CreateFrame("ScrollFrame", "LootHistoryInsightsScroll", pane, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -26, 4)
  self.scroll = scroll
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  self.content = content
  scroll:SetScript("OnSizeChanged", function() Analytics:Layout() end)

  -- Stat cards.
  self.cards = {}
  for _, def in ipairs(CARD_DEFS) do
    local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
    card:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                       insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    card:SetBackdropColor(0.1, 0.1, 0.12, 0.85)
    card:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
    -- The span card holds a longer string, so it uses a smaller number font.
    local num = card:CreateFontString(nil, "OVERLAY",
      def.key == "span" and "GameFontNormal" or "GameFontNormalHuge")
    num:SetPoint("TOP", 0, -9)
    num:SetPoint("LEFT", 2, 0)
    num:SetPoint("RIGHT", -2, 0)
    num:SetJustifyH("CENTER")
    num:SetTextColor(1, 0.82, 0)
    local cl = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cl:SetPoint("BOTTOM", 0, 7)
    cl:SetText(def.label)
    self.cards[def.key] = { frame = card, num = num }
  end

  self:BuildCharts(content)
  self:UpdateRangeButtons()
  self:Refresh()
end

-- ── Range control ─────────────────────────────────────────────────────────────────

function Analytics:SetRange(range)
  self.range = range
  self:UpdateRangeButtons()
  self:Refresh()
end

function Analytics:UpdateRangeButtons()
  for val, b in pairs(self.rangeButtons or {}) do
    if val == self.range then
      b.fs:SetTextColor(1, 0.82, 0)
    else
      b.fs:SetTextColor(0.7, 0.7, 0.72)
    end
  end
end

-- ── Refresh + layout ──────────────────────────────────────────────────────────────

function Analytics:Refresh()
  if not self.content then return end
  local from = NS.Util.RangeFrom(self.range)
  local stats = NS.Database:Stats(from and { from = from } or {})
  self.stats = stats
  self:UpdateCards(stats)
  self:Layout() -- Layout → LayoutCharts binds the charts off self.stats
end

function Analytics:UpdateCards(stats)
  local t = stats.totals
  self.cards.records.num:SetText(tostring(t.records))
  self.cards.items.num:SetText(tostring(t.distinctItems))
  self.cards.chars.num:SetText(tostring(t.distinctChars))
  local span = "\226\128\148" -- em-dash
  if t.firstTs and t.lastTs then
    span = NS.Util.FormatDate(t.firstTs) .. "  \226\128\147  " .. NS.Util.FormatDate(t.lastTs) -- – en-dash
  end
  self.cards.span.num:SetText(span)
end

-- Position everything top-down given the current content width; set the scroll child height.
function Analytics:Layout()
  if not self.content then return end
  local w = self.scroll:GetWidth()
  if not w or w <= 0 then w = 780 end
  self.content:SetWidth(w)

  local PAD, GAP = 8, 8
  local cardW = math.floor((w - PAD * 2 - GAP * 3) / 4)
  local cardH = 52
  local x = PAD
  for _, def in ipairs(CARD_DEFS) do
    local c = self.cards[def.key]
    c.frame:ClearAllPoints()
    c.frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -PAD)
    c.frame:SetSize(cardW, cardH)
    x = x + cardW + GAP
  end

  local y = -PAD - cardH - 14
  y = self:LayoutCharts(y, w, PAD)
  self.content:SetHeight(math.max(1, -y + PAD))
end

-- ── Charts ─────────────────────────────────────────────────────────────────────────

local function sectionHeader(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetText(text)
  fs:SetTextColor(1, 0.82, 0)
  return fs
end

local function listPanel(parent, title)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  p:SetBackdropColor(0.08, 0.08, 0.10, 0.6)
  p:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.7)
  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  t:SetPoint("TOPLEFT", 6, -5)
  t:SetTextColor(1, 0.82, 0)
  t:SetText(title)
  p.title = t
  return p
end

-- Build the persistent chart chrome (section headers, day strip, top-list panels, pools) once.
function Analytics:BuildCharts(content)
  self.headers = {
    source  = sectionHeader(content, "Loot by source"),
    quality = sectionHeader(content, "Quality distribution"),
    time    = sectionHeader(content, "Loot over time (per day)"),
  }
  self.dayStrip = CreateFrame("Frame", nil, content)
  self.zonePanel = listPanel(content, "Top zones")
  self.itemPanel = listPanel(content, "Top items")
  self.emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
  self.emptyText:SetText("No loot in this range.")
  self.emptyText:Hide()
  self.pool = {
    source = { free = {}, active = {} }, quality = { free = {}, active = {} },
    day    = { free = {}, active = {} }, zone    = { free = {}, active = {} },
    item   = { free = {}, active = {} },
  }

  -- Live-update while the Insights tab is visible (new loot / deletes / prune).
  if NS.bus and not self._subscribed then
    self._subscribed = true
    local function live()
      if self.pane and self.pane:IsVisible() then Analytics:Refresh() end
    end
    NS.bus:RegisterMessage("Ka0s_LootHistory_RecordAdded", live)
    NS.bus:RegisterMessage("Ka0s_LootHistory_HistoryChanged", live)
  end
end

-- Bind + position every chart off self.stats for the given width; return the final y cursor.
function Analytics:LayoutCharts(y, w, pad)
  local stats, content, P = self.stats, self.content, self.pool
  releaseAll(P.source); releaseAll(P.quality); releaseAll(P.day)
  releaseAll(P.zone);   releaseAll(P.item)
  local H = self.headers

  if not stats or stats.totals.records == 0 then
    H.source:Hide(); H.quality:Hide(); H.time:Hide()
    self.dayStrip:Hide(); self.zonePanel:Hide(); self.itemPanel:Hide()
    self.emptyText:ClearAllPoints()
    self.emptyText:SetPoint("TOP", content, "TOP", 0, y - 10)
    self.emptyText:Show()
    return y - 50
  end
  self.emptyText:Hide()
  local innerW = w - pad * 2
  local total = stats.totals.records

  -- Loot by source — bars sorted by count desc, length = share of all records.
  H.source:ClearAllPoints(); H.source:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y); H.source:Show()
  y = y - 18
  local srcRows = {}
  for src, count in pairs(stats.bySource) do srcRows[#srcRows + 1] = { src = src, count = count } end
  table.sort(srcRows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.src < b.src
  end)
  for _, row in ipairs(srcRows) do
    local bar = acquire(P.source, function() return makeBar(content) end)
    local col = SOURCE_COLOR[row.src] or { 0.6, 0.6, 0.65 }
    bar.fill:SetColorTexture(col[1], col[2], col[3], 0.95)
    bar.label:SetText(NS.Constants.SourceLabel[row.src] or row.src)
    bar.label:SetTextColor(0.9, 0.9, 0.9)
    bar.value:SetText(string.format("%d  %d%%", row.count, math.floor(row.count / total * 100 + 0.5)))
    bar.value:SetTextColor(0.8, 0.8, 0.82)
    positionBar(bar, content, pad, y, innerW, row.count / total)
    y = y - (BAR_H + BAR_GAP)
  end
  y = y - SECTION_GAP

  -- Quality distribution — bars in quality order, length relative to the biggest bucket.
  H.quality:ClearAllPoints(); H.quality:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y); H.quality:Show()
  y = y - 18
  local qRows, qMax = {}, 1
  for q, count in pairs(stats.byQuality) do
    qRows[#qRows + 1] = { q = q, count = count }
    if count > qMax then qMax = count end
  end
  table.sort(qRows, function(a, b) return a.q < b.q end)
  for _, row in ipairs(qRows) do
    local bar = acquire(P.quality, function() return makeBar(content) end)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.q]
    if c then bar.fill:SetColorTexture(c.r, c.g, c.b, 0.95) else bar.fill:SetColorTexture(0.6, 0.6, 0.6, 0.95) end
    bar.label:SetText(NS.Compat.QualityLabel(row.q))
    if c then bar.label:SetTextColor(c.r, c.g, c.b) else bar.label:SetTextColor(0.9, 0.9, 0.9) end
    bar.value:SetText(tostring(row.count))
    bar.value:SetTextColor(0.8, 0.8, 0.82)
    positionBar(bar, content, pad, y, innerW, row.count / qMax)
    y = y - (BAR_H + BAR_GAP)
  end
  y = y - SECTION_GAP

  -- Loot over time — a per-day bar strip across firstTs..lastTs (gaps filled with 0).
  H.time:ClearAllPoints(); H.time:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y); H.time:Show()
  y = y - 18
  local days = {}
  local t = stats.totals
  if t.firstTs and t.lastTs then
    local function dayStart(ts) local d = date("*t", ts); return ts - (d.hour * 3600 + d.min * 60 + d.sec) end
    for ts = dayStart(t.firstTs), dayStart(t.lastTs), 86400 do
      local key = date("%Y-%m-%d", ts)
      days[#days + 1] = { key = key, count = stats.byDay[key] or 0 }
    end
    if #days > MAX_DAY_BARS then
      local trimmed = {}
      for i = #days - MAX_DAY_BARS + 1, #days do trimmed[#trimmed + 1] = days[i] end
      days = trimmed
    end
  end
  local strip = self.dayStrip
  strip:ClearAllPoints(); strip:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y)
  strip:SetSize(innerW, DAYSTRIP_H); strip:Show()
  local n = #days
  local slot = n > 0 and (innerW / n) or innerW
  local barW = math.max(2, math.min(14, slot - 2))
  local maxC = 1
  for _, d in ipairs(days) do if d.count > maxC then maxC = d.count end end
  for i, d in ipairs(days) do
    local f = acquire(P.day, function() return makeDayBar(strip) end)
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", (i - 1) * slot, 0)
    f:SetSize(barW, DAYSTRIP_H)
    f.fill:SetSize(barW, math.max(1, (d.count / maxC) * (DAYSTRIP_H - 2)))
    f.fill:SetAlpha(d.count == 0 and 0.12 or 0.9)
    f.info = d.key .. ":  " .. d.count
  end
  y = y - DAYSTRIP_H - SECTION_GAP

  -- Top zones / Top items — two ranked columns (top 10 each).
  local colGap = 12
  local colW = math.floor((innerW - colGap) / 2)
  local nZones = math.min(10, #stats.topZones)
  local nItems = math.min(10, #stats.topItems)
  local panelH = 20 + math.max(nZones, nItems, 1) * LIST_ROW_H + 4

  local zp, ip = self.zonePanel, self.itemPanel
  zp:ClearAllPoints(); zp:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y); zp:SetSize(colW, panelH); zp:Show()
  ip:ClearAllPoints(); ip:SetPoint("TOPLEFT", content, "TOPLEFT", pad + colW + colGap, y); ip:SetSize(colW, panelH); ip:Show()

  for i = 1, nZones do
    local z = stats.topZones[i]
    local r = acquire(P.zone, function() return makeListRow(zp) end)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", zp, "TOPLEFT", 4, -20 - (i - 1) * LIST_ROW_H); r:SetWidth(colW - 8)
    r.name:SetWidth(colW - 8 - 44); r.name:SetText(z.zone); r.name:SetTextColor(0.9, 0.9, 0.9)
    r.count:SetWidth(40); r.count:SetText(tostring(z.count)); r.count:SetTextColor(0.8, 0.8, 0.82)
  end
  for i = 1, nItems do
    local it = stats.topItems[i]
    local r = acquire(P.item, function() return makeListRow(ip) end)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", ip, "TOPLEFT", 4, -20 - (i - 1) * LIST_ROW_H); r:SetWidth(colW - 8)
    local q = it.quality or 1
    local star = (q >= 4) and starMarkup() or ""
    r.name:SetWidth(colW - 8 - 44)
    r.name:SetText(star .. (it.itemName or ("item " .. (it.itemID or "?"))))
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then r.name:SetTextColor(c.r, c.g, c.b) else r.name:SetTextColor(0.9, 0.9, 0.9) end
    r.count:SetWidth(40); r.count:SetText(tostring(it.count)); r.count:SetTextColor(0.8, 0.8, 0.82)
  end

  return y - panelH - 4
end
