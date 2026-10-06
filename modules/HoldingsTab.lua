local _, NS = ...
NS.HoldingsTab = NS.HoldingsTab or {}
local HT = NS.HoldingsTab

-- The Holdings tab (timeline-ledger spec §8.2): one line per thing with its total; expanding a thing
-- shows each holder with the container split and how stale the oldest contributing scan is.
-- BuildModel is pure and carries all the logic; the view is a pooled list of fixed-height rows.
--
-- It reads the browser's shared filter like the other tabs, but only the fields NS.Holdings:Search
-- understands (text, quality, itemType, itemSubType, char). Date / Source / Bound / Zone describe a
-- loot EVENT, not something held, so they are ignored here; graying them per tab is spec §8.0 and
-- lands with the Timeline tab (docs/browser.md).

local ORDER = { "bags", "equipped", "bank", "mail", "auctions", "tabs" }
local LABEL = { bags = "Bags", equipped = "Equipped", bank = "Bank", mail = "Mail", auctions = "AH", tabs = "Warband" }
local ROW_H, INDENT, HEADER_H = 18, 16, 20
local PAD, GAP, NAME_MIN, HOLDER_MIN = 4, 8, 160, 120
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0
local DAY = 86400

-- Column model (owner feedback, P4): Name flexes, the rest are History's widths for the same
-- columns (modules/BrowserTable.lua) so the two tables share one rhythm. `drop` orders the optional
-- columns for a narrow pane: the highest goes first, so they hide right to left and Name, Total and
-- Value (no `drop`) always stay.
HT.COLUMNS = {
  { key = "name", label = "Name", flex = true, align = "LEFT",
    desc = "Item, currency or gold. Hover for its tooltip; click to list who holds it." },
  { key = "ilvl", label = "iLvl", width = 34, align = "RIGHT", drop = 1,
    desc = "Item level (equippable gear only)." },
  { key = "quality", label = "Quality", width = 64, align = "LEFT", drop = 2,
    desc = "Item quality (Poor to Legendary)." },
  { key = "type", label = "Type", width = 76, align = "LEFT", drop = 3,
    desc = "Item type; Currency or Gold for those." },
  { key = "subtype", label = "SubType", width = 100, align = "LEFT", drop = 4,
    desc = "Item subtype; a currency's category." },
  { key = "ah", label = "AH Price", width = 80, align = "RIGHT", drop = 5,
    desc = "Auction-house price per unit, chosen by your price-priority order." },
  { key = "total", label = "Total", width = 110, align = "RIGHT",
    desc = "How many you hold across the shown characters; a holder line shows that holder's count." },
  { key = "value", label = "Value", width = 130, align = "RIGHT",
    desc = "What the whole stack is worth; a holder line shows how old its oldest scan is." },
}
local META = { ilvl = true, quality = true, type = true, subtype = true, ah = true }

-- ── pure ──────────────────────────────────────────────────────────────────────────────────────

function HT.FormatContainers(containers)
  local parts = {}
  for _, c in ipairs(ORDER) do
    if containers and containers[c] then parts[#parts + 1] = LABEL[c] .. " " .. containers[c] end
  end
  return table.concat(parts, " · ")
end

function HT.FormatAge(scannedAt, now)
  if not scannedAt then return "never" end
  local s = (now or time()) - scannedAt
  if s < 60 then return "now" end
  if s < 3600 then return math.floor(s / 60) .. " m" end
  if s < DAY then return math.floor(s / 3600) .. " h" end
  return math.floor(s / DAY) .. " d"
end

-- The visible columns for a row `width` px wide, left to right, as { key, x, w, col }. Optional
-- columns drop (highest `drop` first) until Name keeps NAME_MIN.
function HT.ColumnLayout(width)
  local hidden = {}
  while true do
    local fixed, n, top = 0, 0, nil
    for _, c in ipairs(HT.COLUMNS) do
      if not hidden[c.key] then
        n = n + 1
        if not c.flex then fixed = fixed + c.width end
        if c.drop and (not top or c.drop > top.drop) then top = c end
      end
    end
    local nameW = (width or 0) - 2 * PAD - fixed - (n - 1) * GAP
    if nameW >= NAME_MIN or not top then
      local out, x = {}, PAD
      for _, c in ipairs(HT.COLUMNS) do
        if not hidden[c.key] then
          local w = c.flex and math.max(nameW, 1) or c.width
          out[#out + 1] = { key = c.key, x = x, w = w, col = c }
          x = x + w + GAP
        end
      end
      return out
    end
    hidden[top.key] = true
  end
end

-- An item's metadata and worth, in copper. The AH price is History's: the picked unit price over
-- every configured source (NS.AuctionPrice:Pick over GatherAll). Value is priced the way a loot
-- record is (NS.Util.RecordValue: the higher of that and the vendor price) times the held count,
-- from a record-shaped table built off the live sources, since a held stack has no stored capture.
-- Gold is its own value; a currency has none.
local function enrich(t)
  t.qualityLabel = t.quality ~= nil and NS.Item.QualityLabel(t.quality) or nil
  if t.kind == "GOLD" then t.value = t.total; return end
  if t.kind ~= "ITEM" then t.value = 0; return end
  local ref = t.link or ("item:" .. t.id)
  local ah = NS.AuctionPrice and NS.AuctionPrice:GatherAll(ref, t.id) or nil
  t.ahUnit = ah and (NS.AuctionPrice:Pick(ah)) or nil
  t.ilvl = NS.Compat.GearItemLevel(ref)
  local unit = NS.Util.RecordValue({ auctionPrice = ah, vendorPrice = NS.Compat.GetItemSellPrice(ref) })
  t.value = (unit or 0) * t.total
end

-- Sort keys per column. Numeric columns start descending on a first click, text ones ascending,
-- as History's headers do; ties fall back to the name so the order is stable.
local SORT_VAL = {
  name    = function(t) return t.name:lower() end,
  ilvl    = function(t) return t.ilvl or 0 end,
  quality = function(t) return t.quality or -1 end,
  type    = function(t) return (t.itemType or ""):lower() end,
  subtype = function(t) return (t.itemSubType or ""):lower() end,
  ah      = function(t) return t.ahUnit or 0 end,
  total   = function(t) return t.total end,
  value   = function(t) return t.value end,
}
local NUMERIC = { ilvl = true, quality = true, ah = true, total = true, value = true }

local function sorter(key, asc)
  local val = SORT_VAL[key]
  return function(a, b)
    local va, vb = val(a), val(b)
    if va ~= vb then if asc then return va < vb end return va > vb end
    local na, nb = a.name:lower(), b.name:lower()
    if na ~= nb then return na < nb end
    return a.key < b.key
  end
end

-- `sortAsc` nil means the column's own first-click direction. Each thing line carries its stripe
-- index (one per THING); its holder lines repeat it, so an expanded thing reads as one band.
function HT.BuildModel(filter, expanded, sortKey, sortAsc)
  local things = NS.Holdings:Search(filter or {})
  for _, t in ipairs(things) do enrich(t) end
  local key = SORT_VAL[sortKey or "name"] and (sortKey or "name") or "name"
  if sortAsc == nil then sortAsc = not NUMERIC[key] end
  table.sort(things, sorter(key, sortAsc))
  local lines = {}
  for k, t in ipairs(things) do
    local open = expanded and expanded[t.key] or false
    lines[#lines + 1] = { kind = "thing", key = t.key, name = t.name, quality = t.quality,
      total = t.total, value = t.value, expanded = open, thingKind = t.kind, id = t.id, link = t.link,
      ilvl = t.ilvl, qualityLabel = t.qualityLabel, itemType = t.itemType, itemSubType = t.itemSubType,
      ahUnit = t.ahUnit, stripe = k }
    if open then
      for _, h in ipairs(t.holders) do
        lines[#lines + 1] = { kind = "holder", key = t.key, holder = h.holder, count = h.count,
          containers = h.containers, scannedAt = h.scannedAt, stripe = k }
      end
    end
  end
  return lines
end

-- The tooltip a thing line shows on hover: the item's own (its stored link, else a bare item
-- string), the currency's, or a plain title with the formatted amount for gold. A holder line
-- shows none. Every call goes through core/Compat.lua, presence-gated.
function HT.ShowTooltip(owner, l)
  if not (l and l.kind == "thing") then return false end
  if l.thingKind == "ITEM" then return NS.Compat.ShowItemTooltip(owner, l.link or ("item:" .. l.id)) end
  if l.thingKind == "CURRENCY" then return NS.Compat.ShowCurrencyTooltip(owner, l.id) end
  return NS.Compat.ShowTextTooltip(owner, l.name or "Gold", NS.Util.FormatMoney(l.total))
end

-- Right-click actions for one Holdings line, as data (tests/test_holdingstab.lua reads them). A thing
-- line charts the thing; a holder line also offers to forget the character (spec §8.2), never the
-- warband and never the character you are logged in on (its next scan would put it straight back).
function HT.RowActions(line)
  local items = {
    { label = "Show in Timeline", icon = "graph", enabled = NS.Timeline ~= nil,
      fn = function() NS.Browser:ShowTimeline(line.key) end },
  }
  if line.kind == "holder" then
    local h = line.holder
    local forgettable = h ~= NS.Constants.WARBAND_HOLDER and h ~= NS.Util.PlayerKey()
    items[#items + 1] = { label = "|cffff5555Forget this character|r", icon = "clear", enabled = forgettable,
      fn = function()
        if type(StaticPopup_Show) == "function" then
          StaticPopup_Show("KA0S_LOOTHISTORY_FORGET_HOLDER", h, nil, { holder = h })
        end
      end }
  end
  return items
end

-- ── view ──────────────────────────────────────────────────────────────────────────────────────

HT.expanded, HT.sortKey, HT.sortAsc = {}, "name", true

-- The two color helpers Insights already publishes from modules/AnalyticsFormat.lua (loaded first):
-- one answer for "what color is this quality / class" across both tabs.
local function rgb(c) return c[1], c[2], c[3] end

-- History's sort arrows (modules/BrowserTable.lua), tinted to the same header gold.
local ARROW_ASC  = " " .. NS.IconMarkup("sort-up", "Interface\\Buttons\\Arrow-Up-Up", 0, GOLD_R, GOLD_G, GOLD_B)
local ARROW_DESC = " " .. NS.IconMarkup("sort-down", "Interface\\Buttons\\Arrow-Down-Up", 0, GOLD_R, GOLD_G, GOLD_B)

local function holderLabel(holder)
  if holder == NS.Constants.WARBAND_HOLDER then return "Warband", { 0.4, 0.78, 1 } end
  local e = NS.Holdings:Get(holder)
  return holder, NS.Analytics._classColor(e and e.meta and e.meta.classFile)
end

-- Gold counts are copper and read as coins; everything else is a plain count.
local function countText(key, n) if key == "g" then return NS.Util.FormatMoney(n) end return tostring(n) end

local function cellFont(row, col)
  local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetJustifyH(col.align); fs:SetWordWrap(false); fs:SetHeight(ROW_H)
  return fs
end

-- One pooled row: History's skin (BrowserTable:BuildRow) -- the same 3% white stripe and 10% gold
-- hover -- and one FontString per column, plus the holder line's container split.
local function makeRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_H)
  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints(); row.stripe:SetColorTexture(1, 1, 1, 0.03)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.10)
  row.cells = {}
  for _, col in ipairs(HT.COLUMNS) do row.cells[col.key] = cellFont(row, col) end
  row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.detail:SetJustifyH("RIGHT"); row.detail:SetWordWrap(false)
  -- Left click toggles a thing line; right click opens the row actions (HT.RowActions) in the
  -- History table's own menu, so the collection has one row-menu look.
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      if self.line and NS.BrowserTable and NS.BrowserTable.ShowMenu then
        NS.BrowserTable:ShowMenu(self, HT.RowActions(self.line))
      end
    elseif self.thingKey then
      HT:Toggle(self.thingKey)
    end
  end)
  row:SetScript("OnEnter", function(self) HT.ShowTooltip(self, self.line) end)
  row:SetScript("OnLeave", function() NS.Compat.HideTooltip() end)
  return row
end

-- Place every cell for this refresh's layout. A dropped column's cell is emptied and hidden. A
-- holder line's container split spans the visible metadata columns (it has none of its own); with
-- none visible it takes the right part of the Name column instead.
local function placeCells(row, layout, holder)
  for _, fs in pairs(row.cells) do fs:ClearAllPoints(); fs:SetText(""); fs:Hide() end
  local metaL, metaR, name
  for _, c in ipairs(layout) do
    local fs = row.cells[c.key]
    local x, w = c.x, c.w
    if c.key == "name" then
      name = c
      if holder then x, w = x + INDENT, math.max(1, w - INDENT) end
    end
    fs:SetPoint("LEFT", row, "LEFT", x, 0); fs:SetWidth(w); fs:Show()
    if META[c.key] then metaL = metaL or c.x; metaR = c.x + c.w end
  end
  row.detail:ClearAllPoints()
  if not holder then row.detail:SetText(""); row.detail:Hide(); return end
  row.detail:Show()
  if metaL then
    row.detail:SetPoint("LEFT", row, "LEFT", metaL, 0); row.detail:SetWidth(metaR - metaL)
  else
    local nameW = math.min(name.w - INDENT, HOLDER_MIN)
    row.cells.name:SetWidth(math.max(1, nameW))
    row.detail:SetPoint("LEFT", row, "LEFT", name.x + INDENT + nameW + GAP, 0)
    row.detail:SetWidth(math.max(1, name.w - INDENT - nameW - GAP))
  end
end

local function setCell(row, key, text, r, g, b)
  local fs = row.cells[key]
  fs:SetText(text or ""); fs:SetTextColor(r or 1, g or 1, b or 1)
end

local function bindThing(row, l)
  row.thingKey = l.key
  setCell(row, "name", (l.expanded and "- " or "+ ") .. l.name, rgb(NS.Analytics._qualityColor(l.quality or 1)))
  setCell(row, "ilvl", l.ilvl and tostring(l.ilvl) or "")
  if l.qualityLabel then
    setCell(row, "quality", l.qualityLabel, rgb(NS.Analytics._qualityColor(l.quality)))
  else
    setCell(row, "quality", "")
  end
  setCell(row, "type", l.itemType); setCell(row, "subtype", l.itemSubType)
  setCell(row, "ah", l.ahUnit and NS.Util.FormatMoney(l.ahUnit) or "")
  setCell(row, "total", countText(l.key, l.total))
  setCell(row, "value", NS.Util.FormatMoney(l.value))
end

-- Indented under its thing; the age goes gray once the oldest scan feeding it is a day old, the
-- point past which the count is a memory of the container rather than a reading of it.
local function bindHolder(row, l, now)
  row.thingKey = nil
  local label, color = holderLabel(l.holder)
  setCell(row, "name", label, rgb(color))
  row.detail:SetText(HT.FormatContainers(l.containers))
  setCell(row, "total", countText(l.key, l.count), 0.85, 0.85, 0.85)
  local stale = l.scannedAt and (now - l.scannedAt) >= DAY
  local shade = stale and 0.5 or 0.85
  setCell(row, "value", HT.FormatAge(l.scannedAt, now), shade, shade, shade)
end

-- A header cell: History's header style (GameFontNormalSmall in header gold, a sort arrow on the
-- active column, a tooltip describing the column), sorting on click.
local function makeHeaderCell(header, col)
  local b = CreateFrame("Button", nil, header)
  b:SetHeight(HEADER_H)
  b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.fs:SetAllPoints(); b.fs:SetJustifyH(col.align); b.fs:SetWordWrap(false)
  b.fs:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
  b:SetScript("OnClick", function() HT:SetSort(col.key) end)
  b:SetScript("OnEnter", function(self) NS.Compat.ShowTextTooltip(self, col.label, col.desc, "ANCHOR_BOTTOM") end)
  b:SetScript("OnLeave", function() NS.Compat.HideTooltip() end)
  return b
end

-- Lay the header out over the same columns as the rows, with the arrow on the sorted one.
function HT:LayoutHeader(layout)
  local header = self.header
  for _, b in pairs(header.cells) do b:Hide() end
  self._headerText = {}
  for _, c in ipairs(layout) do
    local b = header.cells[c.key]
    local text = c.col.label
    if c.key == self.sortKey then text = text .. (self.sortAsc and ARROW_ASC or ARROW_DESC) end
    b:ClearAllPoints(); b:SetPoint("LEFT", header, "LEFT", c.x, 0); b:SetWidth(c.w); b:Show()
    b.fs:SetText(text)
    self._headerText[#self._headerText + 1] = text
  end
end

-- Re-clicking the active column flips it; a new column starts descending when numeric, ascending
-- when text (History's rule, BrowserTable:SetSort).
function HT:SetSort(key)
  if not SORT_VAL[key] then return end
  if self.sortKey == key then self.sortAsc = not self.sortAsc
  else self.sortKey, self.sortAsc = key, not NUMERIC[key] end
  self:Refresh()
end

function HT:Attach(pane)
  if self.pane then return end
  self.pane = pane
  -- The column header is its own frame holding exactly one cell per column and nothing else. Its
  -- right edge mirrors the scroll frame's 26 px scrollbar gutter, so the cells sit over the rows.
  local header = CreateFrame("Frame", nil, pane)
  header:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -26, 0)
  header:SetHeight(HEADER_H)
  header.cells = {}
  for _, col in ipairs(HT.COLUMNS) do header.cells[col.key] = makeHeaderCell(header, col) end
  self.header = header

  -- Same scroll skin and anchors as the Insights pane (modules/Analytics.lua), below the header.
  local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -HEADER_H)
  scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -26, 4)
  self.scroll = scroll
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  self.content = content
  scroll:SetScript("OnSizeChanged", function() HT:Refresh() end)
  self.rows = NS.Pool.New()
  self:Refresh()
end

-- Rebuild the visible list off the shared filter. Every row goes back to the pool first and comes
-- out again per line, so a refresh reuses the frames the last one made instead of adding to them.
function HT:Refresh()
  if not self.pane then return end
  local filter = NS.Browser and NS.Browser.CurrentFilter and NS.Browser:CurrentFilter() or {}
  local lines = HT.BuildModel(filter, self.expanded, self.sortKey, self.sortAsc)
  NS.Pool.ReleaseAll(self.rows)
  local w = math.max(1, (self.scroll.GetWidth and self.scroll:GetWidth()) or 1)
  local layout = HT.ColumnLayout(w)
  self:LayoutHeader(layout)
  local now = time()
  self._rowList = {}
  for i, l in ipairs(lines) do
    local row = NS.Pool.Acquire(self.rows, function() return makeRow(self.content) end)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetWidth(w)
    row.line = l
    row.stripe:SetShown(l.stripe % 2 == 0)
    placeCells(row, layout, l.kind == "holder")
    if l.kind == "thing" then bindThing(row, l) else bindHolder(row, l, now) end
    self._rowList[i] = row
  end
  self.content:SetSize(w, math.max(1, #lines * ROW_H))
  self._visible = #lines
  if NS.State.debug and NS.Debug then NS.Debug("UI", "holdings: %d line(s), sort=%s", #lines, self.sortKey) end
end

function HT:Toggle(key)
  self.expanded[key] = (not self.expanded[key]) or nil
  self:Refresh()
end

--- Test seams: how many rows the last Refresh acquired, those rows in line order, and the text
--- each visible header cell was given.
function HT:VisibleRowCount() return self._visible or 0 end
function HT:Rows() return self._rowList or {} end
function HT:HeaderLabels() return self._headerText or {} end

--- HOLDINGS_CHANGED repaints the pane while it is on screen. The Reconciler sends it from Flush,
--- which never runs in combat (spec §5.2), so this handler never lands mid-pull. IsVisible, not
--- IsShown, as Analytics' live handler does: closing the browser with Holdings as the last tab
--- leaves the pane SHOWN inside a hidden window, and every flush (any bag, gold or currency change)
--- would then rebuild the whole model off screen, AH-price lookups and pool churn included.
function HT:Enable()
  if not NS.bus or self.__ev then return end
  self.__ev = NS.NewBusTarget()
  self.__ev:RegisterMessage(NS.MSG.HOLDINGS_CHANGED, function()
    if self.pane and self.pane:IsVisible() then self:Refresh() end
  end)
end

--- The stand-down half (slash-commands-§7): the private bus target goes wholesale.
function HT:Disable()
  if not self.__ev then return end
  self.__ev:UnregisterAllMessages()
  self.__ev:UnregisterAllEvents()
  self.__ev = nil
end

NS.Browser:RegisterTab{ name = "Holdings", order = 40,
  -- Holdings are current state: no Date, Source, Bound, Zone or grouping applies (spec §8.2).
  filters = { search = true, quality = true, type = true, subtype = true, char = true },
  charSource = "holders",
  build = function(pane) HT:Attach(pane) end,
  refresh = function() HT:Refresh() end }
