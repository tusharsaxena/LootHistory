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
-- Hues drawn from WoW's palette (Blizzard gold, legendary orange, rare blue), muted a touch.
local BOUND_STYLE = {
  UNBOUND = { 0.60, 0.60, 0.60, 0.40 }, -- not bound: faint grey
  BOE     = { 0.92, 0.92, 0.92, 0.95 }, -- bind on equip: off-white
  BOP     = { 0.30, 0.82, 0.42, 1.00 }, -- bind on pickup: green (distinct from account orange)
  ACCOUNT = { 0.95, 0.52, 0.12, 1.00 }, -- account bound: orange
  WARBAND = { 0.30, 0.58, 0.98, 1.00 }, -- warbound: blue
}

-- Apply a padlock look to a texture, tolerant of missing art: use the first lock atlas that
-- actually exists on this client, else fall back to a solid chip so the column is never blank.
-- communities-icon-lock + greatVault-lock confirmed present on 11.x; the rest are fallbacks
-- for other flavors/versions.
local LOCK_ATLASES = {
  "communities-icon-lock", "greatVault-lock", "UI-LFG-Lock",
  "Professions-Recipe-Locked", "collections-icon-lock",
}

-- Resolve (once) the first lock atlas that exists on this client; false if none.
local resolvedLockAtlas
local function lockAtlas()
  if resolvedLockAtlas ~= nil then return resolvedLockAtlas end
  resolvedLockAtlas = false
  if C_Texture and C_Texture.GetAtlasInfo then
    for _, atlas in ipairs(LOCK_ATLASES) do
      if C_Texture.GetAtlasInfo(atlas) then
        resolvedLockAtlas = atlas
        break
      end
    end
  end
  return resolvedLockAtlas
end

local function applyLockTexture(tex)
  local atlas = lockAtlas()
  if atlas then
    tex:SetAtlas(atlas)
  else
    tex:SetTexture("Interface\\Buttons\\WHITE8X8") -- visible chip fallback (pending a real lock atlas)
  end
end

-- Inline coloured lock (or chip) for tooltip text, tinted to a BOUND_STYLE colour.
local function lockMarkup(style)
  local r = math.floor((style[1] or 1) * 255)
  local g = math.floor((style[2] or 1) * 255)
  local b = math.floor((style[3] or 1) * 255)
  local atlas = lockAtlas()
  if atlas and CreateAtlasMarkup then
    return CreateAtlasMarkup(atlas, 14, 14, 0, 0, r, g, b)
  end
  if CreateTextureMarkup then
    return CreateTextureMarkup("Interface\\Buttons\\WHITE8X8", 8, 8, 12, 12, 0, 1, 0, 1, r, g, b)
  end
  return ""
end

-- Legend for the Bound column tooltip: one "[lock] - Label" line per state.
local BOUND_LEGEND = {
  { "UNBOUND", "Not Bound" },
  { "BOE",     "Bind on Equip" },
  { "BOP",     "Bind on Pickup" },
  { "ACCOUNT", "Account Bound" },
  { "WARBAND", "Warbound" },
}
function BrowserTable:AddBoundLegend(tooltip)
  for _, entry in ipairs(BOUND_LEGEND) do
    tooltip:AddLine(lockMarkup(BOUND_STYLE[entry[1]]) .. " - " .. entry[2], 0.9, 0.9, 0.9)
  end
end

-- Strip realm from "Name-Realm" for the compact Character column (full value in tooltip).
local function charName(char)
  if not char then return "" end
  return char:match("^[^-]+") or char
end

-- Inline class icon (from the shared class-circles texture) for the Character column.
local CLASS_ICON_TEX = "Interface\\TargetingFrame\\UI-Classes-Circles"
local function classIconMarkup(classFile)
  local c = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
  if not (c and CreateTextureMarkup) then return "" end
  return CreateTextureMarkup(CLASS_ICON_TEX, 256, 256, 13, 13,
    c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

-- Class-colored, icon-prefixed display value for a looter.
local function charDisplay(r)
  local name = charName(r.char)
  local icon = classIconMarkup(r.classFile)
  return icon ~= "" and (icon .. " " .. name) or name
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
  { key = "char", label = "Character", width = 104, align = "LEFT",
    desc = "Character who looted the item (class-colored; realm in the item tooltip).",
    valueFn = function(r) return charDisplay(r) end,
    sortFn = function(r) return (r.char or ""):lower() end },
  { key = "ilvl", label = "iLvl", width = 40, align = "RIGHT",
    desc = "Item level (equippable gear only).",
    valueFn = function(r) return r.itemLevel and tostring(r.itemLevel) or "" end,
    sortFn = function(r) return r.itemLevel or 0 end },
  { key = "bound", label = "", width = 18, align = "CENTER", icon = true,
    desc = "Binding: grey = not bound, white = Bind on Equip, green = Bind on Pickup, "
      .. "orange = Account bound, blue = Warbound.",
    valueFn = function() return "" end,   -- rendered as an icon, not text
    sortFn = function(r) return r.bound or "" end },
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
  { key = "type", label = "Type", width = 84, align = "LEFT",
    desc = "Item type (subtype in the Item tooltip).",
    valueFn = function(r) return r.itemType or "" end,
    sortFn = function(r) return (r.itemType or ""):lower() end },
  { key = "vendor", label = "Vendor", width = 76, align = "RIGHT",
    desc = "Vendor sell price per unit.",
    valueFn = function(r) return NS.Util.FormatMoney(r.sellPrice) end,
    sortFn = function(r) return r.sellPrice or 0 end },
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
BrowserTable.testMode = false

-- Synthetic dataset covering every binding state (multiple items each) plus varied quality,
-- item level, and source — for eyeballing the table's look via /lh testmode.
local TEST_BINDINGS = {
  { key = nil,       name = "Unbound" },
  { key = "BOE",     name = "Bind on Equip" },
  { key = "BOP",     name = "Bind on Pickup" },
  { key = "ACCOUNT", name = "Account Bound" },
  { key = "WARBAND", name = "Warbound" },
}
local TEST_SOURCES = { "KILL", "CONTAINER", "MPLUS", "QUEST", "VENDOR" }
local TEST_CLASSES = { "WARRIOR", "MAGE", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER" }
local TEST_TYPES = { "Armor", "Weapon", "Consumable", "Tradegoods", "Quest" }

function BrowserTable:BuildTestData()
  local now = time()
  local out = {}
  for ti, b in ipairs(TEST_BINDINGS) do
    for k = 1, 3 do
      local i = #out + 1
      out[i] = {
        ts = now - i * 137,
        char = TEST_CLASSES[((i - 1) % #TEST_CLASSES) + 1] .. "test-Ravencrest",
        classFile = TEST_CLASSES[((i - 1) % #TEST_CLASSES) + 1],
        itemName = b.name .. " Sample " .. k,
        quality = ((i - 1) % 5) + 1,            -- Common..Legendary spread
        quantity = ((i % 3) == 0) and (i % 5 + 1) or 1,
        itemLevel = (k % 2 == 0) and (600 + ti * 4 + k) or nil, -- some gear, some not
        bound = b.key,
        sellPrice = i * 137 + k * 11,           -- varied vendor prices
        itemType = TEST_TYPES[((i - 1) % #TEST_TYPES) + 1],
        itemSubType = "Sample",
        source = TEST_SOURCES[((i - 1) % #TEST_SOURCES) + 1],
        sourceName = (k == 1) and "Test Source" or nil,
        zone = "Test Zone " .. ti,
        mapID = ti,
        confidence = "CERTAIN",
      }
    end
  end
  return out
end

function BrowserTable:ToggleTestMode()
  self.testMode = not self.testMode
  if NS.Browser and NS.Browser.Show then NS.Browser:Show() end
  self:Refresh()
  return self.testMode
end

-- Flat display list of { kind="row", record=r }. Grouping (3.4) inserts header entries.
function BrowserTable:BuildDisplayList()
  local records = self.testMode and self:BuildTestData() or NS.Database:Query(self.filter)
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
    if col.icon then
      BrowserTable:AddBoundLegend(GameTooltip)
    elseif col.desc then
      GameTooltip:AddLine(col.desc, 0.9, 0.9, 0.9, true)
    end
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
    elseif col.key == "char" then
      local cc = RAID_CLASS_COLORS and r.classFile and RAID_CLASS_COLORS[r.classFile]
      if cc then fs:SetTextColor(cc.r, cc.g, cc.b) else fs:SetTextColor(0.9, 0.9, 0.9) end
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
