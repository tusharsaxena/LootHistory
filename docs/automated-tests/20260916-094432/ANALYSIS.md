# Analysis — 20260916-094432

- **Addon:** LootHistory 1.3.0
- **Verdict:** green
- **Commit:** af217b5032d43a7608d2bc988823ee4dc93fb38a (master), clean
- **Previous run:** [`20260910-234511`](../20260910-234511/)

## Headline

The two gating suites are clean — `luacheck` 0/0 over 59 files and 768 of 768 cases passing with no
skips — so the run and the commit gate are green. The two recorded suites are where the news is:
`lizard` warned for the first time since the `20260804-182216` baseline, with `Sl:ResetEverything`
at CCN 16, and `tests/test_panel.lua` crossed `layout-§1`'s 1500-line cap at 1655. Neither fails this
run, but the CCN warning **would** fail the tag gate as it stands, so both are owed a fix before the
next version bump.

## Suites

| Suite | Status | Result | Artifact | Moved since `20260910-234511` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 59 files | [`lint.txt`](lint.txt) | Unchanged — same 0/0 over the same 59 files. |
| tests | pass | 768 passed, 0 skipped, 0 failed, 768 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | +48 cases (720 → 768); still zero skips, so passed and total agree. |
| perf | skip | no scenarios — this addon ships no `tests/perf.lua` | — (no artifact) | Unchanged — a standing skip, not a new gap. |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | Max CCN 15 → **16**; warnings 0 → **1**; over-cap files 0 → **1**. |

Every figure above comes from [`manifest.json`](manifest.json).

**Complexity in full** — all eight of `lizard`'s footer fields plus the derived counts, from
`manifest.json`'s `suites.complexity`:

| Metric | Value |
|---|---|
| Total NLOC | 14889 |
| Functions | 1980 |
| Avg NLOC / function | 6.4 |
| Avg CCN | 2.2 |
| Max CCN | 16 |
| Avg tokens / function | 51.9 |
| Warnings (CCN > 15) | 1 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 4 |
| Files over the 1500 cap | 1 |

**`perf` — skipped, and that is a standing fact rather than a tooling gap.** The runner reports
`no tests/perf.lua — this addon ships no offline scenarios`, which is the first of
`automated-tests-§3`'s two sanctioned reasons (*nothing to run*), not a ratified `performance-§12`
no-combat-path exemption. Nothing was measured about runtime cost in this run, so nothing in this
bundle says LootHistory is fast or cheap — only that the question was not asked. A Lua 5.1
interpreter, `luacheck` 1.2.0 and `lizard` 1.24.0 were all present, so no suite was skipped for a
missing tool.

**`complexity` — a pass that carries two new findings.** The suite does not gate, and a warning
count never fails a run. What it recorded is a regression against the previous run on two axes, both
ruled on in `RESULTS.md`'s watch list and summarised under *Actions*.

## What moved

- **lint** — nothing. 0 warnings / 0 errors over 59 files at both runs, with the same `.luacheckrc`
  exclusions (`libs/`, `docs/audits/`, `docs/reviews/`, `_dev/`, `tests/_kit/`) out of scope.
- **tests** — 720 → 768 passed, +48 cases, still 0 failed and 0 skipped. The suite grew alongside the
  addon this cycle rather than standing still, which is the shape the coverage check wants.
- **perf** — no change: skipped at both runs, for the same reason.
- **complexity, size** — total NLOC 13892 → 14889 (+997) and functions 1810 → 1980 (+170). Those are
  growth, not density: avg NLOC / function went **down** 6.5 → 6.4 and avg tokens / function down
  52.7 → 51.9, so the addon got bigger while its average function got slightly smaller.
- **complexity, density** — avg CCN held at 2.2, but max CCN moved 15 → 16 and the warning count 0 → 1.
  Seven functions now sit at exactly 15, one over. A flat average with a moving maximum is a local
  finding, not a drift in the codebase as a whole.
- **complexity, file bands** — band files 5 → 4 and over-cap files 0 → 1: `tests/test_panel.lua` did
  not leave the watch list, it moved up a band, from 1030 into breach at 1655.

One carry-forward note for the next reader: the runner carries an unchanged Disposition verbatim, so
the prose in the band rows for `modules/Browser.lua`, `modules/BrowserTable.lua` and
`settings/Panel.lua` still quotes the line counts of the run that authored it (1289, 1173, 1056)
while the generated LOC column now reads 1307, 1225 and 1062. The column is this run's measurement;
the sentence is the older run's argument, and it is still true.

## Complexity watch list

Both tables, with this run's dispositions, are in
[`../RESULTS.md`](../RESULTS.md) — the runner generates them there and the `Disposition` cells are the
one authored part of the record (`automated-tests-§4`). In summary:

| Function | CCN | Location | Disposition |
|---|---|---|---|
| `Sl` (`Sl:ResetEverything`, `@139-163`) | 16 | `settings/Slash.lua` | **Peel next — release-gate blocker.** Dense guarding, not tangled control flow. |

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1178 | Peel next; carried, and now unactioned across six runs. |
| 1000–1500 (on notice) | `modules/Browser.lua` | 1307 | Accepted — own disposition, `LH-37`. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1225 | Accepted. Re-check at 1300 — now 1225. |
| 1000–1500 (on notice) | `settings/Panel.lua` | 1062 | Accepted. Re-check at 1200. |
| > 1500 (over cap) | `tests/test_panel.lua` | 1655 | **Newly over cap.** Split by tab; nothing tracks it yet. |

Two shelf-life notes, per `automated-tests-§4` and anti-pattern #53. `modules/Analytics.lua` has now
carried *Peel next* without moving for six consecutive runs, which is past the point where a
disposition is still a decision; it is owed either the peel or a tracked ID with an owner.
`modules/BrowserTable.lua` was accepted with *Re-check at 1300* and is at 1225 — still inside its own
condition, so the acceptance stands unchanged this run rather than being re-argued.

## Actions

1. **`settings/Slash.lua` — reduce `Sl:ResetEverything` below CCN 15.** It is 21 NLOC of
   `if NS.X and NS.X.Method then` existence guards, every `and` counted as a decision by `lizard`, so
   the fix is to lift the post-wipe refresh fan-out into a helper rather than to simplify any logic.
   This is the one item that blocks a release: the tag gate is all four suites plus zero functions
   above CCN 15, evaluated by `/wow-addon:bump-version` from a release run's `manifest.json`.
2. **`tests/test_panel.lua` — split it back under the 1500-line cap.** 1655 lines, 1168 NLOC over 122
   functions, so it is case count rather than tangle; the seam is the panel's own tabs. New here and
   untracked in the addon's own issue store, so it needs an issue if the split is not taken directly.
3. **`modules/Analytics.lua` — convert *Peel next* into work or into a tracked ID.** Six runs carried,
   still effectively flat at 1178 lines, still nothing owning it.
4. **`perf` — decide whether this addon wants offline scenarios at all.** The skip is sanctioned, but
   it means every row of `RESULTS.md` is silent about runtime cost; that is a choice worth making
   explicitly rather than by default.
