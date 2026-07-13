# 03 — Evidence

`file:line` citations backing every deviation in `02_DEVIATIONS.md`, plus key compliance evidence. Line numbers are as of the audited working tree (2026-07-12).

## Deviation evidence

### LH-01 — TODO.md in a released addon (§15.4 / AP27)
- `TODO.md` exists at repo root (84 lines) — addon is released at `1.0.0` (`LootHistory.toc:5`, `core/Namespace.lua:5`).
- Code references the file: `modules/Attribution.lua:29` — `-- (localization is a TODO — see TODO.md).`
- §15.4: "A **released** addon **MUST NOT** ship a `TODO.md` anywhere (root or `docs/`)."

### LH-02 — Root CLAUDE.md is the full brief, not a stub (§15.2 / AP26)
- `CLAUDE.md` is 139 lines of full agent context — opens `# CLAUDE.md — Ka0s Loot History` / "Agent context for this repo. Read this first…" with sections What-this-addon-is, Stack & tier, Layout, Conventions cheat-sheet, Data model, Git workflow, etc.
- §15.2: root `CLAUDE.md` "**A STUB** … **MUST NOT** carry the full agent brief at root — that lives in `docs/`."

### LH-03 — ARCHITECTURE.md at root instead of docs/ (§15.3)
- `ARCHITECTURE.md` present at repo root (239 lines); `docs/` contains REQUIREMENTS/TECHNICAL_DESIGN/UX_DESIGN/EXECUTION_PLAN but **no** `ARCHITECTURE.md`.
- §15: "Root of the repo ships exactly three docs (plus `LICENSE`)"; §15.3 lists `docs/ARCHITECTURE.md`.

### LH-04 — Logo under media/logo/ not media/logos/ (§1.4 / §6.5)
- Files on disk: `media/logo/loothistory.logo.tga`, `media/logo/loothistory.logo.jpg` (folder is singular `logo`).
- Path constant: `settings/Panel.lua:18` — `local LOGO_PATH = "Interface\\AddOns\\LootHistory\\media\\logo\\loothistory.logo.tga"`.
- §1.4: shipped media MUST live in typed subfolders — `media/logos/` for logo art. §6.5 names `media/logos/`.
- (Runtime `.tga` + editable `.jpg` beside it is correct per §6.5 — only the folder name deviates.)

### LH-05 — TOC missing required metadata fields (§2.1 / AP28)
- `LootHistory.toc:1-10` — full metadata block: Interface, Title, Notes, Author, Version, IconTexture, SavedVariables, DefaultState, `Category-enUS: Bags & Inventory`, `X-License: MIT`.
- **Absent:** `## OptionalDeps:`, `## X-Standard:`, `## X-Curse-Project-ID:`, `## X-Wago-ID:`.
- Published evidence (making Curse/Wago IDs MUST): `README.md:4` — `![CurseForge Version](https://img.shields.io/curseforge/v/1530802)`.
- §2.1: `X-Standard` MUST always; `X-Curse-Project-ID` + `X-Wago-ID` MUST once published; `Category-enUS` set is `<Combat|Group|Auction|Chat|UI|Misc>`.

### LH-06 — Non-canonical TOC file-listing sections (§2.5 / AP28)
- `LootHistory.toc:12,25,34,38,43` — section comments `# Libraries (vendored in libs/ — load first)`, `# core (Compat loads first)`, `# defaults + locales`, `# settings`, `# modules (Attribution before Collector)`.
- §2.5 requires `#` headers in the order **Libraries → Locales → Core → Defaults → Modules → Settings**. Locales is folded into defaults here and casing/wording differ.
- Note: §1.2's MUST load order (defaults → locales → settings → modules) *is* satisfied by the actual file order; §1.2 and §2.5 conflict on module-vs-settings order, so this finding is scoped to section-comment structure.

### LH-07 — No migration runner (§2.2 / §5.1)
- `defaults/Global.lua:9` declares `schemaVersion = 1`; the comment (`:6-8`) states "A migration runner is a post-release concern… When the first schema change ships, add a runner."
- `core/Database.lua:3-6` — `function NS:InitDB() NS.db = LibStub("AceDB-3.0"):New(...) end`; no `RunMigrations` anywhere (`grep RunMigrations` → 0 hits in source).
- §2.2 / §5.1: "MUST ship a `Database.lua` migration runner **even if the body is empty** — schema migration is a from-day-one concern."

### LH-08 — Scrollbar not forced visible/inert (§6.10 / AP30)
- `settings/Panel.lua:97-108` `ensureScroll` creates `AceGUI:Create("ScrollFrame")` with `SetLayout("List")` and anchors it; no `FixScroll` rebind or thumb park/disable follows.
- §6.10: the body `ScrollFrame` MUST keep its vertical scrollbar shown even when content fits (park thumb + disable), rebinding AceGUI's auto-hiding `FixScroll`.

### LH-09 — Paired action buttons at 0.5 not BUTTON_PAIR_REL (§6.6 / §6.8 / AP31)
- Reset All button: `settings/Panel.lua:381` — `btn:SetRelativeWidth(0.5)` (cell-filling action button paired beside Window scale).
- Purge history button: `settings/Panel.lua:259` — `purgeBtn:SetRelativeWidth(0.5)`.
- Layout-constants block `settings/Panel.lua:20-27` defines `PADDING_X/HEADER_*/LOGO_SIZE/ROW_VSPACER/SECTION_*` but **not** `BUTTON_PAIR_REL`.
- §6.6/§6.8: a 50/50 paired action button MUST inset to `BUTTON_PAIR_REL` (**0.492**) so the right button clears the ScrollFrame clip.

### LH-10 — WOW_PROJECT_ID game-flavor branching (§2.3 / §11 / AP9)
- `core/Compat.lua:5-7`:
  ```lua
  Compat.IsRetail  = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
  Compat.IsClassic = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC)
  ```
- Classic-flavor references in Compat comments, e.g. `core/Compat.lua:17-18` ("the challenge-mode API does not exist on Classic flavors").
- `.luacheckrc:23` whitelists `WOW_PROJECT_ID`, `WOW_PROJECT_MAINLINE`, `WOW_PROJECT_CLASSIC`.
- §11 / AP9: "MUST NOT branch on `WOW_PROJECT_ID` for game flavor (Retail only)." §2.3: single-flavor Retail; feature detection via API presence, not flavor.

### LH-11 — README missing standard badge + unresolved repo slug (§15.1 item 2)
- `README.md:3-5` — badge row has `[wow]`, CurseForge version, and `[license]` badges only; no Ka0s WoW Addon Standard badge/link.
- `README.md:123` — `…/loothistory/issues). <!-- TODO: confirm repo URL/slug -->`.
- §15.1 item 2: the badge row MUST include "a badge/line linking the **Ka0s WoW Addon Standard**".

### LH-12 — audit/ not excluded from packaging or lint (§13 / §14)
- `.pkgmeta:6-13` `ignore:` lists `.luacheckrc, .gitignore, reviews, docs, tests, _dev, *.bak` — **no `audit/`**. §13: "MUST ignore `audit/` … in the package".
- `.luacheckrc:4` — `exclude_files = { "libs/", "reviews/", "_dev/", "tests/" }` — **no `audit/`**. §14 template excludes `audit/`.

## Compliance evidence (spot-checked, no deviation)

- **Namespace / no global** (§4.1): every source begins `local addonName, NS = ...` (e.g. `core/Namespace.lua:1`); no `_G[addonName]` table created.
- **AceAddon promotes NS** (§4.2): `core/LootHistory.lua:4` `AceAddon:NewAddon(NS, addonName, "AceEvent-3.0","AceTimer-3.0","AceConsole-3.0")`.
- **Bus receivers on own targets** (§4.4 / AP32): `NS.NewBusTarget()` factory `core/LootHistory.lua:13-19`; consumers use it — `modules/Browser.lua:1010`, `modules/Collector.lua:105`, `settings/Panel.lua:288`. One sender per message.
- **Bus test mock models real dispatch** (§4.4 / AP33): `tests/wow_mock.lua:96-108` keys callbacks by `(event, target)` and fans `SendMessage` to every distinct target.
- **Schema single-source + single write seam** (§4.5): `settings/Schema.lua:10-64` rows; `Schema:Set` `:107-117` (validate → deepcopy → write → onChange); panel widgets and slash `CliSet` both call it (`settings/Panel.lua:137`, `settings/Slash.lua:97`).
- **§6A window**: `modules/Browser.lua:823` non-secure `CreateFrame`; `:917-919` `UISpecialFrames`; `:85-105` position/size persistence; `:940-942` scale; `:19-56` `SKIN`+`ApplySkin`; lazy per-tab build `:111-121`.
- **Slash** (§7): `settings/Slash.lua:39-41` AceConsole `/lh`+`/loothistory`; `:47-58` schema/COMMANDS dispatch, bare `/lh` → help, unknown verb → error+help; `NS.PREFIX` `core/Namespace.lua:9`.
- **Debug console** (§12): `modules/DebugLog.lua` — DIALOG strata `:32`, 700×344 `:30`, JetBrains Mono `:92`, pure formatters `:118-129`, session-only `SetEnabled` seam `:224-230`, Copy/Clear `:141-213`. Font shipped `media/fonts/JetBrainsMono-Regular.ttf` + `OFL.txt`, registered `core/LootHistory.lua:23`.
- **Compat firewall** (§11): deprecated/varying APIs shimmed in `core/Compat.lua` (GUID decode, item/spell/map info, mail header) — only the game-flavor flags (LH-10) violate.
- **Green gate** (§14A/§17): `luacheck .` = 0/0 (18 files); `lua tests/run.lua` = 118 passed / 0 failed, at audit time.
