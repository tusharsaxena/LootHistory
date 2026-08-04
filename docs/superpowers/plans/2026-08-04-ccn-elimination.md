# CCN elimination — LootHistory

Branch `feat/fix-ccn`. Design: `LibKa0s/docs/superpowers/specs/2026-08-04-ccn-elimination-design.md`.

**9 functions** with `lizard` CCN > 15. Target: every one at CCN <= 15, behavior unchanged.

## Exit criteria

1. `luacheck . --quiet` — 0 warnings, 0 errors.
2. `lua5.1 tests/run.lua` — all pass, count >= baseline.
3. `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` — no CCN > 15.
4. No behavior change. No version bump, no CHANGELOG, no merge, no tag.

## Rules

- Preferred shapes, in order: table-driven dispatch; a named file-local helper for a
  self-contained block; a data table + loop replacing repeated defaulting; splitting a
  builder into N small builders.
- No dumping a body into one helper to game the metric. Every resulting function must be a
  unit a reader can name.
- Dispatch/defaults tables are **module-level**, built once at file load — never per call.
- `lizard` counts `and`/`or` as decisions. Prefer `== nil` over `or` wherever a stored
  `false` must survive. **Not `0`** — `0` is truthy in Lua, so `(0 or 99)` is `0` and an `or`
  chain never swallowed a stored zero; only `false` and `nil` are replaced by the default.
- Hot paths must not gain a per-call allocation.
- Sixteen functions across the collection have no coverage; where this file says
  `Coverage: NONE`, write a characterization test pinning current behavior **before**
  refactoring.

## Functions

### `Database@268-356 (real name: Database:QueryList)` — CCN 58 → target 13

`core/Database.lua:268-356` · pattern `field-defaulting` · risk **medium**

**What it does.** The single read-path filter. Takes an arbitrary record array plus an optional filter spec and returns the matching records. Fields (all optional, AND-combined): quality (number = exact, table = set), source/char/itemType/itemSubType/zone (scalar = equality, table = set membership), bound (set only, with r.bound defaulting to "NONE"), from/to on ts, and a case-insensitive substring on itemName.

**Where the branches come from.** Six copies of the same scalar-or-set shape, each written out twice — once as a hoisted `type(x) == "table"` prelude (12 locals) and again as a nested `if isSet then ... elseif ... then ok = false end` inside the record loop. Add `ok and X` short-circuits on every clause (9 of them), the quality number/table split, the `r.zone or ""` and `r.bound or "NONE"` defaults, and the from/to/text tail.

**Fix.** Keep master's hoisting and split the *clauses* into helpers that receive the hoisted values as arguments. This is a HOT path (every filter change re-runs it across the whole history, and BrowserTable renders off the result), so the rule is not merely "allocate nothing per record" — it is **re-derive nothing per record**: no `type()` test, no `filter.<field>` lookup, and no call for a clause that isn't filtered at all.
1) `local function membershipSet(want)` — normalizes one scalar-or-set clause to a membership set ONCE PER CALL: a set filter as it stands, a scalar as a one-key set, an unfiltered clause as nil. CCN 3. This is what removes the per-clause call and the per-record branch on which form the clause took; the table it builds is per query, never per record.
2) `local function matchQuality(r, qSet, qExact)` — the set/number/ignore-anything-else split, both forms hoisted. CCN 4.
3) `local function matchScalarOrSet(r, srcSet, chrSet, itypeSet, isubSet, zoneSet)` — the five clauses written out, each already a membership set, so a clause costs one local test and at most one lookup. CCN 12.
4) `local function matchRange(r, boundSet, from, to, text)` — the bound set test (`r.bound or "NONE"`), the from/to ts window, and the lowered-substring test. CCN 14. `text` is lowered ONCE by the caller and passed in, exactly as today.
5) `local function anyFiltered(a, b, c, d, e)` — is any clause in a group filtered? Hoisted per call so an unfiltered group is skipped by a local test instead of a call per record. CCN 5.
6) `QueryList` itself: hoist the invariants into locals exactly as master does, then `for _, r in ipairs(records) do if (not anyQ or matchQuality(...)) and (not anyScalar or matchScalarOrSet(...)) and (not anyRange or matchRange(...)) then out[#out+1] = r end end`. CCN 13.
Only `zone` gets the `""` default — `char` has none, matching today (`r.char ~= char`, no `or ""`). `bound` stays out of the scalar-or-set group because it is set-only (a non-table bound filter must be ignored, per the existing test).

**Rejected: a module-level descriptor table walked per record.** A `SCALAR_OR_SET = { { f = "source" }, ... }` constant with `for i = 1, #SCALAR_OR_SET do ... filter[s.f] ... type(want) ...` allocates nothing, but it re-does per record everything master hoisted: a numeric `for`, three table lookups and a `type()` per descriptor per record. Measured over 5000 records (lua5.1, 60 passes, `os.clock`, best of 3, three runs agreeing) it cost **3.0-3.5x on the no-filter query — the Browser's default open state — 2.2x on text-only and 1.7x with every filter set.** The argument-passing shape above runs at **0.67x / 0.98x / 1.04x** of master on those same three. "Allocates nothing per record" is the letter of the hot-path constraint; "re-derives nothing per record" is what it was written to mean.

**Also rejected: a per-clause `matchesField(have, want, isSet)` helper.** The first argument-passing shape kept the scalar-vs-set branch per record inside a one-line helper, which cost up to five extra calls per record on top of `matchScalarOrSet`. It held the no-filter case (0.7x) but ran **1.2x-1.5x slower than master on any query with a column filter active** and 1.6x on the worst case (six set filters that every record passes). Hoisting the scalar into a one-key set instead — `membershipSet`, above — deletes both the helper and the branch: measured on the same 5000 records (lua5.1, 150 passes, best of 3, two runs agreeing) the shipped shape is **0.67-0.74x no-filter, 0.93-1.05x on every single- and multi-filter case**, and 1.21-1.26x only on the six-full-sets pathological case, where three helper calls per record still have to run to completion. That last one is the accepted residue: it is the only scenario where the split costs anything, and it is not a scenario the Browser produces.

**Must not change.** A non-number, non-table `quality` (e.g. the stray "all" sentinel) must be IGNORED, not crash and not filter — same for a non-table `bound`. `quality = 0` is a real selection: **0 is truthy in Lua**, so an `or` chain never swallows a stored zero — only a stored `false` (and nil) is replaced by a default. The two quality forms differ on a record with no quality, and that asymmetry ships: the exact form reads it as 0 and matches, the set form looks the raw nil up and misses. A *falsy* filter field means unfiltered (master guards on `if src then`, not `if src ~= nil then`). `zone` matches `r.zone or ""` so a record with no zone lands in the empty-string bucket; `bound` matches `r.bound or "NONE"`. from/to are inclusive against `r.ts or 0`. `text` is lowered once per call, not per record — and an empty `text` is truthy, so it still runs the substring test, which matches everything. The returned array holds the SAME record references (not copies) in input order — Export and the table both rely on that.

**Coverage.** tests/test_database.lua:41-205 — arbitrary-array form, quality exact + set + stray sentinel, source/char/zone scalar and set, itemType/itemSubType scalar and set, bound NONE + union + non-table ignored, empty-zone bucket, from/to window, case-insensitive text, and a combined filter. Best-covered function in the set.

---

### `NS@13-121 (real name: NS:RunMigrations)` — CCN 56 → target 8

`core/Database.lua:13-121` · pattern `schema-migration-chain` · risk **low**

**What it does.** The schema-migration runner. Reads db.global.schemaVersion and walks seven sequential upgrade steps (v1->v2 strip viaWhitelist, v2->v3 sellPrice->vendorPrice, v3->v4 currency quality backfill, v4->v5 currency bound backfill, v5->v6 retire ACCOUNT bind state + rewrite savedView.bound, v6->v7 hand off to the deferred repair, v7->v8 translate savedView.mapID into zone names), then calls NS:ArmBoundRepair(g).

**Where the branches come from.** Seven near-identical `if g.schemaVersion < N then ... end` blocks in one body. Each block adds: the version guard, an ipairs loop over `g.history or {}` (an `or` defaulting), one or two per-row `if` tests, and an identical three-decision debug tail `if NS.State.debug and NS.Debug then NS.Debug(..., NS.MigrationSummary(N-1, N, n)) end`. The debug tail alone contributes 2 decisions x 7 = 14 CCN; the `or {}` defaults another 7.

**Fix.** Table-driven step list plus one shared log helper, both file-local in core/Database.lua.
1) `local function migrateLog(from, to, n) if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(from, to, n)) end end` — collapses seven copies of the debug tail into one (CCN 3).
2) `local MIGRATIONS = { { to = 2, apply = function(g) ... return n end }, { to = 3, apply = ... }, ... { to = 8, apply = ... } }` — an ordered module-level constant array, one entry per step, each `apply(g)` holding exactly the body that is there now and returning the row count `n` (the v6->v7 step returns 0).
3) The runner becomes:
```
function NS:RunMigrations()
  local g = NS.db and NS.db.global
  if not g then return end
  g.schemaVersion = g.schemaVersion or 1
  for i = 1, #MIGRATIONS do
    local m = MIGRATIONS[i]
    if g.schemaVersion < m.to then
      local n = m.apply(g) or 0
      g.schemaVersion = m.to
      migrateLog(m.to - 1, m.to, n)
    end
  end
  NS:ArmBoundRepair(g)
end
```
Runner CCN 5. Largest `apply` is the v5->v6 step (loop + row test + the three-part `type(view)=="table" and type(view.bound)=="table" and view.bound.ACCOUNT` guard) at CCN ~8; v7->v8 is ~7. Order is preserved by array order, so the sequential semantics (each step sees the previous step's output) are unchanged, and the `< m.to` guard keeps idempotency and the skip-forward behavior on an already-current DB.

**Must not change.** Steps must run in ascending order and each must still see the mutations of the previous step. `g.schemaVersion` must be stamped AFTER apply() and only for steps that ran, so a mid-chain error cannot advance the stamp past unapplied work. The v3->v4 and v4->v5 steps call NS.Compat.CurrencyQuality/CurrencyBound, which are in-game-only (C_CurrencyInfo) — headless they return nil and no rows are touched, so the real backfill can only be verified in game. `apply` must return a number (or nil coerced by `or 0`) because MigrationSummary formats it.

**Coverage.** tests/test_database.lua:363-530 — dedicated tests per version step (v1->v2 through v7->v8), plus absent-DB no-op, idempotency across repeated runs, and already-current-DB. Strong; safe to refactor against.

---

### `Database@188-229 (real name: Database:RepairBoundStates)` — CCN 23 → target 8

`core/Database.lua:188-229` · pattern `guard-stack` · risk **low**

**What it does.** Deferred repair pass over history rows whose stored bind state may be too loose (WARBAND/BOE). Re-reads each candidate through NS.Compat.ItemBindState, merges via BestBound, counts fixed/pending/candidates, manages a per-pass budget and a fruitless-attempt cap, clears the job when done, emits a debug line, and fires Ka0s_LootHistory_HistoryChanged when anything changed.

**Where the branches come from.** Three unrelated jobs in one body: (a) the per-row scan — candidate guard `REPAIR_CANDIDATE[r.bound] and (r.itemID or r.itemLink)`, budget branch, settled/unsettled branch, merged-changed branch; (b) the pass bookkeeping — `fixed > 0 and 0 or (g.boundRepairAttempts or 0) + 1`, the `pending == 0 or attempts >= CAP` clear; (c) the debug tail `if NS.State.debug and NS.Debug` plus the `if fixed > 0 and NS.bus` repaint. Each contributes short-circuit `and`/`or` decisions.

**Fix.** Split into three file-local helpers plus a thin method (all in core/Database.lua, above the method).
1) `local function examineRow(r)` — the settled/unsettled body only. Returns `"fixed"` or `"pending"`: unsettled -> `NS.Compat.LoadItem(r.itemID); return "pending"`; settled -> compute `merged = NS.Compat.BestBound(r.bound, state)`, and if it differs assign and return `"fixed"`, else return nil (settled and unchanged — note the original counts this as neither fixed nor pending, which must be preserved). CCN ~4.
2) `local function scanRows(g)` — the ipairs loop with the candidate guard and the per-pass budget, calling examineRow. Returns `fixed, pending, candidates`. CCN ~7.
3) `local function finishPass(g, fixed, pending, candidates)` — the attempt bookkeeping, the clear condition, and the debug line. CCN ~8.
4) The method becomes: the `not (g and g.boundRepairPending)` guard, `local fixed, pending, candidates = scanRows(g)`, `finishPass(g, fixed, pending, candidates)`, the `if fixed > 0 and NS.bus then ... end` repaint, `return fixed, pending, candidates`. CCN ~6.
Keep `REPAIR_CANDIDATE` and `BOUND_REPAIR_PER_PASS` / `BOUND_REPAIR_MAX_ATTEMPTS` where they are (already module-level constants).

**Must not change.** The three return counters are asserted by tests and printed in the debug line — a settled-but-unchanged row counts toward `candidates` only, never `fixed` or `pending`. Rows past BOUND_REPAIR_PER_PASS must count as `pending` without being examined (so the job stays armed). The attempt counter resets to 0 on any pass that fixed something. Clearing sets BOTH `boundRepairPending` and `boundRepairAttempts` to nil. The Compat.ItemBindState tooltip read and LoadItem cache warm are in-game-only; headless the mock reports unsettled, so the real merge-toward-warbound judgment is only observable in game.

**Coverage.** tests/test_database.lua:562-675 — raises rows to the witnessed state, promotes a mis-filed BOE, no-tooltip pending path, link-only row, give-up budget reset on a productive pass, and the attempt cap. Good.

---

### `B@747-766 (real name: B:CaptureView)` — CCN 23 → target 7

`modules/Browser.lua:747-766` · pattern `field-defaulting` · risk **low**

**What it does.** Snapshots the current view — the table's groupBy/sortKey/sortAsc/groupAsc, the six multi-select column-filter selection sets (copied, not aliased), the date range value, and the search text — into a plain table. Deliberately excludes the character scope.

**Where the branches come from.** Pure `and`/`or` defaulting inside one table constructor: four `BT and BT.X or default` chains (~6 decisions) and six identical `setToFilter(dd and dd.X._selected) or {}` lines (12 decisions), plus the date and search defaults. Nothing branches on real logic — every point of CCN is a nil-guard written out per field.

**Fix.** Introduce ONE ordered file-local descriptor shared with ApplyView, then split the capture into two small builders.
1) `local VIEW_FILTERS = { { "quality", "quality" }, { "itemType", "type" }, { "itemSubType", "subtype" }, { "source", "source" }, { "zone", "zone" }, { "bound", "bound" } }` — module-level constant, `{ viewKey, ddKey }`, ordered so both capture and apply keep a deterministic sequence.
2) `local function captureTableState(BT)` — returns `{ groupBy = BT and BT.groupBy or "none", sortKey = BT and BT.sortKey or "date", sortAsc = BT and BT.sortAsc == true, groupAsc = not (BT and BT.groupAsc == false) }`, verbatim. CCN ~7.
3) `local function captureFilters(dd, out)` — `for i = 1, #VIEW_FILTERS do local vk, dk = VIEW_FILTERS[i][1], VIEW_FILTERS[i][2]; out[vk] = (dd and setToFilter(dd[dk]._selected)) or {} end`. CCN 4.
4) `function B:CaptureView() local dd, BT = self._dd, NS.BrowserTable; local v = captureTableState(BT); captureFilters(dd, v); v.date = (dd and dd.date._value) or "all"; v.search = (self._search and self._search:GetText()) or ""; return v end`. CCN ~5.

**Must not change.** Unset column filters must serialize as `{}`, never nil — that is asserted by test. The character scope must remain absent from the returned table. Sets are COPIES (setToFilter), so the saved view can never alias live dropdown state. The `groupAsc = not (BT and BT.groupAsc == false)` inversion and `sortAsc = ... == true` must be reproduced literally; both default the missing-BT case to the stock direction. `dd[dk]._selected` reaches into the dropdown's private field exactly as today.

**Coverage.** tests/test_browser.lua:381-410 — records group/sort state, stores unset filters as empty sets never nil, omits the character scope. All run with `B._dd = nil`, so the dd-nil half is well pinned; the dd-present half (the six `dd.X._selected` reads) is in-game only.

---

### `menu@238-301 (real name: menu:Populate, defined inside EnsureMenu)` — CCN 20 → target 8

`modules/Browser.lua:238-301` · pattern `options-builder` · risk **low**

**What it does.** Fills the one shared dropdown popup from a dropdown's `_options`: lazily creates and recycles row buttons, computes each option's selected state (single-select value match, multi-select set membership, or a per-option `isActive` predicate), builds the label with an optional check mark and inline icon, colors it, wires the click handler (toggle for multi, set-and-close for single), and sizes the menu.

**Where the branches come from.** Four concerns interleaved in one loop body: lazy button construction (`if not b then`), the three-way selection-state decision (`opt.isActive` / `dd.multi` / else, with `(opt.value == "all") and (not next(dd._selected)) or (dd._selected[opt.value] or false)` contributing 3 on its own), the label/color styling (`(dd.multi and selected)`, `opt.icon and opt.icon ~= ""`, the selected/opt.color/default color if-chain), and the click closure with its own multi/single split.

**Fix.** Hoist four file-local helpers out of EnsureMenu (they need no upvalues beyond their arguments) and leave Populate as the loop skeleton.
1) `local function acquireRow(menu, i, rowH)` — the `if not b then ... end` construction block plus the fontstring/highlight setup; returns the button. CCN 2.
2) `local function optionSelected(dd, opt)` — the three-way selection decision, returns a boolean. CCN ~8.
3) `local function styleOption(b, dd, opt, selected)` — the check-mark/icon label assembly and the three-way SetTextColor. CCN ~8.
4) `local function optionClicked(menu, dd, opt)` — the body of the OnClick closure (multi: ToggleSelected + re-Populate + onMultiSelect; single: SetValue + Hide + onSelect). CCN ~5. Populate then wires `b:SetScript("OnClick", function() optionClicked(menu, dd, opt) end)` — same one-closure-per-option-per-populate cost as today.
5) `menu:Populate` keeps: the hide-all loop, `local opts = dd._options or {}`, the width, the `for i, opt in ipairs(opts)` loop calling the four helpers and doing the geometry, and the final SetSize. CCN ~5.
ROW_H (16) moves to a file-local constant so acquireRow and Populate agree.

**Must not change.** Selection-state precedence must stay exactly: `opt.isActive` first, then multi-select set membership (with the "all" sentinel selected only when the set is empty), then single-select value equality. Buttons are RECYCLED across dropdowns — every per-populate property (width, anchor, text, color, OnClick) must be re-set on every call, and rows beyond `#opts` must stay hidden from the leading hide loop. Entirely in-game (CreateFrame, SetBackdrop, textures); no headless test can see any of it.

**Coverage.** NONE. tests/test_browser.lua only exercises the dropdown-less path (`B._dd = nil`). A characterization test is impossible without a frame mock; verify by hand in game (open each dropdown, check the check marks, class icons, quality colors, and that single-select closes the menu).

---

### `dd@369-397 (real name: dd:UpdateMultiLabel, defined inside MakeDropdown)` — CCN 19 → target 7

`modules/Browser.lua:369-397` · pattern `guard-stack` · risk **low**

**What it does.** Computes the collapsed button text for a multi-select dropdown: an active preset option's own label wins outright; otherwise "All" when nothing is selected, the single selection's label when one is picked, else "<Prefix>: N selected" with the prefix taken from the "all" sentinel's label.

**Where the branches come from.** Four passes in one body — the isActive scan (`o.isActive and o.isActive(self)`), the raw-value label seed, the option-row label overlay (`o.value ~= "all" and labels[o.value] ~= nil`), and the count/first pass (`n = (n or 0) + 1`, `firstLabel or lbl`) — then the summary if/elseif/else with `(self._options and self._options[1] and self._options[1].label) or "All"` (3 decisions) and `allLabel:match("^(.-):") or allLabel`.

**Fix.** Three file-local helpers hoisted out of MakeDropdown; the method keeps only the flow.
1) `local function activePresetLabel(dd)` — the isActive scan, returns the label or nil. CCN 4.
2) `local function selectionLabels(dd)` — the seed pass plus the option-row overlay; returns the labels map. CCN ~5. (Same one table per call as today — this runs on selection change, not per frame.)
3) `local function summarize(labels, allLabel)` — the count/first pass and the three-way text choice including the `:` prefix extraction; returns the string. CCN ~7.
4) `function dd:UpdateMultiLabel() local preset = activePresetLabel(self); if preset then self.text:SetText(preset); return end; local allLabel = (self._options and self._options[1] and self._options[1].label) or "All"; self.text:SetText(summarize(selectionLabels(self), allLabel)) end`. CCN ~5.

**Must not change.** The isActive preset check must run FIRST and short-circuit — a selected character with no row in the current option list would otherwise fall back to "All". A selected value with no matching option row must still be labeled by its raw `tostring(k)` and still counted. The prefix is `allLabel:match("^(.-):")` with the whole allLabel as fallback. Only the SetText call touches the frame; the rest is pure and could be unit-tested if a helper is exposed on B for tests.

**Coverage.** NONE. tests/test_browser.lua never builds a dropdown. Consider exposing `selectionLabels`/`summarize` as `B._selectionLabels` / `B._summarizeSelection` (the file already exposes `B._setToFilter`) so a headless characterization test can pin the four label cases before the refactor.

---

### `groupOf@217-237 (file-local function groupOf)` — CCN 19 → target 4

`modules/BrowserTable.lua:217-237` · pattern `elseif-dispatch` · risk **low**

**What it does.** Given the active groupBy mode and a record, returns the group's collapsed-state key (namespaced as `groupBy .. "\001" .. raw`) and its display label. Six modes: source, zone, char, type, quality, day — plus a "?" fallback.

**Where the branches come from.** A six-arm if/elseif chain, each arm carrying its own `or` defaulting: `C.SourceLabel[r.source] or r.source or "Other"` (2), `(r.zone ~= nil and r.zone ~= "" and r.zone) or "Unknown"` (3), `r.char or "Unknown"`, `r.itemType or "Unknown"`, `r.quality ~= nil and ... or ...` plus `r.quality or "-"` (2), `r.ts or 0` twice.

**Fix.** Table-driven dispatch keyed by mode, sitting next to the existing GROUP_COLUMN / GROUP_PREFIX maps.
```
local GROUP_OF = {
  source  = function(r) local l = C.SourceLabel[r.source] or r.source or "Other"; return l, l end,
  zone    = function(r) local l = (r.zone ~= nil and r.zone ~= "" and r.zone) or "Unknown"; return l, l end,
  char    = function(r) local raw = r.char or "Unknown"; return raw, raw end,
  type    = function(r) local l = r.itemType or "Unknown"; return l, l end,
  quality = function(r) return "q" .. tostring(r.quality or "-"),
              r.quality ~= nil and NS.Compat.QualityLabel(r.quality) or "\226\128\148" end,
  day     = function(r) return date("%Y-%m-%d", r.ts or 0), NS.Util.FormatDate(r.ts or 0) end,
}
local function groupOf(groupBy, r)
  local fn = GROUP_OF[groupBy]
  local raw, label
  if fn then raw, label = fn(r) else raw, label = "?", "?" end
  return groupBy .. "\001" .. raw, label
end
```
groupOf drops to CCN 2; the largest handler (zone) is CCN 4. This is a HOT path — called once per record on every group build/render — and the fix is allocation-free: GROUP_OF is a module-level constant built once at load, the handlers are closures created once, and they return two values rather than a table. The only allocation per call remains the existing key concatenation. Adding a seventh group mode becomes one table entry plus one GROUP_COLUMN/GROUP_PREFIX entry, which is the point.

**Must not change.** The key must stay `groupBy .. "\001" .. raw` for EVERY mode including the fallback — collapsed[] state is namespaced by mode and a changed key silently resets every collapsed group. quality's raw is `"q" .. tostring(r.quality or "-")` while its label is the em-dash literal "\226\128\148" when quality is nil — raw and label differ only for quality and day, so the handlers must return (raw, label) in that order consistently. day's raw is ISO via the global `date`, label via NS.Util.FormatDate. Zone treats "" and nil identically as "Unknown", matching Stats and the Zone filter. Hot path: no per-call table allocation.

**Coverage.** tests/test_browsertable.lua:152-440 — group headers per mode, group ordering ascending/descending, collapsed-state round trips, a loop over every group mode, and specific zone/day/quality/source cases. Solid; the key format is exercised indirectly through the collapsed map.

---

### `B@771-809 (real name: B:ApplyView)` — CCN 17 → target 7

`modules/Browser.lua:771-809` · pattern `options-builder` · risk **low**

**What it does.** Applies a saved or stock view: pushes groupBy/sortKey/sortAsc/groupAsc onto BrowserTable, pushes the seven dropdown selections and the date value onto the widgets, sets the search box, resolves the six column filters plus date-range and text into self.activeFilter, then resets the character scope (default "current") via SetCharSet, which triggers the single refresh.

**Where the branches come from.** Three independent sub-parts inline in one body — the BT push (`if BT` plus three `or`/`==` defaults), the widget push (`if dd` plus eight calls with `asSet`/`or` defaults), and the activeFilter resolution (six setToFilter/asSet lines plus the date and search guards) — closed by the scope branch with `ck and { [ck] = true } or nil`.

**Fix.** Split into the three sub-parts it already is, reusing the VIEW_FILTERS descriptor introduced for CaptureView.
1) `local function applyTableState(view)` — the `local BT = NS.BrowserTable; if BT then ... end` block verbatim. CCN ~5.
2) `local function applyDropdowns(dd, view)` — `dd.group:SelectValue(view.groupBy or "none")`, then `for i = 1, #VIEW_FILTERS do local vk, dk = ...; dd[dk]:SetSelected(asSet(view[vk])) end`, then `dd.date:SelectValue(view.date or "all")`. CCN ~4. Use the ORDERED array (ipairs/numeric for), not pairs, so the widget-update order is deterministic and matches today's source order.
3) `local function resolveFilter(self, view)` — `for i = 1, #VIEW_FILTERS do local vk = VIEW_FILTERS[i][1]; self.activeFilter[vk] = setToFilter(asSet(view[vk])) end` plus the two `if view.date ... end` / `if view.search ... end` lines. CCN ~6. Note the activeFilter key IS the view key for all six (quality/source/itemType/itemSubType/zone/bound), so one descriptor serves both loops.
4) `B:ApplyView` keeps: `view = view or STOCK_VIEW`, `self.activeFilter = {}`, the three helper calls (dropdown one guarded by `if dd`), the search SetText guard, and the scope branch ending in SetCharSet. CCN ~7.

**Must not change.** SetCharSet must remain the LAST call and the only refresh — every filter field set above it is painted by that one ApplyFilter. `self.activeFilter = {}` must reset before anything is written, so a view that omits a field clears the previous one. The dd-present path must survive a nil `_dd` (headless and pre-UI). Scope defaults to "current" (only the literal "all" widens it) and resolves through currentKey(); a nil key means no char filter. `view or STOCK_VIEW` must keep the shared STOCK_VIEW table read-only — never mutate `view` in place.

**Coverage.** tests/test_browser.lua:294-375 — pushes group and sort onto the table, plus a run of `_dd = nil` cases covering the resolved activeFilter, date range, search text, and scope handling. Good for the headless half; the dropdown push is in-game only.

---

### `make@353-393 (file-local closure `make` inside BrowserTable:BuildTestData)` — CCN 16 → target 7

`modules/BrowserTable.lua:353-393` · pattern `field-defaulting` · risk **medium**

**What it does.** Builds one synthetic loot record for the /lh test preview dataset from four pivot values (source, quality, class, binding index), deriving everything else — zone, item type and subtype, a skewed item id, a weighted timestamp, quantity, item level, vendor and auction prices, keystone detail, confidence — from the deterministic PRNG.

**Where the branches come from.** One long constructor with derivation inline: `isGear` (`or`), the 45%-hot-item ternary (`and`/`or`), the day-cluster reroll `if`, the gear/quality quantity split, `isGear and ... or nil` for itemLevel, the 70% auction-price ternary with a nested table, the MPLUS sourceDetail ternary, the 14% confidence ternary, and an inline IIFE for itemSubType.

**Fix.** Extract the derivations into file-local helpers that take `rng` as a parameter (no upvalue capture needed), and — critically — hoist every rng-consuming value into locals IN EXACTLY THE ORDER THE CONSTRUCTOR EVALUATES THEM TODAY, since Lua evaluates constructor fields in written order and the PRNG stream must not shift.
1) `local function testItemID(rng)` — the 45% hot / long-tail split. CCN 3.
2) `local function testAge(rng)` — dayOffset (with the 1-in-3 recent reroll) + secInto, returns the seconds to subtract from `now`. CCN 3.
3) `local function testQuantity(rng, q, isGear)` — CCN 4.
4) `local function testVendorPrice(rng, q)` — CCN 1.
5) `local function testAuctionPrice(rng, q)` — the 70% ternary and its nested tsm/oribos table. CCN 3.
6) `local function testSubType(ty, idBase)` — replaces the IIFE. CCN 2. (Consumes no rng.)
7) `make` becomes: b / zone / ty / isGear / idBase / ts / qty / ilvl / vendor / auction / subtype / detail / confidence as locals in that exact sequence, then a flat, branch-free table constructor. CCN ~7 — what remains is `isGear`'s `or`, `isGear and ... or nil` for ilvl, the MPLUS `and ... or nil`, and the confidence ternary.
Not a hot path (only /lh test and the headless suite), so the extra locals cost nothing that matters.

**Must not change.** THE PRNG CALL ORDER IS THE CONTRACT. The dataset must stay byte-identical run to run (fixed seed 0x10A75AFE) and the tests assert two consecutive BuildTestData calls agree. Today the order is: zone pick, type pick, item id (rng(100) then one rng), day offset (+ optional reroll), hour/min/sec, quantity, THEN inside the constructor itemLevel's rng(40), vendorPrice's rng(1800)+rng(500), auctionPrice's rng(100) and its nested draws, then sourceDetail's keystone pick, then confidence's rng(100). Any hoist that reorders these changes every generated record. itemLevel is nil for non-gear (and must consume NO rng in that case — the `and`/`or` short-circuit is load-bearing). auctionPrice is nil ~30% of the time and only then skips its inner draws. The coverage guarantees downstream (every source/quality/class/binding present, >14-day span) depend on the seed pass, not on `make`.

**Coverage.** tests/test_browsertable.lua:50, 218, 551-610 — determinism across two calls, full source/quality/class/binding coverage, the >14-day span, field-shape assertions, and the whole preview render path. Strong, and specifically sensitive to PRNG-order regressions, which is exactly the risk here.

---
