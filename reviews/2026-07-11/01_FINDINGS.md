# 01 — Findings · Ka0s Loot History

**Review date:** 2026-07-11 · **Reviewer:** principal-engineer full-scope pass
**Commit:** `6482a3e` (master, clean) · **Target:** `## Interface: 120007`, `## Version: 0.1.0`

## Verdict

**Minor issues — not ship-blocking, but one High finding (attribution coverage gap) should be
addressed or explicitly documented before tagging 0.1.0.**

The addon is well-structured, cleanly layered, and green on `luacheck .` (1 trivial warning) and
`lua tests/run.lua` (85/85). No taint or secret-value findings: the browser is non-secure by
design (§6A), the settings panel is combat-gated and uses the modern `Settings.*` API correctly
(`Settings.OpenToCategory(mainCategoryID)` — passes the category ID, not the frame), events are
registered in `OnEnable`, saved-variable writes funnel through `Schema:Set` for schema rows, and
there are no protected-API calls in non-secure paths. The issues below are functional-coverage,
convention-drift, and cleanup items.

---

## High

### F-001 — AH / CRAFT / ROLL sources are unreachable; VENDOR/MAIL/TRADE capture is unverified `[design]`
`modules/Attribution.lua` (whole file) · `core/Constants.lua:6-22` · `modules/Collector.lua:56-85`
- **Problem:** `TECHNICAL_DESIGN §4` (lines 270-276) specifies stampers for MAIL, TRADE, AH,
  VENDOR, CRAFT, ROLL, but `Attribution.lua` only implements MAIL, TRADE, VENDOR (plus KILL /
  CONTAINER / MPLUS / QUEST). There is **no AH, CRAFT, or ROLL stamper**, yet `SourceType`,
  `SourceLabel`, `SourceOrder`, `SOURCE_OPTIONS` (mute list), `Analytics.SOURCE_COLOR`, and the
  Browser Source/Group dropdowns all expose those buckets.
- **Second problem:** the collector consumes *only* `CHAT_MSG_LOOT`. VENDOR (`BuyMerchantItem`),
  MAIL (`TakeInboxItem`/`AutoLootMailItem`), and TRADE (`TRADE_ACCEPT_UPDATE`) stamps assume those
  flows emit a self-loot / `LOOT_ITEM_PUSHED_SELF` chat line. That assumption is **unverified** and
  historically false for vendor buys and trade completion (items enter bags with no loot message);
  mail-to-bag is inconsistent. If they do not emit `CHAT_MSG_LOOT`, those three stampers are dead
  and VENDOR/MAIL/TRADE records are never written.
- **Impact:** Users see filter/group/mute options for sources that can never appear; several
  advertised acquisition types may silently record nothing. Coverage does not match the UI or the
  design doc.
- **Note:** the TRADE stamp fires on `playerAccepted==1 and targetAccepted==1`, which is *before*
  completion (TD calls for `ERR_TRADE_COMPLETE`); a re-opened/cancelled trade leaves a premature
  stamp (harmless only because no loot line follows). Verify all three in-client (see 03 §F-001).

---

## Medium

### F-002 — Compat firewall bypass in Attribution `[convention]`
`modules/Attribution.lua:126-131` (`OnChallengeModeStart`)
- **Problem:** calls `C_ChallengeMode.GetActiveKeystoneInfo` and `C_Map.GetBestMapForUnit`
  directly. `core/Compat.lua` already wraps the latter as `Compat.GetPlayerMapID()`; the
  challenge-mode call has no wrapper. CLAUDE convention §4 requires all flavor-varying API access
  to live in `core/Compat.lua`.
- **Impact:** duplicated map-id logic and a Classic-flavor branch outside the firewall;
  future flavor changes ripple into a module instead of one place.

### F-003 — Table-typed setting defaults are aliased on reset `[logic]`
`settings/Schema.lua:89-96` (`S:Set`) · `settings/Slash.lua:112-126` (`CliReset`/`CliResetAll`)
- **Problem:** `S:Set` writes `value` by reference; `CliReset*` pass `row.default` directly. For
  `settings.excludedSources` (`default = {}`), the DB now points at the *same table object* held in
  the schema row. `S:Default` also returns the shared table. Any in-place mutation of the stored
  set would corrupt the schema default (currently masked only because `makeMultiCheck` copies
  before writing).
- **Impact:** latent aliasing hazard; a future writer that mutates the set in place silently
  poisons the defaults for the rest of the session.

### F-004 — Localization infrastructure present but entirely unused `[locale]`
`locales/enUS.lua:5-9` (luacheck `W211 unused variable L`) · all modules
- **Problem:** `NS.L` + the metatable fallback + `locales/enUS.lua` exist, but **no** user-facing
  string routes through `L[...]`. Every label, tooltip, slash description, empty-state message,
  and dialog string is hardcoded English (`"Purge history…"`, `"No loot recorded yet. Go kill
  something."`, column labels, `GROUP_OPTIONS`, etc.). The `local L` in `enUS.lua` is unused.
- **Impact:** the addon is not translatable despite shipping the scaffolding; the convention drift
  will grow with every new string. (May be an accepted v0.1.0 English-only scope decision — if so,
  document it and either remove the unused `L` local or start wrapping strings.)

### F-005 — Duplicated date-range + GUID-kind logic `[design]`
`modules/Browser.lua:348-359` (`dateFrom`) vs `modules/Analytics.lua:124-135` (`rangeFrom`) ·
`core/Compat.lua:25` vs `modules/Attribution.lua:36` (`UNIT_KINDS`)
- **Problem:** `dateFrom` and `rangeFrom` are near-identical range→timestamp helpers; `UNIT_KINDS`
  is declared twice with the same contents.
- **Impact:** two copies that can drift (e.g. adding a "90d" range or a new unit GUID kind must be
  done in two places); the range helpers belong in `core/Util.lua`, the kind set in `Compat`.

### F-006 — Player-scope toggle desyncs from a specific-character filter `[ux]`
`modules/Browser.lua:472-485` (`SetCharFilter`)
- **Problem:** selecting a specific *other* character in the Character dropdown sets the char
  filter to that character but flips the Player toggle to **"All players"** (because
  `char ~= currentKey()`), even though exactly one character is shown.
- **Impact:** the two controls contradict each other — the scope toggle claims "All players" while
  the table shows one non-current character. Confusing state.

---

## Low

### F-007 — Dead helpers `Util.FormatTime` / `Util.TableCount` `[dead-code]`
`core/Util.lua:24-33, 78-82`
- Zero callers anywhere (source or tests). `FormatTime` was superseded by `FormatClock` +
  `FormatDate`; `TableCount` is unreferenced. Remove or wire up.

### F-008 — Collector initial upvalue contradicts schema default `[naming]`
`modules/Collector.lua:9`
- `qualityThreshold` seeds to `2` but the schema default is `1`. Overwritten by `RefreshUpvalues()`
  on `Enable`, so harmless, but the literal misleads. Seed to `1` (or `nil` + guard).

### F-009 — Stale comment references a non-existent command `[comment]`
`modules/BrowserTable.lua:240`
- Comment says "via `/lh testmode`"; the actual command is `/lh test` (`Schema.lua:136`).

### F-010 — `savedView` + `settings.window` persist outside the Schema single-write-path `[design]`
`modules/Browser.lua:76-83, 537-547`
- `NS.db.global.savedView` and `settings.window` are written directly, bypassing `Schema:Set`
  (they are not schema rows, so `Schema:Set` would reject them). Acceptable as non-schema runtime
  state, but it quietly contradicts the "every mutation goes through `Schema:Set`" convention and
  is undocumented. Add a one-line note in CLAUDE/TD carving these out.

### F-011 — `State.keystone.mapID` is stored but never read `[dead-data]`
`modules/Attribution.lua:130` vs `:49-53` (`ResolveLootSource` uses only `keystone.level`)
- Dead field; either drop it or use it in the MPLUS detail.

### F-012 — TOC `Interface`/CRLF hygiene `[toc]`
`LootHistory.toc:1`
- `## Interface: 120007` implies a 12.0.7 client. **Verify** it matches the live/target build (TWW
  is 11.x; 12.x is Midnight-era). No `.gitattributes` declares CRLF for Lua/XML even though the
  repo vendors libs and ships to Windows clients — not a convention already in use, so noted only
  as a hardening suggestion.

### F-013 — `COMBAT_LOG_EVENT_UNFILTERED` registered unfiltered `[perf]`
`modules/Attribution.lua:180`
- The handler runs on *every* combat-log line (very hot in raids) just to harvest
  `UNIT_DIED`/`PARTY_KILL` names into an 80-entry cache. Correct and allocation-free, but the whole
  subsystem exists to name kill sources; consider whether the name cache earns its per-line cost,
  or gate it (e.g. only while a loot-eligible kill is plausible). Low impact; note for later.
