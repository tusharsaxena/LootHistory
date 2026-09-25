# 02 — Candidates

Sources: `git -C ../LibKa0s log --oneline v1.58.0..v1.60.0` (17 commits), the v1.59.0 and v1.60.0
blocks of the tag's `CHANGELOG.md`, and the `Since` markers of `docs/api/DebugLog/version-14.1-docs.md`,
`docs/api/Slash/version-16-docs.md` and `docs/api/Widgets/version-10.3-docs.md`. The three blockers
in `01_DELTA.md` §3g are not listed here: they were fixed in the vendor commit.

## A. Delivered on the re-vendor alone

| Item | Evidence | Reaches the addon as |
|---|---|---|
| The 3000-line console buffer (`MAX_BUFFER` 1500 -> 3000, `BUFFER_SLACK` 64 -> 128) | CHANGELOG v1.60.0, *DebugLog minor 14*; `version-14.1-docs.md` *Compatibility* | The console keeps twice the lines. No host code reads either constant. The owner's measurement (DR-OW-02) chose 3000. The plan says this is not an adoption. |
| `lib.TIME_COPY` copy-timing switch | CHANGELOG v1.60.0, *DebugLog minor 14* | Off by default and never saved; a maintainer turns it on with `/run`. |
| `diagnostics` in `lib.LIVE_VERBS` | `version-16-docs.md`, *What changed* | Delivered to the library's own gate (this addon passes no `liveVerbs`). The host's literal copy moved in the vendor commit (blocker 2). |

## B. Host change required: candidates

| # | Candidate | Evidence | Files it would touch | Blast radius | Plan's answer |
|---|---|---|---|---|---|
| B1 | The diagnostics report: `D:RunDiagnostics` / `BuildDiagnostics` / `DebugVerb`, the `brandName` and `diagnostics` descriptor fields, `Kit.diagnostics` wiring | CHANGELOG v1.60.0, *DebugLogDiagnostics minor 1* and *Test kit revision 27*; `version-14.1-docs.md:525-526` | new `modules/Diagnostics.lua`, `core/DebugLogSetup.lua`, `settings/Schema.lua` (COMMANDS row, `debug` word), `LootHistory.toc`, `tests/run.lua`, tests | Additive | **Adopt in DR-LH-03** |
| B2 | Slash 16's `diagnostics` verb registration (the verb itself, live while disabled) | `version-16-docs.md` | `settings/Schema.lua`, degraded dispatcher in `settings/Slash.lua` | Additive | **Adopt in DR-LH-03**, with B1 |
| B3 | WidgetsDragHandle minor 3's close mark (`spec.onClose`) | CHANGELOG v1.59.0; `docs/api/Widgets/version-10.3-docs.md` | none: this addon builds no `DragHandle` | n/a | **Not a candidate here**: the plan scopes it to ConsumableMaster and AbsorbTracker (DR-OW-03) |

## C. Whole-module adoption

Perf is the one unconsumed major, and v1.60.0 does not move it. Its decline is settled
(performance-§12, `docs/ARCHITECTURE.md` -> Documented deviations), and no premise moved.
