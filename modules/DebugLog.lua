local addonName, NS = ...
NS.DebugLog = NS.DebugLog or {}
local D = NS.DebugLog
local frame
local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer (events-frames-taint-§8)

-- Plain-text mirror of the log (no colour codes), for the Copy window. Capped like the log.
D.buffer = D.buffer or {}
local MAX_BUFFER = 500

local STATUS_H = 16   -- height reserved at the window bottom for the line-counter status bar
local BAR_W    = 8    -- scrollbar track width

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
  frame:SetSize(700, 344)
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

  -- Left-aligned debug on/off toggle. Same flat look as Copy/Clear, but the resting colour
  -- reflects state (green ON / red OFF); clicking flips state through the shared SetEnabled seam.
  local toggleBtn = CreateFrame("Button", nil, titleBar)
  toggleBtn:SetSize(80, 18)
  toggleBtn:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
  local toggleFS = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  toggleFS:SetPoint("LEFT")
  toggleBtn:SetScript("OnEnter", function() toggleFS:SetTextColor(1, 0.82, 0) end)
  toggleBtn:SetScript("OnLeave", function() D:RefreshHeader() end)
  local function onToggleClick() D:SetEnabled(not (NS.State and NS.State.debug)) end
  toggleBtn:SetScript("OnClick", onToggleClick)
  frame.debugToggle = toggleFS
  frame.debugToggleBtn = toggleBtn
  D._toggleClickForTest = onToggleClick   -- test seam (mock stubs GetScript)

  local log = CreateFrame("ScrollingMessageFrame", nil, frame)
  log:SetPoint("TOPLEFT", 8, -(26 + 6))
  -- Right inset clears the scrollbar gutter; bottom inset clears the status bar (and keeps the
  -- newest line's descenders off the window border).
  log:SetPoint("BOTTOMRIGHT", -(BAR_W + 8), STATUS_H + 4)
  log:SetFont(NS.Constants.FONT_MONO, 10, "")
  log:SetJustifyH("LEFT")
  log:SetFading(false)
  log:SetMaxLines(MAX_BUFFER)
  log:EnableMouseWheel(true)
  log:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    D:UpdateScrollBar()   -- keep the thumb in step with wheel scrolling
  end)
  frame.log = log

  -- Thin flat scrollbar synced to the message frame's offset. A ScrollingMessageFrame has no
  -- native scrollbar (wheel-only), so a plain Slider drives its scroll offset. Always-shown to
  -- match the settings panel's inert-when-it-fits scrollbar (options-ui-§10). Vertical Slider
  -- convention: value 0 = thumb at top = oldest; value max = thumb at bottom = newest. The
  -- message-frame offset is inverted (0 = newest/bottom), so offset = maxOffset - value.
  local bar = CreateFrame("Slider", nil, frame)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(BAR_W)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(26 + 6))
  bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, STATUS_H + 4)
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  bar:SetObeyStepOnDrag(true)
  bar:SetValue(0)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(0.24, 0.24, 0.27, 0.30)   -- matches Browser SKIN.divider, dimmed
  local thumb = bar:CreateTexture(nil, "ARTWORK")
  thumb:SetColorTexture(0.5, 0.5, 0.55, 0.85)
  thumb:SetSize(BAR_W, 36)
  bar:SetThumbTexture(thumb)
  bar:SetScript("OnValueChanged", function(_, value)
    if frame._syncing then return end
    local l = frame.log
    if not (l.GetMaxScrollRange and l.SetScrollOffset) then return end
    local maxOffset = l:GetMaxScrollRange()
    if type(maxOffset) ~= "number" then return end
    l:SetScrollOffset(maxOffset - math.floor(value + 0.5))
  end)
  frame.scrollBar = bar

  -- Bottom status bar: a thin divider + a right-aligned "N / MAX lines" counter.
  local statusDivider = frame:CreateTexture(nil, "ARTWORK")
  statusDivider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, STATUS_H)
  statusDivider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, STATUS_H)
  statusDivider:SetHeight(1)
  statusDivider:SetColorTexture(0.24, 0.24, 0.27, 0.85)  -- matches Browser SKIN.divider

  local lineCount = frame:CreateFontString(nil, "OVERLAY")
  lineCount:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 3)
  lineCount:SetFont(NS.Constants.FONT_MONO, 10, "")
  lineCount:SetJustifyH("RIGHT")
  lineCount:SetTextColor(0.6, 0.6, 0.62)
  frame.lineCount = lineCount

  if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(frame) end

  -- State no longer follows visibility; just keep the header label accurate when shown.
  frame:HookScript("OnShow", function() D:RefreshHeader() end)

  D:RefreshHeader()

  frame:Hide()
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryDebugWindow")
  end

  -- Initial scrollbar/counter sync last, so a surprise from the frame API can never abort the
  -- header/ESC/hide wiring above.
  D:UpdateScrollBar()
  D:UpdateStatus()
  return frame
end

-- Pure plain-text line formatter (no frames, no colour codes): "<ts> | [<tag>] <msg>".
-- This is what the Copy buffer mirrors — clean text with the tag rendered verbatim.
function D.FormatPlain(ts, tag, msg)
  return ("%s | [%s] %s"):format(tostring(ts), tostring(tag or ""), tostring(msg))
end

-- Pure colour-coded line formatter for the console view. The timestamp is muted steel-blue
-- (6f8faf) and the [tag] is muted tan/gold (c9a66b) — distinct but easy on a dark backdrop;
-- the "|" separator and the message stay in the frame's default colour (white). "||" renders
-- one literal pipe inside the colour-coded string.
function D.FormatColored(ts, tag, msg)
  return ("|cff6f8faf%s|r || |cffc9a66b[%s]|r %s"):format(
    tostring(ts), tostring(tag or ""), tostring(msg))
end

function D:Add(tag, msg)
  local f = EnsureFrame()
  local ts = date("%H:%M:%S")
  f.log:AddMessage(D.FormatColored(ts, tag, msg))
  -- Mirror a plain-text copy into the buffer (for the Copy window), capped like the log.
  D.buffer[#D.buffer + 1] = D.FormatPlain(ts, tag, msg)
  if #D.buffer > MAX_BUFFER then table.remove(D.buffer, 1) end
  D:UpdateScrollBar()
  D:UpdateStatus()
end

-- Sync the scrollbar thumb/range to the message frame's current offset. Uses the Lua
-- ScrollingMessageFrameMixin API (GetMaxScrollRange / GetScrollOffset), where offset 0 = bottom
-- (newest) and offset = maxRange = top (oldest). No-op until the frame exists; also a clean no-op
-- under the headless mock (whose stub methods return non-numbers — the type guard catches that).
function D:UpdateScrollBar()
  if not (frame and frame.log and frame.scrollBar) then return end
  local log, bar = frame.log, frame.scrollBar
  if not (log.GetMaxScrollRange and log.GetScrollOffset) then return end
  local maxOffset, off = log:GetMaxScrollRange(), log:GetScrollOffset()
  if type(maxOffset) ~= "number" or type(off) ~= "number" then return end
  frame._syncing = true   -- suppress the OnValueChanged → SetScrollOffset feedback loop
  bar:SetMinMaxValues(0, maxOffset)
  bar:SetValue(maxOffset - off)
  frame._syncing = false
  bar:EnableMouse(maxOffset > 0)   -- inert (but still shown) when everything fits
end

-- Update the bottom status bar's line counter. #D.buffer is the live line count (capped at
-- MAX_BUFFER, in lock-step with the log's SetMaxLines).
function D:UpdateStatus()
  if frame and frame.lineCount then
    frame.lineCount:SetText(("%d / %d lines"):format(#D.buffer, MAX_BUFFER))
  end
end

-- Clear both the visible log and the copy buffer.
function D:Clear()
  if frame and frame.log then frame.log:Clear() end
  wipe(D.buffer)
  D:UpdateScrollBar()
  D:UpdateStatus()
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

  local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -30)
  scroll:SetPoint("BOTTOMRIGHT", -28, 10)
  copyFrame.scroll = scroll

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFont(NS.Constants.FONT_MONO, 10, "")
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

-- Keep the settings panel's "Debug console" checkbox in step with the window's visibility. Direct
-- call (not a bus message — the closed bus carries only the three Ka0s_LootHistory_* messages); a
-- no-op until the panel is built. Re-reads all panel widgets, which is cheap and read-only.
local function syncPanel()
  if NS.Panel and NS.Panel.Refresh then NS.Panel:Refresh() end
end

-- Window visibility (distinct from the NS.State.debug logging flag). False until the frame is built.
function D:IsShown() return frame ~= nil and frame:IsShown() and true or false end
function D:Show() EnsureFrame():Show(); syncPanel() end
function D:Hide() if frame then frame:Hide() end; syncPanel() end
function D:Toggle() if D:IsShown() then D:Hide() else D:Show() end end

-- Single seam for changing debug state. Slash command and header toggle both call this so the
-- chat message and header label stay consistent. Session-only: NS.State.debug resets on reload.
function D:SetEnabled(on)
  on = not not on
  NS.State.debug = on
  D:RefreshHeader()
  -- Colour-coded chat ack (debug-logging-§5): ON green (40ff40) / OFF red (ff4040), mirroring the
  -- title-bar "Debug: ON/OFF" toggle so the flag reads identically in chat and on the console header.
  print("debug logging " .. (on and "|cff40ff40ON|r" or "|cffff4040OFF|r"))
  -- Console line at BOTH transitions (debug-logging-§5) so the log itself records when capture
  -- started and stopped. Written through the raw append (D:Add), never the flag-gated NS.Debug sink:
  -- the disable line has to land AFTER the flag has flipped off, which the gated sink would swallow.
  D:Add("Debug", on and "logging enabled" or "logging disabled")
  if on then
    -- [Init] session summary immediately after the enable bracket. Emitted here on enable — NOT at
    -- login/OnEnable — because the flag is session-only and off at login, so a load-time summary
    -- would always be gated off and never render (debug-logging-§5/§8).
    D:Add("Init", NS.InitSummary())
  end
end

-- Updates the header toggle label to match NS.State.debug. Fully wired in the header task;
-- safe no-op until the toggle fontstring exists.
function D:RefreshHeader()
  if not (frame and frame.debugToggle) then return end
  local on = NS.State and NS.State.debug
  frame.debugToggle:SetText(on and "Debug: ON" or "Debug: OFF")
  if on then frame.debugToggle:SetTextColor(0.30, 0.85, 0.30)
  else frame.debugToggle:SetTextColor(0.90, 0.30, 0.30) end
end

-- Global debug sink. No-op (zero alloc) when debug is off; otherwise formats the line and appends
-- to the window. Every message arg is routed through NS.SafeToString BEFORE it reaches
-- string.format, so a combat-protected "secret" value (events-frames-taint-§8) logs as "<secret>"
-- instead of raising the format call — the classic combat crash. Because every arg arrives as a
-- string, the sink's format strings use %s for every placeholder (never %d/%f).
function NS.Debug(tag, fmt, ...)
  if not (NS.State and NS.State.debug) then return end
  local n = select("#", ...)
  local msg = fmt
  if n > 0 then
    local parts = {}
    for i = 1, n do parts[i] = NS.SafeToString((select(i, ...))) end
    msg = fmt:format(unpack(parts))
  end
  D:Add(tag, msg)
end
