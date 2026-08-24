local addonName, NS = ...
NS.Export = NS.Export or {}
local E = NS.Export

-- ── Serialization ────────────────────────────────────────────────────────────────
-- Pure, unit-tested helpers (CSV text, Wowhead URL, bind-state labels). The modal UI below
-- consumes them; it is built lazily and needs the live client, so it is smoke-tested, not unit-
-- tested. Export is called directly by the Browser (NS.Export:Open) — it registers no bus message.

-- Friendly bind-state labels, matching the Bound column's tooltip legend. nil/"NONE" = Not Bound.
local BOUND_LABEL = {
  NONE = "Not Bound", BOE = "Bind on Equip", BOP = "Bind on Pickup",
  WARBAND = "Warbound", WARBAND_UE = "Warbound Until Equipped",
}
function E:BoundLabel(token) return BOUND_LABEL[token or "NONE"] or tostring(token) end

-- Plain-text money for CSV: always "Ng Ns Nc" (never the in-game coin-texture markup that
-- Util.FormatMoney emits). "" for nil so a missing vendorPrice stays blank.
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
-- (label) before `qualityRaw` (number), human `vendorPrice` ("Ng Ns Nc") before `vendorPriceRaw`
-- (copper). `bound` is the friendly label. Following the vendor columns, the AH-price feature adds
-- the COMPUTED `auctionPrice`/`auctionPriceRaw` (NS.AuctionPrice:Pick's price, human/copper),
-- `value`/`valueRaw` (NS.Util.RecordValue: auction-or-vendor, human/copper), and `auctionSource`
-- (Pick's tag, e.g. "tsm:dbmarket", or "" when unpriced). After the vendor/source/zone block, one
-- RAW `auc_<provider>_<key>` column is appended per NS.Constants.AUCTION_KEYS entry (deterministic,
-- capture-config order) exposing every price the addon actually captured, independent of which one
-- Pick chose. `wowheadLink` (from the item's bonus IDs) is last.
-- itemLink / sourceDetail / mapID / subzone / confidence are intentionally not exported.
local COLUMNS = {
  { "ts",           function(r) return r.ts end },
  { "date",         function(r) return NS.Util.FormatDate(r.ts) end },
  { "time",         function(r) return NS.Util.FormatClock(r.ts) end },
  { "char",         function(r) return r.char end },
  { "classFile",    function(r) return r.classFile end },
  { "itemID",       function(r) return r.itemID end },
  { "currencyID",   function(r) return r.currencyID end },
  { "itemName",     function(r) return r.itemName end },
  { "quality",      function(r) return r.quality ~= nil and NS.Item.QualityLabel(r.quality) or "" end },
  { "qualityRaw",   function(r) return r.quality end },
  { "itemLevel",    function(r) return r.itemLevel end },
  { "bound",        function(r) return E:BoundLabel(r.bound) end },
  { "vendorPrice",    function(r) return money(r.vendorPrice) end },
  { "vendorPriceRaw", function(r) return r.vendorPrice end },
  { "auctionPrice",   function(r) return money((NS.AuctionPrice:Pick(r.auctionPrice))) end },
  { "auctionPriceRaw",function(r) return (NS.AuctionPrice:Pick(r.auctionPrice)) end },
  { "value",          function(r) return money(NS.Util.RecordValue(r)) end },
  { "valueRaw",       function(r) return NS.Util.RecordValue(r) end },
  { "auctionSource",  function(r) return select(2, NS.AuctionPrice:Pick(r.auctionPrice)) end },
  { "itemType",     function(r) return r.itemType end },
  { "itemSubType",  function(r) return r.itemSubType end },
  { "quantity",     function(r) return r.quantity end },
  { "source",       function(r) return r.source end },
  { "zone",         function(r) return r.zone end },
}
-- One raw column per captured provider:key (deterministic — Constants.AUCTION_KEYS order), inserted
-- here (before wowheadLink is appended below) so wowheadLink stays the final column.
for _, k in ipairs(NS.Constants.AUCTION_KEYS) do
  local prov, key = k.provider, k.key
  COLUMNS[#COLUMNS + 1] = { "auc_" .. prov .. "_" .. key,
    function(r) return r.auctionPrice and r.auctionPrice[prov] and r.auctionPrice[prov][key] or nil end }
end
COLUMNS[#COLUMNS + 1] = { "wowheadLink", function(r) return E:WowheadLink(r) end }
local HEADER = {}
for i, c in ipairs(COLUMNS) do HEADER[i] = c[1] end

-- Serialize records against a column set to a CSV string (header + one row each, CRLF-terminated).
local function serializeCSV(records, columns, header)
  local lines = { table.concat(header, ",") }
  for _, r in ipairs(records or {}) do
    local cells = {}
    for i, c in ipairs(columns) do cells[i] = csvField(c[2](r)) end
    lines[#lines + 1] = table.concat(cells, ",")
  end
  return table.concat(lines, "\r\n") .. "\r\n"
end

-- Full CSV dump: every column, including the raw per-provider auc_ columns.
function E:CSV(records)
  return serializeCSV(records, COLUMNS, HEADER)
end

-- ── Insights CSV (issue #15) ─────────────────────────────────────────────────────
-- The Insights tab's Export produces an ANALYTICS csv — a flat, sectioned dump that mirrors the
-- Insights view (summary cards + each breakdown + the ranked lists) rather than raw loot rows.
-- Columns: Section, Label, Count, Value (Value = plain "Ng Ns Nc" value; blank when a row
-- has no value dimension). Pure — takes a Database:Stats result, returns text; unit-tested.

local BOUND_LABEL_CSV = {
  BOP = "Soulbound", BOE = "BoE", WARBAND = "Warbound", WARBAND_UE = "Warbound (UE)",
  UNBOUND = "Unbound",
}
local WEEKDAY_CSV = { [0] = "Sun", [1] = "Mon", [2] = "Tue", [3] = "Wed", [4] = "Thu", [5] = "Fri", [6] = "Sat" }

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
  -- Emit a { char → { catKey → magnitude } } matrix — the panel's "× Character" companion charts —
  -- as "Char / CategoryLabel" rows: Count = magnitude, Value = optional parallel value-matrix cell.
  -- Characters sorted by total desc then name; categories within a char by magnitude desc.
  local function charMatrix(name, matrix, labelOf, valueMatrix)
    local chars = {}
    for ch, cats in pairs(matrix or {}) do
      local total = 0
      for _, m in pairs(cats) do total = total + m end
      chars[#chars + 1] = { ch = ch, total = total, cats = cats }
    end
    table.sort(chars, function(a, b)
      if a.total ~= b.total then return a.total > b.total end
      return tostring(a.ch) < tostring(b.ch)
    end)
    for _, c in ipairs(chars) do
      local keys = {}
      for k in pairs(c.cats) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b)
        if c.cats[a] ~= c.cats[b] then return c.cats[a] > c.cats[b] end
        return tostring(a) < tostring(b)
      end)
      local vm = valueMatrix and valueMatrix[c.ch]
      for _, k in ipairs(keys) do
        row(name, tostring(c.ch) .. " / " .. (labelOf and labelOf(k) or tostring(k)),
          c.cats[k], vm and vm[k] or nil)
      end
    end
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
  local qualityLabel = function(q) return NS.Item.QualityLabel(q) end
  local boundLabel = function(b) return BOUND_LABEL_CSV[b] or b end
  -- LOOT breakdowns, each followed by its per-character "× Character" companion (mirrors the panel).
  -- All items-only (currency is excluded upstream in Database:Stats).
  section("By Source", rankedRows(stats.bySource, srcLabel, stats.valueBySource))
  charMatrix("By Character x Source", stats.charBySource, srcLabel, stats.charValueBySource)
  section("By Quality", rankedRows(stats.byQuality, qualityLabel))
  charMatrix("By Character x Quality", stats.charByQuality, qualityLabel)
  section("By Item Type", rankedRows(stats.byType))
  charMatrix("By Character x Item Type", stats.charByType)
  section("By Bound Type", rankedRows(stats.byBound, boundLabel))
  charMatrix("By Character x Bound Type", stats.charByBound, boundLabel)

  -- Per-character carries both count and value (byChar entries are { char, count, value }). byChar
  -- registers currency-only characters with count 0 (for class colors in the UI) — skip those here
  -- so "By Character" stays items-only, matching the dashboard.
  local charRows = {}
  for _, ce in pairs(stats.byChar or {}) do
    if (ce.count or 0) > 0 then
      charRows[#charRows + 1] = { label = ce.char, count = ce.count, value = ce.value }
    end
  end
  table.sort(charRows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return tostring(a.label) < tostring(b.label)
  end)
  section("By Character", charRows)

  section("By Weekday", rankedRows(stats.byWeekday, function(d) return WEEKDAY_CSV[d] or tostring(d) end))
  section("By Hour", rankedRows(stats.byHour, function(h) return string.format("%02d:00", h) end))

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

  -- Currency (issue: currency capture). Top currencies by quantity, then one row per currency×source,
  -- then per-character and per-day, plus the highlight summary rows.
  section("Currency Collected", rankedRows(stats.byCurrency))
  local matrix = stats.currencySourceMatrix or {}
  local curNames = {}
  for cname in pairs(matrix) do curNames[#curNames + 1] = cname end
  table.sort(curNames)
  for _, cname in ipairs(curNames) do
    local perSrc, srcs = matrix[cname], {}
    for s in pairs(perSrc) do srcs[#srcs + 1] = s end
    table.sort(srcs, function(a, b) return (perSrc[a] or 0) > (perSrc[b] or 0) end)
    for _, s in ipairs(srcs) do
      row("Currency by Type x Source", cname .. " / " .. srcLabel(s), perSrc[s])
    end
  end
  -- Per-character currency split by type — the panel's "Currency by Character × Type" companion.
  charMatrix("Currency by Character x Type", stats.currencyCharMatrix)
  local curDayKeys = {}
  for day in pairs(stats.currencyByDay or {}) do curDayKeys[#curDayKeys + 1] = day end
  table.sort(curDayKeys)
  for _, day in ipairs(curDayKeys) do row("Currency by Day", day, stats.currencyByDay[day]) end

  return table.concat(lines, "\r\n") .. "\r\n"
end

-- ── Export modal ────────────────────────────────────────────────────────────────
-- A small skinned window: a Data Set selector (All Data / Current View) plus an Export-to-CSV
-- button. Reuses the Browser's flat skin + close glyph. The output window writes into Export's OWN
-- copy window (deliberately not shared with the debug copy window, so its layout can evolve
-- independently).
local WHITE = "Interface\\Buttons\\WHITE8X8"
local frame
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
--
-- The FRAME is LibKa0s-Widgets-1.0's now, leased through core/WidgetsSetup.lua. What stays here is
-- the DESCRIPTOR: the global name, the monospace face, the title, the skin and the anchor -- the
-- things a vendored library cannot work out for itself. The fifty-two lines it replaced were,
-- character for character with the addon name substituted, BankLedger's fifty-two.
--
-- WHAT IS DELIBERATELY NOT PASSED: width, height, editWidth and backdrop. The library's defaults
-- ARE the constants this file used to spell out -- 640x420, a 590 fallback edit width, and the
-- 0.06/0.06/0.08/0.95 backdrop this window has always worn (denser than the shared skin's 0.92,
-- because a wall of small monospace text loses legibility to whatever bleeds through it). Passing
-- them again would be four more places for the two copies of one number to drift apart.
--
-- The build is lazy INSIDE the handle, so asking for one here costs nothing until the first export:
-- a session that never exports creates no frame at all.
local copyWindow

local function ensureCopyWindow()
  if copyWindow then return copyWindow end
  if not NS.CopyWindow then return nil end   -- degraded install; the caller says so, see :Open
  copyWindow = NS.CopyWindow({
    addonName = addonName,
    name      = "LootHistoryExportCopyWindow",
    title     = "Export \226\128\148 Ctrl+C, then Esc",
    font      = NS.Constants.FONT_MONO,
    fontSize  = 10,
    applySkin = function(f) if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(f) end end,
    -- Consulted on EVERY show rather than once at build: the popup has to land over the History
    -- window wherever the user has since dragged it, and over the screen when it is not up.
    anchorTo  = function()
      return NS.Browser and NS.Browser.GetWindow and NS.Browser:GetWindow() or nil
    end,
  })
  -- Published for tests/test_export.lua. An EditBox is WRITE-ONLY through the frame API as this
  -- module uses it -- nothing here ever reads the text back -- so the handle is the only seam from
  -- which a headless test can assert what the window is showing.
  E.__copyWindow = copyWindow
  return copyWindow
end

--- Show text in the copy window, selected and ready for Ctrl+C.
---
--- THE ORDER inside the window -- width, text, cursor, show, focus, highlight -- is the library's
--- now. It was load-bearing here (highlight before show selects nothing; focus before the text is
--- set leaves the cursor where the last export left it) and it is load-bearing there. What changed
--- is that it is written down once instead of once per addon.
local function ShowCopy(text)
  local win = ensureCopyWindow()
  if not win then return end
  win:Show(text)
end
E.__showCopy = ShowCopy

-- The data for the current Data Set selection (records for History, a Stats result for Insights).
-- Empty table if the provider is missing.
local function selectedData()
  local fn = config.providers and config.providers[dataset]
  return (fn and fn()) or {}
end

-- Flat-skin button matching the Browser bar buttons.
-- `icon` is a catalog name and is OPTIONAL, in both directions: a caller that passes none gets
-- the button this always built, and a caller that passes one still gets that button when the seam
-- answers nil. The LABEL NEVER MOVES -- it stays CENTER-anchored and the mark sits at LEFT +10 --
-- so a missing texture leaves the control pixel-identical rather than off-centre.
--
-- The word stays for a wide action button. "Export to CSV" says WHAT the button does and the
-- spreadsheet mark says WHERE the result lands; replacing the word would turn a plain question
-- into one answered by hovering. No tooltip on the mark, either -- if a mark needs one, the label
-- should have stayed.
local function makeButton(parent, text, width, onClick, icon)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width, 24)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  b:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  b:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
  local path = icon and NS.Icon and NS.Icon(icon)
  if path then
    local tex = b:CreateTexture(nil, "OVERLAY")
    tex:SetSize(14, 14)
    tex:SetPoint("LEFT", 10, 0)
    tex:SetTexture(path)
    tex:SetVertexColor(0.85, 0.85, 0.85)
    b.icon = tex
  end
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER"); fs:SetText(text)
  b:SetScript("OnEnter", function() fs:SetTextColor(1, 0.82, 0) end)
  b:SetScript("OnLeave", function() fs:SetTextColor(1, 1, 1) end)
  b:SetScript("OnClick", onClick)
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
  -- REFUSE TO DRAW with no LibKa0s, and decide it before creating anything. The Data Set picker is
  -- this modal's only control and it is a LibKa0s-Widgets-1.0 dropdown, so a degraded install means
  -- there is no modal worth opening. Asked through NS.HasWidgets rather than by building the
  -- dropdown, because this frame carries a GLOBAL NAME: probing by build-and-discard would strand
  -- one LootHistoryExportWindow per :Open call. Nothing is memoised either way -- `frame` stays nil
  -- so a later session with the library present still builds a real modal, and :Open explains the
  -- absence through the shared cause clause.
  if not (NS.HasWidgets and NS.HasWidgets()) then return nil end
  frame = CreateFrame("Frame", "LootHistoryExportWindow", UIParent, "BackdropTemplate")
  frame:SetSize(372, 150)
  frame:SetPoint("CENTER")
  -- DIALOG (below the dropdown menu's FULLSCREEN catcher) so an outside click closes the Data Set
  -- menu; the copy window (FULLSCREEN) still opens above this modal.
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true); frame:SetMovable(true); frame:SetClampedToScreen(true)

  -- Built FIRST, before any other child, so that a seam which somehow answers nil despite the
  -- library having registered still costs one bare frame rather than a half-built modal wired to a
  -- nil dropdown. Positioned further down, with the rest of the layout.
  local ds = NS.MakeDropdown(frame, 148)
  if not ds then
    frame:Hide()
    frame = nil
    return nil
  end

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

  -- Data Set dropdown (built above, as the library probe), spanning the full button-row width.
  -- Through core/WidgetsSetup.lua's one factory, like the filter bar's nine -- not through
  -- NS.Browser, which no longer owns a widget of its own.
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

  -- Export-to-CSV button, spanning the full row (aligned under the Data Set dropdown).
  local csvBtn = makeButton(frame, "Export to CSV", 150, function()
    local serialize = config.csv or function(d) return E:CSV(d) end
    ShowCopy(serialize(selectedData()))
  end, "spreadsheet")
  csvBtn:SetPoint("TOPLEFT", 16, -80)
  csvBtn:SetPoint("TOPRIGHT", -16, -80)

  if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(frame) end
  -- CLOSE THE SHARED POPUP ON EVERY NON-CLICK CLOSE PATH. The dropdown menu is a process-wide
  -- singleton parented to UIParent at FULLSCREEN_DIALOG -- this frame's Hide() cannot reach it, and
  -- before the adoption this modal had no OnHide at all, so Escape (via the UISpecialFrames
  -- registration below) or the title-bar close left the Data Set menu floating over the game with
  -- nothing left to hide it. One hook covers both, because both route through Hide().
  frame:HookScript("OnHide", function() NS.CloseMenu() end)
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
  if not f then
    -- Degraded install: say why, through the one shared cause clause every LibKa0s seam in this
    -- addon appends its own consequence to, rather than opening a window with a dead control.
    NS.Print(NS.LIBKA0S_MISSING .. ", so the export window is unavailable.")
    return
  end
  if f.titleFS then f.titleFS:SetText(config.title or "Export") end
  centerOnBrowser(f)
  f:Show()
end
