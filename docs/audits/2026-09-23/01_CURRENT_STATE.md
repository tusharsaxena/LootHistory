# 01 — Current state

**Addon:** Ka0s Loot History (`LootHistory`), `## Version: 1.3.0`, `## Interface: 120100`.
**Audited against:** Ka0s WoW Addon Standard **v2.64.0 (2026-09-23)**, fetched verbatim with `curl -fsSL`
from `raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master` (remote `master` =
`e68795f5cd6416fd4eaa9734c99b336ad0b70132` per `git ls-remote`). `AUDIT.md`, `standards/STANDARDS.md`, all
27 section files linked from its Sections list, and `standards/ADDONS.md` were fetched and read.
**Tree audited:** `54b7cc7958a6b4370447a3b41490fa2f70a27714` on branch `feat/2026-09-23-review-audit-remediation`,
clean working tree (`git status --short` empty). Read-only: this bundle is the only write.
**Run date:** 2026-09-23. Prefix **`LH-`** (reused; the highest ID ever issued is `LH-61`, so new rows start at `LH-62`).

**Tooling note.** `ka0s-bounded` is not on `PATH` in this shell, but it exists at
`~/.claude/wow-addon/bin/ka0s-bounded`. Every `luacheck`, `lua tests/run.lua` and `lizard` run in this audit went through
that absolute path, so no `timeout 900` fallback was needed.

## Repository kind

**Addon** — the repo has a `.toc` (`LootHistory.toc`) and is row 6 of `ADDONS.md`'s *In-scope addons* table
(launcher rung **(a) the browser**). The whole addon rule set applies. It is not `Ka0sAddonsCommonTasks`, not a
library repo and not a documentation-and-tooling repo.

## Snapshot, section by section

### layout
- Modular skeleton: `core/` (17 files), `defaults/Global.lua`, `locales/enUS.lua`, `modules/` (8), `settings/` (4),
  `media/logos/` + `media/screenshots/`, `libs/`, `tests/`, `docs/`. Nothing loose at the root beyond the doc trio,
  `LICENSE`, the TOC and dotfiles. No `tools/`, no tracked `.py`; the only tracked `.sh` is the vendored
  `tests/_kit/run-automated-tests.sh` (not a generator, not authored here).
- Authored Lua census (`git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)'`): **65 files, 24,845 lines**,
  **0 over the 1500-line cap**, **6 in the 1000–1500 band** — `modules/Browser.lua` 1271, `modules/BrowserTable.lua`
  1225, `modules/Analytics.lua` 1200, `settings/Panel.lua` 1107, `tests/test_schema.lua` 1048, `tests/test_slash.lua` 1020.
- The cap census exists as `### Files over the 1500-line cap` **under** `## Documented deviations`
  (`docs/ARCHITECTURE.md:506-514`), reading "Nothing is over the cap today" — agrees with the tree. The kit's gate is
  wired by path (`tests/run.lua:104`, `{ name = "test_layout_cap", dir = "tests/_kit/" }`).
- `media/` holds only the addon's own logo set and screenshots; no private font/icon/texture copy.
- Logo: `media/logos/loothistory.logo.128.tga` is TGA type **2**, **128×128**, **32** bpp (header read with `od`);
  the landing-page `loothistory.logo.tga` is a separate RLE 512² file, which is not graded.

### toc-file
- Field order matches `toc-file-§1` exactly (Interface → … → X-Curse-Project-ID). `## IconTexture` names the addon's own
  128 file. `X-Curse-Project-ID: 1607560` (published; README carries the live CurseForge badge).
- `## SavedVariables: LootHistoryDB` only — correct for an addon holding the `performance-§12` exemption.
- Section headers Libraries → Locales → Core → Defaults → Modules → Settings; single trailing CRLF newline.
- `libs\LibKa0s\LibKa0s.xml` listed once, last in `# Libraries`; no individual LibKa0s module file in the TOC.
- **Load-bearing positions (established by reading the seams, not the comments):** `core\ItemSetup.lua` and
  `core\MediaSetup.lua` (annotated), `settings\OptionsSetup.lua` (annotated), and three that are **not** annotated —
  `core\CoreSetup.lua` (`NS.PREFIX` read at file scope), `core\DebugLogSetup.lua` (`NS.Constants.FONT_MONO` read at
  file scope) and `settings\Slash.lua` (`NS.COMMANDS` / `NS.BRAND` read at file scope). `core\PoolSetup.lua` is
  annotated as positional but resolves nothing at load. See LH-56, LH-57, LH-63.

### library-stack
- Vendored: LibStub, CallbackHandler-1.0, AceAddon/AceEvent/AceTimer/AceConsole/AceDB/AceGUI-3.0,
  LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0, LibKa0s (whole folder). No `externals:`.
- **Provenance:** root `CLAUDE.md:51` — `Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.55.0 (MIT)`;
  none in `README.md`. v1.55.0 is the newest tag in `../LibKa0s` and is ≥ the v1.42.0 Lifecycle floor (Slash minor 14).
- **`diff -r` against the v1.55.0 tag (both payloads): empty.** No drift (#45), no partial vendoring (#48).
- LibKa0s majors wired, one seam each: Core (`core/CoreSetup.lua`), Env (`core/EnvSetup.lua`), Compat
  (`core/Compat.lua`, reader arm for `GetSpellName`), Lifecycle (`core/LifecycleSetup.lua`), Bus (`core/Constants.lua`,
  `Catalog` only), Schema (`settings/Schema.lua`, runtime-completing stub), Pool, Item, Media, Widgets, DebugLog, Slash,
  Launcher (no stub — decision written at `core/LauncherSetup.lua` and `docs/ARCHITECTURE.md:64`), Options. **Perf
  is carried in the payload but not wired** (ratified `performance-§12` exemption).
- **Stub coverage** (members the addon reaches vs the library-absent branch): Item (`LoadItem`, `QualityFromLink`,
  `QualityLabel`), Pool (`New`, `Acquire`, `ReleaseAll`), Lifecycle (`Set`, `Release`, `IsDown`, `Reevaluate`),
  Media/Env (functions defined on both branches) — **all answered**. Core/Widgets/Slash/DebugLog/Options/Bus/Compat/Schema
  are pinned by `tests/test_surface_parity.lua`; Env/Item/Media/Pool/Lifecycle are not (LH-68). The Options stub is
  load-completing by design and is not a finding.

### architecture
- `local _, NS = ...` / `local addonName, NS = ...` bootstrap; `AceAddon:NewAddon(NS, …)` in `core/LootHistory.lua:4`,
  `NS.Print` reclaimed from AceConsole at `:12`.
- Closed bus of **3** messages, declared once in `core/Constants.lua:191-209` through `LibKa0s-Bus-1.0`'s `Catalog`;
  PascalCase tails; each receiver on its own `NS.NewBusTarget()`. Production call sites use `NS.MSG.*`; **nine test
  call sites type the literal** (LH-66).
- Schema-as-single-source through `LibKa0s-Schema-1.0` (`Schema:Set` delegates to `NS.SchemaRuntime`); 17 rows on one
  page. Named non-setting state (`settings.window`, `savedView`, `minimap` less its `hide` row, `history` + repair
  bookkeeping) and the id-set registry (`NS.Filters`) are named with owners and writers in `docs/ARCHITECTURE.md:118-160`.
  The write-path grep found no unnamed writer.

### savedvariables
- One global `LootHistoryDB`, account-wide (`db.global`, no `profile` section). `schemaVersion = 1` in
  `defaults/Global.lua:13`; `NS:RunMigrations` (`core/Database.lua:125-138`) walks `MIGRATIONS` to `to = 8`. The default
  is **deliberately** held at 1 (comment at `defaults/Global.lua:8-12`) — see LH-75.

### options-ui
- Library instance `NS.Options` from `settings/OptionsSetup.lua`; landing page + one `General` subcategory drawn with the
  library's `O.TabStrip` — tabs **Master controls · Capture · AH Price · Interface · History · Filters**; Filters carries a
  secondary strip (`O.SubTabStrip`) in the scroll.
- Master controls composed by `O.MasterControls` with `testModePath`, `debugConsolePath` and `minimapPath` — the full
  canonical set (not frameless: two `SetMovable` frames). No color rows, no `disabledIf`, no LSM rows, no arrow
  reorder (the AH price cascade uses the shared `ReorderList`). No host page-level combat lock; the
  `SettingsPanel|HideUIPanel|ToggleGameMenu|OpenToCategory` grep returns only the `mainPanelName` string.
- Global reset: `Sl:ResetEverything` with the profile-less wording verbatim (`settings/Slash.lua:23`); the three-control
  divergence is a ratified row.

### standalone-windows / preview-mode / launcher
- History window and export modal: non-secure frames, `UISpecialFrames`, clamped, persisted geometry, skinned through
  `Core.ApplySkin`. Every close control reaches `NS.MakeCloseButton` (the one wrapper, `core/CoreSetup.lua:167-169`) via
  `B:MakeCloseButton` (`modules/Browser.lua:84-87`) — compliant. The resize grip draws a Blizzard texture where the
  catalog carries `resize` (LH-76).
- Test mode: session-only checkbox from the composer, `/lh test`, ended on `PLAYER_REGEN_DISABLED`, refused in combat.
- Launcher: one `LibKa0s-Launcher-1.0` object, `name = addonName`, `label = NS.BRAND` ("Ka0s Loot History"), icon = the
  128 logo, rung (a) left-click toggles the browser, right-click opens settings, left-click refused while disabled.
  `minimap.hide` row survives both resets (exempt from the row walk and carried across `wipeGlobal`).

### slash-commands (incl. §7 disabled state)
- `LibKa0s-Slash-1.0` minor 14 dispatcher over the host's positional `NS.COMMANDS` (16 verbs: show hide toggle config
  enable disable version get set list reset resetall debug test purge help). No `perf` verb (exemption).
- **Disabled state — measured, compliant.** One `LibKa0s-Lifecycle-1.0` latch (`core/LifecycleSetup.lua`), `disabled`
  hold from the stored `settings.enabled`, `perf` hold published. Registration census: every `RegisterEvent`,
  `RegisterUnitEvent` and `RegisterMessage` in authored Lua has its undo (`UnregisterAllEvents` in `NS.StandDown`,
  `Attribution:Disable` by name + the unit frame, `Collector:Disable`, `Browser:Disable`, `Analytics:Disable`); timers go
  through `NS.After` and are canceled by `NS.CancelDeferrals`; the five hooks are `hooksecurefunc` gated at
  `Attribution:Stamp`. The panel's own refresh subscriptions survive (recorded-not-ruled, not filed).
  `tests/test_disabled.lua` exists, is in the suite list, asserts on the recording mock's registration set and carries
  `-- red under:` comments on steps 3, 6 and 10. The surface keeps every reserved verb live; feature verbs refuse on the
  library's one-line refusal. **No survivor found.**

### localization
- `NS.L` with key-returning metatable; `enUS.lua` only; English-only is a ratified register row. The kit's
  `localization-§5` gate (`tests/_kit/test_prose.lua`) is wired by path and green — no British spelling in authored text.
- The deconstruct fallback compares cast names against localized names derived from seed spell IDs (LH-74).

### events-frames-taint
- AceEvent for ordinary traffic; the one private frame is Attribution's `UNIT_SPELLCAST_SUCCEEDED` / `player`
  filter, held on the module, unregistered in `Disable`, reused — inside the carve-out.
- **No registration block is isolated per event**, and no rejected-name record exists (LH-64).
- `B:VisibilityAllows` reads `InCombatLockdown()` for a purely visual decision (LH-65).
- Secret-safe printer from `LibKa0s-Core-1.0`; no raw global `print()` for user output.

### compat / public-api
- `core/Compat.lua` (419 lines, **21** shims by `documentation-§3`'s grep); `Compat.GetSpellName` routed through
  `LibKa0s-Compat-1.0`. Third-party pricing shims live in `modules/AuctionPrice.lua` by recorded reasoning. No public API.

### debug-logging
- `LibKa0s-DebugLog-1.0` instance with `name` and `addonName` both = folder, `font = NS.Constants.FONT_MONO`, thin
  call-time forwarders for `print` / `safeToString`, session-only flag in `NS.State.debug`.

### packaging
- `.pkgmeta` ignore list passes (a), (b) and (c): the only unaccounted root dot-entry is `.git`. It cites the standard
  as `packaging.md:28` (LH-67).

### line-endings
- `.gitattributes` present, `* text=auto eol=crlf`, `*.sh` and `*.py` carve-outs, 23 `binary` marks; the first 84
  lines are **byte-identical** to `line-endings-§5`'s client-bound body, nothing below it. **(e) = 0** tracked files
  disagree with the pin. `tests/_kit/test_eol.lua` wired and green. `run-automated-tests.sh` recorded `100755`.

### lint
- `luacheck .` → **0 warnings / 0 errors in 65 files** (luacheck 1.2.0). `exclude_files` holds only vendored and frozen
  paths plus `tests/_kit/`; the harness global is in `files["tests/"]`; no `debugprofilestop` / `PerfDB` (exempt);
  per-file `212/self` ignores only.

### testing
- Vendored kit (LibKa0s v1.55.0 / test-kit revision 25) under `tests/_kit/`, thin `tests/wow_mock.lua` extender, runner
  derives the addon load list from the TOC and LibKa0s's list from its XML. **`lua tests/run.lua` → 858 passed, 0 failed,
  0 skipped.** `docs/test-cases.md` regenerates byte-for-byte (`--list` diff empty); README badge `858/858`.

### performance / automated-tests
- `performance-§12` exemption ratified (register row, issue #22). Zero `OnUpdate`, zero tickers in authored Lua.
- `lizard 1.24.0`, the standard's exact invocation → **16,326 NLOC, 2,200 functions, avg CCN 2.1, max CCN 15, 0
  warnings**. Newest bundle `20260916-184506` (commit `b267e38`, 35 commits behind HEAD, 7 days old): 15,349 NLOC,
  2,045 functions, max CCN 15, 0 warnings, 4 band files. **Drift:** no function crossed a threshold; two files newly
  entered the 1000–1500 band (`tests/test_schema.lua` 1048, `tests/test_slash.lua` 1020); Analytics 1178→1200, Browser
  1244→1271, Panel 1062→1107. RESULTS.md rows pre-date the commit-cell rule (kit 25 arrived after the last run) — unknown,
  not a finding. The watch list's Analytics entry still reads *peel next* with nothing tracking it (LH-52). The runner
  records the perf skip under the wrong sanctioned reason (LH-69).

### documentation
- Root: `README.md`, stub `CLAUDE.md`, `DEPENDENCIES.md`, `LICENSE`; no `CHANGELOG.md`, no `TODO.md`.
- README: H1, five badges in order (bare standard badge, `Midnight_12.1.0` matches the TOC, `858/858` matches the run),
  no logo image, no library inventory, no angle-bracket placeholders; canonical section order. Usage's closing
  paragraph is not a one-line signpost (LH-71).
- `CLAUDE.md` carries every mandated part, but the provenance section precedes the green-gate line (LH-72).
- `docs/` trio present; Tier 1 six present under canonical names; Tier 2 accounted for (slash-dispatch 16 verbs,
  midnight-quirks, compat-layer 21 shims, message-bus present below threshold, profiles/debug/perf-analysis *Not
  applicable*); `## Documentation map` has the four tables and reconciles both ways against the tree (18 `.md` files,
  every one registered; the only rows with no file are the three *Not applicable* rows). No non-canonical Tier 1/2 names,
  no retired docs, no `docs/perf-runs/`, no `docs/pending/`.
- **Hub shape:** `docs/ARCHITECTURE.md` is **554** lines; *Settings schema* is **68** lines (LH-60).
- `docs/performance.md` is 190 lines for an exempt addon (LH-70). Doc citations drifted in `DEPENDENCIES.md` and
  `docs/ARCHITECTURE.md` (LH-73).

### audit-review-history
- Frozen stores `docs/audits/` (6 prior runs), `docs/reviews/` (4), `docs/revendor/` (8 bundles), `docs/automated-tests/`
  (11 runs + README + RESULTS). No README over the three frozen stores.
- **Re-vendor ledger:** 31 distinct tags vendored by commits touching `libs/LibKa0s/` since the store's horizon
  (2026-08-25); **25** have no bundle naming them and no register row (LH-62).
- Issue store: 31 issues, every one carries a `state:` and a `severity:` label, no `[status]` prefix; read with
  `gh issue list --json` (no GraphQL).

## The deviation register — read first

Five rows in `docs/ARCHITECTURE.md:482-488`, each re-checked against v2.64.0 and the tree:

| Rule | Decided | Evidence ids | Trigger evaluated against the tree | Status |
|---|---|---|---|---|
| `architecture-§5` (auction.priority cascade) | 2026-07-17 | `schema.md` note | No schema row for `settings.auction.priority` (only a comment, `settings/Schema.lua:385`). **Not fired.** | **Accepted** |
| `performance-§12` | 2026-08-05 | #22 (closed, `state:will-not-do`) resolves | No `SetScript("OnUpdate"`, no ticker, no `ScheduleRepeatingTimer` in authored Lua. **Not fired.** | **Accepted** |
| `options-ui-§12` (three resets) | 2026-09-02 | — | Maintainer has not ruled; §12 unchanged in substance. **Not fired.** | **Accepted** |
| `options-ui-§1` (inverted set pickers) | 2026-08-01 | #20 resolves | v1.55.0's Options publishes no multi-check/set maker with a parent (`O.ChoiceGrid` is a one-choice matrix). **Not fired.** | **Accepted** |
| `localization-§1` (English only) | 2026-09-08 | `LH-48` resolves in `docs/audits/2026-09-07/` | `locales/` holds only `enUS.lua`. **Not fired.** | **Accepted** |

No row cites a rule the standard has since changed. Every issue id (#19, #20, #21, #22, #25, #26, #30) and bundle id
(`LH-47`, `LH-48`, `LH-54`) resolves. Every `state:will-not-do` issue (#18 feature, #19, #20, #21, #22, #29) is covered by
a row, a retirement paragraph, or is a declined feature rather than a declined rule. **Two new departures from a MUST are
reasoned only in code comments with no row** — LH-74 and LH-75 — and one more is LH-76.

## Prior run (`docs/audits/2026-09-08/`) — status

| ID | Status now |
|---|---|
| LH-52 | **Open, carried.** Analytics *peel next*, no issue. |
| LH-55 | **Closed.** The kit's prose gate is wired by path and green. |
| LH-56, LH-57 | **Open, carried.** Both TOC lines still bare (`LootHistory.toc:48`, `:56`). |
| LH-58 | **Open, carried** (dependent of LH-56). |
| LH-59 | Retired (unused). |
| LH-60 | **Open, carried and grown**: 458 → 554 lines, and *Settings schema* now past the ~60-line spill threshold. Issue #31 was closed `state:done` at 490 lines; the hub has regrown since. |
| LH-61 | **Closed.** `packaging` now makes `.claude` conditional; check (c) prints nothing. |

## Non-findings, recorded so they are not re-filed

- `lock` / `unlock` verbs absent: a declined MAY (`slash-commands-§8`), owes no row.
- The panel's refresh subscriptions surviving a stand-down: recorded-not-ruled in `open-evolutions`.
- The Options stub being load-completing, the Schema stub being runtime-completing, the Compat reader arm, the Bus
  `Catalog`-only stub, and Launcher having no stub (reason written): all named shapes or written decisions.
- `B:MakeCloseButton` delegating to `NS.MakeCloseButton`: every close control still ends in the one wrapper with the
  folder name.
- Self-naming headers on 5 of 30 source files: `documentation-§9` is a SHOULD adopted going forward; existing files are
  grandfathered.
- The playbook's own tension: `AUDIT.md` step 4 fixes the re-vendor-ledger finding at **High** while step 5's impact
  table would grade any doc-only gap Low. This bundle follows step 4's explicit grade for LH-62 and says so in the row.
