# 05 — Final summary

> **Status: written ahead of implementation.** This document is the "what shipped" record for the
> 2026-08-05 review cycle, written on the assumption that `04_EXECUTION_PLAN.md` was executed in full
> and every check in `03_SMOKE_TESTS.md` passed. Numbers marked **(confirm)** must be replaced with
> what was actually observed before this is pasted into a PR or a changelog.

---

## Headline

This cycle fixed one way the addon could quietly under-report an item's worth, and closed four
places where the code, its comments, its labels or its tests said something slightly different from
what they did. The visible fix: if you turn on an auction-price source from chat rather than from
the settings panel, that price is now actually used to value your loot — before this change it was
collected, stored and then ignored by everything that computes a value. Everything else is
hardening: a login-time sanity check that could never fire now can, a "Reset All" button that
actually wipes your entire loot history now says so, an install that is missing the shared library
now tells you which commands still work, and three test cases were sharpened so they cannot pass
without proving something.

---

## Counts

**Critical fixed: 0 · High fixed: 1 · Medium fixed: 5 · Low fixed: 3**

Deferred, with reasons:

- **F-009** (`modules/Analytics.lua:176-197` computes per-character stack segments twice) — deferred.
  It is a render-on-demand path, not a hot one, and the addon ships no perf harness, so there is no
  way to state the improvement as a number. Fixing it on a guess is exactly the "interpretation
  without its record" the standard warns about. Revisit if and when `tests/perf.lua` arrives.

---

## Changes by theme

### Theme A — One declaration per default

**What changed.** The auction price *capture set* and *priority cascade* are now declared once, in
`core/Constants.lua`, and `defaults/Global.lua` copies them instead of restating them. The two
statements had already drifted: the defaults file listed seven priority entries where the constant
listed eleven. Separately, the login-time schema check that is supposed to catch a setting with no
shipped default was rewritten so it can actually fire — its condition required a row to be missing
from defaults *and* to have declared no default of its own, which no row ever does.

**Why it mattered.** A user who enabled `tsm:dbhistorical`, `tsm:dbrecent`,
`tsm:dbregionhistorical` or `tsm:dbregionsaleavg` with `/lh set` — without opening the AH Price
settings page, which was the only thing that repaired the stored priority list — had that price
gathered and written into every record, and then skipped by `AuctionPrice:Pick`. The Value column,
the Insights value charts and the CSV `value` / `auctionPrice` / `auctionSource` columns all behaved
as though the price did not exist. No error, no warning, and it healed itself the moment the user
opened that page, which made it near-impossible to reproduce deliberately.

**Findings covered:** F-001, F-002. **Changes implemented:** C-01, C-02.

**Files touched:**
- `defaults/Global.lua`
- `settings/Schema.lua`
- `tests/test_schema.lua`

### Theme B — The degraded install is a first-class install

**What changed.** Three corrections to the "something is missing" paths. The message-bus receivers in
the collector and the browser no longer fall back to the shared bus object when AceEvent cannot be
resolved — they register nothing instead. Every degradation stub is now checked by a test against the
members the addon actually calls, which added `HelpHeader` to the slash stub and removed a
`ConsoleCheckbox` member from the debug-log stub that nothing calls any more. And a bare `/lh` on an
install with no `libs/LibKa0s` now lists the commands that still work instead of only saying the
library is gone.

**Why it mattered.** The shared-bus fallback re-created, in two files, the exact
last-registrant-wins clobber the collection's standard forbids: with AceEvent absent, the browser's
settings handler would have silently replaced the collector's, and the collector would then never
re-read the quality threshold, the source mutes or the master switch after a settings change. The
stub asymmetry meant three of four library seams had their fallback surface maintained purely by
hand — a member omitted there is not a fallback, it is a crash moved to a rarer path.

**Findings covered:** F-003, F-006, F-010. **Changes implemented:** C-03, C-06, C-08.

**Files touched:**
- `modules/Collector.lua`
- `modules/Browser.lua`
- `settings/Slash.lua`
- `core/DebugLogSetup.lua`
- `tests/test_libka0s.lua`
- `tests/test_slash.lua`

### Theme C — Say what a green case actually proved

**What changed.** The two vendored-copy fidelity cases now name their precondition in their titles
and report the skip when the sibling `LibKa0s` checkout is not on disk.

**Why it mattered.** Both cases returned without asserting anything when that checkout was absent —
on a CI runner or a fresh clone they printed `PASS` and proved nothing, while guarding the one
failure mode (a drifted vendored library) that leaves both repositories green. The file's own header
claimed the skip was disclosed in the case names; it was not.

**Findings covered:** F-005. **Changes implemented:** C-05.

**Files touched:**
- `tests/test_vendor_sync.lua`
- `docs/test-cases.md`

### Theme D — Truthful labels, comments and suppressions

**What changed.** The settings panel's `Reset All` button is now `Reset Everything…`; two comments in
`settings/Slash.lua` no longer claim `settings/Panel.lua` reads formatters it does not read; and a
`luacheck` suppression for an `addonName` that is genuinely used was removed.

**Why it mattered.** `resetall` is a verb whose meaning is fixed across every Ka0s addon — reset the
settings. The panel button wearing that name deleted the user's entire recorded history as well, so
the two surfaces taught contradictory expectations and the only disclosure was the confirm dialog.
The comments sent a reader to a file that would not explain anything, and a suppression for a
warning that cannot occur is how a future real warning gets hidden.

**Findings covered:** F-004, F-007, F-008. **Changes implemented:** C-04, C-07.

**Files touched:**
- `settings/Panel.lua`
- `settings/Slash.lua`
- `modules/AuctionPrice.lua`

---

## API / behavior changes

- **Slash commands:** none added, removed or renamed. `/lh resetall` keeps its reserved meaning
  (settings only, history untouched).
- **Settings UI:** the General page's paired action button is relabeled `Reset All` →
  `Reset Everything…`. Its behavior is unchanged (confirm dialog, then settings + filter lists +
  saved view + window geometry + **all history**).
- **Chat output:** on an install missing `libs/LibKa0s`, a bare `/lh` now prints the command list
  after the standing cause clause. The cause clause itself is unchanged, verbatim.
- **Login output:** a settings path with no entry in `defaults/Global.lua` now prints one tagged
  line. On a correct build this never appears.
- **Deprecated APIs:** none replaced this cycle. No `Old → New` table — the addon already routes
  every varying or removed API through `core/Compat.lua`, verified during the review.
- **Locale keys:** none added or renamed. The addon ships English only.

## SavedVariable / migration notes

**No `schemaVersion` bump.** The stored shape is unchanged; the current chain still ends at **v8**
(`core/Database.lua`, `MIGRATIONS`).

One seeding change, which needs no migration:

| | Before | After |
|---|---|---|
| `db.global.settings.auction.priority` on a **fresh** install | 7 tags (from `defaults/Global.lua`) | 11 tags (from `NS.Constants.AUCTION_PRIORITY_DEFAULT`) |
| Existing profiles | untouched by AceDB (key already present) | untouched |

Existing users auto-migrate in the sense that nothing needs to happen: `AuctionPrice:ReconcilePriority`
already appends any unknown-to-the-array tag in `AUCTION_KEYS` order when the AH Price page is
opened, and it did so before this change too. No `/lh reset` is required. Users who had hit F-001
(a CLI-enabled key that was never picked) can either open the AH Price page once or run
`/lh reset settings.auction.capture` and re-enable from the panel.

## Performance impact

**None claimed.** No perf-tagged change was implemented — F-009 was deferred. The addon ships no
`tests/perf.lua` and adopts no `LibKa0s-Perf` major, so there is no scenario allocation count and no
committed capture under `docs/perf-runs/` to cite. This section is deliberately empty rather than
filled with an estimate.

## Test and complexity movement

| | Before (2026-08-05 review baseline) | After **(confirm)** |
|---|---|---|
| Headless cases | 579 passed / 579 total | 585 / 585 |
| `luacheck` | 0 warnings / 0 errors, 23 files | 0 / 0, 23 files |
| `lizard` warnings (CCN > 15) | 0 | 0 |
| Max CCN | 15 (six functions) | 15 (same six) |
| Total NLOC | 11367 | ~11400 |

`docs/test-cases.md` and the `README.md` `[Tests]` badge were regenerated/updated **in the same
commits** that moved the count, per `testing-§7`; the inventory is emitted by
`lua tests/run.lua --list` and was never hand-edited.

Complexity entries these changes are expected to move: **none**. `settings/Schema.lua`'s `S:Register`
gains one decision and stays far below the cap. The next release's `lizard` regeneration
(`/wow-addon:bump-version`) should confirm the six functions at CCN 15 are unmoved and the warning
count is still 0 — that is a release-run confirmation, not a task in this cycle.

## Known follow-ups

- **F-009 — double segment computation in `Analytics._buildCharStackRows`.** Deferred: no harness to
  measure it with, and the path is render-on-demand. The natural fix (compute segments once per
  character into a local, reuse for the totals pass) is a five-line change whenever someone is in
  that file for another reason.
- **No offline perf scenarios.** `docs/automated-tests/RESULTS.md` records `perf: skip` as a
  permanent state, and the review inherited it: nothing in this repo can say what
  `Database:QueryList` or `Database:Stats` cost, and `performance-§9`'s zero-overhead evidence does
  not exist because there is no instrumentation to measure. Whether to adopt `LibKa0s-Perf` is a
  standards-audit question, not a review one — flagged here so it is not lost.
- **`modules/Analytics.lua` (1180 LOC) is still on the `layout-§1` notice band**, carried in
  `RESULTS.md` as "peel next — now unblocked". Untouched by this cycle.

## Verification evidence

- Completed checklist with its sign-off table: `docs/reviews/2026-08-05/03_SMOKE_TESTS.md`
- Findings and the measurement block they rest on: `docs/reviews/2026-08-05/01_FINDINGS.md`
- Commit range / PR: **(confirm)**

## Suggested commit message / PR description

```
Review 2026-08-05: a CLI-enabled price source is now actually used

Fixes the one functional defect found in the 2026-08-05 principal review, plus
five hardening changes around the degraded-install paths, the test suite's
falsifiability and three places where a label or comment did not match the code.

High
  F-001  The AH price priority cascade was declared twice — 7 entries in
         defaults/Global.lua, 11 in core/Constants.lua. A price key enabled with
         `/lh set settings.auction.capture` (i.e. without opening the AH Price
         page, the only caller of ReconcilePriority) was gathered and stored but
         never selected by AuctionPrice:Pick, so it reached no computed value,
         no chart and no CSV value column. defaults/Global.lua now copies the
         constants (savedvariables-§2).

Medium
  F-002  Schema:Register's boot check could never fire (`and` where the intent
         was `or`); it is the check that would have caught F-001 on a client.
  F-003  Collector and Browser fell back to the shared bus object when AceEvent
         was unresolvable, re-creating the last-registrant-wins receiver clobber
         (architecture-§4, anti-patterns #32). They now register nothing.
  F-004  The settings panel's "Reset All" button also purged the entire loot
         history, colliding with the reserved /lh resetall verb, which does not
         (slash-commands-§3). Relabeled "Reset Everything...".
  F-005  The two vendor-sync cases passed with zero assertions when the sibling
         LibKa0s checkout was absent; their titles now disclose the condition.
  F-006  Only the Core degradation stub was checked against its call sites. A
         new case diffs every stub against the members the addon calls; it found
         HelpHeader missing from the Slash stub and ConsoleCheckbox stale in the
         DebugLog stub.

Low
  F-007  Two comments named settings/Panel.lua as a reader of formatters it does
         not read.
  F-008  Stale `luacheck: ignore addonName` in modules/AuctionPrice.lua, where
         addonName is genuinely used.

Deferred: F-009 (Analytics recomputes per-character stack segments twice) — no
perf harness exists to state the improvement as a number.

Tests 579 -> 585, docs/test-cases.md and the README badge moved with them.
luacheck 0/0 over 23 files; lizard 0 warnings, max CCN 15 (unchanged).
Reviewed against Ka0s WoW Addon Standard v2.21.0.
```
