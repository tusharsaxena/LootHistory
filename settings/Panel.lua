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


-- ── History maintenance section: live DB stats + purge (Ka0s Loot History only) ──
local function renderHistory(ctx)
  local scroll = O.EnsureScroll(ctx)
  O.Section(ctx, "History")

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
  if not P.__ev then
    local ev = NS.NewBusTarget()
    if ev then
      local onChange = function() if ctx.panel:IsShown() then refreshStats() end end
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
-- A single sub-page with three sections (item blacklist, item whitelist, currency blacklist).
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
local function makeFilterSection(ctx, listKey, title, desc)
  local scroll = O.EnsureScroll(ctx)
  O.Section(ctx, title)

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

local function buildFilters(ctx)
  makeFilterSection(ctx, "blacklist", "Blacklist",
    "Items here are never recorded when looted from now on. Existing rows are left untouched "
    .. "(this only affects future loots — delete old rows from the history table if you want them gone).")
  makeFilterSection(ctx, "whitelist", "Whitelist",
    "Items here are always recorded, even if they fall below your quality threshold, come from a "
    .. "muted source, or are quest items. Adding an id to one list removes it from the other.")
  makeFilterSection(ctx, "currencyBlacklist", "Blacklisted currencies",
    "Currencies here are never recorded when looted from now on (Valorstones, crests, Honor, etc.). "
    .. "Point-in-time — existing rows are left untouched.")

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
end

-- ── Auction House price table (unified collect + priority) ───────────────────────
-- ONE frame-light table replaces the old Data Collection + Priority sections. Every text column is a
-- FontString (a region, not a frame); only the genuinely-interactive cells (enable checkbox, ⓘ info,
-- ▲▼ reorder arrows) are real frames, and the row slots + their frames are created ONCE and reused on
-- every refresh — never re-allocated. This is load-bearing: the Blizzard Settings canvas runs a
-- super-linear pass over a panel's frames on tab-transition, so the previous ~213-frame AH page froze
-- the client ~1.7s when you navigated away from it (see docs/settings-panel.md). Blizzard art, no
-- files shipped: green/red ReadyCheck ticks + ChatFrame scroll arrows.
local READY     = "Interface\\RaidFrame\\ReadyCheck-Ready"      -- green tick: collecting
local NOTREADY  = "Interface\\RaidFrame\\ReadyCheck-NotReady"   -- red mark: off / not installed
local ARR_UP    = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up"
local ARR_DN    = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"
local INFO_ICON = "Interface\\FriendsFrame\\InformationIcon"

-- Shared column x-offsets (px from each row's left edge). Headers and every cell anchor to the same
-- values so the columns line up: [tick] [Addon] [Price Module] [Order ▲▼] [On ☑] [Status]. The ⓘ is
-- NOT a fixed column — it trails each row's Price Module text (positioned per-row in the refresh).
local ACOL = { tick = 2, addon = 26, module = 148, order = 330, enabled = 384, status = 414 }
local AROW_H, AHEAD_H = 22, 32   -- row pitch; AHEAD_H = header→first-row gap (roomy header band)
local HEAD_Y = -8                -- header baseline inside the host (gap above the header)
local GOLD_RGB = { 0.91, 0.77, 0.42 }
-- Extremely-muted Status colors: collecting = green, not collecting = yellow, not installed = red.
local STATUS_RGB = {
  collecting    = { 0.46, 0.60, 0.46 },
  notcollecting = { 0.66, 0.62, 0.42 },
  notinstalled  = { 0.62, 0.45, 0.45 },
}

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

-- GameTooltip on hover, shared by the ⓘ and arrow buttons. `getTitle`/`getBody` are read on enter so
-- a reused slot always shows its current tag's text.
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

-- Lazily create a slot's ▲▼ arrow buttons (only slots that ever become active pay for them). Anchored
-- at the slot's fixed row y; created once, reused. Their OnClick is (re)wired per refresh.
local function ensureArrows(ctx, r, slotIndex)
  if r.up then return end
  local hf = ctx._priHost
  local y = -(AHEAD_H + (slotIndex - 1) * AROW_H) - 3
  local function mk(tex, dx)
    local b = CreateFrame("Button", nil, hf)
    b:SetSize(16, 16)
    b:SetPoint("TOPLEFT", hf, "TOPLEFT", ACOL.order + dx, y)
    local t = b:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); t:SetTexture(tex); b.tex = t
    return b
  end
  r.up   = mk(ARR_UP, 0)
  r.down = mk(ARR_DN, 17)
  tipScripts(r.up,   function() return "Rank higher" end)
  tipScripts(r.down, function() return "Rank lower" end)
end

-- Re-partition the tags into three groups and repaint the reused row slots. Group order (each keeps
-- the natural priority-array order within it): Collecting → Not collecting → Addon not installed.
-- Only the Collecting group (top) is reorderable.
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
    r.info:SetPoint("TOPLEFT", hf, "TOPLEFT", ACOL.module + mw + 6, r._y - 3)

    local sc = (not avail) and STATUS_RGB.notinstalled
      or (on and STATUS_RGB.collecting or STATUS_RGB.notcollecting)
    r.status:SetText((not avail) and "Addon not installed" or (on and "Collecting data" or "Not collecting data"))
    r.status:SetTextColor(sc[1], sc[2], sc[3])

    r.info.tex:SetVertexColor(live and 1 or 0.55, live and 1 or 0.55, live and 1 or 0.55)

    -- Enabled box: checked only when actually collecting (an uninstalled source reads unchecked),
    -- and non-interactive when the addon isn't present.
    r.check:SetValue(live)
    r.check:SetDisabled(not avail)

    -- Reorder arrows: only the active (top) group reorders, within itself. Inactive rows hide them.
    if i <= nActive then
      ensureArrows(ctx, r, i)
      local canUp, canDn = i > 1, i < nActive
      local upTag, dnTag = order[i - 1], order[i + 1]
      r.up:Show(); r.down:Show()
      r.up.tex:SetVertexColor(canUp and 1 or 0.35, canUp and 1 or 0.35, canUp and 1 or 0.35)
      r.down.tex:SetVertexColor(canDn and 1 or 0.35, canDn and 1 or 0.35, canDn and 1 or 0.35)
      r.up:SetScript("OnClick", canUp and function()
        NS.AuctionPrice:SwapPriorityTags(tag, upTag); runRebuilders(ctx)
      end or nil)
      r.down:SetScript("OnClick", canDn and function()
        NS.AuctionPrice:SwapPriorityTags(tag, dnTag); runRebuilders(ctx)
      end or nil)
    elseif r.up then
      r.up:Hide(); r.down:Hide()
    end
  end
end

-- Build the unified AH Price table: a description, gold left-aligned column headers, and 11 reusable
-- row slots (one per known price source). Slots + their interactive frames are created ONCE here;
-- refreshAuctionTable repaints them in place on every enable-toggle / reorder / Defaults, so no frame
-- is ever re-allocated. Native FontStrings carry all text; only the checkbox, ⓘ and arrows are frames.
local function buildAuctionTable(ctx)
  local scroll = O.EnsureScroll(ctx)
  O.Section(ctx, "Price Sources")

  local descLabel = NS.AceGUI:Create("Label")
  descLabel:SetFullWidth(true)
  descLabel:SetText("Tick a source to collect its price at loot time; ticked sources are ranked "
    .. "top-to-bottom (use the arrows) and the highest-ranked one you have a price for is the value "
    .. "shown. Sources you don't collect, or whose addon isn't installed, drop to the bottom.")
  scroll:AddChild(descLabel)
  O.AddSpacer(scroll, 8)

  local N = #NS.Constants.AUCTION_KEYS
  local host = NS.AceGUI:Create("SimpleGroup")
  host:SetLayout(nil); host:SetFullWidth(true)
  host:SetHeight(AHEAD_H + AROW_H * N + 8)
  scroll:AddChild(host)
  local hf = host.frame
  ctx._priHost = hf

  -- Gold, left-aligned column headers at the shared offsets (a roomy band above the first row).
  local function header(x, text)
    local fs = hf:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", hf, "TOPLEFT", x, HEAD_Y); fs:SetJustifyH("LEFT")
    fs:SetText(text); fs:SetTextColor(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3])
  end
  header(ACOL.addon, "Addon"); header(ACOL.module, "Price Module")
  header(ACOL.order, "Order"); header(ACOL.enabled, "On"); header(ACOL.status, "Status")

  -- Reusable row slots (created once). Text = FontStrings; ⓘ + an AceGUI checkbox are per-slot frames,
  -- arrows are created lazily by ensureArrows only for slots that become active. Cells are nudged down
  -- from the row's top edge so text/controls sit vertically centered in the ~22px band.
  local rows = {}
  for i = 1, N do
    local y = -(AHEAD_H + (i - 1) * AROW_H)
    local r = { _y = y }
    local function fs(x, dy)
      local f = hf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      f:SetPoint("TOPLEFT", hf, "TOPLEFT", x, y + dy); f:SetJustifyH("LEFT"); return f
    end
    r.tick = fs(ACOL.tick, -4); r.addon = fs(ACOL.addon, -5)
    r.module = fs(ACOL.module, -5); r.status = fs(ACOL.status, -5)

    local info = CreateFrame("Button", nil, hf)
    info:SetSize(16, 16); info:SetPoint("TOPLEFT", hf, "TOPLEFT", ACOL.module, y - 3)   -- repositioned per row
    local itex = info:CreateTexture(nil, "ARTWORK"); itex:SetAllPoints(); itex:SetTexture(INFO_ICON)
    info.tex = itex; r.info = info
    tipScripts(info, function() return (keyMetaOf(r._tag or "")) end,
                     function() return (select(2, keyMetaOf(r._tag or ""))) end)

    -- AceGUI CheckBox (the standard gold-tick control used across the panel) rather than a raw
    -- UICheckButtonTemplate — the template left a scaling artifact at this size.
    local cb = NS.AceGUI:Create("CheckBox")
    cb:SetLabel("")
    cb.frame:SetParent(hf); cb.frame:ClearAllPoints()
    cb.frame:SetPoint("TOPLEFT", hf, "TOPLEFT", ACOL.enabled, y - 1); cb.frame:SetWidth(26)
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

  ctx.rebuilders[#ctx.rebuilders + 1] = function() refreshAuctionTable(ctx) end
  refreshAuctionTable(ctx)   -- first paint
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

-- Attaches the "Reset Everything" action button as the RIGHT half of the Window scale row. The
-- label is deliberately NOT "Reset All": this is the confirm-gated TOTAL reset (settings + filter
-- lists + saved view + window geometry + a full history purge, Sl:ResetEverything), while the
-- similarly-named `/lh resetall` verb resets settings and the id-lists ONLY and never touches
-- history. Two affordances with one name and two effects is how a user loses their history to a
-- button they thought was the slash verb (LH-R-04). The KA0S_LOOTHISTORY_RESETALL dialog text has
-- always disclosed both effects; the label now agrees with it. It fires only
-- when that path is currently the lone widget on its line, which it always is here: the row above it
-- (`state.debugConsole`) is `solo` and flushes after itself.
local PAIR_WITH = {
  ["settings.windowScale"] = function(_, rowGroup)
    rowGroup:AddChild(makePairButton("Reset Everything", function()
      if type(StaticPopup_Show) == "function" then
        StaticPopup_Show("KA0S_LOOTHISTORY_RESETALL")
      elseif NS.Slash and NS.Slash.ResetEverything then
        NS.Slash:ResetEverything()
      end
    end))
  end,
}

-- The muted-source picker, drawn after Data Collection's last row — the `settings.excludedSources`
-- row it represents, which the generic path walks but cannot draw (see makeMultiCheck above), so it
-- lands exactly where that path used to put it.
local AFTER_GROUP = {
  ["Data Collection"] = function(ctx)
    local row = NS.Schema:FindRow("settings.excludedSources")
    local scroll = O.EnsureScroll(ctx)
    if row and scroll then makeMultiCheck(ctx, row, scroll) end
  end,
}

-- ── Renderers ───────────────────────────────────────────────────────────────────
--
-- Each is declared through O.SetRenderer, which owns WHEN it runs: the page's first show, and again
-- after a structural refresh marked it dirty while hidden. Every one starts by releasing the
-- previous render's children, because a renderer the library may re-run must be idempotent.

local function renderGeneral(ctx)
  O.ClearScroll(ctx)
  -- Everything except the AH Price group, which is its own sub-page. Passed as an explicit list
  -- rather than through RenderSchema, because this page spans two schema groups.
  local rows = {}
  for _, row in ipairs(NS.Schema.Schema) do
    if row.group ~= "AH Price" then rows[#rows + 1] = row end
  end
  O.RenderRows(ctx, rows, AFTER_GROUP, PAIR_WITH)
  renderHistory(ctx)
  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end

local function renderFilters(ctx)
  O.ClearScroll(ctx)
  ctx.rebuilders = {}   -- ClearScroll reassigns the library's refreshers; these are this addon's
  buildFilters(ctx)
  runRebuilders(ctx)    -- first paint of all three id-lists
end

function P.BuildMain(ctx)
  O.ClearScroll(ctx)
  buildMainContent(ctx)
  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end

-- ── Refresh / Defaults ──────────────────────────────────────────────────────────

--- Scalar re-sync across every registered page: widgets re-read their values, nothing is rebuilt.
--- Wider than what it replaced, which only ever refreshed the General page — so the AH Price page's
--- master checkbox now tracks a `/lh set` too.
function P:Refresh()
  O.RefreshScalars()
end

function P:RestoreDefaults()
  if NS.Slash and NS.Slash.CliResetAll then NS.Slash:CliResetAll() end
  -- Defaults also recenters the window (position is part of "stock state"); history/view are left alone.
  if NS.Browser and NS.Browser.ResetWindow then NS.Browser:ResetWindow() end
  P:Refresh()
end

-- ── Registration ────────────────────────────────────────────────────────────────
local registered

function P:Register()
  if registered then return end
  -- The library registers the MAIN canvas itself and survives a missing Settings API silently, but
  -- each of the three builders below calls RegisterCanvasLayoutSubcategory directly — and a builder
  -- that raises is pcall'd and REPORTED by key, so a client without the API would print three
  -- errors instead of doing nothing. Bail once, up front, exactly as this function always did.
  if not (Settings and Settings.RegisterCanvasLayoutCategory
          and Settings.RegisterCanvasLayoutSubcategory) then return end
  registered = true

  -- The three sub-pages. Each builder runs once, in order, inside O.CreateOptionsPanel — after the
  -- db is ready and after AceGUI has been resolved and handed to this file as NS.AceGUI. A builder
  -- that raises is reported by key and costs only itself.
  O.RegisterOptionsPage("General", "General", function(mainCategory)
    local ctx = O.CreatePanel(nil, "General", { pageKey = "General", defaultsButton = true })
    P.general = ctx
    ctx.rebuilders = {}
    ctx.panel.defaultsOnClick = function() P:RestoreDefaults() end
    O.SetRenderer(ctx, renderGeneral)
    Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "General")
  end)

  -- Filters = blacklist / whitelist / currency-blacklist id management (issue #14).
  O.RegisterOptionsPage("Filters", "Filters", function(mainCategory)
    local ctx = O.CreatePanel(nil, "Filters", { pageKey = "Filters", defaultsButton = true })
    P.filters = ctx
    ctx.rebuilders = {}
    -- The page holds no schema rows, so "restore defaults" here means clearing all three id-lists
    -- (their stock state is empty), confirm-gated.
    ctx.panel.defaultsOnClick = function()
      if type(StaticPopup_Show) == "function" then
        StaticPopup_Show("KA0S_LOOTHISTORY_CLEAR_FILTERS")
      elseif NS.Filters and NS.Filters.ClearAll then
        NS.Filters:ClearAll()
      end
    end
    O.SetRenderer(ctx, renderFilters)
    Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "Filters")
  end)

  -- AH Price = the price-source table and the cascade. This is the one page that keeps its OWN
  -- OnShow rather than going through O.SetRenderer, and the reason is structural: the library's
  -- renderer contract is "re-run me and I redraw the page", which means a ClearScroll releasing
  -- every AceGUI child back to the pool. This page parents eleven reusable row slots of raw
  -- FontStrings and Buttons to an AceGUI SimpleGroup's frame, created ONCE and repainted in place;
  -- releasing that group would orphan them. The ~213-frame version of this page froze the client
  -- ~1.7s on tab-transition and the pooling is what fixed it (docs/settings-panel.md).
  --
  -- Everything else on it is still the library's: the canvas, the breadcrumb header, the lazy
  -- Defaults button, the scroll, the section heading and the schema row.
  O.RegisterOptionsPage("AH Price", "AH Price", function(mainCategory)
    local ctx = O.CreatePanel(nil, "AH Price", { pageKey = "AH Price", defaultsButton = true })
    P.auction = ctx
    ctx.rebuilders = {}
    ctx.panel.defaultsOnClick = function()
      for _, r in ipairs(NS.Schema.Schema) do
        if r.group == "AH Price" then NS.Schema:Set(r.path, NS.Schema:Default(r.path)) end
      end
      -- Priority order is a carve-out array (not schema-driven), so reset it separately. Clear-and-
      -- refill the SAME table so the table's closure sees the new contents. (`capture` — the enabled
      -- set — is a schema row in the "AH Price" group, so the loop above already reset it.)
      local dp = NS.Constants.AUCTION_PRIORITY_DEFAULT
      local p = NS.AuctionPrice:GetPriority()
      for i = #p, 1, -1 do p[i] = nil end          -- clear in place (keep the same table reference)
      for i, tag in ipairs(dp) do p[i] = tag end   -- refill with defaults
      for _, fn in ipairs(ctx.refreshers) do pcall(fn) end   -- scalar: re-sync the master `enabled` box
      runRebuilders(ctx)                                     -- structural: repaint the price table
    end

    local aRendered = false
    ctx.panel:SetScript("OnShow", function()
      O.EnsureDefaultsButton(ctx.panel)
      if not aRendered then
        aRendered = true
        O.RenderSchema(ctx, "AH Price")   -- the master `enabled` checkbox; `capture` is skipRender
        buildAuctionTable(ctx)
        if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
      end
      for _, fn in ipairs(ctx.refreshers) do pcall(fn) end   -- scalar re-sync (the `enabled` checkbox)
    end)
    Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "AH Price")
  end)

  -- Resolves AceGUI, hands it over as NS.AceGUI, registers the main canvas (whose body is the
  -- landing page, drawn on its first OnShow through the descriptor's buildMain) and then runs every
  -- builder above.
  O.CreateOptionsPanel()
end

function P:Open()
  -- The combat refusal lives in the library now, and it is wider than what it replaced: it also
  -- fires when the Blizzard AddOns sidebar reaches a page directly, which bypassed this guard
  -- entirely (options-ui-§2). It still refuses rather than deferring-and-replaying.
  O.OpenOptionsPanel()
end
