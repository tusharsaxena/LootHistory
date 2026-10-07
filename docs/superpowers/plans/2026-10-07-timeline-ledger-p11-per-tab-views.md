# Timeline Ledger — Phase 11 (Per-tab filter views; Holdings Save/Reset/Clear) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal (owner feedback 2026-10-07):** Save, Reset and Clear do nothing on the Holdings tab. Filter settings must be per tab: History, Insights, Timeline and Holdings each keep their own live filter state and their own saved view; Save/Reset/Clear act on the active tab only.

**Controller rulings:** (1) per-tab LIVE state too (each tab its own group/sort/date/search/multi-select filters/tab-specific fields like timelineThing, timelineTotalOnly, holdings group/sort); switching tabs loads that tab's state into the shared filter-bar widgets. This supersedes the issue-#13 "one shared filter for both panes" design — document the change in docs/browser.md and spec §8.0 (dated owner decision). (2) Storage: `profile.savedViews = { History = view, Insights = view, Timeline = view, Holdings = view }`; the old single `profile.savedView` is migrated by schema step `to = 14`: copied into every tab's slot (so every tab starts exactly where the user is today), then removed. Walk every stored profile raw (as earlier profile steps do); idempotent. (3) Save = store the active tab's current state; Reset = restore the active tab's saved view (or stock if none); Clear = the active tab's stock defaults (tab-appropriate: Holdings stock group None/sort name; Timeline keeps no thing? keep the current thing on Clear but reset filters — document). (4) Holdings' group/sort become saved per tab (previously session-only, P6 ruling — superseded).

## Global Constraints
All earlier Global Constraints bind (Compat boundary, ≤ 1500 lines per file — split modules/BrowserFilterBar.lua or Browser.lua view code into `modules/BrowserViews.lua` if needed, append-only migrations with schemaVersion default 0, CRLF restore, gate via ka0s-bounded, regenerate docs/test-cases.md). Test mode stays session-only and never writes saved views.

## Review Focus
1. Save/Reset/Clear on each of the four tabs changes only that tab's state and saved slot (assert the other three untouched). Pinned in Task 1.
2. Switching tabs back and forth restores each tab's live state exactly, including multi-select sets and search text. Pinned in Task 1.
3. Migration v14 from a profile with a savedView → four identical per-tab slots, old key removed; from a profile without one → nothing created; re-run changes 0. Pinned in Task 1.
4. Holdings Save/Reset/Clear actually take effect on the Holdings view (the reported bug). Pinned in Task 1.

### Task 1: Per-tab live state and saved views; v14 migration; Save/Reset/Clear per tab
**Files:** `modules/Browser.lua` (view state, SaveView/ResetView/ClearView/ApplyView, tab registry hooks: each tab spec may contribute `captureView()`/`applyView(view)` for its own fields), `modules/BrowserFilterBar.lua` (load the active tab's state into the widgets; per-tab graying from P3 stays), `modules/BrowserTable.lua` (History state), `modules/HoldingsTab.lua` (group/sort into the view), `modules/Timeline.lua` (thing/totalOnly into the view), `modules/Analytics.lua` (Insights reads its own tab state, not History's), `core/Database.lua` (append `to = 14`), `defaults/Profile.lua` (`savedViews` default per AceDB rules — declare `{}` or nothing, follow the savedView precedent), tests (`tests/test_browser.lua`, `tests/test_database.lua`, `tests/test_profiles.lua` if it pins savedView/version, Holdings/Timeline/Analytics suites), docs (`docs/browser.md`, `docs/schema.md` incl. v14, `docs/profiles.md`, `docs/smoke-tests.md` row HIST-36 "per-tab views", spec §8.0 amendment).
**Requirements:** as Rulings. Diagnose and state in the report why Save/Reset/Clear did nothing on Holdings before. Tests for every Review Focus item; profile switch/reset/copy semantics keep working with savedViews (follow how savedView behaves on profile reset today). Commit(s): `feat(browser): per-tab filter views; Save/Reset/Clear act on the active tab (v14)`.

### Task 2: Restore the original Reset / Clear meanings, per tab (controller ruling correction)

**Why:** Phase 11 ruling 3 swapped the long-standing semantics. On master: **Reset** = delete the saved view and go to stock ("Reset the saved view to stock defaults."); **Clear** = filters/group/sort back to the saved view, or stock if none ("Clear filters and group/sort back to your saved view."). BankLedger's per-tab change kept those meanings. Restore them in LootHistory, per tab, so both addons agree.

**Files:** `modules/Browser.lua` (ResetView, ClearFilters, button tooltips), tests (`tests/test_views.lua` / `tests/test_browser.lua`), docs (`docs/browser.md` "Saved views" bullet, `docs/smoke-tests.md` HIST-18/HIST-36, spec §8.0 amendment text, any README line).

**Requirements:** Reset: `savedViews[activeTab] = nil` (drop the `savedViews` table when its last slot empties, as BankLedger does), apply the active tab's stock view, chat line "view reset to stock defaults." unless silent. Clear: apply the active tab's saved view or its stock view; the saved slot is kept. Neither touches another tab. Test mode: Save refuses; Reset/Clear apply stock without writing. Tooltips: original wording, with "this tab's". Tests: per tab, Reset deletes only that slot and applies stock; Clear applies the saved view when present, stock when absent; other tabs untouched. Commit: `fix(browser): Reset deletes the tab's saved view, Clear returns to it (original meanings, per tab)`.
