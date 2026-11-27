-- tests/test_compat_tooltip.lua — core/Compat.lua's holdings-tooltip members (#34; spec
-- docs/superpowers/specs/2026-11-27-34-tooltip-holdings-design.md, section 4): the post-call
-- installer, the id readers and guards, the painters, the live reads, and core/CompatClient.lua's
-- IsSecret. Every case runs under the active kit profile (KA0S_KIT_CLIENT, retail by default) and
-- asserts that profile's answer, so the same suite proves both clients (clients-§6).
--
-- The post-call registry is tests/mock_tooltip_data.lua's double, installed per case and uninstalled
-- after it; a secret is the kit's secret double (T.secret), with issecretvalue planted on the mock
-- for the case's length, so a reader that touched one would raise.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local TDP = dofile("tests/mock_tooltip_data.lua")
local FOREVER = T.Loader.MockClient.current() == "forever"

-- Plant `fields` on table `t` for the length of `fn`, then put every one back. NIL plants nil.
local NIL = {}
local function with(t, fields, fn)
  local saved = {}
  for k, v in pairs(fields) do
    saved[k] = { v = rawget(t, k) }
    if v == NIL then rawset(t, k, nil) else rawset(t, k, v) end
  end
  local ok, err = pcall(fn)
  for k, s in pairs(saved) do rawset(t, k, s.v) end
  if not ok then error(err, 0) end
end

-- The double installed for `fn`, uninstalled after it whatever happened.
local function withDouble(fn)
  local h = TDP.install(M)
  local ok, err = pcall(fn, h)
  h.uninstall()
  if not ok then error(err, 0) end
end

local function withSecrets(fn)
  with(M, { issecretvalue = function(v) return T.isSecret(v) end }, fn)
end

local C = function() return NS.Compat end

-- ── IsSecret ────────────────────────────────────────────────────────────────────────────────

test("Compat tooltip: IsSecret answers a boolean, true only for a secret", function()
  assertFalse(C().IsSecret(5), "no issecretvalue on the mock: nothing is secret")
  withSecrets(function()
    assertTrue(C().IsSecret(T.secret(5)))
    assertFalse(C().IsSecret(5)); assertFalse(C().IsSecret(nil))
    assertEqual(type(C().IsSecret("x")), "boolean")
  end)
end)

-- ── HookTooltipType ─────────────────────────────────────────────────────────────────────────

test("Compat tooltip: HookTooltipType registers a post call for Item and for Currency", function()
  withDouble(function(h)
    local fn = function() end
    assertTrue(C().HookTooltipType("Item", fn))
    assertTrue(C().HookTooltipType("Currency", fn))
    assertEqual(h.count("Item"), 1); assertEqual(h.count("Currency"), 1)
    assertEqual(h.postCalls[TDP.TYPES.Currency][1], fn, "the Currency member resolved by name")
  end)
end)

test("Compat tooltip: HookTooltipType answers false and installs nothing when it cannot", function()
  withDouble(function(h)
    assertFalse(C().HookTooltipType("Item", "notafunction"), "a non-function fn")
    assertFalse(C().HookTooltipType("Mount", function() end), "no such data type")
    assertFalse(C().HookTooltipType(nil, function() end), "no type name")
    h.dropType("Currency")
    assertFalse(C().HookTooltipType("Currency", function() end), "a client without the Currency type")
    assertTrue(C().HookTooltipType("Item", function() end), "the Item type still hooks")
    assertEqual(h.count("Currency"), 0)
    with(M, { TooltipDataProcessor = NIL }, function()
      assertFalse(C().HookTooltipType("Item", function() end), "no TooltipDataProcessor")
    end)
    with(M, { TooltipDataProcessor = {} }, function()
      assertFalse(C().HookTooltipType("Item", function() end), "no AddTooltipPostCall")
    end)
    assertEqual(h.count("Item"), 1)
  end)
end)

test("Compat tooltip: HookTooltipType answers false with no Enum.TooltipDataType at all", function()
  with(M, { TooltipDataProcessor = { AddTooltipPostCall = function() error("reached") end } }, function()
    assertFalse(C().HookTooltipType("Item", function() end))
  end)
end)

-- ── the id readers ──────────────────────────────────────────────────────────────────────────

test("Compat tooltip: TooltipItemID reads data.id, else the hyperlink's item id", function()
  assertEqual(C().TooltipItemID({ id = 990101 }), 990101)
  assertEqual(C().TooltipItemID({ hyperlink = "|cff0070dd|Hitem:211296::::::::80|h[X]|h|r" }), 211296)
  assertEqual(C().TooltipItemID({ id = 0, hyperlink = "item:42" }), 42, "a non-positive id falls to the link")
  assertNil(C().TooltipItemID({ id = -3 })); assertNil(C().TooltipItemID({ hyperlink = "currency:3008" }))
  assertNil(C().TooltipItemID({})); assertNil(C().TooltipItemID(nil)); assertNil(C().TooltipItemID("item:5"))
end)

test("Compat tooltip: TooltipCurrencyID reads data.id, else the hyperlink's currency id", function()
  assertEqual(C().TooltipCurrencyID({ id = 3008 }), 3008)
  assertEqual(C().TooltipCurrencyID({ hyperlink = "|cffffffff|Hcurrency:2914:0|h[Crest]|h|r" }), 2914)
  assertNil(C().TooltipCurrencyID({ hyperlink = "item:5" })); assertNil(C().TooltipCurrencyID({}))
  assertNil(C().TooltipCurrencyID(nil)); assertNil(C().TooltipCurrencyID(7))
end)

test("Compat tooltip: a secret id, hyperlink or data table reads nil and is never touched", function()
  withSecrets(function()
    for _, read in ipairs({ "TooltipItemID", "TooltipCurrencyID" }) do
      assertNil(C()[read]({ id = T.secret(5) }), read .. ": a secret id")
      assertNil(C()[read]({ hyperlink = T.secret("item:5") }), read .. ": a secret hyperlink")
      assertNil(C()[read](T.secret({ id = 5 })), read .. ": a secret data table")
    end
    assertEqual(C().TooltipItemID({ id = T.secret(5), hyperlink = "item:6" }), 6, "the link answers instead")
  end)
end)

-- ── the guards ──────────────────────────────────────────────────────────────────────────────

test("Compat tooltip: TooltipWritable is false when forbidden or without AddLine", function()
  withDouble(function(h)
    local tip = h.tooltip("LHTestTip")
    assertTrue(C().TooltipWritable(tip))
    tip.forbidden = true
    assertFalse(C().TooltipWritable(tip), "a forbidden tooltip")
    tip.forbidden = false
    assertTrue(C().TooltipWritable(tip))
    -- A plain table: the kit's frames answer every capitalized method, so nil-ing one proves nothing.
    assertFalse(C().TooltipWritable({ AddDoubleLine = function() end }), "no AddLine")
    assertFalse(C().TooltipWritable({ AddLine = function() end }), "no AddDoubleLine")
    assertTrue(C().TooltipWritable({ AddLine = function() end, AddDoubleLine = function() end }))
    assertFalse(C().TooltipWritable(nil)); assertFalse(C().TooltipWritable("GameTooltip"))
  end)
end)

test("Compat tooltip: IsComparisonTooltip names the four shopping tooltips only", function()
  withDouble(function(h)
    for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
      assertTrue(C().IsComparisonTooltip(h.tooltip(name)), name)
    end
    assertFalse(C().IsComparisonTooltip(h.tooltip("GameTooltip")))
    assertFalse(C().IsComparisonTooltip(h.tooltip("ItemRefTooltip")))
    assertFalse(C().IsComparisonTooltip(h.tooltip(nil)), "an unnamed tooltip")
    assertFalse(C().IsComparisonTooltip(nil))
    withSecrets(function()
      local tip = h.tooltip("ShoppingTooltip1")
      tip.GetName = function() return T.secret("ShoppingTooltip1") end
      assertFalse(C().IsComparisonTooltip(tip), "a secret-named tooltip")
    end)
  end)
end)

-- ── the painters ────────────────────────────────────────────────────────────────────────────

local function rgb(token) local r, g, b = NS.Skin.Color(token); return { r, g, b } end
local function same(line, want, prefix)
  prefix = prefix or ""
  return line[prefix .. "r"] == want[1] and line[prefix .. "g"] == want[2] and line[prefix .. "b"] == want[3]
end

test("Compat tooltip: AppendTooltipRows paints each row in its token, then Shows, never SetOwner", function()
  withDouble(function(h)
    local tip = h.tooltip("GameTooltip")
    h.show(tip, "Item", { id = 5 })
    local before = tip.shows
    local rows = {
      { left = "Header", lt = "gtip.title" },
      { left = "Ann", right = "12", lr = 0.25, lg = 0.5, lb = 0.75 },
      { left = "Total", right = "30" },
      { left = "stale", right = "x", rt = "gtip.muted" },
      { left = "past n" },
    }
    assertTrue(C().AppendTooltipRows(tip, rows, 4))
    local L = tip.__lines
    assertEqual(#L, 5, "the client line plus the four rows; the fifth is past n")
    assertEqual(L[2].text, "Header"); assertNil(L[2].right)
    assertTrue(same(L[2], rgb("gtip.title")), "a left token")
    assertEqual(L[3].right, "12")
    assertTrue(same(L[3], { 0.25, 0.5, 0.75 }), "a meaning color passes through")
    assertTrue(same(L[3], rgb("gtip.value"), "r"), "the right column defaults to gtip.value")
    assertTrue(same(L[4], rgb("gtip.body")), "the left column defaults to gtip.body")
    assertTrue(same(L[5], rgb("gtip.muted"), "r"), "a right token")
    assertEqual(tip.shows, before + 1, "Show is called once after appending")
    assertEqual(#tip.owners, 0, "the block never owns the tooltip")
  end)
end)

test("Compat tooltip: AppendTooltipRows writes nothing to a forbidden or absent tooltip", function()
  withDouble(function(h)
    local tip = h.tooltip("GameTooltip")
    tip.forbidden = true
    assertFalse(C().AppendTooltipRows(tip, { { left = "x" } }, 1))
    assertEqual(#tip.__lines, 0)
    assertFalse(C().AppendTooltipRows(nil, { { left = "x" } }, 1))
    tip.forbidden = false
    assertFalse(C().AppendTooltipRows(tip, nil, 1), "no rows")
  end)
end)

test("Compat tooltip: TooltipTint wraps text in the token's components, no byte typed", function()
  local r, g, b = NS.Skin.Color("gtip.muted")
  local function byte(v) return math.floor(v * 255 + 0.5) end
  local want = ("|cff%02x%02x%02x"):format(byte(r), byte(g), byte(b)) .. "3 d|r"
  assertEqual(C().TooltipTint("gtip.muted", "3 d"), want)
  assertEqual(C().TooltipTint("no.such.token", "3 d"), "3 d", "a token the skin leaves alone: the bare text")
end)

test("Compat tooltip: FormatCount groups digits with BreakUpLargeNumbers, else tostring", function()
  with(M, { BreakUpLargeNumbers = function(n) return n == 1205 and "1,205" or tostring(n) end }, function()
    assertEqual(C().FormatCount(1205), "1,205")
  end)
  with(M, { BreakUpLargeNumbers = NIL }, function()
    assertEqual(C().FormatCount(1205), "1205")
  end)
  withSecrets(function() assertEqual(C().FormatCount(T.secret(5)), "", "a secret is never formatted") end)
end)

-- ── the live reads ──────────────────────────────────────────────────────────────────────────

local ITEM = 990101

-- C_Item.GetItemCount modeled as the client counts: carried (bags plus worn), with the bank, and with
-- the warband bank, each by its flags. `parts` = { bags, bank, account } as the client stores them.
local function counter(parts, worn)
  return function(id, includeBank, _, _, includeAccount)
    if id ~= ITEM then return 0 end
    local n = parts.bags + worn
    if includeBank then n = n + parts.bank end
    if includeAccount then n = n + parts.account end
    return n
  end
end

local function withCounts(parts, worn, fn)
  with(M.C_Item, { GetItemCount = counter(parts, worn) }, fn)
end

test("Compat tooltip: LiveItemCounts subtracts worn gear and splits the bank out", function()
  local slot = NS.Constants.EQUIP_SLOTS[1]
  local bagSlot = NS.Compat.BagInventorySlot(1)
  with(M.__inventory, { [slot] = { itemID = ITEM }, [bagSlot] = { itemID = ITEM } }, function()
    withCounts({ bags = 5, bank = 7, account = 3 }, 2, function()
      local bags, bank, account, worn = C().LiveItemCounts(ITEM)
      assertEqual(bags, 5, "the worn piece and the equipped bag are not in the bags")
      assertEqual(worn, 2, "the worn count is the fourth answer (the EQUIPPED container)")
      assertEqual(bank, 7, "the bank is withBank less carried")
      if FOREVER then
        assertNil(account, "WoW Forever has no warband bank (C.FEATURE.warbandBank)")
      else
        assertEqual(account, 3, "Retail: the warband bank is withAcct less withBank")
      end
    end)
  end)
end)

-- Count the client's inventory reads for the length of `fn`.
local function countingInventory(fn)
  local calls = { id = 0, link = 0 }
  local id, link = M.GetInventoryItemID, M.GetInventoryItemLink
  with(M, {
    GetInventoryItemID = function(...) calls.id = calls.id + 1; return id(...) end,
    GetInventoryItemLink = function(...) calls.link = calls.link + 1; return link(...) end,
  }, function() fn(calls) end)
end

test("Compat tooltip: LiveItemCounts reads worn ids only, and never through the wrapped member", function()
  -- red under: wornCount calling Compat.GetInventoryItem, which builds a link per occupied slot and
  -- which a /lh sim session answers from the simulated world's gear.
  local slot = NS.Constants.EQUIP_SLOTS[1]
  local member = NS.Compat.GetInventoryItem
  with(M.__inventory, { [slot] = { itemID = ITEM, link = "L" } }, function()
    withCounts({ bags = 1, bank = 0, account = 0 }, 1, function()
      countingInventory(function(calls)
        rawset(NS.Compat, "GetInventoryItem", function() error("the wrapped member was read") end)
        local ok, err = pcall(function()
          local bags, _, _, worn = C().LiveItemCounts(ITEM)
          assertEqual(bags, 1); assertEqual(worn, 1)
        end)
        rawset(NS.Compat, "GetInventoryItem", member)
        if not ok then error(err, 0) end
        assertTrue(calls.id > 0, "the ids are read"); assertEqual(calls.link, 0, "no link is built")
      end)
    end)
  end)
end)

test("Compat tooltip: LiveItemCounts skips the worn scan when nothing is carried or it cannot be worn", function()
  countingInventory(function(calls)
    withCounts({ bags = 0, bank = 4, account = 0 }, 0, function()
      local bags, bank, _, worn = C().LiveItemCounts(ITEM)
      assertEqual(bags, 0); assertEqual(bank, 4); assertEqual(worn, 0)
    end)
    assertEqual(calls.id, 0, "carried 0: no slot is read")
    with(M.C_Item, { GetItemInfoInstant = function() return ITEM, "Trade Goods", "Herb", "", 1, 7, 9 end }, function()
      withCounts({ bags = 3, bank = 0, account = 0 }, 0, function()
        local bags, _, _, worn = C().LiveItemCounts(ITEM)
        assertEqual(bags, 3); assertEqual(worn, 0)
      end)
    end)
    assertEqual(calls.id, 0, "an empty equip location: no slot is read")
  end)
end)

test("Compat tooltip: LiveItemCounts' account part is nil while the warband feature is off", function()
  with(NS.Constants.FEATURE, { warbandBank = false }, function()
    withCounts({ bags = 1, bank = 2, account = 3 }, 0, function()
      local bags, bank, account = C().LiveItemCounts(ITEM)
      assertEqual(bags, 1); assertEqual(bank, 2); assertNil(account)
    end)
  end)
end)

test("Compat tooltip: LiveItemCounts never goes below zero", function()
  local slot = NS.Constants.EQUIP_SLOTS[1]
  with(M.__inventory, { [slot] = { itemID = ITEM } }, function()
    with(M.C_Item, { GetItemCount = function() return 0 end }, function()
      local bags, bank = C().LiveItemCounts(ITEM)
      assertEqual(bags, 0); assertEqual(bank, 0)
    end)
  end)
end)

test("Compat tooltip: a secret or absent count gives nil for that part only", function()
  withSecrets(function()
    with(M.C_Item, { GetItemCount = function(_, includeBank)
      if includeBank then return T.secret(9) end
      return 4
    end }, function()
      local bags, bank, account = C().LiveItemCounts(ITEM)
      assertEqual(bags, 4, "the carried count is plain")
      assertNil(bank, "the bank count was secret"); assertNil(account)
    end)
  end)
  with(M.C_Item, { GetItemCount = NIL }, function()
    local bags, bank, account, worn = C().LiveItemCounts(ITEM)
    assertNil(bags); assertNil(bank); assertNil(account); assertNil(worn, "no carried count, no worn count")
  end)
  withCounts({ bags = 1, bank = 1, account = 1 }, 0, function()
    local bags, bank, account = C().LiveItemCounts("990101")
    assertNil(bags, "a non-number id"); assertNil(bank); assertNil(account)
  end)
end)

test("Compat tooltip: CurrencyQuantity reads GetCurrencyInfo's plain quantity", function()
  with(M.C_CurrencyInfo, { GetCurrencyInfo = function(id)
    if id == 3008 then return { quantity = 1205 } end
    if id == 2914 then return { quantity = "lots" } end
  end }, function()
    assertEqual(C().CurrencyQuantity(3008), 1205)
    assertNil(C().CurrencyQuantity(2914), "not a number")
    assertNil(C().CurrencyQuantity(1), "no info")
    assertNil(C().CurrencyQuantity("3008"), "a non-number id")
  end)
  with(M.C_CurrencyInfo, { GetCurrencyInfo = NIL }, function()
    assertNil(C().CurrencyQuantity(3008), "no API")
  end)
end)

test("Compat tooltip: ModifierDown reads each key, false for anything else", function()
  local down = { shift = false, ctrl = false, alt = false }
  with(M, {
    IsShiftKeyDown = function() return down.shift end,
    IsControlKeyDown = function() return down.ctrl end,
    IsAltKeyDown = function() return down.alt end,
  }, function()
    for _, key in ipairs({ "shift", "ctrl", "alt" }) do
      assertFalse(C().ModifierDown(key), key .. " up")
      down[key] = true
      assertTrue(C().ModifierDown(key), key .. " down")
      for other in pairs(down) do
        if other ~= key then assertFalse(C().ModifierDown(other), other .. " stays up") end
      end
      down[key] = false
    end
    assertFalse(C().ModifierDown("none")); assertFalse(C().ModifierDown(nil))
  end)
  with(M, { IsShiftKeyDown = NIL }, function() assertFalse(C().ModifierDown("shift"), "no API") end)
end)

test("Compat tooltip: ClassColor answers RAID_CLASS_COLORS' components, nil otherwise", function()
  local cc = M.RAID_CLASS_COLORS.MAGE
  local r, g, b = C().ClassColor("MAGE")
  assertEqual(r, cc.r); assertEqual(g, cc.g); assertEqual(b, cc.b)
  assertNil(C().ClassColor("NOTACLASS")); assertNil(C().ClassColor(nil)); assertNil(C().ClassColor(""))
  with(M, { RAID_CLASS_COLORS = NIL }, function() assertNil(C().ClassColor("MAGE"), "no table") end)
end)
