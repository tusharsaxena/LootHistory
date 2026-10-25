local _, NS = ...
NS.Browser = NS.Browser or {}
local B = NS.Browser

-- The filter bar's DROPDOWN-OPTION KIT, split out of modules/Browser.lua (which had passed its
-- 1400-line re-check; review 2026-10-07 F-002, LH-R-02). The dropdown widget itself is the library's
-- (core/WidgetsSetup.lua) and the bar's construction is modules/BrowserFilterBar.lua; what lives
-- here is everything that turns the current dataset into a dropdown's option list: the quality
-- tint, the Bound labels and order, `dataset`, `withAll` and the seven builders. None of it reads
-- browser state, so it loads directly ABOVE modules/Browser.lua, which binds these as file-scope
-- locals at load; modules/BrowserFilterBar.lua binds them from NS.Browser the same way.

-- Item-quality color as an {r, g, b} triple for tinting dropdown items, or nil if unavailable: the
-- skin's q.* override where it sets one, else the client's color (NS.QualityColor, core/SkinSetup.lua).
local function qualityColor(q)
  local r, g, b = NS.QualityColor(q)
  if r then return { r, g, b } end
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
-- The class icon as inline markup, "" with no class (or before BrowserTable has loaded).
local function classIcon(cf)
  local BT = NS.BrowserTable
  if not (cf and BT and BT.ClassIconMarkup) then return "" end
  return BT:ClassIconMarkup(cf) or ""
end

-- The class color as an {r, g, b} triple, nil with no class or an unknown one.
local function classColor(cf)
  local cc = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
  if not cc then return nil end
  return { cc.r, cc.g, cc.b }
end

-- One Character option for holder `h` of class `cf` (nil for the Warband or an unclassed row).
-- The class icon is FOLDED INTO THE LABEL, not carried in a field of its own. The widget is
-- LibKa0s-Widgets-1.0's and it has no `icon` seam -- deliberately: inline |T...|t / |A...|a markup
-- in a label is measured by its menuWidth (a class icon plus a Name-Realm is the example in its own
-- comment), so a label is the supported way to put art on a row. The class color still rides in
-- `color`, matching the Character column.
local function charItem(h, cf)
  local icon, name = classIcon(cf), NS.LedgerFormat.HolderLabel(h)
  return { value = h, label = (icon ~= "" and (icon .. " " .. name) or name), color = classColor(cf) }
end

-- The class of a history row's holder, through the same seam the Character column reads.
local function rowHolderClass(r)
  local BT = NS.BrowserTable
  return BT and BT.HolderClassFile and BT:HolderClassFile(r)
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
      items[#items + 1] = charItem(c, rowHolderClass(r))
    end
  end
  return items
end

-- The Character list for a tab whose rows are HOLDERS rather than history rows (Timeline, Holdings):
-- every holder the ledger knows, and the warband under the name a player reads, "Warband".
local function holderCharItems()
  local items = {}
  local H = NS.Holdings
  for _, h in ipairs(H and H:Holders() or {}) do
    local e = H:View(h)
    items[#items + 1] = charItem(h, e and e.meta and e.meta.classFile)
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

-- The quality options carry their tint, baked when the list is built, so a skin change rebuilds the
-- built bar's list (the refresh the minimum-quality setting makes, modules/Browser.lua) and a skin's
-- q.* override reaches it. Nothing to do before the bar exists.
if NS.Skin then
  NS.Skin.OnLooksChanged(function()
    if B._dd and B._dd.quality then B._dd.quality:SetOptions(qualityOptions()) end
  end)
end

-- Published for modules/Browser.lua and modules/BrowserFilterBar.lua (bound at their load) and for
-- the headless suite (tests/test_browser.lua). The UI binds through these exact functions.
B._dataset      = dataset
B._withAll      = withAll
B._options = {
  source = sourceOptions, char = charOptions, itemType = typeOptions,
  itemSubType = subtypeOptions, zone = zoneOptions, quality = qualityOptions, bound = boundOptions,
}

-- ── The flat button (LH-02) ────────────────────────────────────────────────────────────────────
--
-- The one small text button this addon's windows wear: the filter bar's Export / Clear / Save /
-- Reset (modules/BrowserFilterBar.lua) and the export modal's Export to CSV (modules/Export.lua).
-- It was two copies of one function until the skin engine; both now build here and are painted by
-- the skin's Button primitive (NS.Skin.Button, LibKa0s-Skin-1.0), which draws the box, the label
-- and the mark from the `btn.*` tokens and follows a skin switch with no reload. On Ka0s Default
-- that is the box the two copies drew: the WHITE8X8 backdrop at edgeSize 1 with 1px insets, the
-- .1/.1/.12/.9 fill, the .24/.24/.27/.9 edge, a white label that turns gold under the pointer and
-- the mark at .85. The library pins that paint against the old makeBarButton
-- (tests/test_skin_paint_controls.lua, upstream).
--
-- `opts.icon` is a catalog name and OPTIONAL. The LABEL NEVER MOVES: it stays CENTER-anchored and
-- the mark sits at LEFT +10, so a nil from the seam leaves the button exactly as it was rather than
-- off-center (docs/browser.md). `opts.tooltip` explains the ACTION, anchored to the whole button.
--
-- The scripts are set BEFORE the primitive runs: it HookScripts its hover pair, and a SetScript
-- after it would replace the hook. Its label is `b.text`, the field the primitive reads.
function B.MakeFlatButton(parent, text, width, height, onClick, opts)
  opts = opts or {}
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width, height)
  local path = opts.icon and NS.Icon and NS.Icon(opts.icon)
  if path then
    local tex = b:CreateTexture(nil, "OVERLAY")
    tex:SetSize(14, 14)
    tex:SetPoint("LEFT", 10, 0)
    tex:SetTexture(path)
    b.icon = tex
  end
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER")
  fs:SetText(text)
  b.text = fs
  local tooltip = opts.tooltip
  if tooltip then
    b:SetScript("OnEnter", function(self2)
      GameTooltip:SetOwner(self2, "ANCHOR_BOTTOM")
      local r, g, bl = NS.SkinColor("gtip.body")
      GameTooltip:AddLine(tooltip, r, g, bl, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  b:SetScript("OnClick", onClick)
  NS.Skin.Button(b)
  return b
end
