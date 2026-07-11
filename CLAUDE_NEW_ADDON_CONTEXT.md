# New Ka0s Addon — Context Pack (v1.0, 2026-05-03)

**Drop this file (or its contents) into the root of any new Ka0s addon as `CLAUDE.md` and you have a complete starter brief.** Self-contained — no external lookups required for an LLM or new contributor to scaffold a fully standards-compliant addon.

Authoritative reference: `WowAddonStandards/03_STANDARDS.md`. This document is its operational distillation.

---

## Identity

- **Author:** add1kted2ka0s (Ka0s)
- **License:** MIT (always; no exceptions)
- **Substrate:** Ace3
- **TOC `Title` prefix:** `Ka0s <Human Name>`
- **SavedVariables:** `<Addon>DB`
- **Slash:** 2-3 lowercase chars (`/at`, `/cm`, `/kcd`, `/pc`, `/wg`)
- **Folder name:** PascalCase = TOC Title's CamelCase form

## Pick a tier

- **Tier 1 (flat, ≤8 source files)** — utility addons. Reference: WhatGroup.
- **Tier 2 (modular)** — multi-feature addons. Reference: KickCD.

If unsure, start Tier 1; promote when file count would exceed 8. Tier 1 → Tier 2 promotion is mechanical (move files into `core/` `modules/` `defaults/` `settings/` `locales/`).

---

## Tier 1 starter tree

```
<Addon>/
  <Addon>.toc
  <Addon>.lua            -- entry, AceAddon registration, message bus init
  Settings.lua           -- Schema rows + AceDB defaults + panel registration + slash dispatch
  Locale.lua             -- L = setmetatable({}, {__index=function(_,k) return k end})
  Compat.lua             -- deprecated-API shims (start as empty scaffold)
  Database.lua           -- migration runner (start as empty function)
  README.md
  CLAUDE.md              -- this file's content
  ARCHITECTURE.md
  LICENSE                -- MIT full text
  .luacheckrc
  .pkgmeta
```

## Tier 2 starter tree

```
<Addon>/
  <Addon>.toc
  core/
    Compat.lua           -- LOAD FIRST
    Constants.lua
    Namespace.lua
    State.lua
    Util.lua
    <Addon>.lua          -- AceAddon registration; promotes NS to AceAddon
    Database.lua         -- AceDB + migration
  defaults/
    Profile.lua
    Global.lua           -- only if needed
  locales/
    enUS.lua             -- canonical
    PostLoad.lua         -- derived-key aliases
  settings/
    Schema.lua
    Panel.lua
    Slash.lua
  modules/
    <Feature>.lua
  media/
  README.md  CLAUDE.md  ARCHITECTURE.md  LICENSE
  .luacheckrc  .pkgmeta
```

---

## Starter snippets

### TOC

```
## Interface: 120000, 120001, 120005
## Title: Ka0s <Name>
## Notes: <one-line description>
## Author: add1kted2ka0s
## Version: 0.1.0
## SavedVariables: <Addon>DB
## OptionalDeps: Ace3, LibStub, CallbackHandler-1.0, LibSharedMedia-3.0
## DefaultState: enabled
## Category-enUS: <Combat|Group|Auction|Chat|UI|Misc>
## X-License: MIT
## X-Curse-Project-ID: <id>
## X-Wago-ID: <id>

# Tier 1: list files in dependency order
Compat.lua
Locale.lua
<Addon>.lua
Database.lua
Settings.lua
```

### `<Addon>.lua` (entry)

```lua
local addonName, NS = ...
local AceAddon = LibStub("AceAddon-3.0")
local addon = AceAddon:NewAddon(NS, addonName, "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
NS.addon = addon

function addon:OnInitialize()
  NS:InitDB()        -- Database.lua
  NS:RunMigrations() -- Database.lua
  NS.Settings:Register()
end

function addon:OnEnable()
  -- subscribe to events
  -- self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnter")
end
```

### `Compat.lua`

```lua
local addonName, NS = ...
NS.Compat = NS.Compat or {}
local Compat = NS.Compat

Compat.IsRetail  = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
Compat.IsClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC

function Compat.GetSpellInfo(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    if info then return info.name, nil, info.iconID end
  end
  return GetSpellInfo and GetSpellInfo(id)
end

function Compat.GetSpecialization()
  return (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()) or GetSpecialization()
end
```

### `Locale.lua`

```lua
local addonName, NS = ...
NS.L = setmetatable({}, { __index = function(_, k) return k end })
-- For non-enUS locales, gate at top of file:
-- if GetLocale() ~= "deDE" then return end
-- local L = NS.L
-- L["Scale"] = "Skalierung"
```

### `Database.lua`

```lua
local addonName, NS = ...

NS.defaults = {
  profile = { -- defaults referenced by Schema rows
  },
  global = { schemaVersion = 1 },
}

function NS:InitDB()
  NS.db = LibStub("AceDB-3.0"):New(addonName .. "DB", NS.defaults, true)
end

function NS:RunMigrations()
  local g = NS.db.global
  g.schemaVersion = g.schemaVersion or 1
  -- if g.schemaVersion < 2 then ... ; g.schemaVersion = 2 end
end
```

### `Settings.lua`

```lua
local addonName, NS = ...
NS.Settings = NS.Settings or {}
local S = NS.Settings

-- Schema: one row per setting. Drives panel widget, slash dispatch, and reset.
S.Schema = {
  { path = "display.scale", default = 1.0, type = "number", min = 0.5, max = 2.0,
    label = "Scale", widget = "Slider",
    onChange = function(v) NS:OnScaleChanged(v) end },
}

-- Single write seam. Panel and slash both call this.
function S:Set(path, value)
  local row = S:FindRow(path)
  if not row then return false, "unknown path: " .. path end
  if row.validate and not row.validate(value) then return false, "invalid value" end
  S:WritePath(NS.db.profile, path, value)
  if row.onChange then row.onChange(value) end
  return true
end

-- AceConsole binding
local COMMANDS = {
  { name = "config", desc = "Open options", fn = function() S:Open() end },
  { name = "set",    desc = "Set a value",  fn = function(arg) S:CliSet(arg) end },
  { name = "get",    desc = "Get a value",  fn = function(arg) S:CliGet(arg) end },
  { name = "list",   desc = "List all",     fn = function() S:CliList() end },
  { name = "reset",  desc = "Reset one",    fn = function(arg) S:CliReset(arg) end },
  { name = "resetall", desc = "Reset all",  fn = function() S:CliResetAll() end },
  { name = "debug",  desc = "Toggle debug", fn = function() NS.db.global.debug = not NS.db.global.debug end },
}
NS.COMMANDS = COMMANDS

function S:Register()
  NS.addon:RegisterChatCommand("at", "OnSlash") -- replace "at" with your verb
  -- Build the canvas-layout panel here; build body lazily on first OnShow.
end

function NS.addon:OnSlash(input)
  if input == nil or input == "" then return S:PrintHelp() end
  local verb, rest = input:match("^(%S+)%s*(.-)$")
  for _, cmd in ipairs(COMMANDS) do
    if cmd.name == verb then return cmd.fn(rest) end
  end
  S:PrintHelp()
end
```

### Debug

```lua
NS.Debug = NS.Debug or {}
function NS.Debug:Print(fmt, ...)
  if not NS.db or not NS.db.global.debug then return end
  local msg = (select("#", ...) > 0) and string.format(fmt, ...) or fmt
  print("|cff33ff99" .. addonName .. "|r " .. msg)
end
```

### Message bus

```lua
-- Producer (pick exactly one)
NS.addon:SendMessage("Ka0s_<Addon>_RosterChanged", roster)

-- Consumer
NS.addon:RegisterMessage("Ka0s_<Addon>_RosterChanged", function(_, roster) ... end)
```

### `.luacheckrc`

```lua
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "libs/", "reviews/", "_dev/" }
ignore = { "212/self", "212/event" }
read_globals = {
  "_G", "LibStub", "CreateFrame", "GetTime", "UnitName", "UnitGUID",
  "GetSpellInfo", "C_Spell", "C_SpecializationInfo", "GetSpecialization",
  "InCombatLockdown", "PlaySound", "GetLocale", "C_Timer", "hooksecurefunc",
  "Settings", "CreateColor",
}
globals = {
  "<Addon>DB",  -- the SavedVariables write target
}
```

### `.pkgmeta`

```yaml
package-as: <Addon>

externals:
  libs/LibStub:                 { url: https://repos.curseforge.com/wow/ace3/trunk/LibStub,                tag: latest }
  libs/CallbackHandler-1.0:     { url: https://repos.curseforge.com/wow/ace3/trunk/CallbackHandler-1.0,   tag: latest }
  libs/AceAddon-3.0:            { url: https://repos.curseforge.com/wow/ace3/trunk/AceAddon-3.0,          tag: latest }
  libs/AceDB-3.0:               { url: https://repos.curseforge.com/wow/ace3/trunk/AceDB-3.0,             tag: latest }
  libs/AceEvent-3.0:            { url: https://repos.curseforge.com/wow/ace3/trunk/AceEvent-3.0,          tag: latest }
  libs/AceTimer-3.0:            { url: https://repos.curseforge.com/wow/ace3/trunk/AceTimer-3.0,          tag: latest }
  libs/AceConsole-3.0:          { url: https://repos.curseforge.com/wow/ace3/trunk/AceConsole-3.0,        tag: latest }
  libs/AceGUI-3.0:              { url: https://repos.curseforge.com/wow/ace3/trunk/AceGUI-3.0,            tag: latest }
  libs/LibSharedMedia-3.0:      { url: https://repos.wowace.com/wow/libsharedmedia-3-0/trunk/LibSharedMedia-3.0, tag: latest }

ignore:
  - .luacheckrc
  - reviews
  - docs/internal
  - _dev
  - "*.bak"
```

(Remove libs you don't use; reference `03_STANDARDS.md §3.2`.)

---

## Hard rules cheat sheet (memorize)

1. Every file starts with `local addonName, NS = ...`. No `_G[addonName] = {}`.
2. SavedVariables: `<Addon>DB`, single global, with `schemaVersion`.
3. License: MIT.
4. Folder casing: `<Addon>/` PascalCase, all subfolders lowercase (`libs/` not `Libs/`).
5. TOC must include `X-Curse-Project-ID`, `X-Wago-ID` (mandatory if published).
6. Slash: AceConsole `:RegisterChatCommand`. Never raw `SLASH_*`.
7. Locale: metatable fallback `__index = function(_,k) return k end`. Never AceLocale strict.
8. Options UI: Blizzard `Settings.RegisterCanvasLayoutCategory` + raw AceGUI body, lazy on first `OnShow`. Never AceConfigDialog for content.
9. Schema-as-single-source: one table drives panel widgets + slash + defaults reset. One write seam.
10. Closed message bus: modules talk via `Ka0s_<Addon>_<Event>` messages, one sender each. No cross-module table reach.
11. All deprecated-API calls live in `Compat.lua`. Modules call `NS.Compat.X`.
12. Combat lockdown: gate `InCombatLockdown()` at panel-open, settings setters, secure-frame attribute writes. Defer with `PLAYER_REGEN_ENABLED`.
13. Per-frame loops: cache db values into module locals, refresh via `M:RefreshUpvalues()` on settings change.
14. ≥10 dynamic frames: use object pool (Acquire/Release/HideAll).
15. File LOC cap: ~1500. Peel when exceeded.
16. Externals not vendoring: declare Ace3 libs in `.pkgmeta` `externals:`. Never commit Ace3 to git.
17. Debug toggle persists in SV (`NS.db.global.debug`). Zero-allocation when off.
18. Doc set: README, CLAUDE.md, ARCHITECTURE.md, LICENSE. No drift; sync before every release.
19. Reviews: archive every audit under `reviews/<YYYY-MM-DD>/` with the 5-artifact bundle.
20. Versioning: semver. Bump TOC, code constants, README. `wow-addon:version-bump` skill automates this.

## Forbidden patterns

- `_G[addonName] = {}` (use private NS).
- AceLocale strict mode.
- Hand-rolled options framework (use Settings + AceGUI).
- AceConfigDialog for non-Profiles content.
- Raw `SLASH_*` registration.
- `if cmd == "x" then elseif ...` slash dispatchers.
- Vendored Ace3 libs.
- Forking Ace libs.
- `if WOW_PROJECT_ID ==` ladders inline (branch in Compat).
- `:Hide()` on Blizzard frames you replace (reparent to hidden parent).
- Replacing `_G.AddMessage`.
- Hard `## Dependencies:` (use OptionalDeps + soft fallback).
- `X-License: All Rights Reserved`.
- Per-flavor TOC duplication (use packager `enable-toc-creation`).
- Files >1500 LOC.
- Multiple senders per bus message.
- In-memory-only debug toggle.
- Cross-module direct table access.
- User-supplied Lua execution.

---

## Definition of done (new addon ready for v0.1.0 release)

- [ ] TOC has all 14 required fields including `X-Curse-Project-ID` and `X-Wago-ID`.
- [ ] `.pkgmeta` with externals, no vendored Ace3.
- [ ] `.luacheckrc` passes clean.
- [ ] `Compat.lua` exists (even if scaffold).
- [ ] `Locale.lua` exists with metatable fallback.
- [ ] `Database.lua` exists with `RunMigrations()` (even if no migrations yet).
- [ ] Settings module exposes Schema with at least one row, single write seam, slash dispatch from `COMMANDS` table.
- [ ] AceConsole `:RegisterChatCommand` registered.
- [ ] Options panel uses `Settings.RegisterCanvasLayoutCategory` + lazy AceGUI body.
- [ ] Combat-lockdown guard on panel-open.
- [ ] Persistent debug toggle (`/<slash> debug`).
- [ ] README, CLAUDE.md, ARCHITECTURE.md drafted; passes the 5-claim drift check.
- [ ] LICENSE = MIT full text.
- [ ] First entry in `reviews/<YYYY-MM-DD>/` (even if just a "Hello world" smoke test).

---

## Reference files in existing Ka0s addons

When stuck, copy from these (they're already standards-aligned in the cited dimension):

| Need | Reference |
|---|---|
| Schema structure | AbsorbTracker `Schema.lua` |
| Macro/protected-API firewall | ConsumableMaster `MacroManager.lua` |
| Tier-2 modular layout | KickCD `core/`, `modules/`, etc. |
| Closed message bus | KickCD's 5 `Ka0s_KickCD_*` messages |
| Compat module | KickCD `core/Compat.lua` |
| Taint-free chat formatting | prettychat `PrettyChat.lua:138-153` |
| Combat-lockdown 3-layer cascade | WhatGroup `WhatGroup.lua:868`, `_Settings.lua:975`, `_Frame.lua:173` |
| Lazy first-OnShow panel build | AbsorbTracker `OptionsPanel.lua` |
| Soft-fallback discipline | AbsorbTracker `Events.lua:47-65` |

---

## Skills you should use while building

(All under `wow-addon:` prefix in your local Claude Code plugin.)

- `wow-addon:new-addon` — scaffold a new addon (Ace3 stack, AceDB, modular folder layout, MIT license, slash command).
- `wow-addon:review` — principal-engineer review of the current addon. Produces `reviews/<DATE>/` bundle.
- `wow-addon:sync-docs` — eliminate doc drift across README, CLAUDE.md, ARCHITECTURE.md.
- `wow-addon:audit-conventions` — walk multiple addons and report drift in shared conventions.
- `wow-addon:bump-interface` — bump TOC Interface line.
- `wow-addon:version-bump` — bump version everywhere (TOC, code constants, README badges + Version History, CLAUDE/ARCHITECTURE, CHANGELOG).
- `wow-addon:normalize-readme` — reshape README to match a reference addon's section structure.
- `wow-addon:diff` — summarize uncommitted changes with risk assessment.
- `wow-addon:commit` — generated-message commit.
