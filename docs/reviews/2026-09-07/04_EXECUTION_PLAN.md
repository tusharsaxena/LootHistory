# 04 — Execution plan

Derived from `02_PROPOSED_CHANGES.md`. Ordered so that the one change with a user-visible behaviour shift lands first and alone, and the mechanical whole-tree change lands last where it cannot obscure anything.

**There is no upstream milestone.** This review raised no `[upstream]` finding; `libs/LibKa0s/` and `tests/_kit/` were verified byte-identical to `v1.25.0` and no task below touches either.

---

## Milestone M1 — the storage estimate, and the test that can prove it

**Done when:** `Database:StorageStats().bytes` counts every populated string field on every record shape, the suite has a case that goes red if that regresses, and `docs/test-cases.md` + the README badge read 700.

| Task | Owner-agent role | Finding / change IDs | Files touched |
|---|---|---|---|
| **T1.1** | lua-refactorer | F-001, F-004 / C-01 | `core/Database.lua` |
| **T1.2** | test-author | F-002 / C-02 | `tests/test_database.lua` |
| **T1.3** | docs-sync | — (`testing-§7` obligation of T1.2) | `docs/test-cases.md` (regenerated), `README.md` |

**Serialization:** T1.1 → T1.2 → T1.3, strictly. T1.2's new assertion is written against T1.1's corrected output; T1.3 regenerates from T1.2's run. **Never** hand-edit `docs/test-cases.md` — `lua tests/run.lua --list > docs/test-cases.md`.

**Note for T1.2:** the existing case at `tests/test_database.lua:379` must be strengthened as well as the new one added — leaving `assertTrue(s.bytes > 0)` in place preserves the hole this milestone exists to close.

---

## Milestone M2 — finish the coalescing pass

**Done when:** all three `Ka0s_LootHistory_RecordAdded` consumers are coalesced, `HistoryChanged` stays immediate at all three, and the settings storage line still updates after a loot burst.

| Task | Owner-agent role | Finding / change IDs | Files touched |
|---|---|---|---|
| **T2.1** | lua-refactorer | F-003 / C-03 | `settings/Panel.lua` |

**Parallelizable with M1** — disjoint file sets (`settings/Panel.lua` vs. `core/Database.lua` + `tests/test_database.lua`). Note the *semantic* coupling: M2 reduces how often M1's function is called, so if both land together the C-01 perf claim and the C-03 perf claim are measured against a moving baseline. Land M1 first if the in-client GC comparison in `03_SMOKE_TESTS.md` C-03 is to mean anything.

---

## Milestone M3 — the guard rails over the unpinned wiring

**Done when:** `Attribution:Enable`'s registration set, the runner's lifecycle kick and `NS.version`-vs-TOC each have a case that fails when they drift, and the inventory + badge read 703.

| Task | Owner-agent role | Finding / change IDs | Files touched |
|---|---|---|---|
| **T3.1** | test-author | F-008 / C-06 | `tests/test_attribution.lua` |
| **T3.2** | test-author | F-009 / C-07 | `tests/test_harness.lua`, `tests/run.lua` |
| **T3.3** | test-author | F-018 / C-08 | `tests/test_envsetup.lua` |
| **T3.4** | docs-sync | — (`testing-§7`) | `docs/test-cases.md`, `README.md` |

**Concurrency:** T3.1, T3.2 and T3.3 touch disjoint suite files and are **parallelizable** among themselves. T3.4 serializes after all three — one badge move for the milestone, not three.

**Conflict callout:** T3.2 edits `tests/run.lua`, which **every** suite loads. It must not run concurrently with T1.2 or T3.1/T3.3 in a way that leaves the runner half-edited; give T3.2 exclusive possession of `tests/run.lua` for its duration.

**Hard rule for T3.2:** if `Slash:Register` genuinely cannot run headless, the case asserts the **deliberate** omission with a comment naming why. It does **not** get weakened to accept whatever the runner happens to call today — that would re-create the silent list this milestone exists to remove.

---

## Milestone M4 — the performance record tells the truth again

**Done when:** `docs/performance.md`'s two sweeps are regenerated from its own commands, every `file:line` in them resolves, and the `CHAT_MSG_LOOT` row names the tooltip build and the AH cascade.

| Task | Owner-agent role | Finding / change IDs | Files touched |
|---|---|---|---|
| **T4.1** | docs-sync | F-005, F-007 / C-04 (parts 1 and 3) | `docs/performance.md` |
| **T4.2** | docs-sync | F-006 / C-04 (part 2) | `docs/performance.md` |

**Serialization:** T4.1 → T4.2, same file.

**Dependency:** T4.1 must run **after** M2, because M2 changes `settings/Panel.lua`'s bus wiring and the sweep's message-bus paragraph (`docs/performance.md:66-80`) should describe the post-M2 state, not the pre-M2 one.

---

## ⛔ CHECKPOINT 1 — human decision, before M5

**Runs after M4 and before anything else.** Not a task an agent completes.

With T4.2's honest description of the `CHAT_MSG_LOOT` path in front of them, the maintainer decides whether `performance-§12` criterion **(a)** still holds:

> *"no `OnUpdate` handler, no repeating ticker, and no event handler doing more than occasional work while the player is in combat."*

The path in question builds a `C_TooltipInfo` tooltip and runs a cross-addon price cascade, once per looted item, during combat with autoloot on.

- **If (a) holds:** record *why* in `docs/performance.md`'s criterion (a) paragraph — that the work is bounded by loot-line frequency rather than frame rate, and that criterion (c) is independently load-bearing. No code change. Proceed to M5.
- **If (a) does not hold:** the full `performance-§1` wiring MUST re-arms. That is **its own project** — `core/PerfSetup.lua`, a bucket descriptor, `tests/perf.lua`, the `/lh perf` verb, a `docs/perf-analysis/` store, and a rewrite of the `LH-20`…`LH-26` register entries. It is explicitly **out of scope** for this change-set and is carried in `05_FINAL_SUMMARY.md` under known follow-ups. Do not begin it inside M5.

**Nothing downstream depends on which way this goes.** M5 and M6 proceed either way.

---

## Milestone M5 — the small true things

**Done when:** the five comment/naming/behaviour corrections have landed, the suite is green, and the inventory + badge read 704.

| Task | Owner-agent role | Finding / change IDs | Files touched |
|---|---|---|---|
| **T5.1** | localization-fixer | F-012 / C-09 | `core/Compat.lua`, `modules/Attribution.lua`, `tests/test_compat.lua` |
| **T5.2** | ux-cleanup | F-016 / C-10 item 4 | `settings/Slash.lua`, `tests/test_libka0s.lua` |
| **T5.3** | lua-refactorer | F-017 / C-10 item 5 | `modules/Attribution.lua`, `modules/Collector.lua`, `tests/test_attribution.lua` |
| **T5.4** | docs-sync | F-013, F-014 / C-10 items 1–3 | `modules/Browser.lua`, `defaults/Global.lua`, `core/Database.lua` |
| **T5.5** | docs-sync | — (`testing-§7`, for T5.1's new case) | `docs/test-cases.md`, `README.md` |

**Concurrency map:**

- **T5.1 and T5.3 both touch `modules/Attribution.lua` → MUST SERIALIZE.** T5.1 edits `seedToken` (`:63-68`); T5.3 renames `Consume` (`:127`). Different functions, same file — run T5.1 then T5.3.
- **T5.3 and T3.1 both touch `tests/test_attribution.lua` → MUST SERIALIZE.** M3 completes before M5 begins, so this is satisfied by milestone ordering; do not run them concurrently across milestones.
- **T5.2 and T5.4 are parallelizable** with each other and with the T5.1→T5.3 chain — disjoint files.
- **T5.5 serializes last.**

---

## Milestone M6 — renormalize the working tree

**Done when:** every tracked non-binary file except `tests/_kit/run-automated-tests.sh` has equal CR and LF byte counts, that one file has zero CRs, and both gate suites are green.

| Task | Owner-agent role | Finding / change IDs | Files touched |
|---|---|---|---|
| **T6.1** | repo-hygiene | F-015 / C-11 | the nine files listed in F-015 |

**MUST be last, and MUST be its own commit.** It rewrites whole files with no semantic change; interleaved with any other task it makes both diffs unreadable and makes a bisect of this pass useless. `.gitattributes` is already correct and is **not** edited.

**Verification, per `line-endings-§7`** — byte counts, never `file`:

```sh
tr -dc '\r' < <path> | wc -c     # must equal…
tr -dc '\n' < <path> | wc -c     # …this
```

`tests/test_vendor_sync.lua` strips CR on the working-tree side before comparing, so the vendored-payload gate is unaffected.

---

## ⛔ CHECKPOINT 2 — pre-handoff verification

**After M6, before the smoke tests.** Confirm all of:

1. `lua tests/run.lua` → `704 passed, 0 failed, 0 skipped, 704 total`.
2. `luacheck .` → `0 warnings / 0 errors in 28 files`.
3. `diff <(lua tests/run.lua --list) docs/test-cases.md` → empty.
4. `README.md:7`'s `[Tests]` badge reads `704%2F704_passing`.
5. `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` → still `No thresholds exceeded`. **To a scratch path.** Do not write it into the repo; the record's checkpoint is release (`/wow-addon:bump-version`), not this pass.
6. The vendor-sync cases still report as passes, not skips — i.e. the sibling `LibKa0s` checkout is present and the payload still matches `v1.25.0`.

Then hand `03_SMOKE_TESTS.md` to the human for the in-client pass.

---

## Critical-path / concurrency summary

```
M1 (Database + its test)  ─┐
                           ├─► M3 (guard rails) ─► M4 (perf doc) ─► ⛔CP1 ─► M5 (small things) ─► M6 (line endings) ─► ⛔CP2
M2 (Panel coalesce)       ─┘
```

- **M1 ∥ M2** — disjoint files. Land M1 first if C-03's GC comparison is to be measured against a stable baseline.
- **M3's three test tasks are parallel among themselves**; T3.2 needs exclusive `tests/run.lua`.
- **M4 depends on M2** (the bus paragraph must describe the post-coalesce state).
- **M5's T5.1 → T5.3 chain is serial** (`modules/Attribution.lua`); T5.2 and T5.4 are free.
- **M6 is strictly last and strictly alone.**

**Files touched by more than one milestone — the serialization callouts:**

| File | Milestones | Resolution |
|---|---|---|
| `modules/Attribution.lua` | M5 (T5.1, T5.3) | serialize T5.1 → T5.3 |
| `tests/test_attribution.lua` | M3 (T3.1), M5 (T5.3) | milestone ordering already serializes them |
| `tests/run.lua` | M3 (T3.2) | exclusive possession for T3.2's duration |
| `docs/test-cases.md`, `README.md` | M1, M3, M5 | one regeneration at the end of each milestone, never mid-milestone |
| `docs/performance.md` | M4 (T4.1, T4.2) | serialize T4.1 → T4.2 |
| every `.lua` | M6 | M6 last and alone |

---

## Incremental commit strategy

One commit per milestone, except M5 where the tasks are independent enough to read better separately and M6 which must stand alone.

| # | Commit message |
|---|---|
| 1 | `fix(database): the byte estimate stops at the first nil field, so currency rows counted 256` |
| 2 | `test(database): the storage estimate case asserts a total, not that it is positive` — *(may be folded into 1; must not land after it in a separate release)* |
| 3 | `perf(settings): coalesce the panel's RecordAdded listener, like its two siblings` |
| 4 | `test: pin Attribution:Enable's wiring, the runner's lifecycle kick, and NS.version against the TOC` |
| 5 | `docs(performance): the sweep says thirteen events and five timers, because that is what the tree says` |
| 6 | `fix(locale): NBSP is not %s — widen the two trims that read localized tooltip and spell text` |
| 7 | `fix(slash): the degraded help stops advertising a config verb that declines` |
| 8 | `refactor(attribution): Consume peeks, so call it that` |
| 9 | `docs: three comments that describe a migration chain and a close path that moved on` |
| 10 | `chore: renormalize line endings (no semantic change)` |

Each commit that moves the pass count carries its `docs/test-cases.md` regeneration and its README badge bump **in the same commit** (`testing-§7`). Reference the finding IDs (`F-001`…`F-018`) in the commit bodies so this bundle stays reachable from the log.
