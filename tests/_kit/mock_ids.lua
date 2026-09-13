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
-- uncached)` and emptied with `M.clearIdRecords()`. A name lookup ignores case, as the client's
-- does, and answers the LOWEST matching id, so two records sharing a name resolve the same way on
-- every run. An item added `uncached` is one the client has not loaded: its icon answers by id
-- (GetItemInfoInstant needs no cache) and its name does not, by id or by name, until the record is
-- added again without the flag -- which is how a suite lands a load.

return function(M)
  M.__idRecords = M.__idRecords or { spell = {}, item = {}, currency = {} }
  function M.addIdRecord(kind, id, name, icon, uncached)
    M.__idRecords[kind][id] = { id = id, name = name, icon = icon, uncached = uncached and true or nil }
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
  local function currencyInfo(id)
    local r = type(id) == "number" and M.__idRecords.currency[id]
    if not r then return nil end
    return { name = r.name, iconFileID = r.icon, quantity = 0, maxQuantity = 0, discovered = true }
  end

  local function fillMissing(t, key, fn)
    if t[key] == nil then t[key] = fn end
  end
  M.C_Spell        = M.C_Spell or {}
  M.C_Item         = M.C_Item or {}
  M.C_CurrencyInfo = M.C_CurrencyInfo or {}
  fillMissing(M.C_Spell, "GetSpellInfo", spellInfo)
  fillMissing(M.C_Item, "GetItemInfoInstant", itemInstant)
  fillMissing(M.C_Item, "GetItemNameByID", itemName)
  fillMissing(M.C_CurrencyInfo, "GetCurrencyInfo", currencyInfo)
  return M
end
