# Ka0s Loot History — Proposed Changes (HLD + LLD), 2026-08-03

Derived from `01_FINDINGS.md`. Change IDs are `C-nnn`; each names the finding IDs it closes.

**Standard resolved: v2.17.1 (2026-08-03)**, fetched from
`https://github.com/tusharsaxena/WowAddonStandards` (index + every section file discovered from its
Sections map). Every change below was checked against it; rules are cited as `filename-§N`. This is a
**guardrail on remediation, not a compliance audit** — pre-existing deviations unrelated to these
changes are deliberately not enumerated here (that is `/wow-addon:standards-audit`'s job).

---

## HLD — themes

### Theme A · Make the panel's refresh contract the library's, not a private shadow of it
**Covers:** F-001, F-002, F-013.

`settings/Panel.lua` grew its own re-render bookkeeping (`ctx.dirty`, `ctx.rebuilders`,
`runRebuilders`) alongside the one `LibKa0s-Options-1.0` already owns (`ctx._dirty`, `ctx._renderFn`,
`ctx.refreshers`). The two never met: the host writes a flag the library does not read, and the
library reads a flag the host does not write. Everything downstream of that — the stale Filters page,
the widget-capturing bus handler, and a test that pins the private flag instead of the outcome — is
one seam mismatch showing up three times.

The direction is to **let the library own WHEN a page redraws** (which is what options-ui-§11 and the
module's own docstring say it is for) and reduce the host's bookkeeping to *what* to draw. The host's
`rebuilders` list stays — it is a genuine host concept (structural sub-lists the library has no widget
maker for) — but the trigger for running it becomes the library's public refresh entry point.

**Alternatives considered and rejected:**
- *Re-render every page on every mutation.* Simplest, and explicitly forbidden — anti-pattern #39 and
  options-ui-§11's MUST NOT. Rejected outright.
- *Set `ctx._dirty` directly from the host.* Reaches into the library's private field. Works today,
  breaks silently on any upstream rename, and is a fork of the contract by another name. Rejected.
- *Add `O.MarkDirty(ctx)` to `LibKa0s-Options-1.0` and use it.* The cleanest long-term shape, and it
  is recorded below as an **optional additive upstream change** — but it must not gate this fix, and
  the library already exposes a correct public path (`O.RefreshAllPanels`, whose `refreshCtx` sets
  `_dirty` for every hidden ctx: `libs/LibKa0s/Options.lua:460-472`). Adopted as the *primary* fix;
  the upstream additive is a follow-up nicety.

**Trade-off:** `O.RefreshAllPanels()` structurally re-renders every *shown* page, not just the one
that changed. This addon has three sub-pages and the Settings window shows exactly one at a time, so
the cost is one page re-render — well inside the budget anti-pattern #39 is about (it is about
rebuilding all *N visited* pages, which `refreshCtx`'s `isShown` gate already prevents).

### Theme B · Preview mode must be read-only
**Covers:** F-003.

`/lh test` swapped the read path cleanly (`Database:ActiveHistory`) but left the write paths pointed
at live storage. The fix is not to make the writes work against synthetic data — that would be a
second, parallel storage model for a preview feature — but to make preview mode honestly read-only,
which is what `README.md` already promises the user. preview-mode's whole premise is placeholder data
that costs the user nothing.

**Alternative rejected:** routing `Database:Delete`/`Filters:AddBlacklist` through `ActiveHistory()`
so test rows behave "for real". That would let a preview action mutate `NS.State.testRecords` and
then vanish on the next toggle, which is a worse lie than a disabled menu item.

### Theme C · Take the per-loot and per-resize repaint costs off the hot path
**Covers:** F-004, F-005.

Two paths do full-dataset work at a frequency set by something the user is doing continuously
(looting, dragging a resize grip). Both are fixed the same way: coalesce the repaint, and remove
gratuitous allocation from the O(n) pass that survives. Neither introduces an `OnUpdate` handler.

### Theme D · Wire the measurement harness the standard mandates
**Covers:** F-006, and provides the evidence for Theme C.

`LibKa0s-Perf-1.0` is already vendored and already loaded; only the ~40 lines of host wiring are
missing. performance-§1 makes that wiring a MUST, and it is what turns Theme C from "this looks
expensive" into a number the user can paste back.

**Alternative rejected:** a small private timer around the two paths. performance-§1: *"Addons MUST
NOT hand-roll a private probe."*

### Theme E · One source of truth for defaults, and honest comments
**Covers:** F-007, F-009, F-010.

Three places where the code and its own description have drifted apart. All are contained edits.

### Theme F · Surface symmetry and polish
**Covers:** F-008, F-011, F-012, F-014.

---

## Upstream change-set

**No upstream defect was found.** Nothing under `libs/` or `tests/_kit/` needs a fix, and **no change
in this document targets a path under either directory.**

One **optional additive** is worth carrying to the library repo:

| Repo | File | Change | Version | Consumer action |
|---|---|---|---|---|
| `LibKa0s` | `Options.lua` | Add a public `O.MarkDirty(ctx)` that sets `ctx._dirty = true` when the ctx has a renderer and is not shown — the narrow half of `refreshCtx`, so a host with one changed page need not structurally refresh every shown one. Additive; no existing behavior changes. | Bump `LibKa0s-Options-1.0`'s **file minor** (per-file, never in lockstep — library-stack-§7) and add the matching changelog entry. | Re-vendor the **whole** `libs/LibKa0s/` folder into this addon (and every other consumer) as **its own commit**, then optionally switch C-001 from `O.RefreshAllPanels()` to `O.MarkDirty(ctx)`. |

This is **not** a local edit to `libs/LibKa0s/Options.lua`. A patch applied here is reverted by the
next whole-folder copy, and the behavior comes back as a regression with no cause in this repo's
history. C-001 below is deliberately written so it needs none of this.

---

## LLD — change-set

### C-001 · Route hidden-page structural refreshes through the library (F-001, F-013)
**Files:** `settings/Panel.lua`, `tests/test_panel.lua`.

`buildFilters`' bus handler currently branches on visibility itself and writes a flag nobody reads.
Hand the decision to the library, which already makes exactly this call.

```lua
-- settings/Panel.lua — buildFilters, before
local onChange = function()
  if ctx.panel:IsShown() then runRebuilders(ctx) else ctx.dirty = true end
end

-- after
local onChange = function()
  if ctx.panel:IsShown() then
    runRebuilders(ctx)
  else
    -- Hand the lazy re-render to the library: refreshCtx flags a hidden ctx `_dirty`, which is the
    -- field SetRenderer's OnShow actually reads (options-ui-§11). The host's own `dirty` field was
    -- never read by anything.
    O.RefreshAllPanels()
  end
end
```

Then delete the now-vestigial `ctx.dirty = false` line from `runRebuilders` (`settings/Panel.lua:138`)
and the three `ctx.rebuilders = {}` initializers keep their current role unchanged.

Because `renderFilters` is the ctx's `_renderFn`, the library's re-render calls it, which calls
`buildFilters` **and** `runRebuilders` — so the list repaints exactly once on the next `OnShow`.

**Test change (F-013):** replace the `NS.Panel.filters.dirty = true` shortcut at
`tests/test_panel.lua:283-286` with the real sequence — render the page, hide the panel, mutate the
list through `NS.Filters:AddBlacklist`, re-show, and assert the new id appears. Add a regression case
that fails on the old code.

**Risk:** low. `O.RefreshAllPanels` re-renders shown pages structurally; with one page shown at a
time that is a single re-render, and the `isShown` gate at `libs/LibKa0s/Options.lua:463` keeps hidden
pages lazy.

**Standards conformance:** implements options-ui-§11's dirty-then-lazy-rebuild MUST using the
library's public API. The rejected alternative (unconditional `RefreshAllPanels` on every mutation,
shown or not) would have violated the same section's MUST NOT and anti-pattern #39.

### C-002 · Make the history-stats subscription render-agnostic (F-002)
**File:** `settings/Panel.lua` (`renderHistory`, `P.__ev`).

Stop capturing the widget. Park the current render's updater on the ctx and have the one-time
subscription call whatever is parked there now — the same shape `buildFilters` already uses for
`runRebuilders`.

```lua
-- before: the subscription closes over this render's refreshStats -> statsLabel
local onChange = function() if ctx.panel:IsShown() then refreshStats() end end

-- after: each render publishes its updater; the subscription reads the current one
ctx._statsRefresh = refreshStats
...
local onChange = function()
  if ctx.panel:IsShown() and ctx._statsRefresh then ctx._statsRefresh() end
end
```

`refreshStats` stays on `ctx.refreshers` as it is today, so the library's scalar refresh path is
unchanged.

**Risk:** low; no behavior change on the first render, which is the only path exercised today.

**Standards conformance:** satisfies options-ui-§11's "releasing a page's widgets MUST also drop that
page's refreshers" at the bus-subscription level. Rejected alternative: re-creating `P.__ev` on every
render — that leaks a CallbackHandler registration per render, which is the opposite defect.

### C-003 · Make preview mode read-only (F-003)
**File:** `modules/BrowserTable.lua` (`ShowRowMenu`).

The menu builder already supports a disabled state (`enabled = false` → gray label, mouse off). Use
it for the three mutating entries while `self.testMode` is true, and add a trailing hint so the
disabled state is legible rather than mysterious.

```lua
local preview = self.testMode
local items = {
  { label = "Link to chat",        enabled = record.itemLink ~= nil, fn = ... },
  { label = "Blacklist item",      enabled = not preview and record.itemID ~= nil,     fn = ... },
  { label = "Blacklist currency",  enabled = not preview and record.currencyID ~= nil, fn = ... },
  { label = "|cffff5555Delete|r",  enabled = not preview,                              fn = ... },
}
```

**Risk:** none to live data; the only behavior change is in test mode.

**Standards conformance:** preview-mode's placeholder-data contract. No new deviation; the
alternative (routing writes at `ActiveHistory()`) was rejected in Theme B.

### C-004 · Coalesce the record-added repaint and de-allocate the byte estimate (F-004)
**Files:** `modules/Browser.lua`, `core/Database.lua`.

1. **Debounce.** In `B:Enable`, keep `HistoryChanged` immediate (it is user-initiated: delete, prune,
   filter edit) but route `RecordAdded` through a short coalescing timer so a burst of loot lines
   costs one repaint:

```lua
local pendingRepaint
local function scheduleRepaint()
  if pendingRepaint then return end
  pendingRepaint = true
  if C_Timer and C_Timer.After then
    C_Timer.After(0.2, function() pendingRepaint = nil; B:OnHistoryChanged() end)
  else
    pendingRepaint = nil; B:OnHistoryChanged()
  end
end
```

2. **Allocation.** Rewrite `estimateRecordBytes` (`core/Database.lua:621-629`) to sum the string
   fields directly instead of building a throwaway array per record:

```lua
local function addLen(n, s) return type(s) == "string" and (n + #s) or n end
local function estimateRecordBytes(r)
  local n = RECORD_OVERHEAD
  n = addLen(n, r.itemLink);    n = addLen(n, r.itemName)
  n = addLen(n, r.zone);        n = addLen(n, r.subzone); n = addLen(n, r.char)
  n = addLen(n, r.itemType);    n = addLen(n, r.itemSubType)
  return n
end
```

**Risk:** the debounce makes the footer/dropdowns lag a looted item by up to 0.2s while the window is
open. Acceptable and invisible in practice; `HistoryChanged` (every user-initiated change) stays
instant.

**Standards conformance:** events-frames-taint-§7's throttling discipline; no `OnUpdate` handler is
added, so nothing approaches anti-pattern territory. The message-bus one-sender-per-message invariant
is untouched — this changes only the *consumer* side.

### C-005 · Throttle the Insights relayout on resize (F-005)
**File:** `modules/Analytics.lua`.

```lua
-- before
scroll:SetScript("OnSizeChanged", function() Analytics:Layout() end)

-- after: coalesce a resize drag into one relayout per tick
local layoutQueued
scroll:SetScript("OnSizeChanged", function()
  if layoutQueued then return end
  layoutQueued = true
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function() layoutQueued = nil; Analytics:Layout() end)
  else
    layoutQueued = nil; Analytics:Layout()
  end
end)
```

**Risk:** the charts settle one frame after the drag rather than during it. Headless tests call
`Analytics:Layout` directly and are unaffected; the `C_Timer`-absent branch keeps the synchronous
path for the mock.

**Standards conformance:** same as C-004.

### C-006 · Wire `LibKa0s-Perf-1.0` (F-006)
**Files:** new `core/PerfSetup.lua`; `LootHistory.toc`; `settings/Schema.lua` (`NS.COMMANDS`);
`.luacheckrc`; new `docs/performance.md`, `docs/perf-runs/README.md`; new `tests/perf.lua`;
`tests/test_libka0s.lua`.

- `core/PerfSetup.lua`: `local lib = LibStub and LibStub("LibKa0s-Perf-1.0", true)`, then
  `NS.Perf = lib:New(descriptor)` only `if lib`, else a stub carrying **every member this addon
  calls** (`Perf.on`, `Perf.Note`, plus whatever the `perf` verb and the show-decision ladder touch).
  Positioned in the TOC's `# Core` section **before** any consumer that takes `local Perf = NS.Perf`
  at file scope — i.e. before `modules/Browser.lua` and `modules/Analytics.lua`.
- Declare buckets in the descriptor, in report order. Start with the two paths this review measured:
  `historyRepaint` (the `OnHistoryChanged` fan-out) and `insightsLayout` (`LayoutCharts`), plus
  `lootCapture` around `Collector:OnChatMsgLoot`.
- Bracket sites use the exact gated form: `local t0 = Perf.on and debugprofilestop()` … `if t0 then
  Perf.Note("<bucket>", debugprofilestop() - t0) end`. Nothing allocates, concatenates or calls
  inside a dormant bracket.
- `NS.COMMANDS` gains `{ "perf", "Performance capture", function(rest) ... end }`, dispatched through
  the addon's own table — **never** registered by the library.
- `LootHistory.toc`: `## SavedVariables: LootHistoryDB, LootHistoryPerfDB` (exactly two, in order).
- `.luacheckrc`: add `debugprofilestop` to `read_globals` and `LootHistoryPerfDB` to `globals`.
- `tests/perf.lua` is the offline scenario runner — **outside** the green gate, asserting only
  deterministic quantities (call counts, bytes allocated), never wall-clock, and its scenarios are
  **not** counted in `--list` or the `[tests]` badge.
- Integration coverage goes in the existing suite, not a duplicate of the library's own: descriptor
  well-formed, **every declared bucket actually reached**, suspend genuinely inert, and the degraded
  path verified by loading the addon with the lib absent.

**Risk:** medium — the largest change in this set, and it touches the TOC and the SV declaration.
It is nonetheless additive: nothing the addon does today becomes wrong.

**Standards conformance:** performance-§1 (vendor + one instance + descriptor + stub, no shared
frame), §2 (bracket idiom), §3 (declared buckets, no unreached bucket), §4 (`perf` reserved verb via
`NS.COMMANDS`), §5 (`<Addon>PerfDB` outside the AceDB tree), §6 (suspend/resume), §9 (offline runner
outside the gate), documentation-§3 (`docs/performance.md` + `docs/perf-runs/README.md`),
toc-file-§1/§2 (two SV globals, in order), toc-file-§5 (`core/PerfSetup.lua` before its consumers),
slash-commands-§2/§3, lint, testing-§7/§8. **Explicitly rejected:** a private timer (performance-§1
MUST NOT) and any local copy of the library's logic.

### C-007 · One source of truth for the AH defaults (F-007)
**File:** `defaults/Global.lua`.

`defaults/Global.lua` loads after `core/Constants.lua` (`LootHistory.toc:24,37`), so it can reference
the constants directly instead of restating them:

```lua
auction = {
  enabled  = true,
  capture  = NS.Constants.AUCTION_CAPTURE_DEFAULT,
  priority = NS.Constants.AUCTION_PRIORITY_DEFAULT,
},
```

AceDB deep-copies table defaults into the saved-variables tree on first access, and
`Schema:Default` already `deepcopy`s (`settings/Schema.lua:152-157,185`), so no live reference to a
constant is ever stored — the hazard that comment warns about is already handled on both paths. The
priority array becomes complete on a fresh install rather than being back-filled at first render.

**Risk:** low. `ReconcilePriority` remains as the tolerant path for existing DBs.

**Standards conformance:** savedvariables-§1 (defaults + migration runner), architecture-§5
(schema-as-single-source). Rejected alternative: deleting the constants and keeping the literals —
that would break `Schema:Default`, the AH page's Defaults button and `ReconcilePriority`, all of
which read the constants.

### C-008 · Ship the current schema shape and correct its comment (F-009)
**File:** `defaults/Global.lua:6-10`.

Set the default `schemaVersion` to the current head (`8` at the time of writing) and rewrite the
comment to describe the runner as a set of steps with a pointer to `core/Database.lua`, rather than
narrating one long-superseded step. `NS:RunMigrations` is unchanged and remains the idempotent seam
for existing databases — a fresh DB now simply starts current.

**Risk:** low, but it must land **with** a suite case asserting that a fresh DB reports the head
version and that a `schemaVersion = 1` DB still walks every step.

**Standards conformance:** savedvariables-§1.

### C-009 · Correct the retired standard reference (F-010)
**File:** `settings/OptionsSetup.lua:99`. Replace `Ka0s standard §3.4` with the current
`filename-§N` form for the rule it means (the one-LibStub-resolution rule in `architecture`). Purely
a comment.

### C-010 · One mark for the addon (F-011)
**Files:** `modules/Browser.lua:1258`, `LootHistory.toc:6`.

Point the LibDataBroker launcher and the TOC `IconTexture` at the same artwork the settings landing
page uses. If a square icon-sized asset is needed, add it under `media/logos/` (layout-§3 already
names that folder).

**Risk:** cosmetic; a user's minimap-button position is keyed on the LDB name, not the icon, so
nothing moves.

### C-011 · `/lh test` should not open the window on the way out (F-012)
**File:** `modules/BrowserTable.lua:418`.

```lua
-- before
if NS.Browser and NS.Browser.Show then NS.Browser:Show() end
-- after
if self.testMode and NS.Browser and NS.Browser.Show then NS.Browser:Show() end
```

`OnDatasetChanged` still runs on both edges, so the badge, dropdowns and footer stay correct.

### C-012 · Close the stub/live surface gap (F-008) and the bus-target fallback (F-014)
**Files:** `settings/Slash.lua`, `modules/Collector.lua`, `modules/Browser.lua`,
`modules/Analytics.lua`.

- Add `Sl.HelpHeader` to the degraded branch, answering with the same `unavailable()` line the other
  library-owned verbs give. **Do not** reproduce the library's header format in the stub — a stub
  that copies a library's line format is the copy that goes stale.
- Replace the three `NS.NewBusTarget() or NS.bus` fallbacks with an explicit refusal:

```lua
local ev = NS.NewBusTarget()
if not ev then return end   -- no AceEvent: do not subscribe on the shared bus-as-self
self.__ev = ev
```

**Risk:** none in practice (AceEvent is a mandatory embed, so the branch is unreachable); it removes
a latent clobber rather than changing live behavior.

**Standards conformance:** architecture-§5's closed message bus, and the degradation-stub contract in
library-stack-§7 / performance-§1's "a stub that omits a member is a crash moved to a rarer path".

---

## Change → finding map

| Change | Findings | Theme | Files |
|---|---|---|---|
| C-001 | F-001, F-013 | A | `settings/Panel.lua`, `tests/test_panel.lua` |
| C-002 | F-002 | A | `settings/Panel.lua` |
| C-003 | F-003 | B | `modules/BrowserTable.lua` |
| C-004 | F-004 | C | `modules/Browser.lua`, `core/Database.lua` |
| C-005 | F-005 | C | `modules/Analytics.lua` |
| C-006 | F-006 | D | `core/PerfSetup.lua` (new), `LootHistory.toc`, `settings/Schema.lua`, `.luacheckrc`, `docs/`, `tests/` |
| C-007 | F-007 | E | `defaults/Global.lua` |
| C-008 | F-009 | E | `defaults/Global.lua` |
| C-009 | F-010 | E | `settings/OptionsSetup.lua` |
| C-010 | F-011 | F | `modules/Browser.lua`, `LootHistory.toc` |
| C-011 | F-012 | F | `modules/BrowserTable.lua` |
| C-012 | F-008, F-014 | F | `settings/Slash.lua`, `modules/Collector.lua`, `modules/Browser.lua`, `modules/Analytics.lua` |
