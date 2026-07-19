# AH-Price Rev 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Polish the "AH Price" settings page: Data Collection layout (indent, spacing, info-follows-text, addon-not-detected muting) and Priority list (closer columns, column headers, show all sources with uncollected sunk to the bottom).

**Tech Stack:** Lua 5.1 (Ace3/AceGUI), luacheck. Panel is smoke-tested in-game (not unit-tested); the data/helper layer IS unit-tested.

## Global Constraints
- **Spec:** the **Revision 4** section of `docs/superpowers/specs/2026-07-18-ah-price-integration-design.md`.
- **Branch:** `feature/ah-price-integration`; one commit per task when green.
- **Icons:** Blizzard textures only (no media). No `▲`/`▼`/`✗` text glyphs in rendered strings (tofu risk) — use textures / `|T...|t` markup.
- **Provider display names:** `C.AUCTION_PROVIDER_NAMES`. Keys/labels/tooltips: `C.AUCTION_KEYS` (`provider`,`key`,`label`,`data`,`desc`). Tag form: `provider..":"..key`.
- **Verify each task:** `lua tests/run.lua` (exit 0) AND `luacheck .` (0/0). Data/helper task adds unit tests; UI tasks are load-tested only (file must still LOAD + suite green) with in-game render deferred.
- **No addon version bump.** Test inventory/badge batched to the last task (or skip if unchanged — R4-1 adds tests so regen at the end).

## File Structure
Modify: `core/Constants.lua`, `modules/AuctionPrice.lua`, `settings/Panel.lua`, `tests/test_auctionprice.lua`, and (final) `docs/test-cases.md` + README badge.

---

## Task R4-1: data-model + helpers (priority defaults, provider availability, reconcile, swap)

**Files:** `core/Constants.lua` (`AUCTION_PRIORITY_DEFAULT`), `modules/AuctionPrice.lua`, `tests/test_auctionprice.lua`.

**Interfaces produced:**
- `C.AUCTION_PRIORITY_DEFAULT` = all 11 tags (7 default-collected first, 4 default-uncollected last).
- `AuctionPrice:IsProviderAvailable(provider)` → bool.
- `AuctionPrice:ReconcilePriority()` → ensures `settings.auction.priority` holds every `AUCTION_KEYS` tag (append missing at end, drop unknown); returns the array.
- `AuctionPrice:SwapPriorityTags(tagA, tagB)` → swaps their positions in the priority array; returns true/false.

- [ ] **Step 1: Expand the priority default** — in `core/Constants.lua`, replace `AUCTION_PRIORITY_DEFAULT` with all 11 tags, default-collected first then default-uncollected:
```lua
C.AUCTION_PRIORITY_DEFAULT = {
  -- default-collected (in AUCTION_CAPTURE_DEFAULT) first
  "tsm:dbmarket", "auctionator:minbuyout", "oribos:market",
  "tsm:dbminbuyout", "tsm:dbregionmarketavg", "tsm:dbregionminbuyoutavg", "oribos:region",
  -- default-uncollected last
  "tsm:dbhistorical", "tsm:dbrecent", "tsm:dbregionhistorical", "tsm:dbregionsaleavg",
}
```

- [ ] **Step 2: Tests (RED)** — append to `tests/test_auctionprice.lua`:
```lua
test("AuctionPrice: IsProviderAvailable reflects addon globals", function()
  assertFalse(NS.AuctionPrice:IsProviderAvailable("tsm"))
  withGlobals({ TSM_API = { GetCustomPriceValue = function() end, ToItemString = function() end } }, function()
    assertTrue(NS.AuctionPrice:IsProviderAvailable("tsm"))
  end)
  withGlobals({ OEMarketInfo = function() end }, function()
    assertTrue(NS.AuctionPrice:IsProviderAvailable("oribos"))
  end)
end)

test("AuctionPrice: ReconcilePriority appends missing tags and drops unknown", function()
  NS.db.global.settings.auction = { priority = { "tsm:dbmarket", "bogus:x" } }
  local p = NS.AuctionPrice:ReconcilePriority()
  assertEqual(p[1], "tsm:dbmarket")                 -- kept, order preserved
  local set = {}; for _, t in ipairs(p) do set[t] = true end
  assertEqual(set["bogus:x"], nil)                  -- unknown dropped
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do  -- every known tag present
    assertTrue(set[k.provider .. ":" .. k.key], "missing " .. k.provider .. ":" .. k.key)
  end
  NS.db.global.settings.auction = nil
end)

test("AuctionPrice: SwapPriorityTags swaps positions", function()
  NS.db.global.settings.auction = { priority = { "a:1", "b:2", "c:3" } }
  assertTrue(NS.AuctionPrice:SwapPriorityTags("a:1", "b:2"))
  local p = NS.AuctionPrice:GetPriority()
  assertEqual(p[1], "b:2"); assertEqual(p[2], "a:1")
  assertFalse(NS.AuctionPrice:SwapPriorityTags("a:1", "zzz"))  -- missing tag
  NS.db.global.settings.auction = nil
end)
```
(`withGlobals`/`assertFalse` already exist in the harness/file; if `assertFalse` isn't exposed, use `assertEqual(x, false)`.)

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Implement in `modules/AuctionPrice.lua`:**
```lua
function AuctionPrice:IsProviderAvailable(provider)
  if provider == "auctionator" then
    return (Auctionator and Auctionator.API and Auctionator.API.v1) and true or false
  elseif provider == "tsm" then
    return (TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString) and true or false
  elseif provider == "oribos" then
    return type(OEMarketInfo) == "function"
  end
  return false
end

-- Ensure the stored priority array holds every known AUCTION_KEYS tag exactly once (append missing
-- at the end in AUCTION_KEYS order; drop tags no longer known). No migration — branch unmerged.
function AuctionPrice:ReconcilePriority()
  local p = self:GetPriority()
  local known, seen = {}, {}
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do known[k.provider .. ":" .. k.key] = true end
  local out = {}
  for _, tag in ipairs(p) do
    if known[tag] and not seen[tag] then out[#out + 1] = tag; seen[tag] = true end
  end
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do
    local tag = k.provider .. ":" .. k.key
    if not seen[tag] then out[#out + 1] = tag; seen[tag] = true end
  end
  for i = #p, 1, -1 do p[i] = nil end        -- rewrite in place (keep the same table reference)
  for i, tag in ipairs(out) do p[i] = tag end
  return p
end

function AuctionPrice:SwapPriorityTags(tagA, tagB)
  local p = self:GetPriority()
  local ia, ib
  for i, t in ipairs(p) do if t == tagA then ia = i elseif t == tagB then ib = i end end
  if not (ia and ib) then return false end
  p[ia], p[ib] = p[ib], p[ia]
  return true
end
```

- [ ] **Step 5: Run → GREEN**; `luacheck .` 0/0.

- [ ] **Step 6: Commit** — `git commit -am "feat(auction): all-11 priority default; IsProviderAvailable/ReconcilePriority/SwapPriorityTags"`

---

## Task R4-2: Data Collection layout + addon-not-detected (`buildAuctionCapture`)

**Files:** `settings/Panel.lua` (`buildAuctionCapture` ~632-684).

Apply, matching existing AceGUI idioms:
1. **#13 spacing:** increase the between-provider spacer above each heading (e.g. `addSpacer(scroll, 4)` → ~`10`); keep a little space above the first heading too.
2. **#12 indent:** indent each key's checkbox row under its heading — prepend a small fixed-width empty `Label` (e.g. width ~14) to the row `rowG` before the checkbox, or set a left inset; headings stay flush-left.
3. **#16 info-follows-text:** stop giving the checkbox a fixed `SetWidth(240)`. Instead size it to its label so the ⓘ icon trails the text with a small gap — after `cb:SetLabel(k.data)`, set `cb:SetWidth((cb.text and cb.text:GetStringWidth() or 80) + 30)` (the `cb.text` fontstring holds the rendered label; +~30 covers the check box + a gap). Verify AceGUI CheckBox exposes `.text`; if not, measure via a temp fontstring or fall back to a sensible per-label width. The ⓘ icon (via `iconButton`) follows in the same Flow row.
4. **#19 addon-not-detected:** for each provider, compute `local avail = NS.AuctionPrice:IsProviderAvailable(k.provider)` once per provider group. If NOT available:
   - Heading text: append a muted " |cff808080(not installed)|r" to the provider heading.
   - Checkbox: `cb:SetDisabled(true)` (non-interactable).
   - Mute: grey the label — AceGUI CheckBox greys its label when disabled; additionally dim the row's info icon (pass a `disabled`-style dim, or set the icon's `.image:SetVertexColor(0.4,0.4,0.4)`), so the whole row reads as inactive.
   - (Do NOT change capture data for unavailable providers — just present them as inactive.)

- [ ] **Step 1:** Read the current `buildAuctionCapture`. Apply the four changes above.
- [ ] **Step 2: Verify** — `luacheck .` 0/0; `lua tests/run.lua` green (file loads). In-game smoke (deferred): rows indent under headings; spacing above headings; ⓘ sits right after each label; an uninstalled addon shows "(not installed)", greyed, non-clickable checkboxes.
- [ ] **Step 3: Commit** — `git commit -am "feat(settings): Data Collection indent/spacing, info-follows-text, addon-not-detected muting"`

---

## Task R4-3: Priority column tweaks + all-sources / uncollected-at-bottom (`rebuildPriorityList` / `buildAuctionPriority`)

**Files:** `settings/Panel.lua` (`rebuildPriorityList` ~580-622, `buildAuctionPriority` ~689-712).

1. **#14 closer columns:** in each row, change the Addon column `SetRelativeWidth(0.34)` → `0.22` and the Data column `SetRelativeWidth(0.30)` → `0.42` (Addon narrows, Data widens by the same amount, so the ▲/▼/checkbox keep their x position; Data text starts closer to Addon text).
2. **#15 column headers:** in `buildAuctionPriority`, after the legend, add a small gap then a muted header row matching the row columns — status(blank, 0.06) + "Addon" (0.22) + "Price data" (0.42) + a blank/"Order" over the arrows + "On" over the checkbox (small/grey font, e.g. `GameFontDisableSmall`-like via `|cff808080…|r`). Keep the existing legend→header gap.
3. **#17 all sources, uncollected at bottom:** rewrite `rebuildPriorityList` to:
   - `local priority = NS.AuctionPrice:ReconcilePriority()` (ensures all 11 tags present).
   - `local capture = NS.db.global.settings.auction.capture or {}`.
   - Partition into `collected` (tags with `capture[tag]`) and `uncollected` (the rest), each **in priority-array order**. Display = `collected` then `uncollected`.
   - Render collected rows normally (status ✓, working ▲/▼, enable checkbox). The ▲/▼ reorder **within the collected group**: up swaps this tag with the previous collected tag (`NS.AuctionPrice:SwapPriorityTags(thisTag, prevCollectedTag)`), down with the next collected tag; disable up on the first collected row and down on the last collected row. After a swap, `rebuildPriorityList` + `DoLayout`.
   - Render uncollected rows **muted** (grey the Addon/Data labels, e.g. wrap in `|cff808080…|r`), status ✗, **no functional arrows** (dim both), enable checkbox may be shown but is moot (optional: still allow enable toggle). They sit at the bottom.
   - Keep the `#priority == 0` empty-state guard (now unlikely, but harmless).
   - The enable checkbox and status logic are unchanged except grouping.

- [ ] **Step 1:** Read the current `rebuildPriorityList`/`buildAuctionPriority`. Implement the three changes. Keep `providerNameOf`/`dataLabelOf`/`iconButton` as-is.
- [ ] **Step 2: Verify** — `luacheck .` 0/0; `lua tests/run.lua` green (file loads). In-game smoke (deferred): all 11 sources listed; uncollected ones muted at the bottom with no arrows; collected ones reorder correctly among themselves; Data column closer to Addon; column headers present with a gap to the legend.
- [ ] **Step 3: Commit** — `git commit -am "feat(settings): priority shows all sources (uncollected muted at bottom), closer columns, headers"`

---

## Task R4-4: test inventory + badge
- [ ] **Step 1:** `lua tests/run.lua --list > docs/test-cases.md`; set README `Tests` badge to the new total (R4-1 added ~3 cases). No version bump.
- [ ] **Step 2:** Final gates: `lua tests/run.lua` all pass; `luacheck .` 0/0; `python3 -m pytest tools/tests/ -q` all pass.
- [ ] **Step 3: Commit** — `git commit -am "docs: regen test inventory + badge (Rev-4)"`

---

## Self-Review
- Coverage: R4.1 layout→R4-2; R4.2 priority→R4-3; R4.3 helpers→R4-1; R4.4 decisions→across.
- Type consistency: `IsProviderAvailable(provider)`, `ReconcilePriority()→array`, `SwapPriorityTags(a,b)→bool` used by Panel exactly as defined; tag form `provider:key` consistent.
- Deferred: all in-game visual verification (indent/spacing/info-follows/not-detected muting/priority partition/columns/headers).
