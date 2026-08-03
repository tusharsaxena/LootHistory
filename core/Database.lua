local addonName, NS = ...

-- AceDB init. Account-wide: all history + settings live in NS.db.global.
function NS:InitDB()
  NS.db = LibStub("AceDB-3.0"):New("LootHistoryDB", NS.defaults, true)
  NS:RunMigrations()   -- normalize the persisted schema before any history read
end

-- Schema-migration runner (toc-file-§2 / savedvariables-§1). Reads/writes db.global.schemaVersion and
-- ships even with an effectively empty body — the *seam* is the requirement: future schema
-- changes get a single, idempotent upgrade path invoked once at init, before any read of
-- db.global.history. Safe no-op when the DB isn't ready yet.
function NS:RunMigrations()
  local g = NS.db and NS.db.global
  if not g then return end
  g.schemaVersion = g.schemaVersion or 1
  -- v1 -> v2: point-in-time filtering (removed soft-add/soft-delete). Strip the retired
  -- per-record `viaWhitelist` flag; rows are never hidden/resurrected after capture. Non-
  -- destructive — no rows are deleted (see docs/superpowers/specs/2026-07-18-*).
  if g.schemaVersion < 2 then
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.viaWhitelist ~= nil then r.viaWhitelist = nil; n = n + 1 end
    end
    g.schemaVersion = 2
    if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(1, 2, n)) end
  end
  -- v2 -> v3: rename per-record sellPrice -> vendorPrice (non-destructive; value preserved).
  if g.schemaVersion < 3 then
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.sellPrice ~= nil then r.vendorPrice = r.sellPrice; r.sellPrice = nil; n = n + 1 end
    end
    g.schemaVersion = 3
    if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(2, 3, n)) end
  end
  -- v3 -> v4: backfill currency-record quality (rows with currencyID but no quality) from
  -- C_CurrencyInfo, so the History browser can color the currency name + fill the Quality column
  -- for currencies looted before quality was captured. In-game only (C_CurrencyInfo); a currency the
  -- client can't resolve at init stays nil. Non-destructive.
  if g.schemaVersion < 4 then
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.currencyID and r.quality == nil then
        local q = NS.Compat.CurrencyQuality(r.currencyID)
        if q ~= nil then r.quality = q; n = n + 1 end
      end
    end
    g.schemaVersion = 4
    if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(3, 4, n)) end
  end

  -- v4 -> v5: backfill currency-record bound (rows with currencyID but no bound) from C_CurrencyInfo —
  -- "WARBAND" for a Warband-transferable currency, else "BOP" — so the History browser shows the bound
  -- glyph for currencies looted before bound was captured. In-game only (C_CurrencyInfo); a currency
  -- the client can't resolve at init stays nil. Non-destructive.
  if g.schemaVersion < 5 then
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.currencyID and r.bound == nil then
        local b = NS.Compat.CurrencyBound(r.currencyID)
        if b ~= nil then r.bound = b; n = n + 1 end
      end
    end
    g.schemaVersion = 5
    if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(4, 5, n)) end
  end

  -- v5 -> v6: retire the "ACCOUNT" bind state, splitting warbound into WARBAND / WARBAND_UE.
  -- Retail has had no account-bound wording distinct from Warbound since 11.0 (every
  -- ITEM_*ACCOUNTBOUND* global reads "Warbound"), and the old scanner filed *all* warbound loot
  -- under ACCOUNT because "Binds to Warband" sat in its account list — so every stored ACCOUNT row
  -- is a mislabeled warbound drop of one kind or the other. Which kind isn't recoverable from the
  -- record, so park every such row on the plain WARBAND state and let the deferred repair below
  -- (RepairBoundStates) split it once the client can answer. Any saved Bound filter naming the
  -- retired token follows too, else the view would match nothing. Non-destructive.
  if g.schemaVersion < 6 then
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.bound == "ACCOUNT" then r.bound = "WARBAND"; n = n + 1 end
    end
    local view = g.savedView
    if type(view) == "table" and type(view.bound) == "table" and view.bound.ACCOUNT then
      view.bound.ACCOUNT = nil
      view.bound.WARBAND, view.bound.WARBAND_UE = true, true
    end
    g.schemaVersion = 6
    if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(5, 6, n)) end
  end

  -- v6 -> v7: hand the warbound split to the deferred repair below. It can't be done inline —
  -- migrations run from InitDB at ADDON_LOADED with a cold item cache, so a one-shot pass here
  -- learns nothing and then bumps the stamp, burning the only chance to fix anything.
  if g.schemaVersion < 7 then
    g.schemaVersion = 7
    if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(6, 7, 0)) end
  end

  -- v7 -> v8: the Zone filter moved from mapID to the zone NAME (one named zone spans many
  -- UiMapIDs — every dungeon floor has its own — so the id-keyed menu listed a zone once per
  -- floor and each entry filtered only part of it). Translate a saved view's mapID set into the
  -- names those ids were recorded under, else the stored view would filter on a field nothing
  -- reads and silently show everything. Ids absent from the history resolve to nothing and drop.
  if g.schemaVersion < 8 then
    local n = 0
    local view = g.savedView
    if type(view) == "table" and type(view.mapID) == "table" then
      local names = {}
      for _, r in ipairs(g.history or {}) do
        if r.mapID ~= nil and view.mapID[r.mapID] then names[r.zone or ""] = true end
      end
      view.zone = next(names) and names or nil
      view.mapID = nil
      n = 1
    end
    g.schemaVersion = 8
    if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(7, 8, n)) end
  end

  NS:ArmBoundRepair(g)
end

-- Arming is versioned by REVISION, not by schemaVersion, because this repair has been wrong more
-- than once and each fix has to re-run it on DBs that already ran (and cleared) a broken pass.
-- Tying that to the schema stamp meant a migration per bug; a revision constant re-arms on the next
-- login when it is bumped, and stays a no-op otherwise. Bump it whenever the repair's *judgment*
-- changes — not when unrelated code moves.
--   1  the original: read the bind type alone, which lies for warbound caches (reports OnEquip)
--   2  read both signals, and treat only a readable tooltip as settling a row
--   3  don't count RETRIEVING_ITEM_INFO as a readable tooltip, and require the item data cached
--   4  match bind wordings as whole lines: "Warbound Cache of …" is an item NAME, and a substring
--      match hit it on line 1, settling the row as plain warbound before the real bind line
local BOUND_REPAIR_REVISION = 4
function NS:ArmBoundRepair(g)
  g = g or (NS.db and NS.db.global)
  if not g then return false end
  if g.boundRepairRevision == BOUND_REPAIR_REVISION then return false end
  g.boundRepairRevision = BOUND_REPAIR_REVISION
  g.boundRepairPending, g.boundRepairAttempts = true, nil
  if NS.State.debug and NS.Debug then
    NS.Debug("Migrate", "bound repair armed (revision %s)", tostring(BOUND_REPAIR_REVISION))
  end
  return true
end

-- Pure migration summary for the [Migrate] line.
function NS.MigrationSummary(from, to, rows)
  return ("v%s -> v%s, %s rows touched"):format(tostring(from), tostring(to), tostring(rows))
end

-- Pure [Init] session summary for the SetEnabled seam (debug-logging-§5/§8): addon name + version,
-- schema/DB version, active profile, and record count — e.g.
-- "LootHistory v1.1.0, schema v2, profile 'Default', 1423 records".
-- Guarded so it can't error before the DB is ready (db.global / GetCurrentProfile may be absent).
-- All values are plain constants/counts, so a raw tostring is secret-safe here.
function NS.InitSummary()
  local g = NS.db and NS.db.global
  local schema = (g and g.schemaVersion) or 0
  local profile = (NS.db and NS.db.GetCurrentProfile and NS.db:GetCurrentProfile()) or "?"
  local records = (g and g.history and #g.history) or 0
  return ("%s v%s, schema v%s, profile '%s', %s records"):format(
    tostring(NS.name), tostring(NS.version), tostring(schema), tostring(profile), tostring(records))
end

NS.Database = NS.Database or {}
local Database = NS.Database

-- How many *fruitless* passes the WARBAND repair gets before it gives up (two run per login, plus
-- one per window open). An id the client never resolves — a removed item — would otherwise keep the
-- job pending for the life of the DB.
local BOUND_REPAIR_MAX_ATTEMPTS = 10

-- Rows examined per pass. Each one costs a GetItemInfo plus a tooltip build, and a large history
-- has hundreds of candidates — enough to be felt as a hitch on the frame that opens the window.
-- Whatever the budget doesn't reach stays pending and is picked up by the next pass.
local BOUND_REPAIR_PER_PASS = 200

-- Deferred half of the v6->v9 migration: raise every under-classified row to the warbound state it
-- really has. Candidates are the parked WARBAND rows and the BOE rows — BOE because the bind type
-- lies about these items (a warbound cache reports 2/OnEquip), so a capture that trusted it filed
-- them one state too loose. Each row is re-read through Compat.ItemBindState (both signals) and
-- merged with BestBound, which only ever moves a row toward the more specific warbound state — a
-- genuine BoE reads back BOE and stays put. A row the client can't answer for at all is requested
-- and left for the next pass; the job clears once none remain, or after BOUND_REPAIR_MAX_ATTEMPTS
-- fruitless passes. Candidates need an id OR a link, so a row missing one is repaired by the other.
-- Returns fixed, pending, candidates (for the tests and the debug line).
local REPAIR_CANDIDATE = { WARBAND = true, BOE = true }
function Database:RepairBoundStates()
  local g = NS.db and NS.db.global
  if not (g and g.boundRepairPending) then return 0, 0, 0 end
  local fixed, pending, candidates, examined = 0, 0, 0, 0
  for _, r in ipairs(g.history or {}) do
    if REPAIR_CANDIDATE[r.bound] and (r.itemID or r.itemLink) then
      candidates = candidates + 1
      if examined >= BOUND_REPAIR_PER_PASS then
        pending = pending + 1     -- past the per-pass budget: not looked at, so not resolved
      else
        examined = examined + 1
        local state, settled = NS.Compat.ItemBindState(r.itemID or r.itemLink, r.itemLink)
        if not settled then
          -- Unsettled means the TOOLTIP wasn't readable. A bind type of BOE is not evidence the
          -- row isn't warbound (it lies for these items), so it must not end the row's retries.
          pending = pending + 1
          NS.Compat.LoadItem(r.itemID)   -- warm the cache so the next pass can answer
        else
          local merged = NS.Compat.BestBound(r.bound, state)
          if merged ~= r.bound then
            r.bound = merged
            fixed = fixed + 1
          end
        end
      end
    end
  end
  -- The cap counts *fruitless* passes, not passes: a run that fixed something proves the client is
  -- answering, so the job has earned its full budget again for whatever is still unresolved.
  g.boundRepairAttempts = fixed > 0 and 0 or (g.boundRepairAttempts or 0) + 1
  if pending == 0 or g.boundRepairAttempts >= BOUND_REPAIR_MAX_ATTEMPTS then
    g.boundRepairPending, g.boundRepairAttempts = nil, nil
  end
  if NS.State.debug and NS.Debug then
    NS.Debug("Migrate", "bound repair: %s fixed, %s pending, %s candidates (attempt %s)",
      tostring(fixed), tostring(pending), tostring(candidates), tostring(g.boundRepairAttempts or 0))
  end
  -- The window can already be open when a pass lands, and it renders the bound column off these
  -- rows — repaint it rather than leave stale locks until the next open.
  if fixed > 0 and NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_HistoryChanged") end
  return fixed, pending, candidates
end


function Database:History()
  return NS.db.global.history
end

-- The dataset every read-path query (Query/Stats/Export, and thus the table + Insights tab)
-- resolves against. In Browser test mode this is the synthetic preview dataset published to
-- State by BrowserTable:ToggleTestMode; otherwise it is the live account-wide history. Filtering
-- is point-in-time (decided at capture) — reads never hide stored rows.
function Database:ActiveHistory()
  return (NS.State and NS.State.testRecords) or NS.db.global.history
end

function Database:Count()
  return #NS.db.global.history
end

-- Append a record to the account-wide history; fire RecordAdded; return its index.
function Database:Add(record)
  local history = NS.db.global.history
  history[#history + 1] = record
  local index = #history
  if NS.bus then
    NS.bus:SendMessage("Ka0s_LootHistory_RecordAdded", record, index)
  end
  return index
end

-- Filter an arbitrary record array by the filter spec. Fields, all optional (AND-combined).
-- source/char/itemType/zone each accept a scalar (equality) OR a set table (membership, for
-- the Browser's multi-select filters); quality accepts a number (EXACT match) or a set table.
--   quality · source · char · itemType · zone · from/to (ts, inclusive) · text (case-
--   insensitive substring on itemName). Empty/nil filter returns all.
-- `zone` matches the zone NAME, not mapID: one named zone spans many UiMapIDs (each dungeon floor
-- and sub-map carries its own), so an id-keyed filter splits a single zone into several. A record
-- with no captured name matches the empty string — the "Unknown" bucket.
-- Kept generic (not tied to the live history) so the Browser can filter its test dataset too.
function Database:QueryList(records, filter)
  filter = filter or {}
  -- A numeric quality matches that quality exactly; a set table matches any listed quality
  -- (multi-select). Anything else (e.g. a stray "all" sentinel) is ignored so it can never
  -- crash the comparison below and take the window with it.
  local qIsSet = type(filter.quality) == "table"
  local qExact = type(filter.quality) == "number" and filter.quality or nil
  local src = filter.source
  local srcIsSet = type(src) == "table"
  local char = filter.char
  local charIsSet = type(char) == "table"
  local itype = filter.itemType
  local itypeIsSet = type(itype) == "table"
  local isub = filter.itemSubType
  local isubIsSet = type(isub) == "table"
  local zone = filter.zone
  local zoneIsSet = type(zone) == "table"
  local boundSet = type(filter.bound) == "table" and filter.bound or nil
  local from = filter.from
  local to = filter.to
  local text = filter.text and filter.text:lower() or nil

  local out = {}
  for _, r in ipairs(records) do
    local ok = true
    if qIsSet then
      if not filter.quality[r.quality] then ok = false end
    elseif qExact and (r.quality or 0) ~= qExact then
      ok = false
    end
    if ok and src then
      if srcIsSet then
        if not src[r.source] then ok = false end
      elseif r.source ~= src then
        ok = false
      end
    end
    if ok and char then
      if charIsSet then if not char[r.char] then ok = false end
      elseif r.char ~= char then ok = false end
    end
    if ok and itype then
      if itypeIsSet then if not itype[r.itemType] then ok = false end
      elseif r.itemType ~= itype then ok = false end
    end
    if ok and isub then
      if isubIsSet then if not isub[r.itemSubType] then ok = false end
      elseif r.itemSubType ~= isub then ok = false end
    end
    if ok and zone then
      local name = r.zone or ""
      if zoneIsSet then if not zone[name] then ok = false end
      elseif name ~= zone then ok = false end
    end
    if ok and boundSet and not boundSet[r.bound or "NONE"] then ok = false end
    if ok and from and (r.ts or 0) < from then ok = false end
    if ok and to and (r.ts or 0) > to then ok = false end
    if ok and text then
      local name = r.itemName and r.itemName:lower() or ""
      if not name:find(text, 1, true) then ok = false end
    end
    if ok then out[#out + 1] = r end
  end
  return out
end

-- Query the active dataset (live history, or the test dataset in Browser test mode).
function Database:Query(filter)
  return self:QueryList(self:ActiveHistory(), filter)
end

-- Plain, metatable-free copy of the (optionally filtered) history — the forward-compatible
-- v2 export contract (see docs/data-model.md). Field shape is stable except for schema bumps
-- (v4 dropped the retired `sourceName`).
function Database:Export(filter)
  local out = {}
  for _, r in ipairs(self:Query(filter or {})) do
    out[#out + 1] = {
      ts = r.ts, char = r.char, classFile = r.classFile, itemID = r.itemID, currencyID = r.currencyID, itemLink = r.itemLink,
      itemName = r.itemName, quality = r.quality, itemLevel = r.itemLevel, bound = r.bound,
      vendorPrice = r.vendorPrice, auctionPrice = r.auctionPrice,
      itemType = r.itemType, itemSubType = r.itemSubType,
      quantity = r.quantity,
      source = r.source or "OTHER", sourceDetail = r.sourceDetail,
      zone = r.zone, mapID = r.mapID, subzone = r.subzone, confidence = r.confidence,
    }
  end
  return out
end

-- Aggregate the (optionally filtered) history in one O(n) pass. Returns count maps, value maps,
-- per-character/type/bound/time breakdowns, pre-sorted top lists, and totals/highlights — the
-- struct all Insights widgets consume (see docs/browser.md). "Value" is the derived value: (auctionPrice or vendorPrice) × quantity
-- (captured at loot time). New fields are additive.
function Database:Stats(filter)
  local records = self:Query(filter or {})
  local bySource, byQuality, byDay, byZone, byItem = {}, {}, {}, {}, {}
  local valueBySource, valueByDay, valueByZone = {}, {}, {}
  local byChar, byType, byBound, byHour, byWeekday, byKeystone, byConfidence =
    {}, {}, {}, {}, {}, {}, {}
  -- Per-character × category matrices (feed the "… by Character" stacked companion charts). Each
  -- mirrors its parent aggregation's guards; { [charKey] = { [categoryKey] = magnitude } }.
  local charBySource, charValueBySource, charByQuality, charByType, charByBound =
        {}, {}, {}, {}, {}
  local distinctItems, distinctChars = 0, 0
  local firstTs, lastTs
  local totalValue, totalQuantity, epicPlus = 0, 0, 0
  local bestDrop, richestDrop
  local byCurrency, currencySourceMatrix, currencyByChar, currencyByDay = {}, {}, {}, {}
  local currencyCharMatrix = {}
  local currencyDistinct, currencyEvents = 0, 0
  local biggestHaul
  local currencyBySource = {}

  -- Nested-table increment used by the per-character category matrices.
  local function bump(matrix, k1, k2, amt)
    if k1 == nil or k2 == nil then return end
    local m = matrix[k1]; if not m then m = {}; matrix[k1] = m end
    m[k2] = (m[k2] or 0) + amt
  end

  for _, r in ipairs(records) do
    local qty = r.quantity or 1
    local value = (NS.Util.RecordValue(r) or 0) * qty
    local isCurrency = r.currencyID ~= nil
    totalValue = totalValue + value
    totalQuantity = totalQuantity + qty

    local ch = r.char

    -- Loot-by-source / value / per-character charts are items-only: currency has its own CURRENCY
    -- section, so counting it here would make per-character totals disagree with the item-attribute
    -- companions (Bound/Quality/Type by Character). `src` is still read below for the currency charts.
    local src = r.source or "OTHER"
    if not isCurrency then
      bySource[src] = (bySource[src] or 0) + 1
      valueBySource[src] = (valueBySource[src] or 0) + value
      bump(charBySource, ch, src, 1)
      bump(charValueBySource, ch, src, value)
    end

    if not isCurrency then
      local q = r.quality or 0
      byQuality[q] = (byQuality[q] or 0) + 1
      bump(charByQuality, ch, q, 1)
      if q >= 4 then epicPlus = epicPlus + 1 end
    end

    if r.ts then
      local day = date("%Y-%m-%d", r.ts)
      byDay[day] = (byDay[day] or 0) + 1
      valueByDay[day] = (valueByDay[day] or 0) + value
      local d = date("*t", r.ts)
      byHour[d.hour] = (byHour[d.hour] or 0) + 1
      byWeekday[d.wday - 1] = (byWeekday[d.wday - 1] or 0) + 1  -- Lua wday 1=Sun → key 0=Sun
      if not firstTs or r.ts < firstTs then firstTs = r.ts end
      if not lastTs or r.ts > lastTs then lastTs = r.ts end
    end

    -- "" (what Compat.GetZone answers with no zone text yet) buckets with nil, matching the Zone
    -- filter's single Unknown option — otherwise a blank-labeled row sits beside Unknown.
    local zone = (r.zone ~= nil and r.zone ~= "" and r.zone) or "Unknown"
    byZone[zone] = (byZone[zone] or 0) + 1
    valueByZone[zone] = (valueByZone[zone] or 0) + value

    if not isCurrency then
      local ty = r.itemType
      if ty and ty ~= "" then byType[ty] = (byType[ty] or 0) + 1; bump(charByType, ch, ty, 1) end
    end

    if not isCurrency then
      local bk = r.bound or "UNBOUND"
      byBound[bk] = (byBound[bk] or 0) + 1
      bump(charByBound, ch, bk, 1)
    end

    local conf = r.confidence or "INFERRED"
    byConfidence[conf] = (byConfidence[conf] or 0) + 1

    local kl = r.sourceDetail and r.sourceDetail.keystoneLevel
    if kl then byKeystone[kl] = (byKeystone[kl] or 0) + 1 end

    if not isCurrency then
      local id = r.itemID
      if id ~= nil then
        local e = byItem[id]
        if e then
          e.count = e.count + 1
          e.value = e.value + value
        else
          byItem[id] = { itemID = id, itemName = r.itemName, quality = r.quality,
                         count = 1, value = value }
          distinctItems = distinctItems + 1
        end
      end
    end

    if ch then
      -- Register every character (for the class-color lookup + the "characters" KPI), but count and
      -- value only their items — "Loot by character" is items-only so it tallies with the item charts.
      local ce = byChar[ch]
      if not ce then
        ce = { char = ch, classFile = r.classFile, count = 0, value = 0 }
        byChar[ch] = ce
        distinctChars = distinctChars + 1
      end
      if not isCurrency then
        ce.count = ce.count + 1
        ce.value = ce.value + value
      end
    end

    if isCurrency then
      currencyEvents = currencyEvents + 1
      local cname = r.itemName or ("currency " .. tostring(r.currencyID))
      if byCurrency[cname] == nil then currencyDistinct = currencyDistinct + 1 end
      byCurrency[cname] = (byCurrency[cname] or 0) + qty

      local m = currencySourceMatrix[cname]
      if not m then m = {}; currencySourceMatrix[cname] = m end
      m[src] = (m[src] or 0) + qty

      currencyBySource[src] = (currencyBySource[src] or 0) + qty

      if r.char then
        local cc = currencyByChar[r.char]
        if cc then cc.quantity = cc.quantity + qty
        else currencyByChar[r.char] = { char = r.char, classFile = r.classFile, quantity = qty } end
        bump(currencyCharMatrix, r.char, cname, qty)
      end

      if r.ts then
        local cday = date("%Y-%m-%d", r.ts)
        currencyByDay[cday] = (currencyByDay[cday] or 0) + qty
      end

      if not biggestHaul or qty > biggestHaul.quantity then
        biggestHaul = { name = cname, quantity = qty }
      end
    end

    if not isCurrency then
      -- Highlights: best gear (max itemLevel, ties → higher quality) + richest single drop.
      local ilvl = r.itemLevel or 0
      if ilvl > 0 and (not bestDrop or ilvl > bestDrop.itemLevel
          or (ilvl == bestDrop.itemLevel and (r.quality or 0) > (bestDrop.quality or 0))) then
        bestDrop = { itemName = r.itemName, quality = r.quality, itemLevel = ilvl, itemLink = r.itemLink }
      end
      if value > 0 and (not richestDrop or value > richestDrop.value) then
        richestDrop = { itemName = r.itemName, quality = r.quality, value = value, itemLink = r.itemLink }
      end
    end
  end

  local topZones = {}
  for zone, count in pairs(byZone) do
    topZones[#topZones + 1] = { zone = zone, count = count, value = valueByZone[zone] or 0 }
  end
  table.sort(topZones, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.zone < b.zone
  end)

  -- topItems and topItemsByValue share the same entry tables (from byItem) — two orderings.
  local topItems, topItemsByValue = {}, {}
  for _, e in pairs(byItem) do
    topItems[#topItems + 1] = e
    topItemsByValue[#topItemsByValue + 1] = e
  end
  table.sort(topItems, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
    return (a.itemID or 0) < (b.itemID or 0)
  end)
  table.sort(topItemsByValue, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    if a.count ~= b.count then return a.count > b.count end
    return (a.itemID or 0) < (b.itemID or 0)
  end)

  local activeDays, busiestDay = 0, nil
  for day, count in pairs(byDay) do
    activeDays = activeDays + 1
    if not busiestDay or count > busiestDay.count then busiestDay = { day = day, count = count } end
  end

  return {
    bySource = bySource, byQuality = byQuality, byDay = byDay,
    byZone = byZone, byItem = byItem, topZones = topZones,
    topItems = topItems, topItemsByValue = topItemsByValue,
    valueBySource = valueBySource, valueByDay = valueByDay, valueByZone = valueByZone,
    byChar = byChar, byType = byType, byBound = byBound,
    byHour = byHour, byWeekday = byWeekday, byKeystone = byKeystone, byConfidence = byConfidence,
    charBySource = charBySource, charValueBySource = charValueBySource, charByQuality = charByQuality,
    charByType = charByType, charByBound = charByBound,
    byCurrency = byCurrency, currencySourceMatrix = currencySourceMatrix,
    currencyByChar = currencyByChar, currencyByDay = currencyByDay,
    currencyCharMatrix = currencyCharMatrix,
    currencyBySource = currencyBySource,
    currencyTotals = { distinct = currencyDistinct, events = currencyEvents, biggestHaul = biggestHaul },
    totals = {
      records = #records, distinctItems = distinctItems, distinctChars = distinctChars,
      firstTs = firstTs, lastTs = lastTs,
      totalValue = totalValue, totalQuantity = totalQuantity,
      activeDays = activeDays, busiestDay = busiestDay,
      epicPlus = epicPlus, bestDrop = bestDrop, richestDrop = richestDrop,
    },
  }
end

local function fireHistoryChanged()
  if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_HistoryChanged") end
end

-- Public HistoryChanged emitter for non-Database owners of a visible-history change (the
-- blacklist/whitelist lists in NS.Filters call this after mutating db.global). Keeps Database the
-- single sending module for this message (message-bus's one-sender-per-message invariant).
function Database:FireHistoryChanged()
  fireHistoryChanged()
end

-- Delete every record for which pred(record) is true. Rebuild-and-swap (no holes).
-- Returns the number removed; fires HistoryChanged.
function Database:Delete(pred)
  local history = NS.db.global.history
  local kept, removed = {}, 0
  for _, r in ipairs(history) do
    if pred(r) then
      removed = removed + 1
    else
      kept[#kept + 1] = r
    end
  end
  NS.db.global.history = kept
  fireHistoryChanged()
  return removed
end

-- Wipe all history (the /lh purge command). Fires HistoryChanged. Returns the count removed.
function Database:Purge()
  local removed = #NS.db.global.history
  NS.db.global.history = {}
  fireHistoryChanged()
  if NS.State.debug and NS.Debug then
    NS.Debug("Data", "purge-all removed %s rows", tostring(removed))
  end
  return removed
end

-- Rough per-record byte cost as written to the SavedVariables .lua file. WoW gives addons
-- no way to read the real on-disk file size, so we estimate: a fixed overhead covering the
-- record's key names, table syntax, and numeric fields, plus the length of each string field.
local RECORD_OVERHEAD = 256
local function estimateRecordBytes(r)
  local n = RECORD_OVERHEAD
  local strFields = { r.itemLink, r.itemName,
                      r.zone, r.subzone, r.char, r.itemType, r.itemSubType }
  for _, s in ipairs(strFields) do
    if type(s) == "string" then n = n + #s end
  end
  return n
end

-- Storage summary for the settings panel: record count, span in days since the earliest
-- record, and an ESTIMATED SavedVariables byte size (see estimateRecordBytes). `now` is
-- injectable for tests; it defaults to time().
function Database:StorageStats(now)
  local history = NS.db.global.history
  local firstTs, bytes = nil, 0
  for _, r in ipairs(history) do
    if r.ts and (not firstTs or r.ts < firstTs) then firstTs = r.ts end
    bytes = bytes + estimateRecordBytes(r)
  end
  local days = 0
  if firstTs then
    now = now or time()
    days = math.max(1, math.ceil((now - firstTs) / 86400))
  end
  return { count = #history, days = days, bytes = bytes }
end

-- Retention cleanup. Drops records older than settings.retentionDays (0 == Never).
-- Rebuild-and-swap avoids O(n^2) shifting and array holes. Fires HistoryChanged when it runs.
function Database:PruneOld()
  local days = NS.db.global.settings.retentionDays
  if not days or days == 0 then return 0 end
  local cutoff = time() - days * 86400
  local history = NS.db.global.history
  local kept = {}
  for _, r in ipairs(history) do
    if (r.ts or 0) >= cutoff then kept[#kept + 1] = r end
  end
  local removed = #history - #kept
  NS.db.global.history = kept
  fireHistoryChanged()
  if NS.State.debug and NS.Debug then
    NS.Debug("Prune", "retention %sd: removed %s rows", tostring(days), tostring(removed))
  end
  return removed
end
