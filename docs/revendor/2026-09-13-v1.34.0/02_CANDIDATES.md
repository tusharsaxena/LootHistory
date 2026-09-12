# 02 — Candidates: LibKa0s v1.34.0

Sources: `git -C ../LibKa0s log --oneline v1.33.0..v1.34.0`, the v1.34.0 block of
`../LibKa0s/CHANGELOG.md`, `../LibKa0s/docs/releasing.md` ("Re-vendoring consumers"),
`../LibKa0s/docs/api/Slash/version-10-docs.md`, `../LibKa0s/docs/api/Options/version-18.15.5.3-docs.md`
and `../LibKa0s/docs/api/testkit/version-19-docs.md`.

## Class A: reached the addon on the re-vendor alone

- **The whole-value string parse (Slash minor 10).** **Reached, and no row newly keeps a multi-word
  value.** The descriptor passes no `parse`, so every row goes through `lib.ParseValue`. The schema
  declares no `string` row: four `bool`, four `number` and two `table` (`settings/Schema.lua`). The
  one `string` row the CLI reaches is the composed `settings.visibility` enum from `O.MasterControls`
  (`settings/Schema.lua:68`). Its four values are single words: `always`, `inCombat`, `outOfCombat`
  and `never`. So the only visible change is a refusal. `/lh set settings.visibility always junk` is
  now refused with `allowed values: …`, where minor 9 stored `always`. The `table` rows still answer
  the library's unknown-type refusal, as before.
- **The *Reset all settings* tooltip (Options minor 18, OptionsCompose minor 5).** **Unchanged, and
  still correct.** The descriptor supplies no `resetProfile`, so the composer keeps the minor-4 text
  byte for byte: *"Restore every setting in this addon to its default."* The button raises
  `KA0S_LOOTHISTORY_RESETALL` (`settings/Schema.lua:94`), whose accept runs `Sl:ResetEverything`
  (`settings/Slash.lua:139`). That empties `db.global` wholesale, so every setting does return to its
  default. It also discards the recorded history, which the tooltip does not say and the confirm
  popup it opens does. The tooltip is the composer's alone (`options-ui-§15`), and this is the same
  text the addon has shown since minor 4. It is not a profile reset (the addon keeps no profile), so
  neither `resetProfile` nor `profilesPage` applies.
- **Kit revision 19, `OnProfileReset` without a key.** **Not reached.** LootHistory registers no
  `OnProfileReset` handler.
- **No surface change.** No member is added to either instance, so no surface-parity exclusion moves.

## Class B: host change required

None. `profilesPage` is read only with `resetProfile`, which this addon's reset (a global wipe, not a
profile reset) cannot honestly supply, and it ships no Profiles page.

## Class C: whole-module adoption

None. No module is new at this tag.
