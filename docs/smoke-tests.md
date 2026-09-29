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
| PANEL-1 to 19 | [Settings panel](#settings-panel) | Landing page, the General strip, Master controls, reset and purge dialogs, panel chrome, AH Price |
| PROFILE-1 to 13 | [Profiles](#profiles) | The Profiles page, what a profile holds, `/lh profile` |
| STATE-1 to 11 | [Enabled state, lock and test mode](#enabled-state-lock-and-test-mode) | Enable/disable, General visibility, Lock frame, test mode |
| COMBAT-1 to 8 | [Combat](#combat) | The window in combat, the settings combat lock, combat-driven refusals |
| CAP-1 to 32 | [Capture, attribution and retention](#capture-attribution-and-retention) | The source matrix, context lifetimes, currency, the gates, zone stamps, retention prune |
| HIST-1 to 33 | [History window](#history-window) | Window, table, dropdowns, saved view, character scope, row actions, marks, export |
| INS-1 to 21 | [Insights](#insights) | Filter scope, KPI cards, chart order, colors, legends, tooltips, the currency block |
| FILT-1 to 23 | [Filter lists](#filter-lists) | Blacklist, whitelist and currency lists: gate, add box, suggestions, grid, refresh |
| LAUNCH-1 to 10 | [Launcher](#launcher) | Minimap button and broker row: art, tooltip, clicks, menu, visibility |
| DIAG-1 to 25 | [Debug console and diagnostics](#debug-console-and-diagnostics) | Console window and logging, tag coverage, the diagnostics report |
| DEGRADED-1 to 11 | [Degraded install](#degraded-install) | LibKa0s missing from the install |
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
- Have ready: two or more characters with recorded loot on the account, a target dummy, a vendor, a
  mailbox, bag space, and (for CAP) a quest with an item reward and a trade partner if you can.
- `/lh test` seeds a synthetic history for HIST and INS checks that do not need live loot.
- On failure, capture the BugSack line and the exact slash sequence, and file an issue at the
  tracker linked from [README.md](../README.md).

**Which themes to run.**

- Capture or attribution (`modules/Collector.lua`, `modules/Attribution.lua`, `core/Compat.lua`,
  `core/EnvSetup.lua`): INSTALL, CAP; any change that moves `core/Compat.lua` also needs LOC.
- Browser, table, Insights or export (`modules/Browser.lua`, `BrowserTable.lua`, `Analytics.lua`,
  `Export.lua`): HIST, INS, STATE-7 to STATE-11.
- Settings or schema: PANEL, SLASH, PROFILE, plus CAP-22 to CAP-24 for a new capture row.
- Filter lists (`modules/Filters.lua`, the Filters tab): FILT, CAP-22 to CAP-24.
- Media or art (`core/MediaSetup.lua`, an `NS.Icon` call site, `libs/LibKa0s/media/`): HIST-5,
  HIST-6, HIST-13, HIST-15, HIST-17, HIST-22, HIST-23, PANEL-18, DIAG-10 and DIAG-11.
- Dropdowns or the filter bar (`core/WidgetsSetup.lua`, `B:BuildFilterBar`, `libs/LibKa0s/Widgets.lua`):
  HIST-2, HIST-3 and HIST-12 to HIST-21 (HIST-12 always: the first click is where this widget broke).
- LibKa0s re-vendor or `core/*Setup.lua` / `settings/Slash.lua` / `settings/OptionsSetup.lua`:
  DEGRADED (always), PANEL (PANEL-6 after every re-vendor), SLASH, DIAG, HIST-12 to HIST-17 and
  HIST-28 to HIST-33.
- Diagnostics or debug logging: DIAG, DEGRADED-4.
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
version, get, set, list, reset, resetall, profile, debug, diagnostics, test, purge, help (eighteen).
Each row is a gold `/lh <verb>`, an em dash and a white description; every line carries `[LH]`; no
raw key such as `HELP_HEADER` shows; the window does not open. Result:

**SLASH-3. `/lh list`.** On a fresh profile, `/lh list` → rows grouped under `[Master controls]`,
`[Capture]`, `[AH Price]`, `[Interface]`, `[History]` in strip order (a `[Collection]` or
`[Maintenance]` header is a missed rename), every schema row present, with the defaults
`settings.enabled = true`, `settings.qualityThreshold = 1`, `settings.retentionDays = 30`,
`settings.windowScale = 1`, `settings.excludeQuestItems = true`, `settings.excludedSources` empty and
`minimap.shown = true` (the row reads SHOWN; the stored key underneath is `minimap.hide = false`).
Result:

**SLASH-4. Panel and CLI write one value.** With the panel open on the right tab, `/lh set
windowScale 1.5` → the Window scale slider moves; drag the slider → `/lh get settings.windowScale`
echoes it. Change **Minimum quality**, **Record data from**, **Exclude quest items** (Capture),
**Keep history for** (History) and **Minimap button** (Master controls) → `/lh get` on each path
echoes the new value, and an open widget follows a slash write live. Result:

**SLASH-5. `set` refuses bad input.** `/lh set windowScale 9` → clamps to 1.6 (bounds 0.6 to 1.6);
`/lh set windowScale abc` → prints "expected a number" and writes nothing; `/lh set settings.enabled
maybe` → refused, nothing written. Result:

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

**PANEL-15. Scrollbar always shown.** Click between the landing page, General tabs and Profiles → the
right-edge scrollbar is always there: parked, grayed and inert on a short page, live on a long one,
and the body's right edge does not shift between pages. Result:

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

**PANEL-19. Panel labels are English.** On General (every tab) and Profiles → the Defaults button
reads **Defaults** and every checkbox, dropdown and slider label is English, with no all-caps
underscored key. Result:

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

**PROFILE-4. Retention is account-wide.** Set **Keep history for** to 90, create a profile and switch
to it, then copy into it and reset it → the new profile shows 90; none of the three raises the
retention confirm or deletes a record; hovering **Keep history for** says the setting is
account-wide. Result:

**PROFILE-5. Filter lists are per profile.** Add an id to the Blacklist on `Default`, switch to a new
profile → its lists are empty; switch back → the id is there, and survives `/reload`. Result:

**PROFILE-6. Enabled is per profile.** Create `Off`, switch to it and untick **Enable Loot History**,
then switch to `Default` → the addon comes back up (loot records again); switch to `Off` → it stands
down as with `/lh disable`. Result:

**PROFILE-7. `/lh profile` lists.** With profiles `Default`, `alt` and `Main` → `/lh profile` prints a
`Profiles` header (no trailing colon), then `alt`, `Default` (current), `Main` sorted ignoring case,
the current one suffixed `(current)`, then `/lh profile <name> switches profile`. Result:

**PROFILE-8. `/lh profile <name>` switches.** `/lh profile Main` → `Switched to profile 'Main'.`, the
settings adopt as in PROFILE-2, an open panel refreshes, and with debug on the console shows one
`[Profile] switched to profile 'Main'` line; open Profiles → the picker reads Main. `/lh profile
Main` again → `Already on profile 'Main'.` and nothing changes. Result:

**PROFILE-9. An unknown name is refused.** `/lh profile main` → `No profile named 'main'.`, then `Did
you mean 'Main'?`, then the list; `/lh profile Nope` → the refusal and the list, no did-you-mean.
Open Profiles → no `main` or `Nope` profile was created. Result:

**PROFILE-10. Quotes and spaces.** Create `My Alt` on the page. `/lh profile "My Alt"` → switches to
`My Alt`; `/lh profile 'Default'` → switches to Default; `/lh profile My Alt` → switches too (inner
spaces kept). Result:

**PROFILE-11. Answers while disabled.** `/lh disable`, then `/lh profile` → the list prints (no
disabled refusal); `/lh profile Main` on a profile where the addon is enabled → switches and the addon
comes back up. Result:

**PROFILE-12. Refused in combat.** Attack a target dummy; in combat `/lh profile Main` → `Can't switch
profiles in combat.` and nothing switches; `/lh profile` and `/lh profile Nope` still answer. Out of
combat the same switch works. Result:

**PROFILE-13. The page follows a slash switch.** With the Profiles page open, close Settings, `/lh
profile Main`, reopen Profiles → the picker reads Main. Result:

## Enabled state, lock and test mode

**STATE-1. Disabled is total.** `/lh disable` → prints `settings.enabled = false`; the History window
closes and will not reopen; loot you take is not recorded; `/lh show` answers `Ka0s Loot History is
disabled — enable it with /lh enable` and does nothing else. Result:

**STATE-2. The command surface while disabled.** Still disabled: bare `/lh` opens the panel, `/lh
version` prints, `/lh list` and `/lh get settings.qualityThreshold` read, `/lh set settings.scale
1.1` writes, `/lh debug` opens the console, `/lh diagnostics` writes its report → all answer; only
`show`, `hide`, `toggle`, `test` and `purge` refuse with the disabled line. Result:

**STATE-3. One switch, three surfaces.** `/lh enable` → prints `settings.enabled = true`, loot records
again and the window opens. Tick and untick **Master controls ▸ Enable Loot History** → `/lh get
settings.enabled` follows, and unticking takes the window down as the verb does. Result:

**STATE-4. Disabled right after login writes nothing.** `/reload` and, within five seconds of the
loading screen clearing, untick **Enable Loot History** → nothing is written: the deferred
retention prune and bound-state repair do not run on the disabled addon, so records older than the
retention are still there. Result:

**STATE-5. General visibility Never.** Set **General visibility** to *Never*, `/lh show` → refused
with a chat line; set *Always* → the window opens. Result:

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
mode** → one `test mode not started — …` line, no window, the box stays unticked. Result:

**STATE-11. Test mode never outlives a reset or reload.** Tick **Test mode**, then **Reset all
settings** and confirm → test mode off, box unticked. Tick it again, `/reload` → off. Result:

## Combat

**COMBAT-1. The window works in combat.** With the window open, attack a dummy; click a row, drag and
resize the window → no "Interface action failed because of an AddOn" error; it stays usable.
Result:

**COMBAT-2. `/lh config` in combat.** In combat, `/lh config` → one gray "can't open in combat" line,
nothing opens. Leave combat → `/lh config` opens the panel, and the panel does not open on its own
when combat drops. Result:

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
tick it and mute that currency's source → still no row. Result:

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
needed. Result:

**CAP-23. Quest-item gate.** With **Exclude quest items** ticked, loot a quest objective drop →
dropped (`reason=quest`, keyed on item class 12); untick it and loot another → recorded. Result:

**CAP-24. Source mute.** In **Record data from**, untick **Kill**, kill and loot a mob → dropped
(`reason=source`); tick it again → captured. The list offers every source: Kill, Container, Mythic+,
Bonus Roll, Roll, Quest, Trade, Mail, Auction House, Vendor, Disenchant, Milling, Prospecting, Craft,
Refund, Other. Result:

**CAP-25. Zone and subzone stamps.** Loot in a zone with a subzone (a capital district, an inn) → the
Zone column reads the zone and the row's tooltip carries the subzone; loot in a zone with no
subzone → the Zone column is filled and nothing is blank-labeled. Result:

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

**CAP-29. Yes prunes.** Change to 7 again and answer **Yes** → records older than 7 days go (no holes),
the table and footer refresh. Result:

**CAP-30. The slash path asks too.** `/lh set settings.retentionDays 7` with older records → the same
confirm; a value that would delete nothing asks nothing. Result:

**CAP-31. Login prune.** With records older than the retention, `/reload` and wait about five seconds
→ the stale records are pruned without touching the setting; no Lua error. Result:

**CAP-32. Always keeps everything.** Set **Keep history for** to *Always*, `/reload` → nothing is
pruned. Result:

## History window

**HIST-1. Toggle, show and hide.** `/lh toggle` twice, then `/lh show`, `/lh hide` → toggle flips,
show and hide are explicit; the window opens on History, and the last tab used is remembered within
the session. Result:

**HIST-2. Esc closes the window and its menu.** Open **Character**, leave its menu open, press Esc
→ the menu and the window both close; no menu is left floating. Result:

**HIST-3. `/lh hide` closes an open menu.** Open **Zone**, leave it open, `/lh hide` → menu and window
both gone. Result:

**HIST-4. Position, size and scale persist.** Drag the title bar, drag the bottom-right grip, `/lh
set windowScale 1.3`, `/reload`, `/lh show` → same position, same size (never below the width that
fits every column), 1.3× scale. Result:

**HIST-5. Sort.** Click each header (Date, Time, iLvl, Item, Qty, Quality, Type, SubType, Source, Zone,
Vendor, Character), twice each → each direction renders; the active header shows one shared up or
down arrow, not Blizzard's spinner arrow. Result:

**HIST-6. Group by.** Cycle **Group by** through None, Day, Quality, Type, Source, Zone, Character;
collapse and expand a header → each renders in column order; headers show a chevron right when
collapsed and a chevron down when expanded, not `+` / `-`. Result:

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

**HIST-15. Row actions.** Right-click a row → **Link to chat**, **Blacklist item** (or **Blacklist
currency**), and **Delete**, each with its mark and every word kept; Link to chat is disabled without
an item link and Blacklist item without an item id. Link to chat and Shift-click both put the link in
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
modal and copy window wear the same; **Export** carries a small left mark with its word still
centered, **Export to CSV** a spreadsheet mark; **Clear**, **Reset** and **Save** carry no mark. Fail:
a blank space where a mark belongs (a path with `.tga`, or a name the catalog lacks); Blizzard art in
its place means the library is missing (DEGRADED-11). Result:

**HIST-23. Bound padlock and the resize grip.** The Bound column draws a padlock, and its header
legend uses the same padlock tinted per state; the bottom-right grip is Blizzard's ChatFrame
three-line hatch, as on the rest of the collection. Result:

**HIST-24. Export is tab-aware.** On History, click **Export** (right of filter row 2) → the modal reads
**Export History**; on Insights → **Export Insights**. Result:

**HIST-25. History CSV.** Export **All Data** → the header `ts,date,time,char,classFile,itemID,currencyID,itemName,quality,qualityRaw,itemLevel,bound,vendorPrice,vendorPriceRaw,auctionPrice,auctionPriceRaw,value,valueRaw,auctionSource,itemType,itemSubType,quantity,source,zone,auc_auctionator_minbuyout,auc_tsm_dbmarket,auc_tsm_dbminbuyout,auc_tsm_dbregionmarketavg,auc_tsm_dbregionminbuyoutavg,auc_tsm_dbhistorical,auc_tsm_dbrecent,auc_tsm_dbregionhistorical,auc_tsm_dbregionsaleavg,auc_oribos_market,auc_oribos_region,wowheadLink`
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
Collected, Currency by Type x Source, Currency by Character x Type, Currency by Day. Loot sections are
items-only; no By Keystone, Attribution Confidence, Currency by Source, flat Currency by Character or
currency Summary rows. Result:

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
copy window centers on it; close the History window and export by another route → it centers on the
screen, with no error. Result:

**HIST-32. Copy window chrome.** Drag the copy window by its title bar, close it with its title-bar ✕
→ it moves, and the close mark matches every other window in the addon. Result:

**HIST-33. The export modal closes its menu.** Open **Data set** in the modal, click the modal's ×
→ the menu goes; reopen, open the menu, press Esc → the menu goes. Result:

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

**INS-4. Coin glyphs.** Money strings (value card, richest drop, Value By Source) use coin icons about
25% smaller than the text's line. Result:

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

**INS-19. Segment tooltips.** Hover one segment of any stacked bar (Character × Source, Currency by
Type × Source, Currency by Character × Type) → "<category>: <value>" (e.g. "Kill: 45"). Result:

**INS-20. The CURRENCY block.** With currency in range → the CURRENCY divider under LOOT, then
Currency Collected (one colored bar per currency, with a legend), Currency by Type × Source (stacked
by source, source legend), Currency by Character × Type (one stacked bar per character, a distinct
color per currency, legend), Currency over time; no "Currency — N types" summary, no Currency by
Source chart, no flat Currency by character. Narrow to a range with no currency → the whole block,
divider included, disappears and LOOT still renders. Result:

**INS-21. Live update.** Loot an item with Insights open → the cards update. Result:

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
the menu) → Show window acts as `/lh toggle` (General visibility refuses it the same way); Test mode
runs `/lh test`; Locked flips **Lock frame**; Enabled runs `/lh disable` and prints `settings.enabled
= false`. Result:

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
state.debugConsole` reports the window). Open the console with `/lh debug`, then close it with Esc
or its ✕ → the checkbox unticks. `/reload` → unticked. Result:

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

**DIAG-21. Ungated by logging.** `/lh debug off`, `/lh diagnostics`, then loot → the full report
lands; the header still reads **Debug: OFF** and the loot writes no trace. Result:

**DIAG-22. Every form.** `/lh debug diagnostics`, `/loothistory diagnostics`, `/loothistory debug
diagnostics` → each writes the same report. Result:

**DIAG-23. No short aliases.** `/lh diag` and `/lh dump` → `unknown command` and the help index; `/lh
debug diag` → toggles the console like any unknown word. Result:

**DIAG-24. While disabled.** `/lh disable`, then `/lh diagnostics` and `/lh debug diagnostics` → full
reports reading `identity: enabled=false stoodDown=true testMode=false` and `capture: stood down
(the loot, currency and context events are unregistered)`; nothing comes back on. `/lh enable`.
Result:

**DIAG-25. The README steps.** `/reload` with the console closed, then follow the README's `##
Reporting a bug` steps word for word → each works, and the paste holds the trace and the whole
report. Result:

## Degraded install

Rename `Interface/AddOns/LootHistory/libs/LibKa0s` to `libs/LibKa0s.off` and `/reload` for DEGRADED-1
to DEGRADED-11; rename it back and `/reload` when done.

**DEGRADED-1. No Lua error.** Load and play → not one Lua error. Result:

**DEGRADED-2. `/lh list` is complete.** `/lh list` → every schema row, grouped, as with the library.
Result:

**DEGRADED-3. The notice, once.** The first line the addon prints is `[LH] The LibKa0s library is
missing from this installation of Ka0s Loot History (expected in libs/LibKa0s); running on reduced
built-in fallbacks.`; `/lh version` and `/lh get settings.enabled` do not repeat it. Result:

**DEGRADED-4. What is unavailable says why.** `/lh debug on` flips logging and says `…, so the debug
console window is unavailable.`; `/lh config` says `…, so the settings panel is unavailable.`, with
the notice's cause clause word for word; `/lh diagnostics` and `/lh debug diagnostics` print
`/lh diagnostics is unavailable: the LibKa0s library did not load.` and write nothing; `/lh help`
lists no `diagnostics`. Result:

**DEGRADED-5. Capture still works.** Loot → it records, its Zone names where you stand (not
**Unknown**), and `/lh version` prints the TOC version. Result:

**DEGRADED-6. The filter bar is absent, not dead.** `/lh show` → no Group by, Date, column filters,
search, Save/Reset/Clear or Export; no button that clicks to nothing. Tabs, table, footer and grip
work; the window opens on the current player. Result:

**DEGRADED-7. Export refuses.** Any route to the export window → `…, so the export window is
unavailable.` and nothing opens. Result:

**DEGRADED-8. Enable and disable.** Bare `/lh` → the help, listing `/lh enable` and `/lh disable`
but not `/lh set`; `/lh disable` → `settings.enabled = false`, recording stops, a feature verb
refuses with the disabled line; `/lh enable` → `settings.enabled = true`, recording resumes. Result:

**DEGRADED-9. `resetall` still works.** Put ids on the Filters lists with the library present, then
degraded `/lh resetall` → `settings reset to defaults.` and the lists are empty. Result:

**DEGRADED-10. `/lh profile` is unavailable.** `/lh profile` and `/lh profile Default` → `/lh profile
is unavailable: the LibKa0s library did not load.`, nothing switches, and the help does not offer
`profile`. Result:

**DEGRADED-11. The art falls back.** Open the window → Blizzard art (down-arrow, `+`/`-`, the client
lock atlas, the tick) where the catalog marks were, and the console in a proportional font. This is
the fallback working, not a failure. Result:

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

**LOC-5. Nothing else moved.** Walk INSTALL-1, CAP-1 to CAP-12 and HIST-5 to HIST-11 on this client →
behavior matches English. Fail: any Lua error, which here means a localized string reached code that
assumed English. Result:

## Pending sign-off

Owner checks with no recorded pass. Origin is the old suite's section, or the change that added them.

| ID | Origin |
|---|---|
| INSTALL-4 | Old §1 (existing-account upgrade), added with the move of settings into profiles |
| INSTALL-7 | Old §3 v4→v5 backfill, "still owed" in the 2026-07-22 field note |
| CAP-9 | Old §3 matrix row 9 (review F-009), open in ARCHITECTURE Known limitations |
| CAP-18 | Old §3 currency category (review F-010), "still owed" in the 2026-07-22 field note |
| CAP-19 | Old §3 S-003; [midnight-quirks.md](midnight-quirks.md) records it not yet run |
| CAP-21 | Old §3 currency bound glyph, "still owed" in the 2026-07-22 field note |
| INS-20 | Old §7 CURRENCY block, "still owed" (layout) in the 2026-07-22 field note |
| PANEL-6 | Old §17k, "NOT YET RUN" |
| PANEL-18 | Old §17l, "NOT YET RUN" |
| PROFILE-1 to PROFILE-13 | New with the Profiles page and `/lh profile`; PROFILE-4 is old §13's last step, PROFILE-5 old §16's per-profile note |
| DEGRADED-10 | New with `/lh profile` |
| LOC-1 to LOC-5 | Old §18a to §18e, "NOT YET RUN" |
