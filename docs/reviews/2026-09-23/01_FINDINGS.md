# LootHistory — Review Findings (2026-09-23)

**Verdict: minor issues.** Nothing here blocks shipping. One High attribution bug writes wrong data to
SavedVariables for any player who runs a Mythic+ key. The rest are Medium and Low data-quality,
performance, stub-drift and hygiene items. The addon is otherwise in very good shape: lint is clean,
858/858 cases pass, no function is over the CCN limit, and the vendored copies are byte-identical to
their source.

Reviewed at branch `feat/2026-09-23-review-audit-remediation` (HEAD `54b7cc7`), addon version 1.3.0,
LibKa0s v1.55.0 vendored.

## Measurement run

All of these ran today, 2026-09-23, from the repo root. `ka0s-bounded` was not on this shell's
`PATH`, so every run used the absolute path `/home/tushar/.claude/wow-addon/bin/ka0s-bounded …`.
Those runs were bounded: the plain `timeout 900` fallback was never needed. All output went to a
scratch directory, and nothing was written into the repo except this bundle.

| Suite | Result | Command |
|---|---|---|
| luacheck | **pass**: 0 warnings / 0 errors in 65 files | `ka0s-bounded luacheck .` |
| Headless test suite | **pass**: 858 passed, 0 failed, 0 skipped, 858 total (exit 0) | `ka0s-bounded lua5.1 tests/run.lua` |
| Fresh `--list` inventory | **pass**: 858 total. Diffing it against the committed `docs/test-cases.md` (CR-normalized) gives **0 lines**, so no drift | `ka0s-bounded lua5.1 tests/run.lua --list > <scratch>/list.md` |
| `tests/perf.lua` | **skipped**: the file does not exist. The repo ships no offline scenarios. The perf harness is a recorded deviation (`performance-§12`, ARCHITECTURE.md → Documented deviations) | — |
| lizard | **pass**: 16326 NLOC, 2200 functions, avg CCN 2.1, **0 warnings**, max CCN 15 (seven functions sit at 15) | `ka0s-bounded lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` |
| `make test` | **skipped**: there is no root `Makefile` | — |
| Vendor sync (lib) | **pass**: `diff -rq LootHistory/libs/LibKa0s LibKa0s/LibKa0s` is empty (LibKa0s at `46ccaa6`, `v1.55.0-3`) | run from the parent dir |
| Vendor sync (kit) | **pass**: `diff -rq LootHistory/tests/_kit LibKa0s/testkit` is empty | run from the parent dir |
| Cross-addon: slash tokens | **clean**: 20 roots across 10 addons (the nine plus AuraMaster), `uniq -d` is empty, zero raw `SLASH_*` in TOC-loaded source | the class-1 pair of commands, TOC-derived scope |
| Cross-addon: vendored minors | **clean**: one line across all 10: `Bus:1 Compat:1 Core:7 DebugLog:12 Env:1 Item:1 Launcher:1 Lifecycle:1 Media:3 Options:23 Perf:12 Pool:3 Schema:1 Slash:14 Widgets:9` | the class-2 command |
| Cross-addon: payload bytes | **clean**: `diff -rq AbsorbTracker/libs/LibKa0s <each>/libs/LibKa0s` is empty for all 10. AbsorbTracker was the reference | the class-3 command |
| Cross-addon: `## Interface:` | **clean**: `120100`, the same in all 10 | the class-4 command |

The cross-addon results depart from the 2026-09-07 recorded baseline in two ways, and neither is a
collision:

- The roster is now ten addons with 20 roots, because AuraMaster was added.
- The majors moved together to the minors listed above, and `## Interface:` moved together from
  `120007` to `120100`.

Both classes are still single-valued, so this is recorded as a **measured non-finding**. The baseline
table needs refreshing upstream.

Where a committed artifact disagrees with today's fresh run:

- **`docs/automated-tests/RESULTS.md`** is stale. Its newest bundle, `20260916-184506` (manifest SHA
  `b267e38`), records 786 cases, 63 lint files, 15349 NLOC and 2045 functions. Today's run gives 858
  cases, 65 files, 16326 NLOC and 2200 functions. All four watch-list band files are still in the
  1000–1500 band, and three have grown:

  | File | Watch list | Today |
  |---|---|---|
  | `modules/Analytics.lua` | 1178 | 1200 |
  | `modules/Browser.lua` | 1244 | 1271 |
  | `settings/Panel.lua` | 1062 | 1107 |
  | `modules/BrowserTable.lua` | 1225 | 1225 |

  The watch list flags no function, and neither does today's run. Browser's disposition says it
  "shrank this cycle", but it has since grown back by 27 lines. This is stale, not non-compliant. It
  gets regenerated at release.
- **`docs/test-cases.md`** matches the fresh run: 858, and 0 diff lines.
- **`docs/performance.md`** has no fresh counterpart to check against, because there is no
  `tests/perf.lua`.

LOC census scope: `git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)' | xargs wc -l` (the default
scope; `tests/` is included). No file is over the 1500 cap. The largest are:

| File | Lines |
|---|---|
| `modules/Browser.lua` | 1271 |
| `modules/BrowserTable.lua` | 1225 |
| `modules/Analytics.lua` | 1200 |
| `settings/Panel.lua` | 1107 |
| `tests/test_schema.lua` | 1048 |
| `tests/test_slash.lua` | 1020 |

**Standards cross-check:** Ka0s WoW Addon Standard **v2.64.0 (2026-09-23)**. The index and all 27
section files it links came through `curl` from `raw.githubusercontent.com`. All 27 are byte-identical
(CR-normalized) to the local `WowAddonStandards` checkout at `e68795f`.

## Conventions detected (sweep)

- **Printer:** `NS.PREFIX` (`core/Namespace.lua:18`) plus `NS.Print` from LibKa0s-Core
  (`core/CoreSetup.lua`). Files that print take `local print = NS.Print` as an upvalue. No raw
  `print(` bypasses the printer.
- **`NS.COMMANDS`:** host-owned positional triples, wrapped by `gateFeatureVerbs`
  (`settings/Schema.lua:719-795`), which the Slash major dispatches.
- **Single write seam:** `NS.Schema:Set` delegates to the LibKa0s-Schema-1.0 runtime
  (`settings/Schema.lua:616`). Direct `db.global` writes exist only for sanctioned carve-outs: the
  history array, the id-list registries, `savedView`, window geometry and the AH priority array.
- **`settings/Schema.lua`:** a flat-row schema with a composed Master controls block.
- **Secret-values doc:** none. `docs/midnight-quirks.md` states the addon reads no secret-tainted data.
- **`.gitattributes`:** `* text=auto eol=crlf`, `*.sh text eol=lf`, and binary marks for images, fonts
  and archives. `git ls-files --eol` reports 355 `w/crlf`, 130 `w/-text` (binary) and 1 `w/lf`, which
  agrees with the pin. This is an observation only; the check itself belongs to
  `/wow-addon:standards-audit`.
- **LibKa0s majors wired**, one setup file each:

  | Major | Setup file |
  |---|---|
  | Core | `core/CoreSetup.lua` |
  | Env | `core/EnvSetup.lua` |
  | Item | `core/ItemSetup.lua` |
  | Media | `core/MediaSetup.lua` |
  | Lifecycle | `core/LifecycleSetup.lua` |
  | Widgets | `core/WidgetsSetup.lua` |
  | DebugLog | `core/DebugLogSetup.lua` |
  | Pool | `core/PoolSetup.lua` |
  | Launcher | `core/LauncherSetup.lua` |
  | Options | `settings/OptionsSetup.lua` |
  | Slash | the seam in `settings/Slash.lua` |
  | Schema | the seam in `settings/Schema.lua` |
  | Bus (Catalog only) | `core/Constants.lua` |
  | Compat (`GetSpellName` only) | `core/Compat.lua:94-95` |

  **Perf is declined**, and the decline is a documented deviation.
- **Test kit:** vendored at `tests/_kit/`. `tests/run.lua` gets its addon load list from
  `Loader.tocFiles` and the library list from `Loader.xmlFiles`, which satisfies `testing-§9`.
- **Media:** the addon draws its marks through `NS.IconMarkup` from the library catalog.
  `modules/Browser.lua:1047-1048` keeps Blizzard's size-grabber on purpose: the comment records the
  choice as a collection-wide match.

---

## High

### F-001 — Mythic+ keystone context is never cleared, so every later GameObject loot is recorded as `MPLUS` `[logic]`

- **Where:** `modules/Attribution.lua:228-233` stamps the context:
  `State.keystone = { level = NS.Compat.GetActiveKeystoneLevel() }`.
  - `:235-243` deliberately keeps it after completion: `-- Keep the keystone context: the reward chest is looted shortly after completion.`
  - `:173-176` consumes it: `elseif kind == "GameObject" then` / `if state.keystone then return S.MPLUS, { keystoneLevel = state.keystone.level }`.
  - The only place anything clears it is `:411`, inside `Attribution:Disable`. No event handler
    clears it. Measured with `grep -rn keystone modules core settings`: the writes are at `:229`,
    `:238` and `:411`.
- **Problem:** once a key starts, `State.keystone` stays set for the rest of the session. Nothing
  clears it on leaving the instance, on `CHALLENGE_MODE_RESET`, or on a zone change. So every later
  `LOOT_OPENED` from a GameObject resolves to `MPLUS` with that key's level. That covers herb and ore
  nodes, world chests, treasure caches, and GameObject containers in any other instance.
- **Impact:** wrong `source` and `sourceDetail.keystoneLevel` values are **persisted** to
  `LootHistoryDB`. They show up in the History table's Source column, the Source filter, Insights
  "Loot by source" and the keystone breakdown (`core/Database.lua:557-558`), and in both CSV exports.
  Nothing repairs them after the fact.
- **Reachability:** any player on a default profile who starts a Mythic+ key and then, without a
  `/reload`, loots a GameObject anywhere else in the same session. That is an ordinary session for
  anyone who runs keys and gathers.
- **Coverage:** the inventory claims only the pure resolver with injected state
  (`tests/test_attribution.lua:71` `ResolveLootSource GameObject in keystone → MPLUS + level`). No case
  covers how long the keystone context lives, so the suite is green over this path without testing it.
- **Related, unverified:** at `:238`,
  `NS.Compat.GetActiveKeystoneLevel() or State.keystone.level` stores `0` if the API answers `0` after
  completion, because `0` is truthy in Lua. Verify in-client (smoke S-001).
- **Fix direction:** clear the keystone context when the player leaves the challenge-mode instance.
  Use `ZONE_CHANGED_NEW_AREA` / `CHALLENGE_MODE_RESET` together with an instance-type check through a
  new `NS.Compat` presence-guarded shim. Do **not** register `PLAYER_ENTERING_WORLD` on the shared
  `NS.addon` target: `core/LifecycleSetup.lua:112` already owns that `(event, target)` pair for
  `OnEnterWorld`, and AceEvent would silently replace it.

## Medium

### F-002 — Encounter detail is cleared at `ENCOUNTER_END`, before the boss is looted `[logic]`

- **Where:** `modules/Attribution.lua:223-226` clears it
  (`function Attribution:OnEncounterEnd()` / `State.encounter = nil`). `:168-171` is the only place
  that reads it (`if state.encounter then detail.encounterID = …`), through `OnLootOpened` (`:203`).
- **Problem:** `ENCOUNTER_END` fires when the boss dies. The corpse's `LOOT_OPENED` comes after that.
  So by the time boss loot is resolved, the encounter context is already gone.
- **Impact:** `sourceDetail.encounterID` and `difficulty` are effectively never written for boss loot.
  Yet `docs/data-flow.md:74` and `docs/midnight-quirks.md:17` describe the field as captured. The
  stored data does not match its documentation, and the export's `sourceDetail` field is emptier than
  the schema says. No UI shows it today, which caps the severity here.
- **Reachability:** any player who loots a boss corpse, every time. The effect is limited to a stored
  field the UI never displays.
- **Fix direction:** keep the last encounter for a short window after a successful `ENCOUNTER_END`,
  mirroring how the keystone context outlives completion, or document the field as not captured.
  Verify the event order in-client first (smoke S-002).

### F-003 — The currency-category cache is built once per session and never rebuilt `[logic]`

- **Where:** `core/Compat.lua:392-393` (`if not currencyCategoryCache then buildCurrencyCategoryCache() end` /
  `return currencyCategoryCache[currencyID]`). It is consumed at capture time in
  `modules/Collector.lua:198` (`itemSubType = NS.Compat.CurrencyCategory(currencyID)`).
- **Problem:** the id-to-header map is a snapshot of the currency list taken at the first currency loot
  of the session. A currency the player first discovers later that session is missing from the
  snapshot. So is one whose header was collapsed when the snapshot was taken, since
  `GetCurrencyListInfo` walks only the visible list (unverified in-client).
- **Impact:** that currency's row is **persisted** with `itemSubType = nil`. It lands in the empty
  Type breakdown and never gets backfilled.
- **Reachability:** any player who picks up a currency new to their account after their first currency
  loot of the session. This happens routinely at the start of a season.
- **Fix direction:** on a miss, rebuild the cache once per miss-burst, or invalidate it on
  `CURRENCY_DISPLAY_UPDATE`. Both belong in `core/Compat.lua` (the compat firewall).

### F-004 — Shortening "Keep history for" deletes history immediately, with no confirm `[ux]`

- **Where:** `settings/Schema.lua:370-375`. The `settings.retentionDays` row's `onChange` is
  `NS.Database:PruneOld()`.
- **Problem:** picking a shorter retention in the dropdown, or typing `/lh set settings.retentionDays 7`,
  deletes every older record in the same click. Deleting all history with `/lh purge`, by contrast,
  goes through a confirm popup (`settings/Slash.lua:8-18`, `KA0S_LOOTHISTORY_PURGE`).
- **Impact:** one mis-click on a dropdown throws away months of stored loot, and it cannot be undone.
  The addon's own UX treats deletion as confirm-worthy everywhere else.
- **Reachability:** any player who opens General → History and picks a shorter value, even by
  accident, or who uses the documented `set` verb.
- **Fix direction:** keep the write, and defer the destructive prune to a confirm, or to the next
  login's deferred prune, which already runs 5 s after entering the world
  (`core/LootHistory.lua:81-84`). Tell the player in chat when the prune will happen.

### F-005 — The degraded Slash stub's refusal line has drifted from the library's `[design]`

- **Where:** `settings/Slash.lua:255-257`:

  ```lua
  return ("%s is disabled \226\128\148 enable it with |cFFFFFF00%s|r"):format(NS.BRAND, "/lh")
  ```

  The library's version is at `libs/LibKa0s/Slash.lua:596`:

  ```lua
  lib.DISABLED_LINE_FORMAT:format(tostring(d.brandName or d.slash), d.slash .. " enable")
  ```
- **Problem:** the stub's comment claims it is "byte-identical to `lib.DISABLED_LINE_FORMAT`", but it
  renders `enable it with /lh`, not `/lh enable`. That breaks the canonical line shape
  (`slash-commands-§7`, *The refusal line*). It is also the failure the review brief names: a stub that
  restates a library line format is the copy that goes stale.
- **Impact:** on a library-less install where the stored switch is off, a feature verb tells the
  player to type `/lh`, which only prints degraded help. On that path, `enable` is also unavailable
  (`:282-286`), so the refusal points at nothing that works.
- **Reachability:** only an install whose `libs/LibKa0s` failed to load **and** whose stored
  `settings.enabled` is `false`. That is not a normal install.
- **Fix direction:** derive the stub line from the same parts the library uses: slash plus `" enable"`.
  The better fix drops the stub's own format. If the wording is also wrong on this path because
  `enable` does not work there, say so plainly and do not re-spell the line. See the
  `library-stack-§7` stub rules.

### F-006 — The value derivation re-parses the AH priority list for every record on every read `[perf]`

- **Where:** `modules/AuctionPrice.lua:91-100`. `AuctionPrice:Pick` calls `cfg()` (`:93`) and then
  runs `tag:match("^(.-):(.+)$")` (`:96`) on each priority tag until one hits. It is reached through
  `NS.Util.RecordValue` (`core/Util.lua:82-88`) once per record in `Database:Stats`
  (`core/Database.lua:657`). The CSV exporter calls it three or four times per row
  (`modules/Export.lua` columns `auctionPrice`, `auctionPriceRaw`, `value`, `valueRaw`,
  `auctionSource`).
- **Also:** `accumulateTime` (`core/Database.lua:536-539`) calls `date()` twice per record, and
  `date("*t")` allocates a table each time.
- **Problem:** the per-record cost grows with the priority list: up to 11 pattern matches, each
  allocating capture strings. That is loop-invariant work that should be hoisted, which is the rule
  `Database:QueryList`'s own header states (`core/Database.lua:307-313`). `Stats` runs on every filter
  change, and after each coalesced `RecordAdded` while Insights is open.
- **Impact:** extra full-history CPU and garbage on the Insights tab and on export. This is
  **unverified**: there is no `tests/perf.lua` to measure it, and no capture exists under
  `docs/perf-analysis/`.
- **Reachability:** any player with a large history who opens Insights or exports. It is worse with
  AH pricing enabled and a record that only matches a low-priority tag.
- **Fix direction:** pre-split the priority list into `{prov, key}` pairs once per settings change,
  following the hot-path upvalue pattern (`events-frames-taint-§7`), and cache the day and hour
  breakdown per distinct `ts` day. Measure it before claiming a win (see 02 §LLD C-006).

### F-007 — `tests/test_debuglog.lua` keeps unit cases for the library's own formatter `[tests]`

- **Where:** `tests/test_debuglog.lua:10-28` (`FormatPlain wraps the tag…`,
  `FormatPlain renders the tag verbatim…`, `FormatPlain tolerates a nil tag`,
  `FormatColored colors the timestamp and tag…`).
- **Problem:** these four cases test LibKa0s-DebugLog's rendering, which is library behavior, not this
  addon's wiring. `testing-§8` says those cases move with the behavior.
- **Impact:** a formatter change upstream has to be fixed in two places. These four cases go red on a
  legitimate library re-vendor while the library's own suite is green.
- **Reachability:** test inventory only. No shipped behavior is affected.
- **Fix direction:** delete the four duplicated cases and keep the integration cases in the same file
  (the secret-safe sink wired through `NS.SafeToString`). The pass count and badge move in the same
  change.

### F-008 — The DebugLog degradation stub copies the library's line formatters, and no addon code calls them `[design]`

- **Where:** `core/DebugLogSetup.lua:34-40`, where `FormatPlain` / `FormatColored` repeat the
  library's format strings and color codes (`|cff6f8faf`, `|cffc9a66b`).
- **Problem:** a grep across the addon's own non-test Lua finds no caller of either member.
  Only `tests/test_debuglog.lua` reaches them, and it reaches the **live** library instance. The stub
  still carries a hard-coded copy of the library's colors.
- **Impact:** this copy goes stale. It is the reverse of an under-answering stub: a stub that
  re-implements library formatters.
- **Reachability:** nobody at runtime. On a degraded install nothing calls these two members, so the
  copy is inert.
- **Fix direction:** if `tests/test_surface_parity.lua` needs the member names to exist, have them
  return `tostring(msg)`, or use the parity `ignore` list. Drop the copied format strings.

## Low

### F-009 — The window resize grip ignores *Lock frame* `[ux]`

- `modules/Browser.lua:1049` (`grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)`)
  has no `B:IsLocked()` check.
- The title-bar drag at `:958-961` does check it: `if B:IsLocked() then return end`.
- **Reachability:** any player who ticks *Lock frame* and then drags the window corner. The resize is
  persisted by `SaveWindow()`.
- `docs/settings-panel.md:40` defines *Lock frame* as drag-only, so this is a UX expectation gap rather
  than a contract break.
- **Fix direction:** gate the grip the same way, or say so in the tooltip.

### F-010 — Four stale or misplaced comments `[naming]`

- `settings/Schema.lua:759-760`: "the only reader of the flag is modules/Collector.lua's capture gate".
  This is false. Collector stopped reading `enabled` (`modules/Collector.lua:10-16`), and the reader
  is now `NS.AddonIsOff` (`core/LifecycleSetup.lua:175-178`).
- `settings/Slash.lua:279`: "modules/Collector.lua still reads it". Also false, for the same reason.
- `core/Util.lua:14`: "Split a dotted settings path…" sits above `Util.DeepCopy`. It belongs above
  `Util.SplitPath` at `:25`.
- `core/Util.lua:38`: "Compact date (MM/DD/YY)", directly followed by "DD-MMM-YYYY", which is what
  the function actually does.
- **Reachability:** a comment; no runtime effect.

### F-011 — Two stale line citations in `docs/midnight-quirks.md` `[docs]`

- `:9` cites `C_TooltipInfo.GetHyperlink (:226)`. It is actually at `core/Compat.lua:234-235`.
- `:64` cites `Compat.GetMailHeader (:90-96)`. It is actually at `core/Compat.lua:98-104`.
- **Reachability:** doc text; no runtime effect.

### F-012 — Two vocabularies for bind state `[ux]`

- **Two label sets across the two exports.** `modules/Export.lua:11-14` uses `BOP = "Bind on Pickup"`
  and `NONE = "Not Bound"` for the row CSV. `:140-141` uses `BOP = "Soulbound"` and
  `UNBOUND = "Unbound"` for the Insights CSV.
- **Two sentinels for the same "no bound" state in one file.** `core/Database.lua:357` uses
  `r.bound or "NONE"`, and `:524` uses `r.bound or "UNBOUND"`.
- **Reachability:** any player who opens both CSVs side by side. The labels disagree, and the data
  does not.

### F-013 — The launcher tooltip repeats the brand literal and offers a left-click that the disabled state refuses `[ux]`

- `core/LauncherSetup.lua:113` hard-codes `"Ka0s Loot History"`, where `NS.BRAND` is the one brand
  spelling (`core/Namespace.lua:13`; `label = NS.BRAND` is already at `:77`).
- `:117` shows "Left-click: open the history window" even while the addon is disabled, when the click
  prints the refusal line (`:104-106`). The click is also a toggle, not just an open.
- **Reachability:** any player who hovers over the minimap button.

### F-014 — The degraded `CliResetAll` clears all three id lists and then says "unavailable" `[ux]`

- `settings/Slash.lua:317-320` runs `NS.Filters:ClearAll()` and then `unavailable()`. The player sees
  only "the slash command interface is unavailable", even though their blacklist, whitelist and
  currency blacklist were just emptied.
- **Reachability:** only a library-less install that reaches `CliResetAll`. The `resetall` verb is not
  dispatched there, so the reach is only through a host caller. Nobody reaches it on a normal install.

### F-015 — Warbound repair can never warm the cache for a row that has only an `itemLink` `[logic]`

- `core/Database.lua:214`: `NS.Item.LoadItem(r.itemID)` with `r.itemID == nil` is a no-op
  (`libs/LibKa0s/Item.lua:122`), so the row stays pending until the 10-pass cap.
- **Reachability:** rows with a link and no id, which live capture does not produce. Only legacy or
  hand-edited rows are affected.
- **Fix direction:** fall back to `NS.Item.ItemIDFromLink(r.itemLink)`.

### F-016 — The loot hot path allocates a gate-config table on every loot line `[perf]`

- `modules/Collector.lua:116-119` builds `{ qualityThreshold = …, … }` for every `CHAT_MSG_LOOT`.
- **Reachability:** every loot line. The cost is one small table, which matters only in mass-loot
  bursts. **Unverified** (no perf runner).
- **Fix direction:** reuse a module-level table refreshed in `RefreshUpvalues`, and set `itemID` on it
  per call.

### F-017 — `Database:Export` calls itself a "plain copy" but shares nested tables with the live history `[design]`

- `core/Database.lua:439` (`auctionPrice = r.auctionPrice`) and `:442` (`sourceDetail = r.sourceDetail`)
  copy by reference.
- **Reachability:** only a caller that mutates an export result. No shipped path does that today.

### F-018 — The login prune always sends `HistoryChanged`, even when it removed nothing `[perf]`

- `core/Database.lua:796-798` calls `fireHistoryChanged()` unconditionally. With the History window
  open, that triggers the roughly nine full-history passes described in `core/Util.lua:230-235`, five
  seconds after login, for nothing.
- **Reachability:** a player with a retention limit set who has the window open five seconds after
  login.

---

## Upstream findings

None. Nothing found under `libs/` or `tests/_kit/` is a defect, and both vendored copies are
byte-identical to their source.
