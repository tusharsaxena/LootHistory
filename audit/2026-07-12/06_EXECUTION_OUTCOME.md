# 06 — Execution Outcome (Remediation)

Outcome of executing the remediation designed in `04_TECHNICAL_DESIGN.md` and sequenced in
`05_EXECUTION_PLAN.md`. All 12 deviations `LH-01…LH-12` are **closed**. Work was done trunk-based on
`master`, sequentially, under the green gate — `lua tests/run.lua` (green) **and** `luacheck .` (0/0)
verified at **every** commit. No SavedVariables migration was triggered; `schemaVersion` stays `1`.

> **Why not parallel-agent editing?** The deviations are heavily interdependent on *shared* files
> (`.luacheckrc` ← LH-10 + LH-12, `settings/Panel.lua` ← LH-04/08/09, the TOC ← LH-05/06). Fanning
> out parallel file-editors would collide on those files, and project memory records that impl
> subagents here drift/over-build and must stay under review gates in the main loop. So the build
> ran sequentially in the main loop with the green gate; a **dynamic verification workflow** (12
> adversarial auditors + a completeness critic) then re-audited the finished work — see §5.

---

## 1. Decisions taken (from the up-front questions)

- **`X-Wago-ID` — omitted.** The addon is not listed on Wago, so the field was intentionally left
  out of the TOC rather than fabricated. Everything else in LH-05 (OptionalDeps, X-Standard,
  X-Curse-Project-ID, Category) shipped. **Action for later:** if/when Ka0s Loot History is listed
  on Wago, add `## X-Wago-ID: <id>` in canonical order (right after `## X-Curse-Project-ID`).
- **TODO.md backlog → GitHub issues.** The pre-1.0.0 backlog was migrated to
  `tusharsaxena/LootHistory` issues **#1–#12** before deleting `TODO.md`. Two TODO items were *not*
  filed because they were already resolved: "Purge history in Settings" (already implemented in
  `settings/Panel.lua`) and "check Reset All / Purge button width" (that *is* LH-09, fixed here).

---

## 2. Per-deviation outcome

| ID | Status | What changed | Key files |
|----|--------|--------------|-----------|
| LH-01 | ✅ Closed | Deleted root `TODO.md`; backlog → issues #1–#12; reworded the deconstruct comment to drop "see TODO.md". | `TODO.md` (deleted), `modules/Attribution.lua` |
| LH-02 | ✅ Closed | Root `CLAUDE.md` reduced to a ~15-line stub (tier + standard link + docs pointer); full brief moved to `docs/AGENT_CONTEXT.md`. | `CLAUDE.md`, `docs/AGENT_CONTEXT.md` |
| LH-03 | ✅ Closed | `ARCHITECTURE.md` → `docs/ARCHITECTURE.md` (`git mv`); inbound refs repointed. | `docs/ARCHITECTURE.md`, `modules/Browser.lua` |
| LH-04 | ✅ Closed | `media/logo/` → `media/logos/` (typed subfolder); `LOGO_PATH` repointed. | `media/logos/*`, `settings/Panel.lua` |
| LH-05 | ✅ Closed | TOC: added `OptionalDeps`, `X-Standard`, `X-Curse-Project-ID: 1607560`; `Category-enUS: Misc`. `X-Wago-ID` intentionally omitted (see §1). | `LootHistory.toc` |
| LH-06 | ✅ Closed | Canonical section comments (`# Libraries/Core/Defaults/Locales/Settings/Modules`), Locales split from Defaults; load order preserved (settings before modules, §1.2). | `LootHistory.toc` |
| LH-07 | ✅ Closed | Added `NS:RunMigrations()` (idempotent; safe no-op when DB absent); called from `InitDB` after AceDB init. TDD: 4 new cases. | `core/Database.lua`, `defaults/Global.lua`, `tests/test_database.lua` |
| LH-08 | ✅ Closed | Per-instance `FixScroll` rebind (`installAlwaysShownScrollbar`) — bar always shown, gutter always reserved, inert (parked + greyed) when the page fits. | `settings/Panel.lua` |
| LH-09 | ✅ Closed | `BUTTON_PAIR_REL = 0.492`; Reset All + Purge routed through a shared `makePairButton`. | `settings/Panel.lua` |
| LH-10 | ✅ Closed | Removed `Compat.IsRetail`/`IsClassic` + Classic-flavor comments; dropped `WOW_PROJECT_*` from `.luacheckrc` and the test mock. TDD: 2 new cases. | `core/Compat.lua`, `.luacheckrc`, `tests/wow_mock.lua`, `tests/test_compat.lua` |
| LH-11 | ✅ Closed | Added the Ka0s WoW Addon Standard badge; fixed the issues slug to `tusharsaxena/LootHistory`; removed the repo-URL TODO comment. | `README.md` |
| LH-12 | ✅ Closed | Excluded `audit/` from packaging (`.pkgmeta`) and lint (`.luacheckrc`). | `.pkgmeta`, `.luacheckrc` |

### Doc-drift fixed alongside (not separate deviations)
Fixing LH-07 and LH-10 reversed statements that several docs still described in the pre-fix tense.
The verification workflow's completeness critic (§5) surfaced the full set; all **living** docs were
swept to match the code:
- `defaults/Global.lua`, `docs/ARCHITECTURE.md`, `docs/TECHNICAL_DESIGN.md` (§3.3) and
  `docs/REQUIREMENTS.md` (FR-C17) said *"no migration runner ships / post-release concern"* —
  updated to describe the shipped `NS:RunMigrations` (LH-07). Stale `0.1.0` → `1.0.0`.
- `docs/ARCHITECTURE.md` and `docs/TECHNICAL_DESIGN.md` (module map + Compat helper list) documented
  *"Flavor flags (IsRetail/IsClassic…)"* — rewritten to the `C_*`-presence / Retail-only idiom (LH-10).
- Dangling `TODO.md` pointers in `docs/TECHNICAL_DESIGN.md` and `docs/EXECUTION_PLAN.md` (backlog
  section) redirected to the GitHub issue tracker (LH-01).
- **Intentionally left as frozen record:** `docs/EXECUTION_PLAN.md` milestone task-log lines
  ("Milestone N — Files: Create core/Compat.lua (IsRetail/IsClassic…)", "Unreleased addon → no
  migration runner"). These describe what each milestone built at the time — a historical build log,
  treated like the `reviews/` and `audit/` bundles. The critic agreed these are historical/low-priority.

---

## 3. Commits (this engagement, on `master`)

```
ff74fe3 settings: §6.6/§6.10 panel conformance — button inset + always-shown scrollbar (LH-08/09)
accf170 compat: remove game-flavor flags; enforce API-presence idiom (LH-10)
ca4bc7d db: ship RunMigrations schema-migration seam, invoked from InitDB (LH-07)
b84c3f5 assets: rename media/logo -> media/logos (typed subfolder); update LOGO_PATH (LH-04)
6f379f3 toc/pkg: §2.1 metadata + canonical listing; audit exclusion; README standard badge (LH-05/06/11/12)
f2a2116 docs: root to §15 shape; migrate TODO backlog to issues (LH-01/02/03)
```

Not pushed — per the Ka0s git workflow, the user pushes when ready.

---

## 4. Test harness

WoW runs **Lua 5.1**, so the tests target it. The harness is fully headless — no game client needed.

### What it is
- **Runner:** `tests/run.lua` — run from the repo root: `lua tests/run.lua`. It loads every source
  file in TOC order through `tests/loader.lua` under a WoW-API mock (`tests/wow_mock.lua`), calls
  `NS:InitDB()` (which now also runs `NS:RunMigrations()`), then executes each suite and prints
  `PASS`/`FAIL` per test plus a total. Exit code is non-zero if any test fails.
- **Loader:** `tests/loader.lua` — runs each chunk as `(addonName, NS)` with an environment where
  WoW globals resolve to the mock set, falling back to `_G`.
- **Mock:** `tests/wow_mock.lua` — a fresh, isolated WoW-API stub per run. Deliberately **omits**
  several `C_*` APIs (`C_ChallengeMode`, `C_Container`, `C_Spell`, `C_TooltipInfo`, …) so the compat
  firewall's API-presence guards are exercised in their degraded path. As of LH-10 it no longer
  defines `WOW_PROJECT_*` (nothing reads them).
- **Suites:** `test_util`, `test_compat`, `test_attribution`, `test_collector`, `test_database`,
  `test_stats`, `test_browsertable`, `test_debuglog`.

### Current status
- **`lua tests/run.lua` → 124 passed, 0 failed, 124 total** (was 118 before this engagement; **+6**:
  4 `RunMigrations` cases in `test_database.lua`, 2 Compat cases in `test_compat.lua`).
- **`luacheck .` → 0 warnings / 0 errors in 18 files** (now skips `audit/` per LH-12).

### New tests added this engagement
- `tests/test_database.lua`: `RunMigrations` sets `schemaVersion` when absent · leaves a current DB
  unchanged · idempotent across repeated runs · safe no-op when the DB is absent.
- `tests/test_compat.lua`: API-absent guards degrade to nil/false **with no flavor flag** · no
  game-flavor flags (`IsRetail`/`IsClassic`) are exposed.

### How to re-run the gate
```bash
cd <repo root>
luacheck .          # expect: 0 warnings / 0 errors in 18 files
lua tests/run.lua   # expect: 124 passed, 0 failed, 124 total
```

---

## 5. Independent verification (dynamic workflow)

Per the request to use ultracode/dynamic workflows, a **verification workflow** (`lh-remediation-verify`)
ran after the build: **12 independent adversarial auditors** (one per LH-item, told to prove or
*disprove* each claim strictly from the repo) plus a **completeness critic** that re-ran the green
gate itself and hunted for drift/regressions. 13 agents, 0 errors, ~348k subagent tokens, ~146s.

**Result: all 12 items independently confirmed CLOSED. No code regressions. Green gate re-confirmed
by the critic** (`luacheck . = 0/0 in 18 files`; `lua tests/run.lua = 124 passed / 0 failed`).

Auditor notes worth recording (none reopen a deviation):
- **LH-05** — the missing `X-Wago-ID` was correctly read as an *accepted omission*, not a defect.
- **LH-04** — the only surviving singular `media\logo\` string is in the frozen `03_EVIDENCE.md`
  audit bundle (a historical record of the pre-fix state), not a live path.
- The critic's one substantive finding was **documentation drift** in `docs/` — living design docs
  still describing the pre-LH-07/LH-10 state, plus dangling `TODO.md` links. **This was then swept**
  (see §2 "Doc-drift fixed alongside"); the frozen milestone task-log lines were intentionally kept.

The workflow artifacts (per-agent verdicts + critic) are in the session's workflow transcript
(`journal.jsonl`).

---

## 6. Manual smoke tests (run in-client)

These validate the runtime-affecting changes. The headless harness can't cover in-game rendering,
the TOC load, or the SavedVariables file — these do. Run on **Retail (Midnight 12.0.7)**.

> Prep: fully exit WoW, copy/refresh the addon, launch, log in a character.

### S-1 — Clean load (LH-05, LH-06, LH-10)
1. At the character-select or in-world, run `/reload`.
2. **Expect:** no Lua error popup; no BugSack/BugGrabber entries for LootHistory. The addon loads
   all files (the TOC edits didn't drop any). `/lh` prints the help index.
3. On the AddOns list (or `/lh config` → landing page), the addon is present.

### S-2 — Category + metadata (LH-05)
1. Open the in-game **AddOns** list / ElvUI addon list where category is shown.
2. **Expect:** Ka0s Loot History is filed under **Misc** (not "Bags & Inventory").

### S-3 — Settings landing logo (LH-04)
1. `/lh config` (or ESC → Options → AddOns → **Ka0s Loot History**).
2. **Expect:** the landing page renders the **logo** image (300×300). A broken/blank logo means the
   `media/logos/` path is wrong — it should display.

### S-4 — Always-shown inert scrollbar + stable width (LH-08)
1. In Settings, select the **General** subcategory (a short page that fits without scrolling).
2. **Expect:** the vertical **scrollbar is visible on the right edge and greyed/disabled** (thumb
   parked at top; up/down arrows inert). It does **not** auto-hide.
3. Click back to the **Ka0s Loot History** landing page (longer content), then back to **General**.
4. **Expect:** the body content's left/right margins **don't jump** between the two pages — the
   right gutter stays reserved, so column widths are identical on both.

### S-5 — Paired action-button width (LH-09)
1. In Settings → **General**, find the **Reset All** button (right of the Window-scale slider) and
   the **Purge history…** button (right of the storage-stats label).
2. **Expect:** each button's **right border is fully drawn** (not shaved/clipped by the scroll
   gutter), and it lines up cleanly with its left-hand neighbor. No spill past the panel edge.

### S-6 — Capture still works (LH-10 regression guard)
1. Close settings. Loot any item at/above your quality threshold (kill a mob, open a container, or
   buy from a vendor).
2. `/lh` (or `/lh toggle`) to open the window → **History** tab.
3. **Expect:** the looted item appears as a new row with a plausible **source** — capture and
   attribution are unaffected by the compat de-branch.

### S-7 — Reset All / Purge dialogs (LH-09 functional)
1. Settings → General → click **Purge history…**. **Expect:** a confirm dialog; Cancel leaves data
   intact.
2. Click **Reset All**. **Expect:** a confirm dialog (it still resets settings; note issue **#1**
   tracks changing it to reset-settings-only).

### S-8 — schemaVersion after a session (LH-07)
1. After playing/looting, fully **log out** (so SavedVariables flush).
2. Open `WTF/Account/<acct>/SavedVariables/LootHistory.lua`.
3. **Expect:** `LootHistoryDB["global"]["schemaVersion"] = 1` — the migration runner ran at init and
   left the version at 1 (no unintended bump).

---

## 7. Residual / follow-ups (not defects)

- **`X-Wago-ID`** — add when the addon is listed on Wago (§1).
- **`X-Curse-Project-ID` corrected to `1607560`.** The audit inputs (`01`–`05`) recorded `1530802`
  (a misread of the README CurseForge badge, which actually points at `1607560`); the shipped TOC
  value was corrected to `1607560` per the author. The frozen `01`–`05` bundle still shows the
  original (incorrect) value as the historical audit record.
- **Backlog** now lives in GitHub issues #1–#12 (was `TODO.md`). Notably **#1** (Reset All →
  reset-settings-only) is a behavior change the audit deliberately left out of scope.
- A **re-audit** (new `audit/<date>/`) should reuse `LH-01…LH-12` and find them all resolved.
