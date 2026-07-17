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

-- Layout constants (Ka0s standard values; see WowAddonStandards §6.8).
local PADDING_X     = 16   -- left/right edge inset for header, divider, body
local HEADER_TOP    = 20   -- title + Defaults button inset from the panel top
local HEADER_HEIGHT = 54   -- top → divider; body starts at HEADER_HEIGHT + 8
local DEFAULTS_W    = 110  -- Defaults button width
local LOGO_SIZE     = 300  -- landing-page logo display size
local ROW_VSPACER   = 8    -- gap between two-column rows
local SECTION_TOP_SPACER, SECTION_BOTTOM_SPACER, SECTION_HEADING_H = 10, 6, 26
-- Cell-filling paired ACTION buttons inset to this (not 0.5) so their right border clears the
-- ScrollFrame's clip (Ka0s standard §6.6/§6.8). Label-inset controls (checkbox/dropdown/slider)
-- reserve that gutter already and stay at 0.5 — they're immune (§6.10).
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

  return { panel = panel, body = body, scroll = nil, refreshers = {}, lastGroup = nil }
end

-- LH-08 / Ka0s §6.10: keep the settings-panel scrollbar ALWAYS visible — and inert when the page
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
  installAlwaysShownScrollbar(scroll)   -- §6.10 always-shown, inert-when-fits scrollbar
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
-- right border isn't shaved by the ScrollFrame clip (§6.6/§6.8) — the single seam for the width.
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
local function renderSchema(ctx, companions)
  local scroll = ensureScroll(ctx)
  local pendingRow

  local function flushRow()
    if pendingRow then scroll:AddChild(pendingRow); addSpacer(scroll, ROW_VSPACER); pendingRow = nil end
  end
  local function startRow()
    local r = AceGUI:Create("SimpleGroup"); r:SetLayout("Flow"); r:SetFullWidth(true); return r
  end

  for _, row in ipairs(NS.Schema.Schema) do
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

-- ── Filters sub-page: blacklist / whitelist item-id management (issue #14) ────────
-- A single sub-page with two sections. Each: a short description, an "add" row (item id or a
-- shift-clicked link) and a live list of current ids with a Remove button per row. The lists are
-- core app logic, so there is deliberately no way to toggle a blacklist/whitelist *display* filter
-- — blacklisted rows just vanish from the browser and whitelisted ids always record.

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

  -- Rebuild on first paint and whenever the lists change elsewhere (e.g. the History right-click
  -- Blacklist action) while this page is open.
  local function refresh() if ctx.panel:IsShown() then rebuildFilterList(ctx, listGroup, listKey) end end
  ctx.refreshers[#ctx.refreshers + 1] = function() rebuildFilterList(ctx, listGroup, listKey) end
  return refresh
end

local function buildFilters(ctx)
  local blRefresh = makeFilterSection(ctx, "blacklist", "Blacklist",
    "Items here are never recorded, and any already-recorded rows are hidden from the browser "
    .. "(nothing is deleted — remove an id to restore its rows).")
  local wlRefresh = makeFilterSection(ctx, "whitelist", "Whitelist",
    "Items here are always recorded, even if they fall below your quality threshold, come from a "
    .. "muted source, or are quest items. Adding an id to one list removes it from the other.")

  -- Live-update both lists when they change from elsewhere (the History right-click Blacklist),
  -- on a private bus target (never NS.bus-as-self) so it can't clobber other consumers.
  if not P.__evFilters then
    local ev = NS.NewBusTarget()
    if ev then
      local onChange = function() blRefresh(); wlRefresh() end
      ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", onChange)
      P.__evFilters = ev
    end
  end
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
      })
      renderHistory(ctx)
      if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
    end
    P:Refresh()
  end)
  Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "General")

  -- Filters subcategory = blacklist / whitelist item-id management (issue #14).
  local fctx = createPanel("LootHistoryFiltersPanel", "Filters", { defaultsButton = false })
  P.filters = fctx
  local fRendered = false
  fctx.panel:SetScript("OnShow", function()
    if not fRendered then
      fRendered = true
      buildFilters(fctx)
      if fctx.scroll and fctx.scroll.DoLayout then fctx.scroll:DoLayout() end
    end
    for _, fn in ipairs(fctx.refreshers) do pcall(fn) end
    if fctx.scroll and fctx.scroll.DoLayout then fctx.scroll:DoLayout() end
  end)
  Settings.RegisterCanvasLayoutSubcategory(mainCategory, fctx.panel, "Filters")
end

function P:Open()
  if InCombatLockdown and InCombatLockdown() then
    print("Can't open settings in combat.")
    return
  end
  if Settings and Settings.OpenToCategory and mainCategoryID then
    Settings.OpenToCategory(mainCategoryID)
  end
end
