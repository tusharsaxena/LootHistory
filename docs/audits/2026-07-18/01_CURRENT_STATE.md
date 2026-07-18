# 01 — Current State

**Addon:** Ka0s Loot History
**Audit date:** 2026-07-18
**Audited against:** **Ka0s WoW Addon Standard v2.8.0 (2026-07-18)** — resolved live from
`https://github.com/tusharsaxena/WowAddonStandards` (`AUDIT.md` playbook + `standards/STANDARDS.md`
index and every section file it links). The retired global `§N.M` notation is gone; findings cite
sections in the current `filename-§N` form.
**Prior audit:** `docs/audits/2026-07-12/` (against v1.0.0) — all 12 deviations `LH-01…LH-12`
were remediated and independently re-verified closed (see that run's `06_EXECUTION_OUTCOME.md`).
This run re-checks them and measures against the current, evolved standard.

This is a **read-only** snapshot. No addon code, TOC, config, or asset was modified.

---

## Verification gate (run this session, read-only)

- **Unit tests:** `lua tests/run.lua` → **224 passed, 0 failed, 224 total**.
- **Lint:** `luacheck .` → **0 warnings / 0 errors in 20 files**.
- **Test inventory:** `docs/test-cases.md` grand total **224**; README `[tests]` badge reads
  **224/224** — in lockstep (testing-§5). Badge is honest.

---

## Section-by-section snapshot

### layout
Modular layout present and correct: `core/`, `defaults/`, `settings/`, `locales/`, `modules/`,
`libs/`, `media/` (typed subfolders `logos/`, `fonts/`, `screenshots/`), `tests/`, `docs/`.
No loose source at root. Load order in the TOC follows layout-§1 (`core → defaults → locales →
settings → modules`). Largest source file `modules/Browser.lua` = 1218 LOC (within the 1500 cap;
`modules/BrowserTable.lua` 1014, `modules/Analytics.lua` 763 — all under cap). Casing correct
(`libs/` lowercase, PascalCase `.lua`). Media in typed subfolders (`media/logos/`, `media/fonts/`).

### toc-file
`LootHistory.toc` metadata block is in the exact required field order (Interface → Title → Notes →
Author → Version → IconTexture → SavedVariables → OptionalDeps → DefaultState → Category-enUS →
X-License → X-Standard → X-Curse-Project-ID). Single `## Interface: 120007`. `X-License: MIT`,
`X-Standard` present, `X-Curse-Project-ID: 1607560` present; `X-Wago-ID`/`X-WoWI-ID` correctly
**omitted** (now MAY under v2.8.0 — not listed on those platforms). Libraries listed directly in the
TOC (each lib's own `.xml`), no `embeds.xml`. **Gap:** the `#`-section *order* of the file listing
(`Libraries → Core → Defaults → Locales → Settings → Modules`) does not match toc-file-§5's mandated
`Libraries → Locales → Core → Defaults → Modules → Settings` — see LH-13 (note: this conflicts with
layout-§1's load order, which the TOC *does* follow).

### library-stack
All eight mandatory Ace3 libs vendored under `libs/` and committed, plus LibSharedMedia-3.0,
LibDataBroker-1.1, LibDBIcon-1.0. Folder-per-lib layout, loaded first in the TOC. No `externals:`.
No Ace-lib forks. No addon-suite dependency. `LibStub("X")` stashed on `NS` at load
(`core/LootHistory.lua`).

### architecture
Namespace bootstrap `local addonName, NS = ...` in every file; no `_G[addonName]` table.
AceAddon registered with `NS` as first arg (`core/LootHistory.lua:4`). Custom printer survives the
AceConsole embed — `NS.Print` is reclaimed from `NS.Util.print` right after `:NewAddon`
(`core/LootHistory.lua:13`). Closed message bus: exactly three `Ka0s_LootHistory_*` messages
(`RecordAdded`, `HistoryChanged`, `SettingsChanged`); Database is the sole sender; every consumer
registers on its own `NS.NewBusTarget()` embed (never the shared bus-as-self). Schema-as-single-source
present (`settings/Schema.lua`) driving AceDB defaults, panel widgets, slash dispatch, and reset,
with one `Schema:Set` write seam and boot validation.

### savedvariables
Single global `LootHistoryDB`; account-wide storage under `.global` (history + settings), no
per-character profiles. `schemaVersion` declared in `defaults/Global.lua` (currently 1 default; a
v1→v2 migration ships). `core/Database.lua:NS:RunMigrations()` runs at init before any history read.

### options-ui
Blizzard `Settings.RegisterCanvasLayoutCategory` + raw AceGUI; registered eagerly in
`OnInitialize`; bodies built lazily in first `OnShow`. Landing page (logo + tagline + Slash-Commands
list) + subcategories (`General`, `Filters`). Two-column schema render, AceGUI `Heading` section
headers, layout constants defined (not inline), always-shown inert scrollbar (`installAlwaysShownScrollbar`),
`BUTTON_PAIR_REL = 0.492` on paired action buttons. Defaults button is an AceGUI `Button`.
Panel refresh is in-place via a `refreshers` list; structural rebuilds are guarded on
`ctx.panel:IsShown()` (no anti-pattern #39). **Gaps:** combat-open notice text/colour is
non-canonical (LH-14); the `Filters` subcategory omits the top-right Defaults button (LH-18).

### standalone-windows
`LootHistoryWindow` is a plain non-secure `CreateFrame("Frame")` — movable, resizable,
`SetClampedToScreen(true)`, registered in `UISpecialFrames`. Position/size persisted in
`db.global.settings.window`; `windowScale` applied via `SetScale`. Tab strip with lazy per-tab
build. Shared `SKIN`/`ApplySkin` seam (stock Blizzard textures) reused by the debug console.
High-churn record list uses **pooled rows** (`BrowserTable:AcquireRow`/`ReleaseAllRows`). Explicit
`show`/`hide`/`toggle` verbs; bare `/lh` prints help.

### preview-mode
Not a positionable on-screen display — it's a data browser. The addon still ships `/lh test`, a
synthetic preview dataset routed through the same read path (`NS.State.testRecords`); cleared on
toggle-off. N/A-to-compliant.

### slash-commands
AceConsole `:RegisterChatCommand("lh"/"loothistory")`. Schema-driven dispatch over `NS.COMMANDS`
(no if/elseif chain). `version` verb prints `<tag> v<version>` from TOC metadata. Mandatory cyan
`NS.PREFIX = |cff00ffff[LH]|r`. Help generated from `NS.COMMANDS`; unknown verb prints
`unknown command '<verb>'` + help. `list`/`get`/`set` use the mandated colour scheme (green header,
azure `[group]`, gold key, white value) via shared `FormatKV`/`FormatSchemaValue`; no trailing
colons. Verb-only lower-casing preserves path case.

### localization
`locales/enUS.lua` exports `NS.L` with a metatable-fallback (returns key on miss). Game data is
matched on stable IDs/tokens only — `classFile` (2nd return of `UnitClass`), `npcID`/kind from
`UnitGUID`, `itemID`, `Enum.ItemClass.Questitem` (`ITEMCLASS_QUEST = 12`), localized loot
GlobalStrings (`LOOT_ITEM_SELF*`) compiled to patterns — never English display literals. Only
`enUS` ships (any other locale is opt-in).

### events-frames-taint
AceEvent for events. Options panel-open gated on `InCombatLockdown()`. Secret-safe seam
(`NS.IsConcatSafe`/`NS.SafeToString`) in `core/Util.lua`, routed through both the chat printer
(`NS.Print`) and the debug sink (`NS.Debug`); detector probes `table.concat`, not `..`. Object
pooling on the record list.

### public-api
Exposes no third-party API surface — rule is N/A (no `_G[addonName]` publish).

### compat
`core/Compat.lua` owns deprecated/varying API calls behind `C_*`/global presence guards. No
`WOW_PROJECT_ID` game-flavor branching anywhere in shipping code (only a test comment references the
token). LH-10 stays closed.

### debug-logging
On-screen console (`modules/DebugLog.lua`, `LootHistoryDebugWindow`, DIALOG strata, 700×344,
`UISpecialFrames`, reuses `ApplySkin`). Monospace JetBrains Mono (OFL) at 10pt on log + copy box
(sanctioned media exception). Timestamped/tagged/coloured lines via two pure formatters
(`FormatPlain`/`FormatColored`). Zero-alloc gated sink; secret-safe. `SetEnabled` seam: colour-coded
ON/OFF chat ack, console line at both transitions, `[Init]` session summary on enable. Session-only
`NS.State.debug`, never persisted. Coverage: `[Loot]`/`[Drop]`/`[Data]`/`[Prune]`/`[Migrate]`/
`[Set]`/`[Filters]`/`[UI]` traces; `[Set]` at the single write seam.

### packaging
`.pkgmeta` present, `package-as: LootHistory`, no `externals:`, ignores `.luacheckrc`/`.gitignore`/
`docs`/`tests`/`_dev`/`*.bak`. **Gap:** the root `tools/` directory (dev-only Python + `__pycache__`)
is not in the ignore list, so it would ship in the package — LH-16.

### lint
`.luacheckrc` present: `std = "lua51"`, `codes`, per-repo `read_globals`/`globals` with justified
extras. `luacheck .` clean. **Gap:** `exclude_files` omits `docs/audits/` and `docs/reviews/` from
the standard template list — LH-17 (functionally moot today, no `.lua` under `docs/`).

### testing
Headless Lua 5.1 harness (`tests/run.lua` + `loader.lua` + `wow_mock.lua`, 13 `test_*` suites).
Bus mock keys by target; AceAddon mock models the `:Print` embed. `--list` mode generates
`docs/test-cases.md`. Green gate honored (224/224, 0/0). TDD evident from prior remediation.

### documentation
Root ships `README.md` (player-facing, correct 5-badge row + canonical section order + `## How
attribution works`), stub `CLAUDE.md`, `LICENSE`. Canonical `docs/` quartet present
(`agent-context.md`, `ARCHITECTURE.md`, `testing.md`, `smoke-tests.md`) + required generated
`docs/test-cases.md` + many topic-detail docs. No `TODO.md`. Standards reference in all four places
(TOC, README badge, CLAUDE, agent-context). **Gaps:** the CLAUDE section is titled
`## Standards compliance` rather than the required `## Standards compliance (read first)` (LH-15);
code comments + CLAUDE cite retired global `§N.M` numbers instead of `filename-§N` (LH-19).

### audit-review-history
`docs/audits/2026-07-12/` retained (frozen); `docs/reviews/2026-07-11/` retained. This run writes a
new dated folder without touching the prior one. `docs/` ignored by `.pkgmeta`.

### versioning-git
Semver `1.1.0` in TOC and `NS.version`. Trunk-based (`master`), clean tree. `schemaVersion`
incremented for the v1→v2 migration. Nothing to flag.

### naming-cheatsheet
Conventions followed: PascalCase folder/files, lowercase subfolders, `NS` private namespace,
`LootHistoryDB`, `/lh` + `/loothistory`, `Ka0s_LootHistory_*` messages, snake_case dotted schema
paths, English-string locale keys, `NS.Util.print` printer convention.

### anti-patterns (#1–#39)
No occurrences of #1–#12, #16–#27, #29–#39 **except**: #28 (TOC file-listing section order — LH-13),
and a documentation-§6-adjacent nuance under #34 (CLAUDE section heading — LH-15). Everything else on
the do-not list is clean.

### open-evolutions
Informational; no addon action required.

---

## Verdict

**Minor deviations.** The addon is architecturally exemplary — bus, schema-as-single-source, secret-safe
printer, debug console, pooled data browser, options panel, and headless test harness are all fully
compliant, and all 12 prior deviations remain closed. The seven open items are TOC-ordering, one
options-panel copy string, one missing subcategory button, and packaging/lint/doc-hygiene nits — none
touch capture, storage, or the read path. One item (LH-13) is most likely a **standard-internal
contradiction** to resolve upstream rather than an addon defect.
