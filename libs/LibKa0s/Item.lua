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
-- "shared bug surface" a module is supposed to avoid being — so this module carries the five
-- primitives both compose, and holds no opinion about how.
--
-- ── WHY THESE FIVE ───────────────────────────────────────────────────────────────────────────
--
-- `QualityLabel` and `LoadItem` were byte-identical in both addons. The next two were each
-- written by only ONE of them — BankLedger had `ItemIDFromLink`, LootHistory had
-- `QualityFromLink` — which is the better argument: each addon was missing a primitive the other
-- had already written, and the color fallback is the one whose absence had already cost a
-- misclassified item. The fifth, `BonusIDsFromLink` (minor 3, LibKa0s#51), is the positional
-- walk BankLedger and LootHistory each wrote to build the Wowhead bonus string: field 13 is the
-- declared count and the ids follow it, which is domain knowledge a copy can get wrong.
--
-- The rest of #51 — a merged link detail, an identity key, the gear item level, a bag-slot level
-- and quality read, a quality-with-source read, the Wowhead URL builder and the loot-line parser —
-- was considered and rejected; each reason and re-check trigger is recorded under "What this
-- major is not" in docs/api/Item/version-3-docs.md.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Item-1.0", 3
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

--- The bonus ids an item link or a bare itemString carries, as numbers, in link order.
---
--- The itemString is colon-separated and POSITIONAL, so empty fields are kept when splitting:
---   field 1 is the itemID, 2..12 are enchant, gems, suffix, unique id, level, spec, upgrade
---   type and difficulty, field 13 is the declared bonus count n, and fields 14..13+n are the
---   bonus ids. What follows them (the modifier block, relic and crafting data) is never read.
---
--- Answers nil for a non-string or a string holding no `item:<id>`, and {} for an item with no
--- bonuses. A non-numeric field inside the declared span is skipped rather than read as 0.
--- Locale-independent, like ItemIDFromLink: it reads the link's structure, never a name.
---
--- @param link string
--- @return number[]|nil
function lib.BonusIDsFromLink(link)
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
end

-- Reverse map of quality-color hex (rrggbb) → quality id, built on first use.
--
-- LAZILY, and that is a requirement rather than a style preference: this file runs from inside
-- `libs/` before the client has populated ITEM_QUALITY_COLORS, so a map built at load would be
-- empty for the life of the session and every lookup would answer nil — silently, since nil is
-- also the legitimate answer for an uncolored link.
--
-- And committed only when NON-EMPTY (minor 2): a build that found nothing to map is not kept, so a
-- first call that lands before the table is populated is retried on the next call rather than
-- pinning nil for the session.
local qualityByHex

local function buildQualityByHex()
  if type(ITEM_QUALITY_COLORS) ~= "table" then return end
  local map, any = {}, false
  for q = 0, 8 do
    local c = ITEM_QUALITY_COLORS[q]
    if c and c.hex then map[c.hex:sub(-6)] = q; any = true end
  end
  if any then qualityByHex = map end
end

--- The quality id encoded in an item link's color prefix, or nil.
---
--- THIS IS THE UNCACHED FALLBACK, and it is the reason the module is worth having. `GetItemInfo`
--- answers nothing until the client has cached the item, and when handed a bare itemID it can only
--- ever answer with the BASE item — so an upgrade-track drop reads back at the quality it started
--- as. The link's color is the real one, available immediately, from the string the game already
--- handed the addon.
---
--- Two rungs. Since patch 11.1.5 the client colors an item link by quality NUMBER, `|cnIQ<n>:`,
--- and that is read first (minor 2), anchored on the digits with no trailing ':' required. The
--- `|cAARRGGBB` hex rung stays for the pre-11.1.5 links a saved variable still holds.
---
--- @param link string
--- @return number|nil
function lib.QualityFromLink(link)
  if not link then return nil end
  local q = link:match("|cnIQ(%d+)")
  if q then return tonumber(q) end
  local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
  if not hex then return nil end
  if not qualityByHex then buildQualityByHex() end
  return qualityByHex and qualityByHex[hex]
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
