# 05 — Execution Plan

Ordered, checkable remediation steps for `02_DEVIATIONS.md`, designed in `04_TECHNICAL_DESIGN.md`.
This is the hand-off to a separate remediation engagement — **the audit itself changed no code.**

Audited against **Ka0s WoW Addon Standard v2.17.1 (2026-08-03)**.

**Gate on every step:** `lua tests/run.lua` green **and** `luacheck .` clean before commit
(`testing-§4`, `versioning-git`). Work test-first. Trunk-based — no branch unless the user asks.

---

## Sprint 0 — Decide (blocks Sprint 2 entirely)

| # | Step | Closes | Done when |
|---|---|---|---|
| 0.1 | Put the perf question to the user with `02_DEVIATIONS.md` §MUST and `04_TECHNICAL_DESIGN.md` §0 in hand. Branch A (adopt the wiring) or Branch B (upstream amendment) — and specifically, which of the three `suspend` resolutions applies. | gates LH-20…LH-26 | A decision is recorded in `docs/pending/LEDGER.md` against **LIBKA0S-17**, superseding or reaffirming the `wont-do`, with the date and the reason. |
| 0.2 | If Branch B (or resolution 1 for `suspend`): open the amendment against `WowAddonStandards` proposing a `performance-§6` carve-out for addons whose `suspend` is **destructive**. Do not edit the standards repo unilaterally. | LH-23 (possibly) | The proposal exists upstream and its outcome is recorded here. |

**Nothing in Sprint 2 starts before 0.1.** Sprints 1 and 3 are independent of it and can run in
parallel.

---

## Sprint 1 — The independent MUSTs (no decision needed)

Small, self-contained, and each closes a MUST. Do these first — they are the fastest route from
"major deviations" to "minor deviations" on everything except the perf cluster.

| # | Step | Closes | Files | Done when |
|---|---|---|---|---|
| 1.1 | **Failing test first:** a case that seeds the Filters page, hides it, fires `Ka0s_LootHistory_HistoryChanged`, drives the mock's recorded `OnShow`, and asserts the **rendered row list reflects the change**. Assert the outcome, never `ctx.dirty` / `ctx._dirty`. | LH-27 | `tests/test_panel.lua` | The case is **red** against today's tree. |
| 1.2 | Route the off-screen branch through the library's public path: `settings/Panel.lua:321` → `O.RefreshAllPanels()`. Verify against the vendored `libs/LibKa0s/Options.lua` that `refreshCtx` sets `_dirty` on hidden ctxs and that visible-panel refresh stays the in-place scalar path (not a full re-render — anti-pattern #39). | LH-27 | `settings/Panel.lua` | 1.1 is green. |
| 1.3 | Delete the dead flag: `ctx.dirty = false` (`:138`) and `ctx.dirty = true` (`:321`). Correct the now-stale comment at `:133-135` so it describes what the code does. Retire the existing test that pins the private flag (named in `docs/reviews/2026-08-03/`). | LH-27 | `settings/Panel.lua`, `tests/test_panel.lua` | `grep -n "ctx.dirty" settings/Panel.lua` returns **nothing**; suite green. |
| 1.4 | **Failing test first:** iterate every non-`sessionOnly` schema row and assert `row.default` deep-equals the value at `row.path` in `NS.defaults.global`. | LH-28 | `tests/test_schema.lua` | The case exists and passes/fails honestly against today's tree (it should pass — the duplicates currently agree; that is the point of adding it before the refactor). |
| 1.5 | Add the `D(path)` reader above `S.Schema` and replace the six duplicated literals (`settings/Schema.lua:25,52,61,70,77,85`) with `D("…")`. Leave `:109` (already references a constant) and session-only rows alone. Re-verify the deep-copy guards at `:168` and `:183-186` still prevent aliasing of table defaults. | LH-28 | `settings/Schema.lua` | 1.4 still green; `defaults/Global.lua` is the only file carrying those six literals. |
| 1.6 | Hoist the `libs/LibKa0s/*.lua` list in `tests/run.lua:17-26` to a named local; capture `Loader.tocFiles(...)` into `addonFiles`; publish both through `Kit.expose{ …, loaded = { libs = …, addon = … } }`. | LH-29 | `tests/run.lua` | Suite still green (no behavior change). |
| 1.7 | Add the four derivation cases: (a) `loaded.addon` equals a fresh derivation, in order; (b) every path in `loaded.addon` + `loaded.libs` opens on disk; (c) no `loaded.addon` entry matches `^libs/`; (d) every file named in `libs/LibKa0s/LibKa0s.xml` appears in `loaded.libs` in XML order. | LH-29 | `tests/test_libka0s.lua` or new `tests/test_runner.lua` (+ suite list) | Four new cases green; each verified falsifiable by temporarily corrupting the list and watching it redden (then reverting from a `cp` backup, **never** `git checkout`). |
| 1.8 | Regenerate the inventory and move the badge: `lua tests/run.lua --list > docs/test-cases.md`, update the README `[tests]` `X/Y`. | — (`testing-§5`) | `docs/test-cases.md`, `README.md:7` | Inventory total = run total = badge. |
| 1.9 | Commit. One commit per closed deviation is preferred so history is legible. | LH-27, LH-28, LH-29 | — | Gate green; nothing under `libs/` or `tests/_kit/` touched. |

---

## Sprint 2 — The perf cluster *(only after Sprint 0.1 chooses Branch A)*

Ordered by dependency: the setup file first (everything else references `NS.Perf`), the SV and lint
next (the descriptor names the global), then the verb, the brackets, the runner and the docs.

| # | Step | Closes | Files | Done when |
|---|---|---|---|---|
| 2.1 | **Failing test first:** descriptor well-formedness — the instance exists, `NS.Perf.on` is a plain boolean field, `NS.Perf.Note` is dot-callable, and the declared bucket keys are the ones intended (`testing-§8`). | LH-20 | `tests/test_libka0s.lua` | Red. |
| 2.2 | Write `core/PerfSetup.lua` per `04` §1.1 — silent lookup, descriptor, degradation stub. TOC-list it in `# Core` **after** `core/DebugLogSetup.lua`, **before** `core/LootHistory.lua`. | LH-20 | new `core/PerfSetup.lua`, `LootHistory.toc` | 2.1 green. `tests/test_libka0s.lua:139`'s speculative seam-list entry for `core/PerfSetup.lua` now finds a real file and its L-trap assertion runs. |
| 2.3 | **Stub-coverage sweep:** grep every member the addon reaches on `NS.Perf` and confirm the library-absent branch answers **all** of them. Add a case in the shape of the existing *"the Core stub answers every member the addon calls"*. | LH-20 | `core/PerfSetup.lua`, `tests/test_libka0s.lua` | The degraded-load case (`tests/test_libka0s.lua:48-62`) still loads the whole addon with LibKa0s absent, with no error. |
| 2.4 | `LootHistory.toc:7` → `## SavedVariables: LootHistoryDB, LootHistoryPerfDB`. Hand the **name** (not a table) to the descriptor. Update `docs/saved-variables.md`. | LH-21 | `LootHistory.toc`, `core/PerfSetup.lua`, `docs/saved-variables.md` | TOC declares exactly two globals in the mandated order. |
| 2.5 | `.luacheckrc`: add `"debugprofilestop"` to `read_globals`; add `LootHistoryPerfDB` **with a comment** to `globals`. | LH-26 | `.luacheckrc` | `luacheck .` still 0/0 after the brackets land (2.7). |
| 2.6 | Add the `perf` verb to `NS.COMMANDS` (after `debug`, before `version`), dispatching to the library's command entry point and printing through the shared printer. Ripple into the README `### Slash commands` table and `docs/ARCHITECTURE.md`'s `## Slash commands` table **in the same change**. | LH-22 | `settings/Schema.lua`, `README.md`, `docs/ARCHITECTURE.md` | `/lh perf` no longer reaches the unknown-verb path; the landing page picks the row up via `Sl:LandingRows()` with no extra work. |
| 2.7 | Declare the buckets and add the brackets in the exact `local t0 = Perf.on and debugprofilestop()` … `if t0 then Perf.Note(key, debugprofilestop() - t0) end` shape: `lootCapture` in `modules/Collector.lua`, `tableRender` + nested `tableBind` in `modules/BrowserTable.lua`. Nothing allocated, concatenated or formatted inside a bracket while capture is off. | LH-20 (coverage) | `core/PerfSetup.lua`, `modules/Collector.lua`, `modules/BrowserTable.lua` | A case per bucket proves **each declared bucket is reached by a real bracket**, driving its genuine entry point (`performance-§3`, `testing-§8`). |
| 2.8 | Implement `suspend`/`resume` per the resolution chosen in Sprint 0.1: unregister events, cancel queued work, gate the show-decision ladder at the source on session-only `NS.State.suspended`, restore from current state, never persist, resume before saving/reporting. If resolution 2, add the confirm dialog beside the existing popups. If Branch B carried, **skip and record the accepted deviation**. | LH-23 | `core/State.lua`, `core/PerfSetup.lua`, `modules/Collector.lua`, `modules/Attribution.lua`, `modules/Browser.lua` | A case proves **suspend genuinely makes this addon inert** — events unregistered, queued work canceled, the show ladder refusing — and that resume restores from current state (`testing-§8`). |
| 2.9 | Write `tests/perf.lua`: TOC-derived load list, the required **zero-overhead** scenario over `lootCapture`, plus a `tableRender` allocation scenario. Assert on call counts and bytes only, never wall-clock. **Do not** add it to `tests/run.lua`'s suite list. | LH-24 | new `tests/perf.lua` | `lua tests/perf.lua` runs and reports; `lua tests/run.lua` does **not** run it; the zero-overhead figure is committed as the evidence `performance-§2` requires. |
| 2.10 | Extend Sprint 1.7's pinning to `tests/perf.lua` by **reading its source** for the `Loader.tocFiles` call (the gate does not execute it). | LH-29 (extension) | `tests/test_runner.lua` | The case names the file and the derivation call. |
| 2.11 | Author `docs/performance.md` and `docs/perf-runs/README.md` per `04` §1.7; add both to `docs/ARCHITECTURE.md`'s `## Doc index`. | LH-25 | `docs/performance.md`, `docs/perf-runs/README.md`, `docs/ARCHITECTURE.md` | Both exist and point at the library for the shared protocol rather than restating it. |
| 2.12 | Regenerate `docs/test-cases.md`, update the README `[tests]` badge, bump the version (**MINOR**) across TOC `## Version`, `core/Namespace.lua:5`, the README badge row and a new `## Version History` row, and roll `## What's new` forward — all in one change. | — (`versioning-git`, `documentation-§1`, AP #40) | `LootHistory.toc`, `core/Namespace.lua`, `README.md`, `docs/test-cases.md` | `## What's new in <new>` matches the new top Version History row. |
| 2.13 | In-game smoke pass: `/lh perf` opens the guided step panel; the panel wears the host's chrome via the `applySkin` hook and the **library's** close glyph; capture lifecycle lines land on the debug console; a full A/B run persists a record and **resumes before reporting**. Add the steps to `docs/smoke-tests.md`. | LH-20…LH-24 | `docs/smoke-tests.md` | Smoke steps recorded and passed. |

---

## Sprint 3 — SHOULD-level (independent; can run alongside Sprint 1)

| # | Step | Closes | Files | Done when |
|---|---|---|---|---|
| 3.1 | Rewrite the two retired citations: `settings/OptionsSetup.lua:99` `§3.4` → `library-stack-§4`; `tests/test_database.lua:363` `§2.2/§5.1` → `toc-file-§2` / `savedvariables-§1`. Leave `docs/superpowers/specs/**` alone (own internal numbering). | LH-19 | 2 files | The repo-wide `§N.M` sweep in `03_EVIDENCE.md` §LH-19 returns only the `docs/superpowers/specs/**` hits. |
| 3.2 | Delegate the window edge: resolve `LibKa0s-Core-1.0` in `modules/Browser.lua` and have `B:ApplySkin` call `Core.ApplySkin(f)`, keeping the current body as the library-absent fallback. Drop `bg`/`border`/`innerBorder`/`divider`/`title` from `B.SKIN`; keep the genuinely host-owned geometry and tab colors. | LH-30 | `modules/Browser.lua` | Suite green; a smoke step confirms the History window, the Export window and the debug console are **pixel-identical** afterward (they should be — the values already agree). |
| 3.3 | Add the LH-30 comparison to `docs/smoke-tests.md` as a standing step (all Ka0s windows side by side). | LH-30 | `docs/smoke-tests.md` | Step recorded. |
| 3.4 | Run `lizard` over `core/ defaults/ locales/ modules/ settings/`, commit `docs/complexity.md` stating that it is generated and how. Do **not** gate commits on it. | LH-31 | new `docs/complexity.md` | The report exists and covers the three 1000–1500 LOC files. |

---

## Sprint 4 — Advisory (user decision only; no work implied)

| # | Step | Relates to | Note |
|---|---|---|---|
| 4.1 | Decide whether `docs/pending/LEDGER.md` stays. It is **not** a `TODO.md` and breaks no rule, and it is currently the standard's own prescribed home for LH-20's accepted deviation — but it is a second backlog beside GitHub issues. | LH-32 | **No action recommended without a user decision.** If it stays, nothing changes. |
| 4.2 | Decide whether `media/logos/wowhead-logo.png` is deleted. Its only references are in a retired "Export to AI" plan doc for a feature removed in 1.2.0; it ships to players and WoW cannot load `.png` at runtime. | LH-33 | Cosmetic package hygiene. If deleted, sweep the rest of the AI-export residue at the same time. |

---

## Verification checklist for the whole engagement

- [ ] `luacheck .` → 0 warnings / 0 errors.
- [ ] `lua tests/run.lua` → all green, exit 0.
- [ ] `docs/test-cases.md` total == run total == README `[tests]` badge.
- [ ] `diff -r ../LibKa0s/LibKa0s libs/LibKa0s` → **empty**.
- [ ] `diff -r ../LibKa0s/testkit tests/_kit` → **empty**.
- [ ] `lua tests/perf.lua` runs, is **not** in the green gate, and its zero-overhead figure is committed.
- [ ] TOC declares exactly `LootHistoryDB, LootHistoryPerfDB`.
- [ ] `/lh perf`, `/lh help` and the settings landing page all list the same verb set.
- [ ] README `[wow]` badge, TOC `## Interface:`, `## What's new` and the top Version History row all agree.
- [ ] Nothing under `libs/` or `tests/_kit/` was edited.
- [ ] `docs/audits/2026-08-04/` was not modified after this run — a re-audit is a **new** dated folder.
