# CLAUDE.md — Ka0s Loot History

**Ka0s WoW addon.** Adheres to the **Ka0s WoW Addon Standard** —
<https://github.com/tusharsaxena/WowAddonStandards>

## Standards compliance (read first)

This repo is built to the **Ka0s WoW Addon Standard** (URL above). All development here — features,
refactors, doc changes — MUST conform to it. The standard is the source of truth for layout, TOC
shape, the Ace substrate, schema-driven settings, slash/prefix conventions, locales, Compat,
tests/lint, and doc structure.

**If a change would deviate from the standard, STOP and flag the deviation explicitly.** Do not
silently deviate and do not silently "fix" to match. Surface it and let the user decide which of
two things it is:

1. **An accepted deviation** — this addon intentionally differs; record it as a row in
   [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) → `## Documented deviations`, shaped
   `| Rule | What differs | Why | Decided | Re-check trigger |`, where Rule is the `filename-§N`
   reference. That register is the single home: the reasoning may live in
   this repo's GitHub issues or an audit bundle and the row cites it, but a
   deviation not in the register is not ratified.
2. **A change to the standard itself** — the standard's definition should evolve; the update belongs
   upstream in the WowAddonStandards repo, after which this addon conforms to the new rule.

When in doubt, treat conformance as a hard requirement and ask.

## Read the docs

This file is a stub (documentation-§2). The full context lives in `docs/` — read these before
touching code:

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — what this addon is: module map, data model,
  message bus, slash surface, event wiring, taint notes, known limitations, the documented-deviations
  register, and the **`## Documentation map`** listing every page under `docs/` (`documentation-§3`). **Start here.**
- **[docs/testing.md](docs/testing.md)** — how to verify: the headless harness, the mock, the vendor
  gate, lint, and the green gate.
- **[docs/data-flow.md](docs/data-flow.md)** — **required** before touching capture or source
  code (the `CHAT_MSG_LOOT` + `lootContext` engine).
- **[docs/common-tasks.md](docs/common-tasks.md)** — the file-by-file rules: namespace preamble, module
  publishing, object pooling, hot-path upvalues.
- **[DEPENDENCIES.md](DEPENDENCIES.md)** (root) — the toolchain contract: what to install to run,
  test or release this addon.
- Everything else — `scope.md`, `module-map.md`, `schema.md`,
  `message-bus.md`, `browser.md`, `settings-panel.md`, `slash-dispatch.md`, `compat-layer.md`,
  `midnight-quirks.md`, `performance.md`, `smoke-tests.md`, `test-cases.md`,
  `automated-tests/` — is listed in ARCHITECTURE.md's `## Documentation map`, which also records which conditional docs do not apply here.

## Vendored LibKa0s

Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.8.1 (MIT) — the Ka0s-owned shared
library behind the chat printer, the debug console, the slash-command interface and the settings
panel, vendored whole-folder into `libs/LibKa0s/` with its test kit under `tests/_kit/`.

That line is not decoration. `tests/test_vendor_sync.lua` greps this file for it, resolves the tag
it names, and diffs both vendored payloads against what LibKa0s published at that tag — so a
provenance line and a payload that disagree fail the run. **Bump the line and re-vendor the bytes in
the same commit**; a maintainer's question about which build carries which library is answered here
rather than in the player-facing README.

## Green gate

Run `lua tests/run.lua` and `luacheck .` (0/0) before every commit; in-game checks are in
[docs/smoke-tests.md](docs/smoke-tests.md).
