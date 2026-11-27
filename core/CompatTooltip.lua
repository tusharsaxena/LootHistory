local _, NS = ...
-- core/CompatTooltip.lua — the holdings tooltip's client reads (#34): the post-call installer, the
-- tooltip id readers and guards, the painters, and the live count reads. Split out of
-- core/Compat.lua (compat, "When to split") when the compat family passed its size trigger; one
-- cohesive topic, and the rules are core/Compat.lua's: globals read bare at call time, never
-- captured at load; a secret is never compared, concatenated or indexed; a missing API answers its
-- documented absent value, never a raise.
--
-- LOAD-BEARING POSITION: in the compat family, after core/Compat.lua and core/CompatClient.lua (whose
-- IsSecret every member here asks at call time) and straight before core/SimSeam.lua, which wraps
-- every NS.Compat member at file load; below the seam these members would escape the wrap.

NS.Compat = NS.Compat or {}
local Compat = NS.Compat

-- A gtip.* token's color, read from NS.Skin at CALL time (core/Compat.lua's tooltip family keeps
-- the same reader; this file loads before core/SkinSetup.lua). Three components, never the alpha.
local function tip(token)
  local r, g, b = NS.Skin.Color(token)
  return r, g, b
end

-- ── Holdings in tooltips (#34): post calls, id readers, painting, live reads ─────────────────
-- Spec docs/superpowers/specs/2026-11-27-34-tooltip-holdings-design.md, section 4. Every member is
-- presence-gated and never raises on a client or harness that lacks the API. A secret is never
-- compared, concatenated or indexed: each read passes through Compat.IsSecret first
-- (core/CompatClient.lua, read at call time; events-frames-taint-§8, client-quirks-§5 Q17).

-- v itself when it is a plain table / positive number / non-empty string, else nil.
local function plainTable(v)
  if Compat.IsSecret(v) or type(v) ~= "table" then return nil end
  return v
end

local function plainNumber(v)
  if Compat.IsSecret(v) or type(v) ~= "number" then return nil end
  return v
end

local function plainPositive(v)
  v = plainNumber(v)
  if v and v > 0 then return v end
  return nil
end

local function plainText(v)
  if Compat.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

-- TooltipDataProcessor.AddTooltipPostCall and the data type `typeName` names, or nil.
local function postCallTarget(typeName)
  local tdp, types = TooltipDataProcessor, Enum and Enum.TooltipDataType
  if not (plainTable(tdp) and plainTable(types) and plainText(typeName)) then return nil end
  if type(tdp.AddTooltipPostCall) ~= "function" then return nil end
  local kind = plainNumber(types[typeName])
  return kind and tdp.AddTooltipPostCall, kind
end

--- Register fn(tooltip, data) as a post call of every tooltip of data type `typeName` ("Item",
--- "Currency"): TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType[typeName], fn). The enum
--- member is resolved BY NAME (client-quirks-§5 Q18). The client keeps the call for the session
--- (there is no removal), so the caller registers once and gates its own body (slash-commands-§7).
--- @return boolean  false: no TooltipDataProcessor, no AddTooltipPostCall, no such type, or fn not a function
function Compat.HookTooltipType(typeName, fn)
  if type(fn) ~= "function" then return false end
  local add, kind = postCallTarget(typeName)
  if not add then return false end
  add(kind, fn)
  return true
end

--- The item a post call's data names: data.id, else the id in data.hyperlink ("item:(%d+)"). Only
--- those two fields are read, never a line's text (Q17). nil for a secret, a non-table, a non-positive
--- or missing id.
--- @return number|nil
function Compat.TooltipItemID(data)
  data = plainTable(data)
  if not data then return nil end
  local id = plainPositive(data.id)
  if id then return id end
  local link = plainText(data.hyperlink)
  return link and plainPositive(tonumber(link:match("item:(%d+)"))) or nil
end

--- The currency a post call's data names: data.id, else Compat.CurrencyLinkID(data.hyperlink). The
--- same guards.
--- @return number|nil
function Compat.TooltipCurrencyID(data)
  data = plainTable(data)
  if not data then return nil end
  local id = plainPositive(data.id)
  if id then return id end
  local link = plainText(data.hyperlink)
  return link and plainPositive(Compat.CurrencyLinkID(link)) or nil
end

--- A table with AddLine and AddDoubleLine whose IsForbidden() is not true.
--- @return boolean
function Compat.TooltipWritable(tt)
  if not plainTable(tt) then return false end
  if type(tt.AddLine) ~= "function" or type(tt.AddDoubleLine) ~= "function" then return false end
  if type(tt.IsForbidden) == "function" and tt:IsForbidden() == true then return false end
  return true
end

--- ShoppingTooltip1/2 and ItemRefShoppingTooltip1/2, by frame name ("ShoppingTooltip%d$"); false for
--- an unnamed or secret-named tooltip.
--- @return boolean
function Compat.IsComparisonTooltip(tt)
  if not (plainTable(tt) and type(tt.GetName) == "function") then return false end
  local name = plainText(tt:GetName())
  return name ~= nil and name:find("ShoppingTooltip%d$") ~= nil
end

-- A row's left color: the meaning color the caller read, else its gtip token, else gtip.body.
local function rowLeftColor(row)
  if row.lr then return row.lr, row.lg, row.lb end
  return tip(row.lt or "gtip.body")
end

--- Append rows to a tooltip someone else owns, then tt:Show() so it lays itself out again. Never
--- SetOwner, never PlaceTooltip: the block does not own the tooltip (standalone-windows, Tooltip
--- placement). rows[i] = { left, right = nil | string, lt = token, lr, lg, lb (a meaning color),
--- rt = token (default gtip.value) }. A row with no `right` is AddLine(left, r, g, b); otherwise
--- AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb). Colors from tip(token) at call time.
--- @param n number  how many leading entries of `rows` to paint (rows is a reused scratch array)
--- @return boolean
function Compat.AppendTooltipRows(tt, rows, n)
  if not (Compat.TooltipWritable(tt) and type(rows) == "table") then return false end
  for i = 1, tonumber(n) or #rows do
    local row = rows[i]
    if type(row) == "table" and row.left ~= nil then
      local lr, lg, lb = rowLeftColor(row)
      if row.right == nil then
        tt:AddLine(row.left, lr, lg, lb)
      else
        local rr, rg, rb = tip(row.rt or "gtip.value")
        tt:AddDoubleLine(row.left, row.right, lr, lg, lb, rr, rg, rb)
      end
    end
  end
  if type(tt.Show) == "function" then tt:Show() end
  return true
end

local function colorByte(v) return math.floor(v * 255 + 0.5) end

--- `text` wrapped in the skin token's color as a |cff escape built from the token's components (no
--- color byte is typed). Used only for the dim stale age inside a right column. The bare text for a
--- token the skin leaves alone.
--- @return string
function Compat.TooltipTint(token, text)
  text = tostring(text or "")
  local r, g, b = tip(token)
  if r == nil then return text end
  return ("|cff%02x%02x%02x"):format(colorByte(r), colorByte(g), colorByte(b)) .. text .. "|r"
end

--- A count with the client's digit grouping (BreakUpLargeNumbers: "1,205"), else tostring(n). "" for
--- a secret.
--- @return string
function Compat.FormatCount(n)
  if Compat.IsSecret(n) then return "" end
  if type(n) == "number" and type(BreakUpLargeNumbers) == "function" then
    local s = BreakUpLargeNumbers(n)
    if plainText(s) then return s end
  end
  return tostring(n)
end

-- C_Item.GetItemCount(...)'s plain number, or nil.
local function countOf(fn, ...)
  return plainNumber(fn(...))
end

-- The id worn in inventory slot `slot`, read from GetInventoryItemID straight, never through the
-- wrapped Compat.GetInventoryItem: no link is built (this runs on every tooltip refresh), and a /lh
-- sim session's simulated gear never meets the real client's GetItemCount (the seam provides
-- GetInventoryItem, and real carried less simulated worn is neither world's count).
local function wornID(slot)
  if type(GetInventoryItemID) ~= "function" then return nil end
  return plainNumber(GetInventoryItemID("player", slot))
end

-- The inventory slot a bag sits in, read the same way (C_Container.ContainerIDToInventoryID).
local function bagSlot(bag)
  local fn = C_Container and C_Container.ContainerIDToInventoryID
  if type(fn) ~= "function" then return nil end
  return plainNumber(fn(bag))
end

-- Whether `itemID` can be worn at all: C_Item.GetItemInfoInstant's equip location is non-empty (a
-- bag's is INVTYPE_BAG). True when the client cannot say, so the scan runs rather than undercounts.
local function wearable(itemID)
  local fn = C_Item and C_Item.GetItemInfoInstant
  if type(fn) ~= "function" then return true end
  local equipLoc = select(4, fn(itemID))
  if Compat.IsSecret(equipLoc) or type(equipLoc) ~= "string" then return true end
  return equipLoc ~= ""
end

-- How many of the worn slots and bag inventory slots hold `itemID` (the client's count includes them).
local function wornCount(itemID)
  if not wearable(itemID) then return 0 end
  local C, n = NS.Constants or {}, 0
  for _, slot in ipairs(C.EQUIP_SLOTS or {}) do
    if wornID(slot) == itemID then n = n + 1 end
  end
  for _, bag in ipairs(C.BAG_IDS or {}) do
    local slot = bagSlot(bag)
    if slot and wornID(slot) == itemID then n = n + 1 end
  end
  return n
end

-- max(0, a - b) when both are numbers, else nil.
local function diff(a, b)
  if a == nil or b == nil then return nil end
  return math.max(0, a - b)
end

--- What the logged-in character holds of base item `itemID`, read live from C_Item.GetItemCount:
---   carried  = (id, false, false, false, false); withBank = (id, true, false, true, false);
---   withAcct = (id, true, false, true, true), only where C.FEATURE.warbandBank;
---   worn     = the C.EQUIP_SLOTS and the C.BAG_IDS inventory slots answering itemID, scanned only
---              when something is carried and the item can be worn (otherwise 0).
--- @return number|nil bags     max(0, carried - worn)
--- @return number|nil bank     max(0, withBank - carried)
--- @return number|nil account  max(0, withAcct - withBank), nil where there is no warband bank
--- @return number|nil worn     the worn count itself (the EQUIPPED container), nil with no carried count
--- Each part is nil when a GetItemCount call it needs is absent, secret or not a number; all four
--- are nil for a non-number id. Extra arguments are ignored by a client that does not take them.
function Compat.LiveItemCounts(itemID)
  local fn = C_Item and C_Item.GetItemCount
  if not plainNumber(itemID) or type(fn) ~= "function" then return nil, nil, nil, nil end
  local carried = countOf(fn, itemID, false, false, false, false)
  local withBank = countOf(fn, itemID, true, false, true, false)
  local feature = (NS.Constants or {}).FEATURE
  local withAcct = feature and feature.warbandBank and countOf(fn, itemID, true, false, true, true) or nil
  local worn = nil
  if carried then worn = carried > 0 and wornCount(itemID) or 0 end
  return diff(carried, worn), diff(withBank, carried), diff(withAcct, withBank), worn
end

--- C_CurrencyInfo.GetCurrencyInfo(id).quantity, a plain number, else nil.
function Compat.CurrencyQuantity(currencyID)
  local fn = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
  if not plainNumber(currencyID) or type(fn) ~= "function" then return nil end
  local info = plainTable(fn(currencyID))
  return info and plainNumber(info.quantity) or nil
end

-- The client's read for a modifier key name, or nil.
local function modifierRead(key)
  if key == "shift" then return IsShiftKeyDown end
  if key == "ctrl" then return IsControlKeyDown end
  if key == "alt" then return IsAltKeyDown end
  return nil
end

--- "shift" / "ctrl" / "alt" -> IsShiftKeyDown / IsControlKeyDown / IsAltKeyDown; false otherwise.
--- @return boolean
function Compat.ModifierDown(key)
  local fn = modifierRead(key)
  if type(fn) ~= "function" then return false end
  return fn() and true or false
end

--- RAID_CLASS_COLORS[classFile] as r, g, b; nil for nil, an unknown class, or no table.
function Compat.ClassColor(classFile)
  local colors = plainTable(RAID_CLASS_COLORS)
  if not (colors and plainText(classFile)) then return nil end
  local c = plainTable(colors[classFile])
  if not c then return nil end
  return c.r, c.g, c.b
end
