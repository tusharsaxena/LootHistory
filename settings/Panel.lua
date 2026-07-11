local addonName, NS = ...
NS.Panel = NS.Panel or {}
local P = NS.Panel
local categoryID

local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

-- ── Widget builders (one per Schema `widget` kind) ────────────────────────────
-- Each returns (widget, refresh) where refresh() re-reads the live value into the
-- widget. Every mutation routes through NS.Schema:Set (validate → write → onChange).

local function buildCheckBox(row)
  local cb = AceGUI:Create("CheckBox")
  cb:SetLabel(row.label)
  cb:SetFullWidth(true)
  cb:SetCallback("OnValueChanged", function(_, _, val)
    NS.Schema:Set(row.path, val and true or false)
  end)
  return cb, function() cb:SetValue(NS.Schema:Get(row.path) and true or false) end
end

local function buildDropdown(row)
  local dd = AceGUI:Create("Dropdown")
  dd:SetLabel(row.label)
  dd:SetFullWidth(true)
  local list, order = {}, {}
  for _, opt in ipairs(row.options) do
    list[opt.value] = opt.label
    order[#order + 1] = opt.value
  end
  dd:SetList(list, order)
  dd:SetCallback("OnValueChanged", function(_, _, key)
    NS.Schema:Set(row.path, key)
  end)
  return dd, function() dd:SetValue(NS.Schema:Get(row.path)) end
end

local function buildSlider(row)
  local sl = AceGUI:Create("Slider")
  sl:SetLabel(row.label)
  sl:SetFullWidth(true)
  sl:SetSliderValues(row.min or 0, row.max or 1, 0.05)
  sl:SetCallback("OnValueChanged", function(_, _, val)
    NS.Schema:Set(row.path, val)
  end)
  return sl, function() sl:SetValue(NS.Schema:Get(row.path) or row.default) end
end

-- Set-map of muted SourceType keys, rendered as a wrapping grid of checkboxes.
local function buildMultiCheck(row)
  local group = AceGUI:Create("InlineGroup")
  group:SetTitle(row.label)
  group:SetFullWidth(true)
  group:SetLayout("Flow")
  local boxes = {}
  for _, opt in ipairs(row.options) do
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel(opt.label)
    cb:SetWidth(150)
    cb:SetCallback("OnValueChanged", function(_, _, val)
      local cur = NS.Schema:Get(row.path) or {}
      local copy = {}
      for k, v in pairs(cur) do copy[k] = v end
      copy[opt.value] = val and true or nil
      NS.Schema:Set(row.path, copy)
    end)
    group:AddChild(cb)
    boxes[opt.value] = cb
  end
  return group, function()
    local cur = NS.Schema:Get(row.path) or {}
    for value, cb in pairs(boxes) do cb:SetValue(cur[value] and true or false) end
  end
end

local BUILDERS = {
  CheckBox   = buildCheckBox,
  Dropdown   = buildDropdown,
  Slider     = buildSlider,
  MultiCheck = buildMultiCheck,
}

-- ── Blizzard Settings canvas entry point ──────────────────────────────────────

function P:Register()
  if categoryID then return end
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local frame = CreateFrame("Frame")
  frame.OnCommit = function() end
  frame.OnDefault = function() if NS.Slash and NS.Slash.CliResetAll then NS.Slash:CliResetAll() end end
  frame.OnRefresh = function() P:Refresh() end
  local category = Settings.RegisterCanvasLayoutCategory(frame, "Ka0s Loot History")
  Settings.RegisterAddOnCategory(category)
  P.category = category
  categoryID = category:GetID()   -- numeric; do NOT overwrite category.ID (breaks OpenToCategory)
  frame:SetScript("OnShow", function()
    P:BuildBody(frame)
    P:Refresh()
  end)
end

-- Lazy raw-AceGUI body, built once on first OnShow and driven by NS.Schema.Schema.
function P:BuildBody(frame)
  if frame.__built then return end
  frame.__built = true

  if not AceGUI then
    local fs = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 16, -16)
    fs:SetText("AceGUI-3.0 not available.")
    return
  end

  local scroll = AceGUI:Create("ScrollFrame")
  scroll:SetLayout("List")
  scroll.frame:SetParent(frame)
  scroll.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
  scroll.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 10)
  scroll.frame:Show()
  P.scroll = scroll

  local heading = AceGUI:Create("Heading")
  heading:SetText("Ka0s Loot History")
  heading:SetFullWidth(true)
  scroll:AddChild(heading)

  P.refreshers = {}
  for _, row in ipairs(NS.Schema.Schema) do
    local builder = BUILDERS[row.widget]
    if builder then
      local widget, refresh = builder(row)
      scroll:AddChild(widget)
      P.refreshers[#P.refreshers + 1] = refresh
    end
  end

  -- ── History maintenance: live stats + purge ─────────────────────────────────
  local histHeading = AceGUI:Create("Heading")
  histHeading:SetText("History")
  histHeading:SetFullWidth(true)
  scroll:AddChild(histHeading)

  local statsLabel = AceGUI:Create("Label")
  statsLabel:SetFullWidth(true)
  scroll:AddChild(statsLabel)

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
    -- \226\137\136 = "≈"  (real SavedVariables file size can't be read in-game; this is estimated)
    statsLabel:SetText(line1 .. "\nDatabase size: \226\137\136 " .. NS.Util.FormatBytes(s.bytes) .. "  (estimated)")
  end
  P.refreshers[#P.refreshers + 1] = refreshStats

  local purgeBtn = AceGUI:Create("Button")
  purgeBtn:SetText("Purge history\226\128\166")   -- ellipsis: opens a confirm dialog
  purgeBtn:SetWidth(220)
  purgeBtn:SetCallback("OnClick", function()
    if type(StaticPopup_Show) == "function" then
      StaticPopup_Show("KA0S_LOOTHISTORY_PURGE")
    elseif NS.Database and NS.Database.Purge then
      NS.Database:Purge()
    end
  end)
  scroll:AddChild(purgeBtn)

  -- Live-refresh the stats when history changes while the panel is open. Uses a private
  -- AceEvent target (NOT NS.bus-as-self) so it can't clobber the Browser/Analytics
  -- consumers that register the same messages on the shared bus.
  if not P.__ev then
    local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
    if AceEvent then
      local ev = {}
      AceEvent:Embed(ev)
      local onChange = function() if frame:IsShown() then refreshStats() end end
      ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", onChange)
      ev:RegisterMessage("Ka0s_LootHistory_RecordAdded", onChange)
      P.__ev = ev
    end
  end

  scroll:DoLayout()
end

-- Re-read every live value into the widgets (after slash edits, reset, reopen).
function P:Refresh()
  if not P.refreshers then return end
  for _, refresh in ipairs(P.refreshers) do refresh() end
end

function P:Open()
  if InCombatLockdown and InCombatLockdown() then
    print("|cff33ff99" .. addonName .. "|r Can't open settings in combat.")
    return
  end
  if Settings and Settings.OpenToCategory and categoryID then
    Settings.OpenToCategory(categoryID)
  end
end
