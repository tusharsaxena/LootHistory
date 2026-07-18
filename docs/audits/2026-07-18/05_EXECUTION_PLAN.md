# 05 — Execution Plan (Remediation)

Ordered, checkable hand-off to the separate remediation engagement. Each step names its deviation
ID(s). Work trunk-based on `master` (no feature branch unless the user asks); commit only on a green
unit (`lua tests/run.lua` = 224/224 **and** `luacheck .` = 0/0). This audit made **no** code changes.

Baseline this session: **224/224 tests, 0/0 lint.**

---

## Sprint 0 — Decisions (no code) · blocks LH-13, LH-18

- [ ] **LH-13:** Present the `toc-file-§5` ↔ `layout-§1` contradiction to the user. Get the call:
      **Path A** (raise upstream + accept deviation here — recommended) or **Path B** (reorder TOC to
      literal `toc-file-§5`). Do not edit the TOC until decided.
- [ ] **LH-18:** Get the call — **add** the Filters Defaults button, or **accept** the deviation (no
      schema rows on that page). Do not edit until decided.

## Sprint 1 — Zero-risk hygiene (config + docs) · LH-15, LH-16, LH-17, LH-19

Batch these; they cannot affect runtime behaviour.

- [ ] **LH-15:** Rename `CLAUDE.md` heading to `## Standards compliance (read first)`; verify body vs
      documentation-§6 canonical wording.
- [ ] **LH-16:** Add `- tools` (and optionally `- .superpowers`) to `.pkgmeta` `ignore:`.
- [ ] **LH-17:** Set `.luacheckrc` `exclude_files = { "libs/", "docs/audits/", "docs/reviews/", "_dev/", "tests/" }`.
- [ ] **LH-19:** Sweep the 15 retired `§N.M` citations to `filename-§N` (table in `04_TECHNICAL_DESIGN.md`)
      across the 8 source/doc files.
- [ ] **Gate:** `luacheck .` → 0/0; `lua tests/run.lua` → 224/224. Commit:
      `docs/pkg/lint: standards-hygiene sweep — CLAUDE heading, tools ignore, lint excludes, §-citations (LH-15/16/17/19)`.

## Sprint 2 — Combat notice (behaviour copy) · LH-14

- [ ] Add locale key `"cannot open settings during combat — Blizzard's category-switch is protected"`
      to `locales/enUS.lua`.
- [ ] Replace the `P:Open` lockdown print with the grey canonical notice through `NS.Print`; keep the
      early `return`; add no `PLAYER_REGEN_ENABLED` replay.
- [ ] (Optional TDD) assert `P:Open` early-returns under a mocked `InCombatLockdown()==true` (no
      `Settings.OpenToCategory` call).
- [ ] **Gate:** green. Commit: `settings: canonical grey combat panel-open notice (LH-14)`.

## Sprint 3 — Conditional, per Sprint-0 decisions

- [ ] **LH-13 (only if Path B):** Reorder `LootHistory.toc` sections to `Libraries → Locales → Core →
      Defaults → Modules → Settings`; smoke-test a clean load (no Lua error, `/lh` help prints,
      addon present in options list). Commit: `toc: reorder sections to toc-file-§5 (LH-13)`.
      **If Path A:** file the upstream standards issue; add an "accepted deviation" note to this
      bundle. No code commit.
- [ ] **LH-18 (only if "add"):** Set Filters `defaultsButton = true`; add a
      `KA0S_LOOTHISTORY_CLEAR_FILTERS` confirm popup wired to `NS.Filters:ClearAll()`; wire
      `fctx.panel.defaultsBtn` OnClick. Smoke-test the button renders top-right and clears both lists.
      Commit: `settings: Defaults button on Filters subcategory (LH-18)`.
      **If "accept":** note the accepted deviation in this bundle + `docs/settings-panel.md`.

## Sprint 4 — Close-out

- [ ] Final gate: `lua tests/run.lua` (224/224 or higher if TDD added cases) + `luacheck .` (0/0).
- [ ] If the suite count moved, regenerate `docs/test-cases.md` (`lua tests/run.lua --list >
      docs/test-cases.md`) and update the README `[tests]` badge **in the same commit** (testing-§5).
- [ ] Write a `06_EXECUTION_OUTCOME.md` in **this** dated folder recording per-ID status, decisions
      taken (LH-13 path, LH-18 add-vs-accept), commits, and smoke-test results — mirroring the
      2026-07-12 run's outcome doc. Do not edit `01`–`05`.

---

## Sequencing rationale

- **Decisions before edits** (Sprint 0) so LH-13/LH-18 don't get half-built.
- **Hygiene batched** (Sprint 1) — all comment/config, one commit, cannot regress tests.
- **Panel copy isolated** (Sprint 2) so the one behavioural string change is its own reviewable commit.
- **Shared-file order:** `settings/Panel.lua` is touched by LH-19 (Sprint 1), LH-14 (Sprint 2), and
  possibly LH-18 (Sprint 3) — doing them in that order avoids rebasing the same file mid-sprint.
- **No version bump** unless the user requests one (per repo hard rules); these are conformance edits.

## Definition of done

- All seven IDs are either **closed** or **recorded as an accepted deviation** (LH-13 / LH-18 may land
  as the latter).
- Green gate holds; test inventory + badge in lockstep if the count moved.
- Prior IDs `LH-01…LH-12` remain closed.
- `06_EXECUTION_OUTCOME.md` written; `01`–`05` left frozen.
