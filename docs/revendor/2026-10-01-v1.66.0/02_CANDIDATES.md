# Candidates (LootHistory, v1.65.0 -> v1.66.0)

Sources: `git -C ../LibKa0s log --oneline v1.65.0..v1.66.0` (24 commits), the v1.66.0 CHANGELOG
block, and the `docs/api/<Major>/` documents of every major whose minor moved.

**Not interviewed this cycle.** The 2026-10-01 issue pass re-vendors all eleven addons and defers
adoption to its census item, GI-LK-13 (Ka0sAddonsCommonTasks
`docs/2026-10-01-GITHUB_ISSUE_PASS/02_SPEC.md` S4 and S5). The candidates are listed so the census
can pick them up; nothing here is adopted or declined.

## Class A: delivered on the re-vendor alone

- Kit revision 35's sighted complexity suite (`run-automated-tests.sh --suite complexity` now
  measures the sanitized shadow with function-count parity, and `-L 1500`). It revealed five
  functions above CCN 15 in this repo; they are GI-LH-01 / GI-LH-02's work.
- The four peels (WidgetsReorder, SlashParse, PerfSampler, PerfCommands) and DebugLog 19's
  `lib:New` helpers: no member moves.

## Class B: host change required

| # | Candidate | Evidence | Would touch | Recommendation | Blast radius |
|---|---|---|---|---|---|
| B1 | Slash `textOf` resolver: the host's `L` can word `ERR_BOOL` ... `NONE` | CHANGELOG v1.66.0 "Slash minor 19"; `docs/api/Slash/version-19.1-docs.md` | `locales/*.lua`, `settings/Slash.lua` | Low value: this addon's `L` carries none of those keys, and the library's English is already what it would say | additive |
| B2 | `O.RenderGrid(ctx, items, parent, opts)` with `opts.gap` | CHANGELOG "OptionsWidgets minor 34"; `docs/api/Options/version-27.2.34.2.2.7.1.7.4.2-docs.md` | none today (no `RenderGrid` call) | No: the AH Price table is a pooled host-drawn table, not a grid | additive |
| B3 | `RenderTabbedSchema` opts (`untabbedSkipRender`, `disabledReplaces`, `rerender`) | CHANGELOG "OptionsTabs minor 8" | none today (the General strip is the schema's own tab strip) | No candidate today | additive |

## Class C: whole-module adoption

- **Perf** (with the new per-bucket budgets): settled decline, performance-§12 no-combat-path
  exemption (`docs/combat-path-sweep.md`). The new version does not change the premise.
