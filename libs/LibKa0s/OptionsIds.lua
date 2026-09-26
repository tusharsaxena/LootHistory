-- LibKa0s-Options-1.0 — the id surface's first half: resolving typed text to an id, the
-- suggestions listed while the player types, and the input line that submits one (O.ResolveId,
-- O.UnnamedCandidates, O.ID_NAME_HINT, O.IdInput).
--
-- Peeled out of OptionsWidgets.lua at OptionsIds minor 1 (issue #32), with OptionsIdList.lua
-- beside it. The id surface was one seam there, but at about 2460 lines it was too big for one file
-- under layout-§1's cap, so it is two files: this one, and the list, which draws this file's input
-- at its head. The module-scope blocks below reach nothing in OptionsWidgets.lua; the members inside
-- lib.__AttachIds reach two of its module-scope helpers (startRow, renderRowGuarded) and the
-- instance's sink and combat refusal, which OptionsWidgets.lua hands over when it calls in. No
-- other local crosses the cut: it is a move, not a rewrite.
--
-- WHO CALLS IN. lib.__AttachWidgets calls lib.__AttachIds at the point the id members used to be
-- defined, so every instance still gets them in the same order and Options.lua did not move. What
-- lib.__AttachIds returns is the list's share of its locals, and lib.__AttachWidgets passes that on
-- to lib.__AttachIdList. A copy with neither file draws no id widget and raises nothing.
--
-- Part of the Options major rather than a major of its own, and guarded with the same multi-file
-- idiom as OptionsWidgets.lua and OptionsTabs.lua: a half of the id surface from one vendored copy
-- paired with a shell from another would hand the list locals it does not expect, and nothing
-- would say so.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: the id surface's resolution, suggestions and input, moved here from OptionsWidgets.lua
-- (issue #32) with no change in behavior.
local IDS_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own — see OptionsScroll.lua for why the
-- file's own counter is not enough.
if lib.__idsMinor and lib.__idsMinor >= IDS_MINOR
  and lib.__idsShellMinor == lib.MINOR then return end
lib.__idsMinor      = IDS_MINOR
lib.__idsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsIds = IDS_MINOR

-- ── id resolution (minor 16) ──────────────────────────────────────────────────────────────
--
-- What O.ResolveId, O.IdInput and O.IdList use to turn typed text into an id. Pure, and at file
-- scope for that reason: nothing here touches a widget or an instance, so it is built once at load.
--
-- THE CLIENT APIS ARE READ AT CALL TIME, and every one is guarded. A client without C_Spell (or a
-- harness that cleared it) degrades to id-only input: a number or a link still resolves, a name
-- finds nothing, and nothing raises.

--- A spell by id, or by a name the client knows: its id, name and icon, spelled as the client
--- spells it. The client's name lookup ignores case, so a player typing in lower case is served.
local function spellLookup(key)
  local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(key)
  if type(info) ~= "table" then return nil end
  return info.spellID, info.name, info.iconID
end
local function spellInfo(id)
  local _, name, icon = spellLookup(id)
  return name, icon
end

--- An item's id and icon from GetItemInfoInstant, which needs no cache; its name from
--- GetItemNameByID, which does. An uncached item answers its icon and no name.
local function itemInstant(key)
  if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
  local id, _, _, _, icon = C_Item.GetItemInfoInstant(key)
  return id, icon
end
local function itemName(id)
  if not (C_Item and C_Item.GetItemNameByID) then return nil end
  return C_Item.GetItemNameByID(id)
end
local function itemInfo(id)
  local _, icon = itemInstant(id)
  return itemName(id), icon
end
local function itemByName(text)
  local id, icon = itemInstant(text)
  if not id then return nil end
  return id, itemName(id) or text, icon
end

--- The color code an item's name is drawn in: the client's quality for the id, through its own
--- ITEM_QUALITY_COLORS palette. Nil, for a plain name, while the item is uncached (the client
--- answers no quality until it is) or the palette has no entry; the redraw a load triggers colors
--- it. The palette is read at call time, as LibKa0s-Item-1.0 reads it: it may be unpopulated when
--- this file loads.
local function itemQualityColor(id)
  local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
  local color = type(quality) == "number" and type(ITEM_QUALITY_COLORS) == "table"
    and ITEM_QUALITY_COLORS[quality]
  return type(color) == "table" and type(color.hex) == "string" and color.hex or nil
end

--- A currency has no client name lookup, so a name reaches one only through the host's
--- candidates. An empty name is the client's answer for an id it does not have.
local function currencyInfo(id)
  local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
  if type(info) ~= "table" or type(info.name) ~= "string" or info.name == "" then return nil end
  return info.name, info.iconFileID
end

-- One row per kind: what a message calls it, the link type it parses, how an id is named, how a
-- name is looked up, which GameTooltip method shows it, and whether an unnamed one can be loaded.
-- A kind the host names that is not here, or no kind at all, is ID_ONLY: numbers only.
local ID_KINDS = {
  spell    = { noun = "spell", plural = "spells", link = "spell", info = spellInfo,
               byName = spellLookup, tooltip = "SetSpellByID" },
  item     = { noun = "item", plural = "items", link = "item", info = itemInfo,
               byName = itemByName, tooltip = "SetItemByID", loads = true },
  currency = { noun = "currency", plural = "currencies", link = "currency", info = currencyInfo,
               tooltip = "SetCurrencyByID" },
}
local ID_ONLY = { noun = "entry", plural = "entries" }

-- The kinds whose entry names are drawn in a color, keyed by the kind table itself so a host's own
-- kind table never matches: an item's quality color. A spell and a currency are drawn plain.
local NAME_COLOR = { [ID_KINDS.item] = itemQualityColor }

-- A host kind whose ids are one library kind's says so with `base = "item"` (or "spell",
-- "currency"): it wears that kind's decorations -- the name color, and the suggestion row's rank
-- and client source below, both keyed by the library's kind table -- and takes these fields from it
-- where it sets none of its own. Never `byName`: what a host kind RESOLVES stays its own, so a
-- typed name still reaches the host's resolver and its candidates rather than the client's name
-- lookup. `resolve`, and any field the host sets (false included), win.
local BASE_FIELDS = { info = true, link = true, tooltip = true, loads = true, noun = true, plural = true }
-- The view idKind hands out for each based host table, and the host table behind each view, so a
-- host that builds its kind per render leaks nothing. basedViews is weak on its VALUES too: a view
-- reaches back to its host, and Lua 5.1 has no ephemerons, so a view held strongly under a weak key
-- would keep that key, and itself, for the session. A view nothing else holds is simply rebuilt.
local basedViews = setmetatable({}, { __mode = "kv" })
local viewHost = setmetatable({}, { __mode = "k" })

--- The library kind a host table's `base` names, or nil. Read at call time: a host whose kind
--- reads through to the one its dropdown names changes base with it.
local function baseKindOf(host)
  local name = host.base
  return type(name) == "string" and ID_KINDS[name] or nil
end

--- The view of a based host table: the host's own fields, then BASE_FIELDS from its base.
local function basedView(host)
  local view = basedViews[host]
  if view then return view end
  view = setmetatable({}, { __index = function(_, key)
    local v = host[key]
    if v == nil and BASE_FIELDS[key] then
      local base = baseKindOf(host)
      if base then v = base[key] end
    end
    return v
  end })
  basedViews[host], viewHost[view] = view, host
  return view
end

--- The kind table for `kind`: a host's own table as given (its based view when it names a library
--- kind as `base`), a named kind, or ID_ONLY.
local function idKind(kind)
  if type(kind) == "table" then
    if baseKindOf(kind) then return basedView(kind) end
    return kind
  end
  return ID_KINDS[kind] or ID_ONLY
end

--- The kind whose decorations `k` wears: a based host kind's library kind, else `k` itself -- so a
--- host kind without a base matches no decoration table, as before.
local function decorKind(k)
  local host = viewHost[k]
  return host and baseKindOf(host) or k
end

--- The color code `id`'s name is drawn in for `k`, or nil for a plain name.
local function nameColor(k, id)
  local color = NAME_COLOR[decorKind(k)]
  return color and color(id)
end

--- What a message calls `k`, singular and plural. A host kind names itself or reads as "entry".
local function kindWords(k)
  local noun = k.noun or ID_ONLY.noun
  return noun, k.plural or (k.noun and k.noun .. "s") or ID_ONLY.plural
end

-- The widgets' words. A literal table, as lib.STRINGS is: the library carries no locale, and a
-- host that has one passes `spec.strings` with any of these keys. `{name}` tokens rather than
-- format specifiers, so a translation can put the words in its own order -- Lua 5.1's
-- string.format has no positional arguments.
local ID_TEXT = {
  add       = "Add",
  remove    = "Remove",
  empty     = "Type an id, a link or a name.",
  notFound  = "No {noun} named '{text}'.",
  ambiguous = "Several {plural} are named '{text}' \226\128\148 pick one from the list, or use the id.",
  unknown   = "Unknown {noun} {id}",
  looking   = "Looking up {plural}...",
  nameHint  = "",
  more      = "+{count} more",
}

-- The named kinds' own words, over ID_TEXT's: a notFound that says where a name can come from, and
-- the hint it ends with (`{hint}`, filled from the `nameHint` key, so a host that rewords the hint
-- rewords both). Keyed by the kind table, as NAME_COLOR is, so a host's own kind never matches.
-- The client has no item-name search: GetItemInfoInstant(name) answers only for an item the player
-- carries or carried this session, and C_Spell.GetSpellInfo(name) only for a spell in the player's
-- own spellbook. Anything else reaches a name through the host's candidates alone.
local KIND_TEXT = {
  [ID_KINDS.item] = {
    notFound = "No item named '{text}' that the game can find. {hint}",
    nameHint = "Names work for items you carry (or carried this session) and ones this list "
      .. "knows; otherwise use the id or shift-click a link.",
  },
  [ID_KINDS.spell] = {
    notFound = "No spell named '{text}' in your spellbook. {hint}",
    nameHint = "Names work for spells in your spellbook and ones this list knows; otherwise use "
      .. "the id or shift-click a link.",
  },
  [ID_KINDS.currency] = {
    notFound = "No currency named '{text}' that this list knows. {hint}",
    nameHint = "Currency names work only for the currencies this list knows; otherwise use the id "
      .. "or shift-click a link.",
  },
}

--- A word for `key` in `kind`'s own set, or nil for the shared default.
local function kindText(kind, key)
  local row = KIND_TEXT[idKind(kind)]
  return row and row[key]
end

--- Fill `{name}` tokens from `fields`; a token with no field is left as written.
local function fillText(template, fields)
  return (tostring(template):gsub("{(%a+)}", function(key)
    local v = fields[key]
    if v ~= nil then return tostring(v) end
  end))
end

local function parseNumber(text)
  return tonumber(text:match("^(%d+)$"))
end

--- The id in a link of `link`'s type -- a chat link (`|Hspell:123:...`) or the bare form
--- (`spell:123`). Kind-specific on purpose: an item link typed into a spell list is not a spell.
local function parseLink(link, text)
  if not link then return nil end
  return tonumber(text:match("|H" .. link .. ":(%d+)") or text:match("^" .. link .. ":(%d+)"))
end

--- Whether typed text is a name: not a number, and not a link of any type. Only a name can match
--- an id another candidate shares, so only a name waits on IdInput's lookup; a number or a link
--- names one id and never waits. Read off the text alone, so it holds for a host kind's resolver.
local function isNameText(text)
  return not (parseNumber(text) or text:find("|H%a+:%d") or text:match("^%a+:%d+$"))
end

local function byClientName(k, text)
  if type(k.byName) ~= "function" then return nil end
  return k.byName(text)
end

--- The host's candidate ids, or none: a raising candidates() is a host bug, and it costs the name
--- step rather than the click.
local function candidateIds(candidates)
  if type(candidates) ~= "function" then return {} end
  local ok, list = pcall(candidates)
  if not ok or type(list) ~= "table" then return {} end
  return list
end

--- A case-insensitive exact name match over the ids `ids`. Two DISTINCT ids with the name are
--- ambiguous -- taking the first would hand the player one they may not have meant -- and one id
--- listed twice is still one.
local function byNameIn(k, text, ids)
  if type(k.info) ~= "function" then return nil, "notFound" end
  local want = text:lower()
  local hitId, hitName, hitIcon
  for _, id in ipairs(ids) do
    local name, icon = k.info(id)
    if type(name) == "string" and name:lower() == want and id ~= hitId then
      if hitId then return nil, "ambiguous" end
      hitId, hitName, hitIcon = id, name, icon
    end
  end
  if hitId then return hitId, hitName, hitIcon end
  return nil, "notFound"
end

--- The name matched over the host's candidates alone.
local function byCandidates(k, text, candidates)
  return byNameIn(k, text, candidateIds(candidates))
end

-- The ids the client enumerates for a named kind (the items in the bags, the spells in the
-- spellbook), or none. Assigned below with the suggestions' sources, which are this same list.
local kindSourceIds

--- The client's name hit, unless a DIFFERENT id carries the same name: a candidate, or an id the
--- client enumerates for the kind. The client answers one id for a name several share (an item's
--- crafted-quality ranks), so the hit alone would hand the player one rank they did not pick --
--- and two ranks of one potion in the bags are as shared as two ranks in the candidates.
local function unlessShared(k, text, candidates, id, name, icon)
  local ids = {}
  for _, c in ipairs(candidateIds(candidates)) do ids[#ids + 1] = c end
  for _, c in ipairs(kindSourceIds(k)) do ids[#ids + 1] = c end
  local other, why = byNameIn(k, text, ids)
  if why == "ambiguous" or (other ~= nil and other ~= id) then return nil, "ambiguous" end
  return id, name, icon
end

local RESOLVE_REASONS = { empty = true, notFound = true, ambiguous = true }

--- A host kind's own resolver, handed everything typed: a number, a link or a name. It answers
--- `id, name, icon`, or `nil, reason`; a raise or an unknown reason reads as not found.
local function customResolve(k, text, candidates)
  local ok, id, a, b = pcall(k.resolve, text, candidates)
  if not ok then return nil, "notFound" end
  if id ~= nil then return id, a, b end
  return nil, RESOLVE_REASONS[a] and a or "notFound"
end

--- Resolve typed text to an id (minor 16). Pure; published as O.ResolveId.
---
--- `kind` is "spell", "item" or "currency", or a host table `{ resolve = function(text,
--- candidates) -> id, name, icon | nil, reason; info = function(id) -> name, icon; noun; plural;
--- tooltip; loads; base }` whose resolver replaces every step below. `loads = true` with an `info`
--- says the kind's ids are items the client loads, so IdInput pre-warms and looks up its candidates
--- as it does the item kind's. `base = "item"` ("spell", "currency") says its ids are that kind's:
--- it takes the base's info, link, tooltip, loads, noun and plural where it sets none, and wears
--- its name color, its rank and the client ids it enumerates -- the spellbook or the bags, which
--- the add box suggests and the shared-name check reads; a based kind's pick is asked of its own
--- resolve, and its own `byName` is never the base's. The order, for a
--- named kind:
---   1. a number (`21562`);
---   2. a link of the kind's own type (`|Hspell:21562:...`, or the bare `spell:21562`);
---   3. the client's name lookup (spells and items; currencies have none);
---   4. a case-insensitive exact name over the ids `candidates()` returns.
--- A name is "ambiguous" when two DISTINCT ids carry it: two candidates, or the client's hit at
--- step 3 and a different candidate or a different id the client enumerates for the kind (an item
--- in the bags, a spell in the spellbook) -- an item's crafted-quality ranks share one name.
--- Returns `id, name, icon` -- a number the client cannot name still resolves, with no name, which
--- is the degraded mode -- or `nil, reason` with reason "empty", "notFound" or "ambiguous".
local function resolveId(kind, text, candidates)
  if type(text) == "number" then text = tostring(text) end
  text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
  if text == "" then return nil, "empty" end
  local k = idKind(kind)
  if type(k.resolve) == "function" then return customResolve(k, text, candidates) end

  local id = parseNumber(text) or parseLink(k.link, text)
  if id then
    if type(k.info) ~= "function" then return id end
    return id, k.info(id)
  end
  local found, name, icon = byClientName(k, text)
  if found then return unlessShared(k, text, candidates, found, name, icon) end
  return byCandidates(k, text, candidates)
end

-- The most unnamed candidates one lookup, or one build's pre-warm, asks the client for. A host's
-- candidate list can be a whole bag or an expansion's consumables; asking for thousands of items
-- at once floods the client's item-data queue for one typed name. Past the cap, the widget's next
-- window (a lookup) or next build (a pre-warm) moves on to the later candidates.
local ID_LOOKUP_CAP = 200

--- Whether this client can both load an item and name one: without either, an unnamed item stays
--- unnamed, and there is nothing to wait for.
local function itemLoadable()
  return C_Item and C_Item.GetItemNameByID and C_Item.RequestLoadItemDataByID and true or false
end

--- Whether the kind cannot name `id` yet. A raising lookup reads as named, so it is not asked for.
local function unnamedId(k, id)
  local ok, name = pcall(k.info, id)
  return ok and (type(name) ~= "string" or name == "")
end

--- The unnamed candidates, as O.UnnamedCandidates answers them, past every id the set `skip` holds.
--- Each id it examines goes into the set `mark` when one is given, so a caller passing one table
--- as both examines each id once, and a later call moves on to the ids after the cap.
local function unnamedIds(kind, candidates, skip, mark)
  local k, out, seen = idKind(kind), {}, {}
  if not (k.loads and type(k.info) == "function" and itemLoadable()) then return out end
  skip = skip or {}
  for _, id in ipairs(candidateIds(candidates)) do
    if type(id) == "number" and not seen[id] and not skip[id] then
      seen[id] = true
      if mark then mark[id] = true end
      if unnamedId(k, id) then out[#out + 1] = id end
      if #out >= ID_LOOKUP_CAP then break end
    end
  end
  return out
end

--- The candidates of a kind the client loads (items) that it cannot name yet: numbers, each once,
--- in the host's order, at most ID_LOOKUP_CAP of them. Pure; published as O.UnnamedCandidates.
--- A host kind loads when it declares `loads = true` and an `info`. None for a spell, a currency,
--- any other host kind, a raising candidates(), or a client that cannot load an item.
local function unnamedCandidates(kind, candidates)
  return unnamedIds(kind, candidates)
end

-- ── suggestions while typing (minor 16, issue #31) ────────────────────────────────────────
--
-- What IdInput's dropdown lists as the player types. Pure, and at file scope for the reason id
-- resolution is. The client has no item-name or spell-name search, so every row is an id something
-- already knows: the host's candidates(), plus what the client enumerates cheaply for the kind --
-- the items in the player's bags, the spells in the spellbook. A currency, or a host's own kind,
-- has the candidates alone.

-- At most this many rows under the box; a longer list ends in a "+N more" line.
local SUGGEST_ROWS = 10
-- A name suggests nothing under two typed characters; digits match ids from the first one.
local SUGGEST_MIN_NAME = 2
-- The most ids one render's index holds, the host's candidates first. Each is named once, on the
-- render's first keystroke; every later keystroke scans those cached names with no client call, and
-- re-reads at most ID_LOOKUP_CAP of the ids the client could not name yet.
local SUGGEST_INDEX_CAP = 2000
-- The pause after the last keystroke before the list is worked out again, in seconds.
local SUGGEST_DEBOUNCE = 0.1
-- The client's own small icon for a crafted or reagent quality tier, inline.
local QUALITY_ATLAS = "|A:Professions-Icon-Quality-Tier%d-Small:14:14|a"

--- Every item id in the backpack and the equipped bags (the reagent bag too, where the client has
--- one), slot by slot.
local function scanBags(C, out)
  local last = tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or tonumber(NUM_BAG_SLOTS) or 4
  for bag = 0, last do
    for slot = 1, tonumber(C.GetContainerNumSlots(bag)) or 0 do
      local id = C.GetContainerItemID(bag, slot)
      if type(id) == "number" then out[#out + 1] = id end
    end
  end
end

--- The item ids the player carries. None on a client without C_Container; a raise ends the scan
--- where it raised.
local function bagItemIds()
  local C, out = C_Container, {}
  if C and C.GetContainerNumSlots and C.GetContainerItemID then pcall(scanBags, C, out) end
  return out
end

--- One skill line's spells: its Spell and FutureSpell slots, never a flyout or a pet action.
local function scanSpellLine(B, line, bank, spellTypes, out)
  local info = B.GetSpellBookSkillLineInfo(line)
  if type(info) ~= "table" then return end
  local first = tonumber(info.itemIndexOffset) or 0
  for slot = first + 1, first + (tonumber(info.numSpellBookItems) or 0) do
    local item = B.GetSpellBookItemInfo(slot, bank)
    if type(item) == "table" and type(item.spellID) == "number" and spellTypes[item.itemType] then
      out[#out + 1] = item.spellID
    end
  end
end

--- The player's own spellbook bank, every skill line. Enum is read at call time, with the client's
--- values as the fallback.
local function scanSpellBook(B, out)
  local E = Enum
  local bank = E and E.SpellBookSpellBank and E.SpellBookSpellBank.Player or 0
  local types = E and E.SpellBookItemType or {}
  local spellTypes = { [types.Spell or 1] = true, [types.FutureSpell or 2] = true }
  for line = 1, tonumber(B.GetNumSpellBookSkillLines()) or 0 do
    scanSpellLine(B, line, bank, spellTypes, out)
  end
end

--- The spell ids in the player's spellbook. None on a client without C_SpellBook's enumeration.
local function spellBookIds()
  local B, out = C_SpellBook, {}
  if B and B.GetNumSpellBookSkillLines and B.GetSpellBookSkillLineInfo and B.GetSpellBookItemInfo then
    pcall(scanSpellBook, B, out)
  end
  return out
end

--- A quality tier from one of the client's two tier lookups, or nil. A raise reads as none.
local function qualityTier(fn, id)
  if type(fn) ~= "function" then return nil end
  local ok, tier = pcall(fn, id)
  if ok and type(tier) == "number" and tier > 0 then return tier end
end

--- An item's rank: its crafted-quality tier, else its reagent-quality tier, as the number a row
--- sorts by and the client's tier icon it shows. Nil for an item with neither, or a client without
--- C_TradeSkillUI.
local function itemRank(id)
  local T = C_TradeSkillUI
  if not T then return nil end
  local tier = qualityTier(T.GetItemCraftedQualityByItemInfo, id)
    or qualityTier(T.GetItemReagentQualityByItemInfo, id)
  if tier then return tier, QUALITY_ATLAS:format(tier) end
end

--- A spell's rank: the client's subtext ("Rank 2", "Racial"), shown as the client words it and
--- sorted by the number in it. Nil for a spell with none, or a client without GetSpellSubtext.
local function spellRank(id)
  local fn = C_Spell and C_Spell.GetSpellSubtext
  if type(fn) ~= "function" then return nil end
  local ok, text = pcall(fn, id)
  if not ok or type(text) ~= "string" or text == "" then return nil end
  return tonumber(text:match("%d+")) or 0, text
end

-- The named kinds' client source and rank, keyed by the kind table -- and read through decorKind
-- below, so a BASED host kind reads its base's row. A host that says `base = "spell"` has said its
-- ids ARE the client's spells, and it says that to get the base's decorations; withholding the
-- client's own list from it would leave a host that wanted nothing but its own entry tooltip with
-- an add box that suggests nothing as the player types. A host kind with NO base still matches
-- nothing here, which is the protection this table has always wanted: its ids need not be the
-- client's at all, and a list of currency ids must never be offered the spellbook. Declaring a
-- base is how a host opts in; leaving it out is how it opts out.
local SUGGEST_KIND = {
  [ID_KINDS.item]  = { sources = bagItemIds, rank = itemRank },
  [ID_KINDS.spell] = { sources = spellBookIds, rank = spellRank },
}

--- The suggestion row `k` wears: a named kind's own, a based host kind's base's, or nil for a host
--- kind with no base. Every reader below goes through this one lookup, so the client source, the
--- rank and the shared-name check can never disagree about which row a kind has.
local function suggestRow(k)
  return SUGGEST_KIND[decorKind(k)]
end

-- Declared above for the shared-name check: what resolves a name and what lists it read one source.
kindSourceIds = function(k)
  local row = suggestRow(k)
  return row and row.sources() or {}
end

--- The ids one render's index covers: the host's candidates, then the kind's client source;
--- numbers only, each once, at most SUGGEST_INDEX_CAP.
local function suggestIds(k, candidates)
  local out, seen = {}, {}
  local function take(list)
    for _, id in ipairs(list) do
      if #out >= SUGGEST_INDEX_CAP then return end
      if type(id) == "number" and not seen[id] then
        seen[id] = true
        out[#out + 1] = id
      end
    end
  end
  take(candidateIds(candidates))
  take(kindSourceIds(k))
  return out
end

--- One row's worth of `id`, or nil while the kind cannot name it. A raising lookup reads as
--- unnamed.
local function suggestEntry(k, id)
  local ok, name, icon = pcall(k.info, id)
  if not ok or type(name) ~= "string" or name == "" then return nil end
  local e = { id = id, name = name, lower = name:lower(), icon = icon }
  local row = suggestRow(k)
  if row then e.rank, e.rankLabel = row.rank(id) end
  return e
end

--- One render's index: the named entries, and the ids still unnamed. Empty for a kind with no
--- `info`, which has nothing to name a row with.
local function buildSuggestIndex(k, candidates)
  local index = { entries = {}, unnamed = {} }
  if type(k.info) ~= "function" then return index end
  for _, id in ipairs(suggestIds(k, candidates)) do
    local e = suggestEntry(k, id)
    if e then index.entries[#index.entries + 1] = e else index.unnamed[#index.unnamed + 1] = id end
  end
  return index
end

--- Read the index's unnamed ids again, the first ID_LOOKUP_CAP of them: IdInput's pre-warm or
--- lookup may have landed them since. The ones now named join the entries.
local function nameUnnamed(k, index)
  local still = {}
  for i, id in ipairs(index.unnamed) do
    local e = i <= ID_LOOKUP_CAP and suggestEntry(k, id)
    if e then index.entries[#index.entries + 1] = e else still[#still + 1] = id end
  end
  index.unnamed = still
end

--- How well the lower-case name `lower` matches the lower-case `text`: 1 the whole name, 2 its
--- start, 3 the start of a word inside it, 4 anywhere in it; nil for no match.
local function nameTier(lower, text)
  if lower == text then return 1 end
  local at = lower:find(text, 1, true)
  if not at then return nil end
  if at == 1 then return 2 end
  while at do
    if lower:sub(at - 1, at - 1):find("[^%w']") then return 3 end
    at = lower:find(text, at + 1, true)
  end
  return 4
end

--- The dropdown's order: by tier, then shorter names first, then by name, then by rank (none is
--- 0), then by id. One name's ranks tie on everything before rank, so they sit together.
local function suggestBefore(a, b)
  if a.tier ~= b.tier then return a.tier < b.tier end
  if #a.lower ~= #b.lower then return #a.lower < #b.lower end
  if a.lower ~= b.lower then return a.lower < b.lower end
  local ra, rb = a.rank or 0, b.rank or 0
  if ra ~= rb then return ra < rb end
  return a.id < b.id
end

--- The length of `text` in characters rather than bytes: a UTF-8 continuation byte is not one.
local function charCount(text)
  return #(text:gsub("[\128-\191]", ""))
end

--- The entries whose id starts with `digits`, ascending.
local function byIdPrefix(entries, digits)
  local out = {}
  for _, e in ipairs(entries) do
    if tostring(e.id):sub(1, #digits) == digits then out[#out + 1] = e end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

--- The entries the trimmed `text` suggests, in the dropdown's order: ids by prefix for digits,
--- names by tier otherwise, and nothing for a name under SUGGEST_MIN_NAME characters.
local function matchSuggestions(entries, text)
  if text:match("^%d+$") then return byIdPrefix(entries, text) end
  if charCount(text) < SUGGEST_MIN_NAME then return {} end
  local want, out = text:lower(), {}
  for _, e in ipairs(entries) do
    e.tier = nameTier(e.lower, want)
    if e.tier then out[#out + 1] = e end
  end
  table.sort(out, suggestBefore)
  return out
end

--- Attach the id resolution, suggestion and input members to one instance. Called by
--- lib.__AttachWidgets, which hands over what the members below share with it: `w.print` (the
--- shell's sink), `w.refused` (the combat refusal), and its `w.startRow` and
--- `w.renderRowGuarded`. Returns the locals OptionsIdList.lua's members use, for
--- lib.__AttachWidgets to pass to lib.__AttachIdList.
function lib.__AttachIds(O, w)
  local print, refused = w.print, w.refused
  local startRow, renderRowGuarded = w.startRow, w.renderRowGuarded

  -- ── the id input (minor 16) ─────────────────────────────────────────────────────────────
  --
  -- The edit box and the button beside it sum to 0.98, not 1, for the reason BUTTON_PAIR_REL sits
  -- under half: the widget that ends at the right edge is clipped by the ScrollFrame's clip
  -- rectangle (options-ui-§8). An entry line uses the same two widths, name then action.
  local ID_MAIN_REL   = 0.78
  local ID_ACTION_REL = 0.20
  -- THE ADD BUTTON IS SIZED TO THE BOX BESIDE IT, not left at AceGUI's default (minor 30).
  --
  -- The two were already CENTERED on each other and always had been: AceGUI's labeled EditBox
  -- publishes `self.alignoffset = 30` (widgets/AceGUIWidget-EditBox.lua's SetLabel) and Flow
  -- anchors the next widget by `frameoffset - lastframeoffset`, so the button's middle lands on
  -- the box's middle to the pixel. What was wrong was the HEIGHT. `InputBoxTemplate` draws its
  -- border art 20 tall; AceGUI's Button is a flat `SetHeight(24)`. Centered, a 24 against a 20
  -- overhangs 2px at each end -- and the overhangs do not read alike, because the top one sits
  -- against the gold caption above the row and the bottom one against empty dark. So the button
  -- read as sitting HIGHER than the box rather than as being taller than it, which is what the
  -- owner reported from the live panel (2026-09-22) and what a measurement of the screenshot
  -- said instead: box 20 tall, button 24, centers one pixel apart.
  --
  -- 20 is Blizzard's number, not a tuned one -- it is the height of InputBoxTemplate's border
  -- art. The centering stays AceGUI's, through the alignoffset it already publishes; this only
  -- stops the button being taller than the thing it is centered on.
  local ID_ADD_H      = 20
  -- The status line's failure color, and the gray an entry's id is drawn in after its name.
  local ID_WARN_R, ID_WARN_G, ID_WARN_B = 1, 0.5, 0
  local ID_GRAY = "|cff808080"

  O.ResolveId = resolveId
  O.UnnamedCandidates = unnamedCandidates
  -- The default name hints, per named kind, for a host's tooltip. A copy per instance, so a host
  -- that rewrites one changes its own and no other host's; the widgets read `spec.strings.nameHint`
  -- and their own defaults, never this table.
  O.ID_NAME_HINT = {}
  for name, k in pairs(ID_KINDS) do O.ID_NAME_HINT[name] = KIND_TEXT[k].nameHint end

  -- A typed NAME, while some item candidates are still unnamed, is looked up whether or not it
  -- found an id: a hit may be one rank of a name an unnamed candidate also carries. Those items
  -- are asked for, a window of at most ID_LOOKUP_CAP at a time, and the text is tried once more
  -- when they land. Each window's wait is bounded as IdList's is -- a check 0.4 s after each ask,
  -- at most LOOKUP_ROUNDS asks -- and a lookup runs at most LOOKUP_WINDOWS windows. The status
  -- line reads the neutral `looking` words in the meantime.
  local LOOKUP_ROUNDS = 5
  local LOOKUP_WINDOWS = 5
  local ID_NEUTRAL_R, ID_NEUTRAL_G, ID_NEUTRAL_B = 1, 1, 1
  -- The candidate ids this instance's pre-warm has examined: each is read, and asked for if the
  -- client cannot name it, once a session, however many renders draw the input.
  local prewarmed = {}
  -- The ids a lookup asked for LOOKUP_ROUNDS times without their landing: retired or invalid.
  -- Every later window passes over them, so they cannot hold the cap for good.
  local deadIds = {}

  local function idText(spec, key, fields)
    local t = spec.strings and spec.strings[key] or kindText(spec.kind, key) or ID_TEXT[key]
    return fillText(t, fields or {})
  end

  --- Call a host callback, reporting a raise rather than letting it into AceGUI's dispatch.
  --- Answers whether it ran and returned.
  local function callHost(fn, ...)
    if type(fn) ~= "function" then return false end
    -- Refused in combat (minor 23), answering false: an add puts its text back, a remove rebuilds
    -- nothing.
    if refused() then return false end
    local ok, err = pcall(fn, ...)
    if not ok then print(lib.STRINGS.BUTTON_FAILED:format(tostring(err))) end
    return ok
  end

  --- Disable `widget` when it is drawn inside a disabled render, as InlineButtonPair does.
  local function disableIfRender(ctx, widget)
    if ctx.__renderDisabled and widget.SetDisabled then widget:SetDisabled(true) end
  end

  --- Run `fn` with `ctx.__renderDisabled` held for the call, as O.ChoiceGrid does: set by
  --- `disabled` or inherited, restored on the way out, a raise included.
  local function underDisable(ctx, disabled, fn, ...)
    local outer = ctx.__renderDisabled
    ctx.__renderDisabled = (disabled or outer) and true or nil
    local ok, a, b, c, e = pcall(fn, ...)
    ctx.__renderDisabled = outer
    if not ok then error(a, 0) end
    return a, b, c, e
  end

  --- Write the status line, remembering what it says: AceGUI's Label has no getter, and a raising
  --- onAdd puts back what was there.
  local function showStatus(parts, text)
    parts.shown = text
    parts.status:SetText(text)
  end

  local function trimmed(text)
    return type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
  end

  -- The suggestion dropdown's answer to a refused shared name, defined with the dropdown below.
  local offerRanks

  --- Say why nothing was added, in orange; the text stays so the player can correct it. A name
  --- several ids share is refused with "pick one from the list", so the list is put up for it.
  local function reportFailure(spec, parts, reason, typed)
    local noun, plural = kindWords(idKind(spec.kind))
    showStatus(parts, idText(spec, reason, { noun = noun, plural = plural, text = typed,
                                             hint = idText(spec, "nameHint") }))
    if parts.status.SetColor then parts.status:SetColor(ID_WARN_R, ID_WARN_G, ID_WARN_B) end
    if reason == "ambiguous" then offerRanks(parts, typed) end
  end

  --- Hand a resolved id to the host. The box and the status line are cleared BEFORE onAdd, because
  --- a host whose onAdd redraws the page has released both into AceGUI's pool by the time it
  --- returns, and the pool may already have handed them to the new render. Nothing touches either
  --- widget after a clean onAdd. A raising one adds nothing, so the text goes back and the status
  --- line reads `restore`. Then `sub.afterAdd` -- IdList's rebuild.
  local function addResolved(ctx, spec, parts, id, sub, restore)
    showStatus(parts, "")
    parts.edit:SetText("")
    if callHost(spec.onAdd, id) then
      if sub.afterAdd then sub.afterAdd(ctx) end
      return
    end
    parts.edit:SetText(type(sub.text) == "string" and sub.text or sub.typed)
    showStatus(parts, restore)
  end

  --- Whether the kind names `id` yet. A raising lookup reads as not yet.
  local function entryNamed(k, id)
    if type(k.info) ~= "function" then return false end
    local ok, name = pcall(k.info, id)
    return ok and type(name) == "string" and name ~= ""
  end

  --- Ask the client for items: through LibKa0s-Item-1.0's LoadItem when it is loaded (the first id
  --- carries `cb`), else straight through C_Item, with C_Timer for `cb`. `cb`, when given, runs once,
  --- 0.4 s on, whether or not they arrived. Answers false, asking nothing, on a client that cannot
  --- ask -- or cannot call back, when a callback is wanted.
  local function requestItems(ids, cb)
    if not (C_Item and C_Item.RequestLoadItemDataByID) then return false end
    if cb and not (C_Timer and C_Timer.After) then return false end
    local Item = LibStub and LibStub("LibKa0s-Item-1.0", true)
    local load = Item and Item.LoadItem
    for i, id in ipairs(ids) do
      if load then load(id, i == 1 and cb or nil) else C_Item.RequestLoadItemDataByID(id) end
    end
    if cb and not load then C_Timer.After(0.4, cb) end
    return true
  end

  --- Ask, once a session per instance, for the item candidates the client cannot name yet, so a
  --- name among them resolves on the first try. At most ID_LOOKUP_CAP a build, each build moving on
  --- past the ids the last one examined, so a redraw reads no candidate twice; nothing waits.
  local function prewarm(spec)
    if type(spec.candidates) ~= "function" then return end
    local fresh = unnamedIds(spec.kind, spec.candidates, prewarmed, prewarmed)
    if #fresh > 0 then requestItems(fresh) end
  end

  --- The last try: the same text once more, now its candidates have had their chance to load. No
  --- second lookup -- it adds, or it says why.
  local function finishLookup(ctx, spec, parts, sub)
    local id, reason = resolveId(spec.kind, sub.typed, spec.candidates)
    if id == nil then return reportFailure(spec, parts, reason, sub.typed) end
    addResolved(ctx, spec, parts, id, sub, "")
  end

  --- Whether the box still holds what was submitted. A widget with no getter is taken at its word.
  local function stillTyped(parts, typed)
    if not parts.edit.GetText then return true end
    return trimmed(parts.edit:GetText()) == typed
  end

  --- The ids of `ids` the kind still cannot name.
  local function stillUnnamed(k, ids)
    local out = {}
    for _, id in ipairs(ids) do
      if not entryNamed(k, id) then out[#out + 1] = id end
    end
    return out
  end

  --- Ask for the lookup's next window: the unnamed candidates no earlier window gave up on, at most
  --- ID_LOOKUP_CAP. Answers false, asking nothing, when there are none or the client cannot ask.
  local function askWindow(spec, lookup)
    local ids = unnamedIds(spec.kind, spec.candidates, deadIds)
    if #ids == 0 then return false end
    lookup.ids, lookup.rounds, lookup.windows = ids, 0, lookup.windows + 1
    return requestItems(ids, lookup.check)
  end

  --- A lookup's check, 0.4 s after each ask. Nothing for a lookup a newer submit or a release has
  --- dropped; a box the player has typed over drops it and clears the looking line. Otherwise it
  --- waits while any id of the window is still unnamed and asks have not run out -- retrying as
  --- soon as ONE lands could add one rank of a name the next rank to land also carries. An id still
  --- unnamed when the asks run out is dead, and the next window moves past it. With no window left,
  --- the text is tried once more.
  local function checkLookup(ctx, spec, parts, lookup)
    if parts.lookup ~= lookup then return end
    if not stillTyped(parts, lookup.sub.typed) then
      parts.lookup = nil
      return showStatus(parts, "")
    end
    lookup.rounds = lookup.rounds + 1
    local waiting = stillUnnamed(idKind(spec.kind), lookup.ids)
    if #waiting > 0 and lookup.rounds < LOOKUP_ROUNDS then
      lookup.ids = waiting
      if requestItems(waiting, lookup.check) then return end
    end
    for _, id in ipairs(waiting) do deadIds[id] = true end
    if lookup.windows < LOOKUP_WINDOWS and askWindow(spec, lookup) then return end
    parts.lookup = nil
    finishLookup(ctx, spec, parts, lookup.sub)
  end

  --- Start a lookup for a typed name: answers false, starting none, when no candidate is unnamed
  --- (bar the dead) or the client cannot ask.
  local function startLookup(ctx, spec, parts, sub)
    local lookup = { windows = 0, sub = sub }
    lookup.check = function() checkLookup(ctx, spec, parts, lookup) end
    parts.lookup = lookup
    if not askWindow(spec, lookup) then
      parts.lookup = nil
      return false
    end
    local noun, plural = kindWords(idKind(spec.kind))
    showStatus(parts, idText(spec, "looking", { noun = noun, plural = plural, text = sub.typed }))
    if parts.status.SetColor then parts.status:SetColor(ID_NEUTRAL_R, ID_NEUTRAL_G, ID_NEUTRAL_B) end
    return true
  end

  --- Resolve what was typed and hand the id to the host. A NAME -- one that found an id or found
  --- nothing -- while some candidates are still unnamed is looked up first (startLookup): a hit may
  --- be one rank of a name an unnamed candidate shares. A number or a link never waits. Any other
  --- failure says why on the status line. A submit replaces any lookup still pending.
  local function submitId(ctx, spec, parts, text, afterAdd)
    parts.lookup = nil
    parts.offer = nil
    local sub = { text = text, typed = trimmed(text), afterAdd = afterAdd }
    local id, reason = resolveId(spec.kind, sub.typed, spec.candidates)
    local byName = (id ~= nil or reason == "notFound") and isNameText(sub.typed)
    if byName and startLookup(ctx, spec, parts, sub) then return end
    if id ~= nil then return addResolved(ctx, spec, parts, id, sub, parts.shown or "") end
    reportFailure(spec, parts, reason, sub.typed)
  end

  -- ── the suggestion dropdown (minor 16, issue #31) ────────────────────────────────────────
  --
  -- One dropdown per instance, built the first time it shows and shared by every IdInput the
  -- instance draws: only the box the player is typing in shows one. `suggest.owner` is that box's
  -- parts. The ten rows and the "+N more" line are built with the frame and reused for every
  -- list, so a redraw of the page builds no frame. It is parented to UIParent at FULLSCREEN_DIALOG
  -- strata and clamped to the screen, so the settings panel's scroll frame cannot clip it and it
  -- draws above the panel. Escape, focus leaving the box, the box hiding with its panel, and the
  -- box's release close it, and drop an update still waiting on the debounce. A shared name the
  -- box refuses puts its ranks up to pick from. Plain frames, nothing protected: none of it is
  -- refused in combat.
  local SUGGEST_ROW_H = 18
  local SUGGEST_PAD   = 6
  local SUGGEST_ICON  = 16
  local SUGGEST_MIN_W = 260
  local SUGGEST_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
  local SUGGEST_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  }
  local ARROW_STEP = { UP = -1, DOWN = 1 }
  local suggest = {}
  -- The frames already hooked, per script. AceGUI pools its widgets, so a box another page drew
  -- is hooked once, and every hook finds its box through `boxParts`.
  local hookedFrames = setmetatable({}, { __mode = "k" })
  -- The box each hooked frame was drawn for last: its input frame and its own frame both map to
  -- that box's parts, so a hook acts for the render the pooled frame belongs to now.
  local boxParts = setmetatable({}, { __mode = "k" })

  --- Close the dropdown if `parts` owns it, and drop any update still waiting on the debounce.
  local function closeSuggest(parts)
    parts.suggestSeq = (parts.suggestSeq or 0) + 1
    parts.sel = nil
    if suggest.owner ~= parts then return end
    suggest.owner = nil
    if suggest.frame then suggest.frame:Hide() end
  end

  --- The id a picked row adds: a based host kind's own `resolve` is asked about it first, as its
  --- digits, because its rows are named through the library's kind while what it takes is the
  --- host's call. Answers `id` or `nil, reason`. Any other kind's row adds its id as it stands.
  local function pickedId(spec, id)
    local k = idKind(spec.kind)
    if not (viewHost[k] and type(k.resolve) == "function") then return id end
    local resolved, reason = resolveId(spec.kind, tostring(id), spec.candidates)
    if resolved == nil then return nil, reason end
    return resolved
  end

  --- Add a picked row's id the way a typed add goes: the box and the status line cleared, then
  --- onAdd, then IdList's rebuild. A pick names one id, so no lookup runs. A based host kind's
  --- refusal is reported as a submit's is, and the text stays.
  local function pickSuggestion(parts, entry)
    closeSuggest(parts)
    parts.lookup = nil
    parts.offer = nil
    local id, reason = pickedId(parts.spec, entry.id)
    if id == nil then return reportFailure(parts.spec, parts, reason, tostring(entry.id)) end
    local text = parts.edit.GetText and parts.edit:GetText() or ""
    addResolved(parts.ctx, parts.spec, parts, id,
      { text = text, typed = trimmed(text), afterAdd = parts.afterAdd }, parts.shown or "")
  end

  --- The keyboard highlight: the row's own highlight texture, locked on. `selected` records it.
  local function markRow(row, on)
    row.selected = on
    if on then row:LockHighlight() else row:UnlockHighlight() end
  end

  --- A line at row position `i`: an icon, then the label, left-aligned on one line.
  local function newSuggestLine(frame, i, font)
    local line = CreateFrame("Button", nil, frame)
    line:SetHeight(SUGGEST_ROW_H)
    local y = -SUGGEST_PAD - (i - 1) * SUGGEST_ROW_H
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", SUGGEST_PAD, y)
    line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SUGGEST_PAD, y)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(SUGGEST_ICON, SUGGEST_ICON)
    line.icon:SetPoint("LEFT", line, "LEFT", 2, 0)
    line.label = line:CreateFontString(nil, "OVERLAY", font)
    line.label:SetPoint("LEFT", line, "LEFT", SUGGEST_ICON + 6, 0)
    line.label:SetPoint("RIGHT", line, "RIGHT", -2, 0)
    line.label:SetJustifyH("LEFT")
    line.label:SetWordWrap(false)
    line:Hide()
    return line
  end

  --- A row the player can click: it adds its entry for whichever box owns the dropdown then.
  local function newSuggestRow(frame, i)
    local row = newSuggestLine(frame, i, "GameFontHighlightSmall")
    row:SetHighlightTexture(SUGGEST_HIGHLIGHT, "ADD")
    row:SetScript("OnClick", function(self)
      local owner = suggest.owner
      if owner and self.entry then pickSuggestion(owner, self.entry) end
    end)
    return row
  end

  --- The dropdown, built once per instance.
  local function suggestFrame()
    if suggest.frame then return suggest.frame end
    local f = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if f.SetBackdrop then
      f:SetBackdrop(SUGGEST_BACKDROP)
      f:SetBackdropColor(0, 0, 0, 0.92)
    end
    f.rows = {}
    for i = 1, SUGGEST_ROWS do f.rows[i] = newSuggestRow(f, i) end
    -- The "+N more" line: a label, not a choice.
    f.more = newSuggestLine(f, SUGGEST_ROWS + 1, "GameFontDisableSmall")
    f.more:EnableMouse(false)
    f:Hide()
    suggest.frame = f
    return f
  end

  --- A row's text: the name (an item's in its quality color), its rank where it has one, and its
  --- id in gray -- which is all that tells two unranked ids of one name apart.
  local function suggestLabel(k, e)
    local name = e.name
    local color = nameColor(k, e.id)
    if color then name = color .. name .. "|r" end
    if e.rankLabel then name = name .. " " .. e.rankLabel end
    local text = name .. " " .. ID_GRAY .. "(" .. tostring(e.id) .. ")|r"
    -- THE HOST'S TAG (minor 28), after the id. `rank` beside it is the LIBRARY's answer about an
    -- id -- a spell's rank, an item's quality -- and a host cannot supply one; this is the other
    -- half, a short word the host knows and the library cannot.
    --
    -- IT IS FOR WARNING BEFORE THE CLICK. Aura Master's case is the one that asked for it: an id
    -- can be a spell's CAST rather than the aura it applies, which matches nothing, and the host
    -- knew that before the player picked the row and could only say so afterwards. A tag on the
    -- row turns a correction into a choice.
    --
    -- SHORT, AND THE HOST'S OWN COLOR. A suggestion row is one line at a fixed height and the
    -- name has already spent most of it, so this is a word or two and is not wrapped, truncated or
    -- measured -- a host that writes a sentence here gets a sentence running off its row and that
    -- is the host's to fix. The library adds no color of its own, because the tag's whole job is
    -- to stand out from the name beside it and only the host knows what it is saying.
    if type(k.suggestTag) == "function" then
      local ok, tag = pcall(k.suggestTag, e.id)
      if ok and type(tag) == "string" and tag ~= "" then
        text = text .. " " .. tag
      end
    end
    return text
  end

  --- Show `entry` on `row`, or hide the row for none. `entry` and `labelText` record what it shows.
  local function fillRow(k, row, entry)
    row.entry = entry
    markRow(row, false)
    if not entry then
      row.labelText = nil
      return row:Hide()
    end
    row.labelText = suggestLabel(k, entry)
    row.label:SetText(row.labelText)
    row.icon:SetTexture(entry.icon)
    row:Show()
  end

  local function fillMore(spec, more, left)
    if left <= 0 then
      more.labelText = nil
      return more:Hide()
    end
    more.labelText = idText(spec, "more", { count = left })
    more.label:SetText(more.labelText)
    more:Show()
  end

  --- The box's width in the dropdown's own units: a panel scaled apart from UIParent draws the box
  --- at another scale than the dropdown. A scale the client does not answer is taken as the same.
  local function boxWidth(f, anchor)
    local width = anchor and anchor.GetWidth and anchor:GetWidth()
    if type(width) ~= "number" then return 0 end
    local from = anchor.GetEffectiveScale and anchor:GetEffectiveScale()
    local to = f.GetEffectiveScale and f:GetEffectiveScale()
    if type(from) == "number" and type(to) == "number" and from > 0 and to > 0 then
      return width * from / to
    end
    return width
  end

  --- Size the dropdown to `lines` lines and hang it under the box's input.
  local function placeSuggest(f, edit, lines)
    local anchor = edit.editbox or edit.frame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    f:SetWidth(math.max(boxWidth(f, anchor), SUGGEST_MIN_W))
    f:SetHeight(lines * SUGGEST_ROW_H + 2 * SUGGEST_PAD)
  end

  local function showSuggestions(parts, matches)
    local f = suggestFrame()
    suggest.owner, parts.matches, parts.sel = parts, matches, nil
    local k = idKind(parts.spec.kind)
    for i, row in ipairs(f.rows) do fillRow(k, row, matches[i]) end
    local rows = math.min(#matches, SUGGEST_ROWS)
    fillMore(parts.spec, f.more, #matches - rows)
    placeSuggest(f, parts.edit, rows + (#matches > rows and 1 or 0))
    f:Show()
  end

  --- Up and Down move the highlight over the rows, wrapping; from none, Down takes the first row
  --- and Up the last. The "+N more" line is never highlighted.
  local function moveSelection(parts, step)
    local n = math.min(#(parts.matches or {}), SUGGEST_ROWS)
    if n == 0 then return end
    local sel = parts.sel
    if sel then sel = (sel - 1 + step) % n + 1 elseif step > 0 then sel = 1 else sel = n end
    parts.sel = sel
    for i, row in ipairs(suggest.frame.rows) do markRow(row, i == sel) end
  end

  --- The parts owning the dropdown, when `frame` is its box's input or its box's frame.
  local function ownerOf(frame)
    local o = boxParts[frame]
    if o and suggest.owner == o then return o end
  end

  --- Whether the pointer is over the dropdown: focus lost to a click on a row keeps it open for
  --- the click. Only a real `true` counts.
  local function pointerOnSuggest()
    local f = suggest.frame
    return f ~= nil and f.IsMouseOver ~= nil and f:IsMouseOver() == true
  end

  --- Whether `parts` may show the dropdown: not released, not hidden since its panel last showed,
  --- and holding the keys. Shown again is read off the frame, because AceGUI's EditBox sets its own
  --- frame's OnShow script and would drop a hook there. Only a real `false` from HasFocus counts as
  --- the keys being elsewhere.
  local function canSuggest(parts)
    if parts.released then return false end
    if parts.hidden then
      local f = parts.edit.frame
      if not (f and f.IsVisible and f:IsVisible() == true) then return false end
      parts.hidden = nil
    end
    local input = parts.edit.editbox
    return not (input and input.HasFocus and input:HasFocus() == false)
  end

  --- Work the list out for `text` and show it, or close the dropdown when nothing matches. The
  --- render's index is built on its first keystroke; each later one re-reads the unnamed items.
  local function updateSuggest(parts, text)
    local k = idKind(parts.spec.kind)
    if not parts.index then
      parts.index = buildSuggestIndex(k, parts.spec.candidates)
    elseif k.loads then
      nameUnnamed(k, parts.index)
    end
    local matches = matchSuggestions(parts.index.entries, trimmed(text))
    if #matches > 0 then return showSuggestions(parts, matches) end
    -- Whichever box showed it, the player is typing here now.
    if suggest.owner then closeSuggest(suggest.owner) end
  end

  --- A shared name refused (reportFailure, from a submit or a lookup's last try): its ranks are
  --- listed for the player to pick from, and listed again when focus comes back to a box still
  --- holding the name. Refused by Add, the box gets the keys back first, so Up, Down and Enter
  --- reach the list. Enter with nothing highlighted refuses again, so no rank is added unpicked.
  offerRanks = function(parts, typed)
    parts.offer = typed
    if parts.refocus and parts.edit.SetFocus then parts.edit:SetFocus() end
    if canSuggest(parts) then updateSuggest(parts, typed) end
  end

  --- Focus back in a box: a refused shared name it still holds lists its ranks again.
  local function reoffer(parts)
    if not parts.offer or suggest.owner == parts then return end
    if not stillTyped(parts, parts.offer) then
      parts.offer = nil
      return
    end
    if canSuggest(parts) then updateSuggest(parts, parts.offer) end
  end

  --- Focus lost to a click on the dropdown. A row's click picks and closes it; a click anywhere
  --- else on it (the backdrop, the "+N more" line) would leave it open under a box without the
  --- keys, where Escape cannot reach it. So the box takes them back on the next frame, unless a
  --- pick has closed the dropdown by then.
  local function refocusLater(parts)
    local function refocus()
      local input = parts.edit.editbox
      if suggest.owner == parts and not parts.released and input and input.SetFocus then
        input:SetFocus()
      end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, refocus) else refocus() end
  end

  local function hookOnce(frame, script, fn)
    if not (frame and frame.HookScript) then return end
    local done = hookedFrames[frame] or {}
    hookedFrames[frame] = done
    if done[script] then return end
    done[script] = true
    frame:HookScript(script, fn)
  end

  --- The keys, the focus and the hiding AceGUI's EditBox has no callback for, hooked once per
  --- pooled frame on its input frame and its own frame. Each hook acts for the box its frame was
  --- drawn for last, and the arrows only while that box owns the dropdown. Leaving -- Escape,
  --- focus lost, the frame hidden -- drops that box's pending update whether or not it shows the
  --- dropdown yet, so a debounce cannot put one up under a box the player has left. A host's AceGUI
  --- without the input frame gets no keys, and the mouse still picks.
  local function hookBox(edit)
    hookOnce(edit.editbox, "OnArrowPressed", function(self, key)
      local o = ownerOf(self)
      if o and ARROW_STEP[key] then moveSelection(o, ARROW_STEP[key]) end
    end)
    hookOnce(edit.editbox, "OnEscapePressed", function(self)
      local p = boxParts[self]
      if p then closeSuggest(p) end
    end)
    hookOnce(edit.editbox, "OnEditFocusLost", function(self)
      local p = boxParts[self]
      if not p then return end
      if suggest.owner == p and pointerOnSuggest() then return refocusLater(p) end
      closeSuggest(p)
    end)
    hookOnce(edit.editbox, "OnEditFocusGained", function(self)
      local p = boxParts[self]
      if p then reoffer(p) end
    end)
    hookOnce(edit.frame, "OnHide", function(self)
      local p = boxParts[self]
      if not p then return end
      p.hidden = true
      closeSuggest(p)
    end)
  end

  --- Drop `parts`' keyboard highlight, and draw its row plain when `parts` owns the dropdown.
  local function dropHighlight(parts)
    if parts.sel == nil then return end
    parts.sel = nil
    if suggest.owner ~= parts then return end
    for _, row in ipairs(suggest.frame.rows) do markRow(row, false) end
  end

  --- A keystroke: the list is worked out SUGGEST_DEBOUNCE after the last one, for the text then,
  --- if the box is still there to show it under. The highlight goes at once: until the debounce
  --- runs the rows are the old text's, and Enter must not take one the new text no longer matches.
  local function onTyped(parts, text)
    parts.suggestSeq = (parts.suggestSeq or 0) + 1
    parts.offer = nil
    dropHighlight(parts)
    local seq = parts.suggestSeq
    local function run()
      if parts.suggestSeq == seq and canSuggest(parts) then updateSuggest(parts, text) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(SUGGEST_DEBOUNCE, run) else run() end
  end

  local function drawIdInput(ctx, parent, spec, afterAdd)
    local group = startRow(O)
    local eb = O.AceGUI:Create("EditBox")
    eb:SetLabel(spec.label or "")
    eb:SetRelativeWidth(ID_MAIN_REL)
    -- AceGUI's EditBox grows its own Okay button on a change; Add is the button here.
    if eb.DisableButton then eb:DisableButton(true) end
    local add = O.AceGUI:Create("Button")
    add:SetText(idText(spec, "add"))
    add:SetRelativeWidth(ID_ACTION_REL)
    -- AFTER SetText, which does not touch the height, and after SetRelativeWidth, which Flow
    -- re-applies on layout -- the height it does not re-apply, so this one sticks.
    add:SetHeight(ID_ADD_H)
    local status = O.AceGUI:Create("Label")
    status:SetFullWidth(true)
    status:SetText("")
    disableIfRender(ctx, eb)
    disableIfRender(ctx, add)

    local parts = { edit = eb, status = status, ctx = ctx, spec = spec, afterAdd = afterAdd }
    -- The hooks find the box from its frames; a pooled frame answers for this render from now on.
    if eb.editbox then boxParts[eb.editbox] = parts end
    if eb.frame then boxParts[eb.frame] = parts end
    -- A released box drops its pending lookup and its suggestions: AceGUI's pool may hand the box
    -- and its status line to another page before the lookup's check or the debounce runs.
    -- The pooled frame outlives the render, and `boxParts` keeps these parts with it until this
    -- instance draws on that frame again, so the index (up to 2000 entries) and the list go now.
    eb:SetCallback("OnRelease", function()
      parts.lookup = nil
      parts.released = true
      closeSuggest(parts)
      parts.index, parts.matches = nil, nil
    end)
    eb:SetCallback("OnTextChanged", function(_, _, text) onTyped(parts, text) end)
    -- Enter takes the highlighted row; with none, it submits what was typed, as it always has --
    -- so a name several ranks share is still refused, never one rank added for the player.
    eb:SetCallback("OnEnterPressed", function(_, _, text)
      if suggest.owner == parts and parts.sel then
        return pickSuggestion(parts, parts.matches[parts.sel])
      end
      closeSuggest(parts)
      submitId(ctx, spec, parts, text, afterAdd)
    end)
    add:SetCallback("OnClick", function()
      closeSuggest(parts)
      -- A shared name refused here hands the box the keys, so the list it puts up can be picked.
      parts.refocus = true
      submitId(ctx, spec, parts, eb.GetText and eb:GetText() or "", afterAdd)
      parts.refocus = nil
    end)
    hookBox(eb)
    O.AttachTooltip(eb, spec.label, spec.tooltip)
    O.AttachTooltip(add, spec.label, spec.tooltip)
    group:AddChild(eb)
    group:AddChild(add)
    group:AddChild(status)
    parent:AddChild(group)
    prewarm(spec)
    return group, eb, add, status
  end

  --- One line an id is added through (minor 16): an edit box taking a number, a shift-clicked link
  --- or a name, an Add button beside it, and a status line under both. Enter or Add resolves the
  --- text through O.ResolveId and hands the id to `spec.onAdd`; the widget never writes a path, so
  --- the host owns storage and its shape. The box and the status line are cleared before onAdd
  --- runs, so onAdd may redraw the page synchronously; a raising onAdd gets both back. It does NOT
  --- redraw anything after an add -- a host that draws its own rows redraws them itself. O.IdList
  --- is this plus the entry lines, and it does.
  ---
  --- Item candidates the client has not cached have no name to match. Drawing the input asks for up
  --- to 200 of them (each id read once a session per instance; the next build moves on to the next
  --- ones), and a typed name -- found or not -- while some are unnamed is looked up: they are asked
  --- for again, 200 a window, the status line reads `looking`, and the text is tried once more when
  --- they land (five asks at 0.4 s a window, at most five windows; an id that never lands is
  --- skipped from then on). A number or a link never waits. A new submit, a box the player types
  --- over, or a released box drops the lookup.
  ---
  --- spec = {
  ---   kind       = "spell" | "item" | "currency", or a host table (see O.ResolveId);
  ---   onAdd      = function(id), called once per successful add;
  ---   candidates = optional function() -> ids, searched by name when the client cannot look one up;
  ---   label, tooltip = the edit box's label and both widgets' tooltip;
  ---   strings    = optional overrides of the words (add, empty, notFound, ambiguous, looking,
  ---                nameHint);
  ---   disabled   = optional; drawn disabled, as ChoiceGrid's is. A disabled render is inherited.
  --- }
  ---
  --- `parent` defaults to the page's scroll. Returns the group, the edit box, the button and the
  --- status label; nil, drawing nothing, with no AceGUI.
  function O.IdInput(ctx, parent, spec)
    parent = parent or O.EnsureScroll(ctx)
    if not (parent and O.AceGUI) then return nil end
    spec = spec or {}
    return underDisable(ctx, spec.disabled, drawIdInput, ctx, parent, spec, nil)
  end

  -- What OptionsIdList.lua's members reach, and nothing else. The list draws this file's input at
  -- its head (drawIdInput), and shares its words, its host-call guard and its kind lookups.
  return {
    print = print, refused = refused, startRow = startRow, renderRowGuarded = renderRowGuarded,
    ID_MAIN_REL = ID_MAIN_REL, ID_ACTION_REL = ID_ACTION_REL, ID_GRAY = ID_GRAY,
    idKind = idKind, kindWords = kindWords, nameColor = nameColor, idText = idText,
    callHost = callHost, disableIfRender = disableIfRender, underDisable = underDisable,
    entryNamed = entryNamed, drawIdInput = drawIdInput,
  }
end
