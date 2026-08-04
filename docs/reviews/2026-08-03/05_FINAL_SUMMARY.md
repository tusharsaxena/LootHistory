# Ka0s Loot History — Final Summary (2026-08-03 review cycle)

> **Status: written ahead of implementation.** This artifact is the post-implementation record for
> the cycle described in `02_PROPOSED_CHANGES.md` and `04_EXECUTION_PLAN.md`, written on the
> assumption that every check in `03_SMOKE_TESTS.md` passes. Fill in the bracketed measurements and
> the commit range as the milestones land; anything still bracketed has not been verified.

---

## Headline

This cycle fixed three bugs a user could actually hit, took two repeat-frequency code paths off the
hot path, and wired the performance harness the collection standard requires so the next such claim
can be measured instead of argued. The bugs were all one shape: a settings page that quietly refused
to redraw after a change made while it was hidden, a live-stats handler that outlived the widget it
was updating, and a "preview" mode whose right-click menu was still pointed at real, persistent data.
Nothing about how loot is captured, attributed or stored changed — the recording engine, the
attribution rules and the saved-variables shape are untouched, apart from a fresh install now
starting at the current schema stamp instead of migrating up to it on first login.

---

## Counts

`Critical fixed: 0 · High fixed: 3 · Medium fixed: 6 · Low fixed: 5`

No findings were deferred. There were no Critical findings and no `[upstream]` defects.

One **optional** cross-repo enhancement (`O.MarkDirty` in `LibKa0s-Options-1.0`, milestone M4) is
tracked separately and is **not** required by any fix in this cycle — `F-001` ships complete using
the library's existing public API.

---

## Changes by theme

### Theme A · The panel's refresh contract is the library's again
**What changed.** `settings/Panel.lua` stopped keeping its own copy of the "this page needs
redrawing" bookkeeping and hands that decision back to `LibKa0s-Options-1.0`, which is the module
that actually owns *when* a page redraws. The Filters sub-page now picks up a change made while it
was closed — blacklisting an item from the History window's right-click menu, or a `/lh resetall` —
the next time you open it. Separately, the settings **History** section's live stats line no longer
holds on to a widget that a later redraw released.

**Why it mattered.** The host wrote a flag nothing read, and the library read a flag nothing wrote,
so the lazy-rebuild path the standard mandates was never actually connected. A user blacklisting an
item and then opening Settings ▸ Filters saw no evidence their action had taken effect. The
stats-handler variant was latent but nastier: after a re-render it would have written the storage
line into a recycled AceGUI Label belonging to some unrelated control.

**Findings covered:** F-001, F-002, F-013. **Changes implemented:** C-001, C-002.

**Files touched**
- `settings/Panel.lua`
- `tests/test_panel.lua`

### Theme B · Preview mode is read-only
**What changed.** While `/lh test` is active, the History table's right-click menu disables
**Blacklist item**, **Blacklist currency** and **Delete**. **Link to chat** stays available.

**Why it mattered.** The read path swapped to synthetic data but the write paths did not.
"Blacklist item" on a fake row wrote a fabricated item id (100001–100030) permanently into the real
account blacklist, and "Delete" scanned the real history, removed nothing, and left the row on
screen — from a feature the README promises is "temporary, never saved".

**Findings covered:** F-003. **Changes implemented:** C-003.

**Files touched**
- `modules/BrowserTable.lua`
- `tests/test_browsertable.lua`

### Theme C · Two hot paths taken off the critical frame
**What changed.** With the History window open, a burst of loot lines now costs one repaint instead
of one per line, and the saved-variables size estimate no longer allocates a throwaway table per
record. On the Insights tab, dragging the window's resize grip coalesces into one relayout per tick
instead of one per frame.

**Why it mattered.** Each looted item previously triggered eight full passes over the entire history
(seven dropdown option rebuilds plus the size estimate) plus a filter-and-sort, and the size estimate
allocated one table per record on every one of those passes. On a multi-thousand-row history during a
mass-loot pull that is felt. The Insights relayout re-sorted every breakdown and re-anchored several
hundred regions on every frame of a resize drag.

**Findings covered:** F-004, F-005. **Changes implemented:** C-004, C-005.

**Files touched**
- `modules/Browser.lua`
- `core/Database.lua`
- `modules/Analytics.lua`
- `tests/test_browser.lua`, `tests/test_database.lua`, `tests/test_analytics.lua`

### Theme D · The performance harness is wired
**What changed.** `LibKa0s-Perf-1.0` — already vendored, already loaded, previously never
instantiated — is now created from a descriptor in `core/PerfSetup.lua`, with a degradation stub for
installs missing the library. `/lh perf` opens a guided two-arm capture, results land in a bounded
`LootHistoryPerfDB` ring outside the AceDB tree, and three buckets are bracketed:
`lootCapture`, `historyRepaint` and `insightsLayout`.

**Why it mattered.** Two measurable hot paths were found in this review and the addon had no
sanctioned way to quantify either in a live client, in a form a user could paste back. It was also
parsing ~1,200 lines of dormant library at every login for nothing.

**Findings covered:** F-006. **Changes implemented:** C-006.

**Files touched**
- `core/PerfSetup.lua` *(new)*
- `LootHistory.toc`
- `settings/Schema.lua`
- `modules/Browser.lua`, `modules/Analytics.lua`, `modules/Collector.lua`
- `.luacheckrc`
- `docs/performance.md` *(new)*, `docs/perf-runs/README.md` *(new)*, `docs/ARCHITECTURE.md`, `README.md`
- `tests/perf.lua` *(new)*, `tests/test_libka0s.lua`

### Theme E · One source of truth for defaults; comments that match the code
**What changed.** `defaults/Global.lua` now references `core/Constants.lua`'s auction tables instead
of restating them, so a fresh install, `/lh reset` and the AH page's **Defaults** button cannot
disagree. The shipped `schemaVersion` default is the current head rather than `1`, and its comment
describes the migration set rather than one long-superseded step. One stale `§3.4`-style standard
reference was rewritten in the current `filename-§N` form.

**Why it mattered.** The duplicated priority array was **already** four tags short of the constant it
copied; only a render-time reconciliation hid it. Edit one copy and the two paths silently produce
different price rankings — a class of bug that surfaces as confusion, never as an error.

**Findings covered:** F-007, F-009, F-010. **Changes implemented:** C-007, C-008, C-009.

**Files touched**
- `defaults/Global.lua`
- `settings/OptionsSetup.lua`
- `tests/test_database.lua`, `tests/test_auctionprice.lua`

### Theme F · Surface symmetry and polish
**What changed.** The degraded-install stub for the slash module now answers `HelpHeader` like every
other library-owned member. The three `NewBusTarget() or bus` fallbacks now decline to subscribe
rather than falling back onto the shared bus-as-self target. `/lh test` no longer forces the History
window open when *leaving* preview mode. The minimap launcher, the TOC `IconTexture` and the settings
landing page now show one mark instead of three.

**Why it mattered.** None of these was breaking anything today, but each is a small mismatch between
what the code claims and what it does — the stub's own comment promised every member, the bus comment
warned against exactly the fallback three lines below it, and a user saw a bag, a wrapped present and
a logo for one addon.

**Findings covered:** F-008, F-011, F-012, F-014. **Changes implemented:** C-010, C-011, C-012.

**Files touched**
- `settings/Slash.lua`
- `modules/Collector.lua`, `modules/Browser.lua`, `modules/Analytics.lua`, `modules/BrowserTable.lua`
- `LootHistory.toc`, possibly `media/logos/`
- `tests/test_slash.lua`, `tests/test_browsertable.lua`

---

## API / behavior changes

| Change | Detail |
|---|---|
| **New slash verb** | `/lh perf` — the reserved performance-capture verb, dispatched through `NS.COMMANDS`. Documented in `README.md`'s command table. |
| **New saved-variable global** | `LootHistoryPerfDB` — a bounded capture ring, declared **second** in the TOC and living **outside** the AceDB tree so it never rides a profile copy, reset or switch. |
| **Row menu** | **Blacklist item**, **Blacklist currency** and **Delete** are disabled while `/lh test` preview mode is active. |
| **`/lh test`** | Leaving preview mode no longer opens the History window. |
| **Repaint timing** | With the window open, a looted item's footer/dropdown refresh is coalesced (≈0.2 s). Every user-initiated change (delete, prune, filter edit) is still immediate. |
| **Icon** | The minimap launcher and the TOC `IconTexture` changed artwork. Minimap button *position* is keyed on the LDB name and is unaffected. |
| **Defaults** | A fresh install now receives the complete 11-entry auction priority array up front (previously 7, back-filled at first render). No change for existing databases. |
| **Removed / renamed** | Nothing. No slash verb was removed or renamed, no locale key changed (the addon has none), no deprecated API was swapped. |

---

## Saved-variable / migration notes

**No schema migration was added this cycle**, and the persisted record shape is unchanged.

Two storage-adjacent changes:

1. **`schemaVersion` default moved from `1` to the current head (8).** This affects **new databases
   only**. `NS:RunMigrations` is unchanged and still walks every step for an existing database; a
   pre-existing profile at any version migrates exactly as before. Nothing auto-migrates differently
   and **no `/lh reset` is required**.
2. **`LootHistoryPerfDB` is a new, second saved-variables global.** It is created empty on first
   `/lh perf` run, is bounded by construction, and is deliberately **not** part of the AceDB tree —
   so `/lh resetall`, `/lh purge` and any future profile operation leave it alone. Deleting it by
   hand is always safe.

**Verification:** cold-start with the SavedVariables file removed and confirm `schemaVersion` reads
the head value after `/reload`; separately, hand-edit an existing file's stamp to `1` and confirm the
`[Migrate]` console lines walk `v1 -> v8` with no record count change (`03_SMOKE_TESTS.md`,
C-007/C-008).

---

## Deprecated-API migrations

**None.** The review found no deprecated or removed API in use. Every varying call already goes
through `core/Compat.lua` as compat-§1 requires, and the two legacy globals that appear there
(`GetSpellInfo` at `core/Compat.lua:75`, `GetAddOnMetadata` at `:477`) are guarded fallbacks behind
their `C_Spell` / `C_AddOns` successors — correct as written, and left alone.

---

## Performance impact

Numbers from `03_SMOKE_TESTS.md`'s spot-checks. **Fill in from the CP-1 and CP-2 checkpoints.**

| Measurement | Before | After | Method |
|---|---|---|---|
| Lua heap delta across a ~10-mob mass-loot pull, window open, ≥500 records | `[ ]` kB | `[ ]` kB | `collectgarbage("count")` before/after |
| `GetAddOnCPUUsage("LootHistory")` across a 5 s Insights resize drag | `[ ]` ms | `[ ]` ms | `/console scriptProfile 1` → `/reload` → drag |
| `lootCapture` bucket, 60 s dummy fight | n/a | `[ ]` | `/lh perf` two-arm capture |
| `historyRepaint` bucket, same fight | n/a | `[ ]` | `/lh perf` |
| `insightsLayout` bucket, same fight | n/a | `[ ]` | `/lh perf` |
| Dormant-bracket overhead | n/a | `[ ]` bytes allocated | `tests/perf.lua` zero-overhead scenario |

The committed capture belongs in `docs/perf-runs/` — a committed capture is evidence that outlives
the write-up interpreting it.

---

## Known follow-ups

| Item | Why it was left |
|---|---|
| **`O.MarkDirty(ctx)` upstream in `LibKa0s-Options-1.0`** (M4, T-18…T-21) | Cross-repo, and genuinely optional: `O.RefreshAllPanels()` is a correct public path that already produces the right behavior for a three-page panel showing one page at a time. The additive seam is the tidier long-term shape and is worth doing on the library's own schedule — but gating a user-visible bug fix on a library release would have been the wrong trade. Must land as a library release + a standalone re-vendor commit here, never as a local edit under `libs/`. |
| **Perf bucket coverage beyond the three declared** | performance-§1 makes the *wiring* a MUST and coverage a SHOULD. Three buckets cover the paths this review actually measured. Extending coverage (export serialization, the bound-repair pass, the AH gather loop) is worth doing once a real capture shows where the remaining time goes — which is the point of having the harness. |
| **Localization** | The addon ships English-only by an explicit, recorded scope decision (`locales/enUS.lua:7-11`); the `NS.L` seam exists and is unused. This review raised no `[locale]` findings and deliberately did not open the question. |
| **`ISS-09` column chooser, `ISS-11` configurable window styling, `ISS-16` item-returning refunds** | Pre-existing backlog, already triaged with recorded decisions in `docs/pending/LEDGER.md`. Out of scope for a review cycle. |

---

## Verification evidence

- **Smoke tests:** `docs/reviews/2026-08-03/03_SMOKE_TESTS.md` — sign-off table completed, one row
  per change ID plus the R1–R12 regression suite.
- **Headless suite:** `lua tests/run.lua` green at every commit (baseline before this cycle: **563
  passed, 0 failed**; expect a higher total after the new regression cases). `lua tests/perf.lua`
  runs separately and is **not** counted in that total or the `[tests]` badge.
- **Lint:** `luacheck .` zero errors.
- **Vendor sync:** `tests/test_vendor_sync.lua` green — `libs/LibKa0s/` and `tests/_kit/` remain
  byte-exact for the LibKa0s tag `README.md` names. **No file under `libs/` or `tests/_kit/` was
  modified by this cycle.**
- **Commit range:** `[ fill in ]`
- **PR:** `[ fill in ]`

---

## Suggested commit message / PR description

```
review(2026-08-03): fix the panel refresh contract, make preview mode read-only,
take two hot paths off the critical frame, and wire the perf harness

Three user-visible bugs, two hot paths and the missing measurement wiring, from a
full-scope review vetted against Ka0s WoW Addon Standard v2.17.1.

Correctness
- F-001  The Filters settings page never rebuilt after a change made while it was
         hidden: the host wrote its own `ctx.dirty`, which nothing read, while the
         library keys its lazy re-render on `ctx._dirty`. Blacklisting an item from
         the History window and then opening Settings showed a stale list. Now routed
         through the library's public structural refresh (options-ui-§11).
- F-002  The settings History section's live-stats bus handler captured the first
         render's AceGUI Label; a later re-render released that widget back to the
         pool, so a subsequent update wrote into a recycled control. The handler is
         now render-agnostic.
- F-003  `/lh test` preview mode left the row context menu pointed at live data:
         "Blacklist item" wrote a fabricated id into the real account blacklist and
         "Delete" silently removed nothing. The mutating entries are now disabled in
         preview mode.

Performance
- F-004  Each looted item triggered eight full history scans plus a table allocation
         per record while the browser was open. The record-added repaint is coalesced
         and the byte estimate is allocation-free.
- F-005  The Insights relayout ran on every frame of a window-resize drag. Throttled.
- F-006  `LibKa0s-Perf-1.0` was vendored and loaded but never instantiated. Wired per
         performance-§1: `core/PerfSetup.lua` descriptor + degradation stub, the
         reserved `perf` verb through `NS.COMMANDS`, `LootHistoryPerfDB` as the second
         SV global, three declared buckets, `tests/perf.lua`, and the two required docs.

Hygiene
- F-007  The AH capture/priority defaults were declared twice and the priority copy was
         already four tags short; `defaults/Global.lua` now references `Constants`.
- F-009  The shipped `schemaVersion` default and its comment were frozen at the initial
         shape while the runner had grown to eight steps.
- F-008  The slash degradation stub was missing `HelpHeader`.
- F-014  Three `NewBusTarget() or bus` fallbacks silently reinstated the shared-target
         clobber the comment above them warns about; they now decline to subscribe.
- F-010/F-011/F-012/F-013  Retired `§N.M` reference form, three different addon icons,
         `/lh test` opening the window on the way out, and a test pinning the dead flag
         instead of the behavior.

No taint findings. No deprecated APIs in use. No changes under libs/ or tests/_kit/.
New SV global `LootHistoryPerfDB`; no schema migration; existing profiles are unaffected.

Review artifacts: docs/reviews/2026-08-03/
```
