Delta: LibKa0s v1.70.0 -> v1.71.0

Run by the 2026-10-07 review-and-audit remediation (item `RV-LH`) on branch
`feat/2026-10-07-review-audit-remediation`. The re-vendor is mechanical; adoption of new surfaces is out
of scope for this run (owner scope 5), so no interview ran.

## Source

```sh
git -C ../LibKa0s rev-parse --short 'v1.71.0^{commit}'   # cb274a4
git -C ../LibKa0s archive v1.71.0 LibKa0s testkit | tar -x -C <scratch>
```

v1.71.0 is a LOCAL annotated tag only (not pushed, no GitHub release), so there is no release or
compare URL. The payload is taken from the tag through `git archive`, never from the working tree.

## Base

The CLAUDE.md provenance line named v1.70.0, which this repo already recorded in
`docs/revendor/2026-10-07-v1.70.0/` (and v1.69.0 in `docs/revendor/2026-10-06-v1.69.0/`). No vendored
tag went unrecorded, so no consolidated span bundle is needed. LootHistory is not in cluster C03.

## Per-file minor delta

- `Env.lua`: Env minor 1 -> 2.
- `Slash.lua` / `SlashParse.lua`: `LibKa0s-Slash-1.0` key 19.1 -> 20.2 (Slash 20, SlashParse 2).
- `WidgetsLineChart.lua`: minor 2 -> 3; `WidgetsAutocomplete.lua`: minor 1 -> 2
  (`LibKa0s-Widgets-1.0` key 12.1.4.2.1 -> 12.1.4.3.2).
- `OptionsIdList.lua`: minor 3 -> 4 (`LibKa0s-Options-1.0` key 28.2.34.2.4.8.1.7.4.2).
- Test kit revision 37 -> 38: `framework.lua`, `inventory.lua` and `README.md` changed; `secrets.lua`
  added.
- No payload file added or removed in `libs/LibKa0s/`; no `NEEDS_*` floor rises; no major added.

## Both diffs, after the copy

```sh
diff -r <scratch>/LibKa0s libs/LibKa0s   # (empty)
diff -r <scratch>/testkit tests/_kit     # (empty)
```

Before the copy: libs differed in `Env.lua`, `OptionsIdList.lua`, `Slash.lua`, `SlashParse.lua`,
`WidgetsAutocomplete.lua` and `WidgetsLineChart.lua`; the kit differed in `README.md`, `framework.lua`
and `inventory.lua`, and lacked `secrets.lua`.

## Majors LootHistory consumes

Bus, Compat, Core, DebugLog, Env, Item, Launcher, Lifecycle, Media, Options, Perf, Pool, Slash and
Widgets (`LineChart` on the Timeline, `Autocomplete` on the Search box, the dropdown, reorder list and
copy window). Of the moved files, LootHistory reaches `Env`, `Slash`/`SlashParse`, `WidgetsLineChart`
and `WidgetsAutocomplete`. It builds no `O.IdList`, so `OptionsIdList` 4 arrives unused.

## Contract changes under unchanged signatures

- **`lib.ParseValue` refuses `nan`, `inf`, `-inf` and overflowing literals on a number row** with the
  existing `ERR_NUMBER` reason. `settings/Schema.lua` has number rows, so `/lh set <path> nan` is now
  refused rather than stored. No LootHistory test pinned the old acceptance.
- **The line chart clips every segment to the plot and re-syncs the hover on every render.**
  `modules/Timeline.lua:308` still calls `chart:ClearHover()` before a repaint; v1.71.0's "What a
  consumer owes" says a host may keep or drop it (it stays idempotent), so it stays.
- **`lib.Autocomplete` re-installs its hooks on every call** and floors `opts.maxRows`. LootHistory
  attaches once, after the box's own scripts, so nothing changes.
- **`Env.GetAddOnMetadata` no longer reads the bare global.** `core/EnvSetup.lua`'s own fallback is
  already two rungs (library, then `C_AddOns.GetAddOnMetadata`, no bare-global rung), matching LK-06.
- **Kit revision 38's `--list` Totals count only the cases that run** and give declared skips their own
  `Skipped` row. Regenerating `docs/test-cases.md` moves the one declared skip (the diagnostics
  contract's opt-out case) out of Total, which resolves LH-A-13 (Total had read one above the badge).

Blockers: none.

## Re-vendor reds, fixed in the same commit

- `tests/test_libka0s.lua`: the v1.69.0 case pinned `KIT_VERSION == 37` and the v1.70.0 case pinned
  `WidgetsAutocomplete == 1`, `WidgetsLineChart == 2` and `KIT_VERSION == 37`. Both relax to `>=` with
  a "pinned there" note, as the file does for every earlier release, and a new v1.71.0 case pins
  WidgetsLineChart 3, WidgetsAutocomplete 2, Slash 20, SlashParse 2, Env 2, OptionsIdList 4 and kit 38.
  That is a consumer-owes test edit; no addon code changed.
