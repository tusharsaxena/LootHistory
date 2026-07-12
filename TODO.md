# TODO — Ka0s Loot History

Actionable items outside the milestone tracker in `CLAUDE.md`. The post-v0.1.0 backlog lives here
(moved from `docs/EXECUTION_PLAN.md`).

## Settings panel

- [ ] **"Reset All" should only reset settings, not purge the database — rename to "Reset Settings".**
  Currently the button (`settings/Panel.lua:378-392`, `Slash:CliResetAll` / `ResetEverything`, and the
  `KA0S_LOOTHISTORY_RESETALL` StaticPopup) wipes history **and** settings. Change it to reset settings only,
  leaving `LootHistoryDB.global.history` intact, and relabel the button + slash command (`resetall`) copy to
  "Reset Settings". History clearing stays the job of the separate **Purge History** action.

- [ ] **Check the width of the "Reset All" / "Purge History" buttons — they appear to overflow the settings panel.**
  Both use `SetRelativeWidth(0.5)`; verify they fit within the panel's content width and don't clip or spill,
  and adjust the relative width / layout if they do.

- [ ] **Purge history in Settings.** A "Clear all history" button (with confirm) in the options panel —
  mirrors the `/lh purge` slash command already implemented.

## Attribution

- [ ] **Broad recipe-crafting attribution → CRAFT.** Disenchant/mill/prospect are stamped (their
  spell SUCCEEDS right as the mats push, within TTL). General profession crafting is not: a recipe's
  cast time can exceed the 1.5s context TTL, so a stamp at `C_TradeSkillUI.CraftRecipe` call time
  would expire before the crafted item lands. Needs a craft-*completion* signal (or an "extend TTL
  while a craft is in progress" mechanism) before hooking recipe crafting.

- [ ] **Tune attribution context lifetime.** Context is stamped once on `LOOT_OPENED` with a fixed 1.5s TTL,
  so *slow manual click-looting* (>1.5s between items in one window) lets later items fall back to
  `OTHER`/`INFERRED`. Consider keeping the context alive *while the loot window is open* — re-stamp/extend on
  each loot, expire on `LOOT_CLOSED` — instead of a fixed TTL. NOTE: CLAUDE.md flags the single-slot TTL as a
  deliberate design; revisit that note if changing.

## Insights / analytics

The Insights tab now covers vendor-value (total + by source/zone + over time + top items by value),
per-character, item-type, bound-type, hour-of-day, weekday, Mythic+ keystone level, attribution confidence,
quality distribution + mix, and the highlight cards — all off the single `Database:Stats` pass. Remaining:

- [ ] **Quality-mix *trend* over time.** Ship a stacked-per-day quality strip (each day's bar segmented by
  quality share) as a richer version of the current single-bar "Quality mix" composition. Needs a
  stacked-over-time chart primitive and a `qualityByDay` aggregation in `Database:Stats`.
- [ ] **Top bosses / NPCs.** Rank kill sources by `sourceDetail.npcID` / `encounterID`. Blocked on
  name resolution — the source *name* is intentionally not stored (schema v4), and there's no cheap
  synchronous `npcID → name` API. Needs a name cache or tooltip-scrape helper first.
- [ ] **(Tier 4 — needs addon interop, see below)** market/AH value analytics (Auctionator/TSM) layered on
  top of the existing vendor-value views, and a **Pawn upgrade-rate** insight (% of gear drops that were an
  upgrade at loot time). These depend on the **Addon interop** item.

## Addon interop

- [ ] **Integrate with value/upgrade addons** and show their data as columns/annotations (degrade gracefully
  when the addon isn't present):
  - **Auctionator / TSM / other AH addons** — market/AH value per item (fallback chain across whichever is
    installed). Feeds the Tier-4 market-value analytics above.
  - **Pawn** — an **upgrade arrow** when the looted gear was an upgrade *at the time of looting* (evaluate
    against the character's equipped gear then and store the verdict on the record, since "now" may differ).
    Feeds the Tier-4 upgrade-rate insight above.
  - **Loot Appraiser** and any other appraisal addons — pull their value estimates where available.

## UI / polish

- [ ] **Column chooser.** Let the user reorder and show/hide table columns (the `BrowserTable.COLUMNS` model
  already carries per-column metadata; add a settings/table-header UI and persist the order + visibility).
- [ ] **Bundle a monospace font** (e.g. Fira Mono) in `media/` and register it via LibSharedMedia, for the
  debug console (WoW ships no monospace; the console currently uses the default font, whose tabular digits
  keep timestamps aligned).
- [ ] **Configurable window styling.** The browser window ships a flat "ElvUI-like" default skin, centralized
  in `modules/Browser.lua`'s `SKIN` table and `B:ApplySkin(frame)`. Add settings to customize **border**
  (color/thickness), **background** (color/alpha), and **font** (via LibSharedMedia), driven off that table
  with live re-skin. New Schema rows under an "Appearance" section; `ApplySkin` already exists as the single
  re-skin seam.

## v2

- [ ] **AI export + companion skill** (the deferred v2 feature; `Database:Export()` seam already in place).
