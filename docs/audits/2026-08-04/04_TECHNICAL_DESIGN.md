# 04 — Technical Design (remediation)

How to close the gaps in `02_DEVIATIONS.md`. Keyed to deviation IDs. This document is a **plan** —
the audit changes no code.

Audited against **Ka0s WoW Addon Standard v2.17.1 (2026-08-03)**.

---

## 0 — The one decision that gates everything

**Seven of the ten MUSTs (LH-20 … LH-26) are one decision, not seven bugs.** They all follow from
`LibKa0s-Perf-1.0` being un-adopted, which is a recorded, reasoned `wont-do`
(`docs/pending/LEDGER.md:70`). Nothing in this section should be executed until the user picks a
branch, because the two branches produce opposite work.

### Branch A — adopt the wiring (conform)

`performance`'s adoption strength is **MUST for the wiring, SHOULD for coverage**, and the section
explicitly anticipates this addon's situation: "*some addons have almost no hot path*". Read that way,
Branch A is small: wire the harness, declare **one or two** honest buckets, register the verb, ship
the two docs and the offline runner. The LEDGER's first objection ("*a bucket would report a number
too small to compare*") is answered by the standard itself — coverage is a SHOULD, so a thin bucket
set is compliant.

The LEDGER's **second** objection is the real one and does not dissolve: `performance-§6` requires
`suspend` to make the addon **inert**, and for a passive loot recorder that means **not recording the
loot that drops during measurement window B**. A diagnostic that destroys the data it is measuring is
a genuine conflict with the addon's reason for existing. Branch A therefore needs an explicit answer
to it (see §1.4), and that answer is a **user decision**, not an engineering one.

### Branch B — take it upstream (change the standard)

The alternative the addon's own `CLAUDE.md` deviation rule prescribes: propose a `performance`
amendment carving out addons whose `suspend` would be **destructive** — allowing the wiring plus the
`perf` verb and `PerfDB` while permitting a declared, documented `suspend` opt-out. If accepted,
LH-20/21/22/24/25/26 stay in scope (they are cheap and unconditionally useful) and **LH-23 alone**
resolves as an accepted deviation.

**Recommendation: Branch B for LH-23, Branch A for everything else.** That closes six of the seven
MUSTs with mechanical, low-risk work and isolates the one genuine conflict for a standards decision
rather than letting it block six easy wins.

The rest of this document designs Branch A's work, since Branch B's outcome is a document change in
another repo plus a one-row LEDGER update here.

---

## 1 — The perf cluster (LH-20 … LH-26)

### 1.1 `core/PerfSetup.lua` (LH-20)

New file, on the canonical shape from `performance-§1`, modeled on the four setup files this repo
already has — same silent-lookup / descriptor / stub structure, same `NS.LIBKA0S_MISSING` cause
clause, same load-order comment block.

```lua
local addonName, NS = ...

-- ── LOAD ORDER ────────────────────────────────────────────────────────────────
--   AFTER  core/CoreSetup.lua   — `print` routes through the shared printer.
--   AFTER  core/DebugLogSetup.lua — capture lifecycle lines land on the console sink.
--   BEFORE every module taking `local Perf = NS.Perf` as a load-time upvalue.

local lib = LibStub and LibStub("LibKa0s-Perf-1.0", true)

if not lib then
  -- Degrade, not error. The hot-path gate must be a plain false field and the sink a
  -- dot-callable no-op, so a bracket costs the same one boolean test as when the lib is present.
  NS.Perf = {
    on = false,
    Note = function() end,
    OnCommand = function() return { NS.LIBKA0S_MISSING .. ", so performance capture is unavailable." } end,
    IsSuspended = function() return false end,
  }
  return
end

NS.Perf = lib:New({
  addon    = NS.name,
  version  = function() return NS.version end,
  savedVar = "LootHistoryPerfDB",              -- the NAME, not the table (LH-21)

  print    = function(line) NS.Print(line) end,          -- late-bound, per the house pattern
  debug    = function(tag, fmt, ...) if NS.Debug then NS.Debug(tag, fmt, ...) end end,
  showLog  = function() if NS.DebugLog then NS.DebugLog:Show() end end,   -- host's call (debug-logging-§12)
  applySkin = function(frame) if NS.Browser then NS.Browser:ApplySkin(frame) end end,

  buckets  = { … },                             -- §1.2
  suspend  = function() NS.Suspend() end,       -- §1.4
  resume   = function() NS.Resume()  end,
})
```

TOC placement (`LootHistory.toc`, `# Core` section): **after** `core/DebugLogSetup.lua`, **before**
`core/LootHistory.lua` — so the console sink exists when the harness logs, and so every module that
might later take `local Perf = NS.Perf` loads after it.

**Stub-coverage rule (the one that bites):** the stub must answer **every** member the addon reaches.
Once §1.3's verb exists, that set is `on`, `Note`, whatever the verb calls, and whatever the
show-decision ladder reads. Grep the call sites and close the set before shipping; a stub missing one
member is a crash moved to a rarer code path.

### 1.2 Buckets (LH-20, coverage half)

`performance-§3` requires every declared bucket be reached by a real bracket — "*a bucket that no
bracket ever reaches is a lie in every report*" — so declare **few** and bracket **all** of them. The
LEDGER's survey is accurate: eleven events, no `OnUpdate`, no ticker, three one-shot timers. Two
honest candidates:

```lua
buckets = {
  { key = "lootCapture" },                       -- the CHAT_MSG_LOOT → record path
  { key = "tableRender" },                        -- one full filter→group→sort→slice→bind pass
  { key = "tableBind", within = "tableRender" },  -- the per-row bind inside it
},
```

Brackets, in the mandated shape (`performance-§2`) — one upvalue read, one field read, one boolean
test when off, and **nothing** built before the gate:

- `modules/Collector.lua` — around the `CHAT_MSG_LOOT` handler body → `lootCapture`.
- `modules/BrowserTable.lua` — around the render pass that ends at the `Table` summary line
  (`:872`) → `tableRender`; around the pooled-row bind (`:877-898`) → `tableBind`.

`tableRender` is the genuinely defensible one: it is the addon's only pass that touches N rows and
re-runs on every filter keystroke and sort change. `lootCapture` is rare but it is the addon's reason
for existing, so a number for it answers "what does recording cost me?" — which is the question the
section exists to answer.

**Do not bracket** settings reads, migrations, or the login prune. A row that always reads `0.000` is
the failure mode `performance-§3` names.

### 1.3 The `perf` verb (LH-22)

One entry in `NS.COMMANDS` (`settings/Schema.lua`), keeping the ordered-triple shape and the host's
printer — the library **must not** register it (`performance-§4`):

```lua
{ "perf", "Measure performance — try `/lh perf` for the workflow", function(rest)
    if not NS.Perf or not NS.Perf.OnCommand then return end
    for _, line in ipairs(NS.Perf.OnCommand(rest) or {}) do print(line) end
  end },
```

Place it after `debug` and before `version`, matching `slash-commands-§3`'s worked example ordering.
A bare `/lh perf` must be the **entry point to a run** (print the phase and open the guided step
panel), not a status line.

Ripples that move in the **same change** (`documentation-§1` item 7, `slash-commands-§4`): the README
`### Slash commands` table and `docs/ARCHITECTURE.md`'s `## Slash commands` table are both generated
from `NS.COMMANDS` and must gain the row. The settings landing page picks it up automatically
(`Sl:LandingRows`).

### 1.4 Suspend / resume (LH-23) — the part that needs a decision

`performance-§6`'s MUSTs: inert without a `/reload`; enforce visibility **at the source** in the
show-decision ladder rather than by hiding frames; restore from **current** state on resume; never
persist the flag; resume **before** saving or reporting.

Mechanically this is straightforward here:

- **inert** — unregister the Collector's and Attribution's event sets and the Browser's bus target;
  cancel any pending `C_Timer` work (`core/LootHistory.lua:53-61`);
- **at the source** — a `NS.State.suspended` check at the top of `NS.Collector`'s record path and in
  `B:Show`'s decision ladder, so a combat transition or a settings change cannot re-arm capture
  behind suspend's back;
- **restore from current state** — re-run `Collector:Enable()` / `Attribution:Enable()` /
  `Browser:Enable()` rather than replaying a snapshot;
- **session-only** — `NS.State.suspended`, beside `NS.State.debug` (`core/State.lua:15`), never in
  SavedVariables.

**The conflict:** while suspended, loot that drops is **not recorded and is unrecoverable**. Three
possible resolutions, in preference order:

1. **Upstream amendment (Branch B)** — carve out destructive-suspend addons in `performance-§6`.
   Cleanest; costs a standards change.
2. **Confirm-gated suspend** — reuse the existing `StaticPopupDialogs` pattern
   (`settings/Slash.lua:7-77`) so the second measurement arm is explicitly consented to, with the
   cost stated in the dialog text. Compliant with §6 as written; makes the data loss the user's
   informed choice.
3. **Buffer-and-replay** — queue capture inputs while suspended and drain on resume. **Rejected:**
   the queue is itself addon work inside the measured window, so it corrupts the very arm it exists
   to protect, and `performance-§6` requires the independent variable be *"does our code run?"* and
   nothing else.

### 1.5 `LootHistoryPerfDB` (LH-21) and lint (LH-26)

- `LootHistory.toc:7` → `## SavedVariables: LootHistoryDB, LootHistoryPerfDB` (this exact order).
- `.luacheckrc` `read_globals` → add `"debugprofilestop"`.
- `.luacheckrc` `globals` → add `LootHistoryPerfDB` **with a comment**, alongside `LootHistoryDB`.
- The ring is written by the **library**, outside the AceDB tree, carrying the library's own schema
  stamp — the addon hands over the **name** only and must not reach into it.
- **Ripple:** `docs/saved-variables.md` documents the SV surface and must gain the second global in
  the same change.

### 1.6 `tests/perf.lua` (LH-24)

New offline runner, **outside** the green gate — do **not** add it to `tests/run.lua`'s suite list
(`testing-§7`). Structure mirrors `tests/run.lua`: `dofile` the kit's `loader.lua`, load the eight
`libs/LibKa0s/*.lua` files explicitly in XML order, then `Loader.tocFiles("LootHistory.toc")` for the
addon's own files (`testing-§9` applies to it too).

Scenarios — assert only on **deterministic quantities** (API call counts, bytes allocated per
iteration, isolated by a full collect either side), **never** wall-clock:

- **zero-overhead** (required by `performance-§2` as *evidence*, not a comment): run the
  `lootCapture` bracket with `Perf.on == false` and pin that it allocates no more than the same path
  with the instrumentation absent.
- **tableRender** allocation per pass at a representative row count.

Output should state plainly that timings are orientation-only.

### 1.7 Docs (LH-25)

- **`docs/performance.md`** — which paths are bracketed and why (naming the buckets and their
  `within` nesting), how to run a capture (`/lh perf`), how to read the report, and what the harness
  can and cannot resolve. Point at the library for the shared protocol and record contract; do not
  restate them.
- **`docs/perf-runs/README.md`** — the naming convention
  (`<YYYY-MM-DD>-<source>-<label>.json`), a schema summary, and a pointer to the library's canonical
  field-by-field contract. The directory is **standing and cumulative**, not tied to one
  investigation.
- Add both to `docs/ARCHITECTURE.md`'s `## Doc index` in the same change.

---

## 2 — LH-27 · The options refresh contract

**Shape of the change: delete a shadow, do not build a bridge.**

`settings/Panel.lua` maintains `ctx.dirty` (written at `:321`, cleared at `:138`, **read nowhere**)
in parallel with the library's `ctx._dirty`, which its renderer actually consults. Two candidate
fixes, and only one is acceptable:

- **Rejected — write `ctx._dirty` from the host.** Works today, reaches into a private field, and
  breaks silently on any upstream rename. That is a fork of the contract by another name
  (anti-patterns #47).
- **Adopted — go through the library's public path.** `O.RefreshAllPanels`'s `refreshCtx` already
  sets `_dirty` on every hidden ctx (`libs/LibKa0s/Options.lua:460-472`). The host's off-screen
  branch calls that; the library then owns **when** a page redraws and the host's `rebuilders` list
  says only **what** to draw.

```lua
-- settings/Panel.lua ~:313-325, after
local onChange = function()
  if ctx.panel:IsShown() then runRebuilders(ctx) else O.RefreshAllPanels() end
end
```

`ctx.dirty` is then dead and must be **deleted** at both `:138` and `:321` — a flag nobody reads is
worse than no flag, because the comment above `runRebuilders` (`:133-135`) currently describes
behavior that does not happen, and the next reader will believe it.

`ctx.rebuilders` **stays**: it is a genuine host concept (three structural id-lists and the pooled
AH-price table, none of which the library has a widget maker for). Keep the reset inside
`renderFilters` (`:668`).

**Risk:** `O.RefreshAllPanels` also re-runs scalar refreshers on visible panels. That is cheap
(closures re-reading values, each `pcall`'d) and is exactly `options-ui-§11`'s in-place path — it is
**not** the O(N) full-renderer rebuild anti-pattern #39 forbids. Confirm against the vendored
`Options.lua` before landing.

**Test (`testing-§4`, test-first):** a case driving the real path — seed the Filters page, hide it,
fire `Ka0s_LootHistory_HistoryChanged`, then run the mock's recorded `OnShow` and assert the **row
list reflects the change**. Assert on the **outcome**, never on `_dirty` or `ctx.dirty`; a case that
pins a private flag is the same mistake as the code. `docs/reviews/2026-08-03/` records an existing
test that pins the private flag — retire it in the same change.

**Order:** land LH-27 before LH-29, because the new case will exercise the runner's lifecycle kick.

---

## 3 — LH-28 · One literal per default

**Shape: make the schema row derive from `NS.defaults`, not restate it.**

`settings/Schema.lua` loads after `defaults/Global.lua` in the TOC (`:44` then `:57`), so
`NS.defaults.global` is fully populated when the row table is constructed. A small reader at the top
of the file closes it:

```lua
-- settings/Schema.lua, above S.Schema
-- The defaults file is the ONE place a default is hardcoded (savedvariables-§2). A row's `default`
-- reads through to it, so AceDB's seed and `reset`/`resetall`/the Defaults button can never disagree.
local function D(path)
  local node = NS.defaults.global
  for _, key in ipairs(NS.Util.SplitPath(path)) do
    if type(node) ~= "table" then return nil end
    node = node[key]
  end
  return node
end
```

Then `default = true` → `default = D("settings.enabled")`, and so on for the six duplicated rows.
`settings.auction.capture` already references a constant (`:109`) and needs no change; session-only
rows (`state.debugConsole`) have no db-backed default and stay as they are.

**Hazard — table defaults must not alias.** `D("settings.excludedSources")` would hand out the *live
default table*. `S:Default` already `deepcopy`s on the way out (`settings/Schema.lua:183-186`) and
`S:Set` `deepcopy`s on the way in (`:168`), so the existing guards cover it — but this is precisely
the aliasing bug the comment at `:148-151` was written for, so re-verify rather than assume.

**Test:** iterate every non-`sessionOnly` row and assert `row.default` deep-equals the value at
`row.path` in `NS.defaults.global`. That case is both the fix's proof and the standing tripwire
against re-divergence, and it can be written **first** — it goes red against today's tree only if a
value has already drifted, so also assert **identity of source** (that the row references the reader)
by construction rather than by value alone.

---

## 4 — LH-29 · Pin the load-list derivation

`testing-§9` names three assertions and the reason each exists (both failure modes are silent: a
missing suite is *skipped, not failed*; an omitted library file makes the suite measure the
degradation stub).

**Runner change** (`tests/run.lua`) — capture and publish what was actually loaded:

```lua
local addonFiles = Loader.tocFiles("LootHistory.toc")
Loader.loadAll(addonFiles, NS, mocks)
…
_G.LH_TEST = Kit.expose{ NS = NS, mocks = mocks, Loader = Loader,
                         loaded = { libs = LIB_FILES, addon = addonFiles } }
```

(hoisting the existing `libs/LibKa0s/*.lua` list at `:17-26` into a named `LIB_FILES` local).

**Cases** — in `tests/test_libka0s.lua`, or a new `tests/test_runner.lua` added to the suite list:

1. `T.loaded.addon` equals a **fresh** `Loader.tocFiles("LootHistory.toc")`, element for element and
   in order.
2. Every path in `T.loaded.addon` and `T.loaded.libs` opens on disk.
3. No entry in `T.loaded.addon` matches `^libs/` — the TOC's `libs\` lines must not leak into the
   addon list.
4. Every file named in `libs/LibKa0s/LibKa0s.xml` appears in `T.loaded.libs`, in XML order. (The
   existing case *"every file of LibKa0s.xml is vendored and loads"* covers presence; this covers the
   **runner's list**, which is the thing that rots.)

Once LH-24 lands, `tests/perf.lua` is pinned by **reading its source** for the `Loader.tocFiles` call
— the gate does not run it, so its list is the one that rots while its figures are still trusted.

---

## 5 — SHOULD-level work

### LH-19 · Retired section citations

Two comment-only edits:

- `settings/OptionsSetup.lua:99` — `Ka0s standard §3.4` → `library-stack-§4` (the "one LibStub
  resolution, stashed on the namespace" rule).
- `tests/test_database.lua:363` — `Ka0s Standard §2.2/§5.1` → `toc-file-§2` / `savedvariables-§1`.

Leave `docs/superpowers/specs/**`'s `§6.2`/`§6.3`/`§8.2` alone — those are those documents' own
internal numbering, not standard citations.

### LH-30 · Delegate the window edge to `Core.ApplySkin`

The values already agree component for component (`03_EVIDENCE.md` §LH-30), so this is
behavior-neutral by construction and its whole value is future-proofing: when the standard next
retunes the edge, a delegating host moves with `Core.SKIN` and a restating host does not.

```lua
-- modules/Browser.lua
local Core = LibStub and LibStub("LibKa0s-Core-1.0", true)

function B:ApplySkin(f)
  if Core and Core.ApplySkin then return Core.ApplySkin(f) end
  … the current body, kept as the library-absent fallback …
end
```

Keep in `B.SKIN` only what is genuinely the host's — `titleBarH`, `tabStripH`, `contentGap`,
`defaultH`, `minH`, `tabActive`, `tabIdle` — and drop `bg` / `border` / `innerBorder` / `divider` /
`title`, which are the library's to own. Verify in-game that the History window, the Export window
(`modules/Export.lua:354,452`) and the debug console (which routes through this same seam via
`core/DebugLogSetup.lua:121-123`) are pixel-identical afterward; `docs/smoke-tests.md` should gain a
step for it.

**Risk:** the fallback branch must stay, because `B:ApplySkin` is reached on the degraded path too.

### LH-31 · `docs/complexity.md`

Run `lizard` over `core/ defaults/ locales/ modules/ settings/` (excluding `libs/`, `tests/`) and
commit the report, stating in the file that it is generated and how. **Must not** gate commits. Most
useful read: the three files in the 1000–1500 LOC band.

---

## 6 — Cross-cutting constraints

- **TDD.** Every item above lands test-first (`testing-§4`): a failing case that pins the intended
  behavior, then the implementation.
- **Green gate.** No commit lands with red `lua tests/run.lua` or non-clean `luacheck .`
  (`testing-§4`, `versioning-git`). Both are green today (563/563, 0/0), so any red is this work's.
- **Inventory + badge move together.** Every case added changes the count: regenerate
  `docs/test-cases.md` via `lua tests/run.lua --list > docs/test-cases.md` and update the README
  `[tests]` badge **in the same change** (`testing-§5`, `documentation-§1`).
- **Do not touch `libs/` or `tests/_kit/`.** Both diffs are empty today. A library defect found while
  doing this work is a finding to fix in `../LibKa0s`, release with the file's `MINOR` bumped, and
  re-vendor whole-folder (`library-stack-§7`, anti-patterns #45).
- **Version bump.** Adopting the perf harness is a **MINOR** (`versioning-git`): TOC `## Version`,
  `core/Namespace.lua:5`, the README badge row and a new `## Version History` row, with `## What's
  new` rolled forward in the same change (`documentation-§1` item 5, anti-pattern #40).
- **`schemaVersion`** does **not** move: `LootHistoryPerfDB` is outside the AceDB tree and carries the
  library's own stamp (`savedvariables-§4`, `performance-§8`).
