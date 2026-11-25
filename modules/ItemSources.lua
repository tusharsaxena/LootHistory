local _, NS = ...

-- modules/ItemSources.lua — where an item comes from, for the History table's item tooltip, read
-- from ForeverDB (SF-LH-02, LibKa0s#105; WowAddonStandards clients-§11).
--
-- WHAT IT ADDS. Hovering an item row of the History table on WoW Forever adds, under the client's
-- own item tooltip and above the click hint:
--
--   Drops from                         (a heading)
--     <creature>             25.0%     (the top three, most likely first; "?" where the rate is unknown)
--     and 2 more                       (only when there are more than three)
--   Sold by <vendor>          12s      (the lowest price any vendor was seen asking, and that vendor)
--
-- Only creatures are named under Drops from: an object has no name in the adapter's version 1, and
-- the containers an item comes out of are a second kind of source this tooltip does not list.
-- Names come from ForeverDB's own `npc` table through the adapter's NPC(); an id it cannot name
-- reads as "#<id>". Both lines come from LibKa0s-ForeverDB-1.0 (core/ForeverDBSetup.lua's
-- NS.ForeverDB). Nothing here reads the `ForeverDB` global.
--
-- WHEN IT LOADS. The first hover of an item row, with the setting on and on WoW Forever, is what
-- loads ForeverDB: the adapter's Available() makes the one LoadAddOn call of the session (some
-- 12 MB). Nothing at login, on a timer or at file load asks, and the Retail client never asks.
--
-- WITHOUT IT. With the setting off (`settings.itemSources`, General > Interface > History window),
-- on Retail, or with ForeverDB not installed or disabled, the tooltip is exactly what it was. The
-- setting's row says it needs ForeverDB. The feature is WoW Forever only (C.FEATURE.itemSources,
-- clients-§4): on Retail the row and its default are absent, and Active() answers false at once.

local IS = {}
NS.ItemSources = IS

IS.PATH = "settings.itemSources"
IS.TOP = 3

--- The setting, as stored (a missing key reads as the shipped default, on).
function IS.Enabled()
  local v = NS.Schema and NS.Schema.Get and NS.Schema:Get(IS.PATH)
  return v ~= false
end

--- Whether a hover should read ForeverDB: WoW Forever, the setting on, and the adapter available.
--- The feature (read once, at file load) and the setting are asked first, so the Retail client and
--- a player who turned it off never reach the adapter, and never load anything.
local FEATURE = NS.Constants.FEATURE.itemSources
function IS.Active()
  if not FEATURE then return false end
  if not IS.Enabled() then return false end
  return (NS.ForeverDB.Available()) == true
end

--- A chance on 0..1 as a percentage: one decimal from 1% up, two below it, "?" when unknown.
function IS.ChanceText(chance)
  if type(chance) ~= "number" then return NS.L["?"] end
  local pct = chance * 100
  if pct >= 1 then return ("%.1f%%"):format(pct) end
  return ("%.2f%%"):format(pct)
end

local function npcName(id)
  local npc = NS.ForeverDB.NPC(id)
  if type(npc) == "table" and type(npc.name) == "string" and npc.name ~= "" then return npc.name end
  return "#" .. tostring(id)
end

-- Drops from: the heading, the top IS.TOP creatures, then how many more.
local function addDrops(lines, src)
  local creatures = type(src) == "table" and src.creatures
  if type(creatures) ~= "table" or #creatures == 0 then return end
  lines[#lines + 1] = { NS.L["Drops from"], kind = "heading" }
  for i = 1, math.min(IS.TOP, #creatures) do
    local c = creatures[i]
    lines[#lines + 1] = { "  " .. npcName(c.id), IS.ChanceText(c.chance), kind = "drop" }
  end
  if #creatures > IS.TOP then
    lines[#lines + 1] = { "  " .. NS.L["and %d more"]:format(#creatures - IS.TOP), kind = "more" }
  end
end

-- Sold by: the vendor seen asking the lowest price, with that price; else the first vendor, unpriced.
local function addVendor(lines, itemID, src)
  local price, vendor = NS.ForeverDB.VendorPrice(itemID)
  if not vendor and type(src) == "table" and type(src.vendors) == "table" then vendor = src.vendors[1] end
  if not vendor then return end
  local money = type(price) == "number" and price > 0 and NS.Util.FormatMoney(price) or nil
  lines[#lines + 1] = { NS.L["Sold by %s"]:format(npcName(vendor)), money, kind = "vendor" }
end

--- The lines for `itemID`, as { { left, right }, ... } (right nil for a one-sided line), with each
--- line's `kind` ("heading", "drop", "more" or "vendor"), or nil when ForeverDB names neither a
--- creature that drops it nor a vendor that sells it. Reads the adapter; never checks Active().
function IS.Lines(itemID)
  if type(itemID) ~= "number" then return nil end
  local src = NS.ForeverDB.ItemSources(itemID)
  local lines = {}
  addDrops(lines, src)
  addVendor(lines, itemID, src)
  if #lines == 0 then return nil end
  return lines
end

--- Add the lines for `itemID` to `tooltip`, when Active(); answers how many lines it added. A
--- heading and a vendor line are in the skin's `gtip.title`, the sources in `gtip.body` with their
--- chances in `gtip.value`, and the "and N more" line in `gtip.muted`.
function IS.AddTo(tooltip, itemID)
  if not (tooltip and itemID and IS.Active()) then return 0 end
  local lines = IS.Lines(itemID)
  if not lines then return 0 end
  local tr, tg, tb = NS.SkinColor("gtip.title")
  local br, bg, bb = NS.SkinColor("gtip.body")
  local vr, vg, vb = NS.SkinColor("gtip.value")
  local mr, mg, mb = NS.SkinColor("gtip.muted")
  for _, line in ipairs(lines) do
    local lr, lg, lb = br, bg, bb
    if line.kind == "heading" or line.kind == "vendor" then lr, lg, lb = tr, tg, tb end
    if line.kind == "more" then lr, lg, lb = mr, mg, mb end
    if line[2] then
      tooltip:AddDoubleLine(line[1], line[2], lr, lg, lb, vr, vg, vb)
    else
      tooltip:AddLine(line[1], lr, lg, lb)
    end
  end
  return #lines
end
