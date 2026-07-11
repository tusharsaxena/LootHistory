local addonName, NS = ...
NS.Panel = NS.Panel or {}
local P = NS.Panel

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
local LOGO_PATH     = "Interface\\AddOns\\LootHistory\\media\\logo\\loothistory.logo.tga"

-- Layout constants (Ka0s standard values).
local PADDING_X     = 16
local HEADER_TOP    = 16
local HEADER_HEIGHT = 40
local DEFAULTS_W    = 100
local LOGO_SIZE     = 300
local ROW_VSPACER   = 8
local SECTION_TOP_SPACER, SECTION_BOTTOM_SPACER, SECTION_HEADING_H = 10, 6, 26

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

local function ensureScroll(ctx)
  if ctx.scroll then return ctx.scroll end
  local scroll = AceGUI:Create("ScrollFrame")
  scroll:SetLayout("List")
  scroll.frame:SetParent(ctx.body)
  scroll.frame:ClearAllPoints()
  scroll.frame:SetPoint("TOPLEFT",     ctx.body, "TOPLEFT",      PADDING_X - 4, -8)
  scroll.frame:SetPoint("BOTTOMRIGHT", ctx.body, "BOTTOMRIGHT", -(PADDING_X + 12), 8)
  scroll.frame:Show()
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

-- Set-map of muted SourceType keys, rendered full-width as a wrapping checkbox grid.
local function makeMultiCheck(ctx, row, scroll)
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
      copy[opt.value] = v and true or nil
      NS.Schema:Set(row.path, copy)
    end)
    group:AddChild(cb)
    boxes[opt.value] = cb
  end
  scroll:AddChild(group)
  ctx.refreshers[#ctx.refreshers + 1] = function()
    local cur = NS.Schema:Get(row.path) or {}
    for value, cb in pairs(boxes) do cb:SetValue(cur[value] and true or false) end
  end
end

-- ── Two-column schema render ────────────────────────────────────────────────────
-- Rows pair into 50%/50% Flow lines. A row with widget=="MultiCheck" (or wide=true)
-- breaks onto its own full-width line. Group changes emit a section heading.
local function renderSchema(ctx)
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
      if not pendingRow then pendingRow = startRow() end
      if row.widget == "CheckBox" then makeCheckbox(ctx, row, pendingRow, 0.5)
      elseif row.widget == "Dropdown" then makeDropdown(ctx, row, pendingRow, 0.5)
      elseif row.widget == "Slider" then makeSlider(ctx, row, pendingRow, 0.5) end
      if pendingRow and #pendingRow.children >= 2 then flushRow() end
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

  local purgeBtn = AceGUI:Create("Button")
  purgeBtn:SetText("Purge history\226\128\166")   -- ellipsis: opens a confirm dialog
  purgeBtn:SetRelativeWidth(0.5)
  purgeBtn:SetCallback("OnClick", function()
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

  -- Live-refresh while the panel is open. Uses a private AceEvent target (NOT
  -- NS.bus-as-self) so it can't clobber the Browser/Analytics consumers registered
  -- on the shared bus for the same messages.
  if not P.__ev then
    local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
    if AceEvent then
      local ev = {}
      AceEvent:Embed(ev)
      local onChange = function() if ctx.panel:IsShown() then refreshStats() end end
      ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", onChange)
      ev:RegisterMessage("Ka0s_LootHistory_RecordAdded", onChange)
      P.__ev = ev
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
      renderSchema(ctx)
      renderHistory(ctx)
      if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
    end
    P:Refresh()
  end)
  Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "General")
end

function P:Open()
  if InCombatLockdown and InCombatLockdown() then
    print("|cff33ff99" .. addonName .. "|r Can't open settings in combat.")
    return
  end
  if Settings and Settings.OpenToCategory and mainCategoryID then
    Settings.OpenToCategory(mainCategoryID)
  end
end
