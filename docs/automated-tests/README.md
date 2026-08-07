# Automated test records

Every run of the four out-of-game suites, recorded. The normative rules are the standard's
[`automated-tests`](https://github.com/tusharsaxena/WowAddonStandards/blob/master/standards/standards/automated-tests.md)
section; this file is the local how-to.

## Running

```sh
tests/_kit/run-automated-tests.sh                            # all four, writes a bundle
tests/_kit/run-automated-tests.sh --suite complexity          # a subset
tests/_kit/run-automated-tests.sh --suite lint --suite tests --no-bundle   # the green gate; writes nothing
```

The runner is **vendored** from `LibKa0s`'s `testkit/` and is byte-identical in every Ka0s addon.
Never edit `tests/_kit/` — a kit fix goes upstream and is re-vendored, and a local patch is reverted
silently by the next re-vendor.

## What gates, and what only records

**Two checkpoints, and the answer differs between them.**

| Suite | Command | Gates the run + the commit? | Gates the tag? |
|---|---|---|---|
| `lint` | `luacheck .` | **yes** (testing-§4) | **yes** |
| `tests` | `lua tests/run.lua` | **yes** (testing-§4) | **yes** |
| `perf` | `lua tests/perf.lua` | no — recorded only | **yes** — at `pass` |
| `complexity` | `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` | no — recorded only | **yes** — at `pass`, zero functions above CCN 15 |

`perf` and `complexity` are **measured, recorded and diffed — never used to fail a run and never used
to block a commit.** A threshold that fails a run teaches everyone to reach for `--no-verify`, after
which the gate protects nothing and the habit remains. They contribute `amber`, which is a signal
rather than a stop.

**The tag is a different checkpoint**: it is gated on all four suites at `pass` plus zero functions
above CCN 15 (automated-tests-§3, *The release gate*), evaluated by `/wow-addon:bump-version` from
the release run's `manifest.json` — not by the runner, whose exit code stays the commit gate's.

**A missing tool is a skip, not a failure**, and the skip is recorded with its reason — so a green
run that measured nothing cannot be mistaken for a green run that measured everything. At the release
gate a skip is **NOT EVALUATED** rather than passed: install the tool and re-run.

## What is here

- **`RESULTS.md`** — one row per run across all four suites, plus the current complexity watch list.
  **One file, overwritten in place**: the git history of that single path is the trend line.
- **`<YYYYMMDD-HHMMSS>/`** — one frozen bundle per run: `manifest.json`, one file per suite, and
  `ANALYSIS.md` (the write-up). Bundles are **never edited** once written and **never pruned**.

Offline perf records live in the bundle with the run that produced them. **In-game** captures cannot
be produced by a script — a human runs the `perf` verb in a live client and exports the record — so in
a bracketed addon they keep their own standing store at `docs/perf-analysis/`: one frozen dated
bundle per capture, `<YYYYMMDD-HHMMSS>/`, holding `report.md`, `dump.json` and `ANALYSIS.md`, with
a `README.md` there carrying the schema summary and the pointer to the library's canonical record
contract (`performance-§8`).

**This addon has neither, deliberately.** It claims the `performance-§12` no-combat-path exemption,
which suspends `documentation-§3`'s `docs/perf-analysis/README.md` **and the `docs/perf-analysis/`
store itself** — an addon that brackets nothing produces no in-game captures to keep. The exemption is
ratified as a register row in [`../ARCHITECTURE.md`](../ARCHITECTURE.md#documented-deviations) and
explained on [`../performance.md`](../performance.md), the one part of the perf doc set the exemption
does **not** suspend. The `perf` column in `RESULTS.md` is a permanent `skip` for the same reason, and
`automated-tests-§3` requires the release notes to say so rather than let the skip read as measured.
