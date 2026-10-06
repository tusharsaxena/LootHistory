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
-- Modes only a tab's own `groups` list offers (Holdings' SubType); History's menu stays the set above.
local GROUP_EXTRA = {
  { value = "subtype", label = "Group: SubType" },
}

-- The Group menu for a tab spec: History's full set by default, or exactly the spec's `groups`, in
-- its order (Browser:SyncGroupControl).
local function groupOptionsFor(spec)
  if not (spec and spec.groups) then return GROUP_OPTIONS end
  local byValue, out = {}, {}
  for _, set in ipairs({ GROUP_OPTIONS, GROUP_EXTRA }) do
    for _, o in ipairs(set) do byValue[o.value] = o end
  end
  for _, v in ipairs(spec.groups) do out[#out + 1] = byValue[v] end
  return out
end

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
B._groupOptionsFor = groupOptionsFor

-- ── Control widths: every label on one line ──────────────────────────────────────────────────
-- Owner feedback (P4): fixed widths let "Direction: 2 selected" and "Quality: Common+" wrap onto a
-- second line. Each dropdown is now as wide as the widest collapsed label it can show, measured
-- with its OWN label FontString (GetUnboundedStringWidth) at build time, and that label is pinned
-- to one non-wrapping line. What can be measured is every STATIC label: the static option sets,
-- the "All" sentinels, "Quality: <q>+" for every quality, every bound state and source, and the
-- library's "<Prefix>: N selected" summary (N up to the option count for a fixed list, two digits
-- for a data-driven one). A data-driven SINGLE pick (one zone, one item type, one character) can be
-- any length, so it is not widened for: it truncates on its one line instead of wrapping.
--
-- FLOOR is the width each control shipped with, so a control never narrows (and a headless font
-- that measures 0 builds the bar exactly as before). Direction and Bound share the larger of their
-- two widths (owner ask), and Group stays as wide as the Date dropdown directly below it.
local GAP, SEARCH_MIN = 8, 120   -- the gap between controls; the narrowest the Search box may get
local ROW1_Y, ROW2_Y = 0, -24    -- the two rows' y offsets inside the bar
-- The library's collapsed label sits 6 px in from the left and 16 px in from the right (the arrow),
-- plus 4 px so the longest label never touches the arrow.
local DD_PAD = 6 + 16 + 4
local FLOOR = { group = 120, dir = 104, date = 120, bound = 96, quality = 100, type = 112,
                subtype = 100, source = 100, zone = 146, char = 146 }
local ROW2_KEYS = { "date", "bound", "quality", "type", "subtype", "source", "zone", "char" }
local MAX_QUALITY = 8      -- Poor (0) through WoW Token (8): every quality the Quality list can offer
local OPEN_COUNT  = 99     -- a data-driven list's "N selected" is measured at two digits

local function addLabels(out, opts)
  for _, o in ipairs(opts) do out[#out + 1] = o.label end
end

-- The library's multi-select summary, "<Prefix>: N selected", for every N from 2 to `maxN`.
local function addSummaries(out, prefix, maxN)
  for n = 2, maxN do out[#out + 1] = prefix .. ": " .. n .. " selected" end
end

-- Every static collapsed label each control can show, keyed like B._dd.
local function widthLabels()
  local L = { group = {}, date = {}, dir = {}, bound = { "Bound: All" },
              quality = { "Quality: All" }, source = { "Source: All" },
              type = { "Type: All" }, subtype = { "SubType: All" }, zone = { "Zone: All" },
              char = { "Character: All", "Character: Current" } }
  addLabels(L.group, GROUP_OPTIONS)
  addLabels(L.group, GROUP_EXTRA)
  addLabels(L.date, DATE_OPTIONS)
  addLabels(L.dir, DIR_OPTIONS)
  addSummaries(L.dir, "Direction", #DIR_OPTIONS - 1)
  for _, k in ipairs(B._boundOrder) do L.bound[#L.bound + 1] = B._boundLabel[k] end
  addSummaries(L.bound, "Bound", #B._boundOrder)
  for q = 0, MAX_QUALITY do
    local name = NS.Item.QualityLabel(q)
    L.quality[#L.quality + 1] = name
    L.quality[#L.quality + 1] = "Quality: " .. name .. "+"   -- the minimum-quality "All" label
  end
  addSummaries(L.quality, "Quality", MAX_QUALITY + 1)
  for _, label in pairs(NS.Constants.SourceLabel) do L.source[#L.source + 1] = label end
  for key, prefix in pairs({ source = "Source", type = "Type", subtype = "SubType", zone = "Zone",
                             char = "Character" }) do
    L[key][#L[key] + 1] = prefix .. ": " .. OPEN_COUNT .. " selected"
  end
  return L
end

-- Each control's width from `measure(key, text)` (pixels): the widest label + DD_PAD, never under
-- FLOOR, with the two pairings applied. Pure given the measurer, so the suite drives it directly.
local function filterWidths(measure)
  local w = {}
  for key, labels in pairs(widthLabels()) do
    local widest = 0
    for _, text in ipairs(labels) do widest = math.max(widest, measure(key, text) or 0) end
    w[key] = math.max(FLOOR[key], math.ceil(widest) + DD_PAD)
  end
  w.dir = math.max(w.dir, w.bound); w.bound = w.dir
  w.group = math.max(w.group, w.date); w.date = w.group
  return w
end

-- A label's unbounded width in `fs`'s own font. The FontString's text is put back afterwards.
local function measureLabel(fs, text)
  local old = fs:GetText()
  fs:SetText(text)
  local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  fs:SetText(old or "")
  return type(w) == "number" and w or 0
end

-- The dropdown block's span left of the Export column: row 2's eight dropdowns and their gaps, or
-- row 1's Group + Direction + a minimum Search box if that is ever the wider.
local function spanOf(w)
  local row2 = (#ROW2_KEYS - 1) * GAP
  for _, k in ipairs(ROW2_KEYS) do row2 = row2 + w[k] end
  return math.max(row2, w.group + GAP + w.dir + GAP + SEARCH_MIN)
end

-- The span at the built bar's measured widths, or at the floor widths before the bar is built
-- (B:MinWidth in modules/Browser.lua reads it either way).
function B:ToolbarSpan()
  return spanOf(self._ddWidths or filterWidths(function() return 0 end))
end

-- ── Layout: the bar fills the window, scaled by one ratio (P6 Task 3) ─────────────────────────
-- Owner feedback: the controls stopped ~120px short of the right border while the left gap was the
-- 6px pane margin. Row 2 now spans the bar exactly, so the right gap always equals the left one:
--   * each row-2 control i (eight dropdowns + Export) has a base width b_i — its measured one-line
--     width (filterWidths), Export its EXPORT_MIN floor;
--   * A = barW - 8 gaps; r = A / sum(b_i), floored at 1 so nothing narrows below its base;
--   * w_i = floor(b_i * r), and Export takes the rounding remainder so the row ends exactly at
--     barW (when r == 1 the row is just the base widths, which the window floor guarantees fit).
-- One ratio for every control keeps their proportions — the widest label stays the widest box.
-- Row 1 sits on row 2's grid: Group over Date, Direction over Bound (same x and width), the
-- Save/Reset/Clear cluster over Export's x-range, and the search box fills between them.
-- Pure given the widths, so the suite drives it directly; B:LayoutFilterBar applies it.
local LAYOUT_ROW2 = { "date", "bound", "quality", "type", "subtype", "source", "zone", "char",
                      "export" }
local ON_ROW1 = { group = true, dir = true, search = true, save = true, reset = true, clear = true }

local function filterBarLayout(widths, barW)
  local base = {}
  for _, k in ipairs(LAYOUT_ROW2) do base[k] = widths[k] end
  base.export = B._EXPORT_MIN
  local sum = 0
  for _, k in ipairs(LAYOUT_ROW2) do sum = sum + base[k] end
  local avail = barW - (#LAYOUT_ROW2 - 1) * GAP
  local r = math.max(1, avail / sum)
  local x, w, cursor, used = {}, {}, 0, 0
  for i, k in ipairs(LAYOUT_ROW2) do
    if i < #LAYOUT_ROW2 then
      w[k] = math.floor(base[k] * r)
      used = used + w[k]
    else
      w[k] = (r > 1) and (avail - used) or base[k]
    end
    x[k] = cursor
    cursor = cursor + w[k] + GAP
  end
  x.group, w.group = x.date, w.date
  x.dir, w.dir = x.bound, w.bound
  -- Three buttons, two gaps, exactly Export's width: equal widths, the left-most (Save) absorbing
  -- the 0-2px rounding remainder.
  local btn = math.floor((w.export - 2 * GAP) / 3)
  w.save = w.export - 2 * GAP - 2 * btn
  w.reset, w.clear = btn, btn
  x.save = x.export
  x.reset = x.save + w.save + GAP
  x.clear = x.reset + w.reset + GAP
  x.search = x.dir + w.dir + GAP
  w.search = math.max(0, x.save - GAP - x.search)
  return { r = r, base = base, x = x, w = w }
end

B._filterWidths, B._DD_PAD, B._SEARCH_MIN = filterWidths, DD_PAD, SEARCH_MIN
B._filterBarLayout, B._FILTER_GAP = filterBarLayout, GAP

-- Position and size every bar control for a bar `barW` wide. Cheap — anchors and widths only, no
-- rebuild — and skipped when the width has not changed, because the window's OnSizeChanged
-- (modules/Browser.lua) calls it on every frame of a drag, height-only drags included. A menu left
-- open would hang off a dropdown that just moved, so it is closed first. No-op on a degraded
-- install, where the bar was never built.
function B:LayoutFilterBar(barW)
  local ctl = self._barCtl
  if not (ctl and self._ddWidths and type(barW) == "number") or barW == self._barW then return end
  self._barW = barW
  NS.CloseMenu()
  local L = filterBarLayout(self._ddWidths, barW)
  for k, c in pairs(ctl) do
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", self._bar, "TOPLEFT", L.x[k], ON_ROW1[k] and ROW1_Y or ROW2_Y)
    c:SetWidth(L.w[k])
  end
end

-- A small flat-skin text button for the filter bar (Export / Clear / Save / Reset).
--
-- `icon` is a catalog name and is OPTIONAL. The LABEL NEVER MOVES: it stays CENTER-anchored and
-- the mark sits at LEFT +10, so a nil from the seam leaves the button exactly as it was rather
-- than off-center. Only buttons at least ~120px wide are given one -- a 14px mark plus a centered
-- five-letter word does not fit a Clear/Save/Reset button (Export's scaled width split three ways
-- with 8px gaps: about 34px at the toolbar floor, wider above it), and an off-center label is worse
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
-- Nothing is anchored here: every control's position and width belong to B:LayoutFilterBar, which
-- the window re-runs whenever its width changes.
function B:BuildFilterBar(bar)
  -- REFUSE TO DRAW rather than build dead controls. The ten dropdowns below are the whole point
  -- of this bar, and NS.MakeDropdown answers nil on an install with no LibKa0s: a bar of buttons
  -- that open no menu is strictly worse than no bar. The FIRST dropdown is the probe -- one real
  -- control, not a throwaway -- and `self._dd` is published only once it exists, so it stays nil
  -- on a degraded install. That is the state every reader downstream (RefreshFilterOptions,
  -- CaptureView, ApplyView, SetCharSet) has always had to tolerate, because the filter paths run
  -- headlessly too.
  local dd = { group = NS.MakeDropdown(bar, FLOOR.group) }
  if not dd.group then return end
  self._dd = dd

  -- ── Row 1: Group by · Direction · Search · Save · Reset · Clear ──
  -- Group sits over the Date dropdown below it, Direction over Bound, and the Save/Reset/Clear
  -- cluster over Export (B:LayoutFilterBar).
  dd.group:SetOptions(GROUP_OPTIONS)
  dd.group:SetValue("none", "Group: None")
  -- The active tab's group (B:SetGroup): History's table, or a tab that owns its own (Holdings).
  dd.group.onSelect = function(v) B:SetGroup(v) end

  -- Direction (multi-select), between Group and Search: row 2's span is the toolbar's width floor
  -- (B:ToolbarSpan), so a ninth row-2 dropdown would widen the minimum window by its whole width;
  -- row 1's search box absorbs it instead. As wide as Bound (the fit pairs them).
  dd.dir = NS.MakeDropdown(bar, FLOOR.dir)
  dd.dir:SetMulti(true)
  dd.dir:SetOptions(DIR_OPTIONS)
  dd.dir.onMultiSelect = function(set)
    B.activeFilter.dir = setToFilter(set)
    ApplyFilter()
  end

  -- Item-name search box (row 1): it fills from Direction to the Save/Reset/Clear cluster, so its
  -- right edge lines up with the row-2 Character dropdown's at every window width.
  local search = CreateFrame("EditBox", nil, bar, "BackdropTemplate")
  search:SetHeight(20)
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
  dd.date = NS.MakeDropdown(bar, FLOOR.date)
  dd.date:SetOptions(DATE_OPTIONS)
  dd.date:SetValue("all", "Date: All")
  dd.date.onSelect = function(v)
    if v == "all" then B.activeFilter.from = nil else B.activeFilter.from = NS.Util.RangeFrom(v) end
    ApplyFilter()
  end

  -- Bound (multi-select): binding-state filter. "NONE" matches unbound records.
  dd.bound = NS.MakeDropdown(bar, FLOOR.bound)
  dd.bound:SetMulti(true)
  dd.bound:SetOptions(boundOptions())
  dd.bound.onMultiSelect = function(set)
    B.activeFilter.bound = setToFilter(set)
    ApplyFilter()
  end

  -- Quality/Type/Source/Zone/Character are multi-select: their onMultiSelect receives the current
  -- selection set (empty = All), copied into the matching filter field. The "all" menu item clears.
  dd.quality = NS.MakeDropdown(bar, FLOOR.quality)
  dd.quality:SetMulti(true)
  dd.quality:SetOptions(qualityOptions())
  dd.quality.onMultiSelect = function(set)
    B.activeFilter.quality = setToFilter(set)
    applyQualityFloor(B.activeFilter)
    ApplyFilter()
  end

  dd.type = NS.MakeDropdown(bar, FLOOR.type)
  dd.type:SetMulti(true)
  dd.type.onMultiSelect = function(set)
    B.activeFilter.itemType = setToFilter(set)
    ApplyFilter()
  end

  dd.subtype = NS.MakeDropdown(bar, FLOOR.subtype)
  dd.subtype:SetMulti(true)
  dd.subtype.onMultiSelect = function(set)
    B.activeFilter.itemSubType = setToFilter(set)
    ApplyFilter()
  end

  dd.source = NS.MakeDropdown(bar, FLOOR.source)
  dd.source:SetMulti(true)
  dd.source.onMultiSelect = function(set)
    B.activeFilter.source = setToFilter(set)
    ApplyFilter()
  end

  dd.zone = NS.MakeDropdown(bar, FLOOR.zone)
  dd.zone:SetMulti(true)
  dd.zone.onMultiSelect = function(set)
    B.activeFilter.zone = setToFilter(set)
    ApplyFilter()
  end

  dd.char = NS.MakeDropdown(bar, FLOOR.char)
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

  -- ── Fit: each control as wide as its widest label, every label on one line ──
  -- See filterWidths above. Measured once, here: the label sets are static, so a later
  -- RefreshFilterOptions never needs a re-fit.
  local widths = filterWidths(function(key, text) return measureLabel(dd[key].text, text) end)
  for key, w in pairs(widths) do
    dd[key]:SetWidth(w)
    dd[key].text:SetWordWrap(false)
    dd[key].text:SetMaxLines(1)
  end
  self._ddWidths = widths

  -- Export (row 2) and the Save/Reset/Clear cluster above it. Their widths are not fixed:
  -- B:LayoutFilterBar scales Export with the rest of row 2 and splits its x-range three ways for
  -- the cluster, so they are built at Export's base width and sized there.
  --
  -- NO MARK ON EXPORT. The filter bar's Export button is one word in a row of four plain word
  -- buttons (Save/Reset/Clear beside it), and a download arrow on the widest of them made the row
  -- read as one decorated button among three bare ones. The mark stays where it explains
  -- something: the export window's "Export to CSV" (modules/Export.lua), where the spreadsheet
  -- says WHERE the result lands.
  --
  -- Tab-aware (issue #15): on History it exports loot rows (All Data / Current View → CSV); on
  -- Insights the analytics summary. Both respect the shared filter.
  local exportW = B._EXPORT_MIN
  local exportBtn = makeBarButton(bar, "Export", exportW, function() B:OpenExport() end,
    "Export the current tab — loot rows (History) or the analytics summary (Insights).")
  self._exportBtn = exportBtn
  local clear = makeBarButton(bar, "Clear", exportW, function() B:ClearFilters() end,
    "Clear filters and group/sort back to your saved view.")
  local resetBtn = makeBarButton(bar, "Reset", exportW, function() B:ResetView() end,
    "Reset the saved view to stock defaults.")
  local saveBtn = makeBarButton(bar, "Save", exportW, function() B:SaveView() end,
    "Save the current group, sort and filters as your default view.")

  -- Every control B:LayoutFilterBar places, keyed like filterBarLayout's x / w tables.
  local ctl = { search = search, export = exportBtn, save = saveBtn, reset = resetBtn, clear = clear }
  for k, d in pairs(dd) do ctl[k] = d end
  self._bar, self._barCtl, self._barW = bar, ctl, nil
  self:LayoutFilterBar(bar:GetWidth())
end
