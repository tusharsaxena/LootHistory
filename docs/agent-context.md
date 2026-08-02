# Agent context — working notes for future sessions

The full brief for Claude Code (and other LLM-assisted editors) working on **Ka0s Loot History**.
Read this before touching code. The root [CLAUDE.md](../CLAUDE.md) is a stub that points here.

## What this addon is

A passive loot tracker for WoW: Midnight (Interface 120007). It records every item the player loots
above a configurable quality threshold (and, optionally, looted **currency** as `Type=Currency` rows),
attributes each drop to a **source** (kill, container, M+ chest,
bonus roll, roll, quest, trade, mail, AH, vendor, disenchant/milling/prospecting, craft, refund, other)
with a **confidence**
(`CERTAIN`/`INFERRED`), stores it **account-wide**, and presents it in a standalone browser window: a
virtualized History table plus an Insights analytics view. Slash: `/lh`, `/loothistory`. English only.
Ace3 throughout, on the shared **LibKa0s** (four majors wired). Ka0s WoW Addon Standard. Current
version **1.2.0**.

> Internal-only terms **Collector** (capture) and **Browser** (view) are used in code/docs. User-facing
> copy says "Loot History", "History", "Insights".

User-facing reference: [../README.md](../README.md). Design overview + invariants:
[ARCHITECTURE.md](ARCHITECTURE.md).

## Namespace & structure

- **Private namespace, no globals.** Every file starts `local addonName, NS = ...`. `core/Compat.lua`
  loads first; `core/LootHistory.lua` promotes the table with
  `AceAddon:NewAddon(NS, addonName, "AceEvent-3.0","AceTimer-3.0","AceConsole-3.0")` and stores
  `NS.addon` / `NS.bus`. There is **no `_G.LootHistory`**.
- **Modular layout.** `core/` (Compat, Constants, Namespace, State, Util, CoreSetup, DebugLogSetup,
  the AceAddon entry, Database), `modules/` (Attribution, Filters, AuctionPrice, Collector, Browser,
  BrowserTable, Export, Analytics), `settings/` (Schema, Slash, OptionsSetup, Panel), `defaults/`,
  `locales/`. `LootHistory.toc` is the load-order source of truth — and for the four LibKa0s seam
  files the position is a hard constraint, not a preference: `core/CoreSetup.lua`,
  `core/DebugLogSetup.lua` and `settings/OptionsSetup.lua` spell theirs out in their file headers, and
  every file taking `local print = NS.Print` at file scope (`modules/Browser.lua`,
  `settings/Schema.lua`, `settings/Slash.lua`, `settings/Panel.lua`) must load after CoreSetup or it
  holds a stale printer while appearing to work. See [module-map.md](module-map.md).

## Hard rules

- **Standards are the source of truth; flag deviations.** This repo follows the
  [Ka0s WoW Addon Standard](https://github.com/tusharsaxena/WowAddonStandards) — consult it (fetch the
  repo when unsure; run `wow-addon:standards-audit`) before structural/convention changes. If anything
  deviates from the standard, **stop and flag it to the user** — never silently conform or silently
  deviate. The user decides whether to fix the deviation here or change the standard's own definition;
  record the resolution (a dated `docs/audits/<date>/` bundle or a `docs/` note).
  - **Flagged deviation (2026-07-17):** the schema gained a `sessionOnly` row kind (`get`/`set`
    accessors, never written to `db.global`) so the "Debug console" window-visibility toggle can live
    in the settings panel while honouring "debug is session-only, never persisted." Extends
    schema-as-single-source rather than breaking it (the toggle is a real schema row); flagged for the
    next standards-audit. See [settings-panel.md](settings-panel.md).
- **Account-wide storage is load-bearing.** All history + settings live in `LootHistoryDB.global`
  (`char` is a column, not separate storage). Switching to per-character profiles is a schema + query
  rewrite. See [saved-variables.md](saved-variables.md).
- **`CHAT_MSG_LOOT` is the authoritative "item received (self)" signal.** Peripheral events only
  *stamp* a short-lived `State.lootContext`; the Collector consumes it. Never write a record from a
  peripheral event directly. See [attribution.md](attribution.md).
- **The attribution context is single-slot with a fixed TTL** (`Constants.CONTEXT_TTL`, ~1.5s) and
  deliberately survives multiple `CHAT_MSG_LOOT` lines from one loot window. Don't "fix" it into a
  queue without reading the TTL rationale.
- **Closed message bus.** The three `Ka0s_LootHistory_*` messages are the only inter-module channel.
  **Every receiver owns its own target** via `NS.NewBusTarget()` — never two subscriptions on the
  shared `NS.bus`/`NS.addon`. See [message-bus.md](message-bus.md).
- **Compat firewall.** Every deprecated/varying API lives in `core/Compat.lua` (`NS.Compat.*`), gated
  by `C_*`/global presence. Retail-only — **no `WOW_PROJECT_ID` game-flavor branching.** See
  [compat-layer.md](compat-layer.md).
- **LibKa0s is wired at four seams, and `libs/` is never edited.** The Ka0s-owned shared library is
  vendored whole-folder at `libs/LibKa0s` (its test harness separately at `tests/_kit/`). Four of its
  five majors are adopted, each through exactly one seam file that owns the descriptor and nothing
  else: `core/CoreSetup.lua` (**Core** — `NS.Print` / `NS.Format` / `NS.Util.print` /
  `NS.SafeToString` / `NS.IsConcatSafe`), `core/DebugLogSetup.lua` (**DebugLog** — `NS.DebugLog` and
  the `NS.Debug` sink), `settings/Slash.lua` (**Slash** — the `/lh` dispatcher, generated help and
  schema CLI) and `settings/OptionsSetup.lua` (**Options** — `NS.Options`, the settings canvas). The
  fifth, **Perf**, is *declined*, not deferred (no hot path to bucket, and `suspend` would drop the
  loot it is measuring) — [pending/LEDGER.md](pending/LEDGER.md), LIBKA0S-17.
  - **Never edit anything under `libs/` or `tests/_kit/`.** A library problem is fixed in
    `../LibKa0s`, released with that file's `MINOR` bumped, and re-vendored back whole-folder. A
    local patch is a fork nobody knows about, and the next re-vendor silently reverts it. The four
    diffs that catch a stale or forked copy are [The vendor gate](testing.md#the-vendor-gate).
  - **`NS.LIBKA0S_MISSING` is a cross-file contract.** `core/CoreSetup.lua` publishes it on **both**
    paths (library present or not) as the one *cause* clause; every other seam appends its own
    *consequence* ("…, so the settings panel is unavailable."). Every seam degrades to a stub rather
    than erroring at load — recording loot needs none of them. Asserted verbatim in
    `tests/test_libka0s.lua`.
  - Adoption decisions **LIBKA0S-01..19** — what was taken, what was declined and why — are recorded
    in [pending/LEDGER.md](pending/LEDGER.md). Read the relevant row before re-litigating a seam.
- **Schema-as-single-source.** `settings/Schema.lua` drives AceDB defaults, panel widgets, and the
  slash CLI; every user-setting mutation goes through `Schema:Set` (validate → write to `NS.db.global`
  → onChange). Carve-outs (persisted directly, not schema rows): the Browser's window geometry
  (`settings.window`), the saved table view (`savedView`), the `blacklist`/`whitelist`/`currencyBlacklist`
  id lists (owned by `NS.Filters`), and the `settings.auction.priority` cascade (owned by
  `NS.AuctionPrice`) — a dynamic id-set or an ordered list has no schema widget; all ratified carve-outs,
  see [saved-variables.md](saved-variables.md). The row vocabulary is **LibKa0s's**, because the
  library reads the table directly: `type = "bool"` (not `"boolean"`), `values` (an array of
  `{ value =, text = }`, position is display order — not `options`/`label`), `solo` (not `soloRow`)
  and `skipRender` (not `panelSkip`); `tooltip` deliberately stays `tooltip` (the library reads it
  first, its own `desc` second). No older spelling errors, which is the whole hazard, and each one
  fails differently: `type = "boolean"` drops off its page entirely (`RenderField` answers nil for a
  type it does not know) and returns a type error on every `set`; `options`/`label` leaves the
  dropdown labelling each entry with its raw stored value; `soloRow` and `panelSkip` are simply not
  read, so the row lands back in the flow — or gets drawn twice, once by the library and once by the
  host page that was meant to own it. `NS.COMMANDS`, in the same file, is likewise the
  library's shape: **positional** `{ name, description, handler }` triples, handler taking the rest
  of the line verbatim and never a `self`.
- **Object pooling** for the History table (never one frame per record); **hot-path upvalues** in the
  Collector, refreshed on `SettingsChanged`.
- **`Database:Export` field shape is the v2 export contract** — do not change it. See
  [data-model.md](data-model.md).
- **Keep the test inventory & README badge in sync.** Any suite change (case added/removed/renamed
  or count moved) MUST regenerate `docs/test-cases.md` via `lua tests/run.lua --list` and update the
  README `tests` badge in the same change. See [testing.md](testing.md) and [test-cases.md](test-cases.md).

## Compat seam

`core/Compat.lua` (`NS.Compat`) wraps every Blizzard API that varies or was deprecated (GUID decode,
item/map/zone info, keystone level, tooltip bound-scan, AH-mail detection, spell-name lookup). Call
through `Compat.*`; a shim degrades to `nil`/false when its API is absent. Full catalogue:
[compat-layer.md](compat-layer.md); Midnight-specific traps: [midnight-quirks.md](midnight-quirks.md).

## Debug console

`core/DebugLogSetup.lua` wires **`LibKa0s-DebugLog-1.0`** — the on-screen console, the copy window,
both formatters and the buffer are the library's; there is no `modules/DebugLog.lua`. The enabled flag
stays the **host's** and is **session-only** — `NS.State.debug` in `core/State.lua`, default off, never
persisted — handed over as the descriptor's `isEnabled`/`setEnabled` pair so `/lh debug on|off`, the
console header toggle and the settings checkbox all read one truth; the window's visibility is
independent of the flag. Emit via `NS.Debug(tag, fmt, ...)` (the library's `Debug`, republished as a
plain bindable function under the name ~40 call sites already use) — tagged
`<ts> | [<tag>] <content>`, zero-alloc gate when disabled. **No raw `print(...)`** on hot paths. The
window **chrome** is split, and the split is the point: `applySkin` is a descriptor hook resolving
`NS.Browser` at **frame-build time** — a closure, never a load-time local, since
`modules/Browser.lua` loads long after `core/`, and hoisting the lookup silently loses the skin —
while **`makeCloseButton` is deliberately not passed**. The window *edge* is shared across every
Ka0s window (`Core.SKIN`), but the *close control* on a library-drawn window is the library's, so
the console and the copy window wear Core's thin 18×18 × and the History browser keeps this addon's
24×24 class-coloured one (standalone-windows-§2; `docs/pending/LEDGER.md` LIBKA0S-19).
`/lh test` publishes a synthetic dataset to `NS.State.testRecords`, which `Database:ActiveHistory`
swaps in for both the table and Insights (also session-only).

## Locale

`locales/enUS.lua` exports `NS.L`, a key-returning metatable. English is the only shipped locale — a
shell, not localization plumbing. The one capture path that touches game-data strings (deconstruct
spell detection) resolves by spell id first and, for un-enumerated variants, matches the cast's
*localized* name against tokens derived from seed spellIDs — locale-independent, no English literals;
see [attribution.md](attribution.md).

## Testing & lint gate

Headless harness under `tests/` runs with **`lua tests/run.lua`**. The registry, the assertions, the
`--list` renderer, the source loader and the universal half of the WoW-API mock are the **shared
LibKa0s test kit**, vendored at `tests/_kit/` — never edited, and kept honest by
[the vendor gate](testing.md#the-vendor-gate). It owns the `(message, target)`-keyed bus that makes
bus receivers testable, and a `LibStub` with a real `NewLibrary` (without which no vendored LibKa0s
file could register at all). `tests/wow_mock.lua` is a thin *extender* over `_kit/mock_base.lua`
adding only what this addon touches, and it deliberately omits several `C_*` APIs so the compat
presence-guards are exercised. The addon load list is derived from the TOC rather than
hand-maintained, so the runner's order cannot drift from the client's. The frame-heavy modules are
covered through their underscore-published pure helpers (see the module-publishing exception below);
the frames themselves belong to [smoke-tests.md](smoke-tests.md). Lint with **`luacheck .`**. Both
must be green before committing; the authoritative case count and full per-case inventory live in
[test-cases.md](test-cases.md) (`lua tests/run.lua --list`). Details: [testing.md](testing.md).
Manual in-game validation: [smoke-tests.md](smoke-tests.md).

## Module publishing pattern

Every module uses the same idiom:

```lua
local addonName, NS = ...
NS.Foo = NS.Foo or {}
local F = NS.Foo
```

- Never overwrite an existing `NS.Foo` without `or {}` — another file may have reached it first.
- Expose the public API on `F` (or `NS.Foo`); keep helpers `local` to the file.
- **One exception:** a pure helper inside a frame-heavy module (`Browser`, `BrowserTable`,
  `Analytics`) may be published as `F._name` next to its `local` definition so the headless suite can
  drive the exact function the UI binds. Underscore-prefixed = test seam, not public API; nothing
  outside the module and `tests/` may call it. See [testing.md](testing.md).
- The four **LibKa0s seam files** are the shape's other end: a descriptor, plus only what genuinely
  cannot leave the host. Each resolves its major with the silent flag (`LibStub("LibKa0s-…-1.0",
  true)`), publishes the library's product under the `NS.*` name the rest of the addon already calls,
  and carries a stub branch answering every member reached on the degraded path. What this addon
  keeps re-enters through a descriptor hook wherever the library offers one — the console chrome
  (`applySkin`), the set-valued formatter (`format`), the landing-page body — never
  through a fork of the library; the rest sits beside the descriptor as host code the library never
  sees (`settings/Slash.lua`'s confirm popups, `Sl:ResetEverything`, the `Sl:CliResetAll` wrapper
  that also clears the three id lists, and `Sl:Register`).

## Working environment

- **Dual-path WSL.** `/home/tushar/GIT/LootHistory/` and
  `/mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory/` are the same repo. Either path works.
- **Git remote.** `origin` = <https://github.com/tusharsaxena/LootHistory>. Work trunk-based on
  `master`; the user pushes when ready.
- **Vendored libs.** `libs/` is committed (Ace3 + LibSharedMedia + LDB + LibDBIcon + **LibKa0s**) per
  Standard v2.0.0 — never switch to `.pkgmeta` externals, and never hand-edit a vendored file.
  LibKa0s is vendored **whole-folder** (four of its majors resolve `LibKa0s-Core-1.0` before
  registering, so a file-by-file copy is how cross-major skew gets manufactured); its test kit lands
  at `tests/_kit/`, not `libs/`, because `libs/` is the ship payload. `../LibKa0s` checked out beside
  this repo is what the vendor-gate diffs need.

## Response style for this repo

- **Terse.** State the change, not the deliberation. Use `file_path:line_number` when pointing at code.
- **Don't write summaries** the user can read from the diff.
- **No comments explaining *what* well-named code does** — only the non-obvious *why* (a Blizzard quirk,
  a subtle invariant).
- **Don't create docs or planning files unless asked.**
- **Never auto-stage, auto-commit, or auto-push.** Editing files is fine; touching the git index is
  not. (Invoking `/wow-addon:commit` is the explicit exception — proceed through its confirmation flow.)
- **Never bump the version** without an explicit instruction (`## Version` in the TOC, `NS.version`,
  README badge/history). Releases are the user's call.

## Do not change without reason

- The **account-wide** storage decision (`.global`, `char` column).
- The **attribution context TTL / single-slot** design.
- The **standalone non-secure browser window** (follows standalone-windows) — non-secure by design.
- `Database:Export` field shape — the forward-compatible v2 export contract.
- The TOC positions of the four LibKa0s seam files, and the fact that both DebugLog chrome hooks are
  closures rather than load-time locals.

## Doc index

Topic-specific detail lives in `docs/`. Read on demand — these are not auto-loaded.

| Topic | File | When to read |
|-------|------|--------------|
| Scope (in / out / resolved decisions), backlog pointer | [scope.md](scope.md) | Evaluating a feature request. |
| Per-file responsibility map + TOC load order + lifecycle | [module-map.md](module-map.md) | "Which file owns X?" / "When does Y run?" |
| Loot-record shape, enums, `schemaVersion`, export contract | [data-model.md](data-model.md) | Adding/changing a record field. |
| `LootHistoryDB` shape, settings, storage-only carve-outs, retention | [saved-variables.md](saved-variables.md) | Adding persistent state. |
| The three `Ka0s_LootHistory_*` messages (sender / payload / consumers) | [message-bus.md](message-bus.md) | Touching anything that sends or listens. |
| Capture + source-attribution engine (`lootContext`, stampers, gates) | [attribution.md](attribution.md) | **Required** before touching capture/source code. |
| Browser window, virtualized table, Insights analytics | [browser.md](browser.md) | Touching the window/table/charts. |
| Schema-driven canvas settings panel — the `LibKa0s-Options-1.0` seam, page builders, the two host-drawn surfaces (options-ui-§6/§10 layout) | [settings-panel.md](settings-panel.md) | Adding an option or a custom widget. |
| `/lh` slash dispatch — the `LibKa0s-Slash-1.0` seam, positional `NS.COMMANDS`, generated help, schema CLI | [slash-dispatch.md](slash-dispatch.md) | Adding or modifying a slash verb. |
| `Compat.*` API-shim catalogue | [compat-layer.md](compat-layer.md) | Wrapping a Blizzard API; reasoning about taint. |
| Midnight (12.0) gotchas (GUID decode, tooltip scans, uncached fallback) | [midnight-quirks.md](midnight-quirks.md) | Patch-day breakage; capture edge cases. |
| Coding conventions / boundaries | [conventions.md](conventions.md) | Style / boundary questions. |
| Headless test harness + lint gate; the shared `tests/_kit/`; generated case inventory | [testing.md](testing.md) · [test-cases.md](test-cases.md) | Adding tests; understanding the mock; the case list. |
| The four `diff -r` checks proving `libs/LibKa0s` and `tests/_kit` have not forked from `../LibKa0s` | [testing.md#the-vendor-gate](testing.md#the-vendor-gate) | Before/after re-vendoring; a suite that passes here but not upstream. |
| Deferred/declined decisions, incl. the LibKa0s adoption record LIBKA0S-01..17 | [pending/LEDGER.md](pending/LEDGER.md) | Re-litigating a seam; "why isn't X adopted?"; deferring an item. |
| In-game smoke tests | [smoke-tests.md](smoke-tests.md) | After any change; before a release. |
| Design overview / invariants / taint notes | [ARCHITECTURE.md](ARCHITECTURE.md) | Designing a cross-module change. |
