# LootHistory — proposed changes (2026-10-07)

**Standard resolved:** Ka0s WoW Addon Standard **v2.76.1 (2026-10-07)**, fetched by curl from `master`. Every change below was checked against it. Each change carries an **adversarial "does it need to be done?" verdict** so the consolidated plan can drop what does not.

## HLD — themes

1. **Restore the release gate (F-001).** Bring the 26 functions back to CCN ≤ 15 by removing decisions, not relocating them. Guard ladders become file-scope ordered lists walked at call time. Real branching splits into helpers named for what they do (`anti-patterns` #52 forbids `part2`-style names). No dispatch or defaults table is built inside the function it serves. Each function with no direct case gets a characterization test first. *Rejected:* re-dispositioning all 26 as accepted in the watch list. That is available for a few dense-defaulting cases, but `automated-tests-§3` gates the tag on zero, and the record shows this repo already chose to fix rather than accept (GI-LH-02).
2. **Peel before the cap, not after it (F-002).** Split `modules/BrowserTable.lua` along a seam it already has, and peel `modules/Browser.lua`'s widget kit as its own disposition prescribed. *Rejected:* waiting for a breach, because `layout-§1` makes a file over 1500 lines a bug and the next feature would be the one to pay for it.
3. **Make the lifecycle and measurement edges honest (F-004, F-005).** Make the coalescer recover from a canceled window, and move the combat-exit flush out of the dirty-bit bucket.
4. **Small correctness and doc hygiene (F-006 – F-009).**

**No upstream change-set.** No finding touches `libs/` or `tests/_kit/`, and nothing below targets them.

## LLD

### C-01 — Bring the 26 functions to CCN ≤ 15 (F-001) — **Needs to be done: YES** (release blocker)

Per file, using today's sighted run figures:

| File | Function @line (CCN) | Shape → remedy |
|---|---|---|
| `core/LifecycleSetup.lua` | `NS.StandDown` @116 (18), `NS.StandUp` @143 (24) | guard ladder → one file-scope ordered name list `UP_ORDER` walked at call time (`local m = NS[name]; if m and m.Enable then m:Enable() end`). StandDown already walks a table literal; hoist it to file scope as `DOWN_ORDER`. |
| `core/Database.lua` | `convertHolderMoves` @149 (24), `compileFilter` @690 (18), `accumulateLedger` @810 (20), `Database.Stats` @1018 (23) | migration step → `convertRow(r, …)` + `pairQueued(queued, buckets)` + `touch(touched, r, holder)`. `Stats` → peel the per-row accumulate dispatch into named `accumulateRow`. `compileFilter` / `accumulateLedger` → split per clause family. **Migration v13 needs a characterization case before it is touched** (test_database already pins v13; confirm before editing). |
| `core/Ledger.lua` | `PairHolders` @129 (17), `scopeReason` @219 (16), `RecomputeFlows` @365 (19) | pure functions with suites (`test_ledger`): split `scopeReason` into `merchantReason` / `goldOutReason`, and `RecomputeFlows` into `collectWant` + `retally`. |
| `core/Compat.lua` | `ListedCurrencyID` @445 (16), `ListCurrencies` @688 (16) | client-API defaulting → extract the per-entry read into `readListEntry`. |
| `modules/Reconciler.lua` | `onEvent` @88 (21), `R.WriteRows` @484 (16) | `onEvent` → event → part file-scope map for the pure mark-and-schedule events (`PLAYER_MONEY = "money"`, …). It is a static table at file scope, not one built per call (the "dispatch table inside the function" anti-pattern does not apply). Keep the special cases as named functions. `WriteRows` → `writeMoves` / `writePairs` / `writeNets`. **Lands after C-05** (same file). |
| `modules/Escrow.lua` | `planMailMoney` @95 (17), `planExits` @136 (18), `commitExits` @208 (17) | split the guard preludes into `mailMoneyEligible(...)` and the exit loops into `bookReturns` / `bookSales`. Co-lands with C-06 if C-06 is adopted. |
| `modules/Collector.lua` | `currencyLine` @217 (16) | extract `resolveCurrencySource(directSource)` (mirrors `resolveLootSource`). |
| `modules/Holdings.lua` | `Holdings.Search` @208 (20) | extract `collectThings(store)` and `matches(d, text, filter)`. |
| `modules/AnalyticsLedger.lua` | `AL.BackToBackRows` @33 (18) | extract the per-row classification. |
| `modules/Browser.lua` | `historyCharItems` @393 (16), `holderCharItems` @420 (16) | one shared `charItem(key, meta)` builder; both callers keep their own iteration. |
| `modules/BrowserTable.lua` | `holderMoves` @557 (16), `SetTestMode` @701 (16), `GroupRecords` @808 (16) | extract the per-record group-key function from `GroupRecords`, and the sample build from `SetTestMode`. |
| `modules/TestData.lua` | `walk` @173 (17), `TD.DefaultTimelineThing` @243 (16) | test-mode sample builders: split by kind. |

- **Risk:** behavior drift in a mechanical diff. The mitigation is one commit per file, the suite green after each, and no behavior change mixed into a refactor commit.
- **Test count:** characterization cases added for any function without a direct case will move `docs/test-cases.md` and the README badge **in the same commit** (`testing` rule on the inventory moving with the count).
- **Watch list:** `RESULTS.md` should show 0 warnings and max ≤ 15 at the next release regeneration. That is for the release to confirm, not a task now.

### C-02 — Peel the two browser files (F-002) — **Needs to be done: YES for `BrowserTable.lua`; YES for `Browser.lua`** (the trigger its own disposition set has fired)

- `modules/Browser.lua` → move the dropdown / filter widget kit the disposition names into a new `modules/BrowserWidgets.lua`, loaded in the TOC directly after `modules/Browser.lua` (both are `NS.Browser` members that are resolved at call time; check with `grep` that nothing reads them at file load).
- `modules/BrowserTable.lua` → peel the grouping and holder-move layer (`holderMoves`, `GroupRecords` and their helpers) into `modules/BrowserTableGroup.lua`, loaded after `BrowserTable.lua`.
- **Tests:** `tests/run.lua` derives the load list from the TOC (`testing-§9`), so no runner edit is needed. `test_harness` pins the derivation.
- **Docs that move in the same commit:** the `docs/module-map.md` tree and numbered list, and the `docs/ARCHITECTURE.md` module map if it names the files.
- **Standards:** `layout-§1` (peel before the cap). The new files sit in `modules/`, one of the five sanctioned source folders.
- **Order:** after C-01, which edits functions in both files.

### C-03 — Record the Phase 2 ledger smokes (F-003) — **Needs to be done: YES, before release; owner action, not an agent edit**

- The owner runs LED-P2-01 … LED-P2-24 in the client and fills in each `Result:`. Any bracketed fact that fails becomes a Compat or mock correction plus a re-run, as the doc prescribes.
- After LED-P2-06 passes, change the comment at `modules/AttributionOut.lua:64-65` from "to be verified by smoke LED-P2-06" to "verified by smoke LED-P2-06 (owner, <date>)".

### C-04 — Make the coalescer survive a canceled window (F-004) — **Needs to be done: YES** (small, contained, and the bug is observed)

`core/Util.lua`, `Util.Coalesce`. Track the handle instead of a boolean, and treat a canceled handle as not pending:

```lua
function Util.Coalesce(fn, delay)
  local pending            -- the NS.After handle of the armed window, or nil
  return function()
    if pending and not pending.canceled then return end
    if not (C_Timer and C_Timer.After) then return fn() end
    pending = NS.After(delay, function()
      pending = nil          -- cleared BEFORE the body (the existing comment's reason still holds)
      fn()
    end)
  end
end
```

- This relies on `NS.After`'s handle `h.canceled` (`core/LifecycleSetup.lua:82`), which is the addon's own code.
- **Test:** add `Coalesce: a window canceled by the stand-down does not wedge the trigger` to `tests/test_util.lua` (trigger → `NS.CancelDeferrals()` → trigger → drain → `ran == 1`). This is +1 case, so update `docs/test-cases.md` and the README badge in the same commit.
- **Rejected:** rebuilding the Panel's bus target on every Enable. That fixes one consumer and leaves the trap in the primitive.

### C-05 — Take the combat-exit flush out of the `ledgerEvent` bracket (F-005) — **Needs to be done: YES, cheap** (the comment and the bucket declaration are currently false)

`modules/Reconciler.lua`. Route `PLAYER_REGEN_ENABLED` before the bracket:

```lua
local function onRegenEnabled(self)
  if self.loginPending then self:LoginScan()
  elseif self.deferred then self.deferred = nil; self:Flush() end
end

function R:OnEvent(event, a1, _, a3, a4, a5)
  if event == "PLAYER_REGEN_ENABLED" then return onRegenEnabled(self) end   -- out-of-combat work, unbracketed
  local t0 = Perf.on and debugprofilestop()
  onEvent(self, event, a1, a3, a4, a5)
  if t0 then Perf.Note("ledgerEvent", debugprofilestop() - t0) end
end
```

This also removes one branch from `onEvent` (it helps C-01). The dormant cost of the regen event becomes one string compare, which is out of combat by definition.

- **Test:** a `tests/test_perf.lua` case: with capture on, fire `PLAYER_REGEN_ENABLED` while `deferred` is set and assert `ledgerEvent` gets no sample, while a `BAG_UPDATE` does. This is +1 case, with the inventory and badge updated in the same commit.
- **Standards:** `performance-§2` (Shape A, the bracket covers the hot handler only).

### C-06 — Escrow exit bookkeeping (F-006) — **Needs to be done: NO code change. Document it as a known limitation.**

The adversarial read: net counts stay correct, only the reason labels drift, and only in a multi-auction, partial-expiry edge case. A correct fix needs per-exit timestamps and a sale quantity the sale mail does not reliably carry, which is a schema change to `escrow.exits` that needs a migration step. That cost is out of proportion to a labeling error. Add one entry to `docs/data-flow.md`'s known limitations naming both effects.

### C-07 — Prune the coalescing map (F-007) — **Needs to be done: NO.** Accept it.

The growth is bounded by distinct keys per session and is a few kilobytes at most. A prune walk adds code to the flush path for no measurable gain. Record it as accepted in the consolidated list and do nothing else.

### C-08 — One location parser (F-008) — **Needs to be done: OPTIONAL. Recommended because it is zero-risk.**

`modules/TimelineModel.lua:156`: replace the local `sideOf` with `NS.Ledger.LocationHolder`. Behavior is identical for every holder key in use. Existing `test_timeline` intraday cases cover `RowDelta`.

### C-09 — Correct the suite count (F-009) — **Needs to be done: YES** (a doc that states a number must state the right one)

`docs/testing.md:65-66`: change "Forty-four … thirty-nine … five" to "Sixty … fifty-five … five". Better still, word it without a hard count and point at the Totals table in `test-cases.md`, since `test_doc_structure` does not pin this number.

## Standards conformance (per change)

| Change | Introduces a deviation? | Rule that shaped it |
|---|---|---|
| C-01 | No | `automated-tests-§3` (release gate), `anti-patterns` #52 (helper naming), `performance-§10` (CCN in Lua is often defaulting) |
| C-02 | No | `layout-§1` (cap and band), `testing-§9` (TOC-derived load list, so the runner needs no edit) |
| C-03 | No | the smoke doc's own gate. Smoke results are owner-recorded only. |
| C-04 | No | `slash-commands-§7` (timers canceled at stand-down. The fix keeps the cancel and makes it recoverable.) |
| C-05 | No | `performance-§2` (Shape A bracket), `performance-§9` |
| C-06 / C-07 | No (no code) | — |
| C-08 / C-09 | No | — |
