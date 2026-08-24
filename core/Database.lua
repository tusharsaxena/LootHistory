local addonName, NS = ...

-- AceDB init. Account-wide: all history + settings live in NS.db.global.
function NS:InitDB()
  NS.db = LibStub("AceDB-3.0"):New("LootHistoryDB", NS.defaults, true)
  NS:RunMigrations()   -- normalize the persisted schema before any history read
end

-- The [Migrate] line every step emits, in one place — the tail was written out once per step and
-- is pure formatting, so it has no business being part of a step's body.
local function migrateLog(from, to, n)
  if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(from, to, n)) end
end

-- The schema-upgrade chain, in ascending order — one entry per step, `to` being the version the
-- step stamps once it has run. Each `apply(g)` mutates db.global in place and returns the number
-- of rows it touched (for the [Migrate] line). Array order IS the run order: a step sees every
-- earlier step's output, so entries are appended, never reordered.
local MIGRATIONS = {
  -- v1 -> v2: point-in-time filtering (removed soft-add/soft-delete). Strip the retired
  -- per-record `viaWhitelist` flag; rows are never hidden/resurrected after capture. Non-
  -- destructive — no rows are deleted (see docs/superpowers/specs/2026-07-18-*).
  { to = 2, apply = function(g)
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.viaWhitelist ~= nil then r.viaWhitelist = nil; n = n + 1 end
    end
    return n
  end },

  -- v2 -> v3: rename per-record sellPrice -> vendorPrice (non-destructive; value preserved).
  { to = 3, apply = function(g)
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.sellPrice ~= nil then r.vendorPrice = r.sellPrice; r.sellPrice = nil; n = n + 1 end
    end
    return n
  end },

  -- v3 -> v4: backfill currency-record quality (rows with currencyID but no quality) from
  -- C_CurrencyInfo, so the History browser can color the currency name + fill the Quality column
  -- for currencies looted before quality was captured. In-game only (C_CurrencyInfo); a currency the
  -- client can't resolve at init stays nil. Non-destructive.
  { to = 4, apply = function(g)
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.currencyID and r.quality == nil then
        local q = NS.Compat.CurrencyQuality(r.currencyID)
        if q ~= nil then r.quality = q; n = n + 1 end
      end
    end
    return n
  end },

  -- v4 -> v5: backfill currency-record bound (rows with currencyID but no bound) from C_CurrencyInfo —
  -- "WARBAND" for a Warband-transferable currency, else "BOP" — so the History browser shows the bound
  -- glyph for currencies looted before bound was captured. In-game only (C_CurrencyInfo); a currency
  -- the client can't resolve at init stays nil. Non-destructive.
  { to = 5, apply = function(g)
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.currencyID and r.bound == nil then
        local b = NS.Compat.CurrencyBound(r.currencyID)
        if b ~= nil then r.bound = b; n = n + 1 end
      end
    end
    return n
  end },

  -- v5 -> v6: retire the "ACCOUNT" bind state, splitting warbound into WARBAND / WARBAND_UE.
  -- Retail has had no account-bound wording distinct from Warbound since 11.0 (every
  -- ITEM_*ACCOUNTBOUND* global reads "Warbound"), and the old scanner filed *all* warbound loot
  -- under ACCOUNT because "Binds to Warband" sat in its account list — so every stored ACCOUNT row
  -- is a mislabeled warbound drop of one kind or the other. Which kind isn't recoverable from the
  -- record, so park every such row on the plain WARBAND state and let the deferred repair below
  -- (RepairBoundStates) split it once the client can answer. Any saved Bound filter naming the
  -- retired token follows too, else the view would match nothing. Non-destructive.
  { to = 6, apply = function(g)
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.bound == "ACCOUNT" then r.bound = "WARBAND"; n = n + 1 end
    end
    local view = g.savedView
    if type(view) == "table" and type(view.bound) == "table" and view.bound.ACCOUNT then
      view.bound.ACCOUNT = nil
      view.bound.WARBAND, view.bound.WARBAND_UE = true, true
    end
    return n
  end },

  -- v6 -> v7: hand the warbound split to the deferred repair below. It can't be done inline —
  -- migrations run from InitDB at ADDON_LOADED with a cold item cache, so a one-shot pass here
  -- learns nothing and then bumps the stamp, burning the only chance to fix anything.
  { to = 7, apply = function()
    return 0
  end },

  -- v7 -> v8: the Zone filter moved from mapID to the zone NAME (one named zone spans many
  -- UiMapIDs — every dungeon floor has its own — so the id-keyed menu listed a zone once per
  -- floor and each entry filtered only part of it). Translate a saved view's mapID set into the
  -- names those ids were recorded under, else the stored view would filter on a field nothing
  -- reads and silently show everything. Ids absent from the history resolve to nothing and drop.
  { to = 8, apply = function(g)
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
    return n
  end },
}

-- Schema-migration runner (toc-file-§2 / savedvariables-§1). Reads/writes db.global.schemaVersion and
-- ships even with an effectively empty body — the *seam* is the requirement: future schema
-- changes get a single, idempotent upgrade path invoked once at init, before any read of
-- db.global.history. Safe no-op when the DB isn't ready yet.
-- The stamp is written AFTER apply() and only for steps that actually ran, so an error mid-chain
-- can never advance the version past unapplied work.
function NS:RunMigrations()
  local g = NS.db and NS.db.global
  if not g then return end
  g.schemaVersion = g.schemaVersion or 1
  for i = 1, #MIGRATIONS do
    local m = MIGRATIONS[i]
    if g.schemaVersion < m.to then
      local n = m.apply(g) or 0
      g.schemaVersion = m.to
      migrateLog(m.to - 1, m.to, n)
    end
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

-- Re-read one candidate row and merge the answer in. Returns "fixed" when the row moved, "pending"
-- when the client couldn't answer yet, and nil when the row was settled but already correct — that
-- third case counts toward `candidates` alone, which is what lets the job clear.
local function examineRow(r)
  local state, settled = NS.Compat.ItemBindState(r.itemID or r.itemLink, r.itemLink)
  if not settled then
    -- Unsettled means the TOOLTIP wasn't readable. A bind type of BOE is not evidence the
    -- row isn't warbound (it lies for these items), so it must not end the row's retries.
    NS.Item.LoadItem(r.itemID)   -- warm the cache so the next pass can answer
    return "pending"
  end
  local merged = NS.Compat.BestBound(r.bound, state)
  if merged ~= r.bound then
    r.bound = merged
    return "fixed"
  end
end

-- One pass over the history: pick the candidates, spend the per-pass budget on them, and tally.
-- Returns fixed, pending, candidates.
local function scanRows(g)
  local fixed, pending, candidates, examined = 0, 0, 0, 0
  for _, r in ipairs(g.history or {}) do
    if REPAIR_CANDIDATE[r.bound] and (r.itemID or r.itemLink) then
      candidates = candidates + 1
      if examined >= BOUND_REPAIR_PER_PASS then
        pending = pending + 1     -- past the per-pass budget: not looked at, so not resolved
      else
        examined = examined + 1
        local outcome = examineRow(r)
        if outcome == "pending" then pending = pending + 1
        elseif outcome == "fixed" then fixed = fixed + 1 end
      end
    end
  end
  return fixed, pending, candidates
end

-- Pass bookkeeping: the fruitless-attempt counter, the give-up/done clear, and the debug line.
local function finishPass(g, fixed, pending, candidates)
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
end

function Database:RepairBoundStates()
  local g = NS.db and NS.db.global
  if not (g and g.boundRepairPending) then return 0, 0, 0 end
  local fixed, pending, candidates = scanRows(g)
  finishPass(g, fixed, pending, candidates)
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
--
-- QueryList is the read path's hot loop: every filter change in the Browser re-runs it over the
-- whole history. The rule the helpers below exist to respect is that NOTHING loop-invariant may
-- be re-derived per record — not a `type()` test, not a `filter.<field>` lookup, not the decision
-- that a clause is unfiltered, and not a per-clause helper call. QueryList hoists all of it into
-- locals once per call and hands the results down as arguments; the helpers only ever touch `r`
-- and those arguments. A descriptor table walked per record would put that work straight back
-- into the loop, which is what this shape is guarding against.

-- Normalize one scalar-or-set clause into a membership set, ONCE PER CALL. A set filter is used
-- as it stands; a scalar becomes a one-key set, so the per-record test is a single table lookup —
-- no `type()`, no branch on which form the clause took, and no nested helper call. An unfiltered
-- clause stays nil, so the loop skips it on one local test; the falsy filter values master also
-- read as unfiltered (`false`) still do.
-- The table built here is per QUERY, never per record: QueryList runs once per filter change and
-- then walks the whole history.
local function membershipSet(want)
  if not want then return nil end
  if type(want) == "table" then return want end
  return { [want] = true }
end

-- A numeric quality matches that quality exactly; a set table matches any listed quality
-- (multi-select). Anything else (e.g. a stray "all" sentinel) is ignored so it can never
-- crash the comparison and take the window with it.
-- The two forms differ on a record with no quality: the exact form reads it as 0, the set form
-- looks the raw nil up and misses. That asymmetry is the shipped behavior — do not "unify" it.
local function matchQuality(r, qSet, qExact)
  if qSet then return qSet[r.quality] end
  if qExact then return (r.quality or 0) == qExact end
  return true
end

-- The clauses that accept a scalar (equality) OR a set table (membership), in the order they were
-- tested when each was written out by hand. Every argument arrives as a membership set (or nil for
-- an unfiltered clause), so a clause costs one local test and at most one lookup — no nested call.
-- `zone` is the only one with a default: a record with no captured name matches "" — the
-- "Unknown" bucket.
local function matchScalarOrSet(r, srcSet, chrSet, itypeSet, isubSet, zoneSet)
  if srcSet and not srcSet[r.source] then return false end
  if chrSet and not chrSet[r.char] then return false end
  if itypeSet and not itypeSet[r.itemType] then return false end
  if isubSet and not isubSet[r.itemSubType] then return false end
  if zoneSet and not zoneSet[r.zone or ""] then return false end
  return true
end

-- The clauses with no scalar form: bound is set-only (a non-table bound filter is ignored), the
-- ts window is inclusive on both ends, and `text` arrives already lowered — once per call, never
-- per record.
local function matchRange(r, boundSet, from, to, text)
  if boundSet and not boundSet[r.bound or "NONE"] then return false end
  if from and (r.ts or 0) < from then return false end
  if to and (r.ts or 0) > to then return false end
  if text then
    local name = r.itemName and r.itemName:lower() or ""
    if not name:find(text, 1, true) then return false end
  end
  return true
end

-- Compile a filter into a query plan, ONCE PER CALL. Every clause is normalized to the exact form
-- the loop wants — a membership set, a number, or nil for unfiltered — and each of the three groups
-- carries a flag saying whether anything in it is filtered at all, so an unfiltered group costs one
-- local test per record instead of a call.
--
-- This is where the "nothing loop-invariant may be re-derived per record" rule is ENFORCED rather
-- than merely observed: a derivation that lives in this function cannot be per record, because this
-- function does not see a record. QueryList below is then only the loop.
--
-- The `any*` flags stay plain `or` chains here rather than going through a helper. A three-line
-- `anyFiltered(a, b, c, d, e)` returning `a or b or c or d or e` would move eight decisions out of
-- whatever function held it and buy nothing at runtime — it is called three times per query, not
-- per record. Complexity moved is not complexity removed (performance-§11, anti-pattern #52).
local function compileFilter(filter)
  local q = filter.quality
  local p = {
    qSet     = type(q) == "table" and q,
    qExact   = type(q) == "number" and q,
    srcSet   = membershipSet(filter.source),
    chrSet   = membershipSet(filter.char),
    itypeSet = membershipSet(filter.itemType),
    isubSet  = membershipSet(filter.itemSubType),
    zoneSet  = membershipSet(filter.zone),
    boundSet = type(filter.bound) == "table" and filter.bound,
    from     = filter.from,
    to       = filter.to,
    text     = filter.text and filter.text:lower(),
  }
  p.anyQ      = p.qSet or p.qExact
  p.anyScalar = p.srcSet or p.chrSet or p.itypeSet or p.isubSet or p.zoneSet
  p.anyRange  = p.boundSet or p.from or p.to or p.text
  return p
end

function Database:QueryList(records, filter)
  local p = compileFilter(filter or {})

  -- Hoist the plan into locals BEFORE the loop. These are plain assignments carrying no decisions,
  -- so they cost nothing in complexity — and they keep every per-record read an upvalue read rather
  -- than a hash lookup on `p`. Measured over the whole history that is worth 20-40% on a filtered
  -- query; reading `p.anyScalar` per record instead was the one shape that made this loop slower
  -- than the flat version it replaced.
  local anyQ, anyScalar, anyRange = p.anyQ, p.anyScalar, p.anyRange
  local qSet, qExact = p.qSet, p.qExact
  local srcSet, chrSet, itypeSet, isubSet, zoneSet = p.srcSet, p.chrSet, p.itypeSet, p.isubSet, p.zoneSet
  local boundSet, from, to, text = p.boundSet, p.from, p.to, p.text

  local out = {}
  for _, r in ipairs(records) do
    if (not anyQ or matchQuality(r, qSet, qExact))
        and (not anyScalar or matchScalarOrSet(r, srcSet, chrSet, itypeSet, isubSet, zoneSet))
        and (not anyRange or matchRange(r, boundSet, from, to, text)) then
      out[#out + 1] = r
    end
  end
  return out
end

-- Query the active dataset (live history, or the test dataset in Browser test mode).
function Database:Query(filter)
  return self:QueryList(self:ActiveHistory(), filter)
end

-- Plain, metatable-free copy of the (optionally filtered) history — the forward-compatible
-- v2 export contract (see docs/schema.md). Field shape is stable except for schema bumps
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

-- Nested-table increment used by the per-character category matrices.
local function bump(matrix, k1, k2, amt)
  if k1 == nil or k2 == nil then return end
  local m = matrix[k1]; if not m then m = {}; matrix[k1] = m end
  m[k2] = (m[k2] or 0) + amt
end

-- One bucket set for a single Stats() pass. Every field below is written by exactly one of the
-- accumulate* helpers that follow, which is the property that lets them be read independently:
-- adding a breakdown means one field here and one line in its helper, not a longer loop body.
local function newAccumulator()
  return {
    bySource = {}, byQuality = {}, byDay = {}, byZone = {}, byItem = {},
    valueBySource = {}, valueByDay = {}, valueByZone = {},
    byChar = {}, byType = {}, byBound = {}, byHour = {}, byWeekday = {},
    byKeystone = {}, byConfidence = {},
    -- Per-character × category matrices (feed the "… by Character" stacked companion charts). Each
    -- mirrors its parent aggregation's guards; { [charKey] = { [categoryKey] = magnitude } }.
    charBySource = {}, charValueBySource = {}, charByQuality = {},
    charByType = {}, charByBound = {},
    byCurrency = {}, currencySourceMatrix = {}, currencyByChar = {},
    currencyByDay = {}, currencyCharMatrix = {}, currencyBySource = {},
    distinctItems = 0, distinctChars = 0,
    currencyDistinct = 0, currencyEvents = 0,
    totalValue = 0, totalQuantity = 0, epicPlus = 0,
    firstTs = nil, lastTs = nil,
    bestDrop = nil, richestDrop = nil, biggestHaul = nil,
  }
end

-- Highlights: best gear (max itemLevel, ties → higher quality) + richest single drop. Ties keep the
-- record seen first, so these track the caller's record order.
local function accumulateHighlights(A, r, value)
  local ilvl = r.itemLevel or 0
  if ilvl > 0 and (not A.bestDrop or ilvl > A.bestDrop.itemLevel
      or (ilvl == A.bestDrop.itemLevel and (r.quality or 0) > (A.bestDrop.quality or 0))) then
    A.bestDrop = { itemName = r.itemName, quality = r.quality, itemLevel = ilvl, itemLink = r.itemLink }
  end
  if value > 0 and (not A.richestDrop or value > A.richestDrop.value) then
    A.richestDrop = { itemName = r.itemName, quality = r.quality, value = value, itemLink = r.itemLink }
  end
end

-- One item's contribution to the byItem roll-up, which is also where distinctItems is counted.
local function accumulateItemEntry(A, r, value)
  local id = r.itemID
  if id == nil then return end
  local e = A.byItem[id]
  if e then
    e.count = e.count + 1
    e.value = e.value + value
  else
    A.byItem[id] = { itemID = id, itemName = r.itemName, quality = r.quality,
                     count = 1, value = value }
    A.distinctItems = A.distinctItems + 1
  end
end

-- Item-attribute breakdowns and their per-character companions. Items only: currency has its own
-- CURRENCY section, so counting it here would make per-character totals disagree with the item
-- attribute companions (Bound/Quality/Type by Character).
local function accumulateItem(A, r, ch, src, value)
  A.bySource[src] = (A.bySource[src] or 0) + 1
  A.valueBySource[src] = (A.valueBySource[src] or 0) + value
  bump(A.charBySource, ch, src, 1)
  bump(A.charValueBySource, ch, src, value)

  local q = r.quality or 0
  A.byQuality[q] = (A.byQuality[q] or 0) + 1
  bump(A.charByQuality, ch, q, 1)
  if q >= 4 then A.epicPlus = A.epicPlus + 1 end

  local ty = r.itemType
  if ty and ty ~= "" then A.byType[ty] = (A.byType[ty] or 0) + 1; bump(A.charByType, ch, ty, 1) end

  local bk = r.bound or "UNBOUND"
  A.byBound[bk] = (A.byBound[bk] or 0) + 1
  bump(A.charByBound, ch, bk, 1)

  accumulateItemEntry(A, r, value)
  accumulateHighlights(A, r, value)
end

-- Day / hour / weekday buckets and the first-last timestamp span. Records with no ts contribute
-- to every other breakdown but not to these.
local function accumulateTime(A, r, value)
  if not r.ts then return end
  local day = date("%Y-%m-%d", r.ts)
  A.byDay[day] = (A.byDay[day] or 0) + 1
  A.valueByDay[day] = (A.valueByDay[day] or 0) + value
  local d = date("*t", r.ts)
  A.byHour[d.hour] = (A.byHour[d.hour] or 0) + 1
  A.byWeekday[d.wday - 1] = (A.byWeekday[d.wday - 1] or 0) + 1  -- Lua wday 1=Sun → key 0=Sun
  if not A.firstTs or r.ts < A.firstTs then A.firstTs = r.ts end
  if not A.lastTs or r.ts > A.lastTs then A.lastTs = r.ts end
end

-- Zone, confidence and keystone level — the breakdowns that count items and currency alike.
local function accumulateProvenance(A, r, value)
  -- "" (what NS.Zone answers with no zone text yet) buckets with nil, matching the Zone
  -- filter's single Unknown option — otherwise a blank-labeled row sits beside Unknown.
  local zone = (r.zone ~= nil and r.zone ~= "" and r.zone) or "Unknown"
  A.byZone[zone] = (A.byZone[zone] or 0) + 1
  A.valueByZone[zone] = (A.valueByZone[zone] or 0) + value

  local conf = r.confidence or "INFERRED"
  A.byConfidence[conf] = (A.byConfidence[conf] or 0) + 1

  local kl = r.sourceDetail and r.sourceDetail.keystoneLevel
  if kl then A.byKeystone[kl] = (A.byKeystone[kl] or 0) + 1 end
end

-- Register every character (for the class-color lookup + the "characters" KPI), but count and
-- value only their items — "Loot by character" is items-only so it tallies with the item charts.
local function accumulateChar(A, r, ch, isCurrency, value)
  if not ch then return end
  local ce = A.byChar[ch]
  if not ce then
    ce = { char = ch, classFile = r.classFile, count = 0, value = 0 }
    A.byChar[ch] = ce
    A.distinctChars = A.distinctChars + 1
  end
  if not isCurrency then
    ce.count = ce.count + 1
    ce.value = ce.value + value
  end
end

-- The CURRENCY section's own buckets, keyed by currency name rather than itemID.
local function accumulateCurrency(A, r, src, qty)
  A.currencyEvents = A.currencyEvents + 1
  local cname = r.itemName or ("currency " .. tostring(r.currencyID))
  if A.byCurrency[cname] == nil then A.currencyDistinct = A.currencyDistinct + 1 end
  A.byCurrency[cname] = (A.byCurrency[cname] or 0) + qty

  local m = A.currencySourceMatrix[cname]
  if not m then m = {}; A.currencySourceMatrix[cname] = m end
  m[src] = (m[src] or 0) + qty

  A.currencyBySource[src] = (A.currencyBySource[src] or 0) + qty

  if r.char then
    local cc = A.currencyByChar[r.char]
    if cc then cc.quantity = cc.quantity + qty
    else A.currencyByChar[r.char] = { char = r.char, classFile = r.classFile, quantity = qty } end
    bump(A.currencyCharMatrix, r.char, cname, qty)
  end

  if r.ts then
    local cday = date("%Y-%m-%d", r.ts)
    A.currencyByDay[cday] = (A.currencyByDay[cday] or 0) + qty
  end

  if not A.biggestHaul or qty > A.biggestHaul.quantity then
    A.biggestHaul = { name = cname, quantity = qty }
  end
end

-- The orderings and day rollup derived from the buckets once the pass is done.
local function derive(A)
  local topZones = {}
  for zone, count in pairs(A.byZone) do
    topZones[#topZones + 1] = { zone = zone, count = count, value = A.valueByZone[zone] or 0 }
  end
  table.sort(topZones, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.zone < b.zone
  end)

  -- topItems and topItemsByValue share the same entry tables (from byItem) — two orderings.
  local topItems, topItemsByValue = {}, {}
  for _, e in pairs(A.byItem) do
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
  for day, count in pairs(A.byDay) do
    activeDays = activeDays + 1
    if not busiestDay or count > busiestDay.count then busiestDay = { day = day, count = count } end
  end

  return topZones, topItems, topItemsByValue, activeDays, busiestDay
end

-- Aggregate the (optionally filtered) history in one O(n) pass. Returns count maps, value maps,
-- per-character/type/bound/time breakdowns, pre-sorted top lists, and totals/highlights — the
-- struct all Insights widgets consume (see docs/browser.md). "Value" is the derived value: (auctionPrice or vendorPrice) × quantity
-- (captured at loot time). New fields are additive.
--
-- The per-record work lives in the accumulate* helpers above, one per breakdown group. The single
-- pass is deliberate and load-bearing (docs/browser.md); the helpers split the *body*, not the pass.
function Database:Stats(filter)
  local records = self:Query(filter or {})
  local A = newAccumulator()

  for _, r in ipairs(records) do
    local qty = r.quantity or 1
    local value = (NS.Util.RecordValue(r) or 0) * qty
    local isCurrency = r.currencyID ~= nil
    local ch = r.char
    -- `src` is read for the currency charts too, which is why it is resolved out here.
    local src = r.source or "OTHER"

    A.totalValue = A.totalValue + value
    A.totalQuantity = A.totalQuantity + qty

    if isCurrency then
      accumulateCurrency(A, r, src, qty)
    else
      accumulateItem(A, r, ch, src, value)
    end
    accumulateTime(A, r, value)
    accumulateProvenance(A, r, value)
    accumulateChar(A, r, ch, isCurrency, value)
  end

  local topZones, topItems, topItemsByValue, activeDays, busiestDay = derive(A)

  return {
    bySource = A.bySource, byQuality = A.byQuality, byDay = A.byDay,
    byZone = A.byZone, byItem = A.byItem, topZones = topZones,
    topItems = topItems, topItemsByValue = topItemsByValue,
    valueBySource = A.valueBySource, valueByDay = A.valueByDay, valueByZone = A.valueByZone,
    byChar = A.byChar, byType = A.byType, byBound = A.byBound,
    byHour = A.byHour, byWeekday = A.byWeekday, byKeystone = A.byKeystone,
    byConfidence = A.byConfidence,
    charBySource = A.charBySource, charValueBySource = A.charValueBySource,
    charByQuality = A.charByQuality,
    charByType = A.charByType, charByBound = A.charByBound,
    byCurrency = A.byCurrency, currencySourceMatrix = A.currencySourceMatrix,
    currencyByChar = A.currencyByChar, currencyByDay = A.currencyByDay,
    currencyCharMatrix = A.currencyCharMatrix,
    currencyBySource = A.currencyBySource,
    currencyTotals = { distinct = A.currencyDistinct, events = A.currencyEvents,
                       biggestHaul = A.biggestHaul },
    totals = {
      records = #records, distinctItems = A.distinctItems, distinctChars = A.distinctChars,
      firstTs = A.firstTs, lastTs = A.lastTs,
      totalValue = A.totalValue, totalQuantity = A.totalQuantity,
      activeDays = activeDays, busiestDay = busiestDay,
      epicPlus = A.epicPlus, bestDrop = A.bestDrop, richestDrop = A.richestDrop,
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
