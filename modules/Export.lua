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

-- CSV columns: the 19 export-contract fields (Database:Export order) + two derived columns
-- (a human DD-MMM-YYYY `date` and a `wowheadLink`), appended last.
local FIELDS = {
  "ts", "char", "classFile", "itemID", "itemLink", "itemName", "quality", "itemLevel", "bound",
  "sellPrice", "itemType", "itemSubType", "quantity", "source", "sourceDetail", "zone", "mapID",
  "subzone", "confidence",
}
local HEADER = {}
for i, f in ipairs(FIELDS) do HEADER[i] = f end
HEADER[#HEADER + 1] = "date"
HEADER[#HEADER + 1] = "wowheadLink"

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

-- Serialize records to a CSV string (header + one row each, CRLF-terminated). `ts` stays epoch;
-- `bound` is emitted as its friendly label; `date` (DD-MMM-YYYY) and `wowheadLink` are appended.
function E:CSV(records)
  local lines = { table.concat(HEADER, ",") }
  for _, r in ipairs(records or {}) do
    local cells = {}
    for i, f in ipairs(FIELDS) do
      local v = r[f]
      if f == "bound" then v = self:BoundLabel(r.bound) end
      cells[i] = csvField(v)
    end
    cells[#cells + 1] = csvField(NS.Util.FormatDate(r.ts))
    cells[#cells + 1] = csvField(self:WowheadLink(r))
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
  copyFrame:Hide()
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryExportCopyWindow")
  end
  return copyFrame
end

local function ShowCopy(text)
  local f = EnsureCopyFrame()
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

-- Two-option Data Set selector (All Data / Current View) — a flat button that toggles on click.
local function makeDatasetToggle(parent)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(180, 24)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  b:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  b:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", 8, 0)
  local function paint()
    fs:SetText("Data set: " .. (dataset == "allData" and "All Data" or "Current View"))
  end
  b:SetScript("OnEnter", function() fs:SetTextColor(1, 0.82, 0) end)
  b:SetScript("OnLeave", function() fs:SetTextColor(1, 1, 1) end)
  b:SetScript("OnClick", function()
    dataset = (dataset == "allData") and "currentView" or "allData"
    paint()
  end)
  paint()
  return b
end

local function EnsureFrame()
  if frame then return frame end
  frame = CreateFrame("Frame", "LootHistoryExportWindow", UIParent, "BackdropTemplate")
  frame:SetSize(340, 150)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("FULLSCREEN")
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

  local toggle = makeDatasetToggle(frame)
  toggle:SetPoint("TOP", 0, -40)

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

-- Build (once) and show the export modal, wiring the dataset providers.
function E:Open(p)
  providers = p or {}
  EnsureFrame():Show()
end

-- Placeholder for the AI-report export (built later): will bundle `records` into a report prompt.
function E:AIPrompt(records)  -- luacheck: ignore records
  return ""
end
