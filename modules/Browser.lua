local addonName, NS = ...
NS.Browser = NS.Browser or {}
local B = NS.Browser
local frame
local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer (events-frames-taint-§8)

local LDB_NAME = "Ka0s Loot History"  -- LibDataBroker object + LibDBIcon registration key
local minimapObject                   -- the LDB launcher, created once on first Enable
local DBIcon                          -- LibDBIcon-1.0, resolved lazily in SetupMinimap

-- The window CHROME this addon owns: the tab strip's two label colors and every height the layout
-- is measured from. The window EDGE is NOT here — the dark flat background, the 1px black outer
-- border, the 1px gray inner highlight, the gold title tint and the gray divider are the normative
-- Ka0s edge, and they live in Core.SKIN (standalone-windows). B:ApplySkin below delegates to
-- Core.ApplySkin rather than restating them, so the History browser, both export copy windows and
-- the debug console cannot drift apart. The seam stays because those four reach the edge through it.
-- TODO (post-1.0.0): make the skin user-configurable (border color/size, background color/alpha,
-- font) via settings. That now belongs at the LibKa0s seam, not here. Tracked as a GitHub issue.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SKIN = {
  tabActive   = { 1.0, 0.82, 0.0 },          -- active tab label (gold)
  tabIdle     = { 0.7, 0.7, 0.72 },          -- idle tab label (gray)
  titleBarH   = 30,
  tabStripH   = 26,
  contentGap  = 14,    -- vertical spacing between the tab strip and the pane content
  defaultH    = 700,   -- opening height — shows the full Insights view without scrolling
  minH        = 460,   -- minimum height (content scrolls below this)
}
B.SKIN = SKIN

-- ── Toolbar geometry (single source of truth) ──────────────────────────────────
-- The 8 row-2 filter dropdowns pack left from the pane's left edge; their combined span
-- (fixed widths + inter-gaps) never changes. The row-2 Export button and the row-1
-- Save/Reset/Clear cluster above it fill the slack from the Character dropdown's right edge
-- to the window's right edge AT MIN WIDTH, and are STATIC — they don't grow when the window
-- widens (the extra space opens up on the right). Both EnsureFrame (the window floor) and
-- BuildFilterBar (Export/cluster sizing) read B:MinWidth() / DROPDOWNS_W here, so the window
-- floor and the toolbar packing can never drift apart.
--   Row-2 dropdowns: Date120 Bound96 Quality100 Type112 SubType100 Source100 Zone146 Character146
local DROPDOWNS_W = 120 + 96 + 100 + 112 + 100 + 100 + 146 + 146 + 7 * 8   -- = 976 (widths + 7×8 gaps)
local EXPORT_MIN  = 120                                                    -- Export never narrower than this
local TOOLBAR_MIN = DROPDOWNS_W + 8 + EXPORT_MIN + 12                      -- dropdowns + gap + min Export + pane margins = 1116

-- Minimum (and default-open) window width: the wider of the column-derived table floor
-- (BrowserTable:MinFrameWidth) and the toolbar-fit floor (TOOLBAR_MIN). Shared by EnsureFrame
-- and the filter-bar builder so Export/cluster geometry stays consistent with the frame size.
function B:MinWidth()
  local colW = (NS.BrowserTable and NS.BrowserTable.MinFrameWidth and NS.BrowserTable:MinFrameWidth())
    or 822
  return math.max(colW, TOOLBAR_MIN)
end

-- Static Export button width: fills from the Character dropdown's right edge (+8px gap) to the
-- bar's right edge at min width, clamped to EXPORT_MIN. (minW-12) is the bar inner width at min
-- (6px pane margin each side); minus the dropdown span + gap leaves exactly the Export width.
function B:ExportWidth()
  return math.max(EXPORT_MIN, (self:MinWidth() - 12) - (DROPDOWNS_W + 8))
end

-- Wear the shared Ka0s window edge. Every value this used to spell out — the WHITE8x8 backdrop at
-- edgeSize 1 with 1px insets, the {0.06,0.06,0.08,0.92} fill, the black border, the
-- {0.24,0.24,0.27,0.85} inner highlight and divider, the {1,0.82,0} title — is Core.SKIN, byte for
-- byte, and Core.ApplySkin makes the same calls in the same order, including building the
-- inner-border child exactly once. Delegated rather than restated so a re-skin lands on every Ka0s
-- window at once (standalone-windows).
--
-- NS.ApplySkin is core/CoreSetup.lua's seam: the library's on a working install, and that file's
-- own pre-library copy when libs/LibKa0s is missing, so the window wears the same edge either way.
-- Guarded anyway, because this is the only file that skins a frame this addon owns. The seam is
-- kept as a method because four windows reach the edge through it — EnsureFrame here, both export
-- copy windows (modules/Export.lua) and the debug console (core/DebugLogSetup.lua's applySkin).
-- `skin` is forwarded even though nothing in this addon passes one today. A forwarder must carry
-- every argument its target takes (anti-patterns #64): lib.ApplySkin(frame, skin) accepts an
-- override table, and a one-argument passthrough drops it silently -- the call still runs, the
-- window still gets an edge, and the override simply never arrives.
function B:ApplySkin(f, skin)
  if NS.ApplySkin then NS.ApplySkin(f, skin) end
end

-- The close control every window this addon owns wears -- the History browser, the export modal
-- and the export copy window. It is Core's, reached through core/CoreSetup.lua's NS.MakeCloseButton
-- so the addon folder name is passed and the shared `close` mark is what draws; on an install
-- missing LibKa0s the same seam answers with the 24x24 class-colored multiplication sign this
-- addon drew before, which is the degraded look and not a second design.
--
-- Kept as a method rather than retired because three call sites and docs/browser.md name it, and
-- because it is the one place to change if this addon ever wants a different control again.
function B:MakeCloseButton(parent, onClick)
  if not NS.MakeCloseButton then return nil end
  return NS.MakeCloseButton(parent, onClick)
end

-- ── Window position/size persistence ──────────────────────────────────────────
-- settings.window = { point, x, y, w, h } relative to UIParent.
--
-- NOTE: settings.window and savedView (see savedViewOrStock below) are view/window runtime state
-- persisted directly to NS.db.global by the Browser — they are intentionally NOT Schema rows, so
-- they don't route through Schema:Set. The "every mutation goes through Schema:Set" convention
-- (CLAUDE §2) covers user settings only; window geometry (standalone-windows) and the saved table
-- view are carved out. See docs/schema.md.

local function SaveWindow()
  if not frame then return end
  local point, _, _, x, y = frame:GetPoint(1)
  NS.db.global.settings.window = {
    point = point, x = x, y = y,
    w = frame:GetWidth(), h = frame:GetHeight(),
  }
end

local function RestoreWindow()
  local w = NS.db and NS.db.global.settings.window
  frame:ClearAllPoints()
  if w and w.point then
    frame:SetPoint(w.point, UIParent, w.point, w.x or 0, w.y or 0)
    if w.w and w.h then
      frame:SetSize(math.max(B._minW or 0, w.w), math.max(B._minH or 0, w.h))
    end
  else
    -- Default (fresh install / after a settings reset): dead-center of the screen, H and V.
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

-- ── Tabs ──────────────────────────────────────────────────────────────────────
local TABS = { "History", "Insights" }
local lastTab = "History"   -- remembered within a session

-- Lazily let the owning modules build their pane content the first time it's shown. The filter bar
-- and footer are NOT here — they are shared window chrome built once in EnsureFrame (issue #13), so
-- both panes render off the same singleton filter. Each pane holds only its view: the table
-- (History) or the analytics charts (Insights).
local function BuildPane(name)
  local pane = frame.panes[name]
  if pane._built then return end
  pane._built = true
  if name == "History" then
    B:BuildTable(pane)
  elseif name == "Insights" and NS.Analytics and NS.Analytics.Attach then
    NS.Analytics:Attach(pane)
  end
end

function B:SelectTab(name)
  if not frame then return end
  lastTab = name
  for _, t in ipairs(TABS) do
    local active = (t == name)
    frame.panes[t]:SetShown(active)
    frame.tabs[t].label:SetTextColor(unpack(active and SKIN.tabActive or SKIN.tabIdle))
    frame.tabs[t].underline:SetShown(active)
  end
  BuildPane(name)
  -- Refresh the newly shown view against the shared filter, then repaint the shared footer/DB size
  -- (issue #13: both read the same filter, so they're kept current on either tab).
  if name == "History" and NS.BrowserTable and NS.BrowserTable.Refresh then
    NS.BrowserTable:Refresh()
    B:RefreshFilterOptions()
  elseif name == "Insights" and NS.Analytics and NS.Analytics.Refresh then
    NS.Analytics:Refresh()
  end
  B:UpdateFooter()
  B:UpdateDbSize()
  if NS.State.debug and NS.Debug then NS.Debug("UI", "tab -> %s", tostring(name)) end
end

local function CreateTabStrip()
  local strip = CreateFrame("Frame", nil, frame)
  strip:SetPoint("TOPLEFT", frame.divider, "BOTTOMLEFT", 6, -2)
  strip:SetPoint("TOPRIGHT", frame.divider, "BOTTOMRIGHT", -6, -2)
  strip:SetHeight(SKIN.tabStripH)
  frame.tabStrip = strip
  frame.tabs = {}

  local x = 0
  for _, name in ipairs(TABS) do
    local tab = CreateFrame("Button", nil, strip)
    tab:SetSize(90, SKIN.tabStripH)
    tab:SetPoint("LEFT", x, 0)
    local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(name)
    tab.label = label
    local underline = tab:CreateTexture(nil, "ARTWORK")
    underline:SetColorTexture(unpack(SKIN.tabActive))
    underline:SetHeight(2)
    underline:SetPoint("BOTTOMLEFT", 8, 0)
    underline:SetPoint("BOTTOMRIGHT", -8, 0)
    tab.underline = underline
    tab:SetScript("OnClick", function() B:SelectTab(name) end)
    frame.tabs[name] = tab
    x = x + 94
  end
end

-- ── Filter bar ──────────────────────────────────────────────────────────────────
-- Compact custom dropdowns + search box matching the flat skin (no Blizzard UIDropDownMenu,
-- so the look stays consistent and there's no protected-call taint surface). All filter
-- changes write B.activeFilter and push it to BrowserTable:SetFilter; group-by drives
-- BrowserTable:SetGroupBy. A footer reports "Showing X of Y".

B.activeFilter = {}

-- THE DROPDOWNS ARE THE LIBRARY'S. Everything that used to stand here -- a MakeDropdown factory,
-- a FULLSCREEN_DIALOG singleton popup with pooled rows, a full-screen click-catcher and six
-- helpers, about two hundred lines -- is now LibKa0s-Widgets-1.0, reached through
-- core/WidgetsSetup.lua's NS.MakeDropdown / NS.CloseMenu. This file was where the widget was
-- written, and it was the third copy of it in the collection; the library carries the two seams
-- this addon's Character filter needs (`opt.isActive` and `dd.presets`, both new at Widgets minor
-- 4 and both ported upstream from here), so the adoption lost nothing. The one behavior that
-- lived here and has no library equivalent is `opt.icon`: a class icon is now folded into the
-- option's LABEL as inline markup, which the library measures (see charOptions below).
--
-- NS.MakeDropdown answers nil on an install with no library, and BuildFilterBar refuses to draw
-- rather than building dead controls -- see the guard at the top of it.
-- Item-quality color as an {r, g, b} triple for tinting dropdown items, or nil if unavailable.
local function qualityColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return { c.r, c.g, c.b } end
  return nil
end

-- Static option sets. "all" is the sentinel for "no filter"; onSelect maps it to nil.
-- (Quality is data-driven — see qualityOptions below — so any quality the history actually contains,
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
}
local DATE_OPTIONS = {
  { value = "all", label = "Date: All" },
  { value = "today", label = "Today" },
  { value = "7d", label = "Last 7 days" },
  { value = "30d", label = "Last 30 days" },
}
-- Binding-state filter labels + fixed display order. "NONE" matches unbound records (r.bound == nil);
-- the other tokens match their bound state. Labels mirror the Bound column's tooltip legend
-- (BrowserTable BOUND_LEGEND). Data-driven like the other value filters (see boundOptions): only the
-- states actually present in the dataset are offered, kept in this logical order (not data order).
local BOUND_LABEL = {
  NONE = "Not Bound", BOE = "Bind on Equip", BOP = "Bind on Pickup",
  WARBAND = "Warbound", WARBAND_UE = "Warbound Until Equipped",
}
local BOUND_ORDER = { "NONE", "BOE", "BOP", "WARBAND", "WARBAND_UE" }

-- The saved "view" = group-by + sort + column filters (NOT the player scope, which is a
-- session-only default of "current player"). This is the stock/reset baseline; the user's
-- saved view lives in NS.db.global.savedView. `date` stores the range option (not an absolute
-- `from`) so it recomputes correctly on each load.
local STOCK_VIEW = {
  groupBy = "none", sortKey = "date", sortAsc = false, groupAsc = true,
  quality = "all", source = "all", itemType = "all", itemSubType = "all", zone = "all",
  date = "all", bound = "all", search = "",
}
local function savedViewOrStock()
  local v = NS.db and NS.db.global and NS.db.global.savedView
  if type(v) == "table" then return v end
  return STOCK_VIEW
end

-- A small flat-skin text button for the filter bar (Export / Clear / Save / Reset).
--
-- `icon` is a catalog name and is OPTIONAL. The LABEL NEVER MOVES: it stays CENTER-anchored and
-- the mark sits at LEFT +10, so a nil from the seam leaves the button exactly as it was rather
-- than off-centre. Only buttons at least ~120px wide are given one -- a 14px mark plus a centred
-- five-letter word does not fit the 36px Clear/Reset cluster, and an off-centre label is worse
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

-- The dataset the filter bar reflects: the table's current records (test data in test mode,
-- otherwise the live history) so dropdown options + the footer match what the table shows.
local function dataset()
  if NS.BrowserTable and NS.BrowserTable.CurrentRecords then
    return NS.BrowserTable:CurrentRecords()
  end
  return NS.Database:History()
end

-- Sort distinct options by label and prefix the "All" sentinel (kept first regardless of sort).
--
-- `sortText` is an optional per-item sort key, and exactly one caller needs it: the Character rows
-- fold a class icon into their LABEL as inline markup, because LibKa0s-Widgets-1.0 has no `icon`
-- field on an option and measures markup in a label instead. Sorting those on the label would order
-- the menu by texture path rather than by character name.
local function withAll(allLabel, items, sortText)
  local keyOf = sortText or function(o) return o.label end
  table.sort(items, function(a, b) return keyOf(a) < keyOf(b) end)
  table.insert(items, 1, { value = "all", label = allLabel })
  return items
end

-- Distinct { value, label } option lists from the current dataset, each prefixed with "All".
local function sourceOptions()
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    local s = r.source
    if s and not seen[s] then
      seen[s] = true
      items[#items + 1] = { value = s, label = (NS.Constants.SourceLabel[s] or s) }
    end
  end
  return withAll("Source: All", items)
end
local function charOptions()
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    local c = r.char
    if c and not seen[c] then
      seen[c] = true
      -- The class icon is FOLDED INTO THE LABEL, not carried in a field of its own. The widget is
      -- LibKa0s-Widgets-1.0's and it has no `icon` seam -- deliberately: inline |T...|t / |A...|a
      -- markup in a label is measured by its menuWidth (a class icon plus a Name-Realm is the
      -- example in its own comment), so a label is the supported way to put art on a row. The
      -- class color still rides in `color`, matching the Character column.
      local icon = (NS.BrowserTable and NS.BrowserTable.ClassIconMarkup
        and NS.BrowserTable:ClassIconMarkup(r.classFile)) or ""
      local cc = r.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.classFile]
      items[#items + 1] = {
        value = c, label = (icon ~= "" and (icon .. " " .. c) or c),
        color = cc and { cc.r, cc.g, cc.b } or nil,
      }
    end
  end
  -- Sorted on the character name, not on the icon-prefixed label -- see withAll's `sortText`.
  local opts = withAll("Character: All", items, function(o) return o.value end)
  -- "Character: Current" is a one-click preset (see dd.char.presets below), not a real char value —
  -- inserted right after the "All" sentinel so the menu reads All / Current / <each character>. Its
  -- `isActive` lights it gold (like "All") when the selection is exactly the current player.
  table.insert(opts, 2, {
    value = "current", label = "Character: Current",
    isActive = function(dd)
      local ck = NS.Util and NS.Util.PlayerKey and NS.Util.PlayerKey()
      local sel = dd._selected or {}
      if not (ck and sel[ck]) then return false end
      for k in pairs(sel) do if k ~= ck then return false end end   -- exactly {current}
      return true
    end,
  })
  return opts
end
local function typeOptions()
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    local ty = r.itemType
    if ty and ty ~= "" and not seen[ty] then
      seen[ty] = true
      items[#items + 1] = { value = ty, label = ty }
    end
  end
  return withAll("Type: All", items)
end
local function subtypeOptions()
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    local st = r.itemSubType
    if st and st ~= "" and not seen[st] then
      seen[st] = true
      items[#items + 1] = { value = st, label = st }
    end
  end
  return withAll("SubType: All", items)
end
-- Keyed by zone NAME, not mapID: a single named zone spans many UiMapIDs — every dungeon floor and
-- sub-map has its own — so keying by id listed "Halls of Atonement" once per floor, each entry
-- filtering only part of the zone. The name is also what the Zone column, group-by-zone and the
-- Insights "Top Zones" list already key on, so all four now agree. Records with no captured name
-- share one "Unknown" bucket (the empty string, which is what QueryList matches them on).
local function zoneOptions()
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    local z = r.zone or ""
    if not seen[z] then
      seen[z] = true
      items[#items + 1] = { value = z, label = (z ~= "" and z) or "Unknown" }
    end
  end
  return withAll("Zone: All", items)
end
-- Distinct qualities present in the dataset, in quality order (Poor → … → Heirloom), each tinted
-- its quality color. Data-driven (not a fixed 1–5 list) so Heirloom/Poor/Artifact appear whenever
-- the history contains them. NB currency rows carry a quality too, so their tiers appear here as
-- well — unlike the Insights "Quality distribution", which stays item-only (excludes currency).
-- Quality filters an EXACT quality (not "that and above"). "all" (kept first) is the no-filter sentinel.
local function qualityOptions()
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    local q = r.quality
    if q ~= nil and not seen[q] then
      seen[q] = true
      items[#items + 1] = { value = q, label = NS.Item.QualityLabel(q), color = qualityColor(q) }
    end
  end
  table.sort(items, function(a, b) return a.value < b.value end)
  table.insert(items, 1, { value = "all", label = "Quality: All" })
  return items
end
-- Distinct binding states present in the dataset (nil → the "NONE" sentinel), kept in the fixed
-- BOUND_ORDER (not data order). Data-driven like the other value filters, so e.g. Warbound only
-- appears once some loot is warbound. "all" (kept first) is the no-filter sentinel.
local function boundOptions()
  local present = {}
  for _, r in ipairs(dataset()) do present[r.bound or "NONE"] = true end
  local items = { { value = "all", label = "Bound: All" } }
  for _, k in ipairs(BOUND_ORDER) do
    if present[k] then items[#items + 1] = { value = k, label = BOUND_LABEL[k] } end
  end
  return items
end

-- Copy a multi-select set into a plain filter value: a fresh set when non-empty, else nil (no
-- filter). Copied — not aliased to the dropdown's live set — so a later toggle can't mutate the
-- filter behind the table's back.
local function setToFilter(set)
  local copy, n = {}, 0
  if type(set) == "table" then for k in pairs(set) do copy[k] = true; n = n + 1 end end
  return n > 0 and copy or nil
end

-- Normalize a stored view field into a selection set. Tolerates the legacy scalar form (a single
-- value, or the "all" sentinel) alongside the current set form, so pre-multi-select saved views
-- still load.
local function asSet(v)
  local s = {}
  if type(v) == "table" then
    for k, on in pairs(v) do if on then s[k] = true end end
  elseif v ~= nil and v ~= "all" then
    s[v] = true
  end
  return s
end

-- Pure helpers published for the headless suite (tests/test_browser.lua). The UI binds through
-- these exact functions, so a test that pins their behavior pins the shipped behavior. Read-only
-- from outside the module — nothing here mutates browser state.
B._stockView    = STOCK_VIEW
B._savedViewOrStock = savedViewOrStock
B._setToFilter  = setToFilter
B._asSet        = asSet
B._withAll      = withAll
B._options = {
  source = sourceOptions, char = charOptions, itemType = typeOptions,
  itemSubType = subtypeOptions, zone = zoneOptions, quality = qualityOptions, bound = boundOptions,
}

-- Push the current filter to the table and refresh the footer count. The filter is a singleton
-- for the whole browser (issue #13): it always drives the table (keeping matchCount + the footer
-- current for both tabs), and it drives the Insights charts live while the Insights tab is the one
-- on screen. Switching to Insights re-runs Analytics:Refresh against this same filter (SelectTab),
-- so a filter changed while viewing History is already reflected when Insights is next shown —
-- without paying for an Insights relayout on every History-side keystroke.
local function ApplyFilter()
  if NS.BrowserTable then NS.BrowserTable:SetFilter(B.activeFilter) end
  B:UpdateFooter()
  if lastTab == "Insights" and NS.Analytics and NS.Analytics.Refresh and NS.Analytics.pane then
    NS.Analytics:Refresh()
  end
end

-- The active filter as a plain copy, for Analytics:Stats (issue #13). Shares the exact field shape
-- Database:QueryList consumes (quality/source/itemType/itemSubType/zone/bound/char/from/text), so
-- the Insights view and the History table always filter by identical criteria.
function B:CurrentFilter()
  local out = {}
  for k, v in pairs(self.activeFilter or {}) do out[k] = v end
  return out
end

function B:UpdateFooter()
  if not self._footer then return end
  local shown = (NS.BrowserTable and NS.BrowserTable.matchCount) or 0
  local total = #dataset()
  self._footer:SetText(("Showing %d of %d"):format(shown, total))
end

-- Estimated SavedVariables size of the stored history (the same estimate the settings panel
-- shows, Database:StorageStats). Recomputed only when history changes or the window (re)opens —
-- never on a filter keystroke, since filtering can't change what's stored. \226\137\136 = "≈".
function B:UpdateDbSize()
  if not self._dbFooter then return end
  local bytes = (NS.Database and NS.Database.StorageStats and NS.Database:StorageStats().bytes) or 0
  self._dbFooter:SetText(("Database \226\137\136 %s"):format(NS.Util.FormatBytes(bytes)))
end

-- Recompute the data-driven dropdowns (source/type/char/zone) from the current dataset.
function B:RefreshFilterOptions()
  local dd = self._dd
  if not dd then return end
  dd.bound:SetOptions(boundOptions())
  dd.quality:SetOptions(qualityOptions())
  dd.source:SetOptions(sourceOptions())
  dd.type:SetOptions(typeOptions())
  dd.subtype:SetOptions(subtypeOptions())
  dd.char:SetOptions(charOptions())
  dd.zone:SetOptions(zoneOptions())
end

-- The table's dataset changed (entering/leaving test mode): rebuild the dropdowns from the new
-- dataset. In test mode show everything (stock view, all players, since test chars differ);
-- leaving it, return to the saved view + current player.
function B:OnDatasetChanged()
  self:RefreshFilterOptions()
  if NS.BrowserTable and NS.BrowserTable.testMode then
    self:ApplyView(STOCK_VIEW, "all")
  else
    self:ApplyView(savedViewOrStock(), "current")
  end
  self:UpdateFooter()
  self:UpdateDbSize()
  self:UpdateTestBadge()
  -- The Insights tab reads the same dataset; refresh it so a live Insights view reflects the swap.
  if NS.Analytics and NS.Analytics.Refresh then NS.Analytics:Refresh() end
end

-- Show/hide the bright-red "TEST MODE" badge beside the window title.
function B:UpdateTestBadge()
  if not (frame and frame.testBadge) then return end
  frame.testBadge:SetShown(NS.BrowserTable and NS.BrowserTable.testMode or false)
end

local function currentKey()
  return NS.Util and NS.Util.PlayerKey and NS.Util.PlayerKey() or nil
end

-- The char filter is surfaced by two controls — the player toggle (Current/All) and the
-- multi-select Character dropdown — so both funnel through here and stay in sync. `set` is a
-- { [char] = true } selection set; nil/empty = all players.
function B:SetCharSet(set)
  local filter = setToFilter(set)   -- fresh copy or nil (empty = no char filter = all players)
  self.activeFilter.char = filter
  local dd = self._dd
  if dd and dd.char then dd.char:SetSelected(filter or {}) end
  ApplyFilter()
end

-- The six multi-select column filters, as { view key, dropdown key } in the order the widgets are
-- laid out. One ordered descriptor drives all three passes — capture, the dropdown push and the
-- filter resolution — so a seventh column filter is one entry here rather than three edits. The
-- activeFilter key IS the view key for all six, which is why one list serves them all.
local VIEW_FILTERS = {
  { "quality", "quality" }, { "itemType", "type" }, { "itemSubType", "subtype" },
  { "source", "source" }, { "zone", "zone" }, { "bound", "bound" },
}

-- The table's own group/sort state. With no table yet (headless, pre-UI) every field reads its
-- stock value.
local function captureTableState(BT)
  return {
    groupBy  = BT and BT.groupBy or "none",
    sortKey  = BT and BT.sortKey or "date",
    sortAsc  = BT and BT.sortAsc == true,
    groupAsc = not (BT and BT.groupAsc == false),
  }
end

-- Multi-select column filters are stored as selection sets (copies, so the saved view isn't
-- aliased to the live dropdown state). An empty {} means "All" — never nil.
local function captureFilters(dd, out)
  for i = 1, #VIEW_FILTERS do
    local f = VIEW_FILTERS[i]
    out[f[1]] = setToFilter(dd and dd[f[2]]._selected) or {}
  end
end

-- Capture the current group/sort/column-filters as a view table (excludes the player scope).
-- Character scope is NOT part of the view (it's the session-only Current/All default).
function B:CaptureView()
  local dd = self._dd
  local v = captureTableState(NS.BrowserTable)
  captureFilters(dd, v)
  v.date   = (dd and dd.date._value) or "all"
  v.search = (self._search and self._search:GetText()) or ""
  return v
end

-- Apply a saved/stock view: set the table's group + sort, the column-filter dropdowns, and the
-- resolved filter. The player scope is NOT part of the view — it resets to `scope` (default
-- "current"), keeping "current player" the per-session default. Calls ApplyFilter (refreshes).
-- Push the view's group + sort onto the table, if there is one yet.
local function applyTableState(view)
  local BT = NS.BrowserTable
  if BT then
    BT.groupBy  = view.groupBy or "none"
    BT.sortKey  = view.sortKey or "date"
    BT.sortAsc  = view.sortAsc == true
    BT.groupAsc = view.groupAsc ~= false
  end
end

-- Push the view onto the widgets so the toolbar reads what the filter does.
local function applyDropdowns(dd, view)
  dd.group:SelectValue(view.groupBy or "none")
  for i = 1, #VIEW_FILTERS do
    local f = VIEW_FILTERS[i]
    dd[f[2]]:SetSelected(asSet(view[f[1]]))
  end
  dd.date:SelectValue(view.date or "all")
end

-- Resolve the view's stored fields into the query filter. Tolerates the legacy scalar form via
-- asSet; an unselected column applies no filter at all (nil, not an empty set).
local function resolveFilter(self, view)
  for i = 1, #VIEW_FILTERS do
    local vk = VIEW_FILTERS[i][1]
    self.activeFilter[vk] = setToFilter(asSet(view[vk]))
  end
  if view.date and view.date ~= "all" then self.activeFilter.from = NS.Util.RangeFrom(view.date) end
  if view.search and view.search ~= "" then self.activeFilter.text = view.search end
end

function B:ApplyView(view, scope)
  view = view or STOCK_VIEW
  self.activeFilter = {}
  applyTableState(view)
  local dd = self._dd
  if dd then applyDropdowns(dd, view) end
  if self._search then self._search:SetText(view.search or "") end
  resolveFilter(self, view)
  -- Character scope resets to `scope` (default "current"). SetCharSet also calls ApplyFilter,
  -- so it is the single refresh that paints all the filter fields set just above.
  if scope == "all" then
    self:SetCharSet(nil)
  else
    local ck = currentKey()
    self:SetCharSet(ck and { [ck] = true } or nil)
  end
end

-- Save the current view as the account-wide default; Reset drops it back to stock.
function B:SaveView()
  if NS.db and NS.db.global then
    NS.db.global.savedView = self:CaptureView()
    print("view saved as default.")
  end
end
-- Drop the saved view back to stock. `silent` suppresses the chat line when called programmatically
-- (the destructive "Reset Everything" prints its own single confirmation) — the filter-bar Reset button
-- calls it with no argument and keeps the message.
function B:ResetView(silent)
  if NS.db and NS.db.global then NS.db.global.savedView = nil end
  self:ApplyView(STOCK_VIEW, "current")
  if not silent then print("view reset to stock defaults.") end
end

-- Reset the persisted window geometry (the settings.window storage-only carve-out) and recenter the
-- live frame. Used only by the destructive "Reset Everything" — window position is runtime state, so the
-- non-destructive settings resets deliberately leave it alone.
function B:ResetWindow()
  if NS.db and NS.db.global and NS.db.global.settings then
    NS.db.global.settings.window = {}
  end
  if frame then
    frame:ClearAllPoints()
    RestoreWindow()   -- empty geometry → RestoreWindow centers the frame
  end
end

-- Clear returns the filters/group/sort to the saved default (or stock), and the player scope
-- to "current player".
function B:ClearFilters()
  self:ApplyView(savedViewOrStock(), "current")
end

-- Build the SHARED, singleton filter bar (issue #13) into `bar` — a window-level host anchored
-- once in EnsureFrame, above both tab panes, so a single filter drives the History table AND the
-- Insights charts. The footer is shared window chrome too (built in EnsureFrame); this function
-- owns only the two rows of controls:
--   Row 1: Group by · [search…] · Save · Reset · Clear
--   Row 2: column filters in table order — Date · Bound · Quality · Type · SubType · Source ·
--          Zone · Character · Export
function B:BuildFilterBar(bar)
  local ROW1, ROW2 = 0, -24

  -- REFUSE TO DRAW rather than build dead controls. The nine dropdowns below are the whole point
  -- of this bar, and NS.MakeDropdown answers nil on an install with no LibKa0s: a bar of buttons
  -- that open no menu is strictly worse than no bar. The FIRST dropdown is the probe -- one real
  -- control, not a throwaway -- and `self._dd` is published only once it exists, so it stays nil
  -- on a degraded install. That is the state every reader downstream (RefreshFilterOptions,
  -- CaptureView, ApplyView, SetCharSet) has always had to tolerate, because the filter paths run
  -- headlessly too.
  local dd = { group = NS.MakeDropdown(bar, 120) }
  if not dd.group then return end
  self._dd = dd

  -- ── Row 1: Group by · Search · Clear ──
  -- Group width matches the Date dropdown directly below it (120); the Save+Reset+Clear cluster is
  -- anchored above the Export button (not the bar's right edge) and resized so its span (three
  -- buttons + two 6px gaps) exactly matches Export's width (B:ExportWidth), so the cluster sits
  -- flush above it and both stay static as the window widens.
  dd.group:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, ROW1)
  dd.group:SetOptions(GROUP_OPTIONS)
  dd.group:SetValue("none", "Group: None")
  dd.group.onSelect = function(v) if NS.BrowserTable then NS.BrowserTable:SetGroupBy(v) end end

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

  -- Item-name search box (row 1). Its LEFT sits beside Group; its RIGHT is pinned to the row-2
  -- Character dropdown's right edge below it (set once dd.char exists) so the two right edges stay
  -- aligned at every window width — top-corner anchoring keeps the box in row 1 despite the
  -- row-2 reference (the -ROW2 y-offset lifts it back up). The Save/Reset/Clear cluster sits to
  -- its right; the min window width guarantees they never overlap.
  local search = CreateFrame("EditBox", nil, bar, "BackdropTemplate")
  search:SetHeight(20)
  search:SetPoint("TOPLEFT", dd.group, "TOPRIGHT", 8, 0)
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

-- Route the Export button to the right modal for the active tab (issue #15). History exports the
-- loot rows; Insights exports the analytics summary computed off the SAME shared filter.
function B:OpenExport()
  -- Title tracks the invoking tab ("Export History" / "Export Insights") and generalizes to any
  -- future tab name — the tab that opens the modal supplies its own label. Export to CSV is
  -- tab-specific: History exports the loot rows, Insights the analytics summary.
  local title = "Export " .. tostring(lastTab)
  if lastTab == "Insights" then
    NS.Export:Open({
      title = title,
      providers = {
        allData     = function() return NS.Database:Stats({}) end,
        currentView = function() return NS.Database:Stats(B:CurrentFilter()) end,
      },
      csv = function(stats) return NS.Export:InsightsCSV(stats) end,
    })
  else
    NS.Export:Open({
      title = title,
      providers = {
        allData     = function() return NS.Database:Export({}) end,
        currentView = function()
          return (NS.BrowserTable and NS.BrowserTable.OrderedFilteredRecords
            and NS.BrowserTable:OrderedFilteredRecords()) or {}
        end,
      },
      csv = function(records) return NS.Export:CSV(records) end,
    })
  end
end

-- Attach the virtualized History table to its pane (issue #13: the pane now holds only the table;
-- the filter bar + footer are shared chrome). The table reads B.activeFilter through
-- BrowserTable.filter, already set by the shared bar's ApplyView.
function B:BuildTable(pane)
  local host = CreateFrame("Frame", nil, pane)
  host:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
  host:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
  if NS.BrowserTable and NS.BrowserTable.Attach then
    NS.BrowserTable:Attach(host)
  end
end

-- ── Frame construction ─────────────────────────────────────────────────────────

local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "LootHistoryWindow", UIParent, "BackdropTemplate")
  -- Default size == minimum size: wide enough for every column, so it can grow but never
  -- shrink into horizontal overflow. B:MinWidth() is the single source of truth — the wider of
  -- the column-derived table floor (BrowserTable:MinFrameWidth) and the toolbar-fit floor
  -- (TOOLBAR_MIN = the 8 row-2 dropdowns 976 + an 8px gap + a min Export 120 + 12px pane margins).
  -- The old hard 1160 floor is gone: with the toolbar now packed left and the Export button + the
  -- Save/Reset/Clear cluster filling the slack to the right edge (static), the window may shrink to
  -- whichever floor is larger. The filter bar reads the SAME helper (B:ExportWidth), so the Export/
  -- cluster geometry and this frame width can't drift.
  local minW = B:MinWidth()
  local minH = SKIN.minH
  B._minW, B._minH = minW, minH
  frame:SetSize(minW, SKIN.defaultH)  -- open at the (taller) default; can shrink to minH
  frame:SetFrameStrata("HIGH")
  frame:EnableMouse(true)   -- capture clicks over the whole window; no click-through to the world
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetClampedToScreen(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minW, minH)
  elseif frame.SetMinResize then
    frame:SetMinResize(minW, minH)
  end

  -- Title bar (also the drag handle), flat with a divider line beneath it.
  local titleBar = CreateFrame("Frame", nil, frame)
  titleBar:SetPoint("TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", -1, -1)
  titleBar:SetHeight(SKIN.titleBarH)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  -- Lock frame (options-ui-§15) gates the DRAG, not the frame's movability: SetMovable(false) would
  -- also break StopMovingOrSizing on a drag already in flight, and the setting says "stop the frame
  -- being dragged", which is a gesture rather than a capability.
  titleBar:SetScript("OnDragStart", function()
    if B:IsLocked() then return end
    frame:StartMoving()
  end)
  titleBar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    SaveWindow()
  end)
  frame.titleBar = titleBar

  local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("CENTER")
  title:SetText("Ka0s Loot History")
  frame.title = title

  -- Bright-red badge beside the title, shown only while the table is in test mode.
  local testBadge = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  testBadge:SetPoint("LEFT", title, "RIGHT", 10, 0)
  testBadge:SetText("TEST MODE")
  testBadge:SetTextColor(1, 0.15, 0.15)
  testBadge:Hide()
  frame.testBadge = testBadge

  local divider = frame:CreateTexture(nil, "ARTWORK")
  divider:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
  divider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  divider:SetHeight(1)
  frame.divider = divider

  -- ElvUI-style thin × close glyph (class-colored on hover). Anchored to the title bar's
  -- vertical center so it lines up with the CENTER-anchored title.
  local close = B:MakeCloseButton(titleBar, function() B:Hide() end)
  close:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
  frame.closeButton = close
  -- (Settings gear removed; open the options panel with /lh config.)

  -- Shared window chrome (issue #13): one singleton filter bar above both panes, and one shared
  -- footer below them. Layout from the top: title bar · tab strip · content gap · FILTER BAR ·
  -- panes · FOOTER. The panes now hold only their view (table / charts).
  local FILTERBAR_H, FILTER_GAP, FOOTER_H = 46, 8, 18
  local barTop  = SKIN.titleBarH + SKIN.tabStripH + SKIN.contentGap
  local paneTop = barTop + FILTERBAR_H + FILTER_GAP

  -- Content panes, one per tab, filling between the shared filter bar and the shared footer.
  frame.panes = {}
  for _, name in ipairs(TABS) do
    local pane = CreateFrame("Frame", nil, frame)
    pane:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -paneTop)
    pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, FOOTER_H)
    pane:Hide()
    frame.panes[name] = pane
  end

  CreateTabStrip()

  -- Shared singleton filter bar host, anchored below the tab strip and above the panes.
  local filterHost = CreateFrame("Frame", nil, frame)
  filterHost:SetPoint("TOPLEFT",  frame, "TOPLEFT",   6, -barTop)
  filterHost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -barTop)
  filterHost:SetHeight(FILTERBAR_H)
  frame.filterHost = filterHost

  -- Shared footer: "Showing X of Y" (bottom-left) + estimated DB size (bottom-right). Both track
  -- the shared filter, so they read the same on either tab. x=-20 keeps the size text left of the
  -- 16px resize grip (frame BOTTOMRIGHT -2) so they never overlap.
  local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 3)
  B._footer = footer
  local dbFooter = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  dbFooter:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 3)
  dbFooter:SetJustifyH("RIGHT")
  B._dbFooter = dbFooter

  -- Build the shared filter controls, populate their options, and apply the saved view (opens
  -- scoped to the current player). The table/charts attach lazily per tab and pick up this filter.
  B:BuildFilterBar(filterHost)
  B:RefreshFilterOptions()
  B:ApplyView(savedViewOrStock(), "current")
  B:UpdateDbSize()

  -- Resize grip, bottom-right.
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  -- Blizzard's corner grabber, which is what BankLedger, MultiMeters and the rest of the
  -- collection draw -- three diagonal hatch lines that sit INSIDE the window's corner and read as
  -- part of the frame. This briefly drew the catalog's `resize` mark instead (a big two-headed
  -- arrow, tinted, with a gold hover): one addon's window corner looking unlike every other
  -- window corner in the collection is drift, whichever mark is prettier on its own.
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    SaveWindow()
    if NS.BrowserTable and NS.BrowserTable.Refresh then NS.BrowserTable:Refresh() end
  end)
  frame.resizeGrip = grip

  -- Close any open dropdown menu whenever the window hides (covers the ESC/UISpecialFrames
  -- path, which calls frame:Hide() directly instead of B:Hide()). Also the single seam for the
  -- [UI] show/hide trace — fires once per visibility change regardless of call path (B:Show/
  -- B:Hide, ESC, or a raw frame:Hide()).
  frame:HookScript("OnShow", function()
    if NS.State.debug and NS.Debug then NS.Debug("UI", "window shown") end
    -- Give the pending bound-state repair another pass here. By the time the user opens the
    -- window the item cache is warm, which is exactly what the login passes may have lacked —
    -- and this is the moment the wrong lock color would be looked at. No-op once it completes.
    if NS.Database and NS.Database.RepairBoundStates then NS.Database:RepairBoundStates() end
  end)
  frame:HookScript("OnHide", function()
    -- The popup is a process-wide singleton parented to UIParent; this frame's own Hide cannot
    -- reach it. This is also the Escape / UISpecialFrames path.
    NS.CloseMenu()
    if NS.State.debug and NS.Debug then NS.Debug("UI", "window hidden") end
  end)

  B:ApplySkin(frame)
  RestoreWindow()
  B:ApplyChrome(frame, NS.db and NS.db.global.settings.windowScale)
  frame:Hide()

  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryWindow")
  end
  return frame
end

-- ── Master controls: the addon-wide chrome (options-ui-§15) ────────────────────
--
-- `settings.scale`, `settings.alpha`, `settings.locked` and `settings.visibility` govern EVERY
-- frame this addon draws — the History window and the export modal — which is what makes them the
-- master rows rather than a second copy of `settings.windowScale`. That one is the History window's
-- OWN scale and MULTIPLIES on top of the master, exactly as a per-instance row is meant to: a
-- player who has sized this window relative to the rest of their UI keeps that relationship when
-- they scale the addon as a whole.
--
-- They live here, on the module that owns this addon's window chrome, and modules/Export.lua
-- borrows them the same way it already borrows MakeCloseButton and the browser anchor.

--- The addon-wide scale, alpha and lock, with the shipped values as the floor.
function B:MasterChrome()
  local s = (NS.db and NS.db.global and NS.db.global.settings) or {}
  return s.scale or 1.0, s.alpha or 1.0, s.locked and true or false
end

--- True while the frames are locked and a drag must not start.
function B:IsLocked()
  return select(3, B:MasterChrome())
end

--- Apply the addon-wide scale and opacity to one of this addon's top-level frames.
--- `windowScale` is that frame's OWN per-window scale, or nil for a frame that has none.
function B:ApplyChrome(f, windowScale)
  if not f then return end
  local scale, alpha = B:MasterChrome()
  f:SetScale(scale * (windowScale or 1.0))
  f:SetAlpha(alpha)
end

--- Whether the History window is allowed on screen right now (the General visibility dropdown).
---
--- The window is opened on demand — a slash verb, the minimap button, a keybind — so honouring the
--- setting means REFUSING to show and hiding a window the setting has stopped allowing. It never
--- opens the window by itself: "Only in combat" is a permission, not an instruction to pop a
--- 1100px browser over a pull.
function B:VisibilityAllows()
  local mode = (NS.db and NS.db.global and NS.db.global.settings
                and NS.db.global.settings.visibility) or "always"
  if mode == "never"  then return false end
  if mode == "always" then return true end
  local inCombat = (InCombatLockdown and InCombatLockdown()) and true or false
  if mode == "inCombat" then return inCombat end
  return not inCombat   -- "outOfCombat"
end

--- Hide the window if the visibility setting no longer allows it. Called on every combat
--- transition and whenever the dropdown is written.
function B:ApplyVisibility()
  if frame and frame:IsShown() and not B:VisibilityAllows() then
    frame:Hide()
  end
end

function B:Show()
  if not B:VisibilityAllows() then
    print("the window is hidden by the General visibility setting.")
    return
  end
  local f = EnsureFrame()
  f:Show()
  -- Eager-build the History pane so the table attaches and matchCount is fresh — the shared footer
  -- (issue #13) then reads correctly even when the window opens straight onto the Insights tab.
  BuildPane("History")
  B:SelectTab(lastTab)
  B:UpdateTestBadge()
end

function B:Hide()
  NS.CloseMenu()   -- the slash-command close path; frame:Hide() below does not reach the popup
  if frame then frame:Hide() end
end

function B:Toggle()
  -- Routed through B:Show rather than f:Show, so the visibility refusal covers the toggle and the
  -- minimap click too. Only the frame that already exists can be hidden, so a refused open never
  -- builds one.
  if frame and frame:IsShown() then frame:Hide() else B:Show() end
end

-- The History window frame (or nil if never built). Lets sibling modules (e.g. Export) anchor
-- their own popups to the browser window rather than the screen.
function B:GetWindow() return frame end

--- The per-window scale row's onChange. Goes through ApplyChrome so the master scale is applied in
--- the same breath — a per-window scale set on its own would otherwise discard it.
function B:SetScale(v)
  B:ApplyChrome(frame, v)
end

-- React to settings changes (master chrome + window scale + visibility + minimap) while the window
-- exists. The export modal is reached from here rather than from a bus target of its own: it is
-- built lazily and may not exist, and E:Open re-applies on every open regardless.
function B:OnSettingsChanged()
  B:ApplyChrome(frame, NS.db.global.settings.windowScale)
  if NS.Export and NS.Export.ApplyChrome then NS.Export:ApplyChrome() end
  B:ApplyVisibility()
  self:SetMinimapHidden(NS.db.global.minimap and NS.db.global.minimap.hide)
end

-- ── Minimap button (LibDBIcon + LibDataBroker) ─────────────────────────────────
-- A "launcher" data object: left-click toggles the window, right-click opens Settings,
-- and the tooltip shows the live record count. Visibility lives in db.global.minimap
-- (the same table the "Hide minimap button" setting writes), which LibDBIcon owns —
-- so registration alone honors the persisted hide state across /reload.

function B:SetupMinimap()
  if minimapObject then return end  -- already registered this session
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  DBIcon = DBIcon or (LibStub and LibStub("LibDBIcon-1.0", true))
  if not (LDB and DBIcon) then return end

  minimapObject = LDB:NewDataObject(LDB_NAME, {
    type  = "launcher",
    label = "Loot History",
    icon  = "Interface\\Icons\\INV_Misc_Bag_08",
    OnClick = function(_, button)
      if button == "RightButton" then
        if NS.Panel and NS.Panel.Open then NS.Panel:Open() end
      else
        B:Toggle()
      end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine("Ka0s Loot History", 1, 0.82, 0)
      local n = (NS.Database and NS.Database.Count) and NS.Database:Count() or 0
      tt:AddLine(n == 1 and "1 record" or (n .. " records"), 0.7, 0.7, 0.7)
      tt:AddLine(" ")
      tt:AddLine("Left-click: open the history window", 0.5, 0.5, 0.5)
      tt:AddLine("Right-click: open settings", 0.5, 0.5, 0.5)
    end,
  })

  local mm = NS.db.global.minimap
  if not mm then mm = { hide = false }; NS.db.global.minimap = mm end
  DBIcon:Register(LDB_NAME, minimapObject, mm)
end

-- Show/hide the minimap button live (driven by the "Hide minimap button" setting).
function B:SetMinimapHidden(hide)
  if DBIcon and DBIcon:IsRegistered(LDB_NAME) then
    if hide then DBIcon:Hide(LDB_NAME) else DBIcon:Show(LDB_NAME) end
  end
end

-- Keep the browser current when the underlying history changes (new loot, a row delete, retention
-- prune, or a blacklist/whitelist edit — issue #14). The shared filter bar + footer (issue #13)
-- refresh on either tab; the table repaints only when it's the visible tab. Insights live-refreshes
-- itself through its own bus subscription.
function B:OnHistoryChanged()
  if not (frame and frame:IsShown()) then return end
  if lastTab == "History" and NS.BrowserTable and NS.BrowserTable.Refresh then
    NS.BrowserTable:Refresh()
  end
  self:RefreshFilterOptions()
  self:UpdateFooter()
  self:UpdateDbSize()
end

-- Subscribe once the addon (bus) is available.
function B:Enable()
  if NS.bus and not self._enabled then
    self._enabled = true
    -- Private bus target (never the shared bus-as-self) so these don't clobber the Collector's
    -- SettingsChanged or Analytics' RecordAdded/HistoryChanged handlers. See NS.NewBusTarget.
    -- No `or NS.bus` tail: NS.NewBusTarget returns nil ONLY when AceEvent-3.0 is unresolvable, and
    -- core/LootHistory.lua:4's NewAddon(NS, addonName, "AceEvent-3.0", …) errors first in exactly
    -- that case, so NS.bus never exists and the `if NS.bus` guard above never opens.
    B.__ev = NS.NewBusTarget()
    B.__ev:RegisterMessage("Ka0s_LootHistory_SettingsChanged", function() B:OnSettingsChanged() end)
    B.__ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", function() B:OnHistoryChanged() end)
    -- COALESCED, and only this one (issue #27). `OnHistoryChanged` is nine full-history passes —
    -- a BrowserTable rebuild, seven dropdown builders each scanning the whole dataset, and a
    -- StorageStats byte estimate — and RecordAdded fires once per LOOTED ITEM, mid-pull, on a
    -- frame that can be open through a boss kill. A multi-drop kill with a long history paid that
    -- price once per drop.
    --
    -- `HistoryChanged` above stays immediate on purpose: it is a delete, a prune or a
    -- blacklist edit — a deliberate user action that arrives one at a time and should repaint at
    -- once. Only the automatic, bursty message needs collapsing.
    B.__ev:RegisterMessage("Ka0s_LootHistory_RecordAdded",
      NS.Coalesce(function() B:OnHistoryChanged() end, NS.Constants.RECORD_ADDED_COALESCE))
    -- The two transitions the General visibility dropdown is about. Only ever HIDES: a window the
    -- setting stops allowing goes away, and one it starts allowing is still the player's to open.
    B.__ev:RegisterEvent("PLAYER_REGEN_DISABLED", function() B:ApplyVisibility() end)
    B.__ev:RegisterEvent("PLAYER_REGEN_ENABLED",  function() B:ApplyVisibility() end)
    B:SetupMinimap()
  end
end
