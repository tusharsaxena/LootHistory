# 03 — Evidence

Every command below was run from the repo root (`/mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory`) at tree
`54b7cc7` on 2026-09-23, and its real output is quoted. Every `file:line` was re-read after it was collected, and the
text at that line is quoted beside it. **Scope is stated per census.** The default denominator is `layout-§1`'s:
`git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)'` — the tracked, authored Lua, `tests/` included, the two
vendored trees excluded. Frozen bundles (`docs/audits/`, `docs/reviews/`, `docs/revendor/`, `docs/automated-tests/<run>/`,
`docs/superpowers/`) are excluded from every prose/citation sweep and said so where it matters.

Bounded runner: `~/.claude/wow-addon/bin/ka0s-bounded` (not on `PATH`; invoked by absolute path). No run exited 124 or 137.

---

## 0. Standard resolution

```
curl -fsSL $RAW/AUDIT.md                      -> 990 lines
curl -fsSL $RAW/standards/STANDARDS.md        -> "# Ka0s WoW Addon Standard (v2.64.0, 2026-09-23)"
curl -fsSL $RAW/standards/standards/<27 files linked under ## Sections>   -> all 27 fetched, 6106 lines incl. ADDONS.md
git ls-remote https://github.com/tusharsaxena/WowAddonStandards refs/heads/master
  e68795f5cd6416fd4eaa9734c99b336ad0b70132	refs/heads/master
```

Section heading counts used for range checks (`grep -c '^### [0-9]'`): architecture 7, automated-tests 7, debug-logging 13,
documentation 9, events-frames-taint 8, launcher 5, layout 4, library-stack 9, line-endings 7, localization 5,
options-ui 18, performance 12, savedvariables 5, slash-commands 8, testing 15, toc-file 5; the eleven un-numbered files 0.

## 1. Lint, suite, inventory

```
$ ~/.claude/wow-addon/bin/ka0s-bounded luacheck --version   -> Luacheck: 1.2.0 / Lua: PUC-Rio Lua 5.1
$ ~/.claude/wow-addon/bin/ka0s-bounded luacheck .
Total: 0 warnings / 0 errors in 65 files          EXIT=0
$ ~/.claude/wow-addon/bin/ka0s-bounded lua tests/run.lua
858 passed, 0 failed, 0 skipped, 858 total        EXIT=0
$ ~/.claude/wow-addon/bin/ka0s-bounded lua tests/run.lua --list > <scratch>/list.txt
$ diff <(tr -d '\r' < docs/test-cases.md) <(tr -d '\r' < <scratch>/list.txt)   -> (empty)
```

- `docs/test-cases.md` last row: `| **Total** | **858** |`; `README.md:7`: `![Tests](https://img.shields.io/badge/Tests-858%2F858_passing-green)`.
- `.luacheckrc` scope: `exclude_files = { "libs/", "docs/audits/", "docs/reviews/", "_dev/", "tests/_kit/" }`;
  harness global in `files["tests/"] = { globals = { "_G.LH_TEST", … } }`; per-file ignores are `212/self` only.
  65 files linted = the 65 authored `.lua` in the default denominator.

## 2. Vendored LibKa0s — provenance and drift

```
$ grep -n 'Bundles \[LibKa0s\]' CLAUDE.md
51:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.55.0 (MIT) — the Ka0s-owned shared
$ grep -n 'Bundles \[LibKa0s\]' README.md                          -> (no hit)
$ grep -nE '^## (Libraries|Bundled libraries|Libraries and credits|Credits and libraries|Credits and bundled libraries)' README.md   -> (no hit)
$ grep -n 'WoW_Addon_Standard' README.md
6:![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)        (bare, not a link)
$ grep -nE 'media/logos|<img' README.md                             -> (no hit)

$ git -C ../LibKa0s tag -l 'v1.5*' --sort=-v:refname | head -1      -> v1.55.0   (commit 6f9c5e0)
$ git -C ../LibKa0s archive v1.55.0 LibKa0s testkit | tar -x -C <scratch>/lib155
$ diff -r <scratch>/lib155/LibKa0s libs/LibKa0s ; echo $?          -> 0  (empty)
$ diff -r <scratch>/lib155/testkit tests/_kit ; echo $?            -> 0  (empty)
```

Both payloads are byte-identical to the tag the provenance line names — whole folder, every module. `libs/LibKa0s/Slash.lua:21`:
`local MAJOR, MINOR = "LibKa0s-Slash-1.0", 14` (≥ the v1.42.0 floor); `libs/LibKa0s/Lifecycle.lua:53`:
`local MAJOR, MINOR = "LibKa0s-Lifecycle-1.0", 1`. TOC: `libs\LibKa0s\LibKa0s.xml` once, no module `.lua` listed.

## 3. Re-vendor ledger (LH-62)

The playbook's commands, run as written under `bash -c` (the login shell is zsh):

```
horizon=2026-08-25
vendored (tags read off CLAUDE.md at each commit touching libs/LibKa0s since the horizon):
  v1.18.0 v1.18.1 v1.19.0 v1.23.0 v1.24.0 v1.25.0 v1.26.0 v1.27.0 v1.28.0 v1.29.0 v1.31.0 v1.32.0 v1.33.0
  v1.34.0 v1.35.0 v1.36.0 v1.36.1 v1.36.2 v1.37.0 v1.38.0 v1.39.0 v1.42.0 v1.44.0 v1.45.0 v1.46.1 v1.47.0
  v1.50.0 v1.51.0 v1.52.0 v1.53.0 v1.55.0                                          (31)
recorded (folder tag, else 01_DELTA.md line 1):
  v1.15.0 v1.25.0 v1.30.0 v1.31.0 v1.32.0 v1.33.0 v1.34.0 v1.55.0                  (8)
UNRECORDED: v1.18.0 v1.18.1 v1.19.0 v1.23.0 v1.24.0 v1.26.0 v1.27.0 v1.28.0 v1.29.0 v1.35.0 v1.36.0 v1.36.1
            v1.36.2 v1.37.0 v1.38.0 v1.39.0 v1.42.0 v1.44.0 v1.45.0 v1.46.1 v1.47.0 v1.50.0 v1.51.0 v1.52.0 v1.53.0
count=25
```

Bare-dated bundles were opened, not name-matched: `docs/revendor/2026-08-25/01_DELTA.md:1` `# 01 — Delta: LootHistory vs LibKa0s v1.15.0`;
`2026-09-03/01_DELTA.md:1` `… LibKa0s v1.24.0 → v1.25.0`; `2026-09-12/01_DELTA.md:1` `… LibKa0s v1.29.0 → v1.30.0`.
No bundle names a span, and `## Documented deviations` has no row for the gap. v1.54.2 is not in scope: `a8f2133`
bumped the line while touching `tests/_kit` only, never `libs/LibKa0s/`.

## 4. Register, issue store, pending ledger

```
$ gh issue list --state all --limit 200 --json number,title,state,labels   (31 issues)
  every issue: exactly one state:* and one severity:* label; no "[status]" title prefix
  open: #9 #11 #16 #17 (state:triaged)      will-not-do: #18 #19 #20 #21 #22 #29
$ ls docs/pending 2>/dev/null        -> (absent)
```

Register rows (`docs/ARCHITECTURE.md:482-488`) and their triggers:

- `architecture-§5` — trigger "`settings.auction.priority` gains a schema row…". `grep -n 'auction.priority' settings/Schema.lua`
  → only `settings/Schema.lua:385`: `-- NOTE: \`settings.auction.priority\` (the ordered cascade selection list) is a carve-out array —`. **Not fired.**
  Row citations re-read: `modules/AuctionPrice.lua:116` `function AuctionPrice:GetPriority()`, `:124` `function AuctionPrice:ReconcilePriority()`,
  `settings/Panel.lua:1059` `function P:RestoreDefaults()`, `:1062` `if NS.AuctionPrice and NS.AuctionPrice.GetPriority then`.
- `performance-§12` — `git ls-files '*.lua' ':!libs' ':!tests' | xargs grep -nE 'SetScript\("OnUpdate"|NewTicker|ScheduleRepeatingTimer'`
  → no output (xargs exit 123). **Not fired.** Issue #22: `CLOSED Wire LibKa0s-Perf-1.0 and a performance harness`.
- `options-ui-§12` — maintainer ruling; none recorded. **Not fired.** `settings/Slash.lua:180` `function Sl:ResetEverything()`;
  `settings/Schema.lua:769` `{ "resetall", "Reset all settings",    function() NS.Slash:CliResetAll() end },`.
- `options-ui-§1` — `grep -rnoE 'function O\.[A-Za-z]+' libs/LibKa0s/Options*.lua` lists `O.ChoiceGrid`, `O.IdList`, `O.RenderGrid` …;
  `O.ChoiceGrid` is documented as "A matrix of one-choice-per-row checkbox cells" (`libs/LibKa0s/OptionsWidgets.lua`, above `:1817`),
  not a multi-check set maker. **Not fired.** Issue #20 resolves.
- `localization-§1` — `ls locales` → `enUS.lua`. **Not fired.** `LH-48` found once in `docs/audits/2026-09-07/02_DEVIATIONS.md`.
- Other ids in the register's retirement notes resolve: #19, #21, #25, #26, #30 (all CLOSED); `LH-47` (1 hit) and `LH-54`
  (2 hits) in `docs/audits/2026-09-07/02_DEVIATIONS.md`.

## 5. Line endings

```
$ test -f .gitattributes && echo present                        -> present
$ grep -n '^\* text=auto eol=\(crlf\|lf\)$' .gitattributes         -> 26:* text=auto eol=crlf
$ grep -nE '^\*\.(sh|py) text eol=lf' .gitattributes               -> 36:*.sh text eol=lf / 37:*.py text eol=lf
$ grep -c ' binary' .gitattributes                                -> 23
$ n=84; diff <(head -n 84 .gitattributes | tr -d '\r') <canonical client-bound body from line-endings-§5>   -> (empty)
$ tail -n +85 .gitattributes | tr -d '\r' | grep -m1 .           -> (nothing)
$ <the (e) one-liner, verbatim from AUDIT.md, whole tracked set>   -> 0
$ git ls-files -s tests/_kit/run-automated-tests.sh               -> 100755 31ff9b3… 0	tests/_kit/run-automated-tests.sh
```

`tests/run.lua:100`: `{ name = "test_eol", dir = "tests/_kit/" },` — green in the run above.

## 6. Packaging

```
bash -c '<AUDIT.md packaging checks (a), (b), (c), verbatim>'
(a) done                       <- nothing NOT IGNORED (tools/.claude absent; .superpowers present and ignored)
UNACCOUNTED — .git             <- the one entry the packager never sees
(b) done
(c) done                       <- no FALSE CLAIM
```

`.pkgmeta:14` `# because packaging.md:28 MUSTs every root dot-entry present in the repo be`; `.pkgmeta:19`
`- .superpowers     # untracked; listed under packaging.md:28`; `.pkgmeta:20` `- .pytest_cache    # untracked; listed under packaging.md:28` (LH-67).

## 7. Layout census and cap gate

```
$ git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)' | wc -l                 -> 65
$ … | xargs wc -l | sort -rn | head
  24845 total / 1271 modules/Browser.lua / 1225 modules/BrowserTable.lua / 1200 modules/Analytics.lua
  1107 settings/Panel.lua / 1048 tests/test_schema.lua / 1020 tests/test_slash.lua / 974 tests/test_panel.lua …
$ … | awk '$2!="total" && $1>1500' | wc -l                                      -> 0
```

Scope: default denominator (tests in, `libs/` and `tests/_kit/` out); the repo declares no generated-data exemption.
Census: `docs/ARCHITECTURE.md:506` `### Files over the 1500-line cap` under `## Documented deviations` (`:470`), body
"Nothing is over the cap today." Gate: `tests/run.lua:104` `{ name = "test_layout_cap", dir = "tests/_kit/" },`.
Generators: `git ls-files '*.py' '*.sh'` → `tests/_kit/run-automated-tests.sh` only (vendored runner — not a finding).

## 8. TOC position annotations (LH-56, LH-57, LH-63, LH-58)

Load-bearing positions, established by reading every seam's file scope:

| TOC line | Text at the line | What resolves at load | Annotated? |
|---|---|---|---|
| `LootHistory.toc:37-40` | `core\ItemSetup.lua` (comment `:37` "LOAD-BEARING POSITION: publishes NS.Item…") | `NS.Item.QualityLabel` in `core/Constants.lua` | yes |
| `LootHistory.toc:41-43` | `core\MediaSetup.lua` (comment `:41`) | `NS.MediaFont` → `core/Constants.lua:64` `C.FONT_MONO = NS.MediaFont and NS.MediaFont(C.FONT_MONO_NAME) or _G.STANDARD_TEXT_FONT` | yes |
| `LootHistory.toc:48` | `core\CoreSetup.lua` | `core/CoreSetup.lua:180` `local printer = lib:New({ prefix = NS.PREFIX })` ← `core/Namespace.lua:18` `NS.PREFIX = "\|cff00ffff[LH]\|r"` | **no** (LH-56) |
| `LootHistory.toc:56` | `core\DebugLogSetup.lua` | `core/DebugLogSetup.lua:90` `font  = NS.Constants.FONT_MONO,` inside `lib:New({` at `:76` | **no** (LH-57) |
| `LootHistory.toc:81-85` | `settings\OptionsSetup.lua` (comment `:81`) | `NS.Options` for `settings/Schema.lua:12` `local O = NS.Options` / `:68` `O.MasterControls{` | yes |
| `LootHistory.toc:87` | `settings\Slash.lua` | `settings/Slash.lua:355` `local Dispatcher = lib:New({` → `:358` `commands     = NS.COMMANDS,` ← `settings/Schema.lua:739` `NS.COMMANDS = gateFeatureVerbs{`; `:415` `brandName = NS.BRAND,` ← `core/Namespace.lua:13` `NS.BRAND = "Ka0s Loot History"` | **no** (LH-63) |

Not load-bearing though commented as positional: `LootHistory.toc:57` `# The LibKa0s-Pool seam. Before every module that pools a
widget (Analytics, BrowserTable).` — `grep -nE '^(local )?[A-Za-z_.]+ *= *NS\.Pool\.New' modules/*.lua settings/*.lua` → no hit;
every `NS.Pool.*` call is inside a function. Conventional groups with no statement (LH-58): `LootHistory.toc:29` `# Locales`,
`:67` `# Defaults`.

## 9. Bus message names (LH-66)

```
$ git ls-files '*.lua' ':!libs' ':!tests/_kit' | xargs grep -nE '(Send|Register)Message\("Ka0s_'
tests/test_browser.lua:536:  for _ = 1, 12 do NS.bus:SendMessage("Ka0s_LootHistory_RecordAdded", {}, 1) end
tests/test_browser.lua:552:  NS.bus:SendMessage("Ka0s_LootHistory_HistoryChanged")
tests/test_collector.lua:440:  NS.bus:RegisterMessage("Ka0s_LootHistory_SettingsChanged", function() browserGot = true end)
tests/test_collector.lua:444:  NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "questfilter")
tests/test_collector.lua:473:  NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "test")
tests/test_harness.lua:145:  listener:RegisterMessage("Ka0s_LootHistory_HarnessProbe", function(msg, a) got = { msg, a } end)
tests/test_harness.lua:146:  NS.bus:SendMessage("Ka0s_LootHistory_HarnessProbe", 42)
tests/test_panel.lua:232:  for _ = 1, 12 do NS.bus:SendMessage("Ka0s_LootHistory_RecordAdded", {}, 1) end
tests/test_panel.lua:252:  NS.bus:SendMessage("Ka0s_LootHistory_HistoryChanged")
```

9 call-site literals, all in tests; scope = authored Lua outside `libs/` and `tests/_kit/`. The casing grep finds only
PascalCase tails (`RecordAdded`, `HistoryChanged`, `SettingsChanged`, `HarnessProbe`); the declarations are
`core/Constants.lua:191` `local MSG = {` … `:209` `NS.MSG = Bus.Catalog((...), MSG)`.

## 10. Event registration, stand-down census (LH-64; disabled state)

```
$ git ls-files '*.lua' ':!libs' ':!tests/_kit' ':!tests' | xargs grep -nE 'Register(Unit)?Event|RegisterMessage|RegisterBucketEvent'
core/LifecycleSetup.lua:112:    NS.addon:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnterWorld")
modules/Analytics.lua:666:  self.__ev:RegisterMessage(NS.MSG.RECORD_ADDED,
modules/Analytics.lua:668:  self.__ev:RegisterMessage(NS.MSG.HISTORY_CHANGED, live)
modules/Attribution.lua:349-355:  bus:RegisterEvent("LOOT_OPENED" … "QUEST_TURNED_IN" …)       (7 bare calls in a row)
modules/Attribution.lua:369:  spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
modules/Browser.lua:1229/1230/1240:  B.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED | HISTORY_CHANGED | RECORD_ADDED …)
modules/Browser.lua:1246:    B.__ev:RegisterEvent("PLAYER_REGEN_DISABLED", function()
modules/Browser.lua:1252:    B.__ev:RegisterEvent("PLAYER_REGEN_ENABLED",  function() B:ApplyVisibility() end)
modules/Collector.lua:218:  bus:RegisterEvent("CHAT_MSG_LOOT", function(_, msg) self:OnChatMsgLoot(_, msg) end)
modules/Collector.lua:219:  bus:RegisterEvent("CHAT_MSG_CURRENCY", function(_, msg) self:OnChatMsgCurrency(_, msg) end)
modules/Collector.lua:228:  self.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, _reason)
settings/Panel.lua:159/169/492:  ev:RegisterMessage(…)   (the panel's own refresh subscriptions — recorded-not-ruled)
```

No `pcall` wraps any of them; `grep -rn 'IsEventValid\|__badEvents\|rejected' core modules settings` → no hit (LH-64).

Undo for each (`… | xargs grep -nE 'Unregister(All)?Events?|UnregisterMessage|…|:Cancel\('`):
`core/LifecycleSetup.lua:93` `if NS.addon and NS.addon.UnregisterAllEvents then NS.addon:UnregisterAllEvents() end`;
`modules/Attribution.lua:405` `for _, event in ipairs(self.__events or {}) do bus:UnregisterEvent(event) end`, `:407`
`if self.__spellFrame then self.__spellFrame:UnregisterAllEvents() end`; `modules/Collector.lua:243-244` (both chat events),
`:248` `self.__ev:UnregisterAllEvents()`; `modules/Browser.lua:1266-1267` (`UnregisterAllMessages` / `UnregisterAllEvents`);
`modules/Analytics.lua:677` `self.__ev:UnregisterAllEvents()`; deferrals `core/LifecycleSetup.lua:80`
`if h.timer and h.timer.Cancel then h.timer:Cancel() end`. Timers/tickers: no `NewTicker`, no `OnUpdate`; one-shots go
through `NS.After` (`core/LootHistory.lua:81`, `:85`; `core/Util.lua:256`). Hooks: `hooksecurefunc` only
(`modules/Attribution.lua:383/386/389`, `core/Compat.lua:41/43/63`), gated at `Attribution:Stamp`. The unit-filter frame is
held on the module (`self.__spellFrame`), unregistered in `Disable`, reused — inside the `events-frames-taint-§1` carve-out.
`tests/test_disabled.lua` is listed in `tests/run.lua:81`; falsification comments at `:191`, `:273`, `:486` (`-- red under: …`).

## 11. Combat reads for display (LH-65)

- `modules/Browser.lua:1135` `local inCombat = (InCombatLockdown and InCombatLockdown()) and true or false`
- `modules/Browser.lua:1246-1247` `B.__ev:RegisterEvent("PLAYER_REGEN_DISABLED", function()` / `B:ApplyVisibility()`
- `modules/BrowserTable.lua:543` `if InCombatLockdown and InCombatLockdown() then`
- The standard's own statement of the timing: options-ui-§15 — test mode "ends when combat starts
  (`PLAYER_REGEN_DISABLED`, while secure writes are still allowed)", i.e. lockdown is not yet engaged in that handler.
- `tests/test_browser.lua:627-636` drives `VisibilityAllows` with the mock's lockdown flag set directly, so the suite cannot
  see the event-handler timing. Not reproduced in the client by this audit.

## 12. Settings panel content

```
$ grep -rn 'ScrollUp-Up\|ScrollDown-Up' --include='*.lua' settings/        -> (no hit)
$ grep -nE 'LSM30_|disabledIf|type *= *"color"' settings/*.lua             -> (no hit)
$ git ls-files '*.lua' ':!libs' ':!tests/_kit' ':!tests' | xargs grep -nE 'SettingsPanel|HideUIPanel|ToggleGameMenu|OpenToCategory'
settings/OptionsSetup.lua:172:  mainPanelName = "LootHistorySettingsPanel",
$ grep -n 'SetMovable(true)' modules/*.lua
modules/Browser.lua:939:  frame:SetMovable(true)
modules/Export.lua:439:  frame:EnableMouse(true); frame:SetMovable(true); frame:SetClampedToScreen(true)
```

Page → tabs: General → Master controls · Capture · AH Price · Interface · History · Filters (`settings/Panel.lua:953`
`local GENERAL_TABS = {`, drawn by `O.TabStrip` at `:1006`); Filters' secondary strip `O.SubTabStrip` at `:453`, in the scroll.
Master controls composed at `settings/Schema.lua:68` `local MASTER_ROWS, MASTER_AFTER_GROUP = O.MasterControls{` with
`testModePath = "state.testMode"` (`:76`) and `minimapPath = "minimap.hide"` (`:91`). Reset popup wording
`settings/Slash.lua:23` = the profile-less canonical text verbatim.

## 13. Stub coverage and parity (LH-68)

```
$ bash -c 'for m in Item Pool Lifecycle; do git ls-files "*.lua" ":!libs" ":!tests" | xargs grep -ohE "NS\.$m[:.][A-Za-z_]+" | sort | uniq -c; done'
  NS.Item.LoadItem 1 / NS.Item.QualityFromLink 1 / NS.Item.QualityLabel 8
  NS.Pool.Acquire 6 / NS.Pool.New 36 / NS.Pool.ReleaseAll 2
  NS.Lifecycle:IsDown 1 / NS.Lifecycle:Reevaluate 1 / NS.Lifecycle:Release 1 / NS.Lifecycle:Set 3
```

Stubs: `core/ItemSetup.lua:40` `NS.Item = Item or {` with `ItemIDFromLink` `:41`, `QualityFromLink` `:46`, `QualityLabel` `:62`,
`LoadItem` `:67`; `core/PoolSetup.lua:24` `NS.Pool = Pool or {` with `New` `:25`, `Acquire` `:27`, `ReleaseAll` `:37`,
`Counts` `:52`; `core/LifecycleSetup.lua:148` `NS.Lifecycle = {` with `Hold`/`Release`/`Set`/`IsHeld`/`IsDown`/`Reevaluate`/
`Holds`/`PrintHolds` (`:150-162`). Every reached member is answered.
`grep -n '^test(' tests/test_surface_parity.lua` → cases at `:66` Core, `:89` Widgets, `:113` Slash, `:123` DebugLog, `:151`
Options, `:176` Bus, `:191` Compat, `:206`/`:213` Schema. No Env, Item, Media, Pool or Lifecycle case.

## 14. Close control, media

```
$ grep -rn 'MakeCloseButton(' --include='*.lua' . | grep -v '/libs/' | grep -v '/tests/'
./core/CoreSetup.lua:168:  return lib.MakeCloseButton(parent, onClick, addonName)
./modules/Export.lua:465:    NS.Browser:MakeCloseButton(tbar, function() frame:Hide() end)
./modules/Browser.lua:84:function B:MakeCloseButton(parent, onClick)
./modules/Browser.lua:86:  return NS.MakeCloseButton(parent, onClick)
./modules/Browser.lua:989:  local close = B:MakeCloseButton(titleBar, function() B:Hide() end)
```

The wrapper is `core/CoreSetup.lua:167` `NS.MakeCloseButton = function(parent, onClick)`; every call ends there.
Resize grip (LH-76): `modules/Browser.lua:1047` `grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")`,
`:1042` `-- Blizzard's corner grabber, which is what BankLedger, MultiMeters and the rest of the`; catalog entry
`libs/LibKa0s/Media.lua:103` `"move", "resize", "fullscreen-enter", …` and `libs/LibKa0s/media/icons/resize.tga` present.
Logo headers: `od -A d -t u1 -N 18 media/logos/loothistory.logo.128.tga` → byte 2 = `2`, bytes 12-15 = `128 0 128 0`, byte 16 = `32`.

## 15. Citations (LH-67, LH-73)

```
$ git ls-files | grep -vE '^(libs/|tests/_kit/|docs/(audits|reviews|automated-tests|revendor|superpowers)/)' | xargs grep -nE '§[0-9]+\.[0-9]' | wc -l
22        (11 in tests/test_disabled.lua, 11 in docs/test-cases.md)
$ … | xargs grep -nE 'disabled-§' | cut -d: -f1 | sort | uniq -c
  12 docs/test-cases.md
  12 tests/test_disabled.lua
```

Scope: every tracked file except vendored trees and frozen bundles. Every other `filename-§N` citation range-checks
against §0's heading counts. Sites: `tests/test_disabled.lua:174` `test("disabled-§7.1: enabled, the addon registers a
NON-EMPTY set and draws", function()` … `:516` `test("disabled-§7: the latch persists NOTHING, …`.

Drift (LH-73), each re-read:
- `DEPENDENCIES.md:53` cites `run-automated-tests.sh` `:186` and `:109`; actual `tests/_kit/run-automated-tests.sh:242`
  `declare -A ST DUR NOTE` and `:122` `elif [ -n "${EPOCHREALTIME:-}" ]; then` (`:186` and `:109` are comment lines).
- `DEPENDENCIES.md:49` cites `docs/testing.md:187` for the lint gate; actual `docs/testing.md:191` `` `luacheck .` — must report
  **0 warnings / 0 errors** before every commit.`` (`:187` is `The inventory doc and the badge are part of the change, not a follow-up.`).
- `DEPENDENCIES.md:112` cites `docs/testing.md:179`; actual `:183` `1. Regenerate the inventory: \`lua tests/run.lua --list > docs/test-cases.md\`.`
- `docs/ARCHITECTURE.md:42` `LibKa0s seams sit inside \`core/\`, and **four** of their positions are load-bearing rather than tidy:`
  (the four named are Item, Media, Widgets, Pool — §8 above shows CoreSetup and DebugLogSetup are load-bearing and Pool is not).
- `docs/ARCHITECTURE.md:207` `… by running the \`config\` verb (slash-commands-§4, Slash minor` — the bare-verb rule is in
  slash-commands-§3 ("Bare `/<slash>` (no args) MUST open the settings panel on its landing page").
- `docs/ARCHITECTURE.md:447` `| \`compat-layer.md\` | Present | \`core/Compat.lua\` is 419 lines of addon-specific shimming beyond LibKa0s |`;
  the trigger count: `grep -cE '^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\.' core/Compat.lua` → **21**.

## 16. Documentation shape

```
$ wc -l docs/ARCHITECTURE.md                                    -> 554
$ awk '/^## /{…}' docs/ARCHITECTURE.md   (lines per ## section, incl. blanks)
  Overview 28, Module map 45, Data model 10, Settings schema 68, Message bus 39, Slash commands 50,
  The disabled state 79, Event subscriptions 27, Menus 33, Taint notes 14, Standards compliance 11,
  Documentation map 45, Documented deviations 47, Known limitations 36
$ wc -l docs/performance.md                                     -> 190
$ grep -n '^#' docs/performance.md
  1 # Performance / 27 ## Why… / 53 ## The sweep… / 130 ## What ends the exemption /
  141 ## The one allocation that is measured… / 157 ## The allocation that is not measured… / 185 ## The complexity half
```

Documentation map reconcile (every non-frozen `.md` under `docs/` vs the map's first-column entries):

```
on disk not in map:            (none)
in map not on disk:            debug.md  perf-analysis/README.md  profiles.md   <- the three "Not applicable" rows
on-disk count 18, map rows 21
```

Tier 1: `scope.md`, `module-map.md`, `schema.md`, `settings-panel.md`, `data-flow.md`, `common-tasks.md` all present. Tier 2 triggers:
`NS.COMMANDS` has **16** entries (`settings/Schema.lua:739-800`: show hide toggle config enable disable version get set list reset
resetall debug test purge help) → `slash-dispatch.md` present; Compat shims 21 → `compat-layer.md` present; 3 messages (below 10)
→ `message-bus.md` present by choice. Four tables present (`docs/ARCHITECTURE.md:429`, `:441`, `:453`, `:464`). No
`data-model.md`/`pipeline.md`/…, no `file-index.md`/`conventions.md`/`complexity.md`, no `docs/perf-runs/`.

`README.md:58` begins `Everything else is configuration, and it lives in two places: the addon's own page under **Settings ▸ AddOns** …`
and runs six sentences (LH-71). `CLAUDE.md:49` `## Vendored LibKa0s` precedes `CLAUDE.md:62` `## Green gate` (LH-72).

## 17. Complexity and the watch list

```
$ ~/.claude/wow-addon/bin/ka0s-bounded lizard --version     -> 1.24.0
$ ~/.claude/wow-addon/bin/ka0s-bounded lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .
No thresholds exceeded (cyclomatic_complexity > 15 or length > 1000 or nloc > 1000000 or parameter_count > 100)
Total nloc 16326 · Avg.NLOC 6.4 · AvgCCN 2.1 · Avg.token 51.3 · Fun Cnt 2200 · Warning cnt 0
Top CCN (all 15): E@39-159 modules/Export.lua; BrowserTable@657-705, @1080-1123, @969-986; Compat.ScanBound@233-253;
                  Attribution@190-213; AuctionPrice@156-180
```

Against the newest bundle `docs/automated-tests/20260916-184506/manifest.json`: `"git": { "sha": "b267e38…", "branch": "master",
"dirty": false }`, complexity `nloc 15349, functions 2045, maxCcn 15, warnings 0, bandFiles 4`. `git rev-list --count b267e38..HEAD`
→ **35**; stamp 2026-09-16 (7 days). Drift: no function crossed CCN 15; band entries new since that run —
`tests/test_schema.lua` (1048), `tests/test_slash.lua` (1020). The checkpoint is release; this is recorded, not filed.
Release runs: `grep -h '"release"' docs/automated-tests/*/manifest.json | sort | uniq -c` → `1 "release": "1.3.0"`, `10 "release": null`.
Watch list: `docs/automated-tests/RESULTS.md:84` `| 1000–1500 (on notice) | \`modules/Analytics.lua\` | 1178 | **Peel next — unblocked since …`;
no open issue names the Analytics peel (§4's list) (LH-52).

Perf skip reason (LH-69): every manifest carries `"perf": { "status": "skip", … "skipReason": "no tests/perf.lua — this addon ships no offline scenarios"`;
the runner decides it at `tests/_kit/run-automated-tests.sh:343-344` `if [ ! -f tests/perf.lua ]; then` /
`ST[perf]="skip"; NOTE[perf]="no tests/perf.lua — this addon ships no offline scenarios"`, and its RESULTS prose at `:838-841`
says the skip is not the `performance-§12` exemption — with no input that could tell it otherwise.

## 18. Localization and versioning (LH-74, LH-75)

- Kit prose gate green: run output `PASS  prose: no authored file carries a British spelling from localization-5's published list`.
- `modules/Attribution.lua:64` `local name = NS.Compat.GetSpellName(seed.id)`; `:94`
  `if cast:find(tok, 1, true) then return seed.source, true end`; reasoning at `:29`
  `-- English literal: GetSpellName returns the client-locale name, so "Milling" on enUS becomes`. No `localization-§4` register row.
- `defaults/Global.lua:13` `schemaVersion = 1,`; `core/Database.lua:103` `{ to = 8, apply = function(g)`; `:133`
  `g.schemaVersion = m.to`; comment `defaults/Global.lua:8-12` ("seeding today's number would hand a brand-new install a stamp
  claiming migrations that never ran on it"). No `versioning-git` register row.

## 19. Pre-formatting (LH-77)

`settings/Slash.lua:40` `print(("blacklist cleared (%d %s)."):format(n, n == 1 and "id" or "ids"))` (and `:51`, `:62`, `:76`,
same shape); `settings/Schema.lua:785` `if switched then print("test mode " .. (on and "on" or "off")) end`. `print` there is
`local print = NS.Print` (`settings/Slash.lua:4`, `settings/Schema.lua:5`). None formats a value from the trigger-set APIs.
