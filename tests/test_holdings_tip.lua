-- tests/test_holdings_tip.lua — the holdings block on item and currency tooltips (#34; spec
-- docs/superpowers/specs/2026-11-27-34-tooltip-holdings-design.md, sections 6 and 7):
-- modules/HoldingsTip.lua's post calls, guard ladder, never-twice marks, re-entrancy guard, rows,
-- replay fast path and settings, painted on tests/mock_tooltip_data.lua's double.
--
-- Every case runs under the active kit profile and asserts that profile's answer (clients-§6). The
-- harness does not stand the addon up, so each case brings the tally and the block up on a fresh
-- double, with the live reads stubbed on NS.Compat (WRAPPED members, read at call time), and puts
-- everything back after it: the double, the hook latches, the store, the five settings.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local time = function() return M.time() end
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local TDP = dofile("tests/mock_tooltip_data.lua")
local HT = function() return NS.HoldingsTip end
local C = NS.Constants
local ME, WB = T.ME, C.WARBAND_HOLDER
local ANN, BOB = T.nameKey("Ann"), T.nameKey("Bob")
local ITEM, CUR = 990101, 3008
local WARBAND_BANK = C.FEATURE.warbandBank
local TIP_KEYS = { "enabled", "containers", "warband", "totalMin2", "modifier" }

local function setTip(key, v) NS.Schema:Set("settings.tooltip." .. key, v) end

--- Run `fn(h, tip)` with the block up on a fresh double. `stubs`: "live" ({ bags, bank, account }),
--- "quantity", "accountWide". The store starts empty.
local function with(stubs, fn)
  local Cm, H, TL = NS.Compat, HT(), NS.HoldingsTally
  local h = TDP.install(M)
  local saved = { Cm.LiveItemCounts, Cm.CurrencyQuantity, Cm.CurrencyIsAccountWide, H._hookedItem, H._hookedCurrency,
                  NS.db.global.holdings, NS.Schema:Get("settings.trackLedger") }
  local wasTally, wasTip = TL.__ev ~= nil, H.__ev ~= nil
  local live = stubs.live or {}
  Cm.LiveItemCounts = function() return live[1], live[2], live[3] end
  Cm.CurrencyQuantity = function() return stubs.quantity end
  Cm.CurrencyIsAccountWide = function() return stubs.accountWide == true end
  NS.db.global.holdings = {}
  H._hookedItem, H._hookedCurrency = nil, nil
  if stubs.dropCurrency then h.dropType("Currency") end
  TL:Enable(); H:Enable()
  TL:Invalidate()
  local ok, err = pcall(fn, h, h.tooltip("GameTooltip"), live)
  for _, k in ipairs(TIP_KEYS) do setTip(k, NS.defaults.profile.settings.tooltip[k]) end
  NS.Schema:Set("settings.trackLedger", saved[7])
  Cm.LiveItemCounts, Cm.CurrencyQuantity, Cm.CurrencyIsAccountWide = saved[1], saved[2], saved[3]
  H._hookedItem, H._hookedCurrency = saved[4], saved[5]
  NS.db.global.holdings = saved[6]
  TL:Invalidate()
  if not wasTip then H:Disable() else H:RefreshConfig() end
  if not wasTally then TL:Disable() end
  h.uninstall()
  if not ok then error(err, 0) end
end

local function put(holder, container, counts, classFile, ts)
  NS.Holdings:ApplyContainer(holder, container, counts, {}, ts or time())
  if classFile then NS.Holdings:Get(holder).meta.classFile = classFile end
end

--- The tooltip's lines after the client's own first one (the block alone), as tdp.texts writes them.
local function block(h, tip)
  local out, texts = {}, h.texts(tip)
  for i = 2, #texts do out[#out + 1] = texts[i] end
  return out
end

local function lineOf(tip, left)
  for i = 2, #tip.__lines do if tip.__lines[i].text == left then return tip.__lines[i] end end
  return nil
end

local function short(key) return key:match("^[^-]+") or key end

local function markup(container, token)
  local r, g, b = NS.Skin.Color(token or "gtip.value")
  return NS.IconMarkup(C.TIP_ICONS[container], C.TIP_ICON_FALLBACK, C.TIP_ICON_SIZE, r, g, b)
end

local function assertColor(line, token, label, right)
  local r, g, b = NS.Skin.Color(token)
  if right then
    assertEqual(line.rr, r, label); assertEqual(line.rg, g, label); assertEqual(line.rb, b, label)
  else
    assertEqual(line.r, r, label); assertEqual(line.g, g, label); assertEqual(line.b, b, label)
  end
end

-- ── the item block ────────────────────────────────────────────────────────────────────────────

test("HoldingsTip: an item block is a spacer, the header, the holders and the Total, in order", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 }, "MAGE"); put(ANN, "bank", { [ITEM] = 10 })
    put(BOB, "mail", { [ITEM] = 20 })
    h.show(tip, "Item", { id = ITEM })
    local got = block(h, tip)
    assertEqual(#got, 5)
    assertEqual(got[1], " ")
    assertEqual(got[2], NS.BRAND)
    assertEqual(got[3], short(BOB) .. " | " .. markup("mail") .. " 20")
    assertEqual(got[4], short(ANN) .. " | " .. markup("bags") .. " 3  " .. markup("bank") .. " 10")
    assertEqual(got[5], "Total | 33")
    assertColor(tip.__lines[3], "gtip.title", "the header")
    assertColor(lineOf(tip, "Total"), "gtip.title", "the Total's label")
    assertColor(lineOf(tip, "Total"), "gtip.value", "the Total's count", true)
    assertColor(lineOf(tip, short(ANN)), "gtip.value", "a holder's counts", true)
  end)
end)

test("HoldingsTip: a character's name is in its class color, else gtip.body", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 }, "MAGE"); put(BOB, "bags", { [ITEM] = 2 })
    h.show(tip, "Item", { id = ITEM })
    local r, g, b = NS.Compat.ClassColor("MAGE")
    assertTrue(r ~= nil, "the mock knows MAGE")
    local ann = lineOf(tip, short(ANN))
    assertEqual(ann.r, r); assertEqual(ann.g, g); assertEqual(ann.b, b)
    assertColor(lineOf(tip, short(BOB)), "gtip.body", "no classFile: gtip.body")
  end)
end)

test("HoldingsTip: the account holder reads in C.ACCOUNT's word and sem.warbandAlt", function()
  with({}, function(h, tip)
    put(WB, "tabs", { [ITEM] = 50 })
    put(ANN, "bags", { [ITEM] = 1 })
    h.show(tip, "Item", { id = ITEM })
    local wb = lineOf(tip, C.ACCOUNT.holder)
    assertTrue(wb ~= nil, "the " .. C.ACCOUNT.holder .. " line")
    assertColor(wb, "sem.warbandAlt", "the account holder")
    assertEqual(tip.__lines[#tip.__lines - 1], wb, "the account holder is the last holder line")
    if WARBAND_BANK then
      assertEqual(wb.right, markup("tabs") .. " 50")
    else
      assertEqual(wb.right, "50", "no tabs mark on WoW Forever: its stored count, plainly")
    end
  end)
end)

test("HoldingsTip: a currency block has plain counts and no icons", function()
  with({ quantity = 7 }, function(h, tip)
    NS.Holdings:ApplyCurrency(ANN, { [CUR] = 1205 }, time())
    h.show(tip, "Currency", { id = CUR })
    local got = block(h, tip)
    assertEqual(table.concat(got, "\n"), table.concat({ " ", NS.BRAND,
      short(ANN) .. " | " .. NS.Compat.FormatCount(1205), short(ME) .. " | 7",
      "Total | " .. NS.Compat.FormatCount(1212) }, "\n"))
    for _, t in ipairs(got) do assertTrue(t:find("|T", 1, true) == nil, "an icon in a currency block: " .. t) end
  end)
end)

-- ── the Total rule ────────────────────────────────────────────────────────────────────────────

test("HoldingsTip: one holder draws no Total by default, a Total with Show the Total only with 2 off", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 })
    h.show(tip, "Item", { id = ITEM })
    assertEqual(#block(h, tip), 3, "spacer, header, one holder")
    setTip("totalMin2", false)
    h.refresh(tip, "Item", { id = ITEM })
    local got = block(h, tip)
    assertEqual(got[#got], "Total | 3")
  end)
end)

test("HoldingsTip: two holders draw a Total", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 }); put(BOB, "bags", { [ITEM] = 4 })
    h.show(tip, "Item", { id = ITEM })
    local got = block(h, tip)
    assertEqual(got[#got], "Total | 7")
  end)
end)

-- ── staleness ─────────────────────────────────────────────────────────────────────────────────

test("HoldingsTip: a stored container three days old draws its muted mark and the age", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 })
    put(ANN, "bank", { [ITEM] = 10 }, nil, time() - 3 * 86400)
    h.show(tip, "Item", { id = ITEM })
    local want = markup("bags") .. " 3  " .. markup("bank") .. " 10  "
      .. NS.Compat.TooltipTint("gtip.muted", markup("bank", "gtip.muted") .. " 3 d")
    assertEqual(lineOf(tip, short(ANN)).right, want)
  end)
end)

-- ── the settings rows ─────────────────────────────────────────────────────────────────────────

test("HoldingsTip: containers off draws one count per holder", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 }); put(ANN, "bank", { [ITEM] = 10 })
    setTip("containers", false)
    h.show(tip, "Item", { id = ITEM })
    assertEqual(block(h, tip)[3], short(ANN) .. " | 13")
  end)
end)

test("HoldingsTip: warband off drops the account line, and an account-wide currency draws no block", function()
  with({ quantity = 40, accountWide = true }, function(h, tip)
    put(WB, "tabs", { [ITEM] = 50 }); put(ANN, "bags", { [ITEM] = 1 })
    setTip("warband", false)
    h.show(tip, "Item", { id = ITEM })
    assertTrue(lineOf(tip, C.ACCOUNT.holder) == nil, "no account line")
    assertEqual(#block(h, tip), 3)
    h.show(tip, "Currency", { id = CUR })
    assertEqual(#tip.__lines, 1, "only the client's line: no header without a holder")
    setTip("warband", true)
    h.refresh(tip, "Currency", { id = CUR })
    assertEqual(block(h, tip)[3], C.ACCOUNT.holder .. " | 40")
  end)
end)

test("HoldingsTip: two characters with one short name show their full keys", function()
  with({}, function(h, tip)
    if T.forever then
      -- WoW Forever's keys have no realm and stay whole (forever-quirks-§4).
      put("Ann Smith", "bags", { [ITEM] = 2 })
      h.show(tip, "Item", { id = ITEM })
      assertTrue(lineOf(tip, "Ann Smith") ~= nil, "a Forever key stays whole")
      return
    end
    put("Ann-RealmA", "bags", { [ITEM] = 2 }); put("Ann-RealmB", "bags", { [ITEM] = 1 })
    put(BOB, "bags", { [ITEM] = 1 })
    h.show(tip, "Item", { id = ITEM })
    assertTrue(lineOf(tip, "Ann-RealmA") ~= nil and lineOf(tip, "Ann-RealmB") ~= nil, "full keys")
    assertTrue(lineOf(tip, "Bob") ~= nil, "a unique short name stays short")
  end)
end)

test("HoldingsTip: Track holdings and losses off draws nothing, and on again draws (D3)", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 })
    NS.Schema:Set("settings.trackLedger", false)
    h.show(tip, "Item", { id = ITEM })
    assertEqual(#tip.__lines, 1)
    NS.Schema:Set("settings.trackLedger", true)
    h.refresh(tip, "Item", { id = ITEM })
    assertEqual(#block(h, tip), 3)
  end)
end)

test("HoldingsTip: Show holdings off draws nothing", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 })
    setTip("enabled", false)
    h.show(tip, "Item", { id = ITEM })
    assertEqual(#tip.__lines, 1)
  end)
end)

test("HoldingsTip: a stood-down addon draws nothing, and stood up again it draws", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 })
    local saved = NS.IsStoodDown
    NS.IsStoodDown = function() return true end
    local ok, err = pcall(h.show, tip, "Item", { id = ITEM })
    NS.IsStoodDown = saved
    if not ok then error(err, 0) end
    assertEqual(#tip.__lines, 1, "the IsStoodDown rung")
    h.refresh(tip, "Item", { id = ITEM })
    assertEqual(#block(h, tip), 3)
  end)
end)

test("HoldingsTip: Only while holding Shift draws only with Shift down", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 })
    setTip("modifier", "shift")
    local saved = rawget(M, "IsShiftKeyDown")
    local down = false
    rawset(M, "IsShiftKeyDown", function() return down end)
    local ok, err = pcall(function()
      h.show(tip, "Item", { id = ITEM })
      assertEqual(#tip.__lines, 1, "no Shift: no block")
      down = true
      h.refresh(tip, "Item", { id = ITEM })
      assertEqual(#block(h, tip), 3, "Shift: the block")
    end)
    rawset(M, "IsShiftKeyDown", saved)
    if not ok then error(err, 0) end
  end)
end)

test("HoldingsTip: each row's onChange sends SETTINGS_CHANGED tooltip, and the cache refreshes", function()
  with({}, function()
    local reasons, probe = {}, NS.NewBusTarget()
    probe:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, reason) reasons[#reasons + 1] = reason end)
    local cfg = HT()._cfg
    local values = { enabled = false, containers = false, warband = false, totalMin2 = false, modifier = "alt" }
    for _, k in ipairs(TIP_KEYS) do
      local before = cfg.cfgVer
      setTip(k, values[k])
      assertTrue(cfg.cfgVer > before, k .. ": the cache did not refresh")
      assertEqual(cfg[k == "enabled" and "active" or k], values[k], k .. ": the cache holds the new value")
    end
    probe:UnregisterAllMessages()
    assertEqual(table.concat(reasons, ","), "tooltip,tooltip,tooltip,tooltip,tooltip")
  end)
end)

-- ── never twice ───────────────────────────────────────────────────────────────────────────────

test("HoldingsTip: a repost adds no second block; a refresh draws exactly one; after hide it draws", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 })
    h.show(tip, "Item", { id = ITEM })
    assertEqual(#tip.__lines, 4)
    h.repost(tip, "Item", { id = ITEM })
    assertEqual(#tip.__lines, 4, "a repost with no clear writes nothing")
    h.refresh(tip, "Item", { id = ITEM })
    assertEqual(#tip.__lines, 4, "clear and refill: one fresh block")
    h.hide(tip)
    h.repost(tip, "Item", { id = ITEM })
    assertEqual(#tip.__lines, 7, "after OnHide the mark is gone")
  end)
end)

-- ── the guards ────────────────────────────────────────────────────────────────────────────────

test("HoldingsTip: a forbidden, a comparison, a secret-id or an id-less tooltip writes nothing", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 })
    tip.forbidden = true
    h.show(tip, "Item", { id = ITEM })
    assertEqual(#tip.__lines, 1, "forbidden")
    tip.forbidden = false
    local shop = h.tooltip("ShoppingTooltip1")
    h.show(shop, "Item", { id = ITEM })
    assertEqual(#shop.__lines, 1, "a comparison tooltip")
    h.show(tip, "Item", {})
    assertEqual(#tip.__lines, 1, "no id")
    local savedSecret = rawget(M, "issecretvalue")
    rawset(M, "issecretvalue", function(v) return T.isSecret(v) end)
    local ok, err = pcall(h.show, tip, "Item", { id = T.secret(ITEM) })
    rawset(M, "issecretvalue", savedSecret)
    if not ok then error(err, 0) end
    assertEqual(#tip.__lines, 1, "a secret id")
  end)
end)

test("HoldingsTip: a re-entrant post call writes nothing, and an error inside releases busy", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 })
    local other = h.tooltip("ItemRefTooltip")
    local add = tip.AddLine
    tip.AddLine = function(self, ...)
      tip.AddLine = add
      HT().OnTooltip(other, { id = ITEM }, 1)
      return add(self, ...)
    end
    h.repost(tip, "Item", { id = ITEM })
    assertEqual(#other.__lines, 0, "the nested post call wrote nothing")
    assertEqual(#tip.__lines, 3, "the outer block still drew (spacer, header, one holder)")
    local paint = NS.Compat.AppendTooltipRows
    NS.Compat.AppendTooltipRows = function() error("boom", 0) end
    local ok = pcall(HT().OnTooltip, other, { id = ITEM }, 1)
    NS.Compat.AppendTooltipRows = paint
    assertFalse(ok, "the error is raised again")
    assertTrue(HT().OnTooltip(other, { id = ITEM }, 1), "busy was released")
  end)
end)

test("HoldingsTip: the block never owns placement (no SetOwner, no PlaceTooltip)", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 })
    local place, placed = NS.Compat.PlaceTooltip, 0
    NS.Compat.PlaceTooltip = function(...) placed = placed + 1; return place(...) end
    local ok, err = pcall(h.show, tip, "Item", { id = ITEM })
    NS.Compat.PlaceTooltip = place
    if not ok then error(err, 0) end
    assertEqual(#tip.owners, 0, "SetOwner")
    assertEqual(placed, 0, "PlaceTooltip")
    assertTrue(tip.shows >= 2, "the block asked the tooltip to lay itself out again")
  end)
end)

-- ── the replay fast path ──────────────────────────────────────────────────────────────────────

test("HoldingsTip: an unchanged refresh replays the lines: no tally compose, no icon markup", function()
  with({ live = { 2, nil, nil } }, function(h, tip, live)
    put(ANN, "bags", { [ITEM] = 3 })
    h.show(tip, "Item", { id = ITEM })
    local first = block(h, tip)
    local TL, markups, composes = NS.HoldingsTally, 0, 0
    local iconMarkup, item = NS.IconMarkup, TL.Item
    NS.IconMarkup = function(...) markups = markups + 1; return iconMarkup(...) end
    TL.Item = function(...) composes = composes + 1; return item(...) end
    local ok, err = pcall(function()
      h.refresh(tip, "Item", { id = ITEM })
      assertEqual(table.concat(block(h, tip), "\n"), table.concat(first, "\n"), "the same lines")
      assertEqual(markups, 0, "icon markup on a replay")
      assertEqual(composes, 0, "a tally compose on a replay")
      live[1] = 5
      h.refresh(tip, "Item", { id = ITEM })
      assertEqual(composes, 1, "a changed live count rebuilds")
    end)
    NS.IconMarkup, TL.Item = iconMarkup, item
    if not ok then error(err, 0) end
    assertEqual(lineOf(tip, short(ME)).right, markup("bags") .. " 5")
  end)
end)

test("HoldingsTip: a skin switch reaches the block's colors on the next refresh", function()
  with({}, function(h, tip)
    put(ANN, "bags", { [ITEM] = 3 })
    h.show(tip, "Item", { id = ITEM })
    local Skin = M.LibStub("LibKa0s-Skin-1.0")
    local before = { NS.Skin.Color("gtip.title") }
    local moved
    for _, def in ipairs(Skin:Skins()) do
      NS.ApplySkinChoice("ka0s", def.key)
      local now = { NS.Skin.Color("gtip.title") }
      if now[1] ~= before[1] or now[2] ~= before[2] or now[3] ~= before[3] then moved = def.key; break end
    end
    local ok, err = pcall(function()
      assertTrue(moved ~= nil, "no shipped skin moves gtip.title")
      h.refresh(tip, "Item", { id = ITEM })
      assertColor(tip.__lines[3], "gtip.title", "the header follows the skin")
      assertEqual(lineOf(tip, short(ANN)).right, markup("bags") .. " 3", "the marks follow gtip.value")
    end)
    NS.ApplySkinChoice()
    if not ok then error(err, 0) end
  end)
end)

-- ── per client ────────────────────────────────────────────────────────────────────────────────

test("HoldingsTip: ORDER draws the warband bank's tabs only where it is a feature", function()
  local order = table.concat(HT().ORDER, ",")
  if WARBAND_BANK then
    assertEqual(order, "bags,equipped,bank,mail,auctions,tabs")
  else
    assertEqual(order, "bags,equipped,bank,mail,auctions")
  end
end)

test("HoldingsTip: WoW Forever never builds the locked-chest mark and says Account", function()
  with({}, function(h, tip)
    put(WB, "tabs", { [ITEM] = 4 }); put(ANN, "bags", { [ITEM] = 1 })
    local iconMarkup, names = NS.IconMarkup, {}
    NS.IconMarkup = function(name, ...) names[name] = true; return iconMarkup(name, ...) end
    local ok, err = pcall(h.show, tip, "Item", { id = ITEM })
    NS.IconMarkup = iconMarkup
    if not ok then error(err, 0) end
    assertEqual(names["gi:locked-chest"] == true, WARBAND_BANK == true, "the locked-chest mark")
    assertTrue(lineOf(tip, C.ACCOUNT.holder) ~= nil)
    assertEqual(C.ACCOUNT.holder, T.forever and "Account" or "Warband")
  end)
end)

test("HoldingsTip: the Include row names the client's account holder", function()
  local row = NS.Schema:FindRow("settings.tooltip.warband")
  assertEqual(row.label, T.forever and "Include the Account" or "Include the Warband")
  assertEqual(row.group, "Interface"); assertEqual(row.subgroup, "Holdings in tooltips")
  local cont = NS.Schema:FindRow("settings.tooltip.containers").tooltip
  assertEqual(cont:find("warband bank", 1, true) ~= nil, WARBAND_BANK == true)
end)

-- ── the hooks and the target ──────────────────────────────────────────────────────────────────

test("HoldingsTip: Enable installs one Item and one Currency post call, once", function()
  with({}, function(h)
    assertEqual(h.count("Item"), 1); assertEqual(h.count("Currency"), 1)
    HT():Disable(); HT():Enable()
    assertEqual(h.count("Item"), 1, "a second Enable installs nothing")
    assertTrue(HT()._hookedItem and HT()._hookedCurrency)
  end)
end)

test("HoldingsTip: with no Currency data type, items still draw", function()
  with({ dropCurrency = true }, function(h, tip)
    assertFalse(HT()._hookedCurrency, "no Currency type: not hooked")
    assertTrue(HT()._hookedItem, "the Item type is hooked")
    put(ANN, "bags", { [ITEM] = 3 })
    h.show(tip, "Item", { id = ITEM })
    assertEqual(#block(h, tip), 3)
  end)
end)

test("HoldingsTip: its bus target is registered while up and gone after Disable", function()
  with({}, function()
    assertTrue(HT().__ev ~= nil)
    HT():Disable()
    assertEqual(HT().__ev, nil)
    HT():Enable()
  end)
end)
