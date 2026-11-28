-- tests/test_farm_details.lua — a farm session's two reading windows (#39, farm spec
-- docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §7.3, §7.4, §13; mockups #39 "Details
-- window" and "Summary at Finish"): the six tabs, the Items columns and `n/a`, the other tabs' rows,
-- the Log's visible-slice binding over 2000 lines and its dropped-lines note, the resize spy (a size
-- tick relays only; one rebind and one save on release), the header marks (settings and close, not a
-- companion), the session reference and its follow into the saved list, the coalesced live refresh,
-- the summary's golden text against the mockup's values, Finish opening it, the refusals and the
-- stand-down.
--
-- After tests/test_farm_panel.lua, with the whole addon brought up. Every case runs on a scratch
-- db.global.farm with time() on a test clock, closes what it opened and hides both windows.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local F, FD, FM = NS.Farm, NS.FarmDetails, NS.FarmModel
local T0 = 1795000000
local clock = { t = T0 }
local NIL = {}

--- rawset `fields` on `t` for the call (NIL removes one), then put each back.
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

--- Chat lines written during `fn`, the prefix stripped.
local function chat(fn)
  local cf = M.DEFAULT_CHAT_FRAME
  local old, out = cf.AddMessage, {}
  cf.AddMessage = function(_, line)
    out[#out + 1] = tostring(line):gsub("^" .. NS.PREFIX:gsub("%p", "%%%0") .. " ", "")
  end
  local ok, err = pcall(fn)
  cf.AddMessage = old
  if not ok then error(err, 0) end
  return out
end

--- `patch` written over the profile settings (a nested `farm` merged key by key) for the call.
local function withSettings(patch, fn)
  local s = NS.db.profile.settings
  local saved = {}
  for k, v in pairs(patch) do saved[k] = { v = s[k] }; s[k] = v end
  local ok, err = pcall(fn)
  for k, v in pairs(saved) do s[k] = v.v end
  if not ok then error(err, 0) end
end

--- Run `body()` on a scratch farm store, the clock at T0, both windows hidden at the end.
local function world(body)
  local g, p = NS.db.global, NS.db.profile.settings.farm
  local saved = { g.farm, p.details, p.panel }
  g.farm, p.details, p.panel = {}, {}, {}
  clock.t = T0
  M.__fireTimers()  -- no repaint left over from an earlier suite lands inside a case
  local ok, err
  with(M, { time = function() return clock.t end }, function()
    chat(function()
      ok, err = pcall(body)
      NS.SimStores.farm, NS.State.testFarm = nil, nil
      if F:Active() then F:Finish("manual", clock.t) end
      F:Reconcile()
      FD:Hide()
      NS.FarmPanel:Hide()
    end)
  end)
  g.farm, p.details, p.panel = saved[1], saved[2], saved[3]
  if not ok then error(err, 0) end
end

local function me() return NS.Util.PlayerKey() end

local LINK_BRACERS = "|cff1eff00|Hitem:212001::::::::80:::::|h[Stormcharged Bracers]|h|r"
local LINK_BISMUTH = "|cffffffff|Hitem:210930::::::::80:::::|h[Bismuth]|h|r"
local LINK_ORE = "|cffffffff|Hitem:210931::::::::80:::::|h[Ironclaw Ore]|h|r"
local LINK_FANG = "|cff9d9d9d|Hitem:212002::::::::80:::::|h[Broken Fang]|h|r"

--- A finished session shaped to the mockup's summary (mockups.html, "Summary at Finish"): 27 Nov
--- 2026 19:02 to 20:31, 1 h 12 m active, Isle of Dorn then Ringing Deeps, 1,466g gross AH.
local function mockFinished(id)
  local start = os.time({ year = 2026, month = 11, day = 27, hour = 19, min = 2, sec = 0 })
  local s = FM.New(start, id or 1, "Charone-Realm", "MAGE", "Isle of Dorn")
  s.activeSec, s.runningSince = 4320, nil
  s.zoneSec = { ["Isle of Dorn"] = 3000, ["Ringing Deeps"] = 1320 }
  s.zoneOrder = { "Isle of Dorn", "Ringing Deeps" }
  s.items = {
    [212001] = { link = LINK_BRACERS, q = 2, qty = 1, vu = 140000, au = 4800000, src = { KILL = 1 } },
    [210930] = { link = LINK_BISMUTH, q = 1, qty = 212, vu = 1205, au = 20991, src = { GATHERING = 212 } },
    [210931] = { link = LINK_ORE, q = 1, qty = 96, vu = 2601, au = 28959, src = { GATHERING = 96 } },
    [212002] = { link = LINK_FANG, q = 0, qty = 2, vu = 9422, src = { KILL = 2 } },
  }
  s.money = { KILL = 1961000, CONTAINER = 650000 }
  s.costs = { REPAIR = 90000, BUY = 110000 }
  s.activity.mobs, s.activity.items, s.activity.nodes, s.activity.quests = 97, 402, 88, 5
  s.activity.quality = { [0] = 2, [1] = 308, [2] = 1 }
  s.log = { FM.Pack(10, "i", 210930, 5, "GATHERING"), FM.Pack(20, "m", 31200, "KILL"),
            FM.Pack(30, "o", "REPAIR", 90000, 0, 0), FM.Pack(40, "q", 7001, "A Glint of Ore") }
  s.endedAt, s.endReason = start + 89 * 60, "manual"
  s.primaryZone, s.name = "Isle of Dorn", "Isle of Dorn"
  s.totals = FM.Totals(s)
  s.mobRing, s.mobPos, s.lastSeen = nil, nil, nil
  return s
end

--- Save `s` into the scratch live store under its character; answers its reference.
local function save(s)
  local store = F:LiveStore()
  store[s.char] = store[s.char] or { sessions = {}, nextId = 1 }
  table.insert(store[s.char].sessions, s)
  return { store = "live", char = s.char, id = s.id }
end

local function dw() return FD:DetailsWindow() end
local function sw() return FD:SummaryWindow() end

local function cells(list, col)
  local out = {}
  for i, e in ipairs(list:Visible()) do out[i] = list.spec.columns[col].text(e) end
  return table.concat(out, "|")
end

local function row(list, i)
  local e, out = list:Visible()[i], {}
  for c, col in ipairs(list.spec.columns) do out[c] = col.text(e) end
  return table.concat(out, "|")
end

-- ── the Details window ───────────────────────────────────────────────────────────────────────

test("FarmDetails: settings and close, not a companion; on WINDOW; the title names the session", function()
  -- red under: the window built as a companion (close alone), or a mark left off.
  world(function()
    local ref = save(mockFinished())
    FD:Open(ref)
    local f = dw()
    assertTrue(f:IsShown())
    local hb = f.headerButtons
    assertTrue(hb ~= nil, "the marks are W.HeaderButtons'")
    assertEqual(table.concat(hb.order, ","), "settings,close")
    assertEqual(hb.companion, nil, "a secondary window, not a companion")
    assertTrue(f.settingsButton ~= nil and f.closeButton ~= nil)
    assertEqual(f.title:GetText(), "Session details: Isle of Dorn")
    assertEqual(f:GetName() or f.__name, "LootHistoryFarmDetails")
    F:Start()
    FD:Open(nil)
    assertEqual(f.title:GetText(), "Farm session: details", "nil is the open session")
  end)
end)

test("FarmDetails: six tabs in order, Items first, each tab its own list", function()
  world(function()
    FD:Open(save(mockFinished()))
    local f = dw()
    assertEqual(table.concat(FD.TABS, ","), "Items,Money,Currencies,Costs,Activity,Log")
    for _, name in ipairs(FD.TABS) do assertTrue(f.tabs[name] ~= nil, "a tab button for " .. name) end
    assertEqual(f.tab, "Items")
    for _, name in ipairs(FD.TABS) do
      f.tabs[name]:__fire("OnClick", "LeftButton")
      assertEqual(f.tab, name)
      assertTrue(f.lists[name] ~= nil and f.panes[name]:IsShown(), name .. " shows its list")
      for other, pane in pairs(f.panes) do
        if other ~= name then assertFalse(pane:IsShown(), other .. " hides behind " .. name) end
      end
    end
  end)
end)

test("FarmDetails: Items reads both prices per unit and in total, AH desc, n/a with no AH price", function()
  world(function()
    FD:Open(save(mockFinished()))
    local list = dw().lists.Items
    assertEqual(table.concat({ list.spec.columns[1].label, list.spec.columns[2].label, list.spec.columns[3].label,
      list.spec.columns[4].label, list.spec.columns[5].label, list.spec.columns[6].label,
      list.spec.columns[7].label }, ","), "Item,Qty,Vendor/u,Vendor,AH/u,AH,Source")
    assertEqual(cells(list, 1), "Stormcharged Bracers|Bismuth|Ironclaw Ore|Broken Fang", "AH value, largest first")
    assertEqual(row(list, 1), "Stormcharged Bracers|1|14g|14g|480g|480g|Kill")
    assertEqual(row(list, 2), "Bismuth|212|12s 05c|25g 54s 60c|2g 09s 91c|445g 92c|Gathering")
    assertEqual(row(list, 4), "Broken Fang|2|94s 22c|1g 88s 44c|n/a|1g 88s 44c|Kill",
      "no AH price: n/a per unit, the vendor price in the total (F8)")
    local r, g = list.spec.columns[1].color(list:Visible()[1])
    assertTrue(r ~= nil and g ~= nil, "the item name is quality-colored")
  end)
end)

test("FarmDetails: Money shares, Costs by reason then currency, Currencies by quantity", function()
  world(function()
    local s = mockFinished()
    s.costCurrencies = { [3008] = 40 }
    s.currencies = { [3008] = { qty = 120, src = { KILL = 100, QUEST = 20 } } }
    local ref = save(s)
    with(NS.Compat, { CurrencyName = function(id) return id == 3008 and "Valorstones" or nil end }, function()
      FD:Open(ref)
      FD:SelectTab("Money")
      local money = dw().lists.Money
      assertEqual(row(money, 1), "Kill|196g 10s|75%")
      assertEqual(row(money, 2), "Container|65g|25%")
      FD:SelectTab("Costs")
      local costs = dw().lists.Costs
      assertEqual(row(costs, 1), "Buy|-11g")
      assertEqual(row(costs, 2), "Repair|-9g")
      assertEqual(row(costs, 3), "Valorstones|x40", "the currency spent comes after the copper")
      FD:SelectTab("Currencies")
      assertEqual(row(dw().lists.Currencies, 1), "Valorstones|120|Kill")
    end)
  end)
end)

test("FarmDetails: Costs carries the ledger-off note while capture cannot see costs", function()
  world(function()
    local ref = save(mockFinished())
    withSettings({ trackLedger = false }, function()
      FD:Open(ref)
      FD:SelectTab("Costs")
      assertTrue(dw().note:IsShown())
      assertTrue(dw().note:GetText():find("Needs Track holdings and losses and Record gold", 1, true) ~= nil)
    end)
    FD:SelectTab("Costs")
    assertFalse(dw().note:IsShown(), "no note with both capture switches on")
  end)
end)

test("FarmDetails: Activity lists every enabled line, then the breakdowns indented", function()
  world(function()
    local s = mockFinished()
    s.activity.rep = { [2590] = { name = "Council of Dornogal", delta = 750 } }
    local ref = save(s)
    FD:Open(ref)
    FD:SelectTab("Activity")
    local list = dw().lists.Activity
    local labels = cells(list, 1)
    assertTrue(labels:find("^Mobs looted|Items looted|Nodes gathered|Fish caught|Quests turned in") ~= nil, labels)
    assertTrue(labels:find("Drops by quality|    Common|    Poor|    Uncommon", 1, true) ~= nil, labels)
    assertTrue(labels:find("Reputation by faction|    Council of Dornogal", 1, true) ~= nil, labels)
    assertEqual(row(list, 1), "Mobs looted|97")
  end)
end)

test("FarmDetails: the Log reads newest first and decodes each kind", function()
  world(function()
    FD:Open(save(mockFinished()))
    FD:SelectTab("Log")
    local list = dw().lists.Log
    assertEqual(row(list, 1), "00:00:40|Quest turned in: A Glint of Ore||Quest")
    assertEqual(row(list, 2), "00:00:30|Repair|-9g|Cost")
    assertEqual(row(list, 3), "00:00:20|3g 12s looted|3g 12s|Kill")
    assertEqual(row(list, 4), "00:00:10|Bismuth x5|10g 49s 55c|Gathering", "the value at the headline measure (AH)")
    assertFalse(dw().note:IsShown(), "nothing was dropped")
  end)
end)

test("FarmDetails: the Log binds only the visible slice of 2000 lines and notes the dropped ones", function()
  world(function()
    local s = mockFinished()
    s.log = {}
    for i = 1, 2000 do s.log[i] = FM.Pack(i, "m", 100 * i, "KILL") end
    s.logDropped = 340
    FD:Open(save(s))
    FD:SelectTab("Log")
    local list = dw().lists.Log
    assertEqual(#list.data, 2000, "every line is a row")
    assertEqual(#list:Visible(), list:NumVisible(), "one screen of rows bound")
    assertTrue(list:NumVisible() < 50)
    local _, active = NS.Pool.Counts(list.pool)
    assertEqual(active, list:NumVisible(), "one pooled row per visible line")
    assertEqual(list.spec.columns[1].text(list:Visible()[1]), "00:33:20", "the newest line first")
    assertEqual(dw().note:GetText(), "Showing the most recent 2,000 lines.")
  end)
end)

test("FarmDetails: a header click sorts Items; the Log is not re-sortable", function()
  world(function()
    FD:Open(save(mockFinished()))
    local items = dw().lists.Items
    items:HeaderClick("qty")
    assertEqual(cells(items, 2), "212|96|2|1", "Qty, largest first")
    FD:SelectTab("Log")
    local log = dw().lists.Log
    local before = cells(log, 1)
    log:HeaderClick("t")
    assertEqual(cells(log, 1), before)
  end)
end)

-- ── resize ───────────────────────────────────────────────────────────────────────────────────

test("FarmDetails: resizable from 480x300; a size tick relays only, the release rebinds once and saves", function()
  -- red under: the rebind or the save wired to OnSizeChanged, or the grip ignoring the lock.
  world(function()
    FD:Open(save(mockFinished()))
    FD:SelectTab("Items")
    local f = dw()
    assertTrue(f.__resizable, "the Details window is resizable")
    assertEqual(f.__resizeBounds[1], 480); assertEqual(f.__resizeBounds[2], 300)
    local list = f.lists.Items
    local binds, relays = 0, 0
    local bind, relay = list.Bind, list.Relayout
    rawset(list, "Bind", function(l) binds = binds + 1; return bind(l) end)
    rawset(list, "Relayout", function(l) relays = relays + 1; return relay(l) end)
    NS.db.profile.settings.farm.details = {}
    f:SetSize(800, 500)
    for _ = 1, 3 do f:__fire("OnSizeChanged", 800, 500) end
    assertTrue(relays >= 3, "each tick relays the columns")
    assertEqual(binds, 0, "a tick never rebinds")
    assertEqual(NS.db.profile.settings.farm.details.w, nil, "a tick never saves")
    with(NS.db.profile.settings, { locked = false }, function()
      f.resizeGrip:__fire("OnMouseDown", "LeftButton")
      f.resizeGrip:__fire("OnMouseUp", "LeftButton")
    end)
    assertEqual(binds, 1, "one rebind on release")
    local d = NS.db.profile.settings.farm.details
    assertEqual(d.w, 800); assertEqual(d.h, 500)
    rawset(list, "Bind", nil); rawset(list, "Relayout", nil)
    local calls = 0
    rawset(f, "StartSizing", function() calls = calls + 1 end)
    with(NS.db.profile.settings, { locked = true }, function()
      f.resizeGrip:__fire("OnMouseDown", "LeftButton")
    end)
    rawset(f, "StartSizing", nil)
    assertEqual(calls, 0, "locked, the grip does not size")
  end)
end)

test("FarmDetails: the saved geometry comes back on the next build's restore", function()
  world(function()
    NS.db.profile.settings.farm.details = { point = "TOPLEFT", x = 40, y = -60, w = 700, h = 450 }
    FD:AdoptProfile()
    FD:Open(save(mockFinished()))
    local f = dw()
    assertEqual(f:GetWidth(), 700); assertEqual(f:GetHeight(), 450)
  end)
end)

-- ── the reference and the live refresh ───────────────────────────────────────────────────────

test("FarmDetails: the open session refreshes live, coalesced, and follows its finish into the saved list", function()
  world(function()
    F:Start()
    FD:Open(nil)
    FD:SelectTab("Items")
    local list = dw().lists.Items
    local binds = 0
    local bind = list.Bind
    rawset(list, "Bind", function(l) binds = binds + 1; return bind(l) end)
    for i = 1, 3 do
      local g = NS.GainFeed:Begin("ITEM")
      g.id, g.link, g.qty, g.quality, g.source, g.name = 210930, LINK_BISMUTH, i, 1, "GATHERING", "Bismuth"
      NS.GainFeed:SendChat(g)
    end
    assertEqual(binds, 0, "nothing repaints inside the coalesce window")
    M.__fireTimers()
    assertEqual(binds, 1, "three gains, one repaint")
    assertEqual(cells(list, 2), "6")
    rawset(list, "Bind", nil)
    local id = F:Active().id
    F:Finish("manual", clock.t + 60)
    M.__fireTimers()
    assertTrue(dw():IsShown(), "the window stays up on the finished session")
    assertEqual(dw().ref.id, id, "it follows the session into the saved list")
    assertTrue(dw().title:GetText():find("^Session details: ") ~= nil, dw().title:GetText())
  end)
end)

test("FarmDetails: a window whose session is gone closes; a saved session ignores gain traffic", function()
  world(function()
    local ref = save(mockFinished())
    FD:Open(ref)
    local refreshes = 0
    with(FD, { Refresh = function() refreshes = refreshes + 1 end }, function()
      F:Changed("gain")
      M.__fireTimers()
      assertEqual(refreshes, 0, "a gain does not touch a saved session's window")
      F:Changed("rename")
      M.__fireTimers()
      assertEqual(refreshes, 1)
    end)
    F:LiveStore()[ref.char].sessions = {}
    F:Changed("delete")
    M.__fireTimers()
    assertFalse(dw():IsShown(), "the deleted session's window closed")
  end)
end)

test("FarmDetails: Open refuses with no session, while stood down and while visibility hides", function()
  world(function()
    local lines = chat(function() FD:Open(nil) end)
    assertEqual(table.concat(lines, "\n"), "no farm session to show.")
    local ref = save(mockFinished())
    with(NS, { IsStoodDown = function() return true end }, function()
      lines = chat(function() FD:Open(ref) end)
    end)
    assertEqual(#lines, 0, "silent while stood down: the verb gate already spoke")
    assertFalse(FD:IsShown())
    withSettings({ visibility = "never" }, function()
      lines = chat(function() FD:Open(ref) end)
    end)
    assertEqual(table.concat(lines, "\n"), "the farm windows are hidden by the General visibility setting.")
    assertFalse(FD:IsShown())
  end)
end)

test("FarmDetails: a visibility edge hides both windows; the panel's Details button opens the open session", function()
  world(function()
    F:Start()
    NS.FarmPanel:Refresh()
    local panel = NS.FarmPanel:Window()
    assertTrue(table.concat(panel.shownButtons, ","):find("details", 1, true) ~= nil, "the panel offers Details")
    panel.buttons.details:__fire("OnClick", "LeftButton")
    assertTrue(FD:IsShown())
    assertEqual(dw().ref.id, nil, "the open session")
    withSettings({ visibility = "outOfCombat" }, function() FD:ApplyVisibility(true) end)
    assertFalse(FD:IsShown(), "the pull hid it")
  end)
end)

test("FarmDetails: a simulation's session shows the sim strip, a saved one none", function()
  world(function()
    FD:Open(save(mockFinished()))
    local f = dw()
    if f.simStrip then assertFalse(f.simStrip:IsShown()) end
    NS.SimStores.farm = {}
    local s = mockFinished(9)
    NS.SimStores.farm[s.char] = { sessions = { s }, nextId = 10 }
    FD:Open({ store = "sim", char = s.char, id = 9 })
    if f.simStrip then assertTrue(f.simStrip:IsShown(), "the sim strip") end
    if f.testStrip then assertFalse(f.testStrip:IsShown()) end
  end)
end)

-- ── the summary ──────────────────────────────────────────────────────────────────────────────

test("FarmDetails: the summary reads the mockup's golden text", function()
  world(function()
    local ref = save(mockFinished())
    FD:OpenSummary(ref)
    local f = sw()
    assertTrue(f:IsShown())
    assertEqual(f.title:GetText(), "Session summary: Isle of Dorn")
    assertEqual(f.meta:GetText(), "27 Nov 2026 \194\183 19:02 to 20:31 \194\183 1 h 12 m active (17 m paused)"
      .. " \194\183 Charone \194\183 Isle of Dorn, Ringing Deeps")
    assertEqual(f.value:GetText(), "1,466g")
    assertEqual(f.rate:GetText(), "1,221g/h")
    assertEqual(f.sub:GetText(), "Gross, AH value \194\183 net 1,446g \194\183 1,205g/h")
    local kv = {}
    for i, p in ipairs(f.kv) do kv[i] = p.k:GetText() .. "=" .. p.v:GetText() end
    assertEqual(table.concat(kv, "|"), "Money looted=261g 10s|Items, vendor / AH=66g 40s / 1,204g 90s"
      .. "|Costs (repairs 9g, buys 11g)=-20g")
    local m = f.model
    local act = {}
    for i, line in ipairs(m.activity) do act[i] = line.label .. "=" .. line.text end
    assertEqual(table.concat(act, "|"), "Mobs looted=97|Items looted=402|Nodes gathered=88|Quests turned in=5",
      "the enabled, non-zero lines")
    local top = {}
    for i, p in ipairs(f.top) do if p.k:IsShown() then top[i] = p.k:GetText() .. "=" .. p.v:GetText() end end
    assertEqual(table.concat(top, "|"), "Stormcharged Bracers=480g|Bismuth x212=445g|Ironclaw Ore x96=278g")
    local src = {}
    for i, p in ipairs(f.src) do if p.k:IsShown() then src[i] = p.k:GetText() .. "=" .. p.v:GetText() end end
    assertEqual(table.concat(src, "|"), "Gathering=723g \194\183 49%|Kill=678g \194\183 46%|Container=65g \194\183 5%")
    assertEqual(f:GetName() or f.__name, "LootHistoryFarmSummary")
    assertEqual(table.concat(f.headerButtons.order, ","), "settings,close", "not a companion")
  end)
end)

test("FarmDetails: the summary's costs read n/a with ledger capture off", function()
  world(function()
    local ref = save(mockFinished())
    withSettings({ recordGold = false }, function()
      FD:OpenSummary(ref)
      assertEqual(sw().kv[3].k:GetText(), "Costs")
      assertEqual(sw().kv[3].v:GetText(), "n/a (needs ledger capture)")
    end)
  end)
end)

test("FarmDetails: the manual Finish opens the summary; its Details button opens the record", function()
  world(function()
    local s = F:Start()
    local g = NS.GainFeed:Begin("GOLD")
    g.qty, g.source = 31200, "KILL"
    NS.GainFeed:SendChat(g)
    clock.t = clock.t + 120
    F:FinishVerb()
    assertTrue(sw() ~= nil and sw():IsShown(), "Finish opened the summary")
    assertEqual(sw().ref.id, s.id)
    assertEqual(sw().ref.store, "live")
    sw().buttons.details:__fire("OnClick", "LeftButton")
    assertTrue(FD:IsShown())
    assertEqual(dw().ref.id, s.id)
    sw().buttons.close:__fire("OnClick", "LeftButton")
    assertFalse(sw():IsShown())
  end)
end)

test("FarmDetails: a discarded finish opens no summary; the summary refuses an open session", function()
  world(function()
    F:Start()
    F:FinishVerb()
    assertTrue(sw() == nil or not sw():IsShown(), "nothing was gained, nothing to summarize")
    F:Start()
    FD:OpenSummary(nil)
    assertTrue(sw() == nil or not sw():IsShown(), "an open session has no summary")
  end)
end)

-- ── the bus and the stand-down ───────────────────────────────────────────────────────────────

test("FarmDetails: Disable drops the bus target, Enable brings it back, Hide takes both windows down", function()
  world(function()
    local ref = save(mockFinished())
    FD:Open(ref)
    FD:OpenSummary(ref)
    assertTrue(FD.__ev ~= nil, "enabled with the addon")
    FD:Disable()
    assertEqual(FD.__ev, nil)
    FD:Enable()
    assertTrue(FD.__ev ~= nil)
    FD:Hide()
    assertFalse(dw():IsShown()); assertFalse(sw():IsShown())
  end)
end)

test("FarmDetails: Resolve reads without writing and answers nil for a missing session", function()
  world(function()
    assertEqual(FD.Resolve({ store = "live", char = "Nobody-Realm", id = 1 }), nil)
    assertEqual(F:LiveStore()["Nobody-Realm"], nil, "no entry created")
    assertEqual(FD.Resolve({ store = "test", char = me() }), nil, "no test sample")
    local ref = FD.Ref({ id = 4 })
    assertEqual(ref.store, "live"); assertEqual(ref.char, me()); assertEqual(ref.id, 4)
    NS.SimStores.farm = {}
    assertEqual(FD.Ref().store, "sim", "a simulation's store while one runs")
  end)
end)
