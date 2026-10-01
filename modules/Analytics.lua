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
local WHITE, BAR_H, BAR_GAP, SECTION_GAP = K.WHITE, K.BAR_H, K.BAR_GAP, K.SECTION_GAP
local DAYSTRIP_H, STRIP_LABEL_H, STRIP_AXIS_GAP = K.DAYSTRIP_H, K.STRIP_LABEL_H, K.STRIP_AXIS_GAP
local STRIP_LABEL_GAP, LABEL_X_ADJUST, LIST_ROW_H = K.STRIP_LABEL_GAP, K.LABEL_X_ADJUST, K.LIST_ROW_H
local LABELW, VALW, LABEL_MAXCHARS, LEGEND_MAXCHARS = K.LABELW, K.VALW, K.LABEL_MAXCHARS, K.LEGEND_MAXCHARS
local MIN_HEADLINE_SIZE, NEUTRAL = K.MIN_HEADLINE_SIZE, K.NEUTRAL
local SOURCE_COLOR, BOUND_LABEL, BOUND_COLOR = F.SOURCE_COLOR, F.BOUND_LABEL, F.BOUND_COLOR
local BOUND_ORDER, WEEKDAY, starMarkup = F.BOUND_ORDER, F.WEEKDAY, F.starMarkup
local money, shortChar, paletteMap = Analytics._money, Analytics._shortChar, Analytics._paletteMap
local classColor, qualityColor = Analytics._classColor, Analytics._qualityColor
local dayKeyList, shortDay, sortedByCount = Analytics._dayKeyList, Analytics._shortDay, Analytics._sortedByCount

-- Show a one-line tooltip pinned just above-and-right of the cursor (offset +5,+5), rather than
-- anchored to the (far-right) row edge. GetCursorPosition returns physical pixels, so divide by the
-- UIParent scale before placing against UIParent's bottom-left.
local function showCursorTooltip(owner, text, r, g, b)
  if not text or text == "" then return end
  GameTooltip:SetOwner(owner, "ANCHOR_NONE")
  local scale = UIParent:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / scale + 5, cy / scale + 5)
  GameTooltip:ClearLines()
  GameTooltip:AddLine(text, r or 1, g or 1, b or 1)
  GameTooltip:Show()
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
  label:SetWordWrap(false)
  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._fullLabel, 1, 0.82, 0) end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

-- A single horizontal bar split into colored segments (used for the Quality-mix composition).
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
  -- Each segment is a mouse-enabled frame (not a bare texture) so it can carry its own hover
  -- tooltip ("<category>: <value>"). The frame's texture fills it.
  bar.segs = {}
  for i = 1, 9 do
    local seg = CreateFrame("Frame", nil, bar)
    seg:EnableMouse(true)
    local tex = seg:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(seg)
    seg.tex = tex
    seg:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._info, 1, 1, 1) end)
    seg:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.segs[i] = seg
  end
  label:SetWordWrap(false)
  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._fullLabel, 1, 0.82, 0) end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return bar
end

-- segments: ordered array of { frac (0..1 of the track), color = {r,g,b}, tip = string|nil }.
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
      seg.tex:SetColorTexture(sd.color[1], sd.color[2], sd.color[3], 0.95)
      seg._info = sd.tip
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

-- A ranked-list row: name (left, may be quality-colored) + count/value (right).
local function makeListRow(parent)
  local r = CreateFrame("Frame", nil, parent)
  r:SetHeight(LIST_ROW_H)
  local name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetJustifyH("LEFT"); name:SetPoint("LEFT", 4, 0); name:SetWordWrap(false)
  r.name = name
  local count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  count:SetJustifyH("RIGHT"); count:SetPoint("RIGHT", -4, 0); count:SetWordWrap(false)
  r.count = count
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._fullName, 1, 1, 1) end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

-- A legend chip: color swatch + label.
local function makeSwatch(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(14)
  local sw = f:CreateTexture(nil, "ARTWORK"); sw:SetSize(10, 10)
  sw:SetPoint("LEFT", f, "LEFT", 0, 0)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", sw, "RIGHT", 4, 0); fs:SetTextColor(0.8, 0.8, 0.82)
  fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
  f.sw, f.fs = sw, fs
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._full, 0.9, 0.9, 0.9) end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

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
    local entry = { frame = card, num = num, bigStr = def.bigStr }
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
  -- Scope by the browser's shared filter (issue #13) so the Insights view and the History table
  -- always reflect the exact same criteria; empty filter = the whole (visible) history.
  local filter = (NS.Browser and NS.Browser.CurrentFilter and NS.Browser:CurrentFilter()) or {}
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

local function sectionHeader(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetText(text)
  fs:SetTextColor(1, 0.82, 0)
  return fs
end

-- Full-width section divider: centered gold title flanked by horizontal rule lines (the
-- "Slash Commands" separator look). Returns a frame; caller anchors its TOPLEFT on the y cursor.
local function sectionDivider(parent, text)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(26) -- taller to fit the enlarged title
  local lineL = f:CreateTexture(nil, "ARTWORK")
  lineL:SetColorTexture(1, 0.82, 0, 0.35)
  lineL:SetHeight(1.25) -- 25% thicker rule
  local lineR = f:CreateTexture(nil, "ARTWORK")
  lineR:SetColorTexture(1, 0.82, 0, 0.35)
  lineR:SetHeight(1.25)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  local file, size, flags = fs:GetFont()
  fs:SetFont(file, size * 1.5, flags) -- 50% larger title
  fs:SetPoint("CENTER", f, "CENTER", 0, 0)
  fs:SetTextColor(1, 0.82, 0)
  fs:SetText(text)
  f.fs = fs
  -- lines fill the space either side of the centered label (8px gap)
  lineL:SetPoint("LEFT", f, "LEFT", 0, 0)
  lineL:SetPoint("RIGHT", fs, "LEFT", -8, 0)
  lineR:SetPoint("LEFT", fs, "RIGHT", 8, 0)
  lineR:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  return f
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

-- Render a horizontal-bar section: header + one bar per row. rows: ordered array of
--   { label, labelColor = {r,g,b}|nil, color = {r,g,b}, frac (0..1), value = string }.
-- Returns the new y cursor (skips the section entirely when rows is empty).
-- rows: ordered { label, labelColor = {r,g,b}|nil, color = {r,g,b}, frac (0..1), value = string }.
-- The label text is colored to match its bar (row.color) unless the caller gives an explicit
-- labelColor (e.g. quality color) — this makes single bars self-legending. legendPool (optional)
-- draws a category legend below the bars (each row's label + color).
function Analytics:renderBarSection(pool, header, rows, y, w, pad, legendPool)
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
    local bar = NS.Pool.Acquire(pool, function() return makeBar(self.content) end)
    bar.fill:SetColorTexture(row.color[1], row.color[2], row.color[3], 0.95)
    bar._fullLabel = Analytics._tipText(row.label, row.value)
    bar.label:SetText((Analytics._truncate(row.label, LABEL_MAXCHARS)))
    local lc = row.labelColor or row.color -- default the label color to its bar color
    bar.label:SetTextColor(lc[1] or 0.9, lc[2] or 0.9, lc[3] or 0.9)
    bar.value:SetText(row.value)
    bar.value:SetTextColor(0.8, 0.8, 0.82)
    positionBar(bar, self.content, pad, y, innerW, row.frac)
    y = y - (BAR_H + BAR_GAP)
  end
  if legendPool then
    local leg = {}
    for _, row in ipairs(rows) do leg[#leg + 1] = { label = row.label, color = row.color, value = row.value } end
    return self:renderLegend(legendPool, leg, y, w, pad)
  end
  return y - SECTION_GAP
end

-- Render a section where each row is a horizontal STACKED bar (one per currency). rows: ordered
--   { label, value (string), segments = { {frac (0..1 of the track), color = {r,g,b}}, ... } }.
-- `frac`s are already max-relative (the caller divides by the largest currency total), so the
-- longest bar fills the track and each segment is that source's share of the track. Empty → skipped.
function Analytics:renderStackedBarSection(pool, header, rows, y, w, pad)
  if #rows == 0 then header:Hide(); return y end
  header:ClearAllPoints(); header:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y); header:Show()
  y = y - 18
  local innerW = w - pad * 2
  for _, row in ipairs(rows) do
    local bar = NS.Pool.Acquire(pool, function() return makeStackedBar(self.content) end)
    bar._fullLabel = Analytics._tipText(row.label, row.value)
    bar.label:SetText((Analytics._truncate(row.label, LABEL_MAXCHARS)))
    local lc = row.labelColor
    bar.label:SetTextColor(lc and lc[1] or 0.9, lc and lc[2] or 0.9, lc and lc[3] or 0.9)
    bar.value:SetText(row.value); bar.value:SetTextColor(0.8, 0.8, 0.82)
    positionStacked(bar, self.content, pad, y, innerW, row.segments)
    y = y - (BAR_H + BAR_GAP)
  end
  return y - SECTION_GAP
end

-- Render a wrapped legend of color-swatch + label chips.
-- rows = { { label, color = {r,g,b}, value = string|nil } }.
-- Chips start at the track's left edge (aligned under the bars, not the text labels). Long labels
-- are truncated with an ellipsis; hovering a chip shows the full label.
function Analytics:renderLegend(pool, rows, y, w, pad)
  local x0 = pad + LABELW + 6 -- align the legend with where the bars/track begin
  local x, rowY, chipW = x0, y, 120
  for _, row in ipairs(rows) do
    if x + chipW > w - pad then x = x0; rowY = rowY - 16 end
    local chip = NS.Pool.Acquire(pool, function() return makeSwatch(self.content) end)
    chip.sw:SetColorTexture(row.color[1], row.color[2], row.color[3], 0.95)
    -- `value` is only present for legends mirroring a bar section (a category key built from
    -- catOrder has no single value) — _tipText then falls back to the label alone.
    chip._full = Analytics._tipText(row.label, row.value)
    chip.fs:SetWidth(chipW - 16)
    chip.fs:SetText((Analytics._truncate(row.label, LEGEND_MAXCHARS)))
    chip:ClearAllPoints(); chip:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, rowY)
    chip:SetWidth(chipW); chip:Show()
    x = x + chipW
  end
  return rowY - 16 - SECTION_GAP
end

-- Render a "… by Character" companion: a per-character stacked bar (segments = a chart's categories,
-- colored by colorFn, hover-tipped via labelFn) plus a color-swatch legend naming each category.
-- catOrder is the global category order; colorFn(k)/labelFn(k) map a category key to color/label.
function Analytics:renderCharCompanion(poolKey, legendKey, header, matrix, catOrder, colorFn, labelFn, valueFmt, y, w, pad)
  local rows = Analytics._buildCharStackRows(matrix or {}, self.stats.byChar, catOrder, colorFn, valueFmt, labelFn)
  y = self:renderStackedBarSection(self.pool[poolKey], header, rows, y, w, pad)
  if #rows > 0 then
    local legend = {}
    for _, k in ipairs(catOrder) do legend[#legend + 1] = { label = labelFn(k), color = colorFn(k) } end
    y = self:renderLegend(self.pool[legendKey], legend, y, w, pad)
  end
  return y
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
    local f = NS.Pool.Acquire(pool, function() return makeStripBar(strip) end)
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
      -- Center x on the bar; the top offset = line gap (below bar) + label gap (below line).
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
    local r = NS.Pool.Acquire(pool, function() return makeListRow(panel) end)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -20 - (i - 1) * LIST_ROW_H)
    r:SetWidth(colW - 8)
    r.name:SetWidth(math.max(1, colW - 8 - rightW - 6)); r.name:SetText(row.name)
    r._fullName = Analytics._tipText(row.name, row.right)
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
  self.currencyStrip:Hide()
  self.lootDivider:Hide(); self.currencyDivider:Hide()
end

-- Bind + position every chart off self.stats for the given width; return the final y cursor.
function Analytics:LayoutCharts(y, w, pad)
  local stats, P = self.stats, self.pool
  for _, name in ipairs({ "source", "vsource", "quality", "itype", "bound", "char",
                          "day", "vday", "hour", "weekday", "zone", "item", "itemval",
                          "curcollected", "curcollectedleg", "cursrc", "curlegend", "curchar", "curcharlegend", "curday",
                          "sourceleg", "vsourceleg", "qualityleg", "itypeleg", "boundleg",
                          "chsource", "chsourceleg", "chvsource", "chvsourceleg", "chquality", "chqualityleg",
                          "chtype", "chtypeleg", "chbound", "chboundleg" }) do
    NS.Pool.ReleaseAll(P[name])
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

  self.lootDivider:ClearAllPoints()
  self.lootDivider:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
  self.lootDivider:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -pad, y)
  self.lootDivider:Show()
  y = y - 30

  -- Loot by character (first chart in the LOOT section) — class-colored, sorted by count desc.
  -- byChar registers currency-only characters with count 0 (for class colors elsewhere); skip them.
  rows = {}
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
  y = self:renderBarSection(P.char, H.char, rows, y, w, pad)

  -- Loot by source — length = share of all records.
  rows = {}
  for _, e in ipairs(sortedByCount(stats.bySource)) do
    rows[#rows + 1] = {
      label = NS.Constants.SourceLabel[e.key] or e.key, color = SOURCE_COLOR[e.key] or NEUTRAL,
      frac = e.count / total, value = string.format("%d  %d%%", e.count, math.floor(e.count / total * 100 + 0.5)),
    }
  end
  y = self:renderBarSection(P.source, H.source, rows, y, w, pad, P.sourceleg)

  -- Loot by Character × Source — companion. Segment order matches the parent's Y axis (count desc).
  local srcOrder = {}
  for _, e in ipairs(sortedByCount(stats.bySource)) do srcOrder[#srcOrder + 1] = e.key end
  local function srcColor(k) return SOURCE_COLOR[k] or NEUTRAL end
  local function srcLabel(k) return NS.Constants.SourceLabel[k] or k end
  y = self:renderCharCompanion("chsource", "chsourceleg", H.charBySource, stats.charBySource,
    srcOrder, srcColor, srcLabel, function(t) return tostring(t) end, y, w, pad)

  -- Vendor value by source — length relative to the biggest bucket, ordered by value desc.
  rows = {}
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

  -- Value by Character × Source — companion. Segment order matches the parent's Y axis (value desc).
  y = self:renderCharCompanion("chvsource", "chvsourceleg", H.charValueSource, stats.charValueBySource,
    vsrcOrder, srcColor, srcLabel, function(t) return money(t) end, y, w, pad)

  -- Quality distribution — bars in quality order, length relative to the biggest bucket.
  rows = {}
  local qRows, qMax = {}, 1
  for q, c in pairs(stats.byQuality) do qRows[#qRows + 1] = { q = q, c = c }; if c > qMax then qMax = c end end
  table.sort(qRows, function(a, b) return a.q < b.q end)
  for _, e in ipairs(qRows) do
    local col = qualityColor(e.q)
    rows[#rows + 1] = { label = NS.Item.QualityLabel(e.q), labelColor = col, color = col,
      frac = e.c / qMax, value = tostring(e.c) }
  end
  y = self:renderBarSection(P.quality, H.quality, rows, y, w, pad, P.qualityleg)

  -- Loot by Character × Quality — companion, segments colored by item quality (parent order).
  local qOrder = {}
  for q = 0, 8 do if stats.byQuality[q] then qOrder[#qOrder + 1] = q end end
  y = self:renderCharCompanion("chquality", "chqualityleg", H.charQuality, stats.charByQuality,
    qOrder, function(q) return qualityColor(q) end, function(q) return NS.Item.QualityLabel(q) end,
    function(t) return tostring(t) end, y, w, pad)

  -- Loot by item type — bars colored per type from the standard palette (rank = sort order); the
  -- Character × Item Type companion reuses the same map so a type keeps its color across both.
  local tyKeys = {}
  for _, e in ipairs(sortedByCount(stats.byType)) do tyKeys[#tyKeys + 1] = e.key end
  local typeColor = paletteMap(tyKeys)
  rows = {}
  for _, e in ipairs(sortedByCount(stats.byType)) do
    rows[#rows + 1] = { label = e.key, color = typeColor[e.key] or NEUTRAL,
      frac = e.count / total, value = tostring(e.count) }
  end
  y = self:renderBarSection(P.itype, H.itype, rows, y, w, pad, P.itypeleg)

  y = self:renderCharCompanion("chtype", "chtypeleg", H.charType, stats.charByType,
    tyKeys, function(k) return typeColor[k] or NEUTRAL end, function(k) return k end,
    function(t) return tostring(t) end, y, w, pad)

  -- Loot by bound type — sorted count desc; the companion reuses this exact order for its segments.
  rows = {}
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

  -- Loot by Character × Bound Type — companion. Segment order matches the parent's Y axis (count desc).
  y = self:renderCharCompanion("chbound", "chboundleg", H.charBound, stats.charByBound,
    boundOrder, function(k) return BOUND_COLOR[k] or NEUTRAL end,
    function(k) return BOUND_LABEL[k] or k end, function(t) return tostring(t) end, y, w, pad)

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

  -- Loot by weekday — Sun..Sat, each day a unique palette color (Sun=rank 1 … Sat=rank 7).
  rows = {}
  local wMax = 1
  for _, c in pairs(stats.byWeekday) do if c > wMax then wMax = c end end
  for d = 0, 6 do
    local c = stats.byWeekday[d]
    if c then rows[#rows + 1] = { label = WEEKDAY[d], color = Analytics.paletteColor(d + 1),
      frac = c / wMax, value = tostring(c) } end
  end
  y = self:renderBarSection(P.weekday, H.weekday, rows, y, w, pad)

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
  -- (fall through to Currency)

  -- ── Currency ──────────────────────────────────────────────────────────────────
  local ct = stats.currencyTotals or { distinct = 0, events = 0 }
  if ct.events and ct.events > 0 then
    self.currencyDivider:ClearAllPoints()
    self.currencyDivider:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
    self.currencyDivider:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -pad, y)
    self.currencyDivider:Show()
    y = y - 30

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

    -- Currency by Type × Source: one stacked bar per currency, segments colored by source.
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

    local legendRows = {}
    for _, le in ipairs(sortedByCount(stats.currencyBySource or {})) do
      legendRows[#legendRows + 1] = { label = NS.Constants.SourceLabel[le.key] or le.key,
        color = SOURCE_COLOR[le.key] or NEUTRAL }
    end
    y = self:renderLegend(P.curlegend, legendRows, y, w, pad)

    -- Currency by Character × Type — one stacked bar per character, segmented by currency (each a
    -- distinct palette color, shared with Currency Collected via curColor). Currencies ordered by
    -- global qty so a given currency keeps a consistent segment position across character rows.
    local ccRows = Analytics._buildCharStackRows(stats.currencyCharMatrix, stats.byChar, curKeys,
      function(cname) return curColor[cname] or NEUTRAL end, function(t) return tostring(t) end,
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
    y = self:renderStrip(P.curday, H.currencyTime, self.currencyStrip, curDayB, y, w, pad)
  else
    H.currencyCollected:Hide(); H.currencySrc:Hide(); H.currencyChar:Hide(); H.currencyTime:Hide()
    self.currencyStrip:Hide()
    self.currencyDivider:Hide()
  end

  return y
end
