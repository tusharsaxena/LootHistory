-- LibKa0s-DebugLog-1.0 — the console window: its frame, its title bar (the toggle, the Diagnostics
-- link, Copy, Clear and the close control), the log, its scrollbar and the status line, and the
-- skin it wears.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF DebugLog.lua ─────────────────────────────────
--
-- Because of `layout-§1`, as for DebugLogGates.lua. DebugLog.lua came into the 1000-1500 band at
-- minor 21 (1008 lines), and the disposition the band recorded named this seam and this trigger:
-- the next DebugLog minor that adds a window feature peels the window, `EnsureFrame`, the drag bar
-- and their chrome helpers, to a file paired on the shell's minor. Minor 22's window feature is the
-- skin owner (LK-09 of Ka0sAddonsCommonTasks docs/2026-10-25-SKINNING), so the window moved here
-- first, unchanged, and the owner was added here. It is NOT a major of its own: it is part of
-- `LibKa0s-DebugLog-1.0`, guarded with the same multi-file idiom, so a window from one vendored
-- copy can never pair with a shell from another without saying so.
--
-- ── THE SKIN OWNER (minor 1) ─────────────────────────────────────────────────────────────────
--
-- The console's owner is the descriptor's `addonName`, the folder its close, copy and clear marks
-- are already built from, and it counts only once that addon called LibKa0s-Skin-1.0's
-- `RegisterOwner` (asked through Core's `__SkinFacade` at build, resolved at call time: no floor on
-- the Skin major). A host that passed its own `skin` table or `applySkin` keeps owning the whole skin
-- job and is never skinned over. Every other console is the previous minor's paint, call for call:
-- the palette below is the constants it drew, and Ka0s Default's tokens are those same constants.
-- An owned console paints its window through the facade (`Core.ApplySkin(f, nil, owner)`, so
-- `S.Shell`), its scrollbar (`S.ScrollBar`) and its status rule (`S.Divider`), and every color the
-- title bar, the line counter and the log draw from the palette, refilled from the owner's tokens on
-- each of its skin switches; the visible log is rebuilt from the buffer in the new colors.
--
-- ── THE SCOPE SWITCHES (minor 2) ─────────────────────────────────────────────────────────────
--
-- An owned console draws every label of its title bar (the toggle, the Diagnostics link, and the
-- Copy and Clear words where the art is missing) in its skin's body face through the facade
-- (`S.Font`, a recorded paint), so a skin switch reaches them and the owner's "Ignore fonts" gives
-- each its template back, live. Under Ka0s Default that face is Oxanium where the template drew Friz
-- Quadrata (decision D-13). The link is measured in the face it wears, again after each switch. The
-- log and the line counter keep the descriptor's face, mono by contract. The console is a window,
-- not the settings panel, so "Ignore settings panel" leaves it skinned (D-01). Its resize grip takes
-- the owner too (Core minor 14's `opts.owner`). LK-06b of Ka0sAddonsCommonTasks
-- docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS, ruling R-5.
--
-- Depends on LibStub, on the DebugLog shell and on LibKa0s-Core-1.0, and on no addon framework. A
-- payload without this file loads whole and its consoles simply never build a window: `D:Show`
-- does nothing and logging still lands in the buffer, as on a client with no UI.

local lib = LibStub and LibStub("LibKa0s-DebugLog-1.0", true)
if not lib then return end
-- Core is guaranteed present here: DebugLog.lua refuses to register without it.
local core = LibStub("LibKa0s-Core-1.0", true)

local WINDOW_MINOR = 2
-- Paired on the SHELL's minor as well as this file's own, as DebugLogGates.lua is: a window built
-- by one vendored copy for a shell from another would call back into members that shell may not
-- have, and nothing would say the two came from different copies.
if lib.__windowMinor and lib.__windowMinor >= WINDOW_MINOR
  and lib.__windowShellMinor == lib.MINOR then return end
lib.__windowMinor      = WINDOW_MINOR
lib.__windowShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.DebugLogWindow = WINDOW_MINOR

-- Minor 21: re-raise any shown StaticPopup when the console shows, so a confirmation shown first
-- stays on top of it (XS-08). Read at call time and guarded, not a Core floor raise: an older Core
-- without the helper raises nothing. The copy window is not toplevel and does not call this (XS-12).
local function raisePopups()
  if type(core.RaiseStaticPopups) == "function" then core.RaiseStaticPopups() end
end

-- ── window furniture ───────────────────────────────────────────────────────────────────────

local TITLE_H  = 26      -- drag bar height
local STATUS_H = 16      -- bottom status bar height
local BAR_W    = 8       -- scrollbar gutter width
-- The line counter's right inset. Core.MakeResizable's grip is 16 px square at 1 px in from the
-- bottom-right corner and ten levels above the console, so a counter at the old 10 px drew its last
-- digits under the grip's art; 22 clears the grip's 17 px with a 5 px gap.
local COUNT_INSET = 22

-- Title-bar arithmetic. PAD is the one gap between every control and its neighbor; CLOSE_W is what
-- Core's own close button measures, and is the fallback when a host's button has no width yet.
local PAD      = 6
local CLOSE_W  = 18
local CLEAR_W  = 42
local COPY_W   = 40

-- What an ICON control measures, when the art is there. Square, and the same 18 the close button
-- has always been, so all three title-bar controls are one size and one rhythm -- where the text
-- buttons were 42 and 40 wide and only lined up by arithmetic.
local ICON_W   = 18
local ICON_ART = 12

-- The console's default size, which is the size it has always opened at (debug-logging-§1). From
-- minor 15 it is resizable from a bottom-right grip (Core.MakeResizable), and this is still the
-- size every session starts at: the size the player drags to lives on the frame for the session
-- and is never saved.
local CONSOLE_W, CONSOLE_H = 700, 344

-- The header toggle's slot, at the bar's left edge. Named because the minimum width reads it.
local TOGGLE_X, TOGGLE_W = 8, 80

-- The Diagnostics link (minor 16): its gap after the toggle's label, and its orange at rest and
-- under the pointer, so it reads as an action beside a state word. Plain text, like that label.
local DIAG_GAP  = 10
local DIAG_REST = { 1, 0.5, 0 }
local DIAG_HOT  = { 1, 0.72, 0.28 }

-- Gray at rest, gold under the pointer -- what the text labels have done since minor 1, kept so the
-- title bar does not change temperature just because its controls changed shape.
local REST = { 0.7, 0.7, 0.72 }
local HOT  = { 1, 0.82, 0 }

-- The fewest log lines the console may be sized down to show, and what a character of the title is
-- taken to measure when the font string cannot say (before layout, or headless).
local MIN_LINES    = 4
local TITLE_CHAR_W = 7

-- ── the palette ────────────────────────────────────────────────────────────────────────────
--
-- Every color the console draws outside the skin's window primitives, as `name = { token,
-- constant }`. The constant is what the console has drawn since the minor that added it, and what
-- every console without a registered owner draws; Ka0s Default's token is the same value: REST and
-- HOT for the text and icon controls, the Diagnostics link's two oranges, the toggle's green ON and
-- red OFF, the status rule, the line counter, and the log line's stamp, tag and message.
local PALETTE = {
  rest    = { "text.muted",   REST },
  icon    = { "icon.tint",    REST },
  hot     = { "text.accent",  HOT },
  diag    = { "text.link",    DIAG_REST },
  diagHot = { "text.linkHot", DIAG_HOT },
  on      = { "sem.on",       { 0.30, 0.85, 0.30 } },
  off     = { "sem.off",      { 0.90, 0.30, 0.30 } },
  rule    = { "divider",      { 0.24, 0.24, 0.27, 0.85 } },
  count   = { "log.count",    { 0.6, 0.6, 0.62 } },
  ts      = { "log.ts",       { 0x6f / 255, 0x8f / 255, 0xaf / 255 } },
  tag     = { "log.tag",      { 0xc9 / 255, 0xa6 / 255, 0x6b / 255 } },
  text    = { "log.text",     { 1, 1, 1 } },
}

-- The constants, shared by every console without an owner. Never written to.
local DEFAULT = {}
for name, spec in pairs(PALETTE) do DEFAULT[name] = spec[2] end

--- Refill `pal` from the facade's tokens, each falling back to its constant.
local function fillPalette(pal, S)
  for name, spec in pairs(PALETTE) do
    local c = S.Token(spec[1])
    pal[name] = type(c) == "table" and c or spec[2]
  end
  return pal
end

local function setText(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

--- An owned console's label in its skin's body face (minor 2): the facade's `Font`, which records
--- the paint, so a switch and "Ignore fonts" reach it. `S` nil (no owner) touches nothing.
local function skinFont(S, fs)
  if S then S.Font(fs) end
end

-- Small flat text button for the title bar (Copy / Clear). The close button comes from Core; this
-- one has no other consumer yet, so it stays private until a second module wants it.
local function makeTextButton(parent, text, width, onClick, pal, S)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 18)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  skinFont(S, fs)
  fs:SetPoint("CENTER")
  fs:SetText(text)
  setText(fs, pal.rest)
  b:SetScript("OnEnter", function() setText(fs, pal.hot) end)
  b:SetScript("OnLeave", function() setText(fs, pal.rest) end)
  b:SetScript("OnClick", onClick)
  b.label = fs
  return b
end

--- The same control drawn from `LibKa0s-Media-1.0`'s art, or nil when there is no art to draw.
---
--- NIL IS THE WHOLE INTERFACE. The caller falls back to the text button above, which is what a host
--- that never passes `addonName` gets and what a host without the Media module gets. A host whose
--- copy lacks the art gets a BLANK control: Media.Icon answers a path and never checks the file
--- exists, so `close, copy, clear` are the host's to declare on its `LibKa0s icons:` line.
---
--- NO TOOLTIP, AND NO LABEL TO PUT IN ONE. Minor 9 took a label and showed it under the control,
--- which put it on top of the first line of the log -- the thing the window exists to show -- every
--- time the pointer crossed the title bar. Anchoring it elsewhere trades one overlap for another on
--- a window that is 700px of text, and the two marks sit beside a close button that has never needed
--- one. The word still exists where it is still drawn: the text-button fallback in the caller.
local function makeIconButton(parent, addonName, icon, onClick, pal)
  if not addonName then return nil end
  local media = LibStub and LibStub("LibKa0s-Media-1.0", true)
  local path = media and media.Icon and media.Icon(addonName, icon)
  if not path then return nil end

  local b = CreateFrame("Button", nil, parent)
  b:SetSize(ICON_W, ICON_W)
  local tex = b:CreateTexture(nil, "OVERLAY")
  tex:SetPoint("CENTER")
  tex:SetSize(ICON_ART, ICON_ART)
  tex:SetTexture(path)
  tex:SetVertexColor(pal.icon[1], pal.icon[2], pal.icon[3])
  b.icon = tex

  b:SetScript("OnEnter", function() tex:SetVertexColor(pal.hot[1], pal.hot[2], pal.hot[3]) end)
  b:SetScript("OnLeave", function() tex:SetVertexColor(pal.icon[1], pal.icon[2], pal.icon[3]) end)
  b:SetScript("OnClick", onClick)
  return b
end

--- Build and place the three title-bar controls, and answer them with the offsets they landed on.
---
--- LIFTED OUT OF `EnsureFrame`, and not for tidiness: adding the icon path took that function to
--- CCN 16, one over the release gate's ceiling of 15 (`automated-tests-§3`). The decisions are all
--- about this one strip -- which shape each control takes, how wide the close button actually is --
--- so this is where they belong anyway, and `EnsureFrame` goes back to assembling a window.
---
--- @param titleBar table
--- @param spec table  { addonName, close = f(parent,onClick,addonName), onClose, onClear, onCopy,
---                      clearLabel, copyLabel, pal, S (the owner's facade or nil, minor 2) }
--- @return table close, table clear, table copy, table offsets
local function buildTitleControls(titleBar, spec)
  -- Anchored to the bar's right edge by absolute offset rather than to each other, because a
  -- close-button factory answers nil where CreateFrame is unavailable and a chain anchored through
  -- it would break. The offsets reproduce that chain exactly, and they are DERIVED rather than
  -- hard-coded, which matters as soon as a host supplies a wider button.
  local close = spec.close(titleBar, spec.onClose, spec.addonName)
  if close then close:SetPoint("RIGHT", titleBar, "RIGHT", -PAD, 0) end

  -- A frame answers 0 from GetWidth before its first layout pass, and a headless stub answers 0
  -- forever, so anything not positive falls back to the size Core's own button is.
  local closeW = CLOSE_W
  if close and type(close.GetWidth) == "function" then
    local w = close:GetWidth()
    if type(w) == "number" and w > 0 then closeW = w end
  end

  -- ICONS ARE NARROWER THAN WORDS. Each control is built as art first and falls back to its label,
  -- and the offsets are derived from what was ACTUALLY built -- so the three end up one size and one
  -- pitch where the art is there, and exactly where they were at minor 8 where it is not.
  local clear = makeIconButton(titleBar, spec.addonName, "clear", spec.onClear, spec.pal)
  local copy  = makeIconButton(titleBar, spec.addonName, "copy", spec.onCopy, spec.pal)
  -- Only CLEAR's width feeds an offset. Copy is the leftmost control and nothing is placed to the
  -- left of it, so its own width has never entered the arithmetic -- it is a size, not a measurement.
  local clearW = CLEAR_W
  if clear then
    clearW = ICON_W
  else
    clear = makeTextButton(titleBar, spec.clearLabel, clearW, spec.onClear, spec.pal, spec.S)
  end
  copy = copy or makeTextButton(titleBar, spec.copyLabel, COPY_W, spec.onCopy, spec.pal, spec.S)

  local clearRight = -PAD - closeW - PAD
  local copyRight  = clearRight - clearW - PAD
  clear:SetPoint("RIGHT", titleBar, "RIGHT", clearRight, 0)
  copy:SetPoint("RIGHT", titleBar, "RIGHT", copyRight, 0)

  return close, clear, copy, { close = -PAD, clear = clearRight, copy = copyRight }
end

--- What font string `fs` measures holding `text` (set on it): its string width when the client can
--- say, else TITLE_CHAR_W per byte (before layout, or headless).
local function textWidth(fs, text, keep)
  if not keep then fs:SetText(text) end
  local w = fs.GetStringWidth and fs:GetStringWidth()
  if type(w) ~= "number" or w <= 0 then w = string.len(text) * TITLE_CHAR_W end
  return w
end

--- The Diagnostics link, drawn only when the instance has the report, and how far its right edge
--- reaches from the bar's left (the WIDER toggle word's case); nil and 0 without the report. Its
--- click is what `/<prefix> diagnostics` runs, D:RunDiagnostics(), which turns logging on. ANCHORED
--- TO THE LABEL'S FONT STRING, not the toggle's 80-wide button, so the gap holds after either word;
--- a level above that button, which runs on under it. An owned link wears the skin's face before it
--- is measured (minor 2).
local function buildDiagnosticsLink(titleBar, toggleBtn, toggleFS, D, pal, S)
  if type(D.RunDiagnostics) ~= "function" then return nil, 0 end
  local labelW = math.max(textWidth(toggleFS, D:Text("DEBUG_ON")),
    textWidth(toggleFS, D:Text("DEBUG_OFF")))
  local b = CreateFrame("Button", nil, titleBar)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  skinFont(S, fs)
  fs:SetPoint("LEFT")
  local w = textWidth(fs, D:Text("DIAGNOSTICS"))
  b:SetSize(w, 18)
  b:SetPoint("LEFT", toggleFS, "RIGHT", DIAG_GAP, 0)
  local level = toggleBtn.GetFrameLevel and toggleBtn:GetFrameLevel()
  if type(level) == "number" then b:SetFrameLevel(level + 1) end
  setText(fs, pal.diag)
  b:SetScript("OnEnter", function() setText(fs, pal.diagHot) end)
  b:SetScript("OnLeave", function() setText(fs, pal.diag) end)
  b:SetScript("OnClick", function() D:RunDiagnostics() end)
  b.label = fs
  return b, TOGGLE_X + labelW + DIAG_GAP + w
end

--- How narrow the console may go: every title-bar control and the centered title still fit, with
--- PAD between the title and the wider of the two control groups. The title is centered, so it is
--- the WIDER side that sets the margin on both. Never above the default, so a long title cannot
--- leave the window smaller than its own minimum on the day it is built. `linkReach` is the
--- Diagnostics link's right edge from the bar's left (0 without the link, minor 16).
local function consoleMinWidth(offsets, copyBtn, title, titleText, linkReach)
  local copyW = (type(copyBtn) == "table" and type(copyBtn.icon) == "table") and ICON_W or COPY_W
  local right = -offsets.copy + copyW
  local left = math.max(TOGGLE_X + TOGGLE_W, linkReach)
  local titleW = textWidth(title, titleText, true)
  local w = 2 * (math.max(left, right) + PAD) + titleW
  return math.min(math.ceil(w), CONSOLE_W)
end

--- How short: the title bar, the status bar and MIN_LINES lines of the log between them.
local function consoleMinHeight(fontSize)
  return TITLE_H + 6 + MIN_LINES * (fontSize + 2) + STATUS_H + 4
end

local function escClose(name)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
end

local function dragBar(parent, height)
  local bar = CreateFrame("Frame", nil, parent)
  -- Inset by one pixel on both axes so the bar sits inside the backdrop's border rather than
  -- overlapping its edge.
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(height)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() parent:StartMoving() end)
  bar:SetScript("OnDragStop", function() parent:StopMovingOrSizing() end)
  return bar
end

-- ── the owned log line ─────────────────────────────────────────────────────────────────────

local function hex(c)
  local function byte(v) return math.floor(v * 255 + 0.5) end
  return ("%02x%02x%02x"):format(byte(c[1]), byte(c[2]), byte(c[3]))
end

--- An owned console's console line: the shell's FormatColored with the palette's stamp and tag,
--- and the message in its text color (the message frame's AddMessage color). Answers text, r, g, b.
local function ownedLine(pal)
  return function(ts, tag, msg)
    local text = ("|cff%s%s|r || |cff%s[%s]|r %s"):format(hex(pal.ts), tostring(ts), hex(pal.tag),
      tostring(tag or ""), tostring(msg))
    return text, pal.text[1], pal.text[2], pal.text[3]
  end
end

--- Put the newest MAX_BUFFER lines of the buffer back into the log in the palette's colors: a skin
--- switch recolors what is already on screen, which a message frame cannot do in place. The buffer
--- holds FormatPlain's "<ts> | [<tag>] <msg>"; a line that does not read that way lands whole.
local function rebuildLog(f, D)
  local log, line = f.log, f.__logLine
  if not (log and line) then return end
  log:Clear()
  local buf = D.buffer
  local first = math.max(1, #buf - lib.MAX_BUFFER + 1)
  for i = first, #buf do
    local ts, tag, msg = buf[i]:match("^(.-) | %[(.-)%] (.*)$")
    if ts then
      log:AddMessage(line(ts, tag, msg))
    else
      local _, r, g, b = line("", "", "")
      log:AddMessage(buf[i], r, g, b)
    end
  end
end

-- ── the window ─────────────────────────────────────────────────────────────────────────────

--- The log, its scrollbar and the status line under them.
local function buildBody(f, D, ctx, pal)
  local log = CreateFrame("ScrollingMessageFrame", nil, f)
  log:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(TITLE_H + 6))
  log:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(BAR_W + 8), STATUS_H + 4)
  log:SetFont(ctx.d.font, ctx.fontSize, "")
  log:SetJustifyH("LEFT")
  log:SetFading(false)
  log:SetMaxLines(lib.MAX_BUFFER)
  log:EnableMouseWheel(true)
  log:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    D:UpdateScrollBar()
  end)
  f.log = log

  -- The slider runs top-to-bottom while a message frame's scroll offset runs bottom-to-top, so
  -- the two are related by `maxOffset - value`. Both directions of that mapping are guarded on
  -- the methods existing AND on the result being a number, which is also what makes the whole
  -- sync a clean no-op under a headless mock whose stubs answer with the frame itself.
  local bar = CreateFrame("Slider", nil, f)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(BAR_W)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -(TITLE_H + 6))
  bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, STATUS_H + 4)
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  bar:SetObeyStepOnDrag(true)
  bar:SetValue(0)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(0.24, 0.24, 0.27, 0.30)
  local thumb = bar:CreateTexture(nil, "ARTWORK")
  thumb:SetColorTexture(0.5, 0.5, 0.55, 0.85)
  thumb:SetSize(BAR_W, 36)
  bar:SetThumbTexture(thumb)
  bar:SetScript("OnValueChanged", function(_, value)
    if f._syncing then return end
    local l = f.log
    if not (l.GetMaxScrollRange and l.SetScrollOffset) then return end
    local maxOffset = l:GetMaxScrollRange()
    if type(maxOffset) ~= "number" then return end
    l:SetScrollOffset(maxOffset - math.floor(value + 0.5))
  end)
  f.scrollBar = bar
  f.__track, f.__thumb = track, thumb

  local rule = pal.rule
  local statusDivider = f:CreateTexture(nil, "ARTWORK")
  statusDivider:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, STATUS_H)
  statusDivider:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, STATUS_H)
  statusDivider:SetHeight(1)
  statusDivider:SetColorTexture(rule[1], rule[2], rule[3], rule[4])
  f.statusDivider = statusDivider

  local lineCount = f:CreateFontString(nil, "OVERLAY")
  lineCount:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -COUNT_INSET, 3)
  lineCount:SetFont(ctx.d.font, ctx.fontSize, "")
  lineCount:SetJustifyH("RIGHT")
  setText(lineCount, pal.count)
  f.lineCount = lineCount
end

--- The title bar: the drag bar, the centered title, the divider under it, Copy | Clear | Close on the
--- right, the toggle and the Diagnostics link on the left. Answers what the minimum width reads.
local function buildTitleBar(f, D, ctx, pal, S)
  local d = ctx.d
  local titleBar = dragBar(f, TITLE_H)

  local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("CENTER")
  -- Recorded as well as set. A font string is write-only through the frame API — there is no
  -- reading it back — so the composed title is the one thing about this window a host's test
  -- could not otherwise see, and composing it is exactly what the library adds to `d.title`.
  f.titleText = d.title .. D:Text("TITLE_SUFFIX")
  title:SetText(f.titleText)
  f.title = title

  local divider = f:CreateTexture(nil, "ARTWORK")
  divider:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
  divider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  divider:SetHeight(1)
  -- Colored from the skin rather than hardcoded black. `applySkin` runs at the end of the build
  -- and tints it again, so this value only shows on a host whose own applySkin ignores the divider
  -- — and black under a gray-inner-bordered window is exactly the mismatch it exists to remove.
  local skin = ctx.skin
  local dc = type(skin.divider) == "table" and skin.divider or { 0, 0, 0, 1 }
  divider:SetColorTexture(dc[1], dc[2], dc[3], dc[4])
  f.divider = divider

  -- The three title-bar controls read Copy | Clear | Close, left to right. The offsets are DERIVED
  -- from the close button's width rather than hard-coded, which matters as soon as a host supplies
  -- its own: Core's is 18 wide, so Clear lands at -30 and Copy at -78, but a 24-wide button would
  -- have put Clear's right edge (-30) precisely on that button's left edge.
  local _, clearBtn, copyBtn, offsets = buildTitleControls(titleBar, {
    addonName  = d.addonName,
    close      = ctx.makeCloseButton,
    onClose    = function() D:Hide() end,
    onClear    = function() D:Clear() end,
    onCopy     = function() D:ShowCopy() end,
    clearLabel = D:Text("CLEAR"),
    copyLabel  = D:Text("COPY"),
    pal        = pal,
    S          = S,
  })
  -- Recorded for the same reason `titleText` is: an anchor cannot be read back through the frame
  -- API, so these are the only handle a host's own test has on what its close button did to the
  -- layout, and on which of the two shapes the controls took.
  f.titleBarOffsets = offsets
  f.clearButton, f.copyButton = clearBtn, copyBtn

  -- The header toggle. OnLeave restores the resting color by re-running RefreshHeader, so the
  -- label's color is always the flag's color rather than whatever the last hover left behind.
  local toggleBtn = CreateFrame("Button", nil, titleBar)
  toggleBtn:SetSize(TOGGLE_W, 18)
  toggleBtn:SetPoint("LEFT", titleBar, "LEFT", TOGGLE_X, 0)
  local toggleFS = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  skinFont(S, toggleFS)
  toggleFS:SetPoint("LEFT")
  toggleBtn:SetScript("OnEnter", function() setText(toggleFS, pal.hot) end)
  toggleBtn:SetScript("OnLeave", function() D:RefreshHeader() end)
  local function onToggleClick() D:SetEnabled(not D:IsEnabled()) end
  toggleBtn:SetScript("OnClick", onToggleClick)
  f.debugToggle = toggleFS
  f.debugToggleBtn = toggleBtn
  -- The Diagnostics link beside it (minor 16), recorded as clearButton and copyButton are.
  local linkReach
  f.diagnosticsButton, linkReach = buildDiagnosticsLink(titleBar, toggleBtn, toggleFS, D, pal, S)
  D._toggleClickForTest = onToggleClick   -- test seam (a headless mock stubs GetScript)
  return title, offsets, copyBtn, linkReach
end

--- Recolor what the palette drew, after it was refilled for a skin switch. The window, the
--- scrollbar and the status rule are the facade's (replayed by the Skin major before this runs).
local function recolor(f, D, pal)
  for _, b in ipairs({ f.clearButton, f.copyButton }) do
    if b.icon then
      b.icon:SetVertexColor(pal.icon[1], pal.icon[2], pal.icon[3])
    elseif b.label then
      setText(b.label, pal.rest)
    end
  end
  local link = f.diagnosticsButton
  if link then
    setText(link.label, pal.diag)
    -- Minor 2: measured again in the face the switch left it (a skin's, or the template's under
    -- "Ignore fonts"), so the link's button stays the width of its word.
    link:SetWidth(textWidth(link.label, D:Text("DIAGNOSTICS")))
  end
  setText(f.lineCount, pal.count)
  D:RefreshHeader()
  rebuildLog(f, D)
  D:UpdateScrollBar()
end

--- A registered owner's console: its scrollbar and status rule through the facade, its log line in
--- the palette's colors, and a refill and recolor on each of the owner's skin switches. The window
--- itself is painted by `ctx.applySkin` (Core.ApplySkin with the owner).
local function adopt(f, D, S, pal)
  f.__logLine = ownedLine(pal)
  S.ScrollBar(f.scrollBar, { track = f.__track, thumb = f.__thumb })
  S.Divider(f.statusDivider)
  S.OnLooksChanged(function()
    fillPalette(pal, S)
    recolor(f, D, pal)
  end)
end

--- Build the console window for one instance. Called by the shell's EnsureFrame, which owns the
--- handle: `ctx.adopt(frame)` hands it over the moment the frame exists, so a frame-API surprise
--- later in the build still leaves the shell holding the window it hid and Esc-wired, and a second
--- call never builds a second one.
---
--- @param D table    the instance (its Text, Hide, Clear, ShowCopy, SetEnabled, IsEnabled,
---                   RefreshHeader, UpdateScrollBar, UpdateStatus, buffer and RunDiagnostics)
--- @param ctx table  { d, fontSize, skin, applySkin, makeCloseButton, facade = fn() -> S or nil,
---                     adopt = fn(frame), onVisibilityChanged = fn() }
--- @return table frame
function lib.__buildConsole(D, ctx)
  local d = ctx.d
  local S = ctx.facade()
  local pal = S and fillPalette({}, S) or DEFAULT

  local name = d.name .. "DebugWindow"
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  ctx.adopt(f)
  f.__palette = pal
  f:SetSize(CONSOLE_W, CONSOLE_H)
  f:SetPoint("CENTER", 220, -80)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)

  local title, offsets, copyBtn, linkReach = buildTitleBar(f, D, ctx, pal, S)
  -- The other test seam. A headless mock's Show()/Hide() track visibility without firing the
  -- OnShow/OnHide scripts, so the only way to exercise the visibility callback below is to drive
  -- the handler directly. Hooking the frame rather than calling the host from Show()/Hide() is
  -- deliberate: Esc and the close button both hide the window without going through either.
  D._frameForTest = f
  buildBody(f, D, ctx, pal)

  f:HookScript("OnShow", function() D:RefreshHeader(); raisePopups(); ctx.onVisibilityChanged() end)
  f:HookScript("OnHide", ctx.onVisibilityChanged)
  D:RefreshHeader()

  f:Hide()
  -- Esc closes it. Hiding is non-destructive, so this is safe to wire.
  escClose(name)

  -- Everything below is deliberately after the Hide and the Esc wiring. A frame-API surprise in
  -- the skin or the scroll sync must not abort them and leave a visible window nobody can close —
  -- and the shell already holds the frame, so EnsureFrame would never try again.
  ctx.applySkin(f)
  if S then adopt(f, D, S, pal) end
  -- Resizable from minor 15, when the Core under it has the grip (Core minor 9). Resolved through
  -- the table at call time and GUARDED rather than floored: an older Core leaves this exactly the
  -- fixed 700 x 344 window it was. The message frame, the scrollbar and the status line are
  -- anchored to the window, so they follow it on their own; what does not is the scrollbar's range
  -- and the line counter, which the relayout resyncs. The buffer and the scroll position are not
  -- touched.
  if type(core.MakeResizable) == "function" then
    core.MakeResizable(f, {
      minWidth  = consoleMinWidth(offsets, copyBtn, title, f.titleText, linkReach),
      minHeight = consoleMinHeight(ctx.fontSize),
      onResize  = function() D:UpdateScrollBar(); D:UpdateStatus() end,
      -- Minor 2: the grip wears the console's skin (Core minor 14; an older Core ignores the key).
      owner     = S and d.addonName or nil,
    })
  end
  D:UpdateScrollBar()
  D:UpdateStatus()
  return f
end
