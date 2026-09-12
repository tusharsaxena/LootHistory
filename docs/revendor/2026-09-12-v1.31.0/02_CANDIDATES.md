# 02 — Candidates: LibKa0s v1.30.0 → v1.31.0

Sources, in the order the procedure reads them:

```sh
git -C ../LibKa0s log --oneline v1.30.0..v1.31.0
#   30db4ed The v1.31.0 release record
#   2b312db v1.31.0: release pointers, standards v2.44.0, the case list
#   f355fdc Kit 17: the Ace surfaces six consumer harnesses migrate onto
#   3162e53 Options 15.15.4.3: a record-backed bind arm for the composers (PanelMaster#48)
#   09099b1 docs(releasing): v1.30.0 is merged in all ten consumers
#   853c62e Merge branch 'fix/kit-27-30'
#   5193ebe Post-tag v1.30.0: consumers table sweep; AuraMaster is the tenth consumer
git -C ../LibKa0s show v1.31.0:CHANGELOG.md                         # the "## v1.31.0 — 2026-09-12" block
git -C ../LibKa0s show v1.31.0:docs/api/testkit/version-17-docs.md
```

The only moved majors are Options' two secondaries (`OptionsCompose` 3 → 4, `OptionsWidgets` 14 →
15) and the kit (16 → 17). No major this addon does not consume moved, so there is no class C
candidate. Perf stays settled as the `performance-§12` register row.

## Class A — delivered on the re-vendor alone

| Item | Evidence | Why nothing is offered |
|---|---|---|
| `spec.bind`, the composers' record-backed arm (`OptionsCompose` minor 4) | `CHANGELOG.md` v1.31.0, *`OptionsCompose.lua` minor 4* | Path-keyed callers are "byte-for-byte unaffected", pinned upstream by `tests/fixture_compose_golden.lua`. This addon calls one composer, `MasterControls`, path-keyed, for schema rows it owns, and edits no registry records through a composer. Nothing to bind. |
| A path-less row reads and writes through its own `get` / `set` (`OptionsWidgets` minor 15) | `CHANGELOG.md` v1.31.0, *`OptionsWidgets.lua` minor 15* | The gate is `path == nil`. Every row this addon renders has a path, so every maker reads and writes through the descriptor exactly as before. |
| AceTimer is real; `M.__fireTimers()` honors cancellation and answers a count | `version-17-docs.md`, *AceTimer, on the kit's one queue* and *`M.__fireTimers()` honors cancellation* | Production embeds AceTimer (`core/LootHistory.lua:4`) but calls no `ScheduleTimer` (`grep -rn 'ScheduleTimer' core modules settings` is empty); the deferrals are `C_Timer.After`. No test reads the new count. |
| AceConsole's `RegisterChatCommand` is recorded | `version-17-docs.md`, *AceConsole* | `settings/Slash.lua:245,324` registers through it. No suite drives `/lh` through `AceConsole:__slash`, and none needs to: `tests/test_slash.lua` drives `Sl:OnSlash` directly. |
| AceEvent messages on CallbackHandler's rules; `M.__fireEvent`; `M.__badEvents` | `version-17-docs.md`, *AceEvent: two CallbackHandler registries* | The one-callback-per-(message, target) clobber this addon's docs lean on (`docs/testing.md`, *The message bus is modeled on CallbackHandler*) is unchanged. No suite fires an event through `t.__events[event](event, ...)` on the addon object (`tests/test_attribution.lua:414` only reads the field), so there is nothing to port to `M.__fireEvent`. |
| AceGUI `WidgetVersions`, `RegisterLayout` / `GetLayout` | `version-17-docs.md`, *AceGUI* | Nothing in this addon reads either. |

The measured claim upstream (`version-17-docs.md`, *For consumers: nothing moves*) is LootHistory
719 / 2 skipped / 721 at `0222fef`, identical at revisions 16 and 17. Here the count after the copy
was 722 / 722 (the extra case is #30's, and the two vendored-payload cases pass rather than skip
because `../LibKa0s` is checked out beside the repo).

## Class B — host change required

### B1. Delete the local `NewAddon` wrapper in `tests/wow_mock.lua`

- **What.** Kit 17's `NewAddon([object,] name, lib, ...)` honors its mixin list and embeds exactly
  the named libraries through `LibStub`. This addon's harness wrapped the kit's `NewAddon` to
  re-embed AceEvent onto the returned object, because at revision 16 the kit ignored the list and
  `NS.bus` is the addon object.
- **Evidence.** `version-17-docs.md`, *AceAddon: `NewAddon` honors its mixin list*, item 4, and its
  *For consumers* section: "LootHistory and MultiMeters through wrappers … All four list
  `AceEvent-3.0`, `AceTimer-3.0` and `AceConsole-3.0` in production, so each addon object still
  carries every mixin it had".
- **Files.** `tests/wow_mock.lua` (the *message bus* block), `tests/test_harness.lua` (the
  characterization case), `docs/testing.md` (*The mock*).
- **Recommendation.** Adopt. The wrapper models exactly what the kit now models, so keeping it is a
  second embed that can only mask a kit regression. The owner's decision 3 (harness declines migrate
  onto the kit) points the same way.
- **Blast radius.** Replaces harness code the repo owns, test-side only. Characterized first.

### Everything else in `tests/wow_mock.lua` — not a candidate

Each remaining local extension was checked against what kit 17 adds. None is made redundant:

| Local extension | Kit 17 | Stays because |
|---|---|---|
| Identity (`UnitName`, `UnitClass`, realm, zone) | unchanged | The suites and the export's `char` column are written against these values. |
| Item, currency, map, loot and currency global strings | unchanged | Addon-specific. |
| `ITEM_QUALITY_COLORS`, `RAID_CLASS_COLORS`, atlas and texture markup, `CLASS_ICON_TCOORDS` | unchanged | Addon-specific whitelists that keep the fallbacks under test. |
| `strtrim`, `strsplit` | unchanged | The kit omits them on purpose (`mock_base.lua` header). |
| `FauxScrollFrame_*` | unchanged | Real client globals the kit does not carry. |
| Frames that remember their size, `GetStringWidth` | unchanged: the geometry flip moved to revision 18 at the earliest | `version-17-docs.md`, *Revision 17 is not the geometry flip*. |
| Tab art heights and a recorded `SetPoint` | unchanged | The options-ui-§13 wrap-invariance case needs them. |
| FontStrings as distinct objects that raise before a face is set | unchanged | The `Font not set` crash guard. |
| An EditBox that remembers its text | unchanged | The copy window's only seam. |
| `SetTitle` and the frame `GetStringWidth` stamp on AceGUI widgets | the kit **declined** `SetTitle` | `version-17-docs.md`, *What the kit declined*. |

Nothing here is declined in the procedure's sense: none of it is a v1.31.0 surface. The rows record
that each was looked at.
