# 04 — Execution plan

Implements `02_PROPOSED_CHANGES.md`. Eight changes, four milestones. No milestone touches `libs/` or
`tests/_kit/` — there are no upstream findings in this review, so there is no cross-repo handoff and
no re-vendor commit.

Standing rule for every task: the commit gate is **clean `luacheck .` + green `lua5.1
tests/run.lua`** (`testing-§4`, `anti-patterns #23`). A task that moves the pass count regenerates
`docs/test-cases.md` and updates the README `[Tests]` badge **in its own commit** (`testing-§7`).

---

## Milestone M1 — The functional defect

**Done when:** a fresh install stores all 11 priority tags, a CLI-enabled price key is selectable
without ever opening the AH Price page, `Schema:Register`'s check can fail, and the suite has cases
for both.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| T1.1 | lua-refactorer | C-01 (F-001) | `defaults/Global.lua` |
| T1.2 | test-author | C-01 coverage | `tests/test_schema.lua` |
| T1.3 | lua-refactorer | C-02 (F-002) | `settings/Schema.lua` |
| T1.4 | test-author | C-02 coverage | `tests/test_schema.lua` |
| T1.5 | docs-scribe | inventory + badge | `docs/test-cases.md`, `README.md` |

**Concurrency.** T1.1 ∥ T1.3 — disjoint files. **T1.2 and T1.4 both touch
`tests/test_schema.lua` → serialize** (T1.2 then T1.4). T1.5 runs last, after both test tasks, and
regenerates rather than hand-edits (`lua tests/run.lua --list > docs/test-cases.md`).

**Write the tests first.** T1.2's case must go **red** against the current `defaults/Global.lua` —
run it before T1.1 lands and confirm it fails with "7 vs 11" — otherwise it is a case that proves
nothing (`testing-§12`). Same for T1.4 against the `and` form.

**Checkpoint C-M1 (human).** Confirm the two new cases were observed red before their fix landed,
and that the pass count in `docs/test-cases.md`, in `README.md:7` and in the runner's own output all
read the same number.

---

## Milestone M2 — The degraded install

**Done when:** neither receiver can land on the shared bus target, every degradation stub answers
every member the addon calls, and a bare `/lh` on a library-less install lists the verbs that work.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| T2.1 | lua-refactorer | C-03 (F-003) | `modules/Collector.lua`, `modules/Browser.lua` |
| T2.2 | test-author | C-03 coverage | `tests/test_libka0s.lua` |
| T2.3 | test-author | C-06 the surface-diff case | `tests/test_libka0s.lua` |
| T2.4 | lua-refactorer | C-06 stub corrections | `settings/Slash.lua`, `core/DebugLogSetup.lua` |
| T2.5 | ux-cleanup | C-08 (F-010) | `settings/Slash.lua` |
| T2.6 | test-author | C-08 coverage | `tests/test_slash.lua` |
| T2.7 | docs-scribe | inventory + badge | `docs/test-cases.md`, `README.md` |

**Concurrency.**
- **T2.2 and T2.3 both touch `tests/test_libka0s.lua` → serialize.**
- **T2.4 and T2.5 both touch `settings/Slash.lua` → serialize** (T2.4 first: T2.5 edits the same
  degraded branch, and landing the stub member before the verb listing avoids a rebase over the same
  hunk).
- T2.1 is parallelizable against everything else in this milestone (`Collector.lua` / `Browser.lua`
  are touched by nothing else here).
- T2.3 must run **before** T2.4 so the new case is what identifies `HelpHeader` as missing, rather
  than the fix being written first and the case retro-fitted to it.
- T2.7 last.

**Ordering constraint against M1.** None — M1 and M2 touch disjoint files except
`docs/test-cases.md` and `README.md`, which are regenerated per milestone. Run M1 first anyway: it
carries the only user-visible defect.

**Checkpoint C-M2 (human).** Run smoke test **T4** from `03_SMOKE_TESTS.md` — the folder-rename
degraded install — before proceeding. This is the one milestone whose behavior no headless case can
fully witness, because it depends on how the real client loads a missing folder.

---

## Milestone M3 — Truthfulness (labels, comments, suppressions, case names)

**Done when:** the panel's destructive reset no longer borrows the reserved verb's name, no comment
names a reader that does not exist, the stale lint suppression is gone, and the two vendor-sync
cases disclose their skip.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| T3.1 | ux-cleanup | C-04 (F-004) | `settings/Panel.lua` |
| T3.2 | docs-scribe | C-07 comments (F-007) | `settings/Slash.lua` |
| T3.3 | lua-refactorer | C-07 suppression (F-008) | `modules/AuctionPrice.lua` |
| T3.4 | test-author | C-05 (F-005) | `tests/test_vendor_sync.lua` |
| T3.5 | docs-scribe | inventory (titles moved, count unchanged) | `docs/test-cases.md` |

**Concurrency.** T3.1, T3.2, T3.3 and T3.4 have **disjoint file sets — all four parallelizable**.
T3.5 last.

**Note on T3.5.** C-05 moves two case *titles* without moving the count, so `docs/test-cases.md`
changes but `README.md:7`'s badge does **not**. Do not touch the badge in this milestone.

**Ordering constraint against M2.** **T3.2 touches `settings/Slash.lua`, which T2.4 and T2.5 also
touch → M3 must start after M2's Slash tasks are committed**, or T3.2 must be folded into M2 as a
trailing task on the same file.

---

## Milestone M4 — Verification and close-out

**Done when:** all four out-of-game suites are green on the final tree, the in-client checklist is
signed off, and `05_FINAL_SUMMARY.md` is filled in with the real numbers.

| Task | Owner role | Implements | Files touched |
|---|---|---|---|
| T4.1 | verifier | re-run `luacheck .`, `lua5.1 tests/run.lua`, `--list` diff, `lizard` | none (scratch output) |
| T4.2 | human / QA | execute `03_SMOKE_TESTS.md`, fill the sign-off table | `docs/reviews/2026-08-05/03_SMOKE_TESTS.md` |
| T4.3 | docs-scribe | complete `05_FINAL_SUMMARY.md` with observed counts | `docs/reviews/2026-08-05/05_FINAL_SUMMARY.md` |

**Explicitly not in this plan.** Regenerating `docs/automated-tests/` or writing a run bundle — that
is `/wow-addon:automated-tests`, and a full bundle belongs to **release**
(`automated-tests-§4/§6`). Do not run it as part of this work and do not hand-edit `RESULTS.md`.

**Checkpoint C-M4 (human).** The last `--list` diff against `docs/test-cases.md` must be empty. If it
is not, a milestone regenerated at the wrong point — regenerate once more and commit that alone.

---

## Critical path

```
M1 (T1.1 ∥ T1.3) → T1.2 → T1.4 → T1.5 → [C-M1]
      ↓
M2   T2.1 ∥ (T2.3 → T2.4 → T2.5 → T2.6) , T2.2 after T2.3 → T2.7 → [C-M2, smoke T4]
      ↓
M3   T3.1 ∥ T3.3 ∥ T3.4 ∥ T3.2(after M2's Slash tasks) → T3.5
      ↓
M4   T4.1 → T4.2 → T4.3 → [C-M4]
```

**Serialization callouts, restated plainly:**
- `tests/test_schema.lua` — T1.2, T1.4
- `tests/test_libka0s.lua` — T2.2, T2.3
- `settings/Slash.lua` — T2.4, T2.5, T3.2
- `docs/test-cases.md` — T1.5, T2.7, T3.5 (one regeneration per milestone, never concurrent)

---

## Commit strategy

One commit per task, each green on its own. Suggested subjects:

```
defaults: single-source the auction capture/priority tables from Constants   [F-001]
tests: pin defaults/Global against AUCTION_PRIORITY_DEFAULT, cover table rows [F-001]
schema: Register's boot check must be able to fail (and -> or)                [F-002]
tests: Register reports a path missing from defaults                          [F-002]
collector/browser: no shared-bus fallback for a receiver target               [F-003]
tests: every bus receiver owns a distinct target                              [F-003]
tests: every degradation stub answers every member the addon calls            [F-006]
slash/debuglog: stub surface follows the call sites (HelpHeader in, ConsoleCheckbox out) [F-006]
slash: a degraded install lists the verbs that still work                     [F-010]
panel: the destructive reset is 'Reset Everything...', not 'Reset All'        [F-004]
slash: comments name the suite, not a Panel reader that does not exist        [F-007]
auctionprice: drop the stale luacheck suppression for a used addonName        [F-008]
tests: vendor-sync case names disclose the sibling-checkout condition         [F-005]
docs: regenerate test-cases.md and move the tests badge                       [testing-§7]
```
