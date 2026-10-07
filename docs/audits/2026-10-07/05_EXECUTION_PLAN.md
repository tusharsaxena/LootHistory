# 05 — Execution plan

The hand-off to the remediation engagement. Ordered sprints, each step tied to deviation IDs from `02_DEVIATIONS.md`.
Every step ends on the green gate (`~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua`,
`~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` at 0/0). Figures quoted here are the ones in `02_DEVIATIONS.md`
and `03_EVIDENCE.md` (14 roots, 18 incl. dependents; 26 functions above CCN 15; 10 band files; 1476/1477 tests).

---

## Sprint 1 — load-order coupling (LH-82, LH-78, LH-79, LH-80, LH-81, LH-58)

- [ ] **S1.1 (LH-82, LH-79)** `modules/AnalyticsCharts.lua`: add `NS.Analytics = NS.Analytics or {}` above `:2`.
- [ ] **S1.2 (LH-82, LH-78)** `modules/Escrow.lua`: stop appending to `NS.Reconciler`'s step lists at file load
  (`:26`, `:160-161`); register through a call-time read or an init call (design §A.2). Characterization case first:
  load Escrow before Reconciler and assert the scan/plan steps are present.
- [ ] **S1.3 (LH-82, LH-80)** `modules/Timeline.lua`: idempotent guard at `:19`; read `TM.TOTAL` lazily instead of at
  `:26`.
- [ ] **S1.4 (LH-81, LH-58, LH-78)** `LootHistory.toc`: annotate `settings\Panel.lua` (`:131`) as load-bearing on
  Schema; mark the `# Modules` group conventional (or annotate any coupling S1.1–S1.3 kept); replace the
  "(Attribution before Collector)" header; drop the `Slash.lua:487` line reference at `:128`.
- [ ] **S1.5** Regenerate `docs/test-cases.md` and the README `[tests]` badge for the new case(s).

Smoke: none new — the change is a load guard. Owner's routine login check covers it.

## Sprint 2 — tests (LH-68)

- [ ] **S2.1 (LH-68)** Add the Perf stub-surface parity case to `tests/test_surface_parity.lua` with its grep comment;
  degraded arm from `tests/degraded_env.lua`. Regenerate `docs/test-cases.md` and the badge.

## Sprint 3 — docs (LH-60, LH-73, LH-85, LH-86, LH-71, LH-83, LH-84)

- [ ] **S3.1 (LH-60)** Spill `## Module map` (`docs/ARCHITECTURE.md:38-115`) to `docs/module-map.md`, leaving a summary
  and one link; trim or spill `## Event subscriptions`. Re-measure the hub (`wc -l`, section awk in `03_EVIDENCE.md`).
- [ ] **S3.2 (LH-73)** Re-derive the seven drifted figures from their commands (after Sprint 1 for the load-bearing
  count): `ARCHITECTURE.md:31`, `:41-42`, `:347`, `:431`; `module-map.md:188`, `:195`; `settings/Panel.lua:7-8`.
- [ ] **S3.3 (LH-85)** `docs/ARCHITECTURE.md:326-327`: use `documentation-§3`'s out-of-scope list, including
  `docs/perf-analysis/<run>/` and `docs/automated-tests/<run>/`. Confirm `tests/test_doc_structure.lua` stays green.
- [ ] **S3.4 (LH-86)** `docs/schema.md:388`: name `R.MarkLoginGenesis` and `Reconciler:ForgetHolder` →
  `Holdings:ForgetHolder` (with the *Forget* popup) as `holdings` writers.
- [ ] **S3.5 (LH-71, LH-83)** README: Usage closes on one sentence (`:63`); delete the contributor line from the 1.4.0
  Version History row (`:134`). De-AI pass on what changed (`documentation-§1`).
- [ ] **S3.6 (LH-84)** `DEPENDENCIES.md:136`, `:140`: the sighted runner in place of raw `lizard`.

## Sprint 4 — before the next tag (LH-87)

- [ ] **S4.1** Full sighted battery on a clean tree (`bash tests/_kit/run-automated-tests.sh`), through `ka0s-bounded`.
- [ ] **S4.2** Each of the 26 functions above CCN 15: refactor under `performance-§11` with a characterization test
  first, or a written ruling in its `Disposition` cell. Report each as guarding/defaulting vs branching.
- [ ] **S4.3** Disposition the 10 band files; peel `modules/BrowserTable.lua` (1476) and act on `modules/Browser.lua`'s
  fired 1400-line trigger.
- [ ] **S4.4** Re-run; the tag needs all four suites `pass`, 0 warnings above CCN 15 and `blindFiles` 0.

## Opportunistic / upstream (LH-77, LH-88, LH-89)

- [ ] **LH-77** Pass printer arguments instead of pre-formatting at the five sites when next touched.
- [ ] **LH-88** File upstream on `LibKa0s`: the kit's `--list` *Totals* should separate passes from skips. No local edit.
- [ ] **LH-89** `settings/Panel.lua:22`: build `LOGO_PATH` from `addonName`.

## Not in this plan

- The four ratified register rows (accepted, re-checked; no trigger fired).
- The disabled-state stand-down, vendored payloads, line endings, packaging, launcher, diagnostics, library debug lines,
  settings content and re-vendor store — measured compliant.
