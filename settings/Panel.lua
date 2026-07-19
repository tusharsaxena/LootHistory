local addonName, NS = ...
NS.Panel = NS.Panel or {}
local P = NS.Panel
local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer (events-frames-taint-§8)

local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

-- Ka0s settings-panel pattern (shared across Ka0s addons; see WowAddonStandards):
--   * A parent canvas category renders the LANDING PAGE — logo + one-liner +
--     slash-command list — with the same gold header every subcategory uses.
--   * Each settings group is a canvas SUBCATEGORY ("General") with a breadcrumb
--     header ("Ka0s Loot History ▸ General"), a Defaults button, and a gold divider.
--   * Bodies render schema rows into a TWO-COLUMN grid (50%/50% Flow rows);
--     section headings (AceGUI Heading, centred label flanked by dividers) group them.
-- Writes route through NS.Schema:Set (validate → write → onChange); reads via :Get.

local ADDON_TITLE   = "Ka0s Loot History"
local ADDON_TAGLINE = "Records every item you loot, attributes its source, and lets you browse and analyse it."
local LOGO_PATH     = "Interface\\AddOns\\LootHistory\\media\\logos\\loothistory.logo.tga"

-- Layout constants (Ka0s standard values; see WowAddonStandards options-ui-§8).
local PADDING_X     = 16   -- left/right edge inset for header, divider, body
local HEADER_TOP    = 20   -- title + Defaults button inset from the panel top
local HEADER_HEIGHT = 54   -- top → divider; body starts at HEADER_HEIGHT + 8
local DEFAULTS_W    = 110  -- Defaults button width
local LOGO_SIZE     = 300  -- landing-page logo display size
local ROW_VSPACER   = 8    -- gap between two-column rows
local SECTION_TOP_SPACER, SECTION_BOTTOM_SPACER, SECTION_HEADING_H = 10, 6, 26
-- Cell-filling paired ACTION buttons inset to this (not 0.5) so their right border clears the
-- ScrollFrame's clip (options-ui-§6/§8). Label-inset controls (checkbox/dropdown/slider)
-- reserve that gutter already and stay at 0.5 — they're immune (options-ui-§10).
local BUTTON_PAIR_REL = 0.492

local mainCategoryID  -- parent "Ka0s Loot History" category (target of /lh config)
local registered

-- ── Tooltip helper (AceGUI widget via SetCallback, plain frame via HookScript) ──
local function attachTooltip(widget, label, tooltip)
  if not widget or not tooltip then return end
  local anchor = widget.frame or widget
  if not anchor then return end
  local function show()
    if not GameTooltip then return end
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    if label and label ~= "" then GameTooltip:SetText(label, 1, 1, 1) end
    GameTooltip:AddLine(tooltip, nil, nil, nil, true)
    GameTooltip:Show()
  end
  local function hide() if GameTooltip then GameTooltip:Hide() end end
  if widget.SetCallback then
    widget:SetCallback("OnEnter", show); widget:SetCallback("OnLeave", hide)
  elseif widget.HookScript then
    widget:HookScript("OnEnter", show); widget:HookScript("OnLeave", hide)
  end
end

-- ── Header: "Ka0s Loot History ▸ <title>" + Defaults button + gold divider ──────
local function buildHeader(panel, title, opts)
  local displayTitle = title
  if not opts.isMain then
    displayTitle = ADDON_TITLE .. " |A:common-icon-forwardarrow:16:16|a " .. title
  end

  local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  titleFS:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING_X, -HEADER_TOP)
  titleFS:SetText(displayTitle)

  local divider = panel:CreateTexture(nil, "ARTWORK")
  divider:SetAtlas("Options_HorizontalDivider", true)
  divider:SetPoint("TOPLEFT",  panel, "TOPLEFT",   PADDING_X, -HEADER_HEIGHT)
  divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PADDING_X, -HEADER_HEIGHT)
  divider:SetVertexColor(titleFS:GetTextColor())   -- track the title's gold

  if opts.defaultsButton and AceGUI then
    local btn = AceGUI:Create("Button")
    btn:SetText("Defaults")
    btn:SetWidth(DEFAULTS_W)
    btn.frame:SetParent(panel)
    btn.frame:ClearAllPoints()
    btn.frame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PADDING_X, -HEADER_TOP)
    btn.frame:Show()
    panel.defaultsBtn = btn
  end
  return titleFS, divider
end

-- ── CreatePanel — a Frame for RegisterCanvasLayout(Sub)category + ctx ───────────
local function createPanel(name, title, opts)
  opts = opts or {}
  local panel = CreateFrame("Frame", name)
  panel.name = title
  panel:Hide()
  buildHeader(panel, title, opts)

  local body = CreateFrame("Frame", nil, panel)
  body:SetPoint("TOPLEFT",     panel, "TOPLEFT",     0, -(HEADER_HEIGHT + 8))
  body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

  -- `refreshers` re-sync scalar widget *values* in place (cheap, run on every OnShow); `rebuilders`
  -- tear down + recreate list rows (structural — expensive). Per options-ui-§11 a structural rebuild
  -- runs only on first paint, on an on-screen edit, or when `dirty` marks an off-screen change — never
  -- on every OnShow (that is anti-pattern #39, the ~1s tab-click freeze).
  return { panel = panel, body = body, scroll = nil, refreshers = {}, rebuilders = {}, dirty = false, lastGroup = nil }
end

-- LH-08 / options-ui-§10: keep the settings-panel scrollbar ALWAYS visible — and inert when the page
-- fits — so the reserved right gutter, and therefore the body width, is identical across short and
-- long subcategories. AceGUI's stock FixScroll hides the bar and reclaims the 20px gutter when
-- content fits, which shifts body width between pages. This per-instance override keeps the bar
-- shown and the gutter reserved at all times; when there's nothing to scroll it parks the thumb at
-- the top and disables it (greyed). Mirrors the stock FixScroll math — note AceGUI's swapped names:
-- `height` is the visible frame height, `viewheight` is the content height.
local function installAlwaysShownScrollbar(scroll)
  local bar = scroll.scrollbar
  if not (bar and scroll.scrollframe and scroll.content) then return end

  local function setInert(inert)
    if inert then
      if bar.Disable then bar:Disable() end
    else
      if bar.Enable then bar:Enable() end
    end
    local up, down = bar.ScrollUpButton, bar.ScrollDownButton
    if up and up.SetEnabled then up:SetEnabled(not inert) end
    if down and down.SetEnabled then down:SetEnabled(not inert) end
  end

  -- Wheel-scroll must be inert when the page fits. AceGUI's stock MoveScroll only gates on
  -- `scrollBarShown`, which this override keeps permanently true (to reserve the gutter) — so
  -- without this guard the wheel would still drift the parked thumb on a short page even though
  -- there's nothing to scroll (LH-08 / smoke-test S-4). Mirror FixScroll's fits check and no-op.
  local stockMoveScroll = scroll.MoveScroll
  scroll.MoveScroll = function(self, value)
    local height, viewheight = self.scrollframe:GetHeight(), self.content:GetHeight()
    if viewheight < height + 2 then return end
    return stockMoveScroll(self, value)
  end

  scroll.FixScroll = function(self)
    if self.updateLock then return end
    self.updateLock = true
    local status = self.status or self.localstatus
    local height, viewheight = self.scrollframe:GetHeight(), self.content:GetHeight()
    local offset = status.offset or 0
    -- Reserve the gutter + show the bar once (mirrors the stock "show" branch, minus the
    -- auto-hide path). Once shown it stays shown, so the body never reflows between pages.
    if not self.scrollBarShown then
      self.scrollBarShown = true
      self.scrollbar:Show()
      self.scrollframe:SetPoint("BOTTOMRIGHT", -20, 0)
      if self.content.original_width then
        self.content.width = self.content.original_width - 20
      end
      self:DoLayout()
    end
    if viewheight < height + 2 then
      -- content fits: park the thumb at the top and make the bar inert (greyed)
      self.scrollbar:SetValue(0)
      setInert(true)
    else
      -- content overflows: a normal, draggable scrollbar
      setInert(false)
      local value = (offset / (viewheight - height) * 1000)
      if value > 1000 then value = 1000 end
      self.scrollbar:SetValue(value)
      self:SetScroll(value)
      if value < 1000 then
        self.content:ClearAllPoints()
        self.content:SetPoint("TOPLEFT", 0, offset)
        self.content:SetPoint("TOPRIGHT", 0, offset)
        status.offset = offset
      end
    end
    self.updateLock = nil
  end
end

local function ensureScroll(ctx)
  if ctx.scroll then return ctx.scroll end
  local scroll = AceGUI:Create("ScrollFrame")
  scroll:SetLayout("List")
  scroll.frame:SetParent(ctx.body)
  scroll.frame:ClearAllPoints()
  scroll.frame:SetPoint("TOPLEFT",     ctx.body, "TOPLEFT",      PADDING_X - 4, -8)
  scroll.frame:SetPoint("BOTTOMRIGHT", ctx.body, "BOTTOMRIGHT", -(PADDING_X + 12), 8)
  scroll.frame:Show()
  installAlwaysShownScrollbar(scroll)   -- options-ui-§10 always-shown, inert-when-fits scrollbar
  ctx.scroll = scroll
  return scroll
end

local function addSpacer(scroll, height)
  local sp = AceGUI:Create("SimpleGroup")
  sp:SetLayout(nil); sp:SetFullWidth(true); sp:SetHeight(height)
  scroll:AddChild(sp)
end

-- Section heading: centred gold label flanked by side dividers (Ka0s standard).
local function section(ctx, label)
  local scroll = ensureScroll(ctx)
  if ctx.lastGroup ~= nil then addSpacer(scroll, SECTION_TOP_SPACER) end
  local h = AceGUI:Create("Heading")
  h:SetText(label); h:SetFullWidth(true); h:SetHeight(SECTION_HEADING_H)
  if h.label and h.label.SetFontObject and _G.GameFontNormalLarge then
    h.label:SetFontObject(_G.GameFontNormalLarge)
  end
  scroll:AddChild(h)
  addSpacer(scroll, SECTION_BOTTOM_SPACER)
end

-- ── Widget makers ───────────────────────────────────────────────────────────────
local function applyWidth(w, rel)
  if rel then w:SetRelativeWidth(rel) else w:SetFullWidth(true) end
end

-- Shared maker for a paired action button (Reset All, Purge). Insets to BUTTON_PAIR_REL so the
-- right border isn't shaved by the ScrollFrame clip (options-ui-§6/§8) — the single seam for the width.
local function makePairButton(text, onClick)
  local btn = AceGUI:Create("Button")
  btn:SetText(text)
  btn:SetRelativeWidth(BUTTON_PAIR_REL)
  if onClick then btn:SetCallback("OnClick", onClick) end
  return btn
end

local function makeCheckbox(ctx, row, parent, rel)
  local cb = AceGUI:Create("CheckBox")
  cb:SetLabel(row.label); applyWidth(cb, rel)
  cb:SetCallback("OnValueChanged", function(_, _, v) NS.Schema:Set(row.path, v and true or false) end)
  attachTooltip(cb, row.label, row.tooltip)
  parent:AddChild(cb)
  ctx.refreshers[#ctx.refreshers + 1] = function() cb:SetValue(NS.Schema:Get(row.path) and true or false) end
  cb:SetValue(NS.Schema:Get(row.path) and true or false)
  return cb
end

local function makeDropdown(ctx, row, parent, rel)
  local dd = AceGUI:Create("Dropdown")
  dd:SetLabel(row.label); applyWidth(dd, rel)
  local list, order = {}, {}
  for i, opt in ipairs(row.options) do list[opt.value] = opt.label; order[i] = opt.value end
  dd:SetList(list, order)
  dd:SetCallback("OnValueChanged", function(_, _, key) NS.Schema:Set(row.path, key) end)
  attachTooltip(dd, row.label, row.tooltip)
  parent:AddChild(dd)
  ctx.refreshers[#ctx.refreshers + 1] = function() dd:SetValue(NS.Schema:Get(row.path)) end
  dd:SetValue(NS.Schema:Get(row.path))
  return dd
end

local function makeSlider(ctx, row, parent, rel)
  local s = AceGUI:Create("Slider")
  s:SetLabel(row.label)
  s:SetSliderValues(row.min or 0, row.max or 1, row.step or 0.05)
  applyWidth(s, rel)
  s:SetCallback("OnMouseUp", function(_, _, v) NS.Schema:Set(row.path, v) end)
  attachTooltip(s, row.label, row.tooltip)
  parent:AddChild(s)
  ctx.refreshers[#ctx.refreshers + 1] = function() s:SetValue(NS.Schema:Get(row.path) or row.default) end
  s:SetValue(NS.Schema:Get(row.path) or row.default)
  return s
end

-- Set-map (excludedSources) rendered full-width as a wrapping checkbox grid. With
-- row.invert, a *checked* box means the source is recorded (i.e. NOT in the muted set),
-- so the stored value is the logical inverse of the checkbox state.
local function makeMultiCheck(ctx, row, scroll)
  local invert = row.invert
  local group = AceGUI:Create("InlineGroup")
  group:SetTitle(row.label); group:SetFullWidth(true); group:SetLayout("Flow")
  local boxes = {}
  for _, opt in ipairs(row.options) do
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel(opt.label); cb:SetWidth(150)
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

-- ── Two-column schema render ────────────────────────────────────────────────────
-- Rows pair into 50%/50% Flow lines. A row with widget=="MultiCheck" (or wide=true)
-- breaks onto its own full-width line. Group changes emit a section heading.
-- `companions` optionally maps a row's path → function(parentRow) that adds a widget
-- (e.g. an action button) into the SAME row, right of the field, then flushes it.
local function renderSchema(ctx, companions, opts)
  opts = opts or {}
  local scroll = ensureScroll(ctx)
  local pendingRow

  local function flushRow()
    if pendingRow then scroll:AddChild(pendingRow); addSpacer(scroll, ROW_VSPACER); pendingRow = nil end
  end
  local function startRow()
    local r = AceGUI:Create("SimpleGroup"); r:SetLayout("Flow"); r:SetFullWidth(true); return r
  end

  for _, row in ipairs(NS.Schema.Schema) do
    local include = not ((opts.only and row.group ~= opts.only)
      or (opts.skip and row.group and opts.skip[row.group])
      or row.panelSkip)   -- panelSkip rows render via a bespoke section, not the generic path
    if include then
      if row.group and row.group ~= ctx.lastGroup then
        flushRow(); section(ctx, row.group); ctx.lastGroup = row.group
      end

      if row.widget == "MultiCheck" or row.wide then
        flushRow()
        makeMultiCheck(ctx, row, scroll)
      else
        -- soloRow widgets sit alone on their own row: flush any half-filled row first so they start fresh.
        if row.soloRow then flushRow() end
        if not pendingRow then pendingRow = startRow() end
        if row.widget == "CheckBox" then makeCheckbox(ctx, row, pendingRow, 0.5)
        elseif row.widget == "Dropdown" then makeDropdown(ctx, row, pendingRow, 0.5)
        elseif row.widget == "Slider" then makeSlider(ctx, row, pendingRow, 0.5) end
        local comp = companions and companions[row.path]
        if comp then
          comp(pendingRow)
          flushRow()
        elseif row.soloRow or #pendingRow.children >= 2 then
          flushRow()
        end
      end
    end
  end
  flushRow()
end

-- ── History maintenance section: live DB stats + purge (Ka0s Loot History only) ──
local function renderHistory(ctx)
  local scroll = ensureScroll(ctx)
  section(ctx, "History")

  local rowFrame = AceGUI:Create("SimpleGroup")
  rowFrame:SetLayout("Flow"); rowFrame:SetFullWidth(true)

  local statsLabel = AceGUI:Create("Label")
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
local function runRebuilders(ctx)
  for _, fn in ipairs(ctx.rebuilders or {}) do pcall(fn) end
  ctx.dirty = false
  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end

-- ── Filters sub-page: blacklist / whitelist item-id management ────────────────────
-- A single sub-page with two sections. Each: a short description, an "add" row (item id or a
-- shift-clicked link) and a live list of current ids with a Remove button per row. The lists are
-- core app logic and act point-in-time: blacklisted ids are dropped at loot time and whitelisted
-- ids are always recorded — neither list ever hides or restores an already-stored row.

-- Display name for an id: "Name  (id)" once cached, "Item id" until the client caches it (a
-- background load is kicked off so a later rebuild fills the name in).
local function filterEntryLabel(id, onCached)
  local name, quality = NS.Compat.ItemNameQuality(id)
  if not name then
    if NS.Compat.LoadItem then NS.Compat.LoadItem(id, onCached) end
    return "|cffaaaaaaItem " .. id .. "|r"
  end
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
  local hex = c and c.color and c.color:GenerateHexColor()
  local shown = hex and ("|c" .. hex .. name .. "|r") or name
  return shown .. "  |cff808080(" .. id .. ")|r"
end

-- Rebuild `listGroup` from the ids currently on `listKey`. Each row: item label + Remove button.
local function rebuildFilterList(ctx, listGroup, listKey)
  listGroup:ReleaseChildren()
  local set = (listKey == "blacklist") and NS.Filters:Blacklist() or NS.Filters:Whitelist()
  local ids = NS.Filters:SortedIDs(set)
  if #ids == 0 then
    local empty = AceGUI:Create("Label")
    empty:SetFullWidth(true)
    empty:SetText("|cff808080(none)|r")
    listGroup:AddChild(empty)
  else
    for _, id in ipairs(ids) do
      local rowG = AceGUI:Create("SimpleGroup")
      rowG:SetLayout("Flow"); rowG:SetFullWidth(true)
      local lbl = AceGUI:Create("Label")
      lbl:SetRelativeWidth(0.78)
      lbl:SetText(filterEntryLabel(id, function()
        if ctx.panel:IsShown() then rebuildFilterList(ctx, listGroup, listKey) end
      end))
      rowG:AddChild(lbl)
      local rm = AceGUI:Create("Button")
      rm:SetText("Remove"); rm:SetRelativeWidth(0.20)
      rm:SetCallback("OnClick", function()
        if listKey == "blacklist" then NS.Filters:RemoveBlacklist(id) else NS.Filters:RemoveWhitelist(id) end
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
  local scroll = ensureScroll(ctx)
  section(ctx, title)

  local descLabel = AceGUI:Create("Label")
  descLabel:SetFullWidth(true); descLabel:SetText(desc)
  scroll:AddChild(descLabel)
  addSpacer(scroll, 6)

  local listGroup = AceGUI:Create("SimpleGroup")
  listGroup:SetLayout("List"); listGroup:SetFullWidth(true)

  local addRow = AceGUI:Create("SimpleGroup")
  addRow:SetLayout("Flow"); addRow:SetFullWidth(true)
  local box = AceGUI:Create("EditBox")
  box:SetLabel("Add item id or link"); box:SetRelativeWidth(0.78)
  local function submit()
    local id = NS.Filters:ParseItemID(box:GetText())
    if not id then
      if NS.Print then NS.Print("enter a numeric item id (or shift-click an item link).") end
      return
    end
    if listKey == "blacklist" then NS.Filters:AddBlacklist(id) else NS.Filters:AddWhitelist(id) end
    box:SetText("")
    rebuildFilterList(ctx, listGroup, listKey)
    if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
  end
  box:SetCallback("OnEnterPressed", function() submit() end)
  addRow:AddChild(box)
  local addBtn = AceGUI:Create("Button")
  addBtn:SetText("Add"); addBtn:SetRelativeWidth(0.20)
  addBtn:SetCallback("OnClick", submit)
  addRow:AddChild(addBtn)
  scroll:AddChild(addRow)
  addSpacer(scroll, 4)

  -- Bulk "Clear all" for this list (confirm-gated). The list view refreshes itself via the
  -- HistoryChanged listener that Filters:ClearList fires, so the button only shows the popup.
  local clearRow = AceGUI:Create("SimpleGroup")
  clearRow:SetLayout("Flow"); clearRow:SetFullWidth(true)
  local clearBtn = AceGUI:Create("Button")
  clearBtn:SetText("Clear all"); clearBtn:SetRelativeWidth(0.30)
  clearBtn:SetCallback("OnClick", function()
    local popup = (listKey == "blacklist") and "KA0S_LOOTHISTORY_CLEAR_BLACKLIST"
      or "KA0S_LOOTHISTORY_CLEAR_WHITELIST"
    if type(StaticPopup_Show) == "function" then
      StaticPopup_Show(popup)
    elseif NS.Filters and NS.Filters.ClearList then
      NS.Filters:ClearList(listKey)
    end
  end)
  clearRow:AddChild(clearBtn)
  scroll:AddChild(clearRow)
  addSpacer(scroll, 4)

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

  -- Live-update both lists when they change from elsewhere (the History right-click Blacklist),
  -- on a private bus target (never NS.bus-as-self) so it can't clobber other consumers. While the
  -- page is on screen we repaint immediately; while it is hidden we only flag it dirty, so the next
  -- OnShow repaints once instead of every tab click paying an AceGUI teardown+rebuild (options-ui-§11).
  if not P.__evFilters then
    local ev = NS.NewBusTarget()
    if ev then
      local onChange = function()
        if ctx.panel:IsShown() then runRebuilders(ctx) else ctx.dirty = true end
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
-- Extremely-muted Status colours: collecting = green, not collecting = yellow, not installed = red.
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

    -- Addon name: no per-provider colour any more — just near-white, dimmed when inactive.
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
  local scroll = ensureScroll(ctx)
  section(ctx, "Price Sources")

  local descLabel = AceGUI:Create("Label")
  descLabel:SetFullWidth(true)
  descLabel:SetText("Tick a source to collect its price at loot time; ticked sources are ranked "
    .. "top-to-bottom (use the arrows) and the highest-ranked one you have a price for is the value "
    .. "shown. Sources you don't collect, or whose addon isn't installed, drop to the bottom.")
  scroll:AddChild(descLabel)
  addSpacer(scroll, 8)

  local N = #NS.Constants.AUCTION_KEYS
  local host = AceGUI:Create("SimpleGroup")
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
  -- from the row's top edge so text/controls sit vertically centred in the ~22px band.
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
    local cb = AceGUI:Create("CheckBox")
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
  local scroll = ensureScroll(ctx)

  local logoGroup = AceGUI:Create("SimpleGroup")
  logoGroup:SetLayout(nil); logoGroup:SetFullWidth(true); logoGroup:SetHeight(LOGO_SIZE)
  local tex = logoGroup.frame:CreateTexture(nil, "ARTWORK")
  tex:SetTexture(LOGO_PATH)
  tex:SetSize(LOGO_SIZE, LOGO_SIZE)
  tex:SetPoint("TOPLEFT", logoGroup.frame, "TOPLEFT", 0, 0)
  scroll:AddChild(logoGroup)
  addSpacer(scroll, 8)

  local desc = AceGUI:Create("Label")
  desc:SetFullWidth(true); desc:SetText(ADDON_TAGLINE)
  if desc.label and desc.label.SetFontObject and _G.GameFontHighlight then
    desc.label:SetFontObject(_G.GameFontHighlight)
  end
  scroll:AddChild(desc)
  addSpacer(scroll, 12)

  local heading = AceGUI:Create("Heading")
  heading:SetFullWidth(true); heading:SetHeight(SECTION_HEADING_H); heading:SetText("Slash Commands")
  if heading.label and heading.label.SetFontObject and _G.GameFontNormalLarge then
    heading.label:SetFontObject(_G.GameFontNormalLarge)
  end
  scroll:AddChild(heading)
  addSpacer(scroll, 6)

  for _, cmd in ipairs(NS.COMMANDS or {}) do
    local labelRow = AceGUI:Create("Label")
    labelRow:SetFullWidth(true)
    labelRow:SetText(("|cffffff00/lh %s|r  |cffffffff\226\128\148|r  %s"):format(cmd.name, cmd.desc))
    scroll:AddChild(labelRow)
  end
end

-- ── Refresh / Defaults ──────────────────────────────────────────────────────────
function P:Refresh()
  if not P.general or not P.general.refreshers then return end
  for _, fn in ipairs(P.general.refreshers) do pcall(fn) end
end

function P:RestoreDefaults()
  if NS.Slash and NS.Slash.CliResetAll then NS.Slash:CliResetAll() end
  -- Defaults also recentres the window (position is part of "stock state"); history/view are left alone.
  if NS.Browser and NS.Browser.ResetWindow then NS.Browser:ResetWindow() end
  P:Refresh()
end

-- ── Registration ────────────────────────────────────────────────────────────────
function P:Register()
  if registered then return end
  if not (AceGUI and Settings and Settings.RegisterCanvasLayoutCategory
          and Settings.RegisterCanvasLayoutSubcategory) then return end
  registered = true

  -- Parent category = landing page.
  local mainCtx = createPanel("LootHistoryMainPanel", ADDON_TITLE, { isMain = true })
  local mainRendered = false
  mainCtx.panel:SetScript("OnShow", function()
    if mainRendered then return end
    mainRendered = true
    buildMainContent(mainCtx)
    if mainCtx.scroll and mainCtx.scroll.DoLayout then mainCtx.scroll:DoLayout() end
  end)
  local mainCategory = Settings.RegisterCanvasLayoutCategory(mainCtx.panel, ADDON_TITLE)
  Settings.RegisterAddOnCategory(mainCategory)
  mainCategoryID = mainCategory and mainCategory.GetID and mainCategory:GetID()

  -- General subcategory = the actual settings.
  local ctx = createPanel("LootHistoryGeneralPanel", "General", { defaultsButton = true })
  P.general = ctx
  if ctx.panel.defaultsBtn then
    ctx.panel.defaultsBtn:SetCallback("OnClick", function() P:RestoreDefaults() end)
  end
  local rendered = false
  ctx.panel:SetScript("OnShow", function()
    if not rendered then
      rendered = true
      -- "Reset All" sits to the right of Window scale; it wipes history AND settings.
      renderSchema(ctx, {
        ["settings.windowScale"] = function(parentRow)
          local btn = makePairButton("Reset All", function()
            if type(StaticPopup_Show) == "function" then
              StaticPopup_Show("KA0S_LOOTHISTORY_RESETALL")
            elseif NS.Slash and NS.Slash.ResetEverything then
              NS.Slash:ResetEverything()
            end
          end)
          parentRow:AddChild(btn)
        end,
      }, { skip = { ["AH Price"] = true } })
      renderHistory(ctx)
      if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
    end
    P:Refresh()
  end)
  Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "General")

  -- Filters subcategory = blacklist / whitelist item-id management (issue #14).
  local fctx = createPanel("LootHistoryFiltersPanel", "Filters", { defaultsButton = true })
  P.filters = fctx
  -- Defaults here = clear both id-lists (their stock state is empty), confirm-gated. The page holds
  -- no Schema rows, so this is the "restore defaults" for what it manages.
  if fctx.panel.defaultsBtn then
    fctx.panel.defaultsBtn:SetCallback("OnClick", function()
      if type(StaticPopup_Show) == "function" then
        StaticPopup_Show("KA0S_LOOTHISTORY_CLEAR_FILTERS")
      elseif NS.Filters and NS.Filters.ClearAll then
        NS.Filters:ClearAll()
      end
    end)
  end
  local fRendered = false
  fctx.panel:SetScript("OnShow", function()
    if not fRendered then
      fRendered = true
      buildFilters(fctx)
      runRebuilders(fctx)          -- first paint of both id-lists
    elseif fctx.dirty then
      runRebuilders(fctx)          -- lists changed while hidden → repaint once (options-ui-§11)
    end
    -- Scalar re-sync only (none on this page today; kept for symmetry). The structural list rebuild
    -- above is gated so a plain tab click with no change costs nothing — no per-click freeze.
    for _, fn in ipairs(fctx.refreshers) do pcall(fn) end
  end)
  Settings.RegisterCanvasLayoutSubcategory(mainCategory, fctx.panel, "Filters")

  -- AH Price subcategory = the AH-price cascade settings (own page).
  local actx = createPanel("LootHistoryAuctionPanel", "AH Price", { defaultsButton = true })
  P.auction = actx
  if actx.panel.defaultsBtn then
    actx.panel.defaultsBtn:SetCallback("OnClick", function()
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
      for _, fn in ipairs(actx.refreshers) do pcall(fn) end   -- scalar: re-sync the master `enabled` box
      runRebuilders(actx)                                     -- structural: repaint the price table
    end)
  end
  local aRendered = false
  actx.panel:SetScript("OnShow", function()
    if not aRendered then
      aRendered = true
      renderSchema(actx, nil, { only = "AH Price" })   -- the master `enabled` checkbox
      buildAuctionTable(actx)
      if actx.scroll and actx.scroll.DoLayout then actx.scroll:DoLayout() end
    end
    for _, fn in ipairs(actx.refreshers) do pcall(fn) end   -- scalar re-sync (the `enabled` checkbox)
  end)
  Settings.RegisterCanvasLayoutSubcategory(mainCategory, actx.panel, "AH Price")
end

function P:Open()
  if InCombatLockdown and InCombatLockdown() then
    -- options-ui-§2: refuse in combat (Blizzard's category-switch is protected). Grey notice, early
    -- return — never defer-and-replay on PLAYER_REGEN_ENABLED. \226\128\148 = em-dash.
    print("|cff808080cannot open settings during combat \226\128\148 Blizzard's category-switch is protected|r")
    return
  end
  if Settings and Settings.OpenToCategory and mainCategoryID then
    Settings.OpenToCategory(mainCategoryID)
  end
end
