-- tests/test_farm_tab.lua — the History window's Farm tab and the panel's sessions list (#39, farm spec
-- docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §7.2, §7.5, §7.6, §12.3, §13; mockups #39
-- "Saved sessions"): the tab's order and honored filters, the Character and Zone option sources, the
-- rows against the filter, the test sample's mockup rows and its best-per-zone stars, the Measure
-- cycle in the saved view, the click, double-click and right-click routes, the Rename and Delete
-- popups (a sim row edits the sim store), the test-mode refusal, TD.Publish, and the sessions list
-- (a companion with close alone, docked, one tooltip group with the panel).
--
-- After tests/test_farm_details.lua, with the whole addon brought up. Every case runs on a scratch
-- db.global.farm with time() on a test clock, and closes every window it opened.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local F, FT, FP, FD, FM, B = NS.Farm, NS.FarmTab, NS.FarmPanel, NS.FarmDetails, NS.FarmModel, NS.Browser
local T0 = os.time({ year = 2026, month = 11, day = 27, hour = 23, min = 0, sec = 0 })
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

--- Run `body()` on a scratch farm store, the clock at T0, every farm window and the browser closed.
local function world(body)
  local g, p = NS.db.global, NS.db.profile.settings
  local saved = { g.farm, p.farm.panel, p.farm.details, p.visibility, FT.sortKey, FT.sortAsc, FT.measure }
  g.farm, p.farm.panel, p.farm.details, p.visibility = {}, {}, {}, "always"
  clock.t = T0
  M.__fireTimers()
  local ok, err
  with(M, { time = function(t) if t then return os.time(t) end return clock.t end }, function()
    ok, err = pcall(body)
    NS.SimStores.farm, NS.State.testFarm = nil, nil
    if F:Active() then F:Finish("manual", clock.t) end
    F:Reconcile()
    FD:Hide(); FP:Hide()
    if B:GetWindow() then B:SelectTab("History"); B._forgetLive("Farm"); B:Hide() end
  end)
  g.farm, p.farm.panel, p.farm.details, p.visibility = saved[1], saved[2], saved[3], saved[4]
  FT.sortKey, FT.sortAsc, FT.measure = saved[5], saved[6], saved[7]
  if not ok then error(err, 0) end
end

local function me() return NS.Util.PlayerKey() end

--- A finished session of `char` started `at`, in `zone`, `activeSec` active, worth `gold` (money only).
local function finished(char, id, at, zone, activeSec, gold, name)
  local s = FM.New(at, id, char, "MAGE", zone)
  s.money = { KILL = gold * 10000 }
  s.activeSec, s.runningSince = activeSec, nil
  s.log = { FM.Pack(10, "m", gold * 10000, "KILL") }
  s.endedAt, s.endReason = at + activeSec, "manual"
  s.primaryZone, s.name = zone, name or zone
  s.totals = FM.Totals(s)
  s.mobRing, s.mobPos, s.lastSeen = nil, nil, nil
  return s
end

--- Put `s` into `store` under its character.
local function put(store, s)
  store[s.char] = store[s.char] or { sessions = {}, nextId = 1 }
  table.insert(store[s.char].sessions, s)
  store[s.char].nextId = math.max(store[s.char].nextId, s.id + 1)
  return { store = "live", char = s.char, id = s.id }
end

local function seed()
  local store = F:LiveStore()
  put(store, finished(me(), 1, T0 - 3 * 86400, "Isle of Dorn", 3600, 500, "Morning ore"))
  put(store, finished(me(), 2, T0 - 86400, "Ringing Deeps", 1800, 400))
  put(store, finished("Alt-Realm", 1, T0 - 2 * 86400, "Isle of Dorn", 3600, 900))
  return store
end

local function cell(e, key) return FT.COLUMNS[key].text(e) end

local function rowText(e)
  local out = {}
  for _, key in ipairs({ "date", "zone", "active", "total", "rate" }) do out[#out + 1] = cell(e, key) end
  out[#out + 1] = e.best and "*" or ""
  return table.concat(out, "|")
end

local function values(opts)
  local out = {}
  for i, o in ipairs(opts) do out[i] = tostring(o.value) end
  return table.concat(out, ",")
end

-- ── the registration ─────────────────────────────────────────────────────────────────────────

test("FarmTab: registered at order 50, after Timeline and Holdings", function()
  local names = B:Tabs()
  assertEqual(table.concat(names, ","), "History,Insights,Timeline,Holdings,Farm")
  assertEqual(B._tabSpec("Farm").order, 50)
end)

test("FarmTab: honors Search, Character and Zone; every other control is grayed", function()
  -- red under: a spec with no `filters` set (it would honor Export and Group too).
  local spec = B._tabSpec("Farm")
  for _, key in ipairs({ "search", "char", "zone" }) do
    assertTrue(B._filterHonored(spec, key), key .. " is honored")
  end
  for _, key in ipairs({ "export", "group", "date", "source", "quality", "type", "subtype", "bound", "dir" }) do
    assertFalse(B._filterHonored(spec, key), key .. " is grayed")
  end
  assertEqual(spec.charSource, "farm"); assertEqual(spec.zoneSource, "farm")
end)

test("FarmTab: the farm option sources list the characters and zones with saved sessions", function()
  -- red under: charOptions/zoneOptions ignoring their mode (the History rows' lists instead).
  world(function()
    seed()
    F:Start()   -- the open session is no saved one: its zone and character do not add an option
    F:Active().zone = "Hallowfall"
    local chars = B._options.char("farm")
    assertEqual(values(chars), "all,current,Alt-Realm," .. me())
    local zones = B._options.zone("farm")
    assertEqual(values(zones), "all,Isle of Dorn,Ringing Deeps")
    assertEqual(table.concat((function()
      local out = {}
      for i, c in ipairs(F:Characters()) do out[i] = c.key .. "=" .. tostring(c.classFile) end
      return out
    end)(), ","), "Alt-Realm=MAGE," .. me() .. "=MAGE")
  end)
end)

test("FarmTab: selecting the tab reads its option sources; leaving it prunes a pick History lacks", function()
  -- red under: B:RefreshFilterOptions reading charSource as the old holders boolean.
  world(function()
    seed()
    B:Show()
    B:SelectTab("Farm")
    assertEqual(B._charMode, "farm")
    B:SetCharSet({ ["Alt-Realm"] = true })
    B:SelectTab("History")
    assertEqual(B._charMode, "history")
  end)
end)

-- ── the rows ─────────────────────────────────────────────────────────────────────────────────

test("FarmTab: rows filter by Character, Zone and Search (name or zone); the open session is not listed", function()
  world(function()
    local store = seed()
    F:Start()
    local function n(f) return #FT.Rows(store, "live", f, "ah") end
    assertEqual(n({}), 3, "every saved session, the open one not among them")
    assertEqual(n({ char = { [me()] = true } }), 2)
    assertEqual(n({ zone = { ["Isle of Dorn"] = true } }), 2)
    assertEqual(n({ text = "morning" }), 1, "the name matches")
    assertEqual(n({ text = "DEEPS" }), 1, "the zone matches, case-blind")
    assertEqual(n({ text = "nowhere" }), 0)
  end)
end)

test("FarmTab: the test sample reproduces the mockup's rows, one star per zone", function()
  -- red under: a sample whose numbers drift from mockups.html's Saved sessions rows.
  world(function()
    local store = NS.FarmTestData.Build(T0)
    local rows = FT.Rows(store, "test", {}, "ah")
    assertEqual(#rows, 6, "six sample sessions")
    table.sort(rows, function(a, b) return a.s.startedAt > b.s.startedAt end)
    assertEqual(rowText(rows[1]), "27 Nov|Isle of Dorn|1:12|1,466g|1,221g|*")
    assertEqual(rowText(rows[2]), "25 Nov|Ringing Deeps|0:48|792g|990g|*")
    assertEqual(rowText(rows[3]), "24 Nov|Isle of Dorn|2:05|1,750g|840g|")
    local zones, stars = {}, 0
    for _, e in ipairs(rows) do
      zones[e.s.primaryZone] = (zones[e.s.primaryZone] or 0) + 1
      if e.best then stars = stars + 1 end
      assertEqual(#e.s.log, 40, "40 log lines each")
      assertTrue(e.s.endedAt ~= nil and e.s.runningSince == nil, "finished")
    end
    assertEqual(zones["Isle of Dorn"], 3); assertEqual(zones["Ringing Deeps"], 2); assertEqual(zones.Hallowfall, 1)
    assertEqual(stars, 3, "one best session per zone")
    assertTrue(cell(rows[1], "star"):find(NS.Icon("star"), 1, true) ~= nil, "the star is the catalog's mark")
  end)
end)

test("FarmTab: the sample is deterministic", function()
  local function dump(store)
    local out = {}
    local keys = {}
    for k in pairs(store) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      for _, s in ipairs(store[k].sessions) do
        out[#out + 1] = k .. ":" .. s.id .. ":" .. s.startedAt .. ":" .. table.concat(s.log, ";")
          .. ":" .. FM.Value(s.totals, "vendor", "net")
      end
    end
    return table.concat(out, "\n")
  end
  assertEqual(dump(NS.FarmTestData.Build(T0)), dump(NS.FarmTestData.Build(T0)))
end)

test("FarmTab: the Total and Gross/h columns follow the measure", function()
  world(function()
    local store = F:LiveStore()
    local s = finished(me(), 1, T0 - 86400, "Isle of Dorn", 3600, 100)
    s.items = { [7] = { link = "|Hitem:7|h[Apple]|h", q = 1, qty = 10, vu = 10000, au = 50000, src = { KILL = 10 } } }
    s.totals = FM.Totals(s)
    put(store, s)
    local function at(m) local e = FT.Rows(store, "live", {}, m)[1]; return cell(e, "total") .. "/" .. cell(e, "rate") end
    assertEqual(at("money"), "100g/100g")
    assertEqual(at("vendor"), "110g/110g")
    assertEqual(at("ah"), "150g/150g")
  end)
end)

-- ── the tab on screen and its saved view ─────────────────────────────────────────────────────

test("FarmTab: the tab lists the sessions newest first under its header band", function()
  world(function()
    seed()
    B:Show(); B:SelectTab("Farm"); B:SetCharSet(nil)
    assertEqual(FT.title:GetText(), "Saved sessions")
    assertEqual(FT.hint:GetText(), FT.HINT)
    assertEqual(FT.measureBtn.text:GetText(), "Measure: AH")
    local vis = FT.list:Visible()
    assertEqual(#vis, 3)
    assertEqual(cell(vis[1], "zone") .. "," .. cell(vis[2], "zone") .. "," .. cell(vis[3], "zone"),
      "Ringing Deeps,Isle of Dorn,Isle of Dorn")
    assertEqual(cell(vis[2], "char"), "Alt", "the character without its realm")
    B:SetCharSet({ [me()] = true })
    assertEqual(#FT.list:Visible(), 2, "the shared Character filter narrows it")
  end)
end)

test("FarmTab: the Measure cycle is part of the tab's saved view", function()
  -- red under: the measure kept outside the view (Save, Reset and Clear would not reach it).
  world(function()
    seed()
    B:Show(); B:SelectTab("Farm")
    FT:CycleMeasure()
    assertEqual(FT.measure, "money")
    assertEqual(FT.measureBtn.text:GetText(), "Measure: Money")
    FT:CycleMeasure(); FT:CycleMeasure()
    assertEqual(FT.measure, "ah", "Money, Vendor, then AH")
    FT:CycleMeasure()
    local v = B:CaptureView()
    assertEqual(v.farmMeasure, "money")
    assertEqual(v.sortKey, "date"); assertEqual(v.sortAsc, false)
    FT._applyView({ sortKey = "total", sortAsc = true, farmMeasure = "vendor" })
    assertEqual(FT.measure, "vendor"); assertEqual(FT.sortKey, "total"); assertTrue(FT.sortAsc)
    FT._applyView({ sortKey = "quality", farmMeasure = "bogus" })
    assertEqual(FT.sortKey, "date", "a column the tab lacks reads as Date")
    assertFalse(FT.sortAsc)
    assertEqual(FT.measure, nil, "an unknown measure reads as the headline value")
    assertEqual(FT.Measure(), NS.db.profile.settings.farm.headlineValue or "ah")
  end)
end)

-- ── the routes, the menu and the popups ──────────────────────────────────────────────────────

test("FarmTab: click opens the summary, double-click Details, right-click the menu", function()
  world(function()
    local ref = put(F:LiveStore(), finished(me(), 1, T0 - 86400, "Isle of Dorn", 3600, 100))
    local e = FT.Rows(F:LiveStore(), "live", {}, "ah")[1]
    local got = {}
    with(FD, { OpenSummary = function(_, r) got[#got + 1] = "summary:" .. r.id end,
               Open = function(_, r) got[#got + 1] = "details:" .. r.id end }, function()
      with(NS.BrowserTable, { ShowMenu = function(_, anchor, items)
        got[#got + 1] = "menu:" .. #items .. ":" .. tostring(anchor)
      end }, function()
        assertEqual(FT.RowClick(e, "LeftButton", "row"), "summary")
        FT.RowDoubleClick(e)
        assertEqual(FT.RowClick(e, "RightButton", "row"), "menu")
      end)
    end)
    assertEqual(table.concat(got, ","), "summary:1,details:1,menu:2:row")
    assertEqual(e.ref.store, ref.store); assertEqual(e.ref.char, ref.char)
    local items = FT.RowActions(e)
    assertEqual(items[1].label, "Rename\226\128\166")
    assertTrue(items[2].label:find("Delete\226\128\166", 1, true) ~= nil)
  end)
end)

test("FarmTab: Rename asks with the name, renames, and an empty answer restores the zone", function()
  world(function()
    local ref = put(F:LiveStore(), finished(me(), 1, T0 - 86400, "Isle of Dorn", 3600, 100))
    local shown, sent = {}, {}
    with(M, { StaticPopup_Show = function(which, a, b, data) shown[#shown + 1] = { which, a, b, data } end }, function()
      assertTrue(FT.AskRename(ref))
    end)
    assertEqual(shown[1][1], "KA0S_LOOTHISTORY_FARM_RENAME"); assertEqual(shown[1][2], "Isle of Dorn")
    local d = M.StaticPopupDialogs["KA0S_LOOTHISTORY_FARM_RENAME"]
    assertTrue(d.hasEditBox); assertEqual(d.maxLetters, 48)
    local box = { text = "" }
    function box.GetText(b) return b.text end
    local dialog = { EditBox = box }
    local ev = NS.NewBusTarget()
    ev:RegisterMessage(NS.MSG.FARM_CHANGED, function(_, reason) sent[#sent + 1] = reason end)
    box.text = "  Dorn | loop  "
    d.OnAccept(dialog, shown[1][4])
    assertEqual(FD.Resolve(ref).name, "Dorn / loop", "trimmed, and a | made /")
    box.text = ""
    d.OnAccept(dialog, shown[1][4])
    assertEqual(FD.Resolve(ref).name, "Isle of Dorn", "an empty answer restores the zone")
    box.text = string.rep("x", 60)
    d.OnAccept(dialog, shown[1][4])
    assertEqual(#FD.Resolve(ref).name, 48, "cut to 48")
    ev:UnregisterAllMessages()
    assertEqual(table.concat(sent, ","), "rename,rename,rename")
  end)
end)

test("FarmTab: Delete confirms with the name and date, and deletes", function()
  world(function()
    local ref = put(F:LiveStore(), finished(me(), 1, T0 - 86400, "Isle of Dorn", 3600, 100))
    local shown = {}
    with(M, { StaticPopup_Show = function(which, a, b, data) shown[#shown + 1] = { which, a, b, data } end }, function()
      assertTrue(FT.AskDelete(ref))
    end)
    assertEqual(shown[1][1], "KA0S_LOOTHISTORY_FARM_DELETE")
    assertEqual(shown[1][2] .. "|" .. shown[1][3], "Isle of Dorn|26 Nov")
    local d = M.StaticPopupDialogs["KA0S_LOOTHISTORY_FARM_DELETE"]
    assertEqual(d.text:format("Isle of Dorn", "26 Nov"),
      "Delete the farm session \"Isle of Dorn\" from 26 Nov? This cannot be undone.")
    d.OnAccept(nil, shown[1][4])
    assertEqual(FD.Resolve(ref), nil, "gone")
    assertEqual(#F:LiveStore()[me()].sessions, 0)
  end)
end)

test("FarmTab: a test-mode sample row refuses Rename and Delete with the line", function()
  world(function()
    NS.State.testFarm = NS.FarmTestData.Build(T0)
    local e = FT.Rows(F:ActiveStore(), FT.StoreKind(), {}, "ah")[1]
    assertEqual(e.ref.store, "test")
    local shown = 0
    local lines = chat(function()
      with(M, { StaticPopup_Show = function() shown = shown + 1 end }, function()
        assertFalse(FT.AskRename(e.ref))
        assertFalse(FT.AskDelete(e.ref))
        assertFalse(F:Rename(e.ref, "x"))
        assertFalse(F:Delete(e.ref))
      end)
    end)
    assertEqual(shown, 0, "no popup")
    assertEqual(lines[1], "test mode shows sample sessions; nothing to rename or delete.")
    assertEqual(#lines, 4)
    assertEqual(#NS.State.testFarm[e.ref.char].sessions > 0, true, "the sample is never written")
  end)
end)

test("FarmTab: a simulation's row edits the simulation's store; a live reference is refused there", function()
  world(function()
    local live = put(F:LiveStore(), finished(me(), 1, T0 - 86400, "Isle of Dorn", 3600, 100))
    NS.SimStores.farm = {}
    local s = finished(me(), 1, T0 - 3600, "Ringing Deeps", 1800, 50)
    put(NS.SimStores.farm, s)
    assertEqual(FT.StoreKind(), "sim")
    local e = FT.Rows(F:ActiveStore(), FT.StoreKind(), {}, "ah")[1]
    assertEqual(e.ref.store, "sim")
    assertTrue(F:Rename(e.ref, "Sim run"))
    assertEqual(s.name, "Sim run")
    assertFalse(F:Delete(live), "a live reference while the sim store takes the writes")
    assertTrue(F:Delete(e.ref))
    assertEqual(#NS.SimStores.farm[me()].sessions, 0)
    assertEqual(#F:LiveStore()[me()].sessions, 1, "the saved store is untouched")
  end)
end)

test("FarmTab: SessionName trims, cuts on a character boundary and falls back", function()
  assertEqual(FM.SessionName("  a  ", "Z"), "a")
  assertEqual(FM.SessionName("   ", "Zone"), "Zone")
  assertEqual(FM.SessionName(nil, nil), "")
  local s = string.rep("a", 47) .. "\195\169"   -- 49 bytes, the last character two of them
  assertEqual(FM.SessionName(s, "Z"), string.rep("a", 47), "the two-byte character is not split")
end)

-- ── test mode ────────────────────────────────────────────────────────────────────────────────

test("FarmTab: TD.Publish publishes the farm sample and clears it, and says so on the bus", function()
  world(function()
    local sent = {}
    local ev = NS.NewBusTarget()
    ev:RegisterMessage(NS.MSG.FARM_CHANGED, function(_, reason) sent[#sent + 1] = reason end)
    NS.TestData.Publish({})
    assertTrue(NS.State.testFarm ~= nil, "published")
    assertTrue(F:ActiveStore() == NS.State.testFarm, "the lists read it")
    assertTrue(F:Store() ~= NS.State.testFarm, "no writer does")
    NS.TestData.Publish(nil)
    assertEqual(NS.State.testFarm, nil, "cleared")
    ev:UnregisterAllMessages()
    assertEqual(table.concat(sent, ","), "store,store")
  end)
end)

-- ── the sessions list ────────────────────────────────────────────────────────────────────────

test("FarmPanel sessions: a companion with close alone, docked, and one tooltip group with the panel", function()
  -- red under: the list built with settings (not a companion), or no SetGroup over the pair.
  world(function()
    seed()
    FP:Show()
    FP:ToggleSessions()
    local f = FP:SessionsWindow()
    assertTrue(f ~= nil and f:IsShown(), "the Sessions button opens it")
    local hb = f.headerButtons
    assertTrue(hb ~= nil, "the marks are W.HeaderButtons'")
    assertEqual(table.concat(hb.order, ","), "close")
    assertTrue(hb.companion == true, "a companion")
    assertEqual(f.title:GetText(), "Farm sessions")
    local Tip = M.LibStub("LibKa0s-Tooltip-1.0", true)
    if Tip then
      local frames, main = Tip.GroupOf(f)
      assertTrue(main == FP:Window(), "the panel is the group's main frame")
      assertEqual(#frames, 2, "the pair, while the list shows")
    end
    FP:ToggleSessions()
    assertFalse(f:IsShown(), "the button closes it again")
    FP:ShowSessions()
    FP:Hide()
    assertFalse(f:IsShown(), "it closes with the panel")
  end)
end)

test("FarmPanel sessions: this character's saved sessions, newest first, at the headline value", function()
  world(function()
    seed()
    FP:Show(); FP:ShowSessions()
    local list = FP:SessionsWindow().list
    local vis = list:Visible()
    assertEqual(#vis, 2, "this character's only")
    assertEqual(rowText(vis[1]), "26 Nov|Ringing Deeps|0:30|400g|800g|*")
    assertEqual(rowText(vis[2]), "24 Nov|Isle of Dorn|1:00|500g|500g|*")
    local labels = {}
    for i, col in ipairs(list.spec.columns) do labels[i] = col.label end
    assertEqual(table.concat(labels, ","), "Date,Zone,Active,Total,/h,")
    -- A rename repaints the open list (coalesced).
    F:Rename({ store = "live", char = me(), id = 2 }, "Deep run")
    M.__fireTimers()
    assertEqual(list:Visible()[1].s.name, "Deep run")
  end)
end)

test("FarmPanel sessions: rows route like the tab's", function()
  world(function()
    seed()
    FP:Show(); FP:ShowSessions()
    local list = FP:SessionsWindow().list
    local got = {}
    with(FD, { OpenSummary = function(_, r) got[#got + 1] = "summary:" .. r.id end,
               Open = function(_, r) got[#got + 1] = "details:" .. r.id end }, function()
      local row = list.pool.active[1]
      row:__fire("OnClick", "LeftButton")
      row:__fire("OnDoubleClick", "LeftButton")
    end)
    assertEqual(table.concat(got, ","), "summary:2,details:2")
  end)
end)
