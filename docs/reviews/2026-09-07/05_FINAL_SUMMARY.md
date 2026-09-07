# 05 — Final summary

> **Status: written in advance.** This document is the post-implementation record for the 2026-09-07 review cycle, drafted under the assumption that every change in `02_PROPOSED_CHANGES.md` has been applied and every check in `03_SMOKE_TESTS.md` has passed. Fill in the sign-off table and the commit range before using it as a PR description or a changelog entry.

---

## Headline

This cycle fixed a real bug in the database-size estimate, closed the test that was letting it through, finished a coalescing pass that had reached two of its three call sites, and put three unpinned wiring paths under guard rails. It also brought the performance record — the sole evidence for this addon's ratified no-instrumentation exemption — back into agreement with the code it describes, after finding it two events, one timer and several line numbers behind.

Nothing here changes what the addon records or how it records it. The one externally visible change is that the database-size figure the History window and the settings page report is now **larger**, because it was previously undercounting every currency row and every row captured with a cold item cache.

The addon arrived in unusually good shape. Every out-of-game suite was green before this cycle started, the vendored `LibKa0s v1.25.0` payload was byte-identical to its declared tag, and the library seams are the strongest examples of the descriptor/stub contract in the collection. No `[upstream]` finding was raised; no change in this cycle touches `libs/` or `tests/_kit/`.

---

## Counts

**Critical fixed: 0 · High fixed: 0 · Medium fixed: 11 · Low fixed: 6**

No Critical or High findings were raised. Every finding cleared its bucket on both the defect-kind floor and the reachability ceiling; several defects that would have graded higher on kind alone are Medium because their reachability line reads *test inventory only*, *a comment*, or *a maintainer reading the record*.

**Fixed:** F-001, F-002, F-003, F-004, F-005, F-006, F-007, F-008, F-009, F-012, F-018 (Medium) · F-013, F-014, F-015, F-016, F-017 (Low)

**Deliberately deferred:**

| ID | Why deferred |
|---|---|
| **F-010** — `AuctionPrice:GatherAll` rebuilds a settings-invariant per loot line | Real, but unmeasurable in this repo: there is no `tests/perf.lua` to put a number on it, and adding one intersects the `performance-§12` exemption decision at Checkpoint 1. Fixing it blind would be an optimization with no record behind it, which is what the standard's evidence rules exist to prevent. Carried as a follow-up. |
| **F-011** — `docs/automated-tests/RESULTS.md` is stale | Regeneration's checkpoint is **release**, not a review. `/wow-addon:bump-version` regenerates it; writing it here by hand would be worse than leaving it stale, because a hand-edited record reads as measured. Carried as a follow-up so the next release run knows what to expect. |

---

## Changes by theme

### Theme A — the storage estimate is correct, and its test can prove it

**What changed.** `Database:StorageStats` now counts every populated string field on every record, instead of stopping at the first missing one. The reported database size rises accordingly — most visibly for histories with many currency rows, which were previously counted as bare overhead. The test over it now asserts an exact byte total rather than "greater than zero".

**Why it mattered.** `estimateRecordBytes` packed seven optional fields into an array literal and walked it with `ipairs`, which halts at the first `nil`. Currency records have no `itemLink`, so the walk ran **zero** iterations and every currency row contributed exactly 256 bytes regardless of its content. Item records captured before the client cached the item lost every field after the first nil. The case over it asserted only `s.bytes > 0`, which two records satisfy on overhead alone — so the suite reported coverage it did not have, which is strictly worse than reporting a gap. Removing the array literal also removed one table allocation per record on a function that walks the whole history.

**Finding IDs covered:** F-001, F-002, F-004 · **Change IDs:** C-01, C-02

**Files touched:**
- `core/Database.lua`
- `tests/test_database.lua`
- `docs/test-cases.md` *(regenerated)*
- `README.md` *(badge)*

---

### Theme B — the coalescing pass reaches all three consumers

**What changed.** The settings panel's `Ka0s_LootHistory_RecordAdded` listener is now collapsed through `NS.Coalesce`, matching the History window and the Insights tab. `HistoryChanged` stays immediate at all three, as it always did.

**Why it mattered.** Issue #27 established that `RecordAdded` fires once per looted item and that each of its consumers pays a full-history pass, so the automatic message must collapse while the deliberate one must not. Two consumers were wired that way with comments explaining the reasoning; the third — the settings panel's storage line, which calls the same `Database:StorageStats` — was registered uncoalesced with no comment acknowledging the difference. With the panel open on the General page, a multi-drop loot burst paid one full-history walk per drop.

**Finding IDs covered:** F-003 · **Change IDs:** C-03

**Files touched:**
- `settings/Panel.lua`

---

### Theme C — the performance record describes the tree again

**What changed.** `docs/performance.md`'s two generated sweeps were re-run from the page's own commands and rewritten to match. The event table gained the two `PLAYER_REGEN_*` registrations it had never listed; the timer table gained `NS.Coalesce`'s one-shot and had a dead file:line corrected. The `CHAT_MSG_LOOT` row now names what the capture path actually costs.

**Why it mattered.** This page is the entire evidence base for a ratified `performance-§12` exemption — the reason this addon ships no `tests/perf.lua`, no `/lh perf` verb and no `docs/perf-analysis/` store. Three of its statements had gone stale. It claimed eleven event registrations where the tree has thirteen, and the two it omitted were `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` — precisely the combat-transition events the exemption's criterion (a) is about. It claimed four `C_Timer` calls where there are five, omitting the one the same page credits two sections later with fixing the `RecordAdded` burst. And its `CHAT_MSG_LOOT` row described the per-fire work as *"parse, threshold-check, and on a keeper one table insert"* when a keeper also builds a `C_TooltipInfo` tooltip and runs a price cascade across up to three third-party addons. A stale exemption reads as a live one.

**Finding IDs covered:** F-005, F-006, F-007 · **Change IDs:** C-04

**Files touched:**
- `docs/performance.md`

---

### Theme D — three unpinned wiring paths now fail loudly

**What changed.** Three new guard-rail cases: one exercising `Attribution:Enable` and asserting its registration set and hook installs; one pinning `tests/run.lua`'s lifecycle kick against what `addon:OnInitialize` actually calls; one asserting `NS.version` equals the TOC's `## Version:`.

**Why it mattered.** All three failed silently. `Attribution:Enable` — seven events, a unit-filtered frame, five hooks, the entire source-attribution wiring — had **zero** test callers; a mistyped event name would have left all 23 attribution cases green while the engine received nothing. `tests/run.lua`'s "lifecycle kick the client's OnInitialize does" is a hand-copy that had already dropped `Slash:Register`, meaning the suite measured an addon initialized differently from the shipped one — the same class of silent drift `testing-§9` names, one level above the lists `tests/test_harness.lua` already pins so well. And `NS.version`'s only assertion compared it to `NS.Version()` **on the path where the TOC cannot be read**, which is the one case that cannot detect drift.

**Finding IDs covered:** F-008, F-009, F-018 · **Change IDs:** C-06, C-07, C-08

**Files touched:**
- `tests/test_attribution.lua`
- `tests/test_harness.lua`
- `tests/run.lua`
- `tests/test_envsetup.lua`
- `docs/test-cases.md` *(regenerated)*
- `README.md` *(badge)*

---

### Theme E — the small true things

**What changed.** The two trims that read localized tooltip and spell text now match NBSP as whitespace. The degraded-install help no longer advertises `/lh config`, a verb that immediately declines on that path. `Attribution:Consume` was renamed to reflect that it peeks rather than consumes. Three comments that described a migration chain and a window-close path that had both moved on were corrected.

**Why it mattered.** Lua's `%s` does not match U+00A0, which localized WoW tooltip lines and spell names carry routinely on deDE and frFR — so a surviving NBSP made the warbound-line lookup and the Mass-Mill name-family prefix miss. Both scanners have a locale-independent path in front of them, so the exposure was narrow, but the fallback was silently blind. The degraded help is rendered by subtraction from `NS.COMMANDS`, which is the right design — the subtracted set was simply short one verb, in the one install where an accurate list of what still works matters most. And `defaults/Global.lua` still described a v1→v2 migration chain that now runs to v8.

**Finding IDs covered:** F-012, F-013, F-014, F-016, F-017 · **Change IDs:** C-09, C-10

**Files touched:**
- `core/Compat.lua`
- `modules/Attribution.lua`
- `modules/Collector.lua`
- `modules/Browser.lua`
- `settings/Slash.lua`
- `defaults/Global.lua`
- `core/Database.lua`
- `tests/test_compat.lua`, `tests/test_attribution.lua`, `tests/test_libka0s.lua`

---

### Theme F — line endings

**What changed.** Nine tracked files that were LF-only (one, `core/Util.lua`, mixed at 252 LF / 216 CR) in a CRLF-pinned tree were renormalized. `.gitattributes` was **not** edited — it was already correct and complete, carrying the `* text=auto eol=crlf` pin, the `*.sh text eol=lf` carve-out and the full binary block.

**Why it mattered.** Four of the nine are shipped source (`core/Constants.lua`, `core/MediaSetup.lua`, `modules/Analytics.lua`, `settings/Slash.lua`). No runtime effect — the client tolerates LF — but every one is diff noise waiting for the next `git add --renormalize`, and a file mixed *within itself* is a merge conflict looking for a home.

**Finding IDs covered:** F-015 · **Change IDs:** C-11

**Files touched:** `.pkgmeta`, `core/Constants.lua`, `core/MediaSetup.lua`, `core/Util.lua`, `docs/revendor/2026-08-25/01_DELTA.md`, `docs/revendor/2026-08-25/05_SUMMARY.md`, `modules/Analytics.lua`, `settings/Slash.lua`, `tests/test_util.lua`

---

## API / behaviour changes

| Change | Detail |
|---|---|
| **Database-size figure rises** | `Database:StorageStats().bytes` now counts string fields on records that previously truncated. Visible in the History window footer (`Database ≈ …`) and the settings General page (`Database size: ≈ …`). The number was previously an **under**-estimate; it is not a growth in stored data. Both surfaces already label it "(estimated)". |
| **Settings storage line lags by up to 0.2 s** | The panel's storage line now updates once per coalesce window (`RECORD_ADDED_COALESCE = 0.2`) during a loot burst instead of once per item. Matches the History window footer and the Insights tab. |
| **`Attribution:Consume` renamed** | Internal only. Not part of any public API and not reachable from a slash command; no user-visible effect. |
| **Degraded-install help omits `config`** | On an install where `libs/LibKa0s/` cannot be resolved, `/lh` no longer lists `config`. The verb still exists and still prints its honest refusal if typed. |

**No slash verbs were added, renamed or removed.** `NS.COMMANDS` still holds the same 14 entries and `README.md:81-93` still documents all of them.

**No locale keys were added or renamed.** The addon remains English-only by the accepted scope decision at `locales/enUS.lua:7-9`; the `NS.L` seam is untouched.

---

## Saved-variable / migration notes

**No schema bump. No migration added. `schemaVersion` remains 8.**

Nothing in this cycle changes what is stored or how it is shaped. `estimateRecordBytes` is a **read**-side estimator; it derives a number from stored records and writes nothing.

Existing profiles need no action, and `/lh resetall` is not required. The only thing a user will notice is that the database-size figure is larger than it was before the update, on identical data.

The `defaults/Global.lua` comment correction (`v1→v2` → the full v1→v8 chain) is a comment; the shipped `schemaVersion = 1` floor is unchanged, so a fresh install still walks every guarded step and stamps 8 at first login — verified by `03_SMOKE_TESTS.md` R-2 step 4.

---

## Deprecated-API migrations

**None.** No deprecated or removed API was found. The addon already routes every varying surface through `core/Compat.lua` and `core/EnvSetup.lua` with modern namespaced calls first and presence-gated global fallbacks below:

| Modern API in use | Fallback below it | Where |
|---|---|---|
| `C_Container.GetContainerItemInfo` / `UseContainerItem` | global `UseContainerItem` | `core/Compat.lua:22-37` |
| `C_Item.GetItemInfo` / `GetItemInfoInstant` / `GetDetailedItemLevelInfo` | link display data | `core/Compat.lua:126-150, 300-323` |
| `C_Spell.GetSpellName` | global `GetSpellInfo` | `core/Compat.lua:64-68` |
| `C_AddOns.GetAddOnMetadata` | global `GetAddOnMetadata` | `core/EnvSetup.lua:51-58` |
| `C_TooltipInfo.GetHyperlink` | returns `nil, false` when absent | `core/Compat.lua:218-219` |
| `C_CurrencyInfo`, `C_ChallengeMode` | presence-gated, degrade to nil | `core/Compat.lua:9-16, 330+` |

Settings registration is `LibKa0s-Options-1.0`'s, not this addon's — no `InterfaceOptions_AddCategory` anywhere.

---

## Performance impact

**No measured before/after numbers exist, and none are invented here.**

This addon carries a ratified `performance-§12` no-combat-path exemption (`docs/ARCHITECTURE.md → ## Documented deviations`, `LH-20`…`LH-26`), so it ships **no** `tests/perf.lua` and **no** `docs/perf-analysis/` store. There is therefore no offline scenario and no committed capture to cite for either C-01 or C-03.

What can be said, and its basis:

- **C-01** removes one table allocation per record from a function that walks the whole history. Structural, from reading `core/Database.lua:750-751` and `:766`; not measured.
- **C-03** reduces the settings panel's full-history passes during a loot burst from one-per-item to one-per-0.2 s-window. Structural, by parity with the two consumers already wired that way; not measured.

The strongest evidence available without the harness is the in-client `collectgarbage("count")` delta in `03_SMOKE_TESTS.md` C-03, with its shared-heap caveat recorded alongside the result. **Record the observed numbers here when that check is run; do not fill this section with an estimate.**

---

## Test and complexity movement

| | Before | After |
|---|---|---|
| Pass count | **699** | **704** |
| Failures / skips | 0 / 0 | 0 / 0 |
| `docs/test-cases.md` | 699, in step | 704, regenerated with the change that moved it |
| README `[Tests]` badge | `699/699` | `704/704`, moved in the same change |
| `luacheck` | 0/0 over 28 files | 0/0 over 28 files |

Five cases added: one for the currency-row byte total (C-02), one for `Attribution:Enable`'s wiring (C-06), one for the runner's lifecycle kick (C-07), one for `NS.version` vs. the TOC (C-08), one for the NBSP-wrapped warbound line (C-09). One existing case strengthened: `tests/test_database.lua`'s `StorageStats` assertion moved from `> 0` to an exact total.

**Complexity — expected movement, to be confirmed by the next release's regeneration, not run here:**

- `estimateRecordBytes` loses a loop and a table construction; both it and its new `addLen` helper stay far below any threshold.
- Nothing touches any of the seven functions at CCN 15.
- `settings/Panel.lua` gains ~4 lines from C-03 and stays in the `layout-§1` 1000–1500 on-notice band (**1004 → ~1008 LOC**). It is a **newly** crossed band entry that `docs/automated-tests/RESULTS.md` does not yet carry a disposition for — F-011 — and the next release run should give it one.
- `modules/Analytics.lua`'s "peel next" entry is now five runs old at 1178 LOC with nothing tracking it. Untouched by this cycle; see follow-ups.

---

## Known follow-ups

| ID | Item | Why it was not done now |
|---|---|---|
| **F-010** | `AuctionPrice:GatherAll` recomputes `wantedByProvider` on every loot line; memoise it behind a `SettingsChanged` upvalue refresh the way `Collector` already does | Real but unmeasurable here — no offline harness exists to put a number on it, and building one is Checkpoint 1's decision, not this cycle's. An optimization with no record behind it is an assertion. |
| **F-011** | `docs/automated-tests/RESULTS.md` is 55 test cases, 1106 NLOC and one band file behind | Its regeneration checkpoint is **release** (`/wow-addon:bump-version`). Hand-editing it would be worse than leaving it stale, because it would read as measured. The next release run closes it. |
| **CP-1 outcome** | If the maintainer decides at Checkpoint 1 that `performance-§12` criterion (a) no longer holds, the full `performance-§1` wiring re-arms: `core/PerfSetup.lua`, a bucket descriptor, `tests/perf.lua`, the `/lh perf` verb, a `docs/perf-analysis/` store, and rewritten `LH-20`…`LH-26` register entries | An entire project, deliberately kept out of a review's change-set. The decision is now *informed*, which is what this cycle delivers; the work it might trigger is its own. |
| — | `modules/Analytics.lua` at 1178 LOC has read "peel next" for five consecutive complexity runs with nothing tracking it | Out of scope for a review pass. The record itself flags this as a shelf-life problem; it needs an owner in the issue store, not a drive-by split. |
| — | `settings/Panel.lua` newly in the 1000–1500 band | On notice, not in breach. `layout-§1` treats this band as compliant; it needs a disposition at the next release, not a split now. |

---

## Verification evidence

- **Smoke tests:** `docs/reviews/2026-09-07/03_SMOKE_TESTS.md`, sign-off table completed. *(Attach the filled table.)*
- **Findings:** `docs/reviews/2026-09-07/01_FINDINGS.md`, including the Step 0 measurement block with every command and its scope.
- **Design:** `docs/reviews/2026-09-07/02_PROPOSED_CHANGES.md`, standards conformance table.
- **Execution:** `docs/reviews/2026-09-07/04_EXECUTION_PLAN.md`, both checkpoints signed off.
- **Commit range:** *(fill in)*
- **PR:** *(fill in)*

---

## Suggested commit message / PR description

```
Review 2026-09-07: the byte estimate, the third coalescer, and four unpinned lists

The database-size figure was undercounting. estimateRecordBytes packed seven
optional fields into an array and walked it with ipairs, which stops at the
first nil — so every currency row (no itemLink) counted as bare overhead, and
any row captured with a cold item cache lost every field after the first gap.
The case over it asserted only `bytes > 0`, which two records satisfy on
overhead alone, so the suite reported coverage it did not have. Both halves are
fixed; the reported size rises on identical data. (F-001, F-002, F-004)

Issue #27's coalescing pass reached two of its three RecordAdded consumers. The
settings panel's storage line — the same full-history Database:StorageStats walk
— was registered uncoalesced. It is now wired like its two siblings, with
HistoryChanged still immediate. (F-003)

docs/performance.md is the only evidence for this addon's ratified
performance-§12 exemption, and it had gone stale on the axis the exemption is
about: eleven events listed where the tree has thirteen, the two omitted being
PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED; four C_Timer calls where there
are five, the missing one being NS.Coalesce's, which the same page credits two
sections later; a dead file:line; and a CHAT_MSG_LOOT row describing "one table
insert" for a path that builds a C_TooltipInfo tooltip and runs a price cascade
across three third-party addons. Regenerated from the page's own commands.
Whether criterion (a) still holds is now an informed decision rather than an
inherited one. (F-005, F-006, F-007)

Three wiring paths that failed silently now have guard rails: Attribution:Enable
(seven events, a unit-filtered frame, five hooks — zero test callers before
this), tests/run.lua's hand-copied lifecycle kick (already missing
Slash:Register), and NS.version against the TOC. (F-008, F-009, F-018)

Plus: NBSP is not %s, so the two trims reading localized tooltip and spell text
were widened; the degraded-install help stops advertising a config verb that
declines; Attribution:Consume renamed to say what it does; three comments
describing a migration chain and a close path that had moved on; and nine
LF-only files renormalized in a CRLF-pinned tree, in their own commit.
(F-012 … F-017)

Tests 699 -> 704, 0 failed, 0 skipped. luacheck 0/0 over 28 files.
lizard: no thresholds exceeded. Vendored LibKa0s v1.25.0 unchanged and verified
byte-identical to its tag — no change in this cycle touches libs/ or tests/_kit/.

Deferred: F-010 (needs a perf harness that intersects the exemption decision),
F-011 (RESULTS.md regenerates at release, not here).

Review bundle: docs/reviews/2026-09-07/
```
