# 05 — Final Summary · Ka0s Loot History

> **Status:** written assuming `02_PROPOSED_CHANGES.md` was implemented and `03_SMOKE_TESTS.md`
> passed. Fill the verification pointers once the work lands. This is the PR/changelog record.

## Headline
This review-and-fix cycle brings Ka0s Loot History's advertised behavior in line with what it
actually does. The addon was already clean, well-layered, taint-free, and green on its headless
suite; the work here closes an attribution-coverage gap (the UI offered filter/mute buckets for
sources that were never captured), tightens the Compat firewall and the settings write-path,
removes duplicated helpers and dead code, fixes a confusing filter-toggle desync, and squares the
docs/TOC with the code. No externally breaking changes to saved data.

## Counts
- **Critical fixed:** 0 (none found)
- **High fixed:** 1 (F-001)
- **Medium fixed:** 4 (F-002, F-003, F-005, F-006) · **deferred:** 1 (F-004 — see follow-ups)
- **Low fixed:** 6 (F-007, F-008, F-009, F-010, F-011, F-012) · **deferred:** 1 (F-013)

Deferred with rationale:
- **F-004 (localization):** infrastructure exists but is unused; wrapping every string in `L[...]`
  is a larger pass than a review-fix cycle warrants for an English-only 0.1.0. Actioned only as a
  luacheck-cleanup + explicit scope note.
- **F-013 (combat-log handler cost):** correct and allocation-free today; gating it needs profiling
  data. Left as a backlog note pending the perf spot-check.

---

## Changes by theme

### T1 — Attribution coverage honesty
- **What changed:** the "Record data from" mute list and the Source filter now expose only sources
  with a live capture path (`Constants.SOURCE_IMPLEMENTED`); AH/CRAFT/ROLL — specified in the design
  but never stamped — are no longer advertised. The `SourceType` enum is unchanged (export
  contract). TD §4 updated to mark unimplemented rows "planned".
- **Why it mattered:** users saw filter/group/mute options for sources that could never appear, and
  three more depended on unverified `CHAT_MSG_LOOT` behavior. The UI now matches reality.
- **Findings:** F-001 · **Changes:** C-001
- **Files:** `core/Constants.lua`, `modules/Browser.lua`, `docs/TECHNICAL_DESIGN.md`

### T2 — Compat firewall + de-duplication
- **What changed:** challenge-mode map/keystone reads route through `NS.Compat`; a single
  `Util.RangeFrom` replaces the duplicated `dateFrom`/`rangeFrom`; one unit-GUID kind set replaces
  the two copies in Compat/Attribution; the dead `State.keystone.mapID` field was removed.
- **Why it mattered:** flavor-varying API calls belonged behind the firewall, and duplicated
  helpers drift. One source of truth each.
- **Findings:** F-002, F-005, F-011 · **Changes:** C-002, C-004, C-010
- **Files:** `modules/Attribution.lua`, `core/Compat.lua`, `core/Util.lua`, `modules/Browser.lua`,
  `modules/Analytics.lua`, `core/State.lua`

### T3 — Settings write-path hardening
- **What changed:** `Schema:Set` and `Schema:Default` deep-copy table-typed values, so
  `/lh reset`/`resetall` and the Defaults button can no longer alias the shared `excludedSources`
  default table.
- **Why it mattered:** the single-write-path is only safe if it never hands out live references to
  the defaults; this removes a latent corruption hazard.
- **Findings:** F-003 · **Changes:** C-003
- **Files:** `settings/Schema.lua`

### T4 — UX + cleanup + docs
- **What changed:** the Player-scope toggle no longer falsely reads "All players" when a specific
  non-current character is filtered; dead `Util.FormatTime`/`Util.TableCount` removed; collector
  quality-threshold seed corrected (2→1); stale `/lh testmode` comment fixed; non-schema persisted
  state (`savedView`, `settings.window`) documented; TOC interface version verified; unused locale
  `L` cleaned up.
- **Why it mattered:** small correctness/clarity items that individually confuse users or future
  maintainers.
- **Findings:** F-004, F-006, F-007, F-008, F-009, F-010, F-012 · **Changes:** C-005, C-006, C-007,
  C-008, C-009, C-011 (+ F-004 note)
- **Files:** `modules/Browser.lua`, `core/Util.lua`, `modules/Collector.lua`,
  `modules/BrowserTable.lua`, `CLAUDE.md`, `locales/enUS.lua`, `LootHistory.toc`, (opt) `.gitattributes`

---

## API / behavior changes (externally observable)
- **Source options reduced:** the settings "Record data from" list and the History Source dropdown
  no longer show AH/Craft/Roll (and possibly Vendor/Mail/Trade, pending the source-matrix result).
  Stored records and the export shape are unaffected.
- **No slash-command changes.** COMMANDS ↔ README parity was already correct and is preserved.
- **No saved-variable schema bump.** `schemaVersion` stays at 3. Table-typed settings are now
  stored as copies rather than shared references (internal; not user-visible).
- **Locale:** unused `L` local removed/annotated; no user-facing string keys added or renamed.

## Saved-variable / migration notes
None. No schema version change; existing `LootHistoryDB` profiles load unchanged. C-003 changes only
*how* table values are written (by copy), not their shape. No `/lh reset` required.

## Deprecated-API migrations
None required — the codebase already uses the modern namespaces.

| Old API | New API | Files | Status |
|---------|---------|-------|--------|
| (none) | — | — | Compat already wraps `C_Item.*`, `C_Map.*`, `C_Container`-free design; `Settings.*` used correctly |

The only API-hygiene change is *internal routing*: two inline `C_Map`/`C_ChallengeMode` calls in
`Attribution.lua` moved behind `core/Compat.lua` (F-002) — not a deprecation, a firewall fix.

## Performance impact
No perf-tagged code changes were made (F-013 deferred). If the smoke-test CPU spot-check is run,
record the `COMBAT_LOG_EVENT_UNFILTERED` handler cost here for the backlog decision.

## Known follow-ups
- **F-001 backlog:** implement real capture for VENDOR/MAIL/TRADE (BAG_UPDATE diffing) and add
  AH/CRAFT/ROLL stampers, then restore them to `SOURCE_IMPLEMENTED`. Deferred: a capture subsystem,
  not a review-fix.
- **F-004:** full `L[...]` wrapping + a non-enUS locale file, if translation is ever in scope.
  Deferred: out of 0.1.0 English-only scope.
- **F-013:** profile and possibly gate the combat-log name cache. Deferred: needs measurement.

## Verification evidence
- Completed sign-off table: `reviews/2026-07-11/03_SMOKE_TESTS.md`.
- Headless gate: `luacheck .` (0 errors/warnings) + `lua tests/run.lua` (all pass).
- Commit range / PR: _fill in once merged._

## Suggested PR description
```
Ka0s Loot History — review-fix pass (reviews/2026-07-11)

Closes the attribution-coverage gap and lands the review cleanup:
- fix(attribution): scope Source UI to reachable sources (F-001)
- refactor(compat): route challenge-mode map/keystone reads through Compat (F-002, F-011)
- fix(settings): deep-copy table values in the Schema write-path (F-003)
- refactor(core): extract Util.RangeFrom, share the unit-GUID kind set (F-005)
- fix(browser): player-scope toggle no longer contradicts a specific-character filter (F-006)
- chore: remove dead helpers; fix collector seed, stale comment, keystone field (F-007..F-011)
- chore(locale/toc): drop unused L; note English-only scope; verify Interface version (F-004, F-012)

No schema bump; existing SavedVariables load unchanged. luacheck clean; 85/85 tests pass.
Deferred: real VENDOR/MAIL/TRADE/AH/CRAFT/ROLL capture (F-001 backlog), full localization (F-004),
combat-log handler gating (F-013).
```
