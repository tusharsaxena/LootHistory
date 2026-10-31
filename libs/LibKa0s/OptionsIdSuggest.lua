-- LibKa0s-Options-1.0 -- the id input's suggestions while typing: the sources and the ranking at file
-- scope, and the one dropdown each instance shares between its id inputs.
--
-- Peeled out of OptionsIds.lua at its minor 6, unchanged (LK-M2-PEEL of Ka0sAddonsCommonTasks
-- docs/2026-10-31-FINDINGS_REMEDIATION), on the seam CLAUDE.md's band census named for that file:
-- the module-scope suggestions-while-typing block and the dropdown members. The history is that
-- file's header (minors 1, 3, 4 and 5).
--
-- WHO CALLS IN. lib.__AttachIds calls lib.__AttachIdSuggest once per instance, at the point the
-- dropdown's members used to be defined, handing over the input's six closures, and keeps the seven
-- things this answers. `lib.__idsKit` is what it reads of OptionsIds.lua's file scope, and
-- `lib.__kindSourceIds` is what OptionsIds.lua's shared-name check reads of this one. Nothing else
-- crosses the cut. A copy without this file offers no suggestions, and the box still adds what is typed.
--
-- A file of the Options major, paired on the shell's minor with the same multi-file idiom as
-- OptionsIds.lua.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib or not lib.__idsKit then return end

-- Minor 1: the suggestion half, moved here unchanged from OptionsIds.lua (its minor 6).
local SUGGEST_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own: see OptionsScroll.lua.
if lib.__suggestMinor and lib.__suggestMinor >= SUGGEST_MINOR
  and lib.__suggestShellMinor == lib.MINOR then return end
lib.__suggestMinor      = SUGGEST_MINOR
lib.__suggestShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsIdSuggest = SUGGEST_MINOR

local kit = lib.__idsKit
local ID_KINDS, ID_LOOKUP_CAP, candidateIds, decorKind = kit.ID_KINDS, kit.ID_LOOKUP_CAP, kit.candidateIds, kit.decorKind
local idKind, nameColor, resolveId, viewHost = kit.idKind, kit.nameColor, kit.resolveId, kit.viewHost

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

-- OptionsIds.lua's shared-name check reads it too: what resolves a name and what lists it read one
-- source.
local function kindSourceIds(k)
  local row = suggestRow(k)
  return row and row.sources() or {}
end
lib.__kindSourceIds = kindSourceIds

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

--- The dropdown for instance `O`: `h` carries the input's closures. Answers `suggest`, `boxParts`,
--- `closeSuggest`, `pickSuggestion`, `onTyped`, `hookBox` and `offerRanks`.
function lib.__AttachIdSuggest(O, h)
  local addResolved, idGray, idText = h.addResolved, h.idGray, h.idText
  local reportFailure, stillTyped, trimmed = h.reportFailure, h.stillTyped, h.trimmed
  local offerRanks

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

  --- At the start of combat (OptionsCombat.lua's O.__releaseOwnedFocus, minor 3), close the list
  --- when the box that owns it sits under one of `panels` (the instance's pages). The list is
  --- parented to UIParent, so the cover over a page cannot reach it, and a pick from it in combat
  --- would be refused by the write seam anyway. A box under none of them is not this release's: its
  --- list is left alone. Leaving combat reopens nothing; the box's next keystroke does.
  function O.__closeOwnedSuggest(panels)
    local owner = suggest.owner
    local frame = owner and owner.edit and owner.edit.frame
    if not frame or type(lib.__descendsFrom) ~= "function" then return end
    for _, ctx in ipairs(panels or {}) do
      if lib.__descendsFrom(frame, ctx.panel) then return closeSuggest(owner) end
    end
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
    -- The highlight is a texture of the row's own (minor 5), so the skin can color it: the same art,
    -- blend and extent the path form drew.
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(SUGGEST_HIGHLIGHT)
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(row)
    row:SetHighlightTexture(hl)
    row.__ka0sHover = hl
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
    local text = name .. " " .. idGray() .. "(" .. tostring(e.id) .. ")|r"
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
    if O.__chromePaint then
      O.__chromePaint("MenuFrame", f, { popup = true })
      -- The rows and the more line (minor 5): the owner's roles, or given back as they were.
      for _, row in ipairs(f.rows) do
        O.__chromePaint("Text", row.label, "menu.text")
        if O.__hoverArt then O.__hoverArt(row.__ka0sHover) end
      end
      O.__chromePaint("Text", f.more.label, "disabled")
    end
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

  return {
    suggest = suggest, boxParts = boxParts, closeSuggest = closeSuggest, pickSuggestion = pickSuggestion,
    onTyped = onTyped, hookBox = hookBox, offerRanks = offerRanks,
  }
end
