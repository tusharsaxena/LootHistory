# Smoke tests — Ka0s Loot History

These are the in-client checks the headless suite cannot make: real `CHAT_MSG_LOOT` capture, the
History window, the settings panel, the minimap button, combat locks and what the client draws. The
pure logic is covered by `lua tests/run.lua` and `luacheck .` (see [testing.md](testing.md)). Run the
suite on the live Retail client (Midnight 12.1.0, Interface 120100) before tagging a release, after a
`## Interface:` bump and after a `libs/` refresh; run the themes a change touches before calling that
change done (see *Which themes to run* below). Start each theme from a clean `/reload` with debug
logging off unless a step turns it on. Record each check on its `Result:` line (pass, or what you
saw). IDs are `<THEME>-<n>`: an ID is never renumbered or reused, and a new check takes the next
free number in its theme.

## Index

| ID range | Theme | What it covers |
|---|---|---|
| INSTALL-1 to 8 | [Install and upgrade](#install-and-upgrade) | Clean load, TOC order, the SavedVariables shape, the upgrade migrations |
| SLASH-1 to 9 | [Slash commands](#slash-commands) | Bare `/lh`, help, `list`/`get`/`set`/`reset`/`resetall`, input refusals, `version` |
| PANEL-1 to 20 | [Settings panel](#settings-panel) | Landing page, the General strip, Master controls, reset and purge dialogs, panel chrome, AH Price |
| PROFILE-1 to 13 | [Profiles](#profiles) | The Profiles page, what a profile holds, `/lh profile` |
| STATE-1 to 12 | [Enabled state, lock and test mode](#enabled-state-lock-and-test-mode) | Enable/disable, General visibility, Lock frame, test mode |
| TM-1 | [Enabled state, lock and test mode](#enabled-state-lock-and-test-mode) | Test mode's Holdings and Timeline sample, and its History row tooltips |
| CUR-1 | [Capture, attribution and retention](#capture-attribution-and-retention) | A hidden tracking currency never writes its own row |
| COMBAT-1 to 8 | [Combat](#combat) | The window in combat, the settings combat lock, combat-driven refusals |
| CAP-1 to 32 | [Capture, attribution and retention](#capture-attribution-and-retention) | The source matrix, context lifetimes, currency, the gates, zone stamps, retention prune |
| HIST-1 to 35 | [History window](#history-window) | Window, table, dropdowns, saved view, character scope, row actions, marks, export, the one-line filter bar |
| FB-1 | [History window](#history-window) | The filter bar fills the window and scales with it |
| AC-1 | [History window](#history-window) | The Search autocomplete on History, Insights, Timeline and Holdings |
| INS-1 to 22 | [Insights](#insights) | Filter scope, KPI cards, chart order, colors, legends, tooltips, the currency block |
| FILT-1 to 25 | [Filter lists](#filter-lists) | Blacklist, whitelist and currency lists: gate, add box, suggestions, grid, refresh |
| LAUNCH-1 to 10 | [Launcher](#launcher) | Minimap button and broker row: art, tooltip, clicks, menu, visibility |
| DIAG-1 to 33 | [Debug console and diagnostics](#debug-console-and-diagnostics) | Console window and logging, resizing, tag coverage, the diagnostics report and the logging it turns on, the console's Diagnostics link, the library's own `[Cmd]` and `[Lifecycle]` lines, state lines held for `debug on` |
| DEGRADED-1 to 12 | [Degraded install](#degraded-install) | LibKa0s missing from the install |
| LED-1 to 10 | [Ledger and holdings](#ledger-and-holdings) | The Holdings tab, bank and warband reads, the upgrade reset popup, combat deferral, `/lh holdings`, the `trackLedger` switch, the P4 columns/banding/tooltips/header row, bank drift from outside the addon |
| LED-P2-01 to 24 | [Ledger capture (timeline ledger Phase 2)](#ledger-capture-timeline-ledger-phase-2) | Bank, warband, vendor, loot, combat, mail, auction house, guild bank, crafting, currency, login and resume drift, History and Insights display, exports, perf run, trainer, taxi, trade, destroy |
| TR-1 to 3 | [Holder moves (timeline ledger Phase 7)](#holder-moves-timeline-ledger-phase-7) | Holder moves are a loss and a gain: warband withdraw, own bank deposit, alt mail |
| TL-1 to 14 | [Timeline](#timeline) | The Timeline tab: lines, line cap, hover, picker, ranges, dashed partial and marker, Warband and colors, per-tab filter graying, Show in Timeline, Forget this character, rollup retention, load, the WoW API facts to verify, and the line toggles |
| LOC-1 to 5 | [Non-English client](#non-english-client) | Bind lines, AH mail, deconstruct names on deDE or frFR |

## Before you start

- **`/reload`** means `/console reloadui`. **BugSack / BugGrabber** (or `/console scriptErrors 1`) is
  the main regression signal: every check also fails on any Lua error.
- Every line the addon prints starts with a cyan `[LH]`. A missing or doubled banner is a failure.
- `/lh` and `/loothistory` are the same root; steps use `/lh`. A bare `/lh` opens the Settings panel
  on its landing page; `/lh toggle|show|hide` drive the History window.
- **"Loot at or above threshold"** means an item whose quality is at or above **Minimum quality**
  (default Common). Anything that prints "You receive loot:" is a capture candidate: kills,
  containers and nodes, vendor buys, mail, trades, quest rewards, M+ chests.
- Run every theme on the `Default` profile (`/lh profile Default`). PROFILE switches profiles and
  ends by switching back to `Default`; the expected `[Init]` and `[Set]` lines in DIAG name it.
- Have ready: two or more characters with recorded loot on the account, a target dummy, a vendor, a
  mailbox, bag space, and (for CAP) a quest with an item reward and a trade partner if you can.
- `/lh test` seeds a synthetic history for HIST and INS checks that do not need live loot.
- On failure, capture the BugSack line and the exact slash sequence, and file an issue at the
  tracker linked from [README.md](../README.md).

**Which themes to run.**

- Capture or attribution (`modules/Collector.lua`, `modules/Attribution.lua`, `core/Compat.lua`,
  `core/EnvSetup.lua`): INSTALL, CAP, SLASH-1 to SLASH-3, STATE-1 to STATE-4, LAUNCH-5 and INS-20;
  a change to `core/EnvSetup.lua` also needs SLASH-9, and one that moves `core/Compat.lua` also
  needs LOC.
- Browser, table, Insights or export (`modules/Browser.lua`, `BrowserTable.lua`, `AnalyticsFormat.lua`,
  `Analytics.lua`, `AnalyticsCharts.lua`, `Export.lua`): HIST, INS, STATE-6, STATE-7 to STATE-12, COMBAT-1, COMBAT-2, COMBAT-6, COMBAT-7 and INSTALL-8.
- Settings or schema: PANEL, SLASH, PROFILE, STATE-3, STATE-5, STATE-6, COMBAT-2, COMBAT-5, DIAG-9
  and FILT-1, plus CAP-22 to CAP-24 for a new capture row.
- Filter lists (`modules/Filters.lua`, the Filters tab): FILT, PROFILE-5, CAP-22 to CAP-24.
- Media or art (`core/MediaSetup.lua`, an `NS.Icon` call site, `libs/LibKa0s/media/`): HIST-5 to
  HIST-11, HIST-13, HIST-15, HIST-17 to HIST-19, HIST-22, HIST-23, INS, PANEL-18, DIAG-10 and DIAG-11.
- Dropdowns or the filter bar (`core/WidgetsSetup.lua`, `B:BuildFilterBar`, `libs/LibKa0s/Widgets.lua`):
  HIST (HIST-12 always: the first click is where this widget broke), COMBAT-1, COMBAT-2, INSTALL-8
  and DIAG-28 (the copy windows are this file's `CopyWindow`).
- LibKa0s re-vendor or `core/*Setup.lua` / `settings/Slash.lua` / `settings/OptionsSetup.lua`:
  DEGRADED (always), PANEL (PANEL-6 after every re-vendor), SLASH, DIAG, HIST-2, HIST-3, HIST-5,
  HIST-12 to HIST-23, HIST-28 to HIST-34, STATE-12, COMBAT-2 to COMBAT-5, STATE-3, STATE-5, STATE-6, CAP-25 to
  CAP-27, FILT-1, FILT-16 and FILT-24.
- Diagnostics or debug logging: DIAG, COMBAT-8, DEGRADED-4, SLASH-2, SLASH-8 and PANEL-19.
- Ledger or holdings (`core/Ledger.lua`, `modules/Scanner.lua`, `Holdings.lua`, `Reconciler.lua`,
  `HoldingsTab.lua`, the v11 migration, the reset popup in `settings/Slash.lua`): LED, COMBAT-1,
  HIST-1 to HIST-3, INSTALL (the upgrade checks), SLASH-2 and STATE-1 to STATE-4. The Phase 2 writers
  (`core/Ledger.lua`, `modules/Reconciler.lua`, `Escrow.lua`, `AttributionOut.lua`, `LedgerFormat.lua`,
  `AnalyticsLedger.lua`, `core/PerfSetup.lua`) add LED-P2 and COMBAT-1.
- The Timeline (`modules/Rollup.lua`, `TimelineModel.lua`, `Timeline.lua`, the Browser's per-tab filters and Date options, `BrowserTable:ShowMenu`, `HoldingsTab.RowActions`, `Reconciler:ForgetHolder`, `core/WidgetsSetup.lua`'s `NS.MakeLineChart`): TL, LED-4, COMBAT-1 and HIST-12. A LibKa0s re-vendor that moves `WidgetsLineChart.lua` also needs TL-1, TL-3, TL-12 and TL-13.
- Release or `## Interface:` bump: every theme, then the headless gate green.

## Install and upgrade

**INSTALL-1. Clean first load.** Quit WoW, delete `WTF/Account/<ACCOUNT>/SavedVariables/LootHistoryDB.lua`
(and its `.bak`), check the character-select AddOns list shows **Ka0s Loot History** enabled, log in,
then `/reload` → no Lua error at login or after the reload. Result:

**INSTALL-2. TOC load order.** The TOC order is Libraries → Locales → Core (Compat first) → Defaults →
Modules (Attribution before Collector) → Settings, so `settings/` loads after `modules/`. After
login run `/lh help` and open Esc → Options → AddOns → the help index prints, and **Ka0s Loot
History** is in the list with two sub-pages, **General** and **Profiles** (Filters and AH Price are
tabs on General, not pages). Result:

**INSTALL-3. Fresh SavedVariables shape.** After INSTALL-1's `/reload`, `/dump
LootHistoryDB.global.schemaVersion` → `10` (the declared default is 0; the runner walks v1→v2
through v9→v10 on the empty DB, touching no rows). `global` holds `history = {}`, `minimap` and
`schemaVersion`; `profiles.Default` holds `settings`. Result:

**INSTALL-4. An existing account upgrades into a profile.** Log in on a SavedVariables file written
by 1.4.0 or earlier (schema 8 or below) → `/dump LootHistoryDB.global.schemaVersion` answers `10`,
every record is still in `global.history`, the old settings, id lists and saved view are in
`profiles.Default`, and a stored retention sits at `global.retentionDays`, in no profile. Result:

**INSTALL-5. SavedVariables after logout.** Loot for a while, log out to character select, open
`LootHistoryDB.lua` → `global.schemaVersion = 10`; `history` is a dense array of full records (`ts`,
`char`, `classFile`, `itemID`, `itemLink`, `quality`, `source`, `confidence`, …); `retentionDays`
(if changed) and `minimap` sit beside it in `global`; `profiles.Default` holds `settings` and
`savedView` (if saved); session-only state (`debug`, `testRecords`) is absent. Log back in and out:
the file is unchanged apart from new loot (the ladder is idempotent). Result:

**INSTALL-6. Currency quality backfill (v3→v4).** Skip without currency rows recorded before the
quality field existed (their `quality` is nil). `/reload` on such a file → those rows go from a
white Name and blank Quality to a colored Name and a filled Quality; no row added or removed.
Result:

**INSTALL-7. Currency bound backfill (v4→v5).** Skip without currency rows recorded before the bound
field existed (`bound = nil`, blank or faint-gray glyph). `/reload` → each resolvable one shows
**blue/Warbound** if Warband-transferable, else **green/Bind on Pickup**; no row added or removed.
Result:

**INSTALL-8. Saved view zone upgrade (v7→v8).** With a view saved while the Zone filter stored map
ids, `/reload` and open the History window → the Zone dropdown selects the same zones by name,
never silently unfiltered. Result:

## Slash commands

**SLASH-1. Bare `/lh` opens the landing page.** Type `/lh`, then `/lh   ` (spaces only), then
`/loothistory` → each opens Settings on the Ka0s Loot History landing page (not General), the History
window stays closed and nothing prints. Result:

**SLASH-2. The help index.** `/lh help` → a header `v<version> — slash commands (/loothistory is an
alias for /lh)`, then one row per command in this order: show, hide, toggle, config, enable, disable,
version, get, set, list, reset, resetall, profile, holdings, debug, diagnostics, test, purge, help (nineteen).
Each row is a gold `/lh <verb>`, an em dash and a white description; every line carries `[LH]`; no
raw key such as `HELP_HEADER` shows; the window does not open. Result:

**SLASH-3. `/lh list`.** `/lh resetall` (the profile back to its defaults), then `/lh list` → an
`Available settings` header, then rows grouped under `[Master controls]`, `[Capture]`, `[AH Price]`,
`[Interface]`, `[History]` in strip order (a `[Collection]` or `[Maintenance]` header is a missed
rename), every schema row present, with the defaults `settings.enabled = true`,
`settings.qualityThreshold = 1`, `settings.windowScale = 1.00x`, `settings.excludeQuestItems = true`,
`settings.excludedSources = (none)` and `minimap.shown = true` (the row reads SHOWN; the stored key
underneath is `minimap.hide = false`). `settings.retentionDays` is account-wide, so no profile reset
moves it: `30` on a fresh install, `90` once PROFILE-4 has run. Result:

**SLASH-4. Panel and CLI write one value.** With the panel open on the right tab, `/lh set
settings.windowScale 1.5` → the Window scale slider moves; drag the slider → `/lh get
settings.windowScale` echoes it. Change **Minimum quality**, **Record data from**, **Exclude quest
items** (Capture), **Keep history for** (History) and **Minimap button** (Master controls) → `/lh get`
on each path echoes the new value, and an open widget follows a slash write live. Result:

**SLASH-5. `set` clamps and refuses bad input.** `/lh set settings.windowScale 9` →
`settings.windowScale = 1.60x` (clamped to the 0.6 to 1.6 bounds); `/lh set settings.windowScale abc`
→ `Invalid value for settings.windowScale`, then `expected a number`, and nothing is written;
`/lh set settings.enabled maybe` → `Invalid value for settings.enabled`, then
`expected true/false/on/off/1/0/yes/no`, and nothing is written. Result:

**SLASH-6. `reset` one row.** Change Minimum quality and mute a source, then `/lh reset
settings.qualityThreshold`, `/lh reset settings.excludedSources`, `/lh reset settings.windowScale` →
each row alone returns to its default (`(none)` for the source list, not a table address); muting a
source afterwards does not change what the next reset restores. Result:

**SLASH-7. `resetall` is non-destructive and does not ask.** Change two settings and put an id on
the Blacklist, then `/lh resetall` → prints `All settings reset to defaults`, raises no popup, and
returns the active profile's settings, lists and saved view to defaults; the loot history, the
retention and the minimap button are untouched. Result:

**SLASH-8. No raw locale keys.** Run `/lh list`, `/lh get settings.enabled`, `/lh set
settings.enabled maybe`, `/lh reset settings.windowScale`, `/lh resetall` → every line is English
prose; not one all-caps underscored token (`UNKNOWN_COMMAND`, `RESET_ALL`, …) reaches chat. Result:

**SLASH-9. `/lh version` reads the TOC.** Temporarily change `LootHistory.toc`'s `## Version` to
something obviously different, `/reload`, `/lh version` → prints the TOC value, not the constant in
`core/Namespace.lua`. Put the TOC back. Result:

## Settings panel

**PANEL-1. Both routes reach one category.** Out of combat, `/lh config`, then Esc → Options →
AddOns → **Ka0s Loot History** → both land on the same category; the tree is the landing page,
**General**, then **Profiles** last. Result:

**PANEL-2. Landing page.** Open the landing page → logo, tagline, a **Slash Commands** heading and
one row per command; each row uses the chat help's format: single spaces around an em dash that is
not white-wrapped, and a white description. Result:

**PANEL-3. General header and strip.** Open **General** → header `Ka0s Loot History ▸ General`, a
gold divider under it, a **Defaults** button top-right, and six tabs: Master controls, Capture, AH
Price, Interface, History, Filters, opening on Master controls; the selected tab cannot be clicked.
Click each: no section heading appears, except AH Price's **Pricing** (above the toggle) and **Price
sources** (above the table) subsection headings. Open **Ka0s Bank Ledger** beside it → the same
names in the same order, without AH Price. Result:

**PANEL-4. Strip wraps without overlap.** Narrow the Settings window until the strip wraps to a
second row → the first control row still starts below the strip, and rows sit at the same height
whichever tab is selected. Result:

**PANEL-5. Per-tab layout.** Walk the tabs → **Master controls**: Enable Loot History | General
visibility, Master scale | Master alpha, Lock frame | Debug console, Minimap button | Test mode, then
the **Reset position** | **Reset all settings** pair. **Capture**: Minimum quality | Record currency,
Exclude quest items alone, then the full-width **Record data from** grid. **AH Price**: *Pricing*,
Enable AH pricing, *Price sources*, the eleven-row table. **Interface**: Window scale | Row height.
**History**: Keep history for, then the storage readout | **Purge history…**. Result:

**PANEL-6. The pooled strip survives re-dressing.** `/lh config` → General; cycle all six tabs three
times ending on Master controls, then cycle the Filters sub-strip three times → on every pass each
tab shows its own label, the pressed tab is the selected one, and the band height does not move;
the AH Price rows are intact after the third pass. Fail: a label carried over from the previous
tab, a highlight on the wrong button, a body under the wrong tab, or a band that changes height.
(The headless case measures a mock that answers 0 for every height.) Result:

**PANEL-7. Master scale and alpha.** Drag **Master scale** → the History window and the export window
both resize, and **Window scale** (Interface) still multiplies on top; drag **Master alpha** → both
fade together. Result:

**PANEL-8. Window scale slider steps.** Drag **Window scale** → it moves smoothly in 0.05 steps
across 0.6 to 1.6 (not only to the two ends). Result:

**PANEL-9. Row height.** Drag **Row height** (Interface) from 18 to 14, then to 28 → table rows change
height and the visible row count follows, with no row clipped at the bottom; back at 18 the table
looks as it did before the slider existed; `/lh get settings.rowHeight` echoes the value. Result:

**PANEL-10. History tab readout.** Open the History tab → the storage readout ("N items collected
over D days", "Database size: ≈ …") with **Purge history…** beside it and nothing else. Loot
something → the count rises on its own; click to Capture and back, loot again → it still rises.
Result:

**PANEL-11. Reset position.** Move the History window, then **Reset position** → the window returns
to the screen center, no dialog appears and no setting changes. Result:

**PANEL-12. Reset all settings.** Change two settings, click **Reset all settings** → a confirm reads
"Reset this profile to the addon's defaults? Everything you have configured or added in it is
discarded — your other profiles are not affected."; Cancel changes nothing; Accept returns every
setting of this profile to default and refreshes the panel; the loot history is untouched. Neither
reset button appears anywhere else in the panel. Result:

**PANEL-13. Purge history.** Click **Purge history…** → the `KA0S_LOOTHISTORY_PURGE` confirm ("Delete
ALL … records? This cannot be undone."); Cancel leaves the data; repeat and Accept → history wiped,
`history purged.` printed. `/lh purge` raises the same dialog. Result:

**PANEL-14. The page's Defaults, both controls.** Change **Minimum quality** and add a Blacklist id,
then click the header **Defaults** → the page resets, the three filter lists clear with it. Repeat
with the Blizzard Settings window's own footer defaults control → the same reset. Result:

**PANEL-15. Scrollbar always shown.** Click between the landing page and the General tabs → the
right-edge scrollbar is always there: parked, grayed and inert on a short page, live on a long one,
and the body's right edge does not shift between pages. (Profiles is AceDBOptions' own layout and
draws no scrollbar; it is not part of this check.) Result:

**PANEL-16. Button borders.** Look at **Reset position**, **Reset all settings** and **Purge
history…** → each draws its full right border (not shaved by the scroll gutter) and lines up with its
left-hand neighbor, with nothing spilling past the panel edge. Result:

**PANEL-17. AH Price does not freeze.** On AH Price, click away and back several times, then close
and reopen the panel → the table draws correctly, tick and status columns right, and leaving the
tab is instant (no ~1.7s hitch). Result:

**PANEL-18. AH Price marks.** On AH Price → each row whose Status reads *Collecting data* has a
**green** leading mark, every other row a **red** one (a `ban`, a slash through a circle, by design);
every row has an ⓘ after its Price Module text, bright on a collecting row and dimmed otherwise,
whose hover shows the key's label and description. Untick a collecting row's **On** → its mark turns
red in place and agrees with Status. Fail: a white or missing mark, a missing ⓘ, or a mark that
does not follow the box. Result:

**PANEL-19. Panel labels are English.** On General (every tab) → the Defaults button reads
**Defaults**; on General and Profiles → every checkbox, dropdown and slider label is English, with no
all-caps underscored key. Result:

**PANEL-20. AH Price reorder still drags.** On AH Price, drag a price source by its handle two rows
down and drop it → the ghost follows the cursor, the row lands where dropped, and closing and
reopening the panel shows the new order. Fail: no ghost, a row that snaps back, or a Lua error.
Result: pass (owner, 2026-10-02)

## Profiles

**PROFILE-1. The Profiles page.** Open **Settings → AddOns → Ka0s Loot History → Profiles** → it is
last in the tree and shows AceDBOptions' controls (current profile, New, Copy From, Delete, Reset
Profile), with no Defaults button. Result:

**PROFILE-2. Switching on the page adopts the profile.** `/lh debug on`. On Profiles create `Alt`
(New), change Row height and Minimum quality and move the History window, then pick `Default` →
the window returns to Default's geometry, row height and saved view, the Filters lists and the AH
Price table redraw from Default, and the console shows one `[Profile] switched to profile 'Default'`
line. Result:

**PROFILE-3. Copy, reset and delete.** On `Alt`, **Copy From** `Default` → one `[Set] copied profile
'Default' → 'Alt'` line and Default's values show; **Reset Profile** → one `[Set] reset profile 'Alt'
to defaults` line; switch back to Default and **Delete** `Alt` → it leaves the list. Result:

**PROFILE-4. Retention is account-wide.** Set **Keep history for** to 90, create `Ret` (New, which
switches to it), then **Copy From** `Default` and **Reset Profile** → `Ret` shows 90 after each;
none of the three raises the retention confirm or deletes a record; hovering **Keep history for**
says the setting is account-wide. Result:

**PROFILE-5. Filter lists are per profile.** Pick `Default`, add an id to the Blacklist, then create
`Lists` (New) → its lists are empty; pick `Default` → the id is there, and survives `/reload`.
Result:

**PROFILE-6. Enabled is per profile.** Create `Off`, switch to it and untick **Enable Loot History**,
then switch to `Default` → the addon comes back up (loot records again); switch to `Off` → it stands
down as with `/lh disable`. Result:

**PROFILE-7. `/lh profile` lists.** On Profiles, pick `Default` and **Delete** `Ret`, `Lists` and
`Off`; create `alt` and then `Main` with **New**, set Main's **Row height** (General → Interface) to
24, and pick `Default` again. `/lh profile` → a `Profiles` header (no trailing colon), then `alt`,
`Default (current)`, `Main`, sorted ignoring case (any other profile already on the account sorts in
among them), only the current one suffixed `(current)`, then `/lh profile <name> switches profile`.
Result:

**PROFILE-8. `/lh profile <name>` switches.** With Settings open on General → Interface (Row height
reads Default's value), `/lh debug on`, then `/lh profile Main` → `Switched to profile 'Main'.`, the
settings adopt as in PROFILE-2, the open panel's Row height moves to Main's 24 without reopening it,
and the console shows one `[Profile] switched to profile 'Main'` line. `/lh profile Main` again →
`Already on profile 'Main'.` and nothing changes. Result:

**PROFILE-9. An unknown name is refused.** `/lh profile main` → `No profile named 'main'.`, then `Did
you mean 'Main'?`, then the list; `/lh profile Nope` → the refusal and the list, no did-you-mean.
Open Profiles → no `main` or `Nope` profile was created. Result:

**PROFILE-10. Quotes and spaces.** Create `My Alt` on the page (New), then pick `Main` again.
`/lh profile "My Alt"` → switches to `My Alt`; `/lh profile 'Default'` → switches to Default;
`/lh profile My Alt` → switches too (inner spaces kept). Result:

**PROFILE-11. Answers while disabled.** On `My Alt`, `/lh disable`, then `/lh profile` → the list
prints (no disabled refusal); `/lh profile Main` (a profile where the addon is enabled) → switches and
the addon comes back up. Result:

**PROFILE-12. Refused in combat.** On `Main`, attack a target dummy; in combat `/lh profile Default`
→ `Can't switch profiles in combat.` and the profile stays `Main`; `/lh profile` and `/lh profile
Nope` still answer. Out of combat `/lh profile Default` → `Switched to profile 'Default'.` Result:

**PROFILE-13. The page follows a slash switch.** On `Default`, open Profiles (the picker reads
`Default`), close Settings, `/lh profile Main`, reopen Profiles → the picker reads `Main`. Finish
with `/lh profile Default`, which leaves the character on `Default` for the themes that follow.
Result:

## Enabled state, lock and test mode

**STATE-1. Disabled is total.** `/lh disable` → prints `settings.enabled = false`; the History window
closes and will not reopen; loot you take is not recorded; `/lh show` answers `Ka0s Loot History is
disabled — enable it with /lh enable` and does nothing else. Result:

**STATE-2. The command surface while disabled.** Still disabled: bare `/lh` opens the panel, `/lh
version` prints, `/lh list` and `/lh get settings.qualityThreshold` read, `/lh set settings.scale
1.1` writes, `/lh debug` opens the console, `/lh diagnostics` writes its report → all answer; only
`show`, `hide`, `toggle`, `test` and `purge` refuse with the disabled line. Result:

**STATE-3. One switch, three surfaces.** `/lh enable` → prints `settings.enabled = true`, loot records
again and `/lh show` opens the window (enabling does not open it by itself). Untick **Master controls
▸ Enable Loot History**, then tick it again → `/lh get settings.enabled` follows each change, and
unticking takes the window down as the verb does. The box ends ticked. Result:

**STATE-4. Disabled right after login writes nothing.** `/reload` and, within five seconds of the
loading screen clearing, untick **Enable Loot History** → nothing is written: the deferred
retention prune and bound-state repair do not run on the disabled addon, so records older than the
retention are still there. Tick **Enable Loot History** again before STATE-5: every check after this
one needs the addon enabled. Result:

**STATE-5. General visibility Never.** Set **General visibility** to *Never*, `/lh show` → one line,
`the window is hidden by the General visibility setting.`, and no window. Set *Always* → nothing
opens by itself; `/lh show` again → the window opens. Result:

**STATE-6. Lock frame.** Tick **Lock frame**, drag the History and export windows by their title bars
and pull the resize grip → nothing moves or resizes; untick → both drag and the grip resizes;
`/reload` keeps the new size. Result:

**STATE-7. Test mode from the slash.** `/lh hide`, `/lh test` → `test mode on`, the window opens by
itself; close it, `/lh test` → `test mode off`, the window stays closed. Result:

**STATE-8. What test mode shows.** With test mode on → a bright-red **TEST MODE** badge beside the
window title; synthetic rows across several synthetic characters; the filter dropdowns rebuilt from
them; the view on stock + all players; Insights on the same dataset. Turn it off → badge gone, the
live history, the saved view and the current player back. Result:

**STATE-9. The Test mode box.** Master controls: tick **Test mode** → the window opens in test mode;
untick → test mode ends; tick it, then `/lh test` → the box unticks. Result:

**STATE-10. Test mode refused under Never.** Set **General visibility** to *Never*, tick **Test
mode** → one `test mode not started — …` line, no window, the box stays unticked. Set **General
visibility** back to *Always*. Result:

**STATE-11. Test mode never outlives a reset or reload.** Tick **Test mode**, then **Reset all
settings** and confirm → test mode off, box unticked. Tick it again, `/reload` → off. Result:

**STATE-12. Lock frame gates the library grip.** Tick **Lock frame**, pull the History window's
resize grip → the grip is still drawn, nothing resizes and no size is saved (`/reload`, `/lh show`
keeps the old size); untick → the grip resizes again and `/reload` keeps the new size. Result:

**TM-1. Test mode fills Holdings and Timeline too.** `/lh test`, open **Holdings** → sample things
held by four sample characters and the Warband (expand one to see the holders; the Character list
offers the same five); open **Timeline** → with no Timeline pick saved (or one the sample lacks) it
opens on Everlight Crystal with lines already drawn, while a saved pick the sample holds (e.g. Gold)
is kept, and picking Gold draws a line per holder plus Total across about 120 days, and picking
another sample item (Sunwell Cinder) draws at least two lines. `/lh test` again → both tabs are back
on your own holdings and Timeline (your own pick, not the sample's), and nothing of the sample is
left in either. While test mode is on, hover a **History** row → a tooltip with the item name in its
quality color, its `Type · SubType`, and a gray `Test-mode sample` line; `/lh test` off → hovering your
own rows shows the real item tooltip as before. Result:

## Combat

**COMBAT-1. The window works in combat.** With the window open, attack a dummy; click a row, drag and
resize the window → no "Interface action failed because of an AddOn" error; it stays usable.
Result:

**COMBAT-2. `/lh config` in combat.** In combat, `/lh config` → one gray `cannot open settings during
combat — Blizzard's category-switch is protected` line, nothing opens. Leave combat → `/lh config`
opens the panel, and the panel does not open on its own when combat drops. Result:

**COMBAT-3. The sidebar path is locked in combat.** In combat, open the Blizzard AddOns list and click
**Ka0s Loot History ▸ General** (then **Profiles**) → the Settings window stays open with a gray cover
reading *Settings are locked during combat.* and nothing drawn under it; chat gets one gray locked
notice for the fight; clicking the cover, a tab or the footer Defaults changes nothing and prints
nothing more; no `ADDON_ACTION_BLOCKED`; Esc closes the window. Result:

**COMBAT-4. The cover drops on an open page and lifts after.** Open General, then pull → the cover
drops over the open page. Leave combat → the cover lifts and the page draws in place. Result:

**COMBAT-5. Only out of combat.** Set **General visibility** to *Only out of combat*, open the window,
pull → the window hides at combat start and does not reopen by itself when combat ends. Result:

**COMBAT-6. Combat ends test mode.** Tick **Test mode**, close the window, attack a dummy → one `test
mode off — combat started` line, the box unticks, the window does not open. Result:

**COMBAT-7. `/lh test` in combat.** In combat, `/lh test` → refused with one line naming combat; no
window, box unticked. Result:

**COMBAT-8. Diagnostics in combat.** Pull a dummy, `/lh diagnostics` in combat → no Lua error; a value
the client hides prints as `<secret>` or `?`, and no `section <name> failed` line appears. Result:

## Capture, attribution and retention

Loot, then `/lh show` → History and read the new row's **Source** and confidence. With debug on, the
`[Attr]` and `[Loot]` lines in the console say why (see [data-flow.md](data-flow.md)).

**CAP-1. Kill.** Kill a mob and loot it → **Kill**, CERTAIN. Result:

**CAP-2. Container.** Open a chest, lockbox, herb or ore node → **Container**, CERTAIN. Result:

**CAP-3. Quest.** Turn in a quest with an item reward → **Quest**, CERTAIN. Result:

**CAP-4. Vendor.** Buy an item from a vendor → **Vendor**, CERTAIN or INFERRED (review F-001). Result:

**CAP-5. Mail.** Take an item attachment from mail → **Mail**, CERTAIN or INFERRED (review F-001).
Result:

**CAP-6. Trade.** Complete a trade that gives you an item → **Trade**, CERTAIN or INFERRED (review
F-001). Result:

**CAP-7. Mythic+ chest.** Loot a Mythic+ end-of-run chest → **Mythic+**, CERTAIN. Result:

**CAP-8. Bonus roll.** Spend a bonus roll on a boss kill → **Bonus Roll**, CERTAIN, overriding the
kill context. Result:

**CAP-9. Roll win.** `/lh debug on`, win a need/greed/transmog roll → **Roll**, CERTAIN, with an
`[Attr] stamp ROLL via roll-won` line just before the item's `[Loot] … src=ROLL` (review F-009).
Fail: the item records as the boss's Kill or Container, meaning the client sent the compact
"no-spam" roll line; see ARCHITECTURE Known limitations. Result:

**CAP-10. Craft.** Craft any item ("You create") → **Craft**, CERTAIN, overriding stale context.
Result:

**CAP-11. Currency refund.** Refund a currency-paid vendor purchase inside the buyback timer → a
`Type=Currency` row, **Refund**, CERTAIN (from the "You are refunded:" `CHAT_MSG_CURRENCY` line),
overriding the purchase's Vendor stamp; with debug on, `[Currency] … src=REFUND`. Result:

**CAP-12. Currency loot.** With **Record currency** on, loot a currency → a `Type=Currency` row with
its source from context, blank iLvl, Vendor and AH cells; the Type filter isolates it; with debug on
`[Currency] <name> x<n> id=<id> src=<source>`. Result:

**CAP-13. Record currency and the source mute.** Untick **Record currency**, loot a currency → no row;
tick it and mute that currency's source → still no row. Tick that source again in **Record data
from**. Result:

**CAP-14. The keystone context ends with the key.** `/lh debug on`, run and complete a key and loot the
chest (**Mythic+**); leave the dungeon, gather a node → **Container**, with `[Attr] keystone cleared`
on the zone change. Zoning out and back mid-key keeps chest and object loot on **Mythic+** (`keystone
re-armed` on re-entry); `CHALLENGE_MODE_RESET` also clears it. Result:

**CAP-15. Boss-corpse loot keeps its encounter.** `/lh debug on`, kill a boss and loot it → `[Attr]
encounter end … kill: context kept 60s for the corpse` before the `LOOT_OPENED` line, and `/dump
LootHistoryDB.global.history[#LootHistoryDB.global.history].sourceDetail` shows `encounterID` and
`difficulty`. A wipe logs `wipe/no context: cleared`. If `LOOT_OPENED` arrives before `encounter end`,
write that down: the grace window (`Constants.ENCOUNTER_GRACE`) is then unneeded. Result:

**CAP-16. Unattributed loot.** Loot something with no fresh context → **Other**, INFERRED; never a Lua
error, never a missing row. Result:

**CAP-17. Row columns render.** Read a few rows → exact item-link tooltip, quality color, iLvl, bound
glyph (BoE/BoP/Warbound/Warbound-until-equipped), Vendor and AH price, type, zone, and the Character
column's class icon and class color. Result:

**CAP-18. Currency category.** Loot a currency → its **Subtype** reads a real Currency-tab header such
as "The War Within" (review F-010). Fail: blank, meaning `Compat.CurrencyCategory` could not read the
headers on this client. Result:

**CAP-19. A currency first seen mid-session.** At a season start, after one currency loot, loot a
currency not yet seen this session → its Subtype reads its header, not blank (a miss rebuilds the
cache once). Then collapse that header in the Currency tab, `/reload` and loot a currency under it;
write in [midnight-quirks.md](midnight-quirks.md) *Currency category* whether Subtype resolves (the
expectation is blank). Result:

**CAP-20. Currency name color, quality and tooltip.** A currency row's Name is colored by its
`C_CurrencyInfo` quality tier, the Quality column shows the tier label, and hovering shows the
in-game currency tooltip (not an item tooltip, not blank). Result:

**CAP-21. Currency bound glyph.** Loot a Warband-transferable currency (Timewarped Badge) and a
non-transferable one (Nebulous Voidcore) → blue/Warbound (tooltip "Warband Transferable") and
green/Bind on Pickup respectively, not blank. Result:

**CAP-22. Quality gate.** Set **Minimum quality** to Rare; loot a Common or Uncommon item, then a Rare
→ the first is dropped (with debug on, `[Drop] … quality`), the Rare records, and no `/reload` was
needed. Set **Minimum quality** back to Common. Result:

**CAP-23. Quest-item gate.** With **Exclude quest items** ticked, loot a quest objective drop →
dropped (`reason=quest`, keyed on item class 12); untick it and loot another → recorded. Result:

**CAP-24. Source mute.** In **Record data from**, untick **Kill**, kill and loot a mob → dropped
(`reason=source`); tick it again → captured. The list offers every source: Kill, Container, Mythic+,
Bonus Roll, Roll, Quest, Trade, Mail, Auction House, Vendor, Disenchant, Milling, Prospecting, Craft,
Refund, Other. Result:

**CAP-25. Zone and subzone stamps.** Loot in a zone with a subzone (a capital district, an inn) → the
Zone column reads the zone, and `/dump
LootHistoryDB.global.history[#LootHistoryDB.global.history].subzone` prints the subzone (neither the
row tooltip nor the CSV export shows it); loot in a zone with no subzone → the Zone column is filled
and nothing is blank-labeled. Result:

**CAP-26. Zone during a loading screen.** Loot in the first frames after a portal or summon, before
the client has zone text → the row buckets under **Unknown** in the Zone filter and in group-by-zone,
with rows that have no zone, never as a blank-named group. Result:

**CAP-27. The map id is stamped.** Loot in a dungeon, then `/dump
LootHistoryDB.global.history[#LootHistoryDB.global.history].mapID` → a number (the CSV export does not
carry `mapID`; see HIST-25). Result:

**CAP-28. A shorter retention asks first.** With records older than 7 days, change **Keep history
for** from 90 to 7 → a confirm names the record count, and nothing is deleted before it is answered.
Answer **No** → every record stays, the dropdown returns to 90, one line `retention kept at 90 days;
no records were deleted.`; a `/reload` then deletes nothing. Result:

**CAP-29. The slash path asks too.** The records older than 7 days are still there (CAP-28 answered
**No**). `/lh set settings.retentionDays 7` → the same confirm; answer **No** → every record stays
and the same `retention kept at 90 days; no records were deleted.` line prints. Then `/lh set
settings.retentionDays 0` (*Always*), a value that would delete nothing → no confirm, and no record
is deleted. Result:

**CAP-30. Yes prunes.** Change **Keep history for** to 7 days and answer **Yes** → records older than
7 days go (no holes), the table and footer refresh. Result:

**CAP-31. Login prune.** Retention is 7 days (CAP-30) and at least one record is left. Age the
last record past it and count the records: `/run local h = LootHistoryDB.global.history;
h[#h].ts = h[#h].ts - 8 * 86400; print(#h)`. `/reload`, wait about five seconds, then `/run
print(#LootHistoryDB.global.history)` → one fewer than the first count; **Keep history for** still
reads 7 days; no Lua error. Result:

**CAP-32. Always keeps everything.** Set **Keep history for** to *Always*, `/reload` → nothing is
pruned. Result:

**CUR-1. A hidden tracking currency never writes its own row (P7).** Loot a currency the client also
tracks under a hidden id (the 2026-10-06 report: **Nebulous Voidcore**, hidden 3513 beside listed
3418) → History shows **one** Gain row for it, SubType the Currency-tab header (here *Midnight*), not
two a second apart with one SubType blank. With `/lh debug on` a line naming no listed currency logs
`[Drop] currency line reason=unlisted` and writes nothing. Rows recorded under the hidden id before
this fix stay: delete them from the row menu. Result:

## History window

**HIST-1. Toggle, show and hide.** `/lh toggle` twice, then `/lh show`, `/lh hide` → toggle flips,
show and hide are explicit; the window opens on History, and the last tab used is remembered within
the session. Result:

**HIST-2. Esc closes the window and its menu.** Open **Character**, leave its menu open, press Esc
→ the menu and the window both close; no menu is left floating. Result:

**HIST-3. `/lh hide` closes an open menu.** Open **Zone**, leave it open, `/lh hide` → menu and window
both gone. Result:

**HIST-4. Position, size and scale persist.** Drag the title bar, drag the bottom-right grip, `/lh set
settings.windowScale 1.3`, `/reload`, `/lh show` → same position, same size (never below the width
that fits every column), 1.3× scale. Result:

**HIST-5. Sort.** Click each header (Date, Time, iLvl, Item, Qty, Quality, Type, SubType, Source, Zone,
Vendor, Character), twice each → each direction renders; the active header shows one shared up or
down arrow, not Blizzard's spinner arrow. Result:

**HIST-6. Group by.** Cycle **Group by** through None, Day, Quality, Type, Type & SubType, Source, Zone, Character;
collapse and expand a header → each renders in column order; headers show a chevron right when
collapsed and a chevron down when expanded, not `+` / `-`. **Type & SubType** headers read
"Type: Armor · Plate" (just "Type: Armor" when an item has no subtype, a currency as "Currency · <category>"),
alphabetical by type then subtype; the same mode is offered on **Holdings**. Result:

**HIST-7. Filters and the row count.** Use **Date** (All, Today, Last 7 days, Last 30 days) and pick two
values in **Bound**, **Quality**, **Type**, **SubType**, **Source**, **Zone**, **Character** → rows narrow
(the filters intersect), a two-value menu reads "N selected", and the bottom-left footer "Showing X of
Y" updates live. Result:

**HIST-8. Database size footer.** Read the bottom-right footer → "Database ≈ <size>", matching the
panel's estimate; it does not change with filters, and does change after a new loot or a delete.
Result:

**HIST-9. Zone filter keys on the name.** With loot from a multi-floor dungeon (Halls of Atonement,
Dire Maul, The Deadmines), open **Zone** → each zone once; picking it shows every row from any floor;
rows with no zone share one **Unknown** entry that selects exactly them. Result:

**HIST-10. Bound filter.** Open **Bound** → five options (Not Bound, Bind on Equip, Bind on Pickup,
Warbound, Warbound Until Equipped) matching the Bound header legend; pick Not Bound, add Bind on
Equip → the visible lock colors match, and Not Bound rows show no lock. Result:

**HIST-11. Search.** Type in **Search items…**, then clear it → matches item names; clearing restores
the unsearched set. Result:

**HIST-12. The first dropdown click.** On a fresh `/reload`, click **Group by** → a menu opens under it
with no Lua error (LibKa0s v1.11.0 and v1.11.1 shipped a `Font not set` error on exactly this click).
Result:

**HIST-13. Every dropdown once.** Open Group by, Date, Bound, Quality, Type, SubType, Source, Zone,
Character and the export modal's **Data set** → ten menus, no error, each anchored under its own
button, at least as wide as it, and each button ends in a gray, vertically centered chevron.
Result:

**HIST-14. One menu at a time.** Open **Quality**, click **Zone** → Quality closes as Zone opens. Open
**Source**, click empty world → it closes. Open it, click the History window behind it → the menu
closes and the click lands on the window in the same press. Result:

**HIST-15. Row actions.** Right-click a row → a menu of four entries, every word kept: **Link to
chat** with a chat mark, **Blacklist item** and **Blacklist currency** with a prohibition mark each,
and a red **Delete** with the clear mark. Link to chat is disabled without an item link, Blacklist
item without an item id (a currency row) and Blacklist currency without a currency id (an item
row). Link to chat and Shift-click both put the link in
the chat box; hover shows the item tooltip; **Delete** removes the row and the table and footer
refresh with no gap. Result:

**HIST-16. The two menus dismiss alike.** With the row menu open, left- or right-click outside → it
closes. With a filter menu open, right-click a table row → the filter menu closes and the row menu
opens on that same press (two presses is a regression). Result:

**HIST-17. Dropdown rows.** Open **Character** and **Quality** → character rows show class icon, then
name in class color (a character with no class token shows the bare name); a selected multi-select
row shows a tick and goes gold; no row shows an empty box. Result:

**HIST-18. Save, Clear, Reset.** Set a group, sort and filters including a **Bound** pick, **Save** →
"view saved as default."; change filters, **Clear** → back to the saved view and the current player;
**Reset** → "view reset to stock defaults.". Save again, Clear, `/reload` → the Bound pick survived.
Result:

**HIST-19. The window opens on the current player.** `/reload`, `/lh show` → the saved view and the
current player; **Character** reads "Character: Current" with that menu row gold. On a character with
no loot (footer "Showing 0 of N") → still "Character: Current", not "Character: All". Result:

**HIST-20. The Character preset.** Open **Character**, click another character → Current goes gray,
that character goes gold, the button reads their name; click **Character: Current** → back to you in
one click, the button reads "Character: Current". Result:

**HIST-21. A selected character with no rows in view.** Filter to a character, then narrow the other
filters until they have no rows → the button still reads their name, never "Character: All".
Result:

**HIST-22. Window and button marks.** The title-bar close is the collection's ✕ mark, and the export
modal and copy window wear the same; the modal's **Export to CSV** carries a spreadsheet mark; the
filter bar's **Export**, **Clear**, **Reset** and **Save** carry no mark, only their word. Fail:
a blank space where a mark belongs (a path with `.tga`, or a name the catalog lacks); a thin text ×
in place of the close mark means the library did not load (DEGRADED-11). Result:

**HIST-23. Bound padlock and the resize grip.** The Bound column draws a padlock, and its header
legend uses the same padlock tinted per state; the bottom-right grip is Blizzard's ChatFrame
three-line hatch, as on the rest of the collection. Result:

**HIST-24. The export modal.** Drag the History window away from the screen center. On History,
click **Export** (right of filter row 2) → the modal opens centered on the History window, not the
screen, and reads **Export History**; on Insights → **Export Insights**. Result:

**HIST-25. History CSV.** Export **All Data** → the header `ts,date,time,char,classFile,itemID,currencyID,itemName,quality,qualityRaw,itemLevel,bound,vendorPrice,vendorPriceRaw,auctionPrice,auctionPriceRaw,value,valueRaw,auctionSource,itemType,itemSubType,quantity,source,zone,auc_auctionator_minbuyout,auc_tsm_dbmarket,auc_tsm_dbminbuyout,auc_tsm_dbregionmarketavg,auc_tsm_dbregionminbuyoutavg,auc_tsm_dbhistorical,auc_tsm_dbrecent,auc_tsm_dbregionhistorical,auc_tsm_dbregionsaleavg,auc_oribos_market,auc_oribos_region,wowheadLink,dir,kind,holder,from,to`
and one row per record: `date` DD-MMM-YYYY, `time` HH:MM; `quality` a label beside `qualityRaw`;
prices as `Ng Ns Nc` beside copper `*Raw` (auction blank when no price is selectable); `value` the
higher of the picked auction price and `vendorPrice`; `auctionSource` the provenance tag (e.g.
`tsm:dbmarket`); `auc_*` the raw captured copper per key; `bound` a label; comma names quoted;
`wowheadLink` a `wowhead.com/item=…` URL with `?bonus=…` when bonus IDs exist; currency rows fill
`currencyID` and leave `itemID` blank. `itemLink`, `sourceDetail`, `mapID`, `subzone`, `confidence`
are absent. Result:

**HIST-26. Insights CSV.** From Insights export → header `Section,Label,Count,Value`, mirroring the
panel: Summary (the KPI cards), By Source, By Character x Source, By Quality, By Character x Quality,
By Item Type, By Character x Item Type, By Bound Type, By Character x Bound Type, By Character, By
Weekday, By Hour, Top Zones, Top Items by Count / Value, By Day, and with currency in range Currency
Collected, Currency by Type x Source, Currency by Character x Type, Currency by Day. Values render
`Ng Ns Nc`. The `… x …` sections are the per-character companions, one `Char / Category` row each (By
Character x Source rows also carry the value). Loot sections are items-only, so a character's total
tallies across them; no By Keystone, Attribution Confidence, Currency by Source, flat Currency by
Character or currency Summary rows. Result:

**HIST-27. All Data and Current View.** Apply a filter, export **Current View** from each tab → both
CSVs honor the shared filter; **All Data** covers the whole visible history. Result:

**HIST-28. The copy window opens right.** History → Export → **Export to CSV** → the copy window opens
centered on the History window, above the modal (visible underneath), CSV pre-selected; it looks as
it always has (640x420, `FULLSCREEN` strata, dark backdrop, 10pt monospace). Result:

**HIST-29. Copy and Esc.** `Ctrl+C`, paste into an editor → the whole CSV with line breaks; `Esc` →
the copy window closes and the export modal stays open. Result:

**HIST-30. One copy window.** Export from Insights after History → the same window is reused (a
different modal title, no second frame). Result:

**HIST-31. The copy window follows its anchor.** Drag the History window elsewhere and export → the
copy window centers on it. Close the copy window, click **Export** to open the modal, type `/lh hide`
(the History window closes; the modal stays up), then click **Export to CSV** → the copy window
centers on the screen, with no error. Result:

**HIST-32. Copy window chrome.** Drag the copy window by its title bar, close it with its title-bar ✕
→ it moves, and the close mark matches every other window in the addon. Result:

**HIST-33. The export modal closes its menu.** Open **Data set** in the modal, click the modal's ×
→ the menu goes; reopen, open the menu, press Esc → the menu goes. Result:

**HIST-34. The library resize grip.** `/lh show`, drag the bottom-right grip with the **left**
button → the window resizes, the grip shows the pressed hatch while held and sits flush inside the
1px corner; it will not shrink narrower than every column fits or shorter than the minimum (about
460px), and the DB-size footer never sits under the grip. Release, `/reload`, `/lh show` → the same
size. Right-click the grip → nothing resizes. Result:

**HIST-35. The filter bar on one line (P4).** The widths come from the client's font metrics, and
the headless mock measures every string as 0, so only the client can check this. `/lh show`, then
drag the grip down to the minimum width. Check each of these:

- Every filter control's label sits on one line, with no wrap and no clipped tail. Pick two
  **Direction** options and read `Direction: 2 selected`. Pick **Common** in **Quality** and read
  `Quality: Common+`. Check **Character: Current**, the **Bound** and **Source** summaries, and
  `N selected` on each multi-select too.
- **Direction** and **Bound** are the same width. Compare their right edges with `/fstack`, or by eye
  against the controls stacked above or below them.
- The window's minimum width grows when the measured span needs it: the grip stops where the last
  control on each row still fits. An older saved size narrower than that opens widened to it after
  `/reload`.
- At the minimum width, **Export** is at least 120 px wide (`/fstack`, or `/dump` on the button's
  `GetWidth()`), the **Save / Reset / Clear** cluster spans exactly Export's width above it, and
  none overlaps the dropdown to its left.

Result:

**FB-1. The filter bar fills the window (P6).** `/lh show`, drag the grip down to the minimum width
→ both filter rows end the same distance in from the right border as they start from the left
(about 6 px), with **Export** and **Clear** flush to that margin. Drag the window wider, then
narrower again → every row-2 dropdown and Export grow and shrink together in proportion, both rows
keep the same right margin as the left at every width, **Group** stays exactly over **Date**,
**Direction** over **Bound**, and **Save / Reset / Clear** over **Export**. Open a dropdown's menu,
then drag the grip → the menu closes rather than hanging off a moved control. Result:

**AC-1. Search autocomplete on every tab (P9).** On each of **History**, **Insights**, **Timeline**
and **Holdings**, type a few letters of something you hold or looted into Search → a list opens
directly under the box, exactly as wide as it, in the same gray border (the two outlines read as one),
each name in its quality color, at most eight rows. History and Insights offer item and currency
names from the rows the other filters show (the sample under `/lh test`), never Gold; Holdings
offers what it lists, Gold included; Timeline offers things with **Gold** first when "gol" is typed.
**Keys:** Down / Up move the highlight, Enter picks it, Esc closes the list and keeps what you typed,
Tab picks the highlighted or first row, and focus never leaves the box. **Pick:** on History,
Insights and Holdings, Search reads exactly the picked name and the view filters to it; on Timeline,
the chart switches to the thing and Search keeps its name. **Close:** click a table row, the chart,
or another tab while the list is open → the list closes (if a row click leaves it open, note it: the
host then needs to clear focus on its own clicks). Drag the window grip wider and narrower with the
list open → it stays under the box at the box's width. Result:

## Insights

Open `/lh show` → **Insights** on a history spanning several days with currency loot (or `/lh test`).

**INS-1. The shared filter scopes everything.** Change the Date dropdown, a column filter and the
search on Insights → every card and chart re-scopes live; switching tabs keeps the same slice; a
filter matching nothing hides the charts cleanly. Insights has no range selector of its own.
Result:

**INS-2. KPI cards.** → records, distinct items, characters, value, active days, epic+ drops, best drop
(ilvl), richest drop, date range, busiest day; "value" is the higher of the picked auction price and
`vendorPrice`, times quantity. Result:

**INS-3. Headline size.** Every KPI value (value, richest drop, date range, busiest day too) renders at
the size of records; a long value stays on one line, shrinking to fit, never wrapping or clipping.
Result:

**INS-4. Coin glyphs.** Look at a money string on Insights (the value card, richest drop, Value By
Source), then at a Vendor or AH price cell on History → the Insights gold, silver and copper icons
are smaller: a fixed 10 px, about 25% under the client's default of about 14 px, which the History
price cells use. The size does not follow the text: on a KPI card the coins sit well below the
digits' height, and on a Value By Source row they are about as tall as the text. Result:

**INS-5. Section dividers.** The gold **LOOT** and **CURRENCY** titles are about 50% larger, with rule
lines about 25% thicker, than sub-section headers. Result:

**INS-6. Titles.** Every sub-section title is Title Case ("Loot By Source", "Loot By Hour Of Day",
"Top Items By Count"); the companions read "Loot By Character × Source / Quality / Item Type / Bound
Type" and "Value By Character × Source". Result:

**INS-7. LOOT order.** Under LOOT: Loot By Character, Loot By Source, Loot By Character × Source, Value
By Source, Value By Character × Source, Loot By Quality, Loot By Character × Quality, Loot By Item
Type, Loot By Character × Item Type, Loot By Bound Type, Loot By Character × Bound Type, Loot Over
Time, Value Over Time, Loot By Hour Of Day, Loot By Weekday, Top Zones, Top Items By Count, Top Items
By Value. No Quality mix, Mythic+ loot by keystone level or Attribution confidence chart. Result:

**INS-8. Companions.** Under each of the five categorical loot charts sits its stacked × Character
companion (character on the Y axis, the parent's colors); a companion with no data hides. Result:

**INS-9. Per-category bar colors.** Loot By Item Type, Loot By Weekday and Currency Collected bars are
each colored per category, matching their companions. Result:

**INS-10. Bar-colored labels.** On single-bar charts the row label takes its bar's color, except Loot
By Quality (quality color) and per-character bars (class color); stacked labels are unchanged.
Result:

**INS-11. No similar neighbors.** Item types, currencies and weekdays draw from the inverse-VIBGYOR
palette by rank → no two similar colors side by side in a chart or legend. Result:

**INS-12. Companion segment order.** Each companion's segments follow the parent chart's Y order (Loot
By Character × Bound Type follows Loot By Bound Type; Value By Character × Source is value-desc).
Result:

**INS-13. Legends.** Every single-bar categorical chart (Loot By Source, Value By Source, Loot By
Quality, Loot By Item Type, Loot By Bound Type, Currency Collected) and every companion has a swatch
legend under it, starting at the bars' left edge. Result:

**INS-14. Legend truncation.** A long legend label ("Artisan Enchanter's Moxie") ends in "…" without
overlapping; hovering the chip shows the full label. Result:

**INS-15. Totals tally.** Currency is excluded from LOOT: a character's Loot By Character total equals
the sum of its segments in each × Character companion; the records KPI still counts currency.
Result:

**INS-16. Row label truncation.** In LOOT and CURRENCY, a long row label is cut near 16 characters with
"…" on one line; hovering shows the full name. Result:

**INS-17. Tooltips carry the value.** Hover a bar row, a stacked row, a ranked-list row and a
bar-section legend chip → each reads "<full label>:  <value>" matching the row (money with coin
glyphs), including an ellipsized label and a clipped value. Only the companion legend chips are
label-only. Result:

**INS-18. Tooltip position.** Every Insights tooltip appears just above and right of the cursor.
Result:

**INS-19. Segment tooltips.** Hover one segment of any stacked bar (Loot By Character × Source,
Currency By Type × Source, Currency By Character × Type) → "<category>: <value>" (e.g. "Kill: 45").
Result:

**INS-20. The CURRENCY block.** With currency in range → the CURRENCY divider under LOOT, then
Currency Collected (one colored bar per currency, with a legend), Currency By Type × Source (stacked
by source, source legend), Currency By Character × Type (one stacked bar per character, a distinct
color per currency, legend), Currency Over Time (Per Day); no "Currency — N types" summary, no
Currency by Source chart, no flat Currency by character. Narrow to a range with no currency → the
whole block, divider included, disappears and LOOT still renders. Result:

**INS-21. Live update.** Loot an item with Insights open → the cards update. Result:

**INS-22. The three-file Insights renders as before.** Open Insights with real history, then again
under `/lh test` → no Lua error; every LOOT and CURRENCY section, every legend, the hover tooltips
(bars, stacked segments, strip bars, list rows, legend chips) and the three strips draw as they did
before the split; resize the window → it re-lays out; change a filter → it refreshes live. Result:
pass (owner, 2026-10-02)

## Filter lists

Filtering is point-in-time: a list changes what happens to future loot and never touches stored rows.

**FILT-1. The Filters tab and its sub-strip.** `/lh config` → General → **Filters** (the last tab) →
it opens on **Blacklist** in a secondary strip (Blacklist, Whitelist, Currencies) that scrolls with
the content; one list and one add box show at a time. Leave for another tab and back → the same
sub-tab; `/reload` → back on Blacklist. Result:

**FILT-2. Blacklist from a row.** In History, right-click a row → **Blacklist item** → the chat line
`Manage in Settings ▸ General ▸ Filters ▸ Blacklist` ("blacklisted …"), a gold-bordered popup, and the
row stays in the table. **Blacklist currency** on a currency row names **▸ Currencies**. Result:

**FILT-3. The blacklist stops future capture.** Loot the blacklisted item again → no new row (with
debug on, `[Drop] … reason=blacklist`); its old rows are untouched. Result:

**FILT-4. Removing brings nothing back.** Click the **X** on its entry, loot it again → nothing
reappeared (nothing was hidden) and the new loot records. Result:

**FILT-5. The whitelist overrides the gates.** On **Whitelist**, add an id that would be dropped
(below threshold, muted source or quest item), loot it → a plain row records. Result:

**FILT-6. Leaving the whitelist keeps rows.** Remove that id → its rows stay; later loot of it goes
through the gates again. Result:

**FILT-7. One list per id.** Add a Whitelist id to the Blacklist (or the reverse) → it leaves the other
list. Result:

**FILT-8. Entry layout.** Each entry reads X on the left, icon, name and id (`Unknown item <id>` until
cached, then the name fills in), no right-hand Remove button; hover shows the item tooltip; an empty
list reads `(none)`. Result:

**FILT-9. Add by name or link.** On Blacklist, type a bag item's name in any case (`hearthstone`) and
press Enter; shift-click a link into the box and press **Add** → each adds that id, clears the box,
and shows at once. Result:

**FILT-10. Suggestions.** Type the first letters of a multi-rank crafted consumable in your history
(`hushed`) → from the second letter (digits from the first) a list opens under the box, above the
panel, with each rank on its own row, quality-tier icon and gray id; Up/Down move, Enter adds the
highlighted row, Escape closes; clicking a rank adds exactly that id and closes the list. Result:

**FILT-11. A shared name needs a pick.** Type the shared name in full and press Enter without picking
→ nothing added; orange `Several items are named '<name>' — pick one from the list, or use the id.`
with the ranks still listed. Same with two ranks only in your bags and never looted. Result:

**FILT-12. Typing after an arrow submits the text.** Arrow to a row, type another letter and press
Enter at once → the typed text is submitted, not the earlier highlight. Result:

**FILT-13. History and list items resolve by name.** Type the name of an item not carried this
session but in your history or on the Whitelist → it resolves and adds. Result:

**FILT-14. Unknown names and garbage.** Type an item name that no bag, history or list knows, then
`abc` → nothing added, the text stays, and an orange line reads `No item named '<name>' that the game
can find. Names work for items you carry (or carried this session), items in your loot history and
ones on these lists; otherwise use the id or shift-click a link.`; hovering the box ends with the
same sentence; nothing prints to chat. Result:

**FILT-15. Currencies.** On **Currencies**, add by id and by shift-clicked currency link → each shows
its name; type a looted currency → it is suggested and adds by name; type one never looted and not
listed (`Honor`) → refused with `No currency named '<name>' that this page knows. Currency names work
for currencies in your loot history and ones on this list; otherwise use the id or shift-click a
currency link.` Result:

**FILT-16. The currency blacklist.** Right-click a currency row → **Blacklist currency**; loot it again
→ no new row; on Currencies it shows its name, an X on the left and no Remove button; click X, loot
→ it records. Re-add it, **Clear all** → a confirm; Accept → the list empties and loot records.
Result:

**FILT-17. Lists never touch stored rows.** To remove existing rows use the row's **Delete**; the
browser's filter dropdowns offer no blacklist or whitelist option. Result:

**FILT-18. Refresh is instant.** With a dozen or more Blacklist ids, click away from Filters and back
several times, and between its three sub-tabs → no stutter or freeze. Result:

**FILT-19. An off-screen add repaints once.** With the panel closed, blacklist a row from History, then
open Filters → the new id is there. Result:

**FILT-20. Two to a line.** With six or more Blacklist ids and two or more currencies → each list reads
two entries per line, left to right then down, with X, icon and name aligned across and down.
Result:

**FILT-21. An odd count.** With an odd number of entries → the last line has one entry on the left
and space to its right, not one entry stretched across. Result:

**FILT-22. Long names truncate.** A long item name is cut at the tail (a long one loses its `(id)`)
instead of wrapping; hovering the entry names the item. Result:

**FILT-23. Grid repacks and falls back.** Remove an entry, then add one → the grid repacks left to
right. Narrow the canvas (small windowed width or `/console uiScale 1`) below about 580px of panel →
item lists draw one full-width column, with no icons stacked over wrapped names and no X on a line
of its own; widen and reopen → two columns. If you cannot get that narrow, record that. Result:

**FILT-24. Blacklist and Whitelist Clear all ask.** With ids on **Blacklist**, click its **Clear
all** → a popup reads `Clear ALL item ids from the blacklist? Future loots of them will be recorded
again; your existing history is unaffected.`; **No** → the ids stay; **Clear all** again, **Yes** →
the list empties and chat prints `blacklist cleared (N ids).` On **Whitelist** the same → `Clear ALL
item ids from the whitelist?`, then `whitelist cleared (N ids).` The Currencies list's Clear all is
FILT-16. Result:

**FILT-25. The item lists draw as before.** `/lh debug on`, then `/lh config` → General → **Filters**
→ step through **Blacklist**, **Whitelist** and **Currencies** → every list renders exactly as before
(no help marks: no entry here carries help), with no Lua error and no `[Cfg] help art:` line in the
console. Result:

## Launcher

One LibDataBroker object drives the minimap button (LibDBIcon) and any broker display. Its visibility
is `minimap.hide`, shown in the CLI and panel as **Minimap button** / `minimap.shown`, in `global`.

**LAUNCH-1. The art appears.** Look at the AddOns list row, the minimap button and a broker row (Titan
Panel, ElvUI data texts or Bazooka, "LootHistory") → each shows the addon's own logo, not a Blizzard
icon or an empty square. Only a client can show this. Result:

**LAUNCH-2. Tooltip.** Hover the button → in order, each once: `Ka0s Loot History  v<TOC version>`,
`Enabled: Yes` (green), `Locked: No`, `Test mode: Off`, "N records" (gray), `Left-click: Open
settings`, `Right-click: Options menu`. Tick Lock frame and Test mode, hover → `Locked: Yes`, `Test
mode: On`. Result:

**LAUNCH-3. Left-click.** Left-click → Settings opens, enabled or disabled, printing nothing. Result:

**LAUNCH-4. The right-click menu.** Right-click → a menu titled `Ka0s Loot History` with checkboxes
**Enabled**, **Locked**, **Test mode**, **Show window**, each ticked to match. Click each (reopening
the menu) → each acts once and the menu closes: Show window acts as `/lh toggle` (General visibility
refuses it the same way); Test mode runs `/lh test`; Locked flips **Lock frame**; Enabled runs `/lh
disable` and prints `settings.enabled = false`. Result:

**LAUNCH-5. Disabled.** While disabled → the tooltip shows `Enabled: No` (red) and the two hints; the
menu has **Enabled** live and `Locked (enable the addon first)`, `Test mode (enable the addon
first)`, `Show window (enable the addon first)` grayed and inert; **Enabled** prints
`settings.enabled = true` and the addon comes back. Result:

**LAUNCH-6. Position persists.** Drag the button around the ring, `/reload` → it stays where dragged
(LibDBIcon's `minimapPos` in the `minimap` table, not keyed by the registration name, so the rename
of the registration to `LootHistory` did not move it). Result:

**LAUNCH-7. Minimap button toggle.** Untick **Minimap button** → the icon hides at once; tick → back;
the state survives `/reload`. Result:

**LAUNCH-8. Hidden stays hidden through a reset.** Untick **Minimap button**, `/lh get minimap.shown`
→ `false`; **Reset all settings** (confirm) → still hidden; `/lh reset minimap.shown` → shown. Result:

**LAUNCH-9. The broker row clicks alike.** Left- and right-click the broker row → the same actions
and the same menu as the button. Result:

**LAUNCH-10. Hiding the button keeps the broker row.** Untick **Minimap button** → the broker row
stays (a display offers its own per-plugin toggle). Result:

## Debug console and diagnostics

Logging (`/lh debug on|off`) is session-only and independent of the console window. Tags and their
meaning are in [debug.md](debug.md).

**DIAG-1. Bare `/lh debug` toggles the window only.** `/lh debug` twice → the console opens and closes;
the logging flag does not change. Result:

**DIAG-2. Logging on and off.** `/lh debug on`, loot at threshold, loot below it, `/lh debug off` →
a `<ts> | [Loot] …` line and a `[Drop] …` line, then nothing more. Close the console, `/lh debug
on`, loot, `/lh debug` → the lines captured while it was closed are there. Result:

**DIAG-3. The acks and the `[Init]` line.** `/lh debug on` then off (and the header **Debug: ON/OFF**
toggle) → chat `[LH] debug logging ON` (green) / `OFF` (red); the console gets `[Debug] logging
enabled` followed by one `[Init] LootHistory v<ver>, schema v<n>, profile 'Default', <r> records`
(on enable, not at login), and `[Debug] logging disabled`. Result:

**DIAG-4. Copy, Clear, Esc.** In the console, **Copy** → an editbox of plain text; **Clear** → empty;
**Esc** → closes. Result:

**DIAG-5. Scrolling.** With many lines, drag the scrollbar and mousewheel over the log → both move
together; the thumb sits at the bottom on the newest line, the top on the oldest; when every line
fits the track shows but is inert. Result:

**DIAG-6. The line counter and cap.** Watch the bottom-right `N / 3000 lines` → it ticks up and reads
`0 / 3000 lines` after Clear. `/run for i = 1, 80 do SlashCmdList.ACECONSOLE_LH("diagnostics") end` →
it pins at `3000 / 3000 lines`; **Copy** opens all 3000 without a noticeable hitch. Result:

**DIAG-7. `/lh debug events`.** Run it, then `/lh disable`, `/lh enable`, loot, and run it again →
`[LH] rejected events: none` both times; window and logging untouched; the loot records. Result:

**DIAG-8. After a reload.** `/reload` → logging off, console closed. Result:

**DIAG-9. The console checkbox follows the window.** Tick **Debug console** (Master controls) → the
console opens; untick → it hides, and `/lh debug on|off` still owns logging (`/lh get
state.debugConsole` reports the window). With the console closed, `/lh debug` → the console opens
and the checkbox is ticked; `/lh debug` again → the console closes and the checkbox unticks; open
it once more and close it with Esc or its ✕ → the checkbox unticks. `/reload` → unticked. Result:

**DIAG-10. Console chrome.** Open `/lh debug` → a flat 1px black border with a lighter inner line, a
gold title, a gray divider, and three same-size icon buttons top-right (✕, copy, clear) evenly spaced;
the copy window takes the same ✕. It matches every other Ka0s console. Fail: a thin × with the words
"Copy" and "Clear", meaning `core/DebugLogSetup.lua` stopped passing `addonName`. Result:

**DIAG-11. Console strings and font.** The title reads **Loot History — Debug**, the toggle **Debug:
ON** / **Debug: OFF**, the status `N / 3000 lines`, and the copy window **Copy log — Ctrl+C, then
Esc**; the console and the export copy box render in JetBrains Mono (an `[Init]` line's columns line
up). Result:

**DIAG-12. One `[Open]` per loot window.** `/lh debug on`, open a corpse or chest with many slots →
exactly one `[Open] LOOT_OPENED N slots -> …`. Result:

**DIAG-13. One `[Set]` per setting.** Change a setting (panel or `/lh set`) → one `[Set] <path> =
<value>`, no `[Cfg]`. Result:

**DIAG-14. A bulk reset is one line.** Change two settings, press General's **Defaults** (or the
footer control) → one `[Set] reset profile 'Default' to defaults (2 rows)`, no per-row `[Set]`;
again → `(0 rows)`; `/lh resetall` logs the same one line; `/lh reset <path>` stays one `[Set]
<path> = <value>`. Result:

**DIAG-15. Data and reset-all lines.** `/lh purge` (confirm) → one `[Data] purge-all removed N rows`;
delete a row → one `[Data] delete removed 1 rows`; change two settings, **Reset all settings**
(confirm) → one `[Set] reset profile 'Default' to defaults (2 rows)`, no `[Data]` line. Result:

**DIAG-16. Window and Insights lines.** Open the window → `[UI] window shown`; switch to Insights →
`[UI] tab -> Insights` and one `[Insights] computed …`. Result:

**DIAG-17. One `[Table]` per change.** Type in search, change group or sort → one `[Table] rendered
M/T rows (…)` per change, never per row. Result:

**DIAG-18. One `[Filters]` per list edit.** Add or remove a Blacklist or Whitelist id → one `[Filters]
blacklist=B whitelist=W`. Result:

**DIAG-19. The report.** `/lh debug on`, loot, `/lh diagnostics` → the console opens if closed; the
`[Loot]` line is still above `[Diag] ==== Ka0s Loot History diagnostics begin ====`; the report ends
`==== Ka0s Loot History diagnostics end: N line(s) ====`; chat shows one line `Diagnostic report
written to the debug console: N lines. Use Copy to share it.`; nothing was cleared. Result:

**DIAG-20. The paste is plain.** **Copy** and paste into an editor → trace, begin and end markers,
no `|c`, `|H` or `|T` escapes; item names in the tail are plain. Result:

**DIAG-21. Diagnostics turns logging on for the session.** `/reload` → logging is off (DIAG-8).
`/lh diagnostics` → chat prints `[LH] debug logging ON`, then the report's line-count line; the
console holds `[Debug] logging enabled` and the `[Init]` line above `[Diag] ==== Ka0s Loot History
diagnostics begin ====`, the report's header reads `debug logging: on`, and the title bar reads
**Debug: ON**. Loot at threshold → a `[Loot]` line streams. `/lh diagnostics` again → the report
appends with no second `logging enabled` line. `/reload` → logging is off again; `/lh debug
diagnostics` → the same, logging on for the session. Result:

**DIAG-22. Every form.** `/lh debug diagnostics`, `/loothistory diagnostics`, `/loothistory debug
diagnostics` → each writes the same report. Result:

**DIAG-23. No short aliases.** `/lh diag` and `/lh dump` → `unknown command` and the help index; `/lh
debug diag` → toggles the console like any unknown word. Result:

**DIAG-24. While disabled.** `/lh disable`, then `/lh diagnostics` and `/lh debug diagnostics` → full
reports reading `identity: enabled=false stoodDown=true testMode=false` and `capture: stood down
(the loot, currency and context events are unregistered)`; debug logging turns on (DIAG-21) but
nothing else comes back on. `/lh enable`.
Result:

**DIAG-25. The README steps.** `/reload` with the console closed, then follow the README's `##
Reporting a bug` steps word for word → each works, and the paste holds the trace and the whole
report. Result:

**DIAG-26. The console resizes.** Open `/lh debug`, fill it past one screen (`/lh diagnostics`) →
a size grabber in the bottom-right corner, over the frame and clear of the `N / 3000 lines` counter.
Drag it larger and smaller on both axes → the log reflows to the new size, the scrollbar thumb and
the counter stay in step, the title and the three top-right buttons stay placed, and the lines and
scroll position are kept. Drag it as small as it goes → it stops where the title and every button
still fit side by side and a few lines still show; nothing overlaps. Result:

**DIAG-27. Session size, default after a reload.** Resize the console, close it (✕, Esc or `/lh
debug`) and reopen it → the same size. Drag it somewhere else and reopen → the size is still yours.
`/reload`, then `/lh debug` → back to the default 700 × 344. Result:

**DIAG-28. The copy windows resize.** In the console, **Copy** → the copy window has its own grabber;
drag it on both axes → the text box widens and narrows with it, the scroll bar's down arrow stays
clickable above the grabber, and it stops at a minimum. Close and **Copy** again → the same size;
the console keeps its own size. The History window's **Export** copy box does the same, with a size
of its own that neither console window shares. `/reload` → both open at their default. Result:

**DIAG-29. Another addon's console is its own.** With a second Ka0s addon loaded, resize this
console, then open that addon's `/<prefix> debug` → it opens at its default; resize it and reopen
`/lh debug` → this console keeps the size you gave it. Skip, and say so, when no other Ka0s addon is
installed. Result:

**DIAG-30. The Diagnostics link.** `/lh debug` → in the title bar, top left, the word **Diagnostics**
sits just right of the **Debug: ON/OFF** toggle with a small gap, drawn orange in the same plain text
as the toggle: no button art, border or background. Hover it → it brightens; move off → orange
again. With logging off, click it → logging turns on first (the toggle reads **Debug: ON**, chat
prints `[LH] debug logging ON`, the console gains `[Debug] logging enabled` and the `[Init]` line),
then the report lands after them as DIAG-19 describes, with its one chat line. Click it again → the
report appends once more with no second `logging enabled` line, and logging stays on. Click the
toggle between ON and OFF → the gap after it holds for either word. Drag the console as small as it
goes (DIAG-26) → the link still fits beside the toggle and the title. Result:

**DIAG-31. A slash refusal is the library's one `[Cmd]` line.** `/lh debug on`, then `/lh get` → chat
prints the `get` usage line; the console gains exactly one `[Cmd] refused get: usage`. `/lh
nosuchverb` → chat prints `unknown command` and the help index; the console gains one `[Cmd] refused
nosuchverb: unknown verb`. `/lh disable`, then `/lh show` → chat prints the disabled line; the
console gains one `[Cmd] refused show: disabled`, and no second line for the same refusal (no `/lh
show refused: addon disabled`). `/lh version` → it prints; no `[Cmd]` line. `/lh enable`. Result:

**DIAG-32. A latch edge is the library's one `[Lifecycle]` line.** `/lh debug on`, then `/lh disable`
→ after `[Set] settings.enabled = false`, one `[Lifecycle] stood down: added disabled (holds:
disabled)`, then `[State] stand-down: capture unregistered, N deferral(s) canceled`; only the
`[Lifecycle]` line names the holds. `/lh disable` again → no `[Lifecycle]` line (nothing moved).
`/lh enable` → one `[Lifecycle] stood up: released disabled (holds: none)`, then `[State] stand-up:
capture registered` and `[State] dependencies: price providers: <the ones installed, or none>;
latch: LibKa0s-Lifecycle-1.0`. Result:

**DIAG-33. State lines from login land at `debug on`.** `/reload` (logging off, DIAG-8), then `/lh
debug on` → after `[Debug] logging enabled` and the `[Init]` line, the console holds `[Launcher]
registered` and `[State] dependencies: price providers: …; latch: LibKa0s-Lifecycle-1.0`, each once,
written at the enable although login ran them with logging off. `/lh debug off`, `/lh debug on` →
neither line again. Result:

## Ledger and holdings

The timeline ledger's Phase 1 (spec `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md`).
Run LED-5 on an account that still holds a **schema 10** SavedVariables file with loot history in it
(copy `LootHistory.lua` from before the upgrade into `WTF/Account/<account>/SavedVariables/`, then
log in). Every other check runs on the live account, with the ledger tick left on (**Track
holdings and losses** under Settings > General > Capture).

**LED-1. Fresh login.** Log in a character with items in its bags and equipped, some gold and a few
currencies, then open the window and select the **Holdings** tab → the tab lists the character's bag
items, equipped items, gold and currencies, each with a total. Expand one item → one line for the
character, class-colored, with `Bags n` (and `Equipped` where it applies) and an age of `now`. The
bank has not been read yet, so a bank line, where shown, reads **never**. Result:

**LED-2. Open the bank.** At a banker, open the bank and the warband bank, then close them → the
`Bank` and `Warband` containers populate on the Holdings tab, warband gold appears on a **Warband**
line, and the ages read `now`. `/reload`, reopen Holdings away from the bank → the same values are
there, now with ages (`m`, `h` or `d`, rising with real time) and no bank line has gone to zero.
Result:

**LED-3. A second character.** Log in a second character, open Holdings, and clear the Character
filter to **All** → both characters appear, each class-colored, and the Warband appears **once**,
labeled `Warband` and never as `§warband`. The first character's lines keep the ages they had.
Result:

**LED-4. Potions in combat.** With 5 of one potion in your bags and the Holdings tab open, drink all
five during a fight with a dummy (or in a dungeon) → no lag, stutter or Lua error while the events
fire. Leave combat → the bag count drops by exactly 5, in one refresh (the tab repaints once, not
five times). `/lh debug on` shows at most one `[Holdings] flush: 1 holder(s) changed` line for the
whole fight. Result:

**LED-5. Upgrade from schema 10.** Log in on the schema 10 file with history → about five seconds in,
one popup with the reset recommendation, showing your record count. Run all four ways, restoring the
saved copy each time. **Keep history** → prints `keeping your loot history.` and never asks again.
**Esc** → closes without a choice and asks again at the next login. **Export first** → opens the
window's export box; closing it shows the popup again. **Reset history** → asks `Delete N loot
records permanently?`; **Yes** empties History (`/lh purge` would find nothing) and prints `history
reset; the ledger starts now.`, and the Holdings tab still lists everything it held. A character
already on schema 11 gets no popup. Result:

**LED-6. Warband gold away from the bank.** Open the warband bank once, close it, walk away from any
banker, `/reload`, and read the **Warband** line's gold on the Holdings tab → record whether the
value is the last-read amount (the client answered `C_Bank.FetchDepositedMoney`) or the line shows
an age far older than the others (it answered `nil`). Either is a valid outcome — this check
**records** which one the client does, for spec §5.6's open question and ARCHITECTURE's known
limitations. It must never show `0` that was not there. Result:

**LED-7. `/lh holdings <name>`.** `/lh holdings hearthstone` (any item you hold) → up to ten lines
`<name>: <total>`, each total matching the Holdings tab. A currency name prints the count. `/lh
holdings zzzz` → `no holdings match 'zzzz'.` With the addon disabled (`/lh disable`), the verb answers
the one disabled line. Result:

**LED-8. The tracking switch.** Untick **Track holdings and losses**, then `/etrace` (filter on
`BAG_UPDATE`) → no `BAG_UPDATE` handling by LootHistory, and drinking a potion changes nothing on the
Holdings tab. Re-tick it → the events are handled again and the tab catches up on the next bag
change. `/lh set settings.trackLedger false` and `true` do the same. Result:

**LED-9. Holdings columns, banding, tooltips and the header row (P4).** Open the window at its
minimum size on the **Holdings** tab with a few items of different qualities, one currency and gold
listed, and check each of these:

- The header row reads exactly `Name · iLvl · Quality · Type · SubType · AH Price · Total · Value`,
  gold, one line each, over the right columns. **No other text sits in the header row.**
- **No stray text after the Timeline (P5).** The owner saw faint green text (`Cou…`, `Coun… <Tr…`)
  over the Holdings header near **Total** and over History rows (under Item on a Gain row, and near
  Source), at different places on the two tabs. The suspected cause was a Timeline or Insights
  region parented outside its pane. The headless suites rule out one form of that: creation-time
  parenting of the Timeline tab and the Insights chart layout. `tests/region_trace.lua` records the
  parent each frame, FontString, Texture and Line is given when it is created, and with the pane
  hidden none of them reads as visible (the Timeline case visits Timeline, then History, then
  Holdings). The trace does not cover a region re-parented after it is made (`SetParent`,
  `SetScrollChild`), the Insights pane's own chain (`Analytics:Attach`, its scroll frame and the
  stat cards; the test builds the chart layout under a stand-in root), or GameTooltip and other
  shared frames, so a leak through any of those is still a lead. **The bug is still open: no fix
  has shipped and the source is unconfirmed.** A fix waits on the in-game frame path below. To check: open the
  **Timeline**, chart Gold, type in Search so the suggestion list opens, hover the chart, then
  switch to **History** and to **Holdings**, and do the same from **Insights**. Neither tab shows
  any green text that is not its own. If any appears, note its text, its color and the tab you came
  from, then hover it with `/fstack` and record the frame path. That path names the FontString, and
  it is the evidence the fix needs.
- Widen and narrow the window. The optional columns hide right to left (AH Price first, iLvl
  last), and Name, Total and Value always stay.
- Every other item line has the faint stripe. Expand a striped item and the holder lines under it
  have the same stripe. Expand an unstriped one and its holder lines are unstriped too.
- Hovering an item's name shows its item tooltip, hovering the currency shows the currency tooltip,
  and hovering Gold shows `Gold` with the total. Moving off the row hides the tooltip.
- Clicking a header sorts by that column. Clicking it again reverses the order, and the arrow
  moves to that header.

Result:

**LED-10. Bank drift from outside the addon (P4).** This is the answer to "what if I trade with the
addon off, or on another PC?" The headless mock cannot reproduce the client's read of the bank as it
opens, so run it in the client. Visit a banker once with the addon on (the bank and the warband tab
now have a baseline), then leave. Change the bank and a warband tab with the addon off: `/lh
disable` (or untick it in the AddOns list) and deposit or withdraw a few known items, or do the same
from another PC that has no copy of this SavedVariables file. Turn the addon back on, `/reload`, and
visit a banker. Check each of these:

- History gets `UNTRACKED` rows for **exactly** the difference: one IN or OUT per item that changed,
  each with the changed count, on the character for the bank and on **Warband** for the tab. No row
  is a MOVE (⇄), and no row has a guessed reason such as Vendor or Loot.
- Deposit one more item in the same visit → one MOVE row (bags → bank), not `UNTRACKED`.
- The Holdings tab's bank and warband counts match the bank you see.
- A bank never read before (a new character's first visit) writes no rows at all.

Caveat: the opening read runs about 0.35 s after the bank frame shows (the flush debounce). A deposit
made inside that window is folded into the drift read: its bank side lands as an `UNTRACKED` IN and
its bags side is classified on its own, so it is not a MOVE row. Wait a moment after opening the
bank before depositing, and record what a quick deposit shows if you test it.

Result:

**LED-11. History Direction column (P5).** Open History with the Direction dropdown on **All** so
gains, losses and transfers all show. Check each of these:

- The column header reads **Direction**, and the column is wide enough that `Transfer` is not cut off.
- A gain reads `▲ Gain` in green, a loss `▼ Loss` in red, a transfer `⇄ Transfer` in gray. The glyph
  and the label share one color, and the glyph is a real arrow, not a box.
- A row recorded before the ledger existed (no direction stored) reads `▲ Gain` in green.
- Scroll the list up and down several pages so rows are reused: every row keeps the glyph, label and
  color that match its own direction, with no glyph left over from another row.
- Pick **Group: Direction**: the group-header rows show no glyph, and the rows under each header
  match it. Click the Direction header to sort: gains, losses, transfers (and the reverse).

Result:

**LED-12. History gold amounts and the Gold tooltip (P5).** With **Record gold** ticked, open History
on rows that include gold gains and losses (a large one if you have it, six or seven digits of gold).

- The Qty column shows every gold amount in full, sign included (`+1,521g 3s 7c`, `-9,661g …`), with no
  `…` cut-off; item and currency counts still read as before.
- Hover a gold row: the tooltip matches BankLedger's gold row: a `Gold` title in pale gold, an
  `Amount` line with the signed coin string on the right, and a gray `Right-click for options` line.
  It never shows an item tooltip. Moving off the row hides it.
- Hover an item row and a currency row: their own tooltips are unchanged.
- The window's minimum width still shows every column: drag the grip to the smallest size and no
  column overlaps its neighbor.

Result:

## Ledger capture (timeline ledger Phase 2)

The timeline ledger's Phase 2 (spec `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md`):
every gain, loss and transfer written as History rows. Run on the live account with **Track holdings
and losses** and **Record gold** ticked, History's Direction filter set to **All** (Direction
dropdown, row 1 of the filter bar) so transfers show, and Quality left on its default. A move inside
one holder is one `⇄` row; since Phase 7 a move between two holders is a loss on the sender and a
gain on the receiver under the action's reason (TR-1 to TR-3). **Bracketed lines are API facts the headless suite could not verify**:
when one fails, the fix is a Compat or mock correction in a follow-up commit, and the check is
re-run. Phase 2 is signed off only when all of LED-P2-01 to LED-P2-24 are recorded.

**LED-P2-01. Bank deposit and withdraw.** At a banker, deposit a stack from your bags, then withdraw
half of it → only `⇄` rows (Direction filter, Transfers), `Bags` to `Bank` and back; no gain or loss
row for the item, and the Holdings tab's bank column updates. Result:

**LED-P2-02. Warband deposit.** Put an item stack and some gold into the warband bank → for each, an
`OUT WARBAND_DEPOSIT` on the character and an `IN WARBAND_DEPOSIT` on the Warband (Phase 7; no `⇄`). [`ACCOUNT_MONEY` fires on a warband gold
deposit; `C_Bank.FetchDepositedMoney(Enum.BankType.Account)` answers while the bank is open.] Result:

**LED-P2-03. Vendor.** Sell a junk item, repair, buy one item, buy one back → item `OUT SELL` and
gold `IN SELL` (about 1.5 s later), gold `OUT REPAIR`, gold `OUT BUY` with item `IN VENDOR` (the item
row chat-claimed), and the buyback as gold `OUT BUY`. [`RepairAllItems` and `BuybackItem` are
hookable globals on 12.x.] Result:

**LED-P2-04. Loot.** Kill a mob that drops gold and two items, one of them gray → one claimed row per
item and one claimed gold row, `source=KILL`. The gray item appears in History only after Quality →
Poor is selected (the minimum-quality view floor). [`CHAT_MSG_MONEY` arrives as "You loot ..." built
from `GOLD_AMOUNT` / `SILVER_AMOUNT` / `COPPER_AMOUNT`.] Result:

**LED-P2-05. Combat potions.** Drink 3 potions in one pull → no hitch during the pull; after combat
exactly one `OUT CONSUME` row with quantity 3. A second pull within 60 s amends that row instead of
adding a second. Result:

**LED-P2-06. Mail to your own alt.** Send items and gold to an alt → `OUT ALT_MAIL` rows on the
sender (Phase 7), and a gold `OUT MAIL_SEND` for the postage. Log the alt in and take the mail →
`IN ALT_MAIL` rows on the alt, no `⇄` and no second loss.
[`SendMail` is a post-hook and `GetSendMailItem` / `GetSendMailMoney` still return the staged
attachments when it runs; `MAIL_SEND_SUCCESS` fires after the bags change or within the 10 s window.]
Result:

**LED-P2-07. Mail from others and a won auction.** Take a mail from another player and an auction
you won → `IN MAIL` and `IN AH`, chat-claimed when a loot line fires. [`GetInboxItem(i, a)` returns
`name, itemID, texture, count`.] Result:

**LED-P2-08. AH post.** Post one item and one commodity → `⇄` to `me/auctions` for each and gold
`OUT AH_POST_FEE`. [`C_AuctionHouse.PostItem(itemLocation, duration, quantity, bid, buyout)` and
`PostCommodity(itemLocation, duration, quantity, unitPrice)`: the third argument is the quantity;
`C_Item.GetItemID(itemLocation)` resolves it.] Result:

**LED-P2-09. AH outcomes.** Cancel one auction (the return, then taking it, is a `⇄`), let another
sell (take the money: item `OUT AH_SOLD` and gold `IN AH_SOLD`). [`OWNED_AUCTIONS_UPDATED` fires after
opening the Auctions tab; `GetOwnedAuctionInfo(i).status` uses `Enum.AuctionStatus.Active` / `Sold`;
`AUCTION_SOLD_MAIL_SUBJECT` matches the sale mail subject and its `%s` is the item name only.]
Result:

**LED-P2-10. Guild bank.** Deposit and withdraw an item and some gold → `OUT GUILD_DEPOSIT` and
`IN GUILD_WITHDRAW`. [`GuildBankFrame` exists after `Blizzard_GuildBankUI` loads and its `OnShow` /
`OnHide` fire on open and close.] Result:

**LED-P2-11. Crafting.** Craft 5 of a recipe → the reagents as `OUT CRAFT_REAGENT` rows and the
product as `IN CRAFT`. [`C_TradeSkillUI.CraftRecipe` / `CraftSalvage` / `CraftEnchant` exist and are
hookable.] Result:

**LED-P2-12. Disenchant.** Disenchant one item → the item as `OUT DECONSTRUCT` and the materials as
`IN DISENCHANT`. Result:

**LED-P2-13. Warband currency transfer.** Transfer a transferable currency to an alt → an
`OUT CURRENCY_TRANSFER` on you and an `IN CURRENCY_TRANSFER` on the alt (to `Alt/currency`, one shared
`pairId`; Phase 7), and any fee as `OUT TRANSFER`. The alt's next login shows no `UNTRACKED` row for it.
[`CURRENCY_TRANSFER_LOG_UPDATE` fires; `C_CurrencyInfo.FetchCurrencyTransferTransactions()` returns
records with `currencyType`, `quantityTransferred` and `destinationCharacterName`;
`CURRENCY_DISPLAY_UPDATE`'s `destroyReason` names `AccountTransfer`.] Result:

**LED-P2-14. Currency spend.** Spend crests on an upgrade and currency at a vendor → `OUT` rows with
mapped reasons (not `OTHER`). [`CURRENCY_DISPLAY_UPDATE`'s payload is `(currencyType, quantity,
quantityChange, quantityGainSource, quantityLostSource)`; `/dump Enum.CurrencySource` and `/dump
Enum.CurrencyDestroyReason` contain the member names in `C.CURRENCY_SOURCE_REASON`. Correct that table
if they do not.] Result:

**LED-P2-15. Login drift.** Disable the addon, log in, move items about, re-enable it and `/reload`
→ `UNTRACKED` rows for the differences. A brand-new character's first login writes none. Result:

**LED-P2-16. Resume drift.** `/lh disable`, loot something, `/lh enable` → the loot appears as
`UNTRACKED` about one second after enabling. Result:

**LED-P2-17. History display.** The glyphs ▲ ▼ ⇄ render (no boxes) in the mono face, colored (green,
red, gray); Qty reads `+3` / `-3`; gold rows show in pale gold; the Direction filter defaults to Gains +
Losses; ticking **Show transfers by default** then **Clear** includes transfers; Group by Direction and
by Holder both work. [JetBrains Mono carries U+21C4.] Result:

**LED-P2-18. Insights.** With losses in range: Gained, Lost, Net and Transfers cards, and the "Gains
vs losses by reason / character / kind" charts above LOOT. Under the default Direction filter the
Transfers card reads 0 (tick Transfers to count them). With kept history and a range before the
upgrade date, the yellow pre-ledger caveat line shows. Result:

**LED-P2-19. Exports.** The History CSV ends `...,wowheadLink,dir,kind,holder,from,to`; legacy rows
read `IN,ITEM,<char>,,`; the Insights CSV ends with `Ledger` sections when losses are in range.
Result:

**LED-P2-20. Perf run.** `/lh perf` opens the step panel. Complete both arms on a training dummy with
a loot-heavy pull, then `/lh perf finish` → a report whose `lootLine`, `spellCast` and `ledgerEvent`
buckets are non-zero. Record it with `/dev-copilot:wow-perf-analysis`. Result:

**LED-P2-21. Trainer and taxi.** Train a skill and take a flight → gold `OUT TRAINING` and
`OUT TRAVEL`. [`Enum.PlayerInteractionType.Trainer` and `.TaxiNode` are the member names.] Result:

**LED-P2-22. Party loot money.** In a group, loot gold that is split → "Your share of the loot is
..." is parsed and claimed. With guild perks, note whether `YOU_LOOT_MONEY_GUILD`'s first amount is the
pre- or post-cut figure (a known limitation if pre-cut). Result:

**LED-P2-23. Trade.** Trade an item and gold to another player → `OUT TRADE_GIVE` rows. [`UnitName("NPC")`
names the trade partner while the trade window is open.] Result:

**LED-P2-24. Destroy.** Delete an item from your bags → `OUT DESTROY`. [`DeleteCursorItem` is a
hookable global.] Result:

### Holder moves (timeline ledger Phase 7)

Owner decision 2026-10-06: a move between two **different** holders is a loss on the sender and a
gain on the receiver, each under the action's reason; a move inside one holder stays one `⇄` row.
History's **Character** column names the row's holder (the Warband reads **Warband**), and the
Character filter matches it. Same setup as above (Direction **All**).

**TR-1. Warband withdraw, gold and an item.** At a banker, withdraw some gold and one item stack from
the warband bank → exactly two rows for each: a `▼ Loss` on **Warband** and a `▲ Gain` on the
character, both reason **Warband Withdraw**, same quantity; no `⇄ Transfer` row. With the Character
filter on **Character: Current** only the gains show; pick **Warband** and only the losses show.
Insights → Gains Vs Losses By Reason has a **Warband Withdraw** row with both sides. Result:

**TR-2. Bags to your own bank.** Deposit an item stack from your bags into your character bank →
exactly one `⇄ Transfer` row (Bags to Bank) on the character, and no gain or loss. Result:

**TR-3. Mail an item to an alt.** Send an item to an own alt → a `▼ Loss` on the sender, reason
**Alt Mail**. Log the alt in and take the mail → a `▲ Gain` on the alt, reason **Alt Mail**; no `⇄`
row and no `UNTRACKED` row. Result:

## Timeline

The timeline ledger's Phase 3 (spec `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md`): the
daily rollup and the **Timeline** tab. Run on the live account with **Track holdings and losses** on,
`/console scriptErrors 1`, and at least two characters that have logged in since the upgrade (the
Timeline starts at the upgrade, so there is nothing to chart before it). The window opens scoped to
the logged-in character: widen the **Character** filter to **All** wherever a check needs more than
one holder. **Phase 3 is signed off only when all of TL-1 to TL-13 are recorded**, and a "no" in
TL-13 is a stop-and-fix before the release.

**TL-1. Line regions draw.** Open the Timeline on Gold with two or more characters known → lines, y
labels in gold (a `g` suffix), date labels, and no Lua error. Result:

**TL-2. Line cap.** Set **Timeline lines** (Settings > General > Interface) to 2, 8 and 16 → the line
count follows (Total plus N), richest first. With the Character filter on one alt, only that alt and
the Total draw. Result:

**TL-3. Hover.** Move across the plot → the crosshair snaps per day and the tooltip lists each
line's value and that day's Gained / Lost. Leaving the plot hides both. Hiding the window mid-hover
leaves no tooltip behind. Result:

**TL-4. Picker.** Type part of a potion's name in Search → the Search autocomplete (AC-1) offers
matching things (Gold first when "gol" is typed). Pick one → the chart switches and Search keeps the
thing's name. `/reload` → the pick is remembered. Result:

**TL-5. Ranges.** **Today** and **Last 7 days** show intraday steps after a vendor sale and a loot.
**Last 30 days**, **Last 90 days**, **Last year** and **All** show daily points. History and Insights
also offer **Last 90 days** and **Last year**. Result:

**TL-6. Partial and marker.** A character created after the upgrade draws dashed until its bank is
first opened, and solid after. The dashed `ledgerSince` rule shows when **All** is selected. Result:

**TL-7. Warband and colors.** **Warband** appears in the Character list on the Timeline and Holdings
tabs, labeled "Warband", and draws in its own blue. Characters draw in class colors (one that has not
logged in since the upgrade draws gray, which is expected). Result:

**TL-8. Filter graying.** On the Timeline, Group, Bound, Quality, Type, SubType, Source, Zone and
Export are grayed and **do not open** on click. On Holdings, Date, Direction, Source, Bound, Zone
and Export are grayed; Group stays live and offers only None, Quality, Type, SubType, Type & SubType and Character,
grouping the list under collapsible "<Prefix>: <Value> (N)" headers without changing History's own
group. History and Insights gray nothing. Result:

**TL-9. Show in Timeline.** Right-click a History row → **Show in Timeline**. Right-click a Holdings
thing → **Show in Timeline**. Both land on the Timeline charting that thing. Result:

**TL-10. Forget.** Right-click an alt's holder line on Holdings → **Forget this character** →
confirm. The alt leaves Holdings and the Timeline; its History rows remain. The option is grayed on
the logged-in character and on the Warband. Result:

**TL-11. Rollup retention.** Set **Keep Timeline days for** to 90 days and `/reload` → after about
five seconds the older days are gone (**All** starts no more than 90 days back) and every line still
starts at its carried value. Result:

**TL-12. Load.** **Last year** on Gold with 16 lines (**Timeline lines** 16, Character on **All**),
then resize the window repeatedly → no visible hitch, and the in/out strip stays aligned under the
plot. Result:

**TL-13. WoW API facts.** The assumptions the headless suite cannot prove. Record each answer
(yes, or what you saw) in the smoke log; any "no" is a stop-and-fix before the addon's release and,
for 1 to 4, a LibKa0s patch release. Result:

1. `Frame:CreateLine(name, drawLayer)` exists on a plain `Frame` and returns a `Line` region.
2. `Line:SetStartPoint(relativePoint, relativeTo, offsetX, offsetY)` and `SetEndPoint(...)` take
   that argument order, and the offsets are in the **relative frame's** coordinate space (the
   chart's `BOTTOMLEFT`), so a chart inside a scaled window draws at the window's scale.
3. `Line:SetThickness(n)` accepts a fractional thickness (1.5, 2.5), and
   `Line:SetColorTexture(r, g, b, a)` colors a Line.
4. Several hundred Lines on one frame (TL-12: 16 lines of up to about 300 segments, plus dashes)
   render without a visible hitch, and hidden pooled Lines cost nothing per frame.
5. `GetCursorPosition()` returns UI-scaled pixels that `/ frame:GetEffectiveScale() -
   frame:GetLeft()` turns into a chart-local x, and an `OnUpdate` armed on `OnEnter` and cleared on
   `OnLeave` fires only while hovered.
6. A disabled LibKa0s dropdown (a `Button`, `SetEnabled(false)`) refuses `OnClick`;
   `EditBox:SetEnabled(false)` blocks typing in the Search box; `SetAlpha(0.4)` reads as grayed
   against the flat skin.
7. `date("*t", ts)` and `time{...}` give local midnight across a daylight-saving change (EU
   2026-10-25, US 2026-11-01): Timeline day labels stay on midnight and no day repeats or vanishes.
8. `GameTooltip:AddDoubleLine` renders `GetCoinTextureString` coin markup on the right side.
9. `StaticPopup_Show(name, text1, text2, data)` hands `data` to `OnAccept(self, data)` on 12.1.
10. `RAID_CLASS_COLORS[classFile]` still carries `r, g, b` for every class, Evoker included.

**TL-14. Line toggles.** On Gold with Character on **All** and three or more lines: click a holder's
legend entry → its line goes, the entry dims in place, the y axis rescales to what is left, and the
hover tooltip no longer lists it; click again → it is back. Hover an entry → "Click to hide/show".
Hide one holder, then tick **Total only** → only the Total draws; untick → the lines from before come
back with that one holder still hidden. Hide every holder by hand → **Total only** ticks itself. Hide
the Total too → the plot says "All lines hidden — click a legend entry to show it." with no axes and no
Lua error. Change the thing and the Date range → the hidden lines stay hidden. Tick **Total only** and
`/reload` → it is still on. The in/out strip never changes with any of this. Result:

**TL-15. Strip tooltips.** On Gold over **Last 30 days**, hover a day's column in the green/red strip
under the chart (the gain bar, the loss bar and the gap between them) → a tooltip at the cursor titled
`<day> · Total` (the hover's date format, e.g. `14 Aug 2026 · Total`) with **Gained** `+<coins>` in
green, **Lost** `-<coins>` in red and **Net** signed in its sign's color (white `0` on an even day); a
side with nothing reads `0`. A day with no bars shows nothing. Move off the strip → it hides. Move from
the plot straight down onto the strip → the strip's tooltip stays up (the chart's crosshair hover
ending does not hide it), and back up onto the plot → the day tooltip takes over. Hide every line with
the legend → the strip tooltip still reads the Total. Pick a currency → counts, not coins. Result:

**TL-16. Smoother lines.** On Gold over **Last year** with Character on **All**, look at a near-flat
holder line and at the Total → the lines read as a few long segments with no stair-stepping, the
holder lines 2 px and the Total slightly heavier. Hover along a line → the crosshair still lands on
real days, and a one-day spike is still drawn. Result:

## Degraded install

Rename `Interface/AddOns/LootHistory/libs/LibKa0s` to `libs/LibKa0s.off` and `/reload` for DEGRADED-1
to DEGRADED-11; rename it back and `/reload` when done.

**DEGRADED-1. No Lua error.** Load and play → not one Lua error. Result:

**DEGRADED-2. The schema commands say why.** `/lh list`, `/lh get settings.enabled`, `/lh set
settings.rowHeight 20`, `/lh reset settings.rowHeight` and `/lh version` → each prints the one line
`[LH] The LibKa0s library is missing from this installation of Ka0s Loot History (expected in
libs/LibKa0s), so the slash command interface is unavailable.` and changes nothing. Result:

**DEGRADED-3. The notice, once.** The first line the addon prints is `[LH] The LibKa0s library is
missing from this installation of Ka0s Loot History (expected in libs/LibKa0s); running on reduced
built-in fallbacks.`; `/lh version` and `/lh get settings.enabled` do not repeat it (they print
DEGRADED-2's line). Result:

**DEGRADED-4. What is unavailable says why.** `/lh debug on` flips logging and says `…, so the debug
console window is unavailable.`; `/lh config` says `…, so the settings panel is unavailable.`, with
the notice's cause clause word for word; `/lh diagnostics` and `/lh debug diagnostics` print
`/lh diagnostics is unavailable: the LibKa0s library did not load.` and write nothing; `/lh help`
lists no `diagnostics`. Result:

**DEGRADED-5. Capture still works.** Loot, then `/lh show` → the row is there, and its Zone names
where you stand (not **Unknown**). Result:

**DEGRADED-6. The filter bar is absent, not dead.** `/lh show` → no Group by, Date, column filters,
search, Save/Reset/Clear or Export; no button that clicks to nothing. Tabs, table, footer and grip
work; the window opens on the current player. Result:

**DEGRADED-7. Export refuses.** With no Export button (DEGRADED-6), call the button's own handler:
`/run LibStub("AceAddon-3.0"):GetAddon("LootHistory").Browser:OpenExport()` twice → each prints `…,
so the export window is unavailable.`, nothing opens, and `/dump LootHistoryExportWindow` then
shows an empty result (no frame was built). Result:

**DEGRADED-8. Enable and disable.** Bare `/lh` → the help, listing `/lh enable` and `/lh disable`
but not `/lh set`; `/lh disable` → `settings.enabled = false`, recording stops, a feature verb
refuses with the disabled line; `/lh enable` → `settings.enabled = true`, recording resumes. Result:

**DEGRADED-9. `resetall` still works.** Put ids on the Filters lists with the library present, then
degraded `/lh resetall` → `settings reset to defaults.` and the lists are empty. Result:

**DEGRADED-10. `/lh profile` is unavailable.** `/lh profile` and `/lh profile Default` → `/lh profile
is unavailable: the LibKa0s library did not load.`, nothing switches, and the help does not offer
`profile`. Result:

**DEGRADED-11. The art falls back.** `/lh show` → the Bound column draws the client's lock atlas (a
plain colored square on a client with none) instead of the catalog padlock, the sorted column's
header shows Blizzard's up or down arrow instead of the shared mark, and the title-bar close is a
thin text × (gray, class-colored on hover) instead of the ✕ mark. This is the fallback working, not
a failure. Result:

**DEGRADED-12. The grip without the library.** `/lh show` → the bottom-right grip still draws the chat
hatch (two pixels inside the corner, no pressed art) and resizes, and `/reload` keeps the size; with
**Lock frame** ticked (set on a working install first, since the degraded panel cannot) it does not
resize. No Lua error. Result:

## Non-English client

Run on a client set to **deDE or frFR**, the two locales ConsumableMaster LOC-1 and KickCD LOC-1 use.
The addon prints English on every client by the accepted scope decision (`localization-§1`
deviation), so an English label on a German client is not a failure. What it **reads** in the
player's language is the tooltip bind lines (`Compat.ScanBound`), the Auction-House mail sender and
subject (`Compat.IsAuctionHouseMail`), the deconstruct spell names (`modules/Attribution.lua`), and
zone names. `core/Compat.lua`'s `WARBAND_LINES`, `BIND_TO_WARBAND_PREFIX` and `UE_LITERAL` are English
fallbacks for `ITEM_ACCOUNTBOUND*` globals the client leaves nil, and every headless case on this path
feeds enUS literals into an enUS mock (`tests/test_compat.lua`, `tests/test_attribution.lua`), so the
suite stays green whether it is right or wrong. There is no sign-off for LOC-1 to LOC-4 without a
non-English client; until one runs they stay in Pending sign-off.

**LOC-1. The six warband globals.** Before looting, run `/dump` on `ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP`,
`ITEM_ACCOUNTBOUND_UNTIL_EQUIP`, `ITEM_BIND_TO_BNETACCOUNT`, `ITEM_BIND_TO_ACCOUNT`,
`ITEM_BNETACCOUNTBOUND`, `ITEM_ACCOUNTBOUND` → record all six verbatim. Which are nil is the finding:
all set means the globals path carries the load; any nil means the English literal is live and LOC-2
tests that failure directly. Result:

**LOC-2. Bind classification.** Get a warbound and a warbound-until-equipped item, `/lh show` →
History, read **Bound** → each reads its own state. Fail: the until-equipped item reads plain
warbound (the qualifier missed), or a cell empty where enUS fills it (`ScanBound` matched no line).
Result:

**LOC-3. Auction-House mail.** Buy on the auction house, take it from the mailbox → **Source** is the
auction house. Fail: mail-from-a-player or nothing, meaning a localized `AUCTION_HOUSE` or
`AUCTION_*_MAIL_SUBJECT` global is nil or splits its `%s` differently. Result:

**LOC-4. The deconstruct name family.** Disenchant an item, mill herbs, prospect ore (plain and mass)
→ every row carries its deconstruct source. Plain casts resolve by spell id; the mass variants build
a stem from the localized name minus its last word, which a German or French name may break. Fail:
a mass mill or mass prospect row with no source or the wrong one while the plain cast is right.
Record `/dump C_Spell.GetSpellName(434926)` and `/dump C_Spell.GetSpellName(225904)`. Result:

**LOC-5. Nothing else moved.** Walk INSTALL-1 to INSTALL-4, SLASH-1 to SLASH-3, STATE-1 to STATE-4,
LAUNCH-5, CAP-1 to CAP-21, INSTALL-6, INSTALL-7, INS-20, HIST-5 to HIST-11, HIST-15 and INSTALL-8 on
this client → behavior matches English (CAP-18 and CAP-19 read the localized Currency-tab headers).
Fail: any Lua error, which here means a localized string reached code that assumed English. Result:

## Pending sign-off

The old suite recorded no result for any check, so every check carried over from it is owed unless
a record of the owner's pass exists. Five do. Review F-001 passed CAP-4 to CAP-6 (ARCHITECTURE
Known limitations). The 2026-07-22 field note in the old § 3 passed currency capture and the refund
flow (CAP-11, CAP-12). The diagnostics rollout's owner pass on 2026-09-26
(Ka0sAddonsCommonTasks `2026-09-25-DIAGNOSTICS_COMMAND/99_REPORT.md`, LH-S1 to LH-S11 and LH-X1)
passed DIAG-19, DIAG-20, DIAG-22, DIAG-24, DIAG-25 and COMBAT-8; it passed DIAG-21 too, as then
written, but standard v2.71.0 rewrote that check (diagnostics now turns logging on), so it is listed
again. The 2026-09-23 remediation plan's X1.4
(`06_SMOKE_TESTS.md`, recorded PASS on 2026-09-25 after M6: `/lh disable`, then left-click opens
Settings, right-click opens the options menu, the status tooltip shows) passed LAUNCH-3. The 2026-10-01
GitHub issue pass (Ka0sAddonsCommonTasks `2026-10-01-GITHUB_ISSUE_PASS/04_SMOKE_TESTS.md`, owner
pass on 2026-10-02) passed its two new checks, PANEL-20 and INS-22. Those fourteen checks are not
listed. The diagnostics rollout passed half of DIAG-6, half of DEGRADED-4 and two of DIAG-23's
three inputs (LH-S8 never ran `/lh dump`), and X1.4 passed part of LAUNCH-2,
LAUNCH-4 and LAUNCH-5; all six stay listed for the rest. The rest of the 2026-09-23 plan
(`06_SMOKE_TESTS.md` Session LH, Session Q and X2.4) is recorded as owed; a row names the plan step
its check carries. Checks new in this rework (SP-LH-01 to SP-LH-03R), and checks whose steps or
expectation it corrected against the code, are listed with what changed. Sign one off on its own
`Result:` line, then remove its row here.

| ID | Origin in the old suite | Owed because |
|---|---|---|
| INSTALL-1 | § 1 setup, pass 1 | No result recorded |
| INSTALL-2 | § 1 load order | No result recorded; expectation rewritten by SP-LH-03 (a second sub-page, Profiles) |
| INSTALL-3 | § 1 fresh DB | No result recorded; expectation rewritten by SP-LH-01 (schema 10, `profiles.Default`); the 2026-09-23 plan's LH.9 is owed |
| INSTALL-4 | § 1 existing account | Added with the move of settings into profiles (SP-LH-01) |
| INSTALL-5 | § 14 | No result recorded; expectation rewritten by SP-LH-01 (schema 10, the global/profile split) |
| INSTALL-6 | § 3 v3→v4 backfill | No result recorded |
| INSTALL-7 | § 3 v4→v5 backfill | "Still owed" in the 2026-07-22 field note |
| INSTALL-8 | § 5 saved view v7→v8 | No result recorded |
| SLASH-1 | § 1 bare `/lh` | No result recorded |
| SLASH-2 | § 1 help index, § 17b | No result recorded; expectation rewritten by SP-LH-02 (the `profile` row, eighteen rows) |
| SLASH-3 | § 1 and § 9 `/lh list` | No result recorded; expectation corrected by SP-LH-03R (`1.00x`, `(none)`, retention account-wide) |
| SLASH-4 | § 9 panel and CLI writes | No result recorded; step corrected by SP-LH-03R (`settings.windowScale`; the short path is not found) |
| SLASH-5 | § 9 clamp and refusal | No result recorded; steps and expectation corrected by SP-LH-03R (full path, the printed lines) |
| SLASH-6 | § 9 `reset <path>` | No result recorded; SP-LH-03R added the `(none)` echo for the source list |
| SLASH-7 | § 17f resetall | No result recorded; expectation rewritten by SP-LH-01 (`resetall` is the profile reset) |
| SLASH-8, SLASH-9 | § 17b raw keys, § 17i.1 | No result recorded |
| PANEL-1 | § 9 setup | No result recorded; expectation rewritten by SP-LH-03 (Profiles last in the tree) |
| PANEL-2 | § 17c.1-2 | No result recorded |
| PANEL-3 | § 9 strip, § 17c.3 | No result recorded; expectation corrected by SP-LH-03 (the Interface tab has no subsection headings) |
| PANEL-4, PANEL-5 | § 9 strip, § 17c.3 pairing | No result recorded |
| PANEL-6 | § 17k | "NOT YET RUN" |
| PANEL-7 to PANEL-11 | § 9 master and sliders, History tab readout, reset pair; § 10 | No result recorded |
| PANEL-12 | § 10 and § 17f reset all | No result recorded; expectation rewritten by SP-LH-01 (profile-reset wording, history untouched) |
| PANEL-13 | § 10 and § 17f purge | No result recorded |
| PANEL-14 | § 17d.1 and § 17f Defaults | No result recorded; expectation rewritten by SP-LH-01 (Defaults is the profile reset) |
| PANEL-15 to PANEL-17 | § 10, § 17c.4, § 17c.5, § 9 | No result recorded |
| PANEL-18 | § 17l | "NOT YET RUN" |
| PANEL-19 | § 17b panel labels | No result recorded; expectation rewritten by SP-LH-03R (General and Profiles; no Defaults button on Profiles) |
| PROFILE-1 to PROFILE-3 | New | New with the Profiles page (SP-LH-01) |
| PROFILE-4 | § 13 last step | Rewritten by SP-LH-01 (retention account-wide, D6) |
| PROFILE-5 | § 16 note | Rewritten by SP-LH-01 (the filter lists are per profile) |
| PROFILE-6 | New | New with the Profiles page (SP-LH-01) |
| PROFILE-7 to PROFILE-13 | New | New with `/lh profile` (SP-LH-02); PROFILE-8's step corrected by SP-LH-03R (`/lh debug on` before the switch) |
| STATE-1, STATE-2 | § 1 disable | No result recorded |
| STATE-3 | § 1 enable, § 9 master | No result recorded; expectation corrected by SP-LH-03R (enabling does not open the window; the box ends ticked) |
| STATE-4 | § 1 deferred writes | No result recorded; SP-LH-03R added the closing re-tick, so the checks after it run enabled |
| STATE-5 | § 9 master General visibility | No result recorded; expectation corrected by SP-LH-03R (the refusal line quoted; setting *Always* opens nothing until `/lh show`) |
| STATE-6 | § 9 master Lock frame | No result recorded; the 2026-09-23 plan's LH.6 is owed |
| STATE-7 to STATE-9, STATE-11 | § 8 | No result recorded |
| STATE-10 | § 8 | No result recorded; SP-LH-03R restored the old step that sets General visibility back to *Always* |
| STATE-12 | New | New with the library resize grip's `canResize` (CA-LH-01, #33, LibKa0s v1.67.0 Core 10) |
| TM-1 | New | New with the timeline ledger P6 (test mode's Holdings and Timeline sample); extended in P9 with the History row tooltips; no result recorded |
| COMBAT-1 | § 2 | No result recorded |
| COMBAT-2 | § 2, § 9 and § 17d.2 `/lh config` in combat | No result recorded; expectation corrected by SP-LH-03R (the library's printed line) |
| COMBAT-3 | § 17d.2 sidebar in combat | No result recorded; expectation rewritten by SP-LH-03 (Profiles covered too) |
| COMBAT-4 | § 17d.2 cover lifts | No result recorded |
| COMBAT-5 | § 9 master Only out of combat | No result recorded; the 2026-09-23 plan's LH.8 is owed |
| COMBAT-6 | § 8 | No result recorded |
| COMBAT-7 | § 8 | No result recorded; the 2026-09-23 plan's LH.8 is owed |
| CAP-1 to CAP-3 | § 3 matrix rows 1-3 | No result recorded |
| CAP-7, CAP-8, CAP-10 | § 3 matrix rows 7, 8, 10 | No result recorded |
| CAP-9 | § 3 matrix row 9 (review F-009) | No result recorded; open in ARCHITECTURE Known limitations |
| CAP-13 | § 3 record currency and mute | No result recorded; SP-LH-03R added the closing unmute |
| CAP-14 | § 3 keystone context | No result recorded; the 2026-09-23 plan's Q.1 is owed |
| CAP-15 | § 3 boss-corpse loot | The 2026-09-23 plan's Q.2 recorded a PASS on 2026-09-24 for the console order and the stamp's `encounterID` only: the loot was gold, so no row was written and the `sourceDetail` dump and the wipe line have no result |
| CAP-16, CAP-17 | § 3 | No result recorded |
| CAP-18 | § 3 currency category (review F-010) | "Still owed" in the 2026-07-22 field note |
| CAP-19 | § 3 S-003 | Not yet run per [midnight-quirks.md](midnight-quirks.md); the 2026-09-23 plan's Q.3 is owed |
| CAP-20 | § 3 currency quality | No result recorded |
| CAP-21 | § 3 currency bound glyph | "Still owed" in the 2026-07-22 field note |
| CAP-22 | § 4 quality gate | No result recorded; SP-LH-03R added the closing reset to Common, which CAP-23 and CAP-24 need |
| CAP-23, CAP-24 | § 4 | No result recorded |
| CAP-25 | § 17i.2 | No result recorded; expectation corrected by SP-LH-03R (the subzone is read with `/dump`) |
| CAP-26 | § 17i.3 | No result recorded |
| CAP-27 | § 17i.4 | No result recorded; expectation corrected by SP-LH-03 (the map id is read with `/dump`; the CSV does not carry it) |
| CAP-28 | § 13 retention confirm | No result recorded; the 2026-09-23 plan's LH.5 is owed |
| CAP-29, CAP-30 | § 13 retention confirm | No result recorded; the 2026-09-23 plan's LH.5 is owed; reordered by SP-LH-03R (the slash confirm is answered **No** before the **Yes** prune, and the no-op is `0`), because after the prune no record is older than 7 days and no confirm can appear |
| CAP-31 | § 13 login prune | No result recorded; given a runnable step by SP-LH-03R (a `/run` ages a record past the retention) |
| CAP-32 | § 13 | No result recorded |
| CUR-1 | New | New with the timeline ledger P7 (hidden tracking currencies never record; a same-name twin takes the row); no result recorded |
| HIST-1 to HIST-3 | § 2, § 17h.4, § 17h.5 | No result recorded |
| HIST-4 | § 2 persistence | No result recorded; step corrected by SP-LH-03R (`settings.windowScale`) |
| HIST-5 to HIST-21 | § 5, § 6, § 17g, § 17h | No result recorded |
| HIST-22 | § 17g | No result recorded; expectation corrected by SP-LH-03R (no mark on the filter bar's Export; the degraded close is a text ×) |
| HIST-23 to HIST-30 | § 6a, § 17g, § 17j.1-5 | No result recorded |
| HIST-31 | § 17j.6 and § 17j.7 | No result recorded; given a runnable route by SP-LH-03R |
| HIST-32, HIST-33 | § 17j.8, § 17h.6 | No result recorded |
| HIST-34 | New | New with the History grip on `Core.MakeResizable` (CA-LH-01, #33, LibKa0s v1.67.0 Core 10) |
| HIST-35 | New | New with the timeline ledger P4 polish (the one-line filter bar, equal Direction/Bound widths, the measured minimum width); no result recorded; the Export/cluster bullet corrected by P6 (the bar now scales) |
| FB-1 | New | New with the timeline ledger P6 (the filter bar fills the window and scales proportionally); no result recorded |
| AC-1 | New | New with the timeline ledger P9 (the Search autocomplete on every tab, LibKa0s v1.70.0 `Autocomplete`); no result recorded |
| INS-1 to INS-3 | § 7 | No result recorded |
| INS-4 | § 7 coin glyphs | No result recorded; expectation corrected by SP-LH-03R (a fixed 10 px against the client's default of about 14 px, read beside the History price cells) |
| INS-5 to INS-18 | § 7 | No result recorded |
| INS-19 | § 7 segment tooltips | No result recorded; chart names corrected by SP-LH-03R (Title Case, as drawn) |
| INS-20 | § 7 CURRENCY block, § 3 | "Still owed" (layout) in the 2026-07-22 field note |
| INS-21 | § 7 live cards | No result recorded |
| FILT-1 to FILT-23 | § 9, § 16, § 19 | No result recorded |
| FILT-24 | § 17f Clear all | No result recorded; expectation spelled out by SP-LH-03R (the popup text and the chat line) |
| FILT-25 | New | New with the Options descriptor's `addonName` (CA-LH-NM, LibKa0s#42) |
| LAUNCH-1 | § 11 art | No result recorded |
| LAUNCH-2 | § 11 tooltip | X1.4 passed the status tooltip on 2026-09-25; the re-hover after ticking **Lock frame** and **Test mode** (`Locked: Yes`, `Test mode: On`) is not in X1.4's steps and has no result |
| LAUNCH-4 | § 11 menu | X1.4 passed the menu opening on 2026-09-25; its four entries' actions have no result |
| LAUNCH-5 | § 11 disabled state; § 1 | X1.4 passed the tooltip and the menu opening while disabled on 2026-09-25; the grayed entries doing nothing and the menu's **Enabled** bringing the addon back have no result (X1.4 re-enabled with `/lh enable`) |
| LAUNCH-6, LAUNCH-7 | § 11 | No result recorded |
| LAUNCH-8 | § 11 `minimap.shown` | No result recorded; the 2026-09-23 plan's LH.2 is owed |
| LAUNCH-9, LAUNCH-10 | § 11 broker row | No result recorded |
| DIAG-1 to DIAG-5 | § 12, § 15 | No result recorded |
| DIAG-6 | § 12 counter and cap | LH-S7 passed the cap half on 2026-09-26 (`3000 / 3000 lines`, Copy); the counter ticking up and Clear's reset have no result |
| DIAG-7 | § 12 `/lh debug events` | No result recorded; the 2026-09-23 plan's LH.4 is owed |
| DIAG-8 to DIAG-13 | § 12, § 15, § 9, § 17b, § 17d.3, § 17e, § 17g | No result recorded |
| DIAG-14 | § 15 bulk-reset line | No result recorded; expectation rewritten by SP-LH-01 (`[Set] reset profile 'Default' …`) |
| DIAG-15 | § 15 data and reset-all lines | No result recorded; expectation rewritten by SP-LH-01 (no `[Data]` line on Reset all settings) |
| DIAG-16 to DIAG-18 | § 15 | No result recorded |
| DIAG-21 | § 12a, the diagnostics rollout (LH-S1 to LH-S11) | Passed on 2026-09-26 as then written; expectation rewritten by DL-LH-03 (the run turns logging on for the session: standard v2.71.0, DebugLogDiagnostics 2) |
| DIAG-23 | § 12a step 5 | LH-S8 passed `/lh diag` and `/lh debug diag` on 2026-09-26; `/lh dump` has no result |
| DIAG-26 to DIAG-29 | New | New with the resizable console and copy windows (DL-LH-01, LibKa0s v1.64.0) |
| DIAG-30 | New | New with the console's Diagnostics link (DL-LH-03, LibKa0s v1.64.0, DebugLog 16 and later) |
| DIAG-31 to DIAG-33 | New | New with the library's own debug lines (DG-LH-01, LibKa0s v1.65.0: Slash 18, Lifecycle 3, Launcher 5, DebugLogGates 1) |
| DEGRADED-1 | § 17a.1 | No result recorded |
| DEGRADED-2 | § 17a.2 | No result recorded; expectation corrected by SP-LH-03R (the schema commands print the unavailable line) |
| DEGRADED-3 | § 17a.3 | No result recorded; expectation corrected by SP-LH-03R (`/lh version` and `/lh get` print DEGRADED-2's line) |
| DEGRADED-4 | § 17a.4 | LH-X1 passed the diagnostics half on 2026-09-26; the `debug` and `config` lines have no result |
| DEGRADED-5 | § 17a.5 | No result recorded; expectation corrected by SP-LH-03R (the `/lh version` clause dropped) |
| DEGRADED-6 | § 17a.6 | No result recorded |
| DEGRADED-7 | § 17a.7 | No result recorded; given a runnable step by SP-LH-03R |
| DEGRADED-8 | § 17a.8 | No result recorded; the 2026-09-23 plan's X2.4 is owed |
| DEGRADED-9 | § 17a.9 | No result recorded; expectation rewritten by SP-LH-01 (`settings reset to defaults.`) |
| DEGRADED-10 | New | New with `/lh profile` (SP-LH-02) |
| DEGRADED-11 | § 17g ladder note | No result recorded; expectation corrected by SP-LH-03R (only what a LibKa0s-less install draws) |
| DEGRADED-12 | New | New with the `core/CoreSetup.lua` fallback grip (CA-LH-01, #33) |
| LED-1 to LED-8 | New | New with the timeline ledger, Phase 1 (the Holdings tab, the Reconciler, the v11 migration and its reset popup); no result recorded |
| LED-9 | New | New with the timeline ledger P4 polish (Holdings columns, banding, tooltips, and the open `Cou…` header-overlap check); P5 widened the stray-text check to History and to a Timeline or Insights visit, after the headless trace ruled out creation-time pane parenting (re-parenting, the Insights Attach/scroll/card chain and shared frames are not traced); the stray-text bug stays open (no fix shipped, needs the `/fstack` frame path); no result recorded |
| LED-10 | New | New with the timeline ledger P4 polish (bank and warband-tab drift on a visit's first read is `UNTRACKED`); no result recorded |
| LED-11 | New | New with the timeline ledger P5 (History Direction column: glyph plus colored label); no result recorded |
| LED-12 | New | New with the timeline ledger P5 (measured Qty width for gold, BankLedger-style Gold tooltip); no result recorded |
| LED-P2-01 to LED-P2-24 | New | New with the timeline ledger, Phase 2 (ledger capture); no result recorded, and the bracketed API facts in each are the unverified assumptions; LED-P2-02, -06 and -13 rewritten by P7 (holder moves are a loss and a gain) |
| TR-1 to TR-3 | New | New with the timeline ledger P7 (holder moves are a loss and a gain; the Character column and filter read the holder); no result recorded |
| TL-1 to TL-13 | New | New with the timeline ledger, Phase 3 (the Timeline tab and the daily rollup); no result recorded, and TL-13's API facts are the unverified assumptions |
| TL-14 | New | New with the timeline ledger P8 (Total only and the click-to-toggle legend); no result recorded |
| TL-15 | New | New with the timeline ledger P8 (tooltips on the in/out strip); no result recorded |
| LOC-1 to LOC-5 | § 18a to § 18e | "NOT YET RUN"; LOC-5's walk list rewritten by SP-LH-03R |
