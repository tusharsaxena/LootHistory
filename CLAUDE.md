# CLAUDE.md — Ka0s Loot History

**Ka0s WoW addon.** Passively records every item you loot above a quality threshold,
attributes each drop to a **source** (kill / container / mail / trade / AH / quest / vendor /
deconstruct / M+ / …), stores it account-wide, and presents it in a standalone browser window with a
filter/sort/group table plus an Insights analytics view. Target client: WoW 12.0.7 (Midnight).
English only. Ace3 throughout.

This addon adheres to the **Ka0s WoW Addon Standard** — <https://github.com/tusharsaxena/WowAddonStandards>.

## Standards compliance (read first)

The **Ka0s WoW Addon Standard** (link above) is the **living source of truth** for this repo's
structure, conventions, TOC/packaging, saved-variables, and UI patterns. Consult it before any
structural or convention decision — fetch the repo when the answer isn't obvious, and run the
`wow-addon:standards-audit` skill to audit the whole addon against it.

> **Deviation rule (MUST).** If you find — or are about to introduce — anything that deviates from the
> standard, **stop and flag it to the user.** Never silently conform, and never silently deviate. The
> user decides whether it is a deviation to fix **in this addon**, or a case where the **standard's own
> definition** should change. Record the resolution (a dated `docs/audits/<date>/` bundle, or a note in
> the relevant `docs/` file).

## The `docs/` set — there is no `agent-context.md`

The canonical `docs/` set is exactly three files: **`ARCHITECTURE.md`** (what this addon is),
**`testing.md`** (how to verify) and **`smoke-tests.md`** (in-game checks) — plus the generated
`test-cases.md` and the topic-detail docs.

**`docs/agent-context.md` does not exist in this repo and MUST NOT be created.** The standard
deleted it in **v2.17.0**; shipping it is **anti-pattern #49**. It held `NEW_ADDON_CONTEXT.md` —
the scaffolding pack — which is fetched at runtime and never stored: a copy in the repo describes
the addon on the day it was born, forever, and because it loads as *working context* a stale copy
does not go quiet, it gets **followed** (documentation-§3). This root `CLAUDE.md` is the repo's
only agent brief.

Older audit bundles, review bundles, ledgers and plans under `docs/` predate v2.17.0 and still
name the file, and some describe a four-file or a pre-v2.3.0 `agent-context.md`-based set. Those
are **frozen history** — never treat them as a live requirement, and never "restore" the file.

## Full context lives in `docs/`

This root file is a stub (per documentation-§2). Read these before touching code:

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — what this addon is: module map, data model,
  message bus, slash surface, event wiring, taint notes, known limitations, and the **doc index**
  covering every topic doc. **Start here.**
- **[docs/testing.md](docs/testing.md)** — how to verify: the headless harness, the mock, the
  vendor gate, lint, the green gate.
- **[docs/conventions.md](docs/conventions.md)** — the file-by-file rules: namespace preamble,
  module publishing, object pooling, hot-path upvalues.
- **[docs/attribution.md](docs/attribution.md)** — required reading before touching capture/source
  code (the `CHAT_MSG_LOOT` + `lootContext` engine).

## Hard rules

- **Flag standards deviations.** If anything deviates from the Ka0s Standard, surface it to the user
  rather than silently conforming or silently deviating — the user decides deviation-vs-standard-change.
  See **Standards compliance** above.
- **Never auto-stage / commit / push.** The user controls `git add` / `commit` / `push`. Leave edits
  in the working tree; don't touch the index. (`/wow-addon:commit` is the one explicit exception.)
- **Never bump the version** (TOC `## Version`, `NS.version`, README badge/history) without an
  explicit instruction.
- **Account-wide storage** (`LootHistoryDB.global`, `char` column) — never per-character profiles.
- **Closed message bus**: the three `Ka0s_LootHistory_*` messages are the only inter-module channel;
  every receiver registers on its OWN `NS.NewBusTarget()` (never the shared addon object).
- **Compat firewall**: every varying/deprecated API lives in `core/Compat.lua` and is gated by
  `C_*`/global presence — Retail-only, no `WOW_PROJECT_ID` game-flavor branching.
- **Schema-as-single-source**: `settings/Schema.lua` drives AceDB defaults, panel widgets, and the
  slash CLI; every user-setting mutation goes through `Schema:Set`. Carve-outs (written straight to
  `NS.db.global`): window geometry, `savedView`, the `blacklist`/`whitelist`/`currencyBlacklist` id
  lists (via `NS.Filters`), and the `settings.auction.priority` cascade (via `NS.AuctionPrice`) — all
  ratified carve-outs (see `docs/saved-variables.md`).
- **Debug is session-only** (`NS.State.debug`, never persisted); it routes to the on-screen console.
- **Never edit `libs/` or `tests/_kit/`.** Both are vendored copies of
  [LibKa0s](https://github.com/tusharsaxena/LibKa0s), the Ka0s shared library this addon wires four
  majors of (`Core`, `DebugLog`, `Slash`, `Options`; `Perf` is declined — `docs/pending/LEDGER.md`,
  LIBKA0S-17). A library problem is fixed in the sibling repo `../LibKa0s`, released with that
  file's `MINOR` bumped, and **re-vendored whole-folder** — a local patch is a fork nobody knows
  about, and the next re-vendor silently reverts it. The four seam files are `core/CoreSetup.lua`,
  `core/DebugLogSetup.lua`, `settings/Slash.lua` and `settings/OptionsSetup.lua`; each degrades
  rather than errors when its major is absent, and each explains the absence through the one shared
  `NS.LIBKA0S_MISSING` clause `core/CoreSetup.lua` publishes. See
  [docs/testing.md](docs/testing.md#the-vendor-gate) for the four diffs that keep the copies honest.
- **Test inventory & badge stay in sync.** When the suite changes (a case added/removed/renamed, or
  the pass count moves), regenerate `docs/test-cases.md` (`lua tests/run.lua --list > docs/test-cases.md`)
  and update the README `tests` badge count in the same change. See [docs/testing.md](docs/testing.md).

## Response style

- **Terse.** State the change, not the deliberation; point at code as `file_path:line_number`.
- **No summaries the user can read off the diff**, and no new docs or planning files unless asked.
- **Comments explain the non-obvious *why*** (a Blizzard quirk, a subtle invariant) — never what
  well-named code already says.

## Local verification (standard: testing)

- Unit tests: `lua tests/run.lua` (headless, exits non-zero on failure).
- Lint: `luacheck .` (0 errors).
- In-game: [docs/smoke-tests.md](docs/smoke-tests.md).

Run both before every commit.
