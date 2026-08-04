# 03 — Evidence

Every claim in `01_CURRENT_STATE.md` and every row in `02_DEVIATIONS.md` is sourced here. Mechanical
checks record the **command actually run and its real output**; nothing below is inferred from the
code looking reasonable.

Audited against **Ka0s WoW Addon Standard v2.17.1 (2026-08-03)**.
Repo HEAD: `17d1d55`. Working tree clean apart from the untracked `docs/reviews/2026-08-03/`.

---

## §0 — Standard provenance (mechanical)

```
$ cd /mnt/d/…/WowAddonStandards && git status --porcelain && git log -1 --format='%H %s'
214122996c6c2db2e1c4a88a1f5d152dce2de928 v2.17.1 — finish the v2.17.0 rollout: no fourth slot, no drop-in imperative
```

(`git status --porcelain` produced **no output** — clean tree.)

```
$ curl -fsSL --max-time 15 ".../master/AUDIT.md" -o std/AUDIT.md ; echo "exit=$?"
exit=0

$ diff AUDIT.md    $R/AUDIT.md                    && echo "AUDIT identical"
AUDIT identical
$ diff STANDARDS.md $R/standards/STANDARDS.md     && echo "STANDARDS identical"
STANDARDS identical
$ for f in *.md; do diff -q $f $R/standards/standards/$f …; done
same: anti-patterns.md          same: architecture.md         same: audit-review-history.md
same: compat.md                 same: debug-logging.md        same: documentation.md
same: events-frames-taint.md    same: layout.md               same: library-stack.md
same: lint.md                   same: localization.md         same: naming-cheatsheet.md
same: open-evolutions.md        same: options-ui.md           same: packaging.md
same: performance.md            same: preview-mode.md         same: public-api.md
same: savedvariables.md         same: slash-commands.md       same: standalone-windows.md
same: testing.md                same: toc-file.md             same: versioning-git.md
```

Fresh re-fetch probe of three section files direct from the raw URL:

```
$ for f in anti-patterns performance testing; do curl -fsSL --max-time 15 ".../standards/standards/$f.md" -o probe_$f.md && diff -q probe_$f.md std/$f.md && echo "fresh-fetch identical: $f"; done
fresh-fetch identical: anti-patterns
fresh-fetch identical: performance
fresh-fetch identical: testing
```

**24 of 24 section files resolved and verified byte-identical.** No section unassessed.

---

## §1 — Mechanical checks on the addon

### 1.1 Lint — `luacheck .`

```
$ cd /mnt/d/…/LootHistory && luacheck .
Checking core/Compat.lua        OK
Checking core/Constants.lua     OK
… (23 files) …
Checking settings/Slash.lua     OK

Total: 0 warnings / 0 errors in 23 files
(exit 0)
```

**Result: clean.** Satisfies `lint` and the `testing-§4` commit gate's lint half.

### 1.2 Headless suite — `lua tests/run.lua`

```
$ cd /mnt/d/…/LootHistory && lua tests/run.lua
…
  PASS  every file of LibKa0s.xml is vendored and loads
  PASS  the vendored copy carries the library's MIT license
  PASS  the four adopted majors all resolved, and the seams are wired to them
  PASS  every seam file resolves its major with the silent flag
  PASS  the Options page registry built every page this addon declares
  PASS  libs/LibKa0s is the LibKa0s release the README says this addon bundles
  PASS  tests/_kit is the test kit that shipped with that release

563 passed, 0 failed, 563 total
(exit 0)
```

**Result: green, 563/563.** Note the case name *"the **four** adopted majors"* — independent
confirmation from the addon's own suite that `LibKa0s-Perf-1.0` is not adopted (**LH-20**).

Cross-check of the inventory and badge (`testing-§5`, `documentation-§1` #5):

```
$ tail -5 docs/test-cases.md
| test_analytics.lua | 57 |
| test_panel.lua | 24 |
| test_libka0s.lua | 17 |
| test_vendor_sync.lua | 2 |
| **Total** | **563** |

$ grep -n 'img.shields.io/badge/Tests' README.md
7:![Tests](https://img.shields.io/badge/Tests-563%2F563_passing-green)
```

**563 = 563 = 563.** Inventory, run and badge agree. Badge uses the canonical `%2F` encoding.

### 1.3 Vendored Ka0s-owned library drift (`library-stack-§7`, AP #45 / #48)

Sibling source repo located and confirmed:

```
$ ls /mnt/d/…/GIT/LibKa0s
CHANGELOG.md  LICENSE  LibKa0s  README.md  docs  testkit  tests
$ cd /mnt/d/…/GIT/LibKa0s && git log -1 --format='%H %s'
ac5d0f576eddeb375b982515e0e49e9faba5d881 docs: act on the 2026-08-02 adoption report
```

`LibKa0s/` (the ship folder) and `testkit/` (its sibling at repo root) are both present, so both
diffs could be run.

**Diff 1 — the ship payload, whole folder:**

```
$ diff -r /mnt/d/…/GIT/LibKa0s/LibKa0s /mnt/d/…/GIT/LootHistory/libs/LibKa0s
EXIT=0
```

**Empty.** No drift, no missing file. **AP #45 clear, AP #48 clear** for the ship folder.

**Diff 2 — the vendored headless harness:**

```
$ diff -r /mnt/d/…/GIT/LibKa0s/testkit /mnt/d/…/GIT/LootHistory/tests/_kit
EXIT=0
```

**Empty.** And it lands under `tests/`, never `libs/` — verified: `ls libs` returns
`AceAddon-3.0 AceConsole-3.0 AceDB-3.0 AceEvent-3.0 AceGUI-3.0 AceTimer-3.0 CallbackHandler-1.0
LibDBIcon-1.0 LibDataBroker-1.1 LibKa0s LibSharedMedia-3.0 LibStub` — no harness present.

The addon additionally carries its **own** byte-identity gate over both copies
(`tests/test_vendor_sync.lua:4,138-141`), which is above what the standard asks of a consumer.

### 1.4 Perf harness — mechanical absence check

```
$ grep -rn "Perf\|perf\|debugprofilestop" --include="*.lua" --include="*.toc" . --exclude-dir=libs
core/Compat.lua:268:-- An uncached item does NOT yield an empty tooltip: it yields a perfectly readable one…
tests/run.lua:24:  "libs/LibKa0s/Perf.lua",
tests/run.lua:25:  "libs/LibKa0s/PerfPanel.lua",
tests/test_compat.lua:211: … "perfectly legible" …
tests/test_libka0s.lua:20-21:  "libs/LibKa0s/Perf.lua", "libs/LibKa0s/PerfPanel.lua",
tests/test_libka0s.lua:139:    "core/PerfSetup.lua",
tests/_kit/…  (kit-internal references only)

$ ls docs/performance.md docs/perf-runs docs/complexity.md
ls: cannot access 'docs/performance.md': No such file or directory
ls: cannot access 'docs/perf-runs': No such file or directory
ls: cannot access 'docs/complexity.md': No such file or directory
$ ls tests/perf.lua
(absent — not in the file listing)
$ ls core/PerfSetup.lua
(absent — not in the file listing)
```

The **only** references to `Perf` in addon-owned code are the two `libs/LibKa0s/Perf*.lua` load-list
entries and `tests/test_libka0s.lua:139`, which names `core/PerfSetup.lua` in a **speculative** seam
list guarded by `if f then` — the file does not exist, so that entry is inert. **Evidence for LH-20,
LH-24, LH-25, LH-31.**

---

## §2 — Evidence per deviation

### LH-20 — `performance-§1` — Perf lib not wired

- **Absence:** no `core/PerfSetup.lua` (repo file listing); no `NS.Perf` anywhere (§1.4 grep).
- **The library IS vendored and IS loaded** by the runner: `tests/run.lua:24-25`. So this is
  non-adoption, not partial vendoring — which is why AP #48 stays clear.
- **Not listed in the TOC's Core section:** `LootHistory.toc:32-41` runs
  `Compat → Constants → Namespace → State → Util → CoreSetup → DebugLogSetup → LootHistory → Database`
  with no `PerfSetup.lua`.
- **The decision on record:** `docs/pending/LEDGER.md:70` —
  `| LIBKA0S-17 | 34d1776d | … | 🔵 wont-do | 2026-08-01 | "LibKa0s-Perf-1.0 is **declined**, not
  deferred, for two independent reasons. **There is no hot path.** … **And `suspend` would destroy
  user data.** … `LootHistoryPerfDB` is deliberately NOT declared in the TOC. |`
- **The rule it fails:** `performance-§1` — "**MUST** create **one instance per addon at load**, from
  a descriptor, and stash it on the namespace … In its own core file (`core/PerfSetup.lua`)", under an
  adoption strength of "**MUST** for the **wiring** … **SHOULD** for **coverage** — which hot paths
  get buckets is genuinely addon-specific, **and some addons have almost no hot path**."

### LH-21 — `performance-§5` / `toc-file-§2` / `savedvariables-§4` — no `LootHistoryPerfDB`

```
LootHistory.toc:7:## SavedVariables: LootHistoryDB
```

`toc-file-§2`: "**MUST** declare exactly **two** SavedVariables globals in the order above:
`<Addon>DB` … and `<Addon>PerfDB`". One is declared.

### LH-22 — `performance-§4` / `slash-commands-§2` — no `perf` verb

`settings/Schema.lua:213-245` is the whole of `NS.COMMANDS`. Verbs present: `show`, `hide`, `toggle`,
`config`, `version`, `get`, `set`, `list`, `reset`, `resetall`, `debug`, `test`, `purge`, `help`
(`settings/Schema.lua:214-244`). **`perf` does not appear.** With no matching entry, the library's
dispatcher reaches its unknown-verb path, so `/lh perf` prints `unknown command 'perf'` plus the help
index (`slash-commands-§3`).

### LH-23 — `performance-§6` — no suspend/resume contract

No descriptor exists to carry `suspend`/`resume` (LH-20), and no suspended flag appears in the
addon's runtime state: `core/State.lua:1-17` declares `lootContext`, `encounter`, `keystone`,
`cleanupDone`, `debug`, `testRecords` and nothing else. The show-decision path
(`modules/Browser.lua`, `B:Show`/`B:Toggle`) has no suspended gate.

### LH-24 — `performance-§9` — no `tests/perf.lua`

Absent from the repo file listing. `tests/run.lua:42-51` lists nineteen suites; none is a measurement
runner (correct — `testing-§7` requires it stay **out** of the gate, but it must still exist).

### LH-25 — `documentation-§3` — missing `docs/performance.md`, `docs/perf-runs/README.md`

See §1.4. The canonical trio **is** present (`docs/ARCHITECTURE.md`, `docs/testing.md`,
`docs/smoke-tests.md`) and `docs/test-cases.md` is generated — so this row is scoped to the two perf
docs the same section makes **required** topic-detail docs.

### LH-26 — `lint` / `performance-§2` / `performance-§5`

```
.luacheckrc:10-41   read_globals = { "_G", "LibStub", "CreateFrame", … "Settings", "CreateColor",
                                     "tinsert", "tremove", "wipe", "select", }      -- no debugprofilestop
.luacheckrc:42-45   globals = {
                      "LootHistoryDB",      -- the SavedVariables write target
                      "StaticPopupDialogs", -- we register a purge-confirm dialog
                    }                                                               -- no LootHistoryPerfDB
```

`performance-§2`: "**MUST** add `debugprofilestop` to `.luacheckrc`'s `read_globals`".
`performance-§5`: "**MUST** be declared in `.luacheckrc`'s `globals` with a comment".

### LH-27 — `options-ui-§11` — the dead `dirty` flag

Every occurrence of the field in the file:

```
$ grep -n "ctx.dirty\|\.dirty" settings/Panel.lua
138:  ctx.dirty = false
321:        if ctx.panel:IsShown() then runRebuilders(ctx) else ctx.dirty = true end
```

Two **writes**, **zero reads.** Context:

```lua
-- settings/Panel.lua:133-140
-- Run a page's structural rebuilders (list rows) + relayout, and clear its dirty flag. Called on
-- first paint, on an on-screen edit, and on the next OnShow after an off-screen change — the gate
-- that keeps AceGUI teardown+rebuild off every tab click (options-ui-§11 / anti-pattern #39).
local function runRebuilders(ctx)
  for _, fn in ipairs(ctx.rebuilders or {}) do pcall(fn) end
  ctx.dirty = false
  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end
```

The comment states the intent — "*and on the next `OnShow` after an off-screen change*" — but nothing
implements it. `renderFilters` (`settings/Panel.lua:666-671`) is handed to `O.SetRenderer`
(`:734`), and the library re-runs a renderer off **its own** `ctx._dirty`, which the host never sets:

```lua
-- settings/Panel.lua:313-325
      local onChange = function()
        if ctx.panel:IsShown() then runRebuilders(ctx) else ctx.dirty = true end
      end
      ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", onChange)
```

The library's own dirty-setting path exists and is public — `O.RefreshAllPanels` →
`refreshCtx` sets `_dirty` for every hidden ctx (`libs/LibKa0s/Options.lua:460-472`, cited in
`docs/reviews/2026-08-03/02_PROPOSED_CHANGES.md:34-37`) — so this is a wiring mistake, not a missing
capability.

**Rule:** `options-ui-§11` — "A **structural rebuild** … **MUST** be scoped to the on-screen
subcategory … flag every other rendered panel **dirty** and rebuild it lazily on its next `OnShow`
(extend the first-show guard to also re-render when dirty)."

Corroboration (a lead, independently re-derived here): `docs/reviews/2026-08-03/01_FINDINGS.md:278`
`| F-001 | High | [design] | settings/Panel.lua:321 |`.

### LH-28 — `savedvariables-§2` — defaults hardcoded twice

Side by side:

| Setting | `defaults/Global.lua` | `settings/Schema.lua` |
|---|---|---|
| `settings.enabled` | `:21` `enabled = true` | `:25` `default = true` |
| `settings.qualityThreshold` | `:22` `qualityThreshold = 1` | `:61` `default = 1` |
| `settings.excludeQuestItems` | `:23` `excludeQuestItems = true` | `:85` `default = true` |
| `settings.recordCurrency` | `:24` `recordCurrency = true` | `:77` `default = true` |
| `settings.retentionDays` | `:26` `retentionDays = 30` | `:70` `default = 30` |
| `settings.windowScale` | `:27` `windowScale = 1.0` | `:52` `default = 1.0` |
| `settings.auction.capture` | `:31-35` (literal set) | `:109` `default = NS.Constants.AUCTION_CAPTURE_DEFAULT` ✅ |

The last row shows the correct form is already understood in this file — it is applied to exactly one
row. AceDB seeds from `NS.defaults` (`core/Database.lua:5`); `reset` / `resetall` / the Defaults
button read `S:Default(path)` → `row.default` (`settings/Schema.lua:183-186`,
`settings/OptionsSetup.lua:79`, `settings/Slash.lua:191`). Two independent sources for one number.

**Rule:** `savedvariables-§2` — "**MUST** be the **only** place a default value is hardcoded. Schema
rows `default =` reference these constants if reused."

### LH-29 — `testing-§9` — derivation not pinned

Derivation is correct:

```lua
-- tests/run.lua:28-30
-- Derived from the TOC rather than hand-listed, so the runner's load order cannot drift from the
-- client's — the exact drift a second hand-maintained list invites.
Loader.loadAll(Loader.tocFiles("LootHistory.toc"), NS, mocks)
```

But nothing is published for a case to compare against:

```lua
-- tests/run.lua:39
_G.LH_TEST = Kit.expose{ NS = NS, mocks = mocks, Loader = Loader }
```

And no suite asserts on it:

```
$ grep -rn "tocFiles" tests/*.lua
tests/run.lua:16:-- … which Loader.tocFiles cannot see (it skips every `libs\` line).
tests/run.lua:30:Loader.loadAll(Loader.tocFiles("LootHistory.toc"), NS, mocks)
tests/test_libka0s.lua:56:  Loader.loadAll(Loader.tocFiles("LootHistory.toc"), ns, mocks)
```

`tests/test_libka0s.lua:56` re-derives the list for the **degraded-load** case (a different purpose,
and a good one) — it does not assert the runner fed the loader exactly the TOC's files in the TOC's
order, that every derived path exists on disk, or that no `libs/` path leaked in.

**Rule:** `testing-§9` — "**MUST** pin the derivation itself with cases: that the runner fed the
loader exactly the TOC's files in the TOC's order (publish what it loaded through `Kit.expose` and
compare against a fresh derivation), that every derived path exists on disk, and that no `libs/` path
leaked in."

### LH-19 — `documentation-§5` — retired `§N.M` citations

```
settings/OptionsSetup.lua:99:  -- Ka0s standard §3.4: one LibStub resolution, stashed for every page file to reuse.
tests/test_database.lua:363:-- ── RunMigrations: the schema-migration seam (Ka0s Standard §2.2/§5.1) ──────────
```

Sweep command (excluding `libs/`, `tests/_kit/`, `.superpowers/`, and frozen `audits/` / `reviews/`):

```
$ grep -rnE "§[0-9]+\.[0-9]+|§[0-9]+[A-Z]" --include="*.lua" --include="*.md" --include="*.toc" .
```

Beyond those two hits, the only matches are `§6.2` / `§6.3` / `§8.2` inside
`docs/superpowers/specs/2026-07-25-insights-dashboard-ux-design.md`, which are **that document's own
internal section numbers**, not standard citations — correctly excluded.

### LH-30 — `standalone-windows-§2` — values restated, not delegated

```lua
-- modules/Browser.lua:20-33
local SKIN = {
  bg          = { 0.06, 0.06, 0.08, 0.92 },  -- flat dark panel
  border      = { 0, 0, 0, 1 },              -- crisp 1px black outer border
  innerBorder = { 0.24, 0.24, 0.27, 0.85 },  -- subtle lighter inner line
  divider     = { 0.24, 0.24, 0.27, 0.85 },  -- title separator
  title       = { 1.0, 0.82, 0.0 },          -- Blizzard gold
  …
}
-- modules/Browser.lua:66-86
function B:ApplySkin(f)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  f:SetBackdropColor(unpack(SKIN.bg));  f:SetBackdropBorderColor(unpack(SKIN.border))
  if not f.innerBorder then … end                       -- the 1px child, built once
  f.innerBorder:SetBackdropBorderColor(unpack(SKIN.innerBorder))
  if f.title   then f.title:SetTextColor(unpack(SKIN.title))       end
  if f.divider then f.divider:SetColorTexture(unpack(SKIN.divider)) end
end
```

**Values checked against the normative table (standalone-windows-§2) component by component:**
background `0.06,0.06,0.08,0.92` ✅ · outer edge `WHITE8X8` `edgeSize = 1` inset 1, `0,0,0,1` ✅ ·
inner highlight 1px child inset one pixel, `0.24,0.24,0.27,0.85` ✅ · title `1.0,0.82,0.0` ✅ ·
divider `0.24,0.24,0.27,0.85` ✅. **The output does not differ**, which is what the section says an
audit should chiefly flag — so this is raised only on the "**SHOULD** delegate to `Core.ApplySkin`
rather than restate them" half. No `LibStub("LibKa0s-Core-1.0")` lookup appears in
`modules/Browser.lua`.

### LH-31 — `performance-§10` — no `docs/complexity.md`

See §1.4. Line counts establishing why it would be useful:

```
$ wc -l modules/*.lua | sort -n | tail -4
  469 modules/Export.lua
 1040 modules/BrowserTable.lua
 1180 modules/Analytics.lua
 1314 modules/Browser.lua
```

All under the 1500 cap (`layout-§1`) — three in the "on notice" band.

### LH-32 / LH-33 — advisory

```
docs/pending/LEDGER.md:1-11   "# Pending-items ledger … Maintained by /wow-addon:pending-audit"
docs/superpowers/plans/2026-07-17-ai-export.md:140,146   the only references to wowhead-logo.png
README.md:172   "…**Removed Export to AI** — Export to CSV remains for History and Insights"
```

---

## §3 — Evidence for the compliance claims (not deviations)

### 3.1 The shared subsystems — descriptors and stubs, not absences

Per `AUDIT.md` step 6, each claim cites the **setup file's** lookup, descriptor and stub branch —
never the library's own source.

**Core** — `core/CoreSetup.lua`
```lua
:32   local lib = LibStub and LibStub("LibKa0s-Core-1.0", true)   -- silent form
:41   if not lib then … end                                       -- stub branch, :46-83
:91   NS.IsConcatSafe = lib.IsConcatSafe
:92   NS.SafeToString = lib.SafeToString
:97   local printer = lib:New({ prefix = NS.PREFIX })
:101  NS.Print  = printer.Print
:107  NS.Util.print = NS.Print                                     -- the reclaim source
```
**Stub coverage (5 members):** `IsConcatSafe` (`:67`), `SafeToString` (`:68`), `Print` (`:69`),
`Format` (`:74`), `Util.print` (`:82`). Every member the addon reaches is answered; the file states
the count and the reason at `:43-45`. The addon's suite pins it: *"degraded install: the Core stub
answers every member the addon calls"*.

**DebugLog** — `core/DebugLogSetup.lua`
```lua
:25   local lib = LibStub and LibStub("LibKa0s-DebugLog-1.0", true)
:27   if not lib then … end                                        -- stub branch, :32-73
:76   NS.DebugLog = lib:New({ name=…, title=…, font=NS.Constants.FONT_MONO, slash="/lh",
:87                           isEnabled=…, setEnabled=…,           -- the flag stays the host's
:92                           print = function(line) NS.Print(line) end,   -- late-bound forwarder
:97                           safeToString=…, :101 initSummary=…, :106 onVisibilityChanged=…,
:121                          applySkin = function(frame) NS.Browser:ApplySkin(frame) end })
:125-130  -- NO makeCloseButton, with the reason written down (standalone-windows-§2)
:135  NS.Debug = NS.DebugLog.Debug                                 -- bound BARE, per §1
```
**Stub coverage (17 members):** `buffer`, `FormatPlain`, `FormatColored`, `Add`, `Clear`,
`BufferSize`, `LastLine`, `FindLine`, `ShowCopy`, `Show`, `Hide`, `IsShown`, `Toggle`, `IsEnabled`,
`RefreshHeader`, `UpdateScrollBar`, `UpdateStatus`, `SetEnabled`, `ConsoleCheckbox`, plus `NS.Debug`
(`:32-72`). Cross-checked against every call site: `NS.Debug` ×39, `NS.DebugLog:IsShown/Show/Hide`
(`settings/Schema.lua:46-50`), `:SetEnabled/:Toggle` (`settings/Schema.lua:228-231`),
`ConsoleCheckbox` (settings page). **No member the addon calls is unanswered.** The stub still flips
the host flag and prints the ack (`:55-62`), as `debug-logging-§7` requires. The omitted
`makeCloseButton` is a **decision with its reason written down** (`:125-130`), not a gap.

**Slash** — `settings/Slash.lua`
```lua
:103  local lib = LibStub and LibStub("LibKa0s-Slash-1.0", true)
:129  if not lib then … end                                        -- stub branch, :135-162
:170  local Dispatcher = lib:New({ slash="/lh", slashAliases={"/loothistory"},
:173                               commands = NS.COMMANDS,          -- the table stays the host's
:176                               print = late-bound forwarder,
:180                               version = TOC metadata w/ constant fallback,
:187-191                           get/set/findRow/allRows/applyDefault → NS.Schema (one write seam),
:197                               groupKey, :200 format })
:208-225  Sl.OnSlash / PrintHelp / HelpHeader / HelpRows / BuildListLines / Cli* / LandingRows
:238-241  AceConsole :RegisterChatCommand("lh") + ("loothistory")   -- no SLASH_* globals
```
**Stub coverage:** `FormatKV`, `HelpRows`, `LandingRows`, `BuildListLines`, `PrintHelp`, `CliList`,
`CliGet`, `CliSet`, `CliReset`, `CliVersion`, `CliResetAll`, `OnSlash`, `Register` (`:138-161`) —
matching the live surface at `:208-225` member for member. Each degraded verb **names the missing
library** through the shared `NS.LIBKA0S_MISSING` clause (`:136`), and the stub does **not**
re-implement the row formatter or parser.

**Options** — `settings/OptionsSetup.lua`
```lua
:35   local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
:37   if not lib then … end                     -- LOAD-COMPLETING stub, :42-63 (see below)
:66   NS.Options = lib:New({ parentTitle=…, mainPanelName="LootHistorySettingsPanel",
:72-79                       print/debug/get/set/applyDefault  -- through NS.Schema:Set
:83-90                       rowsForPage / allRows, :95 scheduleTimer, :100 onAceGUI,
:107                        buildMain = late-bound NS.Panel.BuildMain })
```
The stub publishes `LSMValues` returning a closure yielding an empty table (`:56`) plus the
layout constants pages read off the instance (`:60`) and no-ops the rest. This is the **documented
options-ui-§1 exception** (load-completing, not member-answering) and is **explicitly not flagged**.
`NS.Options` **is** the library instance, not a copy-across table (`:66`).

**Test kit** — `tests/_kit/` vendored byte-identical (§1.3), `tests/wow_mock.lua` a thin extender,
`tests/run.lua:8-10` `dofile`s `framework.lua` / `loader.lua`.

### 3.2 Printer discipline (`events-frames-taint-§8`, `slash-commands-§4`)

```
$ grep -rnE "(^|[^.:%w_])print\(" --include="*.lua" core defaults locales modules settings | grep -v "local print"
modules/Browser.lua:815, :824        settings/Panel.lua:241, :252
settings/Slash.lua:14,37,48,59,73    settings/Schema.lua:195, :235
```

Each of those files takes the shared printer as a file-scope upvalue first:

```
modules/Browser.lua:5   local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer
settings/Schema.lua:5   local print = NS.Print
settings/Slash.lua:4    local print = NS.Print
settings/Panel.lua:4    local print = NS.Print
```

**No call site invokes the Lua global `print()`.** The tag is a single shared constant
(`core/Namespace.lua:10` `NS.PREFIX = "|cff00ffff[LH]|r"`) and is never hand-written per line. The
AceConsole clobber is handled at `core/LootHistory.lua:13` (`architecture-§2`, AP #36).

### 3.3 Bus receivers own their targets (`architecture-§4`, AP #32)

```
core/LootHistory.lua:20-26   function NS.NewBusTarget() … AceEvent:Embed(t); return t end
modules/Collector.lua:217    self.__ev = NS.NewBusTarget() or bus
modules/Analytics.lua:657    self.__ev = NS.NewBusTarget() or NS.bus
modules/Browser.lua:1308     B.__ev    = NS.NewBusTarget() or NS.bus
settings/Panel.lua:123, :318 local ev = NS.NewBusTarget()
```

Four independent consumers of `Ka0s_LootHistory_HistoryChanged` / `RecordAdded` /
`SettingsChanged`, each on its **own** target. No receiver registers on `NS.bus`-as-self.

### 3.4 Compat firewall (`compat`)

29 shims exported from `core/Compat.lua` (`:10` … `:473`). Whole-repo check for deprecated calls
outside the firewall:

```
$ grep -rnE "GetSpellInfo\(|GetSpecialization\(|GetAddOnMetadata\(|GetContainerItemInfo\(" --include="*.lua" core modules settings | grep -v "^core/Compat.lua"
settings/Slash.lua:181:    return (NS.Compat and NS.Compat.GetAddOnMetadata and NS.Compat.GetAddOnMetadata(NS.name, "Version"))
```

One hit, and it is a call **into** `Compat`. No `WOW_PROJECT_ID` anywhere.

### 3.5 Localization (`localization-§4`, `-§5`, AP #37 / #46)

```lua
-- core/Compat.lua:95-109 — matched on the localized GlobalString, never its English value
function Compat.IsAuctionHouseMail(sender, subject)
  if … sender == AUCTION_HOUSE then return true end
  for _, name in ipairs(AH_SUBJECT_GLOBALS) do
    local g = _G[name]; local prefix = g:match("^(.-)%%s") or g
    if prefix ~= "" and subject:sub(1, #prefix) == prefix then return true end
  end
```

`core/Compat.lua:124-146` decodes `creatureID` from `UnitGUID`. The `LOOT_ITEM_*`,
`CURRENCY_GAINED*` and `ITEM_*BOUND*` GlobalStrings are declared in `.luacheckrc:21-39`.

US-English sweep (all `*.lua` / `*.md` / `*.toc`, excluding `libs/`, `tests/_kit/`, `.superpowers/`,
frozen `audits/` / `reviews/`), pattern
`colour|grey|behaviour|centre[ds]?|cancelled|cancelling|analyse|catalogue|dialogue|defence|licence|favour|labelled|initialise|normalise|serialise|organise|optimise|capitalisation`:

```
(no output)
```

**Zero hits. AP #46 clear.**

### 3.6 Debug coverage (`debug-logging-§8`/`§9`/`§10`)

39 `NS.Debug` sites. Lifecycle: `initSummary` descriptor callback (`core/DebugLogSetup.lua:101`),
migrations `core/Database.lua:26,35,50,66,88,96,117`, prune `:664`, purge `:612`. Core flow **and its
not-recorded decisions**: `modules/Collector.lua:117` (`Drop … reason=`), `:138` (`Loot`), `:170,184`
(currency drops), `:203`. Attribution `modules/Attribution.lua:121-214`. **Coalesced** one-line-per-pass
summaries: `modules/BrowserTable.lua:872` (`Table … RenderSummary`), `modules/Analytics.lua:485`
(`Insights … SummaryLine`) — no per-item spam. Settings logged **once, at the write seam**:
`settings/Schema.lua:170-172`, inside `S:Set`, gated on `NS.State.debug`.

### 3.7 README / docs (`documentation-§1`/`§2`/`§3`/`§6`)

```
README.md:1   # Ka0s Loot History
README.md:3   ![WoW](…/badge/WoW-Midnight_12.0.7-purple)          ← matches TOC Interface 120007
README.md:4   ![CurseForge Version](…/curseforge/v/1607560)       ← matches TOC X-Curse-Project-ID
README.md:5   ![License](…/badge/License-MIT-orange)
README.md:6   [![Standard](…/badge/Ka0s-WoW_Addon_Standard-yellow)](…/WowAddonStandards)   ← `_` form
README.md:7   ![Tests](…/badge/Tests-563%2F563_passing-green)
README.md:8   ![Logo](…)
README.md:32  ## What's new in 1.2.0     ← 4 bullets, mirroring the 1.2.0 Version History row (:172)
README.md:39  ## Screenshots             ← immediately below What's new
README.md:59  ## Usage → :65 ### Slash commands → :85 ### Settings panel
README.md:121 ## How attribution works
README.md:127 ## FAQ    :144 ## Troubleshooting    :164 ## Issues and feature requests
README.md:168 ## Version History
```

Angle-bracket sweep of the README returned one hit, `README.md:172`, and it is a deliberate `<br>`
inside a table cell — expressly protected by `documentation-§1`.

The three-place standards reference (`documentation-§6`, AP #34): `LootHistory.toc:12`
`## X-Standard:`, `README.md:6` the standard badge, `CLAUDE.md:11` `## Standards compliance (read
first)`. **All three present.** No `docs/agent-context.md` exists — `CLAUDE.md:24-39` states the
prohibition explicitly. **AP #49 clear.**

---

## §4 — Checks recorded as UNVERIFIED

| Check | Section | Why |
|---|---|---|
| Mutation-proof of negative assertions | `testing-§12` | No suite carries a `-- red under:` comment (`grep -rn "red under" tests/*.lua` → 0). The section states mutation leaves **no repo artifact** and that an audit **MUST NOT** record its absence as a deviation. Recorded as **unverified**, not failed. The section's own SHOULD — a one-line comment naming the mutation — would make it checkable next run. |
| In-game behavior | — | Everything frame-, taint- and render-related is covered by `docs/smoke-tests.md`, which is an in-client suite this read-only audit cannot execute. |
