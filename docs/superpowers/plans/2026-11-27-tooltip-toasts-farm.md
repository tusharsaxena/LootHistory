# Plan — holdings tooltip (#34), loot toasts (#38), farm mode (#39)

**Status ledger is the checkpoint.** A resumed run reads the ledger, checks out the branch of the
first task not `done`, verifies that branch's last commit matches the ledger, and continues there.
Every task ends green (gate below) and with a commit; the ledger row is updated in that same commit.

- Issues: [#34](https://github.com/tusharsaxena/LootHistory/issues/34),
  [#38](https://github.com/tusharsaxena/LootHistory/issues/38),
  [#39](https://github.com/tusharsaxena/LootHistory/issues/39)
- Mockups (v4, owner-reviewed 2026-11-27):
  [`../specs/2026-11-27-tooltip-toasts-farm-mockups.html`](../specs/2026-11-27-tooltip-toasts-farm-mockups.html)
- Owner instructions: branch per milestone, commit per task, push after each milestone, **never merge
  without the owner's go-ahead**; after everything is merged, delete every branch, stash and worktree
  this run created.

## Gate (every task)

```
lua tests/run.lua
KA0S_KIT_CLIENT=forever lua tests/run.lua
~/.claude/dev-copilot/bin/ka0s-bounded luacheck .
python3 -m pytest -q tools/seeds
```

All 0 failed / 0 warnings. Files written by tools land LF on the WSL mount: after committing, restore
each with `rm <path> && git checkout -- <path>` (CRLF per `.gitattributes`), then re-run the gate.

## Branches (stacked, merged in this order)

| # | Branch | Base |
|---|---|---|
| M0 | `feat/2026-11-27-revendor-libka0s-v1.118.0` | `master` |
| M1 | `feat/2026-11-27-34-tooltip-holdings` | M0 |
| M2 | `feat/2026-11-27-rep-appearance-capture` | M1 |
| M3 | `feat/2026-11-27-38-loot-toasts` | M2 |
| M4 | `feat/2026-11-27-39-farm-mode` | M3 |

## Decisions (owner rulings in the grill, 2026-11-27)

| Id | Decision |
|---|---|
| D1 | Re-vendor LibKa0s to v1.118.0 first (M0). No upstream LibKa0s change planned; a need found later is flagged, not silently worked around. |
| D2 | #34: the logged-in character's counts are live client reads (bags, bank, warband bank via `C_Item.GetItemCount` diffs, currency via `C_CurrencyInfo`); every other holder and the Warband from `db.global.holdings`. |
| D3 | #34: with `settings.trackLedger` off the tooltip block is hidden entirely. |
| D4 | #34: containers render as LibKa0s catalog icons plus a count, never words. Icons are added to the CLAUDE.md `LibKa0s icons:` line and the vendored `media/icons/` in the same commit. |
| D5 | #34: a public API, `LootHistory.API.v1`, published `_G.LootHistory = { API = NS.API }` (public-api section): holders, holder info, item and currency counts per holder, money, a read-only holder copy, scan times, and `RegisterCallback(owner, "HoldingsChanged", fn)`. Every answer is a copy. Contract documented in ARCHITECTURE.md. |
| D6 | #38: toasts on by default; they see **every gain the addon can observe, before capture filters and minimum quality** (a pre-gate gain feed). Toast-only filters (own minimum quality, default Poor; own hidden-source list, default empty). |
| D7 | #38 kinds: items, money, currencies, reputation (gain and loss), appearances (Retail), experience, profession skill-ups. No losses of items/money. No party loot, no loot-roll rows. |
| D8 | Reputation and appearances are also **recorded as History rows** (new kinds, Type filter values, Insights, CSV), each with a capture switch, default on. Experience and skill-ups are toast + farm tally only. |
| D9 | #38 toast content: icon, name in quality color, xN, counts in bags / bank / warband bank as icons (no guild bank: scope D3 holds), source tag, value line by price mode (None / Vendor / AH / Vendor+AH / Highest, default Vendor+AH), item level badge, upgrade-over-equipped line, highlight glow + optional LSM sound for mounts / legendaries / upgrades / new appearances, currency cap coloring (70% orange, 90% red). |
| D10 | #38 placement: a 3x3 slot picker (Top/Mid/Bottom x Left/Center/Right) plus an X/Y nudge, grow up/down, **text alignment left (default) or right, icon side left (default) or right**. Default slot Bottom Right, growing up. |
| D11 | #38: up to 3 feeds (Main ships enabled, two more disabled), each with its own slot, kinds, content, style, motion, behavior. |
| D12 | #38 styling: skin by default, every part overridable per feed (background type/color, border texture/size/color mode, font face/size/secondary size/outline/shadow, width, row height, icon size, padding, gap, per-kind colors); one reset-to-skin control. |
| D13 | #38 motion: enter none/fade/slide(4 dirs) + time, hold + fade time, pulse on merged count, optional countdown bar, smooth reposition. Merge window default 3 s: a repeat replaces the toast with the summed one at the newest slot. |
| D14 | #38 behavior: shown-at-once, show in combat (default on), click-through in combat, pin on hover, shift-click link, ctrl-click dressing room, right-click dismiss, click opens History (or searches it when the gain has no row). Optional hiding of Blizzard's loot/money alert toasts and the matching chat message groups, off by default, fully restored on disable. |
| D15 | #39: headline shows total value **and** per-hour; gross or net and money / vendor / AH are settings (default gross, AH). |
| D16 | #39: auto-pause on AFK and after N idle minutes without a gain (default 5, 0 = off; idle time taken off the clock). |
| D17 | #39: logout finishes and saves the session; `/reload` and a disconnect keep it running. |
| D18 | #39: sessions saved account-wide per character, `db.global.farm`, cap per character is a setting (default 100, 0 = all). Each saved session is a full record (totals, item / money / currency / cost lines, activity counts, a log capped at 2000 lines), independent of History rows. |
| D19 | #39: gains come from the same pre-gate feed as the toasts; costs (repairs, buys, AH fees) from recorded `OUT` rows in the session window. |
| D20 | #39 surfaces: companion panel (headline, live numbers, activity tally, Pause/Finish/Details/Sessions, minimize to headline + buttons), a Details window (Items, Money, Currencies, Costs, Activity, Log tabs), a summary at Finish, a Farm tab in the History window, and the panel's own sessions list. |
| D21 | #39 ingress: a title-bar button on the History window, two key bindings (Toggle farm session, Start / finish farm session), `/lh farm [start|pause|resume|finish]`, the launcher menu. |
| D23 | Settings layout (options-ui-§13, at most 8 tabs on a page): #34's rows are a "Holdings in tooltips" subgroup on the Interface tab; #38 Toasts and #39 Farm are settings pages of their own beside General and Profiles (Toasts' tabs are the feeds and their sections). No deviation. |
| D22 | #39 activity tally (each line configurable): mobs looted (distinct corpses from loot windows; Retail 12.x gives addons no reliable kill count), items looted, nodes gathered, fish caught, quests turned in, quest rewards, containers opened, drops by quality, reputation, experience, skill-ups, new appearances; currencies gained and deaths off by default. |

## Status ledger

| Task | What | Status | Commit |
|---|---|---|---|
| M0.1 | Save mockups + this plan | done | `M0.1` commit |
| M0.2 | Re-vendor LibKa0s v1.114.0 → v1.118.0 (both payloads, provenance line, icon prune, gate) | done | `M0.2` commit (bundle `docs/revendor/2026-11-27-v1.118.0/`) |
| M0.3 | Push M0 | todo | |
| M1.1 | Compat: item and currency tooltip post-call hooks, tooltip id readers, live count reads (Retail + Forever) | done | `M1.1: Add Compat tooltip post calls, id readers, painters and live reads` |
| M1.2 | Holdings tally (per thing, per holder, per container; live current character; cache invalidated on `HOLDINGS_CHANGED`) + tests | done | `M1.2: Add the holdings tally over the saved store with a live overlay` |
| M1.3 | Tooltip block: icons + counts, staleness age, Total rule, settings rows (Interface tab subgroup "Holdings in tooltips", owner ruling), modifier mode, disabled-state, tests | done | `M1.3: Add the holdings tooltip block, its settings and container icons` |
| M1.4 | Public API v1 + CallbackHandler + tests + ARCHITECTURE contract | done | `M1.4: Add the public holdings API v1 with a CallbackHandler relay` |
| M1.5 | Docs (module map, schema rows, settings panel, smoke rows, per-client table, test-cases regen) | done | `M1.5: Document the holdings tooltip, its API and their smoke checks` |
| M1.6 | Review pass (workflow) + fixes; push M1 | todo | |
| M2.1 | Kinds `REPUTATION` / `APPEARANCE`, feature gate (appearance Retail-only), Compat reads | todo | |
| M2.2 | Reputation capture (gain + loss, faction, standing; Retail renown/friendship/paragon/warband; Forever standings) + tests | todo | |
| M2.3 | Appearance capture (collected IN, removed OUT; Retail) + tests | todo | |
| M2.4 | History / filters / Insights / Export / test data / sim for the new kinds; capture switches | todo | |
| M2.5 | Docs + review pass + fixes; push M2 | todo | |
| M3.1 | Gain feed: one pre-gate tap (loot, currency, money, rep, appearance, XP, skill-ups) with a single bus message | todo | |
| M3.2 | Feed host spike: LibKa0s Toast v4 vs own frames for slots / styling / motion; decide, record | todo | |
| M3.3 | Feed engine: 3 feeds, slots + nudge, grow, alignment + icon side, merge, stack, pin on hover, clicks | todo | |
| M3.4 | Row content: counts icons, price mode, ilvl badge, upgrade line, highlights + sounds, cap coloring, per-kind rows | todo | |
| M3.5 | Styling overrides (skin by default) + motion (enter, fade, pulse, timer bar, smooth reposition) | todo | |
| M3.6 | Settings (Toasts page, per-feed tabs), test toasts, unlock/drag, Blizzard-duplicate hiding, disabled-state, perf, sim | todo | |
| M3.7 | Docs + review pass + fixes; push M3 | todo | |
| M4.1 | Farm session model: start/pause/resume/finish, clock, AFK + idle, logout finishes, reload keeps, tallies, costs, activity, log cap, storage + cap | todo | |
| M4.2 | Companion panel (headline, numbers, activity, buttons, minimize, paused view) | todo | |
| M4.3 | Details window (6 tabs) + summary at Finish | todo | |
| M4.4 | Farm tab in the History window + panel sessions list (rename, delete, best per zone) | todo | |
| M4.5 | Ingress: title-bar button, 2 key bindings, slash verb, launcher entry; settings (Farm tab) | todo | |
| M4.6 | Test mode / sim, disabled-state, docs + review pass + fixes; push M4 | todo | |
| M5.1 | Whole-run review, doc sync, release notes; report to owner; wait for merge go-ahead | todo | |
| M5.2 | After merge: delete the run's branches (local + origin), stashes, worktrees | todo | |
