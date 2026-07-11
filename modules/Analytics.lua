local addonName, NS = ...
NS.Analytics = NS.Analytics or {}
local Analytics = NS.Analytics

-- Insights tab: stat cards + source/quality/time breakdowns + top zones/items, scoped by a
-- date-range selector (see docs/UX_DESIGN §4, docs/TECHNICAL_DESIGN §8). Everything is driven
-- off a single Database:Stats(filter) pass; widgets are pooled and re-laid-out on resize.

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Date-range options → a `from` timestamp for Database:Stats. "Today" is the calendar day;
-- 7d/30d are rolling windows; "all" is unbounded.
local RANGES = {
  { value = "today", label = "Today" },
  { value = "7d",    label = "7 days" },
  { value = "30d",   label = "30 days" },
  { value = "all",   label = "All" },
}
local function rangeFrom(range)
  local now = time()
  if range == "today" then
    local t = date("*t", now)
    return now - (t.hour * 3600 + t.min * 60 + t.sec)
  elseif range == "7d" then
    return now - 7 * 86400
  elseif range == "30d" then
    return now - 30 * 86400
  end
  return nil -- all
end

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
  local from = rangeFrom(self.range)
  local stats = NS.Database:Stats(from and { from = from } or {})
  self.stats = stats
  self:UpdateCards(stats)
  self:UpdateCharts(stats)
  self:Layout()
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

-- ── Charts (Task 4.2) ──────────────────────────────────────────────────────────────
-- Stubs until 4.2 fills them in.
function Analytics:BuildCharts(_content) end
function Analytics:UpdateCharts(_stats) end
function Analytics:LayoutCharts(y, _w, _pad) return y end
