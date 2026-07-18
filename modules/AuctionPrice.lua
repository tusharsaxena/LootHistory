local addonName, NS = ...   -- luacheck: ignore addonName
NS.AuctionPrice = NS.AuctionPrice or {}
local AuctionPrice = NS.AuctionPrice

-- Reads AH price for a just-looted item from installed pricing addons, in a user-configurable
-- fall-through cascade (Auctionator -> TSM -> OribosExchange by default). Third-party integration
-- boundary — presence-gated here, deliberately NOT in core/Compat.lua (Blizzard-API-only). Every
-- provider call is wrapped so a broken/absent addon degrades to nil and the cascade continues.
-- Returns copper price + a compact provenance tag; both nil when no enabled provider has a price.

-- ── Provider fetchers (each: (itemLink, itemID, tsmSource) -> price|nil, tag|nil) ──
local function fetchAuctionator(itemLink, itemID)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not api then return nil end
  local price
  if itemID and api.GetAuctionPriceByItemID then
    price = api.GetAuctionPriceByItemID(addonName, itemID)
  elseif itemLink and api.GetAuctionPriceByItemLink then
    price = api.GetAuctionPriceByItemLink(addonName, itemLink)
  end
  if price then return price, "auctionator" end
  return nil
end

local function fetchTSM(itemLink, _itemID, tsmSource)
  if not (TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString) then return nil end
  local key = tsmSource or "dbmarket"
  local itemStr = TSM_API.ToItemString(itemLink)
  if not itemStr then return nil end
  local price = TSM_API.GetCustomPriceValue(key, itemStr)
  if price and price > 0 then return price, "tsm:" .. key end
  return nil
end

local function fetchOribos(itemLink, itemID)
  if type(OEMarketInfo) ~= "function" then return nil end
  local info = {}
  OEMarketInfo(itemLink or itemID, info)
  if info.market and info.market > 0 then return info.market, "oribos:market" end
  if info.region and info.region > 0 then return info.region, "oribos:region" end
  return nil
end

-- Canonical providers (order = install-base default). settingKey/priorityKey index settings.auction.
local PROVIDERS = {
  { id = "auctionator", settingKey = "auctionator", priorityKey = "priorityAuctionator", fetch = fetchAuctionator },
  { id = "tsm",         settingKey = "tsm",         priorityKey = "priorityTSM",         fetch = fetchTSM },
  { id = "oribos",      settingKey = "oribos",      priorityKey = "priorityOribos",      fetch = fetchOribos },
}

-- Resolve live settings into an ordered, enabled provider list. Missing settings.auction ⇒
-- feature on, canonical order, dbmarket.
local function resolve()
  local s = NS.db and NS.db.global and NS.db.global.settings and NS.db.global.settings.auction
  if s and s.enabled == false then return nil end
  local tsmSource = (s and s.tsmSource) or "dbmarket"
  local list = {}
  for i, p in ipairs(PROVIDERS) do
    local enabled = not s or s[p.settingKey] ~= false     -- default enabled
    if enabled then
      local priority = (s and tonumber(s[p.priorityKey])) or i
      list[#list + 1] = { fetch = p.fetch, priority = priority, canon = i }
    end
  end
  table.sort(list, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.canon < b.canon
  end)
  return list, tsmSource
end

-- Public: first enabled provider (in priority order) that returns a price wins.
function AuctionPrice:Lookup(itemLink, itemID)
  local list, tsmSource = resolve()
  if not list then return nil, nil end
  for _, p in ipairs(list) do
    local ok, price, tag = pcall(p.fetch, itemLink, itemID, tsmSource)
    if ok and price then return price, tag end
  end
  return nil, nil
end
