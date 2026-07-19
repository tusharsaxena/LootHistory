local addonName, NS = ...
NS.Browser = NS.Browser or {}
local B = NS.Browser
local frame
local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer (events-frames-taint-§8)

local LDB_NAME = "Ka0s Loot History"  -- LibDataBroker object + LibDBIcon registration key
local minimapObject                   -- the LDB launcher, created once on first Enable
local DBIcon                          -- LibDBIcon-1.0, resolved lazily in SetupMinimap

-- Flat "ElvUI-like" default skin: 1px black border + subtle inner line + dark, near-opaque
-- flat background + centered gold title + small red close glyph. Built from stock Blizzard
-- textures only (no ElvUI dependency).
-- TODO (post-1.0.0): make this skin user-configurable (border color/size, background color/
-- alpha, font) via settings, driven off this table. Tracked as a GitHub issue.
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Inline check glyph for selected multi-select menu items (the default font has no ✓ glyph,
-- so, like the sort arrows, it's texture markup sized to the line height).
local CHECK_MARKUP = "|TInterface\\Buttons\\UI-CheckBox-Check:0|t "
local SKIN = {
  bg          = { 0.06, 0.06, 0.08, 0.92 },  -- flat dark panel
  border      = { 0, 0, 0, 1 },              -- crisp 1px black outer border
  innerBorder = { 0.24, 0.24, 0.27, 0.85 },  -- subtle lighter inner line (the ElvUI "double" edge)
  divider     = { 0.24, 0.24, 0.27, 0.85 },  -- title separator
  title       = { 1.0, 0.82, 0.0 },          -- Blizzard gold
  tabActive   = { 1.0, 0.82, 0.0 },          -- active tab label (gold)
  tabIdle     = { 0.7, 0.7, 0.72 },          -- idle tab label (grey)
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

-- Apply the flat skin to the window. Kept separate so a future settings panel can re-skin live.
function B:ApplySkin(f)
  f:SetBackdrop({
    bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  f:SetBackdropColor(unpack(SKIN.bg))
  f:SetBackdropBorderColor(unpack(SKIN.border))

  -- 1px inner highlight line, inset from the black border.
  if not f.innerBorder then
    local inner = CreateFrame("Frame", nil, f, "BackdropTemplate")
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    f.innerBorder = inner
  end
  f.innerBorder:SetBackdropBorderColor(unpack(SKIN.innerBorder))

  if f.title then f.title:SetTextColor(unpack(SKIN.title)) end
  if f.divider then f.divider:SetColorTexture(unpack(SKIN.divider)) end
end

-- ElvUI-style thin × glyph close button, light grey by default and the player's class colour
-- on hover. Shared by the History and Debug windows.
function B:MakeCloseButton(parent, onClick)
  local close = CreateFrame("Button", nil, parent)
  close:SetSize(24, 24)
  local x = close:CreateFontString(nil, "OVERLAY")
  x:SetFont(STANDARD_TEXT_FONT, 24, "")
  x:SetPoint("CENTER", close, "CENTER", 0, 2)  -- the × sits low in its font box; nudge up
  x:SetText("\195\151")  -- × multiplication sign (thin, ElvUI-like)
  x:SetTextColor(0.85, 0.85, 0.85)
  local _, class = UnitClass("player")
  local cc = (class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]) or { r = 1, g = 0.82, b = 0 }
  close:SetScript("OnEnter", function() x:SetTextColor(cc.r, cc.g, cc.b) end)
  close:SetScript("OnLeave", function() x:SetTextColor(0.85, 0.85, 0.85) end)
  close:SetScript("OnClick", onClick)
  return close
end

-- ── Window position/size persistence ──────────────────────────────────────────
-- settings.window = { point, x, y, w, h } relative to UIParent.
--
-- NOTE: settings.window and savedView (see savedViewOrStock below) are view/window runtime state
-- persisted directly to NS.db.global by the Browser — they are intentionally NOT Schema rows, so
-- they don't route through Schema:Set. The "every mutation goes through Schema:Set" convention
-- (CLAUDE §2) covers user settings only; window geometry (standalone-windows) and the saved table
-- view are carved out. See docs/agent-context.md.

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
  if w and w.point then
    frame:ClearAllPoints()
    frame:SetPoint(w.point, UIParent, w.point, w.x or 0, w.y or 0)
    if w.w and w.h then
      frame:SetSize(math.max(B._minW or 0, w.w), math.max(B._minH or 0, w.h))
    end
  else
    frame:SetPoint("CENTER")
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

-- One shared popup menu, reused by every dropdown; a full-screen catcher closes it on an
-- outside click. Menu sits above the HIGH-strata window; the catcher one strata below it.
local menu
local function EnsureMenu()
  if menu then return menu end
  menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  menu:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
  menu:SetBackdropBorderColor(0, 0, 0, 1)
  menu:Hide()
  menu.buttons = {}

  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:Hide()
  catcher:SetScript("OnClick", function() menu:Hide() end)
  menu.catcher = catcher
  menu:SetScript("OnHide", function() catcher:Hide() end)

  function menu:Populate(dd)
    local ROW_H = 16
    for _, b in ipairs(self.buttons) do b:Hide() end
    local opts = dd._options or {}
    local w = math.max(dd:GetWidth(), 90)
    for i, opt in ipairs(opts) do
      local b = self.buttons[i]
      if not b then
        b = CreateFrame("Button", nil, self)
        b:SetHeight(ROW_H)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 8, 0)
        fs:SetPoint("RIGHT", -8, 0)
        fs:SetJustifyH("LEFT")
        b.fs = fs
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.15)
        self.buttons[i] = b
      end
      b:SetWidth(w)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 0, -4 - (i - 1) * ROW_H)
      -- Selection state: single-select highlights the one active value; multi-select highlights
      -- every value in the set (and highlights "all" when the set is empty = no filter).
      local selected
      if dd.multi then
        selected = (opt.value == "all") and (not next(dd._selected)) or (dd._selected[opt.value] or false)
      else
        selected = (opt.value == dd._value)
      end
      -- A leading check marks a selected multi-select item; an optional inline icon (e.g. a
      -- character's class icon) prefixes the label.
      local check = (dd.multi and selected) and CHECK_MARKUP or ""
      local icon = (opt.icon and opt.icon ~= "") and (opt.icon .. " ") or ""
      b.fs:SetText(check .. icon .. opt.label)
      -- The active/selected option is gold; otherwise an option may carry its own colour
      -- (quality colour, class colour) and falls back to near-white.
      if selected then
        b.fs:SetTextColor(1, 0.82, 0)
      elseif opt.color then
        b.fs:SetTextColor(opt.color[1], opt.color[2], opt.color[3])
      else
        b.fs:SetTextColor(0.9, 0.9, 0.9)
      end
      b:SetScript("OnClick", function()
        if dd.multi then
          -- Toggle in place; keep the menu open so several can be picked in one visit.
          dd:ToggleSelected(opt.value)
          menu:Populate(dd)
          if dd.onMultiSelect then dd.onMultiSelect(dd._selected) end
        else
          dd:SetValue(opt.value, opt.label)
          menu:Hide()
          if dd.onSelect then dd.onSelect(opt.value) end
        end
      end)
      b:Show()
    end
    self:SetSize(w, #opts * ROW_H + 8)
  end
  return menu
end

-- A dropdown button: shows the current label + a ▼; clicking opens the shared menu.
local function MakeDropdown(parent, width)
  local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
  dd:SetSize(width, 20)
  dd:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  dd:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  dd:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)

  local fs = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", 6, 0)
  fs:SetPoint("RIGHT", -16, 0)
  fs:SetJustifyH("LEFT")
  dd.text = fs

  -- Down-arrow texture (the ▼ glyph is not in the default WoW font, so it renders as a box).
  local arrow = dd:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(12, 12)
  arrow:SetPoint("RIGHT", -4, 0)
  arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
  arrow:SetVertexColor(0.7, 0.7, 0.72)

  dd._selected = {}   -- multi-select value set (empty = "All"); only used when dd.multi is true
  function dd:SetOptions(opts)
    self._options = opts
    if self.multi then self:UpdateMultiLabel() end
  end
  function dd:SetValue(v, label) self._value = v; self.text:SetText(label or "") end
  -- Set the value and derive its display label from the current options (used when applying a
  -- saved view). Falls back to the raw value if the option isn't present.
  function dd:SelectValue(v)
    for _, o in ipairs(self._options or {}) do
      if o.value == v then self:SetValue(o.value, o.label); return end
    end
    self:SetValue(v, tostring(v))
  end

  -- ── Multi-select ──
  -- Mark this dropdown multi-select: clicks toggle values into _selected (empty = no filter).
  function dd:SetMulti(on) self.multi = on and true or false end
  -- Replace the selection with a copy of `set` (nil/empty = All) and refresh the button label.
  function dd:SetSelected(set)
    local s = {}
    if type(set) == "table" then for k, on in pairs(set) do if on then s[k] = true end end end
    self._selected = s
    self:UpdateMultiLabel()
  end
  -- Toggle one value; the "all" sentinel clears the whole set. Refreshes the button label.
  -- `presets` (optional, per-dropdown: { [value] = function(dd) ... end }) lets specific option
  -- values REPLACE the selection instead of toggling into it — e.g. the Character dropdown's
  -- "current" item, a one-click "only me" preset. A preset function is responsible for setting
  -- `dd._selected` itself; UpdateMultiLabel then runs as usual.
  function dd:ToggleSelected(value)
    if self.presets and self.presets[value] then
      self.presets[value](self)
    elseif value == "all" then
      self._selected = {}
    else
      self._selected[value] = (not self._selected[value]) or nil
    end
    self:UpdateMultiLabel()
  end
  -- Collapsed-button summary: the "All" label when empty, the single option's label when one is
  -- picked, else "<Prefix>: N selected" (prefix taken from the "all" sentinel, e.g. "Quality").
  function dd:UpdateMultiLabel()
    local n, firstLabel
    for _, o in ipairs(self._options or {}) do
      if o.value ~= "all" and self._selected[o.value] then
        n = (n or 0) + 1
        firstLabel = firstLabel or o.label
      end
    end
    local allLabel = (self._options and self._options[1] and self._options[1].label) or "All"
    if not n then
      self.text:SetText(allLabel)
    elseif n == 1 then
      self.text:SetText(firstLabel)
    else
      self.text:SetText((allLabel:match("^(.-):") or allLabel) .. ": " .. n .. " selected")
    end
  end

  dd:SetScript("OnClick", function(self2)
    local m = EnsureMenu()
    if m:IsShown() and m._owner == self2 then m:Hide(); return end
    m._owner = self2
    m:Populate(self2)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", self2, "BOTTOMLEFT", 0, -1)
    m.catcher:Show()
    m:Show()
  end)
  return dd
end

-- Shared factory so other modules (e.g. Export) can build a flat-skin dropdown that reuses the
-- same popup menu machinery. Returns the same `dd` control MakeDropdown produces.
function B:MakeDropdown(parent, width) return MakeDropdown(parent, width) end

-- Item-quality colour as an {r, g, b} triple for tinting dropdown items, or nil if unavailable.
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
  ACCOUNT = "Account Bound", WARBAND = "Warbound",
}
local BOUND_ORDER = { "NONE", "BOE", "BOP", "ACCOUNT", "WARBAND" }

-- The saved "view" = group-by + sort + column filters (NOT the player scope, which is a
-- session-only default of "current player"). This is the stock/reset baseline; the user's
-- saved view lives in NS.db.global.savedView. `date` stores the range option (not an absolute
-- `from`) so it recomputes correctly on each load.
local STOCK_VIEW = {
  groupBy = "none", sortKey = "date", sortAsc = false, groupAsc = true,
  quality = "all", source = "all", itemType = "all", itemSubType = "all", mapID = "all",
  date = "all", bound = "all", search = "",
}
local function savedViewOrStock()
  local v = NS.db and NS.db.global and NS.db.global.savedView
  if type(v) == "table" then return v end
  return STOCK_VIEW
end

-- A small flat-skin text button for the filter bar (Clear / Save / Reset).
local function makeBarButton(parent, text, width, onClick, tooltip)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width, 20)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  b:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  b:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
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
local function withAll(allLabel, items)
  table.sort(items, function(a, b) return a.label < b.label end)
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
      -- Carry the class token so the menu item can show the inline class icon + class colour,
      -- matching the Character column.
      local icon = (NS.BrowserTable and NS.BrowserTable.ClassIconMarkup
        and NS.BrowserTable:ClassIconMarkup(r.classFile)) or ""
      local cc = r.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.classFile]
      items[#items + 1] = {
        value = c, label = c, icon = icon,
        color = cc and { cc.r, cc.g, cc.b } or nil,
      }
    end
  end
  local opts = withAll("Character: All", items)
  -- "Current" is a one-click preset (see dd.char.presets below), not a real char value — inserted
  -- right after the "All" sentinel so the menu reads All / Current / <each character>.
  table.insert(opts, 2, { value = "current", label = "Current" })
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
local function zoneOptions()
  -- Query filters zones by mapID, so options carry mapID as value, zone name as label.
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    if r.mapID and not seen[r.mapID] then
      seen[r.mapID] = true
      items[#items + 1] = { value = r.mapID, label = r.zone or ("Map " .. r.mapID) }
    end
  end
  return withAll("Zone: All", items)
end
-- Distinct qualities present in the dataset, in quality order (Poor → … → Heirloom), each tinted
-- its quality colour. Data-driven (not a fixed 1–5 list) so Heirloom/Poor/Artifact appear whenever
-- the history contains them — matching the Insights "Quality distribution". Quality filters an
-- EXACT quality (not "that and above"). "all" (kept first) is the no-filter sentinel.
local function qualityOptions()
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    local q = r.quality
    if q ~= nil and not seen[q] then
      seen[q] = true
      items[#items + 1] = { value = q, label = NS.Compat.QualityLabel(q), color = qualityColor(q) }
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
-- Database:QueryList consumes (quality/source/itemType/itemSubType/mapID/bound/char/from/text), so
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

-- Capture the current group/sort/column-filters as a view table (excludes the player scope).
function B:CaptureView()
  local dd, BT = self._dd, NS.BrowserTable
  return {
    groupBy  = BT and BT.groupBy or "none",
    sortKey  = BT and BT.sortKey or "date",
    sortAsc  = BT and BT.sortAsc == true,
    groupAsc = not (BT and BT.groupAsc == false),
    -- Multi-select column filters are stored as selection sets (copies, so the saved view isn't
    -- aliased to the live dropdown state). An empty {} means "All". Character scope is NOT part of
    -- the view (it's the session-only Current/All default), so it isn't captured here.
    quality     = setToFilter(dd and dd.quality._selected) or {},
    source      = setToFilter(dd and dd.source._selected) or {},
    itemType    = setToFilter(dd and dd.type._selected) or {},
    itemSubType = setToFilter(dd and dd.subtype._selected) or {},
    mapID       = setToFilter(dd and dd.zone._selected) or {},
    bound       = setToFilter(dd and dd.bound._selected) or {},
    date     = (dd and dd.date._value) or "all",
    search   = (self._search and self._search:GetText()) or "",
  }
end

-- Apply a saved/stock view: set the table's group + sort, the column-filter dropdowns, and the
-- resolved filter. The player scope is NOT part of the view — it resets to `scope` (default
-- "current"), keeping "current player" the per-session default. Calls ApplyFilter (refreshes).
function B:ApplyView(view, scope)
  view = view or STOCK_VIEW
  self.activeFilter = {}
  local BT = NS.BrowserTable
  if BT then
    BT.groupBy  = view.groupBy or "none"
    BT.sortKey  = view.sortKey or "date"
    BT.sortAsc  = view.sortAsc == true
    BT.groupAsc = view.groupAsc ~= false
  end
  local dd = self._dd
  if dd then
    dd.group:SelectValue(view.groupBy or "none")
    dd.quality:SetSelected(asSet(view.quality))
    dd.type:SetSelected(asSet(view.itemType))
    dd.subtype:SetSelected(asSet(view.itemSubType))
    dd.source:SetSelected(asSet(view.source))
    dd.zone:SetSelected(asSet(view.mapID))
    dd.bound:SetSelected(asSet(view.bound))
    dd.date:SelectValue(view.date or "all")
  end
  if self._search then self._search:SetText(view.search or "") end
  self.activeFilter.quality     = setToFilter(asSet(view.quality))
  self.activeFilter.source      = setToFilter(asSet(view.source))
  self.activeFilter.itemType    = setToFilter(asSet(view.itemType))
  self.activeFilter.itemSubType = setToFilter(asSet(view.itemSubType))
  self.activeFilter.mapID       = setToFilter(asSet(view.mapID))
  self.activeFilter.bound       = setToFilter(asSet(view.bound))
  if view.date and view.date ~= "all" then self.activeFilter.from = NS.Util.RangeFrom(view.date) end
  if view.search and view.search ~= "" then self.activeFilter.text = view.search end
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
-- (the destructive "Reset All" prints its own single confirmation) — the filter-bar Reset button
-- calls it with no argument and keeps the message.
function B:ResetView(silent)
  if NS.db and NS.db.global then NS.db.global.savedView = nil end
  self:ApplyView(STOCK_VIEW, "current")
  if not silent then print("view reset to stock defaults.") end
end

-- Reset the persisted window geometry (the settings.window storage-only carve-out) and recenter the
-- live frame. Used only by the destructive "Reset All" — window position is runtime state, so the
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

  local dd = {}
  self._dd = dd

  -- ── Row 1: Group by · Search · Clear ──
  -- Group width matches the Date dropdown directly below it (120); the Save+Reset+Clear cluster is
  -- anchored above the Export button (not the bar's right edge) and resized so its span (three
  -- buttons + two 6px gaps) exactly matches Export's width (B:ExportWidth), so the cluster sits
  -- flush above it and both stay static as the window widens.
  dd.group = MakeDropdown(bar, 120)
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
  dd.date = MakeDropdown(bar, 120)
  dd.date:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, ROW2)
  dd.date:SetOptions(DATE_OPTIONS)
  dd.date:SetValue("all", "Date: All")
  dd.date.onSelect = function(v)
    if v == "all" then B.activeFilter.from = nil else B.activeFilter.from = NS.Util.RangeFrom(v) end
    ApplyFilter()
  end

  -- Bound (multi-select): binding-state filter. "NONE" matches unbound records.
  dd.bound = MakeDropdown(bar, 96)
  dd.bound:SetPoint("LEFT", dd.date, "RIGHT", 8, 0)
  dd.bound:SetMulti(true)
  dd.bound:SetOptions(boundOptions())
  dd.bound.onMultiSelect = function(set)
    B.activeFilter.bound = setToFilter(set)
    ApplyFilter()
  end

  -- Quality/Type/Source/Zone/Character are multi-select: their onMultiSelect receives the current
  -- selection set (empty = All), copied into the matching filter field. The "all" menu item clears.
  dd.quality = MakeDropdown(bar, 100)
  dd.quality:SetPoint("LEFT", dd.bound, "RIGHT", 8, 0)
  dd.quality:SetMulti(true)
  dd.quality:SetOptions(qualityOptions())
  dd.quality.onMultiSelect = function(set)
    B.activeFilter.quality = setToFilter(set)
    ApplyFilter()
  end

  dd.type = MakeDropdown(bar, 112)
  dd.type:SetPoint("LEFT", dd.quality, "RIGHT", 8, 0)
  dd.type:SetMulti(true)
  dd.type.onMultiSelect = function(set)
    B.activeFilter.itemType = setToFilter(set)
    ApplyFilter()
  end

  dd.subtype = MakeDropdown(bar, 100)
  dd.subtype:SetPoint("LEFT", dd.type, "RIGHT", 8, 0)
  dd.subtype:SetMulti(true)
  dd.subtype.onMultiSelect = function(set)
    B.activeFilter.itemSubType = setToFilter(set)
    ApplyFilter()
  end

  dd.source = MakeDropdown(bar, 100)
  dd.source:SetPoint("LEFT", dd.subtype, "RIGHT", 8, 0)
  dd.source:SetMulti(true)
  dd.source.onMultiSelect = function(set)
    B.activeFilter.source = setToFilter(set)
    ApplyFilter()
  end

  dd.zone = MakeDropdown(bar, 146)
  dd.zone:SetPoint("LEFT", dd.source, "RIGHT", 8, 0)
  dd.zone:SetMulti(true)
  dd.zone.onMultiSelect = function(set)
    B.activeFilter.mapID = setToFilter(set)
    ApplyFilter()
  end

  dd.char = MakeDropdown(bar, 146)
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
  -- Current View → CSV); on Insights it exports the analytics summary (issue #15's Insights CSV,
  -- AI report later). Both respect the shared filter. Anchored immediately right of the Character
  -- dropdown (8px gap) rather than the bar's far-right edge; the Save/Reset/Clear cluster above it
  -- is re-anchored to Export's top-right corner (see `clear` above), so the two rows stay aligned.
  exportBtn:SetPoint("LEFT", dd.char, "RIGHT", 8, 0)
end

-- Route the Export button to the right modal for the active tab (issue #15). History exports the
-- loot rows; Insights exports the analytics summary computed off the SAME shared filter.
function B:OpenExport()
  -- Title tracks the invoking tab ("Export History" / "Export Insights") and generalizes to any
  -- future tab name — the tab that opens the modal supplies its own label.
  local title = "Export " .. tostring(lastTab)
  -- The AI export (issue #12) bundles BOTH datasets for the selected Data Set — identical on every
  -- tab, since one report shows History and Insights together. Export to CSV stays tab-specific.
  local ai = {
    history = {
      allData     = function() return NS.Database:Export({}) end,
      currentView = function()
        return (NS.BrowserTable and NS.BrowserTable.OrderedFilteredRecords
          and NS.BrowserTable:OrderedFilteredRecords()) or {}
      end,
    },
    insights = {
      allData     = function() return NS.Database:Stats({}) end,
      currentView = function() return NS.Database:Stats(B:CurrentFilter()) end,
    },
  }
  if lastTab == "Insights" then
    NS.Export:Open({
      title = title, ai = ai,
      providers = {
        allData     = function() return NS.Database:Stats({}) end,
        currentView = function() return NS.Database:Stats(B:CurrentFilter()) end,
      },
      csv = function(stats) return NS.Export:InsightsCSV(stats) end,
    })
  else
    NS.Export:Open({
      title = title, ai = ai,
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
  titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
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

  -- ElvUI-style thin × close glyph (class-coloured on hover). Anchored to the title bar's
  -- vertical centre so it lines up with the CENTER-anchored title.
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
  end)
  frame:HookScript("OnHide", function()
    if menu then menu:Hide() end
    if NS.State.debug and NS.Debug then NS.Debug("UI", "window hidden") end
  end)

  B:ApplySkin(frame)
  RestoreWindow()
  frame:SetScale(NS.db and NS.db.global.settings.windowScale or 1.0)
  frame:Hide()

  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryWindow")
  end
  return frame
end

function B:Show()
  local f = EnsureFrame()
  f:Show()
  -- Eager-build the History pane so the table attaches and matchCount is fresh — the shared footer
  -- (issue #13) then reads correctly even when the window opens straight onto the Insights tab.
  BuildPane("History")
  B:SelectTab(lastTab)
  B:UpdateTestBadge()
end

function B:Hide()
  if menu then menu:Hide() end
  if frame then frame:Hide() end
end

function B:Toggle()
  local f = EnsureFrame()
  if f:IsShown() then f:Hide() else B:Show() end
end

-- The History window frame (or nil if never built). Lets sibling modules (e.g. Export) anchor
-- their own popups to the browser window rather than the screen.
function B:GetWindow() return frame end

function B:SetScale(v)
  if frame then frame:SetScale(v) end
end

-- React to settings changes (window scale + minimap visibility) while the window exists.
function B:OnSettingsChanged()
  if frame then frame:SetScale(NS.db.global.settings.windowScale or 1.0) end
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
    B.__ev = NS.NewBusTarget() or NS.bus
    B.__ev:RegisterMessage("Ka0s_LootHistory_SettingsChanged", function() B:OnSettingsChanged() end)
    B.__ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", function() B:OnHistoryChanged() end)
    B.__ev:RegisterMessage("Ka0s_LootHistory_RecordAdded", function() B:OnHistoryChanged() end)
    B:SetupMinimap()
  end
end
