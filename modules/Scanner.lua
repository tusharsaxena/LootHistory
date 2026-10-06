local _, NS = ...
NS.Scanner = NS.Scanner or {}
local Scanner = NS.Scanner

-- Container reads -> count maps. Stateless and side-effect free: what to scan and when is the
-- Reconciler's business; this file only answers "what is in these containers right now". Counts are
-- keyed by BASE itemID (spec §3): two ilvl variants of one id are one holding. The first hyperlink
-- seen per id is kept for display (GetItemInfo(id) only knows the base item).

local Compat = NS.Compat

function Scanner.ScanContainers(ids)
  local counts, links = {}, {}
  for _, bagID in ipairs(ids) do
    for slot = 1, Compat.GetContainerNumSlots(bagID) do
      local s = Compat.GetContainerSlot(bagID, slot)
      if s then
        counts[s.itemID] = (counts[s.itemID] or 0) + s.count
        if s.link and not links[s.itemID] then links[s.itemID] = s.link end
      end
    end
  end
  return counts, links
end

local function addEquipped(counts, links, id, link)
  if not id then return end
  counts[id] = (counts[id] or 0) + 1
  if link and not links[id] then links[id] = link end
end

-- Worn gear plus the bag items sitting in the bag slots: swapping either must read as a transfer,
-- not as a loss from bags (Phase 2 classification relies on this column existing).
function Scanner.ScanEquipped()
  local counts, links = {}, {}
  for _, slot in ipairs(NS.Constants.EQUIP_SLOTS) do addEquipped(counts, links, Compat.GetInventoryItem(slot)) end
  for bagID = 1, 5 do
    local inv = Compat.BagInventorySlot(bagID)
    if inv then addEquipped(counts, links, Compat.GetInventoryItem(inv)) end
  end
  return counts, links
end

-- Account-wide currencies belong to the warband holder, the rest to the character; a zero balance
-- is not a holding.
function Scanner.ScanCurrencies()
  local char, warband = {}, {}
  for _, c in ipairs(Compat.ListCurrencies()) do
    if c.quantity > 0 then
      if c.accountWide then warband[c.id] = c.quantity else char[c.id] = c.quantity end
    end
  end
  return char, warband
end

function Scanner.ReadMoney() return Compat.GetMoney() end
function Scanner.ReadWarbandMoney() return Compat.GetWarbandMoney() end
