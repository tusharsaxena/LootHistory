# AH-Price Rev 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Overhaul the "AH Price" settings sub-page (rename; nested per-provider Data Collection with info tooltips; priority rows with texture arrows, two label columns, an enable checkbox, and a collected/not-collected status icon + legend; explanatory text) plus inject sample auction data into the AI template.

**Architecture:** Add a `priorityDisabled` carve-out (Pick skips disabled tags). Extend `C.AUCTION_KEYS` with provider display names, short data labels, and info-tooltip text. Rebuild the two panel sections as custom AceGUI, using Blizzard textures (no media). Script-inject `a`/`val` into eligible template sample rows.

**Tech Stack:** Lua 5.1 (Ace3), Python 3 (assembler check), luacheck.

## Global Constraints
- **Spec:** the **Revision 3** section of `docs/superpowers/specs/2026-07-18-ah-price-integration-design.md`.
- **Branch:** `feature/ah-price-integration` (unmerged); incremental auto-commit; one commit per task when green.
- **Icons (Blizzard textures, no media copied):** up `Interface\ChatFrame\UI-ChatIcon-ScrollUp-Up`, down `...-ScrollDown-Up`, check `Interface\RaidFrame\ReadyCheck-Ready`, X `Interface\RaidFrame\ReadyCheck-NotReady`, info `Interface\FriendsFrame\InformationIcon`. **No `▲`/`▼` text glyphs** (Friz Quadrata renders them as tofu).
- **Provider display names:** `auctionator`→"Auctionator", `tsm`→"Tradeskill Master", `oribos`→"Oribos Exchange".
- **Priority enable state:** `settings.auction.priorityDisabled = { [tag]=true }` (default empty). `Pick` skips disabled tags. Status ✓/✗ = whether the tag is in `settings.auction.capture` (read-only).
- **Verify each task:** `lua tests/run.lua` (exit 0) AND `luacheck .` (0/0). Panel is load-tested only (in-game render deferred to human smoke). Template task also runs the assembler + `python3 -m pytest tools/tests/ -q`.
- **Hard rules:** never bump the addon version; test-inventory/badge batched to the final task.

## File Structure
Modify: `core/Constants.lua`, `modules/AuctionPrice.lua`, `defaults/Global.lua`, `settings/Schema.lua`, `settings/Panel.lua`, `docs/ai-export-template.html`, `README.md` + docs, plus `tests/*`.

---

## Task R3-1: data model — priorityDisabled + Constants labels/tooltips

**Files:** `core/Constants.lua`, `modules/AuctionPrice.lua`, `defaults/Global.lua`, tests `test_auctionprice.lua`, `test_schema.lua`.

**Interfaces:**
- Produces: `C.AUCTION_PROVIDER_NAMES`; each `C.AUCTION_KEYS` entry gains `data` + `desc`. `settings.auction.priorityDisabled` set. `AuctionPrice:IsPriorityEnabled(tag)`, `SetPriorityEnabled(tag,on)`; `Pick` skips disabled.

- [ ] **Step 1: Constants** — in `core/Constants.lua`, add provider names and extend each `AUCTION_KEYS` entry with `data` (short label) + `desc` (tooltip). Full replacement of the `AUCTION_KEYS` block:

```lua
C.AUCTION_PROVIDER_NAMES = { auctionator = "Auctionator", tsm = "Tradeskill Master", oribos = "Oribos Exchange" }
C.AUCTION_KEYS = {
  { provider="auctionator", key="minbuyout",            label="Auctionator \226\128\148 Min buyout",        data="Min Buyout",            desc="The lowest current buyout on your realm's auction house, from Auctionator's last scan." },
  { provider="tsm",         key="dbmarket",             label="TSM \226\128\148 Market value",               data="Market Value",          desc="TSM's smoothed market value for your realm (roughly a 14-day average) \226\128\148 its best 'what's it worth' number." },
  { provider="tsm",         key="dbminbuyout",          label="TSM \226\128\148 Min buyout",                 data="Min Buyout",            desc="The lowest buyout on your realm from TSM's most recent scan." },
  { provider="tsm",         key="dbregionmarketavg",    label="TSM \226\128\148 Region market avg",          data="Region Market Avg",     desc="Average market value across your whole region (from the TSM Desktop App) \226\128\148 wide coverage even for items you never scanned." },
  { provider="tsm",         key="dbregionminbuyoutavg", label="TSM \226\128\148 Region min-buyout avg",      data="Region Min-Buyout Avg", desc="Average of the lowest buyouts across your region." },
  { provider="tsm",         key="dbhistorical",         label="TSM \226\128\148 Historical",                 data="Historical",            desc="TSM's long-term historical average for your realm (roughly 60\226\128\9390 days)." },
  { provider="tsm",         key="dbrecent",             label="TSM \226\128\148 Recent",                     data="Recent",                desc="The value from TSM's most recent realm scan (more volatile than market value)." },
  { provider="tsm",         key="dbregionhistorical",   label="TSM \226\128\148 Region historical",          data="Region Historical",     desc="TSM's long-term historical average across your region." },
  { provider="tsm",         key="dbregionsaleavg",      label="TSM \226\128\148 Region sale avg",            data="Region Sale Avg",       desc="The average price items actually SOLD for across your region (realized sales, not listings)." },
  { provider="oribos",      key="market",               label="OribosExchange \226\128\148 Market",         data="Market",                desc="OribosExchange's realm market value, from its imported region/realm dataset." },
  { provider="oribos",      key="region",               label="OribosExchange \226\128\148 Region",         data="Region",                desc="OribosExchange's region-wide market value." },
}
```
(Keep the existing `AUCTION_CAPTURE_DEFAULT`, `AUCTION_PRIORITY_DEFAULT`, `AUCTION_CAPTURE_OPTIONS` blocks as-is.)

- [ ] **Step 2: Defaults** — in `defaults/Global.lua`, add `priorityDisabled = {}` to the `settings.auction` table (after `priority`).

- [ ] **Step 3: Test (RED)** — in `tests/test_auctionprice.lua`:

```lua
test("AuctionPrice: Pick skips priority-disabled tags", function()
  NS.db.global.settings.auction = { enabled = true,
    priority = { "tsm:dbmarket", "oribos:market" }, priorityDisabled = { ["tsm:dbmarket"] = true } }
  local price, tag = NS.AuctionPrice:Pick({ tsm = { dbmarket = 500 }, oribos = { market = 700 } })
  assertEqual(price, 700); assertEqual(tag, "oribos:market")   -- tsm:dbmarket disabled, skipped
  NS.AuctionPrice:SetPriorityEnabled("tsm:dbmarket", true)     -- re-enable
  assertEqual(NS.db.global.settings.auction.priorityDisabled["tsm:dbmarket"], nil)
  assertEqual(NS.AuctionPrice:IsPriorityEnabled("oribos:market"), true)
  NS.db.global.settings.auction = nil
end)
```

- [ ] **Step 4: Run → FAIL.**

- [ ] **Step 5: Implement** — in `modules/AuctionPrice.lua`:
  - In `Pick`, after resolving `prov,key`, skip disabled: read `settings.auction.priorityDisabled` and `if disabled[tag] then` continue. Add a `disabled` local from `cfg`/settings (nil-safe: `local s = NS.db.global.settings.auction; local disabled = (s and s.priorityDisabled) or {}`).
  - Add helpers:

```lua
function AuctionPrice:IsPriorityEnabled(tag)
  local s = NS.db.global.settings.auction
  return not (s and s.priorityDisabled and s.priorityDisabled[tag])
end
function AuctionPrice:SetPriorityEnabled(tag, on)
  local s = NS.db.global.settings.auction
  s.priorityDisabled = s.priorityDisabled or {}
  s.priorityDisabled[tag] = (not on) or nil
end
```

- [ ] **Step 6: Run → GREEN**; `luacheck .` 0/0.

- [ ] **Step 7: Commit** — `git commit -am "feat(auction): priorityDisabled (Pick skips) + provider names/data labels/tooltips"`

---

## Task R3-2: panel — rename tab to "AH Price" + rebuild the Priority section

**Files:** `settings/Panel.lua` (the auction subcategory ~732-760; `buildAuctionPriority`/`rebuildPriorityList` ~530-606; the Defaults handler ~735-749), `settings/Schema.lua` (the `group = "Auction House Price"` strings on the auction rows).

**Design (reuse the ConsumableMaster pattern — Blizzard textures, AceGUI):**
- Small local helper `iconButton(image, size, tooltipLabel, tooltipBody, onClick, disabled)` → `AceGUI:Create("Icon")` with `SetImage(image)`, `SetImageSize(size,size)`, `SetLabel("")`, `SetWidth(size+8)`, OnClick, and GameTooltip on OnEnter/OnLeave (SetOwner(widget.frame,"ANCHOR_RIGHT"); SetText(label,1,1,1); AddLine(body,nil,nil,nil,true)); when `disabled`, dim via `widget.image:SetVertexColor(0.4,0.4,0.4)` and skip the OnClick.
- Status ✓/✗ via inline markup in a Label: `"|TInterface\\RaidFrame\\ReadyCheck-Ready:16|t"` / `"...ReadyCheck-NotReady:16|t"`.

- [ ] **Step 1: Rename the subcategory.** In `settings/Panel.lua`, change the three `"Auction House Price"` strings for the auction page: `createPanel("LootHistoryAuctionPanel", "AH Price", ...)`, `Settings.RegisterCanvasLayoutSubcategory(mainCategory, actx.panel, "AH Price")`, and the Defaults handler's `if r.group == "Auction House Price"` and `renderSchema(...,{ skip = { ["Auction House Price"] = true } })` and `{ only = "Auction House Price" }`. In `settings/Schema.lua`, change the auction rows' `group = "Auction House Price"` → `group = "AH Price"`. (Update ALL occurrences consistently — grep `"Auction House Price"` and `"AH Price"` after.)

- [ ] **Step 2: Rebuild `rebuildPriorityList`** so each row is `[status] [addon] [data] [▲] [▼] [☑]`:

```lua
local READY   = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOTREADY= "Interface\\RaidFrame\\ReadyCheck-NotReady"
local ARR_UP  = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up"
local ARR_DN  = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"

local function providerNameOf(tag)
  local prov = tag:match("^(.-):")
  return (NS.Constants.AUCTION_PROVIDER_NAMES[prov]) or prov or tag
end
local function dataLabelOf(tag)
  local prov, key = tag:match("^(.-):(.+)$")
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do
    if k.provider == prov and k.key == key then return k.data or k.label end
  end
  return key or tag
end

local function rebuildPriorityList(ctx, listGroup)
  listGroup:ReleaseChildren()
  local priority = NS.AuctionPrice:GetPriority()
  local capture = NS.db.global.settings.auction.capture or {}
  for i, tag in ipairs(priority) do
    local rowG = AceGUI:Create("SimpleGroup"); rowG:SetLayout("Flow"); rowG:SetFullWidth(true)

    local status = AceGUI:Create("Label"); status:SetRelativeWidth(0.06)
    status:SetText(capture[tag] and ("|T"..READY..":16|t") or ("|T"..NOTREADY..":16|t"))
    rowG:AddChild(status)

    local addon = AceGUI:Create("Label"); addon:SetRelativeWidth(0.34); addon:SetText(providerNameOf(tag)); rowG:AddChild(addon)
    local data  = AceGUI:Create("Label"); data:SetRelativeWidth(0.30); data:SetText(dataLabelOf(tag)); rowG:AddChild(data)

    rowG:AddChild(iconButton(ARR_UP, 18, "Move up",   "Rank this price higher.", (i > 1) and function()
      NS.AuctionPrice:MovePriority(i, -1); rebuildPriorityList(ctx, listGroup); if ctx.scroll then ctx.scroll:DoLayout() end end or nil, i == 1))
    rowG:AddChild(iconButton(ARR_DN, 18, "Move down", "Rank this price lower.",  (i < #priority) and function()
      NS.AuctionPrice:MovePriority(i, 1); rebuildPriorityList(ctx, listGroup); if ctx.scroll then ctx.scroll:DoLayout() end end or nil, i == #priority))

    local cb = AceGUI:Create("CheckBox"); cb:SetLabel(""); cb:SetRelativeWidth(0.08)
    cb:SetValue(NS.AuctionPrice:IsPriorityEnabled(tag))
    cb:SetCallback("OnValueChanged", function(_, _, v) NS.AuctionPrice:SetPriorityEnabled(tag, v) end)
    rowG:AddChild(cb)

    listGroup:AddChild(rowG)
  end
  if #priority == 0 then
    local empty = AceGUI:Create("Label"); empty:SetFullWidth(true); empty:SetText("|cff808080(none)|r"); listGroup:AddChild(empty)
  end
  if listGroup.DoLayout then listGroup:DoLayout() end
end
```
Add the `iconButton` helper (per Design above) as a file-local function before `rebuildPriorityList`.

- [ ] **Step 3: Update `buildAuctionPriority`** — heading → `section(ctx, "Priority (top = preferred)")`; description → explains collection-vs-priority: "Of the prices you collect, this order decides which one is shown (top wins). Untick a row to skip it; a red ✗ means that source isn't being collected, so it can never win." Add a legend Label under the description: `"|T"..READY..":16|t collected    |T"..NOTREADY..":16|t not collected"`.

- [ ] **Step 4: Defaults handler** — after clearing/refilling `priority`, also clear `priorityDisabled` (`wipe(NS.db.global.settings.auction.priorityDisabled)` or set to `{}`), so Defaults restores full order + all-enabled.

- [ ] **Step 5: Verify** — `luacheck .` 0/0; `lua tests/run.lua` green (Panel loads). Grep confirms no `"Auction House Price"` remains for the panel/schema and no `\226\150\178`/`\226\150\188` text-arrow bytes remain in the priority rows. In-game smoke deferred.

- [ ] **Step 6: Commit** — `git commit -am "feat(settings): AH Price tab; priority rows with texture arrows, addon/data columns, enable + status"`

---

## Task R3-3: panel — Data Collection nested custom section

**Files:** `settings/Panel.lua` (add `buildAuctionCapture`; call it from the auction OnShow; stop rendering the capture MultiCheck via `renderSchema`), `settings/Schema.lua` (mark the capture row so the panel skips rendering it while keeping it schema-backed).

- [ ] **Step 1: Skip the MultiCheck in the panel.** Add `panelSkip = true` to the `settings.auction.capture` schema row, and in `renderSchema` skip rows with `row.panelSkip` (one guard: `if row.panelSkip then <continue> end`, using the existing include/`if` structure — NO goto). The row still drives defaults + slash.

- [ ] **Step 2: Build the nested section** — add `buildAuctionCapture(ctx)`:
  - `section(ctx, "Data Collection")` + a description Label: "Choose which prices to record on every drop. Collecting more gives you more to compare later, at a small storage cost. This is separate from priority."
  - Group `NS.Constants.AUCTION_KEYS` by provider **in AUCTION_KEYS order** (auctionator, tsm, oribos). For each provider: a small heading Label with `NS.Constants.AUCTION_PROVIDER_NAMES[prov]` (bold, e.g. gold `|cffe8c56b...|r`), then for each of its keys a row: a **CheckBox** (label = the key's `data`) bound to the capture set + an **info Icon** (`Interface\FriendsFrame\InformationIcon`, ~16px) whose tooltip shows the key's `desc` (via the same GameTooltip-on-hover helper as the arrows).
    - Checkbox read: `capture[tag] == true`. Write: on change, `local c = NS.db.global.settings.auction.capture or {}; c[tag] = v or nil; NS.db.global.settings.auction.capture = c`; then refresh the Priority list (so its ✓/✗ status updates) — call the priority refresh (expose the priority `listGroup` refresh via `ctx.refreshers` or a shared refresh).
  - Register the capture refresh in `ctx.refreshers`.
  - Use `NS.Schema:Set("settings.auction.capture", ...)` if you want onChange semantics; direct table write is acceptable here since capture has no onChange — but toggling MUST also refresh the priority status icons.

- [ ] **Step 3: Wire order** — in the auction subcategory OnShow, render order: the `enabled` checkbox (`renderSchema` with only the enabled row), then `buildAuctionCapture(actx)` (Data Collection), then `buildAuctionPriority(actx)` (Priority). Confirm toggling a capture checkbox refreshes the priority ✓/✗ (a shared/registered refresh).

- [ ] **Step 4: Verify** — `luacheck .` 0/0; `lua tests/run.lua` green. In-game smoke deferred (nested checkboxes + info tooltips; toggling capture flips a priority row's ✓/✗).

- [ ] **Step 5: Commit** — `git commit -am "feat(settings): nested Data Collection section with per-key info tooltips"`

---

## Task R3-4: template — inject sample auction data

**Files:** `docs/ai-export-template.html`.

- [ ] **Step 1:** Write a one-off transform (python/node in your scratchpad) that reads the template, finds the `const H = [` … `\n];` block, and for each row object whose `"b"` is `"Not Bound"` or `"Bind on Equip"`: compute `a = round(v * m)` where `m` is a multiplier in [2.0,10.0] to one decimal (vary it per row — e.g. derive deterministically from the row's `id`/index so it's reproducible, since Math.random is fine in a real script), and set `val = max(a, v)`. Insert `"a"` and `"val"` keys into the object (keep valid JSON/JS; other rows unchanged). Write the file back. Do NOT touch anything outside the H block.

- [ ] **Step 2: Verify** — build a report via the assembler against the edited template (as in Rev-2 R10) → PASS; open it and confirm: rows that are Not Bound / Bind on Equip show an **Auction** value (roughly 2–10× vendor), other rows show `—`; the hero/value reflects the higher numbers. `python3 -m pytest tools/tests/ -q` green; `lua tests/run.lua` unaffected.

- [ ] **Step 3: Commit** — `git commit -am "chore(ai-template): sample auction prices for tradeable rows"`

---

## Task R3-5: docs + inventory + badge

**Files:** `README.md`, `docs/data-model.md`, `docs/ARCHITECTURE.md`/`docs/saved-variables.md` (note `priorityDisabled` carve-out + per-entry enable), `docs/test-cases.md`, README badge.

- [ ] **Step 1:** README AH-pricing section: mention you can now enable/disable individual priority entries and see which sources are being collected. `docs/saved-variables.md`: add `settings.auction.priorityDisabled` to the carve-out list. `docs/data-model.md`/`ARCHITECTURE.md`: note Pick skips disabled priority entries.
- [ ] **Step 2:** Regenerate `docs/test-cases.md` (`lua tests/run.lua --list > docs/test-cases.md`); set README `Tests` badge to the real total.
- [ ] **Step 3: Final gates** — `lua tests/run.lua` all pass; `luacheck .` 0/0; `python3 -m pytest tools/tests/ -q` all pass.
- [ ] **Step 4: Commit** — `git commit -am "docs(auction): Rev-3 settings UX + priority enable; inventory + badge"`

---

## Self-Review
- Spec coverage: R3.1 rename→R3-2; R3.2 icons→R3-2/R3-3; R3.3 Data Collection→R3-3; R3.4 Priority→R3-2; R3.5 priorityDisabled→R3-1; R3.6 explanatory text→R3-2/R3-3; R3.7 Constants→R3-1; R3.8 template→R3-4; §label split→R3-2.
- Type consistency: `IsPriorityEnabled(tag)`/`SetPriorityEnabled(tag,on)`/`Pick` skip logic all key on the `provider:key` tag; `providerNameOf`/`dataLabelOf` read `C.AUCTION_PROVIDER_NAMES`/`AUCTION_KEYS.data`.
- Deferred: all in-game visual verification (nested checkboxes, info tooltips, arrows, enable checkbox, status icons, legend); template visual via assembler PASS + open.
