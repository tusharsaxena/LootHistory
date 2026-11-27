-- LibKa0s release pins: one case per vendored tag, pinning the minors that tag moved and the test
-- kit revision it paired with. Peeled out of tests/test_libka0s.lua on 2026-11-27 (the v1.118.0
-- re-vendor took that suite past layout-§1's 1500-line cap); the cases moved verbatim. When a later
-- tag moves a minor again, the older case's exact pin becomes a floor and the new case pins it.

local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue =
  T.test, T.assertEqual, T.assertTrue

-- v1.71.0 moves five minors and the kit, with no surface added: the chart clips its segments and
-- re-syncs the hover on every render, the autocomplete re-installs its hooks per call, a number
-- row refuses nan and the infinities, Env and OptionsIdList drop the bare-global addon-API rungs,
-- and kit revision 38's --list Totals leave declared skips out of Total.
test("v1.71.0: the vendored minors and the kit revision match the release", function()
  local W = T.mocks.LibStub("LibKa0s-Widgets-1.0", true)
  assertTrue(W ~= nil and type(W.MODULES) == "table", "Widgets missing: re-vendor v1.71.0")
  assertTrue(W.MODULES.WidgetsLineChart >= 3) -- 4 since v1.78.0, pinned there
  assertTrue(W.MODULES.WidgetsAutocomplete >= 2) -- 3 since v1.77.0, pinned there
  local S = T.mocks.LibStub("LibKa0s-Slash-1.0", true)
  assertTrue(S.MODULES.Slash >= 20) -- 21 since v1.84.0, pinned there
  assertEqual(S.MODULES.SlashParse, 2)
  assertEqual(T.mocks.LibStub("LibKa0s-Env-1.0", true).MODULES.Env, 2)
  assertTrue(T.mocks.LibStub("LibKa0s-Options-1.0", true).MODULES.OptionsIdList >= 4) -- 5 since v1.75.0, pinned there
  assertTrue(T.KIT_VERSION >= 38) -- 41 since v1.75.0, pinned there
end)

-- v1.75.0 (from v1.71.0, the three releases between never vendored here): Widgets 13 (W.SearchBox,
-- W.TestStrip), Item 3 (Item.BonusIDsFromLink), the comment-only Core 11, DebugLog 20,
-- OptionsIdList 5 and PerfPanel 7, DebugLogDiagnostics 3, OptionsTabs 9 (O.__releaseChrome gone),
-- Options 29 with OptionsDrawer 1 (v1.73.0), Media 5 with MediaIcons 1 (v1.74.0), Perf 15
-- (v1.72.0), the new majors Glow 1 and Sim 1 (SimTimeline 1, SimPanel 1), and kit revision 41.
-- W.StepPanel was withdrawn before release, so no WidgetsStepPanel file ships.
test("v1.75.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.75.0")
    return lib.MODULES, lib
  end
  assertTrue(modules("LibKa0s-Core-1.0").Core >= 11) -- 12 since v1.77.0, pinned there
  assertEqual(modules("LibKa0s-Item-1.0").Item, 3)
  assertTrue(modules("LibKa0s-Glow-1.0").Glow >= 1) -- 2 since v1.85.0, pinned there
  local media = modules("LibKa0s-Media-1.0")
  assertTrue(media.Media >= 5) -- 8 since v1.78.0 (re-cut), pinned there
  assertEqual(media.MediaIcons, 1)
  local widgets = modules("LibKa0s-Widgets-1.0")
  assertTrue(widgets.Widgets >= 13) -- 14 since v1.76.0, pinned there
  assertTrue(widgets.WidgetsStepPanel == nil, "W.StepPanel was withdrawn before v1.75.0 shipped")
  local debugLog = modules("LibKa0s-DebugLog-1.0")
  assertTrue(debugLog.DebugLog >= 20) -- 21 since v1.77.0, pinned there
  assertTrue(debugLog.DebugLogDiagnostics >= 3) -- 4 since v1.78.0, pinned there
  local options = modules("LibKa0s-Options-1.0")
  assertTrue(options.Options >= 29) -- 30 since v1.77.0, pinned there
  assertTrue(options.OptionsIdList >= 5) -- 6 since v1.78.0, pinned there
  assertTrue(options.OptionsTabs >= 9) -- 10 since v1.78.0, pinned there
  assertTrue(options.OptionsDrawer >= 1) -- 2 since v1.78.0, pinned there
  -- O.Drawer attaches to each instance lib:New builds, not to the module table LibStub answers.
  assertTrue(type(NS.Options.Drawer) == "function", "O.Drawer missing: OptionsDrawer did not attach")
  local perf = modules("LibKa0s-Perf-1.0")
  assertTrue(perf.Perf >= 15) -- 16 since v1.92.0, pinned there
  assertTrue(perf.PerfPanel >= 7) -- 8 since v1.76.0 (LK-91), pinned there
  local sim, S = modules("LibKa0s-Sim-1.0")
  -- Sim 2 / SimTimeline 2: the local v1.75.0 tag moved to carry LK-26 (Start reads scenarios live).
  -- SimPanel 2: it moved again to carry LK-27 (the picker reads its scenario at use).
  assertTrue(sim.Sim >= 2) -- 3 since v1.105.0, pinned there
  assertTrue(sim.SimTimeline >= 2) -- 3 since v1.76.0, pinned there
  assertTrue(sim.SimPanel >= 2) -- 3 since v1.75.1, pinned there
  assertEqual(S.__timelineShellMinor, S.MINOR, "SimTimeline is not paired on the Sim shell's minor")
  assertEqual(S.__panelShellMinor, S.MINOR, "SimPanel is not paired on the Sim shell's minor")
  assertTrue(T.KIT_VERSION >= 41) -- 42 since v1.77.0, pinned there
end)

-- v1.75.1: SimPanel 3 (a disabled step row or control still shows its tip: the played steps' tips,
-- this addon's `/lh sim` loot step among them, drew nothing in game); nothing else moves.
test("v1.75.1: the vendored minors and the kit revision match the release", function()
  local S = T.mocks.LibStub("LibKa0s-Sim-1.0", true)
  assertTrue(S ~= nil and type(S.MODULES) == "table", "Sim missing: re-vendor v1.75.1")
  assertTrue(S.MODULES.SimPanel >= 3) -- 4 since v1.75.2, pinned there
  assertTrue(S.MODULES.Sim >= 2) -- 3 since v1.105.0, pinned there
  assertTrue(S.MODULES.SimTimeline >= 2) -- 3 since v1.76.0, pinned there
  assertTrue(T.KIT_VERSION >= 41) -- 42 since v1.77.0, pinned there
end)

-- v1.75.2: SimPanel 4 (the picker's scenario dropdown takes the width the bar leaves, so a long
-- scenario name no longer wraps); nothing else moves.
test("v1.75.2: the vendored minors and the kit revision match the release", function()
  local S = T.mocks.LibStub("LibKa0s-Sim-1.0", true)
  assertTrue(S ~= nil and type(S.MODULES) == "table", "Sim missing: re-vendor v1.75.2")
  assertTrue(S.MODULES.SimPanel >= 4) -- 5 since v1.76.0, pinned there
  assertTrue(S.MODULES.Sim >= 2) -- 3 since v1.105.0, pinned there
  assertTrue(S.MODULES.SimTimeline >= 2) -- 3 since v1.76.0, pinned there
  assertTrue(T.KIT_VERSION >= 41) -- 42 since v1.77.0, pinned there
end)

-- v1.76.0: SimTimeline 3 and SimPanel 5 (a typed or clicked start plays on its own; Run all is gone,
-- the controls are Pause/Resume, Restart and Stop), Widgets 14 (W.TestStrip's `kind = "sim"`
-- flavor, strip.kind); Sim 2 and every other file unchanged, kit revision 41 unchanged. The local
-- tag then moved for LK-91 (9949368 -> 7e81ff7): PerfPanel 8 and a same-minor SimPanel 5 bound a
-- step-panel label short of the command column, so a long label truncates instead of overlapping.
test("v1.76.0: the vendored minors and the kit revision match the release", function()
  local S = T.mocks.LibStub("LibKa0s-Sim-1.0", true)
  assertTrue(S ~= nil and type(S.MODULES) == "table", "Sim missing: re-vendor v1.76.0")
  assertTrue(S.MODULES.Sim >= 2) -- 3 since v1.105.0, pinned there
  assertEqual(S.MODULES.SimTimeline, 3)
  assertTrue(S.MODULES.SimPanel >= 5) -- 6 since v1.77.0, pinned there
  assertEqual(S.__timelineShellMinor, S.MINOR, "SimTimeline is not paired on the Sim shell's minor")
  assertEqual(S.__panelShellMinor, S.MINOR, "SimPanel is not paired on the Sim shell's minor")
  local W = T.mocks.LibStub("LibKa0s-Widgets-1.0", true)
  assertTrue(W ~= nil and type(W.MODULES) == "table", "Widgets missing: re-vendor v1.76.0")
  assertTrue(W.MODULES.Widgets >= 14) -- 15 since v1.77.0, pinned there
  local P = T.mocks.LibStub("LibKa0s-Perf-1.0", true)
  assertTrue(P ~= nil and type(P.MODULES) == "table", "Perf missing: re-vendor v1.76.0")
  assertTrue(P.MODULES.PerfPanel >= 8) -- 9 since v1.77.0, pinned there
  assertTrue(T.KIT_VERSION >= 41) -- 42 since v1.77.0, pinned there
end)

-- v1.77.0: Core 12 (Core.RaiseStaticPopups), DebugLog 21, PerfPanel 9 and SimPanel 6 (the debug
-- console, perf panel and sim panel are toplevel and re-raise a shown StaticPopup), Widgets 15 and
-- WidgetsAutocomplete 3 (menus clamped to the screen), WidgetsDragHandle 5 (a level offset and
-- parent alpha), Options 30 with OptionsIds 3, OptionsCombat 2, OptionsCompose 11 (O.StrataTooltip at
-- 8; Master controls notes and the Master opacity label at 9, group tooltips at 10, O.ResetAllTooltip
-- at 11, when the tag moved for the settings layout)
-- and the new twelfth file OptionsKeybinds 4 (the Keybindings tab; one key button and Clear per row
-- at 4, when the tag moved again for the owner's follow-up), and kit revision 42 (binding mock,
-- frame-layer recorder, Bindings.xml check). Every other file unchanged.
test("v1.77.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.77.0")
    return lib.MODULES
  end
  assertTrue(modules("LibKa0s-Core-1.0").Core >= 12) -- 13 since v1.78.0, pinned there
  assertTrue(modules("LibKa0s-DebugLog-1.0").DebugLog >= 21) -- 22 since v1.78.0, pinned there
  assertTrue(modules("LibKa0s-Perf-1.0").PerfPanel >= 9) -- 10 since v1.78.0, pinned there
  local sim = modules("LibKa0s-Sim-1.0")
  assertTrue(sim.Sim >= 2) -- 3 since v1.105.0, pinned there
  assertEqual(sim.SimTimeline, 3)
  assertTrue(sim.SimPanel >= 6) -- 7 since v1.78.0, pinned there
  local widgets = modules("LibKa0s-Widgets-1.0")
  assertTrue(widgets.Widgets >= 15) -- 16 since v1.78.0, pinned there
  assertTrue(widgets.WidgetsDragHandle >= 5) -- 6 since v1.78.0, pinned there
  assertTrue(widgets.WidgetsAutocomplete >= 3) -- 4 since v1.78.0, pinned there
  local options = modules("LibKa0s-Options-1.0")
  assertTrue(options.Options >= 30) -- 33 since v1.78.0, pinned there
  assertTrue(options.OptionsIds >= 3) -- 4 since v1.78.0, pinned there
  assertTrue(options.OptionsCombat >= 2) -- 3 since v1.78.0, pinned there
  assertTrue(options.OptionsCompose >= 11) -- 12 since v1.78.0, pinned there
  assertTrue(options.OptionsKeybinds >= 4) -- 5 since v1.78.0, pinned there
  -- The tab's members and the strata tooltip attach to each instance lib:New builds.
  assertTrue(type(NS.Options.KeybindingsTab) == "function", "O.KeybindingsTab missing: OptionsKeybinds did not attach")
  assertTrue(type(NS.Options.StrataTooltip) == "function", "O.StrataTooltip missing: OptionsCompose 8 did not attach")
  assertTrue(type(NS.Options.ResetAllTooltip) == "function", "O.ResetAllTooltip missing: OptionsCompose 11 did not attach")
  assertTrue(T.KIT_VERSION >= 42) -- 43 since v1.78.0, pinned there
end)

-- v1.78.0: skinning, leg 1. The new major LibKa0s-Skin-1.0 (Skin 4, SkinDefs 4, SkinPaint 2,
-- SkinPaintExtras 1, SkinPaintControls 1, SkinEUI 1, SkinAce 1); Core 13 and Widgets 16 (a skin
-- owner on the library's controls) with WidgetsReorder 2, WidgetsDragHandle 6, WidgetsLineChart 4,
-- WidgetsAutocomplete 4 and the new WidgetsCopyWindow 1; Media 6 (the five OFL skin faces and the
-- Glass art); DebugLog 22, DebugLogDiagnostics 4 and the new DebugLogWindow 1; Options 33 with
-- OptionsRegistry 3, OptionsWidgets 35, OptionsIds 4, OptionsIdList 6, OptionsTabs 10,
-- OptionsCombat 3, OptionsCompose 12 (fromSkin), OptionsScroll 6, OptionsNav 3, OptionsDrawer 2,
-- OptionsKeybinds 5 and the new thirteenth file OptionsAppearance 1 (the Appearance tab);
-- PerfPanel 10 and SimPanel 7 (the tool windows follow their owner); kit revision 43 (the paint
-- recorder). Every other file unchanged. The local tag was re-cut four times before it shipped
-- (fb7b7a3 -> a3790f4 -> 7ec0e0a -> 65a23cb -> 7bc3e9b): Media 7 skips a key LibSharedMedia
-- already holds (LK-A1), SkinDefs 5 adds the bind-state and danger Semantic tokens (LK-A2),
-- SkinDefs 6 adds eleven tokens for the rest of LootHistory's constants (LK-A3), and SkinPaint 3
-- puts an EditBox's face back by path, never its anonymous font object (LK-A4: the Forever ->
-- Midnight client crash). Re-cut a fifth time (-> fe7c3fc) for the owner's skin notes
-- (SF-01..SF-14 of Ka0sAddonsCommonTasks docs/2026-10-26-SKIN_FEEDBACK/): SkinDefs 7 retunes the
-- skins, SkinPaint 4 makes font sizes relative to Ka0s Default's, SkinPaintControls 2 dims a
-- disabled button and squares Ka0s Default's checkbox. Re-cut a sixth time (-> 8291ecc) for the
-- owner's second round (SF-16..SF-22): SkinPaint 5 and SkinPaintExtras 2 give every labeled string
-- the skin's face (dark labels shadowless), SkinPaintControls 3 draws one slider shape. Re-cut again
-- (-> 55883fa) for the owner's fifth round (R5-01..R5-04 of docs/2026-10-28-SKIN_ROUND5/): a scroll
-- corridor and one flat knob (SkinDefs 10, SkinPaintControls 7, OptionsScroll 8), the window edge
-- on a holder above its children (SkinPaint 9), a font family per skin (Media 8, SkinDefs 11), and
-- arrows in each skin's accent (SkinDefs 12, SkinPaint 10, SkinPaintControls 8); then (-> b2f6ec6)
-- Azeroth's window frame as thin as the others' (SkinDefs 13, R5-09). The kit stays at 43.
test("v1.78.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.78.0")
    return lib.MODULES
  end
  assertTrue(modules("LibKa0s-Core-1.0").Core >= 13) -- 14 since v1.81.0, pinned there
  local media = modules("LibKa0s-Media-1.0")
  assertTrue(media.Media >= 8) -- 9 since v1.79.0, pinned there
  assertEqual(media.MediaIcons, 1)
  local skin = modules("LibKa0s-Skin-1.0")
  assertTrue(skin.Skin >= 5) -- 6 since v1.79.0, pinned there
  assertTrue(skin.SkinDefs >= 13) -- 14 since v1.79.0, pinned there
  assertTrue(skin.SkinPaint >= 10) -- 11 since v1.80.0, 12 since v1.81.0, pinned there
  assertTrue(skin.SkinPaintExtras >= 3) -- 4 since v1.79.0, pinned there
  assertTrue(skin.SkinPaintControls >= 8) -- 9 since v1.80.0, 10 since v1.81.0, pinned there
  assertTrue(skin.SkinEUI >= 1) -- 2 since v1.80.0, pinned there
  assertTrue(skin.SkinAce >= 3) -- 4 since v1.80.0, pinned there
  local widgets = modules("LibKa0s-Widgets-1.0")
  assertTrue(widgets.Widgets >= 16) -- 17 since v1.81.0, pinned there
  assertTrue(widgets.WidgetsReorder >= 2) -- 3 since v1.81.0, pinned there
  assertTrue(widgets.WidgetsDragHandle >= 6) -- 7 since v1.81.0, pinned there
  assertTrue(widgets.WidgetsLineChart >= 4) -- 5 since v1.81.0, pinned there
  assertTrue(widgets.WidgetsAutocomplete >= 4) -- 5 since v1.81.0, pinned there
  assertTrue(widgets.WidgetsCopyWindow >= 1) -- 2 since v1.81.0, pinned there
  local debugLog = modules("LibKa0s-DebugLog-1.0")
  assertTrue(debugLog.DebugLog >= 22) -- 23 since v1.105.0, pinned there
  assertTrue(debugLog.DebugLogDiagnostics >= 4) -- 5 since v1.79.0, pinned there
  assertTrue(debugLog.DebugLogWindow >= 1) -- 2 since v1.81.0, pinned there
  local options = modules("LibKa0s-Options-1.0")
  assertTrue(options.Options >= 33) -- 34 since v1.79.0, pinned there
  assertTrue(options.OptionsRegistry >= 3) -- 4 since v1.79.0, pinned there
  assertTrue(options.OptionsWidgets >= 35) -- 36 since v1.81.0, pinned there
  assertTrue(options.OptionsIds >= 4) -- 5 since v1.81.0, pinned there
  assertTrue(options.OptionsIdList >= 6) -- 7 since v1.81.0, pinned there
  assertTrue(options.OptionsTabs >= 10) -- 11 since v1.81.0, pinned there
  assertTrue(options.OptionsCombat >= 3) -- 4 since v1.85.0, pinned there
  assertTrue(options.OptionsCompose >= 12) -- 13 since v1.80.0, pinned there
  assertTrue(options.OptionsScroll >= 8) -- 9 since v1.81.0, pinned there
  assertTrue(options.OptionsNav >= 3) -- 4 since v1.81.0, pinned there
  assertTrue(options.OptionsDrawer >= 2) -- 3 since v1.81.0, pinned there
  assertTrue(options.OptionsKeybinds >= 5) -- 6 since v1.81.0, pinned there
  assertTrue(options.OptionsAppearance >= 2) -- 3 since v1.79.0, pinned there
  -- The Appearance tab's two members attach to each instance lib:New builds.
  assertTrue(type(NS.Options.AppearanceTab) == "function", "O.AppearanceTab missing: OptionsAppearance did not attach")
  assertTrue(type(NS.Options.AppearanceRows) == "function", "O.AppearanceRows missing: OptionsAppearance did not attach")
  assertTrue(modules("LibKa0s-Perf-1.0").PerfPanel >= 10) -- 11 since v1.81.0, pinned there
  assertTrue(modules("LibKa0s-Sim-1.0").SimPanel >= 7) -- 8 since v1.81.0, pinned there
  assertTrue(T.KIT_VERSION >= 43) -- 44 since v1.79.0, pinned there
end)

-- v1.79.0 (unreleased, branch feat/2026-10-28-skin-overrides-picker): the font and texture
-- overrides and the first-run skin picker (LibKa0s#63, #64). Skin 6 (GetOverride, SetOverride, the
-- overrides laid over the tokens, WriteChoice's media), SkinPaintExtras 4 (S.BarTexture),
-- OptionsAppearance 3 (the tab labeled "Skin" and its Font and texture section), Options 34 with
-- the new fourteenth file OptionsSkinPicker 1 (O.SkinPicker, O.HideSkinPicker), DebugLogDiagnostics
-- 5 (Toast in the report's major list) and the new major LibKa0s-Toast-1.0 (Toast 1); kit revision
-- 44 (StatusBar fidelity in the paint mock). Then SO-06 and PK-02 on the same branch: Media 9 (the
-- Oxanium faces and the generated "Ka0s Default" bar), SkinDefs 14 (Ka0s Default draws them; every
-- other skin keeps Friz Quadrata and the Blizzard bar), OptionsRegistry 4 (O.OpenOptionsPanel takes
-- a page key), and OptionsAppearance 3 and OptionsSkinPicker 1 amended in place (the "Look" heading;
-- the picker previews, Apply saves, one window across addons). Every other file unchanged.
test("v1.79.0: the vendored minors and the kit revision match the branch", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.79.0")
    return lib.MODULES
  end
  local skin = modules("LibKa0s-Skin-1.0")
  assertTrue(skin.Skin >= 6) -- 7 since v1.80.0, 8 since v1.81.0, pinned there
  assertTrue(skin.SkinDefs >= 14) -- 15 since v1.80.0, 16 since v1.81.0, pinned there
  assertTrue(skin.SkinPaintExtras >= 4) -- 5 since v1.80.0, 6 since v1.81.0, pinned there
  assertTrue(modules("LibKa0s-Media-1.0").Media >= 9) -- 10 since v1.82.0, pinned there
  assertTrue(modules("LibKa0s-DebugLog-1.0").DebugLogDiagnostics >= 5) -- 6 since v1.84.0, pinned there
  assertTrue(modules("LibKa0s-Toast-1.0").Toast >= 1) -- 2 since v1.85.0, pinned there
  local options = modules("LibKa0s-Options-1.0")
  assertTrue(options.Options >= 34) -- 37 since v1.84.0, pinned there
  assertTrue(options.OptionsRegistry >= 4) -- 5 since v1.92.0, pinned there
  assertTrue(options.OptionsAppearance >= 3) -- 4 since v1.82.0, pinned there
  assertTrue(options.OptionsSkinPicker >= 1) -- 2 since v1.81.0, pinned there
  assertTrue(type(NS.Options.SkinPicker) == "function", "O.SkinPicker missing: OptionsSkinPicker did not attach")
  assertTrue(type(NS.Options.HideSkinPicker) == "function", "O.HideSkinPicker missing: OptionsSkinPicker did not attach")
  local Skin = T.mocks.LibStub("LibKa0s-Skin-1.0", true)
  assertTrue(type(Skin.GetOverride) == "function" and type(Skin.SetOverride) == "function",
    "Skin:GetOverride / Skin:SetOverride missing: re-vendor v1.79.0")
  assertTrue(T.KIT_VERSION >= 44) -- 45 since v1.82.0, pinned there
end)

-- v1.80.0 (the skinning rollout's library half; vendored here only as the step to v1.81.0, since
-- this addon went from v1.79.0 straight to v1.81.0): owner tokens, the slot remap and the icon-border
-- family (Skin 7, SkinDefs 15, SkinPaint 11, SkinPaintExtras 5, SkinPaintControls 9, SkinEUI 2,
-- OptionsCompose 13), Skin:AliasAceType at the library level, and TreeGroup painting (SkinAce 4).
-- All opt-in; this addon adopts none, so it draws what it drew. The kit stays at 44.
test("v1.80.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.81.0")
    return lib.MODULES
  end
  local skin = modules("LibKa0s-Skin-1.0")
  assertTrue(skin.Skin >= 7) -- 8 since v1.81.0, pinned there
  assertTrue(skin.SkinDefs >= 15) -- 16 since v1.81.0, pinned there
  assertTrue(skin.SkinPaint >= 11) -- 12 since v1.81.0, pinned there
  assertTrue(skin.SkinPaintExtras >= 5) -- 6 since v1.81.0, pinned there
  assertTrue(skin.SkinPaintControls >= 9) -- 10 since v1.81.0, pinned there
  assertTrue(skin.SkinEUI >= 2) -- 3 since v1.85.0, pinned there
  assertTrue(skin.SkinAce >= 4) -- 6 since v1.84.0, pinned there
  assertTrue(modules("LibKa0s-Options-1.0").OptionsCompose >= 13) -- 14 since v1.82.0, pinned there
  local Skin = T.mocks.LibStub("LibKa0s-Skin-1.0", true)
  assertTrue(type(Skin.AliasAceType) == "function", "Skin:AliasAceType missing: re-vendor v1.81.0")
  assertTrue(T.KIT_VERSION >= 44) -- 45 since v1.82.0, pinned there
end)

-- v1.81.0 (Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS/, LH-RV): the skin library
-- follow-ups. Skin 8 (Ignore fonts reaches hud.font / hud.outline, ResetToSkin's absent companion,
-- the public Skin:DrawsKey), SkinDefs 16 (the client's exact q.* colors, a HUD face per skin, the
-- new tokens list.hoverArt, icon.grip, gtip.footer), SkinPaint 12, SkinPaintExtras 6 and
-- SkinPaintControls 10 (the stock look retired, S.Text's and the controls' panel scope, the close
-- button's own tint); the Widgets controls, the reorder list (panel-scoped by default), the drag
-- handle's tooltip, the copy window; the settings chrome (OptionsWidgets 36, OptionsIds 5,
-- OptionsIdList 7, OptionsTabs 11, OptionsScroll 9, OptionsNav 4, OptionsDrawer 3, OptionsKeybinds 6)
-- and the picker ("Choose a skin", OptionsSkinPicker 2); the tool windows (Core 14, DebugLogWindow 2,
-- PerfPanel 11, SimPanel 8). The kit stays at 44.
test("v1.81.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.81.0")
    return lib.MODULES
  end
  local skin = modules("LibKa0s-Skin-1.0")
  assertTrue(skin.Skin >= 8) -- 9 since v1.82.0, pinned there
  assertTrue(skin.SkinDefs >= 16) -- 17 since v1.82.0, pinned there
  assertTrue(skin.SkinPaint >= 12) -- 13 since v1.82.0, pinned there
  assertTrue(skin.SkinPaintExtras >= 6) -- 7 since v1.82.0, pinned there
  assertTrue(skin.SkinPaintControls >= 10) -- 11 since v1.82.0, pinned there
  local widgets = modules("LibKa0s-Widgets-1.0")
  assertTrue(widgets.Widgets >= 17) -- 20 since v1.85.0, pinned there
  assertTrue(widgets.WidgetsReorder >= 3) -- 5 since v1.85.0, pinned there
  assertTrue(widgets.WidgetsDragHandle >= 7) -- 8 since v1.82.0, pinned there
  assertTrue(widgets.WidgetsLineChart >= 5) -- 6 since v1.85.0, pinned there
  assertTrue(widgets.WidgetsAutocomplete >= 5) -- 6 since v1.85.0, pinned there
  assertTrue(widgets.WidgetsCopyWindow >= 2) -- 4 since v1.85.0, pinned there
  local options = modules("LibKa0s-Options-1.0")
  assertTrue(options.OptionsWidgets >= 36) -- 37 since v1.82.0, pinned there
  assertTrue(options.OptionsIds >= 5) -- 6 since v1.84.0, pinned there
  assertTrue(options.OptionsIdList >= 7) -- 8 since v1.85.0, pinned there
  assertTrue(options.OptionsTabs >= 11) -- 13 since v1.84.0, pinned there
  assertTrue(options.OptionsScroll >= 9) -- 10 since v1.84.0, pinned there
  assertTrue(options.OptionsNav >= 4) -- 5 since v1.85.0, pinned there
  assertTrue(options.OptionsDrawer >= 3) -- 4 since v1.84.0, pinned there
  assertTrue(options.OptionsKeybinds >= 6) -- 7 since v1.85.0, pinned there
  assertTrue(options.OptionsSkinPicker >= 2) -- 3 since v1.82.0, pinned there
  assertTrue(modules("LibKa0s-Core-1.0").Core >= 14) -- 15 since v1.85.0, pinned there
  assertTrue(modules("LibKa0s-DebugLog-1.0").DebugLogWindow >= 2) -- 3 since v1.85.0, pinned there
  assertTrue(modules("LibKa0s-Perf-1.0").PerfPanel >= 11) -- 12 since v1.85.0, pinned there
  assertTrue(modules("LibKa0s-Sim-1.0").SimPanel >= 8) -- 9 since v1.84.0, pinned there
  local Skin = T.mocks.LibStub("LibKa0s-Skin-1.0", true)
  assertTrue(type(Skin.DrawsKey) == "function", "Skin:DrawsKey missing: re-vendor v1.81.0")
  assertTrue(T.KIT_VERSION >= 44) -- 45 since v1.82.0, pinned there
end)
-- v1.82.0 (Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, LH-01): the skin fonts
-- and feedback batch. Media 10 (Prototype, Expressway and Fira Sans Medium in; Inter, Oxanium and
-- Fira Sans Regular out), Skin 9 (the font outline: GetOutline, SetOutline, OUTLINE_MODES; VOCAB
-- gains FontFlags and HudFontSize), SkinDefs 17 (re-measured sizes, the per-skin HUD factor),
-- SkinPaint 13 and SkinPaintControls 11 (a label's alpha restored when enabled), SkinPaintExtras 7
-- (S.FontFlags, S.HudFontSize), WidgetsDragHandle 8 (the strip re-fits with 2 px slack), the
-- settings chrome (OptionsWidgets 37 with the new fifteenth file OptionsSwitch 1, OptionsCompose 14's
-- From skin flags, OptionsAppearance 4's Font outline and reset buttons, OptionsSkinPicker 3's
-- O.SkinVerb), and kit revision 45 (glyphs.lua's display-glyph guard).
test("v1.82.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.82.0")
    return lib.MODULES
  end
  assertTrue(modules("LibKa0s-Media-1.0").Media >= 10) -- 11 since v1.83.0, pinned there
  local skin = modules("LibKa0s-Skin-1.0")
  assertTrue(skin.Skin >= 9) -- 10 since v1.83.0, pinned there
  assertTrue(skin.SkinDefs >= 17) -- 18 since v1.83.0, pinned there
  assertTrue(skin.SkinPaint >= 13) -- 16 since v1.85.0, pinned there
  assertTrue(skin.SkinPaintExtras >= 7) -- 15 since v1.85.0, pinned there
  assertTrue(skin.SkinPaintControls >= 11) -- 14 since v1.85.0, pinned there
  assertTrue(modules("LibKa0s-Widgets-1.0").WidgetsDragHandle >= 8) -- 10 since v1.84.0, pinned there
  local options = modules("LibKa0s-Options-1.0")
  assertTrue(options.OptionsWidgets >= 37) -- 38 since v1.83.0, pinned there
  assertEqual(options.OptionsSwitch, 1)
  assertTrue(options.OptionsCompose >= 14) -- 16 since v1.84.0, pinned there
  assertTrue(options.OptionsAppearance >= 4) -- 5 since v1.83.0, pinned there
  assertTrue(options.OptionsSkinPicker >= 3) -- 4 since v1.83.0, pinned there
  assertTrue(type(NS.Options.SkinVerb) == "function", "O.SkinVerb missing: OptionsSkinPicker did not attach")
  local Skin = T.mocks.LibStub("LibKa0s-Skin-1.0", true)
  assertTrue(type(Skin.SetOutline) == "function" and type(Skin.GetOutline) == "function",
    "Skin:SetOutline / Skin:GetOutline missing: re-vendor v1.82.0")
  assertTrue(type(NS.Skin.FontFlags) == "function" and type(NS.Skin.HudFontSize) == "function",
    "S.FontFlags / S.HudFontSize missing: re-vendor v1.82.0")
  assertTrue(T.KIT_VERSION >= 45) -- 46 since v1.83.0, pinned there
end)
-- v1.83.0 (Ka0sAddonsCommonTasks docs/2026-10-31-FONT_PICKERS_AND_SKIN_FACES, LH-F01): the font
-- pickers and skin faces batch. Media 11 (fourteen more faces), Skin 10 (the outline default moves
-- to "hud"), SkinDefs 18 (the new faces, re-measured), OptionsWidgets 38, OptionsAppearance 5,
-- OptionsSkinPicker 4 ("Skin's default"), the new sixteenth file OptionsMedia 1 (the Ka0sMedia_*
-- AceGUI types) and kit revision 46.
test("v1.83.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.83.0")
    return lib.MODULES
  end
  assertTrue(modules("LibKa0s-Media-1.0").Media >= 11) -- 12 since v1.85.0, pinned there
  local skin = modules("LibKa0s-Skin-1.0")
  assertTrue(skin.Skin >= 10) -- 11 since v1.84.0, pinned there
  assertTrue(skin.SkinDefs >= 18) -- 19 since v1.84.0, pinned there
  local options = modules("LibKa0s-Options-1.0")
  assertTrue(options.OptionsWidgets >= 38) -- 41 since v1.84.0, pinned there
  assertTrue(options.OptionsAppearance >= 5) -- 6 since v1.85.0, pinned there
  assertTrue(options.OptionsSkinPicker >= 4) -- 5 since v1.84.0, pinned there
  assertTrue(options.OptionsMedia >= 1) -- 3 since v1.84.0, pinned there
  assertEqual(T.mocks.LibStub("LibKa0s-Skin-1.0", true).OUTLINE_DEFAULT, "hud")
  assertTrue(T.KIT_VERSION >= 46) -- 47 since v1.84.0, pinned there
end)
-- v1.84.0 (Ka0sAddonsCommonTasks docs/2026-10-31-FINDINGS_REMEDIATION/M2_LIBRARY_RELEASE.md): the
-- peels, the flow seams and note row (LibKa0s#59), the drag strip's fit (#68), the new major
-- LibKa0s-Charts-1.0 (#66, Charts 1, ChartsRender 1), and kit revision 47. The tag was re-cut for the
-- owner's one-picker ruling (LibKa0s#73): Options 37, OptionsWidgets 41, OptionsCompose 16,
-- OptionsScroll 10, OptionsMedia 3, OptionsDrawer 4 and SkinAce 6.
test("v1.84.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.84.0")
    return lib.MODULES
  end
  local skin = modules("LibKa0s-Skin-1.0")
  assertTrue(skin.Skin >= 11) -- 14 since v1.85.0, pinned there
  assertEqual(skin.SkinOwnerTokens, 1)
  assertTrue(skin.SkinDefs >= 19) -- 24 since v1.85.0, pinned there
  assertTrue(skin.SkinDefsOthers >= 1) -- 6 since v1.85.0, pinned there
  assertTrue(skin.SkinAce >= 6) -- 9 since v1.85.0, pinned there
  local options = modules("LibKa0s-Options-1.0")
  assertTrue(options.Options >= 37) -- 38 since v1.93.0, pinned there
  assertTrue(options.OptionsWidgets >= 41) -- 44 since v1.85.0, pinned there
  assertTrue(options.OptionsFlow >= 2) -- 3 since v1.92.0, pinned there
  assertTrue(options.OptionsIds >= 6) -- 7 since v1.85.0, pinned there
  assertTrue(options.OptionsIdSuggest >= 1) -- 2 since v1.85.0, pinned there
  assertTrue(options.OptionsTabs >= 13) -- 15 since v1.85.0, pinned there
  assertTrue(options.OptionsTabbed >= 2) -- 3 since v1.92.0, pinned there
  assertTrue(options.OptionsCompose >= 16) -- 17 since v1.85.0, pinned there
  assertTrue(options.OptionsScroll >= 10) -- 13 since v1.85.0, pinned there
  assertTrue(options.OptionsMedia >= 3) -- 4 since v1.85.0, pinned there
  assertTrue(options.OptionsDrawer >= 4) -- 5 since v1.85.0, pinned there
  assertTrue(options.OptionsSkinPicker >= 5) -- 7 since v1.85.0, pinned there
  assertEqual(options.OptionsSkinPickerRows, 1)
  assertEqual(modules("LibKa0s-Schema-1.0").Schema, 3)
  assertTrue(modules("LibKa0s-Slash-1.0").Slash >= 21) -- 22 since v1.92.0, pinned there
  assertTrue(modules("LibKa0s-Widgets-1.0").WidgetsDragHandle >= 10) -- 12 since v1.85.0, pinned there
  assertTrue(modules("LibKa0s-DebugLog-1.0").DebugLogDiagnostics >= 6) -- 7 since v1.89.0, pinned there
  assertTrue(modules("LibKa0s-Sim-1.0").SimPanel >= 9) -- 10 since v1.85.0, pinned there
  assertTrue(modules("LibKa0s-Sim-1.0").SimPanelRender >= 1) -- 2 since v1.85.0, pinned there
  local charts = modules("LibKa0s-Charts-1.0")
  assertTrue(charts.Charts >= 1) -- 2 since v1.105.0, pinned there
  assertTrue(charts.ChartsRender >= 1) -- 2 since v1.108.0, pinned there
  assertTrue(T.KIT_VERSION >= 47) -- 49 since v1.85.0, pinned there
end)
-- v1.85.0 (Ka0sAddonsCommonTasks docs/2026-11-01-FULL_SKINNING/): the full skinning library release.
-- The tag is local until the owner's go-ahead. This addon takes its look from the copy (the tooltip
-- lines, the scroll step buttons, the 30 high title bands) and its host half in FS-LH-FIX.
test("v1.85.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.85.0")
    return lib.MODULES
  end
  assertTrue(modules("LibKa0s-Core-1.0").Core >= 15) -- 16 since v1.90.0 (pixel edges), pinned there
  local glow = modules("LibKa0s-Glow-1.0")
  assertEqual(glow.Glow, 2)
  local toast = modules("LibKa0s-Toast-1.0")
  assertTrue(toast.Toast >= 3) -- 4 since v1.89.0 (the stack), pinned there
  local skin = modules("LibKa0s-Skin-1.0")
  assertTrue(skin.Skin >= 16) -- 17 since v1.90.0 (keepScope), pinned there
  assertTrue(skin.SkinDefs >= 27) -- 27 since R5-L1 (a darker title band); 28 since v1.105.0, pinned there
  assertTrue(skin.SkinDefsOthers >= 8) -- 10 since v1.105.0, pinned there
  assertTrue(skin.SkinPaint >= 18) -- 19 since v1.90.0 (pixel edges), pinned there
  assertTrue(skin.SkinPaintExtras >= 17) -- 18 since v1.90.0 (P.pxEdge), pinned there
  assertTrue(skin.SkinPaintControls >= 17) -- 17 since R4-L4 (opts.hud); 18 since v1.105.0, pinned there
  assertEqual(skin.SkinEUI, 4)
  assertEqual(skin.SkinAce, 9)
  local widgets = modules("LibKa0s-Widgets-1.0")
  assertTrue(widgets.Widgets >= 22) -- 23 since v1.89.0 (cascading menus), pinned there
  assertTrue(widgets.WidgetsReorder >= 5) -- 6 since v1.90.0 (pixel row boxes, SF2-L1), pinned there
  assertTrue(widgets.WidgetsDragHandle >= 12) -- 13 since v1.90.0 (pixel strips, SF2-L1), pinned there
  assertTrue(widgets.WidgetsLineChart >= 6) -- 7 since v1.91.0 (physical-pixel lines), pinned there
  assertTrue(widgets.WidgetsAutocomplete >= 7) -- 8 since v1.90.0 (pixel edges), pinned there
  assertTrue(widgets.WidgetsCopyWindow >= 5) -- 5 since R5-L3; 6 since v1.105.0, pinned there
  local debugLog = modules("LibKa0s-DebugLog-1.0")
  assertTrue(debugLog.DebugLogWindow >= 4) -- 4 since R5-L3; 5 since v1.105.0, pinned there
  local launcher = modules("LibKa0s-Launcher-1.0")
  assertTrue(launcher.Launcher >= 7) -- 8 since v1.92.0, pinned there
  local options = modules("LibKa0s-Options-1.0")
  assertTrue(options.OptionsWidgets >= 44) -- 45 since v1.92.0, pinned there
  assertEqual(options.OptionsIds, 7)
  assertEqual(options.OptionsIdList, 9) -- 9 since R5-L5
  assertTrue(options.OptionsTabs >= 15) -- 16 since v1.92.0, pinned there
  assertTrue(options.OptionsCompose >= 19) -- 19 since R6-SIM-L (the Sim mode checkbox); 20 since v1.108.0, pinned there
  assertEqual(options.OptionsScroll, 13)
  assertTrue(options.OptionsNav >= 5) -- 6 since v1.93.0, pinned there
  assertEqual(options.OptionsDrawer, 5)
  assertTrue(options.OptionsKeybinds >= 7) -- 8 since v1.92.0, pinned there
  assertTrue(options.OptionsAppearance >= 6) -- 7 since v1.90.0 (keepScope copy), pinned there
  assertTrue(options.OptionsSkinPicker >= 11) -- 11 since R6-L1 (spec.preview); 12 since v1.105.0, pinned there
  assertEqual(options.OptionsIdSuggest, 2) -- 2 since R5-L5
  assertEqual(options.OptionsMedia, 4)
  assertEqual(options.OptionsCombat, 4)
  local perf = modules("LibKa0s-Perf-1.0")
  assertTrue(perf.PerfPanel >= 13) -- 13 since R5-L3; 14 since v1.105.0, pinned there
  local sim = modules("LibKa0s-Sim-1.0")
  assertTrue(sim.SimPanel >= 10) -- 11 since v1.105.0, pinned there
  assertTrue(sim.SimPanelRender >= 3) -- 3 since R5-L3; 4 since v1.105.0, pinned there
  assertTrue(T.KIT_VERSION >= 50) -- 51 since v1.89.0, pinned there
end)
-- v1.89.0 (Ka0sAddonsCommonTasks docs/2026-11-06-REVENDOR_LIBKA0S_V1_89/, item V89-LH): from v1.85.0,
-- the new major LibKa0s-IconBrowser-1.0 (v1.86.0), DebugLogDiagnostics 7 (the report names
-- IconBrowser), Widgets 23 (cascading W.ContextMenu rows, v1.87.0), Toast 4 (the opt-in stack,
-- v1.88.0) and kit revision 51 (v1.89.0). This addon raises no toast, opens no W.ContextMenu of its
-- own and offers no icon chooser, so it takes all of it on the copy alone.
test("v1.89.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.89.0")
    return lib.MODULES
  end
  local browser = modules("LibKa0s-IconBrowser-1.0")
  assertEqual(browser.IconBrowserSources, 1)
  assertTrue(browser.IconBrowserWindow >= 1) -- 2 since v1.105.0, pinned there
  assertTrue(browser.IconBrowser >= 1) -- 2 since v1.105.0, pinned there
  assertTrue(modules("LibKa0s-DebugLog-1.0").DebugLogDiagnostics >= 7) -- 11 since v1.105.0, pinned there
  assertTrue(modules("LibKa0s-Widgets-1.0").Widgets >= 23) -- 25 since v1.90.0 (pixel edges, then SF2-L1's lines), pinned there
  assertEqual(modules("LibKa0s-Toast-1.0").Toast, 4)
  assertTrue(T.KIT_VERSION >= 51) -- 52 since v1.92.0, pinned there
end)
-- v1.90.0 (Ka0sAddonsCommonTasks docs/2026-11-06-REVENDOR_LIBKA0S_V1_89/SF1_SMOKE_FEEDBACK.md, item
-- SF1-RV-LH): Core 16, Widgets 24 (25 after SF2-L1) and WidgetsAutocomplete 8 draw every library control edge in
-- physical pixels (SF1-L1); Skin 17 and OptionsAppearance 7 add RegisterOwner's keepScope (SF1-L2);
-- SkinPaint 19 and SkinPaintExtras 18 call Core's pixel mechanism. The refreshed tag (SF2-L1) moves Widgets
-- to 25, WidgetsReorder to 6 and WidgetsDragHandle to 13: the menu divider, the row boxes and the drag
-- strips in physical pixels too. This addon owes nothing: it takes
-- the pixel edges on the copy and does not opt into keepScope. The kit stays at revision 51.
test("v1.90.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.90.0")
    return lib.MODULES
  end
  assertTrue(modules("LibKa0s-Core-1.0").Core >= 16) -- 17 since v1.91.0 (the CorePixel peel), pinned there
  local widgets = modules("LibKa0s-Widgets-1.0")
  assertTrue(widgets.Widgets >= 25) -- 26 since v1.91.0 (the WidgetsDropdown peel), pinned there
  assertTrue(widgets.WidgetsReorder >= 6) -- 7 since v1.105.0, pinned there
  assertTrue(widgets.WidgetsDragHandle >= 13) -- 14 since v1.105.0, pinned there
  assertEqual(widgets.WidgetsAutocomplete, 8)
  local skin = modules("LibKa0s-Skin-1.0")
  assertTrue(skin.Skin >= 17) -- 18 since v1.105.0, pinned there
  assertTrue(skin.SkinPaint >= 19) -- 20 since v1.108.0, pinned there
  assertTrue(skin.SkinPaintExtras >= 18) -- 19 since v1.91.0 (the HUD and confirm peels), pinned there
  assertEqual(modules("LibKa0s-Options-1.0").OptionsAppearance, 7)
  assertTrue(T.KIT_VERSION >= 51) -- 52 since v1.92.0, pinned there
end)
-- v1.91.0 (Ka0sAddonsCommonTasks docs/2026-11-06-FOLLOWUPS_V1_91/, item FU-RV-LH): WidgetsLineChart 7 draws
-- the chart's axis, grid, markers and crosshair one physical pixel, and reads a series thickness
-- (this addon's C.TIMELINE.TOTAL_W and LINE_W) as physical pixels (FU-L1). Four peels, each a pure
-- move (FU-L2): Core 17 with CorePixel 1, Widgets 26 with WidgetsDropdown 1, and SkinPaintExtras 19
-- with SkinPaintHud 1 and SkinAceConfirm 1. This addon owes nothing beyond loading the new files. The
-- kit stays at revision 51.
test("v1.91.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.91.0")
    return lib.MODULES
  end
  local core = modules("LibKa0s-Core-1.0")
  assertTrue(core.Core >= 17) -- 18 since v1.105.0, pinned there
  assertEqual(core.CorePixel, 1)
  local widgets = modules("LibKa0s-Widgets-1.0")
  assertTrue(widgets.Widgets >= 26) -- 27 since v1.105.0, pinned there
  assertTrue(widgets.WidgetsDropdown >= 1) -- 2 since v1.105.0, pinned there
  assertTrue(widgets.WidgetsLineChart >= 7) -- 8 since v1.108.0, pinned there
  local skin = modules("LibKa0s-Skin-1.0")
  assertEqual(skin.SkinPaintExtras, 19)
  assertTrue(skin.SkinPaintHud >= 1) -- 2 since v1.108.0, pinned there
  assertEqual(skin.SkinAceConfirm, 1)
  assertTrue(T.KIT_VERSION >= 51) -- 52 since v1.92.0, pinned there
end)

test("v1.92.0: the vendored minors and the kit revision match the release", function()
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.92.0")
    return lib.MODULES
  end
  assertTrue(modules("LibKa0s-Compat-1.0").Compat >= 2) -- 3 since v1.93.0, pinned there
  local slash = modules("LibKa0s-Slash-1.0")
  assertTrue(slash.Slash >= 22) -- 23 since v1.93.0, pinned there
  assertEqual(slash.SlashParse, 2)
  assertTrue(modules("LibKa0s-Launcher-1.0").Launcher >= 8) -- 9 since v1.93.0, pinned there
  local perf = modules("LibKa0s-Perf-1.0")
  assertEqual(perf.Perf, 16)
  assertEqual(perf.PerfSampler, 1)
  assertEqual(perf.PerfCommands, 1)
  assertTrue(perf.PerfPanel >= 13) -- 14 since v1.105.0, pinned there
  local options = modules("LibKa0s-Options-1.0")
  assertEqual(options.OptionsRegistry, 5)
  assertTrue(options.OptionsWidgets >= 45) -- 46 since v1.105.0, pinned there
  assertEqual(options.OptionsFlow, 3)
  assertTrue(options.OptionsTabs >= 16) -- 17 since v1.93.0, pinned there
  assertEqual(options.OptionsTabbed, 3)
  assertEqual(options.OptionsKeybinds, 8)
  assertTrue(T.KIT_VERSION >= 52) -- 53 since v1.93.0, pinned there
end)

test("v1.93.0: the vendored minors and the kit revision match the release", function()
  local lib = T.mocks.LibStub("LibKa0s-Options-1.0", true)
  assertTrue(lib ~= nil and type(lib.MODULES) == "table", "LibKa0s-Options-1.0 missing: re-vendor v1.93.0")
  assertEqual(lib.MODULES.Options, 38)
  assertTrue(lib.MODULES.OptionsNav >= 6) -- 7 since v1.105.0, pinned there
  assertEqual(lib.MODULES.OptionsTabs, 17)
  assertEqual(lib.MODULES.OptionsHeader, 1)
  assertTrue(T.mocks.LibStub("LibKa0s-Compat-1.0", true).MODULES.Compat >= 3) -- 4 since v1.105.0, pinned there
  assertEqual(T.mocks.LibStub("LibKa0s-Slash-1.0", true).MODULES.Slash, 23)
  assertTrue(T.mocks.LibStub("LibKa0s-Launcher-1.0", true).MODULES.Launcher >= 9) -- 11 since v1.105.0, pinned there
  assertTrue(T.KIT_VERSION >= 53) -- 57 since v1.105.0, pinned there
end)

test("v1.105.0: the vendored minors and the kit revision match the release", function()
  -- Every file whose minor moved between v1.93.0 and v1.105.0 (LibKa0s#75 to #92), pinned exactly;
  -- the earlier releases' pins of the same files became floors in the same commit.
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.105.0")
    return lib.MODULES
  end
  local widgets, skin = modules("LibKa0s-Widgets-1.0"), modules("LibKa0s-Skin-1.0")
  local debugLog, options = modules("LibKa0s-DebugLog-1.0"), modules("LibKa0s-Options-1.0")
  local sim, browser = modules("LibKa0s-Sim-1.0"), modules("LibKa0s-IconBrowser-1.0")
  assertTrue(modules("LibKa0s-Core-1.0").Core >= 18) -- 19 since v1.108.0, pinned there
  assertTrue(modules("LibKa0s-Compat-1.0").Compat >= 5) -- 6 since v1.110.0, pinned there
  assertTrue(modules("LibKa0s-Charts-1.0").Charts >= 2) -- 3 since v1.108.0, pinned there
  assertTrue(modules("LibKa0s-Media-1.0").Media >= 13) -- 14 since v1.118.0, pinned there
  assertEqual(modules("LibKa0s-Launcher-1.0").Launcher, 11)
  assertEqual(modules("LibKa0s-Perf-1.0").PerfPanel, 14)
  assertEqual(skin.Skin, 18)
  assertEqual(skin.SkinDefs, 28)
  assertTrue(skin.SkinDefsOthers >= 10) -- 11 since v1.112.0, pinned there
  assertTrue(skin.SkinPaintControls >= 18) -- 19 since v1.108.0, pinned there
  assertTrue(widgets.Widgets >= 28)   -- v1.106.0: the HUD dock guards its measurements; 29 since v1.107.0, pinned there
  assertTrue(widgets.WidgetsDropdown >= 2) -- 3 since v1.108.0, pinned there
  assertEqual(widgets.WidgetsReorder, 7)
  assertTrue(widgets.WidgetsDragHandle >= 14) -- 15 since v1.107.0, pinned there
  assertTrue(widgets.WidgetsDragHandleTip >= 1) -- 2 since v1.107.0, pinned there
  assertTrue(widgets.WidgetsCopyWindow >= 6) -- 7 since v1.112.0, pinned there
  assertTrue(widgets.WidgetsHeader >= 1) -- 2 since v1.112.0, pinned there
  assertTrue(widgets.WidgetsBar >= 1) -- 2 since v1.108.0, pinned there
  assertEqual(debugLog.DebugLog, 23)
  assertTrue(debugLog.DebugLogDiagnostics >= 11) -- 12 since v1.114.0, pinned there
  assertEqual(debugLog.DebugLogWindow, 5)
  assertEqual(options.OptionsWidgets, 46)
  assertEqual(options.OptionsNav, 7)
  assertEqual(options.OptionsSkinPicker, 12)
  assertEqual(options.OptionsSkinPickerQueue, 1)
  assertTrue(browser.IconBrowserWindow >= 2) -- 3 since v1.112.0, pinned there
  assertEqual(browser.IconBrowser, 2)
  assertTrue(sim.Sim >= 4) -- 5 since v1.113.0, pinned there
  assertEqual(sim.SimPanel, 11)
  assertEqual(sim.SimPanelRender, 4)
  assertTrue(T.KIT_VERSION >= 57) -- 58 since v1.108.0, pinned there
end)

test("v1.107.0: the vendored minors and the kit revision match the release", function()
  -- The drag strip's marks and tooltip (AF-LK-01, AF-LK-02, LibKa0s#96): WidgetsDragHandle 15 reads
  -- the marks [?][settings][close] with the settings mark on by default, WidgetsDragHandleTip 2 opens
  -- the strip's tooltip above it. This addon builds no strip; the pins say which payload it carries.
  local lib = T.mocks.LibStub("LibKa0s-Widgets-1.0", true)
  assertTrue(lib ~= nil and type(lib.MODULES) == "table", "LibKa0s-Widgets-1.0 missing: re-vendor v1.107.0")
  assertTrue(lib.MODULES.WidgetsDragHandle >= 15) -- 16 since v1.108.0, pinned there
  assertTrue(lib.MODULES.WidgetsDragHandleTip >= 2) -- 3 since v1.108.0, pinned there
  assertTrue(lib.MODULES.Widgets >= 29) -- LibKa0s#95: secret dock geometry reads as none; 30 since v1.108.0, pinned there
  assertTrue(T.KIT_VERSION >= 57) -- 58 since v1.108.0, pinned there
end)
test("v1.108.0: the vendored minors and the kit revision match the release", function()
  -- LibKa0s#94, #97, #99, #100 (Ka0sAddonsCommonTasks docs/2026-11-20-LIBKA0S_94_97_99_100): the
  -- footer lays only its shown marks (Widgets 30), library defaults follow the skin (WidgetsBar 2,
  -- Charts 3, ChartsRender 2, SkinPaintHud 2, SkinPaintControls 19, OptionsCompose 20, the Callout
  -- and WaypointArrow pairs), the shared menu measures no secret label (WidgetsDropdown 3), host
  -- bands and owner warnings (Core 19, SkinPaint 20, WidgetsDragHandle 16, WidgetsLineChart 8), the
  -- strip tooltip's readable ancestor (WidgetsDragHandleTip 3), and test kit revision 58.
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.108.0")
    return lib.MODULES
  end
  local widgets, skin = modules("LibKa0s-Widgets-1.0"), modules("LibKa0s-Skin-1.0")
  local charts, callout = modules("LibKa0s-Charts-1.0"), modules("LibKa0s-Callout-1.0")
  local arrow = modules("LibKa0s-WaypointArrow-1.0")
  assertTrue(modules("LibKa0s-Core-1.0").Core >= 19) -- 20 since v1.112.0, pinned there
  assertTrue(callout.Callout >= 5) -- 6 since v1.109.0, pinned there
  assertEqual(callout.CalloutSettings, 6)
  assertEqual(arrow.WaypointArrow, 3)
  assertEqual(arrow.WaypointArrowSettings, 3)
  assertEqual(charts.Charts, 3)
  assertEqual(charts.ChartsRender, 2)
  assertEqual(skin.SkinPaint, 20)
  assertEqual(skin.SkinPaintHud, 2)
  assertTrue(skin.SkinPaintControls >= 19) -- 20 since v1.109.0, pinned there
  assertEqual(widgets.Widgets, 30)
  assertTrue(widgets.WidgetsDropdown >= 3) -- 4 since v1.113.0, pinned there
  assertTrue(widgets.WidgetsDragHandle >= 16) -- 17 since v1.111.0, pinned in v1.112.0's case
  assertEqual(widgets.WidgetsDragHandleTip, 3)
  assertEqual(widgets.WidgetsLineChart, 8)
  assertEqual(widgets.WidgetsBar, 2)
  assertTrue(modules("LibKa0s-Options-1.0").OptionsCompose >= 20) -- 21 since v1.109.0, pinned there
  assertTrue(T.KIT_VERSION >= 58) -- 59 since v1.109.0, pinned there
end)

test("v1.109.0: the vendored minors and the kit revision match the release", function()
  -- The layout-§1 peels (Ka0sAddonsCommonTasks docs/2026-11-21-SYNC_FOLLOWUPS): CalloutRoute and
  -- CalloutSound out of Callout.lua (Callout 6), SkinPaintNav out of SkinPaintControls.lua
  -- (SkinPaintControls 20), OptionsComposeMaster out of OptionsCompose.lua (OptionsCompose 21), and
  -- test kit revision 59. This addon calls none of the peeled members directly; the pins say which
  -- payload it carries.
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.109.0")
    return lib.MODULES
  end
  local callout, skin = modules("LibKa0s-Callout-1.0"), modules("LibKa0s-Skin-1.0")
  local options = modules("LibKa0s-Options-1.0")
  assertEqual(callout.Callout, 6)
  assertEqual(callout.CalloutRoute, 1)
  assertEqual(callout.CalloutSound, 1)
  assertTrue(skin.SkinPaintControls >= 20) -- 21 since v1.112.0, pinned there
  assertEqual(skin.SkinPaintNav, 1)
  assertEqual(options.OptionsCompose, 21)
  assertEqual(options.OptionsComposeMaster, 1)
  assertTrue(T.KIT_VERSION >= 59) -- 60 since v1.110.0, pinned there
end)

test("v1.110.0: the vendored minors and the kit revision match the release", function()
  -- LibKa0s#101 (Ka0sAddonsCommonTasks docs/2026-11-22-LIBKA0S_101_CONTAINER_READER): Compat 6 adds
  -- the shared container groups and bank readers, and test kit revision 60 gives the Forever profile
  -- its 27-member Enum.BagIndex and C_Bank.CanViewBank. This addon adopts the readers in K101-LH-02;
  -- the pins say which payload it carries.
  local lib = T.mocks.LibStub("LibKa0s-Compat-1.0", true)
  assertTrue(lib ~= nil and type(lib.MODULES) == "table", "LibKa0s-Compat-1.0 missing: re-vendor v1.110.0")
  assertEqual(lib.MODULES.Compat, 6)
  assertTrue(T.KIT_VERSION >= 60) -- 62 since v1.114.0, pinned there
end)

test("v1.112.0: the vendored minors and the kit revision match the release", function()
  -- The 2026-11-24 feedback batch (Ka0sAddonsCommonTasks docs/2026-11-24-FEEDBACK_BATCH): Core 20
  -- (the preview stand-in and FollowColor), SkinDefsOthers 11 (High Contrast's HUD shadow 1, -1),
  -- SkinPaintControls 21 (a disabled primary looks disabled), WidgetsHeader 2 (companion = true),
  -- WidgetsCopyWindow 7 and IconBrowserWindow 3 (both companions), with WidgetsDragHandle 17 from
  -- v1.111.0. The kit stays at revision 60.
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.112.0")
    return lib.MODULES
  end
  local widgets, skin = modules("LibKa0s-Widgets-1.0"), modules("LibKa0s-Skin-1.0")
  assertEqual(modules("LibKa0s-Core-1.0").Core, 20)
  assertEqual(skin.SkinDefsOthers, 11)
  assertEqual(skin.SkinPaintControls, 21)
  assertEqual(widgets.WidgetsHeader, 2)
  assertEqual(widgets.WidgetsCopyWindow, 7)
  assertEqual(widgets.WidgetsDragHandle, 17)
  assertEqual(modules("LibKa0s-IconBrowser-1.0").IconBrowserWindow, 3)
  assertTrue(T.KIT_VERSION >= 60) -- 62 since v1.114.0, pinned there
end)

test("v1.113.0: the vendored minors and the kit revision match the release", function()
  -- Round 2 of the 2026-11-24 feedback batch (Ka0sAddonsCommonTasks docs/2026-11-24-FEEDBACK_BATCH/
  -- R2_SMOKE_FEEDBACK.md): Sim 5 (every start shows the step panel, and SampleCrowd, LibKa0s#104)
  -- and WidgetsDropdown 4 (a selected row stands off a plain row). The kit stays at revision 60.
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.113.0")
    return lib.MODULES
  end
  assertEqual(modules("LibKa0s-Sim-1.0").Sim, 5)
  assertEqual(modules("LibKa0s-Widgets-1.0").WidgetsDropdown, 4)
  assertTrue(T.KIT_VERSION >= 60) -- 62 since v1.114.0, pinned there
end)

test("v1.114.0: the vendored minors and the kit revision match the release", function()
  -- Ka0sAddonsCommonTasks docs/2026-11-25-SEEDS_AND_FOREVERDB: the new major LibKa0s-ForeverDB-1.0
  -- (ForeverDB 1, LibKa0s#105), DebugLogDiagnostics 12 (the report's ForeverDB line), and test kit
  -- revision 62 (kit 61's mock_foreverdb.lua and kit 62's regenerated Forever name set).
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.114.0")
    return lib.MODULES
  end
  assertTrue(modules("LibKa0s-ForeverDB-1.0").ForeverDB >= 1) -- 4 since v1.118.0, pinned there
  assertEqual(modules("LibKa0s-DebugLog-1.0").DebugLogDiagnostics, 12)
  assertTrue(T.KIT_VERSION >= 62) -- 65 since v1.118.0, pinned there
end)

test("v1.118.0: the vendored minors and the kit revision match the release", function()
  -- The re-vendor ahead of #34, #38 and #39 (docs/superpowers/plans/2026-11-27-tooltip-toasts-farm.md,
  -- M0.2): ForeverDB 4 (Item Search's lookups, objects, spawn spots), Media 14 (the `dash` icon) and
  -- test kit revision 65 (the extended mock_foreverdb.lua).
  local function modules(major)
    local lib = T.mocks.LibStub(major, true)
    assertTrue(lib ~= nil and type(lib.MODULES) == "table", major .. " missing: re-vendor v1.118.0")
    return lib.MODULES
  end
  assertEqual(modules("LibKa0s-ForeverDB-1.0").ForeverDB, 4)
  assertEqual(modules("LibKa0s-Media-1.0").Media, 14)
  assertEqual(T.KIT_VERSION, 65)
end)
