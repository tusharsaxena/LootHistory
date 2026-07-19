local addonName, NS = ...
NS.BrowserTable = NS.BrowserTable or {}
local BrowserTable = NS.BrowserTable
local C = NS.Constants

-- Virtualized pooled-row table over Database:Query — filter -> group -> sort -> slice -> bind
-- (see docs/browser.md).

local ROW_H = 18
local HEADER_H = 20
local ITEM_MIN = 150  -- minimum width of the flex (Item) column
local COL_GAP = 8     -- horizontal space between columns
-- Every row shows a lock; colour + opacity encode the binding state. {r, g, b, alpha}
-- Hues drawn from WoW's palette (Blizzard gold, legendary orange, rare blue), muted a touch.
local BOUND_STYLE = {
  UNBOUND = { 0.60, 0.60, 0.60, 0.40 }, -- not bound: faint grey
  BOE     = { 0.92, 0.92, 0.92, 0.95 }, -- bind on equip: off-white
  BOP     = { 0.30, 0.82, 0.42, 1.00 }, -- bind on pickup: green (distinct from account orange)
  ACCOUNT = { 0.95, 0.52, 0.12, 1.00 }, -- account bound: orange
  WARBAND = { 0.30, 0.58, 0.98, 1.00 }, -- warbound: blue
}

-- Apply a padlock look to a texture, tolerant of missing art: use the first lock atlas that
-- actually exists on this client, else fall back to a solid chip so the column is never blank.
-- communities-icon-lock + greatVault-lock confirmed present on 11.x; the rest are fallbacks
-- for other flavors/versions.
local LOCK_ATLASES = {
  "communities-icon-lock", "greatVault-lock", "UI-LFG-Lock",
  "Professions-Recipe-Locked", "collections-icon-lock",
}

-- Resolve (once) the first lock atlas that exists on this client; false if none.
local resolvedLockAtlas
local function lockAtlas()
  if resolvedLockAtlas ~= nil then return resolvedLockAtlas end
  resolvedLockAtlas = false
  if C_Texture and C_Texture.GetAtlasInfo then
    for _, atlas in ipairs(LOCK_ATLASES) do
      if C_Texture.GetAtlasInfo(atlas) then
        resolvedLockAtlas = atlas
        break
      end
    end
  end
  return resolvedLockAtlas
end

local function applyLockTexture(tex)
  local atlas = lockAtlas()
  if atlas then
    tex:SetAtlas(atlas)
  else
    tex:SetTexture("Interface\\Buttons\\WHITE8X8") -- visible chip fallback (pending a real lock atlas)
  end
end

-- Inline coloured lock (or chip) for tooltip text, tinted to a BOUND_STYLE colour.
local function lockMarkup(style)
  local r = math.floor((style[1] or 1) * 255)
  local g = math.floor((style[2] or 1) * 255)
  local b = math.floor((style[3] or 1) * 255)
  local atlas = lockAtlas()
  if atlas and CreateAtlasMarkup then
    return CreateAtlasMarkup(atlas, 14, 14, 0, 0, r, g, b)
  end
  if CreateTextureMarkup then
    return CreateTextureMarkup("Interface\\Buttons\\WHITE8X8", 8, 8, 12, 12, 0, 1, 0, 1, r, g, b)
  end
  return ""
end

-- Legend for the Bound column tooltip: one "[lock] - Label" line per state.
local BOUND_LEGEND = {
  { "UNBOUND", "Not Bound" },
  { "BOE",     "Bind on Equip" },
  { "BOP",     "Bind on Pickup" },
  { "ACCOUNT", "Account Bound" },
  { "WARBAND", "Warbound" },
}
function BrowserTable:AddBoundLegend(tooltip)
  for _, entry in ipairs(BOUND_LEGEND) do
    tooltip:AddLine(lockMarkup(BOUND_STYLE[entry[1]]) .. " - " .. entry[2], 0.9, 0.9, 0.9)
  end
end

-- Inline class icon for the Character column. Prefer the classicon-<class> atlas (renders
-- cleanly inline); fall back to the shared class-circles texture via CLASS_ICON_TCOORDS.
local CLASS_ICON_TEX = "Interface\\TargetingFrame\\UI-Classes-Circles"
local function classIconMarkup(classFile)
  if not classFile then return "" end
  local atlas = "classicon-" .. classFile:lower()
  if CreateAtlasMarkup and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
    return CreateAtlasMarkup(atlas, 14, 14)
  end
  local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
  if c and CreateTextureMarkup then
    return CreateTextureMarkup(CLASS_ICON_TEX, 256, 256, 14, 14,
      c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
  end
  return ""
end

-- Exposed for the Browser's Character dropdown, so its menu items carry the same inline class
-- icon the Character column renders.
function BrowserTable:ClassIconMarkup(classFile) return classIconMarkup(classFile) end

-- Class-colored, icon-prefixed display value for a looter. Shows the full "Name-Realm" so
-- same-named characters on different realms stay distinct.
local function charDisplay(r)
  local name = r.char or ""
  local icon = classIconMarkup(r.classFile)
  return icon ~= "" and (icon .. " " .. name) or name
end

-- Column model. width 0 + flex=true means "absorb the remaining width" (the Item column).
-- Order note: the Character column is intentionally LAST, and Vendor second-last. Any new
-- columns (AH price, Pawn, …) should be inserted BEFORE Character so it stays the last column.
BrowserTable.COLUMNS = {
  { key = "date", label = "Date", width = 66, align = "LEFT",
    desc = "Date the item was looted.",
    valueFn = function(r) return NS.Util.FormatDate(r.ts) end,
    sortFn = function(r) return r.ts or 0 end },
  { key = "time", label = "Time", width = 32, align = "LEFT",
    desc = "Time of day the item was looted.",
    valueFn = function(r) return NS.Util.FormatClock(r.ts) end,
    sortFn = function(r) return r.ts or 0 end },
  { key = "ilvl", label = "iLvl", width = 34, align = "RIGHT",
    desc = "Item level (equippable gear only).",
    valueFn = function(r) return r.itemLevel and tostring(r.itemLevel) or "" end,
    sortFn = function(r) return r.itemLevel or 0 end },
  { key = "bound", label = "", width = 20, align = "CENTER", icon = true,
    desc = "Binding: grey = not bound, white = Bind on Equip, green = Bind on Pickup, "
      .. "orange = Account bound, blue = Warbound.",
    valueFn = function() return "" end,   -- rendered as an icon, not text
    sortFn = function(r) return r.bound or "" end },
  { key = "item", label = "Item", width = 0, flex = true, align = "LEFT",
    desc = "Item looted. Hover for its tooltip.",
    valueFn = function(r)
      return r.itemName or (r.itemLink and r.itemLink:match("%[(.-)%]")) or "?"
    end,
    sortFn = function(r) return (r.itemName or ""):lower() end },
  { key = "qty", label = "Qty", width = 34, align = "RIGHT",
    desc = "Quantity looted in this event.",
    valueFn = function(r) return tostring(r.quantity or 1) end,
    sortFn = function(r) return r.quantity or 1 end },
  { key = "quality", label = "Quality", width = 64, align = "LEFT",
    desc = "Item quality (Poor → Legendary).",
    valueFn = function(r) return NS.Compat.QualityLabel(r.quality) end,
    sortFn = function(r) return r.quality or 0 end },
  { key = "type", label = "Type", width = 76, align = "LEFT",
    desc = "Item type (subtype in the Item tooltip).",
    valueFn = function(r) return r.itemType or "" end,
    sortFn = function(r) return (r.itemType or ""):lower() end },
  { key = "subtype", label = "SubType", width = 100, align = "LEFT",
    desc = "Item subtype (e.g. Cloth, One-Handed Swords, Potion).",
    valueFn = function(r) return r.itemSubType or "" end,
    sortFn = function(r) return (r.itemSubType or ""):lower() end },
  { key = "source", label = "Source", width = 96, align = "LEFT",
    desc = "How the item was acquired (kill, container, mail, trade, …).",
    valueFn = function(r) return C.SourceLabel[r.source] or r.source or "Other" end,
    sortFn = function(r) return C.SourceLabel[r.source] or r.source or "" end },
  { key = "zone", label = "Zone", width = 100, align = "LEFT",
    desc = "Zone where the item was looted (subzone in the item tooltip).",
    valueFn = function(r) return r.zone or "" end,
    sortFn = function(r) return (r.zone or ""):lower() end },
  { key = "vendor", label = "Vendor", width = 72, align = "RIGHT",
    desc = "Vendor sell price per unit.",
    valueFn = function(r) return NS.Util.FormatMoney(r.vendorPrice) end,
    sortFn = function(r) return r.vendorPrice or 0 end },
  { key = "auction", label = "AH", width = 72, align = "RIGHT",
    desc = "Auction-house price per unit at loot time (chosen by your price-priority order).",
    valueFn = function(r) return NS.Util.FormatMoney((NS.AuctionPrice:Pick(r.auctionPrice))) end,
    sortFn = function(r) return (NS.AuctionPrice:Pick(r.auctionPrice)) or 0 end },
  -- Character is always the last column (see order note above).
  { key = "char", label = "Character", width = 132, align = "LEFT",
    desc = "Character who looted the item — full Name-Realm, class-colored.",
    valueFn = function(r) return charDisplay(r) end,
    sortFn = function(r) return (r.char or ""):lower() end },
}

local COLUMN_BY_KEY = {}
for _, col in ipairs(BrowserTable.COLUMNS) do COLUMN_BY_KEY[col.key] = col end

-- Pure cell text for a column key + record (unit-tested; the UI binds via the same path).
function BrowserTable:CellText(key, record)
  local col = COLUMN_BY_KEY[key]
  if not col then return "" end
  return col.valueFn(record)
end

-- ── Pipeline ───────────────────────────────────────────────────────────────────
BrowserTable.filter = {}
BrowserTable.testMode = false

-- Active sort. Default: newest loot first (Date column, descending).
BrowserTable.sortKey = "date"
BrowserTable.sortAsc = false

-- Columns whose sortFn yields a number. New sort on these starts descending (largest/
-- newest first); text columns start ascending (A→Z). Re-clicking a column toggles.
local NUMERIC_SORT = { date = true, time = true, ilvl = true, qty = true, quality = true, vendor = true, auction = true }

-- The default WoW font has no ▲/▼/▶ glyphs, so all arrows use inline texture markup instead.
-- ":0" sizes the texture to the surrounding line height. These button textures ship in every
-- flavor. Sort arrows use the up/down spinner arrows; group headers use +/- (see BindRow).
local ARROW_ASC  = " |TInterface\\Buttons\\Arrow-Up-Up:0|t"
local ARROW_DESC = " |TInterface\\Buttons\\Arrow-Down-Up:0|t"

-- Grouping. "none" = flat table; otherwise records are partitioned under collapsible
-- headers (see SetGroupBy). collapsed[key] = true hides a group's rows. groupAsc is the
-- group-order direction (ascending by default), toggled by clicking the grouped column.
BrowserTable.groupBy = "none"
BrowserTable.collapsed = {}
BrowserTable.groupAsc = true

-- Group identity + display label for a record under the active group-by. The key is
-- namespaced by group mode so the collapsed-state map never collides across modes (a
-- zone named "Kill" vs the Kill source). \001 is an unprintable separator.
local function groupOf(groupBy, r)
  local raw, label
  if groupBy == "source" then
    label = C.SourceLabel[r.source] or r.source or "Other"; raw = label
  elseif groupBy == "zone" then
    label = r.zone or "Unknown"; raw = label
  elseif groupBy == "char" then
    raw = r.char or "Unknown"; label = raw
  elseif groupBy == "type" then
    label = r.itemType or "Unknown"; raw = label
  elseif groupBy == "quality" then
    label = NS.Compat.QualityLabel(r.quality); raw = "q" .. tostring(r.quality or 0)
  elseif groupBy == "day" then
    -- Key stays ISO (stable, unique per calendar day); label matches the Date column's format.
    raw = date("%Y-%m-%d", r.ts or 0); label = NS.Util.FormatDate(r.ts or 0)
  else
    label = "?"; raw = "?"
  end
  return groupBy .. "\001" .. raw, label
end

-- groupBy mode → the table column it corresponds to (drives the header arrow + group-order
-- toggle) and the human prefix shown in each group header ("Quality: Poor").
local GROUP_COLUMN = { source = "source", zone = "zone", char = "char", quality = "quality", type = "type", day = "date" }
local GROUP_PREFIX = { source = "Source", zone = "Zone", char = "Character", quality = "Quality", type = "Type", day = "Day" }

-- Synthetic dataset for /lh test. A deliberately NON-uniform spread so the Insights charts read
-- like real play: weighted-random sources/qualities/classes/zones/types/timestamps, a handful of
-- "hot" items that drop often over a long tail, and keystone/hour peaks. A deterministic PRNG
-- (fixed seed, NOT math.random) keeps the data byte-identical every run so the headless tests stay
-- stable. A short seed pass first guarantees every source/quality/class/binding appears and the
-- range spans >14 days regardless of how the dice fall.
local TEST_BINDINGS = {
  { key = nil,       name = "Unbound" },
  { key = "BOE",     name = "Bind on Equip" },
  { key = "BOP",     name = "Bind on Pickup" },
  { key = "ACCOUNT", name = "Account Bound" },
  { key = "WARBAND", name = "Warbound" },
}
local TEST_CLASSES = {
  "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
  "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}
-- Midnight (12.0.x) zones — Quel'Thalas region.
local TEST_ZONES = {
  { name = "Silvermoon City",    mapID = 110 },
  { name = "Eversong Woods",     mapID = 94 },
  { name = "Isle of Quel'Danas", mapID = 122 },
  { name = "Zul'Aman",           mapID = 781 },
  { name = "Harandar",           mapID = 2400 },
  { name = "Tirisfal Glades",    mapID = 18 },
}
-- Weighted distributions ({ value, weight }) — larger weight ⇒ appears more, so no two bars match.
local TEST_SOURCE_W = {
  { "KILL", 30 }, { "CONTAINER", 22 }, { "QUEST", 16 }, { "MPLUS", 15 }, { "VENDOR", 10 },
  { "ROLL", 9 }, { "MAIL", 8 }, { "TRADE", 7 }, { "DISENCHANT", 7 }, { "AH", 6 },
  { "CRAFT", 6 }, { "MILLING", 5 }, { "PROSPECTING", 5 }, { "OTHER", 4 },
}
local TEST_QUALITY_W = { { 0, 8 }, { 1, 14 }, { 2, 26 }, { 3, 22 }, { 4, 12 }, { 5, 4 } }
local TEST_CLASS_W = {  -- a few "mains" dominate the play time
  { "MAGE", 14 }, { "WARRIOR", 12 }, { "ROGUE", 10 }, { "PRIEST", 9 }, { "DRUID", 9 },
  { "PALADIN", 8 }, { "HUNTER", 8 }, { "DEATHKNIGHT", 6 }, { "SHAMAN", 6 }, { "WARLOCK", 6 },
  { "MONK", 5 }, { "DEMONHUNTER", 5 }, { "EVOKER", 4 },
}
local TEST_ZONE_W = { { 1, 24 }, { 2, 18 }, { 4, 16 }, { 3, 12 }, { 6, 10 }, { 5, 8 } } -- index into TEST_ZONES
local TEST_TYPE_W = {
  { "Armor", 22 }, { "Consumable", 20 }, { "Tradegoods", 18 }, { "Weapon", 14 },
  { "Quest", 10 }, { "Gem", 8 }, { "Recipe", 6 },
}
-- Representative subtypes per item type, so the SubType column/filter has variety in test mode.
-- Chosen deterministically off idBase (never the RNG stream) to keep the synthetic data stable.
local TEST_SUBTYPES = {
  Armor      = { "Cloth", "Leather", "Mail", "Plate" },
  Weapon     = { "One-Handed Swords", "Daggers", "Staves", "Bows" },
  Consumable = { "Potion", "Food & Drink", "Flask" },
  Tradegoods = { "Herb", "Cloth", "Metal & Stone", "Leather" },
  Gem        = { "Cut Gem", "Uncut Gem" },
  Recipe     = { "Tailoring", "Alchemy", "Blacksmithing" },
  Quest      = { "Quest" },
}
local TEST_SUBTYPES_MISC = { "Other", "Junk" }
local TEST_KEY_W = {  -- keystone levels cluster around the mid keys
  { 2, 4 }, { 3, 6 }, { 4, 8 }, { 5, 10 }, { 6, 11 }, { 7, 12 }, { 8, 11 }, { 9, 9 },
  { 10, 8 }, { 11, 6 }, { 12, 5 }, { 13, 4 }, { 14, 3 }, { 15, 2 }, { 16, 1 }, { 18, 1 }, { 20, 1 },
}
local TEST_HOUR_W = {}  -- evening-leaning hour-of-day curve
do
  local w = { [0] = 2, [1] = 1, [2] = 1, [3] = 1, [4] = 1, [5] = 1, [6] = 2, [7] = 3,
              [8] = 4, [9] = 5, [10] = 6, [11] = 6, [12] = 7, [13] = 6, [14] = 5, [15] = 5,
              [16] = 6, [17] = 8, [18] = 11, [19] = 13, [20] = 14, [21] = 12, [22] = 9, [23] = 5 }
  for h = 0, 23 do TEST_HOUR_W[#TEST_HOUR_W + 1] = { h, w[h] } end
end
-- Item pool: the first 8 are "hot" (recur often), the rest a long tail. Name is keyed off the id.
local TEST_ITEM_NAMES = {
  "Sunwell Cinder", "Thalassian Warblade", "Ley-Woven Cloak", "Void-Touched Shard",
  "Everlight Crystal", "Duskweave Bracers", "Arcane Reservoir", "Bloodgem Signet",
  "Runeblade of Quel'Thalas", "Felflame Ember", "Silvermoon Sigil", "Manaforge Core",
  "Nightfall Pendant", "Amani Warspear", "Sunstrider Medallion", "Auric Bar",
  "Ravaged Sunhawk Plume", "Eversong Petal", "Twilight Opal", "Dawnthread Bolt",
  "Spellfire Cindersilk", "Harandar Relic", "Quel'dorei Warglaive", "Mana-Etched Band",
  "Sanctified Reliquary", "Shadowflame Tome", "Emberglow Sapphire", "Wretched Fel Dust",
  "Highborne Codex", "Sindorei Banner",
}
local TEST_DAY = 86400
local TEST_SPAN_DAYS = 20   -- drops are spread over roughly the last 20 days
local TEST_HOT_ITEMS = 8

-- Minimal-standard (Park–Miller) LCG: products stay < 2^46, so the double arithmetic is exact and
-- the sequence is identical on every platform. rng(n) returns an integer in [1, n].
local function testRng(seed)
  local state = seed % 2147483647
  if state <= 0 then state = state + 2147483646 end
  return function(n)
    state = (state * 16807) % 2147483647
    return (state % n) + 1
  end
end
-- Weighted pick from a { {value, weight}, ... } table.
local function testPick(rng, weighted)
  local total = 0
  for _, e in ipairs(weighted) do total = total + e[2] end
  local roll, acc = rng(total), 0
  for _, e in ipairs(weighted) do
    acc = acc + e[2]
    if roll <= acc then return e[1] end
  end
  return weighted[#weighted][1]
end

function BrowserTable:BuildTestData()
  local now = time()
  local rng = testRng(0x10A75AFE)   -- fixed seed → identical dataset every run
  local out = {}

  -- Build one record from the pivot values; everything else is derived and jittered.
  local function make(source, q, cls, bindIdx)
    local b      = TEST_BINDINGS[bindIdx]
    local zone   = TEST_ZONES[testPick(rng, TEST_ZONE_W)]
    local ty     = testPick(rng, TEST_TYPE_W)
    local isGear = (ty == "Armor" or ty == "Weapon")
    -- Skewed item pool: ~45% of drops land on one of the hot items, the rest on the long tail.
    local idBase = (rng(100) <= 45) and rng(TEST_HOT_ITEMS)
                   or (TEST_HOT_ITEMS + rng(#TEST_ITEM_NAMES - TEST_HOT_ITEMS))
    -- Timestamp: weighted day (a third of drops cluster onto the last few days) + evening hour.
    local dayOffset = rng(TEST_SPAN_DAYS) - 1
    if rng(3) == 1 then dayOffset = rng(5) - 1 end
    local secInto = testPick(rng, TEST_HOUR_W) * 3600 + (rng(60) - 1) * 60 + (rng(60) - 1)
    local qty = 1
    if not isGear then qty = (q <= 1) and (1 + rng(19)) or (1 + rng(4)) end
    out[#out + 1] = {
      ts = now - dayOffset * TEST_DAY - secInto,
      char = cls:sub(1, 1) .. cls:sub(2):lower() .. "-Ravencrest",
      classFile = cls,
      itemID = 100000 + idBase,
      itemName = TEST_ITEM_NAMES[idBase],
      quality = q,
      quantity = qty,
      itemLevel = isGear and (560 + q * 12 + rng(40)) or nil, -- gear only; scales with quality
      bound = b.key,
      vendorPrice = (q * q + 1) * (200 + rng(1800)) + rng(500), -- wide, quality-skewed value spread
      auctionPrice = (rng(100) <= 70) and {
        tsm = { dbmarket = (q * q + 1) * (600 + rng(6000)) + rng(1500),
                dbminbuyout = (q * q + 1) * (400 + rng(5000)) },
        oribos = { market = (q * q + 1) * (500 + rng(6000)) },
      } or nil,
      itemType = ty,
      itemSubType = (function()
        local list = TEST_SUBTYPES[ty] or TEST_SUBTYPES_MISC
        return list[(idBase % #list) + 1]
      end)(),
      source = source,
      sourceDetail = (source == "MPLUS") and { keystoneLevel = testPick(rng, TEST_KEY_W) } or nil,
      zone = zone.name,
      mapID = zone.mapID,
      confidence = (rng(100) <= 14) and "INFERRED" or "CERTAIN",
    }
  end

  -- 1) Coverage seed: guarantee every source/quality/class/binding appears at least once and that
  --    the timestamps reach both ends of the window (the tests assert full coverage + >14d span).
  local seedN = math.max(#C.SourceOrder, #TEST_CLASSES, #TEST_BINDINGS, 6, TEST_SPAN_DAYS)
  for i = 1, seedN do
    make(C.SourceOrder[((i - 1) % #C.SourceOrder) + 1], (i - 1) % 6,
         TEST_CLASSES[((i - 1) % #TEST_CLASSES) + 1], ((i - 1) % #TEST_BINDINGS) + 1)
    out[#out].ts = now - ((i - 1) % TEST_SPAN_DAYS) * TEST_DAY - rng(80000) -- walk the full span
  end

  -- 2) Weighted bulk: the mass of the dataset, fully weighted-random so every pivot comes out uneven.
  for _ = 1, 260 do
    make(testPick(rng, TEST_SOURCE_W), testPick(rng, TEST_QUALITY_W),
         testPick(rng, TEST_CLASS_W), rng(#TEST_BINDINGS))
  end

  return out
end

function BrowserTable:ToggleTestMode()
  self.testMode = not self.testMode
  -- Publish to State so every read-path query (table + Insights) resolves against the same data.
  NS.State.testRecords = self.testMode and self:BuildTestData() or nil
  if NS.Browser and NS.Browser.Show then NS.Browser:Show() end
  -- The dataset changed under the filter bar: reset filters, rebuild the dropdowns from the
  -- new dataset, refresh the footer, and toggle the Test-Mode badge.
  if NS.Browser and NS.Browser.OnDatasetChanged then
    NS.Browser:OnDatasetChanged()
  else
    self:Refresh()
  end
  return self.testMode
end

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

-- Set the active grouping ("none"/source/zone/char/quality/day) and repaint.
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
-- entry labelled "<Column>: <Value>" with its count; a collapsed group emits only its header.
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
    local key, valueLabel = groupOf(groupBy, r)
    local g = byKey[key]
    if not g then
      g = { key = key, label = prefix .. ": " .. valueLabel, rows = {},
            sortKey = sortFn and sortFn(r) or valueLabel }
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

-- ── Pooled rows ─────────────────────────────────────────────────────────────────

local function qualityColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

function BrowserTable:AcquireRow()
  local pool = self.rowPool
  local row = table.remove(pool.free)
  if row then
    row:Show()
    return row
  end

  row = CreateFrame("Button", nil, self.rowHost)
  row:SetHeight(ROW_H)
  row:SetPoint("LEFT", self.rowHost, "LEFT", 0, 0)
  row:SetPoint("RIGHT", self.rowHost, "RIGHT", 0, 0)

  local stripe = row:CreateTexture(nil, "BACKGROUND")
  stripe:SetAllPoints()
  stripe:SetColorTexture(1, 1, 1, 0.03)
  row.stripe = stripe

  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.82, 0, 0.10)

  -- One FontString per data column, laid out left→right with the Item column flexing.
  row.cells = {}
  for _, col in ipairs(self.COLUMNS) do
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH(col.align)
    fs:SetHeight(ROW_H)
    fs:SetWordWrap(false)
    row.cells[col.key] = fs
  end

  -- Bound-state lock icon (Bound column); tinted + shown per record in BindRow.
  local boundIcon = row:CreateTexture(nil, "OVERLAY")
  boundIcon:SetSize(14, 14)
  applyLockTexture(boundIcon)
  boundIcon:Hide()
  row.boundIcon = boundIcon

  -- Group-header styling (used in 3.4); hidden for data rows.
  local header = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  header:SetPoint("LEFT", 4, 0)
  header:SetTextColor(1, 0.82, 0)
  header:Hide()
  row.header = header

  -- Hover → the full in-game item tooltip for this row's record; INFERRED rows get a note
  -- explaining the source is a guess. A hint line advertises the click interactions.
  row:SetScript("OnEnter", function(self2)
    local e = self2.entry
    if e and e.kind == "row" and e.record.itemLink then
      GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(e.record.itemLink)
      if e.record.confidence == "INFERRED" then
        GameTooltip:AddLine("Source inferred (uncertain).", 0.62, 0.62, 0.62)
      end
      GameTooltip:AddLine("Shift-click to link · right-click for options", 0.5, 0.5, 0.5)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Header left-click toggles collapse. Data rows: shift-left-click links the item to chat;
  -- right-click opens the row action menu.
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", function(self2, button)
    local e = self2.entry
    if not e then return end
    if e.kind == "header" then
      if button == "LeftButton" then BrowserTable:ToggleCollapse(e.key) end
      return
    end
    local link = e.record.itemLink
    if button == "LeftButton" then
      if IsShiftKeyDown() and link and ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
      end
    elseif button == "RightButton" then
      BrowserTable:ShowRowMenu(self2, e.record)
    end
  end)

  self:LayoutRowCells(row)
  return row
end

-- Width available for columns (row host viewport), with a fallback before first layout.
function BrowserTable:ContentWidth()
  local w = self.rowHost and self.rowHost:GetWidth()
  if not w or w <= 0 then return 780 end
  return w
end

-- Minimum window width that shows every column without truncation: the sum of fixed column
-- widths + gaps + the Item column's minimum + scrollbar gutter + pane margins. Browser uses
-- this as both the default and the minimum window width so columns never overflow.
function BrowserTable:MinFrameWidth()
  local w = 0
  for _, col in ipairs(self.COLUMNS) do
    w = w + (col.flex and ITEM_MIN or col.width) + COL_GAP
  end
  return math.ceil(w + 24 + 12) -- scrollbar gutter + pane left/right margins
end

-- Position each cell by cumulative column widths; the flex column takes the slack.
function BrowserTable:LayoutRowCells(row)
  local total = self:ContentWidth()
  local fixed = 0
  for _, col in ipairs(self.COLUMNS) do
    if not col.flex then fixed = fixed + col.width + COL_GAP end
  end
  local flexW = math.max(ITEM_MIN, total - fixed)

  local x = 0
  for _, col in ipairs(self.COLUMNS) do
    local w = col.flex and flexW or col.width
    local fs = row.cells[col.key]
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", x, 0)
    fs:SetWidth(w)
    if col.icon and row.boundIcon then
      row.boundIcon:ClearAllPoints()
      row.boundIcon:SetPoint("CENTER", row, "LEFT", x + w / 2, 0)
    end
    x = x + w + COL_GAP
  end
end

function BrowserTable:ReleaseAllRows()
  local pool = self.rowPool
  for _, row in ipairs(pool.active) do
    row:Hide()
    pool.free[#pool.free + 1] = row
  end
  wipe(pool.active)
end

-- ── Attach + render ──────────────────────────────────────────────────────────────

function BrowserTable:Attach(pane)
  if self.frame then return end
  self.pane = pane

  -- Header row (right inset matches the row host so columns line up with the data cells).
  local header = CreateFrame("Frame", nil, pane)
  header:SetPoint("TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", -24, 0)
  header:SetHeight(HEADER_H)
  self.headerFrame = header

  -- FauxScrollFrame drives the scrollbar + offset. Pooled rows live in a sibling overlay
  -- (rowHost) aligned with the scroll viewport, so the ScrollFrame never clips them.
  local scroll = CreateFrame("ScrollFrame", "LootHistoryTableScroll", pane, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  -- Bottom raised 16px so the scrollbar's down-arrow clears the window resize grip.
  scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -24, 16)
  scroll:SetScript("OnVerticalScroll", function(self2, offset)
    FauxScrollFrame_OnVerticalScroll(self2, offset, ROW_H, function() BrowserTable:Bind() end)
  end)
  scroll:SetScript("OnSizeChanged", function() BrowserTable:Bind() end)
  self.scroll = scroll

  local host = CreateFrame("Frame", nil, pane)
  host:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  host:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
  self.rowHost = host

  self.rowPool = { active = {}, free = {} }

  -- Empty-state text.
  local empty = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
  empty:SetPoint("CENTER", scroll, "CENTER", 0, 0)
  empty:Hide()
  self.emptyText = empty

  self:BuildHeaderCells()
  self.frame = pane
  self:Refresh()
end

-- Build one header button per column (text label, or a white lock for the icon column).
-- Each shows a tooltip describing the column and sorts by that column on click.
function BrowserTable:MakeHeaderButton(col)
  local btn = CreateFrame("Button", nil, self.headerFrame)
  btn:SetHeight(HEADER_H)
  if col.icon then
    local tex = btn:CreateTexture(nil, "OVERLAY")
    tex:SetSize(14, 14)
    tex:SetPoint("CENTER")
    applyLockTexture(tex)
    tex:SetVertexColor(1, 1, 1) -- white lock as the Bound header
    btn.tex = tex
  else
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", 0, 0)
    fs:SetJustifyH(col.align)
    fs:SetText(col.label)
    fs:SetTextColor(1, 0.82, 0)
    btn.fs = fs
  end
  btn:SetScript("OnEnter", function(self2)
    GameTooltip:SetOwner(self2, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(col.label ~= "" and col.label or "Bound", 1, 0.82, 0)
    if col.icon then
      BrowserTable:AddBoundLegend(GameTooltip)
    elseif col.desc then
      GameTooltip:AddLine(col.desc, 0.9, 0.9, 0.9, true)
    end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:SetScript("OnClick", function() BrowserTable:SetSort(col.key) end)
  return btn
end

-- Repaint the sort arrow: the active column shows ▲/▼ after its label; others show label only.
-- The icon (Bound) header has no label FontString, so it sorts but shows no arrow.
function BrowserTable:UpdateHeaderArrows()
  local header = self.headerFrame
  if not header or not header.buttons then return end
  -- The grouped column shows the group-order arrow; the row-sort column shows the sort arrow.
  local groupedCol = self.groupBy ~= "none" and GROUP_COLUMN[self.groupBy] or nil
  for key, btn in pairs(header.buttons) do
    if btn.fs then
      local col = COLUMN_BY_KEY[key]
      local label = col and col.label or ""
      if key == groupedCol then
        label = label .. (self.groupAsc and ARROW_ASC or ARROW_DESC)
      elseif key == self.sortKey then
        label = label .. (self.sortAsc and ARROW_ASC or ARROW_DESC)
      end
      btn.fs:SetText(label)
    end
  end
end

function BrowserTable:BuildHeaderCells()
  local header = self.headerFrame
  header.buttons = header.buttons or {}
  local total = self:ContentWidth()
  local fixed = 0
  for _, col in ipairs(self.COLUMNS) do
    if not col.flex then fixed = fixed + col.width + COL_GAP end
  end
  local flexW = math.max(ITEM_MIN, total - fixed)

  local x = 0
  for _, col in ipairs(self.COLUMNS) do
    local w = col.flex and flexW or col.width
    local btn = header.buttons[col.key]
    if not btn then
      btn = self:MakeHeaderButton(col)
      header.buttons[col.key] = btn
    end
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", header, "LEFT", x, 0)
    btn:SetWidth(w)
    if btn.fs then btn.fs:SetWidth(w) end
    x = x + w + COL_GAP
  end
  self:UpdateHeaderArrows()
end

-- Pure one-line render summary for the [Table] trace. filterCount = number of active
-- filter keys; sortAsc drives the direction word. No frames, no side effects.
function BrowserTable.RenderSummary(matchCount, total, filterCount, groupBy, sortKey, sortAsc)
  return ("rendered %s/%s rows (group=%s, sort=%s %s, filters=%s)"):format(
    tostring(matchCount), tostring(total), tostring(groupBy or "none"),
    tostring(sortKey), sortAsc and "asc" or "desc", tostring(filterCount or 0))
end

-- Recompute the display list and repaint. Safe to call before Attach (no-op).
function BrowserTable:Refresh()
  if not self.frame then return end
  self.displayList = self:BuildDisplayList()
  self:Bind()
  if NS.State.debug and NS.Debug then
    local total = #(NS.Database:ActiveHistory() or {})
    local fc = 0
    for _ in pairs(self.filter or {}) do fc = fc + 1 end
    NS.Debug("Table", "%s", BrowserTable.RenderSummary(
      self.matchCount or 0, total, fc, self.groupBy, self.sortKey, self.sortAsc))
  end
end

-- Bind the visible slice of the display list onto pooled rows.
function BrowserTable:Bind()
  if not self.frame then return end
  self:BuildHeaderCells()   -- keep header columns aligned with rows across resizes
  local list = self.displayList or {}
  local scroll = self.scroll
  local viewH = scroll:GetHeight()
  if not viewH or viewH <= 0 then viewH = ROW_H * 20 end
  local numVisible = math.max(1, math.floor(viewH / ROW_H))

  FauxScrollFrame_Update(scroll, #list, numVisible, ROW_H)
  local offset = FauxScrollFrame_GetOffset(scroll)

  self:ReleaseAllRows()
  self.emptyText:SetShown(#list == 0)
  if #list == 0 then
    self.emptyText:SetText(next(self.filter or {}) and "No records match your filters."
      or "No loot recorded yet. Go kill something.")
    return
  end

  local pool = self.rowPool
  for i = 1, numVisible do
    local entry = list[offset + i]
    if entry then
      local row = self:AcquireRow()
      row:SetPoint("TOP", self.rowHost, "TOP", 0, -(i - 1) * ROW_H)
      self:LayoutRowCells(row)
      self:BindRow(row, entry, offset + i)
      pool.active[#pool.active + 1] = row
    end
  end
end

function BrowserTable:BindRow(row, entry, absIndex)
  row.entry = entry
  row.stripe:SetShown(absIndex % 2 == 0)

  if entry.kind == "header" then
    for _, col in ipairs(self.COLUMNS) do row.cells[col.key]:SetText("") end
    row.boundIcon:Hide()
    row.header:Show()
    -- +/- box marks collapsed/expanded (font has no triangle glyphs; texture markup always works).
    local arrow = entry.collapsed and "|TInterface\\Buttons\\UI-PlusButton-Up:0|t"
      or "|TInterface\\Buttons\\UI-MinusButton-Up:0|t"
    row.header:SetText(arrow .. "  " .. (entry.label or "")
      .. "  |cff808080(" .. (entry.count or 0) .. ")|r")
    return
  end

  row.header:Hide()
  local r = entry.record
  for _, col in ipairs(self.COLUMNS) do
    local fs = row.cells[col.key]
    -- (INFERRED rows no longer get a dot before the item name; the row tooltip still notes it.)
    fs:SetText(col.valueFn(r))
    if col.key == "item" or col.key == "quality" then
      fs:SetTextColor(qualityColor(r.quality))
    elseif col.key == "char" then
      local cc = RAID_CLASS_COLORS and r.classFile and RAID_CLASS_COLORS[r.classFile]
      if cc then fs:SetTextColor(cc.r, cc.g, cc.b) else fs:SetTextColor(0.9, 0.9, 0.9) end
    else
      fs:SetTextColor(0.9, 0.9, 0.9)
    end
  end

  -- Bound lock icon (always shown): blue = warbound, white = soulbound, faint grey = unbound.
  local style = BOUND_STYLE[r.bound] or BOUND_STYLE.UNBOUND
  row.boundIcon:SetVertexColor(style[1], style[2], style[3])
  row.boundIcon:SetAlpha(style[4])
  row.boundIcon:Show()
end

-- ── Row context menu (right-click) ───────────────────────────────────────────────
-- A tiny flat-skin popup with per-row actions; an outside-click catcher dismisses it.
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local rowMenu
local function EnsureRowMenu()
  if rowMenu then return rowMenu end
  rowMenu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  rowMenu:SetFrameStrata("FULLSCREEN_DIALOG")
  rowMenu:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
  rowMenu:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
  rowMenu:SetBackdropBorderColor(0.62, 0.5, 0.18, 1)  -- muted gold edge (reads against the world without glaring)
  rowMenu:Hide()
  rowMenu.buttons = {}

  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:Hide()
  catcher:SetScript("OnClick", function() rowMenu:Hide() end)
  catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  rowMenu.catcher = catcher
  rowMenu:SetScript("OnHide", function() catcher:Hide() end)
  return rowMenu
end

function BrowserTable:ShowRowMenu(anchor, record)
  local m = EnsureRowMenu()
  local MENU_ROW_H, W = 18, 150
  local items = {
    { label = "Link to chat", enabled = record.itemLink ~= nil, fn = function()
        if record.itemLink and ChatEdit_InsertLink then ChatEdit_InsertLink(record.itemLink) end
      end },
    -- Blacklist this item: stop recording future loots of this id. Point-in-time — the row you
    -- clicked (and other existing rows of the same id) stay in the history; use Delete to remove
    -- them. Manage the list in Settings ▸ Filters.
    { label = "Blacklist item", enabled = record.itemID ~= nil, fn = function()
        if NS.Filters and NS.Filters:AddBlacklist(record.itemID) and NS.Print then
          NS.Print(("blacklisted %s. Manage in Settings \226\150\184 Filters."):format(
            record.itemName or ("item " .. tostring(record.itemID))))
        end
      end },
    { label = "|cffff5555Delete|r", enabled = true, fn = function()
        NS.Database:Delete(function(r) return r == record end) -- fires HistoryChanged
        BrowserTable:Refresh() -- repaint immediately (in case nothing else listens)
      end },
  }

  for _, b in ipairs(m.buttons) do b:Hide() end
  for i, item in ipairs(items) do
    local b = m.buttons[i]
    if not b then
      b = CreateFrame("Button", nil, m)
      b:SetHeight(MENU_ROW_H)
      local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", 8, 0)
      fs:SetJustifyH("LEFT")
      b.fs = fs
      local hl = b:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(1, 0.82, 0, 0.15)
      m.buttons[i] = b
    end
    b:SetWidth(W)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 0, -4 - (i - 1) * MENU_ROW_H)
    b.fs:SetText(item.label)
    if item.enabled then
      b.fs:SetTextColor(0.9, 0.9, 0.9)
      b:EnableMouse(true)
      b:SetScript("OnClick", function() m:Hide(); item.fn() end)
    else
      b.fs:SetTextColor(0.5, 0.5, 0.5)
      b:EnableMouse(false)
      b:SetScript("OnClick", nil)
    end
    b:Show()
  end

  m:SetSize(W, #items * MENU_ROW_H + 8)
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, 0)
  m.catcher:Show()
  m:Show()
end
