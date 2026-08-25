-- LibKa0s-DebugLog-1.0 — the on-screen debug console: two formatters, a buffer, a window, and the
-- one seam that turns logging on and off.
--
-- The console is the most-duplicated thing in the collection: seven hand-transcribed copies of a
-- window the standard already specifies down to the hex codes, drifting one digit at a time. What
-- is genuinely per-addon is only the CONTENT of what gets logged — so everything else lives here
-- and the host supplies a descriptor.
--
-- Two decisions worth stating up front, because both look like details and neither is:
--
-- The enable flag is NOT stored here. The host owns it and the library reads and writes it through
-- an isEnabled/setEnabled pair. A library that kept its own copy would leave two truths about
-- whether logging is on, and the host's is the one its slash command and its settings panel read.
--
-- Every frame is per-instance and every frame global is derived from the descriptor's `name`. A
-- lib-level singleton would give two addons one console — and, worse, one UISpecialFrames
-- registration, so Esc would close whichever window registered last.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework.

-- Refuse rather than degrade when Core is missing or too old, so a broken vendored copy makes this
-- module absent and the host's own setup stub reports that honestly.
local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

-- Minor 12 draws its copy window with LibKa0s-Widgets-1.0's CopyWindow rather than its own fifth
-- copy of it, so Widgets is now a hard floor and not a nicety. Absent or older, this module is
-- ABSENT rather than half-wired: a console whose Copy button silently does nothing is worse than
-- no console, because the host's degradation stub never fires and nobody is told why. Both files
-- ship in one payload and whole-folder vendoring is mandatory, so a host that trips this floor has
-- a broken copy rather than an unlucky one.
local widgets = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
local NEEDS_WIDGETS = 7
if not widgets or (widgets.MINOR or 0) < NEEDS_WIDGETS then return end

local MAJOR, MINOR = "LibKa0s-DebugLog-1.0", 12
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Which version of each FILE in this major is actually live, so version skew is discoverable at
-- runtime rather than by reading source. See docs/releasing.md.
lib.MODULES = lib.MODULES or {}
lib.MODULES.DebugLog = MINOR

-- The console keeps the last N lines and no more. Fixed by the standard rather than by the host:
-- a console is a diagnostic window read by hand, and the cap and the message frame's own SetMaxLines
-- must move together or the visible log and the copied buffer diverge.
--
-- 1500 rather than the original 500 because the perf capture workflow pastes out of THIS buffer:
-- `perf report` prints its summary here and `perf dump` writes the whole JSON record as one line
-- (Perf.lua), so a long run overflowed 500 and lost its head with nothing saying so. The copy
-- window is a view of this array and caps nothing of its own, which is why raising this raises
-- both and why there is no second number.
lib.MAX_BUFFER = 1500

-- Re-exported rather than left for the host to reach into Core for. A host that draws a close
-- button on its own windows should get the same one its console wears, from one factory — three
-- copies of "the addon's close button" is exactly how two windows that should look identical drift.
--
-- A forwarder rather than `lib.MakeCloseButton = core.MakeCloseButton`, and the indirection is the
-- point: LibStub upgrades a major IN PLACE, so the `core` TABLE stashed above survives a Core minor
-- bump while the FUNCTION on it is replaced. A host carrying a newer Core.lua beside an unchanged
-- DebugLog.lua returns early at the guard and never re-snapshots — so a copied value would leave this
-- console drawing the older Core's button while lib.MODULES.Core truthfully reports the newer minor.
-- Resolving through the table at CALL time keeps the two halves honest, and costs one call frame
-- once per window built. Same shape PerfPanel.lua already uses.
--- THE THIRD ARGUMENT IS THE WHOLE POINT OF MINOR 10. This forwarder took two arguments and Core's
--- gained a third at Core minor 6 -- so minor 9 shipped a console whose copy and clear drew the
--- collection's art while its close, which goes through here, silently fell back to the
--- multiplication sign. A dropped argument is not a failure anything can report: Core simply saw no
--- addon name and did what it does without one.
function lib.MakeCloseButton(parent, onClick, addonName)
  return core.MakeCloseButton(parent, onClick, addonName)
end

-- ── strings ────────────────────────────────────────────────────────────────────────────────
--
-- Every user-visible string routes through here so a host can override any of them via the optional
-- `L` table, keyed identically. Tags are NOT here: `[Debug]` and `[Init]` are read by log-scrapers
-- and by the host's own tests, so they are structure rather than prose.

lib.STRINGS = {
  TITLE_SUFFIX     = " \226\128\148 Debug",
  DEBUG_ON         = "Debug: ON",
  DEBUG_OFF        = "Debug: OFF",
  ACK              = "debug logging %s",
  STATE_ON         = "ON",
  STATE_OFF        = "OFF",
  LOG_ENABLED      = "logging enabled",
  LOG_DISABLED     = "logging disabled",
  CLEAR            = "Clear",
  COPY             = "Copy",
  COPY_TITLE       = "Copy log \226\128\148 Ctrl+C, then Esc",
  LINES            = "%d / %d lines",
  CHECKBOX_LABEL   = "Debug console",
  CHECKBOX_TOOLTIP = "Show or hide the on-screen debug console window. Same as %s debug. " ..
    "Whether logging is on is separate \226\128\148 use %s debug on|off or the window's own toggle.",
  -- The same sentence for a host that declares no slash command. Two strings rather than one with
  -- an empty substitution, because "Same as  debug." reads as a bug and this text ships frozen.
  CHECKBOX_TOOLTIP_NO_SLASH = "Show or hide the on-screen debug console window. Whether logging " ..
    "is on is separate \226\128\148 use the window's own toggle.",
}

-- ── the formatters ─────────────────────────────────────────────────────────────────────────
--
-- Pure, stateless and lib-level: a host's tests call them directly, and there is nothing about a
-- rendered line that depends on which instance rendered it.

--- Plain-text line: "<ts> | [<tag>] <msg>". This is what the buffer holds and what the copy window
--- mirrors — clean text, tag rendered verbatim, no color codes to strip.
function lib.FormatPlain(ts, tag, msg)
  return ("%s | [%s] %s"):format(tostring(ts), tostring(tag or ""), tostring(msg))
end

--- Color-coded line for the console view: timestamp muted steel-blue (6f8faf), [tag] muted
--- tan/gold (c9a66b); the separator and the message stay default white. The `||` renders ONE
--- literal pipe inside a color-coded string — it is an escape, not a typo, and "simplifying" it
--- to a single pipe silently breaks the separator.
function lib.FormatColored(ts, tag, msg)
  return ("|cff6f8faf%s|r || |cffc9a66b[%s]|r %s"):format(
    tostring(ts), tostring(tag or ""), tostring(msg))
end

-- ── window furniture ───────────────────────────────────────────────────────────────────────

local TITLE_H  = 26      -- drag bar height
local STATUS_H = 16      -- bottom status bar height
local BAR_W    = 8       -- scrollbar gutter width
local DEFAULT_FONT_SIZE = 10

-- Title-bar arithmetic. PAD is the one gap between every control and its neighbour; CLOSE_W is what
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

-- Gray at rest, gold under the pointer -- what the text labels have done since minor 1, kept so the
-- title bar does not change temperature just because its controls changed shape.
local REST = { 0.7, 0.7, 0.72 }
local HOT  = { 1, 0.82, 0 }

-- Small flat text button for the title bar (Copy / Clear). The close button comes from Core; this
-- one has no other consumer yet, so it stays private until a second module wants it.
local function makeTextButton(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 18)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("CENTER")
  fs:SetText(text)
  fs:SetTextColor(REST[1], REST[2], REST[3])
  b:SetScript("OnEnter", function() fs:SetTextColor(HOT[1], HOT[2], HOT[3]) end)
  b:SetScript("OnLeave", function() fs:SetTextColor(REST[1], REST[2], REST[3]) end)
  b:SetScript("OnClick", onClick)
  return b
end

--- The same control drawn from `LibKa0s-Media-1.0`'s art, or nil when there is no art to draw.
---
--- NIL IS THE WHOLE INTERFACE. The caller falls back to the text button above, which is what a host
--- that never passes `addonName` gets, what a host without the Media module gets, and what an
--- install missing the art gets -- one path, exercised by every one of those cases, rather than a
--- degraded branch that only runs on installs nobody tests on.
---
--- NO TOOLTIP, AND NO LABEL TO PUT IN ONE. Minor 9 took a label and showed it under the control,
--- which put it on top of the first line of the log -- the thing the window exists to show -- every
--- time the pointer crossed the title bar. Anchoring it elsewhere trades one overlap for another on
--- a window that is 700px of text, and the two marks sit beside a close button that has never needed
--- one. The word still exists where it is still drawn: the text-button fallback in the caller.
local function makeIconButton(parent, addonName, icon, onClick)
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
  tex:SetVertexColor(REST[1], REST[2], REST[3])
  b.icon = tex

  b:SetScript("OnEnter", function() tex:SetVertexColor(HOT[1], HOT[2], HOT[3]) end)
  b:SetScript("OnLeave", function() tex:SetVertexColor(REST[1], REST[2], REST[3]) end)
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
---                      clearLabel, copyLabel }
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
  local clear = makeIconButton(titleBar, spec.addonName, "clear", spec.onClear)
  local copy  = makeIconButton(titleBar, spec.addonName, "copy", spec.onCopy)
  -- Only CLEAR's width feeds an offset. Copy is the leftmost control and nothing is placed to the
  -- left of it, so its own width has never entered the arithmetic -- it is a size, not a measurement.
  local clearW = CLEAR_W
  if clear then
    clearW = ICON_W
  else
    clear = makeTextButton(titleBar, spec.clearLabel, clearW, spec.onClear)
  end
  copy = copy or makeTextButton(titleBar, spec.copyLabel, COPY_W, spec.onCopy)

  local clearRight = -PAD - closeW - PAD
  local copyRight  = clearRight - clearW - PAD
  clear:SetPoint("RIGHT", titleBar, "RIGHT", clearRight, 0)
  copy:SetPoint("RIGHT", titleBar, "RIGHT", copyRight, 0)

  return close, clear, copy, { close = -PAD, clear = clearRight, copy = copyRight }
end

local function escClose(name)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
end

-- ── the instance ───────────────────────────────────────────────────────────────────────────

--- Build a console for one host.
---
--- Descriptor:
---   name        string    required. Seeds the frame globals `<name>DebugWindow`,
---                         `<name>DebugCopyWindow` and `<name>DebugCopyScroll`. Two hosts sharing a
---                         name would clobber each other's globals and each other's Esc handler.
---   title       string    required. The human title; the library appends its own " — Debug".
---   font        string    required. Path to the monospace font the console renders in. Required
---                         rather than defaulted because a nil here raises inside SetFont, halfway
---                         through building a window that is then un-closable.
---   fontSize    number    optional, default 10.
---   isEnabled   function  required. Reads the host's logging flag. The library never stores it.
---   setEnabled  function  required. Writes it. Always handed a real boolean.
---   print       function  optional. Where the chat acknowledgement goes. Defaults to the chat
---                         frame, untagged — a host that wants its own tag passes its printer,
---                         which is what every Ka0s addon does.
---   safeToString function optional, defaults to Core's. Every logged value goes through it, so a
---                         combat-protected value renders rather than raising downstream.
---   initSummary function  optional. Returns one line naming version/schema/profile. The library
---                         owns WHEN it is emitted; only the host can know what it says.
---   onVisibilityChanged function optional. Fired on both OnShow and OnHide, so a host can repaint
---                         a settings panel whose checkbox mirrors the console's visibility.
---   addonName   string    optional, minor 9. The host's own addon FOLDER name, from its first
---                         vararg. Given it, both windows draw this collection's own art -- the
---                         close, copy and clear icons out of `LibKa0s-Media-1.0` -- instead of a
---                         multiplication sign and two words. Omitted, everything looks exactly as
---                         it did at minor 8.
---
---                         IT IS A NAME AND NOT A BOOLEAN because a texture path is absolute from
---                         `Interface\AddOns\` and this library is vendored: there is no one path
---                         to it, and a copy cannot know which addon folder it was copied into.
---                         Do NOT pass `d.name` blindly -- that field seeds frame globals and only
---                         happens to equal the folder name in most hosts.
---   slash       string    optional. Composes the checkbox tooltip's "<slash> debug" reference.
---   L           table     optional. Locale override, keyed to lib.STRINGS.
---   skin        table     optional. Overrides Core.SKIN.
---   applySkin   function  optional, minor 4. function(frame) — owns the whole skin job for BOTH
---                         windows, replacing the library's own. For a host whose window chrome is
---                         more than a backdrop (an inner-border child frame, a title tint, a
---                         divider tint); `skin` is a table and can only reach backdrop fields.
---                         Called on the fully-built frame, after the Hide and the Esc wiring.
---   makeCloseButton function optional, minor 4. function(parent, onClick) -> button or nil.
---                         Overrides Core's x on BOTH windows. May answer nil, as Core's own
---                         does. The Copy/Clear offsets are derived from the returned button's
---                         width, so a wider button pushes them out of its way.
---
---                         RARELY THE RIGHT FIELD, and it has no consumer today. These are the
---                         LIBRARY's windows, so they wear the library's close glyph; a host
---                         whose own main window closes with something else MUST NOT push that
---                         difference onto them (standalone-windows in the Ka0s WoW Addon
---                         Standard). Two adopters passed their 24x24 class-colored x here
---                         and shipped diagnostic windows that did not match the other three's.
---                         Pass this only for a close control that is genuinely DIFFERENT IN
---                         KIND — not merely the host's own.
function lib:New(d)
  d = type(d) == "table" and d or {}
  for _, field in ipairs({ "name", "title", "font", "isEnabled", "setEnabled" }) do
    local wanted = (field == "isEnabled" or field == "setEnabled") and "function" or "string"
    if type(d[field]) ~= wanted then
      error(MAJOR .. ":New requires descriptor." .. field .. " (a " .. wanted .. ")", 2)
    end
  end

  local fontSize    = type(d.fontSize) == "number" and d.fontSize or DEFAULT_FONT_SIZE
  local safeToString = type(d.safeToString) == "function" and d.safeToString or core.SafeToString
  local skin        = type(d.skin) == "table" and d.skin or core.SKIN
  local slash       = type(d.slash) == "string" and d.slash ~= "" and d.slash or nil
  local strings     = type(d.L) == "table" and d.L or nil

  local emit = type(d.print) == "function" and d.print or function(line)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) end
  end

  -- Per-instance state. The console frame and the copy window are built lazily and separately: a
  -- host may copy a buffer it never opened a window on, and the console may be open when nobody
  -- wants the copy box. The copy window's own handle lives beside its builder further down, since
  -- minor 12 — it is Widgets' now, and only that one function touches it.
  local D = {}
  local frame

  D.buffer = {}
  D.FormatPlain, D.FormatColored = lib.FormatPlain, lib.FormatColored
  D.MakeCloseButton = lib.MakeCloseButton

  --- Resolve one user-visible string, host override first.
  ---
  --- rawget, NOT a plain index, and this is load-bearing rather than pedantic. Every Ka0s host's
  --- locale table carries a metatable fallback that answers an unknown key WITH THE KEY (the
  --- standard mandates it — anti-patterns #2). A plain index therefore accepts that synthesized
  --- string for every key, these STRINGS become unreachable, and the host renders raw keys like
  --- DEBUG_ON in place of English. It shipped exactly that way in a consumer's perf panel, for
  --- every string at once, and no headless case caught it because a synthesized value IS a string.
  ---
  --- rawget asks the only question that matters — did the host actually put a value here? — so a
  --- genuine entry still wins and a fallback-only table correctly falls through.
  function D:Text(key)
    local v = strings and rawget(strings, key)
    if type(v) == "string" then return v end
    return lib.STRINGS[key]
  end

  -- ONE implementation, in Core, reached with this instance's skin. It draws the whole Ka0s window
  -- edge — the flat 1px black border, the 1px gray inner highlight, the gold title and the gray
  -- divider — and guards every step on the key being present, so a host passing a plain WoW backdrop
  -- table (no `bg`, no `innerBorder`, …) gets a plain backdrop rather than a raise midway through
  -- building a window that is not yet hidden or Esc-wired.
  --
  -- It used to be a local copy of the three backdrop calls, on the reasoning that a table can only
  -- describe backdrop FIELDS while an inner border, a title tint and a divider tint are CALLS. That
  -- reasoning was right and the conclusion was wrong: the calls belong in the shared implementation,
  -- driven off the shared table, rather than in whichever host happens to want them.
  local function defaultApplySkin(f) core.ApplySkin(f, skin) end

  -- `applySkin` remains, and still owns the WHOLE job for both windows when a host supplies it —
  -- for chrome that differs in SHAPE rather than in color, and for a host that wants its console
  -- to track its own re-skin seam rather than this library's.
  --
  -- It is handed the fully-built frame, so `frame.title` and `frame.divider` are already assigned
  -- and a host's existing "tint whatever this window has" helper works unmodified.
  local applySkin = type(d.applySkin) == "function" and d.applySkin or defaultApplySkin

  -- The x. Defaults to Core's, through the same forwarder `lib.MakeCloseButton` uses, so a host
  -- that says nothing still tracks a Core upgraded underneath an unchanged DebugLog.
  --
  -- The default is almost always what a host wants, and the descriptor field reads as though it
  -- is not: two adopters passed their main window's 24x24 class-colored x here on the reasoning
  -- that all their windows should match, and ended up with diagnostic windows that matched their
  -- own addon and no other. These windows are the LIBRARY's; the edge is shared across every
  -- Ka0s window (Core.SKIN) but the close control on a library window is the library's.
  local makeCloseButton = type(d.makeCloseButton) == "function" and d.makeCloseButton
    or lib.MakeCloseButton

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

  -- ── the console window ───────────────────────────────────────────────────────────────────

  local function EnsureFrame()
    if frame then return frame end
    if type(CreateFrame) ~= "function" then return nil end

    local name = d.name .. "DebugWindow"
    frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(700, 344)
    frame:SetPoint("CENTER", 220, -80)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    local titleBar = dragBar(frame, TITLE_H)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER")
    -- Recorded as well as set. A font string is write-only through the frame API — there is no
    -- reading it back — so the composed title is the one thing about this window a host's test
    -- could not otherwise see, and composing it is exactly what the library adds to `d.title`.
    frame.titleText = d.title .. D:Text("TITLE_SUFFIX")
    title:SetText(frame.titleText)
    frame.title = title

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)
    -- Colored from the skin rather than hardcoded black. `applySkin` runs at the end of this
    -- function and tints it again, so this value only shows on a host whose own applySkin ignores
    -- the divider — and black under a gray-inner-bordered window is exactly the mismatch this
    -- release exists to remove.
    local dc = type(skin.divider) == "table" and skin.divider or { 0, 0, 0, 1 }
    divider:SetColorTexture(dc[1], dc[2], dc[3], dc[4])
    frame.divider = divider

    -- The three title-bar controls read Copy | Clear | Close, left to right. Anchored to the bar's
    -- right edge by absolute offset rather than to each other, because a close-button factory
    -- answers nil where CreateFrame is unavailable and a chain anchored through it would break.
    --
    -- The offsets reproduce that chain exactly, and they are DERIVED from the button's width rather
    -- than hard-coded, which matters as soon as a host supplies its own: Core's is 18 wide, so
    -- Clear lands at -30 and Copy at -78 exactly as before, but a 24-wide button would have put
    -- Clear's right edge (-30) precisely on that button's left edge and the six-pixel gap would
    -- have vanished.
    local _, clearBtn, copyBtn, offsets = buildTitleControls(titleBar, {
      addonName  = d.addonName,
      close      = makeCloseButton,
      onClose    = function() D:Hide() end,
      onClear    = function() D:Clear() end,
      onCopy     = function() D:ShowCopy() end,
      clearLabel = D:Text("CLEAR"),
      copyLabel  = D:Text("COPY"),
    })
    -- Recorded for the same reason `titleText` is: an anchor cannot be read back through the frame
    -- API, so these are the only handle a host's own test has on what its close button did to the
    -- layout, and on which of the two shapes the controls took.
    frame.titleBarOffsets = offsets
    frame.clearButton, frame.copyButton = clearBtn, copyBtn

    -- The header toggle. OnLeave restores the resting color by re-running RefreshHeader, so the
    -- label's color is always the flag's color rather than whatever the last hover left behind.
    local toggleBtn = CreateFrame("Button", nil, titleBar)
    toggleBtn:SetSize(80, 18)
    toggleBtn:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
    local toggleFS = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toggleFS:SetPoint("LEFT")
    toggleBtn:SetScript("OnEnter", function() toggleFS:SetTextColor(1, 0.82, 0) end)
    toggleBtn:SetScript("OnLeave", function() D:RefreshHeader() end)
    local function onToggleClick() D:SetEnabled(not D:IsEnabled()) end
    toggleBtn:SetScript("OnClick", onToggleClick)
    frame.debugToggle = toggleFS
    frame.debugToggleBtn = toggleBtn
    D._toggleClickForTest = onToggleClick   -- test seam (a headless mock stubs GetScript)
    -- The other test seam. A headless mock's Show()/Hide() track visibility without firing the
    -- OnShow/OnHide scripts, so the only way to exercise the visibility callback below is to drive
    -- the handler directly. Hooking the frame rather than calling the host from Show()/Hide() is
    -- deliberate: Esc and the close button both hide the window without going through either.
    D._frameForTest = frame

    local log = CreateFrame("ScrollingMessageFrame", nil, frame)
    log:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(TITLE_H + 6))
    log:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(BAR_W + 8), STATUS_H + 4)
    log:SetFont(d.font, fontSize, "")
    log:SetJustifyH("LEFT")
    log:SetFading(false)
    log:SetMaxLines(lib.MAX_BUFFER)
    log:EnableMouseWheel(true)
    log:SetScript("OnMouseWheel", function(self, delta)
      if delta > 0 then self:ScrollUp() else self:ScrollDown() end
      D:UpdateScrollBar()
    end)
    frame.log = log

    -- The slider runs top-to-bottom while a message frame's scroll offset runs bottom-to-top, so
    -- the two are related by `maxOffset - value`. Both directions of that mapping are guarded on
    -- the methods existing AND on the result being a number, which is also what makes the whole
    -- sync a clean no-op under a headless mock whose stubs answer with the frame itself.
    local bar = CreateFrame("Slider", nil, frame)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(BAR_W)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(TITLE_H + 6))
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, STATUS_H + 4)
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
      if frame._syncing then return end
      local l = frame.log
      if not (l.GetMaxScrollRange and l.SetScrollOffset) then return end
      local maxOffset = l:GetMaxScrollRange()
      if type(maxOffset) ~= "number" then return end
      l:SetScrollOffset(maxOffset - math.floor(value + 0.5))
    end)
    frame.scrollBar = bar

    local statusDivider = frame:CreateTexture(nil, "ARTWORK")
    statusDivider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, STATUS_H)
    statusDivider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, STATUS_H)
    statusDivider:SetHeight(1)
    statusDivider:SetColorTexture(0.24, 0.24, 0.27, 0.85)

    local lineCount = frame:CreateFontString(nil, "OVERLAY")
    lineCount:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 3)
    lineCount:SetFont(d.font, fontSize, "")
    lineCount:SetJustifyH("RIGHT")
    lineCount:SetTextColor(0.6, 0.6, 0.62)
    frame.lineCount = lineCount

    local function visibilityChanged()
      if type(d.onVisibilityChanged) == "function" then d.onVisibilityChanged() end
    end
    frame:HookScript("OnShow", function() D:RefreshHeader(); visibilityChanged() end)
    frame:HookScript("OnHide", visibilityChanged)
    D:RefreshHeader()

    frame:Hide()
    -- Esc closes it. Hiding is non-destructive, so this is safe to wire.
    escClose(name)

    -- Everything below is deliberately after the Hide and the Esc wiring. A frame-API surprise in
    -- the skin or the scroll sync must not abort them and leave a visible window nobody can close —
    -- and `frame` is already assigned, so EnsureFrame would never try again.
    applySkin(frame)
    D:UpdateScrollBar()
    D:UpdateStatus()
    return frame
  end

  -- ── the copy window ──────────────────────────────────────────────────────────────────────

  -- LibKa0s-Widgets-1.0's, as of minor 12. This was the fifth copy of the same fifty-two lines and
  -- the last one outside Widgets; what kept it here was that it was wired to escClose / applySkin /
  -- dragBar, which are locals of this file, and what let it go was Widgets minor 7's `scrollName` —
  -- the one thing this window did that the shared member could not express.
  --
  -- Every local it used to need is now a descriptor field, and two of them are the library's own
  -- rather than this file's: `applySkin` is already the host's-or-Core's seam, and the Esc wiring
  -- and the close control are things CopyWindow does for all four of its callers. `dragBar` had no
  -- equivalent to hand over because CopyWindow builds its own.
  --
  -- The handle is built lazily on first use and kept, because CopyWindow is itself lazy — nothing
  -- is created until the first Show, which matters on a window most sessions never open.
  local copyWindow

  local function EnsureCopyWindow()
    if copyWindow then return copyWindow end
    copyWindow = widgets.CopyWindow({
      -- Falls back to `name`, exactly as PerfPanel's descriptor does. CopyWindow REFUSES a
      -- descriptor with no addonName — it cannot resolve the collection's close art without one —
      -- and this library has always treated `addonName` as optional, so a host that never set it
      -- would have lost its copy window entirely on this upgrade rather than gained a shared one.
      addonName = d.addonName or d.name,
      name      = d.name .. "DebugCopyWindow",
      -- The scrollbar children's names derive from this one. Named here since minor 3 and the
      -- reason `scrollName` exists upstream at all.
      scrollName = d.name .. "DebugCopyScroll",
      title     = D:Text("COPY_TITLE"),
      width     = 560,
      height    = 360,
      font      = d.font,
      fontSize  = fontSize,
      -- The same seam the console window uses, so a host that re-skins one re-skins both and the
      -- two cannot drift apart.
      applySkin = applySkin,
      -- Forwarded so this library's own `makeCloseButton` field keeps covering BOTH windows, as it
      -- has since minor 4. Nothing in the collection passes it today, but the contract is published.
      makeCloseButton = makeCloseButton,
      -- BEHAVIOR GAINED, not preserved. The hand-rolled window anchored once at build, so it
      -- opened wherever it was last dragged however far the console had since moved. CopyWindow
      -- re-anchors on every show, which is what its three other callers already do — the popup
      -- lands over the window that spawned it.
      anchorTo  = function() return frame end,
    })
    return copyWindow
  end

  -- ── logging ──────────────────────────────────────────────────────────────────────────────

  --- Append one line. UNGATED on purpose: the enable seam's own bracket lines and a host's perf
  --- output both have to land whatever the flag says. The gate lives in D.Debug.
  function D:Add(tag, msg)
    -- Through the seam even though the two formatters end in string.format rather than
    -- table.concat: a WoW secret raises inside format just as it does inside concat, and Add is
    -- PUBLIC and ungated — it is the path a host's perf output and the enable brackets take. The
    -- gated sink already guards its varargs; a caller reaching Add directly got no such cover.
    msg = safeToString(msg)
    local f = EnsureFrame()
    local ts = date("%H:%M:%S")
    if f and f.log then f.log:AddMessage(lib.FormatColored(ts, tag, msg)) end
    D.buffer[#D.buffer + 1] = lib.FormatPlain(ts, tag, msg)
    if #D.buffer > lib.MAX_BUFFER then table.remove(D.buffer, 1) end
    D:UpdateScrollBar()
    D:UpdateStatus()
  end

  --- The gated sink. Zero-allocation when off — it returns before building the argument table, so
  --- a disabled console costs one function call and one flag read at every call site.
  ---
  --- A plain function rather than a method: hosts bind it bare (`NS.Debug = D.Debug`) and call it
  --- as `NS.Debug("Tag", "fmt %s", value)` from everywhere.
  function D.Debug(tag, fmt, ...)
    if not D:IsEnabled() then return end
    local n = select("#", ...)
    local msg = fmt
    if n > 0 then
      local parts = {}
      for i = 1, n do parts[i] = safeToString((select(i, ...))) end
      -- pcall'd, and the fallback is the point rather than belt-and-braces. `safeToString` answers
      -- a STRING, so a host logging a combat-protected value through a NUMERIC slot —
      -- `NS.Debug("Absorb", "total=%d", UnitGetTotalAbsorbs("player"))` — hands the sentinel to
      -- `%d`, and string.format raises on it exactly as the unguarded secret would have. That put
      -- the raise back on precisely the path this sink exists to protect (debug-logging-§4), and on
      -- a repeating ticker it takes the feature down until /reload. Found by WhatGroup, whose
      -- hand-written sink had guarded it and whose suite went red on the first load of this one.
      --
      -- On failure the line still LANDS: the format string verbatim, then the stringified
      -- arguments, space-joined. Dropping it would be the other way to lose the diagnostic, and an
      -- unfilled format is more useful to read than nothing. A satisfiable format is untouched.
      local ok, out = pcall(string.format, fmt, unpack(parts))
      if ok then
        msg = out
      else
        local joined = { safeToString(fmt) }
        for i = 1, n do joined[i + 1] = parts[i] end
        msg = table.concat(joined, " ")
      end
    end
    D:Add(tag, msg)
  end

  function D:BufferSize() return #D.buffer end

  function D:LastLine() return D.buffer[#D.buffer] end

  --- The newest line containing `substr`, or nil. Plain search, not a pattern — callers are looking
  --- for a tag or a fragment of a message, neither of which is written as a Lua pattern.
  function D:FindLine(substr)
    for i = #D.buffer, 1, -1 do
      if D.buffer[i]:find(substr, 1, true) then return D.buffer[i] end
    end
    return nil
  end

  function D:Clear()
    if frame and frame.log then frame.log:Clear() end
    for i = #D.buffer, 1, -1 do D.buffer[i] = nil end
    D:UpdateScrollBar()
    D:UpdateStatus()
  end

  function D:UpdateScrollBar()
    if not (frame and frame.log and frame.scrollBar) then return end
    local log, bar = frame.log, frame.scrollBar
    if not (log.GetMaxScrollRange and log.GetScrollOffset) then return end
    local maxOffset, off = log:GetMaxScrollRange(), log:GetScrollOffset()
    if type(maxOffset) ~= "number" or type(off) ~= "number" then return end
    frame._syncing = true   -- suppress the OnValueChanged -> SetScrollOffset feedback loop
    bar:SetMinMaxValues(0, maxOffset)
    bar:SetValue(maxOffset - off)
    frame._syncing = false
    bar:EnableMouse(maxOffset > 0)   -- inert, but still shown, when everything fits
  end

  function D:UpdateStatus()
    if not (frame and frame.lineCount) then return end
    frame.lineCount:SetText(D:Text("LINES"):format(#D.buffer, lib.MAX_BUFFER))
  end

  --- Exactly what the copy window puts in front of the user. Split out from ShowCopy because an
  --- EditBox is write-only through the frame API, so this is the only way to assert the thing that
  --- actually matters about the copy window — that it is the whole buffer, in order.
  function D:CopyText() return table.concat(D.buffer, "\n") end

  function D:ShowCopy()
    local win = EnsureCopyWindow()
    if not win then return end
    -- The width/text/cursor/show/focus/highlight order this used to spell out is CopyWindow's now,
    -- and it is load-bearing there for the same reasons it was here.
    win:Show(D:CopyText())
    D._copyWindowForTest = win
    D._copyFrameForTest  = win:GetFrame()
  end

  -- ── visibility ───────────────────────────────────────────────────────────────────────────

  function D:Show() local f = EnsureFrame(); if f then f:Show() end end

  --- Never builds. A host's settings panel calls IsShown on every refresh, and a Hide that
  --- constructed a window would build one nobody asked for.
  function D:Hide() if frame then frame:Hide() end end

  function D:IsShown() return (frame and frame:IsShown()) and true or false end

  function D:Toggle()
    local f = EnsureFrame()
    if not f then return end
    if f:IsShown() then f:Hide() else f:Show() end
  end

  -- ── the enable seam ──────────────────────────────────────────────────────────────────────

  function D:IsEnabled() return not not d.isEnabled() end

  function D:RefreshHeader()
    if not (frame and frame.debugToggle) then return end
    local on = D:IsEnabled()
    frame.debugToggle:SetText(on and D:Text("DEBUG_ON") or D:Text("DEBUG_OFF"))
    if on then
      frame.debugToggle:SetTextColor(0.30, 0.85, 0.30)
    else
      frame.debugToggle:SetTextColor(0.90, 0.30, 0.30)
    end
  end

  --- The single seam for changing debug state. The slash command and the header toggle both come
  --- through here, so the chat acknowledgement and the header label can never disagree.
  function D:SetEnabled(on)
    on = not not on
    d.setEnabled(on)
    D:RefreshHeader()
    -- Color-coded chat ack: the state word is ON green (40ff40) / OFF red (ff4040), mirroring the
    -- title-bar toggle so the flag reads identically in chat and on the console header.
    local state = on and ("|cff40ff40" .. D:Text("STATE_ON") .. "|r")
      or ("|cffff4040" .. D:Text("STATE_OFF") .. "|r")
    emit(D:Text("ACK"):format(state))
    -- Bracket every session with a console line at both ends. Written through Add rather than the
    -- gated sink, so the "logging disabled" line still lands after the flag has already flipped off
    -- — through the sink it would early-return and the line would never appear.
    D:Add("Debug", on and D:Text("LOG_ENABLED") or D:Text("LOG_DISABLED"))
    -- On enable, follow the bracket with the host's one-line session summary. Emitted HERE rather
    -- than at login because the flag is session-only and off at login, so a load-time summary would
    -- always be gated off and never render. Raw Add, but routed through safeToString: a host that
    -- puts a combat-protected value in its summary must not take the console down with it.
    if on and type(d.initSummary) == "function" then
      local line = d.initSummary()
      if line ~= nil then D:Add("Init", safeToString(line)) end
    end
  end

  -- ── the checkbox data contract ───────────────────────────────────────────────────────────

  --- A plain { label, tooltip, get, set } table for a settings module to render. Deliberately data
  --- rather than a widget: the options library consumes this shape without either library ever
  --- reaching for the other, which is what keeps a real dependency cycle from forming.
  ---
  --- It toggles the window's VISIBILITY only, never the logging flag. Those are separate controls
  --- and a user who closes the console does not expect logging to stop.
  function D:ConsoleCheckbox()
    return {
      label   = D:Text("CHECKBOX_LABEL"),
      tooltip = slash and D:Text("CHECKBOX_TOOLTIP"):format(slash, slash)
        or D:Text("CHECKBOX_TOOLTIP_NO_SLASH"),
      get = function() return D:IsShown() end,
      set = function(v)
        if v then D:Show() else D:Hide() end
      end,
    }
  end

  return D
end
