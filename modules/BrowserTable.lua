local addonName, NS = ...
NS.BrowserTable = NS.BrowserTable or {}
local BrowserTable = NS.BrowserTable
local C = NS.Constants

-- Virtualized pooled-row table over Database:Query — filter -> group -> sort -> slice -> bind
-- (see docs/TECHNICAL_DESIGN §7). Sorting lands in 3.3, grouping in 3.4.

local ROW_H = 18
local HEADER_H = 20
local EMDASH = "\226\128\148"

-- Strip realm from "Name-Realm" for the compact Character column (full value in tooltip).
local function charName(char)
  if not char then return "" end
  return char:match("^[^-]+") or char
end

-- Column model. width 0 + flex=true means "absorb the remaining width" (the Item column).
BrowserTable.COLUMNS = {
  { key = "time", label = "Time", width = 68, align = "LEFT",
    valueFn = function(r) return NS.Util.FormatTime(r.ts) end,
    sortFn = function(r) return r.ts or 0 end },
  { key = "item", label = "Item", width = 0, flex = true, align = "LEFT",
    valueFn = function(r)
      return r.itemName or (r.itemLink and r.itemLink:match("%[(.-)%]")) or "?"
    end,
    sortFn = function(r) return (r.itemName or ""):lower() end },
  { key = "qty", label = "Qty", width = 40, align = "RIGHT",
    valueFn = function(r) return tostring(r.quantity or 1) end,
    sortFn = function(r) return r.quantity or 1 end },
  { key = "quality", label = "Quality", width = 74, align = "LEFT",
    valueFn = function(r) return NS.Compat.QualityLabel(r.quality) end,
    sortFn = function(r) return r.quality or 0 end },
  { key = "source", label = "Source", width = 88, align = "LEFT",
    valueFn = function(r) return C.SourceLabel[r.source] or r.source or "Other" end,
    sortFn = function(r) return C.SourceLabel[r.source] or r.source or "" end },
  { key = "from", label = "From", width = 120, align = "LEFT",
    valueFn = function(r) return r.sourceName or EMDASH end,
    sortFn = function(r) return (r.sourceName or ""):lower() end },
  { key = "zone", label = "Zone", width = 120, align = "LEFT",
    valueFn = function(r) return r.zone or "" end,
    sortFn = function(r) return (r.zone or ""):lower() end },
  { key = "char", label = "Character", width = 96, align = "LEFT",
    valueFn = function(r) return charName(r.char) end,
    sortFn = function(r) return (r.char or ""):lower() end },
}

local COLUMN_BY_KEY = {}
for _, col in ipairs(BrowserTable.COLUMNS) do COLUMN_BY_KEY[col.key] = col end

-- Pure cell text for a column key + record (unit-tested; the UI binds via the same path).
function BrowserTable:CellText(key, record)
  local col = COLUMN_BY_KEY[key]
  if not col then return "" end
  return col.valueFn(record)
end

-- ── Pipeline ───────────────────────────────────────────────────────────────────
BrowserTable.filter = {}

-- Flat display list of { kind="row", record=r }. Grouping (3.4) inserts header entries.
function BrowserTable:BuildDisplayList()
  local records = NS.Database:Query(self.filter)
  local list = {}
  for _, r in ipairs(records) do
    list[#list + 1] = { kind = "row", record = r }
  end
  return list
end

function BrowserTable:SetFilter(filter)
  self.filter = filter or {}
  self:Refresh()
end

-- ── Pooled rows ─────────────────────────────────────────────────────────────────

local function qualityColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

function BrowserTable:AcquireRow()
  local pool = self.rowPool
  local row = table.remove(pool.free)
  if row then
    row:Show()
    return row
  end

  row = CreateFrame("Button", nil, self.rowHost)
  row:SetHeight(ROW_H)
  row:SetPoint("LEFT", self.rowHost, "LEFT", 0, 0)
  row:SetPoint("RIGHT", self.rowHost, "RIGHT", 0, 0)

  local stripe = row:CreateTexture(nil, "BACKGROUND")
  stripe:SetAllPoints()
  stripe:SetColorTexture(1, 1, 1, 0.03)
  row.stripe = stripe

  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.82, 0, 0.10)

  -- One FontString per data column, laid out left→right with the Item column flexing.
  row.cells = {}
  for _, col in ipairs(self.COLUMNS) do
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH(col.align)
    fs:SetHeight(ROW_H)
    fs:SetWordWrap(false)
    row.cells[col.key] = fs
  end

  -- Group-header styling (used in 3.4); hidden for data rows.
  local header = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  header:SetPoint("LEFT", 4, 0)
  header:SetTextColor(1, 0.82, 0)
  header:Hide()
  row.header = header

  self:LayoutRowCells(row)
  return row
end

-- Width available for columns (row host viewport), with a fallback before first layout.
function BrowserTable:ContentWidth()
  local w = self.rowHost and self.rowHost:GetWidth()
  if not w or w <= 0 then return 780 end
  return w
end

-- Position each cell by cumulative column widths; the flex column takes the slack.
function BrowserTable:LayoutRowCells(row)
  local total = self:ContentWidth()
  local fixed = 0
  for _, col in ipairs(self.COLUMNS) do
    if not col.flex then fixed = fixed + col.width + 6 end
  end
  local flexW = math.max(60, total - fixed)

  local x = 0
  for _, col in ipairs(self.COLUMNS) do
    local w = col.flex and flexW or col.width
    local fs = row.cells[col.key]
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", x, 0)
    fs:SetWidth(w)
    x = x + w + 6
  end
end

function BrowserTable:ReleaseAllRows()
  local pool = self.rowPool
  for _, row in ipairs(pool.active) do
    row:Hide()
    pool.free[#pool.free + 1] = row
  end
  wipe(pool.active)
end

-- ── Attach + render ──────────────────────────────────────────────────────────────

function BrowserTable:Attach(pane)
  if self.frame then return end
  self.pane = pane

  -- Header row (right inset matches the row host so columns line up with the data cells).
  local header = CreateFrame("Frame", nil, pane)
  header:SetPoint("TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", -24, 0)
  header:SetHeight(HEADER_H)
  self.headerFrame = header

  -- FauxScrollFrame drives the scrollbar + offset. Pooled rows live in a sibling overlay
  -- (rowHost) aligned with the scroll viewport, so the ScrollFrame never clips them.
  local scroll = CreateFrame("ScrollFrame", "LootHistoryTableScroll", pane, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -24, 0)
  scroll:SetScript("OnVerticalScroll", function(self2, offset)
    FauxScrollFrame_OnVerticalScroll(self2, offset, ROW_H, function() BrowserTable:Bind() end)
  end)
  scroll:SetScript("OnSizeChanged", function() BrowserTable:Bind() end)
  self.scroll = scroll

  local host = CreateFrame("Frame", nil, pane)
  host:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  host:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
  self.rowHost = host

  self.rowPool = { active = {}, free = {} }

  -- Empty-state text.
  local empty = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
  empty:SetPoint("CENTER", scroll, "CENTER", 0, 0)
  empty:Hide()
  self.emptyText = empty

  self:BuildHeaderCells()
  self.frame = pane
  self:Refresh()
end

function BrowserTable:BuildHeaderCells()
  local header = self.headerFrame
  header.cells = header.cells or {}
  local total = self:ContentWidth()
  local fixed = 0
  for _, col in ipairs(self.COLUMNS) do
    if not col.flex then fixed = fixed + col.width + 6 end
  end
  local flexW = math.max(60, total - fixed)

  local x = 0
  for _, col in ipairs(self.COLUMNS) do
    local w = col.flex and flexW or col.width
    local fs = header.cells[col.key]
    if not fs then
      fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fs:SetJustifyH(col.align)
      fs:SetText(col.label)
      fs:SetTextColor(1, 0.82, 0)
      header.cells[col.key] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", header, "LEFT", x, 0)
    fs:SetWidth(w)
    x = x + w + 6
  end
end

-- Recompute the display list and repaint. Safe to call before Attach (no-op).
function BrowserTable:Refresh()
  if not self.frame then return end
  self.displayList = self:BuildDisplayList()
  self:Bind()
end

-- Bind the visible slice of the display list onto pooled rows.
function BrowserTable:Bind()
  if not self.frame then return end
  self:BuildHeaderCells()   -- keep header columns aligned with rows across resizes
  local list = self.displayList or {}
  local scroll = self.scroll
  local viewH = scroll:GetHeight()
  if not viewH or viewH <= 0 then viewH = ROW_H * 20 end
  local numVisible = math.max(1, math.floor(viewH / ROW_H))

  FauxScrollFrame_Update(scroll, #list, numVisible, ROW_H)
  local offset = FauxScrollFrame_GetOffset(scroll)

  self:ReleaseAllRows()
  self.emptyText:SetShown(#list == 0)
  if #list == 0 then
    self.emptyText:SetText(next(self.filter or {}) and "No records match your filters."
      or "No loot recorded yet. Go kill something.")
    return
  end

  local pool = self.rowPool
  for i = 1, numVisible do
    local entry = list[offset + i]
    if entry then
      local row = self:AcquireRow()
      row:SetPoint("TOP", self.rowHost, "TOP", 0, -(i - 1) * ROW_H)
      self:LayoutRowCells(row)
      self:BindRow(row, entry, offset + i)
      pool.active[#pool.active + 1] = row
    end
  end
end

function BrowserTable:BindRow(row, entry, absIndex)
  row.entry = entry
  row.stripe:SetShown(absIndex % 2 == 0)

  if entry.kind == "header" then
    for _, col in ipairs(self.COLUMNS) do row.cells[col.key]:SetText("") end
    row.header:Show()
    row.header:SetText(entry.label or "")
    return
  end

  row.header:Hide()
  local r = entry.record
  for _, col in ipairs(self.COLUMNS) do
    local fs = row.cells[col.key]
    fs:SetText(col.valueFn(r))
    if col.key == "item" or col.key == "quality" then
      fs:SetTextColor(qualityColor(r.quality))
    else
      fs:SetTextColor(0.9, 0.9, 0.9)
    end
  end
end
