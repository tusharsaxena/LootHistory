# 01 — Current State

**Addon:** Ka0s Loot History (`LootHistory`)
**Audit date:** 2026-07-12
**Standard audited against:** Ka0s WoW Addon Standard **v1.0.0 (2026-07-12)** — `standards/01_STANDARD.md` @ `github.com/tusharsaxena/WowAddonStandards`
**Playbook:** `AUDIT.md` (same repo)
**Mode:** read-only. No addon source was modified; only this `audit/2026-07-12/` bundle was written.
**Deviation prefix:** `LH-` (first audit — prefix assigned here, reuse on re-audit).

Version stamps are consistent across surfaces: TOC `## Version: 1.0.0`, `NS.version = "1.0.0"` (`core/Namespace.lua:5`), README Version History `1.0.0`. Green gate at audit time: `luacheck .` = **0 warnings / 0 errors** (18 files); `lua tests/run.lua` = **118 passed, 0 failed**.

---

## Layout & tier

Tier **2 (modular)**, declared in `CLAUDE.md`. Source tree matches the Tier-2 shape:

```
core/      Compat, Constants, Namespace, State, Util, LootHistory, Database
defaults/  Global.lua
locales/   enUS.lua
settings/  Schema, Slash, Panel
modules/   Attribution, Collector, Browser, BrowserTable, Analytics, DebugLog
libs/      LibStub, CallbackHandler-1.0, Ace{Addon,DB,Event,Timer,Console,GUI}-3.0,
           LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0  (all vendored + committed)
media/     fonts/ (JetBrainsMono + OFL.txt), logo/, screenshots/
tests/     run.lua, loader.lua, wow_mock.lua, 8 test_*.lua suites
docs/      REQUIREMENTS, TECHNICAL_DESIGN, UX_DESIGN, EXECUTION_PLAN, superpowers/
```

- LOC: largest source files `modules/Browser.lua` (1016), `modules/BrowserTable.lua` (961), `modules/Analytics.lua` (806). All under the 1500 cap; Browser sits in the 1000–1500 "on notice" band (§1.2) — noted, not a deviation.
- Casing: subfolders lowercase, Lua files PascalCase, `libs/` lowercase — compliant (§1.3).
- **Media subfolder is `media/logo/` (singular)** where the standard specifies the typed `media/logos/` (§1.4, §6.5). See LH-04.
- **Root ships more than the mandated three docs.** Standard §15 requires root = README.md + stub CLAUDE.md + LICENSE only. This root additionally carries `ARCHITECTURE.md` (belongs under `docs/`, §15.3 → LH-03) and `TODO.md` (banned in a released addon, §15.4 → LH-01); and `CLAUDE.md` is the **full** agent brief rather than a stub (§15.2 → LH-02).

## TOC (`LootHistory.toc`)

Present fields, in order: Interface `120007`, Title `Ka0s Loot History`, Notes, Author `add1kted2ka0s`, Version `1.0.0`, IconTexture, SavedVariables `LootHistoryDB`, DefaultState `enabled`, Category-enUS `Bags & Inventory`, X-License `MIT`. File listing is grouped under `# Libraries`, `# core`, `# defaults + locales`, `# settings`, `# modules`.

- Single Interface line, latest Retail (`120007`) — compliant (§2.3). `X-License: MIT` present (§2.1).
- **Missing MUST fields:** `X-Standard`, and — since the addon is **published** (README CurseForge badge, project `1530802`) — `X-Curse-Project-ID` and `X-Wago-ID`. `OptionalDeps` absent; `Category-enUS` value is outside the standard's set. See LH-05.
- **File-listing section comments** are non-canonical vs §2.5's `# Libraries → # Locales → # Core → # Defaults → # Modules → # Settings`. See LH-06. (Note: the *load order* itself — defaults → locales → settings → modules — follows §1.2's explicit MUST; §1.2 and §2.5 disagree on module-vs-settings ordering, so LH-06 is scoped to the section-comment structure only.)

## Libraries & packaging

- All 11 libs vendored under `libs/` and committed; loaded first in the TOC via each lib's `.xml`/`.lua` (§3.1, §3.3) — compliant.
- `.pkgmeta` (`package-as: LootHistory`, no `externals:`) — compliant (§13), **but the ignore list omits `audit/`** (§13 MUST). `.luacheckrc` `exclude_files` also omits `audit/` (§14). See LH-12.
- No suite dependencies; no forked Ace libs — compliant (§3.5, §3.6).

## Architecture & patterns

- Namespace bootstrap `local addonName, NS = ...` in every file; no `_G[addonName]` (§4.1) — compliant. AceAddon promotes NS (`core/LootHistory.lua:4`, §4.2) — compliant.
- **Closed message bus** `Ka0s_LootHistory_{RecordAdded,HistoryChanged,SettingsChanged}`, one sender each; every *receiver* registers on its own `NS.NewBusTarget()` embed (Browser/Collector/Panel), never the shared bus-as-self (§4.4, AP32) — compliant, and the test bus mock keys by `(message,target)` and fans out (§4.4, AP33; `tests/wow_mock.lua:90-108`) — compliant.
- **Schema-as-single-source** (`settings/Schema.lua`): one row per setting drives AceDB defaults, panel widgets, and slash get/set/list/reset; every mutation routes through `Schema:Set` (validate → deepcopy → write → onChange) (§4.5) — compliant. Window geometry / saved view are the documented §6A carve-out.
- Hot-path upvalue cache in the collector, refreshed on `SettingsChanged` (§9.7) — compliant.

## SavedVariables / AceDB

- Single global `LootHistoryDB`; account-wide `.global` holds history + settings; `schemaVersion = 1` declared in `defaults/Global.lua:9` (§5.1) — compliant.
- **No migration runner.** `core/Database.lua` ships `InitDB` but no `RunMigrations`; §2.2/§5.1 require one even with an empty body. See LH-07.

## Options UI (§6 / §6A / §6B)

- Settings panel uses `Settings.RegisterCanvasLayoutCategory` + subcategory, registered eagerly in `OnInitialize`, raw AceGUI body built lazily in `OnShow`, combat-gated open (§6.1, §6.2, §6.5) — compliant. Landing page (logo + tagline + slash list) and two-column schema render present.
- **§6.10 always-visible scrollbar** is not implemented — the AceGUI `ScrollFrame` uses stock behavior that auto-hides the bar on short pages. See LH-08.
- **§6.6/§6.8 paired action buttons** (Reset All, Purge) use `SetRelativeWidth(0.5)` rather than `BUTTON_PAIR_REL` (0.492); the constant is not defined. See LH-09.
- Standalone **browser window** (`modules/Browser.lua`) is §6A's reference pattern: non-secure `CreateFrame`, `UISpecialFrames`, persisted position/size/scale, `SKIN`/`ApplySkin` seam, lazy per-tab build, pooled rows (§6A) — compliant. Preview/test mode via `/lh test` (§6B) — compliant.

## Slash, localization, debug, compat

- AceConsole `/lh` + `/loothistory`; schema + `NS.COMMANDS`-driven dispatch; bare `/lh` prints the generated help; unknown verb prints error + help; shared `NS.PREFIX` tag (§7) — compliant.
- `NS.L` metatable-fallback locale; enUS ships (strings currently hardcoded English, seam in place) (§8) — compliant.
- Debug console `modules/DebugLog.lua`: DIALOG-strata window, shipped JetBrains Mono, two pure formatters, session-only `NS.State.debug`, single `SetEnabled` seam, Copy/Clear (§12) — compliant.
- Compat firewall present; deprecated APIs shimmed. **However `core/Compat.lua:6-7` branch on `WOW_PROJECT_ID` for game flavor (`IsRetail`/`IsClassic`)**, forbidden in a Retail-only addon (§2.3, §11, AP9). See LH-10.

## Tests & docs

- Headless harness present and green (§14A) — compliant.
- ARCHITECTURE content exists (message bus, schema, slash documented) but the file is at root, not `docs/` (LH-03). README follows the canonical section order (§15.1) but **lacks the Ka0s Standard badge/link** (LH-11) and carries an unresolved repo-slug TODO comment.
