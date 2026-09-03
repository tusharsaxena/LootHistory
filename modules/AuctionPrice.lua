local addonName, NS = ...
NS.AuctionPrice = NS.AuctionPrice or {}
local AuctionPrice = NS.AuctionPrice

-- Reads AH prices for a just-looted item from installed pricing addons. Captures EVERY configured
-- price key into a nested map (provider -> key -> copper); a read-time Pick selects one via the
-- configurable priority list. Presence-gated + pcall-guarded per provider (third-party boundary —
-- deliberately not in core/Compat.lua).

-- One fetch per provider (batches that provider's captured keys). Each returns a { key = copper } sub-map
-- (only positive prices), or nil. `keys` is the set of key-names wanted for that provider.
local function fetchAuctionator(keys, itemLink, itemID)
  if not keys["minbuyout"] then return nil end
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not api then return nil end
  local price
  if itemID and api.GetAuctionPriceByItemID then price = api.GetAuctionPriceByItemID(addonName, itemID)
  elseif itemLink and api.GetAuctionPriceByItemLink then price = api.GetAuctionPriceByItemLink(addonName, itemLink) end
  if price and price > 0 then return { minbuyout = price } end
  return nil
end

local function fetchTSM(keys, itemLink)
  if not (TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString) then return nil end
  local itemStr = TSM_API.ToItemString(itemLink)
  if not itemStr then return nil end
  local out
  for key in pairs(keys) do
    local price = TSM_API.GetCustomPriceValue(key, itemStr)
    if price and price > 0 then out = out or {}; out[key] = price end
  end
  return out
end

local function fetchOribos(keys, itemLink, itemID)
  if type(OEMarketInfo) ~= "function" then return nil end
  local info = {}
  OEMarketInfo(itemLink or itemID, info)
  local out, any
  if keys["market"] and info.market and info.market > 0 then out = {}; out.market = info.market; any = true end
  if keys["region"] and info.region and info.region > 0 then
    out = out or {}; out.region = info.region; any = true
  end
  return any and out or nil
end

local PROVIDER_FETCH = { auctionator = fetchAuctionator, tsm = fetchTSM, oribos = fetchOribos }

local function cfg()
  local s = NS.db and NS.db.global and NS.db.global.settings and NS.db.global.settings.auction
  if s and s.enabled == false then return nil end
  local capture = (s and s.capture) or NS.Constants.AUCTION_CAPTURE_DEFAULT
  local priority = (s and s.priority) or NS.Constants.AUCTION_PRIORITY_DEFAULT
  return capture, priority
end

-- Group the capture set (tags) into { provider = { key = true } }.
local function wantedByProvider(capture)
  local out = {}
  for tag, on in pairs(capture) do
    if on then
      local prov, key = tag:match("^(.-):(.+)$")
      if prov and key then out[prov] = out[prov] or {}; out[prov][key] = true end
    end
  end
  return out
end

-- Capture every configured key. Returns { provider = { key = copper } } or nil if empty.
function AuctionPrice:GatherAll(itemLink, itemID)
  local capture = (cfg())
  if not capture then return nil end
  local wanted = wantedByProvider(capture)
  local map
  for prov, keys in pairs(wanted) do
    local fetch = PROVIDER_FETCH[prov]
    if fetch then
      local ok, sub = pcall(fetch, keys, itemLink, itemID)
      if ok and sub and next(sub) then map = map or {}; map[prov] = sub end
    end
  end
  return map
end

-- Select one price from the map via the priority list. Returns price, tag ("provider:key"). The
-- map only ever holds *collected* (enabled) keys — collection and priority are one flag now — so
-- Pick simply returns the highest-ranked tag that has data.
function AuctionPrice:Pick(map)
  if type(map) ~= "table" then return nil, nil end
  local _, priority = cfg()
  priority = priority or NS.Constants.AUCTION_PRIORITY_DEFAULT
  for _, tag in ipairs(priority) do
    local prov, key = tag:match("^(.-):(.+)$")
    local v = prov and key and map[prov] and map[prov][key]
    if v then return v, tag end
  end
  return nil, nil
end

-- True iff the given provider's addon is loaded/present (its API globals exist).
function AuctionPrice:IsProviderAvailable(provider)
  if provider == "auctionator" then
    return (Auctionator and Auctionator.API and Auctionator.API.v1) and true or false
  elseif provider == "tsm" then
    return (TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString) and true or false
  elseif provider == "oribos" then
    return type(OEMarketInfo) == "function"
  end
  return false
end

-- Priority-list accessors used by the settings panel (R6) to render/reorder the cascade.
function AuctionPrice:GetPriority()
  local s = NS.db.global.settings.auction
  s.priority = s.priority or {}
  return s.priority
end

-- Ensure the stored priority array holds every known AUCTION_KEYS tag exactly once (append missing
-- at the end in AUCTION_KEYS order; drop tags no longer known). No migration — branch unmerged.
function AuctionPrice:ReconcilePriority()
  local p = self:GetPriority()
  local known, seen = {}, {}
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do known[k.provider .. ":" .. k.key] = true end
  local out = {}
  for _, tag in ipairs(p) do
    if known[tag] and not seen[tag] then out[#out + 1] = tag; seen[tag] = true end
  end
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do
    local tag = k.provider .. ":" .. k.key
    if not seen[tag] then out[#out + 1] = tag; seen[tag] = true end
  end
  for i = #p, 1, -1 do p[i] = nil end        -- rewrite in place (keep the same table reference)
  for i, tag in ipairs(out) do p[i] = tag end
  return p
end

-- Move one tag to a new position AMONG A SUBSET of the cascade, in one write.
--
-- Replaces the pairwise SwapPriorityTags the settings panel's ▲▼ arrows used to drive. The panel
-- drags now (options-ui-§18) and a drag is a SPLICE TO INDEX, not a run of adjacent swaps: a
-- four-position move has to be one mutation and one repaint, or every intermediate order is written
-- to the DB and announced.
--
-- `subset` is the tags the drag may reorder, in cascade order — the panel's "collecting" partition,
-- which is the only group it lets you drag within. THE TAGS OUTSIDE IT DO NOT MOVE: their slots in
-- the stored array are left exactly where they are and the subset is re-laid into its own slots, so
-- a reorder of the collected sources cannot silently re-rank a source you are not collecting. That
-- also makes the write minimal — `#subset` assignments, however far the row travelled.
--
-- Returns true when something moved, false for a no-op (an out-of-range index, a move to where the
-- row already was, or a tag the cascade does not carry).
function AuctionPrice:MovePriorityWithin(subset, from, to)
  if type(subset) ~= "table" then return false end
  local n = #subset
  if not (type(from) == "number" and type(to) == "number") then return false end
  if from < 1 or from > n or to < 1 or to > n or from == to then return false end

  local p = self:GetPriority()
  -- The subset's own slots in the cascade, ascending — which is the order `subset` is in, because
  -- the caller partitioned it by walking the cascade.
  local slots, at = {}, {}
  for i, tag in ipairs(p) do at[tag] = at[tag] or i end
  for i, tag in ipairs(subset) do
    local pos = at[tag]
    if not pos then return false end
    slots[i] = pos
  end
  table.sort(slots)

  local moved = {}
  for i, tag in ipairs(subset) do moved[i] = tag end
  table.insert(moved, to, table.remove(moved, from))

  for i, tag in ipairs(moved) do p[slots[i]] = tag end
  return true
end
