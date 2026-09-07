# 01 — Findings

**Review date:** 2026-09-07 · **Repo:** LootHistory (v1.2.0, `LootHistory.toc` line 5) · **Reviewer:** principal-engineer review pass
**Standards cross-check:** performed. Resolved **Ka0s WoW Addon Standard v2.38.0, 2026-09-02** (`STANDARDS.md` header), all 27 section files fetched from `master` via the index's Sections list.

---

## Verdict

**Minor issues.** The addon is in unusually good shape: every out-of-game suite is green, the vendored payload is byte-identical to its declared tag, the library seams are model implementations of the descriptor/stub contract, and the load-order annotations in the TOC are genuinely load-bearing rather than decorative. Nothing found is a shipping blocker. What is found is one real display-path logic bug with a sleeping test under it, one un-coalesced burst listener that its two siblings already fix, two uncovered wiring paths, and a committed performance record that no longer describes the tree.

---

## Measurement run (Step 0 — everything re-run today, from scratch)

All commands run from `/mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory`. Fresh output written to a scratch path outside the repo; **no committed artifact was modified**.

| Suite | Command | Result |
|---|---|---|
| **luacheck** | `luacheck .` | **PASS** — `Total: 0 warnings / 0 errors in 28 files`. Scope: the five source folders (`core/ defaults/ locales/ modules/ settings/`); `.luacheckrc`'s `exclude_files` excludes `libs/`, `tests/`, `docs/audits/`, `docs/reviews/`, `_dev/`, so the suite and the vendored library are **not** linted. |
| **Headless suite** | `lua5.1 tests/run.lua` | **PASS** — `699 passed, 0 failed, 0 skipped, 699 total`. `0 skipped` is measured, not absent: the two vendor-sync cases found the sibling `LibKa0s` checkout and actually compared. |
| **Test-case inventory** | `lua5.1 tests/run.lua --list > <scratch>/list.md` then `diff <scratch>/list.md docs/test-cases.md` | **PASS, no drift** — the two files are byte-identical (812 lines, `**Total** \| **699**`). README `[Tests]` badge (`README.md:7`) reads `699%2F699_passing` and agrees. |
| **Offline perf runner** | — | **SKIPPED (absent by design).** `tests/perf.lua` does not exist; neither does `docs/perf-analysis/`. This is the ratified `performance-§12` no-combat-path exemption carried in `docs/ARCHITECTURE.md → ## Documented deviations` (`LH-20`…`LH-26`) and reasoned in `docs/performance.md`. Every perf claim below is therefore **unverified by measurement** and says so. |
| **Complexity** | `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` (verbatim, standard's invocation) | **PASS** — `No thresholds exceeded`; `Total nloc 13222, Fun Cnt 1761, Avg.NLOC 6.4, AvgCCN 2.2, Warning cnt 0`. Max CCN **15**, reached by **seven** functions (see F-011). |
| **Makefile `test:`** | — | **SKIPPED** — no root `Makefile`. |
| **Vendor sync** | `diff -r libs/LibKa0s/ <LibKa0s>/LibKa0s/` and `diff -r tests/_kit/ <LibKa0s>/testkit/`, re-run against `git show v1.25.0:…` with CR stripped | **PASS** — all 18 `libs/LibKa0s/` files plus the 123-file `media/` payload and all six `tests/_kit/` files are byte-identical to the `v1.25.0` tag the provenance line in `CLAUDE.md` names. The raw working-tree `diff` flags `DebugLog.lua`/`Pool.lua` only because the tree is CRLF and the blob is LF. |

### Committed artifacts vs. today's run

| Artifact | Committed says | Today says | Verdict |
|---|---|---|---|
| `docs/test-cases.md` | 699 total | 699 total, identical inventory | **current** |
| `README.md:7` `[Tests]` badge | 699/699 | 699/699 | **current** |
| `docs/automated-tests/RESULTS.md` | newest row `20260825-103428`: 644/644 tests, NLOC 12116, 1639 funcs, `bandFiles 3`; watch list names **six** CCN-15 functions | 699 cases, NLOC 13222, 1761 funcs, **four** files in the 1000–1500 band, **seven** CCN-15 functions | **STALE** — see F-011 |
| `docs/performance.md` | "Game events: eleven"; "`C_Timer` calls: four" | 13 event registrations; 5 `C_Timer.After` call sites | **STALE** — see F-005, F-007 |

**In-client checks are deliberately absent from this block.** They are in `03_SMOKE_TESTS.md`.

---

## High

*None.* No finding clears both the defect-kind floor and the reachability ceiling for High.

---

## Medium

### F-001 — `estimateRecordBytes` walks a table with holes, so the database-size estimate systematically undercounts `[bug]`

**Where:** `core/Database.lua:748-756` (the function), specifically `:750-752`.

```lua
local strFields = { r.itemLink, r.itemName,
                    r.zone, r.subzone, r.char, r.itemType, r.itemSubType }
for _, s in ipairs(strFields) do
```

**Problem:** the seven fields are packed into an array literal and walked with `ipairs`, which stops at the **first `nil`**. Any record whose `itemLink` is nil contributes **zero** string bytes; any record whose `itemName` or `itemType` is nil silently drops every field after it.

**Impact:** `Database:StorageStats().bytes` is wrong for a whole class of stored rows. **Every currency record has no `itemLink`** — `Collector:OnChatMsgCurrency` (`modules/Collector.lua:186-196`) builds its record without one — so every currency row is counted as bare `RECORD_OVERHEAD` (256) and its `itemName`, `zone`, `subzone`, `char`, `itemType`, `itemSubType` are never summed. The same happens to an item row captured while the item cache was cold (`Compat.GetItemInfo` answers nil for `itemName`; `GetItemExtras` answers nil for `itemType`).

**Reachability:** *Any player on a default profile who has ever looted a currency and then opens either the History window footer (`modules/Browser.lua:519-520`, "Database ≈ …") or the settings General page's storage line (`settings/Panel.lua:127`).* `settings.recordCurrency` defaults to `true` (`defaults/Global.lua:38`), so this is the default configuration, not an opt-in one. The consequence is a wrong number on a label that already says "(estimated)" — display only; nothing branches on `bytes`.

**Category:** `[bug]` · **Fix direction:** iterate the seven fields by fixed index (`for i = 1, 7 do`) or, better, sum them inline without building the array — which also removes F-004's per-record allocation. Compliant with `anti-patterns` either way; no standard rule constrains the shape.

---

### F-002 — the `StorageStats` case cannot go red under F-001 `[tests]`

**Where:** `tests/test_database.lua:371-380`, assertion at `:379` — `assertTrue(s.bytes > 0)`.

**Problem:** the case asserts only that the byte total is positive. `RECORD_OVERHEAD` is 256 and the fixture holds two records, so the assertion passes at 512 even if **every** string field were skipped. Worse, the fixture's records carry `ts`, `char`, `itemLink`, `itemName` and **no `zone`** — so `ipairs` truncates at index 3 in the test too, meaning the case is already exercising the buggy path and reporting green.

**Impact:** the inventory (`docs/test-cases.md`) claims coverage of `StorageStats`'s byte estimate. It has none. F-001 is a bug in code the suite says it tests — which is the more valuable half of that pair.

**Reachability:** *Only the test inventory — the shipped code's defect is F-001; this finding is about the assertion that lets it through.* Capped at Medium by that reachability line per the grading rule.

**Category:** `[tests]` · **Fix direction:** assert the **exact** expected byte total for a fixture with every field populated, plus a second fixture whose `itemLink` is nil (a currency row) asserting its `itemName` length *is* counted. Add the `-- red under: …` comment `testing-§12` wants, naming the mutation that reddens it.

---

### F-003 — the settings panel's `RecordAdded` listener is the one that was never coalesced `[perf]`

**Where:** `settings/Panel.lua:154-164`, registration at `:161`.

```lua
ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", onChange)
ev:RegisterMessage("Ka0s_LootHistory_RecordAdded", onChange)
```

**Problem:** issue #27 introduced `NS.Coalesce` (`core/Util.lua:234-249`) and wired it to the two bursty `RecordAdded` consumers — `modules/Browser.lua:1273-1274` and `modules/Analytics.lua:655-656` — each with a comment explaining that `HistoryChanged` stays immediate while the automatic per-item message must collapse. `settings/Panel.lua` is the **third** consumer of the same message and it registers the same handler for both, uncoalesced, with no comment acknowledging the asymmetry.

**Impact:** `onChange` calls `refreshStats` (`settings/Panel.lua:126-138`), which calls `Database:StorageStats` — an O(history) walk with a per-record allocation (F-004). With the settings panel open on the General page, a multi-drop loot burst pays one full-history pass **per looted item**, which is precisely the shape the coalescer exists to remove.

**Reachability:** *A player who leaves the Blizzard settings canvas open on this addon's General page while looting.* The handler is guarded by `P.general.panel:IsShown()`, so a closed panel costs nothing — narrow, but real and reachable out of combat with no special configuration.

**Category:** `[perf]` · **Fix direction:** wrap the `RecordAdded` registration in `NS.Coalesce(onChange, NS.Constants.RECORD_ADDED_COALESCE)`, leaving `HistoryChanged` immediate, exactly as the two sibling call sites do. **Unverified by measurement** — no `tests/perf.lua` exists to quantify it.

---

### F-004 — `estimateRecordBytes` allocates a seven-element table per record `[perf]`

**Where:** `core/Database.lua:750-751`, called once per record from `:766`.

**Problem:** the per-record helper builds a fresh array literal on every call. `StorageStats` walks the whole history, so a 20 000-row history allocates 20 000 short-lived tables per invocation. This is the "dispatch/defaults table built inside the function it serves" shape the standard's complexity guidance calls out — a per-call allocation where a straight-line sum would do.

**Impact:** GC pressure on a full-history pass, paid three times over: the History window footer, the settings storage line, and (per F-003) once per looted item while the panel is open.

**Reachability:** *Any player with a large history who opens the History window; the allocation count scales linearly with the row count.* No user-visible symptom short of a hitch on a very large database.

**Category:** `[perf]` · **Fix direction:** sum the seven fields inline with no intermediate table. Collapses naturally into the F-001 fix — one change covers both. **Unverified**: no offline scenario exists to put a number on it.

---

### F-005 — `docs/performance.md`'s event sweep is stale and omits the two combat-transition registrations `[docs]` `[perf]`

**Where:** `docs/performance.md:40` — *"**Game events: eleven, all of them occasional.**"* — and the table at `:42-52`.

**Problem:** the page's own regeneration command, re-run today, returns **13** rows, not eleven:

```
$ grep -rn "RegisterEvent(\"\|RegisterUnitEvent(\"" core modules settings defaults locales
… 13 matches …
```

The two the table does not list are `modules/Browser.lua:1277-1278` — `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED`, both routed to `B:ApplyVisibility()`. Those are literally the combat-transition events, and the sweep exists to support criterion **(a)** of the `performance-§12` exemption: *"no event handler doing more than occasional work while the player is in combat."*

**Impact:** the sweep is the *evidence* for the exemption, and it is incomplete on exactly the axis the exemption is about. The omitted handlers are in fact cheap (`frame:IsShown()` plus a settings read), so the exemption's **conclusion** survives — but a reader cannot know that from the page, and the next person to re-check the exemption will re-derive the sweep and find it disagrees with the prose.

**Reachability:** *A maintainer re-reading the exemption; no runtime effect.* Capped at Medium by that line.

**Category:** `[docs]` `[perf]` · **Fix direction:** regenerate the table from today's sweep, add the two `PLAYER_REGEN_*` rows with their per-fire cost, and update the count. Keep it in `docs/performance.md`; do not create a second sweep elsewhere.

---

### F-006 — the `CHAT_MSG_LOOT` row understates the per-fire work by an order of magnitude `[docs]` `[perf]`

**Where:** `docs/performance.md:45` — *"One chat line: parse, threshold-check, and on a keeper one table insert."*

**Problem:** on a keeper, `Collector:OnChatMsgLoot` (`modules/Collector.lua:81-150`) additionally runs:

- `NS.Compat.GetItemExtras(link)` (`modules/Collector.lua:123`), which calls `Compat.ScanBound` (`core/Compat.lua:218-239`) → **`C_TooltipInfo.GetHyperlink`, a full tooltip build**, and iterates its lines;
- `NS.AuctionPrice:GatherAll(link, itemID)` (`:124`), which allocates the provider map and `pcall`s into up to three third-party addons, one of them (`fetchTSM`, `modules/AuctionPrice.lua:23-32`) looping `TSM_API.GetCustomPriceValue` once per configured key — seven by default;
- `NS.Zone()`, `NS.PlayerMapID()`, `UnitClass("player")`, the record build, and the `RecordAdded` fan-out.

**Impact:** this sentence is the load-bearing half of criterion (a). A reviewer who trusts it concludes the capture path is a table insert; it is a tooltip build plus a cross-addon price cascade, fired once per looted item, and loot fires **during** combat with autoloot on.

**Reachability:** *A maintainer or auditor reading the exemption; no runtime effect on its own.* The underlying work is real and reachable by every player, but the finding here is the documentation's description of it.

**Category:** `[docs]` `[perf]` · **Fix direction:** rewrite the row to name the tooltip build and the AH cascade, and re-state whether criterion (a) still holds with that work in view. If it does, say why in the row (e.g. bounded by loot-line frequency); if the answer is no longer obvious, that is what `performance.md`'s "What ends the exemption" section is for. Do **not** resolve it by deleting the exemption — that would be a redesign, not a documentation fix.

---

### F-007 — the `C_Timer` table miscounts and cites a line that no longer exists `[docs]`

**Where:** `docs/performance.md:54` (*"**`C_Timer` calls: four**"*) and the row at `:60`.

**Problem, two parts:**

1. **The count is five, not four.** Today's sweep finds `C_Timer.After` at `core/LootHistory.lua:56`, `:60`, `core/ItemSetup.lua:71`, **`core/Util.lua:242`**, and `settings/OptionsSetup.lua:181`. The omitted one is `NS.Coalesce`'s own timer — the very mechanism the same page credits, two sections later at `:75-79`, with fixing the `RecordAdded` burst. The table and the prose below it contradict each other.
2. **The cite is dead.** The row reads `` `core/Compat.lua:202` `` for the item-cache retry. `core/Compat.lua:202` today is `  return false` — the tail of `lineIsAny`, an unrelated helper. The call actually lives at **`core/ItemSetup.lua:71`**, moved by the `LibKa0s-Item` seam adoption.

Two further line cites in the same block have drifted: `PLAYER_ENTERING_WORLD` is cited as `core/LootHistory.lua:37` (actual `:40`) and `C_Timer.After(5, …)` as `core/LootHistory.lua:54` (actual `:56`).

**Reachability:** *A maintainer following the citations; no runtime effect.*

**Category:** `[docs]` · **Fix direction:** regenerate the table from the page's own commands and re-resolve every `file:line`.

---

### F-008 — `Attribution:Enable` has zero test callers: the whole attribution wiring is uncovered `[tests]`

**Where:** `modules/Attribution.lua:327-361`.

**Problem:** `grep -rn "Attribution:Enable\|Attribution.Enable" core modules settings tests` returns exactly two hits — the definition and its single production caller at `core/LootHistory.lua:41`. **No test calls it.** `tests/test_attribution.lua` carries 23 cases, all against the pure resolvers (`DeconstructSource`, `ResolveLootSource`, the stampers) with the events hand-fed.

**Impact:** the function that wires seven `RegisterEvent` calls, one `RegisterUnitEvent` frame, three `hooksecurefunc` installs and two `Compat.Hook*` calls is exercised by nothing. A mistyped event name, a hook installed on the wrong global, or a handler bound to the wrong method would leave every downstream case green — the resolvers would still pass, and the source-attribution engine would simply never receive an event. Compare `Collector:Enable` and `Browser:Enable`, which *are* driven (`tests/test_collector.lua:436,459`; `tests/test_browser.lua:531,547,669`).

**Reachability:** *Only the test inventory today — no defect is present in the wiring. The exposure is that a future one would ship silently.* Capped at Medium.

**Category:** `[tests]` · **Fix direction:** add an integration case in `tests/test_attribution.lua` that calls `Attribution:Enable()` against the mock and asserts the registered event set and the hooked globals — the same shape `testing-§8` prescribes for the addon's own wiring (not a re-test of library behavior).

---

### F-009 — `tests/run.lua`'s lifecycle kick is a fourth hand-maintained list, unpinned, and has already drifted `[tests]`

**Where:** `tests/run.lua:41-46`.

```lua
NS:InitDB()
NS.Schema:Register()
NS.Panel:Register()
```

**Problem:** the comment above it reads *"The lifecycle kick the client's OnInitialize does."* `addon:OnInitialize` (`core/LootHistory.lua:29-35`) does **four** things: `NS:InitDB()`, `Schema:Register()`, **`Slash:Register()`**, `Panel:Register()`. The runner omits `Slash:Register()`. `addon:OnEnable` and `addon:OnEnterWorld` are never invoked at all — `grep -rn "OnEnable\|OnEnterWorld" tests/*.lua` returns only a comment.

`tests/test_harness.lua` is exemplary at pinning the three lists `testing-§9` names (the TOC derivation, the disk check, the suite list, plus duplicate detection). It does not pin this one — and this one has the same silent-failure signature: the runner claims to reproduce the client's init and quietly does something else.

**Impact:** the suite measures an addon initialized differently from the shipped one. Today the divergence is benign (`Slash:Register` only calls `RegisterChatCommand`), but nothing detects the next divergence, and `addon:OnEnterWorld`'s deferred prune + double warbound-repair schedule — the only caller of `Database:PruneOld` and `RepairBoundStates` in the lifecycle — is untested as a sequence.

**Reachability:** *Only the test inventory; the shipped `OnInitialize` is correct.* Capped at Medium.

**Category:** `[tests]` · **Fix direction:** either call `addon:OnInitialize()` directly (with `Slash:Register` mock-guarded) or add a `test_harness.lua` case comparing the runner's kick against the members `OnInitialize` actually calls, so a fifth step added to the lifecycle fails the gate rather than being silently skipped.

---

### F-010 — `AuctionPrice:GatherAll` rebuilds a settings-invariant map on every loot line `[perf]`

**Where:** `modules/AuctionPrice.lua:58-66` (`wantedByProvider`), called from `:73` inside `GatherAll` (`:70`).

**Problem:** `wantedByProvider(capture)` walks `settings.auction.capture` and builds a nested `{ provider = { key = true } }` table. Its input changes only when the user edits the capture set; its output is recomputed on **every captured loot line**, allocating one outer table plus up to three inner ones each time.

`modules/Collector.lua` already owns the pattern for exactly this: hot-path upvalues refreshed on `Ka0s_LootHistory_SettingsChanged` (`modules/Collector.lua:9-12, 67-79, 223-225`). `AuctionPrice` has no equivalent seam and recomputes instead.

**Impact:** four short-lived tables per looted item, in the capture path, plus the `pairs` walk over the capture set. Small per fire; paid per drop on every AoE pull.

**Reachability:** *Any player with `settings.auction.enabled` true (the default, `defaults/Global.lua:47`) on every captured loot line.*

**Category:** `[perf]` · **Fix direction:** memoise `wantedByProvider`'s result in a module upvalue, invalidated on `Ka0s_LootHistory_SettingsChanged` through the same private bus target `Collector` uses (`NS.NewBusTarget`, `core/LootHistory.lua:22-27`). **Unverified by measurement** — no offline scenario exists; if one is added, this is the first candidate. Note that adding `tests/perf.lua` is a **larger** decision that intersects the ratified `performance-§12` exemption; see `02_PROPOSED_CHANGES.md`.

---

### F-011 — `docs/automated-tests/RESULTS.md` no longer describes the tree `[complexity]` `[docs]`

**Where:** `docs/automated-tests/RESULTS.md`, whose newest row is `20260825-103428` (that bundle's `manifest.json` carries the run stamp).

**Drift, from today's verbatim `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .`:**

| | Committed (`20260825-103428`) | Fresh (2026-09-07) |
|---|---|---|
| Tests | 644/644 | **699/699** |
| Total NLOC | 12116 | **13222** |
| Functions | 1639 | **1761** |
| `bandFiles` (1000–1500 LOC) | 3 | **4** |
| Functions at CCN 15 | 6, named in the watch list | **7** |

Specifically:

- **`settings/Panel.lua` has newly crossed into the 1000–1500 on-notice band** at **1004 LOC**. It appears in no band table.
- **`AuctionPrice:MovePriorityWithin`** (`modules/AuctionPrice.lua:153-177`) is a **seventh** function at CCN 15. The watch list names six and states *"unchanged in membership, CCN and line range across the last four runs."*
- Every watch-listed line range has moved: `BrowserTable:GroupRecords` is cited at `:550` (fresh run attributes the CCN-15 block to `BrowserTable@605-653`), `BrowserTable:UpdateHeaderArrows` at `:968` (fresh: `@1028-1071`), `BrowserTable:BindRow` at `:866` (fresh: `@917-934`), `Attribution:OnLootOpened` at `:173` (fresh: `@173-196`, still correct), `Compat.ScanBound` at `:271` (fresh: `@219-239`).
- The `modules/Analytics.lua` "peel next" entry, flagged in the record itself as a shelf-life problem after four runs, is now **five** runs old and the file is at 1178 LOC.

**Impact:** the record still reads as measured. Nothing in it is wrong-by-hand — it is honestly stale — but a reader citing it today cites a tree that is 1106 NLOC and 55 test cases behind.

**Reachability:** *A maintainer or auditor citing the record; no runtime effect.* Capped at Medium.

**Category:** `[complexity]` `[docs]` · **Fix direction:** regenerate at the **next release** via `/wow-addon:bump-version` (`automated-tests` puts the checkpoint at release, not at commit). Do **not** regenerate into the repo as part of a fix, and do not gate commits on `lizard` — the standard names that a documented anti-pattern. `settings/Panel.lua` crossing the band is the entry the next run should carry a disposition for.

---

### F-012 — `%s` trims cannot strip NBSP in the two localized-text scanners `[locale]`

**Where:** `core/Compat.lua:229` and `modules/Attribution.lua:66-67`.

```lua
-- core/Compat.lua:229
local lower = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
-- modules/Attribution.lua:66
if seed.dropLast then name = name:gsub("%s+%S+%s*$", "") end
```

**Problem:** Lua's `%s` class does **not** match U+00A0 (`\194\160`), which localized WoW tooltip lines and spell names carry routinely on deDE and frFR. A leading or trailing NBSP survives both trims, so:

- in `Compat.ScanBound`, `lower` retains the NBSP, and both the `WARBAND_LINES[lower]` lookup and the `BIND_TO_WARBAND_PREFIX` compare (`core/Compat.lua:207`) miss;
- in `Attribution.seedToken`, `%s+%S+%s*$` will not strip a final word separated by an NBSP, so the "Mass Mill/Prospect" name-family prefix is wrong for that client.

**Impact, bounded honestly:** both scanners have a locale-independent path in front of them — `lineIsAny` compares raw `text` against the `_G` wording globals (`core/Compat.lua:196-203`), and `DECONSTRUCT_ID` matches by spell id first (`modules/Attribution.lua:32-43`). So the NBSP path is the **fallback**, not the primary, and a non-enUS client mostly resolves before reaching it. The residual exposure is the un-enumerated Mass-Mill/Prospect variants, and warbound wordings whose `_G` global the client left nil.

**Reachability:** *A player on a non-enUS retail client whose warbound tooltip line or Mass-Mill spell name carries an NBSP, and only where the id/global path did not already answer.* Narrow, and the addon ships English-only user strings anyway (`locales/enUS.lua:7-9`, an accepted scope decision).

**Category:** `[locale]` · **Fix direction:** match `[ \194\160]` in place of `%s` in these two trims, or pre-substitute NBSP with a space before trimming. Do **not** translate the English literal tables — they are correctly the fallback below the `_G` globals.

---

## Low

### F-013 — `B:Hide`'s `NS.CloseMenu` comment describes behavior the frame's own `OnHide` already covers `[naming]`

**Where:** `modules/Browser.lua:1162` — `NS.CloseMenu()   -- the slash-command close path; frame:Hide() below does not reach the popup`.

The claim is no longer true: `modules/Browser.lua:1073-1076` installs `frame:HookScript("OnHide", …)` which calls `NS.CloseMenu()`. The suite pins it (*"Widgets: the History window's OnHide closes the shared popup"*). The explicit call is now harmless-but-redundant and the comment actively misdirects — a reader deleting the `OnHide` hook would believe `B:Hide` is the only guard, when `B:Toggle` (`:1168`) and `frame:Hide()` from Escape both rely on the hook.

**Reachability:** *A comment; no runtime effect.*

**Fix direction:** correct the comment to say the `OnHide` hook is the guard and this call is belt-and-braces, or drop the call and let the hook own it.

---

### F-014 — two migration comments describe a chain that has moved on `[docs]`

**Where:** `defaults/Global.lua:6-9` and `core/Database.lua:193`.

`defaults/Global.lua` still reads *"ships a v1→v2 migration that strips the retired per-record `viaWhitelist` field and bumps the stamp to 2"*; the chain now runs to **v8** (`core/Database.lua:23,32,44,59,78,94,103`). `core/Database.lua:193` calls `RepairBoundStates` *"the deferred half of the v6->v9 migration"* — there is no v9; the pair is v6→v7 (`:94`) plus the revision-armed repair.

Related: `defaults/Global.lua:9` ships `schemaVersion = 1`, so a **fresh install** runs all seven steps over an empty history at first login. Harmless (every step is guarded and non-destructive) but it is unnecessary work and an unnecessary set of `[Migrate]` lines on a brand-new DB, and no comment says the shipped stamp is deliberately the floor.

**Reachability:** *Comments and a small first-login cost; no user-visible effect.*

**Fix direction:** correct both comments. Leave `schemaVersion = 1` as it is unless a comment is added explaining that the floor is deliberate — changing the shipped default would need care around AceDB's defaults merge and is not worth the risk for the benefit.

---

### F-015 — nine tracked files are LF-only in a CRLF-pinned tree, one is mixed `[line-endings]`

**Where:** working tree, measured today with the `line-endings-§7` byte count (`tr -dc '\r' | wc -c` vs `tr -dc '\n' | wc -c`) over `git ls-files` excluding binaries and the `*.sh` carve-out:

```
.pkgmeta                          lf=17    cr=0
core/Constants.lua                lf=172   cr=0
core/MediaSetup.lua               lf=149   cr=0
core/Util.lua                     lf=252   cr=216   ← MIXED
docs/revendor/2026-08-25/01_DELTA.md   lf=104   cr=1
docs/revendor/2026-08-25/05_SUMMARY.md lf=51    cr=0
modules/Analytics.lua             lf=1178  cr=0
settings/Slash.lua                lf=311   cr=0
tests/test_util.lua               lf=374   cr=0
```

`.gitattributes` is correct and complete — the `* text=auto eol=crlf` pin, the `*.sh text eol=lf` carve-out and the full binary block are all present and match the collection's canonical file. `tests/_kit/run-automated-tests.sh` is correctly LF. These are **working-tree stragglers** written by tools that bypassed git's filters, not a policy defect: four are shipped source, and `core/Util.lua` is mixed within one file.

**Reachability:** *No runtime effect — the client tolerates LF. The cost is diff noise and the next `git add --renormalize`.*

**This is an observation, not the authoritative check.** The rolled-up straggler count and its verdict belong to `/wow-addon:standards-audit` (`line-endings-§2`).

**Fix direction:** `git add --renormalize .` at the repo root, then `rm <path> && git checkout -- <path>` for each working-tree straggler, per the recipe `.gitattributes` itself documents at its foot.

---

### F-016 — the degraded slash help lists `config`, which then refuses `[ux]`

**Where:** `settings/Slash.lua:174-178` (`LIBRARY_OWNED`) and `:220-229` (`Sl.HelpRows`).

On a degraded install the help is rendered by **subtraction** — a good design — but `LIBRARY_OWNED` names only the seven verbs the `Slash` module owned. `config` survives the subtraction and is printed as available; invoking it reaches `NS.Panel:Open()` → the `Options` stub's `OpenOptionsPanel` (`settings/OptionsSetup.lua:71-73`), which prints *"…so the settings panel is unavailable."* The one install where the user most needs an accurate list of what still works advertises a verb that immediately declines.

Conversely `help` **is** in `LIBRARY_OWNED`, so it is subtracted out of the list — yet `Sl.PrintHelp` works perfectly on that path (`:230-233`). Defensible (listing "help" inside help output is redundant) but it means `LIBRARY_OWNED`'s comment — *"the verbs that went THROUGH the library, and only those"* — is doing two jobs at once.

**Reachability:** *Only a user whose `libs/LibKa0s/` is missing or fails LibStub's floor — a broken install, and only after they type `/lh`.*

**Fix direction:** the subtraction is right; the set is what needs widening. Rename it to reflect what it means (verbs unavailable on this path) and add `config` to it. Do not hand-write a second verb list — the existing subtraction-from-`NS.COMMANDS` design is the compliant one (`slash-commands-§1`).

---

### F-017 — `Attribution:Consume` never consumes `[naming]`

**Where:** `modules/Attribution.lua:127-133`.

The function reads `State.lootContext`, checks its TTL and returns it — it never clears it. That is deliberate (one kill's context serves several loot lines, and the docstring at `:110` says *"the next self-loot line(s)"*), but the name states a mutation the body does not perform. A reader auditing the single-slot context's lifetime has to read the body to learn that expiry, not consumption, is what ends it.

**Reachability:** *A reader; no runtime effect.*

**Fix direction:** rename to `PeekContext` / `CurrentContext`, or keep the name and add one line stating that the context is TTL-scoped rather than single-use. The former is cheap — `grep -rn "Consume" core modules settings tests` shows a bounded call set.

---

### F-018 — `NS.version` is a second declaration of the TOC's version with nothing pinning them together `[design]`

**Where:** `core/Namespace.lua:5` (`NS.version = "1.2.0"`) and `LootHistory.toc:5` (`## Version: 1.2.0`).

They agree today. `NS.Version()` (`core/EnvSetup.lua:71-74`) correctly prefers the TOC and treats the constant as a fallback, and its comment explains why the fallback is visible here rather than in the library — good reasoning. But nothing in the suite compares the two: `tests/test_envsetup.lua:63` asserts `NS.Version() == NS.version` **on the path where the TOC is unreadable**, which is the case that cannot detect drift. So the constant can go stale at a release and only a headless run — where the TOC reader is absent — would ever surface it, and that run is the one asserting they are equal by construction.

**Reachability:** *Nobody today — the values agree. The exposure is a future release that bumps the TOC and forgets `core/Namespace.lua`, after which only a degraded install reports the wrong version.*

**Fix direction:** add a case that parses `## Version:` out of `LootHistory.toc` and asserts it equals `NS.version`. The loader already reads the TOC (`Loader.tocFiles`), so the machinery exists.

---

## Upstream findings

**None.** Every defect above lands in this repo's own files. The vendored `libs/LibKa0s/` and `tests/_kit/` payloads were diffed against the `v1.25.0` tag `CLAUDE.md` names and are byte-identical; no defect was found in either while reading the seams. Nothing in `02_PROPOSED_CHANGES.md` targets a path under `libs/` or `tests/_kit/`.

---

## What this review looked at and found clean

Recorded so a later reader knows these were examined rather than skipped.

- **Taint / combat lockdown.** No protected API is called from a non-secure path. `hooksecurefunc` is used correctly at all five sites (`core/Compat.lua:23,25,45`; `modules/Attribution.lua:350,353,356`) — never `:Hook`. No `SecureActionButtonTemplate`, no `SetAttribute`, no `RegisterUnitWatch`. `InCombatLockdown()` is read once (`modules/Browser.lua:1134`) and only to decide window visibility. No `setmetatable` on a widget instance.
- **Deprecated APIs.** `C_Container`, `C_Item`, `C_Spell`, `C_AddOns`, `C_UnitAuras`-era surfaces are used throughout with presence-gated global fallbacks (`core/Compat.lua`, `core/EnvSetup.lua`). No `InterfaceOptions_AddCategory`. `Settings.*` registration is the library's, not the addon's.
- **Event registration.** Events are registered in `OnEnable`, never `OnInitialize` (`core/LootHistory.lua:38-43`); each module's `Enable` is idempotent behind `self._enabled`. `UNIT_SPELLCAST_SUCCEEDED` is correctly unit-filtered via a dedicated `RegisterUnitEvent` frame (`modules/Attribution.lua:342-343`). Every message consumer uses a private `NS.NewBusTarget()`, never the shared bus-as-self — the CallbackHandler clobber the comments describe is genuinely avoided.
- **Saved variables.** One write path (`Schema:Set`) with two documented carve-outs (`modules/Browser.lua:105,688`, the window geometry), both matching the `architecture-§5` carve-out the schema header declares. The migration runner stamps **after** apply and only for steps that ran. Defaults contain no functions, frames or cycles; the AH priority array is copied element-by-element rather than aliased (`defaults/Global.lua:70-72`).
- **Library seams.** `core/CoreSetup.lua`, `core/DebugLogSetup.lua`, `core/EnvSetup.lua`, `core/ItemSetup.lua`, `core/MediaSetup.lua`, `core/PoolSetup.lua`, `core/WidgetsSetup.lua`, `settings/OptionsSetup.lua`. Each stub answers a **superset** of the members the addon calls; the `Options` stub deliberately mirrors the live table member-for-member with a comment saying why. `MakeCloseButton` correctly passes the third `addonName` argument. No local re-implementation of a library subsystem was found.
- **Media.** The library catalog is reached first at every art site (`NS.Icon`), with the Blizzard atlas and a solid chip strictly **below** it as fallbacks (`modules/BrowserTable.lua:79-90, 93-114`). No second copy of a shipped asset under `media/`.
- **Test harness.** `tests/run.lua` derives the addon's load list from the TOC via `Loader.tocFiles` and spells out the 14 `libs/LibKa0s/` files in exactly `LibKa0s.xml`'s order (verified). `tests/test_harness.lua` pins all three lists plus duplicate detection. Degraded-path cases load the addon **with the library genuinely absent** (`loadDegraded`), not by hand-stubbing. `test_vendor_sync.lua` reports a **skip carrying its reason** when the sibling checkout is missing rather than an early-return pass.
- **Slash surface.** All 14 `NS.COMMANDS` entries (`settings/Schema.lua:430-462`) are documented in `README.md:81-93`, and every documented verb is in the table. No drift in either direction.
