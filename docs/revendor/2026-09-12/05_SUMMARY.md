# 05 — Summary: LibKa0s v1.29.0 → v1.30.0

## The move

| | |
|---|---|
| From | v1.29.0 |
| To | **v1.30.0** (tag commit `e369e0f`, taken with `git archive`, never from the working tree) |
| Library files that moved | none. All fourteen minors are unchanged; see `01_DELTA.md` |
| Kit revision | 15 → **16** (`README.md`, `framework.lua`, `mock_base.lua`, `vendor_sync.lua`) |
| Files removed upstream | none |
| Cross-major skew found | none |

## What reached this addon for free

- **The runner-mode vendor case** (LibKa0s#28): `the automated-test runner is recorded executable
  (100755)`. It needed no edit, since `tests/test_vendor_sync.lua` is one `VendorSync.register`
  call. It passes, and it is the whole of the count change, 720 → 721.
- **`AceGUI:Release`** (LibKa0s#27): no local model existed and nothing here calls it.
- **`Printf` on the `NewAddon` target** (LibKa0s#30): the addon publishes no `NS.Printf`, so there
  is nothing to reclaim.

## What was adopted

- **B1, LibKa0s#29.** The local AceEvent event-half shim in `tests/wow_mock.lua` and its
  `M.__fireAceEvent` helper are deleted. `tests/test_browser.lua`'s combat-transition case now fires
  the kit's recorded handler, `B.__ev.__events[event](event)`. This goes in the re-vendor commit,
  because a re-vendor without it is red. Test-only code; no production file changed.

## What was declined

Nothing, so there is no issue to file.

## Kept, and why

- The `NewAddon` wrapper that embeds AceEvent's **message** half on the addon object. Kit 16's
  `NewAddon` still stamps only the event half.
- The `aceGUI.Create` wrapper (`SetTitle`, `frame:GetStringWidth`). Unrelated to kit 16.

## Gates

| Gate | Result |
|---|---|
| After the copy, before any edit (characterization) | `719 passed, 2 failed, 0 skipped, 721 total`. The two reds were the predicted combat-transition case and the vendor gate, because the line had not yet moved. |
| `lua tests/run.lua`, final | **721 passed, 0 failed, 0 skipped, 721 total** |
| `luacheck .` | **0 warnings / 0 errors** in 59 files |
| `tests/test_vendor_sync.lua` | all three cases green, the new runner-mode case included |

`luacheck`'s figure is scoped by `.luacheckrc`'s `exclude_files`, which excludes `libs/` and
`tests/_kit/`. So 0/0 means the **host** is clean, including `tests/wow_mock.lua` and
`tests/test_browser.lua`, which carry this adoption. The payloads' own gate is upstream.

## Not pushed

Committed on `chore/libka0s-1.30.0-arch5` only. Pushing and merging are `/wow-addon:finalize`'s.
