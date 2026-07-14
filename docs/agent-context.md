# Agent context — working notes for future sessions

The full brief for Claude Code (and other LLM-assisted editors) working on **Ka0s Loot History**.
Read this before touching code. The root [CLAUDE.md](../CLAUDE.md) is a stub that points here.

## What this addon is

A passive loot tracker for WoW: Midnight (Interface 120007). It records every item the player loots
above a configurable quality threshold, attributes each drop to a **source** (kill, container, mail,
trade, AH, quest, vendor, disenchant/milling/prospecting, M+ chest, other) with a **confidence**
(`CERTAIN`/`INFERRED`), stores it **account-wide**, and presents it in a standalone browser window: a
virtualized History table plus an Insights analytics view. Slash: `/lh`, `/loothistory`. English only.
Ace3 throughout. Ka0s WoW Addon Standard, Tier 2. Current version **1.1.0**.

> Internal-only terms **Collector** (capture) and **Browser** (view) are used in code/docs. User-facing
> copy says "Loot History", "History", "Insights".

User-facing reference: [../README.md](../README.md). Design overview + invariants:
[ARCHITECTURE.md](ARCHITECTURE.md).

## Namespace & structure

- **Private namespace, no globals.** Every file starts `local addonName, NS = ...`. `core/Compat.lua`
  loads first; `core/LootHistory.lua` promotes the table with
  `AceAddon:NewAddon(NS, addonName, "AceEvent-3.0","AceTimer-3.0","AceConsole-3.0")` and stores
  `NS.addon` / `NS.bus`. There is **no `_G.LootHistory`**.
- **Tier-2 layout.** `core/` (Compat, Constants, Namespace, State, Util, the AceAddon entry, Database),
  `modules/` (Attribution, Collector, Browser, BrowserTable, Analytics, DebugLog), `settings/` (Schema,
  Slash, Panel), `defaults/`, `locales/`. `LootHistory.toc` is the load-order source of truth. See
  [module-map.md](module-map.md).

## Hard rules

- **Standards are the source of truth; flag deviations.** This repo follows the
  [Ka0s WoW Addon Standard](https://github.com/tusharsaxena/WowAddonStandards) — consult it (fetch the
  repo when unsure; run `wow-addon:standards-audit`) before structural/convention changes. If anything
  deviates from the standard, **stop and flag it to the user** — never silently conform or silently
  deviate. The user decides whether to fix the deviation here or change the standard's own definition;
  record the resolution (a dated `docs/audits/<date>/` bundle or a `docs/` note).
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
- **Schema-as-single-source.** `settings/Schema.lua` drives AceDB defaults, panel widgets, and the
  slash CLI; every user-setting mutation goes through `Schema:Set` (validate → write to `NS.db.global`
  → onChange). The Browser's window geometry (`settings.window`) and saved table view (`savedView`)
  are the carve-out — persisted directly, not schema rows.
- **Object pooling** for the History table (never one frame per record); **hot-path upvalues** in the
  Collector, refreshed on `SettingsChanged`.
- **`Database:Export` field shape is the v2 export contract** — do not change it. See
  [data-model.md](data-model.md).

## Compat seam

`core/Compat.lua` (`NS.Compat`) wraps every Blizzard API that varies or was deprecated (GUID decode,
item/map/zone info, keystone level, tooltip bound-scan, AH-mail detection, spell-name lookup). Call
through `Compat.*`; a shim degrades to `nil`/false when its API is absent. Full catalogue:
[compat-layer.md](compat-layer.md); Midnight-specific traps: [midnight-quirks.md](midnight-quirks.md).

## Debug console

`modules/DebugLog.lua` is an on-screen console. The enabled flag is **session-only** —
`NS.State.debug` in `core/State.lua`, default off, never persisted. `/lh debug on|off` and the console
header toggle both route through it; the window's visibility is independent of the flag. Emit via
`NS.Debug(tag, fmt, ...)` — tagged `<ts> | [<tag>] <content>`, zero-alloc gate when disabled. **No raw
`print(...)`** on hot paths. `/lh test` publishes a synthetic dataset to `NS.State.testRecords`, which
`Database:ActiveHistory` swaps in for both the table and Insights (also session-only).

## Locale

`locales/enUS.lua` exports `NS.L`, a key-returning metatable. English is the only shipped locale — a
shell, not localization plumbing. The one locale-sensitive capture path (deconstruct spell-name
matching) has an id-based fallback; see [attribution.md](attribution.md).

## Testing & lint gate

Headless harness under `tests/` runs with **`lua tests/run.lua`** (a `wow_mock.lua` stubs the WoW API
+ a `(message,target)`-keyed bus so receivers are testable; it deliberately omits several `C_*` APIs
so the compat presence-guards are exercised). Lint with **`luacheck .`**. Both must be green before
committing (152 tests). Details: [testing.md](testing.md). Manual in-game validation:
[smoke-tests.md](smoke-tests.md).

## Module publishing pattern

Every module uses the same idiom:

```lua
local addonName, NS = ...
NS.Foo = NS.Foo or {}
local F = NS.Foo
```

- Never overwrite an existing `NS.Foo` without `or {}` — another file may have reached it first.
- Expose the public API on `F` (or `NS.Foo`); keep helpers `local` to the file.

## Working environment

- **Dual-path WSL.** `/home/tushar/GIT/LootHistory/` and
  `/mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory/` are the same repo. Either path works.
- **Git remote.** `origin` = <https://github.com/tusharsaxena/LootHistory>. Work trunk-based on
  `master`; the user pushes when ready.
- **Vendored libs.** `libs/` is committed (Ace3 + LibSharedMedia + LDB + LibDBIcon) per Standard v1.1
  — never switch to `.pkgmeta` externals.

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
- The **standalone non-secure browser window** (follows §6A) — non-secure by design.
- `Database:Export` field shape — the forward-compatible v2 export contract.

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
| Schema-driven canvas settings panel (§6.6/§6.10 layout) | [settings-panel.md](settings-panel.md) | Adding an option or a custom widget. |
| `/lh` slash dispatch (`COMMANDS`, generated help, CLI) | [slash-dispatch.md](slash-dispatch.md) | Adding or modifying a slash verb. |
| `Compat.*` API-shim catalogue | [compat-layer.md](compat-layer.md) | Wrapping a Blizzard API; reasoning about taint. |
| Midnight (12.0) gotchas (GUID decode, tooltip scans, uncached fallback) | [midnight-quirks.md](midnight-quirks.md) | Patch-day breakage; capture edge cases. |
| Coding conventions / boundaries | [conventions.md](conventions.md) | Style / boundary questions. |
| Headless test harness + lint gate | [testing.md](testing.md) | Adding tests; understanding the mock. |
| In-game smoke tests | [smoke-tests.md](smoke-tests.md) | After any change; before a release. |
| Design overview / invariants / taint notes | [ARCHITECTURE.md](ARCHITECTURE.md) | Designing a cross-module change. |
