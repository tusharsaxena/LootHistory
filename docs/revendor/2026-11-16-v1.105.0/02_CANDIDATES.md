# 02 Candidates, LibKa0s v1.93.0 -> v1.105.0

Sources: `git -C ../LibKa0s log --oneline v1.93.0..v1.105.0`; LibKa0s CHANGELOG.md, the v1.94.0 to v1.105.0 blocks and v1.105.0's *What a consumer owes*; the `docs/api/` documents of the majors 01_DELTA.md lists as moved; Ka0sAddonsCommonTasks `docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS/03_ADOPTION_PLAN.md` for this addon's site counts, re-checked here by grep. Site counts are approximate until the adoption run re-checks them.

**Class A, delivered on the copy alone (smoke lines, not candidates)**
- The debug console, the copy window and the sim panel carry **extras · settings · close** on their title bands, the settings mark opening this addon's settings through the launcher's registry (#86). The skin picker's gear moves into its header.
- The console's status line is a 24 px Widgets footer, counter in `text.muted` (#90); Copy hands out plain text with no colour codes (#79).
- Ka0s Default's rows read apart: stripe .08, hover .16, selection .26 (#84). Seven skins' `icon.hot` and Glass's and High Contrast's `icon.tint` moved (#82).
- The library's own tooltips are placed by `LibKa0s-Tooltip-1.0`: dropdown and context-menu entries (this addon's ten filter dropdowns among them) and reorder handles beside their menu or window, the skin picker's toolbar tips below their control, the minimap tooltip toward the screen's centre 2 px off the button, and the Charts hover tip (Charts minor 2) (#92).
- Kit revision 57: a registered frame is held until it unregisters (#75), on the re-cut tag (LK-FIX-1) at no per-frame closure cost.
- v1.94.0 to v1.104.0, carried by this sweep: Compat minor 4 members (not wired: Retail-only), Skin minor 18 `DefaultSkin` per client (no change on Retail), Widgets 27 `Footer` / `FOOTER` / `DockTestStrip`, OptionsWidgets 46, the Role, Callout and WaypointArrow majors (not looked up here).

**Class B, host change required: candidates owed in phase [3]** (not interviewed in this run; the tracker is the LibKa0s issue)
| Issue | Surface | What this addon would change | Blast radius |
|---|---|---|---|
| #92 | `LibKa0s-Tooltip-1.0` placers | 14 `SetOwner` sites: the eight tooltip helpers in core/Compat.lua (613-724, `ANCHOR_RIGHT` by default, one `ANCHOR_NONE` cursor placement at 674), and six direct sites (modules/BrowserTable.lua:556, 560, 732; modules/BrowserWidgets.lua:272; modules/Browser.lua:929; settings/PanelAuction.lua:156). Three callers pass `ANCHOR_CURSOR` (modules/AnalyticsLedger.lua:115, modules/Timeline.lua:407, 556), and the chart hosts would move onto `ctx:PlaceTip` | replaces anchors the addon owns; visible |
| #86 | `W.HeaderButtons` | the 2 title bars built through `B:MakeCloseButton` (modules/Browser.lua:1014, modules/Export.lua:490) move onto the strip, with a settings mark on each | replaces chrome the addon owns; visible |
| #89 | `W.Footer` 24 px | the Browser's hand-built 18 px footer (`FOOTER_H = 18`, modules/Browser.lua:130, the `_dbFooter` "Database ~N MB" line at :1062, the skin's `bottomBar` at :1131) | replaces; window geometry |
| #88 | docked test/sim strip | the undocked strip under the Browser's filter bar (`NS.MakeTestStrip`, modules/Browser.lua:923; `NS.TestStripReserve`, core/WidgetsSetup.lua:331) takes `dock = "title"`; do it with #89, one smoke for the window | replaces; window geometry |
| #79 | `D:Report` / `D:Serialize` | not in the run's adoption plan for this addon. The one host list verb that prints to chat is `/lh holdings <query>` (settings/Slash.lua:243, up to ten lines); whether it is a report under the 2026-11-08 routing ruling is the owner's call at adoption. The stub members exist already (core/DebugLogSetup.lua) | replaces a chat list, if ruled a report |
| #87 | `Sim.Sample(client)` | the preview and test characters named `<Class>-Ravencrest` (modules/TestData.lua:26, modules/BrowserTableTestData.lua:171, 240) move onto the shared sets | replaces fixture data |

Not this addon's: #80 and #81 (Skill Master only), #85 (Callout consumers: DpsRace, DropWatcher, QuickComms, Skill Master).

**Class C, whole-module**: none new to offer. Unconsumed majors are listed in 01_DELTA.md 3e.

**Blockers (3g)**: none. The contract changes 01_DELTA.md names were fixed in the re-vendor commit.
