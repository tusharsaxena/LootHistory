# TODO — Ka0s Loot History

Actionable items outside the milestone tracker in `CLAUDE.md`.

## Settings panel

- [ ] **"Reset All" should only reset settings, not purge the database — rename to "Reset Settings".**
  Currently the button (`settings/Panel.lua:378-392`, `Slash:CliResetAll` / `ResetEverything`, and the
  `KA0S_LOOTHISTORY_RESETALL` StaticPopup) wipes history **and** settings. Change it to reset settings only,
  leaving `LootHistoryDB.global.history` intact, and relabel the button + slash command (`resetall`) copy to
  "Reset Settings". History clearing stays the job of the separate **Purge History** action.

- [ ] **Check the width of the "Reset All" / "Purge History" buttons — they appear to overflow the settings panel.**
  Both use `SetRelativeWidth(0.5)`; verify they fit within the panel's content width and don't clip or spill,
  and adjust the relative width / layout if they do.
