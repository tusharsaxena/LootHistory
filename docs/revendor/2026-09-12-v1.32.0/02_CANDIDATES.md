# 02 — Candidates: LibKa0s v1.31.0 → v1.32.0

Sources:

```sh
git -C ../LibKa0s log --oneline v1.31.0..v1.32.0
#   e18dd12 The v1.32.0 release record, re-taken on the final tree
#   c6314d6 CLAUDE.md: the luacheck scope is fifty-four files at v1.32.0
#   4083889 v1.32.0 review: bulkEnd's info names a profile reset (debug-logging-§10 final ruling)
#   4353908 The v1.32.0 release record
#   f7d78cd v1.32.0: Options 16 and Slash 8 bracket their reset walks (debug-logging-§10)
git -C ../LibKa0s show v1.32.0:CHANGELOG.md                        # "## v1.32.0 — 2026-09-12"
git -C ../LibKa0s show v1.32.0:docs/api/Slash/version-8-docs.md
git -C ../LibKa0s show v1.32.0:docs/api/Options/version-16.15.4.3-docs.md
```

The release adds one surface to two consumed majors: an optional descriptor bracket, `bulkBegin(act,
scope)` / `bulkEnd(act, scope, count, err, info)`. It exists so a host can meet standard v2.44.0
`debug-logging-§10`: a bulk reset through the helper is one `[Set] <act> <scope>: N rows` line, never
one per row.

## Class A — delivered on the re-vendor alone

Nothing. A host that supplies neither field runs the v1.31.0 walk exactly, and the gate confirms it:
727 / 727 before and after the copy.

## Class B — host change required

### B1. Slash minor 8: the bracket around `CliResetAll`

- **Reached.** Both the General page's **Defaults** (`P:RestoreDefaults`, `settings/Panel.lua:1008`,
  which the Blizzard footer's `OnDefault` forwarder also calls) and `/lh resetall` go through
  `NS.Slash:CliResetAll` → `Dispatcher:CliResetAll` (`settings/Slash.lua:336`). Before the adoption each
  press logged 16 `[Set] <path> = <value>` lines, one per schema row.
- **Recommendation.** Adopt. `debug-logging-§10` is a MUST and the survey in the rollout brief names
  this act.

### B2. Options minor 16: the bracket around `RestoreDefaults` / `RestoreAllDefaults`

- **Not reached.** `grep -rn "RestoreDefaults\|RestoreAllDefaults" core modules settings` finds only
  the degradation stub's no-ops (`settings/OptionsSetup.lua:65`) and the host's own `P:RestoreDefaults`.
  The one Options page sets `defaultsOnClick` to `P:RestoreDefaults`; the footer `OnDefault` forwards
  to it; the Master controls **Reset all settings** is the host's `onResetAll`. No path calls the
  library's walks.
- **Recommendation.** Decline for now, and record why beside the Slash wiring. Adding an unreached
  bracket would be untestable here.

### B3. `Sl:ResetEverything` — does it need a `[Set]` line?

- **No.** It empties `db.global` in place and merges `NS.defaults.global` back (`wipeGlobal`,
  `settings/Slash.lua:111`); it never calls `Schema:Set`. It is wholesale replacement, the no-profile
  form of `options-ui-§12`, not a walk through the helper. Its one `[Data] reset-all removed N rows`
  line stays, and a new case pins that it writes no row through the seam and logs no `[Set]` line.

### B4. Degradation stubs

- **Nothing to add.** No instance member is added at either minor (the CHANGELOG says so), and
  `tests/test_surface_parity.lua` passes on the copy. The degraded Slash `CliResetAll` walks no rows,
  so it has nothing to bracket.
