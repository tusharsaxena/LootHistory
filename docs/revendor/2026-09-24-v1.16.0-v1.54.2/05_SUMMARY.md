# 05 — Summary: LibKa0s span v1.16.0 -> v1.54.2 (base v1.15.0)

Plan item LH-34, 2026-09-24, branch `feat/2026-09-23-review-audit-remediation`. Records the 29 tags
this addon vendored after its store's first bundle and never recorded (finding LootHistory-A-01).
No code changes, nothing is re-vendored, nothing is pushed, and the addon version is not bumped.
The commit list, the base and how the span was derived are in `01_DELTA.md`.

## One line per tag

The intermediate tags were carried by sweeps, and nothing was adopted from them beyond the commits
named below. "Carried by sweep, nothing adopted" means the bytes arrived and this addon's own code
took no new surface from that tag. Anything the library fixed still reached the player through the
carry.

- **v1.16.0** — carried by sweep, nothing adopted (`3d79b33`: Pool 2, Widgets 7, DebugLog 12, kit 13).
- **v1.17.0** — `d164c11`: the `core/PoolSetup.lua` degraded fallback flipped to Pool 3's backward
  release order, in the re-vendor commit itself.
- **v1.18.0** — carried inside `143fdd7` (options-ui-§12 wholesale reset), nothing adopted from the
  library: this addon has no profile, so its reset empties the account-wide store itself.
- **v1.18.1** — carried by sweep, nothing adopted (the landing logo texture fix arrives with the bytes).
- **v1.19.0** — carried by sweep, nothing adopted at the time (`Widgets.ReorderList` was unused
  until v1.24.0's `179b0c7`).
- **v1.23.0** — `2832dcf`: General and Filters become tab strips through `O.RenderTabbedSchema` and
  `O.TabStrip` (options-ui-13). `O.PageBanner` is stubbed for parity only.
- **v1.24.0** — `179b0c7`: the composed Master controls tab, the settings-revamp-v2 page shape and
  price sources ranked by drag (`NS.MakeReorderList`), in the same commit as the copy.
- **v1.26.0** — carried by sweep, nothing adopted (`1f776a8`; the tab strip pooling arrives with the
  bytes).
- **v1.27.0** — `c17e0d6`: the kit's `test_eol.lua` gate wired into `tests/run.lua`, and `O.__print`
  added to the parity case's ignore list.
- **v1.28.0** — carried by sweep, nothing adopted (Perf only; this addon holds the performance-§12
  exemption and wires no perf verb).
- **v1.29.0** — carried by sweep, nothing adopted (Perf only, as above).
- **v1.35.0** — `1d6e3c8`: the Blacklist, Whitelist and currency Blacklist become `O.IdList`s.
  `95238ed`: the add box suggests names and resolves them from the loot history (#31). Four re-cuts
  of the tag followed (`fff585a`, `67f0cc2`, `8f40c51`, `1a9de0b`); the degradation stub gained the
  new members for surface parity only.
- **v1.36.0** — carried by sweep, nothing adopted (the stub gained `SelectTab` for parity; nothing
  calls the library's).
- **v1.36.1** — carried by sweep, nothing adopted (the pooled CheckBox color fix arrives with the bytes).
- **v1.36.2** — carried by sweep, nothing adopted.
- **v1.37.0** — `4069399`: the Master controls Test mode checkbox through `testModePath`. The
  re-vendor commit `4b0c902` had said nothing would use it; the next commit did.
- **v1.38.0** — `af217b5`: a bare `/lh` opens the settings panel (Slash 11), with the library-absent
  stub and tests, in the re-vendor commit itself.
- **v1.39.0** — `fc8fc82`: the launcher. The hand-built minimap button and broker object become one
  `LibKa0s-Launcher-1.0` object.
- **v1.42.0** — `8b0989e`: the Lifecycle latch. Disabling the addon stands it down through
  `core/LifecycleSetup.lua`. The copy rode in this commit.
- **v1.43.0** — carried by sweep, nothing adopted (kit revision 23 only; the library bytes did not move).
- **v1.44.0** — `a8a7c32`: `removeStyle = "icon"` on the Filters tab's three `O.IdList`s.
- **v1.45.0** — carried by sweep, nothing adopted (`shownWhen` is unused here).
- **v1.46.1** — carried by sweep, nothing adopted. The settings panel's combat lock arrives with the
  bytes and needs no host code; `793cfd1` only makes `tests/test_disabled.lua` close a page an
  earlier suite left shown.
- **v1.47.0** — `8ce2cc8` and `c90182f`: `O.IdList` `columns = 2` on the filter lists. The re-vendor
  commit `3c76b8d` had declined it; `8ce2cc8` reversed that once v1.50.0 fitted the column count to
  the canvas.
- **v1.50.0** — `8ce2cc8`: the same adoption depends on OptionsWidgets 27's fitted column count.
- **v1.51.0** — carried by sweep, nothing adopted (the optional `O.IdList` help fields are unused here).
- **v1.52.0** — carried by sweep, nothing adopted.
- **v1.53.0** — carried by sweep, nothing adopted (the Add button height fix arrives with the bytes).
- **v1.54.2** — `a8f2133`: the kit's US-English prose gate replaces this repo's own copy. The copy
  rode in this commit.

## Declined

The only explicit decline in the span, v1.47.0's `columns` (`3c76b8d`), was reversed by `8ce2cc8`.
No other candidate was formulated at the time, so nothing else counts as declined and no issue is
filed.

## Open

- The frozen bundles are not edited. `docs/revendor/2026-09-03/` and `docs/revendor/2026-09-12/`
  keep their heading-style line 1. The audit reads only the last tag from each, which is why v1.24.0
  and v1.29.0 are in this span.
- Later re-vendors write their own bundles: `2026-09-23-v1.55.0/` and `2026-09-23-v1.56.0/` (the
  RV-LH re-vendor) already do, and every re-vendor from here writes its own
  `docs/revendor/<YYYY-MM-DD>-v<tag>/`.
