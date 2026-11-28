local _, NS = ...
NS.ToastContent = NS.ToastContent or {}
local TC = NS.ToastContent
local C = NS.Constants

-- The toast row content (#38, toast spec docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md
-- §7.4): pure. TC.Content(fid, spec, payload, key) sits behind each feed's `d.content` and fills the
-- Feed's reused row spec from a payload. The Feed wipes the spec (and its three `lines` tables) before
-- each call and runs it under pcall (LibKa0s docs/api/Feed/version-1.1.1.1-docs.md, *The payload and
-- the row spec*); it draws everything, this file only says what. Answers nothing (draw) or false
-- (skip the payload).
--
--   icon, tint, title, count    every kind (the first line)
--   badge                       an item's level, over the icon (cfg.ilvl)
--   prefix                      ‹standing› on reputation, ‹level› on experience
--   lines[1]                    the counts as container marks (items, money), the cap (currencies) or
--                               the progress (reputation, experience); the source tag on the right
--   lines[2]                    an item's value by the feed's price mode
--   lines[3]                    the upgrade over the equipped item (TC.Upgrade, T13)
--   sub                         "Appearance collected"
--   highlight                   the first switched-on highlight that applies; its name is kept on
--                               the payload (p.highlight) for the host's sound (modules/ToastFeed.lua)
--
-- Each secondary part is built under pcall: a client read that raises leaves its line empty and the
-- rest of the row draws. The slow reads are cached on the payload so a repaint or the settle re-read
-- (motion.settle) does not repeat them: the item extras (p.ilvl, p.sellUnit, p.extrasRead) and the
-- prices (p.vendor, p.ah, p.value; p.ah is false once gathered with no price). The merge reducer
-- (modules/ToastModel.lua M.Merge) sums or drops the price cache. The counts are read on every call,
-- so the settle re-read sees the bags after the client caught up (client-quirks-§3).
--
-- Binds NS.Constants at load only; every other read (NS.Compat, NS.Skin, NS.L, NS.Util,
-- NS.HoldingsTally, NS.Holdings, NS.AuctionPrice, the profile) at call time.

local K = C.GainKind
local floor = math.floor

local function L(s) return NS.L[s] end
local function fmtCount(n) return NS.Compat.FormatCount(n) end
local function money(v) return NS.Util.FormatMoney(v) end

-- ── colors (reused tables, refilled per call: a skin switch's repaint reads the new values) ─────

local function fill(t, r, g, b, a)
  a = a or 1
  t[1], t[2], t[3], t[4] = r, g, b, a
  t.r, t.g, t.b, t.a = r, g, b, a
  return t
end

local tints = {}

local function qualityTint(q)
  q = tonumber(q)
  if not (q and NS.QualityColor) then return nil end
  local r, g, b = NS.QualityColor(q)
  if r == nil then return nil end
  tints[q] = tints[q] or {}
  return fill(tints[q], r, g, b, 1)
end

local tokens = {}

--- The skin's color token `name` as a reused color table, or nil when the skin has none.
local function token(name)
  local S = NS.Skin
  if not (S and S.Color) then return nil end
  local r, g, b, a = S.Color(name)
  if type(r) ~= "number" then return nil end
  tokens[name] = tokens[name] or {}
  return fill(tokens[name], r, g, b, a)
end

local KIND_COLOR = { [K.XP] = "xp", [K.REPUTATION] = "rep", [K.SKILL] = "skill" }
local swatches = {}

--- A kind's color (§8.4): the owner token `toast.<key>` while its FromSkin companion is on, else (or
--- while the skin has no such token) the feed's stored swatch.
local function kindColor(cfg, kind)
  local key = KIND_COLOR[kind]
  local colors = type(cfg.colors) == "table" and cfg.colors or {}
  if colors[key .. "FromSkin"] ~= false then
    local c = token("toast." .. key)
    if c then return c end
  end
  local sw = colors[key]
  if type(sw) ~= "table" then return nil end
  swatches[key] = swatches[key] or {}
  return fill(swatches[key], sw.r or sw[1], sw.g or sw[2], sw.b or sw[3], sw.a or sw[4])
end

local function byte(v) return floor((tonumber(v) or 0) * 255 + 0.5) end

--- `text` in color `c` as inline codes; the text alone when there is no color.
local function colored(c, text)
  if not c then return text end
  return ("|cff%02x%02x%02x"):format(byte(c.r), byte(c.g), byte(c.b)) .. text .. "|r"
end

-- ── the counts (§7.4: container marks plus a count) ──────────────────────────────────────────

local marks = {}

local function mark(container)
  local m = marks[container]
  if not m then
    m = NS.IconMarkup(C.TIP_ICONS[container], C.TIP_ICON_FALLBACK, 0)
    marks[container] = m
  end
  return m
end

local PARTS = {}

local function addPart(n, container, v, fmt)
  v = tonumber(v)
  if not v or v <= 0 then return n end
  n = n + 1
  PARTS[n] = mark(container) .. " " .. fmt(v)
  return n
end

local function joined(n)
  if n == 0 then return nil end
  return table.concat(PARTS, "  ", 1, n)
end

local function ledgerOn()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return s ~= nil and s.trackLedger ~= false
end

-- The logged-in holder's bags and bank, and the warband's tabs, from M1's tally.
local function tallyCounts(id)
  local _, rows, n = NS.HoldingsTally:Item(id)
  local bags, bank, tabs
  for i = 1, n or 0 do
    local r = rows[i]
    if r.isMe then
      bags, bank = r.containers[C.Container.BAGS], r.containers[C.Container.BANK]
    elseif r.isWarband then
      tabs = r.containers[C.Container.TABS]
    end
  end
  return bags, bank, tabs
end

local function itemCounts(p)
  local id = tonumber(p.id)
  if not id then return nil end
  local bags, bank, tabs
  if ledgerOn() and NS.HoldingsTally then
    bags, bank, tabs = tallyCounts(id)
  else
    bags, bank, tabs = NS.Compat.LiveItemCounts(id)
  end
  if not C.FEATURE.warbandBank then tabs = nil end
  local n = addPart(0, C.Container.BAGS, bags, fmtCount)
  n = addPart(n, C.Container.BANK, bank, fmtCount)
  return joined(addPart(n, C.Container.TABS, tabs, fmtCount))
end

local function goldCounts()
  local n = addPart(0, C.Container.BAGS, NS.Compat.GetMoney(), money)
  if C.FEATURE.warbandBank and ledgerOn() and NS.Holdings then
    local e = NS.Holdings:Get(C.WARBAND_HOLDER)
    n = addPart(n, C.Container.TABS, e and e.money, money)
  end
  return joined(n)
end

-- ── the first secondary line's left part, per kind ───────────────────────────────────────────

--- A currency's cap (§7.4): "have / max", in sem.warn from 70% and sem.bad from 90%; with no cap,
--- the quantity alone (a count, so only while the feed shows counts).
local function capLine(p, cfg)
  local q, max, earned, uses = NS.Compat.CurrencyCap(p.id)
  if not max then
    if cfg.counts and q then return fmtCount(q) end
    return nil
  end
  local have = (uses and earned) or q
  if not have then return nil end
  local r = have / max
  local c = (r >= 0.9 and token("sem.bad")) or (r >= 0.7 and token("sem.warn")) or nil
  return fmtCount(have) .. " / " .. fmtCount(max), c
end

local function repProgress(p)
  local s, t = tonumber(p.standing), tonumber(p.threshold)
  if not (s and t) then return nil end
  return fmtCount(s) .. " / " .. fmtCount(t)
end

local function xpProgress(p)
  if p.levelUp and p.level then return L("Level %s"):format(tostring(p.level)) end
  local cur, max = tonumber(p.cur), tonumber(p.max)
  if not (cur and max and max > 0) then return nil end
  return L("%.1f%% of level"):format(cur / max * 100)
end

local LEFT1 = {
  [K.ITEM]       = function(p, cfg) if cfg.counts then return itemCounts(p) end end,
  [K.GOLD]       = function(_, cfg) if cfg.counts then return goldCounts() end end,
  [K.CURRENCY]   = capLine,
  [K.REPUTATION] = repProgress,
  [K.XP]         = xpProgress,
}

local SOURCE_KINDS = { [K.ITEM] = true, [K.CURRENCY] = true, [K.GOLD] = true, [K.APPEARANCE] = true,
                       [K.REPUTATION] = true }

local function line1(spec, p, cfg)
  local l = spec.lines[1]
  local fn = LEFT1[p.kind]
  if fn then l.left, l.leftColor = fn(p, cfg) end
  if cfg.source and p.source and SOURCE_KINDS[p.kind] then l.right = C.SourceLabel[p.source] or tostring(p.source) end
end

-- ── item extras and the value line (§7.4) ────────────────────────────────────────────────────

--- The item level and the unit sell price, read once per payload (Compat.GetItemExtras' 1st and 3rd
--- returns). An uncached item answers no price yet, so it is read again on the next paint.
local function extras(p)
  if p.extrasRead or not p.link then return end
  local ilvl, _, sell = NS.Compat.GetItemExtras(p.link)
  p.ilvl, p.sellUnit = tonumber(ilvl), tonumber(sell)
  p.extrasRead = sell ~= nil or nil
end

local function vendorTotal(p, qty)
  if p.vendor == nil then
    extras(p)
    local unit = p.sellUnit
    p.vendor = (unit and unit > 0) and unit * qty or nil
  end
  return p.vendor
end

-- The AH price: the recorded row's own map when the gain was recorded, else gathered once.
local function ahTotal(p, qty)
  if p.ah == nil then
    local AP = NS.AuctionPrice
    local map = type(p.record) == "table" and p.record.auctionPrice or nil
    if map == nil and AP and p.link then map = AP:GatherAll(p.link, p.id) end
    local unit = AP and map and AP:Pick(map)
    unit = tonumber(unit)
    p.ah = (unit and unit > 0) and unit * qty or false
  end
  return p.ah or nil
end

local function priced(label, v)
  if not v then return nil end
  return L(label) .. " " .. money(v)
end

-- The value line's left and right parts for a price mode (`both`: vendor left, AH right; `ah`;
-- `highest`: the larger; `vendor` and anything else: the vendor price).
local function priceParts(mode, vendor, ah)
  if mode == "both" then return priced("Vendor", vendor), priced("AH", ah) end
  if mode == "ah" then return priced("AH", ah) end
  if mode == "highest" and ah and (not vendor or ah > vendor) then return priced("AH", ah) end
  return priced("Vendor", vendor)
end

local function priceLine(spec, p, cfg)
  local mode = cfg.price
  if p.kind ~= K.ITEM or type(mode) ~= "string" or mode == "none" then return end
  local qty = tonumber(p.qty) or 1
  local vendor = mode ~= "ah" and vendorTotal(p, qty) or nil
  local ah = mode ~= "vendor" and ahTotal(p, qty) or nil
  local l = spec.lines[2]
  l.left, l.right = priceParts(mode, vendor, ah)
  if vendor or ah then p.value = math.max(vendor or 0, ah or 0) end
end

-- ── the upgrade rule (§7.4, T13) ─────────────────────────────────────────────────────────────

local ITEMCLASS_WEAPON, ITEMCLASS_ARMOR = 2, 4

-- Whether the equipped `link` is the reference for a new item of this class and subclass: a weapon
-- the equipped weapon's subclass; armor of a worn type (Retail: the class's; WoW Forever: the
-- equipped piece's). A cloak is cloth for every class, so it takes no armor-type gate.
local function fits(classID, subclassID, equipLoc, classFile, link)
  if classID == ITEMCLASS_WEAPON then
    local _, eClass, eSub = NS.Compat.ItemEquipInfo(link)
    return eClass == ITEMCLASS_WEAPON and eSub == subclassID
  end
  local typed = classID == ITEMCLASS_ARMOR and subclassID and subclassID >= 1 and subclassID <= 4
  if not typed or equipLoc == "INVTYPE_CLOAK" then return true end
  if NS.Compat.ClientKey() == "forever" then
    local _, _, eSub = NS.Compat.ItemEquipInfo(link)
    return eSub == subclassID
  end
  return C.CLASS_ARMOR[classFile] == subclassID
end

-- RLF's rule (Features/ItemLoot/ItemLoot.lua:266-279): a Poor item over a better equipped piece, or a
-- Common item over one above Common, is no upgrade.
local function lowQualityRefuses(quality, equippedQuality)
  quality, equippedQuality = tonumber(quality), tonumber(equippedQuality)
  if not (quality and equippedQuality) then return false end
  return (quality == 0 and equippedQuality > 0) or (quality == 1 and equippedQuality > 1)
end

--- The item levels a new item of `equipLoc` (class, subclass, `ilvl`, `quality`) gains over what is
--- equipped, or nil: no line for gear that is not equippable, an empty slot, a type not worn, an
--- equal or lower level. A two-slot location compares against the lower equipped level.
--- `equippedFn(slot)` answers the link in that slot (Compat.EquippedLink).
-- The lower equipped item level over `slots` and that item's link, or nil when a slot is empty, an
-- equipped level is unknown or an equipped item is not the reference type (fits).
local function lowestEquipped(slots, classID, subclassID, equipLoc, classFile, equippedFn)
  local lowest, lowLink
  for i = 1, #slots do
    local link = equippedFn(slots[i])
    if not link then return nil end
    local e = tonumber(NS.Compat.ItemLevelOf(link))
    if not (e and fits(classID, subclassID, equipLoc, classFile, link)) then return nil end
    if not lowest or e < lowest then lowest, lowLink = e, link end
  end
  return lowest, lowLink
end

function TC.Upgrade(equipLoc, classID, subclassID, ilvl, quality, classFile, equippedFn)
  local slots = equipLoc and equipLoc ~= "" and C.EQUIP_LOC_SLOTS[equipLoc]
  ilvl = tonumber(ilvl)
  if not (slots and ilvl and equippedFn) then return nil end
  local lowest, lowLink = lowestEquipped(slots, classID, subclassID, equipLoc, classFile, equippedFn)
  if not lowest then return nil end
  local _, _, eQuality = NS.Compat.GetItemInfo(lowLink)
  if lowQualityRefuses(quality, eQuality) then return nil end
  local diff = ilvl - lowest
  return diff > 0 and diff or nil
end

local function upgradeOf(p)
  if p.kind ~= K.ITEM then return nil end
  extras(p)
  local equipLoc, classID, subclassID = NS.Compat.ItemEquipInfo(p.link or p.id)
  return TC.Upgrade(equipLoc, classID, subclassID, p.ilvl, p.quality, NS.Compat.PlayerClassFile(),
    NS.Compat.EquippedLink)
end

local function upgradeLine(spec, diff)
  local good = token("sem.good")
  local icon = NS.IconMarkup("chevron-up", C.TIP_ICON_FALLBACK, 0, good and good.r, good and good.g,
    good and good.b)
  local l = spec.lines[3]
  l.left = icon .. " " .. L("+%s over equipped"):format(tostring(diff))
  l.leftColor = good
end

-- ── the highlight (§7.4: the first switched-on one that applies) ─────────────────────────────

local function itemHighlight(p, hl, diff)
  if hl.mount and NS.Compat.IsMountItem(tonumber(p.id)) then return "mount" end
  if hl.legendary and tonumber(p.quality) == 5 then return "legendary" end
  if hl.upgrade and diff then return "upgrade" end
  if hl.appearance and (p.newLook or NS.Compat.IsUncollectedLook(p.link)) then return "appearance" end
  return nil
end

local function highlightOf(p, cfg, diff)
  local hl = type(cfg.hl) == "table" and cfg.hl or {}
  if p.kind == K.ITEM then return itemHighlight(p, hl, diff) end
  if p.kind == K.APPEARANCE and hl.appearance and p.newLook then return "appearance" end
  return nil
end

-- ── the first line, per kind ─────────────────────────────────────────────────────────────────

local function itemIcon(p)
  return p.icon or NS.Compat.ItemIcon(p.id) or C.TOAST_ICON_UNKNOWN
end

local function currencyIcon(p)
  return p.icon or NS.Compat.CurrencyIcon(p.id) or C.TOAST_ICON_UNKNOWN
end

local function qtyOf(p) return tonumber(p.qty) or 0 end

local function goldTitle(p) return money(qtyOf(p)) end

local function xpTitle(p, cfg)
  return "+" .. fmtCount(qtyOf(p)) .. " XP", kindColor(cfg, K.XP)
end

-- The delta (sem.good up, sem.bad down) before the faction's name, as the mockup draws it.
local function repTitle(p, cfg)
  local up = p.dir ~= "OUT"
  local delta = colored(token(up and "sem.good" or "sem.bad"), (up and "+" or "-") .. fmtCount(qtyOf(p)))
  return delta .. " " .. tostring(p.name or ""), kindColor(cfg, K.REPUTATION)
end

local function skillTitle(p, cfg)
  local s = colored(kindColor(cfg, K.SKILL), tostring(p.name or ""))
  if p.new then s = s .. " " .. tostring(p.new) end
  return s .. " " .. colored(token("sem.good"), "+" .. fmtCount(qtyOf(p)))
end

local function labelPrefix(p) return p.label and ("\226\128\185" .. tostring(p.label) .. "\226\128\186") or nil end
local function levelPrefix(p) return p.level and ("\226\128\185" .. tostring(p.level) .. "\226\128\186") or nil end

-- Per kind: the icon, whether the quality tints it, the title (text and color), the count chip and
-- the dim prefix.
local KINDS = {
  [K.ITEM]       = { icon = itemIcon, tint = true, count = true },
  [K.CURRENCY]   = { icon = currencyIcon, tint = true, count = true },
  [K.APPEARANCE] = { tint = true },
  [K.GOLD]       = { title = goldTitle },
  [K.REPUTATION] = { title = repTitle, prefix = labelPrefix },
  [K.XP]         = { title = xpTitle, prefix = levelPrefix },
  [K.SKILL]      = { title = skillTitle },
}

local function firstLine(spec, p, cfg, k)
  spec.icon = k.icon and k.icon(p) or C.TOAST_KIND_ICON[p.kind] or C.TOAST_ICON_UNKNOWN
  local tint = k.tint and qualityTint(p.quality) or nil
  spec.tint = tint
  if k.title then
    spec.title, spec.titleColor = k.title(p, cfg)
  else
    spec.title, spec.titleColor = tostring(p.name or ""), tint
  end
  if k.count then spec.count = "x" .. qtyOf(p) end
  if k.prefix then spec.prefix = k.prefix(p) end
end

-- ── the secondary parts ──────────────────────────────────────────────────────────────────────

local function badge(spec, p, cfg)
  if not (cfg.ilvl and p.kind == K.ITEM) then return end
  extras(p)
  if p.ilvl then spec.badge = tostring(p.ilvl) end
end

local function upgradeAndHighlight(spec, p, cfg)
  local hl = type(cfg.hl) == "table" and cfg.hl or {}
  local diff = hl.upgrade and upgradeOf(p) or nil
  if diff then upgradeLine(spec, diff) end
  p.highlight = highlightOf(p, cfg, diff)
  spec.highlight = p.highlight ~= nil or nil
end

local function sub(spec, p)
  if p.kind == K.APPEARANCE or (p.kind == K.ITEM and p.newLook) then spec.sub = L("Appearance collected") end
end

local PARTS_IN_ORDER = { line1, priceLine, badge, upgradeAndHighlight, sub }
local PART_NAMES = { "line1", "price", "badge", "upgrade", "sub" }

local EMPTY = {}

-- One part under pcall; a raise leaves that part empty and is logged while debug is on.
local function part(i, spec, p, cfg)
  local ok, err = pcall(PARTS_IN_ORDER[i], spec, p, cfg)
  if not ok and NS.State and NS.State.debug and NS.Debug then
    NS.Debug("Feed", "content %s part=%s failed: %s", tostring(p.kind), PART_NAMES[i], tostring(err))
  end
end

--- Fill the Feed's row `spec` for `payload` on feed `fid`. False skips a payload of no known kind.
function TC.Content(fid, spec, payload)
  local p = payload
  local k = type(p) == "table" and KINDS[p.kind]
  if not k then return false end
  local cfg = NS.ToastModel and NS.ToastModel.Config(fid) or EMPTY
  firstLine(spec, p, cfg, k)
  for i = 1, #PARTS_IN_ORDER do part(i, spec, p, cfg) end
end
