# Pending-items ledger

Every pending item found in this repo — TODO/FIXME markers, unexecuted audit and review plan steps,
doc open questions, open GitHub issues, and recorded-but-unacted Claude memory — plus the decision the
user made about it.

Maintained by **`/wow-addon:pending-audit`**. The command re-sweeps the repo on every run and matches
what it finds against the rows below on **ID + evidence hash** (the first 8 hex chars of `sha1` over
the item's verbatim evidence text). A row whose evidence has since changed no longer matches, so the
item correctly re-surfaces for a fresh decision.

Do not hand-edit rows for items you are not deciding on — the command merges, it never clobbers.

## Notation

| Marker | Value | Meaning | Re-surfaces? |
|---|---|---|---|
| 🟢 | `done` | Implemented this run | No — closed |
| 🔵 | `wont-do` | User decided it will never be done | No — closed |
| 🟡 | `deferred` | Not now; still on the books | Yes, as a collapsed count |

Both the marker and the word are always written: the word is the data (greppable, screen-reader safe),
the marker is the affordance. There is deliberately no red — nothing here is an error state.

## Decisions

| ID | Evidence hash | Source | Decision | Date | Rationale |
|---|---|---|---|---|---|
| DOC-02 | `5c098496` | `docs/audits/2026-07-18/06_EXECUTION_OUTCOME.md` (LH-17) | 🟢 done | 2026-07-31 | "Make this consistent with WowAddonStandards and other Ka0s addons" — `.luacheckrc` now carries the `lint.md` template line verbatim, matching BankLedger/PanelMaster. |
| DOC-03 | `792cf11c` | `docs/audits/2026-07-18/06_EXECUTION_OUTCOME.md` §3 | 🟢 done | 2026-07-31 | User chose "File a GitHub issue upstream" over patching the standard locally. Filed as WowAddonStandards#1; the `toc-file-§5` ↔ `layout-§1` conflict is now tracked at the source. |
| DOC-01 | `51e54f78` | `docs/audits/2026-07-18/06_EXECUTION_OUTCOME.md` (LH-16) | 🟢 done | 2026-07-31 | Premise void — `tools/` no longer exists (removed with Export-to-AI, commit `10f3851`) and `.pkgmeta`'s `ignore:` already matches the `packaging.md` template exactly. No change needed; not put to the user. |
| DOC-04 | `f3f0a3f1` | `docs/audits/2026-07-18/06_EXECUTION_OUTCOME.md` §5 | 🟢 done | 2026-07-31 | "Add to docs/smoke-tests.md" — the reordered-TOC clean-load check now lives in §1 as a numbered regression step rather than only inside a frozen audit bundle. |
| MEM-01 | `ca050797` | memory `currency-capture-branch-pending-merge.md` | 🟢 done | 2026-07-31 | "Mark this as done, all smoke tests have been verified" — all 7 owed currency in-game smokes confirmed passing; memory entry rewritten as a design record. |
| MEM-02 | `b442b733` | memory `ah-price-branch-pending-merge.md` | 🟢 done | 2026-07-31 | "Mark verified — done" — AH-price in-game smokes confirmed passing, including the load-bearing AH-page freeze fix; memory entry rewritten as a design record. |
| MEM-03 | `a64c7bf6` | memory `currency-capture-branch-pending-merge.md` | 🟢 done | 2026-07-31 | "Rewrite both memory entries" — stale claims corrected: no `TODO(currency-ai)` exists, Export-to-AI was removed 2026-07-26, both branches merged, smokes passed. |
| DOC-05 | `098550b4` | `docs/ARCHITECTURE.md:311` | 🟢 done | 2026-07-31 | "Resolve the contradiction in docs" — ARCHITECTURE.md no longer calls the single-slot TTL a backlog item; it now points at scope.md, which already settles it as a resolved design decision. The limitation itself stays documented. |
| DOC-07 | `3419df05` | `docs/module-map.md:109` | 🔵 wont-do | 2026-07-31 | User closed the serialized "v2 export" permanently — the addon is CSV-only since Export-to-AI was removed. Follow-through accepted: `module-map.md` and `data-model.md` reworded from "deferred to the v2 export" to statements of the settled position, so neither reads as intent-to-change. LibSerialize/LibDeflate are not vendored and will not be. |
| DOC-06 | `e1b0ed85` | `docs/ARCHITECTURE.md:305`, `docs/scope.md` | 🟡 deferred | 2026-07-31 | Needs a real group-loot roll win to confirm the `LOOT_ROLL_YOU_WON` assumption. Costs nothing to wait — the caveat is honestly documented, §F-009 is written up, and the failure mode is a wrong-but-harmless source, never an error. |
| ISS-16 | `f845255b` | GitHub issue #16 | 🟡 deferred | 2026-07-31 | Item-returning refunds on `CHAT_MSG_LOOT` remain speculative-but-retained; the confirm-or-remove call waits. Issue #16 stays open. |
| CODE-01 | `d01fce77` | `modules/Browser.lua:14` | 🟡 deferred | 2026-07-31 | The marker's own condition (post-1.0.0) has not been reached and it names where it is tracked. Same item as ISS-11. |
| ISS-11 | `acdd09b7` | GitHub issue #11 | 🟡 deferred | 2026-07-31 | Configurable window styling — real feature work, backlog. Same item as CODE-01; issue stays open. |
| ISS-09 | `95cc66bc` | GitHub issue #9 | 🟡 deferred | 2026-07-31 | Column chooser — ordinary unbuilt backlog, not unfinished work. Would require making the fixed column geometry (and its numeric test asserts) dynamic. Issue stays open. |
