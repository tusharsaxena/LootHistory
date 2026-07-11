local addonName, NS = ...
NS.DebugLog = NS.DebugLog or {}
local D = NS.DebugLog
local frame

-- A standalone debug console styled like the browser window. Debug output (NS.Debug) prints
-- here instead of the chat frame.
local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "LootHistoryDebugWindow", UIParent, "BackdropTemplate")
  frame:SetSize(560, 320)
  frame:SetPoint("CENTER", 220, -80)
  frame:SetFrameStrata("HIGH")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)

  local titleBar = CreateFrame("Frame", nil, frame)
  titleBar:SetPoint("TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", -1, -1)
  titleBar:SetHeight(26)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
  titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

  local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("CENTER")
  title:SetText("Loot History \226\128\148 Debug")
  frame.title = title

  local divider = frame:CreateTexture(nil, "ARTWORK")
  divider:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
  divider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  divider:SetHeight(1)
  frame.divider = divider

  local close = CreateFrame("Button", nil, titleBar)
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", -6, -3)
  local x = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  x:SetPoint("CENTER")
  x:SetText("\195\151")
  x:SetTextColor(0.9, 0.2, 0.2)
  close:SetScript("OnClick", function() D:Hide() end)

  local clear = CreateFrame("Button", nil, titleBar)
  clear:SetSize(42, 18)
  clear:SetPoint("RIGHT", close, "LEFT", -6, 0)
  local ct = clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ct:SetPoint("CENTER")
  ct:SetText("Clear")
  ct:SetTextColor(0.7, 0.7, 0.72)
  clear:SetScript("OnEnter", function() ct:SetTextColor(1, 0.82, 0) end)
  clear:SetScript("OnLeave", function() ct:SetTextColor(0.7, 0.7, 0.72) end)
  clear:SetScript("OnClick", function() if frame.log then frame.log:Clear() end end)

  local log = CreateFrame("ScrollingMessageFrame", nil, frame)
  log:SetPoint("TOPLEFT", 8, -(26 + 6))
  log:SetPoint("BOTTOMRIGHT", -8, 8)
  log:SetFontObject(GameFontHighlightSmall)
  log:SetJustifyH("LEFT")
  log:SetFading(false)
  log:SetMaxLines(500)
  log:EnableMouseWheel(true)
  log:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  frame.log = log

  if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(frame) end
  frame:Hide()
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryDebugWindow")
  end
  return frame
end

function D:Add(msg)
  local f = EnsureFrame()
  -- Grey, fixed-width timestamp + a "|" separator ("||" renders one literal pipe).
  f.log:AddMessage(("|cff888888%s  ||  |r%s"):format(date("%H:%M:%S"), tostring(msg)))
end

function D:Show() EnsureFrame():Show() end
function D:Hide() if frame then frame:Hide() end end
function D:Toggle()
  local f = EnsureFrame()
  if f:IsShown() then f:Hide() else f:Show() end
end

-- Global debug sink. No-op (zero alloc) when debug is off; otherwise appends to the window.
function NS.Debug(fmt, ...)
  if not (NS.db and NS.db.global and NS.db.global.debug) then return end
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  D:Add(msg)
end
