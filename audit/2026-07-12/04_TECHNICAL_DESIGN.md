# 04 — Technical Design (Remediation)

How to close each deviation in `02_DEVIATIONS.md`. This is design only — the audit changes no code. Every item is keyed to its `LH-` ID. Grouped by nature; ordering constraints are called out where they matter.

All changes must keep the green gate: after each, `lua tests/run.lua` (118+ passing) and `luacheck .` (0/0). Where a change touches testable Lua (LH-07, LH-09, LH-10), add/extend a suite **first** (TDD, §14A).

---

## A. Docs & repo hygiene (LH-01, LH-02, LH-03, LH-11)

Pure file moves / edits; no runtime behavior. Do these together so the repo root ends at the §15 shape (README + stub CLAUDE + LICENSE + the standard folders).

- **LH-01 — delete `TODO.md`.** Migrate any still-live items to GitHub issues (the README already points there). Remove the dangling reference in `modules/Attribution.lua:29` (reword the comment to drop "see TODO.md"; the localization note can stay as prose). *(Note: `modules/Attribution.lua` is addon source — editing it is remediation work, executed in the follow-up engagement, not by this audit.)* Risk: none; a `TODO.md` is not shipped anyway (it is in `.pkgmeta ignore` via `docs`? no — it's at root and **not** ignored, another reason to remove it).
- **LH-02 — stub the root `CLAUDE.md`.** Move the current 139-line brief to `docs/` (e.g. `docs/AGENT_CONTEXT.md` or fold into `docs/ARCHITECTURE.md`). Replace root `CLAUDE.md` with a short stub: (a) tier ("Tier 2 modular"), (b) "adheres to the Ka0s WoW Addon Standard — https://github.com/tusharsaxena/WowAddonStandards", (c) a pointer into `docs/`. Keep the stub under ~15 lines.
- **LH-03 — relocate `ARCHITECTURE.md` → `docs/ARCHITECTURE.md`.** `git mv`. Update any links (root `CLAUDE.md` stub, README) to the new path. Confirm the moved file still satisfies §15.3 content (Overview, Module Map, Settings Schema, Message Bus with sender/payload/consumers, Slash table, Event Subscriptions, Taint Notes, Known Limitations) — it already documents the bus and schema.
- **LH-11 — README badge + repo slug.** Add a Ka0s Standard badge/line to the badge row (`README.md:3-5`), e.g. `[![Standard](https://img.shields.io/badge/Ka0s-WoW%20Addon%20Standard-blue)](https://github.com/tusharsaxena/WowAddonStandards)`. Resolve the repo slug and remove the `<!-- TODO: confirm repo URL/slug -->` at `README.md:123`, hard-setting the correct `/issues` URL.

**Ordering:** LH-02 and LH-03 both move content into `docs/`; do LH-03 (move ARCHITECTURE) first, then LH-02 can fold the brief into it or a sibling and repoint the stub.

## B. TOC & packaging (LH-05, LH-06, LH-12)

Metadata/config only; no runtime risk, but re-run the load smoke (in-game `/reload`) since TOC edits can silently drop a file.

- **LH-05 — add missing TOC fields** in the §2.1 order. Insert after `SavedVariables`: `## OptionalDeps: Ace3, LibStub, CallbackHandler-1.0, LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0`. Add near `X-License`: `## X-Standard: https://github.com/tusharsaxena/WowAddonStandards`, `## X-Curse-Project-ID: 1530802`, and `## X-Wago-ID: <id>` (obtain the Wago ID; if not yet listed on Wago, list it and fill the ID). Change `## Category-enUS: Bags & Inventory` → an allowed value (`Misc` is the closest fit for a passive tracker). Keep the block blank-line-free and in canonical order.
- **LH-06 — re-comment the file listing** to `# Libraries` → `# Locales` → `# Core` → `# Defaults` → `# Modules` → `# Settings`. Split the current `# defaults + locales` into `# Defaults` and `# Locales` comment blocks. **Preserve the actual file load order** (per §1.2's MUST: defaults → locales → settings → modules) — this is a comment/grouping change, not a reorder; do not move `settings\*` after `modules\*` (§1.2 mandates settings before modules; §2.5's example order is the standard's own internal inconsistency and is deferred to the standard maintainers).
- **LH-12 — exclude `audit/`.** Add `- audit/` to `.pkgmeta` `ignore:` and `"audit/"` to `.luacheckrc` `exclude_files`. While in `.luacheckrc`, also drop `WOW_PROJECT_ID/MAINLINE/CLASSIC` from `read_globals` as part of LH-10.

## C. Panel polish (LH-08, LH-09)

Both live in `settings/Panel.lua`; land them together and eyeball the General subcategory in-game (short page) and a hypothetical long page.

- **LH-08 — always-visible inert scrollbar.** In `ensureScroll` (`settings/Panel.lua:97`), after creating the AceGUI `ScrollFrame`, rebind its `FixScroll` (or the scrollbar's show logic) so the vertical bar stays shown and disabled when `viewheight < height`: keep the scrollbar frame `:Show()`n, park the thumb at top, and `:Disable()` the up/down buttons + thumb (grey them). Mirror the Tier-2 tracker's always-show `FixScroll` rebind referenced in §6.10. This reserves the right-edge gutter already set by the `BOTTOMRIGHT` inset (`:104`), so body width is stable across subcategories.
- **LH-09 — `BUTTON_PAIR_REL` for cell-filling buttons.** Add `local BUTTON_PAIR_REL = 0.492` to the constants block (`:20-27`). Introduce a small shared button-pair maker (or a helper) that sets a paired action button's width to `BUTTON_PAIR_REL` instead of `0.5`. Apply to the Reset All button (`:381`) and the Purge button (`:259`). Label-inset controls (checkbox/dropdown/slider) stay at `0.5` — they are immune (§6.10). No test needed (pure layout), but verify the right button's border is not shaved in-game.

## D. Database migration runner (LH-07)

- **LH-07 — ship `RunMigrations`.** In `core/Database.lua`, add:
  ```lua
  function NS:RunMigrations()
    local g = NS.db and NS.db.global
    if not g then return end
    g.schemaVersion = g.schemaVersion or 1
    -- future: if g.schemaVersion < 2 then ... ; g.schemaVersion = 2 end
  end
  ```
  Call it from `NS:InitDB` right after `AceDB:New(...)` (or from `OnInitialize` after `InitDB`), before any read of `db.global.history`. Body may be a no-op today; the seam is the requirement (§2.2/§5.1). **TDD:** add `tests/test_database.lua` cases — `RunMigrations` is idempotent, sets `schemaVersion` when absent, and leaves an already-current DB unchanged.

## E. Compat flavor de-branch (LH-10)

- **LH-10 — remove game-flavor branching.** Delete `Compat.IsRetail`/`Compat.IsClassic` (`core/Compat.lua:5-7`). Audit for consumers (`grep -rn "IsRetail\|IsClassic" core modules settings`) — replace any usage with direct API-presence guards (the file already uses `C_ChallengeMode`/`C_Container`/`C_Spell` presence checks, which is the correct Retail-only idiom). Reword the "does not exist on Classic flavors" comments (`:17-18` and similar) to plain "API-absent" guards. Remove `WOW_PROJECT_ID/MAINLINE/CLASSIC` from `.luacheckrc read_globals` (folds with LH-12). **TDD:** extend `tests/test_compat.lua` to assert the shimmed helpers degrade to `nil`/false when the mock omits the `C_*` API, independent of any flavor flag.

---

## Risk & sequencing summary

- **Zero-runtime-risk (docs/config):** LH-01, LH-02, LH-03, LH-05, LH-06, LH-11, LH-12 — batchable, verify with a `/reload` load-smoke after TOC edits.
- **Low-risk UI:** LH-08, LH-09 — visual verify in-game.
- **Low-risk logic (test-covered):** LH-07, LH-10 — write failing test first.
- No deviation forces a SavedVariables migration or breaks the `Database:Export` v2 contract. `schemaVersion` stays `1` (LH-07 only adds the runner seam).
- LH-04 (folder rename) touches a runtime path constant — the only "code" edit in group A besides comments; verify the logo loads in the settings landing page after the rename.
