# 04 — Execution Plan · Ka0s Loot History

Agent-team plan to implement `02_PROPOSED_CHANGES.md`. Trunk-based on `master` (no feature branch
unless the user asks). Gate every milestone on `luacheck .` (0 errors) + `lua tests/run.lua`
(0 fail). Commit per completed, green Task.

---

## Milestone M0 — Empirical source matrix (blocks C-001 decisions)
**Done when:** the 03 §F-001 in-client source matrix is filled in and the set of truly-reachable
sources is known.

| Task | Role | Findings | Files |
|------|------|----------|-------|
| M0.T1 | qa-in-client | F-001 | none (observation) |

**Checkpoint CP0 (human):** confirm which of VENDOR/MAIL/TRADE record via `CHAT_MSG_LOOT`. Feeds
`SOURCE_IMPLEMENTED` in C-001. No code until this is known.

---

## Milestone M1 — Attribution honesty + firewall (F-001, F-002, F-011)
**Done when:** the mute list / Source options show only reachable sources; challenge-mode reads go
through Compat; dead keystone field removed; tests green.

| Task | Role | Findings | Files |
|------|------|----------|-------|
| M1.T1 | wow-api-migrator | F-001 (C-001) | `core/Constants.lua`, `docs/TECHNICAL_DESIGN.md` |
| M1.T2 | wow-api-migrator | F-002 (C-002), F-011 (C-010) | `modules/Attribution.lua`, `core/Compat.lua`, `core/State.lua` |
| M1.T3 | lua-tester | F-001/F-002 | `tests/test_attribution.lua`, `tests/test_compat.lua` |

**Concurrency:** M1.T1 (Constants) and M1.T2 (Attribution/Compat) touch **different files** →
**parallelizable**. M1.T2 edits `Compat.lua`; if M1.T1 is later extended to touch Compat, serialize.
M1.T3 depends on both.

**Checkpoint CP1 (coordinator):** verify Source dropdown + mute list only show implemented sources;
MPLUS still attributes.

---

## Milestone M2 — Write-path hardening (F-003)
**Done when:** `S:Set`/`S:Default` deep-copy tables; reset cycles can't alias defaults; tests green.

| Task | Role | Findings | Files |
|------|------|----------|-------|
| M2.T1 | lua-refactorer | F-003 (C-003) | `settings/Schema.lua` |
| M2.T2 | lua-tester | F-003 | `tests/` (new: reset does not alias excludedSources) |

**Concurrency:** independent of M1 (Schema.lua vs Attribution/Constants) → **parallelizable with M1**.

---

## Milestone M3 — De-duplication + UX (F-005, F-006)
**Done when:** one `Util.RangeFrom`, one unit-kind set, player toggle no longer contradicts a
specific-character filter; tests green.

| Task | Role | Findings | Files |
|------|------|----------|-------|
| M3.T1 | lua-refactorer | F-005 (C-004) | `core/Util.lua`, `modules/Browser.lua`, `modules/Analytics.lua`, `core/Compat.lua`, `modules/Attribution.lua` |
| M3.T2 | ux-cleanup | F-006 (C-005) | `modules/Browser.lua` |
| M3.T3 | lua-tester | F-005 | `tests/test_util.lua` (new `Util.RangeFrom`) |

**Concurrency:** M3.T1 and M3.T2 **both touch `modules/Browser.lua` → must serialize** (T1 first —
it changes `dateFrom`; then T2 edits `SetCharFilter`). M3.T1 also touches `Compat.lua`/
`Attribution.lua` shared with **M1.T2 → serialize M3.T1 after M1.T2**.

**Checkpoint CP2 (human):** Browser is the highest-churn file (M1? no; M3.T1, M3.T2, plus C-009
comment). Review the merged Browser.lua once before cleanup.

---

## Milestone M4 — Cleanup + docs (F-004, F-007, F-008, F-009, F-010, F-012)
**Done when:** dead helpers gone, comments/seeds fixed, non-schema state documented, TOC verified,
luacheck fully clean; tests green.

| Task | Role | Findings | Files |
|------|------|----------|-------|
| M4.T1 | lua-refactorer | F-007 (C-006), F-008 (C-007) | `core/Util.lua`, `modules/Collector.lua` |
| M4.T2 | docs-cleanup | F-009 (C-008), F-010 (C-009) | `modules/BrowserTable.lua`, `CLAUDE.md`, `modules/Browser.lua` |
| M4.T3 | docs-cleanup | F-004 | `locales/enUS.lua` (drop/annotate unused `L`), README/CLAUDE note "English-only 0.1.0" |
| M4.T4 | packager | F-012 (C-011) | `LootHistory.toc`, optional `.gitattributes` |

**Concurrency:** M4.T2 touches `Browser.lua` → **serialize after all M3 Browser edits**. M4.T1
(Util.lua) overlaps M3.T1 (Util.lua) → **serialize after M3.T1**. M4.T3/M4.T4 are disjoint →
parallelizable.

---

## Milestone M5 — Verification + tag-readiness
**Done when:** `03_SMOKE_TESTS.md` sign-off table is filled, `luacheck .` = 0 warnings/errors,
`lua tests/run.lua` green, `## Version: 0.1.0` consistent across TOC/Namespace/README.

| Task | Role | Findings | Files |
|------|------|----------|-------|
| M5.T1 | qa-in-client | all | none |
| M5.T2 | release | all | version/consistency check |

**Checkpoint CP3 (human):** final go/no-go for tagging 0.1.0.

---

## Critical-path / concurrency map
- **Serial spine:** CP0 → M1.T2 → M3.T1 → M3.T2 → M4.T2 (all touch, in order, the shared
  Attribution/Compat then Browser chain).
- **Parallel lanes:** M2 (Schema.lua) runs alongside M1. M4.T3 (locales) + M4.T4 (TOC) run any time
  after M0.
- **Shared-file serialization callouts:**
  - `modules/Browser.lua`: M3.T1 → M3.T2 → M4.T2 (never concurrent).
  - `core/Compat.lua` + `modules/Attribution.lua`: M1.T2 → M3.T1 (never concurrent).
  - `core/Util.lua`: M3.T1 → M4.T1 (never concurrent).
  - `core/Constants.lua` (M1.T1) and `settings/Schema.lua` (M2.T1) are otherwise isolated.

## Checkpoints summary
- **CP0** — source matrix known before C-001 (blocking).
- **CP1** — attribution UI scoped correctly, MPLUS intact.
- **CP2** — merged Browser.lua reviewed after all edits.
- **CP3** — full smoke + version consistency before tag.

## Incremental commit strategy (one commit per Task, atomic)
- `fix(attribution): scope Source UI to reachable sources (F-001)`
- `refactor(compat): route challenge-mode map/keystone reads through Compat (F-002, F-011)`
- `fix(settings): deep-copy table values in the Schema write-path (F-003)`
- `refactor(core): extract Util.RangeFrom and share the unit-GUID kind set (F-005)`
- `fix(browser): stop player-scope toggle contradicting a specific-character filter (F-006)`
- `chore: remove dead Util helpers; fix collector seed, stale comment, keystone field (F-007..F-011)`
- `chore(locale): drop unused L local; note English-only scope for 0.1.0 (F-004)`
- `chore(toc): verify Interface version; add .gitattributes CRLF pin (F-012)`

Each commit message ends with the repo's required Co-Authored-By / Claude-Session trailers.
