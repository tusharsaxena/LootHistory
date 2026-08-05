# 03 — Evidence

Every claim in `01_CURRENT_STATE.md` and `02_DEVIATIONS.md` is sourced here. Mechanical checks were
**run**, from the repo root, and their real output is recorded — never inferred from the code
looking reasonable, never quietly skipped. Checks that could not run say so.

Repo: `/mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory`, HEAD `48471ef`, working tree clean
apart from the untracked `docs/reviews/2026-08-05/` and this bundle.

---

## A. Mechanical checks

### A1. Lint — RUN, pass

```
$ luacheck .
…
Checking settings/Panel.lua                       OK
Checking settings/Schema.lua                      OK
Checking settings/Slash.lua                       OK

Total: 0 warnings / 0 errors in 23 files
```

Agrees with `docs/automated-tests/20260804-233322/manifest.json`
(`"lint": { "status": "pass", … "warnings": 0, "errors": 0, "files": 23 }`) and with `RESULTS.md`'s
newest row. The 23 files are the shipped source only — `.luacheckrc:4` excludes `libs/`,
`docs/audits/`, `docs/reviews/`, `_dev/` and `tests/`.

### A2. Headless suite — RUN, pass

```
$ lua5.1 tests/run.lua
…
  PASS  libs/LibKa0s is the LibKa0s release the README says this addon bundles
  PASS  tests/_kit is the test kit that shipped with that release

579 passed, 0 failed, 579 total
```

Agrees with the manifest (`"tests": { "status": "pass", "passed": 579, "failed": 0, "total": 579 }`),
with `RESULTS.md`'s newest row, and with the README badge `Tests-579%2F579_passing`
(`README.md:7`) — `testing-§5`'s lockstep rule holds.

Caveat, and it is the substance of **LH-40**: the last two `PASS` lines above are
`tests/test_vendor_sync.lua`'s, and those two cases return without asserting anything when
`../LibKa0s` is absent (`tests/test_vendor_sync.lua:110-116,139-141,145-147`). A `PASS` from them
is therefore not by itself evidence that the vendored copies match.

### A3. Complexity — RUN, verbatim invocation, **zero drift**

```
$ lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .
…
No thresholds exceeded (cyclomatic_complexity > 15 or length > 1000 or nloc > 1000000 or parameter_count > 100)
Total nloc   Avg.NLOC  AvgCCN  Avg.token   Fun Cnt  Warning cnt   Fun Rt   nloc Rt
     11367       6.5     2.2       53.7     1518            0      0.00    0.00
```

`lizard 1.23.0`. The invocation is the standard's, character for character — no added flag, no
narrowed path, no re-tuned threshold — which is the only thing that makes the numbers comparable
with the committed report.

**Comparison against the latest run bundle** (`docs/automated-tests/20260804-233322/`, stamped
`2026-08-04T23:33:22+05:30`, roughly two hours before this audit):

| Figure | This run | `20260804-233322/complexity.txt` + `manifest.json` | Drift |
|---|---|---|---|
| Total NLOC | 11367 | 11367 | none |
| Functions | 1518 | 1518 | none |
| Avg NLOC/fn | 6.5 | 6.5 | none |
| Avg CCN | 2.2 | 2.2 | none |
| Max CCN | 15 | 15 | none |
| Warnings (CCN > 15) | **0** | **0** | none |
| Files over the 1500 cap | 0 | `"overCapFiles": 0` | none |
| Files in the 1000–1500 band | 3 | `"bandFiles": 3` | none |

**No function has crossed a `lizard` threshold and no file has entered the on-notice band since the
recorded run.** The record is current, not stale — anti-pattern #51 is clear. It is also not
hand-edited: `RESULTS.md` explains at length why the `Max CCN` column reads `58 → 0 → 15` across the
three runs (a reader fault in a pre-rev-6 testkit) and **leaves the generated rows exactly as the
tool wrote them**, which is the correct response to a wrong number in a generated file.

The three band files, measured this run by `wc -l`: `modules/Browser.lua` 1372,
`modules/Analytics.lua` 1180, `modules/BrowserTable.lua` 1097 — matching `RESULTS.md`'s band table
to the line.

**Watch-list discipline** (`automated-tests-§4`, anti-patterns #53): the warned-function list reads
`**None.**` — a result, correctly written out rather than dropped — so there are **zero** entries
carrying an `accepted` disposition, and no entry can have carried one across three consecutive
release runs. The band table's three entries are dispositioned *"Already tracked as `LH-31`"*,
*"Peel next — now unblocked"* and *"Accepted"*; the first of those is **LH-37**. Also worth stating
for how the numbers should be read: the six functions sitting **at** the cap (`E@39-159`,
`BrowserTable:GroupRecords` 550, `BrowserTable:BindRow` 866, `BrowserTable:UpdateHeaderArrows` 968,
`Attribution:OnLootOpened` 173, `Compat.ScanBound` 271) are dense **defaulting and guarding** — the
`and`/`or` tax `performance-§10` describes — not tangled control flow, and none of them warns.

### A4. The automated-test artifact itself — RUN

- Runner vendored and executable: `-rwxrwxrwx … tests/_kit/run-automated-tests.sh` (mode `0755`,
  under `tests/`, **not** `libs/` — `testing-§1`).
- `.gitattributes:36` — `*.sh   text eol=lf`, with the reason written out at `:31-35`
  (`automated-tests-§2`). ✅
- `docs/automated-tests/README.md` ✅ and `docs/automated-tests/RESULTS.md` ✅ both exist.
- `RESULTS.md` is one file, overwritten in place, one row per run, carrying lint warnings/errors and
  file count, tests passed/total, perf status, and complexity **totals and averages both**
  (`automated-tests-§4`). ✅
- Three frozen bundles, each with `manifest.json`, `ANALYSIS.md`, `lint.txt`, `tests.txt`,
  `test-cases.md`, `complexity.txt`. No pruning. ✅
- **Retired `docs/complexity.md`:** `git ls-files | grep complexity.md` returns nothing.
  **Correctly absent** (the v2.19.0 finding does not apply here); `docs/testing.md:180-181` records
  the retirement.
- The `perf` suite is `"status": "skip", "skipReason": "no tests/perf.lua — this addon ships no
  offline scenarios"` in every bundle — a skip recorded with its reason, which
  `automated-tests-§3` requires and which is **not** a pass (LH-24, LH-36).

### A5. Vendored Ka0s-owned library drift — **NOT RUN**

The playbook's `diff -r <LibRepo>/<Lib> <Addon>/libs/<Lib>` check was **not run**. This run was
invoked with an explicit single-repo constraint forbidding any read of, write to, or execution
inside a sibling repository under `…/GIT/`, and both halves of the check require reading
`../LibKa0s`:

- `diff -r ../LibKa0s/LibKa0s libs/LibKa0s` — **not run** (sibling out of scope).
- `diff -r ../LibKa0s/testkit tests/_kit` — **not run** (sibling out of scope).

Recorded as **unverified**, never as a pass. Anti-pattern **#45 is therefore unverified this run**.
What is on the record instead, and what it is worth:

- The addon carries its own in-suite equivalent, `tests/test_vendor_sync.lua`, which compares both
  directories against the LibKa0s **tag** the README names — asserting the file **set** first
  (`:121-125`) and then byte content per file (`:126-135`), `README.md` included. Both cases ran
  green in A2.
- But those cases go quiet rather than red when the sibling is absent (`:110-116`, `:139-141`,
  `:145-147`), so their green cannot be distinguished from "could not look". That is **LH-40**, and
  it is why this section says *unverified* rather than *covered by the suite*.
- The prior audit (`docs/audits/2026-08-04/02_DEVIATIONS.md`, "Notes on scope") records both diffs
  empty against `../LibKa0s` at `v1.7.0`, which `README.md:166` still names as the bundled version.
  That is a **prior** measurement, not this run's.

The file inventory of `libs/LibKa0s/` was checked directly and holds all ten shipped paths —
`Core.lua`, `DebugLog.lua`, `Options.lua`, `OptionsScroll.lua`, `OptionsWidgets.lua`, `Perf.lua`,
`PerfPanel.lua`, `Slash.lua`, `LibKa0s.xml`, `LICENSE` — including both files of the Options major
and both of the Perf major the addon does not wire. **No file is missing on the addon side**, which
is the specific evidence anti-pattern **#48** would need; #48 is clear.

---

## B. The LibKa0s seams — descriptor, stub, and stub coverage

Per `AUDIT.md` step 6, evidence for a shared-subsystem finding cites the **descriptor**, not the
behavior, and never the library's own source.

| Module | Silent resolution | Descriptor | Stub branch |
|---|---|---|---|
| Core | `core/CoreSetup.lua:32` `LibStub and LibStub("LibKa0s-Core-1.0", true)` | `:97` `lib:New({ prefix = NS.PREFIX })` | `:41-84` |
| DebugLog | `core/DebugLogSetup.lua:24` | `:74-131` | `:26-72` |
| Slash | `settings/Slash.lua:103` | `:196-217` | `:129-162` |
| Options | `settings/OptionsSetup.lua:37` | `:68-116` | `:39-66` |
| Perf | — | — | — (LH-20) |

Every one uses the silent `true` flag and guards on the result; none uses a bare `LibStub(major)`.
The shared cause clause is set **outside** the `if not lib` branch at `core/CoreSetup.lua:38-39`, so
a degraded install and a healthy one give the same explanation of *why*.

### B1. Stub coverage — measured by grepping the call sites

Members reached on each instance by the **shipped** source (`core/`, `defaults/`, `modules/`,
`settings/`), versus what the library-absent branch answers:

- **Core** — call sites reach `NS.Print`, `NS.Format`, `NS.SafeToString`, `NS.IsConcatSafe`,
  `NS.Util.print`. Stub answers all five (`core/CoreSetup.lua:67-82`). ✅ Pinned by
  `tests/test_libka0s.lua:88-100`.
- **DebugLog** — call sites reach `Debug`, `Show`, `Hide`, `IsShown`, `Toggle`, `SetEnabled`. Stub
  answers all six plus twelve more (`core/DebugLogSetup.lua:31-71`). ✅ `SetEnabled` deliberately
  still flips the host's session flag (`:52-61`) — a decision, with the reason written down.
- **Slash** — call sites reach `CliGet`, `CliList`, `CliReset`, `CliResetAll`, `CliSet`,
  `CliVersion`, `LandingRows`, `PrintHelp`, `Register`, `ResetEverything`. The stub answers all of
  them (`settings/Slash.lua:139-162`); `ResetEverything` is host-owned above the seam. ✅ The live
  path additionally exports `Sl.HelpHeader` (`:210`) which the stub does not — reached only by
  `tests/test_slash.lua:212,233,323`, never by shipped code. That asymmetry is **LH-39**, raised as
  a SHOULD rather than a MUST for exactly that reason.
- **Options** — call sites reach `O.AddSpacer`, `O.BUTTON_PAIR_REL`, `O.ClearScroll`,
  `O.CreateOptionsPanel`, `O.CreatePanel`, `O.EnsureDefaultsButton`, `O.EnsureScroll`,
  `O.OpenOptionsPanel`, `O.RefreshScalars`, `O.RegisterOptionsPage`, `O.RenderField`, `O.RenderRows`,
  `O.RenderSchema`, `O.SECTION_HEADING_H`, `O.Section`, `O.SetRenderer`. Every one is present in the
  stub (`settings/OptionsSetup.lua:45-64`). ✅ The stub is **load-completing rather than
  member-answering** — `options-ui-§1`'s documented exception — and is **not** flagged.

The degraded path is verified by **actually loading the addon without the library**
(`tests/test_libka0s.lua:51-58`, `loadDegraded()` over a fresh mock set), not by hand-stubbing a
namespace member — which is what `testing-§8` requires. Coverage of that path stops at Core, which
is **LH-39**'s other half.

---

## C. Per-deviation evidence

### LH-19 — retired `§N.M` citations (`documentation-§5`)

```
settings/OptionsSetup.lua:101:  -- Ka0s standard §3.4: one LibStub resolution, stashed for every page file to reuse.
tests/test_database.lua:390:-- ── RunMigrations: the schema-migration seam (Ka0s Standard §2.2/§5.1) ─────────────
```

A repo-wide grep for `§<digit>.<digit>` over `core defaults modules settings locales tests` returns
exactly these two. Every other citation in the source is already `filename-§N`.

### LH-20 — Perf not wired (`performance-§1`)

- `git ls-files core/` lists `Compat.lua`, `Constants.lua`, `CoreSetup.lua`, `Database.lua`,
  `DebugLogSetup.lua`, `LootHistory.lua`, `Namespace.lua`, `State.lua`, `Util.lua` — **no
  `PerfSetup.lua`**.
- A grep for `NS.Perf` over `core modules settings` returns nothing.
- The module is vendored (`libs/LibKa0s/Perf.lua`, `libs/LibKa0s/PerfPanel.lua`) and loaded by the
  runner (`tests/run.lua:24-25`), so this is non-adoption, not non-vendoring.
- The decision is recorded: `docs/pending/LEDGER.md`, row `LIBKA0S-17`, `🔵 wont-do`, dated
  2026-08-01, with two stated reasons (no hot path; `suspend` would drop real loot) and the explicit
  note *"`LootHistoryPerfDB` is deliberately NOT declared in the TOC."*

### LH-21 — one SavedVariables global (`toc-file-§2`)

`LootHistory.toc:7` → `## SavedVariables: LootHistoryDB`.

### LH-22 — no `perf` verb (`slash-commands-§2`, `performance-§4`)

`settings/Schema.lua:213-245` — `NS.COMMANDS` holds `show`, `hide`, `toggle`, `config`, `version`,
`get`, `set`, `list`, `reset`, `resetall`, `debug`, `test`, `purge`, `help`. Fourteen entries, all
positional triples, no `perf`. `README.md:73-87` mirrors the same fourteen, so the two are in
lockstep and both are missing the same verb.

### LH-23 — no suspend/resume (`performance-§6`)

No `suspend` or `resume` member exists anywhere under `core/`, `modules/`, `settings/`; there is no
Perf descriptor to carry one (LH-20). `docs/pending/LEDGER.md` `LIBKA0S-17` states the objection
directly: suspending this addon means not recording the loot that drops during window B.

### LH-24 — no `tests/perf.lua` (`performance-§9`, `automated-tests-§3`)

`git ls-files tests/` lists `_kit/…`, `run.lua`, `wow_mock.lua` and eighteen `test_*.lua` suites —
**no `perf.lua`**. Every bundle's manifest carries
`"perf": { "status": "skip", …, "skipReason": "no tests/perf.lua — this addon ships no offline
scenarios", "gating": false }`.

### LH-25 — `docs/performance.md` missing (`documentation-§3`)

The five required topic-detail docs, checked against `git ls-files docs/`:

| Doc | State |
|---|---|
| `docs/test-cases.md` | ✅ present, generated, CRLF-pinned at `.gitattributes:24-29` |
| `docs/performance.md` | ❌ **absent** |
| `docs/perf-runs/README.md` | ✅ present (new since the last audit) |
| `docs/automated-tests/README.md` | ✅ present |
| `docs/automated-tests/RESULTS.md` | ✅ present |

### LH-26 — `.luacheckrc` perf entries (`lint`, `performance-§2/§5`)

`.luacheckrc:20-58` `read_globals` — no `debugprofilestop`. `.luacheckrc:59-62` `globals` — only
`LootHistoryDB` and `StaticPopupDialogs`; no `LootHistoryPerfDB`.

### LH-27 — dead `ctx.dirty` (`options-ui-§11`)

```
settings/Panel.lua:146:  ctx.dirty = false
settings/Panel.lua:329:        if ctx.panel:IsShown() then runRebuilders(ctx) else ctx.dirty = true end
```

Those are the **only** two occurrences of `ctx.dirty` in the addon; a grep over `settings/` and
`modules/` for `dirty` returns them plus three comment lines (`:141`, `:306`, `:323`, `:659`). No
read site exists. The library's own gate is `_dirty`, which no host file writes.

### LH-28 — defaults declared twice (`savedvariables-§2`)

| Setting | `defaults/Global.lua` | `settings/Schema.lua` |
|---|---|---|
| `settings.enabled` | `:21` `true` | `:25` `default = true` |
| `settings.qualityThreshold` | `:22` `1` | `:61` `default = 1` |
| `settings.excludeQuestItems` | `:23` `true` | `:85` `default = true` |
| `settings.recordCurrency` | `:24` `true` | `:77` `default = true` |
| `settings.retentionDays` | `:26` `30` | `:70` `default = 30` |
| `settings.windowScale` | `:27` `1.0` | `:52` `default = 1.0` |

The compliant counter-example is in the same file: `settings/Schema.lua:109` reads
`default = NS.Constants.AUCTION_CAPTURE_DEFAULT`.

### LH-34 — the AH priority cascade has drifted (`savedvariables-§2`, `architecture-§5`)

`defaults/Global.lua:36-39` — **7** tags:

```lua
priority = {  -- ordered provider:key selection list (carve-out; reordered via the panel UI)
  "tsm:dbmarket", "auctionator:minbuyout", "oribos:market",
  "tsm:dbminbuyout", "tsm:dbregionmarketavg", "tsm:dbregionminbuyoutavg", "oribos:region",
},
```

`core/Constants.lua:146-153` — **11** tags, the same 7 plus `tsm:dbhistorical`, `tsm:dbrecent`,
`tsm:dbregionhistorical`, `tsm:dbregionsaleavg`, under the comment `-- default-uncollected last`.
`C.AUCTION_CAPTURE_DEFAULT` (`:141-145`) and `defaults/Global.lua:31-35` still agree at 7 entries
each, so the drift is confined to the ordering list — which is the one `AuctionPrice:Pick` walks.
`tests/test_schema.lua:140-148` guards `row.type ~= "table"`, and `settings.auction.priority` has no
schema row at all, so nothing in the suite compares the two.

### LH-35 — bus fallback to the shared object (`architecture-§4`, #32)

```
modules/Collector.lua:217:  self.__ev = NS.NewBusTarget() or bus
modules/Analytics.lua:657:    self.__ev = NS.NewBusTarget() or NS.bus
modules/Browser.lua:1366:    B.__ev = NS.NewBusTarget() or NS.bus
```

`core/LootHistory.lua:20-24` — `NS.NewBusTarget` resolves `LibStub("AceEvent-3.0", true)` and
**returns nil** when it is absent, which is exactly the branch the `or` tail then takes. Each of the
three sites carries a comment immediately above it explaining the clobber it is trying to avoid
(`modules/Collector.lua:216`, `modules/Analytics.lua:656`, `modules/Browser.lua:1365`) — the intent
is right and the fallback undoes it. The correct shape is two files away:
`settings/Panel.lua:131` and `:326` both read `local ev = NS.NewBusTarget()` with no fallback.

### LH-29 — load-list derivation unpinned (`testing-§9`)

`tests/run.lua:30` — `Loader.loadAll(Loader.tocFiles("LootHistory.toc"), NS, mocks)` ✅ derived.
`tests/run.lua:17-26` — every `LibKa0s.xml` file spelled out in XML order ✅.
`tests/run.lua:39` — `_G.LH_TEST = Kit.expose{ NS = NS, mocks = mocks, Loader = Loader }` — the
loaded list is **not** published, and a grep for `loaded` across `tests/test_libka0s.lua` finds only
`Loader.loadAll` at `:56` inside `loadDegraded()`. None of `testing-§9`'s three assertions exists.

### LH-43 — unreachable boot validation (`architecture-§5`)

```lua
-- settings/Schema.lua:188-196
-- Boot validation: every schema path must resolve against the defaults table.
…
    -- Session-only rows (state.debugConsole) have no db-backed default to resolve — skip them.
    if not row.sessionOnly and S:ReadPath(g, row.path) == nil and row.default == nil then
      print("schema path missing default: " .. tostring(row.path))
```

Every non-session row in `settings/Schema.lua` declares a `default` (`:25,32,43,52,61,70,77,85,94,102,109`),
so `row.default == nil` is false for all of them and the conjunction can never be true. The comment
at `:188` describes the disjunction that was meant. `tests/test_schema.lua:130-138` asserts the
intended rule directly rather than driving `S:Register`, which is why the dead branch stayed green.

### LH-30 — restated window edge (`standalone-windows-§2`)

`modules/Browser.lua:20-33` declares a private `SKIN` table; `:66-86` `B:ApplySkin` draws the
backdrop, the 1px black outer edge, the once-built inner-highlight child, the title tint and the
divider tint by hand. `core/CoreSetup.lua:10-19` records that `Core.SKIN` **is** this treatment as
of Core minor 3 and that the two agree by value — which is the point: they agree today and nothing
keeps them agreeing. `core/DebugLogSetup.lua:117-119` routes the library's own windows through the
host seam via the `applySkin` hook, which is the sanctioned direction.

### LH-36 — the release gate is unstated (`automated-tests-§3`, `documentation-§5`)

Three places describe gating, and all three stop at the run:

- `docs/testing.md:167-176` — the four-row table with `perf`/`complexity` marked *"no — recorded
  only"*, then *"**`perf` and `complexity` never fail a run.**"* `:176` says *"**At release, not at
  commit.** A full bundle is produced as part of every version bump, before the tag… Commits are
  gated on lint + tests only."* — correct about the **bundle** checkpoint, silent on the **gate**.
- `docs/automated-tests/README.md`, section *"What gates, and what only records"* — the same table
  and the same *"never used to fail a run"* sentence; no release gate anywhere in the file.
- `docs/automated-tests/RESULTS.md:9-11` — *"`lint` and `tests` gate. `perf` and `complexity` are
  recorded and never fail a run"*; no release gate.

None of the three states that a tag requires all four suites at `pass` and
`suites.complexity.warnings == 0`, that a `skip` blocks as NOT EVALUATED, or that the
no-`tests/perf.lua` exception must be stated in the release notes — which is this addon's standing
position (A4, LH-24).

### LH-37 — a disposition citing the wrong ID (`automated-tests-§4`)

`docs/automated-tests/RESULTS.md`, band table, first row:
`| 1000–1500 (on notice) | modules/Browser.lua | 1372 | **Already tracked as LH-31.** …`
`docs/audits/2026-08-04/02_DEVIATIONS.md` defines `LH-31` as *"`docs/complexity.md` is not
shipped"* under `performance-§10` — a doc-presence finding, now retired by `automated-tests-§7`, and
never a file-size one.

### LH-38 — `CLAUDE.md` is not a stub (`documentation-§2`, #26)

`CLAUDE.md` is 102 lines. The five required items are present and in order — H1 `:1`, adherence line
`:9`, `## Standards compliance (read first)` `:11-22`, the read-the-docs pointer list `:41-53`, the
green-gate line `:96-102`. Beyond them it carries `## The docs/ set — there is no agent-context.md`
(`:24-39`), `## Hard rules` (`:55-87`, nine bullets covering storage model, bus discipline, the
Compat firewall, schema carve-outs, debug persistence, the `libs/` vendoring rule and the
inventory/badge rule), and `## Response style` (`:89-94`). `docs/ARCHITECTURE.md` already carries a
`## Standards compliance` section (`:277`) and a `## Doc index` (`:358`).

### LH-39 — stub/live asymmetry and Core-only degraded coverage

- `settings/Slash.lua:210` — `Sl.HelpHeader = function() return Dispatcher:HelpHeader() end` on the
  live path; the stub at `:139-162` defines `FormatKV`, `HelpRows`, `LandingRows`, `BuildListLines`,
  `PrintHelp`, the five `Cli*`, `CliResetAll`, `OnSlash`, `Register` — and **no `HelpHeader`**.
- Reached by `tests/test_slash.lua:212`, `:233`, `:323`; by no shipped file.
- `core/DebugLogSetup.lua:63-70` — the stub defines `ConsoleCheckbox`; the only caller anywhere is
  `tests/test_debuglog.lua:179-180`.
- `tests/test_libka0s.lua:88` — *"degraded install: the Core stub answers every member the addon
  calls"* is the only member-surface case, and it walks Core.

### LH-40 — the vendor gate goes quiet (`testing-§11/§12`)

`tests/test_vendor_sync.lua:110-116` — `siblingTag()` returns `nil` when `git show HEAD:LibKa0s/Core.lua`
in `../LibKa0s` produces nothing. `:139-141` and `:145-147` — `local tag = siblingTag(); if not tag
then return end`, i.e. both cases exit with zero assertions. `:105-109` claims *"A missing sibling is
the ONE case where this pair may go quiet, and it is said in the case name rather than hidden"* — the
two case names are *"libs/LibKa0s is the LibKa0s release the README says this addon bundles"* and
*"tests/_kit is the test kit that shipped with that release"*, neither of which says it. Separately,
the header at `:28-32` states the repo pins `* text=auto eol=crlf`; `.gitattributes:10,15` actually
pin `libs/** -text` and `tests/_kit/** -text`.

### LH-41 — perf-run naming (`performance-§8`)

`docs/perf-runs/README.md`, *"Recording one"*: *"One folder per capture, `<YYYYMMDD-HHMMSS>/`,
holding the exported record and a short note…"*. `performance-§8` mandates
`<YYYY-MM-DD>-ingame-<label>.json` in the standing cumulative store. The rest of the file is
compliant and unusually honest — it states that **no** capture exists, that this is a gap rather
than a clean result, and that `performance-§9`'s zero-overhead claim has never been demonstrated
here.

### LH-42 — "Reset All" (`slash-commands-§2`)

`settings/Panel.lua:635` — `rowGroup:AddChild(makePairButton("Reset All", function() …
StaticPopup_Show("KA0S_LOOTHISTORY_RESETALL") … end))`.
`settings/Slash.lua:19-26` — that dialog's text reads *"Reset ALL Ka0s Loot History settings AND
delete ALL recorded history? This cannot be undone."* and its `OnAccept` calls `Sl:ResetEverything()`.
`settings/Schema.lua:223` — the reserved verb `{ "resetall", "Reset all settings", function()
NS.Slash:CliResetAll() end }` correctly resets settings only.
`README.md:162` tells users *"`/lh resetall` resets settings without touching your history"*, which
is true of the verb and not of the identically-named button.

### LH-44 — stale lint suppression (`lint`)

`modules/AuctionPrice.lua:1` — `local addonName, NS = ...   -- luacheck: ignore addonName`, while
`addonName` is used at `:17` and `:18`. `.luacheckrc:14` already carries the global
`"211/addonName"` ignore with its own explanatory comment.

---

## D. Compliance evidence (claims that pass, sourced)

| Claim | Evidence |
|---|---|
| TOC field order exact | `LootHistory.toc:1-14`, matching `toc-file-§1` line for line |
| Single Retail Interface, badge in lockstep | `LootHistory.toc:1` `120007` ↔ `README.md:3` `Midnight_12.0.7` |
| MIT, `X-Standard`, Curse ID present; no Wago/WoWI | `LootHistory.toc:12,13,14` |
| No hard `Dependencies` | `LootHistory.toc:8` uses `## OptionalDeps` only |
| `#`-sectioned file listing in the required order | `LootHistory.toc:16,32,35,45,48,58` |
| Single aggregate LibKa0s XML, after Ace3 | `LootHistory.toc:27` |
| No `externals:` in `.pkgmeta` | `.pkgmeta:3-11`, with the reason stated |
| `docs`/`tests` excluded from the package | `.pkgmeta:8-9` |
| Metatable-fallback locale, no AceLocale strict | `locales/enUS.lua:5` |
| No `_G[addonName]`, no `WOW_PROJECT_ID` ladder | greps over `core modules settings` return nothing |
| AceConsole reclaim wired (#36) | `core/CoreSetup.lua:22-26,104-107`; `core/LootHistory.lua` |
| Cyan `[LH]` tag through one constant | `core/Namespace.lua` (`NS.PREFIX`), consumed at `settings/Slash.lua:4` |
| `schemaVersion` + migration runner | `defaults/Global.lua:10`; `core/Database.lua` `RunMigrations` |
| Media in typed subfolders, `.tga` + `.jpg` pair | `media/logos/loothistory.logo.tga`, `.jpg` |
| No file over the 1500 cap | `wc -l` over `core defaults modules settings locales`, max 1372 |
| Three-place standards reference complete | `LootHistory.toc:13`; `README.md:6`; `CLAUDE.md:11` |
| Root doc set is exactly three docs + LICENSE | `git ls-files` at root: `.gitattributes`, `.gitignore`, `.luacheckrc`, `.pkgmeta`, `CLAUDE.md`, `DEPENDENCIES.md`, `LICENSE`, `LootHistory.toc`, `README.md` |
| No `TODO.md`, no `agent-context.md` | `git ls-files | grep -iE 'todo|agent-context'` → nothing |
| `docs/` trio present | `docs/ARCHITECTURE.md`, `docs/testing.md`, `docs/smoke-tests.md` |
| `ARCHITECTURE.md` carries all eight required sections | `:9,35,70,154,189,217,241,264` (+ `:277`, `:331`, `:358`) |
| `DEPENDENCIES.md` splits runtime/dev/release, uses `pipx`, verifies each tool | `DEPENDENCIES.md:13,44,55,87,98,120` |
| README `## What's new` current and matching the top history row | `README.md:36` `## What's new in 1.2.0` ↔ `:176` top row `1.2.0` |
| README carries no `## Testing` section | `grep -n '^## Testing' README.md` → nothing |
| Badge row canonical, standard badge uses `_` not `%20` | `README.md:3-7` |
| Frozen dated audit/review bundles | `docs/audits/{2026-07-12,2026-07-18,2026-08-04}/`, `docs/reviews/{2026-07-11,2026-08-03,2026-08-05}/` |
