# 04 — Technical design

How to close each deviation in `02_DEVIATIONS.md`. Nothing here is player-visible; every change is a load-order
guard, a comment, a doc line, a test or a release-process step. Keyed to the deviation IDs.

---

## A. File-load coupling between modules — LH-82, then LH-78/79/80/81 and LH-58

**Decide the order of the two fixes first, because one changes what the other writes.** LH-82 removes the reasons the
four positions are load-bearing; LH-78…81 annotate them. Doing LH-82 first means the TOC comments say
*conventional* rather than *load-bearing*, which is the cheaper end state to maintain (anti-patterns #66 exists
because an unannotated load-bearing line fails silently). Where a coupling is kept on purpose, annotate it instead.

1. **`modules/AnalyticsCharts.lua`** — add `NS.Analytics = NS.Analytics or {}` above `:2`, matching its three
   siblings. That alone makes the file order-independent: `Analytics._charts` (`:226`) and the
   `function Analytics:render…` definitions then attach to whichever copy of the table loaded first.
2. **`modules/Escrow.lua`** — the step registration at `:26`, `:160-161` is the one real dependency. Two shapes,
   both acceptable under `architecture-§3`:
   - (preferred) expose `Escrow.SCAN_STEPS` / `Escrow.PLAN_STEPS` and have `modules/Reconciler.lua` concatenate them
     at call time (inside the function that iterates `R.SCAN_STEPS`), so neither file reads the other at load; or
   - keep the append, but do it from an `Escrow:Register()` the Reconciler calls from its `Enable`/first scan.
   Either way `local R = NS.Reconciler` at `:18` becomes `local R = NS.Reconciler or {}` guarded by
   `NS.Reconciler = NS.Reconciler or {}`, or is read inside functions. Characterization: `tests/test_escrow.lua` and
   `tests/test_reconciler*.lua` already drive plan and commit; add one case that loads `Escrow` **before**
   `Reconciler` through the loader and asserts the steps are still present (red under: today's file-load append).
3. **`modules/Timeline.lua`** — read `TM.TOTAL` inside the functions that use it (or guard
   `NS.TimelineModel = NS.TimelineModel or {}` at `:19` and resolve `TOTAL` lazily). `local TM = NS.TimelineModel`
   with the idempotent guard is then order-free.
4. **`settings/Panel.lua:961`** — this one is *settings reading settings*, inside the settings group the layout puts
   last; keeping it is reasonable. Annotate rather than refactor: it is the `LH-81` comment.
5. **TOC** (`LootHistory.toc`):
   - above `:131` `settings\Panel.lua`: `# LOAD-BEARING POSITION: AFTER_GROUP reads NS.Schema.MASTER_GROUP and
     MasterAfterGroup at file load; settings\Schema.lua must be above.`
   - for each of Escrow / AnalyticsCharts / Timeline: if step 1–3 landed, one group comment under `# Modules`
     saying the positions are conventional (that is LH-58's SHOULD); otherwise a `LOAD-BEARING POSITION` comment per
     line naming what resolves.
   - replace `# Modules (Attribution before Collector)` (`:94`) with the reason, or drop the parenthesis — no module
     reads Attribution at load.
   - fix the stale `libs\LibKa0s\Slash.lua:487` reference at `:128` (it is `:357`; better, cite no line — the
     `error(MAJOR .. ":New requires descriptor.commands …")` text is greppable and does not move).

**Risk.** Load order is exercised by the harness through `tests/_kit/loader.lua`, which derives the load list from the
TOC (`testing-§9`), so a reorder test is cheap. The game client is the only place a nil-index-at-load shows as "the
addon never loaded"; the change is a guard, not a behavior change, so no smoke check is new.

## B. Docs — LH-60, LH-71, LH-73, LH-83, LH-84, LH-85, LH-86

- **LH-60 (hub spill).** Move the per-file table and the load-order bullets out of `docs/ARCHITECTURE.md:38-115` into
  `docs/module-map.md` (which already carries both, so this is mostly a deletion), leaving a 6–10 line summary and one
  link. The *Event subscriptions* table (62 lines) has no canonical spill target; either trim it to the registration
  sites with a link to `data-flow.md`'s per-event narrative, or move it to a Tier 3 `event-subscriptions.md` registered
  in *Addon-specific*. Target: the hub under ~400 lines.
- **LH-73 (drift).** Re-derive each figure from its command (the table in `03_EVIDENCE.md`): v1.70.0; 57 shims; largest
  file 1476 (or, better, write the census without a "largest file" sentence that rots on every commit); the
  load-bearing count after section A lands; the seam count; the TOC's `Slash.lua` reference; the Panel header comment.
  The recurring cause is figures typed into prose; where a doc must state a count, state the command beside it.
- **LH-71.** README Usage last paragraph → one sentence, e.g. "Everything else is under Settings → AddOns, and
  `/lh help` (or `/loothistory help`) lists every command." De-AI pass.
- **LH-83.** Delete "Released on lint, tests and complexity only. …" from the 1.4.0 row (`README.md:134`). The record
  of what gated 1.4.0 lives in `docs/automated-tests/20260927-030334/`. Punctuation only otherwise.
- **LH-84.** `DEPENDENCIES.md:136` → `bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle`; `:140`
  "The complexity run is a release step…". Keep `lizard --version` as the install check.
- **LH-85.** `docs/ARCHITECTURE.md:326-327` → name `docs/automated-tests/<run>/` and `docs/perf-analysis/<run>/` (and the
  other stores as `documentation-§3` lists them). `test_doc_structure.lua` reads the map; check it still parses the
  sentence, or that it derives the exclusion from the same list.
- **LH-86.** `docs/schema.md:388`: "`holdings`: `Reconciler:Flush` (every diff, escrow commit and genesis inside a
  flush); `R.MarkLoginGenesis` from `LoginScan` (the login genesis stamp); `Reconciler:ForgetHolder` →
  `Holdings:ForgetHolder` from the Holdings tab's *Forget* popup." No register row.

## C. Tests — LH-68

Add to `tests/test_surface_parity.lua`:

```lua
-- ── Perf ──────────────────────────────────────────────────────────────────────────────────────
test("parity: the Perf stub carries the LibKa0s-Perf-1.0 surface this addon calls", function()
  -- members from: git ls-files '*.lua' ':!libs' ':!tests' | xargs grep -ohE '\b(NS\.)?Perf[.:][A-Za-z_]+' | sort -u
  local members = { "on", "Note", "OnCommand" }   -- plus whatever the step panel / Lifecycle touch
  T.assertSurfaceParity(pick(NS.Perf, members), pick(degradedNS.Perf, members), "Perf stub")
end)
```

Degraded arm from `tests/degraded_env.lua` (loader with a partial file list), never a hand-built stub
(`testing-§8`). Regenerate `docs/test-cases.md` and the README badge in the same commit (`testing-§5`).

## D. Release process — LH-87

The next tag is blocked by the release gate (zero functions above CCN 15, `blindFiles` 0). Plan:

1. Run the full sighted battery (`bash tests/_kit/run-automated-tests.sh`) on a clean tree to write the first sighted
   bundle; it will record 26 warnings and 10 band files and leave their `Disposition` cells blank.
2. For each of the 26, either refactor under `performance-§11` (named helpers, module-level tables, a characterization
   test first — the GI-LH-02 commits are the in-repo model) or write a ruling in its `Disposition`. Candidates for a
   ruling rather than a split: `NS.StandUp` / `NS.StandDown` (runs of guarded `Enable`/`Disable` calls — a module-level
   list iterated once would also drop the CCN honestly). Candidates for a split: the ledger planners in
   `modules/Escrow.lua`, `core/Database.lua` `convertHolderMoves` / `Database.Stats`, `modules/Reconciler.lua`
   `onEvent`.
3. Peel `modules/BrowserTable.lua` (1476) before anything else grows it past 1500; disposition `modules/Browser.lua`
   (1416, past its own 1400 trigger).
4. Leave `RESULTS.md`'s preamble to the runner (the `e09cf58` rename is overwritten by the next run anyway).

## E. Info rows — LH-77, LH-88, LH-89

- LH-77: pass arguments to the printer when those five lines are next edited; not worth a commit of its own.
- LH-88: upstream issue on `LibKa0s` — the kit's `--list` *Totals* should show passes and skips separately so the
  generated inventory and the badge read the same number. No local change (`testing-§1` forbids editing the kit).
- LH-89: `settings/Panel.lua:22` → build from `local addonName = ...` at the top of the file.

## Ordering constraints

- A before the TOC half of LH-73 (the load-bearing count depends on A's outcome).
- C and any test added in A regenerate `docs/test-cases.md` and the badge in the same commit.
- D is a release-time activity; it does not block A–C and A–C do not block it, but D's bundle should be cut after
  A–C so the first sighted record describes the tree that ships.
