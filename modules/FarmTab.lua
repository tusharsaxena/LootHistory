local _, NS = ...
-- luacheck: ignore 212/self
NS.FarmTab = NS.FarmTab or {}
local FT = NS.FarmTab
local FarmModel = NS.FarmModel  -- load-time upvalue: modules/FarmModel.lua loads above
local FarmList = NS.FarmList    -- load-time upvalue: modules/FarmList.lua loads above
local L = NS.L

-- modules/FarmTab.lua — the History window's Farm tab (#39, farm spec
-- docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §7.5, §7.6; mockups #39 "Saved sessions"),
-- and the saved-session row half both session lists share:
--
--   the tab     every character's saved sessions in Farm:ActiveStore() (the test sample in test mode,
--               the simulation's store while one runs), filtered by Search (name or zone), Character
--               and Zone; Date, Character, Zone, Active, Total, Gross/h and the best-per-zone star.
--               A header band names it, cycles the Measure (part of the tab's saved view) and says
--               what a click does. The open session is not listed: it is on the panel.
--   the rows    FT.Entry, the column builders, the click routes (summary, Details, the menu) and
--               the Rename and Delete popups, read at call time by the panel's sessions list
--               (modules/FarmPanel.lua) too.
--
-- A click opens the session's summary, a double-click its Details window and a right-click the
-- Rename / Delete menu (NS.BrowserTable:ShowMenu, the POPUP tier). Both edits go through
-- Farm:Rename / Farm:Delete, which write Store() (a simulation's row edits the simulation's store)
-- and refuse a test-mode sample row.

local BAR_H, GAP = 22, 4
local COALESCE = 0.25
local MEASURES = { "money", "vendor", "ah" }
local MEASURE_WORD = { money = "Money", vendor = "Vendor", ah = "AH" }
local STAR_FALLBACK = "Interface\\Common\\FavoritesIcon"
local SAVED_REASONS = { finish = true, rename = true, delete = true, store = true }
FT.HINT = "Click a row for its summary. Double-click for its full record. Right-click to rename or delete."

FT.sortKey, FT.sortAsc, FT.measure = "date", false, nil

local function debug(fmt, ...)
  if NS.State.debug and NS.Debug then NS.Debug("UI", fmt, ...) end
end

local function farmSettings()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return (s and s.farm) or {}
end

-- ── the saved-session rows (shared with the sessions list) ───────────────────────────────────

--- Which store the session lists read now: "test" (the sample), "sim" or "live".
function FT.StoreKind()
  if NS.State and NS.State.testFarm then return "test" end
  if NS.SimStores and NS.SimStores.farm then return "sim" end
  return "live"
end

--- The measure the Farm tab shows: its own pick, else the headline value setting.
function FT.Measure()
  return FT.measure or farmSettings().headlineValue or "ah"
end

--- One list entry for saved session `s` of character `char` in store `kind`, at `measure` (gross).
function FT.Entry(s, kind, char, measure)
  local total = FarmModel.Value(s.totals or FarmModel.Totals(s), measure, "gross")
  return { s = s, ref = { store = kind, char = char, id = s.id }, total = total,
    rate = FarmModel.PerHour(total, s.activeSec or 0), best = false }
end

--- Mark each zone's best entry (FarmModel.BestPerZone over the sessions listed, at `measure`). A
--- session id is unique only within its character, and the tab lists every character, so the model
--- reads a proxy per entry whose id is the entry's index.
function FT.MarkBest(entries, measure)
  local proxies = {}
  for i, e in ipairs(entries) do
    local s = e.s
    proxies[i] = { id = i, primaryZone = s.primaryZone, activeSec = s.activeSec, totals = s.totals,
      startedAt = s.startedAt, items = s.items, money = s.money, costs = s.costs }
  end
  local best = FarmModel.BestPerZone(proxies, measure)
  for i, e in ipairs(entries) do e.best = best[i] == true end
  return entries
end

local function lower(v) return tostring(v or ""):lower() end

--- Whether saved session `s` of `char` passes the tab's filter: Search on name or zone, Character,
--- Zone (the session's primary zone).
function FT.Matches(s, char, f)
  if f.char and not f.char[char] then return false end
  if f.zone and not f.zone[s.primaryZone or ""] then return false end
  local text = f.text and lower(f.text)
  if text and text ~= "" then
    return lower(s.name):find(text, 1, true) ~= nil or lower(s.primaryZone):find(text, 1, true) ~= nil
  end
  return true
end

--- The Farm tab's entries: every character's saved sessions in `store` that pass `f`, at `measure`.
function FT.Rows(store, kind, f, measure)
  local out = {}
  for char, mine in pairs(store or {}) do
    for _, s in ipairs(mine.sessions or {}) do
      if FT.Matches(s, char, f or {}) then out[#out + 1] = FT.Entry(s, kind, char, measure) end
    end
  end
  return FT.MarkBest(out, measure)
end

-- Whole gold, rounded ("1,466g"); under a gold the copper text.
local function goldText(copper)
  if math.abs(copper or 0) < 10000 then return FarmModel.CopperText(copper) end
  return FarmModel.Grouped(copper / 10000) .. "g"
end

local function charName(char) return (tostring(char or ""):match("^(.-)%-") or tostring(char or "")) end

local function starText(e)
  if not e.best then return "" end
  local r, g, b = NS.SkinColor("sem.gold")
  return NS.IconMarkup("star", STAR_FALLBACK, 0, r, g, b)
end

--- The list columns by key, as FarmList column specs (the two lists pick and size their own).
FT.COLUMNS = {
  date = { key = "date", label = "Date", align = "LEFT", text = function(e) return FarmModel.DayLabel(e.s.startedAt) end,
    sort = function(e) return e.s.startedAt or 0 end },
  char = { key = "char", label = "Character", align = "LEFT", text = function(e) return charName(e.ref.char) end,
    color = function(e) return NS.Compat.ClassColor(e.s.classFile) end, defaultAsc = true },
  zone = { key = "zone", label = "Zone", align = "LEFT", text = function(e) return e.s.primaryZone or "" end,
    defaultAsc = true },
  active = { key = "active", label = "Active", align = "RIGHT", text = function(e) return FarmModel.Short(e.s.activeSec) end,
    sort = function(e) return e.s.activeSec or 0 end },
  total = { key = "total", label = "Total", align = "RIGHT", text = function(e) return goldText(e.total) end,
    sort = function(e) return e.total end },
  rate = { key = "rate", label = "Gross/h", align = "RIGHT", text = function(e) return FarmModel.RateText(e.rate) end,
    sort = function(e) return e.rate or -1 end },
  star = { key = "star", label = "", align = "LEFT", text = starText, sort = function(e) return e.best and 1 or 0 end },
}

--- Copies of the columns `keys` names, each with its width (nil: the flexible one) and label.
function FT.Columns(keys, widths, labels)
  local out = {}
  for i, key in ipairs(keys) do
    local c = {}
    for k, v in pairs(FT.COLUMNS[key]) do c[k] = v end
    c.width = widths[i]
    c.label = L[(labels and labels[key]) or c.label]
    out[i] = c
  end
  return out
end

-- ── the row routes and the two popups (§7.6) ─────────────────────────────────────────────────

local function refuseTest(ref)
  if ref and ref.store == "test" then
    NS.Print(NS.Farm.TEST_REFUSAL)
    return true
  end
  return false
end

--- The Rename popup on saved session `ref` (refused, with a line, on a test-mode sample row).
function FT.AskRename(ref)
  if refuseTest(ref) then return false end
  local s = NS.FarmDetails.Resolve(ref)
  if not (s and type(StaticPopup_Show) == "function") then return false end
  StaticPopup_Show("KA0S_LOOTHISTORY_FARM_RENAME", s.name, nil, { ref = ref, name = s.name })
  return true
end

--- The Delete confirm on saved session `ref` (refused, with a line, on a test-mode sample row).
function FT.AskDelete(ref)
  if refuseTest(ref) then return false end
  local s = NS.FarmDetails.Resolve(ref)
  if not (s and type(StaticPopup_Show) == "function") then return false end
  StaticPopup_Show("KA0S_LOOTHISTORY_FARM_DELETE", s.name, FarmModel.DayLabel(s.startedAt), { ref = ref })
  return true
end

--- The right-click menu's items for an entry, as data (tests/test_farm_tab.lua reads them).
function FT.RowActions(e)
  local ref = e.ref
  return {
    { label = L["Rename\226\128\166"], enabled = true, fn = function() FT.AskRename(ref) end },
    { label = NS.BrowserTable.DangerLabel(L["Delete\226\128\166"]), icon = "clear", enabled = true,
      fn = function() FT.AskDelete(ref) end },
  }
end

--- A row click: the right button opens the menu at the row, any other the session's summary.
function FT.RowClick(e, button, row)
  if button == "RightButton" then
    NS.BrowserTable:ShowMenu(row, FT.RowActions(e))
    return "menu"
  end
  NS.FarmDetails:OpenSummary(e.ref)
  return "summary"
end

--- A row double-click: the session's full record.
function FT.RowDoubleClick(e)
  NS.FarmDetails:Open(e.ref)
end

--- A row's hover: the session's name and what a click does, beside the row's window group.
function FT.RowEnter(e, row)
  NS.Compat.ShowTextTooltip(row, e.s.name ~= "" and e.s.name or (e.s.primaryZone or ""), L[FT.HINT], "body")
end

local function editBox(dialog)
  return dialog and (rawget(dialog, "EditBox") or rawget(dialog, "editBox"))
end

if type(StaticPopupDialogs) == "table" then
  -- Rename (an edit box, 48 characters): an empty answer restores the zone's name. The session
  -- reference arrives as the popup's data, never through a module-level variable.
  StaticPopupDialogs["KA0S_LOOTHISTORY_FARM_RENAME"] = {
    text = "Rename the farm session \"%s\". Leave it empty to use its zone's name.",
    button1 = L["Rename"],
    button2 = L["Cancel"],
    hasEditBox = true,
    maxLetters = FarmModel.NAME_MAX,
    OnShow = function(self, data)
      local eb = editBox(self)
      if eb and data then eb:SetText(data.name or ""); eb:HighlightText() end
    end,
    OnAccept = function(self, data)
      local eb = editBox(self)
      if data and eb then NS.Farm:Rename(data.ref, eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(eb, data)
      if data then NS.Farm:Rename(data.ref, eb:GetText()) end
      eb:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
    preferredIndex = 3,
  }
  StaticPopupDialogs["KA0S_LOOTHISTORY_FARM_DELETE"] = {
    text = "Delete the farm session \"%s\" from %s? This cannot be undone.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data) if data then NS.Farm:Delete(data.ref) end end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
  }
end

-- ── the tab ──────────────────────────────────────────────────────────────────────────────────

local TAB_KEYS = { "date", "char", "zone", "active", "total", "rate", "star" }
local TAB_WIDTHS = { 60, 110, nil, 54, 90, 84, 24 }

local function measureLabel()
  return L["Measure"] .. ": " .. L[MEASURE_WORD[FT.Measure()] or "AH"]
end

--- The Measure button's click: Money, then Vendor, then AH, then Money again.
function FT:CycleMeasure()
  local cur = self.Measure()
  for i, m in ipairs(MEASURES) do
    if m == cur then FT.measure = MEASURES[i % #MEASURES + 1]; break end
  end
  if self.measureBtn then self.measureBtn.text:SetText(measureLabel()) end
  debug("farm tab measure -> %s", FT.measure)
  self:Refresh()
end

local function buildHeader(self, pane)
  local bar = CreateFrame("Frame", nil, pane)
  bar:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
  bar:SetHeight(BAR_H)
  self.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  NS.Skin.Font(self.title)
  self.title:SetPoint("LEFT", 4, 0)
  self.title:SetText(L["Saved sessions"])
  self.title:SetTextColor(NS.SkinColor("text.heading"))
  -- A toolbar button on the tab's header band: CHROME, its tooltip centered above it (AD-92-LH).
  self.measureBtn = NS.Browser.MakeFlatButton(bar, measureLabel(), 96, 18, function() FT:CycleMeasure() end,
    { tooltip = L["Which value the Total and Gross/h columns show."] })
  self.measureBtn:SetPoint("LEFT", self.title, "RIGHT", 10, 0)
  self.hint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  NS.Skin.Font(self.hint)
  self.hint:SetPoint("LEFT", self.measureBtn, "RIGHT", 10, 0)
  self.hint:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
  self.hint:SetJustifyH("LEFT")
  self.hint:SetWordWrap(false)
  self.hint:SetText(L[FT.HINT])
  self.hint:SetTextColor(NS.SkinColor("text.disabled"))
  self.bar = bar
end

function FT:Attach(pane)
  if self.pane then return end
  self.pane = pane
  buildHeader(self, pane)
  local host = CreateFrame("Frame", nil, pane)
  host:SetPoint("TOPLEFT", self.bar, "BOTTOMLEFT", 0, -GAP)
  host:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
  self.host = host
  self.list = FarmList.New(host, {
    columns = FT.Columns(TAB_KEYS, TAB_WIDTHS),
    sortKey = FT.sortKey, sortAsc = FT.sortAsc,
    empty = L["No saved farm sessions match the filters."],
    onClick = FT.RowClick, onDoubleClick = FT.RowDoubleClick, onEnter = FT.RowEnter,
    onSort = function(key, asc) FT.sortKey, FT.sortAsc = key, asc end,
  })
  pane:SetScript("OnSizeChanged", function() if FT.list then FT.list:Relayout(); FT.list:Bind() end end)
  self:Refresh()
end

--- Repaint the tab from the shared filter, the store the lists read and the measure.
function FT:Refresh()
  if not self.list then return end
  local measure = self.Measure()
  self.measureBtn.text:SetText(measureLabel())
  local rows = FT.Rows(NS.Farm:ActiveStore(), FT.StoreKind(), NS.Browser:CurrentFilter("Farm"), measure)
  local list = self.list
  list.sortKey, list.sortAsc = FT.sortKey, FT.sortAsc
  list:PaintHeader()
  list:SetData(rows)
end

function FT:RefreshIfShown()
  if self.pane and self.pane:IsVisible() then
    NS.Browser:RefreshFilterOptions()
    self:Refresh()
  end
end

-- ── the tab's view (P11), suggestions and lifecycle ──────────────────────────────────────────

-- The sort and the measure ride in the Farm view, so Save, Reset and Clear reach them. A stored
-- column this tab does not have (a view migrated from History's) reads as Date, newest first.
local function captureView(v)
  v.sortKey, v.sortAsc, v.farmMeasure = FT.sortKey, FT.sortAsc, FT.measure
end

local function applyView(view)
  if FT.COLUMNS[view.sortKey or ""] then
    FT.sortKey, FT.sortAsc = view.sortKey, view.sortAsc == true
  else
    FT.sortKey, FT.sortAsc = "date", false
  end
  FT.measure = MEASURE_WORD[view.farmMeasure or ""] and view.farmMeasure or nil
end
FT._captureView, FT._applyView = captureView, applyView

--- The Search box's suggestions on this tab: the session names and zones matching the typed text.
function FT.Suggest(text)
  local t = lower((text or ""):match("^%s*(.-)%s*$"))
  if t == "" then return {} end
  local seen, items = {}, {}
  for _, mine in pairs(NS.Farm:ActiveStore()) do
    for _, s in ipairs(mine.sessions or {}) do
      for _, name in ipairs({ s.name or "", s.primaryZone or "" }) do
        if name ~= "" and not seen[name] and lower(name):find(t, 1, true) then
          seen[name] = true
          items[#items + 1] = { text = name, value = name }
        end
      end
    end
  end
  return NS.Browser._rankSuggestions(items, text, NS.Browser._SUGGEST_MAX)
end

local function onChanged(_, reason)
  if SAVED_REASONS[reason] and FT._refresh then FT._refresh() end
end

--- Stand-up: the tab's own bus target; FARM_CHANGED (a saved list's reasons) and SETTINGS_CHANGED,
--- coalesced, repaint the tab while it is on screen.
function FT:Enable()
  if self.__ev or not NS.bus then return end
  self._refresh = NS.Coalesce(function() FT:RefreshIfShown() end, COALESCE)
  self.__ev = NS.NewBusTarget()
  self.__ev:RegisterMessage(NS.MSG.FARM_CHANGED, onChanged)
  self.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function() if FT._refresh then FT._refresh() end end)
end

--- Stand-down: the bus target goes wholesale.
function FT:Disable()
  if not self.__ev then return end
  self.__ev:UnregisterAllMessages()
  self.__ev = nil
  self._refresh = nil
end

--- A skin switch: what this tab colored at build time, then a refresh while it is up.
function FT:Reskin()
  if not self.pane then return end
  self.title:SetTextColor(NS.SkinColor("text.heading"))
  self.hint:SetTextColor(NS.SkinColor("text.disabled"))
  if self.pane:IsVisible() then self:Refresh() end
end

if NS.Skin then NS.Skin.OnLooksChanged(function() FT:Reskin() end) end

NS.Browser:RegisterTab{ name = "Farm", order = 50,
  -- Saved sessions are records, not loot rows: Search, Character and Zone describe them; every other
  -- control (Export and Group among them) is grayed, never hidden (spec §8.0).
  filters = { search = true, char = true, zone = true },
  charSource = "farm", zoneSource = "farm",
  stock = { sortKey = "date", sortAsc = false },
  captureView = captureView,
  applyView = applyView,
  suggest = function(text) return FT.Suggest(text) end,
  pick = function(item) NS.Browser.PickName(item) end,
  build = function(pane) FT:Attach(pane) end,
  refresh = function() FT:Refresh() end }
