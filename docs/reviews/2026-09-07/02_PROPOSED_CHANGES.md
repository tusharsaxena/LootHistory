# 02 — Proposed changes (HLD + LLD)

**Standard resolved:** Ka0s WoW Addon Standard **v2.38.0, 2026-09-02** (`STANDARDS.md` header), index followed to all 27 section files. The standards cross-check below was **performed**, not skipped.

**Scope rule honoured throughout:** no change in this document targets a path under `libs/` or `tests/_kit/`. There are no upstream findings in this review, so the upstream change-set section below is empty by fact rather than by omission.

---

## HLD — themes

### Theme A — make the storage estimate correct, and make its test able to prove it

**Covers:** F-001, F-002, F-004.

The database-size estimate is wrong for a class of rows the default configuration produces (currency), and the case over it asserts a predicate that cannot distinguish right from wrong. Both halves are one small change to one function plus a real assertion; leaving either half undone leaves the other unprotected. Removing the per-record table literal falls out of the same edit, so the perf finding rides along rather than being a second pass over the same lines.

**Alternatives considered.**

- *Fix only the `ipairs` walk, leave the table literal.* Rejected: the allocation is the reason the array exists at all; once the walk is index-based the array has no remaining purpose, and keeping it would be a deliberate per-record allocation with nothing to show for it.
- *Replace the estimate with a real serialized size.* Rejected: there is no in-game way to read the SavedVariables file size, which is exactly what `core/Database.lua:745-746` already says. Serializing the history to measure it would cost more than the label is worth.
- *Delete the estimate.* Rejected: it is surfaced in two places the user reads and is the only signal they have about a growing store.

**Trade-off:** the corrected number will be **larger** than what users see today, and noticeably so for currency-heavy histories. That is a visible behaviour change on a label; it is called out in `05_FINAL_SUMMARY.md` under API/behaviour changes rather than shipped silently.

---

### Theme B — finish the coalescing pass that issue #27 started

**Covers:** F-003.

`NS.Coalesce` exists, is correct, and is wired to two of the three `RecordAdded` consumers. The third was missed. This is not a new mechanism, a new constant or a new decision — it is applying the decision already made and already commented, to the one call site that did not get it.

**Alternatives considered.**

- *Coalesce inside `Database:Add` instead, so every consumer benefits.* Rejected, and worth recording why: `RecordAdded` carries `(record, index)` and is a genuine per-record notification. Collapsing it at the source would either drop those arguments for everyone or lie about which record fired. The standard's own shape here is the consumer deciding — `HistoryChanged` is immediate because a delete is one deliberate act, `RecordAdded` is coalesced because it bursts, and that judgement belongs at each consumer.
- *Gate `refreshStats` more tightly instead of coalescing.* Rejected: it is already gated on `panel:IsShown()`. The remaining cost is exactly the burst the coalescer removes.

---

### Theme C — bring the performance record back into agreement with the tree

**Covers:** F-005, F-006, F-007.

`docs/performance.md` is the sole evidence for a ratified `performance-§12` exemption. Three of its statements no longer hold: the event count, the `C_Timer` count, and the sentence describing what `CHAT_MSG_LOOT` actually costs. Two of the three are pure regeneration; the third requires a judgement — whether criterion (a) still holds now that the per-fire work is stated honestly.

**This theme deliberately does not propose ending the exemption.** `performance.md:82-87` states the trigger in its own words (*"the first `OnUpdate` handler, repeating ticker, or in-combat event handler doing real work"*), and whether `CHAT_MSG_LOOT` meets it is a decision for the maintainer with the register in front of them, not something a review should smuggle into a documentation fix. What this theme delivers is the accurate description; the decision it enables is recorded as an explicit checkpoint in `04_EXECUTION_PLAN.md`.

**Alternatives considered.**

- *Add `tests/perf.lua` and start bracketing.* Rejected **for this pass**: it would reverse a ratified deviation register entry (`LH-20`…`LH-26`) as a side effect of a doc fix, and `performance.md:20-25`'s criterion (c) argument — that `suspend` would suppress the loot the addon exists to record — is unaddressed by anything in this review. If the maintainer decides at the checkpoint that (a) no longer holds, that is its own milestone with its own design, not an appendix to this one.

---

### Theme D — close the two wiring paths nothing exercises

**Covers:** F-008, F-009, F-018.

Three lists/paths in this repo are load-bearing and unpinned: `Attribution:Enable`'s registration set, `tests/run.lua`'s hand-copied lifecycle kick, and `NS.version` against the TOC. All three fail silently. `tests/test_harness.lua` already exists as the home for exactly this class of guard rail and already pins three sibling lists well; these are three more rows in a pattern the repo has established rather than a new idea.

**Alternatives considered.**

- *Unit-test the individual handlers instead.* Rejected: they already are. The gap is the **wiring**, which is what `testing-§8` says the addon's own suite should own (integration over its wiring, not duplicated library coverage).
- *Derive `NS.version` from the TOC at load and delete the constant.* Rejected: `core/EnvSetup.lua:62-66` states why the fallback constant is deliberately visible in this file — a headless run and a client with no metadata reader both need it. Pin the two, do not collapse them.

---

### Theme E — the small true things

**Covers:** F-012, F-013, F-014, F-016, F-017.

Comment corrections, one rename, one NBSP-class widening, one degraded-help set correction. Grouped because each is a few lines, none interacts with another, and splitting them across milestones costs more coordination than the work itself.

---

### Theme F — the working tree's line endings

**Covers:** F-015.

Mechanical. Called out separately because it touches nine files with no semantic change, and interleaving it with any other theme makes both diffs unreadable.

---

## Upstream change-set

**Empty.** No `[upstream]` finding was raised. `libs/LibKa0s/` and `tests/_kit/` were verified byte-identical to `v1.25.0` and no defect was found in either.

---

## LLD — change-set

### C-01 — `estimateRecordBytes`: index the fields, drop the array

**Finding IDs:** F-001, F-004
**File:** `core/Database.lua:748-756`

Before:

```lua
local function estimateRecordBytes(r)
  local n = RECORD_OVERHEAD
  local strFields = { r.itemLink, r.itemName,
                      r.zone, r.subzone, r.char, r.itemType, r.itemSubType }
  for _, s in ipairs(strFields) do
    if type(s) == "string" then n = n + #s end
  end
  return n
end
```

After (sketch — no intermediate table, no `ipairs` hole):

```lua
-- Summed inline rather than through an array literal walked with `ipairs`: a nil field made that
-- walk STOP, so a currency row (no itemLink) counted zero string bytes and an uncached item's row
-- lost every field after the first nil. Seven adds is also seven fewer table allocations per
-- record, and StorageStats walks the whole history.
local function addLen(n, s) return type(s) == "string" and n + #s or n end
local function estimateRecordBytes(r)
  local n = RECORD_OVERHEAD
  n = addLen(n, r.itemLink);    n = addLen(n, r.itemName)
  n = addLen(n, r.zone);        n = addLen(n, r.subzone)
  n = addLen(n, r.char);        n = addLen(n, r.itemType)
  n = addLen(n, r.itemSubType)
  return n
end
```

**Risk:** the reported byte total rises. Nothing branches on it (`grep -rn "StorageStats" core modules settings` → three call sites, all display). `tests/test_database.lua:379`'s `> 0` assertion still passes, which is precisely why C-02 must land in the same change.

**Standards conformance:** compliant. No rule constrains the shape; the chosen form avoids the per-call table the complexity guidance in `performance-§10` warns about. The two-line `addLen` helper is named for what it does — not a `part2`/`doTheRest` extraction (`anti-patterns` #52).

---

### C-02 — a `StorageStats` case that can go red

**Finding ID:** F-002
**File:** `tests/test_database.lua:371-380`

Replace the `assertTrue(s.bytes > 0)` predicate with an exact expected total over a fully-populated fixture, and add a second case for a currency-shaped row:

```lua
-- red under: revert C-01's inline sum to the `ipairs(strFields)` walk — this case then reports
-- 256 for the currency row instead of 256 + #itemName + #zone + #char + #itemType.
test("Database: StorageStats counts a currency row's string fields (no itemLink)", function()
  NS.db.global.history = {
    { ts = 1000, char = "A-Realm", currencyID = 1602, itemName = "Conquest",
      zone = "Valdrakken", subzone = "", itemType = "Currency", itemSubType = "PvP" },
  }
  local s = NS.Database:StorageStats(1000)
  assertEqual(s.bytes, 256 + #"Conquest" + #"Valdrakken" + #"" + #"A-Realm"
                           + #"Currency" + #"PvP")
end)
```

**Regression pressure:** this **adds one case**. The pass count moves **699 → 700**, so `docs/test-cases.md` and the README `[Tests]` badge (`README.md:7`) MUST move in the **same** change (`testing-§7`). Regenerate the inventory with `lua tests/run.lua --list > docs/test-cases.md` — never hand-edit it.

**Standards conformance:** compliant, and it *closes* a `testing-§12` deviation (an assertion with no evidence it can go red). The `-- red under:` comment is required by that section and is included.

---

### C-03 — coalesce the panel's `RecordAdded` listener

**Finding ID:** F-003
**File:** `settings/Panel.lua:154-164`

Before:

```lua
ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", onChange)
ev:RegisterMessage("Ka0s_LootHistory_RecordAdded", onChange)
```

After:

```lua
ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", onChange)
-- COALESCED for the reason modules/Browser.lua:1273 and modules/Analytics.lua:655 are (issue #27):
-- onChange runs Database:StorageStats, a full-history pass, and RecordAdded fires once per LOOTED
-- ITEM. HistoryChanged stays immediate — a delete or a prune is one deliberate action.
ev:RegisterMessage("Ka0s_LootHistory_RecordAdded",
  NS.Coalesce(onChange, NS.Constants.RECORD_ADDED_COALESCE))
```

**Risk:** the storage line lags the loot by up to `RECORD_ADDED_COALESCE` (0.2 s, `core/Constants.lua:172`). That is the same lag the History window footer and the Insights tab already accept.

**Perf claim and its record:** *no committed capture and no offline scenario exists to demonstrate this* — the addon carries the `performance-§12` exemption. The claim is structural: three consumers of one bursty message, two already collapsed. The in-client check is in `03_SMOKE_TESTS.md` as a `collectgarbage("count")` delta across a scripted multi-drop loot with the panel open, which is the strongest evidence available without the harness.

**Standards conformance:** compliant; it applies an existing mechanism to a third call site and introduces nothing new.

---

### C-04 — regenerate `docs/performance.md`'s two sweeps and correct the `CHAT_MSG_LOOT` row

**Finding IDs:** F-005, F-006, F-007
**File:** `docs/performance.md:40-61`

Three edits:

1. **`:40` and the table at `:42-52`** — re-run the page's own `grep`, count **13**, add rows for `modules/Browser.lua:1277` (`PLAYER_REGEN_DISABLED`) and `:1278` (`PLAYER_REGEN_ENABLED`), each described as *"one `frame:IsShown()` test plus one settings read; hides a window the visibility dropdown no longer allows"*. Correct `PLAYER_ENTERING_WORLD`'s cite from `core/LootHistory.lua:37` to `:40`.
2. **`:45`** — rewrite the `CHAT_MSG_LOOT` cell to name what actually runs on a keeper: the `C_TooltipInfo.GetHyperlink` tooltip build inside `Compat.ScanBound`, the AH cascade across up to three third-party addons, the zone/map reads, and the `RecordAdded` fan-out.
3. **`:54-61`** — count **five** `C_Timer.After` sites, correct `core/Compat.lua:202` → `core/ItemSetup.lua:71`, correct `core/LootHistory.lua:54` → `:56`, and add the missing `core/Util.lua:242` row (`NS.Coalesce`'s one-shot window) with a pointer to the `:75-79` paragraph that already credits it.

**Risk:** none — documentation only. **Do not** touch `docs/ARCHITECTURE.md`'s deviation register in this change; whether criterion (a) survives edit 2 is the C-05 checkpoint.

**Standards conformance:** compliant, and it restores a `performance-§12` obligation — the exemption is only as good as the sweep evidencing it. The rejected alternative (adding `tests/perf.lua` here) would have reversed a ratified register entry as a side effect of a doc fix.

---

### C-05 — *(decision, not code)* re-affirm or retire the `performance-§12` exemption

**Finding ID:** F-006 (consequence)
**File:** `docs/ARCHITECTURE.md → ## Documented deviations`, plus `docs/performance.md:12-25`

With C-04's honest description of the `CHAT_MSG_LOOT` path in hand, the maintainer decides whether criterion **(a)** — *"no event handler doing more than occasional work while the player is in combat"* — still holds. Two outcomes, both legitimate:

- **Holds.** Record *why* in the criterion (a) paragraph: the work is bounded by loot-line frequency rather than frame rate, and criterion (c) is independently load-bearing. No code changes.
- **Does not hold.** That re-arms the full `performance-§1` wiring MUST and becomes its own milestone — `core/PerfSetup.lua`, a descriptor with buckets, `tests/perf.lua`, the `/lh perf` verb, `docs/perf-analysis/`. It is **out of scope for this review's change-set** and is listed in `05_FINAL_SUMMARY.md` under known follow-ups.

**Standards conformance:** this is the compliant way to handle it. `performance-§12` requires the exemption to be ratified and conditional, and its end-condition re-checked when the tree changes — which is what this checkpoint is.

---

### C-06 — an integration case over `Attribution:Enable`

**Finding ID:** F-008
**File:** `tests/test_attribution.lua` (new case)

Call `Attribution:Enable()` against the mock and assert the wiring, not the handlers:

- the seven `RegisterEvent` names, exactly (no more, no fewer);
- that `UNIT_SPELLCAST_SUCCEEDED` arrived via `RegisterUnitEvent` on a **separate frame** filtered to `"player"`, not via a bare `RegisterEvent` on the bus;
- that `BuyMerchantItem`, `TakeInboxItem`, `AutoLootMailItem` were each hooked once through `hooksecurefunc`;
- that a second `Enable()` registers nothing further (the `self._enabled` latch).

**Regression pressure:** **+1 case**, 700 → 701 with C-02. Same inventory + badge obligation.

**Standards conformance:** compliant and squarely what `testing-§8` asks the addon's own suite to own — integration over this addon's wiring, not a re-test of anything `libs/` provides.

---

### C-07 — pin the runner's lifecycle kick

**Finding ID:** F-009
**File:** `tests/test_harness.lua` (new case), `tests/run.lua:41-46` (comment + `Kit.expose`)

Publish the kick's step list through `Kit.expose` the way `addonFiles` and `suites` already are, and add a harness case asserting it against the members `addon:OnInitialize` calls. Simplest honest form: have `tests/run.lua` record the names it invoked, and have the case assert that set equals `{ InitDB, Schema:Register, Slash:Register, Panel:Register }` — failing loudly on the currently-missing `Slash:Register` so the drift is closed rather than blessed.

**Risk:** if `Slash:Register` cannot run headlessly, the case must assert the **deliberate** omission with a comment naming why, not silently accept a shorter list. Do not weaken the case to make it pass.

**Regression pressure:** **+1 case**. Same inventory + badge obligation.

**Standards conformance:** compliant; it extends `testing-§9`'s "no hand-maintained list" principle to the fourth list in this repo, in the file the other three already live in.

---

### C-08 — pin `NS.version` against the TOC

**Finding ID:** F-018
**File:** `tests/test_envsetup.lua` (new case)

Read `## Version:` out of `LootHistory.toc` and assert it equals `NS.version`. The loader already opens the TOC, so no new I/O shape is introduced.

**Regression pressure:** **+1 case**. Same inventory + badge obligation.

**Standards conformance:** compliant. Rejected alternative: deleting the constant and deriving from the TOC at load — `core/EnvSetup.lua:62-66` documents why the fallback must stay visible, and removing it would break the headless and no-metadata paths.

---

### C-09 — widen the two NBSP-blind trims

**Finding ID:** F-012
**Files:** `core/Compat.lua:229`, `modules/Attribution.lua:66-67`

```lua
-- core/Compat.lua:229 — `%s` does NOT match U+00A0 (\194\160), which localized tooltip lines carry
-- on deDE/frFR. A surviving NBSP made both the WARBAND_LINES lookup and the prefix compare miss.
local lower = text:lower():gsub("^[ \194\160%s]+", ""):gsub("[ \194\160%s]+$", "")
```

Same substitution in `seedToken`'s two trims and its `dropLast` pattern.

**Risk:** low; the character class only widens. Add a case feeding an NBSP-wrapped warbound line and asserting it still resolves to `WARBAND` (**+1 case**).

**Standards conformance:** compliant with `localization`'s NBSP rule. Explicitly **not** proposed: translating `WARBAND_LINES`' English keys — they are correctly the fallback beneath the `_G` wording globals, and hardcoding more locale literals would be the deviation.

---

### C-10 — the comment and naming corrections

**Finding IDs:** F-013, F-014, F-016, F-017
**Files:** `modules/Browser.lua:1162`; `defaults/Global.lua:6-9`; `core/Database.lua:193`; `settings/Slash.lua:174-178`; `modules/Attribution.lua:110,127`

1. `modules/Browser.lua:1162` — correct the comment to name `frame:HookScript("OnHide", …)` at `:1073-1076` as the guard.
2. `defaults/Global.lua:6-9` — the chain runs to **v8**, not v2. Add one sentence stating that the shipped `schemaVersion = 1` is the deliberate floor so a fresh DB walks the guarded chain.
3. `core/Database.lua:193` — `v6->v9` → `v6->v7 plus the revision-armed repair`.
4. `settings/Slash.lua:174-178` — rename `LIBRARY_OWNED` to something naming what it means on this path (e.g. `UNAVAILABLE_DEGRADED`) and add `config`, whose target is the `Options` stub's declining `OpenOptionsPanel`. Keep the subtraction design.
5. `modules/Attribution.lua` — rename `Consume` → `PeekContext` across its bounded call set, **or** keep the name and add one line at `:127` stating that expiry, not consumption, ends the context. Prefer the rename.

**Risk:** item 5 touches call sites in `modules/Collector.lua` and the suite. Mechanical; `luacheck` and the suite catch a miss.

**Standards conformance:** compliant throughout. Item 4 keeps `slash-commands-§1`'s single-`COMMANDS`-table dispatch and its subtraction-based degraded help; a second hand-typed verb list was rejected for exactly the reason `settings/Slash.lua:176-177` already gives.

---

### C-11 — renormalize the working tree's line endings

**Finding ID:** F-015
**Files:** the nine listed in F-015

```sh
git add --renormalize .
git status                       # review
# then, per straggler:
rm <path> && git checkout -- <path>
# verify (line-endings-§7): these two counts must be equal
tr -dc '\r' < <path> | wc -c
tr -dc '\n' < <path> | wc -c
```

**Risk:** touches nine files with zero semantic change. **Must be its own commit** or every other diff in this pass becomes unreadable. Re-run `lua tests/run.lua` and `luacheck .` afterwards; `tests/test_vendor_sync.lua` normalizes CR on the working-tree side, so the vendored payload comparison is unaffected.

**Standards conformance:** compliant with `line-endings-§2`; `.gitattributes` is already correct and is **not** edited.

---

## Standards conformance summary

| Change | Rule that shaped it | Rejected option, and the rule it broke |
|---|---|---|
| C-01 | `performance-§10` (per-call allocation), `anti-patterns` #52 (named helper, not `part2`) | — |
| C-02 | `testing-§12` (a case must be able to go red), `testing-§7` (inventory + badge move together) | Loosening the assertion to keep the count flat — `testing-§12` |
| C-03 | — (applies an existing in-repo mechanism) | Coalescing inside `Database:Add` — would drop `RecordAdded`'s `(record, index)` contract |
| C-04 | `performance-§12` (the sweep is the exemption's evidence) | Adding `tests/perf.lua` as a side effect — would reverse a ratified register entry without a design |
| C-05 | `performance-§12` (conditional, re-checked exemption) | Silently keeping the exemption after C-04 changed its evidence |
| C-06 | `testing-§8` (integration over the addon's own wiring) | Duplicating library coverage locally — `testing-§8` |
| C-07 | `testing-§9` (no hand-maintained load list) | Blessing the shorter kick to keep the case green — `testing-§12` |
| C-08 | `slash-commands-§3` (TOC preferred, constant as fallback) | Deleting `NS.version` — breaks the headless and no-metadata paths `core/EnvSetup.lua:62-66` documents |
| C-09 | `localization` (NBSP is not `%s`) | Hardcoding more locale literals into `WARBAND_LINES` — `localization-§4` / `anti-patterns` #37 |
| C-10 | `slash-commands-§1` (one `COMMANDS` table, subtraction-based degraded help) | A second hand-typed verb list for the degraded path |
| C-11 | `line-endings-§2`, `line-endings-§7` (byte count, not `file`) | Editing `.gitattributes` — it is already correct |

**No change in this document introduces a new deviation from the standard, and none targets `libs/` or `tests/_kit/`.**

## Test-count movement

C-02, C-06, C-07, C-08 and C-09 each add one case: **699 → 704**. `docs/test-cases.md` and the README `[Tests]` badge must move in the same change as the case that moved them (`testing-§7`) — regenerated with `lua tests/run.lua --list > docs/test-cases.md`, never hand-edited.

## Complexity movement to confirm at the next release

C-01 removes a table construction and one loop from `estimateRecordBytes` (already well under threshold — no watch-list movement expected). Nothing proposed here touches any of the seven CCN-15 functions or moves a file across a `layout-§1` band. `settings/Panel.lua` sits at **1004 LOC** and C-03 adds ~4 lines, keeping it in the 1000–1500 on-notice band — the next release's `automated-tests` regeneration should carry a disposition for it (F-011). Do **not** run `lizard` into the repo as part of this work.
