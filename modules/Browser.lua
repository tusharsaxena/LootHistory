local addonName, NS = ...
NS.Browser = NS.Browser or {}
local B = NS.Browser
local frame

-- Flat "ElvUI-like" default skin: 1px black border + subtle inner line + dark, near-opaque
-- flat background + centered gold title + small red close glyph. Built from stock Blizzard
-- textures only (no ElvUI dependency).
-- TODO (post-v0.1.0): make this skin user-configurable (border color/size, background color/
-- alpha, font) via settings, driven off this table. See docs/EXECUTION_PLAN.md backlog.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SKIN = {
  bg          = { 0.06, 0.06, 0.08, 0.92 },  -- flat dark panel
  border      = { 0, 0, 0, 1 },              -- crisp 1px black outer border
  innerBorder = { 0.24, 0.24, 0.27, 0.85 },  -- subtle lighter inner line (the ElvUI "double" edge)
  divider     = { 0.24, 0.24, 0.27, 0.85 },  -- title separator
  title       = { 1.0, 0.82, 0.0 },          -- Blizzard gold
  tabActive   = { 1.0, 0.82, 0.0 },          -- active tab label (gold)
  tabIdle     = { 0.7, 0.7, 0.72 },          -- idle tab label (grey)
  titleBarH   = 30,
  tabStripH   = 26,
  defaultH    = 440,   -- default == minimum height
}
B.SKIN = SKIN

-- Apply the flat skin to the window. Kept separate so a future settings panel can re-skin live.
function B:ApplySkin(f)
  f:SetBackdrop({
    bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  f:SetBackdropColor(unpack(SKIN.bg))
  f:SetBackdropBorderColor(unpack(SKIN.border))

  -- 1px inner highlight line, inset from the black border.
  if not f.innerBorder then
    local inner = CreateFrame("Frame", nil, f, "BackdropTemplate")
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    f.innerBorder = inner
  end
  f.innerBorder:SetBackdropBorderColor(unpack(SKIN.innerBorder))

  if f.title then f.title:SetTextColor(unpack(SKIN.title)) end
  if f.divider then f.divider:SetColorTexture(unpack(SKIN.divider)) end
end

-- ── Window position/size persistence ──────────────────────────────────────────
-- settings.window = { point, x, y, w, h } relative to UIParent.

local function SaveWindow()
  if not frame then return end
  local point, _, _, x, y = frame:GetPoint(1)
  NS.db.global.settings.window = {
    point = point, x = x, y = y,
    w = frame:GetWidth(), h = frame:GetHeight(),
  }
end

local function RestoreWindow()
  local w = NS.db and NS.db.global.settings.window
  if w and w.point then
    frame:ClearAllPoints()
    frame:SetPoint(w.point, UIParent, w.point, w.x or 0, w.y or 0)
    if w.w and w.h then
      frame:SetSize(math.max(B._minW or 0, w.w), math.max(B._minH or 0, w.h))
    end
  else
    frame:SetPoint("CENTER")
  end
end

-- ── Tabs ──────────────────────────────────────────────────────────────────────
local TABS = { "History", "Insights" }
local lastTab = "History"   -- remembered within a session

-- Lazily let the owning modules build their pane content the first time it's shown.
local function BuildPane(name)
  local pane = frame.panes[name]
  if pane._built then return end
  pane._built = true
  if name == "History" then
    B:BuildHistory(pane)
  elseif name == "Insights" and NS.Analytics and NS.Analytics.Attach then
    NS.Analytics:Attach(pane)
  end
end

function B:SelectTab(name)
  if not frame then return end
  lastTab = name
  for _, t in ipairs(TABS) do
    local active = (t == name)
    frame.panes[t]:SetShown(active)
    frame.tabs[t].label:SetTextColor(unpack(active and SKIN.tabActive or SKIN.tabIdle))
    frame.tabs[t].underline:SetShown(active)
  end
  BuildPane(name)
  -- Refresh the table when the History tab is (re)shown so it reflects current data;
  -- rebuild the data-driven filter dropdowns and footer against the latest history.
  if name == "History" and NS.BrowserTable and NS.BrowserTable.Refresh then
    NS.BrowserTable:Refresh()
    B:RefreshFilterOptions()
    B:UpdateFooter()
  elseif name == "Insights" and NS.Analytics and NS.Analytics.Refresh then
    NS.Analytics:Refresh()
  end
end

local function CreateTabStrip()
  local strip = CreateFrame("Frame", nil, frame)
  strip:SetPoint("TOPLEFT", frame.divider, "BOTTOMLEFT", 6, -2)
  strip:SetPoint("TOPRIGHT", frame.divider, "BOTTOMRIGHT", -6, -2)
  strip:SetHeight(SKIN.tabStripH)
  frame.tabStrip = strip
  frame.tabs = {}

  local x = 0
  for _, name in ipairs(TABS) do
    local tab = CreateFrame("Button", nil, strip)
    tab:SetSize(90, SKIN.tabStripH)
    tab:SetPoint("LEFT", x, 0)
    local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(name)
    tab.label = label
    local underline = tab:CreateTexture(nil, "ARTWORK")
    underline:SetColorTexture(unpack(SKIN.tabActive))
    underline:SetHeight(2)
    underline:SetPoint("BOTTOMLEFT", 8, 0)
    underline:SetPoint("BOTTOMRIGHT", -8, 0)
    tab.underline = underline
    tab:SetScript("OnClick", function() B:SelectTab(name) end)
    frame.tabs[name] = tab
    x = x + 94
  end
end

-- ── Filter bar ──────────────────────────────────────────────────────────────────
-- Compact custom dropdowns + search box matching the flat skin (no Blizzard UIDropDownMenu,
-- so the look stays consistent and there's no protected-call taint surface). All filter
-- changes write B.activeFilter and push it to BrowserTable:SetFilter; group-by drives
-- BrowserTable:SetGroupBy. A footer reports "Showing X of Y".

B.activeFilter = {}

-- One shared popup menu, reused by every dropdown; a full-screen catcher closes it on an
-- outside click. Menu sits above the HIGH-strata window; the catcher one strata below it.
local menu
local function EnsureMenu()
  if menu then return menu end
  menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  menu:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
  menu:SetBackdropBorderColor(0, 0, 0, 1)
  menu:Hide()
  menu.buttons = {}

  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:Hide()
  catcher:SetScript("OnClick", function() menu:Hide() end)
  menu.catcher = catcher
  menu:SetScript("OnHide", function() catcher:Hide() end)

  function menu:Populate(dd)
    local ROW_H = 16
    for _, b in ipairs(self.buttons) do b:Hide() end
    local opts = dd._options or {}
    local w = math.max(dd:GetWidth(), 90)
    for i, opt in ipairs(opts) do
      local b = self.buttons[i]
      if not b then
        b = CreateFrame("Button", nil, self)
        b:SetHeight(ROW_H)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 8, 0)
        fs:SetPoint("RIGHT", -8, 0)
        fs:SetJustifyH("LEFT")
        b.fs = fs
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.15)
        self.buttons[i] = b
      end
      b:SetWidth(w)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 0, -4 - (i - 1) * ROW_H)
      b.fs:SetText(opt.label)
      if opt.value == dd._value then
        b.fs:SetTextColor(1, 0.82, 0)
      else
        b.fs:SetTextColor(0.9, 0.9, 0.9)
      end
      b:SetScript("OnClick", function()
        dd:SetValue(opt.value, opt.label)
        menu:Hide()
        if dd.onSelect then dd.onSelect(opt.value) end
      end)
      b:Show()
    end
    self:SetSize(w, #opts * ROW_H + 8)
  end
  return menu
end

-- A dropdown button: shows the current label + a ▼; clicking opens the shared menu.
local function MakeDropdown(parent, width)
  local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
  dd:SetSize(width, 20)
  dd:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  dd:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  dd:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)

  local fs = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", 6, 0)
  fs:SetPoint("RIGHT", -16, 0)
  fs:SetJustifyH("LEFT")
  dd.text = fs

  local arrow = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  arrow:SetPoint("RIGHT", -5, 0)
  arrow:SetText("\226\150\188") -- ▼
  arrow:SetTextColor(0.7, 0.7, 0.72)

  function dd:SetOptions(opts) self._options = opts end
  function dd:SetValue(v, label) self._value = v; self.text:SetText(label or "") end

  dd:SetScript("OnClick", function(self2)
    local m = EnsureMenu()
    if m:IsShown() and m._owner == self2 then m:Hide(); return end
    m._owner = self2
    m:Populate(self2)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", self2, "BOTTOMLEFT", 0, -1)
    m.catcher:Show()
    m:Show()
  end)
  return dd
end

-- Static option sets. "all" is the sentinel for "no filter"; onSelect maps it to nil.
local QUALITY_OPTIONS = {
  { value = "all", label = "Quality: All" },
  { value = 1, label = "Common+" },
  { value = 2, label = "Uncommon+" },
  { value = 3, label = "Rare+" },
  { value = 4, label = "Epic+" },
  { value = 5, label = "Legendary+" },
}
local GROUP_OPTIONS = {
  { value = "none", label = "Group: None" },
  { value = "source", label = "Group: Source" },
  { value = "zone", label = "Group: Zone" },
  { value = "char", label = "Group: Character" },
  { value = "quality", label = "Group: Quality" },
  { value = "day", label = "Group: Day" },
}

-- Distinct { value, label } option lists from the current history, each prefixed with "All".
local function sourceOptions()
  local seen, out = {}, { { value = "all", label = "Source: All" } }
  for _, r in ipairs(NS.Database:History()) do
    local s = r.source
    if s and not seen[s] then
      seen[s] = true
      out[#out + 1] = { value = s, label = (NS.Constants.SourceLabel[s] or s) }
    end
  end
  return out
end
local function charOptions()
  local seen, out = {}, { { value = "all", label = "Character: All" } }
  for _, r in ipairs(NS.Database:History()) do
    local c = r.char
    if c and not seen[c] then
      seen[c] = true
      out[#out + 1] = { value = c, label = c }
    end
  end
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end
local function zoneOptions()
  -- Query filters zones by mapID, so options carry mapID as value, zone name as label.
  local seen, out = {}, { { value = "all", label = "Zone: All" } }
  for _, r in ipairs(NS.Database:History()) do
    if r.mapID and not seen[r.mapID] then
      seen[r.mapID] = true
      out[#out + 1] = { value = r.mapID, label = r.zone or ("Map " .. r.mapID) }
    end
  end
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end

-- Push the current filter to the table and refresh the footer count.
local function ApplyFilter()
  if NS.BrowserTable then NS.BrowserTable:SetFilter(B.activeFilter) end
  B:UpdateFooter()
end

function B:UpdateFooter()
  if not self._footer then return end
  local shown = (NS.BrowserTable and NS.BrowserTable.matchCount) or 0
  local total = (NS.Database and NS.Database.Count and NS.Database:Count()) or 0
  self._footer:SetText(("Showing %d of %d"):format(shown, total))
end

-- Recompute the data-driven dropdowns (source/char/zone) from the current history.
function B:RefreshFilterOptions()
  local dd = self._dd
  if not dd then return end
  dd.source:SetOptions(sourceOptions())
  dd.char:SetOptions(charOptions())
  dd.zone:SetOptions(zoneOptions())
end

-- Reset every filter control to its "All"/empty default (grouping is left untouched).
function B:ClearFilters()
  self.activeFilter = {}
  local dd = self._dd
  if dd then
    dd.quality:SetValue("all", "Quality: All")
    dd.source:SetValue("all", "Source: All")
    dd.char:SetValue("all", "Character: All")
    dd.zone:SetValue("all", "Zone: All")
  end
  if self._search then self._search:SetText("") end
  ApplyFilter()
end

-- Build the History tab chrome: filter bar (top), table host (middle), footer (bottom).
function B:BuildHistory(pane)
  local bar = CreateFrame("Frame", nil, pane)
  bar:SetPoint("TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", 0, 0)
  bar:SetHeight(22)

  local dd = {}
  self._dd = dd

  dd.group = MakeDropdown(bar, 116)
  dd.group:SetPoint("LEFT", 0, 0)
  dd.group:SetOptions(GROUP_OPTIONS)
  dd.group:SetValue("none", "Group: None")
  dd.group.onSelect = function(v) if NS.BrowserTable then NS.BrowserTable:SetGroupBy(v) end end

  dd.quality = MakeDropdown(bar, 100)
  dd.quality:SetPoint("LEFT", dd.group, "RIGHT", 6, 0)
  dd.quality:SetOptions(QUALITY_OPTIONS)
  dd.quality:SetValue("all", "Quality: All")
  dd.quality.onSelect = function(v)
    B.activeFilter.quality = (v == "all") and nil or v
    ApplyFilter()
  end

  dd.source = MakeDropdown(bar, 100)
  dd.source:SetPoint("LEFT", dd.quality, "RIGHT", 6, 0)
  dd.source:SetValue("all", "Source: All")
  dd.source.onSelect = function(v)
    B.activeFilter.source = (v == "all") and nil or v
    ApplyFilter()
  end

  dd.char = MakeDropdown(bar, 120)
  dd.char:SetPoint("LEFT", dd.source, "RIGHT", 6, 0)
  dd.char:SetValue("all", "Character: All")
  dd.char.onSelect = function(v)
    B.activeFilter.char = (v == "all") and nil or v
    ApplyFilter()
  end

  dd.zone = MakeDropdown(bar, 120)
  dd.zone:SetPoint("LEFT", dd.char, "RIGHT", 6, 0)
  dd.zone:SetValue("all", "Zone: All")
  dd.zone.onSelect = function(v)
    B.activeFilter.mapID = (v == "all") and nil or v
    ApplyFilter()
  end

  -- Clear button (right-aligned).
  local clear = CreateFrame("Button", nil, bar, "BackdropTemplate")
  clear:SetSize(52, 20)
  clear:SetPoint("RIGHT", 0, 0)
  clear:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                      insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  clear:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  clear:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
  local cl = clear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cl:SetPoint("CENTER")
  cl:SetText("Clear")
  clear:SetScript("OnEnter", function() cl:SetTextColor(1, 0.82, 0) end)
  clear:SetScript("OnLeave", function() cl:SetTextColor(1, 1, 1) end)
  clear:SetScript("OnClick", function() B:ClearFilters() end)

  -- Item-name search box, filling the gap between the zone dropdown and Clear.
  local search = CreateFrame("EditBox", nil, bar, "BackdropTemplate")
  search:SetHeight(20)
  search:SetPoint("LEFT", dd.zone, "RIGHT", 8, 0)
  search:SetPoint("RIGHT", clear, "LEFT", -8, 0)
  search:SetAutoFocus(false)
  search:SetFontObject("GameFontHighlightSmall")
  search:SetTextInsets(6, 6, 0, 0)
  search:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                       insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  search:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  search:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
  local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ph:SetPoint("LEFT", 6, 0)
  ph:SetText("Search items…")
  search:SetScript("OnTextChanged", function(self2)
    local t = self2:GetText()
    ph:SetShown(t == "")
    B.activeFilter.text = (t ~= "") and t or nil
    ApplyFilter()
  end)
  search:SetScript("OnEscapePressed", function(self2) self2:ClearFocus() end)
  search:SetScript("OnEnterPressed", function(self2) self2:ClearFocus() end)
  self._search = search

  -- Footer count.
  local footer = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", 2, 2)
  self._footer = footer

  -- Table host between the filter bar and the footer.
  local host = CreateFrame("Frame", nil, pane)
  host:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
  host:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 14)

  if NS.BrowserTable and NS.BrowserTable.Attach then
    NS.BrowserTable:Attach(host)
  end
  self:RefreshFilterOptions()
  self:UpdateFooter()
end

-- ── Frame construction ─────────────────────────────────────────────────────────

local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "LootHistoryWindow", UIParent, "BackdropTemplate")
  -- Default size == minimum size: wide enough for every column, so it can grow but never
  -- shrink into horizontal overflow. Width is derived from the column model.
  local minW = (NS.BrowserTable and NS.BrowserTable.MinFrameWidth and NS.BrowserTable:MinFrameWidth())
    or 822
  local minH = SKIN.defaultH
  B._minW, B._minH = minW, minH
  frame:SetSize(minW, minH)
  frame:SetFrameStrata("HIGH")
  frame:EnableMouse(true)   -- capture clicks over the whole window; no click-through to the world
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetClampedToScreen(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minW, minH)
  elseif frame.SetMinResize then
    frame:SetMinResize(minW, minH)
  end

  -- Title bar (also the drag handle), flat with a divider line beneath it.
  local titleBar = CreateFrame("Frame", nil, frame)
  titleBar:SetPoint("TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", -1, -1)
  titleBar:SetHeight(SKIN.titleBarH)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
  titleBar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    SaveWindow()
  end)
  frame.titleBar = titleBar

  local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("CENTER")
  title:SetText("Ka0s Loot History")
  frame.title = title

  local divider = frame:CreateTexture(nil, "ARTWORK")
  divider:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
  divider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  divider:SetHeight(1)
  frame.divider = divider

  -- Small red close glyph, ElvUI style.
  local close = CreateFrame("Button", nil, titleBar)
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", -6, -5)
  local x = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  x:SetPoint("CENTER")
  x:SetText("\195\151")  -- multiplication sign glyph
  x:SetTextColor(0.9, 0.2, 0.2)
  close:SetScript("OnEnter", function() x:SetTextColor(1, 0.35, 0.35) end)
  close:SetScript("OnLeave", function() x:SetTextColor(0.9, 0.2, 0.2) end)
  close:SetScript("OnClick", function() B:Hide() end)
  frame.closeButton = close

  -- Gear → Settings, left of the close glyph. Uses the stock options-cog texture
  -- (the ⚙ glyph is not in the default WoW font).
  local gear = CreateFrame("Button", nil, titleBar)
  gear:SetSize(16, 16)
  gear:SetPoint("RIGHT", close, "LEFT", 0, 0)
  local g = gear:CreateTexture(nil, "ARTWORK")
  g:SetAllPoints()
  g:SetTexture("Interface\\Buttons\\UI-OptionsButton")
  g:SetVertexColor(0.8, 0.8, 0.82)
  gear:SetScript("OnEnter", function() g:SetVertexColor(1, 0.82, 0) end)
  gear:SetScript("OnLeave", function() g:SetVertexColor(0.8, 0.8, 0.82) end)
  gear:SetScript("OnClick", function() if NS.Panel and NS.Panel.Open then NS.Panel:Open() end end)
  frame.gearButton = gear

  -- Content panes, one per tab, filling below the tab strip.
  frame.panes = {}
  for _, name in ipairs(TABS) do
    local pane = CreateFrame("Frame", nil, frame)
    pane:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -(SKIN.titleBarH + SKIN.tabStripH + 6))
    pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    pane:Hide()
    frame.panes[name] = pane
  end

  CreateTabStrip()

  -- Resize grip, bottom-right.
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    SaveWindow()
    if NS.BrowserTable and NS.BrowserTable.Refresh then NS.BrowserTable:Refresh() end
  end)
  frame.resizeGrip = grip

  -- Close any open dropdown menu whenever the window hides (covers the ESC/UISpecialFrames
  -- path, which calls frame:Hide() directly instead of B:Hide()).
  frame:HookScript("OnHide", function() if menu then menu:Hide() end end)

  B:ApplySkin(frame)
  RestoreWindow()
  frame:SetScale(NS.db and NS.db.global.settings.windowScale or 1.0)
  frame:Hide()

  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryWindow")
  end
  return frame
end

function B:Show()
  local f = EnsureFrame()
  f:Show()
  B:SelectTab(lastTab)
end

function B:Hide()
  if menu then menu:Hide() end
  if frame then frame:Hide() end
end

function B:Toggle()
  local f = EnsureFrame()
  if f:IsShown() then f:Hide() else B:Show() end
end

function B:SetScale(v)
  if frame then frame:SetScale(v) end
end

-- React to settings changes (scale) while the window exists.
function B:OnSettingsChanged()
  if frame then frame:SetScale(NS.db.global.settings.windowScale or 1.0) end
end

-- LibDBIcon wiring lands in Milestone 5.
function B:SetMinimapHidden(_hide)
end

-- Subscribe once the addon (bus) is available.
function B:Enable()
  if NS.bus and not self._enabled then
    self._enabled = true
    NS.bus:RegisterMessage("Ka0s_LootHistory_SettingsChanged", function() B:OnSettingsChanged() end)
  end
end
