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
-- Minor 2: a refused host callback is named "id list change", for the shell's Cfg line (gap G3).
-- Minor 3: O.__closeOwnedSuggest, which OptionsCombat.lua's O.__releaseOwnedFocus calls at the
-- start of combat, closes a suggestion list one of the instance's pages opened (BAN-S11).
-- Minor 4: a registered skin owner's suggestion list takes its popup colors on every open
-- (S.MenuFrame, `popup`) after its own backdrop (LK-07 of the skinning run).
-- Minor 5: on a registered skin owner's page the suggestion rows wear the skin too, on every open:
-- each row's label `menu.text` in the body face (S.Text; the dropdown menu's rows' color), the
-- "+N more" line `text.disabled`, each row's highlight art `list.hoverArt` (O.__hoverArt), and the
-- gray every id is drawn in (here and in the id list, through the `idGray` this file hands
-- OptionsIdList.lua) the owner's `text.disabled`, `|cff808080` exactly in Ka0s Default. An
-- owner-less page and an owner ignoring its settings panel draw the templates, the client's art and
-- `|cff808080` (LK-06c of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS, ruling R-5,
-- decisions D-13 and D-14).
-- Minor 6: the suggestion half moved out, unchanged, to OptionsIdSuggest.lua (LK-M2-PEEL of
-- Ka0sAddonsCommonTasks docs/2026-10-31-FINDINGS_REMEDIATION, the seam CLAUDE.md's census named).
local IDS_MINOR = 6
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

--- The client's name hit, unless a DIFFERENT id carries the same name: a candidate, or an id the
--- client enumerates for the kind. The client answers one id for a name several share (an item's
--- crafted-quality ranks), so the hit alone would hand the player one rank they did not pick --
--- and two ranks of one potion in the bags are as shared as two ranks in the candidates.
local function unlessShared(k, text, candidates, id, name, icon)
  local ids = {}
  for _, c in ipairs(candidateIds(candidates)) do ids[#ids + 1] = c end
  -- The ids the client enumerates for a named kind (the items in the bags, the spells in the
  -- spellbook), or none: OptionsIdSuggest.lua's, with the suggestions' sources, the same list.
  for _, c in ipairs(lib.__kindSourceIds and lib.__kindSourceIds(k) or {}) do ids[#ids + 1] = c end
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

-- What OptionsIdSuggest.lua reads at its load: the kinds and the id lookups the suggestions share.
lib.__idsKit = {
  ID_KINDS = ID_KINDS, ID_LOOKUP_CAP = ID_LOOKUP_CAP, candidateIds = candidateIds, decorKind = decorKind,
  idKind = idKind, nameColor = nameColor, resolveId = resolveId, viewHost = viewHost,
}

-- The dropdown's answers for a copy without OptionsIdSuggest.lua.
local function noSuggest() end
local NO_SUGGEST = { suggest = {}, boxParts = {}, closeSuggest = noSuggest, pickSuggestion = noSuggest,
  onTyped = noSuggest, hookBox = noSuggest, offerRanks = noSuggest }

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

  --- The gray an id is drawn in on this page (minor 5): the owner's `text.disabled` as a color code
  --- while the chrome is skinned, else ID_GRAY. Asked whenever a label is built, so a skin switch
  --- reaches the next render.
  local function idGray()
    local S = O.__chromeSkin and O.__chromeSkin()
    local c = S and type(S.Token) == "function" and S.Token("text.disabled") or nil
    if type(c) ~= "table" or type(c[1]) ~= "number" then return ID_GRAY end
    local function byte(x) return math.floor(math.max(0, math.min(1, x)) * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", byte(c[1]), byte(c[2]), byte(c[3]))
  end

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
    if refused("id list change") then return false end
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

  -- The suggestion dropdown lives in OptionsIdSuggest.lua, which answers what the input below calls.
  -- A copy without that file offers no suggestions, and the box still adds what is typed.
  local dropdown = lib.__AttachIdSuggest and lib.__AttachIdSuggest(O, {
    addResolved = addResolved, idGray = idGray, idText = idText, reportFailure = reportFailure,
    stillTyped = stillTyped, trimmed = trimmed,
  }) or NO_SUGGEST
  local suggest, boxParts, closeSuggest = dropdown.suggest, dropdown.boxParts, dropdown.closeSuggest
  local pickSuggestion, onTyped, hookBox = dropdown.pickSuggestion, dropdown.onTyped, dropdown.hookBox
  offerRanks = dropdown.offerRanks

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
    ID_MAIN_REL = ID_MAIN_REL, ID_ACTION_REL = ID_ACTION_REL, ID_GRAY = ID_GRAY, idGray = idGray,
    idKind = idKind, kindWords = kindWords, nameColor = nameColor, idText = idText,
    callHost = callHost, disableIfRender = disableIfRender, underDisable = underDisable,
    entryNamed = entryNamed, drawIdInput = drawIdInput,
  }
end
