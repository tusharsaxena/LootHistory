local addonName, NS = ...

-- LibKa0s-DebugLog-1.0 seam: the on-screen debug console.
--
-- This replaces modules/DebugLog.lua outright (359 lines). The two formatters were already
-- byte-identical to the library's, the frame globals the descriptor generates from `name` are the
-- exact names that file hardcoded ("LootHistoryDebugWindow" / "LootHistoryDebugCopyWindow"), and
-- the buffer, the cap, the status counter and the enable seam's chat ack all match to the byte.
--
-- The window CHROME is the part that used to force a decline, and it no longer does. DebugLog minor
-- 4 added `applySkin` and `makeCloseButton`, both defaulting to what minor 3 did, precisely so a
-- host like this one — a flat 1px WHITE8X8 double border with a synthesised inner border, a gold
-- title tint, a grey divider and a 24x24 class-coloured x — could keep its own chrome instead of
-- turning down a module whose formatters it already shares. Both hooks are passed below.
--
-- ── LOAD ORDER ─────────────────────────────────────────────────────────────────────────────────
--   AFTER  core/Constants.lua  — `font` is read at :New time (NS.Constants.FONT_MONO).
--   AFTER  core/CoreSetup.lua  — `print` routes through the shared printer.
--   BEFORE core/Database.lua   — its migrations call NS.Debug during InitDB.
--
-- The two chrome hooks reach modules/Browser.lua, which loads much LATER. That is safe only because
-- they are CLOSURES resolved at frame-build time, not references taken at load. Hoisting either
-- lookup into a local here would reintroduce the ordering hazard and silently lose the skin.

local lib = LibStub and LibStub("LibKa0s-DebugLog-1.0", true)

if not lib then
  -- Degrade, not error: recording loot does not need a diagnostics console. The stub answers every
  -- member this addon calls — `NS.Debug` from ~40 sites across seven files, and the Show/Hide/
  -- IsShown/Toggle/SetEnabled/buffer surface the `state.debugConsole` schema row, the `/lh debug`
  -- verb and the settings panel all reach for.
  NS.DebugLog = {
    buffer      = {},
    FormatPlain = function(ts, tag, msg)
      return ("%s | [%s] %s"):format(tostring(ts), tostring(tag or ""), tostring(msg))
    end,
    FormatColored = function(ts, tag, msg)
      return ("|cff6f8faf%s|r || |cffc9a66b[%s]|r %s"):format(
        tostring(ts), tostring(tag or ""), tostring(msg))
    end,
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
  return
end

NS.DebugLog = lib:New({
  -- Seeds LootHistoryDebugWindow / LootHistoryDebugCopyWindow / LootHistoryDebugCopyScroll. The
  -- first two are the names modules/DebugLog.lua hardcoded, so nothing that reaches this window by
  -- global name — /framestack, a user macro, the Esc registration — changes.
  name  = addonName,
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

  -- Fired on the frame's OnShow AND OnHide, so the settings panel's "Debug console" checkbox tracks
  -- the window however it was closed. Strictly wider than what it replaces: modules/DebugLog.lua
  -- only synced from its own Show/Hide, so an Esc or a click on the x left the checkbox stale.
  onVisibilityChanged = function()
    if NS.Panel and NS.Panel.Refresh then NS.Panel:Refresh() end
  end,

  -- ── the two chrome hooks (DebugLog minor 4) ─────────────────────────────────────────────────
  --
  -- Resolved HERE, inside the closure, rather than into a local at file load: both fire at
  -- frame-build time, long after modules/Browser.lua has run, which is the only reason a core/ file
  -- may reach for a member of a module that loads after it.

  -- Routes both windows through THIS addon's own re-skin seam. As of Core minor 3 the library's
  -- default draws the same edge, so this no longer changes what is rendered — it keeps the console
  -- tracking `modules/Browser.lua` if that file's SKIN is ever retuned, which is one of the two
  -- purposes standalone-windows-§2 sanctions the hook for. The library hands over a fully-built
  -- frame with `title` and `divider` already assigned, which is exactly what B:ApplySkin reads.
  applySkin = function(frame)
    if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(frame) end
  end,

  -- The same x every other window in this addon closes with — 24x24, light grey, class-coloured on
  -- hover — rather than Core's 18x18 fixed red. Answering nil is allowed and is what Core's own
  -- factory does where CreateFrame is unavailable.
  makeCloseButton = function(parent, onClick)
    if NS.Browser and NS.Browser.MakeCloseButton then
      return NS.Browser:MakeCloseButton(parent, onClick)
    end
  end,
})

-- The gated sink, republished under the name ~40 call sites across seven files already use. A plain
-- bindable function, never a method: every site calls it as NS.Debug("Tag", "fmt %s", value).
NS.Debug = NS.DebugLog.Debug
