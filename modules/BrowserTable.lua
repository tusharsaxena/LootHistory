local addonName, NS = ...
NS.BrowserTable = NS.BrowserTable or {}
local BrowserTable = NS.BrowserTable
local C = NS.Constants

-- Virtualized pooled-row table over Database:Query — filter -> group -> sort -> slice -> bind
-- (see docs/TECHNICAL_DESIGN §7). Sorting lands in 3.3, grouping in 3.4.

local ROW_H = 18
local HEADER_H = 20
local EMDASH = "\226\128\148"
local ITEM_MIN = 90   -- minimum width of the flex (Item) column
local COL_GAP = 6
-- Every row shows a lock; colour + opacity encode the binding state. {r, g, b, alpha}
local BOUND_STYLE = {
  WARBOUND  = { 0.35, 0.55, 1.0, 1.0 },  -- blue, solid
  SOULBOUND = { 1.0, 1.0, 1.0, 1.0 },    -- white, solid
  UNBOUND   = { 0.6, 0.6, 0.6, 0.40 },   -- grey, faint
}

-- Apply a padlock look to a texture, tolerant of missing art: prefer the LFG lock atlas,
-- else fall back to a solid chip so the Bound column is never blank.
local LOCK_ATLAS = "UI-LFG-Lock"
local function applyLockTexture(tex)
  if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(LOCK_ATLAS) then
    tex:SetAtlas(LOCK_ATLAS)
  else
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
  end
end

-- Strip realm from "Name-Realm" for the compact Character column (full value in tooltip).
local function charName(char)
  if not char then return "" end
  return char:match("^[^-]+") or char
end

-- Column model. width 0 + flex=true means "absorb the remaining width" (the Item column).
BrowserTable.COLUMNS = {
  { key = "date", label = "Date", width = 60, align = "LEFT",
    desc = "Date the item was looted.",
    valueFn = function(r) return NS.Util.FormatDate(r.ts) end,
    sortFn = function(r) return r.ts or 0 end },
  { key = "time", label = "Time", width = 44, align = "LEFT",
    desc = "Time of day the item was looted.",
    valueFn = function(r) return NS.Util.FormatClock(r.ts) end,
    sortFn = function(r) return r.ts or 0 end },
  { key = "char", label = "Character", width = 96, align = "LEFT",
    desc = "Character who looted the item (realm in the item tooltip).",
    valueFn = function(r) return charName(r.char) end,
    sortFn = function(r) return (r.char or ""):lower() end },
  { key = "bound", label = "", width = 22, align = "CENTER", icon = true,
    desc = "Binding: blue = Warbound, white = Soulbound, dim grey = not bound.",
    valueFn = function() return "" end,   -- rendered as an icon, not text
    sortFn = function(r) return r.bound or "" end },
  { key = "ilvl", label = "iLvl", width = 40, align = "RIGHT",
    desc = "Item level (equippable gear only).",
    valueFn = function(r) return r.itemLevel and tostring(r.itemLevel) or "" end,
    sortFn = function(r) return r.itemLevel or 0 end },
  { key = "item", label = "Item", width = 0, flex = true, align = "LEFT",
    desc = "Item looted. Hover for its tooltip.",
    valueFn = function(r)
      return r.itemName or (r.itemLink and r.itemLink:match("%[(.-)%]")) or "?"
    end,
    sortFn = function(r) return (r.itemName or ""):lower() end },
  { key = "qty", label = "Qty", width = 40, align = "RIGHT",
    desc = "Quantity looted in this event.",
    valueFn = function(r) return tostring(r.quantity or 1) end,
    sortFn = function(r) return r.quantity or 1 end },
  { key = "quality", label = "Quality", width = 74, align = "LEFT",
    desc = "Item quality (Poor → Legendary).",
    valueFn = function(r) return NS.Compat.QualityLabel(r.quality) end,
    sortFn = function(r) return r.quality or 0 end },
  { key = "source", label = "Source", width = 88, align = "LEFT",
    desc = "How the item was acquired (kill, container, mail, trade, …).",
    valueFn = function(r) return C.SourceLabel[r.source] or r.source or "Other" end,
    sortFn = function(r) return C.SourceLabel[r.source] or r.source or "" end },
  { key = "from", label = "From", width = 120, align = "LEFT",
    desc = "Where it came from — mob, mail sender, trade partner, merchant, or quest.",
    valueFn = function(r) return r.sourceName or EMDASH end,
    sortFn = function(r) return (r.sourceName or ""):lower() end },
  { key = "zone", label = "Zone", width = 120, align = "LEFT",
    desc = "Zone where the item was looted (subzone in the item tooltip).",
    valueFn = function(r) return r.zone or "" end,
    sortFn = function(r) return (r.zone or ""):lower() end },
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

  -- Bound-state lock icon (Bound column); tinted + shown per record in BindRow.
  local boundIcon = row:CreateTexture(nil, "OVERLAY")
  boundIcon:SetSize(14, 14)
  applyLockTexture(boundIcon)
  boundIcon:Hide()
  row.boundIcon = boundIcon

  -- Group-header styling (used in 3.4); hidden for data rows.
  local header = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  header:SetPoint("LEFT", 4, 0)
  header:SetTextColor(1, 0.82, 0)
  header:Hide()
  row.header = header

  -- Hover → the full in-game item tooltip for this row's record.
  row:SetScript("OnEnter", function(self2)
    local e = self2.entry
    if e and e.kind == "row" and e.record.itemLink then
      GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(e.record.itemLink)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)

  self:LayoutRowCells(row)
  return row
end

-- Width available for columns (row host viewport), with a fallback before first layout.
function BrowserTable:ContentWidth()
  local w = self.rowHost and self.rowHost:GetWidth()
  if not w or w <= 0 then return 780 end
  return w
end

-- Minimum window width that shows every column without truncation: the sum of fixed column
-- widths + gaps + the Item column's minimum + scrollbar gutter + pane margins. Browser uses
-- this as both the default and the minimum window width so columns never overflow.
function BrowserTable:MinFrameWidth()
  local w = 0
  for _, col in ipairs(self.COLUMNS) do
    w = w + (col.flex and ITEM_MIN or col.width) + COL_GAP
  end
  return math.ceil(w + 24 + 12) -- scrollbar gutter + pane left/right margins
end

-- Position each cell by cumulative column widths; the flex column takes the slack.
function BrowserTable:LayoutRowCells(row)
  local total = self:ContentWidth()
  local fixed = 0
  for _, col in ipairs(self.COLUMNS) do
    if not col.flex then fixed = fixed + col.width + COL_GAP end
  end
  local flexW = math.max(ITEM_MIN, total - fixed)

  local x = 0
  for _, col in ipairs(self.COLUMNS) do
    local w = col.flex and flexW or col.width
    local fs = row.cells[col.key]
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", x, 0)
    fs:SetWidth(w)
    if col.icon and row.boundIcon then
      row.boundIcon:ClearAllPoints()
      row.boundIcon:SetPoint("CENTER", row, "LEFT", x + w / 2, 0)
    end
    x = x + w + COL_GAP
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
  -- Bottom raised 16px so the scrollbar's down-arrow clears the window resize grip.
  scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -24, 16)
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

-- Build one header button per column (text label, or a white lock for the icon column).
-- Each shows a tooltip describing the column; buttons will drive sorting in 3.3.
function BrowserTable:MakeHeaderButton(col)
  local btn = CreateFrame("Button", nil, self.headerFrame)
  btn:SetHeight(HEADER_H)
  if col.icon then
    local tex = btn:CreateTexture(nil, "OVERLAY")
    tex:SetSize(14, 14)
    tex:SetPoint("CENTER")
    applyLockTexture(tex)
    tex:SetVertexColor(1, 1, 1) -- white lock as the Bound header
    btn.tex = tex
  else
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", 0, 0)
    fs:SetJustifyH(col.align)
    fs:SetText(col.label)
    fs:SetTextColor(1, 0.82, 0)
    btn.fs = fs
  end
  btn:SetScript("OnEnter", function(self2)
    GameTooltip:SetOwner(self2, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(col.label ~= "" and col.label or "Bound", 1, 0.82, 0)
    if col.desc then GameTooltip:AddLine(col.desc, 0.9, 0.9, 0.9, true) end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return btn
end

function BrowserTable:BuildHeaderCells()
  local header = self.headerFrame
  header.buttons = header.buttons or {}
  local total = self:ContentWidth()
  local fixed = 0
  for _, col in ipairs(self.COLUMNS) do
    if not col.flex then fixed = fixed + col.width + COL_GAP end
  end
  local flexW = math.max(ITEM_MIN, total - fixed)

  local x = 0
  for _, col in ipairs(self.COLUMNS) do
    local w = col.flex and flexW or col.width
    local btn = header.buttons[col.key]
    if not btn then
      btn = self:MakeHeaderButton(col)
      header.buttons[col.key] = btn
    end
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", header, "LEFT", x, 0)
    btn:SetWidth(w)
    if btn.fs then btn.fs:SetWidth(w) end
    x = x + w + COL_GAP
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
    row.boundIcon:Hide()
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

  -- Bound lock icon (always shown): blue = warbound, white = soulbound, faint grey = unbound.
  local style = BOUND_STYLE[r.bound] or BOUND_STYLE.UNBOUND
  row.boundIcon:SetVertexColor(style[1], style[2], style[3])
  row.boundIcon:SetAlpha(style[4])
  row.boundIcon:Show()
end
