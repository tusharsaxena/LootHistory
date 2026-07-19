# Testing

WoW runs **Lua 5.1**, so the headless suite targets Lua 5.1 too. Two gates guard every commit: the unit tests (`lua tests/run.lua`) and the linter (`luacheck .`). Both must be green — see [The green gate](#the-green-gate). For in-client, end-to-end scenarios that the headless harness can't reach — real `CHAT_MSG_LOOT` capture, the browser window, minimap button, combat-gated settings panel — see [smoke-tests.md](smoke-tests.md).

## The harness

`lua tests/run.lua`, run **from the repo root**, is the whole show. `tests/run.lua` does four things:

1. Builds a fresh WoW-API mock set via `tests/wow_mock.lua` (a builder — one isolated environment per run).
2. Loads every source file in TOC order through `tests/loader.lua` into a shared `NS` table, then calls `NS:InitDB()` — mirroring the in-game load + `OnInitialize`.
3. Exposes the tiny test framework and the built environment on the `_G.LH_TEST` handoff table (`NS`, `mocks`, `test`, `assertEqual`, `assertTrue`, `assertFalse`).
4. `dofile`s each suite, runs every registered test under `pcall`, prints `PASS`/`FAIL` per test and a `N passed, N failed, N total` tail, and exits non-zero if anything failed.

### The loader

`tests/loader.lua` `loadfile`s each source path and `setfenv`s the chunk into an environment whose `__index` resolves WoW globals to the mock set first, then falls back to real `_G`. Each chunk is called with `("LootHistory", NS)` — exactly the `local addonName, NS = ...` header every file expects. `loadAll` walks the TOC-ordered path list (`locales/enUS` first, then `core/Compat`, Attribution before Collector, settings last), so load-order bugs surface here just as they would in-game.

### The mock (deliberately partial)

`tests/wow_mock.lua` stubs **only what the addon touches at load and test time** — `CreateFrame` returns a universal frame stub (any PascalCase method is a self-returning no-op; lowercase/custom fields miss through to `nil`), plus `UnitClass`, `C_Map`, `C_Item`, the `LOOT_ITEM_*` format strings, `Settings`, and the Ace libraries.

Two design choices make the mock earn its keep rather than merely satisfy `require`:

- **It omits several `C_*` APIs on purpose** — e.g. `C_Container`, `C_ChallengeMode`, `C_AuctionHouse`, `C_TooltipInfo`, `C_Texture`, `C_Spell`. `core/Compat.lua` presence-guards each of these before calling, so their absence drives the compat shims down their **degraded path** every run. The tests therefore prove the fallbacks work, not just the happy path.
- **The message bus is modeled on CallbackHandler**, keyed by `(message, target)`. Registering the same message twice on one target overwrites (only the last survives); `SendMessage` fires once per distinct target. This mirrors the real semantics so a same-target clobber — the exact bug that shipped when the bus was a bare no-op mock — is catchable, and enforces the convention that receivers register on their own `NS.NewBusTarget()`.

### The test framework

Intentionally minimal, defined inline in `tests/run.lua`: `test(name, fn)` registers a case; `assertEqual(got, want, msg)`, `assertTrue(cond, msg)`, and `assertFalse(cond, msg)` are the only assertions. Failures `error` with a source-level line, and the runner catches them per test so one failure never masks the rest.

## The suites

Thirteen files, loaded in this order (see **[test-cases.md](test-cases.md)** for the full per-case
inventory and the authoritative count):

| Suite | Covers |
|-------|--------|
| `test_util.lua` | pure helpers — time/link/loot-string parsing, table ops, `PlayerKey`; the secret-safe printer (`IsConcatSafe`/`SafeToString`/`NS.Print`, reclaimed from AceConsole) |
| `test_compat.lua` | `NS.Compat` shims — GUID decode, item/map info, degraded fallbacks |
| `test_attribution.lua` | source-resolution engine — context stamp/consume, TTL, confidence |
| `test_filters.lua` | `NS.Filters` blacklist/whitelist id lists — add/remove (mutually exclusive, copy-on-write), `IsBlacklisted`/`IsWhitelisted`, `SortedIDs`, `ParseItemID` |
| `test_auctionprice.lua` | `GatherAll` captures every enabled `provider:key` price into a nested map (per-provider Auctionator/TSM/OribosExchange, `pcall`-guarded so a broken addon is skipped not fatal, gated on the capture set + master switch, `nil` when nothing gathered); `Pick` resolves one via the `settings.auction.priority` cascade (reorder-aware, first present wins); `IsProviderAvailable`; `ReconcilePriority` appends missing / drops unknown tags; `SwapPriorityTags` reorders |
| `test_collector.lua` | `CHAT_MSG_LOOT` gate — self-filter, quality/quest-item threshold, record build |
| `test_database.lua` | Add/Query/Delete/PruneOld, retention rebuild-and-swap |
| `test_stats.lua` | `Stats`/aggregation feeding the Insights tab |
| `test_browsertable.lua` | filter→group→sort→slice pipeline, group headers/counts, test mode, `OrderedFilteredRecords` |
| `test_export.lua` | `Export:CSV` columns/quoting, friendly `bound`/`date`, `WowheadLink` bonus-ID parsing |
| `test_debuglog.lua` | `NS.Debug` tagged format + secret-safe sink, session-only flag, `/lh debug` toggles |
| `test_slash.lua` | `/lh list`/`get`/`set` slash-commands-§5 output — `FormatSchemaValue`/`FormatKV`/`BuildListLines`, grouping, Usage/not-found, `/lh version` |
| `test_schema.lua` | `NS.Schema` rows — `Set` validation + write-through, `Get`/`Default`, session-only rows (`state.debugConsole`) never touching `db.global` |

See [module-map.md](module-map.md) for the source files behind each suite and [compat-layer.md](compat-layer.md) for the shims `test_compat` exercises.

## Current status

The authoritative case count and full per-case inventory live in
**[test-cases.md](test-cases.md)** (generated by `lua tests/run.lua --list`). Re-verify the live
pass/fail at any time with the tail of `lua tests/run.lua`.

## Keeping the inventory & badge in sync

Whenever the suite changes — a case added, removed, or renamed, or the pass count moves (which is
exactly what resolving a test failure does) — you **MUST**, as part of the same change:

1. Regenerate the inventory: `lua tests/run.lua --list > docs/test-cases.md`.
2. Update the README `tests` badge (`![tests](https://img.shields.io/badge/tests-<pass>%2F<total>_passing-brightgreen)`)
   to the new count.

The inventory doc and the badge are part of the change, not a follow-up.

## Lint

`luacheck .` — must report **0 warnings / 0 errors** before every commit. Config is `.luacheckrc`: `std = "lua51"`, the WoW globals whitelisted under `read_globals`/`globals`, and `exclude_files = { "libs/", "_dev/", "tests/" }` (vendored libraries and the tests themselves are not linted; the `docs/reviews/` and `docs/audits/` bundles are Markdown-only, so `luacheck` never scans them). To syntax-check a single file without the full suite: `luac -p path/to/file.lua`.

## The green gate

Both checks run before every commit:

```
lua tests/run.lua     # all suites green (count: docs/test-cases.md)
luacheck .            # 0 warnings / 0 errors
```

A commit ships only when both are green.

## Toolchain install

The suite needs Lua 5.1 and luacheck (Debian/Ubuntu/WSL):

```
sudo apt-get update && sudo apt-get install -y lua5.1 luarocks
sudo luarocks install luacheck
```

`lua` must resolve to the 5.1 interpreter (`lua5.1`). `luac -p` uses the matching 5.1 compiler for single-file syntax checks.

## Tooling tests (Python)

`tools/` ships one dev-time helper, `build_report.py`, with its own stdlib-only
test suite (not part of the Lua green gate, not shipped in the addon):

```
cd tools && python3 -m unittest discover -s tests
```

These cover the CSV→`H` transcription, the INSIGHTS cross-check (including
value = Σ(val×qty)), the splice, and the verbatim head/tail verification.
