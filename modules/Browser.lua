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
  if name == "History" and NS.BrowserTable and NS.BrowserTable.Attach then
    NS.BrowserTable:Attach(pane)
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
  -- Refresh the table when the History tab is (re)shown so it reflects current data.
  if name == "History" and NS.BrowserTable and NS.BrowserTable.Refresh then
    NS.BrowserTable:Refresh()
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
