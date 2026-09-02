local addonName, NS = ...
NS.Panel = NS.Panel or {}
local P = NS.Panel
local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer (events-frames-taint-§8)

-- The LibKa0s-Options-1.0 instance: the canvas shell, the page registry, the lazy Defaults button,
-- the five widget makers, the two-column flow engine and the always-shown scrollbar patch. Wired in
-- settings/OptionsSetup.lua, which loads immediately before this file and is where every descriptor
-- decision (and every declined surface) is written down.
local O = NS.Options

-- Ka0s settings-panel pattern (shared across Ka0s addons; see WowAddonStandards):
--   * A parent canvas category renders the LANDING PAGE — logo + one-liner +
--     slash-command list — with the same gold header every subcategory uses.
--   * Each settings group is a canvas SUBCATEGORY ("General") with a breadcrumb
--     header ("Ka0s Loot History ▸ General"), a Defaults button, and a gold divider.
--   * Bodies render schema rows into a TWO-COLUMN grid (50%/50% Flow rows);
--     section headings (AceGUI Heading, centered label flanked by dividers) group them.
-- All of the above is now the library's. Writes still route through NS.Schema:Set (validate → write
-- → onChange); reads via :Get — the descriptor points at both.

local ADDON_TAGLINE = "Records every item you loot, attributes its source, and lets you browse and analyze it."
local LOGO_PATH     = "Interface\\AddOns\\LootHistory\\media\\logos\\loothistory.logo.tga"
local LOGO_SIZE     = 300  -- landing-page logo display size

-- The layout constants moved to LibKa0s-Options-1.0's own LAYOUT table, which carries the SAME
-- numbers this file used to declare (PADDING_X 16, HEADER_TOP 20, HEADER_HEIGHT 54, DEFAULTS_W 110,
-- ROW_VSPACER 8, the 10/6/26 section triple, BUTTON_PAIR_REL 0.492). The three this file's own page
-- code still needs are re-exported on the instance so host layout stays in lockstep with the engine.

-- ── Shared maker for a paired action button (Reset Everything, Purge) ───────────────────
-- Insets to BUTTON_PAIR_REL rather than a flat 0.5 so the right border isn't shaved by the
-- ScrollFrame clip (options-ui-§6/§8). Kept host-side: the library's InlineButtonPair builds its own
-- Flow row, and both of this addon's uses need a bare button to drop into a row someone else owns.
local function makePairButton(text, onClick)
  local btn = NS.AceGUI:Create("Button")
  btn:SetText(text)
  btn:SetRelativeWidth(O.BUTTON_PAIR_REL)
  if onClick then btn:SetCallback("OnClick", onClick) end
  return btn
end

-- ── The inverted set picker (host-drawn) ────────────────────────────────────────
-- A set-map rendered full-width as a wrapping checkbox grid. With row.invert, a *checked* box means
-- the source is recorded (i.e. NOT in the muted set), so the stored value is the logical inverse of
-- the checkbox state.
--
-- DECLINED from the library, deliberately: its five makers are checkbox / slider / dropdown /
-- editbox / color picker, and an inverted set picker is none of them. The row stays in the schema,
-- so the CLI and every reset still see it, and it is drawn from `afterGroup` below — which fires
-- after its group's last row is flushed, i.e. exactly where it used to sit.
--
-- It does NOT carry `skipRender`, and why it draws nothing on the generic path is worth knowing: it
-- is `type = "table"`, and `O.RenderField` dispatches on `row.type` over bool/number/string/color,
-- deliberately returning nil for a type it does not know. So the row IS walked and IS handed to the
-- renderer, which silently produces no widget. The visible result is identical to `skipRender`; the
-- mechanism is not. If the library ever grows a `table` maker this row starts drawing twice — once
-- generically, once here. `settings.auction.capture` is the row that really does carry
-- `skipRender`.
local function makeMultiCheck(ctx, row, scroll)
  local invert = row.invert
  local group = NS.AceGUI:Create("InlineGroup")
  group:SetTitle(row.label); group:SetFullWidth(true); group:SetLayout("Flow")
  local boxes = {}
  for _, opt in ipairs(row.values) do
    local cb = NS.AceGUI:Create("CheckBox")
    cb:SetLabel(opt.text); cb:SetWidth(150)
    cb:SetCallback("OnValueChanged", function(_, _, v)
      local cur = NS.Schema:Get(row.path) or {}
      local copy = {}
      for k, val in pairs(cur) do copy[k] = val end
      -- muted = checked when inverted, unchecked otherwise
      copy[opt.value] = ((invert and not v) or (not invert and v)) or nil
      NS.Schema:Set(row.path, copy)
    end)
    group:AddChild(cb)
    boxes[opt.value] = cb
  end
  scroll:AddChild(group)
  ctx.refreshers[#ctx.refreshers + 1] = function()
    local cur = NS.Schema:Get(row.path) or {}
    for value, cb in pairs(boxes) do
      local muted = cur[value] and true or false
      cb:SetValue(invert and not muted or (not invert and muted))
    end
  end
end


-- ── The Maintenance tab's body: live DB stats, Purge, Reset Everything ──────────
--
-- Drawn from RenderTabbedSchema's `afterGroup` hook, keyed to the Maintenance group, rather than
-- appended by the page renderer. That is not decoration: a tab click re-enters RenderTabbedSchema
-- directly (ClearScroll, then the active tab's rows), never the page renderer, so anything the
-- renderer appended AFTER the schema rows would be drawn once and then vanish on the first click.
-- The hook is the seam that survives the click. There is no before-group hook, which is fine —
-- this block belongs under the retention row anyway.
--
-- NO O.Section heading any more. Under a strip the tab IS the heading, and a "History" heading
-- inside a tab called Maintenance is the page saying the same thing twice.
local function renderHistory(ctx)
  local scroll = O.EnsureScroll(ctx)
  if not scroll then return end

  local rowFrame = NS.AceGUI:Create("SimpleGroup")
  rowFrame:SetLayout("Flow"); rowFrame:SetFullWidth(true)

  local statsLabel = NS.AceGUI:Create("Label")
  statsLabel:SetRelativeWidth(0.5)
  rowFrame:AddChild(statsLabel)

  -- "Purge history…" — ellipsis: opens a confirm dialog.
  local purgeBtn = makePairButton("Purge history\226\128\166", function()
    if type(StaticPopup_Show) == "function" then StaticPopup_Show("KA0S_LOOTHISTORY_PURGE")
    elseif NS.Database and NS.Database.Purge then NS.Database:Purge() end
  end)
  rowFrame:AddChild(purgeBtn)
  scroll:AddChild(rowFrame)

  -- "Reset Everything" is NOT here any more. It is the confirm-gated global reset (options-ui-§12)
  -- and options-ui-§15 puts that on the Master controls tab as the closing button pair's
  -- "Reset all settings", drawn by the composer's own afterGroup hook. Same popup, same
  -- Sl:ResetEverything, same blast radius — two buttons over one act is the thing this pass exists
  -- to remove, so this one is gone rather than duplicated.

  local function refreshStats()
    local s = NS.Database:StorageStats()
    local line1
    if s.count == 0 then
      line1 = "No items collected yet."
    else
      local count = (BreakUpLargeNumbers and BreakUpLargeNumbers(s.count)) or s.count
      line1 = string.format("%s %s collected over %d %s.",
        tostring(count), s.count == 1 and "item" or "items", s.days, s.days == 1 and "day" or "days")
    end
    -- \226\137\136 = "≈"  (real SavedVariables file size can't be read in-game; estimated)
    statsLabel:SetText(line1 .. "\nDatabase size: \226\137\136 " ..
      NS.Util.FormatBytes(s.bytes) .. "  (estimated)")
  end
  ctx.refreshers[#ctx.refreshers + 1] = refreshStats
  refreshStats()

  -- Live-refresh while the panel is open. Uses a private bus target (NOT NS.bus-as-self) so it
  -- can't clobber the Browser/Analytics consumers registered for the same messages. See
  -- NS.NewBusTarget.
  --
  -- The listener is registered ONCE but the label is not: every tab click builds a new statsLabel
  -- and a new refreshStats over it, and the old widget goes back to AceGUI's pool. So the
  -- registration closes over `P.__stats`, reassigned on every render, instead of over the
  -- refreshStats of whichever render happened to be first — which would have kept a released
  -- widget alive and repainted it forever while the live label went stale. (Latent before the
  -- strip too: O.SetRenderer re-runs a renderer whose page was dirtied off-screen.)
  P.__stats = refreshStats
  if not P.__ev then
    local ev = NS.NewBusTarget()
    if ev then
      local onChange = function()
        if P.general and P.general.panel:IsShown() and P.__stats then P.__stats() end
      end
      ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", onChange)
      ev:RegisterMessage("Ka0s_LootHistory_RecordAdded", onChange)
      P.__ev = ev
    end
  end
end

-- Run a page's structural rebuilders (list rows) + relayout, and clear its dirty flag. Called on
-- first paint, on an on-screen edit, and on the next OnShow after an off-screen change — the gate
-- that keeps AceGUI teardown+rebuild off every tab click (options-ui-§11 / anti-pattern #39).
--
-- The flag is the LIBRARY's `ctx._dirty` — the one O.SetRenderer's OnShow actually reads — and not
-- a private `ctx.dirty` alongside it. A page-local flag is written and never read: the library
-- returns early on `_rendered and not _dirty`, so an off-screen change would never repaint.
local function runRebuilders(ctx)
  for _, fn in ipairs(ctx.rebuilders or {}) do pcall(fn) end
  ctx._dirty = false
  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end

-- ── Filters sub-page: blacklist / whitelist item-id management ────────────────────
-- A single sub-page, three TABS (item blacklist, item whitelist, currency blacklist), one on screen.
-- Each: a short description, an "add" row (an id or a shift-clicked link) and a live list of
-- current ids with a Remove button per row. The lists are core app logic and act point-in-time:
-- blacklisted ids are dropped at loot time and whitelisted ids are always recorded — neither list
-- ever hides or restores an already-stored row.

-- Display name for an id: "Name  (id)" once cached, "Item id" until the client caches it (a
-- background load is kicked off so a later rebuild fills the name in).
local function filterEntryLabel(id, onCached)
  local name, quality = NS.Compat.ItemNameQuality(id)
  if not name then
    if NS.Item.LoadItem then NS.Item.LoadItem(id, onCached) end
    return "|cffaaaaaaItem " .. id .. "|r"
  end
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
  local hex = c and c.color and c.color:GenerateHexColor()
  local shown = hex and ("|c" .. hex .. name .. "|r") or name
  return shown .. "  |cff808080(" .. id .. ")|r"
end

-- Label for a currency-blacklist entry: the currency's name (gray id suffix), or a placeholder.
local function currencyEntryLabel(id)
  local name = NS.Compat.CurrencyName and NS.Compat.CurrencyName(id)
  if not name then return "|cffaaaaaaCurrency " .. id .. "|r" end
  return name .. "  |cff808080(" .. id .. ")|r"
end

-- Rebuild `listGroup` from the ids currently on `listKey`. Each row: item label + Remove button.
local function rebuildFilterList(ctx, listGroup, listKey)
  listGroup:ReleaseChildren()
  local set
  if listKey == "currencyBlacklist" then
    set = NS.Filters:CurrencyBlacklist()
  else
    set = (listKey == "blacklist") and NS.Filters:Blacklist() or NS.Filters:Whitelist()
  end
  local ids = NS.Filters:SortedIDs(set)
  if #ids == 0 then
    local empty = NS.AceGUI:Create("Label")
    empty:SetFullWidth(true)
    empty:SetText("|cff808080(none)|r")
    listGroup:AddChild(empty)
  else
    for _, id in ipairs(ids) do
      local rowG = NS.AceGUI:Create("SimpleGroup")
      rowG:SetLayout("Flow"); rowG:SetFullWidth(true)
      local lbl = NS.AceGUI:Create("Label")
      lbl:SetRelativeWidth(0.78)
      if listKey == "currencyBlacklist" then
        lbl:SetText(currencyEntryLabel(id))
      else
        lbl:SetText(filterEntryLabel(id, function()
          if ctx.panel:IsShown() then rebuildFilterList(ctx, listGroup, listKey) end
        end))
      end
      rowG:AddChild(lbl)
      local rm = NS.AceGUI:Create("Button")
      rm:SetText("Remove"); rm:SetRelativeWidth(0.20)
      rm:SetCallback("OnClick", function()
        if listKey == "currencyBlacklist" then
          NS.Filters:RemoveCurrencyBlacklist(id)
        elseif listKey == "blacklist" then
          NS.Filters:RemoveBlacklist(id)
        else
          NS.Filters:RemoveWhitelist(id)
        end
        rebuildFilterList(ctx, listGroup, listKey)
        if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
      end)
      rowG:AddChild(rm)
      listGroup:AddChild(rowG)
    end
  end
  if listGroup.DoLayout then listGroup:DoLayout() end
end

-- One section (blacklist or whitelist): heading, description, add-row, live list.
local function makeFilterSection(ctx, listKey, desc)
  local scroll = O.EnsureScroll(ctx)
  -- No O.Section heading: the page is a tab strip now (options-ui-§13) and the tab IS the heading.
  -- A "Blacklist" heading under a tab called Blacklist is the page saying it twice.
  local descLabel = NS.AceGUI:Create("Label")
  descLabel:SetFullWidth(true); descLabel:SetText(desc)
  scroll:AddChild(descLabel)
  O.AddSpacer(scroll, 6)

  local listGroup = NS.AceGUI:Create("SimpleGroup")
  listGroup:SetLayout("List"); listGroup:SetFullWidth(true)

  local addRow = NS.AceGUI:Create("SimpleGroup")
  addRow:SetLayout("Flow"); addRow:SetFullWidth(true)
  local box = NS.AceGUI:Create("EditBox")
  box:SetLabel(listKey == "currencyBlacklist" and "Add currency id or link" or "Add item id or link")
  box:SetRelativeWidth(0.78)
  local function submit()
    if listKey == "currencyBlacklist" then
      local id = NS.Filters:ParseCurrencyID(box:GetText())
      if not id then
        print("enter a numeric currency id (or shift-click a currency link).")
        return
      end
      NS.Filters:AddCurrencyBlacklist(id)
      box:SetText("")
      rebuildFilterList(ctx, listGroup, listKey)
      if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
      return
    end
    local id = NS.Filters:ParseItemID(box:GetText())
    if not id then
      print("enter a numeric item id (or shift-click an item link).")
      return
    end
    if listKey == "blacklist" then NS.Filters:AddBlacklist(id) else NS.Filters:AddWhitelist(id) end
    box:SetText("")
    rebuildFilterList(ctx, listGroup, listKey)
    if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
  end
  box:SetCallback("OnEnterPressed", function() submit() end)
  addRow:AddChild(box)
  local addBtn = NS.AceGUI:Create("Button")
  addBtn:SetText("Add"); addBtn:SetRelativeWidth(0.20)
  addBtn:SetCallback("OnClick", submit)
  addRow:AddChild(addBtn)
  scroll:AddChild(addRow)
  O.AddSpacer(scroll, 4)

  -- Bulk "Clear all" for this list (confirm-gated). The list view refreshes itself via the
  -- HistoryChanged listener that Filters:ClearList fires, so the button only shows the popup.
  local clearRow = NS.AceGUI:Create("SimpleGroup")
  clearRow:SetLayout("Flow"); clearRow:SetFullWidth(true)
  local clearBtn = NS.AceGUI:Create("Button")
  clearBtn:SetText("Clear all"); clearBtn:SetRelativeWidth(0.30)
  clearBtn:SetCallback("OnClick", function()
    local popup
    if listKey == "currencyBlacklist" then
      popup = "KA0S_LOOTHISTORY_CLEAR_CURRENCY"
    elseif listKey == "blacklist" then
      popup = "KA0S_LOOTHISTORY_CLEAR_BLACKLIST"
    else
      popup = "KA0S_LOOTHISTORY_CLEAR_WHITELIST"
    end
    if type(StaticPopup_Show) == "function" then
      StaticPopup_Show(popup)
    elseif NS.Filters and NS.Filters.ClearList then
      NS.Filters:ClearList(listKey)
    end
  end)
  clearRow:AddChild(clearBtn)
  scroll:AddChild(clearRow)
  O.AddSpacer(scroll, 4)

  scroll:AddChild(listGroup)

  -- A structural rebuild (rows added/removed), so it registers as a *rebuilder*: it fires on first
  -- paint, on an on-screen edit, and on the next OnShow after an off-screen change — never on every
  -- OnShow. Off-screen changes arrive on the HistoryChanged bus in buildFilters, which flags dirty.
  ctx.rebuilders[#ctx.rebuilders + 1] = function() rebuildFilterList(ctx, listGroup, listKey) end
end

-- The Filters TAB's three SUB-tabs, in strip order. The tab is called Filters, so none of them
-- repeats the word: "Blacklisted currencies" is Currencies here, because the only currency list
-- there is IS a blacklist and the qualifier was carrying nothing. Items first (both item lists
-- adjacent, because they are read together — an id on one is off the other), currencies last.
--
-- SECONDARY, not primary (options-ui-§13). Filters was its own canvas sub-page with its own
-- three-tab strip until R6 deprecated it into General; three id-lists are a list of like subjects
-- inside one category, which is exactly the division a secondary strip is for. O.SubTabStrip draws
-- it as ordinary page content inside the scroll, so it scrolls with the lists it divides rather
-- than pinning a second chrome band and pushing every page down twice.
--
-- Not schema groups either way: there is no Schema row for a dynamic list of item ids, so this
-- tab's body cannot come from the flow engine — it partitions ROWS, and this tab has none.
--
-- The PRIMARY tab's key, spelled once: it is both this tab's entry in GENERAL_TABS below and the
-- key `ctx.activeSubTab` is filed under, and the convention only works while the two agree.
local FILTERS_TAB = "Filters"

local FILTER_TABS = {
  { key = "blacklist", label = "Blacklist",
    desc = "Items here are never recorded when looted from now on. Existing rows are left untouched "
      .. "(this only affects future loots — delete old rows from the history table if you want them gone)." },
  { key = "whitelist", label = "Whitelist",
    desc = "Items here are always recorded, even if they fall below your quality threshold, come from a "
      .. "muted source, or are quest items. Adding an id to one list removes it from the other." },
  { key = "currencyBlacklist", label = "Currencies",
    desc = "Currencies here are never recorded when looted from now on (Valorstones, crests, Honor, etc.). "
      .. "Point-in-time — existing rows are left untouched." },
}

--- The Filters tab: a secondary strip over the three id-lists, then the selected list.
---
--- THE SUB-TAB SELECTION IS THE HOST'S STATE, and the convention the library establishes for the
--- collection is `ctx.activeSubTab` as a TABLE keyed by the PRIMARY tab's key — so switching
--- category and back returns to the list you were on, and a stale pointer heals per category. It is
--- session state and is never persisted (options-ui-§13), exactly like `ctx.activeTab`.
local function buildFiltersTab(ctx)
  local scroll = O.EnsureScroll(ctx)
  if not scroll then return end

  ctx.activeSubTab = ctx.activeSubTab or {}
  local key = ctx.activeSubTab[FILTERS_TAB]
  -- A pointer naming a list this tab no longer has would render blank, so a stale one heals to the
  -- first rather than being trusted — the same cheap check the library's own strip does.
  local known = false
  for _, tab in ipairs(FILTER_TABS) do if tab.key == key then known = true end end
  if not known then key = FILTER_TABS[1].key end
  ctx.activeSubTab[FILTERS_TAB] = key

  -- The strip's buttons are raw frames, so they need a frame to live on: a layout-suppressed
  -- SimpleGroup added as an ordinary scroll child, sized to whatever height the strip reports.
  -- ClearScroll drains the library's __subTabKids ledger BEFORE it releases this group, which is
  -- what stops the buttons riding a pooled frame into somebody else's page.
  local host = NS.AceGUI:Create("SimpleGroup")
  host:SetLayout(nil); host:SetFullWidth(true)
  scroll:AddChild(host)

  local tabs = {}
  for i, tab in ipairs(FILTER_TABS) do tabs[i] = { key = tab.key, label = tab.label } end
  local _, height = O.SubTabStrip(ctx, host.frame, {
    tabs  = tabs,
    value = key,
    onSelect = function(k)
      if k == ctx.activeSubTab[FILTERS_TAB] then return end
      ctx.activeSubTab[FILTERS_TAB] = k
      -- Structural: re-enter the page renderer, which clears the scroll and draws the newly
      -- selected list. A sub-tab click inside an already-open panel was never a protected action,
      -- so it needs no combat guard of its own (options-ui-§13).
      O.RefreshPanel(ctx, true)
    end,
  })
  host:SetHeight(height or 0)
  O.AddSpacer(scroll, 6)

  -- ONE section, the selected one. Three stacked lists were three AceGUI teardown-and-rebuilds on
  -- every paint and a page a player scrolled past two lists to reach the third; a sub-tab click now
  -- rebuilds exactly the list on screen (anti-pattern #39 is why that matters here of all pages).
  for _, tab in ipairs(FILTER_TABS) do
    if tab.key == key then makeFilterSection(ctx, tab.key, tab.desc) end
  end

  -- Live-update both lists when they change from elsewhere (the History right-click Blacklist),
  -- on a private bus target (never NS.bus-as-self) so it can't clobber other consumers. While the
  -- page is on screen we repaint immediately; while it is hidden we only flag it dirty, so the next
  -- OnShow repaints once instead of every tab click paying an AceGUI teardown+rebuild (options-ui-§11).
  if not P.__evFilters then
    local ev = NS.NewBusTarget()
    if ev then
      local onChange = function()
        if ctx.panel:IsShown() then runRebuilders(ctx) else ctx._dirty = true end
      end
      ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", onChange)
      P.__evFilters = ev
    end
  end

  runRebuilders(ctx)   -- first paint of the selected id-list
end

-- ── Auction House price table (unified collect + priority) ───────────────────────
-- ONE frame-light table replaces the old Data Collection + Priority sections. Every text column is a
-- FontString (a region, not a frame); only the genuinely-interactive cells (enable checkbox, ⓘ info)
-- plus the library's drag handle are real frames, and the row slots + their frames are created ONCE
-- and reused on every refresh — never re-allocated. This is load-bearing: the Blizzard Settings
-- canvas runs a super-linear pass over a panel's frames on tab-transition, so the previous ~213-frame
-- AH page froze the client ~1.7s when you navigated away from it (see docs/settings-panel.md).
-- Blizzard art, no files shipped: green/red ReadyCheck ticks.
--
-- ── WHAT R6 CHANGED, AND WHAT IT DELIBERATELY DID NOT ─────────────────────────────────────────
--
-- The ▲▼ arrows are gone (anti-pattern #75, options-ui-§18): the cascade is dragged now, through
-- LibKa0s-Widgets-1.0's shared ReorderList. That needed a REAL FRAME per row — the widget anchors
-- its handle to it, fades it to 0.35 while it is carried, and draws the bounded box behind it — so
-- each slot is a Frame with its FontStrings parented to it instead of eleven sets of regions on one
-- host. THE POOLING IS UNCHANGED: the slots are still created once and repainted in place, which is
-- the whole reason this page does not freeze the client.
--
-- The host draws NO row background and NO row border. The library owns both now, and a host copy
-- beside them is double chrome (options-ui-§18). It never had one, so there was nothing to delete.
local READY     = "Interface\\RaidFrame\\ReadyCheck-Ready"      -- green tick: collecting
local NOTREADY  = "Interface\\RaidFrame\\ReadyCheck-NotReady"   -- red mark: off / not installed
local INFO_ICON = "Interface\\FriendsFrame\\InformationIcon"

-- Shared column x-offsets, in px from each ROW's content origin — which is the far side of the drag
-- handle's gutter, not the row's left edge: the handle owns a fixed-width gutter at the far left and
-- row contents start beyond it (options-ui-§18). Headers and every cell add the same gutter, so the
-- columns line up: [handle] [tick] [Addon] [Price Module] [On ☑] [Status]. The ⓘ is NOT a fixed
-- column — it trails each row's Price Module text (positioned per-row in the refresh).
--
-- The old `order` column is gone with the arrows it held.
local ACOL = { tick = 2, addon = 26, module = 148, enabled = 330, status = 362 }
local AROW_H, AHEAD_H = 22, 32   -- row pitch; AHEAD_H = header→first-row gap (roomy header band)
local HEAD_Y = -8                -- header baseline inside the host (gap above the header)
local GOLD_RGB = { 0.91, 0.77, 0.42 }
-- Extremely-muted Status colors: collecting = green, not collecting = yellow, not installed = red.
local STATUS_RGB = {
  collecting    = { 0.46, 0.60, 0.46 },
  notcollecting = { 0.66, 0.62, 0.42 },
  notinstalled  = { 0.62, 0.45, 0.45 },
}

--- The handle gutter, READ off the library rather than restated (options-ui-§8/§18).
---
--- Zero without the library, and that is the honest answer rather than a fallback constant: the
--- degraded path draws no handle at all, so reserving a gutter for it would indent every column
--- past nothing.
local function handleGutter()
  local box = NS.ReorderRowBox and NS.ReorderRowBox()
  return (box and box.HANDLE_W) or 0
end

-- Human name for the addon behind a "provider:key" tag (e.g. "auctionator:minbuyout" → "Auctionator").
local function providerNameOf(tag)
  local prov = tag:match("^(.-):")
  return (prov and NS.Constants.AUCTION_PROVIDER_NAMES[prov]) or prov or tag
end

-- Short data-point label for a "provider:key" tag (the `data` column form from AUCTION_KEYS).
local function dataLabelOf(tag)
  local prov, key = tag:match("^(.-):(.+)$")
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do
    if k.provider == prov and k.key == key then return k.data or k.label end
  end
  return key or tag
end

-- Label/desc for a tag's ⓘ tooltip.
local function keyMetaOf(tag)
  local prov, key = tag:match("^(.-):(.+)$")
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do
    if k.provider == prov and k.key == key then return k.label, k.desc end
  end
  return tag, nil
end

-- GameTooltip on hover, shared by the ⓘ buttons. `getTitle`/`getBody` are read on enter so a reused
-- slot always shows its current tag's text.
local function tipScripts(btn, getTitle, getBody)
  btn:SetScript("OnEnter", function()
    if not GameTooltip then return end
    local title = getTitle and getTitle()
    if not title or title == "" then return end
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    local body = getBody and getBody()
    if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

--- Release the live reorder controller, if there is one.
---
--- CALLED AT THE TOP OF THE PAGE RENDER, before the first widget is created — not merely before the
--- list is rebuilt. Handles and row boxes are POOLED, and releasing one is what takes it off the
--- host frame it was parented to; that frame goes back to AceGUI's pool the moment ClearScroll runs,
--- so a Cancel that ran afterwards would be reclaiming chrome from a widget that already belongs to
--- something else. This is the single most common way an adoption of this widget goes wrong
--- (options-ui-§18), so it is a named function called from exactly two places rather than a line
--- someone can move.
local function cancelReorder(ctx)
  local list = ctx._priList
  ctx._priList = nil
  if list then list:Cancel() end
end

-- Re-partition the tags into three groups and repaint the reused row slots. Group order (each keeps
-- the natural priority-array order within it): Collecting → Not collecting → Addon not installed.
-- Only the Collecting group (top) is draggable, and `boundary` is what stops a drag leaving it.
local function refreshAuctionTable(ctx)
  local rows = ctx._priRows
  if not rows then return end
  local hf = ctx._priHost
  local priority = NS.AuctionPrice:ReconcilePriority()
  local capture = NS.db.global.settings.auction.capture or {}

  local collecting, notCollecting, notInstalled = {}, {}, {}
  for _, tag in ipairs(priority) do
    local prov = tag:match("^(.-):")
    if not NS.AuctionPrice:IsProviderAvailable(prov) then notInstalled[#notInstalled + 1] = tag
    elseif capture[tag] then collecting[#collecting + 1] = tag
    else notCollecting[#notCollecting + 1] = tag end
  end
  local order = {}
  for _, t in ipairs(collecting)    do order[#order + 1] = t end
  for _, t in ipairs(notCollecting) do order[#order + 1] = t end
  for _, t in ipairs(notInstalled)  do order[#order + 1] = t end
  local nActive = #collecting

  -- A repaint is a NEW controller: it holds the rows of the pass that built it (the library says so
  -- in as many words), and the old one is describing a partition that no longer exists. Safe here
  -- without the top-of-render rule above, because a repaint creates no AceGUI widget and releases
  -- none — the handles go back to the pool and come straight out of it again.
  cancelReorder(ctx)
  local list = NS.MakeReorderList{
    stride   = AROW_H,
    boundary = nActive,
    handleTooltip = "Drag to re-rank",
    -- ONE WRITE, not a run of adjacent swaps. `from`/`to` are display indices, and the collecting
    -- group occupies display slots 1..nActive, so they are indices into `collecting` directly.
    onMove = function(from, to)
      NS.AuctionPrice:MovePriorityWithin(collecting, from, to)
      runRebuilders(ctx)
    end,
  }
  ctx._priList = list

  for i, tag in ipairs(order) do
    local r = rows[i]
    local prov = tag:match("^(.-):")
    local avail = NS.AuctionPrice:IsProviderAvailable(prov)
    local on = capture[tag] and true or false
    local live = on and avail          -- collecting right now
    r._tag = tag

    r.tick:SetText("|T" .. (live and READY or NOTREADY) .. ":16|t")

    -- Addon name: no per-provider color any more — just near-white, dimmed when inactive.
    r.addon:SetText(providerNameOf(tag))
    local ag = live and 0.86 or 0.5
    r.addon:SetTextColor(ag, ag, ag)

    local mg = live and 0.9 or 0.5
    r.module:SetText(dataLabelOf(tag)); r.module:SetTextColor(mg, mg, mg)
    -- ⓘ trails the Price Module text with a small gap (per-row, since the text width varies).
    local mw = r.module:GetStringWidth() or 0
    r.info:ClearAllPoints()
    r.info:SetPoint("LEFT", r.frame, "LEFT", r._gutter + ACOL.module + mw + 6, 0)

    local sc = (not avail) and STATUS_RGB.notinstalled
      or (on and STATUS_RGB.collecting or STATUS_RGB.notcollecting)
    r.status:SetText((not avail) and "Addon not installed" or (on and "Collecting data" or "Not collecting data"))
    r.status:SetTextColor(sc[1], sc[2], sc[3])

    r.info.tex:SetVertexColor(live and 1 or 0.55, live and 1 or 0.55, live and 1 or 0.55)

    -- Enabled box: checked only when actually collecting (an uninstalled source reads unchecked),
    -- and non-interactive when the addon isn't present.
    r.check:SetValue(live)
    r.check:SetDisabled(not avail)

    -- Registered in DISPLAY order, every row, draggable or not: an inert row is still a place a drag
    -- can LAND, still counts for the index arithmetic, and still wants the bounded box — a stack
    -- where only some rows have an edge reads as a rendering fault rather than as a rule.
    if list then
      list:AddRow(r.frame, {
        draggable = i <= nActive,
        dimmed    = i > nActive,
        ghostText = providerNameOf(tag) .. " — " .. dataLabelOf(tag),
      })
    end
  end

  if list then list:Finish(hf) end
end

-- Build the unified AH Price table: gold left-aligned column headers and 11 reusable row slots (one
-- per known price source). Slots + their frames are created ONCE here; refreshAuctionTable repaints
-- them in place on every enable-toggle / drag / Defaults, so no frame is ever re-allocated. Native
-- FontStrings carry all text; only the checkbox, the ⓘ and the library's handle are frames.
--
-- THE HOST IS A RAW FRAME THIS ADDON OWNS FOR THE SESSION, not an AceGUI child. That is the whole of
-- how the pooling survives a tab strip: the tab body is re-rendered on every click, and ClearScroll
-- hands every AceGUI child back to the pool — which would orphan eleven slots of raw FontStrings
-- parented to a SimpleGroup and put the ~1.7s freeze back. So the host is created once, parked on
-- the panel while another tab is on screen, and RE-PARENTED to a fresh full-width placeholder each
-- time this tab is drawn. Nothing is ever allocated twice and nothing is ever released.
local function buildAuctionTable(ctx)
  local scroll = O.EnsureScroll(ctx)
  if not scroll then return end

  local descLabel = NS.AceGUI:Create("Label")
  descLabel:SetFullWidth(true)
  descLabel:SetText("Tick a source to collect its price at loot time; ticked sources are ranked "
    .. "top-to-bottom (drag by the handle) and the highest-ranked one you have a price for is the "
    .. "value shown. Sources you don't collect, or whose addon isn't installed, drop to the bottom.")
  scroll:AddChild(descLabel)
  O.AddSpacer(scroll, 8)

  local N = #NS.Constants.AUCTION_KEYS
  local placeholder = NS.AceGUI:Create("SimpleGroup")
  placeholder:SetLayout(nil); placeholder:SetFullWidth(true)
  placeholder:SetHeight(AHEAD_H + AROW_H * N + 8)
  scroll:AddChild(placeholder)

  local hf = ctx._priHost
  if not hf then
    hf = CreateFrame("Frame", nil, ctx.panel)
    ctx._priHost = hf
  end
  hf:SetParent(placeholder.frame)
  hf:ClearAllPoints()
  hf:SetAllPoints(placeholder.frame)
  hf:Show()

  if not ctx._priRows then
    local gutter = handleGutter()

    -- Gold, left-aligned column headers at the shared offsets (a roomy band above the first row).
    local function header(x, text)
      local fs = hf:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
      fs:SetPoint("TOPLEFT", hf, "TOPLEFT", gutter + x, HEAD_Y); fs:SetJustifyH("LEFT")
      fs:SetText(text); fs:SetTextColor(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3])
    end
    header(ACOL.addon, "Addon"); header(ACOL.module, "Price Module")
    header(ACOL.enabled, "On"); header(ACOL.status, "Status")

    -- Reusable row slots (created once). Each is a real Frame, because that is what ReorderList
    -- anchors its handle and its bounded box to and what it fades while the row is carried; the
    -- cells inside it are FontStrings plus the ⓘ and an AceGUI checkbox.
    local rows = {}
    for i = 1, N do
      local rf = CreateFrame("Frame", nil, hf)
      rf:SetPoint("TOPLEFT",  hf, "TOPLEFT",  0, -(AHEAD_H + (i - 1) * AROW_H))
      rf:SetPoint("TOPRIGHT", hf, "TOPRIGHT", 0, -(AHEAD_H + (i - 1) * AROW_H))
      rf:SetHeight(AROW_H)
      local r = { frame = rf, _gutter = gutter }

      local function fs(x)
        local f = rf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        f:SetPoint("LEFT", rf, "LEFT", gutter + x, 0); f:SetJustifyH("LEFT"); return f
      end
      r.tick = fs(ACOL.tick); r.addon = fs(ACOL.addon)
      r.module = fs(ACOL.module); r.status = fs(ACOL.status)

      local info = CreateFrame("Button", nil, rf)
      info:SetSize(16, 16)
      info:SetPoint("LEFT", rf, "LEFT", gutter + ACOL.module, 0)   -- repositioned per row
      local itex = info:CreateTexture(nil, "ARTWORK"); itex:SetAllPoints(); itex:SetTexture(INFO_ICON)
      info.tex = itex; r.info = info
      tipScripts(info, function() return (keyMetaOf(r._tag or "")) end,
                       function() return (select(2, keyMetaOf(r._tag or ""))) end)

      -- AceGUI CheckBox (the standard gold-tick control used across the panel) rather than a raw
      -- UICheckButtonTemplate — the template left a scaling artifact at this size. Parented to the
      -- ROW, never added as a scroll child, so ClearScroll cannot reclaim it either.
      local cb = NS.AceGUI:Create("CheckBox")
      cb:SetLabel("")
      cb.frame:SetParent(rf); cb.frame:ClearAllPoints()
      cb.frame:SetPoint("LEFT", rf, "LEFT", gutter + ACOL.enabled, 0); cb.frame:SetWidth(26)
      cb.frame:Show()
      cb:SetCallback("OnValueChanged", function(_, _, val)
        local tag = r._tag
        if not tag then return end
        local src = NS.Schema:Get("settings.auction.capture") or {}
        local c = {}
        for k, v in pairs(src) do c[k] = v end
        c[tag] = val or nil
        NS.Schema:Set("settings.auction.capture", c)
        runRebuilders(ctx)
      end)
      r.check = cb

      rows[i] = r
    end
    ctx._priRows = rows
  end

  -- REGISTERED ON EVERY RENDER, not only on the pass that built the slots. renderGeneral reassigns
  -- ctx.rebuilders each time (ClearScroll reassigns the library's refreshers beside it), so a
  -- rebuilder added once inside the build branch above would be dropped the first time the reader
  -- left this tab and came back — and with it the repaint every enable-toggle and every drag needs.
  ctx.rebuilders[#ctx.rebuilders + 1] = function() refreshAuctionTable(ctx) end

  refreshAuctionTable(ctx)   -- first paint, and every later paint of this tab
end
-- ── Landing page: logo + tagline + slash-command list ───────────────────────────
local function buildMainContent(ctx)
  local scroll = O.EnsureScroll(ctx)

  local logoGroup = NS.AceGUI:Create("SimpleGroup")
  logoGroup:SetLayout(nil); logoGroup:SetFullWidth(true); logoGroup:SetHeight(LOGO_SIZE)
  local tex = logoGroup.frame:CreateTexture(nil, "ARTWORK")
  tex:SetTexture(LOGO_PATH)
  tex:SetSize(LOGO_SIZE, LOGO_SIZE)
  tex:SetPoint("TOPLEFT", logoGroup.frame, "TOPLEFT", 0, 0)
  scroll:AddChild(logoGroup)
  O.AddSpacer(scroll, 8)

  local desc = NS.AceGUI:Create("Label")
  desc:SetFullWidth(true); desc:SetText(ADDON_TAGLINE)
  if desc.label and desc.label.SetFontObject and _G.GameFontHighlight then
    desc.label:SetFontObject(_G.GameFontHighlight)
  end
  scroll:AddChild(desc)
  O.AddSpacer(scroll, 12)

  local heading = NS.AceGUI:Create("Heading")
  heading:SetFullWidth(true); heading:SetHeight(O.SECTION_HEADING_H); heading:SetText("Slash Commands")
  if heading.label and heading.label.SetFontObject and _G.GameFontNormalLarge then
    heading.label:SetFontObject(_G.GameFontNormalLarge)
  end
  scroll:AddChild(heading)
  O.AddSpacer(scroll, 6)

  -- CONVERGENCE (LibKa0s adoption). This page used to carry its OWN command-row formatter — double
  -- spaces around the em dash, the dash explicitly white-wrapped, the description left bare — while
  -- settings/Slash.lua two files away already rendered the same data another way. Both now go
  -- through lib.FormatRow: single spaces, no color span on the dash, the description white.
  -- Deliberate and user-visible; do not "fix" it back. See closed issue #24 (LIBKA0S-09).
  for _, line in ipairs(NS.Slash.LandingRows and NS.Slash:LandingRows() or {}) do
    local labelRow = NS.AceGUI:Create("Label")
    labelRow:SetFullWidth(true)
    labelRow:SetText(line)
    scroll:AddChild(labelRow)
  end
end

-- ── Flow-engine hooks ───────────────────────────────────────────────────────────
--
-- Hoisted to file scope rather than rebuilt per render, which the library explicitly supports: it
-- keeps its one-shot bookkeeping in call-local sets, so a second render of the same page fires both
-- again instead of silently dropping them.

-- No `pairWith` table any more. The one entry it ever held attached "Reset Everything" to the
-- right half of the Window scale row; that button is the Master controls tab's "Reset all settings"
-- now, drawn by the composer's own afterGroup hook (settings/Schema.lua). `pairWith` fires only
-- while its path is the lone widget on its line, and Window scale is paired with Row height on the
-- Interface tab — so the hook would silently never fire, which is the worst of the two outcomes.

-- The host-drawn blocks the flow engine cannot draw itself, one per tab that has one.
--
--   Master controls — the closing button pair (Reset position | Reset all settings). NOT this
--                     file's: `O.MasterControls` returned it beside the rows, and it is passed
--                     through under the group name the composer used, because the group name IS
--                     the hook key (settings/Schema.lua).
--   Collection      — the muted-source picker. The `settings.excludedSources` row it represents is
--                     walked by the generic path and produces no widget (type = "table"; see
--                     makeMultiCheck above), so this lands exactly where that path would have put
--                     it: after the group's last row, on a fresh line.
--   AH Price        — the pooled price-source table, under the "Price sources" subsection heading
--                     the `settings.auction.capture` row declares.
--   Maintenance     — the storage readout and "Purge history…".
--
-- afterGroup is the ONLY seam that survives a tab click: the strip's onSelect re-enters the page
-- renderer, and while that does re-run this file, a block appended after the rows would land at the
-- BOTTOM of every tab rather than inside the one it belongs to.
local AFTER_GROUP = {
  ["Collection"] = function(ctx)
    local row = NS.Schema:FindRow("settings.excludedSources")
    local scroll = O.EnsureScroll(ctx)
    if row and scroll then makeMultiCheck(ctx, row, scroll) end
  end,
  ["AH Price"]   = buildAuctionTable,
  ["Maintenance"] = renderHistory,
}
AFTER_GROUP[NS.Schema.MASTER_GROUP] = NS.Schema.MasterAfterGroup

-- ── The General page's strip ────────────────────────────────────────────────────
--
-- ONE page now. Filters and AH Price were canvas sub-pages of their own until R6 deprecated them
-- into General: three pages, each with its own strip, made a player hunt for which of the three
-- held the setting they wanted, and one of the three (AH Price) drew no strip at all.
--
-- THE STRIP IS DRAWN BY HAND rather than by O.RenderTabbedSchema, and the reason is that two of the
-- six tabs hold no schema rows to partition. RenderTabbedSchema derives its tab list from `group`,
-- which is exactly right for a page whose every section is rows — and cannot name a tab whose body
-- is a dynamic list of item ids. So the tab list is declared here, each entry is either a schema
-- GROUP (rendered by the same O.RenderRows call the library would have made, `noHeadings` and all)
-- or a `build` function, and tests/test_panel.lua pins the two against each other so a group added
-- to the schema and not to this list cannot go unnoticed.
local GENERAL_TABS = {
  -- options-ui-§15: the FIRST tab, under that exact name, in every Ka0s addon.
  { key = "Master controls" },
  { key = "Collection" },
  { key = FILTERS_TAB, build = buildFiltersTab },
  { key = "AH Price" },
  { key = "Interface" },
  { key = "Maintenance" },
}

--- The rows of one schema group, in declaration order.
local function rowsOfGroup(group)
  local out = {}
  for _, row in ipairs(NS.Schema.Schema) do
    if row.page == "General" and row.group == group then out[#out + 1] = row end
  end
  return out
end

-- ── Renderers ───────────────────────────────────────────────────────────────────
--
-- Each is declared through O.SetRenderer, which owns WHEN it runs: the page's first show, and again
-- after a structural refresh marked it dirty while hidden. Every one starts by releasing the
-- previous render's children, because a renderer the library may re-run must be idempotent.

-- No banner (options-ui-§14): this addon is account-wide — every path resolves against db.global
-- and there is no profile, no per-window state and nothing for a banner to be a picker FOR. It
-- draws no page-header block either: nothing on this page applies to every tab.
local function renderGeneral(ctx)
  -- FIRST, before ClearScroll and before the first widget of the new pass exists. The reorder
  -- controller's handles and boxes are pooled and are parented to frames ClearScroll is about to
  -- hand back to AceGUI (options-ui-§18).
  cancelReorder(ctx)
  -- The pooled price host is this addon's own frame and is NOT released by ClearScroll, so it has
  -- to be taken off the placeholder it was anchored to by hand — otherwise it stays visible over
  -- whichever tab is drawn next, and its anchor rides a placeholder that has gone back to the pool.
  if ctx._priHost then
    ctx._priHost:Hide()
    ctx._priHost:SetParent(ctx.panel)
    ctx._priHost:ClearAllPoints()
  end

  O.ClearScroll(ctx)
  ctx.rebuilders = {}   -- ClearScroll reassigns the library's refreshers; these are this addon's

  -- A stale pointer heals to the first tab rather than being trusted, exactly as the library's own
  -- RenderTabbedSchema does: a tab naming a section this page no longer has would render blank.
  local known = false
  for _, tab in ipairs(GENERAL_TABS) do if tab.key == ctx.activeTab then known = true end end
  if not known then ctx.activeTab = GENERAL_TABS[1].key end

  local tabs = {}
  for i, tab in ipairs(GENERAL_TABS) do tabs[i] = { key = tab.key, label = tab.key } end
  O.TabStrip(ctx, {
    tabs  = tabs,
    value = ctx.activeTab,
    onSelect = function(key)
      if key == ctx.activeTab then return end
      ctx.activeTab = key
      -- Structural: re-enter this renderer, which clears the scroll and draws the newly selected
      -- tab. A tab click inside an already-open panel was never a protected action, so it needs no
      -- combat guard of its own (options-ui-§13); the one that matters lives in the panel's OnShow
      -- and covers the category switch Blizzard protects.
      O.RefreshPanel(ctx, true)
    end,
  })

  for _, tab in ipairs(GENERAL_TABS) do
    if tab.key == ctx.activeTab then
      if tab.build then
        tab.build(ctx)
      else
        -- `noHeadings`, exactly as RenderTabbedSchema renders an active tab: under a strip the tab
        -- IS the group's heading. A row's `subgroup` is NOT suppressed by it, which is what gives
        -- the AH Price tab its two subsection headings.
        O.RenderRows(ctx, rowsOfGroup(tab.key), AFTER_GROUP, nil, { noHeadings = true })
      end
    end
  end

  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end

function P.BuildMain(ctx)
  O.ClearScroll(ctx)
  buildMainContent(ctx)
  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end

-- ── Refresh / Defaults ──────────────────────────────────────────────────────────

--- Scalar re-sync across every registered page: widgets re-read their values, nothing is rebuilt.
function P:Refresh()
  O.RefreshScalars()
end

--- The General page's Defaults button — page-wide, and the page is the whole panel now
--- (options-ui-§13: a per-page Defaults button's blast radius MUST NOT narrow to the visible tab).
--- It therefore covers what the Filters and AH Price pages' own Defaults buttons used to:
---
---   * every schema row plus the three id-lists          — Slash:CliResetAll
---   * the auction cascade, a carve-out array with no schema row that the walk cannot see
---
--- It does NOT recentre the window any more. That was folded in here when there was nowhere else to
--- put it; "Reset position" is a real button on the Master controls tab now, and a player asking for
--- defaults no longer gets their window moved as a side effect (options-ui-§12/§15).
function P:RestoreDefaults()
  if NS.Slash and NS.Slash.CliResetAll then NS.Slash:CliResetAll() end
  -- Clear-and-refill the SAME table so the price table's closures see the new contents.
  if NS.AuctionPrice and NS.AuctionPrice.GetPriority then
    local p = NS.AuctionPrice:GetPriority()
    for i = #p, 1, -1 do p[i] = nil end
    for i, tag in ipairs(NS.Constants.AUCTION_PRIORITY_DEFAULT) do p[i] = tag end
  end
  P:Refresh()
  -- Structural as well as scalar: the price table repaints off the cascade, and the id-lists off
  -- their rebuilders, neither of which a refresher sweep touches.
  if P.general then O.RefreshPanel(P.general, true) end
end

-- ── Registration ────────────────────────────────────────────────────────────────
local registered

function P:Register()
  if registered then return end
  -- The library registers the MAIN canvas itself and survives a missing Settings API silently, but
  -- the builder below calls RegisterCanvasLayoutSubcategory directly — and a builder that raises is
  -- pcall'd and REPORTED by key, so a client without the API would print an error instead of doing
  -- nothing. Bail once, up front, exactly as this function always did.
  if not (Settings and Settings.RegisterCanvasLayoutCategory
          and Settings.RegisterCanvasLayoutSubcategory) then return end
  registered = true

  -- ONE sub-page. Filters and AH Price were sub-pages of their own until R6 folded them into
  -- General's strip; their bodies are unchanged and their two registrations are gone.
  O.RegisterOptionsPage("General", "General", function(mainCategory)
    local ctx = O.CreatePanel(nil, "General", { pageKey = "General", defaultsButton = true })
    P.general = ctx
    ctx.rebuilders = {}
    ctx.panel.defaultsOnClick = function() P:RestoreDefaults() end
    O.SetRenderer(ctx, renderGeneral)
    Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "General")
  end)

  -- Resolves AceGUI, hands it over as NS.AceGUI, registers the main canvas (whose body is the
  -- landing page, drawn on its first OnShow through the descriptor's buildMain) and then runs the
  -- builder above.
  O.CreateOptionsPanel()
end
function P:Open()
  -- The combat refusal lives in the library now, and it is wider than what it replaced: it also
  -- fires when the Blizzard AddOns sidebar reaches a page directly, which bypassed this guard
  -- entirely (options-ui-§2). It still refuses rather than deferring-and-replaying.
  O.OpenOptionsPanel()
end
