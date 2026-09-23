# LootHistory — Execution Plan (2026-09-23)

This plan implements `02_PROPOSED_CHANGES.md`. **There is no upstream milestone.** The review raised no
`[upstream]` finding, and vendor sync is clean. If the suite-wide plan re-vendors LibKa0s into this
repo, that commit lands **before M1**, as its own commit, exactly as upstream publishes it. Then
re-run Step 0, re-base this plan on the fresh numbers, and check again whether F-005's library line
format has moved.

## Rules that apply to every task

- **Work on `feat/2026-09-23-review-audit-remediation`.** Never edit `libs/` or `tests/_kit/`.
- **Run the green gate after every task:**
  `ka0s-bounded lua5.1 tests/run.lua` must show 0 failed, and `ka0s-bounded luacheck .` must show 0/0.
- **Any task that moves the pass count also regenerates `docs/test-cases.md`**, with
  `lua5.1 tests/run.lua --list > docs/test-cases.md`, and updates the README `Tests-N%2FN` badge **in
  the same commit** (`testing-§5`).

## Milestones

### M1 — Attribution correctness (the High and its sibling)

**Done when:** F-001, F-002 and F-003 are covered by new red-under cases; those cases are green; and
`docs/data-flow.md` and `docs/midnight-quirks.md` describe the new context lifetimes.

| Task | Owner | Findings / changes | Files |
|---|---|---|---|
| M1.1 | wow-api-migrator | F-001 / C-001 | `core/Compat.lua`, `modules/Attribution.lua`, `tests/test_attribution.lua`, `docs/data-flow.md`, `docs/midnight-quirks.md`, `docs/test-cases.md`, `README.md` |
| M1.2 | lua-refactorer | F-002 / C-002 | `core/Constants.lua`, `modules/Attribution.lua`, `tests/test_attribution.lua`, `docs/data-flow.md`, `docs/test-cases.md`, `README.md` |
| M1.3 | wow-api-migrator | F-003 / C-003 | `core/Compat.lua`, `tests/test_compat.lua`, `docs/test-cases.md`, `README.md` |

- **Order:** M1.1, then M1.2, **serially**, because both touch `modules/Attribution.lua`,
  `tests/test_attribution.lua` and `docs/data-flow.md`. M1.3 shares `core/Compat.lua` with M1.1, so it
  also runs after M1.1.
- **Checkpoint CP-1, a human step:**
  - Run S-001 and S-002 in-client.
  - If S-002 shows loot opening **before** `ENCOUNTER_END`, revert M1.2 and close F-002 as
    not-reproduced.
  - Do not start M2 until CP-1 is signed.

### M2 — Destructive-path UX and degraded-stub honesty

**Done when:** retention shrink no longer deletes in the same click; the degraded refusal line
matches the library shape, pinned by a parity case; the DebugLog stub carries no library format
string; and the degraded `CliResetAll` reports what it cleared.

| Task | Owner | Findings / changes | Files |
|---|---|---|---|
| M2.1 | ux-cleanup | F-004 / C-004 | `settings/Schema.lua`, `settings/Slash.lua` (new `KA0S_LOOTHISTORY_PRUNE` popup), `core/Database.lua` (`CountOlderThan`), `tests/test_schema.lua`, `docs/settings-panel.md`, `docs/test-cases.md`, `README.md` |
| M2.2 | lua-refactorer | F-005, F-014 / C-005, C-013 | `settings/Slash.lua`, `tests/test_slash.lua`, `docs/test-cases.md`, `README.md` |
| M2.3 | lua-refactorer | F-008 / C-008 | `core/DebugLogSetup.lua`, possibly `tests/test_surface_parity.lua` |

- M2.1 and M2.2 both touch `settings/Slash.lua`, `docs/test-cases.md` and `README.md`, so they run
  **serially**: M2.1 first.
- M2.3 is **parallelizable** with both. Its file set is disjoint, except that it may touch
  `tests/test_surface_parity.lua`, which neither of the others touches.
- **Checkpoint CP-2:** run S-004 and S-005 in-client.

### M3 — Performance hoists

**Done when:** `Pick` walks a compiled plan; the day buckets are cached per `Stats` pass; the collector
gate table is reused; `PruneOld` sends only when it removed rows; and S-006's before/after numbers are
recorded.

| Task | Owner | Findings / changes | Files |
|---|---|---|---|
| M3.0 | perf-measurer | baseline for C-006 | none. Record the S-006 "before" numbers and an uncommitted headless micro-benchmark **before** M3.1 lands |
| M3.1 | lua-refactorer | F-006 / C-006 (AuctionPrice plan, `accumulateTime` cache) | `modules/AuctionPrice.lua`, `core/Database.lua`, `core/LifecycleSetup.lua` (the new bus target in the `StandDown`/`StandUp` module list), `tests/test_auctionprice.lua`, `tests/test_disabled.lua` (confirm only), `docs/test-cases.md`, `README.md` |
| M3.2 | lua-refactorer | F-016, F-018 / C-006 (steps 3 and 4) | `modules/Collector.lua`, `core/Database.lua`, `tests/test_database.lua`, `docs/test-cases.md`, `README.md` |

- M3.1 and M3.2 both touch `core/Database.lua`, so they run **serially**.
- `core/Database.lua` is also touched by M2.1. M3 starts only after M2 is merged into the working
  branch.
- **Checkpoint CP-3:**
  - Run S-006. If the memory delta did not improve, keep the change for its correctness (the plan
    refreshes on reorder) and write "no measured improvement" in 05.
  - Also confirm that `MovePriorityWithin` gained no branch. It is at CCN 15 today.

### M4 — Tests and hygiene

**Done when:** the four duplicated formatter cases are gone; the comments and doc citations are
corrected; the bound labels are unified; the tooltip is corrected; the grip is gated; the export
copies deeply; and the link-only repair warms the item.

| Task | Owner | Findings / changes | Files |
|---|---|---|---|
| M4.1 | test-curator | F-007 / C-007 | `tests/test_debuglog.lua`, `docs/test-cases.md`, `README.md` |
| M4.2 | ux-cleanup | F-009 / C-009 | `modules/Browser.lua`, `docs/settings-panel.md` |
| M4.3 | doc-hygiene | F-010, F-011 / C-010 | `settings/Schema.lua`, `settings/Slash.lua`, `core/Util.lua`, `docs/midnight-quirks.md` |
| M4.4 | ux-cleanup | F-012 / C-011 | `modules/Export.lua`, `core/Database.lua` (comments only), `tests/test_export.lua` |
| M4.5 | ux-cleanup | F-013 / C-012 | `core/LauncherSetup.lua`, `tests/test_launcher.lua` (if it pins tooltip text) |
| M4.6 | lua-refactorer | F-015, F-017 / C-014, C-015 | `core/Database.lua`, `tests/test_database.lua`, `docs/test-cases.md`, `README.md` |

**Concurrency:**

- **Parallelizable:** M4.2 and M4.5 have fully disjoint files. M4.3 is disjoint from everything else
  in M4, but it touches `settings/Slash.lua` and `settings/Schema.lua`, which M2 touched, so it starts
  after M2.
- **Serialize:**
  - M4.1 and M4.6 both regenerate `docs/test-cases.md` and the README badge.
  - M4.4 and M4.6 both touch `core/Database.lua`.
  - Run order: M4.1, then M4.6, then M4.4.
- **Checkpoint CP-4:** run S-007 and S-008, then the full regression suite in 03.

### M5 — Close-out

**Done when:** the green gate passes on the final tree; the `--list` inventory equals the committed
`docs/test-cases.md`; the README badge equals the total; `05_FINAL_SUMMARY.md` has its measured
numbers; and the 03 sign-off table is filled in.

- M5.1, owned by the coordinator: run the full Step 0 battery again, including lizard to scratch,
  and compare it with this review.
- **Do not regenerate `docs/automated-tests/` here.** That happens at release, through
  `/wow-addon:bump-version`.

## Critical path

M1.1 → M1.2 → CP-1 → M2.1 → M2.2 → CP-2 → M3.0 → M3.1 → M3.2 → CP-3 → M4.1 → M4.6 → M4.4 → CP-4 → M5.

These can run alongside the critical path:

- M1.3, after M1.1.
- M2.3.
- M4.2, M4.3 and M4.5, once their preceding milestone's shared files are settled.

## Commit strategy

One commit per task, each carrying the finding IDs. Suggested messages:

| Task | Commit message |
|---|---|
| M1.1 | `End the keystone context when the player leaves the instance (F-001)` |
| M1.2 | `Keep encounter detail through the post-kill loot (F-002)` |
| M1.3 | `Rebuild the currency-category cache on a miss (F-003)` |
| M2.1 | `Ask before a shorter retention deletes history (F-004)` |
| M2.2 | `Build the degraded refusal line from the library's shape (F-005, F-014)` |
| M2.3 | `Drop the library format strings from the DebugLog stub (F-008)` |
| M3.1 | `Compile the AH price plan once per settings change (F-006)` |
| M3.2 | `Reuse the collector gate table; send HistoryChanged only on a real prune (F-016, F-018)` |
| M4.1 | `Move formatter unit cases to where the formatter lives (F-007)` |
| M4.2 | `Lock frame also stops the resize grip (F-009)` |
| M4.3 | `Correct stale comments and doc citations (F-010, F-011)` |
| M4.4 | `One bound-label vocabulary across both exports (F-012)` |
| M4.5 | `Launcher tooltip: brand constant, and the disabled state (F-013)` |
| M4.6 | `Warm link-only rows in the bound repair; deep-copy the export (F-015, F-017)` |

Each commit message ends with the session's attribution lines. Push after each milestone
checkpoint. **Do not merge to `main`/`master` without the owner's go-ahead.**
