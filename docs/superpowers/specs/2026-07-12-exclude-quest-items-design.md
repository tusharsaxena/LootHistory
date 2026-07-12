# Design — Exclude Quest-type items at capture

**Date:** 2026-07-12
**Status:** Approved (pending spec review)
**Scope:** Add an opt-in, account-wide setting that drops Quest-class items at the data collection layer.

---

## Problem

Quest items (the transient objects collected during quests — quest starters, temporary
turn-in reagents) are recorded into loot history like any other loot above the quality
threshold. They add noise to the History table and Insights without carrying lasting
value. Users should be able to exclude them.

The filter belongs at the **data collection layer**: quest items are transient by nature,
so there is no reason to persist them. Gating at capture — alongside the existing quality
threshold and muted-source gates — is cleaner than filtering at display time and keeps the
stored dataset smaller.

## Behavior

- New account-wide setting `settings.excludeQuestItems`, a boolean, **default `false`**
  (ships disabled; opt-in).
- When enabled, the collector drops any looted item whose item **class is Quest** before
  it is written to `LootHistoryDB.global.history`.
- Toggleable through the Settings panel checkbox and slash `get` / `set` / `list` / `reset`,
  exactly like every other collection setting.
- Capture-time only: enabling the setting does **not** retroactively remove quest items
  already stored. (A one-time cleanup of existing records is explicitly out of scope.)

## Locale-safe signal (key decision)

The filter keys on the item **class ID** (`Enum.ItemClass.Questitem`, numeric `12`), **not**
the localized `itemType` string. `itemType` returns "Quest" only on English clients; a
string match would silently fail on other locales — a violation of the addon's
locale-independence convention (cf. `classFile` for classes).

The class ID is already available cheaply: `C_Item.GetItemInfoInstant(link)` returns it as
its 6th value, and that call is instant/cached, so reading it in the gate path adds no
meaningful cost.

## Components / files touched

1. **`core/Constants.lua`** — add `C.ITEMCLASS_QUEST = 12`, commented as
   `Enum.ItemClass.Questitem`. Named constant the gate references (no magic number in the
   collector).

2. **`core/Compat.lua`** — extend `Compat.GetItemInfo(link)` to return `classID` as a 4th
   value. It already calls `GetItemInfoInstant`; surface its 6th return. Update the doc
   comment to document the new return.

3. **`defaults/Global.lua`** — add `excludeQuestItems = false` to `settings`.

4. **`settings/Schema.lua`** — add a `CheckBox` row in the **Data Collection** group:
   - `path = "settings.excludeQuestItems"`, `default = false`, `type = "boolean"`,
     `widget = "CheckBox"`.
   - `label = "Exclude quest items"`,
     `tooltip = "Skip items of the Quest type (transient quest objects)."`.
   - Ordered **between** `qualityThreshold` and `retentionDays`, so it pairs as the second
     cell of the first two-column row (Minimum quality | Exclude quest items).
   - `onChange` sends `Ka0s_LootHistory_SettingsChanged` (tag e.g. `"questfilter"`).

5. **`modules/Collector.lua`**:
   - Add hot-path upvalue `excludeQuestItems`, refreshed in `RefreshUpvalues` from
     `s.excludeQuestItems`.
   - Change `ShouldRecord` signature to `ShouldRecord(quality, source, classID, cfg)` and
     add the gate: `if cfg.excludeQuestItems and classID == NS.Constants.ITEMCLASS_QUEST
     then return false end`. Per-item signals (quality, source, classID) precede `cfg`
     (config); item class is deliberately **not** folded into `cfg`.
   - In `OnChatMsgLoot`, capture `classID` from the extended `GetItemInfo` return and pass
     it plus `excludeQuestItems` in the cfg table.

6. **`tests/`**:
   - `wow_mock.lua` — extend the mocked `GetItemInfoInstant` to return a class ID at
     position 6 (so the full `OnChatMsgLoot` path exercises the new return).
   - `test_collector.lua` — update the 4 existing `ShouldRecord` call sites for the new
     `classID` argument; add cases:
     - quest class (`12`) dropped when `excludeQuestItems = true`;
     - quest class kept when `excludeQuestItems = false`;
     - non-quest class unaffected in both states.

## Conventions / non-goals

- Routes through the existing `SettingsChanged` → `RefreshUpvalues` refresh. **No new
  message, no cross-module reach** (closed message bus, CLAUDE §3).
- Schema-as-single-source is preserved: the setting is a normal Schema row driving AceDB
  default, panel widget, and slash get/set/list/reset (CLAUDE §2).
- No locale-file change — Schema labels/tooltips are inline strings, matching existing rows.
- No display-layer filter. No retroactive purge of already-stored quest items.
- The `SourceType` enum and `Database:Export` shape are untouched (export contract stable).

## Verification

- `luacheck .` → 0/0.
- `lua tests/run.lua` → green, including the new quest-gate cases.
- Smoke (in-client): with the setting OFF, loot a quest item → recorded; toggle ON, loot a
  quest item → not recorded; a non-quest item of the same quality → recorded in both states;
  confirm the "Exclude quest items" checkbox renders cleanly in the Data Collection group's
  two-column layout.
