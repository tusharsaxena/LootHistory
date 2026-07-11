# Ka0s WoW Addon Standard (v1.1, 2026-07-11)

**Status:** Source of truth. All `04_DEVIATIONS.md` audits and `05_NEW_ADDON_CONTEXT.md` template content derive from this document. When the standard changes, bump the date and version at the top.

**Changelog**

- **v1.1 (2026-07-11):** Reversed the library-embedding rule. Ka0s addons now **vendor all libraries in `libs/` and commit them**; `.pkgmeta` `externals:` for libs is forbidden. Rationale: fully self-contained, offline-installable addons. Affects §3.1, §3.3, §6.3, §13, §19. (v1.0 mandated externals.)
- **v1.0 (2026-05-03):** Initial standard.

**Audience:** future Ka0s and any agent (human or LLM) authoring or maintaining a Ka0s addon.

**Substrate:** Ace3. The ecosystem and Ka0s collection are aligned on it; deviations from Ace3 are case-by-case and must be justified.

**License:** MIT. Hostile licenses (`All Rights Reserved`) are forbidden.

---

## 0. Reading this document

Each section uses these markers:

- **MUST** — non-negotiable; deviations are bugs.
- **SHOULD** — strongly preferred; deviations require a comment in code explaining why.
- **MAY** — optional; pick when it fits.
- **MUST NOT** / **SHOULD NOT** — forbidden patterns with cited reasons.

Where a Ka0s addon today already implements a rule well, it's named as the **reference implementation**. Where industry practice diverged, the industry source is cited.

---

## 1. Tiered layout

A Ka0s addon is in one of two tiers. **MUST** declare the tier in the addon's `CLAUDE.md` so reviewers know which rules to apply.

### 1.1 Tier 1 — Flat (≤8 source files)

For utility-class addons (current example: WhatGroup at 3 files, prettychat at ~10 files).

```
<AddonName>/
  <AddonName>.toc
  <AddonName>.lua          -- entry; AceAddon registration
  Settings.lua             -- schema + AceDB defaults + panel
  Locale.lua               -- L = setmetatable({}, {__index=function(_,k) return k end})
  Compat.lua               -- deprecated-API shims (only if needed)
  README.md
  CLAUDE.md
  ARCHITECTURE.md
  LICENSE                  -- MIT
  .luacheckrc
  .pkgmeta
  libs/                    -- vendored Ace3 + other libs, committed to git (§3.3)
  media/                   -- textures/sounds shipped with the addon
```

- **MUST** stay flat — no `core/`, `modules/` subfolders.
- **MUST** keep each file under 1500 LOC. If a file exceeds 1000, plan a peel.
- **MAY** peel a single oversized file into 2-3 sub-files in the same folder (e.g. `Settings_Schema.lua`, `Settings_Panel.lua`) — **MUST NOT** introduce subfolders.
- Promotion to Tier 2 is mandatory once source-file count would exceed 8 (excluding `libs/`, `media/`, `docs/`, `reviews/`).

### 1.2 Tier 2 — Modular (>8 files or any addon with multiple feature modules)

Reference implementation: **KickCD**.

```
<AddonName>/
  <AddonName>.toc          -- single file, multi-Interface line, lists all .lua in dependency order
  core/
    Compat.lua             -- deprecated-API shims; loaded FIRST
    Constants.lua          -- numeric constants, enum-like tables
    Namespace.lua          -- bootstrap: local addonName, NS = ...; sets up shared upvalues
    State.lua              -- mutable runtime state, message bus
    Util.lua               -- pure helpers
    <AddonName>.lua        -- AceAddon registration; promotes NS to AceAddon
    Database.lua           -- AceDB profile/global setup, migration runner
  defaults/
    Profile.lua            -- C = profile defaults table
    Global.lua             -- G = global defaults table (rare; only when needed)
    Spells.lua / Data*.lua -- per-flavor data tables (use *_Mainline.lua / *_Classic.lua suffix)
  settings/
    Schema.lua             -- one row per setting: {path, default, type, label, widget, validate, onChange}
    Panel.lua              -- Blizzard Settings.RegisterCanvasLayoutCategory + raw AceGUI render
    Slash.lua              -- AceConsole binding; reads Schema for get/set/list/reset
  locales/
    enUS.lua               -- canonical
    deDE.lua, frFR.lua, ... -- gated with `if GetLocale() ~= "deDE" then return end`
    PostLoad.lua           -- derived-key aliases (L[2806] = L[2706])
  modules/
    <Feature>.lua          -- one file per feature module; max ~1500 LOC each
    ...
  media/
  libs/                    -- vendored Ace3 + other libs, committed to git (§3.3)
  docs/
  reviews/<YYYY-MM-DD>/    -- audit history
  README.md
  CLAUDE.md
  ARCHITECTURE.md
  LICENSE
  .luacheckrc
  .pkgmeta
```

- **MUST** load order: `core/Compat.lua` → `core/Constants.lua` → `core/Namespace.lua` → other `core/*` → `defaults/*` → `locales/*` → `settings/*` → `modules/*`.
- **MUST** cap any single `.lua` file at 1500 LOC. ConsumableMaster's `SlashCommands.lua` (1257) is at the edge; KickCD's `IconGrid.lua` (1753) and WhatGroup's `WhatGroup_Settings.lua` (1056) violate this.

### 1.3 Casing

- Addon root folder: **PascalCase** matching the `## Title:` in TOC. (Fixes prettychat → PrettyChat.)
- Subfolders: **lowercase** (`core/`, `modules/`, `libs/`, `media/`, `defaults/`, `settings/`, `locales/`, `docs/`, `reviews/`). **MUST** use `libs/` lowercase. (Fixes prettychat's `Libs/`.)
- Lua files: **PascalCase.lua** (`Database.lua`, `IconGrid.lua`).
- Non-source folders that ship: lowercase.

---

## 2. TOC file

### 2.1 Required fields

```
## Interface: 120000, 120001, 120005     -- multi-flavor, comma+space separated
## Title: Ka0s <Human Name>              -- prefix every Ka0s addon
## Notes: <one-line user-facing description>
## Author: add1kted2ka0s
## Version: <semver>                     -- managed by version-bump skill
## SavedVariables: <Addon>DB             -- single global SV per addon
## OptionalDeps: Ace3, LibStub, CallbackHandler-1.0, LibSharedMedia-3.0
## DefaultState: enabled
## IconTexture: <fileID>                 -- optional but encouraged
## Category-enUS: <Combat|Group|Auction|Chat|UI|Misc>
## X-License: MIT
## X-Curse-Project-ID: <id>              -- mandatory if published
## X-Wago-ID: <id>                       -- mandatory if published
## X-WoWI-ID: <id>                       -- only if WoWI listing exists
```

- **MUST** have `X-License: MIT`. **MUST NOT** ship "All Rights Reserved".
- **MUST** have `X-Curse-Project-ID` and `X-Wago-ID` once an addon is published anywhere.
- **SHOULD NOT** declare hard `Dependencies`. Use `OptionalDeps` and shim missing libs with soft fallbacks (AbsorbTracker is the reference: AceDB-missing flat-table shim, LSM-missing Blizzard fallback constants).

### 2.2 SavedVariables naming

- **MUST** be `<Addon>DB`, single global. (`AbsorbTrackerDB`, `KickCDDB`, etc.) Already universal in the collection.
- **SHOULD NOT** use `SavedVariablesPerCharacter` unless the data is genuinely per-character (most Ka0s addons run profile-per-character via AceDB; that's enough).
- **MUST** declare a `schemaVersion` integer in defaults. **MUST** ship a `Database.lua` migration runner even if the body is empty — schema migration is a from-day-one concern.

### 2.3 Multi-flavor

- **MUST** ship a single TOC with a comma-separated multi-Interface line whenever possible. Per-flavor branching is data (TOC-included `Spells_Mainline.lua` vs `Spells_Classic.lua`) or runtime flags (`Compat.IsRetail`), not separate TOC files.
- **MUST NOT** use `if WOW_PROJECT_ID == ... then` ladders inline in feature code. Branch in `Compat.lua` and expose flags.

### 2.4 File listing

- **MUST** list `.lua` files in dependency-correct order. **MUST NOT** rely on alphabetical loading.
- **SHOULD NOT** use `embeds.xml` at Tier 1. Tier 2 **MAY** use a single `embeds.xml` if file count justifies it. ConsumableMaster's `embeds.xml` is the only current user; remove if it doesn't earn its keep.

---

## 3. Library stack

### 3.1 Mandatory libs (every Ace3 addon)

| Lib | Purpose | Embedded as |
|---|---|---|
| LibStub | lib registry | vendored |
| CallbackHandler-1.0 | Ace3 dependency | vendored |
| AceAddon-3.0 | addon + module lifecycle | vendored |
| AceDB-3.0 | profile / char / global SV | vendored |
| AceEvent-3.0 | event subscription | vendored |
| AceTimer-3.0 | timers | vendored |
| AceConsole-3.0 | slash registration | vendored |
| AceGUI-3.0 | options panel widgets | vendored |

All libraries are **vendored in `libs/` and committed** (§3.3).

### 3.2 Common optional libs

| Lib | When |
|---|---|
| LibSharedMedia-3.0 | any addon with user-facing fonts/textures/sounds |
| AceDBOptions-3.0 | only if Profiles sub-page is wired |
| AceConfig-3.0 / AceConfigDialog-3.0 | **only if** the addon ships a Profiles sub-page using AceDBOptions; otherwise the canonical pattern is Blizzard Settings + raw AceGUI |
| LibDualSpec-1.0 | spec-aware profile switching |
| LibSerialize | export/import |
| LibDeflate | export/import compression |
| LibDBIcon-1.0 | minimap LDB icon |

### 3.3 Vendoring over externals

Ka0s addons **MUST ship every library vendored in `libs/` and committed to git**. The addon must be fully self-contained — installable by copying the folder into `Interface/AddOns/` with no packager step required to obtain libraries.

- **MUST** vendor all Ace3 and third-party libs under `libs/` and commit them. **MUST NOT** use `.pkgmeta` `externals:` to fetch libraries.
- **MUST** use the standard folder-per-lib layout (`libs/AceAddon-3.0/AceAddon-3.0.xml`, `libs/LibStub/LibStub.lua`, …) and load libs **first** in the TOC — the lib's `.xml` where it ships one (it pulls the lib's `.lua` + any sub-files), the `.lua` otherwise.
- **SHOULD** copy the folder-per-lib set from an existing Ka0s addon (e.g. KickCD's `libs/`) so lib versions stay consistent across the suite. Pull libs the suite doesn't yet vendor (LibDataBroker-1.1, LibDBIcon-1.0, …) from a current retail install or the upstream release.
- **MUST** vendor only libs the addon actually `LibStub("X")` — vendor what you use, nothing more. Prune dead weight (e.g. AceConfig where only Profiles needs it; AceLocale/AceBucket/AceComm/AceHook/AceSerializer/AceTab where unloaded).
- **MAY** vendor an addon-private micro-lib (e.g. an 80-line `ObjectPoolMixin`) the same way.

### 3.4 Lib registry pattern

- **SHOULD** call `LibStub("X")` exactly once at addon load and stash on the addon's namespace: `NS.LSM = LibStub("LibSharedMedia-3.0")`. **SHOULD NOT** call `LibStub` from per-frame code.

### 3.5 Forking Ace libs is forbidden

- **MUST NOT** privately fork an Ace3 lib (ElvUI's `Ace3-ElvUI`, OmniCD's `LibOmniCDC` are anti-patterns). Block on every Ace3 update.
- **MUST** extend AceGUI via `AceGUI:RegisterWidgetType("Ka0s_X", ...)` if a custom widget is needed.

---

## 4. Architecture

### 4.1 Namespace bootstrap (both tiers)

Every file **MUST** start with:

```lua
local addonName, NS = ...
```

`NS` is a single shared private table populated by ordered TOC loading. `addonName` is a string constant. **MUST NOT** create a `_G[addonName]` table; if a public surface is needed, expose it via `NS.API.v1` (see §10).

Optional ergonomic alias for hot files:

```lua
local L = NS.L         -- locale
local C = NS.C         -- profile defaults / current values cache
local State = NS.State -- runtime state
```

### 4.2 AceAddon registration (Tier 2 / any addon using Ace3 lifecycle)

Reference: KickCD bootstrap-namespace promotion at `core/<AddonName>.lua`.

```lua
local addonName, NS = ...
local AceAddon = LibStub("AceAddon-3.0")
local addon = AceAddon:NewAddon(NS, addonName, "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
NS.addon = addon  -- keep NS reference; modules read state through NS, not _G
```

- **MUST** pass the NS table as the first arg to `:NewAddon` (Ace3 supports this) so the bootstrap and AceAddon point at the same object.
- **SHOULD NOT** use AceAddon's per-module submodule pattern (`addon:NewModule("Foo")`) for fewer than ~10 feature modules. Direct `NS.Foo = NS.Foo or {}` per-module tables are lighter and equally testable.

### 4.3 Module pattern

```lua
local addonName, NS = ...
NS.IconGrid = NS.IconGrid or {}
local M = NS.IconGrid

function M:OnInitialize() ... end  -- only if registered as AceAddon submodule
function M:HandleSomething(...) ... end
```

- **MUST** publish modules via `NS.<Module> = NS.<Module> or {}` (idempotent) so file load order can be re-arranged without breakage.
- **SHOULD NOT** call into another module's table at file-load. Cross-module wiring happens after `PLAYER_LOGIN` or via the message bus.

### 4.4 Closed message bus (Tier 2)

Modules **MUST** communicate via named messages, not direct calls.

```lua
-- Producer (one per message)
NS.bus:SendMessage("Ka0s_<Addon>_RosterChanged", roster)

-- Consumer
NS.bus:RegisterMessage("Ka0s_<Addon>_RosterChanged", function(_, roster) ... end)
```

- **MUST** prefix every message `Ka0s_<Addon>_` to avoid collision.
- **MUST** document each message in `ARCHITECTURE.md` with: name, sender (one), payload schema, all consumers.
- **MUST NOT** have two senders for the same message.
- Implementation: AceEvent-3.0's `:SendMessage`/`:RegisterMessage` (already in the addon); no new lib needed.

### 4.5 Schema-as-single-source

The single most important Ka0s pattern. Already implemented well in AbsorbTracker, KickCD, ConsumableMaster, prettychat, WhatGroup. **MUST** be present in every addon with ≥3 user-visible settings.

```lua
NS.Schema = {
  { path = "display.scale",         default = 1.0,    type = "number",  min = 0.5, max = 2.0,
    label = "Scale", widget = "Slider", validate = function(v) ... end,
    onChange = function(v) NS.Display:UpdateScale(v) end },
  { path = "display.color",         default = {1,1,1,1}, type = "color",
    label = "Color", widget = "ColorPicker",
    onChange = function(v) NS.Display:UpdateColor(v) end },
  ...
}
```

- **MUST** drive all of: AceDB defaults, AceGUI panel widgets, `/<slash> get|set|list|reset` dispatch, defaults reset.
- **MUST** route every mutation through one helper: `NS.Schema:Set(path, value)` calls validate → write → onChange. Panel and slash both call this.
- **MUST** validate at boot: every schema row's `path` resolves against the defaults table; warn loudly on mismatch (AbsorbTracker reference: `Schema.lua:101-105`).

### 4.6 Two-phase init (only when needed)

For Tier 2 addons with ≥6 modules, **SHOULD** use ElvUI's two-phase pattern: an "initial" queue that runs before AceDB is ready (Compat shims, Constants), and a "regular" queue that runs after (`OnInitialize`/`OnEnable`).

### 4.7 DBM-style Prototype Registry (optional)

For Tier 2 addons where TOC ordering has been fragile (KickCD's pain point), **MAY** use a lazy table cache:

```lua
NS._prototypes = setmetatable({}, { __index = function(t, k) t[k] = {}; return t[k] end })
function NS:GetPrototype(name) return NS._prototypes[name] end
```

Producer files write methods onto `GetPrototype("Foo")`; consumers read methods off it. Either side can load first.

---

## 5. SavedVariables / AceDB

### 5.1 Structure

```lua
NS.defaults = {
  profile = { display = {...}, behavior = {...} },
  global  = { schemaVersion = 1, ignored = {} },
  char    = {},   -- only if genuinely per-character
}
local AceDB = LibStub("AceDB-3.0")
NS.db = AceDB:New("<Addon>DB", NS.defaults, true)   -- true = use current profile
```

- **MUST** keep one global namespace `<Addon>DB`.
- **MUST** declare `schemaVersion` in the global namespace and ship a migration function in `core/Database.lua`:

```lua
function NS:RunMigrations()
  local g = NS.db.global
  g.schemaVersion = g.schemaVersion or 1
  if g.schemaVersion < 2 then ... ; g.schemaVersion = 2 end
end
```

- **SHOULD** allow user to opt out via the soft-fallback path (AbsorbTracker's AceDB-missing shim). Not mandatory.

### 5.2 Defaults

- **MUST** declare in `defaults/Profile.lua` (Tier 2) or in `Settings.lua` (Tier 1).
- **MUST** be the **only** place a default value is hardcoded. Schema rows `default =` reference these constants if reused.

### 5.3 Per-zone profile trees (optional)

For party/group/raid/PvP context-aware addons (currently: KickCD), **SHOULD** consider OmniCD's per-zone profile model: `profile.party.arena`, `profile.party.party`, `profile.party.raid`, each carrying full settings.

---

## 6. Options UI

### 6.1 Canonical pattern

Already converged across all 5 Ka0s addons; codify:

```lua
-- settings/Panel.lua
local categoryID
function NS.Panel:Register()
  if categoryID then return end
  local frame = CreateFrame("Frame")
  frame.OnCommit = function() end
  frame.OnDefault = function() NS.Schema:ResetAll() end
  frame.OnRefresh = function() end
  local category = Settings.RegisterCanvasLayoutCategory(frame, addonName)
  category.ID = addonName
  Settings.RegisterAddOnCategory(category)
  categoryID = category:GetID()
  frame:SetScript("OnShow", function() NS.Panel:BuildBody(frame) end) -- lazy
end
```

- **MUST** use `Settings.RegisterCanvasLayoutCategory` for the entry point. **MUST NOT** use the deprecated `InterfaceOptions_AddCategory`.
- **MUST** render content with **raw AceGUI** inside the canvas. **MUST NOT** use AceConfigDialog for content. (Industry: BigWigs and WeakAuras use AceConfig but at a scale that justifies the tax; ElvUI/Plater/DBM hand-roll. Ka0s sits in the AceGUI sweet spot.)
- **MUST** build body lazily in first `OnShow`. (Universal Ka0s pattern; preserve it.)
- **MUST** wrap panel-build in `C_Timer.After(0, ...)` if the panel can be opened at file-load (WhatGroup taint-fix pattern).

### 6.2 Combat lockdown

- **MUST** check `InCombatLockdown()` before opening the options panel from slash; defer with `RegisterEvent("PLAYER_REGEN_ENABLED")` and one-shot replay.
- **SHOULD** apply the same gate to any settings setter that creates/destroys frames.

### 6.3 Profiles sub-page

- **MAY** ship a Profiles sub-category using AceDBOptions-3.0 + AceConfigDialog-3.0. **If included**, vendor AceConfig in `libs/` like every other lib (§3.3).
- **SHOULD** be the **only** legitimate use of AceConfig in a Ka0s addon.

### 6.4 Lazy options loading (large addons)

- For addons with ≥5 options sub-panels or whose options code is large, **SHOULD** ship options as a sibling LoadOnDemand addon (`<Addon>_Options.toc` with `## LoadOnDemand: 1`). None of the current 5 Ka0s addons need this.

---

## 7. Slash commands

### 7.1 Registration

- **MUST** use AceConsole-3.0 `:RegisterChatCommand`. (Currently zero of 5 Ka0s addons do this; all hand-roll `SLASH_*`. Migrate.)

```lua
addon:RegisterChatCommand("at", "OnSlash")
addon:RegisterChatCommand("absorbtracker", "OnSlash")
```

### 7.2 Verb naming

- **MUST** use 2-3 lowercase chars as the primary verb (`at`, `cm`, `kcd`, `pc`, `wg` already aligned). **SHOULD** also register the full lowercase addon name as an alias.
- **MUST NOT** collide with existing well-known addon slashes.

### 7.3 Dispatch

- **MUST** be schema-driven. Built-in subcommands `get`, `set`, `list`, `reset`, `resetall` walk `NS.Schema`. Custom verbs live in an ordered table:

```lua
NS.COMMANDS = {
  { name = "get",     desc = "Get a setting value",   fn = function(arg) ... end },
  { name = "set",     desc = "Set a setting value",   fn = function(arg) ... end },
  { name = "list",    desc = "List all settings",     fn = function() ... end },
  { name = "reset",   desc = "Reset one setting",     fn = function(arg) ... end },
  { name = "resetall", desc = "Reset all to defaults", fn = function() ... end },
  { name = "config",  desc = "Open options panel",    fn = function() NS.Panel:Open() end },
  { name = "debug",   desc = "Toggle debug logging",  fn = function() ... end },
}
```

- **MUST** render `/<slash>` (no args) as the help output, generated from this table — no hand-maintained help string.
- **MUST NOT** use `if arg == "foo" then elseif arg == "bar" then` chains (DBM anti-pattern).

---

## 8. Localization

### 8.1 Module shape

```lua
-- locales/enUS.lua  (loads always)
local addonName, NS = ...
NS.L = setmetatable({}, { __index = function(_, k) return k end })
local L = NS.L
L["Scale"] = "Scale"
L["Reset all settings to defaults?"] = "Reset all settings to defaults?"
```

```lua
-- locales/deDE.lua (locale-gated)
if GetLocale() ~= "deDE" then return end
local addonName, NS = ...
local L = NS.L
L["Scale"] = "Skalierung"
```

- **MUST** export `NS.L` with a metatable that returns the key on miss. Replaces AceLocale strict mode (which hard-errors on missing keys) and is industry-aligned (WeakAuras, OmniCD, KickCD, Plumber).
- **MAY** use AceLocale-3.0 in non-strict mode if you prefer it. Strict mode is forbidden.
- **MUST** gate non-enUS files with `if GetLocale() ~= "<locale>" then return end` at top of file. (Plumber anti-pattern: loading all locales for every player.)
- **SHOULD** put derived-key aliases in `locales/PostLoad.lua` (Plumber pattern): `L["Use original"] = L["Original"]`. Translators don't duplicate work.

### 8.2 Source-of-truth keys

- **MUST** use the English string itself as the key. Reasons: missing-key fallback yields English; keys are self-documenting; no separate string-table maintenance.
- **SHOULD NOT** use opaque IDs like `L.STR_42`.

### 8.3 Coverage

- **MUST** at minimum ship `enUS.lua`. Any additional locale is opt-in.
- **MUST NOT** rely on Blizzard `_G` strings as a substitute for a locale module. (Current WhatGroup pattern is acceptable for tiny addons but should still ship a locale module shell.)

---

## 9. Events, frames, taint

### 9.1 Event registration

- **MUST** use AceEvent-3.0 (`addon:RegisterEvent("X")`). **MUST NOT** create per-module frames just for events (DBM/Details!-scale hand-rolling is overkill below 1000 events/min).
- **SHOULD** centralize CLEU dispatch on a single shared frame with a spellID hash table when CLEU is the hot path. Reference: BigWigs `mod:Log(subevent, fn, spellId)`. **MUST NOT** subscribe N modules separately to CLEU.
- **MAY** use AceEvent's `:RegisterMessage`/`:SendMessage` for the closed message bus (§4.4).

### 9.2 Combat lockdown

- **MUST** guard secure-environment writes (frame `:SetAttribute`, secure-template parents, focus-frame mutations) with `InCombatLockdown()` returning early and replaying on `PLAYER_REGEN_ENABLED`.
- Reference implementations: WhatGroup 3-layer cascade (`runConfig`, `Settings.Register`, `ShowFrame`); prettychat combat-gated `OpenConfig`.

### 9.3 Taint-replacing Blizzard UI (Bagnon recipe)

If your addon replaces a Blizzard frame (bag UI, bag manager, group finder window):

- **MUST** `hooksecurefunc` on Toggle*. **MUST NOT** assign a replacement function to `_G.ToggleX`.
- **SHOULD** guard hooks with `debugstack():find("Manager")` to ignore Blizzard-internal recursion.
- **MUST** reparent hidden Blizzard frames to a hidden parent — **MUST NOT** call `:Hide()` on them (causes taint propagation).
- **MUST NOT** instantiate `MoneyFrame` directly; use `TooltipDataProcessor.AddLinePreCall` + `GetMoneyString()`.
- **SHOULD** ship a `core/TaintLess.xml` as the first XML include if XML is used.

### 9.4 Macro / protected-action APIs

If your addon writes macros or calls protected APIs (`CreateMacro`, `EditMacro`, `RunMacro`, `EditMacroByID`):

- **MUST** firewall: a single module is the **only** caller of those APIs. Reference: ConsumableMaster's `MacroManager.lua` is the sole caller of `CreateMacro`/`EditMacro`. Audit at lint time.
- **MUST NOT** call protected APIs from event handlers that can fire in combat.

### 9.5 Chat-frame manipulation

If your addon formats chat (currently: prettychat):

- **SHOULD** prefer overriding `_G[GLOBALSTRING]` (prettychat's pattern) over `ChatFrame_AddMessageEventFilter` and `hooksecurefunc(ChatFrame, "AddMessage")`.
- **MUST NOT** replace `AddMessage` outright — breaks every other chat addon.
- **MUST** make cross-registration ordering deterministic (prettychat current bug: `pairs()` over filters). Use an ordered table.

### 9.6 Frame creation

- **MUST** prefer Lua `CreateFrame` over XML for non-templated frames in Tier 1 addons.
- **MAY** use XML for declarative groups of similar widgets in Tier 2 (Auctionator's `Manifest.xml` pattern).
- **MUST** use object pooling for any high-churn UI (≥10 dynamic frames). Reference: OmniCD's ~80-line `ObjectPoolMixin` (Acquire/Release/HideAll). Roster churn becomes free.

### 9.7 Hot-path upvalue cache

For per-frame loops:

```lua
-- module locals refreshed on settings change
local DB_AURA_ENABLED, DB_USE_RANGE = false, false
function M:RefreshUpvalues()
  DB_AURA_ENABLED = NS.db.profile.auraEnabled
  DB_USE_RANGE   = NS.db.profile.useRange
end
-- in OnUpdate / OnEvent
if DB_AURA_ENABLED then ... end
```

- **MUST** call `M:RefreshUpvalues()` at end of every settings setter that touches values used in the hot path. Reference: Plater `RefreshDBUpvalues()`.

---

## 10. Public API surface

If your addon exposes any function or data for third-party consumption:

- **MUST** version-namespace it: `NS.API = NS.API or {}; NS.API.v1 = {...}`. Public consumers reference `MyAddon.API.v1.SomeFunction`.
- **MUST** publish via `_G[addonName] = NS.API` (only the API surface; not the whole NS).
- **MUST** document the v1 contract in `ARCHITECTURE.md` and treat it as semver-stable.
- **SHOULD NOT** break v1 even if the implementation changes; introduce v2 as a sibling table.
- Ka0s-internal addons currently expose nothing; this rule is for future addons that anchor to other UF addons (KickCD-class) or expose hooks.

---

## 11. Compat / deprecated APIs

Every addon **MUST** ship a `Compat.lua` (Tier 1) or `core/Compat.lua` (Tier 2). It is the **only** file that calls deprecated APIs and exposes shimmed versions.

```lua
local addonName, NS = ...
NS.Compat = NS.Compat or {}
local Compat = NS.Compat

Compat.IsRetail  = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
Compat.IsClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC

-- Spell info: post-11.x consolidation
function Compat.GetSpellInfo(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    if info then return info.name, nil, info.iconID end
  end
  return GetSpellInfo and GetSpellInfo(id)
end

-- Specialization: post-11.x deprecation
function Compat.GetSpecialization()
  return (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()) or GetSpecialization()
end
```

- **MUST** route every deprecated-API call through `Compat`. KickCD currently violates: direct `GetSpecialization`/`GetSpecializationInfo` at `modules/Cooldowns.lua:78-82` and `modules/IconGrid.lua:286-290`.

---

## 12. Debug / logging

Every addon **MUST** ship a debug seam. Reference: ConsumableMaster's `Debug.lua`.

```lua
NS.Debug = NS.Debug or {}
function NS.Debug:Print(fmt, ...)
  if not NS.db or not NS.db.global.debug then return end  -- gated; SV-persistent
  local msg = (select("#", ...) > 0) and string.format(fmt, ...) or fmt
  print("|cff33ff99" .. addonName .. "|r " .. msg)
end
```

- **MUST** gate via persistent SV flag (`NS.db.global.debug`). AbsorbTracker's in-memory-only `/at debug` is a deviation: resets every login.
- **MUST** be zero-allocation when off (the gate is the first line; no `string.format` until past the gate).
- **MUST** be toggleable via slash `/<addon> debug`.
- **MAY** support levels (`Debug:Print(level, fmt, ...)`) for large addons.

---

## 13. Packaging (`.pkgmeta`)

Every addon **MUST** ship `.pkgmeta` at the root for packager configuration (package name, ignore lists). Libraries are **vendored and committed** (§3.3), so `.pkgmeta` **MUST NOT** contain an `externals:` block.

Minimum template:

```yaml
package-as: <Addon>

# Libraries are vendored in libs/ and committed to git — NOT fetched as externals.

ignore:
  - .luacheckrc
  - reviews
  - docs/internal
  - _dev
  - "*.bak"
```

- **MUST** vendor and commit every library the addon uses (§3.3). **MUST NOT** declare `externals:`; **MUST** commit `libs/` to git as part of the addon.
- **MUST** ignore `reviews/`, `_dev/`, `docs/`, `tests/`, lockfiles in the package.
- **SHOULD** use `enable-toc-creation: yes` if you ship multiple flavors that need separate TOCs.
- **MAY** use `move-folders:` only when the repo is a monorepo for multiple addons (out of scope today; Bagnon-style future direction).

CI (GitHub Actions) is **explicitly out of scope for this standard** per Ka0s decision.

---

## 14. Lint (`.luacheckrc`)

Every addon **MUST** ship `.luacheckrc` at the root. Use the BigWigsMods snippet as the base:

```lua
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "libs/", "reviews/", "_dev/" }
ignore = {
  "212/self",   -- unused argument self
  "212/event",  -- unused argument event
}
read_globals = {
  "_G", "LibStub", "CreateFrame", "GetTime", "UnitName", "UnitGUID",
  "GetSpellInfo", "C_Spell", "C_SpecializationInfo", "GetSpecialization",
  "InCombatLockdown", "PlaySound", "GetLocale",
  "Settings", "InterfaceOptionsFrame_OpenToCategory",
  "C_Timer", "hooksecurefunc",
  "CreateColor",
  -- per-addon globals are added per-repo
}
globals = {
  "<Addon>DB",        -- per-repo
}
```

- **MUST** lint on every commit (locally or as a pre-commit hook).
- **MUST NOT** add `globals` (write access) without a comment justifying it.

---

## 15. Documentation set

Every addon **MUST** ship:

- `README.md` — user-facing. Sections in this order: Title, Badges, Description (1-2 paragraphs), Features (bullet list), Installation, Usage / Slash Commands (table), Configuration (high level), Version History (table, last 5 versions). Reference: any of the 5 current Ka0s READMEs.
- `LICENSE` — MIT, full text.
- `CLAUDE.md` — agent context. Sections: stack, layout tier, key files (with one-line purpose each), conventions cheat-sheet, current TODOs, "do not change without reason" notes.
- `ARCHITECTURE.md` — engineer context. Sections: Overview, Module Map, Settings Schema, Message Bus (named messages with sender/payload/consumers), Slash Commands (table from `NS.COMMANDS`), Event Subscriptions, Taint Notes, Known Limitations.

**MUST** keep all four in sync with code. Drift is the #1 gripe surfaced in every Ka0s `reviews/` folder. The `wow-addon:sync-docs` skill exists exactly for this; run it before every release.

---

## 16. Reviews / audit history

- **MUST** keep `reviews/<YYYY-MM-DD>/` folders for every audit. Five-artifact bundle: `01_FINDINGS.md`, `02_PROPOSED_CHANGES.md`, `03_SMOKE_TESTS.md`, `04_EXECUTION_PLAN.md`, `05_FINAL_SUMMARY.md`. The `wow-addon:review` skill produces this format.
- **SHOULD** retain every prior `reviews/` folder; they are the addon's institutional memory.

---

## 17. Versioning

- **MUST** use semver (`MAJOR.MINOR.PATCH`). MAJOR for backwards-incompatible API or SV changes; MINOR for new features; PATCH for fixes only.
- **MUST** bump in TOC `## Version:`, and in any code constants and README badges/Version History tables. The `wow-addon:version-bump` skill automates this.
- **MUST** increment `schemaVersion` (in defaults) whenever a SV migration is required.

---

## 18. Naming cheatsheet

| Thing | Convention | Example |
|---|---|---|
| Addon folder | PascalCase | `KickCD` |
| Subfolders | lowercase | `core/`, `modules/`, `libs/` |
| Lua files | PascalCase.lua | `IconGrid.lua` |
| Namespace upvalue | `NS` (private) | `local addonName, NS = ...` |
| Public API | `_G[addonName].API.v1` | `KickCD.API.v1` |
| SavedVariables | `<Addon>DB` | `KickCDDB` |
| Slash verbs | 2-3 lowercase | `/at`, `/kcd` |
| Bus messages | `Ka0s_<Addon>_<Event>` | `Ka0s_KickCD_RosterChanged` |
| AceConfig options key | snake_case dotted path | `display.scale` |
| Locale keys | English source string | `L["Reset all settings"]` |
| Module table | `NS.<PascalCase>` | `NS.IconGrid` |

---

## 19. Anti-patterns (forbidden)

For quick reference, the rules above as a do-not list:

1. `_G[addonName] = {}` (global namespace) — use private `NS`.
2. AceLocale strict mode — use metatable fallback.
3. Hand-rolled options framework — use Settings + AceGUI.
4. AceConfig for non-Profiles content — use raw AceGUI.
5. `SLASH_*` direct registration — use AceConsole.
6. `if cmd == "x" then elseif ...` slash dispatcher — use schema + COMMANDS table.
7. `.pkgmeta` `externals:` for libraries — vendor and commit all libs instead (§3.3).
8. Forking Ace libs — use `RegisterWidgetType` extension instead.
9. `if WOW_PROJECT_ID == ...` ladders inline — branch in Compat.
10. Direct calls to deprecated APIs — route through Compat.
11. `:Hide()` on Blizzard frames you replace — reparent to hidden parent.
12. Replacing `AddMessage` — override globals or use AddMessageEventFilter.
13. Hard `## Dependencies:` (use OptionalDeps + soft fallback).
14. `## X-License: All Rights Reserved` — must be MIT.
15. Per-flavor TOC duplication — use packager `enable-toc-creation`.
16. Files >1500 LOC — peel.
17. Multiple senders for the same bus message.
18. In-memory-only debug toggle — must persist in SV.
19. Cross-module direct table access — use the bus.
20. User-supplied Lua execution — banned at the standard level (no Ka0s addon needs it).

---

## 20. Open evolutions

Items recorded for future versions of this standard:

- **Ka0s-Core sibling addon.** Long-term: extract Schema runtime, AceGUI panel scaffold, slash dispatcher, Compat templates into a single `Ka0s-Core` addon (Bagnon's BagBrother model). Out of scope for v1.
- **Shared luacheckrc base.** A `Ka0s-luacheckrc.lua` symlinked into every addon.
- **Shared vendored libs.** Once monorepo'd, vendor each lib once at the repo root and share it across addons (Bagnon BagBrother model) rather than duplicating `libs/` per addon.
- **Multi-zone profile model adoption** for KickCD and any future group-context addon.
- **Object pool standard** packaged as a copyable micro-lib.

---

**End of standard. Authoritative as of 2026-05-03. Bump on amendment.**
