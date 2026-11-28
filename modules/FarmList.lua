local _, NS = ...
NS.FarmList = NS.FarmList or {}
local FL = NS.FarmList

-- modules/FarmList.lua — the farm windows' one list widget (#39, farm spec §3.1, §7.2-§7.5). A
-- virtualized, sortable table in the BrowserTable shape (modules/BrowserTable.lua's Bind): a
-- FauxScrollFrame drives the offset, pooled rows (NS.Pool) sit in an overlay over its viewport, and
-- a bind touches only the visible slice, so a 2000-line session log costs one screen of rows.
--
--   FL.New(parent, spec)     a list filling `parent`; answers the list object
--   list:SetData(entries)    the rows (a plain array, kept by reference), sorted, then bound
--   list:SortBy(key, asc)    sort on a column (the header click's path); spec.onSort is told
--   list:Bind()              the visible slice onto pooled rows
--   list:Relayout()          the cheap half of a resize: column widths and the visible-row count
--   list:Visible()           the entries bound right now (a test seam and the hover's read)
--
-- `spec` = {
--   columns  = { { key, label, width (nil: the one flexible column), align ("LEFT"|"RIGHT"),
--                  text = fn(entry) -> string, color = fn(entry) -> r, g, b | nil,
--                  sort = fn(entry) -> comparable (default: text), defaultAsc = bool }, ... },
--   sortKey, sortAsc     the opening sort; sortable = false fixes the order the data came in
--   rowH                 row height (default FL.ROW_H)
--   empty                the line shown with no rows
--   onClick(entry, button, row), onDoubleClick(entry, row), onEnter(entry, row), onSort(key, asc)
-- }
--
-- Binds nothing at load: NS.Pool, NS.Skin and the FauxScrollFrame globals are read at call time.

FL.ROW_H, FL.HEADER_H, FL.BAR_W = 18, 20, 24
local CELL_PAD = 4

local List = {}
List.__index = List

local function header(self)
  local h = CreateFrame("Frame", nil, self.parent)
  h:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 0, 0)
  h:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", -FL.BAR_W, 0)
  h:SetHeight(FL.HEADER_H)
  if NS.Skin and NS.Skin.SortHeaderBar then NS.Skin.SortHeaderBar(h) end
  self.header, self.headCells = h, {}
  for i, col in ipairs(self.spec.columns) do
    local b = CreateFrame("Button", nil, h)
    b:SetHeight(FL.HEADER_H)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints(b)
    fs:SetJustifyH(col.align or "LEFT")
    NS.Skin.Font(fs)
    b.fs, b.col = fs, col
    b:SetScript("OnClick", function() self:HeaderClick(col.key) end)
    self.headCells[i] = b
  end
end

local function scrollFrame(self)
  local scroll = CreateFrame("ScrollFrame", nil, self.parent, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, -2)
  scroll:SetPoint("BOTTOMRIGHT", self.parent, "BOTTOMRIGHT", -FL.BAR_W, 0)
  scroll:SetScript("OnVerticalScroll", function(f, offset)
    FauxScrollFrame_OnVerticalScroll(f, offset, self.rowH, function() self:Bind() end)
  end)
  local bar = rawget(scroll, "ScrollBar")
  if bar and NS.Skin and NS.Skin.ScrollBar then NS.Skin.ScrollBar(bar) end
  self.scroll = scroll
  local host = CreateFrame("Frame", nil, self.parent)
  host:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  host:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
  self.rowHost = host
  local empty = self.parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  empty:SetPoint("CENTER", scroll, "CENTER", 0, 0)
  NS.Skin.Text(empty, "disabled")
  empty:Hide()
  self.emptyText = empty
end

--- A new list over `parent` (see the header for `spec`).
function FL.New(parent, spec)
  local self = setmetatable({ parent = parent, spec = spec, rowH = spec.rowH or FL.ROW_H,
    data = {}, visible = {}, pool = NS.Pool.New(), widths = {} }, List)
  self.sortKey, self.sortAsc = spec.sortKey, spec.sortAsc and true or false
  header(self)
  scrollFrame(self)
  self:Relayout()
  return self
end

local function column(self, key)
  for _, col in ipairs(self.spec.columns) do
    if col.key == key then return col end
  end
  return nil
end

--- The header's labels, with the sort column's arrow (the catalog's sort-down / sort-up).
function List:PaintHeader()
  for _, b in ipairs(self.headCells) do
    local label = b.col.label or ""
    if self.spec.sortable ~= false and b.col.key == self.sortKey then
      local arrow = self.sortAsc and "sort-up" or "sort-down"
      label = label .. " " .. NS.IconMarkup(arrow, "Interface\\Buttons\\UI-SortArrow", 10)
    end
    b.fs:SetText(label)
  end
end

--- The column widths: every fixed width as given, the flexible column the rest (never under 40).
function List:Relayout()
  local total = (self.parent.GetWidth and self.parent:GetWidth() or 0) - FL.BAR_W
  local fixed, flex = 0, nil
  for _, col in ipairs(self.spec.columns) do
    if col.width then fixed = fixed + col.width else flex = flex or col.key end
  end
  local x = 0
  for i, col in ipairs(self.spec.columns) do
    local w = col.width or math.max(40, total - fixed)
    self.widths[i] = w
    local b = self.headCells[i]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", self.header, "TOPLEFT", x + CELL_PAD, 0)
    b:SetWidth(w - 2 * CELL_PAD)
    x = x + w
  end
  self.flexKey = flex
  self:PaintHeader()
end

local function sortValue(col, e)
  if col.sort then return col.sort(e) end
  return col.text and col.text(e) or ""
end

-- Compare two decorated entries: the column's value, then the original index, so equal values keep
-- the order the data came in (a stable sort over table.sort).
local function before(asc)
  return function(a, b)
    if a.v ~= b.v then
      if type(a.v) ~= type(b.v) then return tostring(a.v) < tostring(b.v) end
      if asc then return a.v < b.v end
      return a.v > b.v
    end
    return a.i < b.i
  end
end

--- Sort the data on the current sort column (no-op for a fixed-order list or an unknown column).
function List:Sort()
  local col = self.sortKey and column(self, self.sortKey)
  if self.spec.sortable == false or not col then return end
  local dec = {}
  for i, e in ipairs(self.data) do dec[i] = { e = e, v = sortValue(col, e), i = i } end
  table.sort(dec, before(self.sortAsc))
  for i, d in ipairs(dec) do self.data[i] = d.e end
end

--- Replace the rows: sorted, then the visible slice bound.
function List:SetData(entries)
  self.data = entries or {}
  self:Sort()
  self:Bind()
end

--- Sort on `key` (asc), repaint, and tell spec.onSort (a host that saves the sort with its view).
function List:SortBy(key, asc)
  if not column(self, key) then return end
  self.sortKey, self.sortAsc = key, asc and true or false
  self:Sort()
  self:PaintHeader()
  self:Bind()
  if self.spec.onSort then self.spec.onSort(self.sortKey, self.sortAsc) end
end

--- A header click: the same column flips the direction, another starts at its default.
function List:HeaderClick(key)
  if self.spec.sortable == false then return end
  local col = column(self, key)
  if not col then return end
  if key == self.sortKey then return self:SortBy(key, not self.sortAsc) end
  self:SortBy(key, col.defaultAsc == true)
end

local function rowScripts(self, row)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", function(r, button)
    if r.entry and self.spec.onClick then self.spec.onClick(r.entry, button, r) end
  end)
  row:SetScript("OnDoubleClick", function(r)
    if r.entry and self.spec.onDoubleClick then self.spec.onDoubleClick(r.entry, r) end
  end)
  row:SetScript("OnEnter", function(r)
    if r.entry and self.spec.onEnter then self.spec.onEnter(r.entry, r) end
  end)
  row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function buildRow(self)
  local row = CreateFrame("Button", nil, self.rowHost)
  row:SetPoint("LEFT", self.rowHost, "LEFT", 0, 0)
  row:SetPoint("RIGHT", self.rowHost, "RIGHT", 0, 0)
  row.cells = {}
  for i, col in ipairs(self.spec.columns) do
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH(col.align or "LEFT")
    fs:SetWordWrap(false)
    NS.Skin.Font(fs)
    row.cells[i] = fs
  end
  rowScripts(self, row)
  return row
end

local function bindCells(self, row, entry)
  local x = 0
  for i, col in ipairs(self.spec.columns) do
    local fs, w = row.cells[i], self.widths[i]
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", x + CELL_PAD, 0)
    fs:SetWidth(w - 2 * CELL_PAD)
    fs:SetText(col.text and col.text(entry) or "")
    local r, g, b = nil, nil, nil
    if col.color then r, g, b = col.color(entry) end
    if r then fs:SetTextColor(r, g, b) else NS.Skin.Text(fs, "body") end
    x = x + w
  end
end

--- How many rows the viewport shows (twenty while it has no measured height, as BrowserTable).
function List:NumVisible()
  local h = self.scroll:GetHeight()
  if not h or h <= 0 then h = self.rowH * 20 end
  return math.max(1, math.floor(h / self.rowH))
end

--- Bind the visible slice of the data onto pooled rows.
function List:Bind()
  local data, n = self.data, self:NumVisible()
  FauxScrollFrame_Update(self.scroll, #data, n, self.rowH)
  local offset = FauxScrollFrame_GetOffset(self.scroll) or 0
  NS.Pool.ReleaseAll(self.pool, function(r) r.entry = nil end)
  for i = #self.visible, 1, -1 do self.visible[i] = nil end
  self.emptyText:SetShown(#data == 0)
  if #data == 0 then
    self.emptyText:SetText(self.spec.empty or "")
    return
  end
  for i = 1, n do
    local entry = data[offset + i]
    if not entry then break end
    local row = NS.Pool.Acquire(self.pool, function() return buildRow(self) end)
    row:SetHeight(self.rowH)
    row:SetPoint("TOP", self.rowHost, "TOP", 0, -(i - 1) * self.rowH)
    row.entry = entry
    bindCells(self, row, entry)
    self.visible[i] = entry
  end
end

--- The entries bound right now, in screen order.
function List:Visible() return self.visible end
