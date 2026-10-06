local _, NS = ...
NS.Browser = NS.Browser or {}
local B = NS.Browser

-- The History window's SHARED filter bar (issue #13): B:BuildFilterBar, the static option sets it
-- seeds its dropdowns from and the flat-skin bar button. Split out of modules/Browser.lua, which
-- owns the window shell, the dataset-driven option builders and the view logic this bar reads
-- through the B._ helpers below. Loads directly after modules/Browser.lua (TOC), so every helper is
-- already published when these file-scope locals capture it.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local setToFilter       = B._setToFilter
local applyQualityFloor = B._applyQualityFloor
local ApplyFilter       = B._applyFilter
local currentKey        = B._currentKey
local boundOptions      = B._options.bound
local qualityOptions    = B._options.quality

-- Static option sets. "all" is the sentinel for "no filter"; onSelect maps it to nil.
-- (Quality is data-driven — see qualityOptions in modules/Browser.lua — so any quality the history actually contains,
-- Heirloom / Poor / Artifact included, shows up and absent ones don't clutter.)
-- Ordered to mirror the table's column layout: Date, Quality, Type, Source, Zone, Character.
local GROUP_OPTIONS = {
  { value = "none", label = "Group: None" },
  { value = "day", label = "Group: Day" },
  { value = "quality", label = "Group: Quality" },
  { value = "type", label = "Group: Type" },
  { value = "source", label = "Group: Source" },
  { value = "zone", label = "Group: Zone" },
  { value = "char", label = "Group: Character" },
  { value = "dir", label = "Group: Direction" },
  { value = "holder", label = "Group: Holder" },
}
local DATE_OPTIONS = {
  { value = "all", label = "Date: All" },
  { value = "today", label = "Today" },
  { value = "7d", label = "Last 7 days" },
  { value = "30d", label = "Last 30 days" },
  { value = "90d", label = "Last 90 days" },
  { value = "1y", label = "Last year" },
}

-- Direction filter (timeline-ledger spec §7). Values are the stored `dir` tokens; a legacy row with
-- no `dir` reads as IN everywhere (Util.RowDir, Database's dirSet match).
local DIR_OPTIONS = {
  { value = "all",  label = "Direction: All" },
  { value = "IN",   label = "Gains" },
  { value = "OUT",  label = "Losses" },
  { value = "MOVE", label = "Transfers" },
}

-- Published for the headless suite (tests/test_browser.lua), beside the pure helpers
-- modules/Browser.lua publishes.
B._dateOptions  = DATE_OPTIONS
B._groupOptions = GROUP_OPTIONS

-- A small flat-skin text button for the filter bar (Export / Clear / Save / Reset).
--
-- `icon` is a catalog name and is OPTIONAL. The LABEL NEVER MOVES: it stays CENTER-anchored and
-- the mark sits at LEFT +10, so a nil from the seam leaves the button exactly as it was rather
-- than off-center. Only buttons at least ~120px wide are given one -- a 14px mark plus a centered
-- five-letter word does not fit the 36px Clear/Reset cluster, and an off-center label is worse
-- than no mark (see docs/browser.md).
--
-- The existing `tooltip` stays and is NOT a tooltip on the mark: it predates the art, it is
-- anchored to the whole button, and it explains the ACTION rather than the picture.
local function makeBarButton(parent, text, width, onClick, tooltip, icon)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width, 20)
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
  fs:SetPoint("CENTER")
  fs:SetText(text)
  b:SetScript("OnEnter", function(self2)
    fs:SetTextColor(1, 0.82, 0)
    if tooltip then
      GameTooltip:SetOwner(self2, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(tooltip, 0.9, 0.9, 0.9, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() fs:SetTextColor(1, 1, 1); GameTooltip:Hide() end)
  b:SetScript("OnClick", onClick)
  return b
end

-- Build the SHARED, singleton filter bar (issue #13) into `bar` — a window-level host anchored
-- once in EnsureFrame, above both tab panes, so a single filter drives the History table AND the
-- Insights charts. The footer is shared window chrome too (built in EnsureFrame); this function
-- owns only the two rows of controls:
--   Row 1: Group by · Direction · [search…] · Save · Reset · Clear
--   Row 2: column filters in table order — Date · Bound · Quality · Type · SubType · Source ·
--          Zone · Character · Export
function B:BuildFilterBar(bar)
  local ROW1, ROW2 = 0, -24

  -- REFUSE TO DRAW rather than build dead controls. The ten dropdowns below are the whole point
  -- of this bar, and NS.MakeDropdown answers nil on an install with no LibKa0s: a bar of buttons
  -- that open no menu is strictly worse than no bar. The FIRST dropdown is the probe -- one real
  -- control, not a throwaway -- and `self._dd` is published only once it exists, so it stays nil
  -- on a degraded install. That is the state every reader downstream (RefreshFilterOptions,
  -- CaptureView, ApplyView, SetCharSet) has always had to tolerate, because the filter paths run
  -- headlessly too.
  local dd = { group = NS.MakeDropdown(bar, 120) }
  if not dd.group then return end
  self._dd = dd

  -- ── Row 1: Group by · Direction · Search · Clear ──
  -- Group width matches the Date dropdown directly below it (120); the Save+Reset+Clear cluster is
  -- anchored above the Export button (not the bar's right edge) and resized so its span (three
  -- buttons + two 6px gaps) exactly matches Export's width (B:ExportWidth), so the cluster sits
  -- flush above it and both stay static as the window widens.
  dd.group:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, ROW1)
  dd.group:SetOptions(GROUP_OPTIONS)
  dd.group:SetValue("none", "Group: None")
  dd.group.onSelect = function(v) if NS.BrowserTable then NS.BrowserTable:SetGroupBy(v) end end

  -- Direction (multi-select), between Group and Search: row 2's span is the toolbar's width floor
  -- (DROPDOWNS_W), so a ninth row-2 dropdown would widen the minimum window by 104 px; row 1's
  -- search box absorbs it instead.
  dd.dir = NS.MakeDropdown(bar, 104)
  dd.dir:SetPoint("LEFT", dd.group, "RIGHT", 8, 0)
  dd.dir:SetMulti(true)
  dd.dir:SetOptions(DIR_OPTIONS)
  dd.dir.onMultiSelect = function(set)
    B.activeFilter.dir = setToFilter(set)
    ApplyFilter()
  end

  -- Export button is created here (row 1, ahead of its row-2 position further down) so the
  -- Save/Reset/Clear cluster below can anchor its top-right corner to it; SetPoint only needs the
  -- frame to exist, not to be positioned yet — its own anchor (to dd.char) is set once dd.char
  -- exists, in the Row 2 section below. Its width is static (B:ExportWidth): at min window width it
  -- fills from the Character dropdown's right edge to the bar's right edge; it does NOT grow when
  -- the window widens (no right anchor to the bar).
  local exportW = B:ExportWidth()
  --
  -- NO MARK ON THIS ONE. The filter bar's Export button is one word in a row of four plain word
  -- buttons (Save/Reset/Clear beside it), and a download arrow on the widest of them made the row
  -- read as one decorated button among three bare ones. The mark stays where it explains
  -- something: the export window's "Export to CSV" (modules/Export.lua), where the spreadsheet
  -- says WHERE the result lands.
  local exportBtn = makeBarButton(bar, "Export", exportW, function() B:OpenExport() end,
    "Export the current tab — loot rows (History) or the analytics summary (Insights).")
  self._exportBtn = exportBtn

  -- Right cluster (row 1): Save · Reset · Clear, spanning exactly exportW so its right edge sits
  -- flush above Export's. Three buttons + two 6px gaps = exportW: Clear/Reset each take
  -- floor((exportW-12)/3); Save takes the remainder so the widths sum exactly. Static (no growth).
  local btnW = math.floor((exportW - 12) / 3)
  local clear = makeBarButton(bar, "Clear", btnW, function() B:ClearFilters() end,
    "Clear filters and group/sort back to your saved view.")
  clear:SetPoint("TOPRIGHT", exportBtn, "TOPRIGHT", 0, ROW1 - ROW2)
  local resetBtn = makeBarButton(bar, "Reset", btnW, function() B:ResetView() end,
    "Reset the saved view to stock defaults.")
  resetBtn:SetPoint("RIGHT", clear, "LEFT", -6, 0)
  local saveBtn = makeBarButton(bar, "Save", exportW - 12 - 2 * btnW, function() B:SaveView() end,
    "Save the current group, sort and filters as your default view.")
  saveBtn:SetPoint("RIGHT", resetBtn, "LEFT", -6, 0)

  -- Item-name search box (row 1). Its LEFT sits beside Direction; its RIGHT is pinned to the row-2
  -- Character dropdown's right edge below it (set once dd.char exists) so the two right edges stay
  -- aligned at every window width — top-corner anchoring keeps the box in row 1 despite the
  -- row-2 reference (the -ROW2 y-offset lifts it back up). The Save/Reset/Clear cluster sits to
  -- its right; the min window width guarantees they never overlap.
  local search = CreateFrame("EditBox", nil, bar, "BackdropTemplate")
  search:SetHeight(20)
  search:SetPoint("TOPLEFT", dd.dir, "TOPRIGHT", 8, 0)
  search:SetAutoFocus(false)
  search:SetFontObject("GameFontHighlightSmall")
  search:SetTextInsets(6, 6, 0, 0)
  search:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                       insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  search:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  search:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
  local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ph:SetPoint("LEFT", 6, 0)
  ph:SetText("Search items…")
  search:SetScript("OnTextChanged", function(self2)
    local t = self2:GetText()
    ph:SetShown(t == "")
    B.activeFilter.text = (t ~= "") and t or nil
    ApplyFilter()
  end)
  search:SetScript("OnEscapePressed", function(self2) self2:ClearFocus() end)
  search:SetScript("OnEnterPressed", function(self2) self2:ClearFocus() end)
  self._search = search

  -- ── Row 2: column filters, left→right in the same order the columns appear in the table:
  --   Date · Bound · Quality · Type · SubType · Source · Zone · Character ──
  dd.date = NS.MakeDropdown(bar, 120)
  dd.date:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, ROW2)
  dd.date:SetOptions(DATE_OPTIONS)
  dd.date:SetValue("all", "Date: All")
  dd.date.onSelect = function(v)
    if v == "all" then B.activeFilter.from = nil else B.activeFilter.from = NS.Util.RangeFrom(v) end
    ApplyFilter()
  end

  -- Bound (multi-select): binding-state filter. "NONE" matches unbound records.
  dd.bound = NS.MakeDropdown(bar, 96)
  dd.bound:SetPoint("LEFT", dd.date, "RIGHT", 8, 0)
  dd.bound:SetMulti(true)
  dd.bound:SetOptions(boundOptions())
  dd.bound.onMultiSelect = function(set)
    B.activeFilter.bound = setToFilter(set)
    ApplyFilter()
  end

  -- Quality/Type/Source/Zone/Character are multi-select: their onMultiSelect receives the current
  -- selection set (empty = All), copied into the matching filter field. The "all" menu item clears.
  dd.quality = NS.MakeDropdown(bar, 100)
  dd.quality:SetPoint("LEFT", dd.bound, "RIGHT", 8, 0)
  dd.quality:SetMulti(true)
  dd.quality:SetOptions(qualityOptions())
  dd.quality.onMultiSelect = function(set)
    B.activeFilter.quality = setToFilter(set)
    applyQualityFloor(B.activeFilter)
    ApplyFilter()
  end

  dd.type = NS.MakeDropdown(bar, 112)
  dd.type:SetPoint("LEFT", dd.quality, "RIGHT", 8, 0)
  dd.type:SetMulti(true)
  dd.type.onMultiSelect = function(set)
    B.activeFilter.itemType = setToFilter(set)
    ApplyFilter()
  end

  dd.subtype = NS.MakeDropdown(bar, 100)
  dd.subtype:SetPoint("LEFT", dd.type, "RIGHT", 8, 0)
  dd.subtype:SetMulti(true)
  dd.subtype.onMultiSelect = function(set)
    B.activeFilter.itemSubType = setToFilter(set)
    ApplyFilter()
  end

  dd.source = NS.MakeDropdown(bar, 100)
  dd.source:SetPoint("LEFT", dd.subtype, "RIGHT", 8, 0)
  dd.source:SetMulti(true)
  dd.source.onMultiSelect = function(set)
    B.activeFilter.source = setToFilter(set)
    ApplyFilter()
  end

  dd.zone = NS.MakeDropdown(bar, 146)
  dd.zone:SetPoint("LEFT", dd.source, "RIGHT", 8, 0)
  dd.zone:SetMulti(true)
  dd.zone.onMultiSelect = function(set)
    B.activeFilter.zone = setToFilter(set)
    ApplyFilter()
  end

  dd.char = NS.MakeDropdown(bar, 146)
  dd.char:SetPoint("LEFT", dd.zone, "RIGHT", 8, 0)
  dd.char:SetMulti(true)
  -- "Current" is a preset, not a toggle: it REPLACES the selection with just the current player's
  -- key (a one-click "only me"), nil-guarded so it's a no-op if PlayerKey() is unavailable.
  dd.char.presets = {
    current = function(ddSelf)
      local ck = currentKey()
      ddSelf._selected = ck and { [ck] = true } or {}
    end,
  }
  -- SetCharSet keeps the char filter in sync (the window opens scoped to the current player).
  dd.char.onMultiSelect = function(set) B:SetCharSet(set) end

  -- Pin the row-1 Search box's right edge to the Character dropdown's right edge (see the search
  -- box creation above). -ROW2 lifts the top-right corner from row 2 back up into row 1.
  search:SetPoint("TOPRIGHT", dd.char, "TOPRIGHT", 0, -ROW2)

  -- Export button (row 2): tab-aware (issue #15). On History it exports loot rows (All Data /
  -- Current View → CSV); on Insights it exports the analytics summary (issue #15's Insights CSV).
  -- Both respect the shared filter. Anchored immediately right of the Character
  -- dropdown (8px gap) rather than the bar's far-right edge; the Save/Reset/Clear cluster above it
  -- is re-anchored to Export's top-right corner (see `clear` above), so the two rows stay aligned.
  exportBtn:SetPoint("LEFT", dd.char, "RIGHT", 8, 0)
end
