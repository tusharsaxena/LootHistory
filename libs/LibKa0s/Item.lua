-- LibKa0s-Item-1.0 — item identity, as primitives. No policy.
--
-- ── WHAT THIS IS NOT, FIRST ──────────────────────────────────────────────────────────────────
--
-- There is NO merged "resolve an item" function here, and its absence is the design.
--
-- Two addons in this collection resolve items, and they disagree — deliberately, in writing —
-- about what an UNCACHED item means. LootHistory guesses: it falls back to the name in the link's
-- brackets and the quality in its color, because a browsable capture log would rather show an
-- approximate row than lose the drop. BankLedger refuses: its quality gate records the skip as
-- "uncached" and asks the client to cache the id, because "cannot be judged" is not "passes" and a
-- row it can never classify is not one a threshold ever asked for.
--
-- Both are correct for their addon. A shared resolver would have to pick one, and picking would
-- have silently overturned a decision the other addon wrote down and tested. That is exactly the
-- "shared bug surface" a module is supposed to avoid being — so this module carries the four
-- primitives both compose, and holds no opinion about how.
--
-- ── WHY THESE FOUR ───────────────────────────────────────────────────────────────────────────
--
-- `QualityLabel` and `LoadItem` were byte-identical in both addons. The other two were each
-- written by only ONE of them — BankLedger had `ItemIDFromLink`, LootHistory had
-- `QualityFromLink` — which is the better argument: each addon was missing a primitive the other
-- had already written, and the color fallback is the one whose absence had already cost a
-- misclassified item.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Item-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Item = MINOR

-- ── identity ─────────────────────────────────────────────────────────────────────────────

--- The itemID carried by an item link or a bare itemString.
---
--- Locale-independent: it reads the link's own structure, never a displayed name.
---
--- @param link string
--- @return number|nil
function lib.ItemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|?H?item:(%d+)"))
end

-- Reverse map of quality-color hex (rrggbb) → quality id, built on first use.
--
-- LAZILY, and that is a requirement rather than a style preference: this file runs from inside
-- `libs/` before the client has populated ITEM_QUALITY_COLORS, so a map built at load would be
-- empty for the life of the session and every lookup would answer nil — silently, since nil is
-- also the legitimate answer for an uncolored link.
local qualityByHex

local function buildQualityByHex()
  qualityByHex = {}
  if type(ITEM_QUALITY_COLORS) == "table" then
    for q = 0, 8 do
      local c = ITEM_QUALITY_COLORS[q]
      if c and c.hex then qualityByHex[c.hex:sub(-6)] = q end
    end
  end
end

--- The quality id encoded in an item link's color prefix, or nil.
---
--- THIS IS THE UNCACHED FALLBACK, and it is the reason the module is worth having. `GetItemInfo`
--- answers nothing until the client has cached the item, and when handed a bare itemID it can only
--- ever answer with the BASE item — so an upgrade-track drop reads back at the quality it started
--- as. The link's color is the real one, available immediately, from the string the game already
--- handed the addon.
---
--- @param link string
--- @return number|nil
function lib.QualityFromLink(link)
  if not link then return nil end
  local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
  if not hex then return nil end
  if not qualityByHex then buildQualityByHex() end
  return qualityByHex[hex]
end

-- ── display ──────────────────────────────────────────────────────────────────────────────

-- The English names, behind the client's own localized globals. Present so that a headless suite
-- and a client that has not populated the globals both answer something a human recognizes.
local QUALITY_LABEL_EN = {
  [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare",
  [4] = "Epic", [5] = "Legendary", [6] = "Artifact", [7] = "Heirloom", [8] = "WoW Token",
}

--- A quality id's display label.
---
--- Matched on the ID and never on a localized string (localization-§4): the client's own
--- `ITEM_QUALITY<n>_DESC` first, the static English map second, and the number itself for a
--- quality neither knows — which is a visible answer rather than a nil that renders as a blank
--- cell nobody can explain.
---
--- @param q number|nil
--- @return string
function lib.QualityLabel(q)
  q = q or 0
  return _G["ITEM_QUALITY" .. q .. "_DESC"] or QUALITY_LABEL_EN[q] or tostring(q)
end

--- Ask the server to cache an item id, and fire `cb` once it should have arrived.
---
--- Inert without an id and without the API, because both mean the same thing to a caller: no name
--- yet, show the placeholder, try again later.
---
--- @param id number
--- @param cb function|nil
function lib.LoadItem(id, cb)
  if not (id and C_Item and C_Item.RequestLoadItemDataByID) then return end
  C_Item.RequestLoadItemDataByID(id)
  if cb and C_Timer and C_Timer.After then C_Timer.After(0.4, cb) end
end
