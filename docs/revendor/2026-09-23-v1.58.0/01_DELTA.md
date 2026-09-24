Delta: LibKa0s v1.57.0 -> v1.58.0

# 01 — Delta

Run: 2026-09-25, plan item M6-LH of the 2026-09-23 review and standards-audit remediation (the
folder carries the plan's date, as `2026-09-23-v1.57.0/` does). Steps 2–4 of the local
`../wow-addon/commands/revendor-libka0s.md` were taken by hand and non-interactively by an
orchestrated session. As with M5-LH, the same item owns the adoption (M6, the launcher's
left-click-settings / right-click-menu ruling), so the blockers below are cleared in the vendor
commit, as the playbook asks. No filing, no push. Target: this repo, branch
`feat/2026-09-23-review-audit-remediation` @ `2008b51`.

Source: the sibling checkout `../LibKa0s`, **tag `v1.58.0` (tag object `93cf3ad` -> commit
`34931c9`)**, extracted with `git -C ../LibKa0s archive v1.58.0 LibKa0s testkit tests/mock_menu.lua |
tar -x -C <scratch>/`, never the working tree. The tag is local to `../LibKa0s` and not yet pushed;
`tests/test_vendor_sync.lua` compares against the tag the provenance line names, so the local tag is
enough (it passes on this copy).

`git -C ../LibKa0s log --oneline v1.57.0..v1.58.0` lists 2 commits: `02999d0` (LK-37: Launcher
minor 4, left-click settings, right-click options menu) and `34931c9` (LK-37: the v1.58.0 release
run).

## Base pre-flight

The newest single-tag bundle, `docs/revendor/2026-09-23-v1.57.0/`, names base v1.56.0 and new
v1.57.0 on line 1, and the provenance line before this run named v1.57.0. The chain is unbroken, no
tag went unrecorded, and no span bundle is owed.

## 3a — Claimed version, before this run

`grep -n '[Bb]undles' CLAUDE.md` -> `CLAUDE.md:56`: Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s)
**v1.57.0** (MIT). No provenance line in `README.md`.

## 3b — Actual version, before this run

`grep -hoE 'local (MAJOR, )?([A-Z_]*MINOR) *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua` gives
v1.57.0's block (the left column of 3c), and kit revision 26 (`grep -n 'Kit.VERSION'
tests/_kit/framework.lua`). The line and the bytes agreed before the copy.

## 3c — Per-file minor delta

File list read from the tag's `LibKa0s/LibKa0s.xml` (21 `<Script>` rows, byte-identical to
v1.57.0); same grep on both sides.

| File | v1.57.0 | v1.58.0 |
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
| **`Launcher.lua`** | 3 | **4** |
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

`diff -rq <scratch>/testkit tests/_kit` is empty: the kit bytes are v1.57.0's (and so v1.56.0's).

After the copy (`rm -rf` then `cp -r` of both payloads, runner kept executable) both `diff -r` runs
are empty.

## 3e — Consumption map

Unchanged from the v1.57.0 bundle's 3e. The one major that moved is consumed here:

| Major | Lookup site | Minor moved? |
|---|---|---|
| Launcher | `core/LauncherSetup.lua:42` | 3 -> 4 |

Every other major keeps its minor, so the rest of the map receives unchanged bytes.

## 3f — Kit revision, and the pairing rule

`grep -n 'Kit.VERSION' <scratch>/testkit/framework.lua tests/_kit/framework.lua` -> **26 -> 26**.
Both payloads are copied whole in one commit, so the pairing rule holds by construction.

## 3g — Contract delta

`git -C ../LibKa0s diff --stat v1.57.0 v1.58.0 -- docs/api` adds
`docs/api/Launcher/version-4-docs.md` and `members-4.json` (the same member surface as
`members-3.json`: "No member is added or removed"); `version-3-docs.md` changes header metadata and
`docs/api/README.md` its index row. No `NEEDS_*` floor rises and no major changes, but this is
**the first Launcher version to retire descriptor fields** (`onClick`, `leftClickLabel`,
`disabledLine`, `slash`, ignored if passed) and it changes both buttons under an unchanged
signature, so every change below is an adoption blocker rather than a candidate.

### Blockers — red on the copy, cleared in this commit

Run on the copy: 925 passed, 4 failed, 929 total.

1. **Left-click no longer runs `onClick`.** `launcher: RUNG (a) — left-click toggles the browser,
   the addon's own switch` failed: minor 4 calls `openSettings` on a left click on every host, so the
   History window was unreachable from the button (version-4-docs "Compatibility").
2. **The hints are fixed.** `launcher: the enabled tooltip is the library's block…` and
   `launcher: while disabled the tooltip still shows…` failed on `Left-click: Open settings` /
   `Right-click: Options menu`, where minor 3 drew `Toggle History window` and
   `disabled — /lh enable`.
3. **The disabled refusal is gone.** `slash-commands-§7 step 8: the left click is refused…` failed:
   a disabled left click now opens the panel and prints nothing.

### Adoption (the M6-LH item, same commit)

`core/LauncherSetup.lua` passes, per "What a consumer owes on re-vendoring v1.58.0" in the
CHANGELOG and the four entries `WowAddonStandards/standards/ADDONS.md` records for this addon
(`Enabled · Locked · Test mode · Show window (the History browser)`), which the code agrees with:

- `setEnabled(on)`: the `enable` / `disable` entry of `NS.COMMANDS` (each `/lh set settings.enabled
  <bool>` through `CliSet`), beside the existing `isEnabled`.
- `toggleLock`: `Schema:Set("settings.locked", not locked)`, the *Lock frame* row's own write. This
  addon has no `lock` / `unlock` verb, so the row's seam is the handler (launcher-§2 names "`lock` /
  `unlock` or the *Lock frame* row"). Beside M5's `isLocked`.
- `toggleTestMode`: the `test` entry of `NS.COMMANDS` (`BrowserTable:ToggleTestMode` plus its line).
  Beside M5's `isTestMode`.
- `isWindowShown` / `toggleWindow`: the History window's `IsShown`, and the `toggle` entry of
  `NS.COMMANDS` (`B:Toggle`).
- Removed: `onClick`, `leftClickLabel`, and `disabledLine` (retired and read by nothing; keeping it
  would be dead configuration, launcher-§5). `NS.Slash.DisabledLine` stays: the verb gate prints it.
- Kept: `version`, `isLocked`, `isTestMode`, `onTooltipShow` (the record count), `openSettings`.

The verb handlers are called through a file-local `runVerb`, which looks the verb up in
`NS.COMMANDS` at call time and calls `entry[3]` — the function `/lh <verb>` dispatches to, feature
gate included — rather than `B:Toggle` or `BT:ToggleTestMode` directly.

### Also arrived: the library's menu mock

`tests/mock_menu.lua` is not in the kit; version-4-docs ("Testing a host") asks a host that pins its
menu entries to install its own fake modeled on it. It is copied **verbatim** from the tag (a
provenance header prepended), with a `.luacheckrc` stanza scoping `212/self` and `432/self` to that
one file, which is how LibKa0s lints the same bytes.
