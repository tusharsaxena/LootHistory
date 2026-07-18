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
  { "auctionPrice", function(r) return money(r.auctionPrice) end },
  { "auctionPriceRaw", function(r) return r.auctionPrice end },
  { "value",        function(r) return money(NS.Util.RecordValue(r)) end },
  { "valueRaw",     function(r) return NS.Util.RecordValue(r) end },
  { "priceSource",  function(r) return r.priceSource end },
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

-- ── Insights CSV (issue #15) ─────────────────────────────────────────────────────
-- The Insights tab's Export produces an ANALYTICS csv — a flat, sectioned dump that mirrors the
-- Insights view (summary cards + each breakdown + the ranked lists) rather than raw loot rows.
-- Columns: Section, Label, Count, Value (Value = plain "Ng Ns Nc" value; blank when a row
-- has no value dimension). Pure — takes a Database:Stats result, returns text; unit-tested.

local BOUND_LABEL_CSV = {
  BOP = "Soulbound", BOE = "BoE", ACCOUNT = "Account", WARBAND = "Warbound", UNBOUND = "Unbound",
}
local WEEKDAY_CSV = { [0] = "Sun", [1] = "Mon", [2] = "Tue", [3] = "Wed", [4] = "Thu", [5] = "Fri", [6] = "Sat" }
local CONF_LABEL_CSV = { CERTAIN = "Certain", INFERRED = "Inferred" }

-- Count-map → array of { label, count, value } sorted count-desc then label-asc. `labelOf` maps a
-- raw key to a display label; `valueMap` (optional) supplies the value column per key.
local function rankedRows(map, labelOf, valueMap)
  local rows = {}
  for key, count in pairs(map or {}) do
    rows[#rows + 1] = { label = labelOf and labelOf(key) or tostring(key),
      count = count, value = valueMap and valueMap[key] or nil, _k = key }
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return tostring(a.label) < tostring(b.label)
  end)
  return rows
end

function E:InsightsCSV(stats)
  stats = stats or {}
  local t = stats.totals or {}
  local lines = { "Section,Label,Count,Value" }
  local function row(section, label, count, valueCopper)
    lines[#lines + 1] = table.concat({
      csvField(section), csvField(label),
      count ~= nil and csvField(count) or "",
      valueCopper ~= nil and csvField(money(valueCopper)) or "",
    }, ",")
  end
  local function section(name, rows)
    for _, r in ipairs(rows) do row(name, r.label, r.count, r.value) end
  end

  -- Summary (the stat/highlight cards).
  local dash = ""
  row("Summary", "Records", t.records or 0)
  row("Summary", "Distinct items", t.distinctItems or 0)
  row("Summary", "Characters", t.distinctChars or 0)
  row("Summary", "Value", nil, t.totalValue or 0)
  row("Summary", "Active days", t.activeDays or 0)
  row("Summary", "Epic+ drops", t.epicPlus or 0)
  row("Summary", "Best drop iLvl", t.bestDrop and t.bestDrop.itemLevel or dash)
  row("Summary", "Richest drop", nil, t.richestDrop and t.richestDrop.value or 0)
  if t.firstTs and t.lastTs then
    row("Summary", "Date range", NS.Util.FormatDate(t.firstTs) .. " to " .. NS.Util.FormatDate(t.lastTs))
  end
  if t.busiestDay then row("Summary", "Busiest day", t.busiestDay.day .. " (" .. t.busiestDay.count .. ")") end

  local srcLabel = function(k) return NS.Constants.SourceLabel[k] or k end
  section("By Source", rankedRows(stats.bySource, srcLabel, stats.valueBySource))
  section("By Quality", rankedRows(stats.byQuality, function(q) return NS.Compat.QualityLabel(q) end))
  section("By Item Type", rankedRows(stats.byType))
  section("By Bound Type", rankedRows(stats.byBound, function(b) return BOUND_LABEL_CSV[b] or b end))

  -- Per-character carries both count and value (byChar entries are { char, count, value }).
  local charRows = {}
  for _, ce in pairs(stats.byChar or {}) do
    charRows[#charRows + 1] = { label = ce.char, count = ce.count, value = ce.value }
  end
  table.sort(charRows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return tostring(a.label) < tostring(b.label)
  end)
  section("By Character", charRows)

  section("By Weekday", rankedRows(stats.byWeekday, function(d) return WEEKDAY_CSV[d] or tostring(d) end))
  section("By Hour", rankedRows(stats.byHour, function(h) return string.format("%02d:00", h) end))
  section("By Keystone", rankedRows(stats.byKeystone, function(l) return "+" .. l end))
  section("Attribution Confidence", rankedRows(stats.byConfidence, function(c) return CONF_LABEL_CSV[c] or c end))

  for _, z in ipairs(stats.topZones or {}) do row("Top Zones", z.zone, z.count, z.value) end
  for _, it in ipairs(stats.topItems or {}) do
    row("Top Items by Count", it.itemName or ("item " .. tostring(it.itemID)), it.count, it.value)
  end
  for _, it in ipairs(stats.topItemsByValue or {}) do
    row("Top Items by Value", it.itemName or ("item " .. tostring(it.itemID)), it.count, it.value)
  end

  -- Per-day activity (chronological), count + value.
  local dayKeys = {}
  for day in pairs(stats.byDay or {}) do dayKeys[#dayKeys + 1] = day end
  table.sort(dayKeys)
  for _, day in ipairs(dayKeys) do
    row("By Day", day, stats.byDay[day], (stats.valueByDay or {})[day] or 0)
  end

  return table.concat(lines, "\r\n") .. "\r\n"
end

-- ── AI report prompt (issue #12) ─────────────────────────────────────────────────
-- Assembles the "Export to AI" prompt: short framing + a link to the in-repo guideline (the "pure
-- pointer" — the guideline points the AI at a ready-made HTML template to fill in and defines the
-- data contract, so the prompt stays small) + the History and Insights CSVs for the selected dataset.
-- Pure/unit-tested; the modal below feeds it the two serialized CSVs.
local GUIDELINE_URL =
  "https://raw.githubusercontent.com/tusharsaxena/LootHistory/refs/heads/master/docs/ai-export-guideline.md"
local AI_LARGE_ROWS = 4000

function E:AIPrompt(historyCSV, insightsCSV, opts)
  opts = opts or {}
  local lines = {
    "You are given a World of Warcraft loot-history export from the \"Ka0s Loot History\" addon.",
    "Build ONE single, self-contained HTML file that presents this data as a beautiful, interactive report.",
    "",
    "Follow this guideline EXACTLY — fetch and read it first. It points you at a ready-made HTML",
    "template to fill in (the styling, charts and interactions are fixed) and defines the data contract:",
    GUIDELINE_URL,
    "",
    "If you can run code (Claude Code, Claude Desktop with code, ChatGPT code interpreter): the guideline",
    "has you build with the shipped assembler tools/build_report.py — run that in ONE command; do not",
    "hand-transcribe the data or write your own build/splice scripts. Hand this export to the AI as a FILE",
    "(attach/upload it, or paste in Claude Code which auto-files a large paste) and point the tool at it —",
    "do not retype the data. The guideline you fetch describes that assembler; if the copy you receive",
    "does not mention build_report.py you fetched a stale CDN cache — bypass the cache for a fresh copy",
    "(curl/wget it in your code sandbox, or add a ?v= cache-buster; a plain re-fetch through the same",
    "tool just returns the stale copy). Either way THIS prompt is authoritative: the assembler builds,",
    "validates, AND downloads the template itself in one command, so never web_fetch the template.",
    "",
    "Rules:",
    "- Output only the HTML file, nothing else. It must be fully self-contained: all CSS and JS inline,",
    "  no external requests, no CDNs, no web fonts (use system fonts only).",
    "- Leave the <title> and hero heading alone: the engine derives the title, realm and date range",
    "  at runtime from the data. Do not hand-edit them.",
    "- Two datasets follow as CSV: the full loot HISTORY (one row per drop) and a pre-computed INSIGHTS",
    "  summary. The guideline explains how to turn HISTORY into the template's data array, and how to",
    "  use INSIGHTS when you write the analysis section.",
    "- Each HISTORY row carries THREE prices: vendor (v), auction (a, may be blank), and value",
    "  (val = auction-if-present-else-vendor). Use VALUE for every worth/gold figure and ranking;",
    "  mention vendor or auction only when specifically contrasting them. The engine aggregates Σ(val×qty).",
  }
  if (opts.rows or 0) > AI_LARGE_ROWS then
    lines[#lines + 1] =
      "- NOTE: this is a large export. If your AI tool truncates it, re-export using the modal's"
    lines[#lines + 1] =
      "  \"Current View\" data set to narrow the loot before exporting."
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "=== HISTORY (CSV) ==="
  lines[#lines + 1] = historyCSV or ""
  lines[#lines + 1] = "=== INSIGHTS (CSV) ==="
  lines[#lines + 1] = insightsCSV or ""
  return table.concat(lines, "\n")
end

-- ── Export modal ────────────────────────────────────────────────────────────────
-- A small skinned window: a Data Set selector (All Data / Current View) plus Export-to-CSV and
-- Export-to-AI (placeholder) buttons. Reuses the Browser's flat skin + close glyph. Both output
-- windows write into Export's OWN copy window (deliberately not shared with the debug copy window,
-- so its layout can evolve independently).
local WHITE = "Interface\\Buttons\\WHITE8X8"
local frame, copyFrame
-- Per-open config (issue #15): { title = "Export …", providers = { allData, currentView },
-- csv = function(dataset) return text end }. `title` is the window header the invoking tab supplies
-- ("Export History" / "Export Insights", and any future tab); `csv` is the serializer for whichever
-- dataset the Data Set dropdown selects. Set by :Open.
local config = {}
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

-- The data for the current Data Set selection (records for History, a Stats result for Insights).
-- Empty table if the provider is missing.
local function selectedData()
  local fn = config.providers and config.providers[dataset]
  return (fn and fn()) or {}
end

-- The History records + Insights stats for the current Data Set, for the AI export (which bundles
-- BOTH datasets regardless of which tab opened the modal). Empty fallbacks if a provider is missing.
local function selectedAIData()
  local h = config.ai and config.ai.history and config.ai.history[dataset]
  local i = config.ai and config.ai.insights and config.ai.insights[dataset]
  return (h and h()) or {}, (i and i()) or {}
end

-- The Export-to-AI help popup: a small skinned window explaining how to use the pasted prompt.
local helpFrame
local function EnsureHelpFrame()
  if helpFrame then return helpFrame end
  helpFrame = CreateFrame("Frame", "LootHistoryExportHelpWindow", UIParent, "BackdropTemplate")
  helpFrame:SetSize(440, 300)
  helpFrame:SetPoint("CENTER")
  helpFrame:SetFrameStrata("FULLSCREEN")
  helpFrame:EnableMouse(true); helpFrame:SetMovable(true); helpFrame:SetClampedToScreen(true)

  local tbar = CreateFrame("Frame", nil, helpFrame)
  tbar:SetPoint("TOPLEFT", 1, -1); tbar:SetPoint("TOPRIGHT", -1, -1); tbar:SetHeight(26)
  tbar:EnableMouse(true); tbar:RegisterForDrag("LeftButton")
  tbar:SetScript("OnDragStart", function() helpFrame:StartMoving() end)
  tbar:SetScript("OnDragStop", function() helpFrame:StopMovingOrSizing() end)
  local t = tbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("CENTER"); t:SetText("Export to AI \226\128\148 how it works")
  if NS.Browser and NS.Browser.MakeCloseButton then
    NS.Browser:MakeCloseButton(tbar, function() helpFrame:Hide() end)
      :SetPoint("RIGHT", tbar, "RIGHT", -6, 0)
  end

  local body = helpFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  body:SetPoint("TOPLEFT", 16, -34); body:SetPoint("BOTTOMRIGHT", -16, 14)
  body:SetJustifyH("LEFT"); body:SetJustifyV("TOP"); body:SetSpacing(3)
  body:SetText(table.concat({
    "|cffe8c56bExport to AI|r turns your loot into a beautiful, shareable web page.",
    "",
    "1. Click |cffe8c56bExport to AI|r, then Ctrl+C to copy the whole prompt.",
    "   |cffe8c56bBest: save it as a .txt and attach that file|r to the AI chat (or paste it in Claude",
    "   Code, which auto-files a big paste). That avoids truncation and lets a code-capable AI",
    "   read the data from disk with its assembler tool instead of slowly retyping it.",
    "2. Paste it into an AI chat that can browse the web \226\128\148 Claude, ChatGPT, or Gemini.",
    "   (Web access must be ON: the prompt links to a design guide the AI reads.)",
    "3. The AI replies with a single self-contained HTML file \226\128\148 your report.",
    "   In Claude you can publish it as an Artifact to get a shareable link.",
    "",
    "It always bundles |cffe8c56bboth|r your History and Insights, and honors the",
    "Data Set choice (All Data vs Current View).",
  }, "\n"))

  if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(helpFrame) end
  helpFrame:Hide()
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryExportHelpWindow")
  end
  return helpFrame
end

-- Flat-skin button matching the Browser bar buttons. enabled=false greys it, disables the click,
-- and shows a "Coming soon" tooltip (kept for any future disabled action).
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
  frame:SetSize(372, 150)
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
  frame.titleFS = t
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

  local csvBtn = makeButton(frame, "Export to CSV", 150, function()
    local serialize = config.csv or function(d) return E:CSV(d) end
    ShowCopy(serialize(selectedData()))
  end, true)
  csvBtn:SetPoint("TOPLEFT", 16, -80)

  -- Export to AI bundles BOTH datasets (history + insights) for the selected Data Set.
  local aiBtn = makeButton(frame, "Export to AI", 150, function()
    local records, stats = selectedAIData()
    ShowCopy(E:AIPrompt(E:CSV(records), E:InsightsCSV(stats), { rows = #records }))
  end, true)
  aiBtn:SetPoint("TOPLEFT", 178, -80)

  -- Small "?" help button at the far right of the AI button row.
  local helpBtn = makeButton(frame, "?", 22, function() EnsureHelpFrame():Show() end, true)
  helpBtn:SetPoint("TOPRIGHT", -16, -80)

  if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(frame) end
  frame:Hide()
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryExportWindow")
  end
  return frame
end

-- Build (once) and show the export modal for the given config (issue #15). `cfg.title` is the
-- header supplied by the invoking tab; `cfg.providers` feeds the Data Set dropdown; `cfg.csv`
-- serializes the selected dataset. Always re-centers on the History window.
function E:Open(cfg)
  config = cfg or {}
  local f = EnsureFrame()
  if f.titleFS then f.titleFS:SetText(config.title or "Export") end
  centerOnBrowser(f)
  f:Show()
end
