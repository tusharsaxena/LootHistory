local addonName, NS = ...

-- LibKa0s-DebugLog-1.0 seam: the on-screen debug console.
--
-- This replaces modules/DebugLog.lua outright (359 lines). The two formatters were already
-- byte-identical to the library's, the frame globals the descriptor generates from `name` are the
-- exact names that file hardcoded ("LootHistoryDebugWindow" / "LootHistoryDebugCopyWindow"), and
-- the buffer, the cap, the status counter and the enable seam's chat ack all match to the byte.
--
-- The window CHROME is the part that used to force a decline, and it no longer does. DebugLog minor
-- 4 added `applySkin` and `makeCloseButton` so a host could keep its own chrome; this addon passed
-- `applySkin` (routing to B:ApplySkin) until the skin engine. Since DebugLog minor 22 the console is
-- painted for its skin OWNER, the descriptor's `addonName`, but only when the host passes neither
-- `skin` nor `applySkin` (a host hook owns the whole job and is never skinned over). So neither hook
-- is passed any more (LH-05): the window, its copy window, the log lines, the scroll bar and the
-- line counter all follow the skin core/SkinSetup.lua registered for "LootHistory".
--
-- ── LOAD ORDER ─────────────────────────────────────────────────────────────────────────────────
--   AFTER  core/Constants.lua  — `font` is read at :New time (NS.Constants.FONT_MONO).
--   AFTER  core/CoreSetup.lua  — `print` routes through the shared printer.
--   BEFORE core/Database.lua   — its migrations call NS.Debug during InitDB.
--   AFTER  core/SkinSetup.lua  — not at load: the library asks whether `addonName` is a registered
--                                skin owner when it builds the window, long after both files ran.

local lib = LibStub and LibStub("LibKa0s-DebugLog-1.0", true)

if not lib then
  -- Degrade, not error: recording loot does not need a diagnostics console. The stub answers every
  -- member this addon calls — `NS.Debug` from ~40 sites across seven files, and the Show/Hide/
  -- IsShown/Toggle/SetEnabled/buffer surface the `state.debugConsole` schema row, the `/lh debug`
  -- verb and the settings panel all reach for.
  NS.DebugLog = {
    buffer      = {},
    -- Kept for surface parity only, and deliberately NOT the library's format: no addon caller
    -- reaches either member (`grep -rn 'FormatPlain\|FormatColored' core modules settings` returns
    -- only this stub), so a copy of the library's format string and color codes would be inert
    -- and go stale (library-stack-§7, anti-pattern #47).
    FormatPlain   = function(_, _, msg) return tostring(msg) end,
    FormatColored = function(_, _, msg) return tostring(msg) end,
    Add         = function() end,
    Clear       = function() end,
    BufferSize  = function() return 0 end,
    LastLine    = function() return nil end,
    FindLine    = function() return nil end,
    ShowCopy    = function() end,
    Show        = function() end,
    Hide        = function() end,
    IsShown     = function() return false end,
    Toggle      = function() end,
    IsEnabled   = function() return NS.State and NS.State.debug and true or false end,
    RefreshHeader = function() end,
    UpdateScrollBar = function() end,
    UpdateStatus    = function() end,
    SetEnabled  = function(_, on)
      -- The flag itself is the host's, so it still flips — only the WINDOW is gone. `/lh debug on`
      -- must not become a no-op just because the console is unavailable.
      if NS.State then NS.State.debug = not not on end
      if NS.Print then
        NS.Print(NS.LIBKA0S_MISSING .. ", so the debug console window is unavailable.")
      end
    end,
    -- The diagnostics report (DebugLog 14.1, debug-logging-14). With no library there is no
    -- console to write it into, so the report prints the collection's placeholder line naming the
    -- command, writes nothing and returns 0. The other two are carried for surface parity:
    -- BuildDiagnostics answers an empty report, and DebugVerb answers false so the `debug` verb
    -- keeps its own fallback.
    RunDiagnostics = function()
      if NS.Print then
        NS.Print(NS.L["%s is unavailable: the LibKa0s library did not load."]:format("/lh diagnostics"))
      end
      return 0
    end,
    BuildDiagnostics = function()
      return { lines = {}, dropped = 0, capped = false, capsHit = false }
    end,
    DebugVerb = function() return false end,
    -- The change gates and the at-enable queue (DebugLogGates 1, LibKa0s v1.65.0). With no console
    -- there is nothing to write to, so each answers nothing, as the stub NS.Debug below does.
    DebugOnce     = function() end,
    DebugChanged  = function() end,
    DebugForget   = function() end,
    DebugAtEnable = function() end,
    ConsoleCheckbox = function()
      return {
        label   = "Debug console",
        tooltip = NS.LIBKA0S_MISSING .. ", so the debug console window is unavailable.",
        get     = function() return false end,
        set     = function() end,
      }
    end,
  }
  NS.Debug = function() end
  NS.DebugOnce, NS.DebugChanged = NS.DebugLog.DebugOnce, NS.DebugLog.DebugChanged
  NS.DebugForget, NS.DebugAtEnable = NS.DebugLog.DebugForget, NS.DebugLog.DebugAtEnable
  return
end

NS.DebugLog = lib:New({
  -- Seeds LootHistoryDebugWindow / LootHistoryDebugCopyWindow / LootHistoryDebugCopyScroll. The
  -- first two are the names modules/DebugLog.lua hardcoded, so nothing that reaches this window by
  -- global name — /framestack, a user macro, the Esc registration — changes.
  name  = addonName,
  -- THE FOLDER NAME, which is a different question from the one above even though this addon
  -- answers both with the same string. `name` seeds frame globals; `addonName` is what the library
  -- builds a TEXTURE PATH from, so its own close, copy and clear controls draw this collection's
  -- art instead of a multiplication sign and two words. A vendored library cannot work that out
  -- for itself -- there is no one path to it -- and a host where the two strings diverge would
  -- hand it a path into nowhere, which draws nothing and raises nothing. Passed explicitly for
  -- that reason rather than left to the library to infer from `name`.
  addonName = addonName,
  title = "Loot History",     -- the library appends its own " — Debug"
  font  = NS.Constants.FONT_MONO,
  slash = "/lh",

  -- The flag stays the HOST's. It is session-only (NS.State.debug, never persisted), and the slash
  -- verb, the settings panel and the console header must all read the one truth.
  isEnabled  = function() return NS.State and NS.State.debug and true or false end,
  setEnabled = function(on) if NS.State then NS.State.debug = on end end,

  -- Late-bound rather than `print = NS.Print`: core/LootHistory.lua reclaims NS.Print from
  -- NS.Util.print after AceConsole's Embed clobbers it, and that file loads after this one.
  print = function(line) NS.Print(line) end,

  -- The addon's own guard, which is the library's own function published under NS by
  -- core/CoreSetup.lua. Passed explicitly rather than defaulted so the seam is visible at the call
  -- site if either side ever stops being the other.
  safeToString = function(v) return NS.SafeToString(v) end,

  -- One line naming version / schema / profile / record count. The library owns WHEN it is emitted
  -- (on enable, as the [Init] line); only the host can know what it says.
  initSummary = function() return NS.InitSummary() end,

  -- The diagnostics report (DebugLog 14.1, debug-logging-§14). The brand goes on both markers, so a
  -- paste holding several addons' reports can be split. The sections are modules/Diagnostics.lua's,
  -- looked up when the report runs rather than here, because that file loads long after this one.
  brandName   = NS.BRAND,
  diagnostics = function()
    return NS.Diagnostics and NS.Diagnostics.Sections and NS.Diagnostics.Sections() or {}
  end,

  -- Fired on the frame's OnShow AND OnHide, so the settings panel's "Debug console" checkbox tracks
  -- the window however it was closed. Strictly wider than what it replaces: modules/DebugLog.lua
  -- only synced from its own Show/Hide, so an Esc or a click on the x left the checkbox stale.
  onVisibilityChanged = function()
    if NS.Panel and NS.Panel.Refresh then NS.Panel:Refresh() end
  end,

  -- ── no chrome hooks: the skin owner paints the console (DebugLog minor 22) ─────────────────
  --
  -- NO `applySkin` and NO `skin`. Either one would make the console the host's to draw and the
  -- library would never paint it for its owner (tests/test_skin_tools.lua pins both absent). The
  -- owner is `addonName` above, which core/SkinSetup.lua registered with LibKa0s-Skin-1.0: the
  -- library hands the window to Core.ApplySkin with that owner (the facade's Shell), paints the
  -- scroll bar and the status rule, colors the log lines from the skin's palette and refills it on
  -- every switch. On Ka0s Default it draws the edge B:ApplySkin drew before.
  --
  -- STILL NO `makeCloseButton`. The console and the copy window are the LIBRARY's windows, so they
  -- wear the library's close -- and since Core minor 6 the library's close IS this collection's
  -- `close` mark, because the `addonName` above reaches it (libs/LibKa0s/DebugLog.lua forwards
  -- d.addonName to Core).
})

-- The gated sink, republished under the name ~40 call sites across seven files already use. A plain
-- bindable function, never a method: every site calls it as NS.Debug("Tag", "fmt %s", value).
NS.Debug = NS.DebugLog.Debug

-- The console's change gates and at-enable queue (DebugLogGates 1, LibKa0s v1.65.0; debug-logging-§1,
-- §9), bound bare the same way. DebugOnce / DebugChanged replace the four memos this addon kept by
-- hand (the [AHPrice] and [Cfg] once-per-error lines, the [Table] and [Insights] change gates): the
-- console re-arms them on Clear and on enable, which a file-local memo never was. DebugAtEnable
-- holds a STATE line written while logging is off -- the load-time stand-up's dependency line, a
-- refused event name, the launcher's registration -- until the player turns logging on.
NS.DebugOnce, NS.DebugChanged = NS.DebugLog.DebugOnce, NS.DebugLog.DebugChanged
NS.DebugForget, NS.DebugAtEnable = NS.DebugLog.DebugForget, NS.DebugLog.DebugAtEnable
