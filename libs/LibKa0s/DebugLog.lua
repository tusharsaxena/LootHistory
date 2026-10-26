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

-- Minor 21: the console is toplevel and re-raises a shown StaticPopup on show (frame-layering-§4).
-- Minor 22: the window peeled to DebugLogWindow.lua, and it follows the console's skin owner, the
-- descriptor's `addonName` once that addon registered with LibKa0s-Skin-1.0 (LK-09 of
-- Ka0sAddonsCommonTasks docs/2026-10-25-SKINNING).
local MAJOR, MINOR = "LibKa0s-DebugLog-1.0", 22
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
-- The history, because each step had its own reason. 500 through minor 10. 1500 from minor 11
-- through minor 13, because the perf capture workflow pastes out of THIS buffer: `perf report`
-- prints its summary here and `perf dump` writes the whole JSON record as one line (Perf.lua), so
-- a long run overflowed 500 and lost its head with nothing saying so. 3000 from minor 14, because
-- the diagnostics report (DebugLogDiagnostics.lua) is written into this same buffer after the
-- debug trace, so a player copies both in one go. At 1500 a report at its 1200-line cap
-- (DIAG_MAX_LINES) would leave as little as 300 lines of the trace it is meant to travel with.
--
-- Why 3000 and not 5000: measured in the live client on 2026-09-26 with a throwaway, uncommitted
-- copy bench addon (open + highlight plus the next frame, the N = 0 baseline subtracted, median of
-- three), not with TIME_COPY below, which only prints one ShowCopy's figures. At 120-column
-- lines 3000 cost 246 ms against a 250 ms limit and 5000 cost 378 ms, and by hand the copy box at
-- 5000 was sluggish. 3000 passes, only just, so this is the ceiling rather than a starting point.
--
-- The copy window is a view of this array and caps nothing of its own, which is why raising this
-- raises both and why there is no second number.
lib.MAX_BUFFER = 3000

-- How far the raw array may run past MAX_BUFFER before it is compacted (minor 13). Through minor 12
-- every Add past the cap ran table.remove(buffer, 1), a MAX_BUFFER-slot shift per line for as long
-- as logging stayed on. Now the array grows to MAX_BUFFER + BUFFER_SLACK and the newest MAX_BUFFER
-- lines are then moved down in one pass: one compaction per BUFFER_SLACK + 1 lines instead of a
-- shift per line.
--
-- `buffer` stays a plain ordered array rather than a ring, because host suites across the
-- collection index it directly. What moves is only its LENGTH past the cap: between compactions it
-- may hold up to MAX_BUFFER + BUFFER_SLACK raw entries, and every public reader (BufferSize,
-- LastLine, FindLine, CopyText, the status line) answers the newest MAX_BUFFER and no more.
--
-- Published at minor 14 rather than kept a local, and read by Add at call time like MAX_BUFFER.
-- The two move together: moves per line is roughly MAX_BUFFER / (BUFFER_SLACK + 1), so a bigger
-- buffer takes a bigger slack to keep the same amortized cost, and a suite that pinned 64 as a
-- literal next to a constant it reads back would go stale the day the buffer moves. It did move,
-- in the same minor: 64 at 1500 was about 23 moves per line, and 128 at 3000 keeps it there.
lib.BUFFER_SLACK = 128

-- Copy timing (minor 14). Off by default and never persisted: a session-only switch for measuring
-- what the copy window costs at a given buffer size, set by hand with
-- `/run LibStub("LibKa0s-DebugLog-1.0").TIME_COPY = true`. While it is on, every ShowCopy prints
-- one COPY_TIMING line through the host's chat printer, never through Add, so a measurement does
-- not grow the very buffer it is measuring. Lib-level on purpose: it is a question about the
-- library's window, and one switch answers it for every console loaded.
lib.TIME_COPY = false

-- Re-exported rather than left for the host to reach into Core for. A host that draws a close
-- button on its own windows should get the same one its console wears, from one factory — three
-- copies of "the addon's close button" is exactly how two windows that should look identical drift.
--
-- A forwarder rather than a copied value: LibStub upgrades a major IN PLACE, so the `core` TABLE
-- survives a Core minor bump while the FUNCTION on it is replaced, and resolving at CALL time keeps
-- the console on the live Core's button (as PerfPanel.lua does). The third argument is minor 10's
-- fix: minor 9 dropped it, and its close silently fell back to the multiplication sign.
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
  -- The title-bar link that runs the diagnostics report (minor 16), drawn beside the toggle.
  DIAGNOSTICS      = "Diagnostics",
  COPY_TITLE       = "Copy log \226\128\148 Ctrl+C, then Esc",
  LINES            = "%d / %d lines",
  CHECKBOX_LABEL   = "Debug console",
  CHECKBOX_TOOLTIP = "Show or hide the on-screen debug console window. Same as %s debug. " ..
    "Whether logging is on is separate \226\128\148 use %s debug on|off or the window's own toggle.",
  -- The same sentence for a host that declares no slash command. Two strings rather than one with
  -- an empty substitution, because "Same as  debug." reads as a bug and this text ships frozen.
  CHECKBOX_TOOLTIP_NO_SLASH = "Show or hide the on-screen debug console window. Whether logging " ..
    "is on is separate \226\128\148 use the window's own toggle.",
  -- Printed only while lib.TIME_COPY is on (minor 14). Milliseconds from debugprofilestop.
  COPY_TIMING      = "copy timing: %d lines, %d bytes, concat %.1fms, open+highlight %.1fms, " ..
    "next frame %.1fms",
  -- The one chat line a diagnostics report prints (minor 14, DebugLogDiagnostics.lua). Localizable
  -- like every string here; the report BODY is English diagnostic text and never goes through `L`.
  DIAG_WRITTEN     = "Diagnostic report written to the debug console: %d lines. " ..
    "Use Copy to share it.",
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

local DEFAULT_FONT_SIZE = 10

-- The header toggle's two colors: green ON, red OFF. The window's palette answers them
-- (DebugLogWindow.lua, minor 22, a skin owner's `sem.on` / `sem.off`); these are the constants it
-- falls back to, and what every console without an owner draws.
local STATE_ON, STATE_OFF = { 0.30, 0.85, 0.30 }, { 0.90, 0.30, 0.30 }

-- ── the instance ───────────────────────────────────────────────────────────────────────────

-- lib:New's descriptor reads, out of its closure (CCN 27 sighted, WowAddonStandards#6). Same defaults.
local function field(v, kind, fallback) if type(v) == kind then return v end return fallback end
local function nonEmpty(v) if type(v) == "string" and v ~= "" then return v end return nil end
local function chatPrint(line) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) end end
local function checkDescriptor(d)
  for _, key in ipairs({ "name", "title", "font", "isEnabled", "setEnabled" }) do
    local wanted = (key == "isEnabled" or key == "setEnabled") and "function" or "string"
    if type(d[key]) ~= wanted then error(MAJOR .. ":New requires descriptor." .. key .. " (a " .. wanted .. ")", 3) end
  end
  return d
end

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
---   print       function  optional. Where the chat acknowledgment goes. Defaults to the chat
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
---   brandName   string    optional, minor 14. The addon's plain-text brand, `Ka0s <Name>`, named
---                         in both diagnostics markers. Falls back to `title`.
---   diagnostics function  optional, minor 14. Returns the host's report sections as
---                         `{ { name, fn }, ... }`, each `fn(out)`. CALLED AT RUN TIME rather than
---                         read at New, so a module that loads after the console can still supply
---                         a section. Read only when DebugLogDiagnostics.lua is loaded, like:
---   diagnosticsEnablesLogging  optional, minor 17. `false` stops a report run turning logging on.
---   onClear     function  optional, minor 18. Called by `D:Clear()` after the wipe, pcall'd (a
---                         raise costs one line), so a host re-arms its own change gates.
function lib:New(d)
  d = checkDescriptor(field(d, "table", {}))
  local fontSize    = field(d.fontSize, "number", DEFAULT_FONT_SIZE)
  local safeToString = field(d.safeToString, "function", core.SafeToString)
  local skin        = field(d.skin, "table", core.SKIN)
  local slash       = nonEmpty(d.slash)
  local strings     = field(d.L, "table", nil)
  local emit        = field(d.print, "function", chatPrint)

  -- Per-instance state. The console frame and the copy window are built lazily and separately: a
  -- host may copy a buffer it never opened a window on, and the console may be open when nobody
  -- wants the copy box. The copy window's own handle lives beside its builder further down, since
  -- minor 12 — it is Widgets' now, and only that one function touches it.
  local D = {}
  local frame, rearm, flushAtEnable   -- DebugLogGates.lua's gate reset and queue flush, or nil

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
  --
  -- Minor 22: the skin owner. `addonName` counts once that addon registered with LibKa0s-Skin-1.0
  -- (Core's `__SkinFacade`, asked at call time), and only when the host passed neither its own
  -- `skin` table nor its own `applySkin`: a host that drew its console its own way keeps doing so.
  -- An owned window is handed to the owner's facade through Core.ApplySkin's third argument.
  local owner = (d.skin == nil and d.applySkin == nil) and d.addonName or nil
  local function facade()
    if not owner or type(core.__SkinFacade) ~= "function" then return nil end
    return core.__SkinFacade(owner)
  end
  local function defaultApplySkin(f)
    if facade() then return core.ApplySkin(f, nil, owner) end
    core.ApplySkin(f, skin)
  end

  -- `applySkin` remains, and still owns the WHOLE job for both windows when a host supplies it —
  -- for chrome that differs in SHAPE rather than in color, and for a host that wants its console
  -- to track its own re-skin seam rather than this library's.
  --
  -- It is handed the fully-built frame, so `frame.title` and `frame.divider` are already assigned
  -- and a host's existing "tint whatever this window has" helper works unmodified.
  local applySkin = field(d.applySkin, "function", defaultApplySkin)

  -- The x. Defaults to Core's, through the same forwarder `lib.MakeCloseButton` uses, so a host
  -- that says nothing still tracks a Core upgraded underneath an unchanged DebugLog.
  --
  -- The default is almost always what a host wants, and the descriptor field reads as though it
  -- is not: two adopters passed their main window's 24x24 class-colored x here on the reasoning
  -- that all their windows should match, and ended up with diagnostic windows that matched their
  -- own addon and no other. These windows are the LIBRARY's; the edge is shared across every
  -- Ka0s window (Core.SKIN) but the close control on a library window is the library's.
  local makeCloseButton = field(d.makeCloseButton, "function", lib.MakeCloseButton)

  -- ── the console window ───────────────────────────────────────────────────────────────────

  -- DebugLogWindow.lua's, since minor 22 (the band's named seam). The shell keeps the handle: the
  -- window file hands the frame over through `adopt` the moment it exists, so a raise later in the
  -- build still leaves a window that is hidden, Esc-wired and never built twice. Without the window
  -- file (or with no client) there is no window, and logging still lands in the buffer.
  local function EnsureFrame()
    if frame then return frame end
    if type(CreateFrame) ~= "function" or type(lib.__buildConsole) ~= "function" then return nil end
    lib.__buildConsole(D, {
      d = d, fontSize = fontSize, skin = skin, applySkin = applySkin,
      makeCloseButton = makeCloseButton, facade = facade,
      adopt = function(f) frame = f end,
      onVisibilityChanged = function()
        if type(d.onVisibilityChanged) == "function" then d.onVisibilityChanged() end
      end,
    })
    return frame
  end

  -- ── the copy window ──────────────────────────────────────────────────────────────────────

  -- LibKa0s-Widgets-1.0's, as of minor 12. This was the fifth copy of the same fifty-two lines and
  -- the last one outside Widgets; what kept it here was that it was wired to escClose / applySkin /
  -- dragBar, which were locals of this file (DebugLogWindow.lua's, since minor 22), and what let it go was Widgets minor 7's `scrollName` —
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

  local function copySkin()
    if facade() then return nil end
    return applySkin
  end

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
      -- Minor 22: an owned console hands its copy window no applySkin, so CopyWindow paints it for
      -- the same owner (its addonName) with its scrollbar and dense fill.
      applySkin = copySkin(),
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

  --- The append itself, without the repaint. Add is this plus one scrollbar and status update; the
  --- diagnostics report (minor 14) writes up to DIAG_MAX_LINES lines through this and repaints once
  --- at the end, rather than repainting the status line once per line.
  local function append(tag, msg)
    -- Through the seam even though the two formatters end in string.format rather than
    -- table.concat: a WoW secret raises inside format just as it does inside concat, and Add is
    -- PUBLIC and ungated — it is the path a host's perf output and the enable brackets take. The
    -- gated sink already guards its varargs; a caller reaching Add directly got no such cover.
    msg = safeToString(msg)
    local f = EnsureFrame()
    local ts = date("%H:%M:%S")
    -- An owned window colors its line from the owner's skin (DebugLogWindow.lua's `__logLine`).
    if f and f.log then
      if f.__logLine then
        f.log:AddMessage(f.__logLine(ts, tag, msg))
      else
        f.log:AddMessage(lib.FormatColored(ts, tag, msg))
      end
    end
    local buf = D.buffer
    buf[#buf + 1] = lib.FormatPlain(ts, tag, msg)
    local n, cap = #buf, lib.MAX_BUFFER
    if n > cap + lib.BUFFER_SLACK then
      -- One pass: the newest `cap` lines move down to 1..cap, then the tail is cleared from the end
      -- so the array stays dense at every step.
      local drop = n - cap
      for i = 1, cap do buf[i] = buf[i + drop] end
      for i = n, cap + 1, -1 do buf[i] = nil end
    end
  end

  --- Append one line. UNGATED on purpose: the enable seam's own bracket lines and a host's perf
  --- output both have to land whatever the flag says. The gate lives in D.Debug.
  function D:Add(tag, msg)
    append(tag, msg)
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

  --- The index of the oldest line a reader may see. The raw array can run up to BUFFER_SLACK lines
  --- past the cap between compactions, and those older lines are already evicted as far as any
  --- reader is concerned.
  local function firstKept()
    local first = #D.buffer - lib.MAX_BUFFER + 1
    return first > 1 and first or 1
  end

  function D:BufferSize() return #D.buffer - firstKept() + 1 end

  function D:LastLine() return D.buffer[#D.buffer] end

  --- The newest line containing `substr`, or nil. Plain search, not a pattern — callers are looking
  --- for a tag or a fragment of a message, neither of which is written as a Lua pattern.
  function D:FindLine(substr)
    for i = #D.buffer, firstKept(), -1 do
      if D.buffer[i]:find(substr, 1, true) then return D.buffer[i] end
    end
    return nil
  end

  function D:Clear()
    if frame and frame.log then frame.log:Clear() end
    for i = #D.buffer, 1, -1 do D.buffer[i] = nil end
    if rearm then rearm() end
    if type(d.onClear) == "function" then
      local ok, err = pcall(d.onClear)
      if not ok then append("Debug", "onClear raised: " .. safeToString(err)) end
    end
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
    frame.lineCount:SetText(D:Text("LINES"):format(D:BufferSize(), lib.MAX_BUFFER))
  end

  --- Exactly what the copy window puts in front of the user. Split out from ShowCopy because an
  --- EditBox is write-only through the frame API, so this is the only way to assert the thing that
  --- actually matters about the copy window — that it is the whole buffer, in order. The newest
  --- MAX_BUFFER lines only, since minor 13: any slack past the cap is already evicted.
  function D:CopyText() return table.concat(D.buffer, "\n", firstKept(), #D.buffer) end

  --- ShowCopy with the three costs measured (minor 14): the concat that builds the text, the open
  --- (CopyWindow's SetText, cursor, Show, SetFocus and HighlightText), and whatever the client does
  --- before the next frame, which is where laying out a large EditBox lands. Headless, or on a client
  --- without either clock, the window opens untimed rather than raising: the flag is a measuring
  --- aid, and a missing clock must never cost the user the copy window itself.
  local function timedShowCopy(win)
    local clock, timer = debugprofilestop, C_Timer
    local after = type(timer) == "table" and timer.After
    if type(clock) ~= "function" or type(after) ~= "function" then
      win:Show(D:CopyText())
      return
    end
    local t0 = clock()
    local text = D:CopyText()
    local t1 = clock()
    win:Show(text)
    local t2 = clock()
    local lines, bytes = D:BufferSize(), #text
    after(0, function()
      emit(D:Text("COPY_TIMING"):format(lines, bytes, t1 - t0, t2 - t1, clock() - t2))
    end)
  end

  function D:ShowCopy()
    local win = EnsureCopyWindow()
    if not win then return end
    -- The width/text/cursor/show/focus/highlight order this used to spell out is CopyWindow's now,
    -- and it is load-bearing there for the same reasons it was here.
    if lib.TIME_COPY then timedShowCopy(win) else win:Show(D:CopyText()) end
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
    local pal = frame.__palette
    local c = on and (pal and pal.on or STATE_ON) or (pal and pal.off or STATE_OFF)
    frame.debugToggle:SetTextColor(c[1], c[2], c[3])
  end

  --- The single seam for changing debug state. The slash command and the header toggle both come
  --- through here, so the chat acknowledgment and the header label can never disagree.
  function D:SetEnabled(on)
    on = not not on
    d.setEnabled(on)
    if on and rearm then rearm() end   -- a new session hears every gated line again
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
    if on and flushAtEnable then flushAtEnable() end   -- the at-enable queue, after the bracket
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

  -- The secondary files of this major install themselves here when they loaded, each handed only
  -- what it needs: the gates and queue (minor 18, DebugLogGates.lua) the stringifier, and the report
  -- (minor 14, DebugLogDiagnostics.lua) the append, repaint, printer, stringifier and descriptor.
  -- Absent, the instance lacks those members, which a host's degradation stub already answers.
  if type(lib.__installGates) == "function" then
    rearm, flushAtEnable = lib.__installGates(D, { safeToString = safeToString })
  end
  if type(lib.__installDiagnostics) == "function" then
    lib.__installDiagnostics(D, { d = d, emit = emit, safeToString = safeToString, append = append,
      repaint = function() D:UpdateScrollBar(); D:UpdateStatus() end })
  end

  return D
end
