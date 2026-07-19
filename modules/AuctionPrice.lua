local addonName, NS = ...   -- luacheck: ignore addonName
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

-- Select one price from the map via the priority list. Returns price, tag ("provider:key").
-- Tags present in settings.auction.priorityDisabled are skipped (temporarily disabled cascade
-- entries; distinct from removing them from the priority list outright).
function AuctionPrice:Pick(map)
  if type(map) ~= "table" then return nil, nil end
  local _, priority = cfg()
  priority = priority or NS.Constants.AUCTION_PRIORITY_DEFAULT
  local s = NS.db.global.settings.auction
  local disabled = (s and s.priorityDisabled) or {}
  for _, tag in ipairs(priority) do
    if not disabled[tag] then
      local prov, key = tag:match("^(.-):(.+)$")
      local v = prov and key and map[prov] and map[prov][key]
      if v then return v, tag end
    end
  end
  return nil, nil
end

-- Priority-list accessors used by the settings panel (R6) to render/reorder the cascade.
function AuctionPrice:GetPriority()
  local s = NS.db.global.settings.auction
  s.priority = s.priority or {}
  return s.priority
end
function AuctionPrice:MovePriority(index, delta)   -- delta = -1 up / +1 down
  local p = self:GetPriority()
  local j = index + delta
  if index < 1 or index > #p or j < 1 or j > #p then return false end
  p[index], p[j] = p[j], p[index]
  return true
end

-- Priority-disabled accessors: a tag can stay in the priority order but be temporarily skipped
-- by Pick (e.g. a provider's data looked unreliable) without losing its place in the list.
function AuctionPrice:IsPriorityEnabled(tag)
  local s = NS.db.global.settings.auction
  return not (s and s.priorityDisabled and s.priorityDisabled[tag])
end
function AuctionPrice:SetPriorityEnabled(tag, on)
  local s = NS.db.global.settings.auction
  s.priorityDisabled = s.priorityDisabled or {}
  s.priorityDisabled[tag] = (not on) or nil
end
