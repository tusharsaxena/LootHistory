Delta: LibKa0s v1.62.0 -> v1.63.0

# The delta (LootHistory)

Copied from the tag `v1.63.0` (`dd7a774`, local annotated tag), never from a working tree:
`git -C ../LibKa0s archive v1.63.0 LibKa0s testkit | tar -x -C <scratch>`.

## Claimed and actual version

- `grep -n '[Bb]undles' CLAUDE.md`: the provenance line claimed v1.62.0.
- `git log -1 --format=%H -- libs/LibKa0s tests/_kit` is `93e879d` (LH-ATS-RV), whose CLAUDE.md
  names v1.62.0. The payload today equals `git archive v1.62.0` byte for byte (`diff -rq` against
  both folders: `payload-matches`). No line/bytes disagreement.
- Pre-flight: the newest bundle, `2026-09-26-v1.62.0`, states base v1.61.0, and the provenance line
  before `93e879d` named v1.61.0 (`191765a`). No correction owed.
- No unrecorded vendored tag: every tag the provenance line has named since the store's horizon has
  a bundle, so no span bundle is written.

## libs/LibKa0s (`diff -rq --strip-trailing-cr`, before the copy)

```
Files <tag>/LibKa0s/Slash.lua and libs/LibKa0s/Slash.lua differ
```

The byte diff (`diff -rq`, no strip) named the same file: no line-ending-only drift. No
`Only in libs/LibKa0s` line, so nothing is deleted. `git -C ../LibKa0s diff --stat v1.62.0 v1.63.0
-- LibKa0s testkit`: `LibKa0s/Slash.lua | 131 ++++-`, one file.

| File | Constant | v1.62.0 | v1.63.0 |
|---|---|---|---|
| `Slash.lua` | `MINOR` | 16 | 17 |

Every other file keeps its minor (the per-file loop over the tag's `LibKa0s.xml` prints only
`Slash.lua`). No `NEEDS_*` floor rises and no major is added (v1.63.0 CHANGELOG).

## tests/_kit

`Kit.VERSION` 31 -> 31 (`grep -n 'Kit.VERSION' testkit/framework.lua tests/_kit/framework.lua`).
`diff -rq` with and without `--strip-trailing-cr`: empty. The kit did not move; both payloads are
still copied whole in one commit (the kit-revision pairing rule).

## Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/`:
Bus, Compat, Core, DebugLog, Env, Item, Launcher, Lifecycle, Media, Options, Perf, Pool, Schema,
Slash, Widgets. Only `LibKa0s-Slash-1.0` moved a minor, and this addon consumes it
(`settings/Slash.lua`).

## Blockers (contract delta)

None. `docs/api/Slash/version-17-docs.md` (Compatibility) states the release is additive: a
descriptor field (`profiles`), two instance members (`CliProfile`, `ProfileSwitch`), one lib-level
function (`ProfileNames`) and nine `lib.STRINGS` keys. `lib.LIVE_VERBS` is unchanged, and a host
that passes no `profiles` and registers no `profile` row sees no change. The same section measured
LootHistory green on the copy alone: its parity case (`tests/test_surface_parity.lua`) uses the
four-argument form over two tables the host builds, so the new instance members do not reach it.
`grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit` finds no
host call site.
