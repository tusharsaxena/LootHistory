# Ka0s Loot History — Review Findings (2026-08-03)

**Verdict: minor issues.** Nothing blocks a ship and nothing is a taint, data-loss or security
problem. Three user-visible functional bugs and two measurable hot paths are worth fixing before the
next release; the rest is maintainability and polish.

**Standards cross-check: performed.** The living Ka0s WoW Addon Standard was resolved at
**v2.17.1 (2026-08-03)** and every fix direction below was vetted against it. Rules are cited as
`filename-§N`.

**Scope reviewed:** the whole repo — `core/`, `defaults/`, `settings/`, `modules/`, `locales/`,
`tests/`, the TOC, `.pkgmeta`, `.luacheckrc`, `.gitattributes`, `README.md` and `docs/`.
`libs/` and `tests/_kit/` were read but treated as read-only vendored copies.

---

## Areas found clean (stated so the silence is not mistaken for an unread area)

- **Taint / combat lockdown.** The addon calls no protected API. It creates no
  `SecureActionButtonTemplate`, sets no secure attributes, and never `:Show`/`:Hide`/`:SetPoint`s a
  secure frame. Every Blizzard-function hook goes through `hooksecurefunc`, never a raw `:Hook`
  (`core/Compat.lua:31,33,53`; `modules/Attribution.lua:348-360`). No value from a protected API is
  bound to a local and re-read; the secret-safe stringifier is adopted from `LibKa0s-Core-1.0` and
  published as `NS.SafeToString` (`core/CoreSetup.lua:91-92`). `Settings.RegisterCanvasLayout*` runs
  from `OnInitialize` (`settings/Panel.lua:704-784`), which is what options-ui-§9 requires — the
  registration is eager, the bodies are lazy.
- **Deprecated APIs.** Every varying or deprecated call is funnelled through the single
  `core/Compat.lua` module as compat-§1 requires. `GetSpellInfo` (`core/Compat.lua:75`) and
  `GetAddOnMetadata` (`:477`) appear only as guarded fallbacks *behind* their `C_Spell` / `C_AddOns`
  successors. `C_Item`, `C_Container`, `C_UnitAuras`-era shapes are used correctly; `BackdropTemplate`
  is passed on every `SetBackdrop` frame.
- **Chat printer.** No raw `print(` bypasses the prefix helper. Every `print` call site is the
  file-scope `local print = NS.Print` shadow (`settings/Schema.lua:5`, `settings/Slash.lua:4`,
  `settings/Panel.lua:4`, `modules/Browser.lua:5`), i.e. the cyan `[LH]` tag slash-commands-§4
  mandates.
- **Slash dispatcher parity.** All 14 verbs in `NS.COMMANDS` (`settings/Schema.lua:213-245`) are
  documented in `README.md:72-83`, and every documented verb exists in the table. No drift in either
  direction.
- **Widget hygiene.** No `setmetatable` is applied to a Blizzard widget anywhere in addon code.
  Rows, menu buttons, chart bars and AH-table slots are all pooled and reused
  (`modules/BrowserTable.lua:581-676,720-727`; `modules/Analytics.lua:218-228`;
  `settings/Panel.lua:529-567`); no `CreateFrame` sits in a per-event or per-update path.
- **Dead code.** A cross-file sweep of every `function X.y` / `function X:y` export found no
  zero-caller function. The three that look unreferenced (`OnInitialize`, `OnEnable`, `OnEnterWorld`)
  are AceAddon lifecycle / string-dispatched.
- **Suite.** `lua tests/run.lua` is green: **563 passed, 0 failed**, including the vendored-payload
  gate (`tests/test_vendor_sync.lua`) which proves `libs/LibKa0s/` and `tests/_kit/` are byte-exact
  for the LibKa0s tag `README.md` names — library-stack-§7's vendor-sync MUST is genuinely enforced
  here, not merely claimed.

## Upstream findings

**None.** No defect was found in `libs/` or `tests/_kit/`. One *additive* library improvement is
suggested in `02_PROPOSED_CHANGES.md` (an `O.MarkDirty(ctx)` seam for `LibKa0s-Options-1.0`), but it
is an enhancement, not a bug, and the fix for F-001 does **not** depend on it — a compliant host-side
fix using the library's existing public API is available today.

---

## High

### F-001 · The Filters settings page never rebuilds after an off-screen change `[design]`
**Where:** `settings/Panel.lua:321` (write), `settings/Panel.lua:138` (clear); library key at
`libs/LibKa0s/Options.lua:455,464`.

**Problem:** `buildFilters`' bus handler sets the host's own `ctx.dirty = true` when the page is
hidden, but **nothing anywhere reads `ctx.dirty`** — `runRebuilders` only clears it. The library's
lazy re-render is keyed on a *different* field, `ctx._dirty`, which the host never sets, so
`SetRenderer`'s `OnShow` takes its `if ctx._rendered and not ctx._dirty then return end` early exit.

**Impact:** Blacklist an item from the History window's right-click menu (or run `/lh resetall`)
while the settings panel is closed, then reopen **Settings ▸ Filters** — the id list is stale and the
change is invisible until something else forces a structural refresh. This is exactly the behavior
options-ui-§11 makes a MUST ("flag every other rendered panel **dirty** and rebuild it lazily on its
next `OnShow`").

**Fix direction:** Drive the hidden-page branch through the library's existing public structural
refresh rather than a private flag. Do **not** "fix" it by re-rendering every page on every mutation
— that is anti-pattern #39 and options-ui-§11's explicit MUST NOT.

### F-002 · Live-stats bus handler keeps a widget the next render releases `[design]`
**Where:** `settings/Panel.lua:102-130` (`refreshStats` + the `P.__ev` registration).

**Problem:** `P.__ev` is created once, guarded by `if not P.__ev`, and closes over the `refreshStats`
of the **first** render, which in turn closes over that render's `statsLabel`. `renderGeneral` is
declared through `O.SetRenderer` and therefore *can* be re-run (any `O.RefreshScalars()` while the
General page is hidden sets the library's `_dirty` at `libs/LibKa0s/Options.lua:464`, and the next
`OnShow` re-renders). `O.ClearScroll` then releases `statsLabel` back into the AceGUI widget pool.

**Impact:** After such a re-render, the next `HistoryChanged`/`RecordAdded` writes the storage line
into a **recycled AceGUI Label** that now belongs to some other control, while the visible stats line
goes stale. Same class of hazard options-ui-§11 names ("releasing a page's widgets MUST also drop
that page's refreshers") one level further out — a *bus* subscription outliving the widgets it
captured. Note `buildFilters`' equivalent subscription is safe, because it re-reads `ctx.rebuilders`
rather than capturing a widget.

**Fix direction:** Make the subscription render-agnostic — have it call into the current render's
state (as `buildFilters` already does) rather than capture a widget instance.

### F-003 · Test-mode rows expose destructive actions against live data `[ux]`
**Where:** `modules/BrowserTable.lua:975-1001` (`ShowRowMenu`, no `testMode` guard); synthetic ids at
`modules/BrowserTable.lua:370`; `Database:Delete` at `core/Database.lua:591`.

**Problem:** `/lh test` swaps the *read* path to the synthetic dataset (`NS.State.testRecords`,
`core/Database.lua:240`) but the row context menu is unguarded, and the write paths still target live
storage:
- **"Blacklist item"** on a synthetic row calls `NS.Filters:AddBlacklist(record.itemID)` with a
  fabricated id in the 100001–100030 range, permanently writing junk into the user's real
  `db.global.blacklist`.
- **"Delete"** calls `Database:Delete`, which iterates `NS.db.global.history` — never
  `ActiveHistory()` — so it removes nothing, fires `HistoryChanged`, repaints, and the row is still
  there.

**Impact:** Silent corruption of a real user setting from a feature whose whole promise is that it is
"temporary, never saved" (`README.md:141`), plus a visibly broken Delete in preview mode.

**Fix direction:** Gate the mutating menu entries on `not self.testMode` (disabled, with the existing
`enabled = false` styling already in the menu builder), so preview mode stays read-only.

---

## Medium

### F-004 · Every looted item triggers eight full history scans while the browser is open `[perf]`
**Where:** `modules/Browser.lua:1311` → `:1292` `OnHistoryChanged` → `:696` `RefreshFilterOptions`
and `:689` `UpdateDbSize`; `core/Database.lua:634` `StorageStats` → `:621` `estimateRecordBytes`.

**Problem:** `RecordAdded` is wired straight to `OnHistoryChanged`, which rebuilds seven data-driven
dropdown option lists — `boundOptions`, `qualityOptions`, `sourceOptions`, `typeOptions`,
`subtypeOptions`, `charOptions`, `zoneOptions` — each a full `ipairs` pass over the entire history,
then recomputes `StorageStats`, an eighth full pass that **allocates a seven-element table per
record** (`local strFields = { ... }`) purely to sum string lengths.

**Impact:** With the window open during a mass-loot pull (a raid boss, a bag of Mythic+ chests), each
looted item costs 8×O(n) plus n table allocations, on top of the `BrowserTable:Refresh` filter+sort
that also runs. On a multi-thousand-row history this is felt as a hitch per loot line, and the
garbage is pure churn.

**Fix direction:** Batch/debounce the record-added repaint, and make the byte estimate allocation-free
(sum the string lengths directly). No new deviation: the shared filter singleton and the
one-sender-per-message bus invariant (architecture-§5, message-bus) both stay intact.

### F-005 · `Analytics:Layout` runs unthrottled on every resize frame `[perf]`
**Where:** `modules/Analytics.lua:432` (`scroll:SetScript("OnSizeChanged", function() Analytics:Layout() end)`),
`:509` `Layout`, `:880` `LayoutCharts`.

**Problem:** `Layout` re-runs `LayoutCharts`, which releases and re-acquires 35 widget pools, re-sorts
every breakdown, rebuilds palette maps, and re-anchors several hundred FontStrings/textures. It is
bound directly to `OnSizeChanged`, which fires continuously while the user drags the History
window's resize grip (`modules/Browser.lua:1174`) with the Insights tab visible.

**Impact:** A visible stall for the duration of a resize drag; the heavier the history, the worse.

**Fix direction:** Coalesce the relayout (a next-frame / short `C_Timer` throttle, as
`settings/OptionsSetup.lua:95` already does for the color-picker drag), keeping the final layout
exact. events-frames-taint-§7's throttling discipline applies; no `OnUpdate` handler is introduced.

### F-006 · The performance harness is vendored and loaded but never wired `[design]`
**Where:** `libs/LibKa0s/LibKa0s.xml:8-9` (Perf + PerfPanel loaded), `LootHistory.toc:31`; absent:
`core/PerfSetup.lua`, a `perf` row in `NS.COMMANDS` (`settings/Schema.lua:213-245`),
`LootHistoryPerfDB` in `LootHistory.toc:7`, `docs/performance.md`, `docs/perf-runs/`.

**Problem:** The whole-folder vendor rule (library-stack-§7) correctly brings `Perf.lua` (982 lines)
and `PerfPanel.lua` (247 lines) into the TOC's load list, but no instance is ever created. The
addon's own suite confirms the gap — `tests/test_libka0s.lua` asserts *"the four adopted majors"*,
i.e. Core, DebugLog, Slash and Options only.

**Impact:** Two directly measurable hot paths were found in this review (F-004, F-005) and the addon
has no sanctioned way to quantify either, in-client, in a form a user can paste back. It also parses
~1,200 lines of dormant library at every login. performance-§1 makes the wiring a **MUST**.

**Fix direction:** Adopt `LibKa0s-Perf-1.0` per performance-§1 — one `core/PerfSetup.lua` descriptor
plus a degradation stub, the reserved `perf` verb dispatched through the addon's own `NS.COMMANDS`
(slash-commands-§2/§3), `LootHistoryPerfDB` declared second in the TOC (toc-file-§1/§2), and buckets
bracketed around the two paths above. **MUST NOT** hand-roll a private probe or copy the library's
logic locally.

### F-007 · AH capture/priority defaults are declared twice and already disagree `[design]`
**Where:** `defaults/Global.lua:29-40` vs `core/Constants.lua:142-153`.

**Problem:** `defaults.global.settings.auction.capture` and `.priority` are hand-written literals that
duplicate `C.AUCTION_CAPTURE_DEFAULT` and `C.AUCTION_PRIORITY_DEFAULT`. The `capture` copies match
today; the `priority` copy is **already short by four tags** (it omits `tsm:dbhistorical`,
`tsm:dbrecent`, `tsm:dbregionhistorical`, `tsm:dbregionsaleavg`). They only converge because
`AuctionPrice:ReconcilePriority` (`modules/AuctionPrice.lua:121-136`) re-appends the missing tags in
`AUCTION_KEYS` order at render time.

**Impact:** Two sources of truth for one default. Edit `Constants` alone and a fresh install gets one
set while `/lh reset settings.auction.capture` and the AH page's Defaults button give another —
divergence that surfaces as an inexplicable ranking change, not as an error.

**Fix direction:** Have `defaults/Global.lua` reference the `Constants` tables (it already loads
after `core/Constants.lua` per `LootHistory.toc:24,37`), keeping the schema-as-single-source rule of
architecture-§5.

### F-008 · Degradation-stub surface does not match the live surface `[design]`
**Where:** `settings/Slash.lua:210` (live `Sl.HelpHeader`) vs `settings/Slash.lua:138-149` (the
`if not lib` stub, which omits it).

**Problem:** The `LibKa0s-Slash-1.0` degradation stub answers every other member — `FormatKV`,
`HelpRows`, `LandingRows`, `BuildListLines`, `PrintHelp`, the five `Cli*` verbs and `CliResetAll` —
but not `HelpHeader`. The file's own comment states the stub's contract as *"every verb the
dispatcher would have owned has to answer with an honest line rather than a nil-index error."*

**Impact:** Latent rather than live: `HelpHeader` has no production caller today (only
`tests/test_slash.lua:212,233,323`, which always load the real library). But it is on the published
surface, so the first host or doc snippet to call it in a degraded install gets a nil-index error at
a rarer point than a load-time failure would have been.

**Fix direction:** Either add the member to the stub or stop publishing it — but keep the two sides
symmetric. Do **not** re-implement the library's header format in the stub; a stub that copies a
library's line format is the copy that goes stale.

### F-009 · The shipped schema stamp and its comment are frozen at the initial shape `[design]`
**Where:** `defaults/Global.lua:6-10` vs `core/Database.lua:13-118`.

**Problem:** The default is still `schemaVersion = 1` and the comment beside it describes only *"a
v1→v2 migration that strips the retired per-record `viaWhitelist` field and bumps the stamp to 2"*,
while `NS:RunMigrations` now ships **eight** steps (v1→v8) plus a revision-armed bound repair
(`core/Database.lua:120-144`).

**Impact:** Every brand-new database runs eight no-op migration passes at first login, and — worse —
the comment actively misdescribes the migration set, which is precisely the file a maintainer reads
first when adding step nine. savedvariables-§1 wants the stamp and its migration runner to be the
readable single seam.

**Fix direction:** Ship the current shape as the default (and let the runner remain the idempotent
seam for existing DBs), and correct the comment to describe the set rather than one step.

---

## Low

### F-010 · Stale standard reference uses the retired global numbering `[naming]`
**Where:** `settings/OptionsSetup.lua:99` — `-- Ka0s standard §3.4: one LibStub resolution, ...`.
The global `§N.M` scheme was retired in favor of `filename-§N`; the whole repo otherwise uses the
current form (e.g. `settings/Schema.lua:52`, `modules/Collector.lua:8`). One stale reference is
enough to teach the next reader the wrong convention.
**Fix direction:** Restate as the correct `filename-§N` reference.

### F-011 · Three different marks for one addon `[ux]`
**Where:** `modules/Browser.lua:1258` (`Interface\Icons\INV_Misc_Bag_08` for the minimap launcher),
`LootHistory.toc:6` (`inv_holiday_christmas_present_03` as `IconTexture`),
`settings/Panel.lua:23` (`media/logos/loothistory.logo.tga` on the landing page). A user sees a bag
on the minimap, a wrapped present in the AddOns list, and the real logo in Settings.
**Fix direction:** Pick one mark (the shipped logo is the obvious candidate) and use it in all three
places. layout-§3 already gives `media/logos/` as the home for it.

### F-012 · `/lh test` forces the window open on the way out of test mode `[ux]`
**Where:** `modules/BrowserTable.lua:418` — `if NS.Browser and NS.Browser.Show then NS.Browser:Show() end`
runs unconditionally in `ToggleTestMode`. Clearing test mode from chat with the window closed pops
the window open, which is not what "run it again to clear" (`README.md:141`) promises.
**Fix direction:** Only show the window when *entering* test mode.

### F-013 · The suite pins the dead flag instead of the behavior `[testability]`
**Where:** `tests/test_panel.lua:283-286` — sets `NS.Panel.filters.dirty = true` and re-shows, with
the comment *"drive the structural rebuild the page registers"*. That flag is the one F-001 shows
nothing reads, which is exactly why F-001 survived a 563-case suite.
**Fix direction:** Assert the observable outcome (an off-screen list change is visible on the next
open) rather than the host's private bookkeeping. testing-§8's principle — verify through the real
path, not a hand-set flag — applies.

### F-014 · `NewBusTarget() or bus` silently reinstates the clobber it warns about `[design]`
**Where:** `modules/Collector.lua:217`, `modules/Browser.lua:1308`, `modules/Analytics.lua:657` —
all three read `NS.NewBusTarget() or NS.bus`, three lines under a comment explaining that sharing the
bus-as-self target makes CallbackHandler drop all but the last registrant of a message.
`NS.NewBusTarget` returns `nil` only when AceEvent is unresolvable (`core/LootHistory.lua:20-26`).
Unreachable today (AceEvent is a mandatory embed), but the fallback is the failure mode, not a
mitigation of it.
**Fix direction:** Treat a `nil` target as "do not subscribe" rather than "subscribe unsafely".

---

## Finding index

| ID | Severity | Tag | Location |
|---|---|---|---|
| F-001 | High | `[design]` | `settings/Panel.lua:321` |
| F-002 | High | `[design]` | `settings/Panel.lua:122-130` |
| F-003 | High | `[ux]` | `modules/BrowserTable.lua:975-1001` |
| F-004 | Medium | `[perf]` | `modules/Browser.lua:1292-1311`, `core/Database.lua:621` |
| F-005 | Medium | `[perf]` | `modules/Analytics.lua:432` |
| F-006 | Medium | `[design]` | `libs/LibKa0s/LibKa0s.xml:8-9`, `LootHistory.toc:7,31` |
| F-007 | Medium | `[design]` | `defaults/Global.lua:29-40` |
| F-008 | Medium | `[design]` | `settings/Slash.lua:138-149,210` |
| F-009 | Medium | `[design]` | `defaults/Global.lua:6-10` |
| F-010 | Low | `[naming]` | `settings/OptionsSetup.lua:99` |
| F-011 | Low | `[ux]` | `modules/Browser.lua:1258`, `LootHistory.toc:6` |
| F-012 | Low | `[ux]` | `modules/BrowserTable.lua:418` |
| F-013 | Low | `[testability]` | `tests/test_panel.lua:283-286` |
| F-014 | Low | `[design]` | `modules/Collector.lua:217` + 2 |
