# M4 design: farm mode (#39)

Plan: `docs/superpowers/plans/2026-11-27-tooltip-toasts-farm.md` (decisions D15-D23, rows M4.1-M4.6).
Mockups: `docs/superpowers/specs/2026-11-27-tooltip-toasts-farm-mockups.html` (the `#39` section,
lines ~470-690). Builds on M1 (`2026-11-27-34-tooltip-holdings-design.md`), M2
(`2026-11-27-rep-appearance-capture-design.md`) and M3 (the pre-gate gain feed, M3.1). Branch
`feat/2026-11-27-39-farm-mode`, based on M3.

Line citations were refreshed on 2026-11-28 against the tree at `edd81d0` (M3 committed below this
branch). See "Aligned to M3" under the Owner rulings for what moved.

---


> **Owner rulings, 2026-11-27 (supersede the spec text they touch).**
> - **D-1 → add a persistent-window tier (plan D26).** The farm panel goes on a new MEDIUM layers key for
>   persistent windows in `NS.Constants.LAYERS`, per frame-layering-§1. If the standard names no key for that
>   tier, the key is added upstream in WowAddonStandards first (task M4.0), then used here. No deviation row.
> - **D-2 → widen the existing localization-§4 register row (plan D27)** to cover Gathering and the shipped
>   Fishing name match alongside deconstruct, same reasoning and re-check trigger.
> - **D-1 resolved upstream (M4.0 done):** WowAddonStandards v2.122.0 gives T4 two keys, `WINDOW_PERSISTENT`
>   (`MEDIUM`, a window kept up while playing) and `WINDOW` (`HIGH`, opened to read). M4.2 adds
>   `WINDOW_PERSISTENT = "MEDIUM"` to `C.LAYERS.STRATA` and builds the companion panel on it; the Details,
>   Summary and sessions-list windows stay on `WINDOW`. `tests/test_layers.lua` pins both. The key exists
>   from standard v2.122.0 (the standards reference here is unversioned, so nothing else moves). Every "builds the panel at `WINDOW` (`HIGH`)" line
>   below is superseded by this.
> - **D-3:** the launcher column edit to `standards/ADDONS.md` is done in WowAddonStandards in task M4.0.
> - **D-4:** cite the Forever interface source for the logout-hook routing before M4 merges (M4.1).
>   M4.1a (2026-11-28): no Forever interface source is available locally, so it is recorded as a
>   per-client fallback (§12.1) and smoke row FOREVER-22 rather than a citation (§5.4, §14).
> - F1 (GATHERING source), F2, F5, F6 rulings stand.
> - Chat-line hiding is out of scope (D25); nothing in farm mode depends on it.

> **Aligned to M3 (2026-11-28, task M4.0b; no owner decision changed).**
> - §2: the hypothetical `GainFeed:SetConsumer(name, on)` is gone. M3 shipped `GainFeed:SetFarm(kinds)`
>   (`modules/GainFeed.lua:186-190`), so Farm passes `C.FARM.GAIN_KINDS` or nil. The payload field list
>   is now the real `GainFeed.FIELDS` (`:24-29`). Nothing has to be added at the sender. The stand-down
>   order is now spelled out: `GainFeed:Disable` drops the farm set, and `Farm:Enable` sets it again.
> - §3.2/§3.3/§9: the Farm schema follows the shipped Toasts precedent. `settings/SchemaFarm.lua` loads
>   above `settings/Schema.lua`, which appends `NS.SchemaFarm.Rows()` next to its Toasts loop
>   (`settings/Schema.lua:666-668`). It does not load below Schema through `SchemaRuntime.AddRows`.
>   `settings/PanelFarm.lua` goes after `settings/PanelToasts.lua`.
> - §9.4: M3.6 already made `tests/test_panel.lua`'s subcategory set multi-page (`General | Toasts`)
>   and added the Toasts bullet to `docs/settings-panel.md`. `/lh list`'s `groupKey`
>   (`settings/Slash.lua:485`) is still page-blind, and it now matters: Toasts and Farm both have a
>   `General` tab. M4.5 keeps that fix and the stale "one subcategory" doc lines.
> - §7/§11.3: the panel is built on `C.LAYERS.STRATA.WINDOW_PERSISTENT` (`MEDIUM`). The Details,
>   Summary and sessions-list windows stay on `WINDOW` (`HIGH`). The old D-1 text in §14 is kept only
>   as history.
> - §10: the icons come from the vendored `v1.119.0 (unreleased, branch feat/2026-11-27-feed)` source
>   through an archive extract and that extract's `tools/prune-icons.lua`, not from `v1.118.0`.
> - §11.2: `farmGain` declares `within = "gainSend"` and passes it, because it runs only inside a
>   send. `gainSend` itself declares no `within` (the M3 precedent). `farmWindow` is top-level.
> - §13: the feed suite is `tests/test_gain_feed.lua`. `test_layers` pins the new key.
> - §17: M4.1 is split into M4.1a (pure model and contracts) and M4.1b (runtime).
> - Stale line citations are refreshed throughout.

> **Built in M4.1b (2026-11-28; small calls inside the spec, no owner decision changed).**
> - §5.4 Finish: the last price fill runs **before** `FarmModel.Close`, so the totals snapshot includes
>   the late prices (the order above filled them after the snapshot, which the snapshot would miss).
> - §5.1 `Farm:Active()` reads without creating the character's entry; only the writers (`Mine`) create
>   it, so a read on the saved store (Reconcile, diagnostics, a sim stop) never changes saved data.
> - §5.2 idle: `FarmModel.IdleAt` measures from the later of `lastGainAt` and `runningSince`. Measured
>   from `lastGainAt` alone, a gain from before an idle pause made the next tick after a resume pause
>   again at once, with zero seconds banked.
> - §5.4/§12.2 `PLAYER_LOGOUT` does nothing while a simulation holds `SimStores.farm`: during a sim the
>   live session is never written, and the next load closes or resumes it through restore rule 2.
> - §8 the minimal verb: bare `/lh farm` prints the session's status until M4.2 makes it toggle the
>   panel. The keep-cap confirm stays with M4.5; M4.1b ships `Farm:CountOverCap` and `OnKeepChanged`.

> **Built in M4.2 (2026-11-28; small calls inside the spec, no owner decision changed).**
> - §7.1 minimized: the mockup (owner-reviewed) draws rows 1-2, `<elapsed> elapsed` and the footer, so
>   the minimized panel is sized to that content. The "band height minus twice its inset" line (a
>   title-only collapse, the Drop Watcher precedent) contradicts the mockup and is not used.
> - §7.1 footer: `Details` and `Sessions` are drawn only once their windows exist
>   (`NS.FarmDetails`, M4.3; `FarmPanel:ToggleSessions`, M4.4), so no button is ever dead.
> - §7.1 mode badge: only the simulation's. Test mode never reaches the panel (§12.3), so it has no
>   test strip and no test badge.
> - §6 activity lines live in `modules/FarmModel.lua` (`M.ACTIVITY`, `ActivityValue`,
>   `ActivityLines`), pure, so the summary and the Details Activity tab (M4.3) reuse one definition.
> - §3.3 `modules/FarmList.lua` is CONVENTIONAL in the TOC until a window binds it at load (the
>   panel does not use it); its cases are in `tests/test_farm_panel.lua`.
> - §7.1 lock and strip: `modules/Browser.lua` publishes `B.LockExtra`, `B:PaintMark`,
>   `B:PaintLockMarkOn`, `B.MakeSimStrip` and `B.SIM_MARK`, so the panel shares one lock path and
>   one sim strip with the History window. `B:OnSettingsChanged` calls `FarmPanel:OnChromeChanged`
>   (chrome, lock mark, visibility); `B:AdoptProfile` calls `FarmPanel:AdoptProfile` before its own
>   early return. The sim listener in `modules/SimPanel.lua` also calls `FarmPanel:UpdateStrip`.
> - §7.1 buttons call the Farm verbs directly (`Farm:PauseVerb` ...); `runVerb(verb, rest)` is M4.5's.
> - F9: a show the visibility setting refuses also marks the panel to come back on the next
>   allowing edge (it prints `the farm panel is hidden by the General visibility setting.`).
> - §7.1 double-click: a Frame has no `OnDoubleClick`, so two title-bar presses within 0.35 s are one.
> - §10: `minimise` is the catalog's file name; `tests/prose_waivers.lua` waives the British spelling
>   per file (CLAUDE.md, the panel, its suite, `tests/test_mediasetup.lua`).
> - §13 `test_layers`: the panel case is added; the sessions list, Details and Summary cases come with
>   those frames (M4.3, M4.4).

> **Built in M4.3 (2026-11-28; small calls inside the spec, no owner decision changed).**
> - §7.3 footer none: the Costs ledger-off note and the Log's `Showing the most recent 2,000 lines.`
>   are one note line under the list, and the resize grip sits on the window's own corner.
> - §7.3 Costs and Activity are fixed-order lists, not header-sortable: the copper costs largest
>   first, then the currency spent; the enabled lines in §6 order (zero lines included, so
>   `hideZero` is the panel's and the summary's only), then the quality, faction, skill and currency
>   breakdowns, each a heading and its indented lines. `Open(ref)` keeps the selected tab.
> - §7.3 a Details window on the open session follows it into the saved list when it finishes (the
>   title becomes `Session details: <name>`); either window closes when its session is gone
>   (discarded, deleted, a released simulation store). A saved session's window repaints only on
>   `finish`, `rename`, `delete` and `store`, not on gain traffic.
> - §7.4 top earners draw `x<qty>` only past one, as the mockup does (`Stormcharged Bracers`). The
>   ranked lists (top earners, by source, the costs parenthesis) read whole gold, rounded; the
>   percents are largest-remainder, so they sum to 100 (the mockup's 49 / 46 / 5). Under the money
>   measure, which values no item, the ranked lists value items at AH. The meta line names the
>   character without its realm. The summary opens centered and keeps no position.
> - §7.4 only the manual Finish (`Farm:FinishVerb`: the verb, the panel's button, the key binding
>   from M4.5) opens the summary; a logout or stale finish does not.
> - §7 visibility: both windows only ever hide at a visibility edge or a settings change (the
>   History window's rule; F9's re-show is the panel's). `B:OnSettingsChanged`, both combat edges
>   and `B:AdoptProfile` fan out to `NS.FarmDetails`. A refused show prints
>   `the farm windows are hidden by the General visibility setting.`
> - §7 strips: `modules/Browser.lua` publishes `B.MakeTestModeStrip` beside `B.MakeSimStrip`, so a
>   test-mode sample session (M4.4) shows the History window's amber band.

> **Built in M4.4 (2026-11-28; small calls inside the spec, no owner decision changed).**
> - §5.9 a session id is unique only within its character, and the Farm tab lists every character,
>   so `FarmModel.BestPerZone`'s id set would star every session sharing a best one's id.
>   `FT.MarkBest` hands the model one proxy per listed entry, its id the entry's index; the model's
>   API is unchanged.
> - §7.5 `charOptions(mode)` takes `nil`, `"holders"` or `"farm"` (the old boolean is gone; its test
>   callers pass the word), `zoneOptions(mode)` `nil` or `"farm"`, from `Farm:Characters()` and
>   `Farm:Zones()`. `B:RefreshFilterOptions` prunes the Character picks on a source change
>   (`_charMode`). The tab repaints, options included, on `finish`, `rename`, `delete` and `store`
>   and on `SETTINGS_CHANGED`, never on gain traffic: it lists saved sessions only. Its measure is
>   nil until cycled (the headline value setting), saved as `farmMeasure` beside `sortKey` and
>   `sortAsc`.
> - §7.2 the sessions list is titled `Farm sessions`, its title-bar drag moves the panel it docks
>   to, it is parented to `UIParent` (so the master scale applies once) and it shows only while the
>   panel does. Its `/h` column and the tab's `Gross/h` are one column spec. A row's hover names the
>   session and says what a click does, which is what the tooltip group places outside the pair.
>   In test mode it reads the sample like the tab, so it lists this character's sample sessions,
>   which is none: the sample's characters are the History sample's.
> - §7.6 the row half (columns, click routes, the menu and both popups) is `modules/FarmTab.lua`'s;
>   the sessions list reads it at call time. The menu's items stay enabled on a test row and the ask
>   refuses with the line (the spec's refusal), as `Farm:Rename` / `Farm:Delete` do. A name is
>   `FarmModel.SessionName`: trimmed, a `|` made `/`, cut to `NAME_MAX` (48) bytes on a character
>   boundary, empty giving the zone. The popups' buttons are `Rename` / `Cancel` and `Yes` / `No`.
> - §12.3 the sample's characters are `TestSample.charKey` over the History sample's four classes,
>   so the mockup's hunter row is the warrior's. The zone names are the spec's on both clients.
>   `TD.Publish` also sends `FARM_CHANGED("store")`, so the lists repaint and a window on a sample
>   session closes when test mode ends.

> **Built in M4.5 (2026-11-28; small calls inside the spec, no owner decision changed).**
> - §9.2 the trim confirm's buttons are `Delete` and `Cancel`, not `Delete…`: the popup's own button
>   opens nothing further, and options-ui-§21 keeps the ellipsis for a control that opens a dialog.
>   The confirm lives in `settings/SchemaFarm.lua` (`SF.OnKeepChanged`, `SF.ConfirmKeep`, popup
>   `KA0S_LOOTHISTORY_FARM_TRIM`), beside its row, as FarmTab keeps its own popups; `settings/Schema.lua`
>   gains only the `RESET_EXEMPT` entry. The last confirmed cap is seeded by the row's own `set` from the
>   value it overwrites, so no init hook is owed. `0` reads `all` in the Cancel line.
> - §9.2 rows: `showPanelOnStart`, `hideZero` and the twelve unnamed activity rows get tooltips of
>   their own (the spec gives two). The General tab follows the §9.2 table order (Show the panel before
>   Sessions kept), not the mockup's. `idleMinutes` and `pauseOnAFK` reach the session through the new
>   `Farm:OnSettingChanged(leaf, v)`, called by every Farm row before its `SETTINGS_CHANGED "farm"`.
> - §4.6 the storage readout's farm line is `Farm sessions: N (~X)`: `~`, not `≈` (ruling D-19, two
>   skin faces cannot draw it). It repaints on `FARM_CHANGED` `start`, `finish`, `delete` and `store`.
> - §9.4 `tests/test_panel.lua`'s subcategory set reads `Farm | General | Toasts`: the mock's registry
>   is keyed by name, so the case sorts it, as it did for `General | Toasts`.
> - §8 the launcher's Farm session entry and both farm key bindings run `runVerb("farm", ...)`; the
>   History title mark runs `NS.RunVerb("farm")`. The full `/lh farm` grammar was already M4.1b's.

## 1. Goal

A player starts a farm session, farms, and finishes it. While it runs, a companion panel shows the
session's total value and the rate per hour, the money, vendor and AH sub-totals, the costs, and an
activity tally. Finishing opens a summary. Every finished session is saved per character as a full,
self-contained record (D18). The record has a Details window, a Farm tab in the History window, and
a sessions list on the panel. A `/reload` or a disconnect keeps the session going, and a logout
finishes it (D17). The clock pauses on AFK and after N idle minutes, and idle time comes off the
clock (D16). Gains come from M3's pre-gate feed and costs from recorded `OUT` rows (D19).

### Decisions implemented

| Id | What M4 does |
|---|---|
| D15 | The headline is the total **and** the rate per hour. `settings.farm.headlineBasis` (gross / net, default gross) and `settings.farm.headlineValue` (money / vendor / ah, default ah) |
| D16 | `settings.farm.pauseOnAFK` (default on) and `settings.farm.idleMinutes` (default 5, 0 = off). An idle pause banks the clock back to the last gain (§5.2) |
| D17 | Logout-intent hooks plus `PLAYER_LOGOUT`: intent finishes the session, and no intent suspends it so it resumes on load. A stale-session fallback covers Alt-F4 and crashes (§5.4) |
| D18 | `db.global.farm[charKey]`. `global.farmKeep` (default 100, 0 = all) is set through the row `settings.farm.keep`. Each session is a full record: totals, item, money, currency and cost lines, activity, and a log capped at 2000 lines (§4) |
| D19 | Gains from `NS.MSG.GAIN` (M3.1). Costs from a `Database:OnWrite` hook on `OUT` `GOLD` rows with reason `REPAIR`, `BUY` or `AH_POST_FEE` (§5.6) |
| D20 | Companion panel (§7.1), Details window (§7.3), summary at Finish (§7.4), Farm tab (§7.5), and the panel's sessions list (§7.2) |
| D21 | A title-bar mark on the History window, two key bindings, `/lh farm [start\|pause\|resume\|finish]`, and a launcher entry (§8) |
| D22 | Fourteen activity lines, each a setting. Currencies and deaths are off by default (§6) |
| D23 | A `Farm` settings page of its own with tabs `General` and `Activity` (§9) |

### Rulings this spec makes (architect's calls, inside the owner's decisions; each is cheap to flip)

| # | Ruling | Why |
|---|---|---|
| F1 | **Append a `GATHERING` source** (both clients), stamped when a GameObject loot window opens within `C.GATHERING_TTL` (5 s) of a Herb Gathering or Mining cast. History rows for herbs and ore then read *Gathering* instead of *Container* | "Nodes gathered" has no backing source today: a GameObject window resolves to `CONTAINER` (`modules/Attribution.lua:244-251`). The owner-approved mockup already shows *Gathering* as a History row source (`mockups.html:457`, Bismuth) and in the Details, Log and By-source views. The mockup's note that "Nodes gathered ... reuse the sources Attribution already assigns" (`mockups.html:661`) is wrong, and this ruling makes it true. The change is additive, following the FISHING precedent (`core/Constants.lua:82-85`) |
| F2 | **A manual pause stops the clock and the gain and activity tally.** Costs still count. An idle or AFK pause stops only the clock: the next gain is tallied and resumes it | The mockup's paused copy says "Your next gain or Resume starts it again" only for idle (`mockups.html:566-568`). A manual pause means "not farming now", but a repair in town during that pause is the textbook farm cost (D19 names it first) |
| F3 | An AFK pause banks the clock up to the moment AFK sets, not back to the last gain | A manual `/afk` is instant. With idle on (the default), the idle rule takes the dead minutes off first anyway |
| F4 | Farm counts item, money and currency gains whose source is in `C.FARM.GAIN_SOURCES` (§5.5). `OTHER` counts only when the gain came from a chat line (`gain.origin == "chat"`). Vendor buys, mail, AH, trade, crafting, deconstruct output and every ledger reason do not count. Reputation, XP, skill-ups and appearances count from any source | The pre-gate feed carries Reconciler diff gains: mail, AH buys and vendor purchases. Counting those as farm income would be wrong |
| F5 | Stale window `C.FARM.STALE_SEC = 1800` (30 min) | Long enough for a disconnect and a reconnect queue. Short enough that an Alt-F4 session does not reopen the next evening |
| F6 | A finished session with zero log lines is discarded, with one chat line (`farm session discarded: nothing was gained.`) | Keeps a mis-press of the Start/finish key out of the saved list |
| F7 | Prices are snapshot once per item per session at its first gain (a row's own prices when the feed carries the record). The read is deferred off the combat path | Point-in-time, the same policy as the record's `vendorPrice`/`auctionPrice` (`modules/Collector.lua:206-217`), with one `GatherAll` per item per session instead of one per gain |
| F8 | "AH value" uses the per-unit AH price, or the vendor price when there is none (`mockups.html:583`, "n/a" per unit, vendor in the total). It is never `Util.RecordValue`'s max | D15's AH mode. `RecordValue` (`core/Util.lua:104-110`) is the "Highest" rule, which is a different measure |
| F9 | The farm panel follows General visibility. A panel hidden by visibility comes back on the next allowing edge | `settings.visibility` governs every frame (`modules/Browser.lua:755-763`). A persistent display hidden at the pull should not stay gone for the rest of the session |
| F10 | Holdings' *Forget holder* does not touch farm sessions. Retention and purge do not either | The record is the session's own copy (`mockups.html:684`) |
| F11 | Skinning a corpse is not a node. Its loot window is a creature window, so the mob set dedupes it (§5.7) | One corpse, one mob |

---

## 2. Dependencies on M1-M3 (contracts M4 consumes)

**M3.1 gain feed (as shipped).** `modules/GainFeed.lua` is the only sender of
`NS.MSG.GAIN = "Ka0s_LootHistory_Gain"` (`core/Constants.lua:524-527`; its comment already names
`NS.Farm` as a receiver). The send is `GainFeed.Send(_, g, parent)` (`:73-81`), and it is reached
through `SendChat` (`:93-100`, origin `chat`), `SendEvent` (`:104-108`, origin `event`) and
`FromDiff` (`:136-147`, origin `diff`). Every send carries one reused scratch table (`:34`), and it
is valid only during the synchronous send. A receiver copies what it keeps.

*Payload.* `GainFeed.FIELDS` (`:24-29`) is cleared by `Begin` on every send. These are the fields
each observer actually fills:

| kind (`C.GainKind`, `core/Constants.lua:219-220`) | Sender | Fields set (besides `kind`, `dir = "IN"`, `sim`, `origin`, `recorded`) |
|---|---|---|
| `ITEM`, chat | `modules/Collector.lua:172-179` | `id` (itemID), `link`, `qty`, `name`, `quality`, `classID`, `source`, `sourceDetail`, `confidence`, `record` (row or nil), `gated` (drop reason or nil) |
| `ITEM` / `CURRENCY` / `GOLD`, diff | `modules/GainFeed.lua:122-147` | `id`, `link` (items), `name`, `quality`, `classID` (items), `qty` (the delta the feed claims did not take), `source` = the diff reason, `confidence`. `record` is nil, and `recorded` is `Reconciler:RowAllowed` |
| `CURRENCY`, chat | `modules/Collector.lua:307-313` | `id` (currencyID), `name`, `qty`, `quality`, `source`, `sourceDetail`, `confidence`, `record`, `gated` |
| `GOLD`, chat | `modules/Collector.lua:367-373` | `qty` (copper), `name = "Gold"`, `source`, `sourceDetail`, `confidence`, `record`, `gated`. **`id` is nil** |
| `REPUTATION` | `modules/Reputation.lua:164-172` | `dir` (`IN`, or `OUT` for a loss), `id` (factionID), `qty` (the **absolute** delta), `name`, `label`, `rank`, `standing`, `threshold`, `repType`, `accountWide`, `source`, `sourceDetail`, `confidence`, `record`, `gated` |
| `APPEARANCE` (Retail) | `modules/Appearance.lua:82-89` | `id` (sourceID), `itemID`, `link`, `name`, `quality`, `qty = 1`, `newLook` (boolean), `source`, `sourceDetail`, `confidence`, `record`, `gated`. IN only |
| `XP` | `modules/Progress.lua:76-81` | `qty` (the delta), `level`, `levelUp`, `cur`, `max`, `source`, `sourceDetail`, `confidence` |
| `SKILL` | `modules/Progress.lua:126-131` | `id` (skill line), `name`, `old`, `new`, `max`, `qty` (= new − old), `source = OTHER`, `confidence` |

`icon` is declared in `FIELDS` but no observer sets it. Every field §5.5 reads is in this table, so
**M4 adds no payload field**. Within a send, a chat gain that wrote no row posts a feed claim
(`:93-100`), and the holdings diff consumes that claim (`:139`). So Farm sees each gain once.

*The farm entry.* M3 shipped `GainFeed:SetFarm(kinds)` (`:186-190`). `kinds` is a set keyed by
`C.GainKind`, or nil. `Recompute` (`:170-184`) ORs that set into `wants[kind]`, still masked by
`C.FEATURE.appearances`. It keeps `toastWants` as the feeds' share only, sets `on`, and then runs
`syncObservers` (`:160-166`). That calls each `SyncCapture`: Reputation (`modules/Reputation.lua:308-313`)
and Appearance (`modules/Appearance.lua:184-189`) register on *record switch OR `wants`*, and Progress
(`modules/Progress.lua:256-263`) registers on `wants` alone and seeds a kind when it is switched on.
A profile or toasts `Recompute` keeps `_farm`. `GainFeed:Disable` (`:207-216`) clears `_farm` along
with everything else. So:
- `Farm:Reconcile` calls `NS.GainFeed:SetFarm(C.FARM.GAIN_KINDS)` when it goes live and
  `SetFarm(nil)` when it goes down (§5.1). `C.FARM.GAIN_KINDS` is one constant table with all seven
  kinds (§4.4). A running session keeps every observer registered even with toasts and record
  switches off. Activity settings only control display, so they never narrow the set.
- Stand-up order: `Farm:Enable` runs after `GainFeed:Enable` and after the observers' Enables (§11.1).
  Its `Reconcile` sets the set again after a stand-down has dropped it. Stand-down order:
  `Farm:Disable` runs before `GainFeed:Disable`. Its `SetFarm(nil)` is harmless there, because each
  observer's `SyncCapture` is already a no-op (`_settings`/`_up` cleared).
- **M4.1a adds nothing to `modules/GainFeed.lua`.** `tests/test_gain_feed.lua` gains Farm-shaped cases.
  The full set keeps Reputation, Appearance (Retail) and Progress registered with toasts and record
  switches off. A `profile` Recompute keeps the set. `Disable` drops it, and a following `SetFarm`
  restores it. The `SetFarm` case already at `tests/test_gain_feed.lua:115-121` stays.

M4 never reaches into Collector, Reconciler, Reputation, Appearance or Progress for gain data.

**M2.** `REPUTATION`/`APPEARANCE` kinds, `C.FEATURE.appearances` (Retail), and `newLook` on rows
and in the feed.

**M1.** No runtime dependency. The icon declaration line will already carry M1/M3 additions, and
M4 appends to it (§10).

**M3.6 (as shipped).** The Toasts page made `tests/test_panel.lua`'s subcategory set multi-page
(`"General | Toasts"`, `:33-41`), and `P:Register` registers Toasts between General and Profiles
(`settings/Panel.lua:809-813`). It did **not** make `/lh list` page-aware: `groupKey` is still
`row.group or "?"` (`settings/Slash.lua:481-485`). M4.5 extends the first two changes and makes the
third (§9.4).

---

## 3. Files

### 3.1 New files

| File | Contents |
|---|---|
| `core/CompatFarm.lua` | Compat family file, topic "farm session reads" (compat: `core/Compat<Topic>.lua`). `Compat.LootSourceGUIDs`, `Compat.IsPlayerAFK`, `Compat.QuestTitle`, `Compat.HookLogoutFamily` (§5.4) |
| `modules/FarmModel.lua` | `NS.FarmModel`. **Pure**: session constructor, clock math, zone banking, tally application, totals, rates, log pack/unpack, log and cap trims, best-per-zone, display formatters. No client reads, no store reads |
| `modules/Farm.lua` | `NS.Farm`. Runtime: store routing, start/pause/resume/finish/suspend/restore, feed handler, cost write hook, loot-window/container/quest notifications from Attribution, zone/AFK/death rows, logout intent, idle ticker, price pass, `FARM_CHANGED` sender, `Enable`/`Disable` |
| `modules/FarmList.lua` | `NS.FarmList`. One virtualized, sortable list widget (FauxScrollFrame, the BrowserTable bind-slice shape) used by every farm table |
| `modules/FarmPanel.lua` | `NS.FarmPanel`. The companion panel (`LootHistoryFarmPanel`) and its docked sessions list (`LootHistoryFarmSessions`) |
| `modules/FarmDetails.lua` | `NS.FarmDetails`. The Details window (`LootHistoryFarmDetails`, 6 tabs) and the summary window (`LootHistoryFarmSummary`) |
| `modules/FarmTab.lua` | The Farm tab: `NS.Browser:RegisterTab{ name = "Farm", order = 50, ... }` |
| `modules/FarmTestData.lua` | `NS.FarmTestData.Build(now)`: the session-only test-mode sample |
| `settings/SchemaFarm.lua` | `NS.SchemaFarm.Rows()`: the Farm page's schema rows (§9.2), which `settings/Schema.lua` appends at file load beside the Toasts loop (the `settings/SchemaToasts.lua` precedent), plus the keep-cap confirm |
| `settings/PanelFarm.lua` | `NS.FarmPage.Build(mainCategory)`: the Farm settings page |
| `docs/farm.md` | Addon-specific doc (documentation-§3 Tier 3): session model, storage, logout rules, activity sources |
| `tests/test_farm_model.lua`, `tests/test_farm.lua`, `tests/test_compat_farm.lua`, `tests/test_farm_panel.lua`, `tests/test_farm_details.lua`, `tests/test_farm_tab.lua` | §13 |

### 3.2 Changed files

| File | Change |
|---|---|
| `core/Compat.lua` | The family header (`:12-14`) names `core/CompatFarm.lua` (compat: the root's header lists every family file). The header also omits M3's `core/CompatGain.lua`, so the same edit adds that file too |
| `core/Constants.lua` | `GATHERING` in `SourceType`/`SourceOrder`/`SourceLabel`/`SOURCE_IMPLEMENTED` (not `LEDGER_REASON`); `C.GATHERING_TTL = 5`; `C.FARM` with `GAIN_KINDS` (§4.4); `MSG.FARM_CHANGED`. M4.2 adds `C.LAYERS.STRATA.WINDOW_PERSISTENT = "MEDIUM"` and the stack-comment lines (§11.3) |
| `core/State.lua` | `NS.SimStores` (`:33`) gains `farm`; `State.testFarm` beside `testHoldings`/`testDaily` (`:23-24`); `State.farmLogoutIntent` |
| `core/LifecycleSetup.lua` | STAND_DOWN_STEPS (`:173-209`) and STAND_UP_STEPS (`:212-230`) (§11.1) |
| `core/LauncherSetup.lua` | `runVerb(verb, rest)`; two binding buttons, labels and `NS.BINDINGS` rows; launcher `extraEntries` (§8) |
| `core/PerfSetup.lua` | Buckets `{ key = "farmGain", within = "gainSend" }` and `{ key = "farmWindow" }`, appended after `skillScan` (`:63-81`) |
| `Bindings.xml` | Two `<Binding>` lines after the Show window line |
| `defaults/Global.lua` | `farm = {}`, `farmKeep = 100` |
| `defaults/Profile.lua` | `settings.farm = {...}` (§9.1) |
| `modules/Attribution.lua` | Gathering cast detection plus the `GATHERING` branch in `OnLootOpened`; three Farm notifications (§5.7) |
| `modules/GainFeed.lua` | No change. Farm uses the shipped `SetFarm(kinds)` (§2). `tests/test_gain_feed.lua` gains the Farm-shaped cases |
| `modules/Browser.lua` | `farm` title-mark extra; `charSource`/`zoneSource == "farm"` option sources; FarmPanel fan-out in `OnSettingsChanged`, `AdoptProfile` and the combat edges |
| `modules/BrowserWidgets.lua` | `charOptions(mode)` and `zoneOptions(mode)` take a source mode (§7.5) |
| `modules/Sim.lua` | Prepare sets `S.farm = {}` beside `S.history, S.holdings, S.daily` (`:277`); `releaseStores` sets `S.farm = nil` (`:412-417`); both call `NS.Farm:OnStoreSwapped()` |
| `modules/SimWorld.lua` | Providers for `LootSourceGUIDs` (one GUID per slot, the world's window source), `IsPlayerAFK` (false), `QuestTitle` (fixture title or nil) |
| `modules/TestData.lua` | `TD.Publish` sets/clears `NS.State.testFarm` through `NS.FarmTestData.Build` |
| `modules/Diagnostics.lua` | A `farm` section and `farm` in the sim-store line (§11.5) |
| `core/Database.lua` | `StorageStats` gains `farmBytes`/`farmSessions` from `NS.Farm:StorageStats()` |
| `settings/Schema.lua` | Appends `NS.SchemaFarm.Rows()` after the Toasts loop (`:666-668`); `S.RESET_EXEMPT["settings.farm.keep"] = "farmKeep"` (`:724-727`); `NS.COMMANDS` (`:1256`) gains `farm` after `holdings` (`:1305`). M4.1b adds a minimal row and M4.5 the full grammar |
| `settings/Panel.lua` | `P:Register` registers the Farm page after the Toasts block (`:809-813`) and before Profiles, and its "THREE sub-pages" comment (`:790`) becomes four; the General > History storage readout adds the farm line |
| `settings/Slash.lua` | `groupKey` (`:481-485`) becomes page-aware. M3 did not do this (§9.4) |
| `LootHistory.toc` | §3.3 |
| `CLAUDE.md` | `LibKa0s icons:` line (§10); `docs/farm.md` in the docs list |
| `libs/LibKa0s/media/icons/` | `add`, `map-marker`, `media-pause`, `media-play`, `minimise`, `star`, copied from the vendored `feat/2026-11-27-feed` source (§10) |
| `.luacheckrc` | Globals the new files read/write (`StaticPopupDialogs` entries already allowed; add `LootHistoryFarm*` frame names, `BINDING_NAME_*` through rawset needs none) |

### 3.3 TOC placement

```
core\Compat.lua
core\CompatClient.lua
core\CompatTooltip.lua
core\CompatProgress.lua
core\CompatGain.lua
# LOAD-BEARING POSITION: a compat family file (compat: listed contiguously after the root) and
# above core\SimSeam.lua, whose Sim:NewSeam wraps every NS.Compat member at file load; a member
# added below the seam escapes the wrap (NS.SimSeam:Unwrapped(), tests/test_sim_seam.lua).
core\CompatFarm.lua
# (SimSeam's own comment, LootHistory.toc:55-61, adds core\CompatFarm.lua to its family list)
core\SimSeam.lua
...
modules\Timeline.lua
# LOAD-BEARING POSITION: pure; modules\Farm.lua, modules\FarmPanel.lua, modules\FarmDetails.lua and
# modules\FarmTab.lua bind NS.FarmModel as a file-scope upvalue at load, so it must be above them.
modules\FarmModel.lua
# LOAD-BEARING POSITION: binds NS.FarmModel and NS.Perf as file-scope upvalues at load (the gain
# feed and loot-window hot paths, performance-§2); modules\FarmModel.lua and core\PerfSetup.lua must
# be above. Below modules\GainFeed.lua (LootHistory.toc:147); it calls NS.GainFeed:SetFarm and
# subscribes to NS.MSG.GAIN at call time only.
modules\Farm.lua
# LOAD-BEARING POSITION: modules\FarmPanel.lua, modules\FarmDetails.lua and modules\FarmTab.lua bind
# NS.FarmList at file load; it must be above them.
modules\FarmList.lua
# LOAD-BEARING POSITION: binds NS.FarmModel and NS.FarmList at load; both must be above.
modules\FarmPanel.lua
# LOAD-BEARING POSITION: binds NS.FarmModel and NS.FarmList at load; both must be above.
modules\FarmDetails.lua
# LOAD-BEARING POSITION: calls NS.Browser:RegisterTab at file load; modules\Browser.lua must be above.
modules\FarmTab.lua
# CONVENTIONAL: read at call time by modules\TestData.lua's TD.Publish; kept beside the farm files.
modules\FarmTestData.lua
modules\TestData.lua
modules\ToastModel.lua
...
settings\SchemaToasts.lua
# LOAD-BEARING POSITION: settings\Schema.lua appends NS.SchemaFarm.Rows() to its row array at file
# load, beside the Toasts rows and before the Schema runtime is built, so this must be above it.
# Like settings\SchemaToasts.lua, it reads NS.Options' composers and both defaults tables at load.
settings\SchemaFarm.lua
settings\Schema.lua
settings\Slash.lua
settings\Panel.lua
settings\PanelAuction.lua
settings\PanelToasts.lua
# CONVENTIONAL: the Farm page's builder, registered from P:Register (settings\Panel.lua) at call time.
settings\PanelFarm.lua
settings\Profiles.lua
```

`modules/Attribution.lua` (above all of these) reaches `NS.Farm` only at call time, through a
`_live` test (§5.7). `modules/Browser.lua` reaches `NS.FarmPanel` only at call time.

---

## 4. Data shapes

### 4.1 The store

`db.global.farm` is declared `farm = {}` in `defaults/Global.lua`. That is additive and backfilled by
AceDB, so there is no MIGRATIONS step and `SCHEMA_VERSION` stays where M2 left it (the v11
precedent, `core/Database.lua:412-420`; the ladder now ends at v16, `:442-447`; and M2 §2).

```lua
db.global.farm[charKey] = {          -- charKey = NS.Util.PlayerKey() (core/Util.lua:10-20)
  active   = <session>|nil,          -- at most one open session per character
  sessions = { <session>, ... },     -- finished, oldest first
  nextId   = 1,
}
db.global.farmKeep = 100             -- D18 cap; 0 = keep all. Row: settings.farm.keep (§9.2)
```

### 4.2 A session

```lua
{
  v = 1,                       -- the session's own shape stamp; a later reshape migrates by `v`
  id = 7, name = "Isle of Dorn",  -- name: primaryZone at Finish, renamable; "" while open
  char = "Charone-Realm", classFile = "MAGE",   -- NS.Compat.PlayerClassFile() (core/Compat.lua:906)
  startedAt = 1795000000, endedAt = nil, endReason = nil, -- "manual"|"logout"|"stale"
  -- clock (all time() epochs; GetTime() resets on reload)
  activeSec = 0,               -- banked running seconds
  runningSince = 1795000000,   -- epoch while running, nil while paused
  pauseReason = nil,           -- "manual"|"idle"|"afk"|"standDown" while paused
  lastGainAt = nil, lastSeen = 1795000000,
  resumeOnLoad = nil, wasRunning = nil,  -- set by Suspend at PLAYER_LOGOUT without logout intent
  -- zones
  zone = "Isle of Dorn", zoneSince = 1795000000, zoneSec = { ["Isle of Dorn"] = 0 },
  zoneOrder = { "Isle of Dorn" },  -- zones in first-seen order: primaryZone's tie rule (M4.1a)
  primaryZone = nil,           -- set at Finish: argmax zoneSec, ties to the first seen
  -- lines
  items = { [itemID] = { link = "|cff...|r", q = 3, qty = 63, vu = 176, au = 21000,
                         src = { GATHERING = 63 } } },  -- vu/au: copper per unit or nil
  money = { [SOURCE] = copper },
  currencies = { [currencyID] = { qty = 40, src = { KILL = 40 } } },
  costs = { REPAIR = 90000, BUY = 110000 },       -- copper, by reason
  costCurrencies = { [currencyID] = qty },        -- currency spent under BUY (no copper value)
  activity = { mobs = 0, items = 0, nodes = 0, fish = 0, quests = 0, questRewards = 0,
               containers = 0, quality = { [q] = n }, rep = { [factionID] = { name = "", delta = 0 } },
               xp = 0, skill = { [lineID] = { name = "", from = 0, to = 0 } }, looks = 0,
               currency = 0, deaths = 0 },
  log = { "2512|i|210930|5|GATHERING", ... },     -- packed lines, oldest first (§4.3)
  logDropped = 0,
  totals = nil,                -- { money, vendor, ah, costs } snapshot written at Finish
  mobRing = { guid, ... }, mobPos = 0,            -- active only; dropped at Finish
}
```

Runtime-only state (the mob set, the price queue, the totals cache) lives in tables keyed by the
session table inside `modules/Farm.lua` and is never written into the session.

### 4.3 The packed log

One string per line: `<t>|<k>|<fields...>`, where `t` is integer seconds since `startedAt`. The
fields are joined with `|`, and any `|` inside a free-text field is replaced with `/` first.

| k | Fields | Shown as (Log tab) |
|---|---|---|
| `i` | itemID, qty, source | `<name> x<qty>`, value = qty * unit price at the measure, source label |
| `m` | copper, source | `<money> looted`, value = copper |
| `c` | currencyID, qty, source | `<currency name> x<qty>`, no value |
| `r` | factionID, signed delta | `<faction> +n` / `-n` |
| `x` | amount | `Experience +n` |
| `s` | lineID, newLevel | `<skill> <newLevel>` |
| `a` | itemID or 0 | `New appearance: <item name>` |
| `q` | questID, title (cut to 60 chars) | `Quest turned in: <title>`, source Quest |
| `o` | reason, copper, currencyID or 0, qty or 0 | `<reason label>`, value = -copper, source Cost |
| `d` | (none) | `Died` |
| `z` | zone name | `Entered <zone>` |
| `p` | reason | `Paused (<reason>)` |
| `u` | (none) | `Resumed` |

`FarmModel.Pack(t, k, ...)` / `FarmModel.Unpack(line)` round-trip every kind. Trimming: when
`#log > C.FARM.LOG_CAP + C.FARM.LOG_BATCH` (2000 + 100), drop the oldest `LOG_BATCH` in place (a
shift loop: the client's Lua 5.1 has no `table.move`) and add that to `logDropped`. At Finish, trim to exactly `LOG_CAP`. Totals never come
from the log, so trimming changes no total (`mockups.html:685`).

### 4.4 Constants (`core/Constants.lua`)

```lua
C.GATHERING_TTL = 5
C.FARM = {
  STALE_SEC = 1800, INTENT_TTL = 30, IDLE_TICK = 30,
  LOG_CAP = 2000, LOG_BATCH = 100, MOB_RING = 256, MIN_RATE_SEC = 60,
  PRICE_DELAY = 1, PRICE_BATCH = 20,
  COST_REASONS = { REPAIR = true, BUY = true, AH_POST_FEE = true },
  GAIN_SOURCES = { KILL = true, CONTAINER = true, MPLUS = true, GATHERING = true, FISHING = true,
                   QUEST = true, BONUS_ROLL = true, ROLL = true, OTHER = true },
  EPIC_FLOOR = 4,               -- the panel's "Epic+ drops" line
  -- The set Farm hands GainFeed:SetFarm while a session is live (§2): every C.GainKind. One table,
  -- never mutated; Recompute masks APPEARANCE by C.FEATURE.appearances itself.
  GAIN_KINDS = { ITEM = true, GOLD = true, CURRENCY = true, REPUTATION = true, APPEARANCE = true,
                 XP = true, SKILL = true },
}
-- MSG: Sender: modules/Farm.lua (every session edge and each tallied gain). Payload: (reason)
--      "start"|"pause"|"resume"|"finish"|"gain"|"cost"|"store"|"rename"|"delete".
FARM_CHANGED = "Ka0s_LootHistory_FarmChanged",
```

### 4.5 Named non-setting state (architecture-§5)

`settings.farm.panel = { point, x, y, minimized }` and `settings.farm.details = { point, x, y, w, h }`
are profile-scoped geometry like `settings.window` (`defaults/Profile.lua:122`). `FarmPanel` and
`FarmDetails` are the only writers. List them in `docs/schema.md#state-outside-the-rows`.

### 4.6 Size

A packed line is about 55 B on disk. The 2000-line cap gives ~110 KB per session worst case, and a
one-hour session writes a few hundred lines. `Farm:StorageStats()` estimates
`Σ (256 + 60·#log + 90·items + 40·(currencies+costs+zones))` bytes plus the session count, and the
General > History storage readout prints `Farm sessions: N (≈X)` under the history line.

---

## 5. Algorithms (`modules/FarmModel.lua` pure, `modules/Farm.lua` runtime)

### 5.1 Store routing and registration (`Farm:Reconcile`)

```lua
function Farm:LiveStore()  -- db.global.farm, created if missing
function Farm:Store()      return NS.SimStores.farm or self:LiveStore() end     -- every writer
function Farm:ActiveStore() return NS.State.testFarm or self:Store() end         -- list readers
function Farm:Mine(store)  -- store[PlayerKey()] created on demand { sessions = {}, nextId = 1 }
function Farm:Active()     return self:Mine(self:Store()).active end
```

The panel's live view reads `Store()`, never the test sample (§12.2). The Farm tab and the
sessions list read `ActiveStore()`. Precedent: `modules/Rollup.lua:29-43` (`Store` and `ActiveStore`).

`Farm:Reconcile()` runs after every edge (start, finish, enable, disable, store swap). With
`open = not NS.IsStoodDown() and self:Active() ~= nil`:

- `open` and not `self._live`: `NS.RegisterRows("Farm", self.__ev, "farm")`,
  `NS.RegisterRows("Farm", self.__unitFrame, "farmUnit")`, the four lifecycle events (§5.4) on
  `self.__ev` through `NS.SafeRegisterEvent`, `self.__ev:RegisterMessage(NS.MSG.GAIN, onGain)`,
  `self._hook = NS.Database:OnWrite(onWrite)`, `NS.GainFeed:SetFarm(C.FARM.GAIN_KINDS)` (§2), arm the
  idle ticker, then `self._live = true`. `SetFarm` runs `Recompute`, which registers the observers
  synchronously, so the session's first gain is already wanted.
- not `open` and `self._live`: undo each of those (`UnregisterRows("Farm")`,
  `__unitFrame:UnregisterAllEvents()`, `__ev:UnregisterAllEvents()`/`UnregisterAllMessages()`,
  `RemoveWriteHook(self._hook)`, `NS.GainFeed:SetFarm(nil)`, cancel the ticker and the price pass through
  `NS.CancelDeferral(h)`), then `self._live = nil`.

`Database:OnWrite(fn)` answers `fn` (`core/Database.lua:650-653`), so `self._hook` is the handle
`RemoveWriteHook` takes (the Rollup precedent, `modules/Rollup.lua:112-118`). So with no session
open, farm holds no registration at all. Attribution's notifications test
`F._live`, which is one nil test on the hot path. `self.__ev = NS.NewBusTarget()` and
`self.__unitFrame = CreateFrame("Frame")` are created once and reused (the Attribution spell-frame
precedent, `modules/Attribution.lua:607-613`).

### 5.2 The clock (pure)

```
Elapsed(s, now)  = s.activeSec + (s.runningSince and max(0, now - s.runningSince) or 0)
PausedSec(s)     = (s.endedAt - s.startedAt) - s.activeSec        -- finished sessions
Bank(s, at)      : if s.runningSince then
                     at = max(at, s.runningSince); BankZone(s, at)
                     s.activeSec = s.activeSec + (at - s.runningSince); s.runningSince = nil
Pause(s, reason, at): Bank(s, at); s.pauseReason = reason; log p
Resume(s, now)   : s.runningSince = now; s.zoneSince = now; s.pauseReason = nil; log u
BankZone(s, at)  : if running and s.zone ~= "" then zoneSec[zone] += at - max(zoneSince, runningSince)
                   s.zoneSince = at
```

- **Idle** (`Farm:IdleTick(now)`, every `IDLE_TICK` s while a session is open): stamp
  `lastSeen = now`. If running, `idleMinutes > 0`, and
  `now - (lastGainAt or runningSince) >= idleMinutes*60`, then
  `Pause(s, "idle", max(runningSince, lastGainAt or runningSince))`. The idle span leaves the clock
  (D16). The ticker is a self-re-arming `NS.After(IDLE_TICK, ...)` chain whose handle is kept in
  `self._tick`. It re-arms only while `C_Timer and C_Timer.NewTimer` exist, because headless
  `NS.After` runs straight through (`core/LifecycleSetup.lua:59-72`). `NS.CancelDeferrals` reaches
  it at stand-down.
- **AFK** (row `PLAYER_FLAGS_CHANGED`, unit `player`): `afk = NS.Compat.IsPlayerAFK()`. A nil
  answer (secret or unknown) changes nothing. With afk true, running, and `pauseOnAFK`:
  `Pause(s, "afk", now)` (F3). With afk false and `pauseReason == "afk"`: `Resume`.
- **Gain on an idle/afk pause**: tallied, then `Resume` (F2). On a manual pause: dropped (F2).
- **Stand-down**: `Farm:Disable` runs `Pause(s, "standDown", now)` on a running live session. A
  session that is already paused keeps its reason. `Farm:Enable` resumes when
  `pauseReason == "standDown"`. The disable is a user command or a perf hold, never a game event
  (slash-commands-§7, performance-§6).
- Rates: `PerHour(value, activeSec) = activeSec >= MIN_RATE_SEC and value*3600/activeSec or nil`,
  and a nil rate shows `—`.

Golden (mockup, `mockups.html:518-537`): money 152g40s, vendor 38g12s, AH 611g05s, costs 14g20s,
elapsed 42:17. Gross AH 763g45s at 1,083g/h, net 749g25s at 1,063g/h. The per-hour table reads
Money 216g/196g, Vendor 270g/250g, AH 1,083g/1,063g. These are the `test_farm_model` goldens.

### 5.3 Totals (pure, `FarmModel.Totals(s)`)

```
money  = Σ s.money[*]
vendor = Σ item.qty * (item.vu or 0)
ah     = Σ item.qty * (item.au or item.vu or 0)          -- F8
costs  = Σ s.costs[*]
Value(t, measure, basis) = (measure == "money" and t.money or t.money + t[measure]) - (basis == "net" and t.costs or 0)
```

`Farm` caches the open session's totals in a weak table keyed by session and dirties it on each
tally and price fill. A finished session reads `s.totals`, written once at Finish.

### 5.4 Start, finish, suspend, restore, logout intent

**Start** (`Farm:Start()`): refuse with `a farm session is already running.` when one is open.
Otherwise `s = FarmModel.New(now, id, char, classFile, zone)`, `mine.nextId += 1`,
`mine.active = s`, `Reconcile`, send `FARM_CHANGED("start")`, and when `showPanelOnStart` is on,
`FarmPanel:Show()`. Prints `farm session started.`

**Finish** (`Farm:Finish(reason, at)`): `Bank(s, at)`. If `#s.log == 0`, discard (F6). Otherwise:
`endedAt = at`, `endReason = reason`, `primaryZone = argmax zoneSec` (or the current zone, or
`Unknown`), `name = primaryZone` unless renamed, `totals` snapshot, `TrimLog` to `LOG_CAP`, and
then clear `runningSince`, `pauseReason`, `resumeOnLoad`, `wasRunning`, `mobRing`, `mobPos` and
`lastSeen`. Append to `sessions` and run `TrimCap(mine.sessions, keep)` (drop oldest while
`keep > 0 and #sessions > keep`). Set `active = nil`, run a last price fill for items with nil
prices, `Reconcile`, send `FARM_CHANGED("finish")`. When `reason == "manual"`, open the summary.

**Logout intent.** `NS.State.farmLogoutIntent` is a `GetTime()` stamp.
- Set by post-hooks on the globals `Logout`, `Quit`, `ForceQuit` and by the events
  `PLAYER_CAMPING`, `PLAYER_QUITING`.
- Cleared by post-hooks on `CancelLogout`, `ReloadUI`, `C_UI.Reload` and by `LOGOUT_CANCEL`.
- Hooks: `Compat.HookLogoutFamily(onIntent, onCancel)` in `core/CompatFarm.lua` installs each
  through `Compat.HookSecure` / `HookSecureMember(C_UI, "Reload")` (`core/Compat.lua:953-968`,
  presence-gated). It is installed once per session (latch `Farm._hooked`) at the first `Enable`.
  Each body starts with `if NS.IsStoodDown() then return end` (the hooksecurefunc carve-out).
- These are **not** HOOK_ROWS and the four events are **not** EVENT_ROWS. They are session
  lifecycle, not capture, and a real logout must reach them while a simulation runs. Through
  `NS.Deliver`, the simulator's filter would absorb `PLAYER_LOGOUT` (`Host.OnRealEvent`, `modules/Sim.lua:190-201`; only `target == "toasts"` rows are exempt).
- Route evidence (Retail live, wow-ui-source@ab5cb850): `/logout` → `Logout()`, `/quit` → `Quit()`,
  `/reload` → `ReloadUI()` (`Blizzard_ChatFrameBase/Shared/SlashCommands.lua:752-764, 1390-1392`).
  Game menu → `GenerateMenuCallback(Logout/Quit)` rebuilt on every OnShow
  (`Blizzard_GameMenu/Shared/GameMenuFrame.lua:57-68, 215-216`). QUIT popup → `ForceQuit` /
  `CancelLogout` (`Blizzard_StaticPopup_Game/GameDialogDefs.lua:1422-1437`). CAMP Cancel →
  `CancelLogout` (`.../Mainline/GameDialogDefs.lua:407-420`). Forever: all six symbols are in the
  kit's Forever export (`tests/_kit/client_globals_forever.lua`, Ketho/BlizzardInterfaceResources
  `forever` @ `e230342a`, 2026-11-14: inherited from the live base, none in `removed`), and so are
  `UnitIsAFK`, `C_QuestLog.GetTitleForQuestID` and `GetLootSourceInfo`. That export lists names
  only. No Forever FrameXML source is checked out locally (M4.1a looked in the kit and the sibling
  checkouts), so the routing of `/logout`, `/quit`, the game menu and the QUIT/CAMP popups through
  these globals is **not cited** (§14, D-4). Per-client fallback (§12.1): the intent has a second
  path that does not depend on that routing, the `PLAYER_CAMPING` and `PLAYER_QUITING` events. With
  neither, `PLAYER_LOGOUT` suspends the session as for a reload, and the restore rules close it: a
  return after `STALE_SEC` finishes it as `stale` (F5), a return within it resumes it. Smoke row
  FOREVER-22 checks the routing in game.

**PLAYER_LOGOUT** (on `Farm.__ev`, registered while a session is open). It acts on
`Farm:LiveStore()` only, and the sim store is never persisted.
- `intent = farmLogoutIntent and GetTime() - farmLogoutIntent <= C.FARM.INTENT_TTL`. The TTL
  covers the 20 s countdown. An intent left behind by a movement-cancel that fired no event expires
  on its own.
- intent: `Finish("logout", time())`.
- else **Suspend**: `wasRunning = runningSince ~= nil`, `Bank(s, now)`, `resumeOnLoad = true`,
  `lastSeen = now`. The seconds of a reload or reconnect stay off the clock.

**Restore** (first `Farm:Enable` of the client session, latch `Farm._restored`; later stand-ups
only resume a `standDown` pause). For `s = LiveStore()[me].active`:
1. `s.resumeOnLoad`: clear it. If `now - lastSeen > STALE_SEC`, `Finish("stale", lastSeen)`. Else,
   if `wasRunning`, `Resume(s, now)`. Clear `wasRunning`.
2. `s.runningSince` set (no clean logout: crash, Alt-F4, window close): `Bank(s, lastSeen)`. Then
   `Finish("stale", lastSeen)` if `now - lastSeen > STALE_SEC`, else `Resume(s, now)`.
3. Paused: `Finish("stale", lastSeen)` if `now - lastSeen > STALE_SEC`; a `standDown` pause
   resumes.
4. Rebuild the mob set from `mobRing`.

A stale finish prints `farm session from <date> was left open; it has been finished and saved.`
and opens nothing. Sessions are per charKey, so an open session on character A survives playing
character B, and rule 1 or 2 closes it when A returns.

### 5.5 Gains (`onGain`, `NS.MSG.GAIN`, bucket `farmGain`)

```lua
local function onGain(_, g)
  local t0 = Perf.on and debugprofilestop()
  local s = Farm:Active()                       -- Store(): the sim store during a sim
  if s and not (s.pauseReason == "manual" or s.pauseReason == "standDown") then
    FarmModel.ApplyGain(s, g, time(), vu, au)   -- pure; returns tallied?, itemIDNeedingPrice
    -- vu, au: read here from g.record (nil when it has none), never from the client
    -- tallied: lastGainAt = lastSeen = now; idle/afk pause -> Resume; dirty totals; queue price;
    --          FARM_CHANGED("gain") (receivers coalesce)
  end
  -- GAIN is sent only from inside GainFeed:Send's gainSend bracket, so the parent is always gainSend
  -- (declared `within = "gainSend"` in core/PerfSetup.lua; performance-§3).
  if t0 then Perf.Note("farmGain", debugprofilestop() - t0, "gainSend") end
end
```

The receiver is registered on `Farm.__ev`. The toast feeds use a private target of their own
(`modules/ToastFeed.lua:17`), so Farm's registration does not replace theirs. Copy every value the
handler keeps: `g` is the reused scratch table (§2).

`FarmModel.ApplyGain(s, g, now, vu, au)`. The fields read are those in the §2 payload table:
- `ITEM` IN: skip unless `GAIN_SOURCES[g.source]` and (`g.source ~= "OTHER"` or
  `g.origin == "chat"`) (F4). Then `items[g.id]` is created with `link = g.link`, `q = g.quality`,
  and `vu`/`au` from the caller. Those come from `g.record.vendorPrice` and
  `NS.AuctionPrice:Pick(g.record.auctionPrice)` when the chat gain wrote a row (`modules/Collector.lua:206-217`).
  A gated or diff gain has `record == nil`, so its prices come from the price pass. Then `qty += g.qty`; `src[g.source] += g.qty`; `activity.items += g.qty`;
  `quality[q] += g.qty`; `questRewards += 1` when the source is QUEST; log `i`.
- `GOLD` IN: same source rule. `g.id` is nil for money, so it is keyed by source alone.
  `money[src] += qty`, `questRewards += 1` when QUEST, log `m`.
- `CURRENCY` IN: same source rule. `currencies[id].qty += qty`, `src`, `activity.currency += qty`,
  `questRewards += 1` when QUEST, log `c`.
- `REPUTATION`: `g.qty` is the absolute delta and `g.dir` its sign (`modules/Reputation.lua:167`), so
  `rep[id].delta += (dir == "OUT" and -qty or qty)`, `rep[id].name = g.name`, log `r`.
- `XP`: `xp += qty`, log `x`. `SKILL`: `skill[g.id]` takes `from = min(from, g.old)` and
  `to = max(to, g.new)`, and `name = g.name`. Log `s` with `g.new`. Progress seeds a kind when the
  farm set switches it on (`modules/Progress.lua:256-263`), so the first XP or skill event after Start
  diffs against Start and is not lost.
- `APPEARANCE` IN with `newLook`: `looks += 1`, log `a`. Any other appearance: skip.
- Every `OUT` of `ITEM`/`GOLD`/`CURRENCY` is skipped. Costs come from §5.6.

**Price pass**: an item whose `vu`/`au` are unknown goes into the session's price queue. One
coalesced `NS.After(PRICE_DELAY)` pass prices up to `PRICE_BATCH` queued items:
`vu = select(3, NS.Compat.GetItemExtras(link))`, `au = NS.AuctionPrice:Pick(NS.AuctionPrice:GatherAll(link, id))`.
In combat (`NS.Compat.PlayerInCombat()`) the pass re-arms instead of pricing. A nil `vu` stays
queued for the next pass and for Finish. Every price fill dirties totals and sends one
`FARM_CHANGED("gain")`.

### 5.6 Costs (`onWrite`, a `Database:OnWrite` hook, `core/Database.lua:648-683`; `Add` `:665`, `Amend` `:678`)

```lua
local function onWrite(row, delta, isNew)
  if NS.IsStoodDown() then return end             -- behavioral stand-down proof (Rollup precedent)
  local s = Farm:Active(); if not s then return end
  if NS.Util.RowDir(row) ~= "OUT" or NS.Util.RowHolder(row) ~= NS.Util.PlayerKey() then return end
  if not C.FARM.COST_REASONS[row.source] then return end
  if row.kind == "GOLD" then FarmModel.ApplyCost(s, row.source, delta, time())      -- log o
  elseif row.kind == "CURRENCY" and row.source == "BUY" then
    FarmModel.ApplyCurrencyCost(s, row.itemID or row.currencyID, delta, time()) end
  -- FARM_CHANGED("cost")
end
```

- The hook adds `delta`, never `row.quantity`, because the Reconciler amends a key's row inside
  its coalesce window (`modules/Rollup.lua:64-76` comment). Costs accrue paused or running (F2).
  During a sim, the history writes and `Store()` are both the session stores, so the sim stays
  consistent.
- Use the row's own currency-id field (the same field `Ledger.RowThingKey` reads).
- **Costs need ledger capture.** `OUT` rows exist only with `settings.trackLedger` on, and gold rows
  only with `settings.recordGold` on (`defaults/Profile.lua:76-77`). When either is off, the panel's
  Costs line and the summary's Costs line read `n/a (needs ledger capture)` in `text.disabled`
  color, and the net figures equal gross. The row tooltip says
  `Costs come from the loss rows History records. Needs Track holdings and losses and Record gold (General > Capture).`
  (M4.5 confirms the exact row labels against the schema.)

### 5.7 Activity from loot windows, containers and quests (Attribution notifications)

Farm does not register its own `LOOT_OPENED` or `QUEST_TURNED_IN`. Attribution owns both on the
bus (`modules/Attribution.lua:563, 574`), and AceEvent keeps one handler per event per target.
The notification also has to run after Attribution has classified the window. So Attribution calls
Farm directly:

```lua
local F = NS.Farm; if F and F._live then F:OnLootWindow(source, n) end
```

That call goes at the end of each classified branch of `OnLootOpened` (`:261-297`): the fishing
branch (`:276-281`), the new gathering branch, and the slot-loop branch (`:282-294`) with its resolved
`source`, before that branch's `return` (the loop stops at the first slot with a GUID). It does not
go in the deconstruct branch or the no-GUID branch. `F:OnContainerOpened()` goes after the stamp in
`OnContainerItemUse` (`:427-438`), and `F:OnQuestTurnedIn(questID)` in `OnQuestTurnedIn` (`:539-542`).
The sim already drives all three paths through Attribution's rows.

`Farm:OnLootWindow(source, n)` (bucket `farmWindow`, skipped on a manual or standDown pause; on an
idle/afk pause it counts and resumes):
- `FISHING`: `fish += 1`.
- `GATHERING`: `nodes += 1`. Count windows, so a multi-tap node counts each tap.
- `KILL`: for each slot, `k = NS.Compat.LootSourceGUIDs(slot, scratch)`. For each GUID that is not
  `NS.Compat.IsSecret` and whose `DecodeGUID` kind is `Creature` or `Vehicle`, and is not yet in the
  mob set: `mobs += 1`, add it to the set, and write it into `mobRing[mobPos % MOB_RING + 1]`,
  evicting the old GUID from the set. AoE loot carries several GUIDs per slot, so every pair is read.
- `CONTAINER`/`MPLUS`: when the first GUID's kind is `Item` and
  `GetTime() - (self._containerAt or -1e9) <= C.CONTAINER_TTL`, the window belongs to a hook stamp
  that was already counted: clear `_containerAt` and add nothing. Otherwise `containers += 1`. A
  GameObject chest counts as a container.
- Others: nothing.

`OnContainerOpened`: `containers += 1`, `_containerAt = GetTime()`. `OnQuestTurnedIn(questID)`:
`quests += 1`, log `q` with `NS.Compat.QuestTitle(questID)` or `Quest <id>`. Each one stamps
`lastSeen`, and none of them sets `lastGainAt`.

**Gathering source (F1), in `modules/Attribution.lua`:**
- `GATHERING_SEEDS = { 2366, 2575 }` (Herb Gathering, Mining, present on both clients).
- `Attribution:IsGatheringSpell(spellID)` answers `hit, conclusive` by comparing the cast's
  localized name (`FoldNBSP`, lowercased) with each seed's name. The `IsFishingSpell` shape is at
  `:459-467`. There is no id table: every expansion's gathering ids are different.
- `noteGathering(self, spellID)` is memoized per spellID in `_gatherCache` and sets
  `State.gatheringUntil = GetTime() + C.GATHERING_TTL`. It is called from `spellCast` next to
  `noteFishing` (`spellCast`, `:484-487`; `noteFishing` itself is `:469-482`).
- `Attribution:GatheringArmed()` is true when `gatheringUntil` is still in the future and slot 1's
  GUID kind is `GameObject`.
- In `OnLootOpened`, after the fishing branch: if armed, clear `gatheringUntil`,
  `Stamp(GATHERING, nil, CERTAIN, "LOOT_OPENED")`, `OpenLootWindow(n, GATHERING, ...)`, notify Farm,
  and return. `ResetContexts` clears `gatheringUntil`.

### 5.8 Zones and deaths (EVENT_ROWS, owner `Farm`)

| Row | Target | Handler |
|---|---|---|
| `ZONE_CHANGED_NEW_AREA` | `farm` | `z = NS.Compat.Zone()` (`core/Compat.lua:85-96`). An empty `z` is no change. Otherwise `BankZone(s, now)`, `s.zone = z`, log `z`, `FARM_CHANGED("gain")` |
| `PLAYER_DEAD` | `farm` | `deaths += 1`, log `d` (counted even on a manual pause; it is not a gain) |
| `PLAYER_FLAGS_CHANGED` | `farmUnit`, unit `player` | §5.2 AFK |

`core/Dispatch.lua`'s header gains the targets `farm` (`Farm.__ev`) and `farmUnit`
(`Farm.__unitFrame`, a RegisterUnitEvent frame). Farm's `PLAYER_ENTERING_WORLD` is not a row: the
addon object owns that event (`modules/Attribution.lua:556-561`). Restore runs from `Enable`
instead, and the zone is read at Start and Restore.

### 5.9 Best per zone (pure, `FarmModel.BestPerZone(sessions, measure)`)

Over the sessions currently listed (after filters), group by `primaryZone`. Each zone's best is the
session with the highest gross per hour at `measure`. Only sessions with
`activeSec >= MIN_RATE_SEC` are eligible, and a tie goes to the earlier session. The answer is a
set of session ids. The list draws a ★ (`star` icon) on those rows.

---

## 6. Activity lines (D22)

| Key (`settings.farm.activity.*`) | Label | Default | Panel value | Source |
|---|---|---|---|---|
| `mobs` | Mobs looted | on | `mobs` | §5.7 distinct creature GUIDs |
| `items` | Items looted | on | `items` (quantity) | item gains |
| `nodes` | Nodes gathered | on | `nodes` | GATHERING windows |
| `fish` | Fish caught | on | `fish` | FISHING windows |
| `quests` | Quests turned in | on | `quests` | QUEST_TURNED_IN via Attribution |
| `questRewards` | Quest rewards | on | `questRewards` | gain lines with source QUEST |
| `containers` | Containers opened | on | `containers` | Item/chest windows, container hook |
| `quality` | Drops by quality | on | panel: `Epic+ drops` = Σ quality[q ≥ 4]; Details: one line per quality | item gains |
| `rep` | Reputation gained | on | `+Σ delta` (signed) | REPUTATION gains |
| `xp` | Experience gained | on | `+xp` | XP gains |
| `skill` | Skill-ups | on | Σ (to − from) | SKILL gains |
| `looks` | New appearances | on (Retail only, row `clients = { "retail" }`) | `looks` | APPEARANCE newLook |
| `currency` | Currencies gained | off | Σ currency qty | CURRENCY gains |
| `deaths` | Deaths | off | `deaths` | PLAYER_DEAD |

The panel and the summary draw the enabled lines in this order. With `settings.farm.hideZero` on,
lines that read 0 are hidden. The Details Activity tab lists every enabled line plus the breakdowns:
per quality, per faction, per skill line and per currency.

---

## 7. UI surfaces (matched to the mockups)

Every frame is `CreateFrame("Frame", <name>, UIParent, "BackdropTemplate")` and follows the
checklist the Export modal and the History window use (`modules/Export.lua:473-592`,
`modules/Browser.lua:554-700`):
- `SetFrameStrata(...)` from `C.LAYERS.STRATA` (`core/Constants.lua:617-624`): the companion panel
  uses **`WINDOW_PERSISTENT`** (`MEDIUM`, added in M4.2, frame-layering-§1 T4 since standard v2.122.0).
  The sessions list, Details and Summary use **`WINDOW`** (`HIGH`), the History window's tier.
  Every window also gets `SetToplevel(true)` and is clamped and movable, with a title-bar drag
  gated by `B:IsLocked()`.
- `NS.Skin.TitleBar`, then `B:MakeTitleMarks` and `NS.Skin.Header`.
- `B:ApplySkin(f, nil, { noTopBar = true })` and `B:ApplyChrome(f)`.
- `table.insert(UISpecialFrames, name)`, and an `OnHide` that runs `NS.CloseMenu()` and closes the
  window's popups.
- A footer from `NS.MakeFooter(f, ...)` whenever the window has action buttons.
- `NS.MakeTestStrip` docked under the title bar when the window shows sample or sim data.
- Body tooltips are `place = "body"` and the action buttons are `"chrome"`
  (`core/Compat.lua:636-708`).
- Every show path refuses through `NS.IsStoodDown()` and `B:VisibilityAllows()`
  (`modules/Browser.lua:800-858`).

### 7.1 Companion panel (`LootHistoryFarmPanel`, `modules/FarmPanel.lua`)

**Role.** The panel is opened by a key binding, the launcher and a verb, so it fails the companion
test. It is also a display the player keeps up and moves under the master lock, so it is a
**primary window** (standalone-windows: close, settings and lock). Its header is
`B:MakeTitleMarks(bar, f, close, nil, { minimizeExtra(), lockExtra() })`, which reads `– 🔓 ⚙ ✕`.
The mockup's `–  ≡  🔓  ✕` (`mockups.html:511`) maps as: `–` is the minimize extra, `≡` is the
settings mark, then lock and close. The library fixes the order as extras, settings, close, so the
lock sits before the gear. Panel lock mark: the same `lock`/`unlock` art and the same verbs as the
History window. `FarmPanel:PaintLockMark()` is called from `B:OnSettingsChanged` and
`B:AdoptProfile`, next to `B:PaintLockMark()` (`modules/Browser.lua:902-906`).

**Minimize** extra: `{ key = "minimize", icon = "minimise", glyph = "-", tip = "Minimize the panel" }`.
While minimized it swaps to `add` / `+` / `Expand the panel`, repainted by the host the way
`PaintLockMark` repaints (`:140-155`). The state is `settings.farm.panel.minimized`. A double-click
on the title bar also toggles it. The minimized height is `NS.Skin.Band(f)` height minus twice its
inset, with a fallback of `TITLE_H + 2` (the Drop Watcher precedent). While minimized under test or
sim mode, the title shows the mode badge (preview-mode).

**Width** 300, fixed (not resizable). **Body, running** (`mockups.html:509-551`):
1. Zone (left) and a status chip (right): `NS.IconMarkup("media-play")` plus `Running` in
   `sem.good`, or `media-pause` plus `Paused: <reason>` in `text.disabled`. The reason words are
   `idle N min`, `AFK`, `manual`, `addon disabled`.
2. Headline: the value at basis and measure in large gold, then `<rate>/h`.
3. Sub-line, small: `<Gross|Net>, <Money|Vendor value|AH value> · <other basis> <value> · <rate>/h`.
4. Key/value grid: `Elapsed` (hh:mm:ss), `Money looted`, `Items, vendor value`,
   `Items, AH value`, `Costs` (`−` prefix, `sem.bad`).
5. `Activity` heading, then the enabled lines (§6).
6. `Gold per hour` grid: columns Money / Vendor / AH, rows Gross / Net.
7. Footer, controls only: `Pause` or `Resume`, `Finish`, `Details`, `Sessions`.

**Paused view** (`:563-569`): rows 1-2, then the hint `The clock is stopped. Your next gain or
Resume starts it again.` (idle/afk) or `The clock is stopped. Resume starts it again.` (manual).
Footer: `Resume`, `Finish`. **Minimized** (`:553-561`): rows 1-2, `<elapsed> elapsed`, and footer
`Pause`/`Resume`, `Finish`. **No session**: `No farm session running.` with footer `Start`,
`Sessions`.

**Refresh.** A full repaint runs on `FARM_CHANGED`, coalesced with `NS.Coalesce(fn, 0.25)`. A 1 Hz
`OnUpdate` repaints elapsed and the rates. It is set in `OnShow` and cleared in `OnHide`, and only
set while a session runs. Rows are pooled with `NS.Pool`. Position: `settings.farm.panel`, saved on
drag stop. The default is `RIGHT, UIParent, RIGHT, -40, 80`.

**Visibility** (F9): `FarmPanel:ApplyVisibility(inCombat)` runs from Browser's two combat edges
(`:956-968`) and from `OnSettingsChanged`. Hidden by the setting means `_hiddenByVisibility = true`,
and the next allowing edge shows the panel again.

### 7.2 Sessions list (`LootHistoryFarmSessions`, docked to the panel's right edge)

The panel's `Sessions` button is the only thing that opens it, and it belongs to the panel, so it is
a **companion**: `B:MakeTitleMarks(..., true)` gives it close only. It closes with the panel. Add
`Tip.SetGroup(panel, function() return shown companions end)`, so its tooltips open outside the
pair. The ARCHITECTURE Tooltip-placement section then names this group.
- Contents: this character's sessions from `Farm:ActiveStore()`, newest first, through `FarmList`.
- Columns: Date (`27 Nov`), Zone (`name`), Active (`h:mm`), Total, `/h`, and ★.
- Measure: `headlineValue`, gross.
- Row actions: click opens the summary, double-click opens Details, right-click opens the menu
  (§7.6).
- Size 360 x 320, not resizable.

### 7.3 Details window (`LootHistoryFarmDetails`, `modules/FarmDetails.lua`)

It is opened from the panel, the Farm tab, the summary and the sessions list. More than one owner
means it is **not a companion**, so it is a secondary window with **close and settings**
(standalone-windows). The mockup shows close only (`:578`), and the settings mark is added to meet
the standard. Title `Farm session: details` for the open session, or `Session details: <name>` for
a saved one. **Resizable** through `NS.MakeResizable`:
- `canResize = not B:IsLocked()`.
- Size ticks run only a cheap relayout (column widths and the visible-row count).
- The full rebind and the save to `settings.farm.details` run once, in `onResizeStop`.
- Default 640 x 420, minimum 480 x 300.

It has its own tab strip of 6 tabs: `Items`, `Money`, `Currencies`, `Costs`, `Activity`, `Log`. The
buttons come from `NS.Skin.Tab` and `NS.Skin.SetTabSelection`, the `LayoutTabButtons` pattern
(`modules/Browser.lua:290-316`). `B:RegisterTab` is History-only. Each tab is a `FarmList`:

| Tab | Columns (default sort) |
|---|---|
| Items | Item (quality color, link tooltip `body`), Qty, Vendor/u, Vendor, AH/u (`n/a`), AH, Source (largest src). Default sort: AH desc |
| Money | Source, Amount, Share %. Amount desc |
| Currencies | Currency, Qty, Source. Qty desc |
| Costs | Reason (`C.SourceLabel`), Amount; then currency-cost lines (Currency, Qty). Amount desc. The ledger-off note (§5.6) when it applies |
| Activity | Line, Value; then the quality, faction, skill and currency breakdowns as indented lines |
| Log | Time (`hh:mm:ss` since start), What, Value, Source. Newest first, not re-sortable. Virtualized (2000 lines). A footer note when `logDropped > 0`: `Showing the most recent 2,000 lines.` |

The window takes a session reference `{ store = "live"|"sim"|"test", char, id|nil }` (nil id = the
open session). It re-reads on `FARM_CHANGED` (coalesced 0.25 s) while it shows the open session.
`Details:Open(ref)` replaces the shown session. Footer: none (no actions).

### 7.4 Summary at Finish (`LootHistoryFarmSummary`)

It opens on a manual Finish, which can come from a key binding, and from a row click. A keybind
route means it is **not a companion**: close and settings. The mockup shows close only (`:597`).
Title: `Session summary: <name>`. Fixed width 380. Body (`mockups.html:598-628`):
1. Meta line: `<d Mon yyyy> · <HH:MM> to <HH:MM> · <h> h <m> m active (<m> m paused) · <char> · <zones by seconds, comma-joined>`.
2. Headline: value and `/h`. Basis line as on the panel.
3. `Money looted`, `Items, vendor / AH`, `Costs (repairs 9g, buys 11g)`, the parenthesis listing
   each non-zero cost reason in lower case.
4. `Activity`: the enabled, non-zero lines.
5. `Top earners`: the top 3 items by value at the measure, each `<name> x<qty> <value>`.
6. `By source`: the top 3 sources by value at the measure (items + money), `<label> <value> · <pct>%`.
7. Footer controls: `Details`, `Close`.

A test-sample or sim session shows the strip.

### 7.5 Farm tab (`modules/FarmTab.lua`, mockups `:667-680`)

```lua
NS.Browser:RegisterTab{ name = "Farm", order = 50,
  filters = { search = true, char = true, zone = true },   -- the rest are grayed, never hidden
  charSource = "farm", zoneSource = "farm",
  stock = { sortKey = "date", sortAsc = false },
  captureView = ..., applyView = ...,                          -- sortKey, sortAsc, measure
  suggest = function(text) return FT.Suggest(text) end,        -- session names and zones
  pick = function(item) NS.Browser.PickName(item) end,
  build = function(pane) FT:Attach(pane) end, refresh = function() FT:Refresh() end }
```

- `modules/BrowserWidgets.lua`: `charOptions(mode)` takes `nil`, `"holders"` or `"farm"`. `"farm"`
  lists `NS.Farm:Characters()`: every charKey in `ActiveStore()` with at least one session, with
  the session's `classFile` for the icon. `zoneOptions(mode)` with `"farm"` lists the distinct
  `primaryZone`s.
- `B:RefreshFilterOptions` (`modules/Browser.lua:396-412`) reads `spec.charSource` as a mode, prunes
  picks when the mode changes, and passes `spec.zoneSource` to `zoneOptions`.
- The search text matches name or zone.
- Header band (Timeline precedent, `modules/Timeline.lua:199-214`): the title `Saved sessions`, then
  a `Measure: AH` cycle button (click cycles Money → Vendor → AH, chrome tooltip
  `Which value the Total and Gross/h columns show.`), then the hint `Click a row for its summary.
  Double-click for its full record. Right-click to rename or delete.` The measure is part of the
  tab's saved view.
- Columns: Date (`d Mon`), Character (class-colored), Zone, Active (`h:mm`), Total, `Gross/h` (sort
  desc by default on Date; header click sorts), and ★.
- Rows come from every character's `sessions` in `ActiveStore()`, filtered. The open session is not
  listed; it is on the panel.
- `filters.export` is false, so Export is grayed. Group is not offered.
- Built lazily, `FarmList`-backed. Refreshes on `FARM_CHANGED` while the tab is visible, and on
  `ApplyTabFilters`.

### 7.6 Rename and delete

Two menu items through `NS.BrowserTable:ShowMenu(anchor, items)` (`modules/BrowserTable.lua`, POPUP
tier): `Rename…` and `Delete…`.
- `KA0S_LOOTHISTORY_FARM_RENAME` is an edit-box StaticPopup, max 48 characters. An empty answer
  restores the zone name.
- `KA0S_LOOTHISTORY_FARM_DELETE`: `Delete the farm session "<name>" from <date>? This cannot be undone.`
- Both refuse on a test-sample row with `test mode shows sample sessions; nothing to rename or delete.`
  (the HoldingsTab Forget precedent, `modules/HoldingsTab.lua:284-296`). A sim-store row edits the sim
  store.
- `Farm:Rename(ref, name)` and `Farm:Delete(ref)` write `Store()` and send `FARM_CHANGED`. A Details
  or summary window showing a deleted session closes.

---

## 8. Ingress (D21)

**Slash** (`settings/Schema.lua` `NS.COMMANDS`, inserted after `holdings`; a feature verb, so the
disabled gate wraps it, `gateFeatureVerbs`, `:1190-1256`; `holdings` is `:1305`):

```lua
{ "farm", NS.L["Farm session: farm [start|pause|resume|finish]; bare toggles the panel"], function(rest)
    local w = rest and tostring(rest):lower():match("^%s*(%S*)") or ""
    if w == "" then return NS.FarmPanel:Toggle() end
    if w == "start" then return NS.Farm:Start() end
    if w == "pause" then return NS.Farm:PauseVerb() end      -- "no farm session is running." / "the farm session is already paused."
    if w == "resume" then return NS.Farm:ResumeVerb() end    -- "no farm session is running." / "the farm session is not paused."
    if w == "finish" then return NS.Farm:FinishVerb() end    -- "no farm session is running."
    NS.Format("usage: /lh farm [start|pause|resume|finish]")
  end },
```

**Key bindings** (`Bindings.xml`, after the Show window line, same category, no header or default):

```xml
<Binding name="CLICK LootHistoryToggleFarm:LeftButton" category="BINDING_HEADER_LOOTHISTORY"/>
<Binding name="CLICK LootHistoryFarmStartFinish:LeftButton" category="BINDING_HEADER_LOOTHISTORY"/>
```

`core/LauncherSetup.lua`:
- `runVerb(verb, rest)` passes `rest or ""` (`:61-68`). Existing one-argument callers are unchanged.
- Two hidden, named, non-secure Buttons are created above the degraded exit, next to
  `LootHistoryToggleWindow` (`:88-94`), each with `RegisterForClicks("AnyDown")` and an
  `NS.RefusalLine()` gate first. `LootHistoryToggleFarm` → `runVerb("farm")`.
  `LootHistoryFarmStartFinish` → `runVerb("farm", NS.Farm:Active() and "finish" or "start")`. The
  verb's own handler runs, and the button only picks the word. The names are permanent.
- Labels: `rawset(_G, "BINDING_NAME_CLICK LootHistoryToggleFarm:LeftButton", NS.L["Toggle farm session"])`
  and `... LootHistoryFarmStartFinish ...` with `NS.L["Start or finish farm session"]`. The mockup's
  "Start / finish" becomes a verb phrase with "or" (launcher-§6, options-ui-§21).
- `NS.BINDINGS` gains, in XML order: `{ command = "CLICK LootHistoryToggleFarm:LeftButton",
  tooltip = NS.L["Shows or hides the farm session panel."] }` and `{ command =
  "CLICK LootHistoryFarmStartFinish:LeftButton", tooltip = NS.L["Starts a farm session, or finishes
  the running one and shows its summary."] }`.

**Launcher** (`Launcher:New{...}`, `:196`): `extraEntries = { { label = NS.L["Farm session"],
checked = function() return NS.FarmPanel and NS.FarmPanel:IsShown() or false end,
onClick = function() runVerb("farm") end } }`. It is gated by default (grayed while disabled). The
upstream `standards/ADDONS.md` LootHistory launcher column must add `Farm session` after the
built-ins (launcher-§2). That edit is in another repo (§14, D-3).

**History title mark** (`modules/Browser.lua`, the extras passed at the History window's
`MakeTitleMarks`): `{ key = "farm", icon = "map-marker", tip = "Farm session: shows or hides the
panel.", onClick = function() NS.RunVerb("farm") end }`, placed before `lockExtra()`. The icon and
tip are static, so the host never repaints it. Published as `win.farmButton = hb.extras.farm`
inside `MakeTitleMarks`.

---

## 9. Settings (D23)

### 9.1 Defaults (`defaults/Profile.lua`, under `settings`)

```lua
farm = {
  headlineBasis = "gross", headlineValue = "ah", pauseOnAFK = true, idleMinutes = 5,
  showPanelOnStart = true, hideZero = false,
  activity = { mobs = true, items = true, nodes = true, fish = true, quests = true,
               questRewards = true, containers = true, quality = true, rep = true, xp = true,
               skill = true, looks = true, currency = false, deaths = false },
  panel = {}, details = {},   -- named non-setting state (§4.5)
},
```

`defaults/Global.lua`: `farm = {}` and `farmKeep = 100`, with comments in the `retentionDays` style
(D6 rationale: the cap deletes recorded data, so no profile event may move it). Readers default with
`== nil` (savedvariables-§5), so `0` stays `0`.

### 9.2 Rows (`settings/SchemaFarm.lua`, `page = "Farm"`)

The file follows `settings/SchemaToasts.lua`. It publishes `NS.SchemaFarm` with `PAGE = "Farm"` and
`Rows()`, which returns a fresh array. It loads above `settings/Schema.lua`, which appends the array
at file load directly after the Toasts loop (`settings/Schema.lua:666-668`):
`for _, row in ipairs(NS.SchemaFarm.Rows()) do S.Schema[#S.Schema + 1] = row end`. Each row's
`default` reads `PD.farm.*` / `GD.farmKeep` (one declaration site).

| Path | Type / widget | Default | Group | Label | Tooltip |
|---|---|---|---|---|---|
| `settings.farm.headlineBasis` | string Dropdown `{gross "Gross", net "Net"}` | `gross` | General | Headline | Whether the headline and the per-hour rate subtract costs. |
| `settings.farm.headlineValue` | string Dropdown `{money "Money only", vendor "Vendor value", ah "AH value"}` | `ah` | General | Headline value | What the headline counts: money alone, or money plus items at vendor or AH value. AH value uses the vendor price for an item with no AH price. |
| `settings.farm.pauseOnAFK` | bool CheckBox | true | General | Pause when AFK | Stops the clock while you are flagged AFK and starts it again when the flag clears. |
| `settings.farm.idleMinutes` | number Slider 0-30 step 1 | 5 | General | Pause after idle (minutes, 0 = off) | Stops the clock after this many minutes without a gain, and takes those minutes off the clock. Your next gain or Resume starts it again. |
| `settings.farm.showPanelOnStart` | bool CheckBox | true | General | Show the panel when a session starts | |
| `settings.farm.keep` | number Slider 0-500 step 10, own get/set on `global.farmKeep` | 100 | General | Sessions kept per character (0 = all) | Account-wide: shared by every profile. When a session finishes, the oldest sessions past this count are deleted. Lowering it asks first. |
| `settings.farm.activity.<key>` x14 | bool CheckBox | §6 | Activity | §6 labels | One line per key, for example `Shows the distinct corpses you looted, taken from the loot window. Retail 12.x gives addons no reliable kill count.` for `mobs`, and `Your own deaths.` for `deaths`. `looks` carries `clients = { "retail" }` |
| `settings.farm.hideZero` | bool CheckBox | false | Activity | Hide lines that read 0 | |

Every `onChange` sends `SETTINGS_CHANGED("farm")`. FarmPanel, FarmDetails and FarmTab repaint on
that reason. `idleMinutes` also re-arms the ticker, and `pauseOnAFK` off resumes an `afk` pause.

`settings.farm.keep` follows the retention row (`settings/Schema.lua:557-576`): `S.RESET_EXEMPT`
maps it to `farmKeep`, so neither the profile reset nor the Farm page's Defaults moves it. Its
`onChange = function(v) Farm:OnKeepChanged(v) end` counts `n = Σ max(0, #sessions - v)` over every
character in the live store.
- `n == 0` or `v == 0`: accept.
- `NS.SimBlocks("Trim farm sessions")`: restore the old value quietly.
- Otherwise `StaticPopup_Show("KA0S_LOOTHISTORY_FARM_TRIM", v, n)`:
  `Keep %d sessions per character? This deletes %d saved sessions.` with buttons `Delete…`/`Cancel`.
- Accept trims every character. Cancel restores the last confirmed value through a quiet write, plus
  `sessions kept at %s; no sessions were deleted.` This is the `S:OnRetentionChanged` /
  `ConfirmRetention` shape (`:1089-1130`).

### 9.3 Page (`settings/PanelFarm.lua`)

```lua
function NS.FarmPage.Build(mainCategory)
  local ctx = O.CreatePanel(nil, "Farm", { pageKey = NS.SchemaFarm.PAGE, defaultsButton = true,
    defaultsTooltip = "Restores every setting on the Farm page to its default. Sessions kept per character is account-wide and stays as it is."
      .. " " .. O.KEYBINDS_UNCHANGED })                                            -- options-ui-§20, as Toasts
  ctx.panel.defaultsOnClick = function() O.RestoreDefaults(NS.SchemaFarm.PAGE, ctx) end   -- page-wide (options-ui-§13)
  O.SetRenderer(ctx, function(c) O.ClearScroll(c); O.RenderTabbedSchema(c, "Farm") end)
  Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "Farm")
end
```

The shape is `NS.ToastsPage.Build`'s (`settings/PanelToasts.lua:182-192`), without the banner.
`P:Register` adds `if NS.FarmPage then O.RegisterOptionsPage("Farm", "Farm", NS.FarmPage.Build) end`
directly after the Toasts block (`settings/Panel.lua:809-813`) and before Profiles, which stays last
(options-ui-§3). The page
has two tabs, General first (options-ui-§14), well inside the 8-tab budget. The farm key bindings
appear on General > Keybindings with no change (`O.KeybindingsTab` reads `NS.BINDINGS`). The global
reset is `db:ResetProfile`, so it restores every farm row except the exempt `keep`.

### 9.4 Multi-page fixes (what M3.6 left)

M3.6 already did two things. `tests/test_panel.lua:33-41` asserts the exact set `"General | Toasts"`,
and `docs/settings-panel.md:8` lists the Toasts subcategory. Still owed, all in M4.5:
- `settings/Slash.lua` `groupKey` (`:481-485`, still `row.group or "?"`), with its "single-panel
  addon" comment rewritten: `row.page ~= "General" and (row.page .. " > " .. (row.group or "?")) or (row.group or "?")`.
  This is needed now, not just tidier, because the Toasts strip (`settings/SchemaToasts.lua:30`) and the
  Farm strip both have a `General` tab, and `/lh list` would merge them. The change also renames the
  Toasts rows' `/lh list` headers to `Toasts > <group>`. No suite pins `groupKey` today, so M4.5 adds
  the case to `tests/test_slash_verbs.lua`: one General row, one Toasts row and one Farm row give
  three distinct headings.
- `tests/test_panel.lua`: the exact set becomes `"General | Toasts | Farm"`.
- `settings/Panel.lua:790`'s "THREE sub-pages" comment becomes four.
- `docs/settings-panel.md:3` ("**one** subcategory") and `:165` ("there is only one left to draw one",
  "the landing page, **General**, and **Profiles** last") still describe a single page. Rewrite them
  with the ARCHITECTURE schema paragraph (`docs/ARCHITECTURE.md:169`).
- The `settings/Panel.lua` `rowsOfGroup` filter (`:674-679`) stays `page == "General"` (it serves
  General only).

---

## 10. Icons

Append to CLAUDE.md's `LibKa0s icons:` line, keeping it alphabetical: `add`, `map-marker`,
`media-pause`, `media-play`, `minimise`, `star`. The vendored library is
`v1.119.0 (unreleased, branch feat/2026-11-27-feed)` (CLAUDE.md provenance line), so the source is
that branch and not a tag. Extract `git -C ../LibKa0s archive feat/2026-11-27-feed LibKa0s tools testkit`
into a fresh scratch directory. Copy only the needed `LibKa0s/media/icons/<name>.tga` files into
`libs/LibKa0s/media/icons/`, then run that extract's `tools/prune-icons.lua` against this repo. Do
this in the same commit as the declaration edit (M4.2 for minimise/add/media-*, M4.4 for star, M4.5
for map-marker). `tests/test_vendor_sync.lua` diffs the payload against the branch head in the
sibling checkout. All six exist on that branch (checked 2026-11-28).

---

## 11. Lifecycle, disabled state, perf, taint

### 11.1 Stand-down and stand-up (`core/LifecycleSetup.lua:173-230`)

STAND_DOWN_STEPS:
- `method("Farm", "Disable")` after `method("Rollup", "Disable")` (`:190`). That is after every gain
  observer's Disable (`:186-187`) and before `method("GainFeed", "Disable")` (`:195`). It pauses a
  running session with `standDown`, runs `Reconcile` (all down, `SetFarm(nil)` included), and
  `RemoveWriteHook`. `GainFeed:Disable` drops the farm set again in any case (§2).
- `method("FarmPanel", "Disable")`, `method("FarmDetails", "Disable")` and
  `method("FarmTab", "Disable")` after `method("Timeline", "Disable")`. Their bus targets go.
- `method("FarmPanel", "Hide")` and `method("FarmDetails", "Hide")` after
  `method("Export", "Hide")`. The panel, list, Details and Summary go, with `OnUpdate` cleared.
- `SimStop` stays first, so `SimStores.farm` is released before `Farm:Disable` pauses the live
  session.

STAND_UP_STEPS:
- `method("Farm", "Enable")` after `method("Rollup", "Enable")` (`:219`). That is after
  `method("GainFeed", "Enable")` (`:216`) and every observer's Enable (`:217-218`). It installs the
  logout hooks once, runs Restore once, resumes a `standDown` pause, and runs `Reconcile`. That
  `Reconcile` sets the farm set again (`SetFarm(C.FARM.GAIN_KINDS)`) after the stand-down dropped it.
- `method("FarmPanel", "Enable")`, `method("FarmDetails", "Enable")` and `method("FarmTab", "Enable")`
  after `method("Timeline", "Enable")`. These are bus targets for `FARM_CHANGED` and
  `SETTINGS_CHANGED`.

While disabled: no registration, no timer, no `OnUpdate`, no hook body acts, and nothing writes from
a game event (anti-pattern #85). A logout while disabled leaves the session open, and Restore closes
it on a later login if it is stale. The panel's show path refuses silently while stood down,
because the verb gate already printed the line.

### 11.2 Perf (performance-§2/§3)

`farmGain` (the GAIN handler) and `farmWindow` (`Farm:OnLootWindow`) are Shape-A brackets.
`Farm.lua` takes `NS.Perf` as a load-time local (`modules/Attribution.lua:18` precedent). Both
buckets are appended to `core/PerfSetup.lua`'s list (`:63-81`), after `skillScan`:
- `{ key = "farmGain", within = "gainSend" }`. The handler runs only inside `GainFeed:Send`'s bracket
  (`modules/GainFeed.lua:73-81`) and passes `"gainSend"` as its observed parent, as `toastPaint` does
  on a push. `gainSend` keeps no `within`, because it has no one parent (`core/PerfSetup.lua:72-75`).
  The `docs/performance.md:31` nesting note adds that `farmGain` never sums into `gainSend`.
- `{ key = "farmWindow" }`, top level. `Attribution:OnLootOpened` is not bracketed, and the
  container-hook path is not either, so it passes no parent. Per gain the work is O(1): table bumps and one
packed string, with pricing deferred (§5.5). With no session open, nothing is registered at all, and
Attribution pays one nil test. `docs/performance.md` and `docs/combat-path-sweep.md` list both
paths, and `tests/perf.lua` adds a `farmGain` scenario (1000 item gains with a session open).

### 11.3 Layers (frame-layering-§1/§5)

Owner ruling D26, resolved upstream in standard v2.122.0: frame-layering-§1 T4 now has two keys.
M4.2 adds `WINDOW_PERSISTENT = "MEDIUM"` to `C.LAYERS.STRATA` (`core/Constants.lua:617-624`) beside
`WINDOW = "HIGH"`.
- The companion panel (`LootHistoryFarmPanel`) is built on **`WINDOW_PERSISTENT`** (`MEDIUM`),
  toplevel and clamped. In the stack comment (`core/Constants.lua:590-616`), it gets a new `MEDIUM`
  line above the LibDBIcon line, as a peer of the minimap button.
- The sessions list (`LootHistoryFarmSessions`), Details (`LootHistoryFarmDetails`) and Summary
  (`LootHistoryFarmSummary`) stay on **`WINDOW`** (`HIGH`), as peers of the History window. The
  sessions list is docked to the panel's right edge and moves with it. It sits one strata above the
  panel, which is the owner's call, and nothing overlaps because the two are side by side.
- The rename/delete/trim popups are StaticPopups (DIALOG), and the row menu is POPUP.
- `tests/test_layers.lua` pins `L.STRATA.WINDOW_PERSISTENT == "MEDIUM"`, adds the key to its
  `TIER_KEYS` set (`:22`), and keeps `WINDOW == "HIGH"` (`:65`). It adds cases for the four frames:
  the panel on `WINDOW_PERSISTENT` and the other three on `WINDOW`. This is not a deviation and
  needs no register row.

### 11.4 Taint and secrets

- Every hook is `hooksecurefunc` through the Compat installers (post-hook, no taint on the secure
  logout path), latched once per session, with the body self-gated.
- No Blizzard method is replaced (events-frames-taint-§3).
- GUIDs, the AFK flag and quest titles pass `NS.Compat.IsSecret` (`core/CompatClient.lua:74-83`)
  before any compare or table key (events-frames-taint-§8, `docs/midnight-quirks.md:93-94`).
- Logging goes through `NS.Debug` with tag `Farm`, one line per state edge: start, pause (reason),
  resume, finish (reason, lines, value), suspend, restore (rule 1-3), stale, discard, trim (n), and
  each refusal. Nothing logs per gain (debug-logging-§9).

### 11.5 Diagnostics (`modules/Diagnostics.lua`)

A `farm` section:
`farm: live=%s active=%s state=%s sessions(this char)=%d chars=%d log=%d est=%s intent=%s`.
`simStores` (`:360-370`) adds `farm=%s` (the sim store's character count, or `-`).

### 11.6 `core/CompatFarm.lua` members

| Member | Seam | Behavior |
|---|---|---|
| `LootSourceGUIDs(slot, out)` | WRAPPED | `GetLootSourceInfo(slot)` returns `guid1, qty1, guid2, qty2, ...`. Writes each guid into `out[1..k]`, wipes the tail from the last call, and answers `k`. Absent API: 0 |
| `IsPlayerAFK()` | WRAPPED | `UnitIsAFK("player")`. A secret or non-boolean answers nil |
| `QuestTitle(questID)` | WRAPPED | `C_QuestLog.GetTitleForQuestID(questID)` when it is a plain non-empty string, else nil. Present on both clients (kit lists) |
| `HookLogoutFamily(onIntent, onCancel)` | PURE (installer) | Hooks `Logout`, `Quit`, `ForceQuit` → onIntent; `CancelLogout`, `ReloadUI`, `C_UI.Reload` → onCancel. Answers the count installed |

`docs/compat-layer.md` lists them. `tests/test_sim_seam.lua`'s `Unwrapped()` stays empty, and the
routing scan (`tests/test_compat_routing.lua`) covers the new file.

---

## 12. Per-client, simulator, test mode

### 12.1 Per-client (clients-§4/§5)

| Behavior | Retail 12.x | WoW Forever 1.x |
|---|---|---|
| charKey | `Name-Realm` | name and surname (`C.CHARACTER_FORM`) |
| New appearances line | shown | row hidden (`clients = { "retail" }`), tally stays 0 |
| Gathering detection | seed-name match on Herb Gathering 2366 / Mining 2575 casts | same seeds (vanilla ids). Smoke row confirms the node cast names |
| Fishing count | IsFishingLoot or the cast | cast-armed (Forever windows carry no GUID, `FishingArmed`, `modules/Attribution.lua:302-308`) |
| Zones | `ZONE_CHANGED_NEW_AREA` row (Farm's own; Attribution's is Retail-only, `modules/Attribution.lua:575-578`) | same row |
| Logout hooks | cited at wow-ui-source@ab5cb850 | symbols present (kit, `forever` @ `e230342a`); routing not cited, no local Forever source (D-4). Fallback: `PLAYER_CAMPING`/`PLAYER_QUITING` stamp the intent; with neither, the session suspends and the stale rule (F5) closes it. Smoke FOREVER-22 |
| Warband costs | a repair paid from the warband bank has holder `§warband` and does not count | n/a |

There is no new `C.FEATURE_CLIENTS` entry: farm mode is on both clients. ARCHITECTURE's per-client
table gains the `looks` row and the gathering row.

### 12.2 Simulator (H4)

- `Host.Prepare` sets `S.farm = {}` beside history/holdings/daily (`modules/Sim.lua:277`).
  `releaseStores` sets `S.farm = nil` (`:412-417`). Both call `NS.Farm:OnStoreSwapped()`, which runs
  `Reconcile` and sends `FARM_CHANGED("store")`.
- During a sim, `Store()` is the sim store. A live open session is never written: its wall-clock
  `runningSince` keeps ticking, and its idle ticker is down, because `Reconcile` sees no active
  session in the sim store. After the stop, the first idle tick banks back to `lastGainAt` when
  idle-pause is on. With idle off, the sim minutes count (§15).
- `/lh farm start` during a sim opens a sim session. Simulated gains (GAIN), costs (OnWrite on sim
  rows) and loot windows (Attribution's rows, driven by the sim) tally into it. The panel shows it
  with the cyan sim strip.
- `PLAYER_LOGOUT` acts on `LiveStore()` only.
- Farm's three EVENT_ROWS (§5.8) have target `farm`/`farmUnit`. The simulator absorbs them while a
  session runs, and only `target == "toasts"` rows are exempt (`modules/Sim.lua:190-201`). So a real
  zone change, death or AFK during a sim is absorbed, and the simulated world's deliveries reach Farm
  through `NS.DeliverAll`.
- The simulator's Prepare and stop already call `GainFeed:ResetState` (the feed claims,
  `modules/GainFeed.lua:218-221`). The farm set is not session state and stays as `Reconcile` left it.
- `tests/test_sim_store.lua`'s byte-identical invariant extends to `db.global.farm`
  (`docs/testing.md:134`).

### 12.3 Test mode (preview-mode)

- `TD.Publish` sets `NS.State.testFarm = NS.FarmTestData.Build(time())`: 6 finished sessions over
  the History sample's characters (`modules/TestData.lua:27-28, 51` keys: `TestSample.charKey` over `CLASSES`).
- Two zones (`Isle of Dorn` x3, `Ringing Deeps` x2, `Hallowfall` x1), one best pair per zone, and
  logs of 40 lines each. Fixed RNG seed. It reproduces the mockup's three rows
  (`mockups.html:675-677`).
- It is read through `ActiveStore()` and never written. Rename/Delete refuse.
- The panel ignores it and always shows the live (or sim) session.
- Test mode ends at combat start (`modules/Browser.lua:956-965`), which clears the sample too.

---

## 13. Test plan

Characterization first: before touching `modules/Attribution.lua`, run `tests/test_attribution.lua`
green on the current code. Before touching `NS.RunVerb`, run `test_keybinding`/`test_launcher` green.

| Suite | Cases |
|---|---|
| `tests/test_gain_feed.lua` | Farm-shaped `SetFarm` cases (§2): `C.FARM.GAIN_KINDS` with every feed and record switch off keeps `on`, every `wants`, and the Reputation/Appearance(Retail)/Progress rows registered. A `profile` Recompute keeps the set. `Disable` drops it and a following `SetFarm` restores it. `SetFarm(nil)` unregisters the observers again |
| `tests/test_farm_model.lua` (new, pure) | Elapsed/Bank/Pause/Resume arithmetic. Idle banks to `lastGainAt`, and to `runningSince` when there is no gain. AFK at now. Zone banking only while running, `''` ignored. primaryZone argmax with a tie to the first. Totals with vendor fallback for AH (F8). Gross/net, all three measures. Per-hour nil under 60 s. **Mockup goldens** (§5.2). Pack/Unpack round-trip for all 13 kinds plus `\|` sanitizing. Trim batches (2101 → 2001, logDropped 100) and Finish trim to 2000. TrimCap keep 100 and 0. Source rule (VENDOR/MAIL/AH/diff OTHER skipped, chat OTHER counted). questRewards for QUEST item/money/currency. Rep signed sums. Skill from/to. newLook only. BestPerZone (eligibility, tie). `v == 1` |
| `tests/test_farm.lua` (new, mock) | With no session, no rows, message, hook or timer are live (`M.__timers()` empty), and `NS.GainFeed._farm` is nil. Start registers all of them and calls `SetFarm(C.FARM.GAIN_KINDS)`, and Finish removes all of them and calls `SetFarm(nil)`. A stand-down/stand-up cycle with an open session leaves `_farm` set again. Start-while-open refusal line. The GAIN payload tallies, driven through the real senders (`GainFeed:SendChat`/`SendEvent`/`FromDiff`) with the §2 fields. A GOLD gain with `id == nil` tallies by source. A REPUTATION `OUT` subtracts. A diff `OTHER` gain is skipped and a chat `OTHER` gain counted. A manual pause drops gains and keeps costs. An idle pause resumes on a gain. Costs: `Database:Add` OUT GOLD REPAIR plus an `Amend` adds `delta` twice. Another holder, `WARBAND_DEPOSIT` and `AH_BUY` are ignored. Currency BUY goes to costCurrencies. Logout: intent (Logout hook) → Finish("logout"). No intent → Suspend, then Enable → Resume, with the reload seconds excluded. Intent older than 30 s → Suspend. CancelLogout and LOGOUT_CANCEL clear the intent. Crash path within/beyond stale. Paused-stale. Per-character isolation. Stand-down pauses with `standDown`, a hook body while stood down is a no-op, stand-up resumes. AFK is a unit row on `player`, a secret AFK changes nothing, `pauseOnAFK` off ignores AFK. Loot windows: an AoE slot with 3 GUIDs counts 3. The same corpse in a second (skinning) window adds 0. Ring eviction at 257. Fishing/gathering/chest/Item window counts. The hook stamp followed by an Item window within TTL counts once. Quest turned in plus title. Death. Zone row. Price pass deferred out of combat and filled at Finish. F6 discard. Keep-cap confirm accept/cancel. `/reload` during a sim leaves the live session byte-identical |
| `tests/test_compat_farm.lua` (new) | LootSourceGUIDs pairs, tail wipe, absent API. IsPlayerAFK secret/nil. QuestTitle. HookLogoutFamily counts installed members, and an absent `C_UI` installs 5 |
| `tests/test_attribution.lua` | A gathering cast followed by a GameObject window stamps GATHERING. With no cast, CONTAINER. A creature window after the cast is KILL. The name-seed match is conclusive only once the seed name is cached. Memo. `ResetContexts` clears it. Farm notifications fire only with `_live` |
| `tests/test_farm_panel.lua` (new) | Header marks are extras (minimize, lock) then settings then close, `companion` nil. Minimize swaps the icon and tip and persists. The headline follows both settings. Activity order and hideZero. The paused and no-session views. Costs n/a with the ledger off. Visibility hide and re-show (F9). Lock repaint on SETTINGS_CHANGED. Sim strip, and the minimized badge. OnUpdate cleared on hide. Stand-down hides everything. The sessions list is a companion (close only) and carries the Tip group |
| `tests/test_farm_details.lua` (new) | Six tabs. Items columns plus `n/a`. Log binds only the visible slice of 2000. The resize spy (ticks relayout only; one rebind plus one save on release). Settings mark present (not companion). Summary golden text against mockup values. Live refresh coalesced |
| `tests/test_farm_tab.lua` (new) | Order 50, after Holdings and Timeline. Honored filters. charSource/zoneSource farm options. The Measure cycle is part of the saved view. ★ rows. Click, double-click and right-click routes. Rename/Delete popups. Test-mode refusal |
| `tests/test_keybinding.lua` | `assertBindingsXml` with three labels, Show window first. `#NS.BINDINGS == 3`. Each new button is named, not secure, AnyDown, one press is one verb call, present on a degraded install, and refuses while disabled with the RefusalLine |
| `tests/test_launcher.lua` | The menu shows the five built-ins plus `Farm session`. checked follows the panel. Grayed while disabled |
| `tests/test_profiles.lua` | Verb order with `farm` after `holdings` (`:438-444`; the count goes from 24 to 25) |
| `tests/test_slash_verbs.lua` | Each `/lh farm` word and its refusal lines. The disabled gate prints DisabledLine and does nothing. `/lh list` headings are page-aware (§9.4) |
| `tests/test_panel.lua`, `tests/test_schema.lua`, `tests/test_panel_keybinds.lua` | Subcategory set `"General | Toasts | Farm"` (`tests/test_panel.lua:40`). Farm page tabs `General`, `Activity`. Page-wide Defaults leaves `farmKeep`. RESET_EXEMPT entry. Shipped defaults equal row defaults. `looks` row Retail-only. Keybindings tab draws 3 rows |
| `tests/test_disabled.lua` | The survey covers Farm's rows (targets `farm`/`farmUnit`), the four lifecycle events, the GAIN message, the write hook (behavioral: a REPAIR row written while stood down tallies nothing), the ticker and the price pass (`M.__timers()` empty), the panel OnUpdate, and the step order |
| `tests/test_dispatch.lua` | SNAPSHOT gains the three Farm rows on both clients |
| `tests/test_sim_store.lua` | Byte-identical `db.global.farm`. A sim farm session writes only `SimStores.farm`, and it is released at stop |
| `tests/test_layers.lua` | `WINDOW_PERSISTENT == "MEDIUM"` and in `TIER_KEYS`; `WINDOW == "HIGH"` unchanged. The panel on `WINDOW_PERSISTENT`; the sessions list, Details and Summary on `WINDOW` |
| `tests/test_constants.lua` | `FARM_CHANGED` wire pin through the real sender. GATHERING in the source tables, not in `LEDGER_REASON` |
| `tests/test_diagnostics.lua`, `tests/test_debug_coverage.lua` | The farm section. `[Farm]` edge lines |
| `tests/test_browser.lua` | The History title marks are farm, lock, settings, close. The farm mark runs the verb |
| `tests/test_testdata.lua` or the existing TestData case | `testFarm` is published and cleared, and deterministic |
| `tests/perf.lua`, `tests/test_perf.lua` | `farmGain` baseline. The bucket list carries `farmGain` (`within = "gainSend"`) and `farmWindow` |

---

## 14. Deviations to flag

Each needs the owner's call before its task merges. The choice is a register row in
`docs/ARCHITECTURE.md` `## Documented deviations`, or an upstream change to the standard. Status on
2026-11-28: D-1 and D-3 are **resolved upstream** (M4.0), and D-2 is **ruled** (D27: widen the row,
done in M4.1a). D-4 is **recorded** (M4.1a: no local Forever source; a per-client fallback and smoke
row FOREVER-22 instead). The D-1 text below is history. Its
"builds the panel at `WINDOW`" and its interim register row are superseded (§11.3).

- **D-1 `frame-layering-§1` (resolved: standard v2.122.0 `WINDOW_PERSISTENT`).** T4 puts a persistent window at `MEDIUM` and an on-demand one at
  `HIGH` under the single key `WINDOW` (`frame-layering.md:19`). The farm panel is persistent, but
  this addon's `WINDOW` is `HIGH` for the History window (`core/Constants.lua:617-624` today), and a table
  key holds one value. The spec builds the panel at `WINDOW` (`HIGH`). The recommended route is a
  **change to the standard**: a second T4 key for a persistent window beside an on-demand one (for
  example `WINDOW_PERSISTENT = "MEDIUM"`). Then the panel moves to it in a one-line change. Until
  then, a register row: `| frame-layering-§1 | The farm panel, a persistent window, sits at HIGH
  with the History window | One T4 key; a second key needs the standard | 2026-11-27 | The standard
  gains a persistent-window key |`.
- **D-2 `localization-§4` (ruled D27; M4.1a widens the row at `docs/ARCHITECTURE.md:851`).** Gathering detection (F1) compares the cast's localized name with names
  derived from seed ids, which is the same shape as the registered deconstruct row. The Fishing
  seed-name fallback shipped 2026-11-27 (`modules/Attribution.lua:451-482`) is not named in that row
  either. Recommendation: widen the existing row to "deconstruct, fishing and gathering casts". The
  trigger is unchanged.
- **D-3 `launcher-§2` (done upstream in M4.0, WowAddonStandards v2.122.1).** The extra entry must be listed in `standards/ADDONS.md`'s LootHistory
  launcher column. That file is upstream, so it is an upstream edit, not a deviation, and it is due
  with M4.5.
- **D-4 `events-frames-taint-§9` (recorded in M4.1a; verified in game by FOREVER-22).** The
  logout-family hooks are cited for Retail at wow-ui-source@ab5cb850 (§5.4). For Forever, the kit's
  export (`forever` @ `e230342a`) shows all six globals present, but no Forever interface source is
  available locally to cite their routing. Not a deviation and not a blocker: the hooks are
  presence-gated, and the per-client row in §12.1 records the fallback (the `PLAYER_CAMPING` /
  `PLAYER_QUITING` intent events, then the stale rule). If FOREVER-22 shows `/logout` reaching no
  hook and no event, the Forever logout is a stale finish, and ARCHITECTURE's per-client table says
  so (M4.6).
- **Not deviations, recorded so a reviewer does not re-raise them:**
  - Details and Summary carry the settings mark, and the panel's marks read `– 🔓 ⚙ ✕`. Both differ
    from the mockup (`:511, :578, :597`) to meet standalone-windows.
  - Escape closes the persistent panel (UISpecialFrames is a MUST).
  - Farm's lifecycle events and logout hooks bypass `NS.EVENT_ROWS`/`HOOK_ROWS`. Those tables are
    a repo rule for capture registrations (`core/Dispatch.lua:3-12`), not a standard rule, and §5.4
    gives the reason.
  - Appending `GATHERING` is an additive export-contract change on the FISHING precedent, not a
    standard deviation. It is listed in §15 as a ruling the owner may overrule.

## 15. Open questions for the owner

Nothing blocks the build. These rulings stand unless the owner overrules them: F1 (GATHERING
source), F2 (a manual pause also stops gains), F5 (30 min stale window), F6 (discard empty
sessions), and the sim-minutes caveat with idle-pause off (§12.2). These in-game facts are
verification gates, and each one is a smoke row:
1. Do Retail 12.x node casts carry the names Herb Gathering / Mining (Khaz Algar variants)?
2. Do `PLAYER_CAMPING`, `PLAYER_QUITING` and `LOGOUT_CANCEL` fire on both clients?
3. Does `PLAYER_LOGOUT` fire, and do SavedVariables flush, on a disconnect?

---

## 16. Doc updates

| Doc | Update |
|---|---|
| `docs/ARCHITECTURE.md` | Module map (the new files of §3.1). Data model (`farm`, `farmKeep`). Message bus (`FARM_CHANGED`). Slash table plus the feature-verb list (`farm`). Key bindings (three). Disabled state. Event subscriptions (Farm rows, lifecycle events, hooks). Frame layering (pointer). Tooltip placement (the panel and sessions-list group). Per-client rows. Documented deviations: the D-2 widening only (D27). D-1 needs no row. Documentation map (`farm.md`) |
| `docs/farm.md` (new) | Session model, clock rules (F2, F3), logout/reload/stale rules with the hook evidence, activity sources, cost reasons, storage and caps, sim and test-mode behavior |
| `docs/schema.md` | `db.global.farm` shape, the `v` stamp, `farmKeep` (reset-exempt), `settings.farm.*` rows, and the state-outside-the-rows entries (§4.5) |
| `docs/module-map.md`, `docs/message-bus.md` | New modules. `FARM_CHANGED` sender and receivers. `docs/message-bus.md:58` currently says "Toasts ... are its only receiver today; the farm session (#39) enters through `GainFeed:SetFarm`". It now names Farm as the second receiver |
| `docs/data-flow.md` | GATHERING (cast → window). Attribution → Farm notifications |
| `docs/settings-panel.md`, `docs/slash-dispatch.md` | The Farm page and multi-page notes. The `farm` verb grammar |
| `docs/disabled-state.md`, `docs/performance.md`, `docs/combat-path-sweep.md` | Farm steps. `farmGain`/`farmWindow` |
| `docs/compat-layer.md`, `docs/debug.md`, `docs/browser.md` | CompatFarm members. The `Farm` debug tag. The Farm tab |
| `docs/smoke-tests.md` | LH-FARM rows: start/pause/resume/finish; AFK; idle 1 min; `/reload` keeps; `/logout` finishes; `/camp` cancel by moving then `/reload` keeps; Alt-F4 then relog within 30 min resumes; a disconnect resumes; gathering herb and ore on Retail and Forever; fishing; AoE loot of 3 corpses = 3; chest and bag container; repair cost; ledger-off note; panel minimize/lock/visibility; hover placement per window; Details resize; key bindings; launcher entry; test mode and sim strips |
| `docs/test-cases.md` | Regenerated |
| `CLAUDE.md` | The icons line. The docs list mentions `farm.md` |
| upstream `standards/ADDONS.md` | Launcher column (D-3), by the owner or the standards workflow |

---

## 17. Task breakdown (plan rows M4.1-M4.6)

Each task ends green on the four-suite gate with one commit, and updates the ledger row in that
commit. LF→CRLF repair follows each commit. M4.1a and M4.1b both write their note under the plan's row M4.1, and M4.1 is marked done only after
M4.1b.

| Task | Contents |
|---|---|
| **M4.1a** Model and contracts (pure, no runtime) | (1) Constants: `GATHERING` in `SourceType`/`SourceOrder`/`SourceLabel`/`SOURCE_IMPLEMENTED` (not `LEDGER_REASON`), `C.GATHERING_TTL`, `C.FARM` with `GAIN_KINDS` (§4.4), and `test_constants` (GATHERING in the source tables, not in `LEDGER_REASON`). `MSG.FARM_CHANGED` waits for M4.1b, because `tests/test_constants.lua:394-405` pins the exact catalog through real senders. (2) `core/CompatFarm.lua` (§11.6), the TOC line after `core\CompatGain.lua`, the `core/Compat.lua:12-14` family header (CompatGain and CompatFarm), the SimSeam TOC comment, SimWorld providers, `test_compat_farm`, `test_sim_seam`, `test_compat_routing`. (3) Defaults: `defaults/Global.lua` `farm = {}` / `farmKeep = 100`, `defaults/Profile.lua` `settings.farm` (§9.1), and the `core/State.lua` fields (`SimStores.farm`, `testFarm`, `farmLogoutIntent`). (4) `modules/FarmModel.lua` and `test_farm_model` (every pure rule in §4.3, §5.2, §5.3, §5.5 `ApplyGain`/`ApplyCost`, §5.9, and the formatters). (5) GainFeed contract: no code change, and the Farm-shaped `SetFarm` cases in `tests/test_gain_feed.lua` (§2, §13). (6) Attribution: gathering detection and the `GATHERING` branch (F1, §5.7), plus the three Farm notifications behind `NS.Farm and NS.Farm._live` (inert until M4.1b). Characterization comes first (`test_attribution` green on the current code). The D27 widening of the `localization-§4` register row (`docs/ARCHITECTURE.md:851`) to deconstruct, fishing and gathering casts goes in the same commit. Gate, and regenerate test-cases |
| **M4.1b** Runtime | `modules/Farm.lua` (TOC after `modules\FarmModel.lua`): store routing (§5.1), `Reconcile` with `SetFarm(C.FARM.GAIN_KINDS)`/`SetFarm(nil)`, the GAIN receiver on `Farm.__ev` (bucket `farmGain`, parent `gainSend`), the clock and the idle ticker (`NS.After`), AFK/zone/death EVENT_ROWS (targets `farm`/`farmUnit`, the `core/Dispatch.lua` header), the logout intent plus `Compat.HookLogoutFamily` and the four lifecycle events, Suspend/Restore/stale, the price pass, the `Database:OnWrite` cost hook, F6 discard, cap trim and `OnKeepChanged`, `StorageStats` and the `Database:StorageStats` fields, the Diagnostics section. `MSG.FARM_CHANGED` comes with its sender. The perf buckets `farmGain` (`within = "gainSend"`) and `farmWindow` go in `core/PerfSetup.lua`. The lifecycle steps go in `core/LifecycleSetup.lua` (`Farm` Disable after Rollup and before GainFeed; Enable after Rollup, §11.1). The `modules/Sim.lua` store swap (`:277`, `:412-417`) and `OnStoreSwapped`. A minimal `/lh farm` row in `NS.COMMANDS` after `holdings` (start/pause/resume/finish; bare prints status until M4.2). The D-4 Forever citation for the logout routing. Tests: `test_farm`, `test_dispatch`, `test_disabled`, `test_constants` (`FARM_CHANGED` pin), `test_sim_store`, `test_profiles` (25 verbs), `test_diagnostics`, `test_debug_coverage`, `test_perf`. If `modules/Farm.lua` nears 1500 lines or a function nears CCN 15, peel the logout/restore half into `modules/FarmSession.lua` (TOC, routing tests, docs) |
| **M4.2** Panel | `C.LAYERS.STRATA.WINDOW_PERSISTENT = "MEDIUM"` plus the stack-comment line (§11.3). `modules/FarmList.lua` (base list). `modules/FarmPanel.lua` on `WINDOW_PERSISTENT`, with all its views, minimize, the lock mark, visibility, OnUpdate, and the sim strip and badge. The Browser fan-out. The bare verb toggling the panel. Icons `minimise`/`add`/`media-play`/`media-pause` (§10). `test_farm_panel`, `test_layers` (the new key pinned; panel on it) |
| **M4.3** Details and Summary | `modules/FarmDetails.lua` (6 tabs, resize, Log virtualization, summary), both on `WINDOW`. Finish opens the summary. `test_farm_details`, plus `test_layers` cases for the two windows |
| **M4.4** Farm tab and sessions list | `modules/FarmTab.lua` (order 50, after Holdings 40 and Timeline 30). The BrowserWidgets/Browser option-source modes. The sessions-list companion on `WINDOW` with its Tip group. BestPerZone ★ (icon `star`). The Rename/Delete popups and menu. `modules/FarmTestData.lua` plus TD.Publish (`modules/TestData.lua:264-266`). `test_farm_tab`, and the `test_layers` case for the list |
| **M4.5** Ingress and settings | The History title mark (icon `map-marker`). `Bindings.xml` plus two buttons, labels and `NS.BINDINGS`, and `runVerb(verb, rest)`. The launcher extra entry. The full `/lh farm` grammar. `settings/SchemaFarm.lua` above `settings/Schema.lua` (appended beside the Toasts loop), RESET_EXEMPT and the keep confirm. `settings/PanelFarm.lua` after `settings/PanelToasts.lua`, and the `P:Register` order after the Toasts block. The §9.4 leftovers: page-aware `groupKey`, the `test_panel` exact set `General \| Toasts \| Farm`, the Panel comment, and the settings-panel/ARCHITECTURE single-page lines. The storage readout line. Tests: `test_keybinding`, `test_launcher`, `test_panel`, `test_schema`, `test_slash_verbs`, `test_browser` |
| **M4.6** Sim, test mode, docs, review | The sim e2e case (a sim session tallies a scenario's gains; the live store stays byte-identical). Test-mode checks. `tests/perf.lua` farmGain. The disabled-state survey sweep. Every §16 doc, including the `docs/message-bus.md:58` receiver line and the `docs/performance.md:31` nesting note. The test-cases regen. Then the review-pass workflow, its fixes, and push M4. Do not merge |
