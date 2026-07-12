local addonName, NS = ...
NS.Browser = NS.Browser or {}
local B = NS.Browser
local frame

local LDB_NAME = "Ka0s Loot History"  -- LibDataBroker object + LibDBIcon registration key
local minimapObject                   -- the LDB launcher, created once on first Enable
local DBIcon                          -- LibDBIcon-1.0, resolved lazily in SetupMinimap

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
  contentGap  = 14,    -- vertical spacing between the tab strip and the pane content
  defaultH    = 700,   -- opening height — shows the full Insights view without scrolling
  minH        = 460,   -- minimum height (content scrolls below this)
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

-- ElvUI-style thin × glyph close button, light grey by default and the player's class colour
-- on hover. Shared by the History and Debug windows.
function B:MakeCloseButton(parent, onClick)
  local close = CreateFrame("Button", nil, parent)
  close:SetSize(24, 24)
  local x = close:CreateFontString(nil, "OVERLAY")
  x:SetFont(STANDARD_TEXT_FONT, 24, "")
  x:SetPoint("CENTER", close, "CENTER", 0, 2)  -- the × sits low in its font box; nudge up
  x:SetText("\195\151")  -- × multiplication sign (thin, ElvUI-like)
  x:SetTextColor(0.85, 0.85, 0.85)
  local _, class = UnitClass("player")
  local cc = (class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]) or { r = 1, g = 0.82, b = 0 }
  close:SetScript("OnEnter", function() x:SetTextColor(cc.r, cc.g, cc.b) end)
  close:SetScript("OnLeave", function() x:SetTextColor(0.85, 0.85, 0.85) end)
  close:SetScript("OnClick", onClick)
  return close
end

-- ── Window position/size persistence ──────────────────────────────────────────
-- settings.window = { point, x, y, w, h } relative to UIParent.
--
-- NOTE: settings.window and savedView (see savedViewOrStock below) are view/window runtime state
-- persisted directly to NS.db.global by the Browser — they are intentionally NOT Schema rows, so
-- they don't route through Schema:Set. The "every mutation goes through Schema:Set" convention
-- (CLAUDE §2) covers user settings only; §6A window geometry and the saved table view are
-- carved out. See CLAUDE.md.

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

  -- Down-arrow texture (the ▼ glyph is not in the default WoW font, so it renders as a box).
  local arrow = dd:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(12, 12)
  arrow:SetPoint("RIGHT", -4, 0)
  arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
  arrow:SetVertexColor(0.7, 0.7, 0.72)

  function dd:SetOptions(opts) self._options = opts end
  function dd:SetValue(v, label) self._value = v; self.text:SetText(label or "") end
  -- Set the value and derive its display label from the current options (used when applying a
  -- saved view). Falls back to the raw value if the option isn't present.
  function dd:SelectValue(v)
    for _, o in ipairs(self._options or {}) do
      if o.value == v then self:SetValue(o.value, o.label); return end
    end
    self:SetValue(v, tostring(v))
  end

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
local DATE_OPTIONS = {
  { value = "all", label = "Date: All" },
  { value = "today", label = "Today" },
  { value = "7d", label = "Last 7 days" },
  { value = "30d", label = "Last 30 days" },
}
local PLAYER_OPTIONS = {
  { value = "current", label = "Current player" },
  { value = "all", label = "All players" },
}

-- The saved "view" = group-by + sort + column filters (NOT the player scope, which is a
-- session-only default of "current player"). This is the stock/reset baseline; the user's
-- saved view lives in NS.db.global.savedView. `date` stores the range option (not an absolute
-- `from`) so it recomputes correctly on each load.
local STOCK_VIEW = {
  groupBy = "none", sortKey = "date", sortAsc = false, groupAsc = true,
  quality = "all", source = "all", itemType = "all", mapID = "all", date = "all", search = "",
}
local function savedViewOrStock()
  local v = NS.db and NS.db.global and NS.db.global.savedView
  if type(v) == "table" then return v end
  return STOCK_VIEW
end

-- A small flat-skin text button for the filter bar (Clear / Save / Reset).
local function makeBarButton(parent, text, width, onClick, tooltip)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width, 20)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  b:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  b:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER")
  fs:SetText(text)
  b:SetScript("OnEnter", function(self2)
    fs:SetTextColor(1, 0.82, 0)
    if tooltip then
      GameTooltip:SetOwner(self2, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(tooltip, 0.9, 0.9, 0.9, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() fs:SetTextColor(1, 1, 1); GameTooltip:Hide() end)
  b:SetScript("OnClick", onClick)
  return b
end

-- The dataset the filter bar reflects: the table's current records (test data in test mode,
-- otherwise the live history) so dropdown options + the footer match what the table shows.
local function dataset()
  if NS.BrowserTable and NS.BrowserTable.CurrentRecords then
    return NS.BrowserTable:CurrentRecords()
  end
  return NS.Database:History()
end

-- Sort distinct options by label and prefix the "All" sentinel (kept first regardless of sort).
local function withAll(allLabel, items)
  table.sort(items, function(a, b) return a.label < b.label end)
  table.insert(items, 1, { value = "all", label = allLabel })
  return items
end

-- Distinct { value, label } option lists from the current dataset, each prefixed with "All".
local function sourceOptions()
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    local s = r.source
    if s and not seen[s] then
      seen[s] = true
      items[#items + 1] = { value = s, label = (NS.Constants.SourceLabel[s] or s) }
    end
  end
  return withAll("Source: All", items)
end
local function charOptions()
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    local c = r.char
    if c and not seen[c] then
      seen[c] = true
      items[#items + 1] = { value = c, label = c }
    end
  end
  return withAll("Character: All", items)
end
local function typeOptions()
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    local ty = r.itemType
    if ty and ty ~= "" and not seen[ty] then
      seen[ty] = true
      items[#items + 1] = { value = ty, label = ty }
    end
  end
  return withAll("Type: All", items)
end
local function zoneOptions()
  -- Query filters zones by mapID, so options carry mapID as value, zone name as label.
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    if r.mapID and not seen[r.mapID] then
      seen[r.mapID] = true
      items[#items + 1] = { value = r.mapID, label = r.zone or ("Map " .. r.mapID) }
    end
  end
  return withAll("Zone: All", items)
end

-- Push the current filter to the table and refresh the footer count.
local function ApplyFilter()
  if NS.BrowserTable then NS.BrowserTable:SetFilter(B.activeFilter) end
  B:UpdateFooter()
end

function B:UpdateFooter()
  if not self._footer then return end
  local shown = (NS.BrowserTable and NS.BrowserTable.matchCount) or 0
  local total = #dataset()
  self._footer:SetText(("Showing %d of %d"):format(shown, total))
end

-- Recompute the data-driven dropdowns (source/type/char/zone) from the current dataset.
function B:RefreshFilterOptions()
  local dd = self._dd
  if not dd then return end
  dd.source:SetOptions(sourceOptions())
  dd.type:SetOptions(typeOptions())
  dd.char:SetOptions(charOptions())
  dd.zone:SetOptions(zoneOptions())
end

-- The table's dataset changed (entering/leaving test mode): rebuild the dropdowns from the new
-- dataset. In test mode show everything (stock view, all players, since test chars differ);
-- leaving it, return to the saved view + current player.
function B:OnDatasetChanged()
  self:RefreshFilterOptions()
  if NS.BrowserTable and NS.BrowserTable.testMode then
    self:ApplyView(STOCK_VIEW, "all")
  else
    self:ApplyView(savedViewOrStock(), "current")
  end
  self:UpdateFooter()
  self:UpdateTestBadge()
end

-- Show/hide the bright-red "TEST MODE" badge beside the window title.
function B:UpdateTestBadge()
  if not (frame and frame.testBadge) then return end
  frame.testBadge:SetShown(NS.BrowserTable and NS.BrowserTable.testMode or false)
end

local function currentKey()
  return NS.Util and NS.Util.PlayerKey and NS.Util.PlayerKey() or nil
end

-- The char filter is surfaced by two controls — the player toggle (Current/All) and the
-- Character dropdown — so both funnel through here and stay in sync. char == nil = all players.
function B:SetCharFilter(char)
  self.activeFilter.char = char
  local dd = self._dd
  if dd then
    if dd.player then
      if char == nil then
        dd.player:SetValue("all", "All players")
      elseif char == currentKey() then
        dd.player:SetValue("current", "Current player")
      else
        -- A specific non-current character is selected via the Character dropdown; neither scope
        -- preset applies. Show a neutral label naming that character instead of contradicting the
        -- single-character table with "All players". "custom" matches no PLAYER_OPTIONS value, so
        -- the dropdown menu highlights nothing.
        dd.player:SetValue("custom", (char:match("^[^-]+")) or char)
      end
    end
    if dd.char then
      if char == nil then dd.char:SelectValue("all") else dd.char:SelectValue(char) end
    end
  end
  ApplyFilter()
end

-- Capture the current group/sort/column-filters as a view table (excludes the player scope).
function B:CaptureView()
  local dd, BT = self._dd, NS.BrowserTable
  return {
    groupBy  = BT and BT.groupBy or "none",
    sortKey  = BT and BT.sortKey or "date",
    sortAsc  = BT and BT.sortAsc == true,
    groupAsc = not (BT and BT.groupAsc == false),
    quality  = (dd and dd.quality._value) or "all",
    source   = (dd and dd.source._value) or "all",
    itemType = (dd and dd.type._value) or "all",
    mapID    = (dd and dd.zone._value) or "all",
    date     = (dd and dd.date._value) or "all",
    search   = (self._search and self._search:GetText()) or "",
  }
end

-- Apply a saved/stock view: set the table's group + sort, the column-filter dropdowns, and the
-- resolved filter. The player scope is NOT part of the view — it resets to `scope` (default
-- "current"), keeping "current player" the per-session default. Calls ApplyFilter (refreshes).
function B:ApplyView(view, scope)
  view = view or STOCK_VIEW
  self.activeFilter = {}
  local BT = NS.BrowserTable
  if BT then
    BT.groupBy  = view.groupBy or "none"
    BT.sortKey  = view.sortKey or "date"
    BT.sortAsc  = view.sortAsc == true
    BT.groupAsc = view.groupAsc ~= false
  end
  local dd = self._dd
  if dd then
    dd.group:SelectValue(view.groupBy or "none")
    dd.quality:SelectValue(view.quality or "all")
    dd.type:SelectValue(view.itemType or "all")
    dd.source:SelectValue(view.source or "all")
    dd.zone:SelectValue(view.mapID or "all")
    dd.date:SelectValue(view.date or "all")
  end
  if self._search then self._search:SetText(view.search or "") end
  if view.quality and view.quality ~= "all" then self.activeFilter.quality = view.quality end
  if view.source and view.source ~= "all" then self.activeFilter.source = view.source end
  if view.itemType and view.itemType ~= "all" then self.activeFilter.itemType = view.itemType end
  if view.mapID and view.mapID ~= "all" then self.activeFilter.mapID = view.mapID end
  if view.date and view.date ~= "all" then self.activeFilter.from = NS.Util.RangeFrom(view.date) end
  if view.search and view.search ~= "" then self.activeFilter.text = view.search end
  if scope == "all" then self:SetCharFilter(nil) else self:SetCharFilter(currentKey()) end
end

-- Save the current view as the account-wide default; Reset drops it back to stock.
function B:SaveView()
  if NS.db and NS.db.global then
    NS.db.global.savedView = self:CaptureView()
    print(NS.PREFIX .. " view saved as default.")
  end
end
function B:ResetView()
  if NS.db and NS.db.global then NS.db.global.savedView = nil end
  self:ApplyView(STOCK_VIEW, "current")
  print(NS.PREFIX .. " view reset to stock defaults.")
end

-- Clear returns the filters/group/sort to the saved default (or stock), and the player scope
-- to "current player".
function B:ClearFilters()
  self:ApplyView(savedViewOrStock(), "current")
end

-- Build the History tab chrome: two-row filter bar (top), table host (middle), footer (bottom).
--   Row 1: Group by · [search…] · Clear
--   Row 2: column filters in table order — Date · Quality · Type · Source · Zone · Character
function B:BuildHistory(pane)
  local ROW1, ROW2 = 0, -24
  local bar = CreateFrame("Frame", nil, pane)
  bar:SetPoint("TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", 0, 0)
  bar:SetHeight(46)

  local dd = {}
  self._dd = dd

  -- ── Row 1: Group by · Search · Clear ──
  -- Group width matches the Date dropdown directly below it (120); the player toggle at the
  -- right of row 2 matches the Save+Reset+Clear button cluster above it (48+6+52+6+52 = 164).
  dd.group = MakeDropdown(bar, 120)
  dd.group:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, ROW1)
  dd.group:SetOptions(GROUP_OPTIONS)
  dd.group:SetValue("none", "Group: None")
  dd.group.onSelect = function(v) if NS.BrowserTable then NS.BrowserTable:SetGroupBy(v) end end

  -- Right cluster (row 1): Save · Reset · Clear (right-aligned).
  local clear = makeBarButton(bar, "Clear", 52, function() B:ClearFilters() end,
    "Clear filters and group/sort back to your saved view.")
  clear:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, ROW1)
  local resetBtn = makeBarButton(bar, "Reset", 52, function() B:ResetView() end,
    "Reset the saved view to stock defaults.")
  resetBtn:SetPoint("RIGHT", clear, "LEFT", -6, 0)
  local saveBtn = makeBarButton(bar, "Save", 48, function() B:SaveView() end,
    "Save the current group, sort and filters as your default view.")
  saveBtn:SetPoint("RIGHT", resetBtn, "LEFT", -6, 0)

  -- Item-name search box, filling the gap between Group by and the Save button (row 1).
  local search = CreateFrame("EditBox", nil, bar, "BackdropTemplate")
  search:SetHeight(20)
  search:SetPoint("LEFT", dd.group, "RIGHT", 8, 0)
  search:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
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

  -- ── Row 2: column filters, left→right in the same order the columns appear in the table:
  --   Date · Quality · Type · Source · Zone · Character ──
  dd.date = MakeDropdown(bar, 120)
  dd.date:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, ROW2)
  dd.date:SetOptions(DATE_OPTIONS)
  dd.date:SetValue("all", "Date: All")
  dd.date.onSelect = function(v)
    if v == "all" then B.activeFilter.from = nil else B.activeFilter.from = NS.Util.RangeFrom(v) end
    ApplyFilter()
  end

  dd.quality = MakeDropdown(bar, 100)
  dd.quality:SetPoint("LEFT", dd.date, "RIGHT", 6, 0)
  dd.quality:SetOptions(QUALITY_OPTIONS)
  dd.quality:SetValue("all", "Quality: All")
  dd.quality.onSelect = function(v)
    -- Explicit branch: `(v=="all") and nil or v` is the Lua ternary trap — with nil in the
    -- middle it evaluates back to v, so "All" would never clear the filter.
    if v == "all" then B.activeFilter.quality = nil else B.activeFilter.quality = v end
    ApplyFilter()
  end

  dd.type = MakeDropdown(bar, 116)
  dd.type:SetPoint("LEFT", dd.quality, "RIGHT", 6, 0)
  dd.type:SetValue("all", "Type: All")
  dd.type.onSelect = function(v)
    if v == "all" then B.activeFilter.itemType = nil else B.activeFilter.itemType = v end
    ApplyFilter()
  end

  dd.source = MakeDropdown(bar, 100)
  dd.source:SetPoint("LEFT", dd.type, "RIGHT", 6, 0)
  dd.source:SetValue("all", "Source: All")
  dd.source.onSelect = function(v)
    if v == "all" then B.activeFilter.source = nil else B.activeFilter.source = v end
    ApplyFilter()
  end

  dd.zone = MakeDropdown(bar, 120)
  dd.zone:SetPoint("LEFT", dd.source, "RIGHT", 6, 0)
  dd.zone:SetValue("all", "Zone: All")
  dd.zone.onSelect = function(v)
    if v == "all" then B.activeFilter.mapID = nil else B.activeFilter.mapID = v end
    ApplyFilter()
  end

  dd.char = MakeDropdown(bar, 150)
  dd.char:SetPoint("LEFT", dd.zone, "RIGHT", 6, 0)
  dd.char:SetValue("all", "Character: All")
  dd.char.onSelect = function(v) B:SetCharFilter(v == "all" and nil or v) end

  -- Player scope toggle (row 2, right-aligned): Current player (session default) vs All players.
  -- Shares the char filter with the Character dropdown via SetCharFilter.
  dd.player = MakeDropdown(bar, 164)
  dd.player:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, ROW2)
  dd.player:SetOptions(PLAYER_OPTIONS)
  dd.player:SetValue("current", "Current player")
  dd.player.onSelect = function(v) B:SetCharFilter(v == "current" and currentKey() or nil) end

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
  self:RefreshFilterOptions()                     -- populate dropdown options first
  self:ApplyView(savedViewOrStock(), "current")   -- open on the saved view + current player
end

-- ── Frame construction ─────────────────────────────────────────────────────────

local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "LootHistoryWindow", UIParent, "BackdropTemplate")
  -- Default size == minimum size: wide enough for every column, so it can grow but never
  -- shrink into horizontal overflow. Width is derived from the column model.
  local minW = (NS.BrowserTable and NS.BrowserTable.MinFrameWidth and NS.BrowserTable:MinFrameWidth())
    or 822
  local minH = SKIN.minH
  B._minW, B._minH = minW, minH
  frame:SetSize(minW, SKIN.defaultH)  -- open at the (taller) default; can shrink to minH
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

  -- Bright-red badge beside the title, shown only while the table is in test mode.
  local testBadge = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  testBadge:SetPoint("LEFT", title, "RIGHT", 10, 0)
  testBadge:SetText("TEST MODE")
  testBadge:SetTextColor(1, 0.15, 0.15)
  testBadge:Hide()
  frame.testBadge = testBadge

  local divider = frame:CreateTexture(nil, "ARTWORK")
  divider:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
  divider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  divider:SetHeight(1)
  frame.divider = divider

  -- ElvUI-style thin × close glyph (class-coloured on hover). Anchored to the title bar's
  -- vertical centre so it lines up with the CENTER-anchored title.
  local close = B:MakeCloseButton(titleBar, function() B:Hide() end)
  close:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
  frame.closeButton = close
  -- (Settings gear removed; open the options panel with /lh config.)

  -- Content panes, one per tab, filling below the tab strip.
  frame.panes = {}
  for _, name in ipairs(TABS) do
    local pane = CreateFrame("Frame", nil, frame)
    pane:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -(SKIN.titleBarH + SKIN.tabStripH + SKIN.contentGap))
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
  B:UpdateTestBadge()
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

-- React to settings changes (window scale + minimap visibility) while the window exists.
function B:OnSettingsChanged()
  if frame then frame:SetScale(NS.db.global.settings.windowScale or 1.0) end
  self:SetMinimapHidden(NS.db.global.minimap and NS.db.global.minimap.hide)
end

-- ── Minimap button (LibDBIcon + LibDataBroker) ─────────────────────────────────
-- A "launcher" data object: left-click toggles the window, right-click opens Settings,
-- and the tooltip shows the live record count. Visibility lives in db.global.minimap
-- (the same table the "Hide minimap button" setting writes), which LibDBIcon owns —
-- so registration alone honors the persisted hide state across /reload.

function B:SetupMinimap()
  if minimapObject then return end  -- already registered this session
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  DBIcon = DBIcon or (LibStub and LibStub("LibDBIcon-1.0", true))
  if not (LDB and DBIcon) then return end

  minimapObject = LDB:NewDataObject(LDB_NAME, {
    type  = "launcher",
    label = "Loot History",
    icon  = "Interface\\Icons\\INV_Misc_Bag_08",
    OnClick = function(_, button)
      if button == "RightButton" then
        if NS.Panel and NS.Panel.Open then NS.Panel:Open() end
      else
        B:Toggle()
      end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine("Ka0s Loot History", 1, 0.82, 0)
      local n = (NS.Database and NS.Database.Count) and NS.Database:Count() or 0
      tt:AddLine(n == 1 and "1 record" or (n .. " records"), 0.7, 0.7, 0.7)
      tt:AddLine(" ")
      tt:AddLine("Left-click: open the history window", 0.5, 0.5, 0.5)
      tt:AddLine("Right-click: open settings", 0.5, 0.5, 0.5)
    end,
  })

  local mm = NS.db.global.minimap
  if not mm then mm = { hide = false }; NS.db.global.minimap = mm end
  DBIcon:Register(LDB_NAME, minimapObject, mm)
end

-- Show/hide the minimap button live (driven by the "Hide minimap button" setting).
function B:SetMinimapHidden(hide)
  if DBIcon and DBIcon:IsRegistered(LDB_NAME) then
    if hide then DBIcon:Hide(LDB_NAME) else DBIcon:Show(LDB_NAME) end
  end
end

-- Keep the History tab current when the underlying history changes (new loot, a row delete,
-- retention prune). Only does work when the window is open on the History tab.
function B:OnHistoryChanged()
  if not (frame and frame:IsShown() and lastTab == "History") then return end
  if NS.BrowserTable and NS.BrowserTable.Refresh then NS.BrowserTable:Refresh() end
  self:RefreshFilterOptions()
  self:UpdateFooter()
end

-- Subscribe once the addon (bus) is available.
function B:Enable()
  if NS.bus and not self._enabled then
    self._enabled = true
    NS.bus:RegisterMessage("Ka0s_LootHistory_SettingsChanged", function() B:OnSettingsChanged() end)
    NS.bus:RegisterMessage("Ka0s_LootHistory_HistoryChanged", function() B:OnHistoryChanged() end)
    NS.bus:RegisterMessage("Ka0s_LootHistory_RecordAdded", function() B:OnHistoryChanged() end)
    B:SetupMinimap()
  end
end
