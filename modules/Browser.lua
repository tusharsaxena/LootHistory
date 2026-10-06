local _, NS = ...
NS.Browser = NS.Browser or {}
local B = NS.Browser
local frame
local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer (events-frames-taint-§8)

-- The window CHROME this addon owns: the tab strip's two label colors and every height the layout
-- is measured from. The window EDGE is NOT here — the dark flat background, the 1px black outer
-- border, the 1px gray inner highlight, the gold title tint and the gray divider are the normative
-- Ka0s edge, and they live in Core.SKIN (standalone-windows). B:ApplySkin below delegates to
-- Core.ApplySkin rather than restating them, so the History browser, both export copy windows and
-- the debug console cannot drift apart. The seam stays because those four reach the edge through it.
-- TODO (post-1.0.0): make the skin user-configurable (border color/size, background color/alpha,
-- font) via settings. That now belongs at the LibKa0s seam, not here. Tracked as a GitHub issue.
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
-- The filter bar's controls are MEASURED, not fixed: modules/BrowserFilterBar.lua sizes every
-- control from the widest label it can show, so no label wraps, and B:ToolbarSpan answers the span
-- those widths need (row 2's eight dropdowns, or row 1's Group + Direction + a minimum Search if
-- that is ever wider; the floor widths until the bar is built). The window floor adds an 8px gap,
-- Export's EXPORT_MIN and the 12px pane margins, so at the toolbar floor row 2 fits exactly at its
-- base widths. Wider than that, B:LayoutFilterBar scales every row-2 control by one ratio so the
-- bar always ends 6px in from the right border, as it starts on the left (P6 Task 3).
local EXPORT_MIN  = 120                                                    -- Export never narrower than this
B._EXPORT_MIN = EXPORT_MIN   -- Export's base width in the filter bar's layout
local BAR_INSET   = 6        -- the filter bar host's left and right inset (EnsureFrame)

-- Minimum (and default-open) window width: the wider of the column-derived table floor
-- (BrowserTable:MinFrameWidth) and the toolbar-fit floor (the dropdown span + an 8px gap + a
-- minimum Export + 12px pane margins). Shared by EnsureFrame and the resize grip.
function B:MinWidth()
  local colW = (NS.BrowserTable and NS.BrowserTable.MinFrameWidth and NS.BrowserTable:MinFrameWidth())
    or 822
  return math.max(colW, self:ToolbarSpan() + 8 + EXPORT_MIN + 2 * BAR_INSET)
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
-- NOTE: settings.window and savedView (see savedViewOrStock below) are named non-setting state
-- (architecture-§5): no control chooses them and no row addresses them, so this module owns them and
-- writes them directly rather than through Schema:Set. Every writer and the act that reaches it are
-- named in docs/ARCHITECTURE.md → Settings schema; a new writer goes on that list too.

local function SaveWindow()
  if not frame then return end
  local point, _, _, x, y = frame:GetPoint(1)
  NS.db.profile.settings.window = {
    point = point, x = x, y = y,
    w = frame:GetWidth(), h = frame:GetHeight(),
  }
end

local function RestoreWindow()
  local w = NS.db and NS.db.profile.settings.window
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
  -- The client's OnSizeChanged re-lays the filter bar out too; this covers a size that did not
  -- change (and is a no-op then).
  B:LayoutFilterBar(frame:GetWidth() - 2 * BAR_INSET)
end

-- ── Tabs ──────────────────────────────────────────────────────────────────────
-- A registry, not a hard-coded pair (timeline-ledger spec §8.0): each tab is a spec its owning
-- module registers -- { name, order, build(pane), refresh(), export(title), filters }. The filter
-- bar and footer are shared window chrome (EnsureFrame, issue #13); a pane holds only its view.
local tabSpecs, tabOrder = {}, {}
local lastTab = "History"   -- remembered within a session
local FILTERBAR_H, FILTER_GAP, FOOTER_H = 46, 8, 18   -- shared chrome heights; panes sit between

function B:Tabs() local out = {}; for i, n in ipairs(tabOrder) do out[i] = n end; return out end
function B:ActiveTab() return lastTab end

-- Lazily let the owning module build its pane content the first time it's shown.
local function BuildPane(name)
  local pane = frame.panes[name]
  if not pane._built then pane._built = true; tabSpecs[name].build(pane) end
end

-- One content pane, filling between the shared filter bar and the shared footer.
local function CreatePane(name)
  local top = SKIN.titleBarH + SKIN.tabStripH + SKIN.contentGap + FILTERBAR_H + FILTER_GAP
  local pane = CreateFrame("Frame", nil, frame)
  pane:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -top)
  pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, FOOTER_H)
  pane:Hide(); frame.panes[name] = pane
end

function B:SelectTab(name)
  if not (frame and tabSpecs[name]) then return end
  lastTab = name
  B:ApplyTabFilters(name)
  for _, t in ipairs(tabOrder) do
    local active = (t == name)
    frame.panes[t]:SetShown(active)
    frame.tabs[t].label:SetTextColor(unpack(active and SKIN.tabActive or SKIN.tabIdle))
    frame.tabs[t].underline:SetShown(active)
  end
  BuildPane(name)
  -- Refresh the shown view against the shared filter, then the shared footer/DB size (issue #13).
  if tabSpecs[name].refresh then tabSpecs[name].refresh() end
  B:UpdateFooter()
  B:UpdateDbSize()
  if NS.State.debug and NS.Debug then NS.Debug("UI", "tab -> %s", tostring(name)) end
end

-- Per-tab filters (spec §8.0). The bar is one window-wide singleton; a tab that does not honor a
-- control GRAYS it rather than hiding it, so the bar never reflows when the player switches tabs and
-- the filter it still holds is visible. A spec with no `filters` set honors every control (History,
-- Insights). Keys are B._dd's keys plus "search" and "export".
local GRAY_ALPHA = 0.4

function B._filterHonored(spec, key)
  if not (spec and spec.filters) then return true end
  return spec.filters[key] == true
end

-- SetEnabled where the widget has it (Buttons: the dropdowns, Export); Enable/Disable otherwise
-- (an EditBox), so a grayed control also stops taking input rather than only looking dim.
local function setHonored(ctl, on)
  if not ctl then return end
  if ctl.SetEnabled then ctl:SetEnabled(on)
  elseif on and ctl.Enable then ctl:Enable()
  elseif not on and ctl.Disable then ctl:Disable() end
  if ctl.SetAlpha then ctl:SetAlpha(on and 1 or GRAY_ALPHA) end
end

function B:ApplyTabFilters(name)
  local spec = tabSpecs[name]
  for key, ctl in pairs(self._dd or {}) do setHonored(ctl, B._filterHonored(spec, key)) end
  setHonored(self._search, B._filterHonored(spec, "search"))
  setHonored(self._exportBtn, B._filterHonored(spec, "export"))
  self:SyncGroupControl()
  self:RefreshFilterOptions()
end

-- Per-tab grouping (P6). A spec may own its group mode: `groups` (the modes it offers, in menu
-- order), `group()` (its current mode) and `setGroup(mode)`. The one Group dropdown then offers
-- only those modes and shows that tab's value while the tab is active, and a pick goes to the tab.
-- A spec with none of that (History, Insights) drives the History table's groupBy, as always.
function B:SetGroup(mode)
  local spec = tabSpecs[lastTab]
  if spec and spec.setGroup then return spec.setGroup(mode) end
  if NS.BrowserTable then NS.BrowserTable:SetGroupBy(mode) end
end

-- Repaint the Group dropdown for the active tab: its option set and its value. SelectValue does
-- not fire onSelect, so this never regroups anything.
function B:SyncGroupControl()
  local dd = self._dd and self._dd.group
  if not dd then return end
  local spec = tabSpecs[lastTab]
  dd:SetOptions(B._groupOptionsFor(spec))
  local mode = (spec and spec.group) and spec.group() or (NS.BrowserTable and NS.BrowserTable.groupBy)
  dd:SelectValue(mode or "none")
end

-- Strip on first call, missing buttons, then every button placed by index (late tabs re-flow it).
local function LayoutTabButtons()
  local strip = frame.tabStrip
  if not strip then
    strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", frame.divider, "BOTTOMLEFT", 6, -2)
    strip:SetPoint("TOPRIGHT", frame.divider, "BOTTOMRIGHT", -6, -2)
    strip:SetHeight(SKIN.tabStripH)
    frame.tabStrip, frame.tabs = strip, {}
  end
  for i, name in ipairs(tabOrder) do
    local tab = frame.tabs[name]
    if not tab then
      tab = CreateFrame("Button", nil, strip); tab:SetSize(90, SKIN.tabStripH)
      tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      tab.label:SetPoint("CENTER"); tab.label:SetText(name)
      tab.underline = tab:CreateTexture(nil, "ARTWORK")
      tab.underline:SetColorTexture(unpack(SKIN.tabActive)); tab.underline:SetHeight(2)
      tab.underline:SetPoint("BOTTOMLEFT", 8, 0); tab.underline:SetPoint("BOTTOMRIGHT", -8, 0)
      tab:SetScript("OnClick", function() B:SelectTab(name) end)
      frame.tabs[name] = tab
    end
    tab:ClearAllPoints(); tab:SetPoint("LEFT", (i - 1) * 94, 0)
  end
end

-- Meant for file load, before the window is built; a later call creates the pane + button on the spot.
function B:RegisterTab(spec)
  if not tabSpecs[spec.name] then tabOrder[#tabOrder + 1] = spec.name end
  tabSpecs[spec.name] = spec
  table.sort(tabOrder, function(a, b) return tabSpecs[a].order < tabSpecs[b].order end)
  if frame then if not frame.panes[spec.name] then CreatePane(spec.name) end; LayoutTabButtons() end
end

-- Test-only: drop a tab, its pane and its button; an active one falls back to History.
function B:_UnregisterTabForTest(name)
  for i, n in ipairs(tabOrder) do if n == name then table.remove(tabOrder, i); break end end
  tabSpecs[name] = nil
  if lastTab == name then lastTab = "History" end
  if not frame then return end
  for _, set in ipairs({ frame.panes, frame.tabs }) do if set[name] then set[name]:Hide(); set[name] = nil end end
  LayoutTabButtons()
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
-- NS.MakeDropdown answers nil on an install with no library, and BuildFilterBar
-- (modules/BrowserFilterBar.lua) refuses to draw rather than building dead controls -- see the
-- guard at the top of it.
-- Item-quality color as an {r, g, b} triple for tinting dropdown items, or nil if unavailable.
local function qualityColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return { c.r, c.g, c.b } end
  return nil
end

-- Binding-state filter labels + fixed display order. "NONE" matches unbound records (r.bound == nil);
-- the other tokens match their bound state. Labels mirror the Bound column's tooltip legend
-- (BrowserTable BOUND_LEGEND). Data-driven like the other value filters (see boundOptions): only the
-- states actually present in the dataset are offered, kept in this logical order (not data order).
local BOUND_LABEL = {
  NONE = "Not Bound", BOE = "Bind on Equip", BOP = "Bind on Pickup",
  WARBAND = "Warbound", WARBAND_UE = "Warbound Until Equipped",
}
local BOUND_ORDER = { "NONE", "BOE", "BOP", "WARBAND", "WARBAND_UE" }
B._boundLabel, B._boundOrder = BOUND_LABEL, BOUND_ORDER   -- the filter bar measures every label

-- The saved "view" = group-by + sort + column filters (NOT the player scope, which is a
-- session-only default of "current player"). This is the stock/reset baseline; the user's
-- saved view lives in the profile, NS.db.profile.savedView. `date` stores the range option (not an absolute
-- `from`) so it recomputes correctly on each load. `dir` is deliberately ABSENT: a view that never
-- stored one takes the Direction default (defaultDirSet, settings.showTransfers) at apply time, and
-- the minimum-quality floor (applyQualityFloor) rides on `quality` staying unselected.
local STOCK_VIEW = {
  groupBy = "none", sortKey = "date", sortAsc = false, groupAsc = true,
  quality = "all", source = "all", itemType = "all", itemSubType = "all", zone = "all",
  date = "all", bound = "all", search = "",
}
local function savedViewOrStock()
  local v = NS.db and NS.db.profile and NS.db.profile.savedView
  if type(v) == "table" then return v end
  return STOCK_VIEW
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
-- Keyed by each row's HOLDER (the Character column's value, timeline-ledger Phase 7): a legacy
-- row's holder is its char, and the Warband half of a holder move lists the Warband, under the name
-- a player reads and with no class art (BrowserTable:HolderClassFile, which the column reads too).
local function historyCharItems()
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    local c = r.holder or r.char
    if c and not seen[c] then
      seen[c] = true
      local cf = NS.BrowserTable and NS.BrowserTable.HolderClassFile and NS.BrowserTable:HolderClassFile(r)
      -- The class icon is FOLDED INTO THE LABEL, not carried in a field of its own. The widget is
      -- LibKa0s-Widgets-1.0's and it has no `icon` seam -- deliberately: inline |T...|t / |A...|a
      -- markup in a label is measured by its menuWidth (a class icon plus a Name-Realm is the
      -- example in its own comment), so a label is the supported way to put art on a row. The
      -- class color still rides in `color`, matching the Character column.
      local icon = (NS.BrowserTable and NS.BrowserTable.ClassIconMarkup
        and NS.BrowserTable:ClassIconMarkup(cf)) or ""
      local cc = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
      local name = NS.LedgerFormat.HolderLabel(c)
      items[#items + 1] = {
        value = c, label = (icon ~= "" and (icon .. " " .. name) or name),
        color = cc and { cc.r, cc.g, cc.b } or nil,
      }
    end
  end
  return items
end

-- The Character list for a tab whose rows are HOLDERS rather than history rows (Timeline, Holdings):
-- every holder the ledger knows, and the warband under the name a player reads, "Warband".
local function holderCharItems()
  local items = {}
  for _, h in ipairs(NS.Holdings and NS.Holdings:Holders() or {}) do
    local e = NS.Holdings:View(h)
    local cf = e and e.meta and e.meta.classFile
    local icon = (cf and NS.BrowserTable and NS.BrowserTable.ClassIconMarkup
      and NS.BrowserTable:ClassIconMarkup(cf)) or ""
    local cc = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
    local name = NS.LedgerFormat.HolderLabel(h)
    items[#items + 1] = { value = h, label = (icon ~= "" and (icon .. " " .. name) or name),
      color = cc and { cc.r, cc.g, cc.b } or nil }
  end
  return items
end

local function charOptions(holdersMode)
  local items = holdersMode and holderCharItems() or historyCharItems()
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
  -- With a minimum-quality setting above Poor, "all" is not all: the default view floors items at
  -- it (applyQualityFloor), so the sentinel names the floor rather than promising every row.
  local t = NS.db and NS.db.profile and NS.db.profile.settings and NS.db.profile.settings.qualityThreshold
  local allLabel = (type(t) == "number" and t > 0) and ("Quality: " .. NS.Item.QualityLabel(t) .. "+") or "Quality: All"
  table.insert(items, 1, { value = "all", label = allLabel })
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

-- The Direction filter's default (spec §7): gains and losses; transfers only when the player asked
-- for them in settings. Applied to a view that never stored a `dir` (the stock view, and every view
-- saved before the ledger existed); a stored empty set means "All".
local function defaultDirSet()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return { IN = true, OUT = true, MOVE = (s and s.showTransfers) and true or nil }
end

-- The minimum-quality setting is also the default History view's floor (spec §5.3, F5): items
-- below it are captured now, but hidden until the player picks qualities explicitly. Whitelisted
-- ids are exempt, exactly as they were exempt from the capture gate.
local function applyQualityFloor(f)
  local p = NS.db and NS.db.profile
  local t = p and p.settings and p.settings.qualityThreshold
  if f.quality or type(t) ~= "number" or t <= 0 then
    f.minQuality, f.minQualityExempt = nil, nil
  else
    f.minQuality, f.minQualityExempt = t, p.whitelist
  end
end

local VIEW_DEFAULTS = { dir = defaultDirSet }

-- A view field as a selection set: the stored set, or the field's default when the view never
-- stored one.
local function viewSet(view, key)
  local v = view[key]
  if v == nil and VIEW_DEFAULTS[key] then return VIEW_DEFAULTS[key]() end
  return asSet(v)
end

-- Pure helpers published for the headless suite (tests/test_browser.lua). The UI binds through
-- these exact functions, so a test that pins their behavior pins the shipped behavior. Read-only
-- from outside the module — nothing here mutates browser state.
B._stockView    = STOCK_VIEW
B._savedViewOrStock = savedViewOrStock
B._setToFilter  = setToFilter
B._asSet        = asSet
B._withAll      = withAll
B._defaultDirSet = defaultDirSet
B._applyQualityFloor = applyQualityFloor
B._options = {
  source = sourceOptions, char = charOptions, itemType = typeOptions,
  itemSubType = subtypeOptions, zone = zoneOptions, quality = qualityOptions, bound = boundOptions,
}

-- Push the current filter to the table and refresh the footer count. The filter is a singleton
-- for the whole browser (issue #13): it always drives the table (keeping matchCount + the footer
-- current on every tab), and it live-refreshes any other built tab while it is on screen. SelectTab
-- re-runs a tab's refresh on switch, so a filter changed on History is already in Insights when
-- next shown — without an Insights relayout on every History-side keystroke.
local function ApplyFilter()
  if NS.BrowserTable then NS.BrowserTable:SetFilter(B.activeFilter) end
  B:UpdateFooter()
  local s = tabSpecs[lastTab]
  if lastTab ~= "History" and s and s.refresh and frame and frame.panes[lastTab]._built then s.refresh() end
end
B._applyFilter = ApplyFilter   -- the filter bar's controls (modules/BrowserFilterBar.lua) push through it

-- The active filter as a plain copy, for Analytics:Stats (issue #13). Shares the exact field shape
-- Database:QueryList consumes (quality/source/itemType/itemSubType/zone/bound/char/from/text), so
-- the Insights view and the History table always filter by identical criteria.
function B:CurrentFilter()
  local out = {}
  for k, v in pairs(self.activeFilter or {}) do out[k] = v end
  return out
end

-- The Date dropdown's range KEY ("today", "7d", ...), not its resolved `from`: the Timeline draws
-- intraday points for Today / 7d only, which a timestamp cannot tell it.
function B:DateRange()
  local dd = self._dd
  return (dd and dd.date and dd.date._value) or "all"
end

-- One field of the saved view, written without a Save (the Timeline's last pick, spec §8.1). With no
-- saved view yet, the view is materialized as a COPY of the stock one, which applies exactly as stock
-- does, so remembering a pick never changes anything else a later Reset or Save would see.
function B:SetViewField(k, v)
  local p = NS.db and NS.db.profile
  if not p then return end
  if type(p.savedView) ~= "table" then
    local copy = {}
    for kk, vv in pairs(STOCK_VIEW) do copy[kk] = vv end
    p.savedView = copy
  end
  p.savedView[k] = v
end

function B:ViewField(k) return savedViewOrStock()[k] end

-- "Show in Timeline" from a History or Holdings row (spec §8.2).
function B:ShowTimeline(key)
  if NS.Timeline and NS.Timeline.SetThing then NS.Timeline:SetThing(key, true) end
  self:Show()
  self:SelectTab("Timeline")
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
  local spec = tabSpecs[lastTab]
  local holders = spec ~= nil and spec.charSource == "holders"
  local charOpts = charOptions(holders)
  dd.char:SetOptions(charOpts)
  -- One Character control, two option sources: on a source switch, drop picks the new list lacks.
  if self._charHolders ~= nil and self._charHolders ~= holders then self:PruneCharSet(charOpts) end
  self._charHolders = holders
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
B._currentKey = currentKey   -- the Character dropdown's "Current" preset (modules/BrowserFilterBar.lua)

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

-- A pick the shown option list does not offer (the warband or an alt with no history rows, carried
-- from Holdings to History) would filter to nothing under a raw-key label; it goes through SetCharSet.
-- The current player stays: "Character: Current" is a preset even before they have a history row.
function B:PruneCharSet(opts)
  local cur = self.activeFilter and self.activeFilter.char
  if not cur then return end
  local listed, keep, dropped, me = {}, {}, false, currentKey()
  for _, o in ipairs(opts) do listed[o.value] = true end
  for k in pairs(cur) do
    if listed[k] or k == me then keep[k] = true else dropped = true end
  end
  if dropped then self:SetCharSet(keep) end
end

-- The seven multi-select filters (six column filters plus Direction), as { view key, dropdown key }
-- in the order the widgets are laid out. One ordered descriptor drives all three passes — capture,
-- the dropdown push and the filter resolution — so another filter is one entry here rather than
-- three edits. The activeFilter key IS the view key for all seven, which is why one list serves
-- them all. A field with a VIEW_DEFAULTS entry (Direction) takes that default when a view never
-- stored it.
local VIEW_FILTERS = {
  { "quality", "quality" }, { "itemType", "type" }, { "itemSubType", "subtype" },
  { "source", "source" }, { "zone", "zone" }, { "bound", "bound" }, { "dir", "dir" },
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
  v.timelineThing = savedViewOrStock().timelineThing
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
    dd[f[2]]:SetSelected(viewSet(view, f[1]))
  end
  dd.date:SelectValue(view.date or "all")
end

-- Resolve the view's stored fields into the query filter. Tolerates the legacy scalar form via
-- asSet; an unselected column applies no filter at all (nil, not an empty set).
local function resolveFilter(self, view)
  for i = 1, #VIEW_FILTERS do
    local vk = VIEW_FILTERS[i][1]
    self.activeFilter[vk] = setToFilter(viewSet(view, vk))
  end
  applyQualityFloor(self.activeFilter)
  if view.date and view.date ~= "all" then self.activeFilter.from = NS.Util.RangeFrom(view.date) end
  if view.search and view.search ~= "" then self.activeFilter.text = view.search end
end

function B:ApplyView(view, scope)
  view = view or STOCK_VIEW
  self.activeFilter = {}
  applyTableState(view)
  local dd = self._dd
  if dd then applyDropdowns(dd, view); self:SyncGroupControl() end   -- a tab with its own group keeps it
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

-- Save the current view as this profile's default; Reset drops it back to stock.
function B:SaveView()
  if NS.db and NS.db.profile then
    NS.db.profile.savedView = self:CaptureView()
    print("view saved as default.")
  end
end
-- Drop the saved view back to stock. `silent` suppresses the chat line when called programmatically;
-- the filter-bar Reset button calls it with no argument and keeps the message.
function B:ResetView(silent)
  if NS.db and NS.db.profile then NS.db.profile.savedView = nil end
  self:ApplyView(STOCK_VIEW, "current")
  if not silent then print("view reset to stock defaults.") end
end

-- Reset the persisted window geometry (named non-setting state, see the NOTE above SaveWindow) and recenter the
-- live frame. Reached from the Master controls "Reset position" button. "Reset all settings" does not
-- call it: the geometry lives in the profile, and the profile reset brings it back (options-ui-§12).
function B:ResetWindow()
  if NS.db and NS.db.profile and NS.db.profile.settings then
    NS.db.profile.settings.window = {}
  end
  if frame then
    frame:ClearAllPoints()
    RestoreWindow()   -- empty geometry → RestoreWindow centers the frame
  end
end

--- The History window's half of the profile adopt path (NS.OnProfileEvent, core/LootHistory.lua).
--- Everything the window draws from the profile is re-read from the NEW one: its geometry, its
--- saved view (or the stock view when the profile has none), its row height and its chrome. A
--- window that was never built has nothing to re-read; its first build reads the new profile.
--- Test mode keeps its stock view: the preview is session state, not the profile's.
function B:AdoptProfile()
  if not frame then return end
  frame:ClearAllPoints()
  RestoreWindow()
  if not (NS.BrowserTable and NS.BrowserTable.testMode) then
    self:ApplyView(savedViewOrStock(), "current")
  end
  if NS.BrowserTable and NS.BrowserTable.Bind then NS.BrowserTable:Bind() end
  B:ApplyChrome(frame, NS.db.profile.settings.windowScale)
  B:ApplyVisibility()
end

-- Clear returns the filters/group/sort to the saved default (or stock), and the player scope
-- to "current player".
function B:ClearFilters()
  self:ApplyView(savedViewOrStock(), "current")
end

-- Route the Export button to the active tab's modal (issue #15), titled after the tab ("Export
-- Insights"). A spec carrying `export` owns its modal (Insights: the analytics summary off the SAME
-- shared filter); every other tab gets the default below, the History loot rows.
function B:OpenExport()
  local title = "Export " .. tostring(lastTab)
  local s = tabSpecs[lastTab]
  if s and s.export then return s.export(title) end
  NS.Export:Open({ title = title,
    providers = { allData = function() return NS.Database:Export({}) end,
      currentView = function()
        return (NS.BrowserTable and NS.BrowserTable.OrderedFilteredRecords
          and NS.BrowserTable:OrderedFilteredRecords()) or {}
      end },
    csv = function(records) return NS.Export:CSV(records) end })
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

-- The built-in tabs. History's filter push stays ApplyFilter's unconditional half (the footer needs it).
B:RegisterTab{ name = "History", order = 10,
  build = function(pane) B:BuildTable(pane) end,
  refresh = function() if NS.BrowserTable and NS.BrowserTable.Refresh then NS.BrowserTable:Refresh(); B:RefreshFilterOptions() end end }
B:RegisterTab{ name = "Insights", order = 20,
  build = function(pane) if NS.Analytics and NS.Analytics.Attach then NS.Analytics:Attach(pane) end end,
  refresh = function() if NS.Analytics and NS.Analytics.Refresh then NS.Analytics:Refresh() end end,
  export = function(title) NS.Export:Open({ title = title,   -- the analytics summary, same filter
    providers = { allData = function() return NS.Database:Stats({}) end,
                  currentView = function() return NS.Database:Stats(B:CurrentFilter()) end },
    csv = function(stats) return NS.Export:InsightsCSV(stats) end }) end }

-- ── Frame construction ─────────────────────────────────────────────────────────

local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "LootHistoryWindow", UIParent, "BackdropTemplate")
  -- Default size == minimum size: wide enough for every column, so it can grow but never
  -- shrink into horizontal overflow. B:MinWidth() is the single source of truth — the wider of
  -- the column-derived table floor (BrowserTable:MinFrameWidth) and the toolbar-fit floor (the
  -- measured dropdown span + an 8px gap + a min Export 120 + 12px pane margins). The filter bar
  -- scales to fill whatever width the window has (B:LayoutFilterBar), so the window may shrink to
  -- whichever floor is larger. The floor is taken here from the bar's floor widths and taken AGAIN
  -- once BuildFilterBar has measured its labels (below).
  local minW = B:MinWidth()
  local minH = SKIN.minH
  B._minW, B._minH = minW, minH
  frame:SetSize(minW, SKIN.defaultH)  -- open at the (taller) default; can shrink to minH
  frame:SetFrameStrata("HIGH")
  frame:EnableMouse(true)   -- capture clicks over the whole window; no click-through to the world
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  -- Resizable, and its bounds, come from the corner grip below (NS.MakeResizable).

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
  local barTop = SKIN.titleBarH + SKIN.tabStripH + SKIN.contentGap
  frame.panes = {}
  for _, name in ipairs(tabOrder) do CreatePane(name) end   -- one content pane per registered tab
  LayoutTabButtons()   -- builds the tab strip on its first call

  -- Shared singleton filter bar host, anchored below the tab strip and above the panes.
  local filterHost = CreateFrame("Frame", nil, frame)
  filterHost:SetPoint("TOPLEFT",  frame, "TOPLEFT",   BAR_INSET, -barTop)
  filterHost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -BAR_INSET, -barTop)
  filterHost:SetHeight(FILTERBAR_H)
  frame.filterHost = filterHost

  -- Shared footer: "Showing X of Y" (bottom-left) + estimated DB size (bottom-right). Both track
  -- the shared filter, so they read the same on either tab. x=-20 keeps the size text left of the
  -- 16px resize grip (frame BOTTOMRIGHT -1, or -2 on a degraded install) so they never overlap.
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
  -- The bar has measured its labels, so the toolbar floor is final only now. The grip below and
  -- RestoreWindow both clamp to it, which widens a size saved by a build with narrower controls.
  -- The table's Qty column is measured here too (gold amounts at the row font), since the column
  -- floor is summed from the column widths.
  if NS.BrowserTable and NS.BrowserTable.MeasureColumns then NS.BrowserTable:MeasureColumns(frame) end
  minW = B:MinWidth()
  B._minW = minW
  frame:SetWidth(minW)
  B:RefreshFilterOptions()
  B:ApplyView(savedViewOrStock(), "current")
  B:UpdateDbSize()

  -- Resize grip, bottom-right: Core.MakeResizable through the seam (#33). The library draws the
  -- client's chat size grabber, the same corner every window in the collection wears.
  --   * minHeight is passed on purpose: the library's default floor is the CURRENT size, and the
  --     window opens at SKIN.defaultH, so leaving it out would raise the floor from minH to 700.
  --   * Lock frame gates the resize as well as the title-bar drag (canResize, read at every press):
  --     the grip stays drawn and does nothing while locked, and a refused press saves nothing.
  --   * The save and the table refresh run once per release (onResizeStop). Never onResize, which
  --     also runs on every OnSizeChanged -- every frame of a drag, and RestoreWindow's SetSize. The
  --     live relayout during a drag is the scroll frames' own OnSizeChanged.
  NS.MakeResizable(frame, {
    minWidth = minW,
    minHeight = minH,
    canResize = function() return not B:IsLocked() end,
    onResizeStop = function()
      SaveWindow()
      if NS.BrowserTable and NS.BrowserTable.Refresh then NS.BrowserTable:Refresh() end
    end,
  })
  -- The filter bar follows the window's width live, every frame of a drag (P6 Task 3): anchors and
  -- widths only, skipped when the width did not change. Its own hook rather than MakeResizable's
  -- opts.onResize (which the library also runs off a hooked OnSizeChanged): onResize stays unused,
  -- per the note above, and this relayout is cheap enough for every size tick.
  frame:HookScript("OnSizeChanged", function(_, w) B:LayoutFilterBar(w - 2 * BAR_INSET) end)

  -- Close any open dropdown menu whenever the window hides (covers the ESC/UISpecialFrames
  -- path, which calls frame:Hide() directly instead of B:Hide()). Also the single seam for the
  -- [UI] show/hide trace — fires once per visibility change regardless of call path (B:Show/
  -- B:Hide, ESC, or a raw frame:Hide()).
  frame:HookScript("OnShow", function()
    if NS.State.debug and NS.Debug then NS.Debug("UI", "window shown") end
    -- An open is a view open (debug-logging-§8): the first [Table] / [Insights] summary after it
    -- lands even when it matches the last one logged, which the change gate would otherwise hold.
    if NS.BrowserTable and NS.BrowserTable.ResetRenderTrace then NS.BrowserTable.ResetRenderTrace() end
    if NS.Analytics and NS.Analytics.ResetRenderTrace then NS.Analytics.ResetRenderTrace() end
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
  B:ApplyChrome(frame, NS.db and NS.db.profile.settings.windowScale)
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
  local s = (NS.db and NS.db.profile and NS.db.profile.settings) or {}
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

--- The stored General visibility mode, "always" when nothing is stored yet.
local function visibilityMode()
  return (NS.db and NS.db.profile and NS.db.profile.settings
          and NS.db.profile.settings.visibility) or "always"
end

--- Whether the History window is allowed on screen right now (the General visibility dropdown).
---
--- The window is opened on demand — a slash verb, the minimap button, a keybind — so honoring the
--- setting means REFUSING to show and hiding a window the setting has stopped allowing. It never
--- opens the window by itself: "Only in combat" is a permission, not an instruction to pop a
--- 1100px browser over a pull.
---
--- `inCombat` is the combat edge when a transition calls in (true from PLAYER_REGEN_DISABLED, false
--- from PLAYER_REGEN_ENABLED); nil everywhere else, and the player's combat flag answers.
function B:VisibilityAllows(inCombat)
  -- THE FIRST RUNG, and it is the whole of slash-commands-§7's "hidden AT THE SOURCE". A window
  -- taken down imperatively comes back: the next combat transition, the next settings change or
  -- the next `ApplyVisibility` re-shows it behind the switch's back, and the addon is then visibly
  -- running while it claims to be off. Refusing here means every route into the window -- the verb,
  -- the minimap click, the tab restore, the visibility dropdown -- answers no from one place.
  if NS.IsStoodDown and NS.IsStoodDown() then return false end
  local mode = visibilityMode()
  if mode == "never"  then return false end
  if mode == "always" then return true end
  -- A display decision, so never the combat-lockdown flag (events-frames-taint-§2):
  -- PLAYER_REGEN_DISABLED fires BEFORE lockdown engages, so at the pull the lockdown still reads
  -- false and "Only out of combat" would leave the window up for the whole fight. The edge itself
  -- is the state; off an edge, UnitAffectingCombat("player") is the display-side read.
  if inCombat == nil then
    inCombat = UnitAffectingCombat and UnitAffectingCombat("player") and true or false
  end
  if mode == "inCombat" then return inCombat end
  return not inCombat   -- "outOfCombat"
end

--- Hide the window if the visibility setting no longer allows it. Called on every combat
--- transition (which passes the edge through as `inCombat`) and whenever the dropdown is written.
---
--- The one [UI] line names the setting that took the window down, so a window that "vanished at
--- the pull" reads as the choice it was (debug-logging-§8, state edges). An edge that changes
--- nothing logs nothing.
function B:ApplyVisibility(inCombat)
  if frame and frame:IsShown() and not B:VisibilityAllows(inCombat) then
    if NS.State.debug and NS.Debug then
      NS.Debug("UI", "window hidden by visibility=%s (%s)", tostring(visibilityMode()),
        inCombat == nil and "setting changed" or ("combat=" .. tostring(inCombat)))
    end
    frame:Hide()
  end
end

function B:Show()
  -- Silently, and only here: a stood-down addon's refusal is the DISPATCHER's one line, and a
  -- second line from the show ladder underneath it would be the two-line lecture §7 forbids. The
  -- visibility refusal below still speaks, because that one is about a setting the player chose.
  -- Both refusals still leave one gated [UI] line naming the guard (debug-logging-§8): the chat
  -- rule above is about the player's chat, and the log is where "nothing opened" gets its answer.
  if NS.IsStoodDown and NS.IsStoodDown() then
    if NS.State.debug and NS.Debug then NS.Debug("UI", "open refused: stood down") end
    return
  end
  if not B:VisibilityAllows() then
    if NS.State.debug and NS.Debug then
      NS.Debug("UI", "open refused: visibility=%s", tostring(visibilityMode()))
    end
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
  -- Belt and braces, and the braces are the load-bearing half: the frame's own OnHide hook (in
  -- BuildWindow, beside the RepairBoundStates kick) already calls NS.CloseMenu, so `frame:Hide()`
  -- below reaches the popup through it. That hook is what covers Escape and every other close
  -- path; this call only covers the case where the frame was never built.
  NS.CloseMenu()
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

-- React to settings changes (master chrome + window scale + visibility) while the window
-- exists. The export modal is reached from here rather than from a bus target of its own: it is
-- built lazily and may not exist, and E:Open re-applies on every open regardless.
function B:OnSettingsChanged()
  B:ApplyChrome(frame, NS.db.profile.settings.windowScale)
  if NS.Export and NS.Export.ApplyChrome then NS.Export:ApplyChrome() end
  B:ApplyVisibility()
  -- The MINIMAP BUTTON is deliberately not re-applied here any more. It is the Master controls
  -- "Minimap button" row, and that row's set drives NS.Launcher:SetShown through this addon's
  -- single write seam (settings/Schema.lua) the instant it is flipped -- so re-asserting it on
  -- every unrelated chrome message would be a second writer of one state (launcher-§3).
  -- The minimum-quality floor follows the setting live while the window is up.
  if frame and frame:IsShown() and B.activeFilter then
    applyQualityFloor(B.activeFilter)
    if B._dd and B._dd.quality then B._dd.quality:SetOptions(qualityOptions()) end
    ApplyFilter()
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
    B.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function() B:OnSettingsChanged() end)
    B.__ev:RegisterMessage(NS.MSG.HISTORY_CHANGED, function() B:OnHistoryChanged() end)
    -- COALESCED, and only this one (issue #27). `OnHistoryChanged` is nine full-history passes —
    -- a BrowserTable rebuild, seven dropdown builders each scanning the whole dataset, and a
    -- StorageStats byte estimate — and RecordAdded fires once per LOOTED ITEM, mid-pull, on a
    -- frame that can be open through a boss kill. A multi-drop kill with a long history paid that
    -- price once per drop.
    --
    -- `HistoryChanged` above stays immediate on purpose: it is a delete, a prune or a
    -- blacklist edit — a deliberate user action that arrives one at a time and should repaint at
    -- once. Only the automatic, bursty message needs collapsing.
    B.__ev:RegisterMessage(NS.MSG.RECORD_ADDED,
      NS.Coalesce(function() B:OnHistoryChanged() end, NS.Constants.RECORD_ADDED_COALESCE))
    -- The two transitions the General visibility dropdown is about. Only ever HIDES: a window the
    -- setting stops allowing goes away, and one it starts allowing is still the player's to open.
    -- The combat start also ends test mode (preview-mode, options-ui-§15): no sample row may sit
    -- over real loot in a fight. EndTestModeForCombat never opens the window.
    -- Per event through Core's helper (events-frames-taint-§1): a refused name costs only itself.
    NS.SafeRegisterEvent(B.__ev, "PLAYER_REGEN_DISABLED", function()
      B:ApplyVisibility(true)
      if NS.BrowserTable and NS.BrowserTable.EndTestModeForCombat then
        NS.BrowserTable:EndTestModeForCombat()
      end
    end, NS.RejectedEvents)
    NS.SafeRegisterEvent(B.__ev, "PLAYER_REGEN_ENABLED", function() B:ApplyVisibility(false) end,
      NS.RejectedEvents)
  end
end

--- The stand-down half of Enable (slash-commands-§7). The private bus target carries all five
--- registrations -- three messages and the two combat transitions -- so it goes wholesale, and the
--- coalescing RecordAdded trigger goes with it: an armed repaint timer that wakes to find nothing
--- to paint is the shape §7 singles out as the most expensive one.
---
--- The window itself is taken down by NS.StandDown, and kept down by the first rung of
--- B:VisibilityAllows. This function only stops the subscriptions.
function B:Disable()
  if not self._enabled then return end
  if B.__ev then
    B.__ev:UnregisterAllMessages()
    B.__ev:UnregisterAllEvents()
    B.__ev = nil
  end
  self._enabled = nil
end
