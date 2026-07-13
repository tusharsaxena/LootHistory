# CLAUDE.md — Ka0s Loot History

**Tier 2** (modular) WoW addon. Passively records every item you loot above a quality threshold,
attributes each drop to a **source** (kill / container / mail / trade / AH / quest / vendor /
deconstruct / M+ / …), stores it account-wide, and presents it in a standalone browser window with a
filter/sort/group table plus an Insights analytics view. Target client: WoW 12.0.7 (Midnight).
English only. Ace3 throughout.

This addon adheres to the **Ka0s WoW Addon Standard** — <https://github.com/tusharsaxena/WowAddonStandards>.

## Standards compliance

The **Ka0s WoW Addon Standard** (link above) is the **living source of truth** for this repo's
structure, conventions, TOC/packaging, saved-variables, and UI patterns. Consult it before any
structural or convention decision — fetch the repo when the answer isn't obvious, and run the
`wow-addon:standards-audit` skill to audit the whole addon against it.

> **Deviation rule (MUST).** If you find — or are about to introduce — anything that deviates from the
> standard, **stop and flag it to the user.** Never silently conform, and never silently deviate. The
> user decides whether it is a deviation to fix **in this addon**, or a case where the **standard's own
> definition** should change. Record the resolution (a dated `audit/<date>/` bundle, or a note in the
> relevant `docs/` file).

## Full agent context lives in `docs/`

This root file is a stub (per standard §15.2). Read these before touching code:

- **[docs/agent-context.md](docs/agent-context.md)** — the full working-notes brief: hard rules,
  module-publishing pattern, response style, working environment, and the doc index. **Start here.**
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — design overview: module map, data model,
  message bus, slash surface, event wiring, taint notes, known limitations.
- **[docs/attribution.md](docs/attribution.md)** — required reading before touching capture/source
  code (the `CHAT_MSG_LOOT` + `lootContext` engine).

## Hard rules (full text in [docs/agent-context.md](docs/agent-context.md))

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
  slash CLI; every user-setting mutation goes through `Schema:Set` (window geometry is the carve-out).
- **Debug is session-only** (`NS.State.debug`, never persisted); it routes to the on-screen console.

## Local verification (standard §14A)

- Unit tests: `lua tests/run.lua` (headless, exits non-zero on failure).
- Lint: `luacheck .` (0 errors).
- In-game: [docs/smoke-tests.md](docs/smoke-tests.md).

Run both before every commit.
