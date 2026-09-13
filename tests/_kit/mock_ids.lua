-- testkit/mock_ids.lua — the kit's opt-in id lookups (revision 20): name and id answers for
-- C_Spell, C_Item and C_CurrencyInfo, for a suite that drives LibKa0s-Options-1.0's ResolveId,
-- IdInput or IdList.
--
-- Returns an INSTALLER, called on a finished mock:
--
--   local M = base()
--   M.C_Item = { ... }                       -- the harness's own namespaces first
--   dofile("tests/_kit/mock_ids.lua")(M)     -- then the lookups it lacks
--
-- OPT-IN, AND A FILE OF ITS OWN, for two reasons.
--
-- 1. NOT INSTALLED BY THE BASE. ConsumableMaster, WhatGroup and MultiMeters reach their Compat
--    fallbacks by clearing C_Spell or C_Item, and the loader reads the mock before _G, so a
--    base-level namespace would resolve ahead of the cleared one and make those branches
--    unreachable (the reason the base carries no C_AddOns either). The installer fills only the
--    keys still missing, so a consumer's own item fixture keeps answering and only the lookups it
--    lacks join it.
-- 2. mock_base.lua sits at layout-§1's 1500-line cap, and this is a surface a suite asks for, not
--    one every suite stands on.
--
-- Records are id-keyed, one table per kind, seeded with `M.addIdRecord(kind, id, name, icon,
-- uncached, quality)` and emptied with `M.clearIdRecords()`. A name lookup ignores case, as the
-- client's does, and answers the LOWEST matching id, so two records sharing a name resolve the same
-- way on every run. An item added `uncached` is one the client has not loaded: its icon answers by
-- id (GetItemInfoInstant needs no cache) and its name and quality do not, until the record is added
-- again without the flag -- which is how a suite lands a load. `quality` is an item's
-- Enum.ItemQuality number, answered by C_Item.GetItemQualityByID; a record seeded without one
-- answers nil, as a client with no quality for the id does.
--
-- The same revision carries what IdInput's suggestions read (v1.35.0, issue #31): the bags
-- (`M.setBagItems`, answered by C_Container), the spellbook (`M.setSpellBook`, C_SpellBook), an
-- item's crafted or reagent quality tier (`M.setCraftedQuality` / `M.setReagentQuality`,
-- C_TradeSkillUI) and a spell's subtext (`M.setSpellSubtext`, C_Spell.GetSpellSubtext). Those
-- namespaces are a second opt-in, `M.installIdSuggestions()`, filled only where missing too, which
-- also gives the AceGUI fake's EditBox the `editbox` input frame the keys land on. clearIdRecords
-- empties what was seeded.

return function(M)
  M.__idRecords = M.__idRecords or { spell = {}, item = {}, currency = {} }
  function M.addIdRecord(kind, id, name, icon, uncached, quality)
    M.__idRecords[kind][id] = { id = id, name = name, icon = icon, quality = quality,
                                uncached = uncached and true or nil }
  end
  function M.clearIdRecords()
    for kind in pairs(M.__idRecords) do M.__idRecords[kind] = {} end
  end

  --- The record `key` names: a number is an id, a string a name. An uncached record has no name.
  local function idRecord(kind, key)
    local recs = M.__idRecords[kind]
    if type(key) == "number" then return recs[key] end
    if type(key) ~= "string" then return nil end
    local want, hit = key:lower(), nil
    for _, r in pairs(recs) do
      if not r.uncached and type(r.name) == "string" and r.name:lower() == want
        and (not hit or r.id < hit.id) then
        hit = r
      end
    end
    return hit
  end

  -- The client's shapes: C_Spell answers a SpellInfo table, GetItemInfoInstant seven values (the
  -- icon fifth; a misc-junk item's type, subtype, equip slot, class 15 and subclass 0 around it),
  -- C_CurrencyInfo a CurrencyInfo table. An item link is read for its id, as the client reads it.
  local function spellInfo(key)
    local r = idRecord("spell", key)
    if not r then return nil end
    return { name = r.name, iconID = r.icon, originalIconID = r.icon, castTime = 0,
             minRange = 0, maxRange = 0, spellID = r.id }
  end
  local function itemInstant(key)
    local linked = type(key) == "string" and tonumber(key:match("item:(%d+)"))
    local r = idRecord("item", linked or key)
    if not r then return nil end
    return r.id, "Miscellaneous", "Junk", "", r.icon, 15, 0
  end
  local function itemName(id)
    local r = type(id) == "number" and M.__idRecords.item[id]
    if not r or r.uncached then return nil end
    return r.name
  end
  --- GetItemQualityByID reads an id or a link, and needs the cache, as GetItemNameByID does.
  local function itemQuality(key)
    local id = type(key) == "string" and tonumber(key:match("item:(%d+)")) or key
    local r = type(id) == "number" and M.__idRecords.item[id]
    if not r or r.uncached then return nil end
    return r.quality
  end
  local function currencyInfo(id)
    local r = type(id) == "number" and M.__idRecords.currency[id]
    if not r then return nil end
    return { name = r.name, iconFileID = r.icon, quantity = 0, maxQuantity = 0, discovered = true }
  end

  -- ── what IdInput's suggestions read (LibKa0s v1.35.0, issue #31) ─────────────────────────
  --
  -- The client sources beside the host's candidates -- the bags and the spellbook -- and the rank
  -- a row is labeled with: an item's crafted or reagent quality tier, a spell's subtext. Seeded per
  -- suite and emptied by clearIdRecords with the records. A tier needs the item cached, as its
  -- quality does; a spellbook slot and a subtext read the spell records for the name.
  local function resetSources()
    M.__bags, M.__spellBook = {}, {}
    M.__craftedQuality, M.__reagentQuality, M.__spellSubtext = {}, {}, {}
  end
  resetSources()
  local clearRecords = M.clearIdRecords
  function M.clearIdRecords()
    clearRecords()
    resetSources()
  end
  --- `ids` is the bag's slots in order; `false` is an empty slot.
  function M.setBagItems(bag, ids) M.__bags[bag] = ids end
  --- The player's spellbook, one skill line holding `ids` in order.
  function M.setSpellBook(ids) M.__spellBook = ids end
  function M.setCraftedQuality(id, tier) M.__craftedQuality[id] = tier end
  function M.setReagentQuality(id, tier) M.__reagentQuality[id] = tier end
  function M.setSpellSubtext(id, text) M.__spellSubtext[id] = text end

  local function bagSlots(bag) return #(M.__bags[bag] or {}) end
  local function bagItem(bag, slot)
    local id = (M.__bags[bag] or {})[slot]
    return type(id) == "number" and id or nil
  end
  local function skillLines() return #M.__spellBook > 0 and 1 or 0 end
  local function skillLine(line)
    if line ~= 1 or #M.__spellBook == 0 then return nil end
    return { name = "General", itemIndexOffset = 0, numSpellBookItems = #M.__spellBook }
  end
  --- Slot `slot` of the player's bank (Enum.SpellBookSpellBank.Player is 0): a Spell (itemType 1).
  local function spellBookItem(slot, bank)
    local id = bank == 0 and M.__spellBook[slot]
    if type(id) ~= "number" then return nil end
    local r = M.__idRecords.spell[id] or {}
    return { actionID = id, spellID = id, itemType = 1, name = r.name, iconID = r.icon,
             isPassive = false, isOffSpec = false, skillLineIndex = 1 }
  end
  local function tierFrom(map)
    return function(key)
      local id = type(key) == "string" and tonumber(key:match("item:(%d+)")) or key
      local r = type(id) == "number" and M.__idRecords.item[id]
      if not r or r.uncached then return nil end
      return map()[id]
    end
  end
  local function spellSubtext(id) return M.__spellSubtext[id] or "" end

  local function fillMissing(t, key, fn)
    if t[key] == nil then t[key] = fn end
  end

  --- AceGUI's EditBox keeps its input frame as `editbox`, where the keys a player presses land, and
  --- the base's fake has none. From here on every EditBox gets one, unless the harness registered
  --- an EditBox of its own. Registered without a version, so GetWidgetVersion("EditBox") still
  --- answers nil; the frame comes from the CreateFrame in place now, so a suite that later spies
  --- CreateFrame to count frames does not count these.
  local function giveEditBoxesInput()
    local gui = M.__libs and M.__libs["AceGUI-3.0"]
    if not (gui and gui.WidgetRegistry and M.__makeAceGUIWidget) or gui.WidgetRegistry.EditBox then
      return
    end
    local newFrame = M.CreateFrame
    gui.WidgetRegistry.EditBox = function()
      local w = M.__makeAceGUIWidget("EditBox")
      w.editbox = newFrame("EditBox")
      return w
    end
  end

  --- What IdInput's suggestions read, filled only where missing, and ONLY WHEN A HARNESS ASKS --
  --- for the reason the lookups stay out of the base. ConsumableMaster's harness walks its bags
  --- through `_G.C_Container` and installs these lookups, and the loader reads the mock before _G,
  --- so a C_Container put on the mock here would shadow its bags; WhatGroup reaches a Compat rung
  --- by clearing C_SpellBook; PanelMaster's harness gives an EditBox an `editbox` of its own only
  --- when it has none. A suite that drives the suggestions calls this after the install.
  function M.installIdSuggestions()
    giveEditBoxesInput()
    M.C_Container    = M.C_Container or {}
    M.C_SpellBook    = M.C_SpellBook or {}
    M.C_TradeSkillUI = M.C_TradeSkillUI or {}
    fillMissing(M.C_Spell, "GetSpellSubtext", spellSubtext)
    fillMissing(M.C_Container, "GetContainerNumSlots", bagSlots)
    fillMissing(M.C_Container, "GetContainerItemID", bagItem)
    fillMissing(M.C_SpellBook, "GetNumSpellBookSkillLines", skillLines)
    fillMissing(M.C_SpellBook, "GetSpellBookSkillLineInfo", skillLine)
    fillMissing(M.C_SpellBook, "GetSpellBookItemInfo", spellBookItem)
    fillMissing(M.C_TradeSkillUI, "GetItemCraftedQualityByItemInfo",
      tierFrom(function() return M.__craftedQuality end))
    fillMissing(M.C_TradeSkillUI, "GetItemReagentQualityByItemInfo",
      tierFrom(function() return M.__reagentQuality end))
    return M
  end

  M.C_Spell        = M.C_Spell or {}
  M.C_Item         = M.C_Item or {}
  M.C_CurrencyInfo = M.C_CurrencyInfo or {}
  fillMissing(M.C_Spell, "GetSpellInfo", spellInfo)
  fillMissing(M.C_Item, "GetItemInfoInstant", itemInstant)
  fillMissing(M.C_Item, "GetItemNameByID", itemName)
  fillMissing(M.C_Item, "GetItemQualityByID", itemQuality)
  fillMissing(M.C_CurrencyInfo, "GetCurrencyInfo", currencyInfo)
  return M
end
