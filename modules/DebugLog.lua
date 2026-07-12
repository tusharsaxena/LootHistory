local addonName, NS = ...
NS.DebugLog = NS.DebugLog or {}
local D = NS.DebugLog
local frame

-- Plain-text mirror of the log (no colour codes), for the Copy window. Capped like the log.
D.buffer = D.buffer or {}
local MAX_BUFFER = 500

-- Small flat text button for the title bar (Copy / Clear).
local function makeTextButton(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 18)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("CENTER")
  fs:SetText(text)
  fs:SetTextColor(0.7, 0.7, 0.72)
  b:SetScript("OnEnter", function() fs:SetTextColor(1, 0.82, 0) end)
  b:SetScript("OnLeave", function() fs:SetTextColor(0.7, 0.7, 0.72) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- A standalone debug console styled like the browser window. Debug output (NS.Debug) prints
-- here instead of the chat frame.
local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "LootHistoryDebugWindow", UIParent, "BackdropTemplate")
  frame:SetSize(560, 344)
  frame:SetPoint("CENTER", 220, -80)
  frame:SetFrameStrata("DIALOG")  -- above the History window (HIGH) so it's never hidden behind it
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

  -- ElvUI-style thin × close glyph (class-coloured on hover); shared with the browser window.
  local close
  if NS.Browser and NS.Browser.MakeCloseButton then
    close = NS.Browser:MakeCloseButton(titleBar, function() D:Hide() end)
  else
    close = CreateFrame("Button", nil, titleBar)
    close:SetScript("OnClick", function() D:Hide() end)
  end
  close:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)  -- vertical centre, aligned with the title

  local clear = makeTextButton(titleBar, "Clear", 42, function() D:Clear() end)
  clear:SetPoint("RIGHT", close, "LEFT", -6, 0)

  local copy = makeTextButton(titleBar, "Copy", 40, function() D:ShowCopy() end)
  copy:SetPoint("RIGHT", clear, "LEFT", -6, 0)

  local log = CreateFrame("ScrollingMessageFrame", nil, frame)
  log:SetPoint("TOPLEFT", 8, -(26 + 6))
  -- Bottom inset raised so the newest line's descenders clear the window border (not clipped).
  log:SetPoint("BOTTOMRIGHT", -8, 14)
  log:SetFont(NS.Constants.FONT_MONO, 12, "")
  log:SetJustifyH("LEFT")
  log:SetFading(false)
  log:SetMaxLines(500)
  log:EnableMouseWheel(true)
  log:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  frame.log = log

  if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(frame) end

  -- Debug state tracks window visibility (session-only): showing the console enables logging;
  -- closing it (X button or ESC via UISpecialFrames) disables logging. Reset every reload.
  frame:HookScript("OnShow", function() NS.State.debug = true end)
  frame:HookScript("OnHide", function() NS.State.debug = false end)

  frame:Hide()
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryDebugWindow")
  end
  return frame
end

-- Pure line formatter (no frames): "<ts>  |  [<tag>] <msg>". The tag is left-justified and
-- padded/truncated to a fixed 10 chars INSIDE the brackets so the closing ] and all content align.
function D.FormatPlain(ts, tag, msg)
  return ("%s  |  [%-10.10s] %s"):format(tostring(ts), tostring(tag or ""), tostring(msg))
end

function D:Add(tag, msg)
  local f = EnsureFrame()
  local ts = date("%H:%M:%S")
  -- Grey the timestamp / separator / bracketed tag; content in the default colour.
  -- "||" renders one literal pipe inside a colour-coded segment.
  f.log:AddMessage(("|cff888888%s  ||  [%-10.10s]|r %s"):format(ts, tostring(tag or ""), tostring(msg)))
  -- Mirror a plain-text copy into the buffer (for the Copy window), capped like the log.
  D.buffer[#D.buffer + 1] = D.FormatPlain(ts, tag, msg)
  if #D.buffer > MAX_BUFFER then table.remove(D.buffer, 1) end
end

-- Clear both the visible log and the copy buffer.
function D:Clear()
  if frame and frame.log then frame.log:Clear() end
  wipe(D.buffer)
end

-- ── Copy window ────────────────────────────────────────────────────────────────
-- A read-through EditBox holding the whole log as plain text; the user selects (auto-highlighted)
-- and copies with Ctrl+C.
local copyFrame
local function EnsureCopyFrame()
  if copyFrame then return copyFrame end

  copyFrame = CreateFrame("Frame", "LootHistoryDebugCopyWindow", UIParent, "BackdropTemplate")
  copyFrame:SetSize(560, 360)
  copyFrame:SetPoint("CENTER")
  copyFrame:SetFrameStrata("FULLSCREEN")  -- above the DIALOG-strata debug window
  copyFrame:EnableMouse(true)
  copyFrame:SetMovable(true)
  copyFrame:SetClampedToScreen(true)

  local tbar = CreateFrame("Frame", nil, copyFrame)
  tbar:SetPoint("TOPLEFT", 1, -1)
  tbar:SetPoint("TOPRIGHT", -1, -1)
  tbar:SetHeight(26)
  tbar:EnableMouse(true)
  tbar:RegisterForDrag("LeftButton")
  tbar:SetScript("OnDragStart", function() copyFrame:StartMoving() end)
  tbar:SetScript("OnDragStop", function() copyFrame:StopMovingOrSizing() end)
  local t = tbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("CENTER")
  t:SetText("Copy log \226\128\148 Ctrl+C, then Esc")
  copyFrame.title = t

  local cclose
  if NS.Browser and NS.Browser.MakeCloseButton then
    cclose = NS.Browser:MakeCloseButton(tbar, function() copyFrame:Hide() end)
  else
    cclose = CreateFrame("Button", nil, tbar)
    cclose:SetScript("OnClick", function() copyFrame:Hide() end)
  end
  cclose:SetPoint("RIGHT", tbar, "RIGHT", -6, 0)

  local scroll = CreateFrame("ScrollFrame", "LootHistoryDebugCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -30)
  scroll:SetPoint("BOTTOMRIGHT", -28, 10)
  copyFrame.scroll = scroll

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFont(NS.Constants.FONT_MONO, 12, "")
  edit:SetAutoFocus(false)
  edit:SetWidth(510)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); copyFrame:Hide() end)
  scroll:SetScrollChild(edit)
  copyFrame.edit = edit

  if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(copyFrame) end
  copyFrame:Hide()
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryDebugCopyWindow")
  end
  return copyFrame
end

function D:ShowCopy()
  local f = EnsureCopyFrame()
  f.edit:SetWidth(f.scroll:GetWidth() > 0 and f.scroll:GetWidth() or 510)
  f.edit:SetText(table.concat(D.buffer, "\n"))
  f.edit:SetCursorPosition(0)
  f:Show()
  f.edit:SetFocus()
  f.edit:HighlightText()
end

function D:Show() EnsureFrame():Show() end
function D:Hide() if frame then frame:Hide() end end
function D:Toggle()
  local f = EnsureFrame()
  if f:IsShown() then f:Hide() else f:Show() end
end

-- Global debug sink. No-op (zero alloc) when debug is off; otherwise appends to the window.
function NS.Debug(tag, fmt, ...)
  if not (NS.State and NS.State.debug) then return end
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  D:Add(tag, msg)
end
