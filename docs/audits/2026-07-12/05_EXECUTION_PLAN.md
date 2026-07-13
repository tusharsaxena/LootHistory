# 05 — Execution Plan (Remediation)

Ordered, checkable hand-off to the separate remediation engagement. Grouped into three sprints, cheapest-and-safest first. Each step names its `LH-` ID(s) and its verification. This audit is read-only — nothing here has been executed.

**Global gate (every commit):** `lua tests/run.lua` green **and** `luacheck .` = 0/0 (§14A/§17). Commit trunk-based on `master`, one commit per sub-milestone (a completed, green step or tight group), no feature branch unless asked.

---

## Sprint 1 — Docs, TOC & packaging hygiene (zero runtime risk)

Batch of file moves/edits that bring the repo root and metadata to the §15 / §2.1 shape.

- [ ] **S1.1 — Delete `TODO.md`; migrate items to GitHub issues** (LH-01). Reword `modules/Attribution.lua:29` to drop "see TODO.md". _Verify:_ no `TODO.md` at root or in `docs/`; `grep -rn "TODO.md" core modules settings` = 0 hits.
- [ ] **S1.2 — Move `ARCHITECTURE.md` → `docs/ARCHITECTURE.md`** (LH-03). `git mv`; repoint links. _Verify:_ file present under `docs/`, absent at root; §15.3 sections intact.
- [ ] **S1.3 — Stub the root `CLAUDE.md`** (LH-02). Move the full brief into `docs/` (fold into `docs/ARCHITECTURE.md` or a sibling); leave a ≤15-line stub (tier + standard link + docs pointer). _Verify:_ root `CLAUDE.md` is a stub; no full brief at root.
- [ ] **S1.4 — TOC metadata fields** (LH-05). Add `OptionalDeps`, `X-Standard`, `X-Curse-Project-ID: 1530802`, `X-Wago-ID` in §2.1 order; set `Category-enUS: Misc`. _Verify:_ fields present and ordered; `/reload` in-client loads clean.
- [ ] **S1.5 — TOC file-listing section comments** (LH-06). Re-comment to `# Libraries → # Locales → # Core → # Defaults → # Modules → # Settings`; keep the §1.2 load order (settings before modules). _Verify:_ section comments canonical; all 18 source files still load.
- [ ] **S1.6 — Exclude `audit/` from package + lint** (LH-12). Add `audit/` to `.pkgmeta ignore:` and `.luacheckrc exclude_files`. _Verify:_ `luacheck .` still 0/0 (and now skips `audit/`).
- [ ] **S1.7 — README standard badge + repo slug** (LH-11). Add the Ka0s Standard badge/link to the badge row; resolve the slug and remove the `<!-- TODO -->`. _Verify:_ badge renders; no TODO comment in README.

_Commit:_ one or two commits ("docs: root to §15 shape + TODO removal", "toc/pkg: §2.1 fields + audit exclusion + README standard badge"). Gate green.

## Sprint 2 — Structural/logic seams (test-first)

- [ ] **S2.1 — Media folder rename** (LH-04). `git mv media/logo media/logos`; update `LOGO_PATH` (`settings/Panel.lua:18`). _Verify:_ logo displays on the settings landing page in-client; `grep -rn "media\\\\logo\\\\" .` = 0 stale references.
- [ ] **S2.2 — Schema migration runner** (LH-07). _Test-first:_ add `tests/test_database.lua` cases (idempotent; sets `schemaVersion` when absent; no-op when current). Then add `NS:RunMigrations()` to `core/Database.lua` and call it in `InitDB`/`OnInitialize` after AceDB init. _Verify:_ new tests pass; existing suites green.
- [ ] **S2.3 — Compat flavor de-branch** (LH-10). _Test-first:_ extend `tests/test_compat.lua` to assert helpers degrade to nil/false on absent `C_*` APIs. Remove `Compat.IsRetail`/`IsClassic` and Classic-flavor comments; replace any consumers with API-presence guards; drop `WOW_PROJECT_*` from `.luacheckrc read_globals`. _Verify:_ `grep -rn "WOW_PROJECT_ID\|IsClassic\|IsRetail" core modules settings` = 0; tests + luacheck green.

_Commit:_ per step (each is independently green).

## Sprint 3 — Settings-panel conformance (visual verify)

Both in `settings/Panel.lua`; land together, then in-client eyeball the General subcategory.

- [ ] **S3.1 — `BUTTON_PAIR_REL` for paired action buttons** (LH-09). Define `BUTTON_PAIR_REL = 0.492`; route the Reset All (`:381`) and Purge (`:259`) buttons through a shared pair-maker at that width. _Verify:_ right button's border no longer shaved; left/right buttons symmetric.
- [ ] **S3.2 — Always-visible inert scrollbar** (LH-08). Rebind the AceGUI `ScrollFrame`'s `FixScroll` in `ensureScroll` (`:97`) to keep the bar shown + disabled when content fits. _Verify:_ scrollbar visible and greyed on the short General page; body width identical to a long/overflowing page (no jitter).

_Commit:_ one commit ("settings: §6.6/§6.10 panel conformance — button inset + always-shown scrollbar"). Gate green.

---

## Done criteria

- All 12 `LH-` deviations closed; a re-audit (new `audit/<date>/`) reuses these IDs and finds them resolved.
- Repo root = README + stub CLAUDE + LICENSE + standard folders (§15); TOC carries all required §2.1 fields with canonical §2.5 listing; `media/logos/`; migration runner present; no `WOW_PROJECT_ID` flavor branch; panel matches §6.6/§6.10.
- `lua tests/run.lua` green and `luacheck .` = 0/0 at every commit; no SavedVariables migration triggered (`schemaVersion` stays 1).
