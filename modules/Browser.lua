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
  titleBarH   = 30,
}

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

local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "LootHistoryWindow", UIParent, "BackdropTemplate")
  frame:SetSize(820, 520)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetClampedToScreen(true)

  -- Title bar (also the drag handle), flat with a divider line beneath it.
  local titleBar = CreateFrame("Frame", nil, frame)
  titleBar:SetPoint("TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", -1, -1)
  titleBar:SetHeight(SKIN.titleBarH)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
  titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
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

  -- Placeholder content (replaced by the table + tabs in Milestone 3).
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  hint:SetPoint("CENTER", 0, -SKIN.titleBarH / 2)
  hint:SetText("Loot history will appear here.")

  B:ApplySkin(frame)
  frame:SetScale(NS.db and NS.db.global.settings.windowScale or 1.0)
  frame:Hide()

  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryWindow")
  end
  return frame
end

function B:Show()
  EnsureFrame():Show()
end

function B:Hide()
  if frame then frame:Hide() end
end

function B:Toggle()
  local f = EnsureFrame()
  if f:IsShown() then f:Hide() else f:Show() end
end

function B:SetScale(v)
  if frame then frame:SetScale(v) end
end

-- LibDBIcon wiring lands in Milestone 5.
function B:SetMinimapHidden(_hide)
end
