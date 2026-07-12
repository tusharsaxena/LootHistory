# CLAUDE.md — Ka0s Loot History

**Tier 2 (modular)** WoW addon. Adheres to the **Ka0s WoW Addon Standard** —
https://github.com/tusharsaxena/WowAddonStandards

Start here, then read the docs:

- **`docs/AGENT_CONTEXT.md`** — the full agent brief (stack, layout, conventions cheat-sheet,
  standards-compliance notes, "do not change without reason").
- **`docs/ARCHITECTURE.md`** — module map, data model, message bus, slash surface, event wiring.
- **`docs/TECHNICAL_DESIGN.md`** · **`docs/REQUIREMENTS.md`** · **`docs/UX_DESIGN.md`** — design depth.

Green gate before every commit: `lua tests/run.lua` and `luacheck .` (0/0). See `docs/AGENT_CONTEXT.md`
for the local dev/test toolchain.
