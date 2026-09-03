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
-- 2. NOTHING ANY MORE, on the renderer. The AH Price page used to keep its own `OnShow` rather than
--    going through `SetRenderer`: the library's renderer contract is "re-run me and I redraw the
--    page", which means a `ClearScroll` releasing every AceGUI child back to the pool, and that page
--    parented eleven reusable row slots of raw FontStrings and Buttons to an AceGUI SimpleGroup's
--    frame. The ~213-frame version of it froze the client for ~1.7s on tab-transition and the
--    pooling is what fixed it (docs/settings-panel.md).
--
--    R6 merged that page into General as a TAB, which made "keep your own OnShow" unavailable —
--    there is one page and one renderer now. The pooling is preserved by a different move: the price
--    host is a RAW frame this addon owns for the session, parked on the panel while another tab is
--    on screen and re-parented to a fresh placeholder each time its own tab is drawn. It is never an
--    AceGUI child, so ClearScroll cannot reclaim it, and nothing is allocated twice. See
--    settings/Panel.lua's buildAuctionTable.
--
-- 3. Core's window skin. See core/CoreSetup.lua and closed issue #19 (LIBKA0S-02).
--
-- ── LOAD ORDER ─────────────────────────────────────────────────────────────────────────────────
--   AFTER  core/CoreSetup.lua   — `print` routes through the shared printer.
--   BEFORE settings/Schema.lua  — LOAD-BEARING as of the Master controls adoption: that file calls
--                                 NS.Options.MasterControls at FILE LOAD to compose its first tab
--                                 (options-ui-§15), so NS.Options has to exist by then. Nothing here
--                                 resolves at load — every descriptor field below is a closure over
--                                 NS.Schema / NS.Panel — so the move costs nothing.
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

    -- ── the page chrome: tab strip and banner (options-ui-§13/§14) ────────────────────────────
    -- Arrived with LibKa0s v1.23.0 and the General page draws its strip from RenderTabbedSchema,
    -- so the degraded path has to answer for all of it. Nothing here can be DRAWN — every maker
    -- in the library refuses without AceGUI and EnsureScroll already answers nil — so the two
    -- builders answer nil and RenderTabbedSchema reports an empty tab list, which is exactly what
    -- the live one does when AceGUI is missing.
    SetChromeHeight = noop,
    TabStrip = function() return nil end,
    PageBanner = function() return nil end,
    RenderTabbedSchema = function() return {} end,

    -- ── the chrome block and the secondary strip (options-ui-§13/§14) ─────────────────────────
    -- Arrived with LibKa0s v1.24.0. This addon calls SubTabStrip (the Filters tab's three id
    -- lists) and never PageHeader — but a stub that omits a member the live table has is how a
    -- degraded install finds a nil where the live one finds a function, so both answer, and both
    -- answer what the live pair answers with no AceGUI: nil, having drawn nothing. The two seams
    -- around them are the strip's measured row pitch and the sub-strip ledger drain ClearScroll
    -- calls; a page with no chrome measures the same pitch every time and has nothing to drain.
    PageHeader          = function() return nil end,
    SubTabStrip         = function() return nil end,
    __releaseSubTabs    = noop,
    __tabArtHeight      = function() return 0 end,
    __resetTabArtHeight = noop,

    -- ── the schema composers (options-ui-§15/§16/§17) ─────────────────────────────────────────
    -- PURE FUNCTIONS returning arrays of ordinary schema rows: no widget, no AceGUI, no state.
    -- They still answer NOTHING here, and that is the honest shape rather than a shortfall. The
    -- product of a composer is DECLARATION -- rows that only a settings panel and a slash CLI read,
    -- and on this path both of those come from the same absent library. settings/Schema.lua
    -- therefore ships its Master controls block empty on a degraded install; every stored value it
    -- declares still exists, because defaults/Global.lua is what AceDB merges and modules read
    -- `NS.db.global.settings` directly (modules/Collector.lua, modules/Browser.lua) rather than
    -- through Schema:Get.
    --
    -- MasterControls returns TWO values -- the rows and the afterGroup hook that draws the closing
    -- button pair -- so the stub does too, or a host unpacking both finds a nil where a function
    -- goes.
    MasterControls = function() return {}, noop end,
    ColorPair      = function() return {} end,
    FontGroup      = function() return {} end,
    BorderGroup    = function() return {} end,
    BarGroup       = function() return {} end,

    -- The composers' published constants. Read off the instance by a host that renders one of the
    -- canonical enums itself; this addon reads MASTER_GROUP (settings/Schema.lua) and nothing else,
    -- but a scalar that answers nil on one path and a table on the other is the same trap the
    -- layout scalars below are published to avoid.
    FONT_FLAGS = {}, FONT_FLAGS_SORT = {},
    VISIBILITY_VALUES = {}, VISIBILITY_SORT = {},
    MASTER_GROUP = "Master controls",
    CLASS_COLOR_NOTE =
      "Not read while Use class color is on, except for its opacity, which always applies.",

    -- The strip's pure arithmetic. No call site in this addon reaches any of them —
    -- `grep -rn "Options\.__\(layoutTabs\|tabPlacement\|bannerBand\|tabBand\|scrollTopInset\|releaseChrome\)" core settings modules`
    -- returns nothing — but they are surface all the same, and a stub that omits a member the
    -- live table has is how a degraded install finds a nil where the live one finds a function.
    -- Each answers the value a page with NO chrome produces rather than nil: zero rows, zero
    -- band, and a scroll inset of the bare gap. `__scrollTopInset` restates CHROME_GAP for the
    -- same reason ROW_VSPACER and BUTTON_PAIR_REL below it do — the scalars are published
    -- precisely so a host measuring its own chrome never reads nil off this table.
    __layoutTabs     = function() return {} end,
    __tabPlacement   = function() return {}, 0 end,
    __bannerBand     = function() return 0 end,
    __tabBand        = function() return 0 end,
    __releaseChrome  = noop,
    __scrollTopInset = function(ctx) return 8 + ((ctx and ctx.chromeHeight) or 0) end,

    ROW_VSPACER = 8, SECTION_HEADING_H = 26, BUTTON_PAIR_REL = 0.492,
    CHROME_GAP = 8, TAB_H = 37, BANNER_H = 44,
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

  -- This addon has no per-unit or per-page filter, so `filter` is ignored. `pageKey` matches the
  -- row's `page` — the canvas subcategory — and NOT its `group`, which is now the TAB within that
  -- page (options-ui-§13). It matched `group` while every page held exactly one section and the
  -- two were the same string; General spans three tabs now, and matching on group would hand
  -- RenderTabbedSchema one tab's rows and let it conclude the page has one section.
  rowsForPage = function(pageKey)
    local out = {}
    for _, row in ipairs(NS.Schema.Schema) do
      if row.page == pageKey then out[#out + 1] = row end
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
