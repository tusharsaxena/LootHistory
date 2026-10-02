Delta: LibKa0s v1.66.0 -> v1.67.0

# The delta (LootHistory)

Copied from the tag `v1.67.0` (`0bccf4c`, local tag; the LibKa0s checkout was at that commit with a
clean tree), never from a branch tip: `git -C ../LibKa0s archive v1.67.0 LibKa0s testkit | tar -x -C
<scratch>`, then both folders copied whole with deletion. Part of the 2026-10-02 LibKa0s census
adoption (Ka0sAddonsCommonTasks `docs/2026-10-02-LIBKA0S_CENSUS_ADOPTION/`, item CA-LH-RV).

## Claimed and actual version

- `grep -n '[Bb]undles' CLAUDE.md`: the provenance line claimed v1.66.0.
- `git log --format=%h -1 --grep=-RV:` is `9c3829c` (GI-LH-RV), whose CLAUDE.md names v1.66.0, and
  `tests/test_vendor_sync.lua` passed against v1.66.0 before the copy.
- Pre-flight: the newest single-tag bundle, `2026-10-01-v1.66.0`, states base v1.65.0. No correction
  owed, and no vendored tag is unrecorded, so no span bundle.

## libs/LibKa0s (`diff -rq`, before the copy)

Changed: `Core.lua`, `Options.lua`, `OptionsIdList.lua`. No `Only in` line on either side, so
nothing is added or deleted. `git -C ../LibKa0s diff --stat v1.66.0 v1.67.0 -- LibKa0s testkit`:
3 files changed, 125 insertions(+), 36 deletions(-).

| File | Constant | v1.66.0 | v1.67.0 |
|---|---|---|---|
| `Core.lua` | `MINOR` | 9 | 10 |
| `Options.lua` | `MINOR` | 27 | 28 |
| `OptionsIdList.lua` | `IDLIST_MINOR` | 2 | 3 |

No `NEEDS_*` floor rises, no major is added and no member is added (Core's degradation stubs are
untouched). The payload stays at 32 files, so neither `LibKa0s.xml` nor `tests/test_libka0s.lua`'s
`LIB_FILES` list moves.

## tests/_kit

`Kit.VERSION` 35 -> 35: `diff -rq` of the tag's `testkit/` against `tests/_kit/` is empty. The copy
was still made whole (the kit-revision pairing rule), and changed nothing.

## Line endings

As at GI-LH-RV: the archive is written through LibKa0s's own `.gitattributes`, so `.lua`, `.xml`
and `.md` land CRLF, `run-automated-tests.sh` LF, and media binary. This repo's `.gitattributes`
(`* text=auto eol=crlf`, `*.sh eol=lf`) stores them the same way.

## After the copy

`diff -r` (bytes, no strip) of the tag's `LibKa0s/` against `libs/LibKa0s/` and of `testkit/`
against `tests/_kit/`: both empty.

## Contract delta (3g)

Majors that moved a minor and that this addon consumes: Core, Options.

- **Core 9 -> 10**: `MakeResizable` takes three more optional `opts` fields, `canResize`,
  `onResizeStop` and `gripParent` (`docs/api/Core/version-10-docs.md`, "The resize grip"). Absent,
  the grip behaves exactly as minor 9. This addon does not call `MakeResizable` today (`grep -rn
  MakeResizable core modules settings`: none); the library's own callers (DebugLog's console,
  Widgets' `CopyWindow`, PerfPanel) pass none of the three, so they are unchanged.
- **Options 27 -> 28 / OptionsIdList 2 -> 3**: Options 28 is a docblock change only (`addonName` is
  now RECOMMENDED for every host). OptionsIdList 3 takes the descriptor's `addonName` for the
  per-entry help art only when the client reports that addon loaded, and writes one `Cfg` line
  through the descriptor's `debug` when the ladder falls past that rung. This addon's descriptor
  (`settings/OptionsSetup.lua:171`) passes no `addonName`, and its one `O.IdList`
  (`settings/Panel.lua:336`) draws no help marks, so the help ladder is never asked and nothing is
  logged or drawn differently.

**Blockers: none.**

## Consumer tests that moved with the library

- `tests/test_vendor_sync.lua` (the kit's `vendor_sync.lua`) "libs/LibKa0s is the LibKa0s release CLAUDE.md says this addon
  bundles" failed after the copy until the provenance line rolled; it rolled in the same commit.

No other consumer test moved: no pin in this repo names Core 9, Options 27 or OptionsIdList 2.
