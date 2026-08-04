# Ka0s Loot History — Execution Plan (2026-08-03)

Implements `02_PROPOSED_CHANGES.md`. Verified by `03_SMOKE_TESTS.md`.

**Standing rules for every task**
- TDD: a failing case first, then the fix (testing). `lua tests/run.lua` must be **green before every
  commit** (testing-§6, versioning-git).
- `luacheck .` must be zero-error (lint).
- **No task may edit a file under `libs/` or `tests/_kit/`.** Those are vendored copies; a local edit
  is silently reverted by the next re-vendor.
- Trunk-based: work on the current branch unless the user explicitly asks for one.

---

## Milestone M0 — Correctness (the three user-visible bugs)

**Done when:** C-001, C-002 and C-003 are implemented, the suite is green with new regression cases
for each, and the C-001/C-002/C-003 sections of `03_SMOKE_TESTS.md` pass in-client.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| T-01 | `lua-refactorer` | C-001 (F-001, F-013) | `settings/Panel.lua`, `tests/test_panel.lua` |
| T-02 | `lua-refactorer` | C-002 (F-002) | `settings/Panel.lua`, `tests/test_panel.lua` |
| T-03 | `ux-cleanup` | C-003 (F-003) | `modules/BrowserTable.lua`, `tests/test_browsertable.lua` |

**Concurrency:** T-01 and T-02 both touch `settings/Panel.lua` and `tests/test_panel.lua` →
**must serialize**, T-01 first (it settles the refresh contract T-02 then relies on).
T-03 is **parallelizable** with both — disjoint file set.

**Checkpoint CP-0 (human):** before starting M1, confirm in-client that the Filters page picks up an
off-screen blacklist add and that preview mode cannot touch live data. These are the two findings a
user would actually report; everything after this is optimization and hygiene.

---

## Milestone M1 — Hot paths

**Done when:** C-004 and C-005 are implemented, the suite is green, and the C-004/C-005 smoke
sections plus the two performance spot-checks pass with recorded before/after numbers.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| T-04 | `perf-engineer` | C-004 (F-004) — repaint debounce | `modules/Browser.lua`, `tests/test_browser.lua` |
| T-05 | `perf-engineer` | C-004 (F-004) — allocation-free `estimateRecordBytes` | `core/Database.lua`, `tests/test_database.lua` |
| T-06 | `perf-engineer` | C-005 (F-005) | `modules/Analytics.lua`, `tests/test_analytics.lua` |

**Concurrency:** T-04, T-05 and T-06 touch three disjoint module files and three disjoint test files
→ **all three parallelizable**. T-05's test must pin the *byte total* as unchanged, so it is a pure
refactor with an exact-equality assertion.

**Checkpoint CP-1 (human):** record the `collectgarbage("count")` and `GetAddOnCPUUsage` deltas
before/after. They become the "Performance impact" section of `05_FINAL_SUMMARY.md` and the baseline
M2's harness will later reproduce properly.

---

## Milestone M2 — Performance harness adoption

**Done when:** `/lh perf` runs a complete two-arm capture on a live client, `LootHistoryPerfDB` is
written outside the AceDB tree, every declared bucket is reached, `tests/perf.lua` passes outside the
green gate, the degraded-install check passes, and `docs/performance.md` + `docs/perf-runs/README.md`
exist.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| T-07 | `lua-refactorer` | C-006 — setup file + descriptor + degradation stub | `core/PerfSetup.lua` (new), `LootHistory.toc` |
| T-08 | `lua-refactorer` | C-006 — the `perf` verb | `settings/Schema.lua` (`NS.COMMANDS`) |
| T-09 | `perf-engineer` | C-006 — brackets around `historyRepaint`, `insightsLayout`, `lootCapture` | `modules/Browser.lua`, `modules/Analytics.lua`, `modules/Collector.lua` |
| T-10 | `lua-refactorer` | C-006 — SV global + lint globals | `LootHistory.toc`, `.luacheckrc` |
| T-11 | `test-author` | C-006 — integration coverage + offline runner | `tests/test_libka0s.lua`, `tests/perf.lua` (new) |
| T-12 | `docs-author` | C-006 — required docs | `docs/performance.md` (new), `docs/perf-runs/README.md` (new), `docs/ARCHITECTURE.md`, `README.md` |

**Concurrency:**
- T-07 and T-10 both touch `LootHistory.toc` → **must serialize** (T-07 first: it adds the file entry,
  T-10 amends the SavedVariables line). Consider folding them into one commit.
- T-09 touches `modules/Browser.lua` and `modules/Analytics.lua`, which **M1's T-04 and T-06 also
  touch** → T-09 **must run after M1 completes**. Do not parallelize across milestones here.
- T-08 (`settings/Schema.lua`) is disjoint from everything else in M2 → **parallelizable**.
- T-11 depends on T-07/T-08/T-09 being in place (it asserts every declared bucket is reached, which
  needs the brackets) → **serialize last**.
- T-12 is **parallelizable** throughout, but must be re-read against the final descriptor before the
  milestone closes.

**Checkpoint CP-2 (human):** run a real two-arm capture on a dummy and eyeball the report before
declaring M2 done. Specifically confirm (a) suspend needs **no** `/reload`, (b) the addon is resumed
**before** the report is written, and (c) no bucket reports zero samples.

---

## Milestone M3 — Defaults, comments and polish

**Done when:** C-007 through C-012 are implemented, the suite is green, and the corresponding smoke
sections plus regression checks R2, R6, R8, R9 pass.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| T-13 | `lua-refactorer` | C-007 (F-007) + C-008 (F-009) | `defaults/Global.lua`, `tests/test_database.lua`, `tests/test_auctionprice.lua` |
| T-14 | `ux-cleanup` | C-010 (F-011) | `modules/Browser.lua`, `LootHistory.toc`, possibly `media/logos/` |
| T-15 | `ux-cleanup` | C-011 (F-012) | `modules/BrowserTable.lua`, `tests/test_browsertable.lua` |
| T-16 | `lua-refactorer` | C-012 (F-008, F-014) | `settings/Slash.lua`, `modules/Collector.lua`, `modules/Browser.lua`, `modules/Analytics.lua`, `tests/test_slash.lua` |
| T-17 | `docs-author` | C-009 (F-010) | `settings/OptionsSetup.lua` |

**Concurrency:**
- T-14 and T-16 both touch `modules/Browser.lua` → **must serialize**.
- T-16 also touches `modules/Analytics.lua` and `modules/Collector.lua`, which **M2's T-09 touches**
  → run T-16 after M2, or accept a merge in one of them.
- T-13, T-15 and T-17 are **parallelizable** with each other and with everything above.

**Checkpoint CP-3 (human):** wipe SavedVariables and do a genuine cold first-login pass. C-007 and
C-008 only show their true behavior on a database that has never existed before.

---

## Milestone M4 — Upstream follow-up (optional, cross-repo)

This milestone lands in a **different repository**. It is deliberately separate from every task above
and **must not** be folded into one that edits this addon's own files.

**Done when:** the additive seam is released in `LibKa0s` and re-vendored here as its own commit.

| Task | Owner role | Implements | Repo / files |
|---|---|---|---|
| T-18 | `library-author` | Add public `O.MarkDirty(ctx)` to `LibKa0s-Options-1.0` (additive; sets `_dirty` for a hidden ctx with a renderer) | **`LibKa0s` repo** — `Options.lua` |
| T-19 | `library-author` | Bump `LibKa0s-Options-1.0`'s **file minor** and add the changelog entry; cut a release tag | **`LibKa0s` repo** |
| T-20 | `vendor-maintainer` | Re-vendor the **whole** `libs/LibKa0s/` folder into this addon; update the README provenance line in the **same commit**; `tests/test_vendor_sync.lua` must go green against the new tag | **this repo** — `libs/LibKa0s/**`, `README.md` |
| T-21 | `lua-refactorer` | Optionally switch C-001's call from `O.RefreshAllPanels()` to `O.MarkDirty(ctx)` | **this repo** — `settings/Panel.lua` |

**Exit criterion:** a **re-vendor commit in this repo** whose only content is the copied folder plus
the provenance line, with `tests/test_vendor_sync.lua` green. T-21 is a separate commit after it.

**Concurrency:** T-18 → T-19 → T-20 → T-21 is a strict chain across two repositories. Nothing in
M0–M3 may wait on it: C-001 ships complete without any of this.

**Checkpoint CP-4 (human):** confirm the re-vendor commit is standalone before T-21 changes any call
site. A re-vendor mixed with a behavior change is exactly the commit that makes a future regression
untraceable.

---

## Critical path

```
M0: T-01 → T-02          (T-03 parallel)
        ↓ CP-0
M1: T-04 ‖ T-05 ‖ T-06
        ↓ CP-1
M2: T-07 → T-10          (T-08, T-12 parallel)  →  T-09  →  T-11
        ↓ CP-2
M3: T-14 → T-16          (T-13, T-15, T-17 parallel)
        ↓ CP-3
M4: T-18 → T-19 → T-20 → T-21   (cross-repo; off the critical path)
```

**Serialization callouts (files touched by more than one task):**
- `settings/Panel.lua` — T-01, T-02
- `modules/Browser.lua` — T-04, T-09, T-14, T-16
- `modules/Analytics.lua` — T-06, T-09, T-16
- `modules/BrowserTable.lua` — T-03, T-15
- `LootHistory.toc` — T-07, T-10, T-14
- `tests/test_panel.lua` — T-01, T-02
- `tests/test_browsertable.lua` — T-03, T-15

---

## Incremental commit strategy

One commit per task, each green. Suggested messages (US English throughout — localization-§5):

| Task | Message |
|---|---|
| T-01 | `fix(panel): rebuild the Filters page on its next open after an off-screen change (F-001)` |
| T-02 | `fix(panel): stop the history-stats subscription from holding a released widget (F-002)` |
| T-03 | `fix(browser): preview mode is read-only — disable blacklist and delete on test rows (F-003)` |
| T-04 | `perf(browser): coalesce the record-added repaint (F-004)` |
| T-05 | `perf(db): drop the per-record table allocation from the byte estimate (F-004)` |
| T-06 | `perf(insights): throttle the chart relayout on window resize (F-005)` |
| T-07+T-10 | `feat(perf): wire LibKa0s-Perf-1.0 — descriptor, stub, LootHistoryPerfDB (F-006)` |
| T-08 | `feat(slash): add the reserved perf verb to NS.COMMANDS (F-006)` |
| T-09 | `feat(perf): bracket the loot-capture, history-repaint and insights-layout buckets (F-006)` |
| T-11 | `test(perf): integration coverage plus the offline scenario runner (F-006)` |
| T-12 | `docs(perf): add docs/performance.md and docs/perf-runs/README.md (F-006)` |
| T-13 | `fix(defaults): one source of truth for the AH defaults; ship the current schema stamp (F-007, F-009)` |
| T-14 | `fix(ui): one mark for the addon across minimap, TOC and settings (F-011)` |
| T-15 | `fix(browser): /lh test no longer opens the window on the way out (F-012)` |
| T-16 | `fix(slash,bus): close the stub surface gap and the bus-target fallback (F-008, F-014)` |
| T-17 | `docs: use the filename-§N reference form (F-010)` |
| T-20 | `chore(libs): re-vendor LibKa0s <tag> (Options minor <n>)` |
| T-21 | `refactor(panel): use O.MarkDirty for the hidden-page refresh (F-001)` |

Bump the addon version (`LootHistory.toc` `## Version` **and** `core/Namespace.lua:5` — they must
move together) once per milestone group, at the point the milestone closes, per versioning-git semver:
M0+M1+M3 are a patch/minor depending on whether the UX changes are user-visible enough; M2 is a
**minor** (new `perf` verb, new SV global, additive).
