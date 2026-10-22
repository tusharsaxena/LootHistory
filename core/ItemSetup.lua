local _, NS = ...

-- core/ItemSetup.lua — wires the addon into LibKa0s-Item-1.0 (library-stack-§7).
--
-- ── WHAT MOVED, AND WHAT POINTEDLY DID NOT ───────────────────────────────────────────────────
--
-- Three shims left core/Compat.lua for the library — QualityFromLink, QualityLabel and LoadItem —
-- and a fourth primitive arrives that this addon never had: ItemIDFromLink, which only BankLedger
-- had written. QualityLabel and LoadItem were byte-identical in both addons; QualityFromLink, the
-- color fallback, was this addon's alone.
--
-- THE RESOLVER DID NOT MOVE, and that is a decision rather than an oversight. Compat.GetItemInfo
-- still GUESSES for an item the client has not cached: the name from the link's brackets and the
-- quality from its |cff color, because a browsable capture log would rather show an approximate
-- row than lose the drop. BankLedger's resolver does the opposite on purpose — its quality gate
-- records the skip as "uncached" and asks the client to cache the id, because "cannot be judged" is
-- not "passes". A shared resolver would have had to pick one, and picking would have silently
-- overturned the other.
--
-- ── WHAT A DEGRADED INSTALL GETS ─────────────────────────────────────────────────────────────
--
-- The same five primitives, locally (BonusIDsFromLink joined with Item minor 3, LibKa0s v1.75.0). They are short, pure and three of them were here before;
-- a caller that had to branch on the library's presence would be a caller that classifies drops
-- differently on a broken install — and the quality it wrote is stored, not just drawn.

local Item = LibStub and LibStub("LibKa0s-Item-1.0", true)

-- Falls back to a static English map headlessly and for unknown ids.
local QUALITY_LABEL_EN = {
  [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare",
  [4] = "Epic", [5] = "Legendary", [6] = "Artifact", [7] = "Heirloom", [8] = "WoW Token",
}

-- Reverse map of item-quality color hex (rrggbb) → quality id, for the uncached fallback. Built
-- lazily on first use, never at load: ITEM_QUALITY_COLORS is not populated when this file runs, so
-- a map built here would be empty for the session and every lookup would answer nil — silently,
-- since nil is also the honest answer for an uncolored link.
local qualityByHex

NS.Item = Item or {
  ItemIDFromLink = function(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("|?H?item:(%d+)"))
  end,

  -- The library's positional walk, not an approximation of it: the itemString keeps its empty
  -- fields, field 13 is the declared count and fields 14..13+n are the ids, a non-numeric one
  -- skipped. nil for a non-string or no `item:<id>`; {} for an item with no bonuses.
  BonusIDsFromLink = function(link)
    if type(link) ~= "string" then return nil end
    local body = link:match("item:([%-%d:]*)")
    if not body then return nil end
    local fields = {}
    for v in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = v end
    if not tonumber(fields[1]) then return nil end
    local out = {}
    for i = 14, 13 + (tonumber(fields[13]) or 0) do
      local id = tonumber(fields[i])
      if id then out[#out + 1] = id end
    end
    return out
  end,

  QualityFromLink = function(link)
    if not link then return nil end
    local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
    if not hex then return nil end
    if not qualityByHex then
      qualityByHex = {}
      if type(ITEM_QUALITY_COLORS) == "table" then
        for q = 0, 8 do
          local c = ITEM_QUALITY_COLORS[q]
          if c and c.hex then qualityByHex[c.hex:sub(-6)] = q end
        end
      end
    end
    return qualityByHex[hex]
  end,

  QualityLabel = function(q)
    q = q or 0
    return _G["ITEM_QUALITY" .. q .. "_DESC"] or QUALITY_LABEL_EN[q] or tostring(q)
  end,

  LoadItem = function(id, cb)
    if not (id and C_Item and C_Item.RequestLoadItemDataByID) then return end
    C_Item.RequestLoadItemDataByID(id)
    if cb and C_Timer and C_Timer.After then C_Timer.After(0.4, cb) end
  end,
}
