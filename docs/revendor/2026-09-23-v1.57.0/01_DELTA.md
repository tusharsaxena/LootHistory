Delta: LibKa0s v1.56.0 -> v1.57.0

# 01 — Delta

Run: 2026-09-24, plan item M5-LH of the 2026-09-23 review and standards-audit remediation (the
folder carries the plan's date, as `2026-09-23-v1.56.0/` does). Steps 2–4 of the local
`../wow-addon/commands/revendor-libka0s.md` were taken by hand and non-interactively by an
orchestrated session. Unlike RV-LH, the same item also owns the adoption (M5, the always-on launcher
status tooltip), so the one blocker below is cleared in the vendor commit, as the playbook asks. No
filing, no push. Target: this repo, branch `feat/2026-09-23-review-audit-remediation` @ `3eb4edf`.

Source: the sibling checkout `../LibKa0s`, **tag `v1.57.0` (tag object `d03e836` -> commit
`aa37bc9`)**, extracted with `git -C ../LibKa0s archive v1.57.0 LibKa0s testkit | tar -x -C <scratch>/`,
never the working tree. The tag is local to `../LibKa0s` and not yet pushed;
`tests/test_vendor_sync.lua` compares against the tag the provenance line names, so the local tag is
enough (it passes on this copy).

`git -C ../LibKa0s log --oneline v1.56.0..v1.57.0` lists 2 commits: `281f26f` (LK-36: Launcher
minor 3, the library always draws the status tooltip) and `aa37bc9` (LK-36: the v1.57.0 release run).

## Base pre-flight

The newest single-tag bundle, `docs/revendor/2026-09-23-v1.56.0/`, names base v1.55.0 and new
v1.56.0 on line 1, and the provenance line before this run named v1.56.0. The chain is unbroken, no
tag went unrecorded, and no span bundle is owed.

## 3a — Claimed version, before this run

`grep -n '[Bb]undles' CLAUDE.md` -> `CLAUDE.md:56`: Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s)
**v1.56.0** (MIT). No provenance line in `README.md`.

## 3b — Actual version, before this run

`grep -hoE 'local (MAJOR, )?([A-Z_]*MINOR) *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua` gives
v1.56.0's block (the left column of 3c), and kit revision 26 (`grep -n 'Kit.VERSION'
tests/_kit/framework.lua`). The line and the bytes agreed before the copy.

## 3c — Per-file minor delta

File list read from the tag's `LibKa0s/LibKa0s.xml` (21 `<Script>` rows, byte-identical to
v1.56.0); same grep on both sides.

| File | v1.56.0 | v1.57.0 |
|---|---|---|
| `Core.lua` | 8 | 8 |
| `Env.lua` | 1 | 1 |
| `Compat.lua` | 1 | 1 |
| `Lifecycle.lua` | 2 | 2 |
| `Bus.lua` | 2 | 2 |
| `Schema.lua` | 2 | 2 |
| `Pool.lua` | 3 | 3 |
| `Item.lua` | 2 | 2 |
| `Media.lua` | 4 | 4 |
| `Widgets.lua` | 10 | 10 |
| `WidgetsDragHandle.lua` | 2 | 2 |
| `DebugLog.lua` | 13 | 13 |
| `Slash.lua` | 15 | 15 |
| **`Launcher.lua`** | 2 | **3** |
| `Options.lua` | 24 | 24 |
| `OptionsWidgets.lua` | 31 | 31 |
| `OptionsTabs.lua` | 4 | 4 |
| `OptionsCompose.lua` | 7 | 7 |
| `OptionsScroll.lua` | 4 | 4 |
| `Perf.lua` | 13 | 13 |
| `PerfPanel.lua` | 5 | 5 |

One minor moves, no major changes, no file is added or removed.

## 3d — Both diffs

`diff -rq <scratch>/LibKa0s libs/LibKa0s` and `diff -rq --strip-trailing-cr` report the same one
file: `Launcher.lua` differs. No `Only in` line on either side. Content and bytes agree, so nothing
forked and there is no line-ending drift.

`diff -rq <scratch>/testkit tests/_kit` and the `--strip-trailing-cr` form are both empty: the kit
bytes are v1.56.0's (`git -C ../LibKa0s diff --stat v1.56.0 v1.57.0 -- testkit` is empty too).

After the copy (`rm -rf` then `cp -r` of both payloads, runner kept executable) both `diff -r` runs
are empty.

## 3e — Consumption map

Unchanged from the v1.56.0 bundle's 3e. The one major that moved is consumed here:

| Major | Lookup site | Minor moved? |
|---|---|---|
| Launcher | `core/LauncherSetup.lua:40` | 2 -> 3 |

Every other major keeps its minor, so the rest of the map receives unchanged bytes.

## 3f — Kit revision, and the pairing rule

`grep -n 'Kit.VERSION' <scratch>/testkit/framework.lua tests/_kit/framework.lua` -> **26 -> 26**.
Both payloads are copied whole in one commit, so the pairing rule holds by construction.

## 3g — Contract delta

`git -C ../LibKa0s diff --stat v1.56.0 v1.57.0 -- docs/api` adds
`docs/api/Launcher/version-3-docs.md` and `members-3.json` (the same member surface as
`members-2.json`); `version-2-docs.md` changes only header metadata. The CHANGELOG calls the release
additive: no `NEEDS_*` floor rises and no major changes. But one descriptor field changes meaning
under an unchanged signature, which makes it an adoption blocker rather than a candidate:

### Blocker — red on the copy, cleared in this commit

Run on the copy: 927 passed, 1 failed, 928 total; `luacheck .` 0 / 0 in 67 files.

1. **`onTooltipShow` now appends.** `tests/test_launcher.lua` failed: `launcher: while disabled the
   tooltip shows the refusal line in gray and no left-click hint`. From Launcher minor 3 the library
   owns the LDB object's `OnTooltipShow` and draws the title, the status lines and both click hints
   itself (`../LibKa0s/docs/api/Launcher/version-3-docs.md`, "What changed at this version"), calling
   the host's hook between them. This addon's hook drew a title, a spacer, both hints and the refusal
   line, so every one was drawn twice (anti-pattern #89) and the library's `Left-click:` line was
   present while the addon was off. Cleared here by the adoption below.

### Adoption (the M5-LH item, same commit)

`core/LauncherSetup.lua` passes, per "What a consumer owes" in the v1.57.0 CHANGELOG:

- `version`: `NS.Version()`, the TOC's `## Version` (core/EnvSetup.lua).
- `isLocked`: `B:IsLocked()`, reading `settings.locked`, the *Lock frame* row's store.
- `isTestMode`: `BrowserTable.testMode`, what the `state.testMode` row's own `get` reads.
- `leftClickLabel`: `NS.L["Toggle History window"]`, rung (a) (the browser) per the standard's
  `ADDONS.md` roster.
- `onTooltipShow`: cut to the record count alone.

Not passed: `slash`. The library reads `/lh` out of `disabledLine()` (`NS.Slash.DisabledLine()`,
which names `/lh enable`), so the field would be a second spelling of the command.
