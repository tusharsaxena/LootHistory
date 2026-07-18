# 03 — Evidence

Every deviation in `02_DEVIATIONS.md` and every material compliance claim in `01_CURRENT_STATE.md`
is backed here with `file:line` citations. Read-only; line numbers are as of this audit's tree.

---

## Deviations

### LH-13 — TOC file-listing section order (`toc-file-§5`, MUST, AP #28)

`LootHistory.toc` section comments, in file order:

- `LootHistory.toc:15` `# Libraries (vendored in libs/ — load first)`
- `LootHistory.toc:28` `# Core (Compat loads first)`
- `LootHistory.toc:37` `# Defaults`
- `LootHistory.toc:40` `# Locales`
- `LootHistory.toc:43` `# Settings`
- `LootHistory.toc:48` `# Modules (Attribution before Collector)`

Order = `Libraries → Core → Defaults → Locales → Settings → Modules`.
toc-file-§5 MUST: `Libraries → Locales → Core → Defaults → Modules → Settings` ("Libraries always
load first; settings last"). Mismatches: **Locales after Core** (§5 wants it before), **Settings
before Modules** (§5 wants Settings last).

**Standard-internal conflict:** `layout-§1` MUST states the load order is
`core/* → defaults/* → locales/* → settings/* → modules/*` — which the TOC follows exactly. So
toc-file-§5's section order and layout-§1's load order disagree, and no TOC can satisfy both. The
addon chose layout-§1's order.

### LH-14 — Combat panel-open notice not canonical/grey (`options-ui-§2`, MUST)

`settings/Panel.lua:639-647`:

```lua
function P:Open()
  if InCombatLockdown and InCombatLockdown() then
    print("Can't open settings in combat.")   -- :641 — non-canonical, not grey
    return
  end
  if Settings and Settings.OpenToCategory and mainCategoryID then
    Settings.OpenToCategory(mainCategoryID)
  end
end
```

The gate is inside the open function and refuses correctly (early `return`; no `OpenToCategory` call
under lockdown; no `PLAYER_REGEN_ENABLED` defer) — options-ui-§2 satisfied on behaviour. Only the
message fails: canonical text is `"cannot open settings during combat — Blizzard's category-switch is
protected"` and it MUST be a **grey** notice; the printed string is `"Can't open settings in combat."`
with no grey colour code (`print` = `NS.Print`, which prepends the cyan tag but does not colour the
body).

### LH-15 — CLAUDE.md standards section heading (`documentation-§2`/`-§6`, MUST, AP #34)

- `CLAUDE.md:11` `## Standards compliance` — required heading is `## Standards compliance (read first)`
  (documentation-§2 item 3; documentation-§6 item 3; AP #34).
- Substance present: `CLAUDE.md:14-22` carries the "living source of truth" statement and the
  **Deviation rule (MUST)** — stop and flag, user decides fix-here-vs-change-standard, record the
  resolution — matching the canonical wording in substance.

### LH-16 — `tools/` ships in the package (`packaging`, SHOULD)

- `.pkgmeta` `ignore:` list = `.luacheckrc`, `.gitignore`, `docs`, `tests`, `_dev`, `*.bak` (no
  `tools`). File: `.pkgmeta:6-12`.
- Dev-only tree exists: `tools/`, `tools/__pycache__/`, `tools/tests/`, `tools/tests/__pycache__/`
  (directory listing). Not ignored → packaged to players.

### LH-17 — lint `exclude_files` omits audit/review dirs (`lint`, SHOULD)

- `.luacheckrc:4` `exclude_files = { "libs/", "_dev/", "tests/" }`.
- Standard template (lint) = `{ "libs/", "docs/audits/", "docs/reviews/", "_dev/", "tests/" }`.
  Missing `docs/audits/` and `docs/reviews/`. (Moot today — no `.lua` under `docs/` — but off-template.)

### LH-18 — Filters subcategory has no Defaults button (`options-ui-§5`, SHOULD)

- `settings/Panel.lua:624` `local fctx = createPanel("LootHistoryFiltersPanel", "Filters", { defaultsButton = false })`.
- Contrast `settings/Panel.lua:594` (General): `{ defaultsButton = true }`, wired at `:596-598`.
- options-ui-§5 header rule: "(subcategories) a **Defaults** button top-right." The header builder
  only creates the button when `opts.defaultsButton` is set (`settings/Panel.lua:74-83`).

### LH-19 — Retired `§N.M` standard citations (`documentation-§5`, SHOULD)

Code comments citing the old global numbering (should be `filename-§N`):

- `core/Namespace.lua:7` `Ka0s standard §7.4`
- `core/Database.lua:9` `Ka0s Standard §2.2/§5.1`
- `modules/Collector.lua:8` `standard §9.7`
- `modules/Browser.lua:83` `§6A window geometry`
- `modules/Attribution.lua:15` `(standard §8)`
- `settings/Panel.lua:21` `WowAddonStandards §6.8`
- `settings/Panel.lua:30` `§6.6/§6.8`
- `settings/Panel.lua:31` `§6.10`
- `settings/Panel.lua:102` `Ka0s §6.10`
- `settings/Panel.lua:183` `§6.10`
- `settings/Panel.lua:213` `§6.6/§6.8`
- `settings/Slash.lua:74` `Ka0s standard §7.4`
- `settings/Slash.lua:90` `Ka0s standard §7.4`
- `CLAUDE.md:26` `per standard §15.2`
- `CLAUDE.md:58` `## Local verification (standard §14A)`

(Many other comments already use the new form, e.g. `core/Util.lua:127` `events-frames-taint-§8`,
`core/LootHistory.lua:13` `architecture-§2`, `settings/Slash.lua:84` `slash-commands-§5`.)

---

## Prior deviations — re-verified closed (`LH-01 … LH-12`)

- **LH-01** (no released `TODO.md`): `find . -iname TODO.md` → none. Closed.
- **LH-02** (CLAUDE stub): `CLAUDE.md` is a stub pointing into `docs/` (`CLAUDE.md:24-33`); full
  brief at `docs/agent-context.md`. Closed. *(New nit LH-15 is a heading-name refinement, not a regression.)*
- **LH-03** (ARCHITECTURE under docs): `docs/ARCHITECTURE.md` present; none at root. Closed.
- **LH-04** (typed logo folder): `media/logos/loothistory.logo.tga` exists; `LOGO_PATH` points at
  `media\logos\` (`settings/Panel.lua:19`). Closed.
- **LH-05** (TOC metadata): `LootHistory.toc:1-13` — full field set in order, `Category-enUS: Misc`,
  `X-Standard`, `X-Curse-Project-ID: 1607560`, `OptionalDeps` present. Closed.
- **LH-06** (canonical section comments): `LootHistory.toc:15,28,37,40,43,48` use the canonical
  comment *names* (Libraries/Core/Defaults/Locales/Settings/Modules). Closed. *(LH-13 is a separate,
  newly-measured concern about section **order** vs toc-file-§5, not the comment names LH-06 fixed.)*
- **LH-07** (migration runner): `core/Database.lua:13-28` `NS:RunMigrations()`, invoked from
  `InitDB` (`core/Database.lua:6`). Closed.
- **LH-08** (always-shown inert scrollbar): `settings/Panel.lua:109-172` `installAlwaysShownScrollbar`.
  Closed.
- **LH-09** (paired-button inset): `settings/Panel.lua:32` `BUTTON_PAIR_REL = 0.492`, applied via
  `makePairButton` (`:214-220`). Closed.
- **LH-10** (no game-flavor branch): `grep WOW_PROJECT` in shipping code → only a test comment
  (`tests/test_compat.lua:43`). Closed.
- **LH-11** (standard badge + repo slug): `README.md:6` standard badge; `README.md:138` Issues
  section resolved. Closed.
- **LH-12** (exclude audit dir from pkg/lint): `.pkgmeta` ignores `docs` (which now holds
  `docs/audits/`); lint still omits `docs/audits/` (now re-surfaced as the minor LH-17). Substantially
  closed; see LH-17.

---

## Compliance evidence (spot citations backing `01_CURRENT_STATE.md`)

- **AceConsole embed reclaim:** `core/LootHistory.lua:13`
  `if NS.Util and NS.Util.print then NS.Print = NS.Util.print end`.
- **Bus target factory (per-receiver):** `core/LootHistory.lua:20-26` `NS.NewBusTarget`; consumers at
  `modules/Collector.lua:125-128`, `settings/Panel.lua:375-383,515-522`.
- **One sender per message:** Database is the only `SendMessage` caller for `RecordAdded`
  (`core/Database.lua:74`), `HistoryChanged` (`core/Database.lua:315` via `fireHistoryChanged`);
  `SettingsChanged` sent only from schema `onChange` (`settings/Schema.lua:17,53,60,76`). `NS.Filters`
  routes its change through Database's emitter, not a new sender (`modules/Filters.lua:54`).
- **Schema single write seam:** `settings/Schema.lua:124-139` `S:Set` (validate → write → onChange);
  `[Set]` debug at `:134-136`.
- **Secret-safe seam:** `core/Util.lua:134-162` (`IsConcatSafe` probes `table.concat`; `SafeToString`;
  `NS.Print`); debug sink routes args through `SafeToString` at `modules/DebugLog.lua:271`.
- **Debug SetEnabled seam:** `modules/DebugLog.lua:231-248` — colour-coded ack (`:237`), console line
  both transitions (`:241`), `[Init]` summary on enable (`:246`).
- **Session-only debug flag:** `core/State.lua:15`; never in defaults (`defaults/Global.lua:29`).
- **Standalone window:** `modules/Browser.lua:968` `CreateFrame("Frame", "LootHistoryWindow", …)`,
  movable/resizable/clamped `:983-985`, `UISpecialFrames` `:1107-1108`, scale `:1104`.
- **Pooled rows:** `modules/BrowserTable.lua:573-575,701-707,858-887`.
- **Eager category / lazy body:** register in `OnInitialize` (`core/LootHistory.lua:32-34`);
  bodies built in `OnShow` (`settings/Panel.lua:583-588,600-620,627-635`).
- **Standards reference in 4 places:** TOC `LootHistory.toc:12`; README badge `README.md:6`; CLAUDE
  `CLAUDE.md:9,11`; agent-context `docs/agent-context.md:32,35`.
- **Badge honesty:** `lua tests/run.lua` → 224/224; `docs/test-cases.md` Totals = 224; `README.md:7`
  `Tests-224%2F224_passing`.
- **Lint clean:** `luacheck .` → 0/0 in 20 files.
