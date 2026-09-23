# LootHistory — Final Summary (2026-09-23 review cycle)

> Written ahead of implementation, on the assumption that every task in `04_EXECUTION_PLAN.md` lands
> and every check in `03_SMOKE_TESTS.md` passes. Anything marked *[fill in]* is a measured value that
> does not exist yet. Record it; do not estimate it.

## Headline

This cycle fixes how Ka0s Loot History attributes loot after a Mythic+ run. The addon used to keep the
keystone context for the rest of the session, so every later herb, ore node or world chest was
recorded as Mythic+ loot. Now the context ends when the player leaves the dungeon.

Boss loot now keeps its encounter id. New currencies get their category. Shortening the retention
period no longer deletes history in the same click. The library-less fallback no longer tells players
to type the wrong command. Two full-history hot paths stop redoing work on every record.

The rest is hygiene: stale comments and doc citations, one set of bind-state labels, a resize grip
that respects *Lock frame*, and four test cases handed back to the library they test.

## Counts

**Critical fixed: 0, High fixed: 1, Medium fixed: 7, Low fixed: 10.**

| Severity | Findings |
|---|---|
| High | F-001 |
| Medium | F-002, F-003, F-004, F-005, F-006, F-007, F-008 |
| Low | F-009, F-010, F-011, F-012, F-013, F-014, F-015, F-016, F-017, F-018 |

**Deferred:** none planned. There is one conditional item: **F-002 is dropped if CP-1's in-client
check shows that loot opens before `ENCOUNTER_END`**. If so, record it here as "not reproduced" and
move one Medium out of *fixed*.

## Changes by theme

### T1 — Attribution context ends when its situation ends

- **What changed:** the Mythic+ keystone context is cleared when the player leaves the dungeon or the
  key resets. A successful boss kill keeps its encounter id for a short grace window, so loot taken
  from the corpse carries it.
- **Why it mattered:** herbs, ores and chests were being stored as Mythic+ loot for the rest of any
  session that included a key. That polluted the Source column, the Source filter, Insights and the
  exports, and nothing could repair the stored rows afterwards.
- **Findings / changes:** F-001, F-002 / C-001, C-002.
- **Files:**
  - `core/Compat.lua`
  - `core/Constants.lua`
  - `modules/Attribution.lua`
  - `tests/test_attribution.lua`
  - `docs/data-flow.md`
  - `docs/midnight-quirks.md`

### T2 — Capture data does not depend on a stale session snapshot

- **What changed:** the currency-category lookup rebuilds itself once when it meets an id it does not
  know. The warbound repair can now warm the item cache for a row that has a link but no id.
- **Why it mattered:** the first currency of a new season was stored with no category, permanently.
- **Findings / changes:** F-003, F-015 / C-003, C-014.
- **Files:**
  - `core/Compat.lua`
  - `core/Database.lua`
  - `tests/test_compat.lua`
  - `tests/test_database.lua`

### T3 — Destructive effects are confirmed

- **What changed:** picking a shorter retention now asks before it deletes anything. If the player
  declines, the deletion waits for the next login's deferred prune, and the addon says so in chat.
- **Why it mattered:** one mis-click on a dropdown could throw away months of history with no undo,
  while `purge` was confirm-gated.
- **Findings / changes:** F-004 / C-004.
- **Files:**
  - `settings/Schema.lua`
  - `settings/Slash.lua`
  - `core/Database.lua`
  - `tests/test_schema.lua`
  - `docs/settings-panel.md`

### T4 — Degradation stubs are honest and copy nothing

- **What changed:**
  - The library-less refusal line now names `/lh enable`, and a parity case pins it.
  - The DebugLog stub no longer carries the library's color codes.
  - The library-less reset now reports what it cleared.
- **Why it mattered:** stub copies of library text are the copies that drift. One already had.
- **Findings / changes:** F-005, F-008, F-014 / C-005, C-008, C-013.
- **Files:**
  - `settings/Slash.lua`
  - `core/DebugLogSetup.lua`
  - `tests/test_slash.lua`
  - possibly `tests/test_surface_parity.lua`

### T5 — Loop-invariant work leaves the full-history loops

- **What changed:**
  - The AH price priority is compiled once per settings change, not re-parsed per record.
  - Day and weekday buckets are derived once per calendar day inside an Insights pass.
  - The loot handler reuses its gate table.
  - The login prune repaints only when it actually removed rows.
- **Why it mattered:** Insights and export walk the whole history, and they did pattern matching on
  every record inside that walk.
- **Findings / changes:** F-006, F-016, F-018 / C-006.
- **Files:**
  - `modules/AuctionPrice.lua`
  - `core/Database.lua`
  - `core/LifecycleSetup.lua`
  - `modules/Collector.lua`
  - `tests/test_auctionprice.lua`
  - `tests/test_database.lua`

### T6 — The suite tests this addon's wiring

- **What changed:** four DebugLog formatter unit cases were removed. They live in LibKa0s's suite
  (`testing-§8`).
- **Findings / changes:** F-007 / C-007.
- **Files:** `tests/test_debuglog.lua`.

### T7 — Hygiene

- **What changed:**
  - Corrected comments in `Schema.lua`, `Slash.lua` and `Util.lua`.
  - Re-pointed citations in `docs/midnight-quirks.md`.
  - One bind-state label set across both CSV exports.
  - The launcher tooltip uses the brand constant, says show/hide, and reflects the disabled state.
  - The resize grip respects *Lock frame*.
  - The data export copies nested tables deeply.
- **Findings / changes:** F-009, F-010, F-011, F-012, F-013, F-017 / C-009, C-010, C-011, C-012, C-015.
- **Files:**
  - `modules/Browser.lua`
  - `settings/Schema.lua`
  - `settings/Slash.lua`
  - `core/Util.lua`
  - `docs/midnight-quirks.md`
  - `docs/settings-panel.md`
  - `modules/Export.lua`
  - `core/Database.lua`
  - `core/LauncherSetup.lua`
  - `tests/test_export.lua`

## API / behavior changes

- **New events registered while enabled:** `ZONE_CHANGED_NEW_AREA` and `CHALLENGE_MODE_RESET`, both
  on the addon's own AceEvent target. They are torn down on disable through the recorded
  `__events` list.
- **New bus subscription:** `AuctionPrice` subscribes to `SettingsChanged` to refresh its price plan.
  It stands down with the addon.
- **New popup:** `KA0S_LOOTHISTORY_PRUNE`, the confirm for a shorter retention.
- **New constant:** `Constants.ENCOUNTER_GRACE`, about 60 s.
- **New Compat shim:** `NS.Compat.InPartyInstance()`.
- **Changed Insights CSV labels:** "Soulbound", "BoE", "Unbound" and so on now read "Bind on Pickup",
  "Bind on Equip", "Not Bound", and so on, matching the History CSV and the Bound column legend.
  Anyone who parses the Insights CSV by label should take note.
- **Changed tooltip text:** the minimap/broker tooltip's click line.
- **Unchanged:** no slash verb was added, renamed or removed. No default changed.

## Saved-variable / migration notes

**No schema bump.** Nothing new is stored, and the `retentionDays` value is written exactly as before.

**Existing mislabeled rows are not repaired.** Rows recorded as `MPLUS` before this fix stay `MPLUS`,
because the record does not preserve enough to tell a real reward chest from a later herb. A player
who wants them gone can filter Source = Mythic+ and delete them. Recording a migration for this was
considered and rejected: there is no signal to decide which rows are wrong.

## Deprecated-API migrations

None. No deprecated call was found in the addon's own code.

## Performance impact

To be filled in from S-006 and the M3.0 baseline only. Nothing is claimed yet.

| Measure | Before | After | Record |
|---|---|---|---|
| `collectgarbage("count")` delta across 3 Insights range switches (same dataset) | *[fill in]* | *[fill in]* | S-006 |
| Headless micro-benchmark, `Stats` over a synthetic 20k history (KB allocated) | *[fill in]* | *[fill in]* | M3.0, uncommitted |

If no improvement is measured, this section says so, and the change stays for its correctness.

## Test and complexity movement

- **Pass count:** 858 before. Expected about 866 after (+8: C-001 +3, C-002 +2, C-003 +1, C-004 +2,
  C-005 +1, C-006 +2, C-007 −4, C-014 +1). The authoritative figure is the `--list` output at M5.
- **Inventory and badge:** `docs/test-cases.md` and the README `Tests` badge move in **each** commit
  that moves the count.
- **Complexity watch list:** the next release's regeneration should confirm these, not this cycle.
  - `modules/Browser.lua` grows by one line.
  - `core/Database.lua` stays under 1000 lines.
  - `AuctionPrice:MovePriorityWithin` stays at CCN 15 and must not reach 16.
  - `RESULTS.md` is already stale against today's run (786 → 858 cases), and release regeneration
    closes that gap.

## Known follow-ups

- **Retro-repair of stored `MPLUS` rows:** not possible without a signal. Deferred indefinitely.
- **`tests/perf.lua`:** still absent under the recorded `performance-§12` deviation. The T5 claims
  therefore rest on an in-client memory proxy. If the owner re-arms the perf harness, T5's paths are
  the first scenarios to write.
- **Cross-addon baseline table:** the review agent's recorded baseline (the 2026-09-07 minors and
  `## Interface: 120007`) is out of date. Today's measured values are in 01. The table should be
  refreshed in the plugin, not here.
- **The `modules/Analytics.lua` peel:** still the watch list's open item (1200 lines). This review
  did not take it on.

## Verification evidence

- `03_SMOKE_TESTS.md` sign-off table: *[link the completed copy]*.
- Commit range: *[fill in: first M1.1 commit … M5 close-out]* on
  `feat/2026-09-23-review-audit-remediation`.

## Suggested commit message / PR description

```
LootHistory: review remediation (2026-09-23)

Fix Mythic+ keystone context leaking past the dungeon, which recorded every later
GameObject loot (herbs, ore, chests) as MPLUS (F-001). Keep encounter detail through
post-kill looting (F-002). Rebuild the currency-category cache on a miss (F-003).
Confirm before a shorter retention deletes history (F-004). Degraded-path stubs
build the refusal line from the library's shape and stop copying library formats
(F-005, F-008, F-014). Compile the AH price plan once per settings change and cache
day buckets per Stats pass (F-006, F-016, F-018). Move formatter unit cases to
LibKa0s (F-007). Hygiene: lock gates resize, one bound-label vocabulary, launcher
tooltip, comments and doc citations, deep-copied export, link-only repair
(F-009..F-013, F-015, F-017).

Tests: 858 -> <N> (docs/test-cases.md and README badge updated per commit).
Review bundle: docs/reviews/2026-09-23/.
```
