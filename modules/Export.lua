local addonName, NS = ...   -- luacheck: ignore addonName
NS.Export = NS.Export or {}
local E = NS.Export

-- ── Serialization ────────────────────────────────────────────────────────────────
-- Pure, unit-tested helpers (CSV text, Wowhead URL, bind-state labels). The modal UI below
-- consumes them; it is built lazily and needs the live client, so it is smoke-tested, not unit-
-- tested. Export is called directly by the Browser (NS.Export:Open) — it registers no bus message.

-- Friendly bind-state labels, matching the Bound column's tooltip legend. nil/"NONE" = Not Bound.
local BOUND_LABEL = {
  NONE = "Not Bound", BOE = "Bind on Equip", BOP = "Bind on Pickup",
  ACCOUNT = "Account Bound", WARBAND = "Warbound",
}
function E:BoundLabel(token) return BOUND_LABEL[token or "NONE"] or tostring(token) end

-- Plain-text money for CSV: always "Ng Ns Nc" (never the in-game coin-texture markup that
-- Util.FormatMoney emits). "" for nil so a missing sellPrice stays blank.
local function money(copper)
  if copper == nil then return "" end
  copper = tonumber(copper) or 0
  return string.format("%dg %ds %dc",
    math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100)
end

-- Split a colon-delimited itemString into fields, preserving empty fields (a trailing sentinel
-- guarantees the final field is captured). "1:2::4" -> { "1", "2", "", "4" }.
local function splitColons(s)
  local parts = {}
  for field in (s .. ":"):gmatch("(.-):") do parts[#parts + 1] = field end
  return parts
end

-- Build a Wowhead item URL from a record's itemLink, carrying bonus IDs (the modifiers Wowhead
-- needs to reconstruct the exact item — ilvl, tertiaries, sockets). itemString layout:
--   itemID : enchant : gem1..gem4 : suffix : unique : linkLevel : specID : modifiersMask :
--   itemContext : numBonusIDs : bonusID1..N : numModifiers : ...
-- so itemID is field 1 and numBonusIDs is field 13. Falls back to a bare item=<id>, or "".
function E:WowheadLink(record)
  record = record or {}
  local itemStr = record.itemLink and record.itemLink:match("|?H?item:([%-%d:]+)")
  local id, bonuses
  if itemStr then
    local parts = splitColons(itemStr)
    id = tonumber(parts[1])
    local numBonus = tonumber(parts[13]) or 0
    if numBonus > 0 then
      local b = {}
      for i = 14, 13 + numBonus do
        if parts[i] and parts[i] ~= "" then b[#b + 1] = parts[i] end
      end
      if #b > 0 then bonuses = table.concat(b, ":") end
    end
  end
  id = id or tonumber(record.itemID)
  if not id then return "" end
  local url = "https://www.wowhead.com/item=" .. id
  if bonuses then url = url .. "?bonus=" .. bonuses end
  return url
end

-- RFC-4180 field quoting: wrap on comma/quote/CR/LF; double embedded quotes.
local function csvField(v)
  if v == nil then return "" end
  local s = tostring(v)
  if s:find('[,"\r\n]') then s = '"' .. s:gsub('"', '""') .. '"' end
  return s
end

-- CSV columns: { header, value(record) }. `ts` is followed by human `date` (DD-MMM-YYYY) and
-- `time` (HH:MM). Renamed raw columns carry a *Raw suffix beside a human sibling: human `quality`
-- (label) before `qualityRaw` (number), human `sellPrice` ("Ng Ns Nc") before `sellPriceRaw`
-- (copper). `bound` is the friendly label; `wowheadLink` (from the item's bonus IDs) is last.
-- itemLink / sourceDetail / mapID / subzone / confidence are intentionally not exported.
local COLUMNS = {
  { "ts",           function(r) return r.ts end },
  { "date",         function(r) return NS.Util.FormatDate(r.ts) end },
  { "time",         function(r) return NS.Util.FormatClock(r.ts) end },
  { "char",         function(r) return r.char end },
  { "classFile",    function(r) return r.classFile end },
  { "itemID",       function(r) return r.itemID end },
  { "itemName",     function(r) return r.itemName end },
  { "quality",      function(r) return NS.Compat.QualityLabel(r.quality) end },
  { "qualityRaw",   function(r) return r.quality end },
  { "itemLevel",    function(r) return r.itemLevel end },
  { "bound",        function(r) return E:BoundLabel(r.bound) end },
  { "sellPrice",    function(r) return money(r.sellPrice) end },
  { "sellPriceRaw", function(r) return r.sellPrice end },
  { "itemType",     function(r) return r.itemType end },
  { "itemSubType",  function(r) return r.itemSubType end },
  { "quantity",     function(r) return r.quantity end },
  { "source",       function(r) return r.source end },
  { "zone",         function(r) return r.zone end },
  { "wowheadLink",  function(r) return E:WowheadLink(r) end },
}
local HEADER = {}
for i, c in ipairs(COLUMNS) do HEADER[i] = c[1] end

-- Serialize records to a CSV string (header + one row each, CRLF-terminated).
function E:CSV(records)
  local lines = { table.concat(HEADER, ",") }
  for _, r in ipairs(records or {}) do
    local cells = {}
    for i, c in ipairs(COLUMNS) do cells[i] = csvField(c[2](r)) end
    lines[#lines + 1] = table.concat(cells, ",")
  end
  return table.concat(lines, "\r\n") .. "\r\n"
end

-- ── Export modal ────────────────────────────────────────────────────────────────
-- A small skinned window: a Data Set selector (All Data / Current View) plus Export-to-CSV and
-- Export-to-AI (placeholder) buttons. Reuses the Browser's flat skin + close glyph. Both output
-- windows write into Export's OWN copy window (deliberately not shared with the debug copy window,
-- so its layout can evolve independently).
local WHITE = "Interface\\Buttons\\WHITE8X8"
local frame, copyFrame
local providers            -- { allData = fn, currentView = fn }, set by :Open
local dataset = "allData"  -- current Data Set selection

-- Center a popup on the History window (falling back to the screen when it isn't built/shown).
-- Re-applied on each open so the popup always lands over the browser wherever the user moved it.
local function centerOnBrowser(f)
  f:ClearAllPoints()
  local win = NS.Browser and NS.Browser.GetWindow and NS.Browser:GetWindow()
  if win and win:IsShown() then
    f:SetPoint("CENTER", win, "CENTER", 0, 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

-- Export's own read-only copy window: Ctrl+C to copy, Esc to close.
local function EnsureCopyFrame()
  if copyFrame then return copyFrame end
  copyFrame = CreateFrame("Frame", "LootHistoryExportCopyWindow", UIParent, "BackdropTemplate")
  copyFrame:SetSize(640, 420)
  copyFrame:SetPoint("CENTER")
  copyFrame:SetFrameStrata("FULLSCREEN")
  copyFrame:EnableMouse(true)
  copyFrame:SetMovable(true)
  copyFrame:SetClampedToScreen(true)

  local tbar = CreateFrame("Frame", nil, copyFrame)
  tbar:SetPoint("TOPLEFT", 1, -1); tbar:SetPoint("TOPRIGHT", -1, -1); tbar:SetHeight(26)
  tbar:EnableMouse(true); tbar:RegisterForDrag("LeftButton")
  tbar:SetScript("OnDragStart", function() copyFrame:StartMoving() end)
  tbar:SetScript("OnDragStop", function() copyFrame:StopMovingOrSizing() end)
  local t = tbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("CENTER"); t:SetText("Export \226\128\148 Ctrl+C, then Esc")

  if NS.Browser and NS.Browser.MakeCloseButton then
    NS.Browser:MakeCloseButton(tbar, function() copyFrame:Hide() end)
      :SetPoint("RIGHT", tbar, "RIGHT", -6, 0)
  end

  local scroll = CreateFrame("ScrollFrame", "LootHistoryExportCopyScroll", copyFrame,
    "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -30); scroll:SetPoint("BOTTOMRIGHT", -28, 10)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFont(NS.Constants.FONT_MONO, 10, "")
  edit:SetAutoFocus(false)
  edit:SetWidth(590)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); copyFrame:Hide() end)
  scroll:SetScrollChild(edit)
  copyFrame.scroll, copyFrame.edit = scroll, edit

  if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(copyFrame) end
  -- Denser than the shared skin (0.92): the CSV is dense monospace text, so bump to 0.95 alpha so
  -- the world/UI behind doesn't bleed through and hurt legibility.
  copyFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
  copyFrame:Hide()
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryExportCopyWindow")
  end
  return copyFrame
end

local function ShowCopy(text)
  local f = EnsureCopyFrame()
  centerOnBrowser(f)
  f.edit:SetWidth(f.scroll:GetWidth() > 0 and f.scroll:GetWidth() or 590)
  f.edit:SetText(text)
  f.edit:SetCursorPosition(0)
  f:Show(); f.edit:SetFocus(); f.edit:HighlightText()
end

-- Records for the current Data Set selection (empty array if the provider is missing).
local function selectedRecords()
  local fn = providers and providers[dataset]
  return (fn and fn()) or {}
end

-- Flat-skin button matching the Browser bar buttons. enabled=false greys it, disables the click,
-- and shows a "Coming soon" tooltip (the AI placeholder).
local function makeButton(parent, text, width, onClick, enabled)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width, 24)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  b:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  b:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER"); fs:SetText(text)
  if enabled == false then
    fs:SetTextColor(0.5, 0.5, 0.5)
    b:SetScript("OnEnter", function(self2)
      GameTooltip:SetOwner(self2, "ANCHOR_BOTTOM")
      GameTooltip:AddLine("Coming soon", 0.9, 0.9, 0.9); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  else
    b:SetScript("OnEnter", function() fs:SetTextColor(1, 0.82, 0) end)
    b:SetScript("OnLeave", function() fs:SetTextColor(1, 1, 1) end)
    b:SetScript("OnClick", onClick)
  end
  return b
end

-- Data Set dropdown options (All Data / Current View). The collapsed button shows a "Data set:"
-- prefix; the menu rows show the bare labels.
local DATASET_OPTIONS = {
  { value = "allData", label = "All Data" },
  { value = "currentView", label = "Current View" },
}
local function datasetLabel(v)
  for _, o in ipairs(DATASET_OPTIONS) do if o.value == v then return o.label end end
  return v
end

local function EnsureFrame()
  if frame then return frame end
  frame = CreateFrame("Frame", "LootHistoryExportWindow", UIParent, "BackdropTemplate")
  frame:SetSize(340, 150)
  frame:SetPoint("CENTER")
  -- DIALOG (below the dropdown menu's FULLSCREEN catcher) so an outside click closes the Data Set
  -- menu; the copy window (FULLSCREEN) still opens above this modal.
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true); frame:SetMovable(true); frame:SetClampedToScreen(true)

  local tbar = CreateFrame("Frame", nil, frame)
  tbar:SetPoint("TOPLEFT", 1, -1); tbar:SetPoint("TOPRIGHT", -1, -1); tbar:SetHeight(26)
  tbar:EnableMouse(true); tbar:RegisterForDrag("LeftButton")
  tbar:SetScript("OnDragStart", function() frame:StartMoving() end)
  tbar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  local t = tbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("CENTER"); t:SetText("Export")
  if NS.Browser and NS.Browser.MakeCloseButton then
    NS.Browser:MakeCloseButton(tbar, function() frame:Hide() end)
      :SetPoint("RIGHT", tbar, "RIGHT", -6, 0)
  end

  -- Data Set dropdown, spanning the full button-row width (CSV left edge → AI right edge).
  local ds = NS.Browser:MakeDropdown(frame, 148)
  ds:SetHeight(24)
  ds:ClearAllPoints()
  ds:SetPoint("TOPLEFT", 16, -40)
  ds:SetPoint("TOPRIGHT", -16, -40)
  ds:SetOptions(DATASET_OPTIONS)
  ds:SetValue(dataset, "Data set: " .. datasetLabel(dataset))
  ds.onSelect = function(v)
    dataset = v
    ds:SetValue(v, "Data set: " .. datasetLabel(v))
  end

  local csvBtn = makeButton(frame, "Export to CSV", 148, function()
    ShowCopy(E:CSV(selectedRecords()))
  end, true)
  csvBtn:SetPoint("TOPLEFT", 16, -80)

  local aiBtn = makeButton(frame, "Export to AI", 148, nil, false)
  aiBtn:SetPoint("TOPRIGHT", -16, -80)

  if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(frame) end
  frame:Hide()
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryExportWindow")
  end
  return frame
end

-- Build (once) and show the export modal, wiring the dataset providers. Always re-centers on the
-- History window.
function E:Open(p)
  providers = p or {}
  local f = EnsureFrame()
  centerOnBrowser(f)
  f:Show()
end

-- Placeholder for the AI-report export (built later): will bundle `records` into a report prompt.
function E:AIPrompt(records)  -- luacheck: ignore records
  return ""
end
