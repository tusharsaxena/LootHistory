# 05 — Execution plan

Ordered, checkable steps keyed to `02_DEVIATIONS.md`. **Upstream first**: Sprint 0 lands in `LibKa0s` /
`WowAddonStandards` before any addon step that depends on it. Every addon step ends on the green gate
(`~/.claude/wow-addon/bin/ka0s-bounded lua tests/run.lua` all green, `… luacheck .` 0/0); a step that adds or renames a
case regenerates `docs/test-cases.md` and the README `[tests]` badge in the same commit (`testing-§5`).

Tally this plan closes: **20 roots + 1 dependent = 21 rows** (High 1, Medium 1, Low 18, Info 1).

---

## Sprint 0 — upstream (other repos; this addon only consumes)

- [ ] **0.1 (LH-69)** In `LibKa0s/testkit/run-automated-tests.sh`: detect a ratified `performance-§12` register row (or an
      explicit override) and emit `automated-tests-§3`'s reason (2) in `skipReason` and in RESULTS' *Perf* section; kit case
      for with-row / without-row / unparseable register. Release a LibKa0s tag.
- [ ] **0.2 (LH-75)** Propose in `WowAddonStandards`: `versioning-git`'s "increment `schemaVersion` in defaults" to defer to
      the `open-evolutions` migration-stamp ruling (the defaults value as the pre-migration floor). Not blocking — Sprint 2's
      register row ratifies the current shape meanwhile.
- [ ] **0.3 (LH-76, optional)** Propose in `WowAddonStandards` whether a window's resize grip is a catalog mark or the
      Blizzard grabber collection-wide. Not blocking — Sprint 3 picks one locally.

## Sprint 1 — record-keeping and TOC (behavior-neutral)

- [ ] **1.1 (LH-62)** Write `docs/revendor/<date>-v1.53.0/` — `01_DELTA.md` line 1 naming the span `v1.15.0 → v1.53.0`,
      a table of the 25 unrecorded tags with the vendoring commit for each (`git log --format='%h %ad %s' --date=short --
      libs/LibKa0s`), and `05_SUMMARY.md`. Re-run `AUDIT.md`'s ledger commands: `count=0`.
- [ ] **1.2 (LH-56, LH-57, LH-63, LH-58)** One `LootHistory.toc` commit: LOAD-BEARING comments above `core\CoreSetup.lua`
      (`:48`, names `NS.PREFIX` ← Namespace), `core\DebugLogSetup.lua` (`:56`, names `NS.Constants.FONT_MONO` ← Constants),
      `settings\Slash.lua` (`:87`, names `NS.COMMANDS` ← Schema); a conventional note on `# Locales`, `# Defaults` and the
      plain `# Core` run; reword the PoolSetup comment (`:57`) as conventional. Suite green (the TOC-derivation cases in
      `tests/test_harness.lua` must still pass).
- [ ] **1.3 (LH-52)** `gh issue create` — "Peel modules/Analytics.lua: renderers vs formatting/segmenting helpers",
      labels `state:triaged`, `severity:low`. Note the number for the next run's Disposition cell.

## Sprint 2 — documentation

- [ ] **2.1 (LH-72)** Swap `CLAUDE.md`'s `## Vendored LibKa0s` and `## Green gate`; `tests/test_vendor_sync.lua` still green.
- [ ] **2.2 (LH-73)** Re-point `DEPENDENCIES.md:49` → `docs/testing.md:191`, `:53` → `run-automated-tests.sh:242`/`:122`,
      `:112` → `docs/testing.md:183`; `docs/ARCHITECTURE.md:42-48` and `docs/module-map.md` list the load-bearing seams as
      Item, Media, Core, DebugLog (+ Options and Slash in `settings/`), with Widgets/Pool described accurately;
      `:207` cites `slash-commands-§3`; `:447` trigger reads "21 shims".
- [ ] **2.3 (LH-74, LH-75, LH-76 if the grabber is kept)** Add the register rows from `04_TECHNICAL_DESIGN.md` §C to
      `docs/ARCHITECTURE.md` → `## Documented deviations`, each with Decided = the commit date.
- [ ] **2.4 (LH-70)** Cut `docs/performance.md` to one screen; move the sweep to `docs/combat-path-sweep.md`; register it in
      `### Addon-specific`; re-point the `performance-§12` row's Why link. `tests/test_doc_structure.lua` green.
- [ ] **2.5 (LH-60)** Spill *Settings schema* (`docs/ARCHITECTURE.md:118-160`) into `schema.md`; move *The disabled state*
      body to `docs/disabled-state.md` (Tier 3, registered); hub < 400 lines, *Settings schema* ≤ 60 with one link.
- [ ] **2.6 (LH-71)** README *Usage*: relocate the enable/disable sentences, close on one configuration sentence; de-AI pass.

## Sprint 3 — code and tests

- [ ] **3.1 (LH-67)** Rename the 12 `disabled-§7…` cases in `tests/test_disabled.lua` to `slash-commands-§7 step N: …`;
      `.pkgmeta:14/19/20` cite `packaging`. Regenerate `docs/test-cases.md` (case names change; count unchanged at 858).
      Re-run the §15 sweep in `03_EVIDENCE.md`: `disabled-§` 0 hits, dotted `§N.M` 0 hits.
- [ ] **3.2 (LH-66)** Replace the nine test literals with `NS.MSG.*` / a local `PROBE` constant; re-run the playbook grep → 0.
- [ ] **3.3 (LH-68)** Add the Env, Item, Media, Pool and Lifecycle parity cases with `-- members from: grep …` comments;
      verify each goes red when a stub member is deleted (record the mutation in the case comment, `testing-§12`); badge +
      inventory in the same commit.
- [ ] **3.4 (LH-64)** Add `NS.SafeRegister` + `NS.RejectedEvents`; route every registration block through it; add
      `/lh debug events` and the `[Init]` clause; `.luacheckrc` gains `C_EventUtils`. Tests with `M.__badEvents`;
      `tests/test_disabled.lua` still reaches an empty registration set.
- [ ] **3.5 (LH-65)** `VisibilityAllows(inCombat)` / `ApplyVisibility(inCombat)` fed from the event edge, else
      `UnitAffectingCombat("player")`; same for `testModeRefusal`; `.luacheckrc` gains `UnitAffectingCombat`. New
      `tests/test_browser.lua` cases fire `PLAYER_REGEN_DISABLED` with lockdown still false. Version History highlight for
      the behavior change.
- [ ] **3.6 (LH-76)** Either draw `NS.Icon("resize")` with the Blizzard grabber as fallback, or keep the grabber under the
      Sprint 2.3 row.
- [ ] **3.7 (LH-77, optional)** Argument-style `print` at `settings/Slash.lua:40/51/62/76` and `settings/Schema.lua:785`.

## Sprint 4 — re-vendor and record

- [ ] **4.1 (LH-69)** Re-vendor the whole LibKa0s tag from Sprint 0.1 (`libs/LibKa0s/` and `tests/_kit/`), bump
      `CLAUDE.md`'s provenance line in the same commit, `git update-index --chmod=+x tests/_kit/run-automated-tests.sh`,
      and write its `docs/revendor/<date>-v<tag>/` bundle (01 and 05 at minimum) so LH-62 does not recur.
- [ ] **4.2** Run `tests/_kit/run-automated-tests.sh` (four suites) → a new bundle whose manifest carries `perf.skipReason`
      reason (2) naming `performance-§12`, commit SHA and clean mark; write its `ANALYSIS.md`; set the Analytics
      Disposition to *already tracked as #N* (the only hand edit `RESULTS.md` permits).

## Smoke tests (in client)

- [ ] **S1 (LH-65)** *General visibility* = *Only out of combat*; open the History window; pull a training dummy → the
      window hides at the pull. Leave combat → it stays closed (the setting only ever hides). Repeat with *Only in combat*:
      window opened mid-fight hides on leaving combat.
- [ ] **S2 (LH-64)** `/lh debug events` on a normal install prints "no rejected events"; `/lh debug on` shows the `[Init]`
      line without a rejected-events clause.
- [ ] **S3 (LH-76, if the mark is adopted)** The grip draws the catalog mark bottom-right, tints on hover, still resizes.

## Done when

- `AUDIT.md`'s ledger, bus-literal, citation and TOC checks all return clean; the hub is under 400 lines; the next audit
  finds 0 of LH-52 … LH-77 open other than register-ratified rows.
