# 03 — Evidence

Every command below was run from the repo root (`/mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory`) at tree
`b9c1271`. Each census states what it swept and what it left out. Every `file:line` cited in this bundle was re-read
before it was written, and the text quoted beside it is what is at that line (CRLF stripped for display).

---

## Standard resolution

```sh
RAW=https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master
curl -fsSL $RAW/AUDIT.md; curl -fsSL $RAW/standards/STANDARDS.md; curl -fsSL $RAW/standards/ADDONS.md
# then every file the STANDARDS.md Sections list links: 27 files under standards/standards/
git ls-remote https://github.com/tusharsaxena/WowAddonStandards refs/heads/master
#  f47238929230c0059409e1b0a8d69cea99123bd9	refs/heads/master
```

`standards/STANDARDS.md:1`: `# Ka0s WoW Addon Standard (v2.76.1, 2026-10-07)`. `diff -q` of the fetched `AUDIT.md` and
`diff -rq` of the fetched `standards/` against `../WowAddonStandards`: no content differences (local-only:
`EXECUTIVE_SUMMARY.md`, `INDUSTRY_RESEARCH.md`, `NEW_ADDON_CONTEXT.md`, `README.md`, `_raw/`).

Repo kind: `dev-copilot-profile` → `profile=wow`, `kind=addon`, `reason=toc:## Interface`.

---

## Green gate (bounded)

```sh
~/.claude/dev-copilot/bin/ka0s-bounded luacheck .
#  Total: 0 warnings / 0 errors in 116 files            exit 0
~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
#  1476 passed, 0 failed, 1 skipped, 1477 total          exit 0
#  SKIP  diagnostics contract: an addon that opts out lands the report and leaves logging off — this addon keeps
#        the default (Kit.diagnostics.enablesLogging is not false) …
```

Scope of lint: `.luacheckrc:12` `exclude_files = { "libs/", "docs/audits/", "docs/reviews/", "_dev/", "tests/_kit/" }`;
no top-level `ignore`. `tests/` is linted; the harness global sits in `files["tests/"]` (`.luacheckrc:77`).
116 linted files equals the authored-Lua census below.

```sh
~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua --list > <scratch>/tc.md   # exit 0
diff <(tr -d '\r' < docs/test-cases.md) <(tr -d '\r' < <scratch>/tc.md)            # empty
```
`docs/test-cases.md` *Totals* `| **Total** | **1477** |`; the skip appears with its reason at `docs/test-cases.md:1627`.
`README.md:7`: `![Tests](https://img.shields.io/badge/Tests-1476%2F1476_passing-green)` (LH-88).

---

## Authored-Lua census (`layout-§1`)

```sh
git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)' | wc -l              # 116
git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)' | xargs wc -l         # 44858 total
… | awk '$2!="total" && $1>1500' | wc -l                                     # 0
```
Scope: the tracked set, `tests/` **in**, `libs/` and `tests/_kit/` out; no generated-data exemption is declared, so none
is subtracted. Band (1000–1500), 10 files: `modules/BrowserTable.lua` 1476, `modules/Browser.lua` 1416,
`tests/test_browser.lua` 1414, `tests/test_browsertable.lua` 1247, `core/Database.lua` 1218, `tests/test_schema.lua`
1202, `settings/Schema.lua` 1133, `settings/Panel.lua` 1133, `tests/test_slash.lua` 1129, `tests/test_database.lua` 1109.

Census heading: `docs/ARCHITECTURE.md:425` `### Files over the 1500-line cap`, under `## Documented deviations`
(`:372`). `docs/ARCHITECTURE.md:431`: "Nothing is over the cap today. The largest authored file is
`modules/BrowserTable.lua` at 1296 lines" (LH-73 item 3). Gate: `tests/run.lua:119`
`{ name = "test_layout_cap", dir = "tests/_kit/" },`.

---

## TOC load-bearing positions (`toc-file-§5`) — LH-78…LH-81, LH-58, LH-82

Positions established by reading every module and settings file for file-scope reads of another file's table:

```sh
for f in modules/*.lua settings/*.lua; do tr -d '\r' < $f | grep -nE '^[^ \t-].*NS\.(Analytics|…|Reconciler|…|TimelineModel|Schema|…)\b'; done
```
(scope: `modules/` and `settings/` only; `core/` and `defaults/` positions were already read and are all annotated.)

| TOC line | Text at the TOC line | Why it is load-bearing (re-read) |
|---|---|---|
| `LootHistory.toc:102` | `modules\Escrow.lua` (no comment above; `:101` is `modules\Reconciler.lua`) | `modules/Escrow.lua:18` `local R = NS.Reconciler`; `:26` `R.SCAN_STEPS[#R.SCAN_STEPS + 1] = function(self, snap, me)`; `:160` `R.PLAN_STEPS[#R.PLAN_STEPS + 1] = planMail`; `:161` `R.PLAN_STEPS[#R.PLAN_STEPS + 1] = planPost` |
| `LootHistory.toc:112` | `modules\AnalyticsCharts.lua` | `modules/AnalyticsCharts.lua:1-2` `local _, NS = ...` / `local Analytics = NS.Analytics` (no `or {}`); `:226` `Analytics._charts = { sectionHeader = sectionHeader, sectionDivider = sectionDivider, listPanel = listPanel }` |
| `LootHistory.toc:116` | `modules\Timeline.lua` (`:115` is `modules\TimelineModel.lua`) | `modules/Timeline.lua:19` `local TM = NS.TimelineModel`; `:26` `local TOTAL = TM.TOTAL` |
| `LootHistory.toc:131` | `settings\Panel.lua` | `settings/Panel.lua:961` `AFTER_GROUP[NS.Schema.MASTER_GROUP] = NS.Schema.MasterAfterGroup` |

Compare the idempotent publish every sibling uses: `modules/AnalyticsFormat.lua:2`, `modules/Analytics.lua:2`,
`modules/AnalyticsLedger.lua:2` each `NS.Analytics = NS.Analytics or {}`. `LootHistory.toc:94`:
`# Modules (Attribution before Collector)` — `modules/Collector.lua` has no file-scope read of `NS.Attribution` (same
grep, no hit). Annotated positions: `grep -c 'LOAD-BEARING' LootHistory.toc` → **9** (`:40`, `:44`, `:56`, `:61`, `:65`,
`:72`, `:87`, `:121`, `:127`). Prior rows closed: `LootHistory.toc:56` `# LOAD-BEARING POSITION: lib:New{ prefix =
NS.PREFIX } runs at file load …`, `:72` `# LOAD-BEARING POSITION: the file-load lib:New descriptor reads
NS.Constants.FONT_MONO;`, `:127` `# LOAD-BEARING POSITION: the dispatcher is built at file load with commands =
NS.COMMANDS, assigned`.

---

## Vendored payloads (`library-stack-§7`, anti-patterns #45/#48)

```sh
grep -n 'Bundles \[LibKa0s\]' CLAUDE.md   # CLAUDE.md:56:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.70.0 (MIT) — …
grep -n 'Bundles \[LibKa0s\]' README.md   # (none)
grep -nE '^## (Libraries|Bundled libraries|Libraries and credits|Credits and libraries|Credits and bundled libraries)' README.md   # (none)
grep -n 'WoW_Addon_Standard' README.md    # README.md:6:![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)
cd ../LibKa0s && git rev-parse 'v1.70.0^{commit}'   # 162a7fda6c46b7fdc6143eac1d219da4ec6ebda1
git archive v1.70.0 LibKa0s testkit | tar -x -C <scratch>/lk170
diff -r <scratch>/lk170/LibKa0s ../LootHistory/libs/LibKa0s   # empty
diff -r <scratch>/lk170/testkit ../LootHistory/tests/_kit     # empty
```
Diffed against the tag the provenance line names, not the sibling's `HEAD`. `tests/_kit/framework.lua:20`
`Kit.VERSION = 37`.

---

## Re-vendor store (`audit-review-history`) — LH-62 closed

The `AUDIT.md` step-4 script, run under `bash`, `horizon=2026-08-25`:
```
vendored: 52
recorded: 52
UNRECORDED:            (nothing; grep exit 1)
```
Scope: commits touching `libs/LibKa0s` or `tests/_kit` since `2026-08-25 00:00`, tag read from each commit's
`CLAUDE.md`; recorded side read from every `docs/revendor/*/` (23 bundles; each has `01_DELTA.md` and `05_SUMMARY.md`).

---

## Line endings (`line-endings`)

```sh
test -f .gitattributes                                    # present
grep -n '^\* text=auto eol=\(crlf\|lf\)$' .gitattributes  # 26:* text=auto eol=crlf
grep -nE '^\*\.(sh|py) text eol=lf$' .gitattributes       # 36:*.sh text eol=lf / 37:*.py text eol=lf
grep -c ' binary$' .gitattributes                         # 20
diff <(head -n 84 .gitattributes | tr -d '\r') <canonical client-bound body from line-endings-§5>   # empty
tail -n +85 .gitattributes | wc -l                        # 0
# (e) the AUDIT.md one-liner, run as written under bash, whole tracked set (no exclusions):
#   0            (of 675 tracked files)
```
Gate `tests/run.lua:115` `{ name = "test_eol", dir = "tests/_kit/" },`.

---

## Packaging

```sh
# (a), (b), (c) of AUDIT.md, run under bash:
#   (a) nothing printed       (b) UNACCOUNTED — .git       (c) nothing printed
git ls-files .pytest_cache .superpowers | wc -l           # 0 — both untracked, both ignored with a comment
```

---

## Bus messages (`architecture-§4`)

```sh
git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)' | xargs grep -nE '(Send|Register)Message\("Ka0s_'   # (none)
git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)' | xargs grep -noE '"Ka0s_[A-Za-z]+_[A-Za-z0-9_]+"'
#  HarnessProbe ×1, HistoryChanged ×6, HoldingsChanged ×3, RecordAdded ×4, SettingsChanged ×4 — all PascalCase
```
Scope: authored tracked Lua, `tests/` included. LH-66 closed.

---

## Disabled state (`slash-commands-§7`) — compliant

```sh
git ls-files '*.lua' ':!libs' ':!tests' | xargs grep -nE 'Register(Unit)?Event|RegisterMessage|RegisterBucketEvent|SafeRegister'
git ls-files '*.lua' ':!libs' ':!tests' | xargs grep -nE 'Unregister(All)?Events?|UnregisterMessage|UnregisterAllMessages|CancelTimer|:Cancel\(|NewTicker|NewTimer|C_Timer.After|SetScript\("OnUpdate"'
```
Scope: the shipped tree (`libs/` and `tests/` excluded — what the client loads). Every registration site maps to an
unregistration reached from `NS.StandDown` (`core/LifecycleSetup.lua:116` `function NS.StandDown()`):
`NS.addon:UnregisterAllEvents()` (`:120`); the module loop (`:121-122`, Collector, Reconciler, Attribution, Browser,
Analytics, HoldingsTab, Timeline, Rollup); `Attribution:DisableOut` (`:125`); `NS.DropLedgerResetOffer` (`:126`);
`NS.CancelDeferrals` (`:127`). `modules/Reconciler.lua:686-689` `R:Disable` drops both private targets. The
`settings/Panel.lua:158`, `:168`, `:504` refresh subscriptions are the open-evolutions case and are not filed.
Uncancelable `C_Timer.After` sites: `core/ItemSetup.lua:70` (only caller `core/Database.lua:474` passes no callback),
`settings/OptionsSetup.lua:228` (the panel's slider throttle, player-driven). Latch: `core/LifecycleSetup.lua:165-175`
`Lifecycle:New{ … }`; perf hold through `core/PerfSetup.lua` `lifecycle = NS.Lifecycle`. Suite: `tests/run.lua:87`
`"test_disabled",`; `tests/test_disabled.lua:216` `-- red under: drop the UnregisterAllEvents / UnregisterEvent calls
from NS.StandDown and the`.

---

## Slash surface, diagnostics, library debug lines

```sh
grep -n '"diagnostics"' settings/*.lua core/*.lua
#  settings/Schema.lua:1095:      if arg == "diagnostics" then return NS.DebugLog:RunDiagnostics() end
#  settings/Schema.lua:1109:  { "diagnostics", NS.L["Write the diagnostics report to the debug console"],
grep -rniE '"(diag|dump|dx)"' settings core modules         # (none)
grep -n 'SetEnabled' settings/*.lua core/*.lua modules/*.lua # only the debug on/off words (settings/Schema.lua:1101-1102) and the DebugLog stub
grep -n 'diagnosticsEnablesLogging' core/*.lua               # (none) — default
```
Descriptor sinks: `settings/Slash.lua:488` `debug = function(tag, message) if NS.Debug then NS.Debug(tag, message) end end,`;
`settings/OptionsSetup.lua:181` `debug = function(tag, fmt, ...) …`; `core/LifecycleSetup.lua:174`; `core/LauncherSetup.lua:167`
and `debugAtEnable` at `:173`. Options `addonName`: `settings/OptionsSetup.lua:178` `addonName     = addonName,`.
`/lh debug events`: `settings/Schema.lua:1096-1098`.

---

## Launcher

`core/LauncherSetup.lua` (de-commented): `label = NS.BRAND`, `isEnabled`/`setEnabled`, `isLocked`/`toggleLock`,
`isTestMode`/`toggleTestMode`, `isWindowShown`/`toggleWindow`, `onTooltipShow` adding `"N records"` only. `ADDONS.md:24`:
`| Ka0s Loot History | … | Enabled · Locked · Test mode · Show window (the History browser) |`. No host `NewDataObject`,
`OnTooltipShow` assignment, `MenuUtil` or `EasyMenu` outside `libs/`.

---

## Close buttons and the settings window

```sh
grep -rn 'MakeCloseButton(' --include='*.lua' . | /usr/bin/grep -v '/libs/' | /usr/bin/grep -v '/tests/'
#  ./core/CoreSetup.lua:277:  return lib.MakeCloseButton(parent, onClick, addonName)      (the one wrapper, :276)
#  ./modules/Browser.lua:75:function B:MakeCloseButton(parent, onClick)                  (forwards to NS.MakeCloseButton at :77)
#  ./modules/Browser.lua:1087:  local close = B:MakeCloseButton(titleBar, function() B:Hide() end)
#  ./modules/Export.lua:514:    NS.Browser:MakeCloseButton(tbar, function() frame:Hide() end)
git ls-files '*.lua' ':!libs' ':!tests' | xargs grep -nE 'SettingsPanel|HideUIPanel|ToggleGameMenu|OpenToCategory'
#  settings/OptionsSetup.lua:175:  mainPanelName = "LootHistorySettingsPanel",   (a frame name, not a call)
```

---

## Citations (`documentation-§6`)

```sh
git ls-files | grep -vE '^(libs/|tests/_kit/|docs/(audits|reviews|automated-tests|revendor|superpowers|investigations|perf-analysis/[^/]+)/)' \
  | xargs grep -En '§[0-9]+\.[0-9]'                       # 79 hits — all cite the project's own design spec (e.g. "spec §8.1"), none the standard
… | xargs grep -onE '\b[a-z][a-z-]*-§[0-9:]+'             # 800 citations, 79 distinct; each range-checked with
#   grep -c '^### [0-9]' standards/standards/<file>  → 0 malformed, 0 out of range, 0 naming a file that does not exist
```
Scope: the whole tracked set minus vendored payloads and frozen/generated stores (note the untracked `.superpowers/`
is **not** in it — a `grep -r` sweep over the working tree returns 214 hits, almost all in that untracked scratch
directory, which is why the tracked scope is the one recorded). LH-67's sites are gone:
`grep -n 'packaging.md\|disabled-§' .pkgmeta tests/test_disabled.lua` → none.

Doc `file:line` resolvability: a script walking every `path:N` in the live doc set (`docs/*.md` minus frozen stores,
`DEPENDENCIES.md`, `CLAUDE.md`, `README.md`, the TOC, `.pkgmeta`, `.luacheckrc`; 411 references) checked that each path
exists and has at least N lines → **0 missing, 0 past end of file**. Content was spot-checked, not proven, for all 411;
the drifts that were found are LH-73.

---

## LH-60 — hub shape

```sh
wc -l docs/ARCHITECTURE.md        # 478
tr -d '\r' < docs/ARCHITECTURE.md | awk '/^## /{if(h)print n"\t"h; h=$0; n=0; next}{n++} END{print n"\t"h}'
#  28 Overview · 77 Module map · 14 Data model · 22 Settings schema · 27 Message bus · 33 Slash commands
#  11 The disabled state · 62 Event subscriptions · 8 Menus · 14 Taint notes · 8 Standards compliance
#  47 Documentation map · 64 Documented deviations · 41 Known limitations
```
`## Module map` at `docs/ARCHITECTURE.md:38`, next `##` at `:116`; it links `module-map.md` twice plus eight other
targets (`browser.md#…`, `compat-layer.md#…`, `data-flow.md#…` ×2, `disabled-state.md`, `performance.md`,
`profiles.md` ×2, issue #26).

## LH-68 — Perf parity

`core/PerfSetup.lua:27-34` `local function stub() … OnCommand = function() return { "perf capture unavailable." } end, … end`;
`:36-39` `if not (lib and NS.Lifecycle) then NS.Perf = stub() return end`. `tests/test_surface_parity.lua` cases:
`:66` Core, `:89` Widgets, `:113` Slash, `:123` DebugLog, `:151` Options, `:176` Bus, `:191` Compat, `:206`/`:213`
Schema, `:223` Item, `:234` Pool, `:247` Lifecycle, `:279` Env, `:284` Media — no Perf. Members called:
`git ls-files '*.lua' ':!libs' ':!tests' | xargs grep -ohE '\b(NS\.)?Perf[.:][A-Za-z_]+' | sort | uniq -c` →
`NS.Perf.OnCommand` 1, `Perf.Note` 5, `Perf.on` 5 — all answered by the stub.

## LH-71 / LH-83 — README

`README.md:63`: "Everything else is on the addon's page under Settings → AddOns. `/lh` (or `/loothistory`) on its own
opens it, and `/lh help` lists every command."
`README.md:134` (the 1.4.0 row) ends: "…Lock frame also stops resizing<br>Released on lint, tests and complexity only.
Loot History holds a ratified no-combat-path exemption (`performance-§12`), so it ships no `tests/perf.lua` and the
perf suite was skipped, not measured. |". `tests/perf.lua` exists today.
`grep -nE '^[[:space:]]*[0-9]+[.)][[:space:]]' README.md` → none. No `media/logos` or `<img>` in the README.

## LH-73 — drifted figures

| Citation | Text there | Measured |
|---|---|---|
| `docs/ARCHITECTURE.md:31` | "…the Timeline's line chart (vendored at v1.69.0, see `CLAUDE.md`)" | `CLAUDE.md:56` v1.70.0 |
| `docs/ARCHITECTURE.md:347` | "`compat-layer.md` \| Present \| 47 shims (`grep -cE '^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\.' core/Compat.lua`)" | that grep → **57** |
| `docs/ARCHITECTURE.md:431` | "The largest authored file is `modules/BrowserTable.lua` at 1296 lines" | `wc -l` → **1476** |
| `docs/ARCHITECTURE.md:41-42` | "**Nine** LibKa0s seams sit inside `core/` … **Seven** TOC positions are load-bearing" | 12 majors wired from `core/`; 9 `LOAD-BEARING` comments; 4 more positions load-bearing |
| `docs/module-map.md:188` | "**Seven positions are load-bearing**, and each carries a `LOAD-BEARING POSITION` comment" | as above |
| `docs/module-map.md:195` | "one of the four files in `core/` whose TOC position is load-bearing" | `core/` carries seven annotated positions (`:40`, `:44`, `:56`, `:61`, `:65`, `:72` plus Lifecycle-relative) |
| `LootHistory.toc:128` | "above Schema, LibKa0s-Slash :New raises (libs\LibKa0s\Slash.lua:487)" | `libs/LibKa0s/Slash.lua:357` `error(MAJOR .. ":New requires descriptor.commands — the host's own verb table", 3)`; `:487` is `--- a set echo. Never on reset or resetall …` |
| `settings/Panel.lua:7-8` | "settings/OptionsSetup.lua, which loads immediately before this file" | `LootHistory.toc:125-131`: OptionsSetup, Schema, Slash, Panel |

## LH-84 — raw lizard in DEPENDENCIES.md

`DEPENDENCIES.md:136`: `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .              # complexity report (release only)`;
`:140`: "…The `lizard`" (run is a release step). `docs/testing.md:257` names the sighted runner and is compliant.

## LH-85 — documentation map scope

`docs/ARCHITECTURE.md:326-327`: "Frozen and generated directories are named once each and never enumerated per run:
`docs/audits/`, `docs/reviews/`, `docs/automated-tests/`, `docs/revendor/`, `docs/superpowers/`."
`ls docs/perf-analysis/20261007-104651` → `ANALYSIS.md dump.json report.md`. Live `.md` census
(`git ls-files 'docs/*.md'` minus frozen stores) → 23 files; each appears in exactly one table (`:329-370`).

## LH-86 — holdings writers

`docs/schema.md:388`: "**Writers.** `holdings`: `Reconciler:Flush` only. …"
`modules/Reconciler.lua:699` `local had = NS.Holdings:ForgetHolder(holder)` (in `R.ForgetHolder`, `:696`), reached from
`settings/Slash.lua:45` `if data and data.holder and NS.Reconciler then NS.Reconciler:ForgetHolder(data.holder) end`;
`modules/Reconciler.lua:612-613` `NS.Holdings:MarkGenesis(NS.Util.PlayerKey(), now)` / `if NS.Holdings:Get(WARBAND) then
NS.Holdings:MarkGenesis(WARBAND, now) end` (in `R.MarkLoginGenesis`, called from `LoginScan`).
`modules/Holdings.lua:46` names the module's own write set: "write (Get with create, Apply*, Credit*, ForgetHolder, the
rollup seed) stays on Store()".

## LH-87 — complexity, measured

```sh
~/.claude/dev-copilot/bin/ka0s-bounded bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle
#  complexity  pass  — 26 warnings (fun rate 0.01), 31695 NLOC / 4431 funcs, avg NLOC 6.9, avg CCN 2.5 (max 24) …
#  record:  newest bundle 20260927-030334 measured 8e60c1f, 171 commit(s) behind HEAD
```
The runner prints no per-function rows under `--no-bundle`, so its own two steps were repeated into a scratch directory
to list them — the kit's sanitizer (`lua5.1 tests/_kit/lizard_sighted.lua shadow <scratch>/src < files`) and the
runner's verbatim command (`lizard -l lua -L 1500 -x "./libs/*" -x "./tests/_kit/*" .`, inside the shadow) — and the
footer matched the runner's exactly (31695 NLOC, 4431 functions, 26 warnings). `lizard_sighted.lua parity` printed
nothing (0 blind files). The 26, CCN in brackets:
`core/Database.lua` convertHolderMoves (24), compileFilter (18), accumulateLedger (20), Database.Stats (23);
`core/Ledger.lua` Ledger.PairHolders (17), scopeReason (16), Ledger.RecomputeFlows (19);
`core/Compat.lua` Compat.ListedCurrencyID (16), Compat.ListCurrencies (16);
`core/LifecycleSetup.lua` NS.StandDown (18), NS.StandUp (24);
`modules/Collector.lua` currencyLine (16); `modules/TestData.lua` walk (17), TD.DefaultTimelineThing (16);
`modules/BrowserTable.lua` holderMoves (16), BrowserTable.SetTestMode (16), BrowserTable.GroupRecords (16);
`modules/AnalyticsLedger.lua` AL.BackToBackRows (18); `modules/Reconciler.lua` onEvent (21), R.WriteRows (16);
`modules/Browser.lua` historyCharItems (16), holderCharItems (16); `modules/Holdings.lua` Holdings.Search (20);
`modules/Escrow.lua` planMailMoney (17), planExits (18), commitExits (17).
`docs/automated-tests/20260927-030334/manifest.json`: no `blindFiles` key (`grep -o '"blindFiles"'` → none).
`docs/automated-tests/RESULTS.md` newest row: `| 20260927-030334 | 8e60c1f | clean | 1.3.0 → 1.4.0 | 0/0 | 70 |
961/0/961 | skip | 18447 | 2519 | 6.3 | 2.1 | 15 | 0 | green |`; dispositions "Re-check at 1400 lines" (Browser.lua) and
"Re-check at 1300 lines" (BrowserTable.lua). Release runs carrying *Accepted* for Browser.lua: `59bea38` (1.3.0) and
`90cbc21` (1.4.0) — two, below anti-pattern #53's three. Hand edit: `git show e09cf58 -- docs/automated-tests/RESULTS.md`
changes `/wow-addon:bump-version` to `/dev-copilot:bump-version` in the preamble.
Refactors since the last audit (`ffde712`, `f4e059c`, `9c0fe33`, `e75b40d`, `f31727b`) extract named helpers
(`layoutCharacters`, `emitCurrency`, `partitionTags`, `resolveLootSource`, `browserWindow`, …) after characterization
tests (`b7b74e2`, `dbe3a89`, `cf8238e`) — no #52/#43/#54 shape found.

## LH-77, LH-89

`settings/Schema.lua:1098` `return print("rejected events: " .. (#names > 0 and table.concat(names, ", ") or "none"))`;
`settings/Slash.lua:239` `if #rows == 0 then print("no holdings match '" .. query .. "'."); return end`; `:243`
`print(("%s: %s"):format(r.name, total))`; `modules/Browser.lua:919` `print(("%s view saved as default."):format(lastTab))`;
`:933` `print(("%s view reset to stock defaults."):format(lastTab))`.
`settings/Panel.lua:22` `local LOGO_PATH     = "Interface\\AddOns\\LootHistory\\media\\logos\\loothistory.logo.tga"`;
`core/LauncherSetup.lua:50-51` `NS.LAUNCHER_ICON =` / `"Interface\\AddOns\\" .. addonName .. "\\media\\logos\\loothistory.logo.128.tga"`.

---

## Register

`docs/ARCHITECTURE.md:386-389` (four rows). Trigger checks: `grep -rlnE 'MultiCheck|multiCheck|SetPicker|MakeSet'
libs/LibKa0s` → none (options-ui-§1 row); no ordered-list row kind in `libs/LibKa0s/Schema*.lua` / `Options*.lua`
(architecture-§5 row); `ls locales` → `enUS.lua` only (localization-§1 row). Evidence ids: `docs/schema.md:281`
*Standards note*; issue #20 closed `state:will-not-do`; `LH-48` in `docs/audits/2026-09-07/02_DEVIATIONS.md`; issue #2
closed `state:done`; `LH-74` in `docs/audits/2026-09-23/02_DEVIATIONS.md`. Retirement notes cite #22, #29, #33, #19, #25,
#26, #21, `LH-76`, `LH-54`, `LH-47` — all resolve.

```sh
gh issue list --state all --limit 200 --json number,title,state,labels
#  34 issues; open: #34 (state:untriaged, no severity), #17, #16, #11, #9 (state:triaged + severity)
#  state:will-not-do: #18, #19, #20, #21, #22, #29
```
No `docs/pending/`. No `[status]` title prefix.

## Shared media

`media/logos/`: `loothistory.logo.128.tga`, `.256.jpg`, `.jpg`, `.png`, `.tga`; `media/screenshots/`: four `.png`.
`od -A d -t u1 -N 18 media/logos/loothistory.logo.128.tga` → byte 2 = `2`, bytes 12-15 = `128 0 128 0`, byte 16 = `32`.
`core/MediaSetup.lua` passes `addonName` to `Media.Icon`/`Media.Font`/`Media.RegisterLSM`. Blizzard texture paths in
shipped code are fallbacks behind catalog marks (`NS.IconMarkup("sort-up", "Interface\\Buttons\\Arrow-Up-Up", …)`,
`modules/BrowserTable.lua:330`) or the flat `WHITE8X8`.
