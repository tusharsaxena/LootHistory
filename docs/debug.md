# Debug surfaces

Loot History has two debug surfaces, and both write into the same window:

- **The debug console** is `LibKa0s-DebugLog-1.0`'s window. Tagged `NS.Debug` lines land there while
  the session flag is on.
- **The diagnostics report** is a one-shot snapshot of the addon's state, written into the console
  by `/lh diagnostics` or the console's orange **Diagnostics** link (`debug-logging-§14`). It is why this page exists (`documentation-§3`, Tier 2):
  every Ka0s addon ships the report, and a maintainer reading a pasted one needs to know what each
  line means.

The console itself is the library's, and its contract lives in LibKa0s's
[`docs/api/DebugLog/version-19.2.1-docs.md`](https://github.com/tusharsaxena/LibKa0s/blob/master/docs/api/DebugLog/version-19.2.1-docs.md)
(DebugLog 19 with DebugLogDiagnostics 2 and DebugLogGates 1 is the vendored set, from LibKa0s v1.68.1). This page covers only what Loot History
adds on top.

## The console

| Command | Effect |
|---|---|
| `/lh debug` | Shows or hides the console window, "Loot History — Debug". The logging flag is unchanged. |
| `/lh debug on` / `off` | Sets or clears the logging flag through `NS.DebugLog:SetEnabled`, which confirms on one chat line. |
| `/lh debug diagnostics` | Writes the diagnostics report (below). |
| `/lh debug events` | Prints the event names this client refused at registration, or `none`. Touches neither the window nor the flag. |
| `/lh debug <anything else>` | Toggles the window, like bare `/lh debug`. |

What Loot History supplies, all in `core/DebugLogSetup.lua`:

- **The flag is ours, and session-only.** It is `NS.State.debug`: off at login, never written to
  SavedVariables, and reset by every `/reload`. The Master controls **Debug console** checkbox shows
  and hides the window (the session-only `state.debugConsole` row); it does not set the flag.
- **The buffer is the library's 3000 lines** (`lib.MAX_BUFFER`). The footer counter reads
  `N / 3000 lines` and pins there, and Copy pastes out of the same buffer, so a long capture keeps
  only its newest 3000 lines.
- **The `[Init]` line** opens a session when the flag goes on:
  `LootHistory v<version>, schema v<n>, profile '<name>', <n> records` (`NS.InitSummary`,
  `core/Database.lua`). The report's identity header prints the same line.
- **The sink is `NS.Debug(tag, fmt, ...)`**, bound to the library's gated `Debug`. A call with the
  flag off does nothing.
- **The chrome is ours.** The window takes the History window's skin through the `applySkin` hook,
  and the console checkbox follows the window however it was closed.

Every tag in use, what writes it and when, is in [Coverage](#coverage) below. The in-game checks that
each one fires once rather than once per row are in
[smoke-tests.md](smoke-tests.md#debug-console-and-diagnostics) DIAG-2, DIAG-3 and DIAG-12 to
DIAG-18; the library's own `[Cmd]` and `[Lifecycle]` lines, and the state lines held for `debug on`,
are DIAG-31 to DIAG-33, pinned headlessly in `tests/test_debug_coverage.lua`. On an install without LibKa0s the
flag still flips on `on` / `off`, but the window is gone: instead of a confirmation, each prints the
library-absent line ending `so the debug console window is unavailable.`

## Coverage

What the log carries, tag by tag (`debug-logging-§8` flows and Diagnosis, `§9` coalescing and quiet
steady state). Every line is one gated `NS.Debug` call with its string-building behind the flag,
except the two library brackets written through the raw append, the lines the console's change
gates write (`DebugOnce` / `DebugChanged`, gated the same way), and the state lines held in the
console's at-enable queue (`DebugAtEnable`, below). The tags are single words, rendered verbatim.

**Which lines are the library's.** `Debug` (the enable bracket and a full at-enable queue), the
`Init` session summary, `Cmd` (every refusal the slash dispatcher decides, Slash 18), `Lifecycle`
(each latch edge, Lifecycle 3), `Launcher` (Launcher 5) and the combat lock's `Cfg` lines (Options
27) are written by `LibKa0s` through the sink this addon passes each descriptor as `debug`
(`debug-logging-§4`, *The library's own lines*); this addon writes no copy of any of them. Everything
else is this addon's own.

**Held for `debug on`.** Logging is off at login, so a state line written then goes through
`NS.DebugAtEnable` and lands the first time the player turns logging on, after the `[Init]` line:
the launcher's registration lines (through the Launcher descriptor's `debugAtEnable`), the
stand-up's `dependencies:` line and a refused event name. With logging already on each is written
at once.

| Tag | What emits it | When |
|---|---|---|
| `Debug` | `LibKa0s-DebugLog-1.0`, `SetEnabled` | `logging enabled` / `logging disabled`, once at each end of a session |
| `Init` | the library on enable (`NS.InitSummary`, `core/Database.lua`); `core/CoreSetup.lua` | the session summary line, right after `logging enabled`; `event X refused by this client`, once per name the first time a registration is refused, held for `debug on` when logging is off |
| `Lifecycle` | `LibKa0s-Lifecycle-1.0` (minor 3), through the descriptor's `debug` in `core/LifecycleSetup.lua` | once per latch edge, before the host's callback: `stood down: added <key> (holds: <set>)` and `stood up: released <key> (holds: none)`. A call that moves no edge writes nothing |
| `State` | `NS.StandDown` / `NS.StandUp`, `core/LifecycleSetup.lua` | right after each `[Lifecycle]` edge, only what this addon took from it: `stand-down: capture unregistered, N deferral(s) canceled`, and `stand-up: capture registered`. Neither repeats the edge or the holds. Each stand-up also writes the dependency line, `dependencies: price providers: …; latch: …`, through the at-enable queue: the load-time stand-up runs with the flag off, so that one is held and lands at `debug on`, while the two edge lines of that stand-up are not |
| `Set` | `LibKa0s-Schema-1.0` (per write and bulk acts); `traceProfileEvent`, `core/LootHistory.lua`; `S:Set`, `settings/Schema.lua` | one line per accepted write (`path = value`) or bulk act (`act scope: N rows`); a profile reset or copy; a refused write, `path rejected: <reason>` |
| `Profile` | `traceProfileEvent`, `core/LootHistory.lua` | a profile switch |
| `Migrate` | `core/Database.lua` | a migration step that ran (`vN -> vM, N rows touched`); the bound repair armed; each repair pass, `N fixed, N pending, N candidates (attempt N, still pending / done / gave up)` |
| `Prune` | `Database:PruneOld` | each retention prune with its count; `skipped: retention is Always` when there is nothing to prune by |
| `Data` | `Database:Delete` / `Database:Purge` | each delete and each purge, with the rows removed |
| `Loot` | `Collector:OnChatMsgLoot` | an item recorded: name, quality, item level, source, confidence |
| `AHPrice` | `Collector:OnChatMsgLoot`; `AuctionPrice:GatherAll` | the prices gathered and picked for each recorded item; a provider fetch that raised, once per distinct provider and message through the console's `DebugOnce` gate, so a Clear or a fresh `debug on` re-arms it |
| `Drop` | `Collector:OnChatMsgLoot` / `OnChatMsgCurrency` | an item or currency not recorded, with the guard: `blacklist`, `quality`, `source`, `quest`, and for the player's own currency lines `recordCurrency-off` and `unresolved-link` |
| `Currency` | `Collector:OnChatMsgCurrency` | a currency recorded |
| `Attr` | `modules/Attribution.lua`; `modules/AttributionOut.lua` | a context stamp and its trigger; each consume, or `OTHER (INFERRED)` with no fresh context; encounter start and end; keystone start, completion, clear and re-arm; a hook's stamp `ignored: stood down`; for the ledger's loss side, an outbound stamp and its trigger (`stamp-out <reason> via <trigger>`, or `stamp-out <reason> ignored: stood down`) and an interaction frame opening or closing (`scope <name> open` or `closed`) |
| `Open` | `Attribution:OnLootOpened` / `OnContainerItemUse` | one summary per loot window (never per slot); a lootable bag item `ignored: spell targeting`. A bag item with no loot logs nothing: a merchant sale is one `UseContainerItem` per item |
| `Cast` | `Attribution:OnSpellSucceeded` | a deconstruct cast only, never the rest of the rotation |
| `Mail` | `Attribution:StampMail` | a mail attachment taken, with the AH-or-mail verdict |
| `UI` | `modules/Browser.lua`; `modules/Export.lua` | the window shown and hidden; a tab switch; an open refused (`stood down`, or `visibility=<mode>`); the window hidden by the visibility setting, on a combat edge or when the setting is written (an edge that changes nothing logs nothing); a CSV export, with the data set and the text's size |
| `Table` | `BrowserTable:Refresh` / `SetTestMode` | the render summary, **change-gated** through the console's `DebugChanged`: logged only when it differs from the last one logged, once again after each window open (`DebugForget`), and again after a Clear or a fresh `debug on`, which re-arm the console's gates. Test mode on (with the sample row count), off (with the reason, `combat started`), or refused with its reason |
| `Insights` | `Analytics:Refresh` | the recompute summary, **change-gated** the same way (`DebugChanged`, forgotten on each open, re-armed by a Clear): the live refresh on every coalesced `RecordAdded` stays quiet while the numbers do not move |
| `Filters` | `Filters:_notify` | each list edit, naming the act and id, with all three list sizes after it |
| `Cmd` | `LibKa0s-Slash-1.0` (minor 18), through the descriptor's `debug` in `settings/Slash.lua` | every refusal the dispatcher decides, after its chat line, `refused <verb>[ <arg>]: <guard>`: a feature verb while the addon is switched off (`disabled`), an unknown verb, `get` / `set` / `reset` usage, not found, parse or write refusal, a reset with no default, and the profile verb's `unavailable`, `already current`, `in combat` and `unknown profile`. A live verb that runs logs nothing |
| `Cfg` | `LibKa0s-Options-1.0` (minor 27); `runRebuilders`, `settings/Panel.lua` | the panel registration parked in combat and its `register flushed (combat ended)`, the open refused in combat, and opened; each write, Defaults, button, toggle, tab or id-list change the combat lock refuses, `<what> refused (in combat)`, once per text per combat; a list rebuilder that raised, once per distinct message (`DebugOnce`, re-armed by a Clear) |
| `Launcher` | `LibKa0s-Launcher-1.0` (minor 5) | registration, and the broker or minimap library missing, once at register; these are state lines on the descriptor's `debugAtEnable`, held for `debug on` because register runs at login with logging off |
| `Holdings` | `modules/Reconciler.lua`, `Flush` | `flush: <n> holder(s) changed`, once per flush that moved at least one holder; a flush that changed nothing writes nothing |
| `Diag` | `/lh diagnostics`; the console's **Diagnostics** link | the report (below), ungated; the run turns logging on first when it is off |

### Deliberately not logged

- **Other players' loot and currency lines.** `CHAT_MSG_LOOT` and `CHAT_MSG_CURRENCY` fire for the
  whole group; a line that is not the player's is not a decision this addon made, so it is parsed
  away before any guard (currency capture off included) gets to log it.
- **A partial trade accept, a non-deconstruct cast, a zone change that moves no keystone state.**
  Each fires often and changes nothing.
- **Each coalesced repaint trigger.** The held repaint is one timer per burst; its flush is the
  `[Table]` / `[Insights]` line, and a stand-down that cancels it is counted in the `[State]` line.
- **The login deferrals.** The five- and twenty-second prune and repair passes run with the flag off
  (it is session-only), so their `[Prune]` and `[Migrate]` lines land only when logging is already on.
- **Positions, sizes and the saved view.** Named non-setting state (`debug-logging-§10`).

## The diagnostics report

### Running it

There are exactly two forms, and no third:

- `/lh diagnostics`, a row of `NS.COMMANDS` in `settings/Schema.lua`, directly after `debug`;
- `/lh debug diagnostics`, the first word the `debug` handler tests, in any case.

Beside the two slash forms, the console's title bar carries the library's orange **Diagnostics** link,
just right of the **Debug: ON/OFF** toggle (DebugLog 16 and later). It is not a slash form: a click
runs `NS.DebugLog:RunDiagnostics()`, the same call both forms make.

`/loothistory` reaches both, as it reaches every verb. `diag`, `dump`, `dx` and every other short name
are ordinary unknown words: `/lh diag` prints `unknown command 'diag'` and the help index, and
`/lh debug diag` toggles the console window like any word the `debug` verb does not know.

`diagnostics` is on the library's live set (`lib.LIVE_VERBS`, restated as `LIVE_WHILE_DISABLED` in
`settings/Schema.lua`), so both forms answer while the addon is **disabled**. A disabled addon is
stood down, and the report says so where it matters rather than printing empty data (see `capture`
below).

### What it does to the console

- **It appends.** The report lands after whatever the console already holds, so the trace a player
  has just reproduced stays above it and one Copy carries both. Nothing the report reaches calls
  `Clear()`.
- **It turns logging on for the session.** When logging is off, the run first calls the flag's one
  seam, `NS.DebugLog:SetEnabled(true)` (debug-logging-§14, standard v2.71.0; DebugLogDiagnostics 2),
  as `/lh debug on` would: chat prints `[LH] debug logging ON`, the console gets `[Debug] logging
  enabled` and the `[Init]` line ahead of the begin marker, the report's
  header line reads `debug logging: on` and the console's toggle **Debug: ON**.
  What the player does next is traced. It never turns logging off, and with logging already on it
  writes no second enable line. A `/reload` turns it off again, as always. This addon keeps the
  library's default: its descriptor does not set `diagnosticsEnablesLogging = false`.
- **It is ungated.** It writes through the library's raw append, not `NS.Debug`. The sections only
  print the flag; only the run, before it writes, sets it.
- **It reveals the console** if it is hidden, then prints one chat line:
  `Diagnostic report written to the debug console: N lines. Use Copy to share it.`
- **It is plain text.** The library strips color, texture, atlas and hyperlink escapes from every
  line, so the Copy text reads cleanly. The history tail prints the item name the record stored,
  never its link.

The report body is English diagnostic text and does not go through `NS.L`, like every trace line.
The chat line after it is the library's localizable one.

### What it prints

The library writes the frame: the begin marker, its half of the identity header, each section under
its own `pcall`, the cap and the end marker. `modules/Diagnostics.lua` writes the sections in
between, in this order. Every line carries the `[Diag]` tag, the markers included, so a paste can be
cut out of a longer trace by tag alone.

| Section | What it reports |
|---|---|
| (begin) | `==== Ka0s Loot History diagnostics begin ====` |
| library header | The `[Init]` summary line (above); the client's version, build, date and interface from `GetBuildInfo()`; the locale; the logging flag; `InCombatLockdown` and `UnitAffectingCombat("player")`; the **running** LibKa0s minors, file by file, which under LibStub may come from another addon's vendored copy |
| identity | Brand, version and folder; the stored and code schema versions; the active profile, `profile: '<name>' (settings per profile; history account-wide)`; `enabled`, `stoodDown` and `testMode` |
| patterns | How many of the client globals the self-loot and self-currency patterns are built from are present, and which are missing; whether the roll-won global is present. Read by name, so no pattern set is built or cached by the report |
| lifecycle | The Lifecycle holds, whether the addon is stood down, and whether the latch is `LibKa0s-Lifecycle-1.0` or the local fallback |
| capture | Whether the Collector and Attribution are wired and how many events Attribution holds; while stood down, one line saying the loot, currency and context events are unregistered. Then the rejected events, the same list `/lh debug events` prints |
| settings | Every row that differs from its default, as `path = value (default)`, with a set-valued row shown as its sorted keys. `settings.enabled`, `settings.retentionDays` and `settings.auction.enabled` always print, whatever their value. Then the count printed |
| auction | Whether AH capture is on and how many keys it captures; the priority cascade as stored; which price providers are loaded (Auctionator, TSM, Oribos) |
| filters | The item blacklist, the whitelist and the currency blacklist: each list's size, then its ids in order |
| attribution | The stored loot context (source, its detail as `key=value` fields, confidence, seconds until it expires); the current encounter; the keystone level, or `none` |
| history | Record count with the oldest and newest timestamps; counts by source, confidence, quality, item type and bound state; distinct characters; how many records carry an AH price |
| tail | The newest 25 records, newest first: index, timestamp, stored name, id, quantity, quality, source, confidence, bound state, zone and character |
| bound repair | Whether the deferred bound-state repair is pending, its attempt count and its revision |
| browser | Whether the History window is built, shown and locked; the table's sort, grouping, match count and test-record count; the saved view's keys |
| launcher | Whether the launcher is present and whether the minimap button is hidden |
| pools | The History row pool's free and active counts, and how many Insights chart pools exist |
| (end) | `==== Ka0s Loot History diagnostics end: N line(s) ====`, with `N` counting both markers |

A section that raises costs one line, `section <name> failed: <err>`, and the rest of the report
still lands. On an install where `modules/Diagnostics.lua` failed to load, the report is the markers
and the library header around no sections.

### Caps

- **The whole report** stops at `lib.DIAG_MAX_LINES` (1200), which the library clamps to
  `lib.MAX_BUFFER - 100`, so the report never pushes itself out of the 3000-line buffer. The trace
  above it is kept on a best-effort basis.
- **Each id list** (the three filter lists, the rejected events) prints at most
  `lib.DIAG_MAX_PER_LIST` (40) entries and then `(+N more)`. A joined line wraps at 200 characters.
- **The history is aggregated, not listed.** Only the 25-record tail prints rows, so a history of any
  size costs the same few dozen lines.
- A capped report ends with `truncated: N line(s) omitted, per-list caps hit=yes|no`, then the end
  marker.

### What it does not do

- **It calls none of the slow or live item APIs.** No `GetItemInfo`, no `Compat.ScanBound`, no
  tooltip build and no `C_ChallengeMode`. Those can be slow, can raise on a secret, and can answer
  differently from when the record was written. The report says what the addon was working with, not
  what a fresh lookup says now. No raw loot or currency chat text is printed, because the addon never
  keeps any.
- **It writes nothing else.** Past the run turning session logging on (above), which the sections
  never do: no Lifecycle hold taken or released, no event registered, no timer armed, no
  cache rebuilt, no `Schema:Set`. The AH cascade is read raw rather than through
  `AuctionPrice:GetPriority()`, which would write an empty cascade into a store that has none.
- **It calls no protected API**, so it is safe in combat.
- **It does not do arithmetic on secret values.** Every value goes through `NS.SafeToString` before a
  format sees it, so a secret prints as `<secret>`, and the one computed number (the context's
  seconds left) is worked out only when both operands read as numbers; otherwise it prints `?`.
- **Nothing is redacted.** Players send the report to the maintainer privately, so it prints what a
  maintainer needs to reproduce the bug, character names included.

With no LibKa0s the stub's `RunDiagnostics` prints
`/lh diagnostics is unavailable: the LibKa0s library did not load.`, writes nothing, turns no logging
on and returns 0.
The degraded help does not offer `diagnostics`, because answering is not the same as working
([slash-dispatch.md](slash-dispatch.md)).

## Where else this is pinned

The command rows are in [slash-dispatch.md](slash-dispatch.md), the disabled-state behavior in
[disabled-state.md](disabled-state.md), and the player-facing steps in the README's
`## Reporting a bug`. The in-game checks are DIAG-1 to DIAG-33 and COMBAT-8 in [smoke-tests.md](smoke-tests.md). The
suites are `tests/test_diagnostics.lua` (this addon's sections), the kit's shared
`tests/_kit/test_diagnostics_contract.lua` (wired in `tests/run.lua`), `tests/test_disabled.lua`
(both forms while stood down) and `tests/test_slash_degraded.lua` (both forms with no library).
