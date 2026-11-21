local _, NS = ...
NS.Browser = NS.Browser or {}
local B = NS.Browser
local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer (events-frames-taint-§8)

-- The History window's PER-TAB VIEW LAYER, split out of modules/Browser.lua on its recorded seam
-- (layout-§1, docs/ARCHITECTURE.md -> Documented deviations): what each tab honors on the shared
-- filter bar, its group mode and its Search suggestions; the saved and stock views and their pure
-- helpers; the live filter push (ApplyFilter); every tab's parked state (P11); capture, apply,
-- Save / Reset / Clear; and the Export button's routing. modules/Browser.lua owns the window shell
-- and its state -- the frame, the tab registry and the active tab -- and this file reads them only
-- through B:GetWindow, B._tabSpec and B:ActiveTab, so that state keeps one writer. The `switching`
-- flag and the parked `live` states are this layer's own. Loads directly after modules/Browser.lua
-- and before modules/BrowserFilterBar.lua (TOC), which binds B._setToFilter, B._applyQualityFloor,
-- B._applyFilter and B._currentKey from here as file-scope locals at its load.

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
  local spec = B._tabSpec(name)
  for key, ctl in pairs(self._dd or {}) do setHonored(ctl, B._filterHonored(spec, key)) end
  setHonored(self._search, B._filterHonored(spec, "search"))
  setHonored(self._exportBtn, B._filterHonored(spec, "export"))
  -- The Search box's suggestion list belongs to the tab that filled it: a switch closes it, and the
  -- next keystroke asks the new tab (B:Suggest).
  if self._autocomplete then self._autocomplete:Close() end
  self:SyncGroupControl()
  self:RefreshFilterOptions()
end

-- Per-tab grouping (P6). A spec may own its group mode: `groups` (the modes it offers, in menu
-- order), `group()` (its current mode) and `setGroup(mode)`. The one Group dropdown then offers
-- only those modes and shows that tab's value while the tab is active, and a pick goes to the tab.
-- A spec with none of that (History, Insights) drives the History table's groupBy, as always.
function B:SetGroup(mode)
  local spec = B._tabSpec(B:ActiveTab())
  if spec and spec.setGroup then return spec.setGroup(mode) end
  if NS.BrowserTable then NS.BrowserTable:SetGroupBy(mode) end
end

-- Repaint the Group dropdown for the active tab: its option set and its value. SelectValue does
-- not fire onSelect, so this never regroups anything.
function B:SyncGroupControl()
  local dd = self._dd and self._dd.group
  if not dd then return end
  local spec = B._tabSpec(B:ActiveTab())
  dd:SetOptions(B._groupOptionsFor(spec))
  local mode = (spec and spec.group) and spec.group() or (NS.BrowserTable and NS.BrowserTable.groupBy)
  dd:SelectValue(mode or "none")
end

-- Search autocomplete (P9). The Search box's suggestion list (NS.MakeAutocomplete, built in
-- modules/BrowserFilterBar.lua) is one widget for every tab; what it offers and what a pick does are
-- the ACTIVE tab's, through its spec's optional `suggest(text)` (an array of { text, value, color })
-- and `pick(item)`. A tab with no `suggest` offers nothing, and a tab whose Search is grayed offers
-- nothing either -- its box takes no input, so a list could only be stale.
function B:Suggest(text)
  local spec = B._tabSpec(B:ActiveTab())
  if not (spec and spec.suggest and B._filterHonored(spec, "search")) then return nil end
  return spec.suggest(text)
end

function B:PickSuggestion(item)
  local spec = B._tabSpec(B:ActiveTab())
  if spec and spec.pick and item then spec.pick(item) end
end

-- The saved "view" = group-by + sort + column filters (NOT the player scope, which is a
-- session-only default of "current player"). This is the stock/Clear baseline; the user's saved
-- views live in the profile, one per tab: NS.db.profile.savedViews[tab] (P11, schema v14). `date`
-- stores the range option (not an absolute `from`) so it recomputes correctly on each load. `dir` is
-- deliberately ABSENT: a view that never stored one takes the Direction default (defaultDirSet,
-- settings.showTransfers) at apply time, and the minimum-quality floor (applyQualityFloor) rides on
-- `quality` staying unselected.
local STOCK_VIEW = {
  groupBy = "none", sortKey = "date", sortAsc = false, groupAsc = true,
  quality = "all", source = "all", itemType = "all", itemSubType = "all", zone = "all",
  date = "all", bound = "all", search = "",
}

-- A tab's stock view: STOCK_VIEW itself, or a copy with the tab spec's `stock` fields laid over it
-- (Holdings sorts by name, not date).
local function stockView(tab)
  local spec = B._tabSpec(tab or B:ActiveTab())
  local extra = spec and spec.stock
  if not extra then return STOCK_VIEW end
  local v = {}
  for k, x in pairs(STOCK_VIEW) do v[k] = x end
  for k, x in pairs(extra) do v[k] = x end
  return v
end

-- A tab's saved view (the active tab's by default), or its stock view when it has none.
local function savedViewOrStock(tab)
  tab = tab or B:ActiveTab()
  local all = NS.db and NS.db.profile and NS.db.profile.savedViews
  local v = type(all) == "table" and all[tab]
  if type(v) == "table" then return v end
  return stockView(tab)
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
B._stockViewFor = stockView
B._savedViewOrStock = savedViewOrStock
B._setToFilter  = setToFilter
B._asSet        = asSet
B._defaultDirSet = defaultDirSet
B._applyQualityFloor = applyQualityFloor

-- Push the current filter to the table and refresh the footer count. B.activeFilter is the ACTIVE
-- tab's filter (P11: each tab keeps its own): it always drives the table (keeping matchCount + the
-- footer current on every tab), and it live-refreshes any other built tab while it is on screen.
-- While SelectTab is putting a tab's state on the bar (`switching`) the tab is not repainted here:
-- SelectTab refreshes it once, after.
local switching = false
local function ApplyFilter()
  if NS.BrowserTable then NS.BrowserTable:SetFilter(B.activeFilter) end
  B:UpdateFooter()
  local tab, win = B:ActiveTab(), B:GetWindow()
  local s = B._tabSpec(tab)
  if switching or tab == "History" then return end
  if s and s.refresh and win and win.panes[tab]._built then s.refresh() end
end
B._applyFilter = ApplyFilter   -- the filter bar's controls (modules/BrowserFilterBar.lua) push through it

-- ── Per-tab views (P11, owner decision 2026-10-07) ─────────────────────────────────────────────
-- Each tab keeps its OWN live filter state on the one shared bar: group, sort, date, search, every
-- multi-select filter, the Character scope and its own fields (spec hooks). `live[tab]` parks a
-- tab's state while another tab is on the bar: { view = CaptureView(), char = selection set }. A tab
-- not yet shown this session opens on its saved view (or its stock view) scoped to the current
-- player, or on the stock view over every character in test mode. Session only: a profile adopt or a
-- dataset swap (test mode in or out) forgets every parked state.
local function currentKey()
  return NS.Util and NS.Util.PlayerKey and NS.Util.PlayerKey() or nil
end
B._currentKey = currentKey   -- the Character dropdown's "Current" preset (modules/BrowserFilterBar.lua)

local live = {}

local function initialFor(tab)
  if NS.BrowserTable and NS.BrowserTable.testMode then return stockView(tab), "all" end
  return savedViewOrStock(tab), "current"
end

function B._forgetLive(tab)
  if tab then live[tab] = nil else live = {} end
end

-- Park `tab`'s state as the bar holds it now (the tab is still the active one).
function B._stashLive(tab)
  if not (B:GetWindow() and B._tabSpec(tab)) then return end
  live[tab] = { view = B:CaptureView(), char = setToFilter(B.activeFilter and B.activeFilter.char) or {} }
end

-- Put `tab`'s parked state (or its opening state) on the bar. `tab` is already the active tab.
function B._restoreLive(tab)
  local e = live[tab]
  switching = true
  local ok, err
  if e then ok, err = pcall(B.ApplyView, B, e.view, e.char)
  else ok, err = pcall(B.ApplyView, B, initialFor(tab)) end
  switching = false
  if not ok then error(err, 0) end
end

-- The filter a parked (or never shown) tab would apply, built without touching the bar.
local resolveInto   -- defined with ApplyView below
local function parkedFilter(tab)
  local e, view, char = live[tab]
  if e then
    view, char = e.view, e.char
  else
    local scope
    view, scope = initialFor(tab)
    local ck = currentKey()
    char = (scope == "current" and ck) and { [ck] = true } or nil
  end
  local f = {}
  resolveInto(f, view)
  f.char = setToFilter(char)
  return f
end

-- A tab's filter as a plain copy (issue #13; per tab since P11): the active tab's live filter, or,
-- for `tab` naming another tab, that tab's own parked state. Shares the exact field shape
-- Database:QueryList consumes (quality/source/itemType/itemSubType/zone/bound/char/from/text).
function B:CurrentFilter(tab)
  if tab and tab ~= B:ActiveTab() then return parkedFilter(tab) end
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

-- One field of a tab's saved view (the active tab's by default), written without a Save (the
-- Timeline's last pick, spec §8.1). With no saved view yet, the tab's view is materialized as a COPY
-- of its stock one, which applies exactly as stock does, so remembering a pick never changes anything
-- else a later Reset or Save would see.
function B:SetViewField(k, v, tab)
  local p = NS.db and NS.db.profile
  if not p then return end
  tab = tab or B:ActiveTab()
  if type(p.savedViews) ~= "table" then p.savedViews = {} end
  if type(p.savedViews[tab]) ~= "table" then
    local copy = {}
    for kk, vv in pairs(stockView(tab)) do copy[kk] = vv end
    p.savedViews[tab] = copy
  end
  p.savedViews[tab][k] = v
end

function B:ViewField(k, tab) return savedViewOrStock(tab)[k] end

-- "Show in Timeline" from a History or Holdings row (spec §8.2).
-- The Timeline keeps its own Search text (P11), so the thing's name is put there, as a pick would.
function B:ShowTimeline(key)
  if NS.Timeline and NS.Timeline.SetThing then NS.Timeline:SetThing(key, true) end
  self:Show()
  self:SelectTab("Timeline")
  local d = key and NS.Holdings and NS.Holdings.Describe and NS.Holdings:Describe(key)
  if B:ActiveTab() == "Timeline" and d and d.name then self:SetSearchText(d.name) end
end

-- The table's dataset changed (entering/leaving test mode): rebuild the dropdowns from the new
-- dataset. In test mode show everything (stock view, all players, since test chars differ);
-- leaving it, return to the saved view + current player. Every tab's parked state is forgotten, so
-- each opens the same way when next shown (B._restoreLive).
function B:OnDatasetChanged()
  self:RefreshFilterOptions()
  live = {}
  self:ApplyView(initialFor(B:ActiveTab()))
  self:UpdateFooter()
  self:UpdateDbSize()
  self:UpdateTestStrip()
  -- The Insights tab reads the same dataset; refresh it so a live Insights view reflects the swap.
  if NS.Analytics and NS.Analytics.Refresh then NS.Analytics:Refresh() end
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

-- Capture the active tab's group/sort/column-filters as a view table (excludes the player scope).
-- Character scope is NOT part of the view (it's the session-only Current/All default). A tab spec's
-- `captureView(v)` then writes the tab's own fields over it (Holdings' group and sort, the
-- Timeline's remembered pick).
function B:CaptureView()
  local dd = self._dd
  local v = captureTableState(NS.BrowserTable)
  captureFilters(dd, v)
  v.date   = (dd and dd.date._value) or "all"
  v.search = (self._search and self._search:GetText()) or ""
  local spec = B._tabSpec(B:ActiveTab())
  if spec and spec.captureView then spec.captureView(v) end
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

-- Resolve the view's stored fields into the query filter `f`. Tolerates the legacy scalar form via
-- asSet; an unselected column applies no filter at all (nil, not an empty set).
function resolveInto(f, view)
  for i = 1, #VIEW_FILTERS do
    local vk = VIEW_FILTERS[i][1]
    f[vk] = setToFilter(viewSet(view, vk))
  end
  applyQualityFloor(f)
  if view.date and view.date ~= "all" then f.from = NS.Util.RangeFrom(view.date) end
  if view.search and view.search ~= "" then f.text = view.search end
end

-- Apply a view to the ACTIVE tab. A tab spec with `applyView` owns its group and sort (Holdings);
-- every other tab's go onto the History table, as they always did.
function B:ApplyView(view, scope)
  view = view or stockView(B:ActiveTab())
  self.activeFilter = {}
  local spec = B._tabSpec(B:ActiveTab())
  if spec and spec.applyView then spec.applyView(view) else applyTableState(view) end
  local dd = self._dd
  if dd then applyDropdowns(dd, view); self:SyncGroupControl() end   -- a tab with its own group keeps it
  if self._search then self._search:SetText(view.search or "") end
  resolveInto(self.activeFilter, view)
  -- Character scope resets to `scope`: "all", an explicit selection set (a parked tab's, P11), or
  -- by default "current". SetCharSet also calls ApplyFilter, so it is the single refresh that
  -- paints all the filter fields set just above.
  if scope == "all" then
    self:SetCharSet(nil)
  elseif type(scope) == "table" then
    self:SetCharSet(scope)
  else
    local ck = currentKey()
    self:SetCharSet(ck and { [ck] = true } or nil)
  end
end

-- The filter bar's Save / Reset / Clear (P11): each acts on the ACTIVE tab alone.
--   Save  stores the tab's current state as its saved view (profile.savedViews[tab]).
--   Reset deletes the tab's saved view and applies its stock view.
--   Clear returns the tab's filters/group/sort to its saved view, or its stock view when it has
--         none; the saved slot is kept. The Timeline's remembered thing and Total only are not
--         filters and are untouched by Clear (it never applies them from a view).
-- Test mode is session-only and never writes a saved view (Save refuses), and its Reset and Clear
-- both land on the stock view over every character without writing.
function B:SaveView()
  if not (NS.db and NS.db.profile) then return end
  if NS.BrowserTable and NS.BrowserTable.testMode then
    print("test mode is a preview: the view was not saved.")
    return
  end
  local p = NS.db.profile
  if type(p.savedViews) ~= "table" then p.savedViews = {} end
  p.savedViews[B:ActiveTab()] = self:CaptureView()
  NS.Format("%s view saved as default.", B:ActiveTab())
end

-- `silent` suppresses the chat line when called programmatically; the filter-bar Reset button
-- calls it with no argument and keeps the message.
function B:ResetView(silent)
  local p = NS.db and NS.db.profile
  local testMode = NS.BrowserTable and NS.BrowserTable.testMode
  if p and not testMode and type(p.savedViews) == "table" then
    p.savedViews[B:ActiveTab()] = nil
    if next(p.savedViews) == nil then p.savedViews = nil end
  end
  self:ApplyView(stockView(B:ActiveTab()), testMode and "all" or "current")
  if not silent then
    NS.Format("%s view reset to stock defaults.", B:ActiveTab())
  end
end

-- Clear returns the active tab's filters/group/sort to its saved view (its stock view when it has
-- none; the saved slot is kept), and the player scope to "current player" (every character in
-- test mode). See SaveView above.
function B:ClearFilters()
  self:ApplyView(initialFor(B:ActiveTab()))
end

-- Route the Export button to the active tab's modal (issue #15), titled after the tab ("Export
-- Insights"). A spec carrying `export` owns its modal (Insights: the analytics summary off the SAME
-- shared filter); every other tab gets the default below, the History loot rows.
function B:OpenExport()
  local title = "Export " .. tostring(B:ActiveTab())
  local s = B._tabSpec(B:ActiveTab())
  if s and s.export then return s.export(title) end
  NS.Export:Open({ title = title,
    providers = { allData = function() return NS.Database:Export({}) end,
      currentView = function()
        return (NS.BrowserTable and NS.BrowserTable.OrderedFilteredRecords
          and NS.BrowserTable:OrderedFilteredRecords()) or {}
      end },
    csv = function(records) return NS.Export:CSV(records) end })
end
