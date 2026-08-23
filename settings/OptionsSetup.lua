local addonName, NS = ...

-- LibKa0s-Options-1.0 seam: the Blizzard settings-canvas shell, the page registry, the lazy
-- Defaults button, the five widget makers and the two-column flow engine.
--
-- The layout constants matched EXACTLY before this file existed — PADDING_X 16, HEADER_TOP 20,
-- HEADER_HEIGHT 54, DEFAULTS_W 110, ROW_VSPACER 8, the 10/6/26 section triple and the 0.492
-- button-pair inset are the same numbers settings/Panel.lua carried, and the breadcrumb separator
-- is byte-identical. So is the always-shown scrollbar patch's intent. That is what makes this a
-- migration rather than a redesign: nothing on screen is supposed to move.
--
-- ── WHAT THIS ADDON DECLINES, AND WHY ──────────────────────────────────────────────────────────
--
-- 1. The MultiCheck set picker (`settings.excludedSources`). The library has four widget makers and
--    an EditBox; an inverted set picker rendered as a wrapping InlineGroup of checkboxes is not one
--    of them. The row stays in the schema, so the CLI and every reset still see it, and
--    settings/Panel.lua draws it at the exact point in the flow it used to occupy — through
--    `afterGroup`, which fires after that group's last row is flushed. It draws nothing on the
--    generic path because it is `type = "table"` and `O.RenderField` returns nil for a type it does
--    not know — not because it carries `skipRender`, which it does not.
--
-- 2. `SetRenderer` on the AH Price page. The library's renderer contract is "re-run me and I redraw
--    the page", which means a `ClearScroll` releasing every AceGUI child back to the pool. That page
--    parents ELEVEN reusable row slots of raw FontStrings and Buttons to an AceGUI SimpleGroup's
--    frame, created once and repainted in place; releasing that group would orphan them. The
--    ~213-frame version of this page froze the client for ~1.7s on tab-transition and the pooling is
--    what fixed it (docs/settings-panel.md), so the page keeps its own OnShow. Everything else on it
--    — the canvas, the header, the Defaults button, the scroll, the section heading, the schema row
--    — is the library's.
--
-- 3. Core's window skin. See core/CoreSetup.lua and closed issue #19 (LIBKA0S-02).
--
-- ── LOAD ORDER ─────────────────────────────────────────────────────────────────────────────────
--   AFTER  core/CoreSetup.lua   — `print` routes through the shared printer.
--   BEFORE settings/Panel.lua   — that file takes NS.Options as a file-scope upvalue.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)

if not lib then
  -- Degrade, not error. `/lh config` is registered unconditionally, and NS.Panel:Register runs from
  -- OnInitialize whatever the install looks like, so every member settings/Panel.lua reaches for has
  -- to answer. A no-op page registry plus an honest line is the right shape: there is no settings
  -- panel, and saying so beats a Lua error in exactly the install this branch exists for.
  local function noop() end
  NS.Options = {
    CreatePanel = function() return { refreshers = {}, rebuilders = {} } end,
    EnsureDefaultsButton = noop, EnsureScroll = function() return nil end, ClearScroll = noop,
    Section = noop, AddSpacer = noop, AttachTooltip = noop, InlineButtonPair = noop,
    RenderField = noop, SessionCheckbox = noop, RenderRows = noop, RenderSchema = noop,
    RenderGrid = noop, SetRenderer = noop,
    RegisterOptionsPage = noop, CreateOptionsPanel = noop,
    OpenOptionsPanel = function()
      NS.Print(NS.LIBKA0S_MISSING .. ", so the settings panel is unavailable.")
    end,
    RestoreDefaults = noop, RestoreAllDefaults = noop,
    RefreshAllPanels = noop, RefreshScalars = noop, RefreshPanel = noop,
    PatchAlwaysShowScrollbar = noop,
    LSMValues = function() return function() return {} end end,
    __pages = function() return {} end,
    __panels = function() return {} end,
    __panelFor = function() return nil end,
    ROW_VSPACER = 8, SECTION_HEADING_H = 26, BUTTON_PAIR_REL = 0.492,
    AceGUI = nil,
  }
  return
end

NS.Options = lib:New({
  parentTitle   = "Ka0s Loot History",
  -- Named rather than anonymous so /framestack attributes the canvas to this addon and two addons
  -- cannot collide on it. The frame was anonymous before this adoption.
  mainPanelName = "LootHistorySettingsPanel",

  print = function(line) NS.Print(line) end,
  debug = function(tag, fmt, ...) if NS.Debug then NS.Debug(tag, fmt, ...) end end,

  -- The single write seam. A panel click takes exactly the path a slash command does — validate,
  -- write, debug line, onChange — which is the whole reason Schema:Set exists.
  get          = function(path) return NS.Schema:Get(path) end,
  set          = function(path, v) NS.Schema:Set(path, v) end,
  applyDefault = function(row) NS.Schema:Set(row.path, NS.Schema:Default(row.path)) end,

  -- This addon has no per-unit or per-page filter, so `filter` is ignored. `pageKey` maps onto the
  -- schema's `group`, which is what its section headings already were.
  rowsForPage = function(pageKey)
    local out = {}
    for _, row in ipairs(NS.Schema.Schema) do
      if row.group == pageKey then out[#out + 1] = row end
    end
    return out
  end,
  allRows = function() return NS.Schema.Schema end,

  -- Backs the color picker's 50 ms drag throttle. No schema row is a color today, so nothing
  -- reaches it — passed anyway because a future color row would otherwise commit every frame, and
  -- a missing throttle is invisible until someone drags a swatch.
  scheduleTimer = function(fn, delay)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn) end
  end,

  -- library-stack-§4: one LibStub resolution, stashed for every page file to reuse.
  onAceGUI = function(AceGUI) NS.AceGUI = AceGUI end,

  -- The landing page's body — logo, tagline and the slash-command rows. Late-bound through NS.Panel
  -- because that file loads AFTER this one (it takes NS.Options as a file-scope upvalue, so the
  -- order cannot be the other way round). The library routes it through SetRenderer, which is what
  -- gives the main page the same lazy first-show render, combat guard and dirty-re-render every
  -- sub-page has — none of which it had before.
  buildMain = function(ctx)
    if NS.Panel and NS.Panel.BuildMain then NS.Panel.BuildMain(ctx) end
  end,

  -- Deliberately NOT handed the addon's locale table. This addon translates nothing, and the
  -- Options module reads no descriptor `L` at all today — tests/test_libka0s.lua carries the
  -- tripwire that goes red the day it grows one.
})
