Delta: LibKa0s v1.67.0 -> v1.68.0

# The delta (LootHistory)

Copied from the local annotated tag `v1.68.0`, never from a branch tip: `git -C ../LibKa0s archive
v1.68.0 LibKa0s testkit | tar -x -C <scratch>`, then both folders copied whole. The LibKa0s working
tree sat on `feat/2026-10-02-drag-attach` at the tag commit, and `git -C ../LibKa0s diff --quiet
v1.68.0 -- LibKa0s testkit` exited 0. Part of the 2026-10-02 LibKa0s tooltip-place sweep
(Ka0sAddonsCommonTasks `docs/2026-10-02-LIBKA0S_TOOLTIP_PLACE/`, item TP-LH-01).

The run was non-interactive: the owner delegated every decision for this sweep, so the decisions in
`03_DECISIONS.md` are the executor's, with the reasoning written down.

## Claimed and actual version (3a, 3b)

- `grep -n '[Bb]undles' CLAUDE.md`: line 56 claims v1.67.0.
- `git log -1 --format=%H -- libs/LibKa0s tests/_kit` is `c47d050` (CA-LH-RV, "re-vendor LibKa0s
  v1.67.0"), whose CLAUDE.md names v1.67.0. `git log c47d050..HEAD -- CLAUDE.md` lists nothing, and
  `diff -rq` of the v1.67.0 archive against both payloads printed `payload-matches`. Base: v1.67.0.
- Pre-flight (Step 0) for this addon: the newest single-tag bundle, `2026-10-02-v1.67.0`, states base
  v1.66.0, and the provenance before `c47d050` was v1.66.0. `ok`, so no correction is owed.
- Span check (3h, horizon 2026-08-25): the vendored-minus-recorded listing is empty, so no span
  bundle.
- The minors on disk (3b) match v1.67.0's in every file, so the line and the bytes agreed.

`git -C ../LibKa0s log --oneline v1.67.0..v1.68.0`: DA-LK-01 (`2cc8a03`, WidgetsDragHandle minor 4,
`tooltipPlace`), DA-LK-02 to DA-LK-07R (release records, the test split, CHANGELOG and doc rows),
and the census merge's tail (CA-LK-04, CA-LK-04R, CA-FIN-02). `git -C ../LibKa0s diff --stat v1.67.0
v1.68.0 -- LibKa0s testkit`: one payload file, `LibKa0s/WidgetsDragHandle.lua`.

## Per-file minors (3c)

From the tag's `LibKa0s/LibKa0s.xml` (32 files). One file moved; the other 31 are unchanged.

| File | Constant | v1.67.0 | v1.68.0 |
|---|---|---|---|
| `WidgetsDragHandle.lua` | `DRAG_MINOR` | 3 | 4 |

No file is new (no empty `old:` column), so neither `LibKa0s.xml` nor `tests/test_libka0s.lua`'s
`LIB_FILES` list moves. No consumer file is behind the tag, so no cross-major skew.

## Diffs before the copy (3d)

- `diff -rq --strip-trailing-cr <tag>/LibKa0s libs/LibKa0s`: `WidgetsDragHandle.lua` differs (content).
- `diff -rq <tag>/LibKa0s libs/LibKa0s` (bytes): the same single file.
- `diff -rq` of `<tag>/testkit` against `tests/_kit`, with and without `--strip-trailing-cr`: empty.
- No `Only in` line on either side, so nothing is added or deleted.

## Consumption map (3e)

Lookup sites outside `libs/` and `tests/`: Item (`core/ItemSetup.lua:26`), DebugLog
(`core/DebugLogSetup.lua:25`), Core (`core/CoreSetup.lua:44`), Env (`core/EnvSetup.lua:42`), Compat
(`core/Compat.lua:102`), Bus (`core/Constants.lua:207`), Launcher (`core/LauncherSetup.lua:42`), Media
(`core/MediaSetup.lua:57`), Lifecycle (`core/LifecycleSetup.lua:47`, `modules/Diagnostics.lua:129`),
Pool (`core/PoolSetup.lua:22`), Widgets (`core/WidgetsSetup.lua:85`), Options
(`settings/OptionsSetup.lua:47`), Slash (`settings/Slash.lua:110`), Schema (`settings/Schema.lua:687`).
Unchanged from the v1.67.0 run. Perf has no lookup: a settled decline (performance-§12 no-combat-path
exemption, `docs/combat-path-sweep.md`); v1.68.0 does not touch Perf, so the premise has not moved.

Widgets is consumed, but only for `Dropdown`, `ReorderList` and `CopyWindow` through
`core/WidgetsSetup.lua`. `grep -rn 'DragHandle' --include='*.lua' core modules settings` finds no
call: this addon builds no drag strip.

## Kit revision (3f)

`Kit.VERSION` 35 -> 35 (`grep -n 'Kit.VERSION'` on both `framework.lua`). The kit is byte-identical,
and is still copied whole, because the pairing rule (LibKa0s v1.9.0 or newer needs kit revision 11 or
newer in the same commit) is why the two payloads travel together.

## Contract delta (3g)

Majors that moved a minor and that this addon consumes: Widgets (12.1.3 -> 12.1.4).

`diff` of `docs/api/Widgets/version-12.1.3-docs.md` at v1.67.0 against `version-12.1.4-docs.md` at
v1.68.0: the header rows, the new "What changed at 12.1.4" section (lines 18-48), the census restamp
v1.66.0 -> v1.67.0 (lines 467-471), the `tooltipPlace` spec row (line 692), its prose and sketch
(lines 725-746), and the descriptor's `place` field (line 756). Every new surface is marked **Since
4** and optional. The one sentence that bears on existing hosts says the opposite of a tightening:
"Without a hook nothing changes. A host that sets neither field gets minor 3's calls in minor 3's
order" (line 44), and "What a host must change: nothing" (line 47).

`grep -rn '__Attach[A-Za-z]*' --include='*.lua' --exclude-dir=libs --exclude-dir=Libs
--exclude-dir=_kit .`: no site. This addon hands the library no callback members through an attach
point, and it calls no `DragHandle`, so no host-supplied member's call site moved.

**Blockers: none.**

## Line endings

The archive is written through LibKa0s's own `.gitattributes`, so `.lua`, `.xml` and `.md` land
CRLF, `run-automated-tests.sh` LF, and media binary. This repo's `.gitattributes` (`* text=auto
eol=crlf`, `*.sh eol=lf`) stores them the same way, so the byte diff and the content diff agree.

## After the copy

`diff -r` of the tag's `LibKa0s/` against `libs/LibKa0s/` and of `testkit/` against `tests/_kit/`,
both with and without `--strip-trailing-cr`: all four empty.

## Consumer tests that moved with the library

- `tests/test_vendor_sync.lua` ("libs/LibKa0s is the LibKa0s release CLAUDE.md says this addon
  bundles") reads the provenance line, which rolled to v1.68.0 in the same commit as the bytes.

No other consumer test pins `DRAG_MINOR` or `WidgetsDragHandle`'s minor (`grep -rn 'DRAG_MINOR'
tests/*.lua`: none; `tests/test_libka0s.lua:42` lists the file only by path).
