# Profiles

Ka0s Loot History keeps its settings in AceDB profiles and its loot history, with the retention that
prunes it, account-wide. This page
says what a profile holds, what stays outside every profile, how the addon reacts when the profile
changes, and how the old account-wide settings got into a profile. The stored shape is in
[schema.md](schema.md); the panel is in [settings-panel.md](settings-panel.md).

## What a profile holds, and what it does not

| Scope | Where | What |
|---|---|---|
| **Profile** (`db.profile`) | `defaults/Profile.lua` | Every schema row under `settings.*` except `settings.retentionDays` and `settings.rollupRetentionDays` (the Master controls, Capture, AH Price and Interface tabs), the AH price cascade (`settings.auction.priority`), the three id filter lists (`blacklist`, `whitelist`, `currencyBlacklist`), the saved table view (`savedView`, which can now also be created by the Timeline remembering its thing, as a copy of the stock view; see [schema.md](schema.md#state-outside-the-rows)) and the History window's geometry (`settings.window`) |
| **Account-wide** (`db.global`) | `defaults/Global.lua` | The recorded loot history (`history`) and the warbound repair's bookkeeping beside it; **Keep history for** (`retentionDays`, the row `settings.retentionDays`), the setting that governs what the prune deletes from that history; the Timeline's daily rollup (`daily`, with its bookkeeping `rollupSeeded`) and **Keep Timeline days for** (`rollupRetentionDays`, the row `settings.rollupRetentionDays`), which governs it the same way; LibDBIcon's `minimap` table (whether the button is shown, and where), the `schemaVersion` stamp |
| **Session only** | `NS.State`, the modules | Test mode, the debug console window, the debug logging flag, the character scope of the History window |

The split is the owner's decision D5 (2026-09-29): **settings only**. Loot is collected across every
character on the account and every record carries the looter in its `char` column, so the browser
and the Insights tab can show one alt's drops or all of them. A per-profile history would split the
very thing the addon exists to join up, so the history is in no profile. Everything a player
configures is, with one exception, below. The minimap button stays global for a different reason:
launcher-§3 makes it part of the installation, so a profile switch must not move it or hide it.

**Retention is account-wide** (owner decision D6, 2026-09-29). **Keep history for** decides what the
login prune deletes from the one shared history, so it is one value for the whole account and no
profile holds a copy. Its row keeps the CLI path `settings.retentionDays`, but its own `get` and `set`
read and write `db.global.retentionDays` (`settings/Schema.lua`), and its tooltip on the History tab
says it is account-wide. A profile switch, copy or reset never changes it, never prunes and never
deletes a record. A per-profile retention would let a switch to a profile that keeps a week delete
everything older at the next login for every profile.

The db is created with `AceDB:New("LootHistoryDB", NS.defaults, true)` (`core/Database.lua:7`): the
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
absent. `/lh profile` (below) switches from chat.

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
   - **The one message**, from `S:AdoptProfile` (`settings/Schema.lua`), the module that is
     `SettingsChanged`'s one sender: one `SettingsChanged("profile")`, which the Collector (its
     gates and id lists) and the Browser (chrome and visibility) already listen to
     (`message-bus.md`). There is no retention step: the retention is account-wide, so the new
     profile brings none of its own.
   - **Every settings panel** re-renders, so the Filters tab's lists and the AH Price table redraw
     from the new profile's tables.

The loot history is not touched by any of this (D6). Nothing on this path prunes, counts records
against a retention or raises the prune confirm; the only prune is the once-per-session login one
(`addon:OnEnterWorld`, `core/LootHistory.lua`), which reads the account-wide retention. A copy or a
reset changes the profile and nothing else. `tests/test_profiles.lua` pins it: a switch, a copy, a
reset and `/lh resetall` over records a short retention would drop leave every record in place.

## The global reset is the profile reset

`/lh resetall`, the General page's **Defaults** button and the Master controls' **Reset all
settings** are one act, `Sl:CliResetAll` (`settings/Slash.lua`), and it is `db:ResetProfile()`
(`options-ui-§12`): the session-only rows are restored first (test mode ends, the debug console
closes), then the active profile goes back to its defaults, whole. Other profiles and the profile
list are untouched, and so are the history, the retention and the minimap button (both rows are in
`NS.Schema.RESET_EXEMPT`). Reset all settings confirms first,
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

The v9→v10 migration (`moveRetentionToGlobal`, `core/Database.lua`) takes the retention back out
(D6). It reads both stored shapes: a `retentionDays` still under `global.settings` (a file the v9 step
could not move) and one in any raw profile (where v9 put it, in `Default`, and wherever a character
wrote it while it was per profile). Every value found is cleared from where it was, and the one that
deletes the least (`0`, keep Always, beats any day count; otherwise the longer window) becomes
`global.retentionDays`, so the move can never shorten what is kept. A second run finds nothing and
leaves the account's value alone.

## The `profile` verb

`/lh profile` lists the profiles, sorted case-insensitively, the current one marked `(current)`,
then a hint row. `/lh profile <name>` switches to that profile. The name must match an existing
profile exactly, case included; one pair of surrounding quotes is stripped (`/lh profile "My Alt"`)
and inner spaces are kept.

- The current profile answers `Already on profile '<name>'.` and switches nothing.
- An unknown name answers `No profile named '<name>'.`, then `Did you mean '<name>'?` when exactly
  one profile matches ignoring case, then the list. **It never creates a profile**: AceDB's
  `SetProfile` creates whatever it is handed, so a typo would otherwise become a stray profile.
  Creating one is the Profiles page's job.
- In combat the switch answers `Can't switch profiles in combat.`; the list and the refusals above
  still answer.
- The verb **answers while the addon is disabled**. `settings.enabled` belongs to the profile, so
  switching to a profile where the addon is on brings it back up. The descriptor passes
  `lib.LIVE_VERBS` plus `profile` as its `liveVerbs` (`settings/Slash.lua`), and the COMMANDS-table
  gate lists it in `LIVE_WHILE_DISABLED` (`settings/Schema.lua`).

The behavior is `LibKa0s-Slash-1.0`'s (`CliProfile`, Slash minor 17), shared by the whole
collection; this addon owns the COMMANDS row and hands the dispatcher its store,
`profiles = function() return NS.db end`. A switch goes through AceDB's `SetProfile`, so it reaches
the same adopt path as the Profiles page and logs the same one `[Profile] switched to profile '<name>'`
line; the library logs nothing of its own. With LibKa0s absent, the verb prints
`/lh profile is unavailable: the LibKa0s library did not load.` and switches nothing, and the
degraded help does not offer it. `tests/test_profiles.lua`, `tests/test_disabled.lua` and
`tests/test_slash_degraded.lua` pin it.
