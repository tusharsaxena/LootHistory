-- tests/test_toast_content.lua — modules/ToastContent.lua in full (toast spec
-- docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §7.4, §13.2): the Feed row spec per kind
-- (icon, tint, badge, title and its colors, the count, the prefix, the three secondary lines, the sub
-- line, the highlight), the counts as container marks, the currency cap colors, the five price
-- modes and their payload cache, the upgrade rule (TC.Upgrade), the highlight order, the kind colors
-- and a raising client read.
--
-- Pure: no frame is built. TC.Content is called the way the Feed calls it, on a wiped spec with its
-- three lines tables. Every case that swaps a profile leaf, an NS.Compat member or another seam puts it
-- back, so tests/test_sim_seam.lua's Unwrapped()-empty case still holds after this slot.

local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local C = NS.Constants
local function TC() return NS.ToastContent end
local function M() return NS.ToastModel end

--- Run `fn` with the fields of `over` set on `tbl`, then put each one back (a nil included).
local function with(tbl, over, fn)
  local saved = {}
  for k, v in pairs(over) do saved[k] = { tbl[k] }; tbl[k] = v end
  local ok, err = pcall(fn)
  for k, s in pairs(saved) do tbl[k] = s[1] end
  if not ok then error(err, 0) end
end

--- Run `fn` with the Main feed's stored settings deep-copied and patched by `over`, and the
--- snapshot dropped before and after.
local function withMain(over, fn)
  local feeds = NS.db.profile.settings.toasts.feeds
  local saved = feeds.main
  local f = NS.Util.DeepCopy(saved)
  for k, v in pairs(over or {}) do f[k] = v end
  feeds.main = f
  M().Rebuild()
  local ok, err = pcall(fn, f)
  feeds.main = saved
  M().Rebuild()
  if not ok then error(err, 0) end
end

local function content(p)
  local spec = { lines = { {}, {}, {} } }
  local res = TC().Content("main", spec, p, M().Key(p))
  return spec, res
end

local LINK = "|cff0070dd|Hitem:7::|h[Apple]|h|r"

local function item(over)
  local p = { kind = "ITEM", dir = "IN", id = 7, qty = 1, name = "Apple", quality = 2, icon = 1234, link = LINK }
  for k, v in pairs(over or {}) do p[k] = v end
  return p
end

-- The quiet client: no counts, no prices, no upgrade, no highlight. Cases switch on what they test.
local QUIET = {
  GetItemExtras = function() return nil end,
  LiveItemCounts = function() return nil end,
  ItemEquipInfo = function() return nil end,
  IsMountItem = function() return false end,
  IsUncollectedLook = function() return nil end,
}

local function quiet(over, fn)
  local stubs = {}
  for k, v in pairs(QUIET) do stubs[k] = v end
  for k, v in pairs(over or {}) do stubs[k] = v end
  with(NS.Compat, stubs, fn)
end

local function color(token)
  local r, g, b = NS.Skin.Color(token)
  return r, g, b
end

local function sameColor(c, token, what)
  local r, g, b = color(token)
  assertTrue(c ~= nil, what .. ": a color")
  assertEqual(c.r, r, what .. " r"); assertEqual(c.g, g, what .. " g"); assertEqual(c.b, b, what .. " b")
end

-- ── the first line (§7.4) ────────────────────────────────────────────────────────────────────

test("ToastContent: an item's badge is its level, read once and only while the feed shows it", function()
  local reads = 0
  quiet({ GetItemExtras = function() reads = reads + 1; return 489, nil, 50 end }, function()
    withMain({ price = "none" }, function()
      local p = item()
      local spec = content(p)
      assertEqual(spec.badge, "489")
      assertEqual(spec.count, "x1")
      assertEqual(spec.countColor, nil, "the Feed draws the count in the glow color while it pulses")
      content(p)
      assertEqual(reads, 1, "a repaint reads the extras from the payload")
    end)
    withMain({ ilvl = false, price = "none" }, function()
      assertEqual(content(item()).badge, nil, "the badge switch off")
    end)
    assertEqual(content({ kind = "CURRENCY", id = 3, qty = 2, name = "Coin" }).badge, nil, "items only")
  end)
end)

test("ToastContent: reputation draws its delta, its standing as the prefix and its progress", function()
  quiet(nil, function()
    withMain({ colors = { repFromSkin = false, rep = { r = 0.1, g = 0.2, b = 0.3, a = 1 } } }, function()
      local spec = content({ kind = "REPUTATION", dir = "IN", id = 72, qty = 668, name = "Stormwind",
                             label = "Honored", standing = 21000, threshold = 42000, source = "KILL" })
      assertTrue(spec.title:find("+" .. NS.Compat.FormatCount(668), 1, true) ~= nil, spec.title)
      assertTrue(spec.title:find("Stormwind", 1, true) ~= nil)
      assertEqual(spec.titleColor.r, 0.1, "the stored swatch while its FromSkin companion is off")
      assertEqual(spec.prefix, "\226\128\185Honored\226\128\186")
      assertEqual(spec.lines[1].left, NS.Compat.FormatCount(21000) .. " / " .. NS.Compat.FormatCount(42000))
      assertEqual(spec.lines[1].right, C.SourceLabel.KILL)
      assertEqual(spec.tint, nil, "reputation carries no quality")
      local loss = content({ kind = "REPUTATION", dir = "OUT", id = 72, qty = 50, name = "Stormwind" })
      assertTrue(loss.title:find("-50", 1, true) ~= nil, "a loss reads negative: " .. loss.title)
      assertEqual(loss.lines[1].left, nil, "no standing read, no progress")
    end)
  end)
end)

test("ToastContent: experience draws its level, the percent through it, and a level-up", function()
  quiet(nil, function()
    withMain(nil, function()
      local spec = content({ kind = "XP", dir = "IN", qty = 1500, level = 80, cur = 468, max = 1000 })
      assertEqual(spec.title, "+" .. NS.Compat.FormatCount(1500) .. " XP")
      assertEqual(spec.prefix, "\226\128\18580\226\128\186")
      assertEqual(spec.lines[1].left, "46.8% of level")
      assertEqual(spec.lines[1].right, nil, "experience carries no source tag")
      spec = content({ kind = "XP", dir = "IN", qty = 1500, level = 81, levelUp = true, cur = 10, max = 1000 })
      assertEqual(spec.lines[1].left, "Level 81")
    end)
  end)
end)

test("ToastContent: a skill-up draws its name, the new rank and the rise", function()
  quiet(nil, function()
    withMain(nil, function()
      local spec = content({ kind = "SKILL", dir = "IN", id = 185, qty = 5, name = "Cooking", old = 295, new = 300 })
      assertTrue(spec.title:find("Cooking", 1, true) ~= nil, spec.title)
      assertTrue(spec.title:find(" 300 ", 1, true) ~= nil, "the new rank: " .. spec.title)
      assertTrue(spec.title:find("+5", 1, true) ~= nil, "the rise: " .. spec.title)
      assertEqual(spec.icon, C.TOAST_KIND_ICON.SKILL)
      assertEqual(spec.lines[1].left, nil); assertEqual(spec.lines[1].right, nil)
    end)
  end)
end)

test("ToastContent: a kind color is the skin's owner token while FromSkin, else the swatch", function()
  local Skin = NS.Skin
  with(Skin, { Color = function(name)
    if name == "toast.xp" then return 0.9, 0.5, 1, 1 end
    return nil
  end }, function()
    withMain(nil, function()
      local spec = content({ kind = "XP", dir = "IN", qty = 10 })
      assertEqual(spec.titleColor.r, 0.9, "the owner token")
    end)
    withMain({ colors = { xpFromSkin = false, xp = { r = 0.2, g = 0.3, b = 0.4, a = 1 } } }, function()
      assertEqual(content({ kind = "XP", dir = "IN", qty = 10 }).titleColor.r, 0.2, "the swatch")
    end)
  end)
  with(Skin, { Color = function() return nil end }, function()
    withMain(nil, function()
      local c = content({ kind = "XP", dir = "IN", qty = 10 }).titleColor
      assertEqual(c.r, NS.db.profile.settings.toasts.feeds.main.colors.xp.r, "a skin with no token: the swatch")
    end)
  end)
end)

-- ── the counts (§7.4) ────────────────────────────────────────────────────────────────────────

local function mark(container) return NS.IconMarkup(C.TIP_ICONS[container], C.TIP_ICON_FALLBACK, 0) end

test("ToastContent: an item's counts come from the tally while the ledger is on, as marks", function()
  local tally = { { isMe = true, containers = { [C.Container.BAGS] = 21, [C.Container.BANK] = 0 } },
                  { isWarband = true, containers = { [C.Container.TABS] = 40 } } }
  with(NS.HoldingsTally, { Item = function(_, id) assertEqual(id, 7); return 61, tally, 2 end }, function()
    quiet(nil, function()
      withMain({ price = "none" }, function()
        local left = content(item()).lines[1].left
        local want = mark(C.Container.BAGS) .. " 21"
        if C.FEATURE.warbandBank then want = want .. "  " .. mark(C.Container.TABS) .. " 40" end
        assertEqual(left, want, "a zero part is left out; the tabs only where there is a warband bank")
      end)
    end)
  end)
end)

test("ToastContent: with the ledger off, an item's counts are the client's live ones", function()
  local s = NS.db.profile.settings
  with(s, { trackLedger = false }, function()
    with(NS.HoldingsTally, { Item = function() error("the tally is not read with the ledger off") end }, function()
      quiet({ LiveItemCounts = function() return 3, 9, nil, 1 end }, function()
        withMain({ price = "none" }, function()
          assertEqual(content(item()).lines[1].left,
            mark(C.Container.BAGS) .. " 3  " .. mark(C.Container.BANK) .. " 9")
        end)
        withMain({ price = "none", counts = false }, function()
          assertEqual(content(item()).lines[1].left, nil, "the counts switch off")
        end)
      end)
    end)
  end)
end)

test("ToastContent: money reads the purse, and the warband's stored money where there is one", function()
  quiet({ GetMoney = function() return 1230000 end }, function()
    with(NS.Holdings, { Get = function(_, holder)
      return holder == C.WARBAND_HOLDER and { money = 152000000 } or nil
    end }, function()
      withMain(nil, function()
        local spec = content({ kind = "GOLD", dir = "IN", qty = 12345, source = "KILL" })
        assertEqual(spec.title, NS.Util.FormatMoney(12345))
        local want = mark(C.Container.BAGS) .. " " .. NS.Util.FormatMoney(1230000)
        if C.FEATURE.warbandBank then
          want = want .. "  " .. mark(C.Container.TABS) .. " " .. NS.Util.FormatMoney(152000000)
        end
        assertEqual(spec.lines[1].left, want)
        assertEqual(spec.lines[1].right, C.SourceLabel.KILL)
      end)
      withMain({ source = false }, function()
        assertEqual(content({ kind = "GOLD", dir = "IN", qty = 1, source = "KILL" }).lines[1].right, nil,
          "the source switch off")
      end)
    end)
  end)
end)

-- ── the currency cap (§7.4) ──────────────────────────────────────────────────────────────────

test("ToastContent: a currency's cap turns warn at 70% and bad at 90%", function()
  local have
  quiet({ CurrencyCap = function() return have, 100, nil, false end, CurrencyIcon = function() return 99 end },
    function()
      withMain(nil, function()
        local p = { kind = "CURRENCY", dir = "IN", id = 3008, qty = 5, name = "Valorstones", quality = 1 }
        have = 69
        local l = content(p).lines[1]
        assertEqual(l.left, "69 / 100"); assertEqual(l.leftColor, nil, "under 70%: the text color")
        have = 70
        sameColor(content(p).lines[1].leftColor, "sem.warn", "70%")
        have = 89
        sameColor(content(p).lines[1].leftColor, "sem.warn", "89%")
        have = 90
        sameColor(content(p).lines[1].leftColor, "sem.bad", "90%")
        assertEqual(content(p).icon, 99, "the client's currency icon")
      end)
    end)
end)

test("ToastContent: a cap on total earned reads earned; no cap reads the quantity", function()
  local cap
  quiet({ CurrencyCap = function() return cap() end }, function()
    withMain(nil, function()
      local p = { kind = "CURRENCY", dir = "IN", id = 3008, qty = 5, name = "Valorstones" }
      cap = function() return 10, 2000, 1500, true end
      assertEqual(content(p).lines[1].left, NS.Compat.FormatCount(1500) .. " / " .. NS.Compat.FormatCount(2000))
      cap = function() return 1205, nil, nil, false end
      local l = content(p).lines[1]
      assertEqual(l.left, NS.Compat.FormatCount(1205)); assertEqual(l.leftColor, nil)
    end)
  end)
end)

-- ── the value line (§7.4) ────────────────────────────────────────────────────────────────────

local function withPrices(ahUnit, fn)
  local gathers = 0
  local AP = NS.AuctionPrice
  with(AP, {
    GatherAll = function() gathers = gathers + 1; return ahUnit and { tsm = { dbmarket = ahUnit } } or nil end,
    Pick = function(_, map) return map and map.tsm and map.tsm.dbmarket, "tsm:dbmarket" end,
  }, function()
    quiet({ GetItemExtras = function() return nil, nil, 900 end }, function()
      fn(function() return gathers end)
    end)
  end)
end

local function priceLine(mode, ahUnit, qty)
  local l
  withPrices(ahUnit, function()
    withMain({ price = mode }, function()
      l = content(item({ qty = qty or 2 })).lines[2]
    end)
  end)
  return l
end

test("ToastContent: the five price modes, with and without an AH price", function()
  local F = NS.Util.FormatMoney
  local l = priceLine("both", 21000)
  assertEqual(l.left, "Vendor " .. F(1800)); assertEqual(l.right, "AH " .. F(42000))
  l = priceLine("both", nil)
  assertEqual(l.left, "Vendor " .. F(1800)); assertEqual(l.right, nil, "no AH price: that part is left out")
  l = priceLine("vendor", 21000)
  assertEqual(l.left, "Vendor " .. F(1800)); assertEqual(l.right, nil)
  l = priceLine("ah", 21000)
  assertEqual(l.left, "AH " .. F(42000)); assertEqual(l.right, nil)
  assertEqual(priceLine("ah", nil).left, nil, "AH mode with no AH price draws nothing")
  assertEqual(priceLine("highest", 21000).left, "AH " .. F(42000), "the larger of the two")
  assertEqual(priceLine("highest", 100).left, "Vendor " .. F(1800))
  assertEqual(priceLine("highest", nil).left, "Vendor " .. F(1800))
  l = priceLine("none", 21000)
  assertEqual(l.left, nil); assertEqual(l.right, nil)
end)

test("ToastContent: prices are cached on the payload, and a recorded gain reuses its row's price", function()
  withPrices(21000, function(gathers)
    withMain({ price = "both" }, function()
      local p = item({ qty = 2 })
      content(p)
      assertEqual(gathers(), 1)
      assertEqual(p.vendor, 1800); assertEqual(p.ah, 42000); assertEqual(p.value, 42000)
      content(p)
      assertEqual(gathers(), 1, "a repaint does not gather again")
      local r = item({ qty = 1, recorded = true, record = { auctionPrice = { tsm = { dbmarket = 500 } } } })
      assertEqual(content(r).lines[2].right, "AH " .. NS.Util.FormatMoney(500))
      assertEqual(gathers(), 1, "the recorded row's own price, GatherAll not called")
      local none = item({ qty = 1 })
      with(NS.AuctionPrice, { GatherAll = function() return nil end }, function()
        content(none)
        assertEqual(none.ah, false, "gathered with no price is remembered")
      end)
      assertEqual(content(none).lines[2].right, nil, "and not gathered again")
    end)
  end)
end)

-- ── the upgrade rule (§7.4, T13) ─────────────────────────────────────────────────────────────

-- The equipped items: slot -> { link, ilvl, classID, subclassID, quality }.
local function withEquipped(slots, client, fn)
  local bySlot, byLink = {}, {}
  for slot, e in pairs(slots) do
    local link = "eq:" .. slot
    bySlot[slot] = link
    byLink[link] = e
  end
  with(NS.Compat, {
    ItemLevelOf = function(link) return byLink[link] and byLink[link].ilvl end,
    ItemEquipInfo = function(link)
      local e = byLink[link]
      if not e then return nil end
      return "", e.classID, e.subclassID
    end,
    GetItemInfo = function(link) local e = byLink[link]; return nil, nil, e and e.quality end,
    ClientKey = function() return client end,
  }, function() fn(function(slot) return bySlot[slot] end) end)
end

local function plate(ilvl, quality) return { ilvl = ilvl, classID = 4, subclassID = 4, quality = quality or 3 } end
local function sword(ilvl) return { ilvl = ilvl, classID = 2, subclassID = 7, quality = 3 } end

test("ToastContent: Upgrade compares a worn armor type against the equipped item level", function()
  local U = TC().Upgrade
  withEquipped({ [5] = plate(480) }, "retail", function(eq)
    assertEqual(U("INVTYPE_CHEST", 4, 4, 489, 3, "WARRIOR", eq), 9)
    assertEqual(U("INVTYPE_CHEST", 4, 4, 480, 3, "WARRIOR", eq), nil, "an equal level is no upgrade")
    assertEqual(U("INVTYPE_CHEST", 4, 4, 470, 3, "WARRIOR", eq), nil)
    assertEqual(U("INVTYPE_CHEST", 4, 4, 489, 3, "MAGE", eq), nil, "Retail: a mage does not see plate")
    assertEqual(U("INVTYPE_CHEST", 4, 1, 489, 3, "MAGE", eq), 9, "Retail: cloth is the mage's type")
    assertEqual(U("INVTYPE_HEAD", 4, 4, 489, 3, "WARRIOR", eq), nil, "an empty slot gets no line")
    assertEqual(U("", 4, 4, 489, 3, "WARRIOR", eq), nil, "not equippable")
    assertEqual(U("INVTYPE_BAG", 1, 0, 489, 3, "WARRIOR", eq), nil, "not a gear slot")
  end)
  withEquipped({ [5] = plate(480) }, "forever", function(eq)
    assertEqual(U("INVTYPE_CHEST", 4, 4, 489, 3, "MAGE", eq), 9, "Forever: the equipped piece's subclass")
    assertEqual(U("INVTYPE_CHEST", 4, 3, 489, 3, "WARRIOR", eq), nil, "Forever: mail over worn plate")
  end)
  withEquipped({ [15] = { ilvl = 400, classID = 4, subclassID = 1, quality = 3 } }, "retail", function(eq)
    assertEqual(U("INVTYPE_CLOAK", 4, 1, 410, 3, "WARRIOR", eq), 10, "a cloak takes no armor-type gate")
  end)
end)

test("ToastContent: Upgrade matches a weapon's subclass and a two-slot item takes the lower level", function()
  local U = TC().Upgrade
  withEquipped({ [16] = sword(480), [17] = sword(470) }, "retail", function(eq)
    assertEqual(U("INVTYPE_WEAPON", 2, 7, 475, 3, "WARRIOR", eq), 5, "over the lower of the two hands")
    assertEqual(U("INVTYPE_WEAPON", 2, 4, 489, 3, "WARRIOR", eq), nil, "a mace over swords")
  end)
  withEquipped({ [16] = sword(480) }, "retail", function(eq)
    assertEqual(U("INVTYPE_WEAPON", 2, 7, 489, 3, "WARRIOR", eq), nil, "an empty off hand gets no line")
  end)
  withEquipped({ [11] = { ilvl = 400, classID = 4, subclassID = 0, quality = 3 },
                 [12] = { ilvl = 420, classID = 4, subclassID = 0, quality = 3 } }, "retail", function(eq)
    assertEqual(U("INVTYPE_FINGER", 4, 0, 410, 3, "MAGE", eq), 10, "rings: no armor type, the lower ring")
  end)
end)

test("ToastContent: Upgrade refuses Poor over better and Common over above-Common", function()
  local U = TC().Upgrade
  withEquipped({ [5] = plate(10, 1) }, "retail", function(eq)
    assertEqual(U("INVTYPE_CHEST", 4, 4, 20, 0, "WARRIOR", eq), nil, "Poor over Common")
    assertEqual(U("INVTYPE_CHEST", 4, 4, 20, 1, "WARRIOR", eq), 10, "Common over Common")
  end)
  withEquipped({ [5] = plate(10, 2) }, "retail", function(eq)
    assertEqual(U("INVTYPE_CHEST", 4, 4, 20, 1, "WARRIOR", eq), nil, "Common over Uncommon")
    assertEqual(U("INVTYPE_CHEST", 4, 4, 20, 2, "WARRIOR", eq), 10)
  end)
end)

test("ToastContent: an upgrade draws its line and the upgrade highlight", function()
  withEquipped({ [5] = plate(480) }, "retail", function()
    with(NS.Compat, { PlayerClassFile = function() return "WARRIOR" end,
                      EquippedLink = function(slot) return slot == 5 and "eq:5" or nil end,
                      GetItemExtras = function() return 489, nil, 0 end,
                      IsMountItem = function() return false end,
                      IsUncollectedLook = function() return nil end }, function()
      local saved = NS.Compat.ItemEquipInfo
      with(NS.Compat, { ItemEquipInfo = function(x)
        if x == LINK then return "INVTYPE_CHEST", 4, 4 end
        return saved(x)
      end }, function()
        withMain({ price = "none" }, function()
          local p = item({ quality = 3 })
          local spec = content(p)
          assertTrue(spec.lines[3].left:find("+9 over equipped", 1, true) ~= nil, tostring(spec.lines[3].left))
          sameColor(spec.lines[3].leftColor, "sem.good", "the upgrade line")
          assertTrue(spec.highlight == true)
          assertEqual(p.highlight, "upgrade")
        end)
        local hl = NS.Util.DeepCopy(NS.db.profile.settings.toasts.feeds.main.hl)
        hl.upgrade = false
        withMain({ price = "none", hl = hl }, function()
          local spec = content(item({ quality = 3 }))
          assertEqual(spec.lines[3].left, nil, "the upgrade switch off: no line")
          assertEqual(spec.highlight, nil)
        end)
      end)
    end)
  end)
end)

-- ── the highlight (§7.4) ─────────────────────────────────────────────────────────────────────

test("ToastContent: the highlight is the first switched-on one of mount, legendary, upgrade, appearance", function()
  local mount, uncollected = true, true
  quiet({ IsMountItem = function() return mount end, IsUncollectedLook = function() return uncollected end },
    function()
      local function hlOf(over, p)
        local hl = NS.Util.DeepCopy(NS.db.profile.settings.toasts.feeds.main.hl)
        for k, v in pairs(over) do hl[k] = v end
        local name
        withMain({ hl = hl, price = "none" }, function()
          local spec = content(p)
          name = p.highlight
          assertEqual(spec.highlight, name ~= nil or nil)
        end)
        return name
      end
      assertEqual(hlOf({}, item({ quality = 5 })), "mount")
      assertEqual(hlOf({ mount = false }, item({ quality = 5 })), "legendary")
      assertEqual(hlOf({ mount = false, legendary = false }, item({ quality = 5 })), "appearance")
      mount = false
      assertEqual(hlOf({}, item({ quality = 3 })), "appearance", "an uncollected look")
      uncollected = nil
      assertEqual(hlOf({}, item({ quality = 3 })), nil)
      assertEqual(hlOf({}, item({ quality = 3, newLook = true })), "appearance", "an absorbed look")
      assertEqual(hlOf({ appearance = false }, item({ quality = 3, newLook = true })), nil)
      assertEqual(hlOf({}, { kind = "APPEARANCE", dir = "IN", id = 1, qty = 1, name = "Cuffs", newLook = true }),
        "appearance")
      assertEqual(hlOf({}, { kind = "XP", dir = "IN", qty = 1 }), nil, "experience never glows")
    end)
end)

-- ── the sub line and a raising read ──────────────────────────────────────────────────────────

test("ToastContent: an appearance, and an item with a new look, carry the sub line", function()
  quiet(nil, function()
    withMain({ price = "none" }, function()
      local spec = content({ kind = "APPEARANCE", dir = "IN", id = 1, qty = 1, name = "Cuffs", quality = 4,
                             source = "KILL" })
      assertEqual(spec.sub, "Appearance collected")
      assertEqual(spec.icon, C.TOAST_KIND_ICON.APPEARANCE)
      assertEqual(spec.lines[1].right, C.SourceLabel.KILL)
      assertEqual(content(item({ newLook = true })).sub, "Appearance collected")
      assertEqual(content(item()).sub, nil)
    end)
  end)
end)

test("ToastContent: a raising client read leaves its line empty and never raises", function()
  local boom = function() error("client read failed") end
  quiet({ GetItemExtras = boom, LiveItemCounts = boom, CurrencyCap = boom, ItemEquipInfo = boom }, function()
    with(NS.db.profile.settings, { trackLedger = false }, function()
      withMain({ price = "both" }, function()
        local spec, res = content(item({ source = "KILL" }))
        assertEqual(res, nil, "the row still draws")
        assertEqual(spec.title, "Apple")
        assertEqual(spec.lines[1].left, nil)
        assertEqual(spec.badge, nil)
        local cur = content({ kind = "CURRENCY", dir = "IN", id = 3, qty = 2, name = "Coin" })
        assertEqual(cur.lines[1].left, nil)
        assertFalse(cur.title == nil)
      end)
    end)
  end)
end)
