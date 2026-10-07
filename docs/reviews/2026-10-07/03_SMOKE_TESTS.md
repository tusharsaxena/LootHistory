# LootHistory — in-client smoke tests for the 2026-10-07 review changes

This list covers only what the client can verify. The headless suites ran in the measurement block of `01_FINDINGS.md`.

## Pre-flight

- After the changes land, re-run headless: `lua tests/run.lua` (all green, with the count matching `docs/test-cases.md`) and `luacheck .` (0/0).
- Retail 12.x, `## Interface: 120100`, loaded from `GIT/LootHistory` (the symlinked folder, never a side worktree).
- Turn on `/console scriptErrors 1` and keep BugSack handy. Turn on `/lh debug` where a step asks for it.
- Every line the addon prints must start with a cyan `[LH]`.

## Per-change tests

### C-01 — CCN refactor (no behavior change intended)
- **Setup:** an existing profile with history, the ledger on.
- **Steps:** 1. `/reload`. 2. Open `/lh`, and on the History tab cycle Group by through each option. 3. Toggle test mode on and then off. 4. Open the Holdings tab, type a search, and clear it. 5. Open Insights. 6. Run `/lh disable`, then `/lh enable`. 7. Visit a vendor, sell one item and buy one item.
- **Expected:** no Lua error. Groups, test-mode sample, holdings search results and Insights look the same as before the change. After step 6 the History window refreshes on a new loot line. After step 7 there is an `OUT SELL`, a gold `IN SELL`, a gold `OUT BUY` and an item `IN VENDOR`.
- **Pass:** all of the expected outcomes hold, with no BugSack entry.

### C-02 — Browser file peel
- **Setup:** as above.
- **Steps:** 1. `/reload`. 2. Open the window and use every filter-bar dropdown (Quality, Source, Character, Type, Zone, Direction, Bound) once. 3. Group by Character, then by Type & SubType. 4. Resize the window and drag it.
- **Expected:** every dropdown opens, ticks and filters. Grouping and holder-move rows render. No error.
- **Pass:** no Lua error, and every dropdown and grouping works.

### C-03 — Ledger Phase 2 sign-off
- Run **LED-P2-01 … LED-P2-24** exactly as written in `docs/smoke-tests.md` (*Ledger capture (timeline ledger Phase 2)*) and record each `Result:` there. LED-P2-06 (mail to your own alt) is the one that settles the `SendMail` post-hook fact cited at `modules/AttributionOut.lua:65`.
- **Pass:** all 24 results recorded, and any failure is filed and fixed.

### C-04 — Coalescer recovers after a stand-down
- **Setup:** Esc → Options → AddOns → Ka0s Loot History, General page open (the storage readout visible).
- **Steps:** 1. Loot an item, and type `/lh disable` within about 0.2 s of the loot line (a macro `/lh disable` bound to a key and pressed as the loot window closes makes this repeatable). 2. `/lh enable`. 3. Loot another item with the General page visible.
- **Expected:** the record count on the General page goes up by one after step 3.
- **Pass:** the count updates. (Before the fix it stayed frozen until a delete or prune.)

### C-05 — `ledgerEvent` bucket excludes the combat-exit flush
- **Setup:** carry several stacks of consumables.
- **Steps:** 1. Start `/lh perf` on the clean arm. 2. Enter combat with a target dummy, use a consumable 3 times, and leave combat. 3. Stop the capture and read the report.
- **Expected:** the `ledgerEvent` bucket's max per call stays in the dirty-bit range (hundredths of a ms) and shows no spike at the combat exit. After combat there is one `OUT CONSUME` row with quantity 3.
- **Pass:** no `ledgerEvent` call is an order of magnitude above the others. Record the capture as a frozen `docs/perf-analysis/<stamp>/` bundle through `/dev-copilot:wow-perf-analysis`.

### C-08 — Timeline intraday with holder moves
- **Steps:** deposit an item stack into the warband bank, then open the Timeline on that item, range **Today**.
- **Expected:** the character line steps down and the Warband line steps up at the deposit time. The Total stays flat.
- **Pass:** the lines step as described.

## Regression suite

- `/reload` cleanly, then log in with no error. `ADDON_LOADED` → `PLAYER_LOGIN` → `PLAYER_ENTERING_WORLD` raise no error.
- Enter and leave combat with the window open, and check that the General visibility setting is honored.
- Switch profiles once (`/lh profile <name>`), then switch back.
- Open the settings panel and toggle every Master-controls option once.
- **Cross-addon:** with all eleven Ka0s addons loaded, type each root (`/at /am /bl /cm /kcd /lh /mm /pm /pfe /pc /wg`) and confirm each reaches its own addon. Open Settings → AddOns and confirm each addon appears exactly once, and each multi-page addon's pages appear once each.

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|---|---|---|---|
| C-01 | | | |
| C-02 | | | |
| C-03 | | | |
| C-04 | | | |
| C-05 | | | |
| C-08 | | | |
| Regression | | | |
