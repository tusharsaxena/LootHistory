# The disabled state

What switching Loot History off does, and what it deliberately leaves alone. The summary sits in
[ARCHITECTURE.md → *The disabled state*](ARCHITECTURE.md#the-disabled-state); the in-game checks are in
[smoke-tests.md](smoke-tests.md).

**Disabled means the addon is not running** (`slash-commands-§7`, standard v2.57.0). Not hidden, not
quiet, not skipping a repaint — not running. A player who unticks **Enable Loot History** has asked
for the same outcome they would get by unticking the addon in Blizzard's own AddOns list, minus the
`/reload`.

**This addon shipped a draw gate until v1.41.0, and it is worth naming.** `settings.enabled` was one
hot-path upvalue `modules/Collector.lua` read at the top of `OnChatMsgLoot`, and nothing else
changed: `CHAT_MSG_LOOT` stayed registered, so the client went on walking the registration list on
every loot line in the raid, building the argument frame and entering Lua for an addon the player
had switched off. The addon had not stopped watching — it had stopped reacting — and the dispatch it
went on paying is precisely what a player switching it off is trying to stop paying
(`anti-patterns #85`). The upvalue is gone; the registrations go instead.

## The slash surface while disabled

**The slash surface is UNCHANGED while the addon is disabled** (slash-commands-§2/§7, standard
v2.57.0, LibKa0s v1.41.0 / Slash minor 13). Every reserved verb answers: `config` and the bare `/lh`
open the panel, `version` prints, `debug` runs, `diagnostics` writes its report (in both forms,
`/lh diagnostics` and `/lh debug diagnostics`), and the whole schema CLI — `get`, `set`, `list`,
`reset`, `resetall` — reads and repairs settings, which is precisely when a player most needs it.
The standard narrowed this to `enable` and `help` at v2.56.0 and **reversed it** at v2.57.0; the
case that settled the reversal was the smallest one, `/lh` on a disabled addon returning a refusal
instead of the one surface it can be switched back on from by hand. This addon passes **no**
`liveVerbs` to the dispatcher, so it takes the library's set rather than a copy that could drift.

**A disabled addon refuses a feature verb** (slash-commands-§2's SHOULD, which survived the
reversal and is the only refusal in the disabled state). While `settings.enabled` is `false`,
`show` / `hide` / `toggle` / `test` / `purge` answer one tagged line naming `/lh enable` and do
nothing else. The gate is **one gate**, wrapped round each feature handler as `NS.COMMANDS` is built
(`settings/Schema.lua`), so every route into a verb passes it — the library's dispatcher, the
positional walk the library-less install falls back to, and a direct call on the triple — and a verb
declared tomorrow is gated by default. The live set is named once, as data (`LIVE_WHILE_DISABLED`),
and is `lib.LIVE_VERBS` restated (Slash minor 16): `help`, `config`, `version`, `enable`,
`disable`, `debug`, `perf`, `diagnostics` and the schema CLI. `diagnostics` joined the set at
LibKa0s v1.60.0 because a disabled addon is the one a player is most likely to be reporting; the
report reads state only, takes no hold and registers nothing, and says which parts are stood down
([debug.md](debug.md)). **The refusal line is the collection's, not this addon's** — one shape, built by
`LibKa0s-Slash-1.0` from `NS.BRAND` and the slash and reached through `NS.Slash.DisabledLine()` by
the verb gate, the one call site that prints it (the launcher's left click printed it too until
Launcher minor 4, LibKa0s v1.58.0, retired the refusal: the left button now opens the panel in either
state). It is no longer an `NS.L` string:
`locales/enUS.lua` carried `SLASH_DISABLED_VERB` until v1.41.0, and slash-commands-§7 makes the
wording the collection's rather than the addon's.

## One latch, named holds

`core/LifecycleSetup.lua` is the `LibKa0s-Lifecycle-1.0` seam: ONE latch, stood down while at least
one **hold** is taken and stood up only when the last is released. `NS.Lifecycle:Set("disabled", …)`
is the one branch, and the checkbox, the `enable` / `disable` verbs, `/lh set settings.enabled` and
AceDB's profile callbacks all arrive at it through `NS.OnEnabledChanged`. There is deliberately no
bare stand-up: releasing one hold must not resurrect an addon another is still holding down.

**This addon takes one hold today.** It declines `LibKa0s-Perf` (`performance-§12`, a ratified row in
[§ Documented deviations](ARCHITECTURE.md#documented-deviations)), so nothing here takes `perf`. The key is
published (`NS.HOLD_PERF`) and the latch honors it, because the invariant is the library's rather
than this addon's — `tests/test_disabled.lua` drives both holds through it, so arming the harness
later is a registration and not a rewrite.

## What stands down

| Goes down | Where |
|---|---|
| The AceAddon target's own registrations — `PLAYER_ENTERING_WORLD`, the Collector's two chat events, Attribution's nine | `NS.addon:UnregisterAllEvents()` in `NS.StandDown` |
| The three private bus targets — `SettingsChanged`, `HistoryChanged`, `RecordAdded`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED` | `Collector:Disable` / `Browser:Disable` / `Analytics:Disable` |
| Attribution's per-unit spell frame (`UNIT_SPELLCAST_SUCCEEDED`, `player`) | `Attribution:Disable` |
| Every deferral the addon armed — the retention prune, the bound-state repair, both coalesced repaints | `NS.CancelDeferrals`, over the handles `NS.After` tracks |
| The History window, the export modal and the debug console | `NS.StandDown`, and kept down by the first rung of `B:VisibilityAllows` |

**Hidden AT THE SOURCE, not imperatively.** The first rung of `B:VisibilityAllows` answers `false`
while the latch is down, so every route into the window — the verb, the minimap click, the tab
restore, the visibility dropdown — asks one question. An imperative hide alone would come back on
the next combat transition or settings change, and the addon would be visibly running while it
claimed to be off.

**The one sanctioned gate is `hooksecurefunc`**, which has no un-hook. Five hooks reach
`Attribution:Stamp` — `BuyMerchantItem`, `TakeInboxItem`, `AutoLootMailItem`, `UseContainerItem` and
`GetQuestReward` — and that one funnel gates its body and returns. It is not license to gate
anything that has a real unregister.

**`NS.After` replaced bare `C_Timer.After` for the addon's own deferrals**, and that is load-bearing
rather than tidy: the retention prune is a SavedVariables write on a five-second fuse lit by
`PLAYER_ENTERING_WORLD`, and `C_Timer.After` cannot be put out. A player who switched the addon off
inside those five seconds got the write anyway, from a game event, while it was disabled.

## What survives, because it is SETUP

The chat command and the dispatcher; `NS.COMMANDS`; the settings-category registration and the panel
body, including the panel's own bus subscriptions; the AceDB handle, `Schema:Set` and AceDB's
`OnProfileChanged` / `OnProfileCopied` / `OnProfileReset` callbacks; and the launcher's registration
— the minimap button stays on the minimap and the broker row stays in the display, because
the minimap button's visibility (row `minimap.shown`, stored key `minimap.hide`) is a per-installation display preference and says nothing about whether the addon is
running. Without those, `/lh enable` would not exist and the switch would only go one way.

**The launcher refuses no click; its menu grays the features** (`launcher-§2`, standard v2.67.0; Launcher minor 4,
LibKa0s v1.58.0). The left click opens the settings panel in either state — the panel is setup, and
it is where the addon is switched back on — so it prints no refusal. The right click opens the
options menu, and while the addon is disabled the library grays **Locked**, **Test mode** and
**Show window** with "enable the addon first" and calls none of their toggles; **Enabled** stays
live and runs `/lh enable`. The gate is the library's, read from the descriptor's `isEnabled`
(`NS.AddonIsOff`), and a grayed entry writes no SavedVariables even when a client dispatches it.
**The tooltip still shows while disabled** (Launcher minor 3, the library's own block): it reads
`Enabled: No` under the same two fixed hints.

## The conformance suite

`tests/test_disabled.lua` is `slash-commands-§7`'s mandated suite, in the green gate like any other.
Every negative case asserts on the **registration set** through the kit's recording mock, never on a
handler's return value — an early return is exactly what a draw gate does, so a suite written
against one certifies the thing it exists to catch. It was confirmed red against the draw gate by
putting it back: steps 3, 4, 6 and 10 all redden, and the Collector's early return does not save it.

Step 7 covers the diagnostics report too. Both forms, `/lh diagnostics` and
`/lh debug diagnostics`, run while the addon is stood down. Each writes a full report, begin marker
to end marker, and leaves the registration set as the stand-down left it. The kit's shared
`tests/_kit/test_diagnostics_contract.lua` repeats the while-disabled check against this dispatcher.
