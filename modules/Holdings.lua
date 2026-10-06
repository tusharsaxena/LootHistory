local _, NS = ...
-- luacheck: ignore 212/self
NS.Holdings = NS.Holdings or {}
local Holdings = NS.Holdings

-- The holdings ledger (timeline-ledger spec §4.2): db.global.holdings[holder]. Account-wide; one
-- writer (the Reconciler, through the Apply* calls); every reader goes through this API.

local C = NS.Constants
local WARBAND = C.WARBAND_HOLDER

function Holdings:Store()
  local g = NS.db and NS.db.global
  if not g then return {} end
  g.holdings = g.holdings or {}
  return g.holdings
end

function Holdings:Get(holder, create)
  local s = self:Store()
  local e = s[holder]
  if not e and create then
    e = { meta = {}, scanned = {}, items = {}, currency = {}, links = {} }
    s[holder] = e
  end
  return e
end

function Holdings:ApplyContainer(holder, container, counts, links, ts)
  local e = self:Get(holder, true)
  local changed = false
  for id, row in pairs(e.items) do
    local want = counts[id]
    if row[container] ~= want then
      row[container] = want; changed = true
      if next(row) == nil then e.items[id] = nil end
    end
  end
  for id, n in pairs(counts) do
    local row = e.items[id]
    if not row then row = {}; e.items[id] = row end
    if row[container] ~= n then row[container] = n; changed = true end
  end
  for id, link in pairs(links or {}) do e.links[id] = link end
  e.scanned[container] = ts
  e.meta.lastSeen = ts
  return changed
end

local function sameMap(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function Holdings:ApplyCurrency(holder, map, ts)
  local e = self:Get(holder, true)
  local changed = not sameMap(e.currency, map)
  e.currency = map
  e.scanned.currency, e.meta.lastSeen = ts, ts
  return changed
end

function Holdings:ApplyMoney(holder, copper, ts)
  local e = self:Get(holder, true)
  local changed = e.money ~= copper
  e.money = copper
  e.scanned.money, e.meta.lastSeen = ts, ts
  return changed
end

function Holdings:MarkGenesis(holder, ts)
  local e = self:Get(holder, true)
  e.meta.genesis = e.meta.genesis or ts
  local gate = (holder == WARBAND) and C.Container.TABS or C.Container.BANK
  e.meta.partial = e.scanned[gate] == nil
end

function Holdings:ItemCounts(holder)
  local e, out = self:Get(holder), {}
  if not e then return out end
  for id, row in pairs(e.items) do
    local n = 0; for _, c in pairs(row) do n = n + c end
    out[id] = n
  end
  return out
end

function Holdings:Holders()
  local chars, hasWarband = {}, false
  for h in pairs(self:Store()) do
    if h == WARBAND then hasWarband = true else chars[#chars + 1] = h end
  end
  table.sort(chars)
  if hasWarband then chars[#chars + 1] = WARBAND end
  return chars
end

-- One holder's count of `thingKey`, with its container split and the oldest scan feeding it.
local function holderCount(e, kind, id)
  if kind == "GOLD" then return e.money or 0, nil, e.scanned.money end
  if kind == "CURRENCY" then return e.currency[id] or 0, nil, e.scanned.currency end
  local row = e.items[id]
  if not row then return 0 end
  local n, oldest, split = 0, nil, {}
  for c, k in pairs(row) do
    n = n + k; split[c] = k
    local t = e.scanned[c]
    if t and (not oldest or t < oldest) then oldest = t end
  end
  return n, split, oldest
end

function Holdings:Total(thingKey, holderSet)
  local kind, id = NS.Ledger.ParseThingKey(thingKey)
  local total, rows = 0, {}
  if not kind then return 0, rows end
  for h, e in pairs(self:Store()) do
    if not holderSet or holderSet[h] then
      local n, split, at = holderCount(e, kind, id)
      if n ~= 0 then
        total = total + n
        rows[#rows + 1] = { holder = h, count = n, containers = split, scannedAt = at }
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.holder < b.holder
  end)
  return total, rows
end

-- Display fields for a thing. Uncached items keep a row: name falls back to the link's bracket text,
-- then to "item:<id>" (Review Focus 2).
local function describe(key, kind, id, link)
  if kind == "GOLD" then return { name = _G.GOLD or "Gold", itemType = _G.GOLD or "Gold" } end
  if kind == "CURRENCY" then
    return { name = NS.Compat.CurrencyName(id) or ("currency:" .. id), quality = NS.Compat.CurrencyQuality(id),
             itemType = C.CURRENCY_TYPE, itemSubType = NS.Compat.CurrencyCategory(id) }
  end
  local _, name, quality = NS.Compat.GetItemInfo(link or ("item:" .. id))
  local itemType, itemSubType = NS.Compat.GetItemTypeInfo(link or id)
  return { name = name or ("item:" .. id), quality = quality, itemType = itemType, itemSubType = itemSubType, key = key }
end

local function setPasses(set, v) return not set or next(set) == nil or (v ~= nil and set[v]) end

function Holdings:Search(filter)
  filter = filter or {}
  local holderSet = (filter.char and next(filter.char)) and filter.char or nil
  local text = filter.text and filter.text ~= "" and filter.text:lower() or nil
  local seen, links = {}, {}
  for _, e in pairs(self:Store()) do
    for id in pairs(e.items) do seen["i:" .. id] = true; links[id] = links[id] or e.links[id] end
    for id in pairs(e.currency) do seen["c:" .. id] = true end
    if e.money then seen.g = true end
  end
  local out = {}
  for key in pairs(seen) do
    local kind, id = NS.Ledger.ParseThingKey(key)
    local d = describe(key, kind, id, links[id])
    if (not text or d.name:lower():find(text, 1, true))
      and setPasses(filter.quality, d.quality) and setPasses(filter.itemType, d.itemType)
      and setPasses(filter.itemSubType, d.itemSubType) then
      local total, rows = self:Total(key, holderSet)
      if total ~= 0 then
        out[#out + 1] = { key = key, kind = kind, id = id, name = d.name, quality = d.quality,
          itemType = d.itemType, itemSubType = d.itemSubType, total = total, holders = rows, link = links[id] }
      end
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

function Holdings:ForgetHolder(holder)
  local s = self:Store()
  if s[holder] == nil then return false end
  s[holder] = nil
  return true
end

-- Credit an own alt's stored currency for a transfer this character just made, so the alt's next
-- login does not read the arrival as untracked drift. Only a holder whose currency was ever scanned:
-- an alt with no baseline gets the amount as part of its genesis instead.
function Holdings:CreditCurrency(holder, id, qty)
  local e = self:Get(holder)
  if not (e and e.scanned.currency) then return false end
  local v = (e.currency[id] or 0) + qty
  e.currency[id] = (v > 0) and v or nil
  return true
end
