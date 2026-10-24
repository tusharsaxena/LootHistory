# 01 — Findings (Ka0s Loot History, review of 2026-08-05)

**Verdict: minor issues.** The addon is coherent, well-layered and unusually well-documented at the
seams; every out-of-game suite is green today. One functional defect (F-001) can silently drop a
user-enabled price source out of every computed value, and one boot check that reads as validation
(F-002) cannot fire. Nothing here blocks a release; F-001 should land before the next one.

Standards cross-check: performed against **Ka0s WoW Addon Standard v2.21.0 (2026-08-04)**, fetched
from `raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master` (index + all 26 section
files).

---

## Measurement run (Step 0 — everything below was executed today, from the repo root)

| Suite | Command | Result |
|---|---|---|
| **luacheck** | `luacheck .` | **pass** — `Total: 0 warnings / 0 errors in 23 files`, exit 0 |
| **Headless tests** | `lua5.1 tests/run.lua` | **pass** — `579 passed, 0 failed, 579 total`, exit 0 |
| **Test-case inventory** | `lua5.1 tests/run.lua --list > <scratch>/list.txt` | **pass** — 668 lines; `diff` against `docs/test-cases.md` is **empty** |
| **Offline perf runner** | — | **skipped (no `tests/perf.lua` in this repo)**; no `docs/performance.md`, no captures under `docs/perf-runs/` (only its `README.md`). The addon wires four LibKa0s majors and **not** `Perf`, so there are no declared buckets and no brackets to check — see the note below. |
| **Complexity** | `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` | **pass** — `Warning cnt 0`; total NLOC 11367, 1518 functions, Avg NLOC 6.5, Avg CCN 2.2. **No function exceeds CCN 15.** |
| **`make test`** | — | **skipped (no `Makefile` in the repo)** |
| **Vendor sync** | not run as a standalone `diff` | **covered by the suite** — `tests/test_vendor_sync.lua` compares `libs/LibKa0s/` and `tests/_kit/` byte-for-byte against `git show v1.7.0:…` in the sibling `../LibKa0s` checkout (present on this machine); both cases passed. A standalone `diff -r` into the sibling repo was **not** run: this review is scoped to a single repository. See F-005 for what those two cases do when the sibling is absent. |

**Every function at CCN 15 in today's run** (the cap, none above it), for the record:

```
15  E@39-159@./modules/Export.lua                 (the block lizard attributes to E:WowheadLink)
15  Compat.ScanBound@271-291@./core/Compat.lua
15  BrowserTable@968-1005@./modules/BrowserTable.lua   (UpdateHeaderArrows)
15  BrowserTable@866-883@./modules/BrowserTable.lua    (BindRow)
15  BrowserTable@550-598@./modules/BrowserTable.lua    (GroupRecords)
15  Attribution@173-196@./modules/Attribution.lua      (OnLootOpened)
```

Next below the cap: `matchRange` 14 (`core/Database.lua:356`), `Collector@160-206` 14
(`modules/Collector.lua`), then four at 13.

**Committed artifacts vs. today's run — no disagreements.**

- `docs/test-cases.md` — **current**. Byte-identical to a fresh `--list`. Totals agree with the run
  (579) and with the README `[Tests]` badge (`README.md:7`, `Tests-579%2F579_passing`).
- `docs/automated-tests/RESULTS.md` — **current**. Its newest row (`20260804-233322`, addon 1.2.0)
  claims lint 0/0 over 23 files, tests 579/579, perf `skip`, NLOC 11367, 1518 funcs, avg CCN 2.2,
  max CCN 15, 0 CCN warnings. Every one of those reproduced exactly. Its watch list ("**None.** No
  function in this addon exceeds CCN 15", and the six named functions sitting on the cap) matches
  the fresh run function-for-function and line-for-line.
- `docs/automated-tests/20260804-233322/manifest.json` stamp: `git.sha 8f4e7aaf…`, `branch
  feat/fix-ccn`, `dirty true`. The tree is clean at `1c19181`-equivalent state today; the numbers
  still reproduce, so the report is dated but not stale.
- `docs/performance.md` — does not exist; nothing to compare.

**A note on what the perf skip costs this review.** `RESULTS.md`'s own Perf paragraph is accurate:
the record says nothing about this addon's runtime cost, and `performance-§9`'s zero-overhead
evidence does not exist for it. Because the addon adopts no `Perf` major there are no declared
buckets to cross-check against brackets, and no bracket-hygiene defects to find — the check is
vacuous rather than failed. Consequently **every performance claim in this document is by
inspection and is marked unverified**; F-009 in particular has no measurement behind it.

In-client checks (taint under combat, locale rendering, `/reload` migration, the `/lh` capture
protocol) are deliberately absent here — they are in `03_SMOKE_TESTS.md`.

---

## High

### F-001 — A price key enabled from the CLI is collected but can never be picked `[bug]` `[design]`

- **Where:** `defaults/Global.lua:36-39` vs `core/Constants.lua:147-153`; consumed at
  `modules/AuctionPrice.lua:88-98` (`Pick`) and `modules/AuctionPrice.lua:49-55` (`cfg`).
- **Problem:** the AH-price *priority* cascade is declared twice. `defaults/Global.lua` hard-codes a
  **7-entry** array; `core/Constants.lua`'s `C.AUCTION_PRIORITY_DEFAULT` declares **11** (the same
  seven plus `tsm:dbhistorical`, `tsm:dbrecent`, `tsm:dbregionhistorical`, `tsm:dbregionsaleavg`).
  AceDB seeds `db.global.settings.auction.priority` from the *defaults* file, so a fresh install
  stores seven. `AuctionPrice:Pick` walks exactly that stored array.
- **Impact:** a user who enables one of the four missing keys with `/lh set
  settings.auction.capture …` — i.e. without opening the AH Price settings page, which is the only
  caller of `ReconcilePriority` (`settings/Panel.lua:431`) and therefore the only thing that repairs
  the array — gets that price **gathered and stored** (`GatherAll`, `AuctionPrice.lua:70-83`) but
  **never selected**: `Pick` returns nil for it, so the Value column, `NS.Util.RecordValue`, the
  Insights value charts and the CSV `value`/`auctionPrice`/`auctionSource` columns all behave as if
  the price does not exist. Only the raw `auc_<provider>_<key>` CSV column shows it. Silent, no
  error, and self-healing the moment the user happens to open the AH Price page — which is the worst
  shape a bug can take for reproduction.
- **Coverage:** the suite has a case for exactly this class of drift —
  `tests/test_schema.lua:140-148`, *"the shipped default equals the schema's declared default"* —
  but it guards `row.type ~= "table"`, which excludes both table rows, and `priority` is a
  documented carve-out with no schema row at all. So the one drift that exists is in the one place
  the check does not look. This is a coverage gap under a High finding, not an asleep test.
- **Fix direction:** make `core/Constants.lua` the single declaration and have `defaults/Global.lua`
  reference it (`savedvariables-§2`: defaults **MUST** be the only place a default is hard-coded,
  and schema rows reference those constants). Do **not** "fix" it by calling `ReconcilePriority`
  from `InitDB` — that hides the duplication instead of removing it.

---

## Medium

### F-002 — `Schema:Register`'s boot validation cannot fire `[bug]` `[tests]`

- **Where:** `settings/Schema.lua:189-198`, condition at `:194`.
- **Problem:** the guard is
  `if not row.sessionOnly and S:ReadPath(g, row.path) == nil and row.default == nil then`. Every row
  in `S.Schema` declares a non-nil `default`, so the third conjunct is false for every row and the
  `print("schema path missing default: …")` on `:195` is unreachable. The comment on `:188` —
  *"Boot validation: every schema path must resolve against the defaults table"* — describes an
  `or`, not the `and` that shipped.
- **Impact:** the addon's only runtime defence against a schema path with no entry in
  `defaults/Global.lua` is dead. It is the check that would have surfaced F-001's family of drift on
  a live client.
- **Coverage:** `tests/test_schema.lua:130-138` asserts the *intended* rule directly against
  `NS.defaults.global` and passes, which is precisely why the dead branch has stayed invisible — the
  suite proves the invariant holds, not that `Register` checks it.
- **Fix direction:** `and` → `or` on the `row.default == nil` clause (a path missing from defaults
  is a defect whether or not the row carries its own default), and keep the test as the gate.

### F-003 — The bus-target fallback re-introduces the receiver clobber the standard names `[design]`

- **Where:** `modules/Collector.lua:494` (`self.__ev = NS.NewBusTarget() or bus`) and
  `modules/Browser.lua:1366` (`B.__ev = NS.NewBusTarget() or NS.bus`).
- **Problem:** `NS.NewBusTarget()` (`core/LootHistory.lua:22-28`) returns nil when
  `LibStub("AceEvent-3.0", true)` fails. Both call sites then fall back to **the shared bus object**,
  and both register `Ka0s_LootHistory_SettingsChanged` on it. CallbackHandler keys callbacks by
  `(message, target)`, so the later registrant wins — and `addon:OnEnable`
  (`core/LootHistory.lua:44-47`) enables `Attribution`, then `Collector`, then `Browser`, so
  `Browser:OnSettingsChanged` silently replaces `Collector:RefreshUpvalues`. The collector would then
  never re-read `enabled` / `qualityThreshold` / `excludedSources` after a settings change.
- **Impact:** latent — AceEvent is vendored and TOC-loaded, so the branch is unreachable in a normal
  install. It is nonetheless the exact shape `anti-patterns #32` / `architecture-§4` forbid, sitting
  in the file that documents the rule three lines above it, and it is one bad `libs/` extraction away
  from being live. `settings/Panel.lua:130-138` and `:325-334` handle the identical case correctly
  by registering **nothing** when the factory returns nil.
- **Fix direction:** drop the `or bus` / `or NS.bus` tail at both sites and follow the Panel's shape.

### F-004 — Two different "Reset All"s, one of which purges the history `[ux]`

- **Where:** `settings/Panel.lua:633-643` (button labeled `"Reset All"`, wired to
  `KA0S_LOOTHISTORY_RESETALL`, `settings/Slash.lua:19-26`, whose `OnAccept` runs
  `Sl:ResetEverything` → `Database:Purge`) vs `settings/Schema.lua:223`
  (`{ "resetall", "Reset all settings", … }` → `Sl:CliResetAll`, which never touches history).
- **Problem:** the same two words name a settings-only reset in chat and a
  settings-**plus-every-recorded-row** wipe in the panel. `slash-commands-§3` reserves `resetall`'s
  meaning across the whole collection, so the CLI is right and the button's label is the drift.
- **Impact:** a user who has learned one surface will mis-predict the other. The panel path is
  confirm-gated so the damage is recoverable at the dialog, but the dialog is the *first* place the
  difference is disclosed.
- **Fix direction:** relabel the panel button to something that names the wipe (e.g.
  `"Reset Everything…"`, ellipsis for the confirm) and leave `/lh resetall` exactly as it is.

### F-005 — Two vendor-sync cases pass with zero assertions when the sibling repo is absent `[tests]`

- **Where:** `tests/test_vendor_sync.lua:138-142` and `:144-150`; the escape is
  `local tag = siblingTag(); if not tag then return end`, with `siblingTag` returning nil at `:111`.
- **Problem:** on any machine without `../LibKa0s` — a CI runner, a fresh clone, a packaging box —
  both cases execute no assertion and print `PASS`. The file's own header says *"A missing sibling
  is the ONE case where this pair may go quiet, and it is said in the case name rather than
  hidden"* (`:107-109`), but neither case name mentions the sibling or the skip: they read
  *"libs/LibKa0s is the LibKa0s release the README says this addon bundles"*.
- **Impact:** two of the 579 green cases can be green for a reason the inventory does not disclose,
  and the thing they guard (`anti-patterns #45`, a drifted vendored copy) is the one failure mode
  that is silent in both repos. On **this** machine the sibling is present and both cases really did
  compare against `v1.7.0` (`README.md:166`), so today's green is real.
- **Fix direction:** say it in the name — e.g. *"…, when the sibling LibKa0s checkout is present"* —
  and print the skip reason. Do not delete or weaken the assertions.

### F-006 — Only the Core degradation stub is checked against its call sites `[design]` `[tests]`

- **Where:** `tests/test_libka0s.lua:90-102` (*"the Core stub answers every member the addon
  calls"*), with no counterpart for DebugLog / Options / Slash.
- **Problem:** two concrete symptoms of the missing check. (a) `settings/Slash.lua:138-149` — the
  degraded branch publishes `FormatKV`, `HelpRows`, `LandingRows`, `BuildListLines`, `PrintHelp`,
  the five `Cli*`, `CliResetAll`, `OnSlash` and `Register`, but **not** `HelpHeader`, which the live
  path does export at `settings/Slash.lua:210`. (b) `core/DebugLogSetup.lua:84-91` stubs
  `ConsoleCheckbox`, a member no addon file calls any more — the console checkbox is the
  `state.debugConsole` schema row (`settings/Schema.lua:43-50`).
- **Impact:** small today — `HelpHeader` has no non-test caller, so the omission is currently a
  crash that nothing reaches, and `ConsoleCheckbox` is stub-only surface that will go stale
  unnoticed. But the *asymmetry* is the finding: the stub/live surfaces are kept in step by hand for
  three of the four adopted majors.
- **Fix direction:** generalize the Core case into one that diffs each stub's key set against the
  members grepped out of the addon's own `.lua` files, and add `HelpHeader` to the Slash stub / drop
  `ConsoleCheckbox` from the DebugLog stub as that case dictates. Do **not** re-implement any library
  behavior in a stub (`anti-patterns #47`).

---

## Low

### F-007 — Two comments name a reader that does not exist `[naming]`

`settings/Slash.lua:111-112` (*"Kept as a public member because settings/Panel.lua and the suite both
read it"*) and `:165-167` (*"Re-exported so settings/Panel.lua and the suite reach ONE key/value
formatter"*). `settings/Panel.lua` references neither `FormatSchemaValue` nor `FormatKV` — grep over
`core/ modules/ settings/` returns only `settings/Slash.lua` itself. The suite is the sole reader of
`FormatKV`, `HelpHeader`, `HelpRows` and `BuildListLines`. Fix direction: correct the comments (the
justification is "the suite pins the one formatter", which is still a good reason to keep them).

### F-008 — A stale lint suppression `[lint]`

`modules/AuctionPrice.lua:1` carries `-- luacheck: ignore addonName` for a variable that **is** used,
at `:17` and `:18` (Auctionator's API takes the caller's addon name). `modules/Export.lua:1` and
`modules/Filters.lua:1` carry the same comment legitimately. Suppressing a warning that no longer
occurs is the shape that later hides a real one. Verified against today's clean `luacheck .` run —
removing it does not redden lint.

### F-009 — Per-character stack segments are computed twice `[perf]` *(unverified — no perf harness)*

`modules/Analytics.lua:176-197`: `_buildCharStackRows` calls `_charStackSegments` once per character
in the totals pass (`:180`) and again per character in the rows pass (`:185`). Each call allocates a
list, sorts it, allocates a rank table and sorts again (`:150-169`). On the Insights tab this runs
per stacked companion chart per refresh. It is not a hot path (render-on-demand, not per frame), so
this is a tidy-up rather than a fix; `lizard` flags the function at CCN 13, below the cap. There is no
measurement behind this — the addon ships no `tests/perf.lua`.

### F-010 — A degraded install cannot discover the verbs that still work `[ux]`

`settings/Slash.lua:150-157`: with LibKa0s absent, a bare `/lh` matches no entry in `NS.COMMANDS` and
falls through to `unavailable()`. The seven host verbs (`show`/`hide`/`toggle`/`config`/`debug`/
`test`/`purge`) still function — the file's own comment at `:132-134` says so — but nothing lists
them. Fix direction: have the fallback print the host verbs from `NS.COMMANDS` alongside the cause
clause; keep the clause verbatim (`tests/test_libka0s.lua:30-34` pins it).

---

## Not findings — checked and clean

Recorded so the next reviewer does not re-walk them: no `OnUpdate` handlers anywhere in the addon's
own code; every `SetBackdrop` target is created with `"BackdropTemplate"` (including the frame handed
to `B:ApplySkin` by the DebugLog seam); every deprecated global (`GetSpellInfo`, `GetAddOnMetadata`,
`UseContainerItem`) is presence-gated behind `core/Compat.lua`; every secure hook is
`hooksecurefunc`; no raw `print(` bypasses the file-scope `local print = NS.Print` shadow; all six
`StaticPopupDialogs` keys are reachable; `tests/run.lua:30` derives the addon's own load list from the
TOC via `Loader.tocFiles` and spells out the eight `LibKa0s.xml` files explicitly at `:17-26`, with
`tests/test_libka0s.lua:209-220` pinning the two lists against each other; the suite list and
`tests/test_*.lua` on disk agree exactly in both directions.
