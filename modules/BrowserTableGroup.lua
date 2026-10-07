local _, NS = ...
NS.BrowserTable = NS.BrowserTable or {}
local BrowserTable = NS.BrowserTable
local C = NS.Constants

-- The History table's display-list layer: sort, group, and the filter -> sort -> group pipeline
-- the virtualizer binds (see docs/browser.md). Peeled verbatim out of modules/BrowserTable.lua,
-- which had passed its 1300-line re-check trigger with the layout-§1 cap 24 lines away (review
-- 2026-10-07 F-002). It extends NS.BrowserTable rather than publishing a module of its own.
--
-- LOAD-BEARING: binds BrowserTable._columnByKey and BrowserTable._groupColumn as file-scope locals
-- at load, so modules/BrowserTable.lua, which publishes them, must load directly above.
local COLUMN_BY_KEY = BrowserTable._columnByKey
local GROUP_COLUMN = BrowserTable._groupColumn

-- Columns whose sortFn yields a number. New sort on these starts descending (largest/
-- newest first); text columns start ascending (A→Z). Re-clicking a column toggles.
local NUMERIC_SORT = { date = true, time = true, dir = true, ilvl = true, qty = true, quality = true, vendor = true, auction = true }

-- Grouping. "none" = flat table; otherwise records are partitioned under collapsible
-- headers (see SetGroupBy). collapsed[key] = true hides a group's rows. groupAsc is the
-- group-order direction (ascending by default), toggled by clicking the grouped column.
BrowserTable.groupBy = "none"
BrowserTable.collapsed = {}
BrowserTable.groupAsc = true

-- One handler per group-by mode, returning (raw key part, display label) in that order, plus an
-- optional order value for a mode with no column to sort by (typesub). The table and its closures
-- are module-level, built once at load: groupOf runs once per record on every group build, so
-- nothing here may allocate per call. Adding a group mode is one entry here plus one in
-- GROUP_COLUMN/GROUP_PREFIX below.
local GROUP_OF = {
  source = function(r)
    local label = C.SourceLabel[r.source] or r.source or "Other"
    return label, label
  end,
  -- "" buckets with nil (NS.Zone answers "" with no zone text), as in Stats/the Zone filter.
  zone = function(r)
    local label = (r.zone ~= nil and r.zone ~= "" and r.zone) or "Unknown"
    return label, label
  end,
  char = function(r)
    local raw = r.holder or r.char or "Unknown"
    return raw, NS.LedgerFormat.HolderLabel(raw)
  end,
  type = function(r)
    local label = r.itemType or "Unknown"
    return label, label
  end,
  -- "Type & SubType" (P9): "Armor · Cloth", "Armor" with no subtype, by type then subtype.
  typesub = function(r) return NS.LedgerFormat.TypeSub(r.itemType, r.itemSubType) end,
  quality = function(r)
    return "q" .. tostring(r.quality or "-"),
           r.quality ~= nil and NS.Item.QualityLabel(r.quality) or "\226\128\148"
  end,
  -- Key stays ISO (stable, unique per calendar day); label matches the Date column's format.
  day = function(r)
    return date("%Y-%m-%d", r.ts or 0), NS.Util.FormatDate(r.ts or 0)
  end,
  dir = function(r)
    local d = NS.Util.RowDir(r)
    return d, C.DirLabel[d] or d
  end,
  holder = function(r)
    local h = NS.Util.RowHolder(r) or "Unknown"
    return h, NS.LedgerFormat.HolderLabel(h)
  end,
}

-- Group identity + display label for a record under the active group-by. The key is
-- namespaced by group mode so the collapsed-state map never collides across modes (a
-- zone named "Kill" vs the Kill source). \001 is an unprintable separator.
local function groupOf(groupBy, r)
  local fn = GROUP_OF[groupBy]
  local raw, label, order = "?", "?", nil
  if fn then raw, label, order = fn(r) end
  return groupBy .. "\001" .. raw, label, order
end

-- groupBy mode → the human prefix shown in each group header ("Quality: Poor"). The table column
-- each mode corresponds to is GROUP_COLUMN, in modules/BrowserTable.lua.
local GROUP_PREFIX = { source = "Source", zone = "Zone", char = "Character", quality = "Quality", type = "Type", day = "Day",
                       dir = "Direction", holder = "Holder", typesub = "Type" }

-- Stable sort by the active column into a NEW array (records are not mutated). Lua 5.1's
-- table.sort is not stable, so we tiebreak on the original index to keep equal keys in
-- their prior (chronological) order.
function BrowserTable:SortRecords(records)
  local col = COLUMN_BY_KEY[self.sortKey]
  if not col or not col.sortFn then return records end
  local keyFn, asc = col.sortFn, self.sortAsc
  local deco = {}
  for i = 1, #records do
    deco[i] = { r = records[i], i = i, k = keyFn(records[i]) }
  end
  table.sort(deco, function(a, b)
    if a.k ~= b.k then
      if asc then return a.k < b.k end
      return a.k > b.k
    end
    return a.i < b.i
  end)
  local out = {}
  for i = 1, #deco do out[i] = deco[i].r end
  return out
end

-- Handle a header click. If the table is grouped by this column, flip the GROUP order;
-- otherwise set the row sort — re-clicking the active column flips direction, a new column
-- starts descending for numeric columns and ascending for text.
function BrowserTable:SetSort(key)
  local col = COLUMN_BY_KEY[key]
  if not col or not col.sortFn then return end
  local groupedCol = self.groupBy ~= "none" and GROUP_COLUMN[self.groupBy] or nil
  if key == groupedCol then
    self.groupAsc = not self.groupAsc
    self:UpdateHeaderArrows()
    self:Refresh()
    return
  end
  if self.sortKey == key then
    self.sortAsc = not self.sortAsc
  else
    self.sortKey = key
    self.sortAsc = not NUMERIC_SORT[key]
  end
  self:UpdateHeaderArrows()
  self:Refresh()
end

-- Set the active grouping ("none"/source/zone/char/quality/type/typesub/day/dir/holder) and repaint.
function BrowserTable:SetGroupBy(key)
  self.groupBy = key or "none"
  self:Refresh()
end

-- Collapse/expand a group header (keyed by groupOf's namespaced key) and repaint.
function BrowserTable:ToggleCollapse(key)
  self.collapsed[key] = (not self.collapsed[key]) or nil
  self:Refresh()
end

-- Turn a (already-sorted) record array into the flat display list. With no grouping every
-- record is a { kind="row" } entry. With grouping, records are partitioned into groups sorted
-- by the grouping column's natural order (alphabetical for text, numeric for quality,
-- chronological for day; direction = groupAsc). Each group is preceded by a { kind="header" }
-- entry labeled "<Column>: <Value>" with its count; a collapsed group emits only its header.
-- The active row sort still holds within each group.
function BrowserTable:GroupRecords(records)
  local list = {}
  local groupBy = self.groupBy
  if not groupBy or groupBy == "none" then
    for _, r in ipairs(records) do
      list[#list + 1] = { kind = "row", record = r }
    end
    return list
  end

  local colKey = GROUP_COLUMN[groupBy]
  local col = colKey and COLUMN_BY_KEY[colKey]
  local sortFn = col and col.sortFn
  local prefix = GROUP_PREFIX[groupBy] or "?"

  local order, byKey = {}, {}
  for _, r in ipairs(records) do
    local key, valueLabel, groupOrder = groupOf(groupBy, r)
    local g = byKey[key]
    if not g then
      g = { key = key, label = prefix .. ": " .. valueLabel, rows = {},
            sortKey = sortFn and sortFn(r) or groupOrder or valueLabel }
      byKey[key] = g
      order[#order + 1] = g
    end
    g.rows[#g.rows + 1] = r
  end

  local asc = self.groupAsc ~= false
  table.sort(order, function(a, b)
    if a.sortKey ~= b.sortKey then
      if asc then return a.sortKey < b.sortKey end
      return a.sortKey > b.sortKey
    end
    return a.key < b.key
  end)

  for _, g in ipairs(order) do
    local collapsed = self.collapsed[g.key] or false
    list[#list + 1] = { kind = "header", key = g.key, label = g.label,
                        count = #g.rows, collapsed = collapsed }
    if not collapsed then
      for _, r in ipairs(g.rows) do
        list[#list + 1] = { kind = "row", record = r }
      end
    end
  end
  return list
end

-- The base dataset the table is showing: the synthetic dataset in test mode, else live history.
-- The filter bar (options + footer) reads this too, so filters work identically in both modes.
function BrowserTable:CurrentRecords()
  return NS.Database:ActiveHistory()
end

-- Filter -> sort -> group into the flat display list the virtualizer binds.
-- matchCount is the number of records that passed the filter (the "X" the footer shows),
-- captured before grouping inserts header entries.
function BrowserTable:BuildDisplayList()
  local records = NS.Database:QueryList(self:CurrentRecords(), self.filter)
  self.matchCount = #records
  return self:GroupRecords(self:SortRecords(records))
end

function BrowserTable:SetFilter(filter)
  self.filter = filter or {}
  self:Refresh()
end

-- The filtered records in current sort/group order (group headers dropped) — the "Current View"
-- dataset the Export modal serializes. Mirrors what the table shows on screen.
function BrowserTable:OrderedFilteredRecords()
  local out = {}
  for _, entry in ipairs(self:BuildDisplayList()) do
    if entry.kind == "row" then out[#out + 1] = entry.record end
  end
  return out
end
