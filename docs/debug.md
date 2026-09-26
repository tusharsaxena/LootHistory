# Debug surfaces

Loot History has two debug surfaces, and both write into the same window:

- **The debug console** is `LibKa0s-DebugLog-1.0`'s window. Tagged `NS.Debug` lines land there while
  the session flag is on.
- **The diagnostics report** is a one-shot snapshot of the addon's state, written into the console
  by `/lh diagnostics` (`debug-logging-§14`). It is why this page exists (`documentation-§3`, Tier 2):
  every Ka0s addon ships the report, and a maintainer reading a pasted one needs to know what each
  line means.

The console itself is the library's, and its contract lives in LibKa0s's
[`docs/api/DebugLog/version-14.1-docs.md`](https://github.com/tusharsaxena/LibKa0s/blob/master/docs/api/DebugLog/version-14.1-docs.md)
(DebugLog 14.1 is the vendored minor, from LibKa0s v1.60.0). This page covers only what Loot History
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

The tags in use, and the checks that each one fires once rather than once per row, are in
[smoke-tests.md §15](smoke-tests.md#15-debug-console-coverage). On an install without LibKa0s the
flag still works and `on` / `off` still confirm, but the window is gone and the stub says so.

## The diagnostics report

### Running it

There are exactly two forms, and no third:

- `/lh diagnostics`, a row of `NS.COMMANDS` in `settings/Schema.lua`, directly after `debug`;
- `/lh debug diagnostics`, the first word the `debug` handler tests, in any case.

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
- **It is ungated.** It writes through the library's raw append, not `NS.Debug`, so it lands in full
  with logging off, and it does not read or change the flag: the header reads the same afterwards.
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
| identity | Brand, version and folder; the stored and code schema versions; `profile: account-wide` (everything lives under `db.global`); `enabled`, `stoodDown` and `testMode` |
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
- **It writes nothing.** No Lifecycle hold taken or released, no event registered, no timer armed, no
  cache rebuilt, no `Schema:Set`. The AH cascade is read raw rather than through
  `AuctionPrice:GetPriority()`, which would write an empty cascade into a store that has none.
- **It calls no protected API**, so it is safe in combat.
- **It does not do arithmetic on secret values.** Every value goes through `NS.SafeToString` before a
  format sees it, so a secret prints as `<secret>`, and the one computed number (the context's
  seconds left) is worked out only when both operands read as numbers; otherwise it prints `?`.
- **Nothing is redacted.** Players send the report to the maintainer privately, so it prints what a
  maintainer needs to reproduce the bug, character names included.

With no LibKa0s the stub's `RunDiagnostics` prints
`/lh diagnostics is unavailable: the LibKa0s library did not load.`, writes nothing and returns 0.
The degraded help does not offer `diagnostics`, because answering is not the same as working
([slash-dispatch.md](slash-dispatch.md)).

## Where else this is pinned

The command rows are in [slash-dispatch.md](slash-dispatch.md), the disabled-state behavior in
[disabled-state.md](disabled-state.md), and the player-facing steps in the README's
`## Reporting a bug`. The in-game checks are §12 and §12a in [smoke-tests.md](smoke-tests.md). The
suites are `tests/test_diagnostics.lua` (this addon's sections), the kit's shared
`tests/_kit/test_diagnostics_contract.lua` (wired in `tests/run.lua`), `tests/test_disabled.lua`
(both forms while stood down) and `tests/test_slash_degraded.lua` (both forms with no library).
