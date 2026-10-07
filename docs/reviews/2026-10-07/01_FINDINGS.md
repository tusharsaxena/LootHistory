# LootHistory — review findings (2026-10-07)

**Verdict: minor issues.** No Critical or High findings. The suites are green, lint is clean, and the cross-addon pass is clean. The timeline-ledger work merged on 2026-10-06/07 put 26 functions back above CCN 15, which blocks the next release tag. It also left two files near the 1500-line cap and the ledger's in-client API checks unrecorded.

**Resolved scope:** `all`, so the whole repository at `b9c1271` (branch `feat/2026-10-07-review-audit-remediation`, clean tree). The review covered the authored Lua (`git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)'`, 116 files), the TOC and the docs that make claims about the code. `libs/` and `tests/_kit/` were checked only through vendor sync. Depth was uneven: the timeline-ledger modules (`core/Ledger.lua`, `modules/Reconciler.lua`, `modules/Escrow.lua`, `modules/Holdings.lua`, `modules/Rollup.lua`, `modules/AttributionOut.lua`, `modules/TimelineModel.lua`, `core/LifecycleSetup.lua`, `core/Database.lua` migrations and the write path, plus `settings/Slash.lua`) were read in full. The older UI modules were checked by targeted greps for frame creation, script handlers, raw `print`, timers, hooks and deprecated APIs.

**Profile:** `profile=wow`, `kind=addon`, from `dev-copilot-profile`. **Standard:** v2.76.1 (2026-10-07), fetched with curl from `tusharsaxena/WowAddonStandards@master` into scratch. The standards cross-check ran.

## Measurement run

The scratch root for every output is `/tmp/claude-1000/.../scratchpad/lh/`, and `B` = `~/.claude/dev-copilot/bin/ka0s-bounded`. The interpreter is Lua 5.1.5 (`/usr/bin/lua`). There is no root `Makefile`, so the `make test` row does not apply.

| Suite | Result | Command |
|---|---|---|
| luacheck | **pass**: 0 warnings / 0 errors in 116 files | `B luacheck .` |
| Headless suite | **pass**: 1476 passed, 0 failed, 1 skipped, 1477 total. The skip is the kit's `diagnostics contract: an addon that opts out…`, which skips by design because this addon keeps the default. | `B lua tests/run.lua` |
| `--list` inventory | **pass**: byte-identical to the committed `docs/test-cases.md` (`diff` after CR strip printed nothing) | `B lua tests/run.lua --list > scratch/list.md` |
| Offline perf (`tests/perf.lua`) | **ran**, 5 PASS lines: harness live; zero-overhead dropped loot line 0.0 B/iter bracketed vs 0.0 bare; combat `BAG_UPDATE` 0.0 B/iter and 0 scans; reconcile 1 scan per dirty group | `B lua tests/perf.lua` |
| Complexity (sighted, kit rev 37) | **recorded, non-gating**: **26 warnings**, max CCN **24**, 4431 functions / 31695 NLOC, avg CCN 2.5, blind files 0 (none reported) | `B bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle` |
| Complexity at `f31727b` (2026-10-01, last GI-LH-02 commit) | 0 warnings (sighted shadow over a `git archive` extract in scratch) | `git archive f31727b \| tar -x -C scratch/old`, then the runner's own shadow + fixed lizard invocation |
| Vendor sync | **pass**: `diff -rq libs/LibKa0s ../LibKa0s/LibKa0s` and `diff -rq tests/_kit ../LibKa0s/testkit` printed nothing. The LibKa0s checkout equals tag `v1.70.0` (`git diff --stat v1.70.0 -- LibKa0s testkit` printed nothing), matching the `CLAUDE.md` provenance line `v1.70.0`. Kit revision 37 on both sides. | as stated |
| Cross-addon, class 1 (slash tokens) | **clean**: 22 roots across 11 addons, `uniq -d` empty. LootHistory holds `lh` and `loothistory`. No raw `SLASH_*` in any TOC-loaded file. | the two loops in the overlay, TOC-derived load list |
| Cross-addon, class 2 (LibKa0s minors) | **clean**: one line, agreed by all 11 (`Bus:2 Compat:1 Core:10 DebugLog:19 Env:1 Item:2 Launcher:5 Lifecycle:3 Media:4 Options:28 Perf:14 Pool:3 Schema:2 Slash:19 Widgets:12`) | overlay loop |
| Cross-addon, class 3 (payload bytes) | **clean**: no `diff -rq` output for any addon against AbsorbTracker's copy | overlay loop |
| Cross-addon, class 4 (`## Interface:`) | **clean**: `120100` in all 11 | overlay loop |

The roster has 11 addons (the rows of `WowAddonStandards/standards/ADDONS.md`) and the tag is `v1.70.0`. The tag has moved past the overlay's v1.56.0 baseline, so the library-derived figures above are today's, recorded at v1.70.0. The overlay's baseline is out of date, which is not drift and not a finding.

**Committed artifacts compared with today's run:**

- `docs/automated-tests/RESULTS.md` and the newest bundle `20260927-030334` (`manifest.json`: sha `8e60c1f`, 171 commits behind HEAD) are **stale**. They record 961 tests, 0 CCN warnings, max CCN 15 over 2519 functions, and `perf` as a permanent `skip` under the `performance-§12` exemption. Today's run measures 1476/1/1477 tests and 26 warnings at max 24 over 4431 functions, and `tests/perf.lua` now runs because the exemption was retired on 2026-10-06 (`docs/ARCHITECTURE.md`, *Documented deviations*). Stale means stale, not non-compliant: the record is regenerated at release.
- `docs/test-cases.md` matches the fresh `--list` output exactly.
- `docs/performance.md`'s scenarios 1–3 agree with today's perf output. No contradiction found.
- README `Tests-1476/1476_passing` matches the 1476 passed today. The 1477th case is the kit skip.

---

## Medium

### F-001 — 26 functions above CCN 15 since 2026-10-01, which blocks the next release tag `[complexity]`

- **Where:** the 26 functions in today's sighted run. Among them are `core/Database.lua:149` `convertHolderMoves` (CCN 24), `core/LifecycleSetup.lua:143` `NS.StandUp` (24), `core/Database.lua:1018` `Database.Stats` (23), `modules/Reconciler.lua:88` `onEvent` (21), `core/Database.lua:810` `accumulateLedger` (20) and `modules/Holdings.lua:208` `Holdings.Search` (20). The full list is in `02_PROPOSED_CHANGES.md` C-01. Cited line text: `core/Database.lua:149` reads `local function convertHolderMoves(g)`, and `core/LifecycleSetup.lua:143` reads `function NS.StandUp()`.
- **Problem:** The last GI-LH-02 commit (`f31727b`, 2026-10-01) measured 0 sighted warnings. The 123 commits since then, mostly the timeline ledger, added 26 functions above CCN 15, and none of them is on the committed watch list.
- **Impact:** `automated-tests-§3` (*The release gate*) gates the tag on "zero functions above CCN 15". `/dev-copilot:bump-version` will therefore refuse the next release until these are fixed or ruled on. Several of them, such as `NS.StandUp` (16 `X and X.Y` guards) and `R.WriteRows`, score high because of dense guarding rather than tangled control flow. Others, such as `convertHolderMoves`, `planExits` and `onEvent`, are real branching.
- **Reachability:** No player. Only the maintainer cutting the next release, whose `bump-version` run gates on this.
- **Measurement:** fresh run `26 warnings … max 24`. `f31727b` extract: 0 warnings.

### F-002 — `BrowserTable.lua` is 24 lines under the file cap, and both browser files are past their own re-check triggers `[design]`

- **Where:** `modules/BrowserTable.lua` has 1476 lines and `modules/Browser.lua` has 1416 (`wc -l`). Census, default scope: `git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)' | tr '\n' '\0' | xargs -0 wc -l | awk '$2!="total" && $1>1000'` lists 10 files in the 1000–1500 band (5 source: `modules/BrowserTable.lua` 1476, `modules/Browser.lua` 1416, `core/Database.lua` 1218, `settings/Panel.lua` 1133, `settings/Schema.lua` 1133; 5 test files: `tests/test_browser.lua` 1414, `tests/test_browsertable.lua` 1247, `tests/test_schema.lua` 1202, `tests/test_slash.lua` 1129, `tests/test_database.lua` 1109) and 0 over 1500.
- **Problem:** The committed watch-list dispositions set triggers that have now fired. `BrowserTable.lua` was "Re-check at 1300 lines" (it was 1227 then) and `Browser.lua` was "Re-check at 1400 lines, and peel the widget kit then" (1289 then). The ledger work grew them by 249 and 127 lines.
- **Impact:** The band is the compliant state under `layout-§1`, but the next feature in `BrowserTable.lua` (the History table's grouping, holder moves and test-mode code all live there) breaches the 1500 cap, which `layout-§1` calls "a bug — peel it".
- **Reachability:** Maintainers only, with no runtime effect. Any change of about 25 lines to `BrowserTable.lua` turns this into a cap breach.

### F-003 — The ledger's in-client API facts have no recorded result, though the doc's own sign-off condition requires them `[tests]`

- **Where:** `docs/smoke-tests.md:1328`, which reads "Phase 2 is signed off only when all of LED-P2-01 to LED-P2-24 are recorded." All 24 `LED-P2-*` entries have an empty `Result:` (`awk` count: 24 blank, 0 filled). `modules/AttributionOut.lua:65` reads `-- (to be verified by smoke LED-P2-06). The bags only change on MAIL_SEND_SUCCESS.`
- **Problem:** The bracketed facts are client behavior the headless suite cannot check. Examples: `SendMail` is a post-hook that still sees the staged attachments, and `ACCOUNT_MONEY` fires on a warband deposit. The ledger rows' reasons and pairings depend on them, and the docs' own gate says Phase 2 is not signed off until they are recorded. The feature merged to master (`f60fb05`, 2026-10-07) with that gate open.
- **Impact:** If any one of those facts is wrong, every ledger row that depends on it is written with the wrong reason or pairing. Those rows are persisted account-wide in `LootHistoryDB`, so a later fix cannot rewrite them.
- **Reachability:** Today, only the owner's live install (the game loads `GIT/LootHistory` through a symlink). The ledger is unreleased: `LootHistory.toc:5` reads `## Version: 1.4.0`, and 1.4.0 was released at `8e60c1f`, before the ledger. Once the next version ships, every player on the default profile reaches it (`defaults/Profile.lua:41`: `trackLedger = true`).
- **Note:** Only the owner can run this. In-client smoke results are recorded by the owner and are never marked passed by an agent.

## Low

### F-004 — A coalesced repaint whose timer the stand-down cancels never fires again on a surface that outlives the stand-down `[correctness]`

- **Where:** `core/Util.lua:249` (`function Util.Coalesce(fn, delay)`): `pending` is set before `NS.After(delay, function()` (`:261`) and cleared only inside that body (`:265`, `pending = false`). `core/LifecycleSetup.lua:66` (`if h.canceled then return end`) returns before that body runs once `NS.CancelDeferrals` has set `h.canceled = true` (`:82`).
- **Problem:** If the deferral is canceled, `pending` stays `true` for the life of the closure. The Browser, Insights and Timeline rebuild their coalescer on every `Enable`, so they recover. The settings panel's storage-readout coalescer does not: it is built once (`settings/Panel.lua:152` `if not P.__ev then`, `:168-169` `ev:RegisterMessage(NS.MSG.RECORD_ADDED,` / `NS.Coalesce(onChange, NS.Constants.RECORD_ADDED_COALESCE))`) and survives stand-down as setup.
- **Impact:** After that, the General page's record count, span and size readout stops updating on new records for the rest of the session. A `HistoryChanged` event (delete, prune or blacklist edit) still refreshes it.
- **Reachability:** A player who has opened the General settings page in the session and whose addon stands down within 0.2 s (`RECORD_ADDED_COALESCE = 0.2`) of a recorded row. That happens through `/lh disable`, the Master-controls switch, a profile switch to a disabled profile, or the `/lh perf` suspend arm starting during a loot burst.
- **Measurement:** A scratch probe (`scratch/coalesce_probe.lua`) loaded the real `core/LifecycleSetup.lua` and `core/Util.lua` with a mock `C_Timer`, then ran trigger → `CancelDeferrals` → trigger. It printed `runs after stand-down + new trigger: 0`.

### F-005 — The `ledgerEvent` perf bucket includes the full combat-exit flush, though it is declared as dirty bits only `[perf]`

- **Where:** `modules/Reconciler.lua:119` reads `-- Shape A bracket (performance-§2): every capture event, in combat included, is a dirty bit or a`, and `:120` continues "the flush it schedules is not inside this bucket". But `onEvent`'s `PLAYER_REGEN_ENABLED` branch (`:113-115`, `elseif self.deferred then self.deferred = nil; self:Flush() end`) runs `LoginScan` or `Flush` synchronously inside the bracket that `:124` closes (`if t0 then Perf.Note("ledgerEvent", …)`). `core/PerfSetup.lua:68` declares the bucket as `-- Reconciler:OnEvent (BAG_UPDATE storms, money, currency: dirty bits)`.
- **Problem:** A full scan, plan and write at the regen edge is attributed to a bucket documented as O(1) dirty-bit work.
- **Impact:** A `/lh perf` capture that spans a combat exit with deferred bag work would show a `ledgerEvent` spike that reads as in-combat event cost. That is the evidence `performance-§12`'s retired exemption now relies on. The 2026-10-07 capture saw only one call (`docs/perf-analysis/20261007-104651/ANALYSIS.md:50`), so no recorded figure is wrong yet.
- **Reachability:** Only a player or maintainer reading a `/lh perf` capture that crossed a combat exit with deferred ledger work. No gameplay effect.

### F-006 — Auction exits: the TTL clock restarts on every new exit, and one sale mail books every pending exit of that item as sold `[correctness]`

- **Where:** `modules/Escrow.lua:215` (`x.n, x.ts = x.n + n, now`) and `:151-152` (`if left > 0 and (byMail or (now - x.ts) >= Escrow.EXIT_TTL) then` / `plan.sold[id] = left`).
- **Problem:** (a) Exits of one item share a single `ts` that each later exit overwrites, so the oldest exit's 30-day TTL is pushed back by every newer one. (b) A sale mail naming the item books **all** remaining exits as `AH_SOLD`. If some of those auctions expired instead, their return mail later lands as a plain `IN MAIL` gain.
- **Impact:** The net item count stays right, but the reasons are wrong for a player selling several of one item at once: phantom `AH_SOLD` OUT rows paired with `MAIL` IN rows.
- **Reachability:** A ledger-on player who has several auctions of the same item leave the owned list before the first sale mail is taken, and some of them expire.

### F-007 — The Reconciler's coalescing map is never pruned during a session `[perf]`

- **Where:** `modules/Reconciler.lua:458` (`self.recent[ck] = { row = row, index = index, ts = now }`). The map is only reset at `:678` (`self.claims, self.recent, self.reasonMemo = {}, {}, {}`, `DisableCapture`).
- **Problem:** An entry is dead 60 s after it is written (`COALESCE_WINDOW`), but it stays in the map until stand-down or reload, and it keeps its row alive even after a retention prune removes that row from history.
- **Impact:** Memory grows with the number of distinct (holder, thing, direction, reason, route) keys written in a session. That is bounded and small: a few hundred to a few thousand small tables.
- **Reachability:** Every ledger-on session. It is unmeasurable at normal session lengths.

### F-008 — Two parsers for one `<holder>/<container>` location string `[design]`

- **Where:** `core/Ledger.lua:403` (`return loc:match("^(.*)/[^/]*$")`, the last `/`) and `modules/TimelineModel.lua:156` (`local function sideOf(path) return path and path:match("^(.-)/") end`, the first `/`). `modules/Reconciler.lua:462` reuses the name `sideOf` for something else (`local function sideOf(key, holder, explicit)`).
- **Problem:** The two parsers agree only because no holder key contains `/`, and the second one duplicates a published primitive.
- **Impact:** No impact today. It is a maintainability hazard if the holder-key format ever changes.
- **Reachability:** A comment-level hazard with no runtime effect today.

### F-009 — `docs/testing.md` states a stale suite count `[docs]`

- **Where:** `docs/testing.md:65-66` reads "Forty-four suites … thirty-nine files of this repo's own under `tests/`, and five the kit ships".
- **Problem:** The fresh inventory's Totals table lists **60** suites: 55 of this repo's own (`git ls-files 'tests/test_*.lua' | wc -l` → 55) plus the 5 the kit ships (`git ls-files 'tests/_kit/test_*.lua'`).
- **Reachability:** Doc text only, with no runtime effect.

---

No `[upstream]` findings. Vendor sync and all four cross-addon classes are clean.
