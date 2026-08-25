# 05 — Summary: LootHistory re-vendor, 2026-08-25

## Tag

**v1.15.0 → v1.15.0.** No move. The addon was already carrying the newest tagged
LibKa0s release when this run started.

Per-file minors: `Core` 6, `Env` 1, `Pool` 1, `Item` 1, `Media` 3, `Widgets` 6,
`DebugLog` 11, `Slash` 7, `Options` 8 (`OptionsWidgets` 7, `OptionsScroll` 3),
`Perf` 7 (`PerfPanel` 4). Kit revision 12. Every one identical to the tag.

## What reached the addon for free

**Nothing** — there was no release in between to deliver anything. This is the
class-A row that would otherwise be invisible, and here it is genuinely empty rather
than merely unreported.

## Adopted

**Nothing.** Steps 5 through 7 do not run on an empty delta: there is no
`<old-tag>..<new-tag>` range to read candidates out of, so no candidate was
formulated, no interview was held, and no code was written.

## Declined

**Nothing**, and therefore no GitHub issue was filed. An unreached candidate is
reported as unreached, never as a decline.

## Skipped

Nothing in this repo. Collection-wide, `BuffTextNotifications` and `WhoGotLoots`
were skipped — neither carries a `libs/LibKa0s/`, so neither is a re-vendor target;
a first adoption belongs to `/wow-addon:new-addon`.

## Gates

| Gate | Command | Result |
|---|---|---|
| Lint | `luacheck .` | 0 warnings / 0 errors in 28 files |
| Tests | `lua tests/run.lua` | 644 passed, 0 failed, 0 skipped |
| Vendor sync | `tests/test_vendor_sync.lua` | both assertions green |

No tool was missing; nothing was skipped for want of a toolchain.

## Standing observation

Majors this addon does not consume at all: `Perf`.

That is recorded as a fact about today's wiring, **not** offered as an adoption — a
whole-module candidate is raised from a release delta, and there is no delta here. It
becomes a live question the next time LibKa0s tags a release that touches one of them.
