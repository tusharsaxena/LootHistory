# Exclude Quest-type Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in, account-wide setting (`settings.excludeQuestItems`, default OFF) that drops Quest-class items at the data collection layer, before they are written to history.

**Architecture:** Gate quest items in the existing `Collector:ShouldRecord` pure seam, keyed on the locale-independent item **class ID** (`Enum.ItemClass.Questitem` = `12`) which `C_Item.GetItemInfoInstant` already returns. The setting is a normal Schema row (drives AceDB default, panel checkbox, slash get/set/list/reset) and the collector caches it as a hot-path upvalue refreshed on `Ka0s_LootHistory_SettingsChanged` — no new message, no cross-module reach.

**Tech Stack:** Lua 5.1, Ace3 (AceDB/AceEvent), headless test harness (`tests/run.lua`), luacheck.

## Global Constraints

- **Locale-safe:** gate on class ID `12`, never the localized `itemType` string.
- **Schema-as-single-source:** every user setting mutation routes through `Schema:Set`; the row drives AceDB default + panel + slash. Paths resolve against `NS.db.global` (account-wide).
- **Closed message bus:** reuse `Ka0s_LootHistory_SettingsChanged`; do not add a new message.
- **Compat firewall:** all flavor/deprecated API access lives in `core/Compat.lua`; modules call `NS.Compat.X`.
- **Hot-path upvalues:** collector caches settings, refreshed on `SettingsChanged`.
- Files capped at 1500 LOC. `luacheck .` must report **0/0** and `lua tests/run.lua` must be green before every commit.
- Capture-time only: no retroactive purge of already-stored quest items; no display-layer filter.
- Do not touch the `SourceType` enum or `Database:Export` shape (export contract).

---

### Task 1: Locale-safe class-ID plumbing

Surface the item class ID from Compat and expose the Quest class constant, so the collector can gate on it. Purely additive — nothing consumes the new value yet, so all existing tests stay green.

**Files:**
- Modify: `core/Constants.lua` (add `C.ITEMCLASS_QUEST`)
- Modify: `core/Compat.lua:168-180` (`GetItemInfo` returns classID)
- Modify: `tests/wow_mock.lua:48-51` (mock returns classID at position 6)
- Test: `tests/test_compat.lua`

**Interfaces:**
- Produces: `NS.Constants.ITEMCLASS_QUEST == 12`.
- Produces: `NS.Compat.GetItemInfo(link)` → `itemID, itemName, quality, classID` (classID is the 4th return; `nil` when the item is uncached/unknown).
- Produces (test seam): `T.mocks.__itemClassID` — overridable class ID the mocked `GetItemInfoInstant` returns at position 6; defaults to `0` (Consumable) so existing end-to-end tests still record.

- [ ] **Step 1: Update the mock to return a class ID at position 6**

In `tests/wow_mock.lua`, replace the `GetItemInfoInstant` line (currently `GetItemInfoInstant = function() return 211296 end,`) so it returns a class ID as the 6th value, sourced from an overridable field (default 0):

```lua
  M.__itemClassID = 0   -- overridable per-test item class (Enum.ItemClass); 0 = Consumable
  M.C_Item = {
    GetItemInfoInstant = function() return 211296, nil, nil, nil, nil, M.__itemClassID end,
    GetItemInfo = function(link) return "Item Name", link, 4 end,
  }
```

- [ ] **Step 2: Write the failing Compat test**

Append to `tests/test_compat.lua`:

```lua
test("Compat: GetItemInfo surfaces the item class id", function()
  T.mocks.__itemClassID = 12
  local _, _, _, classID = NS.Compat.GetItemInfo("|cffffffff|Hitem:1::::::::80:::::|h[X]|h|r")
  assertEqual(classID, 12)
  T.mocks.__itemClassID = 0   -- restore default
end)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL — `GetItemInfo` currently returns only 3 values, so `classID` is `nil` (assert `12 ~= nil`).

- [ ] **Step 4: Add the constant**

In `core/Constants.lua`, after the `C.Confidence` block (around line 40), add:

```lua
-- Item class id for Quest-type items (Enum.ItemClass.Questitem). Locale-independent; the
-- collector's optional quest-item filter gates on this, never the localized itemType string.
C.ITEMCLASS_QUEST = 12
```

- [ ] **Step 5: Extend `Compat.GetItemInfo` to return classID**

In `core/Compat.lua`, update `GetItemInfo`. Change the instant-info block to also capture classID, and add it to the return + doc comment:

```lua
-- Resilient item info for an item link. Returns itemID, itemName, quality, classID, falling
-- back to the link's own display data when the item is not yet cached (GetItemInfo returns nil).
-- classID is the locale-independent item class (Enum.ItemClass.*); nil when uncached/unknown.
function Compat.GetItemInfo(link)
  local itemID, classID
  if C_Item and C_Item.GetItemInfoInstant then
    itemID = C_Item.GetItemInfoInstant(link)
    classID = select(6, C_Item.GetItemInfoInstant(link))
  end
  local name, _, quality
  if C_Item and C_Item.GetItemInfo then
    name, _, quality = C_Item.GetItemInfo(link)
  end
  name = name or (link and link:match("%[(.-)%]"))
  quality = quality or Compat.QualityFromLink(link)
  return itemID, name, quality, classID
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: PASS (new Compat test green; all prior tests still green).

- [ ] **Step 7: Lint**

Run: `luacheck .`
Expected: 0 warnings / 0 errors.

- [ ] **Step 8: Commit**

```bash
git add core/Constants.lua core/Compat.lua tests/wow_mock.lua tests/test_compat.lua
git commit -m "feat(compat): surface item class id + ITEMCLASS_QUEST constant

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Quest gate in the collector

Add the filter to `ShouldRecord` and wire the collector to pass the class ID and read the (not-yet-exposed) setting. The setting field defaults to nil/false until Task 3 adds it to defaults, so the filter stays off unless a test writes the field directly — everything stays green.

**Files:**
- Modify: `modules/Collector.lua` (upvalue, `RefreshUpvalues`, `ShouldRecord`, `OnChatMsgLoot`)
- Test: `tests/test_collector.lua`

**Interfaces:**
- Consumes: `NS.Constants.ITEMCLASS_QUEST`, `NS.Compat.GetItemInfo` → 4th return `classID` (Task 1).
- Produces: `Collector:ShouldRecord(quality, source, classID, cfg)` where `cfg = { qualityThreshold, excludedSources, excludeQuestItems }`. Returns `false` when `cfg.excludeQuestItems` is truthy and `classID == NS.Constants.ITEMCLASS_QUEST`.
- Produces: `NS.db.global.settings.excludeQuestItems` (boolean) read into the collector's `excludeQuestItems` upvalue on `RefreshUpvalues`.

- [ ] **Step 1: Update existing ShouldRecord tests for the new signature + add quest cases**

In `tests/test_collector.lua`, update the four existing `ShouldRecord` call sites to insert a class-ID argument (`0` = non-quest) before `cfg`, and append three new tests. The four edits:

```lua
-- "passes at/above threshold"
  assertTrue(NS.Collector:ShouldRecord(2, "KILL", 0, cfg))
  assertTrue(NS.Collector:ShouldRecord(4, "KILL", 0, cfg))
-- "rejects below threshold"
  assertFalse(NS.Collector:ShouldRecord(1, "KILL", 0, cfg))
  assertFalse(NS.Collector:ShouldRecord(0, "KILL", 0, cfg))
-- "rejects excluded source"
  assertFalse(NS.Collector:ShouldRecord(4, "VENDOR", 0, cfg))
  assertTrue(NS.Collector:ShouldRecord(4, "KILL", 0, cfg))
-- "treats nil quality as 0"
  assertFalse(NS.Collector:ShouldRecord(nil, "KILL", 0, cfg))
```

New tests (append after the `nil quality` test):

```lua
test("Collector: ShouldRecord drops quest items when excludeQuestItems on", function()
  local cfg = { qualityThreshold = 1, excludedSources = {}, excludeQuestItems = true }
  assertFalse(NS.Collector:ShouldRecord(4, "KILL", NS.Constants.ITEMCLASS_QUEST, cfg))
end)

test("Collector: ShouldRecord keeps quest items when excludeQuestItems off", function()
  local cfg = { qualityThreshold = 1, excludedSources = {}, excludeQuestItems = false }
  assertTrue(NS.Collector:ShouldRecord(4, "KILL", NS.Constants.ITEMCLASS_QUEST, cfg))
end)

test("Collector: ShouldRecord unaffected for non-quest class when filter on", function()
  local cfg = { qualityThreshold = 1, excludedSources = {}, excludeQuestItems = true }
  assertTrue(NS.Collector:ShouldRecord(4, "KILL", 0, cfg))
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL — old `ShouldRecord(quality, source, cfg)` treats the 3rd arg as `classID` and the 4th (`cfg`) as `nil`, so `cfg.qualityThreshold` errors; new quest cases also fail.

- [ ] **Step 3: Update the upvalue declaration + RefreshUpvalues**

In `modules/Collector.lua`, change the upvalue line (currently `local enabled, qualityThreshold, excludedSources = true, 1, {}`) to:

```lua
local enabled, qualityThreshold, excludedSources, excludeQuestItems = true, 1, {}, false
```

And in `RefreshUpvalues`, after the `excludedSources` line, add:

```lua
  excludeQuestItems = s.excludeQuestItems
```

- [ ] **Step 4: Add the gate to ShouldRecord**

Replace `Collector:ShouldRecord` with the 4-arg version:

```lua
-- Quality gate + per-source exclude + optional quest-item drop.
-- cfg = { qualityThreshold, excludedSources, excludeQuestItems }.
function Collector:ShouldRecord(quality, source, classID, cfg)
  if (quality or 0) < cfg.qualityThreshold then return false end
  if cfg.excludedSources and cfg.excludedSources[source] then return false end
  if cfg.excludeQuestItems and classID == NS.Constants.ITEMCLASS_QUEST then return false end
  return true
end
```

- [ ] **Step 5: Wire OnChatMsgLoot to capture classID and pass the cfg**

In `Collector:OnChatMsgLoot`, capture the 4th return of `GetItemInfo` and pass it plus `excludeQuestItems` into `ShouldRecord`:

```lua
  local itemID, itemName, quality, classID = NS.Compat.GetItemInfo(link)
  local source, sourceDetail, confidence = NS.Attribution:Consume()

  if not self:ShouldRecord(quality, source, classID,
    { qualityThreshold = qualityThreshold, excludedSources = excludedSources,
      excludeQuestItems = excludeQuestItems }) then
    return
  end
```

- [ ] **Step 6: Add an end-to-end quest-drop test**

Append to `tests/test_collector.lua`:

```lua
test("Collector: end-to-end drops quest items when the filter is on", function()
  local mocks = T.mocks
  mocks.__now = 0
  mocks.__itemClassID = NS.Constants.ITEMCLASS_QUEST
  NS.db.global.settings.excludeQuestItems = true
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before)   -- quest item dropped

  -- restore: filter off, non-quest class → records again
  NS.db.global.settings.excludeQuestItems = false
  mocks.__itemClassID = 0
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before + 1)
end)
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: PASS (all collector tests green, including quest cases + e2e).

- [ ] **Step 8: Lint**

Run: `luacheck .`
Expected: 0 warnings / 0 errors.

- [ ] **Step 9: Commit**

```bash
git add modules/Collector.lua tests/test_collector.lua
git commit -m "feat(collector): drop quest-class items when excludeQuestItems set

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Expose the setting (Schema row + default)

Register the setting so it appears in the panel and slash CLI, with `default = false`. After this task the feature is fully user-controllable.

**Files:**
- Modify: `defaults/Global.lua:11-18` (add default)
- Modify: `settings/Schema.lua:33-46` (add row in Data Collection group)
- Test: `tests/test_collector.lua` (schema-registration assertions)

**Interfaces:**
- Consumes: `NS.Schema:Set`, `NS.Schema:Get`, `NS.Schema:Default` (existing seams).
- Produces: Schema row `settings.excludeQuestItems`, `default = false`, in the `Data Collection` group; AceDB default `NS.defaults.global.settings.excludeQuestItems = false`.

- [ ] **Step 1: Write the failing schema test**

Append to `tests/test_collector.lua`:

```lua
test("Schema: excludeQuestItems row exists, defaults false, settable", function()
  assertEqual(NS.Schema:Default("settings.excludeQuestItems"), false)
  assertEqual(NS.defaults.global.settings.excludeQuestItems, false)
  assertTrue(NS.Schema:Set("settings.excludeQuestItems", true))
  assertEqual(NS.Schema:Get("settings.excludeQuestItems"), true)
  NS.Schema:Set("settings.excludeQuestItems", false)   -- restore
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL — `S:Default` returns `nil` for the unknown path; `S:Set` returns `false, "unknown path"`.

- [ ] **Step 3: Add the AceDB default**

In `defaults/Global.lua`, inside the `settings = { … }` table, add after the `qualityThreshold` line:

```lua
    excludeQuestItems = false,  -- opt-in: drop Quest-class items at capture
```

- [ ] **Step 4: Add the Schema row**

In `settings/Schema.lua`, in the `Data Collection` group, insert this row **between** the `qualityThreshold` row and the `retentionDays` row (so it pairs as the second cell of the first two-column row):

```lua
  { path = "settings.excludeQuestItems", default = false, type = "boolean", widget = "CheckBox",
    group = "Data Collection", label = "Exclude quest items",
    tooltip = "Skip items of the Quest type (transient quest objects).",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "questfilter") end
    end },
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: PASS (schema test green; all prior tests still green).

- [ ] **Step 6: Lint**

Run: `luacheck .`
Expected: 0 warnings / 0 errors.

- [ ] **Step 7: Commit**

```bash
git add defaults/Global.lua settings/Schema.lua tests/test_collector.lua
git commit -m "feat(settings): add opt-in Exclude quest items setting (default off)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Smoke tests (in-client, post-implementation)

Not automatable headless — run once in WoW:

1. Open `/lh config` → **Data Collection** shows an "Exclude quest items" checkbox (unchecked by default), paired cleanly beside "Minimum quality".
2. With it **unchecked**, loot/accept a quest item → it appears in the History table.
3. **Check** it (or `/lh set settings.excludeQuestItems true`), loot a quest item → it does **not** appear; a non-quest item of the same quality still records.
4. `/lh get settings.excludeQuestItems` reflects the current value; `/lh reset settings.excludeQuestItems` returns it to `false`.

## Self-review notes

- **Spec coverage:** constant (T1), locale-safe classID plumbing (T1), gate on class 12 (T2), upvalue refresh via SettingsChanged (T2/T3), Schema row + default OFF + slash (T3), tests at unit + e2e + schema levels (T1–T3). Capture-time-only and no-export-change are respected (no display or Export edits). All spec sections mapped.
- **Signature consistency:** `ShouldRecord(quality, source, classID, cfg)` used identically in the gate definition (T2 Step 4), the caller (T2 Step 5), and every test call site (T2 Step 1). `GetItemInfo` 4-return shape consistent between T1 Step 5 and its T2 consumer.
- **No placeholders:** every code/command step shows concrete content and expected output.
