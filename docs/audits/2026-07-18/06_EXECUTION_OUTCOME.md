# 06 — Execution Outcome (Remediation)

Outcome of executing the remediation designed in `04_TECHNICAL_DESIGN.md` and sequenced in
`05_EXECUTION_PLAN.md`. Scope of this pass was **user-directed**: address **all three MUST
deviations (LH-13, LH-14, LH-15)** plus **LH-18 and LH-19**. The two remaining SHOULD items —
**LH-16** (`tools/` packaging) and **LH-17** (lint excludes) — were **not** in scope and remain open.

Work was done trunk-based on `master`, in the main loop, under the green gate — `lua tests/run.lua`
(224/224) **and** `luacheck .` (0/0) verified after the edits. No SavedVariables migration was
triggered; `schemaVersion` stays `1`. Edits were left in the working tree (not committed — the user
controls `git`). `01`–`05` of this bundle are left frozen; this file is the only addition.

---

## 1. Decisions taken (from the up-front questions)

- **LH-13 → Path B (reorder the TOC).** The user chose to conform the TOC to the literal
  `toc-file-§5` section order rather than raise the contradiction upstream (Path A). See §3 for the
  standard-internal consequence this creates.
- **LH-18 → add the Defaults button** (not "accept the deviation"). Wired to a confirm-gated
  clear-both-lists, since the page holds no Schema rows and its default state is two empty lists.
- **LH-14 string kept hardcoded English** (not routed through a new `NS.L` key). The addon has a
  documented English-only scope decision (`locales/enUS.lua` header: no user-facing string routes
  through `NS.L` yet, and deliberately no `local L` alias until the first is wrapped). Every other
  label/tooltip/message in the addon is hardcoded English; introducing a lone wrapped string would be
  an inconsistent partial-localization. The `options-ui-§2` requirement — canonical text **and** grey
  notice — is met regardless; `localization-§2` is satisfied by the seam existing (the auditor did not
  flag any of the other ~200 hardcoded strings).

---

## 2. Per-deviation outcome

| ID | Status | What changed | Key files |
|----|--------|--------------|-----------|
| LH-13 | ✅ Closed vs `toc-file-§5` (⚠ see §3) | Reordered TOC sections to `Libraries → Locales → Core → Defaults → Modules → Settings`. Mirrored the same order into the headless test loader so the new load order is exercised. | `LootHistory.toc`, `tests/run.lua` |
| LH-14 | ✅ Closed | `P:Open` lockdown branch now prints the canonical grey notice `\|cff808080cannot open settings during combat — Blizzard's category-switch is protected\|r` through `NS.Print`; early `return` kept; no `PLAYER_REGEN_ENABLED` defer/replay added. | `settings/Panel.lua` |
| LH-15 | ✅ Closed | Root `CLAUDE.md` heading renamed `## Standards compliance` → `## Standards compliance (read first)` (`documentation-§2`/`-§6`). Body already carried the Deviation-rule substance. | `CLAUDE.md` |
| LH-18 | ✅ Closed | Filters subcategory created with `defaultsButton = true`; button wired to a new confirm popup `KA0S_LOOTHISTORY_CLEAR_FILTERS` → `NS.Filters:ClearAll()` (clears both id-lists; panel auto-refreshes via the `HistoryChanged` listener `ClearAll` fires). | `settings/Panel.lua`, `settings/Slash.lua` |
| LH-19 | ✅ Closed | Swept all 15 retired `§N.M` citations to `filename-§N` (verified live against the section files). One block (`core/Namespace.lua`) was a stale, self-contradictory duplicate — removed rather than re-cited (see §4). | `core/Namespace.lua`, `core/Database.lua`, `modules/Collector.lua`, `modules/Browser.lua`, `modules/Attribution.lua`, `settings/Panel.lua`, `settings/Slash.lua`, `CLAUDE.md` |
| LH-16 | ⬜ Open (out of scope) | `tools/` still not in `.pkgmeta` `ignore:`. | — |
| LH-17 | ⬜ Open (out of scope) | `.luacheckrc` still omits `docs/audits/`, `docs/reviews/`. | — |

Prior deviations `LH-01…LH-12` remain **closed** (unaffected by this pass).

---

## 3. ⚠ Standard-internal consequence of LH-13 / Path B (MUST flag)

`toc-file-§5` and `layout-§1` **contradict each other** on load order, and no single TOC can satisfy
both (documented in `02_DEVIATIONS.md` / `03_EVIDENCE.md`). By choosing Path B, the addon now:

- **conforms to `toc-file-§5`** — section order `Libraries → Locales → Core → Defaults → Modules → Settings`;
- **but now deviates from `layout-§1`**, which mandates load order `core → defaults → locales → settings → modules`.
  (The prior 2026-07-12 run had deliberately kept `layout-§1`'s order — "settings before modules,
  §1.2".)

So this pass **traded one MUST-conformance for another**; the underlying contradiction is unresolved.
**Recommended follow-up (not done — outward-facing):** file an upstream issue on `WowAddonStandards`
flagging the `toc-file-§5` ↔ `layout-§1` order conflict so the standard reconciles the two sections.
Until then, whichever section the addon satisfies, it violates the other.

**Load-safety of the reorder:** verified headlessly. The test loader was reordered to match
(Settings loaded *after* Modules) and the full suite still passes 224/224 — no file references
`NS.Schema`/`NS.COMMANDS`/`NS.Slash`/`NS.Panel` at module-load scope (`NS.COMMANDS` is defined in
`settings/Schema.lua` and only consumed inside functions). **Still required:** an in-game clean-load
smoke test (no Lua error on login; `/lh` prints help; addon appears in the options list) — the TOC
load path itself is not unit-testable.

---

## 4. Note on the `core/Namespace.lua` LH-19 edit

The flagged citation sat in a **stale duplicate** comment block (old lines 7–8) that (a) cited the
retired `§7.4`, (b) described the chat tag as a "green accent … Loot History's identity", and (c) was
fully superseded by the block immediately below it (lines 9–11), which already carries the correct
`slash-commands-§4` citation **and** the mandate that the tag is the cyan Ka0s house colour that "MUST
NOT be substituted". Since the actual constant is cyan (`|cff00ffff[LH]|r`), the old block was not
just redundant but wrong. It was **removed** rather than re-cited — the cleanest resolution of the
retired citation. All other LH-19 edits were in-place citation rewrites (comment-only).

---

## 5. Verification

- `luacheck .` → **0 warnings / 0 errors in 20 files.**
- `lua tests/run.lua` → **224 passed, 0 failed, 224 total** (unchanged count → `docs/test-cases.md`
  and the README `[tests]` badge stay in sync; no regeneration needed).
- No version bump (conformance edits only; per repo hard rules).
- **Pending manual step:** in-game smoke test of the reordered TOC (see §3).

---

## 6. Definition of done — status

- **In-scope IDs closed:** LH-13 (vs `toc-file-§5`, with the §3 caveat), LH-14, LH-15, LH-18, LH-19.
- **Out-of-scope, still open:** LH-16, LH-17 (SHOULD; user did not request them this pass).
- **Green gate holds;** test inventory + badge already in lockstep (count unchanged).
- **`01`–`05` left frozen;** this `06` is the only addition to the 2026-07-18 bundle.
