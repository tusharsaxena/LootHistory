# LibKa0s v1.60.0 -> v1.61.0: the delta (LootHistory)

Copied from the tag `v1.61.0` (`c6183bd`), never from a working tree.

## libs/LibKa0s (`diff -rq --strip-trailing-cr`, before the copy)

```
Files <tag>/LibKa0s/LibKa0s.xml and libs/LibKa0s/LibKa0s.xml differ
Files <tag>/LibKa0s/Options.lua and libs/LibKa0s/Options.lua differ
Only in <tag>/LibKa0s: OptionsNav.lua
Files <tag>/LibKa0s/OptionsTabs.lua and libs/LibKa0s/OptionsTabs.lua differ
```

- `Options.lua`: minor 24 -> 25. The scroll's left anchor reads `lib.__railInset`; `lib:New` attaches the nav half (`lib.__AttachNav`).
- `OptionsTabs.lua`: minor 4 -> 5. The strip and the content panel start right of a nav rail.
- `OptionsNav.lua`: new, minor 1. `O.NavRail(ctx, spec)`, the pinned nav rail (options-ui-§13).
- `LibKa0s.xml`: loads `OptionsNav.lua` after `OptionsScroll.lua`.
- The Options major key moves from `24.31.4.7.4` to `25.31.5.7.4.1`. With no rail drawn the inset is 0: no page moves.

## tests/_kit

`testkit/` is identical at v1.60.0 and v1.61.0 (kit revision 27): 0 differing files, so `tests/_kit` is not copied.
