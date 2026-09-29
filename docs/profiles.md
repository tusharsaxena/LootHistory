# Profiles

Ka0s Loot History keeps its settings in AceDB profiles and its loot history account-wide. This page
says what a profile holds, what stays outside every profile, how the addon reacts when the profile
changes, and how the old account-wide settings got into a profile. The stored shape is in
[schema.md](schema.md); the panel is in [settings-panel.md](settings-panel.md).

## What a profile holds, and what it does not

| Scope | Where | What |
|---|---|---|
| **Profile** (`db.profile`) | `defaults/Profile.lua` | Every schema row under `settings.*` (the Master controls, Capture, AH Price, Interface and History tabs), the AH price cascade (`settings.auction.priority`), the three id filter lists (`blacklist`, `whitelist`, `currencyBlacklist`), the saved table view (`savedView`) and the History window's geometry (`settings.window`) |
| **Account-wide** (`db.global`) | `defaults/Global.lua` | The recorded loot history (`history`) and the warbound repair's bookkeeping beside it, LibDBIcon's `minimap` table (whether the button is shown, and where), the `schemaVersion` stamp |
| **Session only** | `NS.State`, the modules | Test mode, the debug console window, the debug logging flag, the character scope of the History window |

The split is the owner's decision D5 (2026-09-29): **settings only**. Loot is collected across every
character on the account and every record carries the looter in its `char` column, so the browser
and the Insights tab can show one alt's drops or all of them. A per-profile history would split the
very thing the addon exists to join up, so the history is in no profile. Everything a player
configures is. The minimap button stays global for a different reason: launcher-§3 makes it part of
the installation, so a profile switch must not move it or hide it.

The db is created with `AceDB:New("LootHistoryDB", NS.defaults, true)` (`core/Database.lua:6`): the
`true` puts every character on one shared profile, `Default`, until the player picks another. So out
of the box the addon behaves exactly as it did when the settings were account-wide.

## The Profiles page

**Settings → AddOns → Ka0s Loot History → Profiles** (`settings/Profiles.lua`, `options-ui-§3`) is
AceDBOptions' own control set: choose a profile, create one, copy another into the current one,
delete one, and reset the current one. AceConfigDialog draws it into an AceGUI group inside a canvas
subcategory, through the library's renderer so the combat lock covers it. `P:Register`
(`settings/Panel.lua`) registers it after General, so it is last in the tree, and it has **no
Defaults button**: AceDBOptions' Reset Profile is the page's reset. It is the only AceConfig use in
the addon. With AceDBOptions or AceConfig missing, the builder answers nil and the page is simply
absent. No slash verb switches profiles yet; this page is the control.

## One adopt path for every profile event

AceDB fires `OnProfileChanged` on a switch, `OnProfileCopied` on a copy and `OnProfileReset` on a
reset. `NS.BindLifecycle` (`core/LifecycleSetup.lua`) registers all three onto **`NS.OnProfileEvent`**
(`core/LootHistory.lua`), which does the same four things for each, in this order:

1. **Migrations.** None to run: every `MIGRATIONS` step is account-wide and runs at load, before any
   profile is read, so a profile created later is born in today's shape (`savedvariables-§1`). This
   is where a profile-scoped step would run, against a per-profile stamp, if one is ever needed.
2. **The latch.** `settings.enabled` belongs to the profile, so switching to a profile where the
   addon is off stands it down, and switching back brings it up (`slash-commands-§7`). A disabled
   addon keeps these three registrations for exactly that reason.
3. **One line** (`debug-logging-§10`), worded by the event: `[Profile] switched to profile 'X'` for a
   switch, `[Set] copied profile 'A' → 'B'` for a copy, and `[Set] reset profile 'X' to defaults
   (N rows)` for a reset. N is there when the reset went through the addon's own reset act, which
   counts the rows off their default first; AceDBOptions' Reset Profile goes straight to the db, so
   its line carries no count.
4. **Every setting's effect, re-applied**:
   - **The History window** re-reads its geometry, its saved view (or the stock view), its row
     height and its chrome (`B:AdoptProfile`, `modules/Browser.lua`).
   - **Retention, then the one message**, both in `S:AdoptProfile` (`settings/Schema.lua`), the
     module that is `SettingsChanged`'s one sender. The new profile's `settings.retentionDays` was
     never confirmed against this history, so `S:AdoptRetention` treats a different value as a
     change: it asks before a shorter retention deletes anything, and **No** writes the confirmed
     retention into the new profile. Then one `SettingsChanged("profile")` goes out, which the
     Collector (its gates and id lists) and the Browser (chrome and visibility) already listen to
     (`message-bus.md`).
   - **Every settings panel** re-renders, so the Filters tab's lists and the AH Price table redraw
     from the new profile's tables.

The loot history is not touched by any of this. A copy or a reset changes the profile and nothing
else.

## The global reset is the profile reset

`/lh resetall`, the General page's **Defaults** button and the Master controls' **Reset all
settings** are one act, `Sl:CliResetAll` (`settings/Slash.lua`), and it is `db:ResetProfile()`
(`options-ui-§12`): the session-only rows are restored first (test mode ends, the debug console
closes), then the active profile goes back to its defaults, whole. Other profiles and the profile
list are untouched, and so are the history and the minimap button. Reset all settings confirms first,
in the collection's profile wording. Clearing the history is `/lh purge`, a separate act with its own
confirm. The scope matrix is in [schema.md](schema.md#reset-semantics).

## How the settings got into a profile

Before schema v9 every setting lived in `db.global` beside the history. The v8→v9 migration
(`moveSettingsToProfile`, `core/Database.lua`) runs once, at load, before anything reads a profile:
it copies the stored `settings` block, the three id lists and `savedView` from `db.global` into the
raw `Default` profile (creating it if absent) and clears them from global. A stored table is laid
over whatever the profile already holds, so a value the account stored wins and a key it never
stored keeps its default. A second run finds nothing left to move. `tests/test_profiles.lua` pins
it, along with the adopt path and the Profiles page.

## The `profile` verb

There is no `/lh profile` verb yet. The collection's `profile <name>` verb arrives with the LibKa0s
release that carries it; until then the Profiles page is the only way to switch.
