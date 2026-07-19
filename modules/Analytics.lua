local addonName, NS = ...
NS.Analytics = NS.Analytics or {}
local Analytics = NS.Analytics

-- Insights tab: stat/highlight cards + a stack of breakdown sections (source, value, quality,
-- item type, bound type, per-character, time-of-day/week, M+ keystone, confidence) plus top
-- zones/items/value lists, scoped by a date-range selector (see docs/browser.md). Everything
-- is driven off a single Database:Stats(filter) pass; widgets are pooled and re-laid-out on resize.
-- "Value" is vendor value (vendorPrice × quantity), not market price.

local WHITE = "Interface\\Buttons\\WHITE8X8"

local BAR_H, BAR_GAP = 16, 3
local SECTION_GAP = 16
local DAYSTRIP_H = 46
local STRIP_LABEL_H = 44   -- reserved space under a strip for the rotated x-axis labels
local STRIP_AXIS_GAP = 2   -- gap between the bar bases and the separator line
local STRIP_LABEL_GAP = 7  -- gap between the separator line and the label text
local LABEL_X_ADJUST = -2  -- nudge to visually centre the rotated label under the bar (tunable)
local LIST_ROW_H = 16
local LABELW, VALW = 84, 92   -- fixed label/value columns in a horizontal bar; track fills the rest
local MAX_DAY_BARS = 60        -- cap the per-day strip so long "All" ranges stay readable
local NEUTRAL = { 0.55, 0.62, 0.72 }

-- Per-source bar colours (no such table in Constants; kept local to the chart).
local SOURCE_COLOR = {
  KILL      = { 0.85, 0.35, 0.35 }, CONTAINER = { 0.85, 0.65, 0.30 },
  MPLUS     = { 0.65, 0.45, 0.90 }, ROLL      = { 0.40, 0.75, 0.55 },
  QUEST     = { 0.95, 0.82, 0.35 }, TRADE     = { 0.45, 0.70, 0.95 },
  MAIL      = { 0.60, 0.75, 0.85 }, AH        = { 0.90, 0.55, 0.75 },
  VENDOR    = { 0.70, 0.70, 0.75 }, CRAFT     = { 0.55, 0.80, 0.70 },
  DISENCHANT = { 0.80, 0.50, 0.90 }, MILLING   = { 0.55, 0.75, 0.45 },
  PROSPECTING = { 0.45, 0.75, 0.80 },
  OTHER     = { 0.55, 0.55, 0.60 },
}

-- Bound-type display labels + colours.
local BOUND_LABEL = {
  BOP = "Soulbound", BOE = "BoE", ACCOUNT = "Account", WARBAND = "Warbound", UNBOUND = "Unbound",
}
local BOUND_COLOR = {
  BOP = { 0.85, 0.45, 0.45 }, BOE = { 0.55, 0.80, 0.60 }, ACCOUNT = { 0.60, 0.70, 0.90 },
  WARBAND = { 0.80, 0.65, 0.40 }, UNBOUND = { 0.60, 0.60, 0.65 },
}
local BOUND_ORDER = { "BOP", "BOE", "WARBAND", "ACCOUNT", "UNBOUND" }

local WEEKDAY = { [0] = "Sun", [1] = "Mon", [2] = "Tue", [3] = "Wed", [4] = "Thu", [5] = "Fri", [6] = "Sat" }
local CONF_LABEL = { CERTAIN = "Certain", INFERRED = "Inferred" }
local CONF_COLOR = { CERTAIN = { 0.45, 0.75, 0.55 }, INFERRED = { 0.80, 0.70, 0.40 } }

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

-- Class colour for a per-character bar (falls back to a neutral grey).
local function classColor(classFile)
  local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if c then return { c.r, c.g, c.b } end
  return { 0.7, 0.7, 0.72 }
end

-- Item-quality colour as an {r,g,b} triple (falls back to neutral grey).
local function qualityColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
  if c then return { c.r, c.g, c.b } end
  return { 0.6, 0.6, 0.6 }
end

-- Short character label ("Name-Realm" → "Name") for narrow per-character bars.
local function shortChar(key) return (key and key:match("^[^-]+")) or key or "?" end

-- Value → display string (coin glyphs in-game, "Ng Ns Nc" headless; "0" when zero).
local function money(copper)
  copper = copper or 0
  if copper <= 0 then return "0" end
  return NS.Util.FormatMoney(copper)
end

-- ── Widget primitives (pooled) ─────────────────────────────────────────────────────
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

-- A single horizontal bar split into coloured segments (used for the Quality-mix composition).
local function makeStackedBar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(BAR_H)
  local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetJustifyH("LEFT")
  bar.label = label
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(1, 1, 1, 0.06)
  bar.track = track
  local value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  value:SetJustifyH("RIGHT")
  bar.value = value
  bar.segs = {}
  for i = 1, 9 do bar.segs[i] = bar:CreateTexture(nil, "ARTWORK") end
  return bar
end

-- segments: ordered array of { frac (0..1 of the track), color = {r,g,b} }; fracs sum ≤ 1.
local function positionStacked(bar, content, pad, y, barW, segments)
  bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y); bar:SetWidth(barW)
  bar.label:ClearAllPoints(); bar.label:SetPoint("LEFT", 0, 0); bar.label:SetWidth(LABELW)
  bar.value:ClearAllPoints(); bar.value:SetPoint("RIGHT", 0, 0); bar.value:SetWidth(VALW)
  local trackW = math.max(1, barW - LABELW - VALW - 12)
  bar.track:ClearAllPoints(); bar.track:SetPoint("LEFT", LABELW + 6, 0); bar.track:SetSize(trackW, BAR_H - 4)
  local x = 0
  for i = 1, #bar.segs do
    local seg, sd = bar.segs[i], segments[i]
    if sd and sd.frac and sd.frac > 0 then
      local segW = math.max(1, trackW * math.min(1, sd.frac))
      seg:ClearAllPoints(); seg:SetPoint("LEFT", bar.track, "LEFT", x, 0); seg:SetSize(segW, BAR_H - 4)
      seg:SetColorTexture(sd.color[1], sd.color[2], sd.color[3], 0.95)
      seg:Show()
      x = x + segW
    else
      seg:Hide()
    end
  end
end

-- One vertical bar in a per-bucket strip; hovering shows the bucket's info line.
local function makeStripBar(parent)
  local f = CreateFrame("Frame", nil, parent)
  local fill = f:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("BOTTOM", 0, 0)
  fill:SetColorTexture(0.40, 0.60, 0.95, 0.9)
  f.fill = fill
  -- Vertical axis label under the bar, rotated 90° CCW so it reads bottom-to-top. It is
  -- right-aligned to the axis line (top of the label at the line, hanging down) in renderStrip,
  -- where its measured width sets the anchor offset.
  local axis = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  axis:SetRotation(math.pi / 2)
  axis:SetTextColor(0.7, 0.7, 0.72)
  f.axis = axis
  f:SetScript("OnEnter", function(self2)
    if not self2.info then return end
    GameTooltip:SetOwner(self2, "ANCHOR_TOP")
    GameTooltip:AddLine(self2.info, 1, 1, 1)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

-- A ranked-list row: name (left, may be quality-coloured) + count/value (right).
local function makeListRow(parent)
  local r = CreateFrame("Frame", nil, parent)
  r:SetHeight(LIST_ROW_H)
  local name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetJustifyH("LEFT"); name:SetPoint("LEFT", 4, 0); name:SetWordWrap(false)
  r.name = name
  local count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  count:SetJustifyH("RIGHT"); count:SetPoint("RIGHT", -4, 0); count:SetWordWrap(false)
  r.count = count
  return r
end

-- Stat / highlight cards, in row order (4 columns per row; `wide` spans 2). `str` cards hold a
-- string (smaller font). Value strings are produced in UpdateCards.
local CARD_DEFS = {
  { key = "records", label = "records" },
  { key = "items",   label = "distinct items" },
  { key = "chars",   label = "characters" },
  { key = "value",   label = "value", str = true },
  { key = "active",  label = "active days" },
  { key = "epic",    label = "epic+ drops" },
  { key = "best",    label = "best drop (ilvl)" },
  { key = "richest", label = "richest drop", str = true },
  { key = "span",    label = "date range", str = true, wide = true },
  { key = "busy",    label = "busiest day", str = true, wide = true },
}

-- ── Build ────────────────────────────────────────────────────────────────────────

function Analytics:Attach(pane)
  if self.pane then return end
  self.pane = pane

  -- No range selector here (issue #13): the Insights view is scoped by the browser's shared filter
  -- bar (its Date dropdown + every column filter), so the charts fill the whole pane below.
  local scroll = CreateFrame("ScrollFrame", "LootHistoryInsightsScroll", pane, "UIPanelScrollFrameTemplate")
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
    -- String cards hold a longer value, so they use a smaller number font.
    local num = card:CreateFontString(nil, "OVERLAY", def.str and "GameFontNormal" or "GameFontNormalHuge")
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
  self:Refresh()
end

-- ── Refresh + layout ──────────────────────────────────────────────────────────────

-- Pure one-line summary for the [Insights] trace.
function Analytics.SummaryLine(scope, count)
  return ("computed range=%s, %s records"):format(tostring(scope), tostring(count))
end

function Analytics:Refresh()
  if not self.content then return end
  -- Scope by the browser's shared filter (issue #13) so the Insights view and the History table
  -- always reflect the exact same criteria; empty filter = the whole (visible) history.
  local filter = (NS.Browser and NS.Browser.CurrentFilter and NS.Browser:CurrentFilter()) or {}
  local stats = NS.Database:Stats(filter)
  self.stats = stats
  self:UpdateCards(stats)
  self:Layout() -- Layout → LayoutCharts binds the charts off self.stats
  if NS.State.debug and NS.Debug then
    local scope = next(filter) and "filtered" or "all"
    NS.Debug("Insights", "%s", Analytics.SummaryLine(scope, stats.totals.records))
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
    col = col + span
  end

  local y = rowY - cardH - 14
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

-- Build the persistent chart chrome (section headers, strips, list panels, pools) once.
function Analytics:BuildCharts(content)
  self.headers = {
    source  = sectionHeader(content, "Loot by source"),
    vsource = sectionHeader(content, "Value by source"),
    quality = sectionHeader(content, "Quality distribution"),
    qmix    = sectionHeader(content, "Quality mix"),
    itype   = sectionHeader(content, "Loot by item type"),
    bound   = sectionHeader(content, "Loot by bound type"),
    char    = sectionHeader(content, "Loot by character"),
    time    = sectionHeader(content, "Loot over time (per day)"),
    vtime   = sectionHeader(content, "Value over time (per day)"),
    hour    = sectionHeader(content, "Loot by hour of day"),
    weekday = sectionHeader(content, "Loot by weekday"),
    keystone = sectionHeader(content, "Mythic+ loot by keystone level"),
    conf    = sectionHeader(content, "Attribution confidence"),
  }
  self.dayStrip   = CreateFrame("Frame", nil, content)
  self.valueStrip = CreateFrame("Frame", nil, content)
  self.hourStrip  = CreateFrame("Frame", nil, content)
  self.zonePanel  = listPanel(content, "Top zones")
  self.itemPanel  = listPanel(content, "Top items by count")
  self.itemValuePanel = listPanel(content, "Top items by value")
  self.emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
  self.emptyText:SetText("No loot in this range.")
  self.emptyText:Hide()
  self.pool = {
    source = { free = {}, active = {} }, vsource = { free = {}, active = {} },
    quality = { free = {}, active = {} }, qmix = { free = {}, active = {} },
    itype  = { free = {}, active = {} }, bound   = { free = {}, active = {} },
    char   = { free = {}, active = {} }, day     = { free = {}, active = {} },
    vday   = { free = {}, active = {} }, hour    = { free = {}, active = {} },
    weekday = { free = {}, active = {} }, keystone = { free = {}, active = {} },
    conf   = { free = {}, active = {} }, zone    = { free = {}, active = {} },
    item   = { free = {}, active = {} }, itemval = { free = {}, active = {} },
  }

  -- Live-update while the Insights tab is visible (new loot / deletes / prune).
  if NS.bus and not self._subscribed then
    self._subscribed = true
    local function live()
      if self.pane and self.pane:IsVisible() then Analytics:Refresh() end
    end
    -- Private bus target (never the shared bus-as-self) so these don't clobber the Browser's
    -- RecordAdded/HistoryChanged handlers on the same bus. See NS.NewBusTarget.
    self.__ev = NS.NewBusTarget() or NS.bus
    self.__ev:RegisterMessage("Ka0s_LootHistory_RecordAdded", live)
    self.__ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", live)
  end
end

-- Render a horizontal-bar section: header + one bar per row. rows: ordered array of
--   { label, labelColor = {r,g,b}|nil, color = {r,g,b}, frac (0..1), value = string }.
-- Returns the new y cursor (skips the section entirely when rows is empty).
function Analytics:renderBarSection(pool, header, rows, y, w, pad)
  if #rows == 0 then header:Hide(); return y end
  -- Normalize so the largest bar always fills the track and the rest scale relative to it
  -- (a no-op for sections already built max-relative). Bars are ordered by the caller.
  local maxFrac = 0
  for _, row in ipairs(rows) do if (row.frac or 0) > maxFrac then maxFrac = row.frac end end
  if maxFrac > 0 then
    for _, row in ipairs(rows) do row.frac = (row.frac or 0) / maxFrac end
  end
  header:ClearAllPoints(); header:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y); header:Show()
  y = y - 18
  local innerW = w - pad * 2
  for _, row in ipairs(rows) do
    local bar = acquire(pool, function() return makeBar(self.content) end)
    bar.fill:SetColorTexture(row.color[1], row.color[2], row.color[3], 0.95)
    bar.label:SetText(row.label)
    local lc = row.labelColor
    bar.label:SetTextColor(lc and lc[1] or 0.9, lc and lc[2] or 0.9, lc and lc[3] or 0.9)
    bar.value:SetText(row.value)
    bar.value:SetTextColor(0.8, 0.8, 0.82)
    positionBar(bar, self.content, pad, y, innerW, row.frac)
    y = y - (BAR_H + BAR_GAP)
  end
  return y - SECTION_GAP
end

-- Render a per-bucket vertical strip. buckets: ordered array of { info (hover), count, label }.
-- Each bar carries a rotated x-axis label (thinned out when bars get too narrow to fit them).
function Analytics:renderStrip(pool, header, strip, buckets, y, w, pad)
  if #buckets == 0 then header:Hide(); strip:Hide(); return y end
  header:ClearAllPoints(); header:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y); header:Show()
  y = y - 18
  local innerW = w - pad * 2
  strip:ClearAllPoints(); strip:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
  strip:SetSize(innerW, DAYSTRIP_H); strip:Show()
  local n = #buckets
  local slot = n > 0 and (innerW / n) or innerW
  local barW = math.max(2, math.min(14, slot - 2))
  local labelStride = math.max(1, math.ceil(11 / slot))  -- keep labels >= ~11px apart
  local maxC = 1
  for _, b in ipairs(buckets) do if b.count > maxC then maxC = b.count end end
  -- Axis line separating the bars (above) from the labels (below), spanning the strip. Sits a
  -- small gap below the bar bases so the bars don't touch it.
  strip.axisLine = strip.axisLine or strip:CreateTexture(nil, "ARTWORK")
  strip.axisLine:SetColorTexture(0.45, 0.45, 0.5, 0.8)
  strip.axisLine:ClearAllPoints()
  strip.axisLine:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, -STRIP_AXIS_GAP)
  strip.axisLine:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, -STRIP_AXIS_GAP)
  strip.axisLine:SetHeight(1); strip.axisLine:Show()
  for i, b in ipairs(buckets) do
    local f = acquire(pool, function() return makeStripBar(strip) end)
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", (i - 1) * slot, 0)
    f:SetSize(barW, DAYSTRIP_H)
    f.fill:SetSize(barW, math.max(1, (b.count / maxC) * (DAYSTRIP_H - 2)))
    f.fill:SetAlpha(b.count == 0 and 0.12 or 0.9)
    f.info = b.info
    if b.label and ((i - 1) % labelStride == 0) then
      f.axis:SetText(b.label)
      -- Right-align the rotated label: its top (right end pre-rotation) sits a gap below the axis
      -- line and it hangs straight down, so labels of different lengths all start at the line.
      -- Centre x on the bar; the top offset = line gap (below bar) + label gap (below line).
      local tw = f.axis:GetStringWidth() or 0
      f.axis:ClearAllPoints()
      f.axis:SetPoint("CENTER", f, "BOTTOMLEFT", barW / 2 + LABEL_X_ADJUST,
        -(tw / 2) - STRIP_AXIS_GAP - STRIP_LABEL_GAP)
      f.axis:Show()
    else
      f.axis:SetText(""); f.axis:Hide()
    end
  end
  return y - DAYSTRIP_H - STRIP_LABEL_H - SECTION_GAP
end

-- Render a ranked list panel (top zones / items / value). rows: array of
--   { name, nameColor = {r,g,b}|nil, right (string) }, capped to 10. `rightW` sizes the value
--   column — money strings (coin glyphs) need more room than plain counts. Returns new y.
function Analytics:renderListPanel(pool, panel, rows, y, colW, pad, rightW)
  rightW = rightW or 48
  local n = math.min(10, #rows)
  local panelH = 20 + math.max(n, 1) * LIST_ROW_H + 4
  panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
  panel:SetSize(colW, panelH); panel:Show()
  for i = 1, n do
    local row = rows[i]
    local r = acquire(pool, function() return makeListRow(panel) end)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -20 - (i - 1) * LIST_ROW_H)
    r:SetWidth(colW - 8)
    r.name:SetWidth(math.max(1, colW - 8 - rightW - 6)); r.name:SetText(row.name)
    local nc = row.nameColor
    r.name:SetTextColor(nc and nc[1] or 0.9, nc and nc[2] or 0.9, nc and nc[3] or 0.9)
    r.count:SetWidth(rightW); r.count:SetText(row.right); r.count:SetTextColor(0.8, 0.8, 0.82)
  end
  return panelH
end

-- Hide every chart section (used for the empty-range state).
function Analytics:HideAllCharts()
  for _, h in pairs(self.headers) do h:Hide() end
  self.dayStrip:Hide(); self.valueStrip:Hide(); self.hourStrip:Hide()
  self.zonePanel:Hide(); self.itemPanel:Hide(); self.itemValuePanel:Hide()
end

-- Build the firstTs..lastTs day-key list (gaps included), capped to MAX_DAY_BARS most recent.
local function dayKeyList(firstTs, lastTs)
  local keys = {}
  if not (firstTs and lastTs) then return keys end
  local function dayStart(ts) local d = date("*t", ts); return ts - (d.hour * 3600 + d.min * 60 + d.sec) end
  for ts = dayStart(firstTs), dayStart(lastTs), 86400 do keys[#keys + 1] = date("%Y-%m-%d", ts) end
  if #keys > MAX_DAY_BARS then
    local trimmed = {}
    for i = #keys - MAX_DAY_BARS + 1, #keys do trimmed[#trimmed + 1] = keys[i] end
    keys = trimmed
  end
  return keys
end

-- "YYYY-MM-DD" → compact "M/D" for the per-day strip's x-axis labels.
local function shortDay(k)
  local m, d = k:match("^%d+%-(%d+)%-(%d+)$")
  if m then return tonumber(m) .. "/" .. tonumber(d) end
  return k
end

-- Sort a key→count map into a { key, count } array, count desc then key asc.
local function sortedByCount(map)
  local rows = {}
  for k, c in pairs(map) do rows[#rows + 1] = { key = k, count = c } end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return tostring(a.key) < tostring(b.key)
  end)
  return rows
end

-- Bind + position every chart off self.stats for the given width; return the final y cursor.
function Analytics:LayoutCharts(y, w, pad)
  local stats, P = self.stats, self.pool
  for _, name in ipairs({ "source", "vsource", "quality", "qmix", "itype", "bound", "char",
                          "day", "vday", "hour", "weekday", "keystone", "conf", "zone", "item", "itemval" }) do
    releaseAll(P[name])
  end

  if not stats or stats.totals.records == 0 then
    self:HideAllCharts()
    self.emptyText:ClearAllPoints()
    self.emptyText:SetPoint("TOP", self.content, "TOP", 0, y - 10)
    self.emptyText:Show()
    return y - 50
  end
  self.emptyText:Hide()
  local H, total = self.headers, stats.totals.records
  local rows

  -- Loot by source — length = share of all records.
  rows = {}
  for _, e in ipairs(sortedByCount(stats.bySource)) do
    rows[#rows + 1] = {
      label = NS.Constants.SourceLabel[e.key] or e.key, color = SOURCE_COLOR[e.key] or NEUTRAL,
      frac = e.count / total, value = string.format("%d  %d%%", e.count, math.floor(e.count / total * 100 + 0.5)),
    }
  end
  y = self:renderBarSection(P.source, H.source, rows, y, w, pad)

  -- Vendor value by source — length relative to the biggest bucket.
  rows = {}
  local vMax = 1
  for _, v in pairs(stats.valueBySource) do if v > vMax then vMax = v end end
  local vsrc = {}
  for src, v in pairs(stats.valueBySource) do vsrc[#vsrc + 1] = { src = src, v = v } end
  table.sort(vsrc, function(a, b) return a.v > b.v end)
  for _, e in ipairs(vsrc) do
    if e.v > 0 then
      rows[#rows + 1] = { label = NS.Constants.SourceLabel[e.src] or e.src,
        color = SOURCE_COLOR[e.src] or NEUTRAL, frac = e.v / vMax, value = money(e.v) }
    end
  end
  y = self:renderBarSection(P.vsource, H.vsource, rows, y, w, pad)

  -- Quality distribution — bars in quality order, length relative to the biggest bucket.
  rows = {}
  local qRows, qMax = {}, 1
  for q, c in pairs(stats.byQuality) do qRows[#qRows + 1] = { q = q, c = c }; if c > qMax then qMax = c end end
  table.sort(qRows, function(a, b) return a.q < b.q end)
  for _, e in ipairs(qRows) do
    local col = qualityColor(e.q)
    rows[#rows + 1] = { label = NS.Compat.QualityLabel(e.q), labelColor = col, color = col,
      frac = e.c / qMax, value = tostring(e.c) }
  end
  y = self:renderBarSection(P.quality, H.quality, rows, y, w, pad)

  -- Quality mix — one bar, segmented low→high quality by share of records.
  local segs = {}
  for q = 0, 8 do
    local c = stats.byQuality[q]
    if c then segs[#segs + 1] = { frac = c / total, color = qualityColor(q) } end
  end
  if #segs > 0 then
    H.qmix:ClearAllPoints(); H.qmix:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y); H.qmix:Show()
    y = y - 18
    local bar = acquire(P.qmix, function() return makeStackedBar(self.content) end)
    bar.label:SetText("All loot"); bar.label:SetTextColor(0.9, 0.9, 0.9)
    bar.value:SetText(tostring(total)); bar.value:SetTextColor(0.8, 0.8, 0.82)
    positionStacked(bar, self.content, pad, y, w - pad * 2, segs)
    y = y - (BAR_H + BAR_GAP) - SECTION_GAP
  else
    H.qmix:Hide()
  end

  -- Loot by item type.
  rows = {}
  for _, e in ipairs(sortedByCount(stats.byType)) do
    rows[#rows + 1] = { label = e.key, color = { 0.5, 0.7, 0.9 }, frac = e.count / total, value = tostring(e.count) }
  end
  y = self:renderBarSection(P.itype, H.itype, rows, y, w, pad)

  -- Loot by bound type — sorted high→low.
  rows = {}
  local bRows = {}
  for _, bk in ipairs(BOUND_ORDER) do
    local c = stats.byBound[bk]
    if c then bRows[#bRows + 1] = { bk = bk, c = c } end
  end
  table.sort(bRows, function(a, b) if a.c ~= b.c then return a.c > b.c end return a.bk < b.bk end)
  for _, e in ipairs(bRows) do
    rows[#rows + 1] = { label = BOUND_LABEL[e.bk] or e.bk, color = BOUND_COLOR[e.bk] or NEUTRAL,
      frac = e.c / total, value = tostring(e.c) }
  end
  y = self:renderBarSection(P.bound, H.bound, rows, y, w, pad)

  -- Loot by character — class-coloured, sorted by count desc; value shows count + vendor value.
  rows = {}
  local chRows = {}
  for _, ce in pairs(stats.byChar) do chRows[#chRows + 1] = ce end
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
  y = self:renderBarSection(P.char, H.char, rows, y, w, pad)

  -- Loot over time + vendor value over time — two per-day strips over the same day range.
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

  -- Loot by hour of day — 24 fixed buckets.
  local hourB = {}
  for h = 0, 23 do
    local c = stats.byHour[h] or 0
    hourB[#hourB + 1] = { info = string.format("%02d:00  %d", h, c), count = c, label = string.format("%02d", h) }
  end
  y = self:renderStrip(P.hour, H.hour, self.hourStrip, hourB, y, w, pad)

  -- Loot by weekday — Sun..Sat.
  rows = {}
  local wMax = 1
  for _, c in pairs(stats.byWeekday) do if c > wMax then wMax = c end end
  for d = 0, 6 do
    local c = stats.byWeekday[d]
    if c then rows[#rows + 1] = { label = WEEKDAY[d], color = { 0.45, 0.65, 0.9 }, frac = c / wMax, value = tostring(c) } end
  end
  y = self:renderBarSection(P.weekday, H.weekday, rows, y, w, pad)

  -- Mythic+ loot by keystone level (only when there's keyed loot).
  rows = {}
  local klRows = {}
  for lvl, c in pairs(stats.byKeystone) do klRows[#klRows + 1] = { lvl = lvl, c = c } end
  table.sort(klRows, function(a, b) return a.lvl > b.lvl end)
  local klMax = 1
  for _, e in ipairs(klRows) do if e.c > klMax then klMax = e.c end end
  for _, e in ipairs(klRows) do
    rows[#rows + 1] = { label = "+" .. e.lvl, color = SOURCE_COLOR.MPLUS, frac = e.c / klMax, value = tostring(e.c) }
  end
  y = self:renderBarSection(P.keystone, H.keystone, rows, y, w, pad)

  -- Attribution confidence — sorted high→low.
  rows = {}
  local cRows = {}
  for _, key in ipairs({ "CERTAIN", "INFERRED" }) do
    local c = stats.byConfidence[key]
    if c then cRows[#cRows + 1] = { key = key, c = c } end
  end
  table.sort(cRows, function(a, b) if a.c ~= b.c then return a.c > b.c end return a.key < b.key end)
  for _, e in ipairs(cRows) do
    rows[#rows + 1] = { label = CONF_LABEL[e.key], color = CONF_COLOR[e.key],
      frac = e.c / total, value = string.format("%d  %d%%", e.c, math.floor(e.c / total * 100 + 0.5)) }
  end
  y = self:renderBarSection(P.conf, H.conf, rows, y, w, pad)

  -- Ranked lists — two half-width columns:
  --   left  : Top items by value → Top zones (stacked)
  --   right : Top items by count
  local colGap = 12
  local colW = math.floor((w - pad * 2 - colGap) / 2)
  local leftX, rightX = pad, pad + colW + colGap
  local MONEY_W = 110  -- value column wide enough for "Ng Ns Nc" coin strings (no wrapping)

  -- Top items by value (left, top).
  local valRows = {}
  for i = 1, math.min(10, #stats.topItemsByValue) do
    local it = stats.topItemsByValue[i]
    if (it.value or 0) > 0 then
      local star = ((it.quality or 1) >= 4) and starMarkup() or ""
      valRows[#valRows + 1] = { name = star .. (it.itemName or ("item " .. (it.itemID or "?"))),
        nameColor = qualityColor(it.quality or 1), right = money(it.value) }
    end
  end

  -- Top items by count (right, top).
  local itemRows = {}
  for i = 1, math.min(10, #stats.topItems) do
    local it = stats.topItems[i]
    local star = ((it.quality or 1) >= 4) and starMarkup() or ""
    itemRows[#itemRows + 1] = { name = star .. (it.itemName or ("item " .. (it.itemID or "?"))),
      nameColor = qualityColor(it.quality or 1), right = tostring(it.count) }
  end

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
  y = y - math.max(leftH, hItem) - SECTION_GAP
  return y
end
