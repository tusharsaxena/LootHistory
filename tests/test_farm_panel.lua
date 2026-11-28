-- tests/test_farm_panel.lua — the farm session's companion panel and its list widget (#39, farm spec
-- docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §7.1, §13; mockups #39): the header marks,
-- minimize, the four views and their numbers against the mockup's values, the activity lines, the
-- costs line with ledger capture off, visibility (F9), the lock mark, the sim strip and badge, the
-- 1 Hz OnUpdate, the stand-down, the bare verb and the Start show; then modules/FarmList.lua.
--
-- After tests/test_farm.lua, with the whole addon brought up. Every case runs on a scratch
-- db.global.farm with time() on a test clock, closes what it opened and hides the panel.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local F, FP, FM, FL = NS.Farm, NS.FarmPanel, NS.FarmModel, NS.FarmList
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

--- `fs` written over the farm profile settings for the call, then put back.
local function withFarm(patch, fn)
  local farm = NS.db.profile.settings.farm
  local saved = {}
  for k, v in pairs(patch) do saved[k] = { v = farm[k] }; farm[k] = v end
  local ok, err = pcall(fn)
  for k, s in pairs(saved) do farm[k] = s.v end
  if not ok then error(err, 0) end
end

--- Run `body()` on a scratch farm store, the clock at T0, the panel expanded and hidden at the end.
local function world(body)
  local g, p = NS.db.global, NS.db.profile.settings.farm
  local saved = { g.farm, p.panel }
  g.farm, p.panel = {}, {}
  clock.t = T0
  local ok, err
  with(M, { time = function() return clock.t end }, function()
    chat(function()
      ok, err = pcall(body)
      NS.SimStores.farm = nil
      if F:Active() then F:Finish("manual", clock.t) end
      F:Reconcile()
      FP:Hide()
    end)
  end)
  g.farm, p.panel = saved[1], saved[2]
  if not ok then error(err, 0) end
end

--- A session opened and shaped like the mockup's: 00:42:17 active, running, in Isle of Dorn.
local function mockSession()
  local s = F:Start()
  s.zone, s.activeSec, s.runningSince = "Isle of Dorn", 2537, clock.t
  return s
end

-- The mockup's sub-totals (mockups.html, "Companion panel, running").
local MOCK_TOTALS = { money = 1524000, vendor = 381200, ah = 6110500, costs = 142000 }

local function withTotals(t, fn) with(F, { Totals = function() return t end }, fn) end

local function win() return FP:Window() end

local function texts(fsList)
  local out = {}
  for i, fs in ipairs(fsList) do out[i] = fs:GetText() or "" end
  return table.concat(out, "|")
end

-- ── the header ───────────────────────────────────────────────────────────────────────────────

test("FarmPanel: the header reads minimize · lock · settings · close, and it is not a companion", function()
  -- red under: the panel built as a companion (close alone), or the extras in the wrong order.
  world(function()
    FP:Show()
    local f = win()
    local hb = f.headerButtons
    assertTrue(hb ~= nil, "the marks are W.HeaderButtons'")
    assertEqual(table.concat(hb.order, ","), "minimize,lock,settings,close")
    assertEqual(hb.companion, nil, "a primary window, not a companion")
    assertTrue(f.settingsButton ~= nil, "the settings mark")
    assertTrue(f.lockButton ~= nil and f.lockButton == hb.extras.lock, "the lock extra")
    assertTrue(f.minimizeButton ~= nil and f.minimizeButton == hb.extras.minimize, "the minimize extra")
    assertEqual(f.title:GetText(), "Farm session")
  end)
end)

test("FarmPanel: minimize swaps the mark's art and tip, persists, and a title double-click flips it", function()
  world(function()
    mockSession()
    local f = win()
    local mark, path = f.minimizeButton, nil
    rawset(mark.icon, "SetTexture", function(_, p) path = p end)
    assertEqual(mark.__tip, "Minimize the panel")
    FP:ToggleMinimized()
    assertEqual(NS.db.profile.settings.farm.panel.minimized, true, "the state persists in the profile")
    assertEqual(path, NS.Icon("add")); assertEqual(mark.__tip, "Expand the panel")
    assertEqual(f.view, "min")
    FP:ToggleMinimized()
    assertEqual(NS.db.profile.settings.farm.panel.minimized, nil)
    assertEqual(path, NS.Icon("minimise")); assertEqual(mark.__tip, "Minimize the panel")
    -- Two presses within the window are one double-click; two far apart are not.
    M.__now = 100
    f.titleBar:__fire("OnMouseDown", "LeftButton")
    M.__now = 100.2
    f.titleBar:__fire("OnMouseDown", "LeftButton")
    assertEqual(f.view, "min", "a double-click on the title minimizes")
    M.__now = 101
    f.titleBar:__fire("OnMouseDown", "LeftButton")
    M.__now = 103
    f.titleBar:__fire("OnMouseDown", "LeftButton")
    assertEqual(f.view, "min", "two slow presses change nothing")
    rawset(mark.icon, "SetTexture", nil)
    M.__now = 0
  end)
end)

-- ── the full view against the mockup ─────────────────────────────────────────────────────────

test("FarmPanel: the running view draws the mockup's numbers (gross, AH value)", function()
  world(function()
    mockSession()
    withTotals(MOCK_TOTALS, function()
      FP:Refresh()
      local f = win()
      assertEqual(f.view, "full")
      assertEqual(f.zone:GetText(), "Isle of Dorn")
      assertTrue(f.chip:GetText():find("Running", 1, true) ~= nil, "the chip reads Running")
      assertTrue(f.chip:GetText():find(NS.Icon("media-play"), 1, true) ~= nil, "with the media-play mark")
      assertEqual(f.value:GetText(), "763g 45s")
      assertEqual(f.rate:GetText(), "1,083g/h")
      assertEqual(f.sub:GetText(), "Gross, AH value \194\183 net 749g 25s \194\183 1,063g/h")
      local kv = {}
      for i, p in ipairs(f.kv) do kv[i] = p.k:GetText() .. "=" .. p.v:GetText() end
      assertEqual(table.concat(kv, "|"), "Elapsed=00:42:17|Money looted=152g 40s|Items, vendor value=38g 12s"
        .. "|Items, AH value=611g 05s|Costs=-14g 20s")
      assertEqual(texts(f.grid[1]), "|Money|Vendor|AH")
      assertEqual(texts(f.grid[2]), "Gross|216g|270g|1,083g")
      assertEqual(texts(f.grid[3]), "Net|196g|250g|1,063g")
      assertEqual(table.concat(f.shownButtons, ","), "pause,finish,details", "Sessions waits for its list (M4.4)")
    end)
  end)
end)

test("FarmPanel: the headline follows headlineValue and headlineBasis", function()
  world(function()
    mockSession()
    withTotals(MOCK_TOTALS, function()
      withFarm({ headlineBasis = "net", headlineValue = "ah" }, function()
        FP:Refresh()
        assertEqual(win().value:GetText(), "749g 25s")
        assertEqual(win().rate:GetText(), "1,063g/h")
        assertEqual(win().sub:GetText(), "Net, AH value \194\183 gross 763g 45s \194\183 1,083g/h")
      end)
      withFarm({ headlineBasis = "gross", headlineValue = "money" }, function()
        FP:Refresh()
        assertEqual(win().value:GetText(), "152g 40s")
        assertEqual(win().rate:GetText(), "216g/h")
      end)
      withFarm({ headlineBasis = "gross", headlineValue = "vendor" }, function()
        FP:Refresh()
        assertEqual(win().value:GetText(), "190g 52s")
        assertTrue(win().sub:GetText():find("^Gross, Vendor value \194\183") ~= nil, win().sub:GetText())
      end)
    end)
  end)
end)

test("FarmPanel: a rate under a minute reads the dash", function()
  world(function()
    local s = mockSession()
    s.activeSec = 30
    withTotals(MOCK_TOTALS, function()
      FP:Refresh()
      assertEqual(win().rate:GetText(), "\226\128\148/h")
    end)
  end)
end)

test("FarmPanel: Costs read n/a with ledger capture off", function()
  world(function()
    mockSession()
    withTotals(MOCK_TOTALS, function()
      local s = NS.db.profile.settings
      for _, key in ipairs({ "trackLedger", "recordGold" }) do
        local before = s[key]
        s[key] = false
        local ok, err = pcall(function()
          FP:Refresh()
          local v = win().kv[5].v
          assertEqual(v:GetText(), "n/a (needs ledger capture)", key .. " off")
          local r, g, b = v:GetTextColor()
          local er, eg, eb = NS.SkinColor("text.disabled")
          assertEqual(("%.2f %.2f %.2f"):format(r, g, b), ("%.2f %.2f %.2f"):format(er, eg, eb))
        end)
        s[key] = before
        if not ok then error(err, 0) end
      end
    end)
  end)
end)

-- ── activity ─────────────────────────────────────────────────────────────────────────────────

test("FarmPanel: the activity lines draw in §6 order, and hideZero drops the zero lines", function()
  world(function()
    local s = mockSession()
    local a = s.activity
    a.mobs, a.items, a.nodes, a.quests, a.questRewards, a.containers, a.xp = 58, 214, 41, 3, 4, 6, 18400
    a.quality[4], a.quality[2] = 1, 50
    a.rep[2590] = { name = "Council of Dornogal", delta = 1240 }
    FP:Refresh()
    local labels = {}
    for i, c in ipairs(win().actCells) do labels[i] = c.k:GetText() .. "=" .. c.v:GetText() end
    local want = "Mobs looted=58|Items looted=214|Nodes gathered=41|Fish caught=0|Quests turned in=3"
      .. "|Quest rewards=4|Containers opened=6|Epic+ drops=1|Reputation=+1,240|Experience=+18,400|Skill-ups=0"
    if NS.Constants.FEATURE.appearances then want = want .. "|New appearances=0" end
    assertEqual(table.concat(labels, "|"), want, "currencies and deaths are off by default")
    withFarm({ hideZero = true }, function()
      FP:Refresh()
      local keys = {}
      for i, c in ipairs(win().actCells) do keys[i] = c.key end
      assertEqual(table.concat(keys, ","), "mobs,items,nodes,quests,questRewards,containers,quality,rep,xp")
    end)
  end)
end)

-- ── the other views ──────────────────────────────────────────────────────────────────────────

test("FarmPanel: the paused view dims the headline and hints by the pause's reason", function()
  world(function()
    local s = mockSession()
    withTotals(MOCK_TOTALS, function()
      FM.Pause(s, "idle", clock.t)
      FP:Refresh()
      local f = win()
      assertEqual(f.view, "paused")
      assertTrue(f.chip:GetText():find("Paused: idle 5 min", 1, true) ~= nil, f.chip:GetText())
      assertEqual(f.note:GetText(), "The clock is stopped. Your next gain or Resume starts it again.")
      assertEqual(table.concat(f.shownButtons, ","), "resume,finish")
      assertFalse(f.sub:IsShown(), "no basis line while paused")
      assertFalse(f.kv[1].k:IsShown(), "no grid while paused")
      s.pauseReason = "manual"
      FP:Refresh()
      assertEqual(f.note:GetText(), "The clock is stopped. Resume starts it again.")
      assertTrue(f.chip:GetText():find("Paused: manual", 1, true) ~= nil)
      s.pauseReason = "standDown"
      assertEqual(select(1, FP.ChipFor(s)):match("Paused: (.*)$"), "addon disabled")
      s.pauseReason = "afk"
      assertEqual(select(1, FP.ChipFor(s)):match("Paused: (.*)$"), "AFK")
    end)
  end)
end)

test("FarmPanel: minimized shows the headline, the elapsed line and Pause or Resume with Finish", function()
  world(function()
    local s = mockSession()
    withTotals(MOCK_TOTALS, function()
      FP:ToggleMinimized()
      local f = win()
      assertEqual(f.view, "min")
      assertEqual(f.value:GetText(), "763g 45s")
      assertEqual(f.note:GetText(), "00:42:17 elapsed")
      assertEqual(table.concat(f.shownButtons, ","), "pause,finish")
      assertFalse(f.kv[1].k:IsShown(), "no grid while minimized")
      FM.Pause(s, "manual", clock.t)
      FP:Refresh()
      assertEqual(table.concat(f.shownButtons, ","), "resume,finish")
    end)
  end)
end)

test("FarmPanel: with no session the panel says so and offers Start", function()
  world(function()
    FP:Show()
    local f = win()
    assertEqual(f.view, "none")
    assertEqual(f.note:GetText(), "No farm session running.")
    assertFalse(f.zone:IsShown())
    assertEqual(table.concat(f.shownButtons, ","), "start")
    f.buttons.start:__fire("OnClick", "LeftButton")
    assertTrue(F:Active() ~= nil, "Start opened a session")
    FP:Refresh()
    assertEqual(f.view, "full")
  end)
end)

test("FarmPanel: Details and Sessions appear once their windows exist", function()
  world(function()
    mockSession()
    local opened = 0
    with(NS, { FarmDetails = { Open = function() opened = opened + 1 end } }, function()
      with(FP, { ToggleSessions = function() end }, function()
        FP:Refresh()
        assertEqual(table.concat(win().shownButtons, ","), "pause,finish,details,sessions")
        win().buttons.details:__fire("OnClick", "LeftButton")
        assertEqual(opened, 1, "Details opens the Details window")
      end)
    end)
  end)
end)

test("FarmPanel: the footer buttons run the verbs", function()
  world(function()
    mockSession()
    local f = win()
    f.buttons.pause:__fire("OnClick", "LeftButton")
    assertEqual(F:Active().pauseReason, "manual")
    f.buttons.resume:__fire("OnClick", "LeftButton")
    assertTrue(F:Active().runningSince ~= nil)
    f.buttons.finish:__fire("OnClick", "LeftButton")
    assertEqual(F:Active(), nil, "Finish closed the session")
  end)
end)

-- ── show paths, visibility, the lock ─────────────────────────────────────────────────────────

test("FarmPanel: Start shows the panel when showPanelOnStart is on, and not when it is off", function()
  world(function()
    withFarm({ showPanelOnStart = false }, function() F:Start() end)
    assertFalse(FP:IsShown(), "off: Start leaves the panel down")
    F:Finish("manual", clock.t)
    F:Start()
    assertTrue(FP:IsShown(), "on: Start shows it")
  end)
end)

test("FarmPanel: the bare /lh farm toggles the panel", function()
  world(function()
    F:RunVerb("")
    assertTrue(FP:IsShown(), "the first bare verb shows it")
    F:RunVerb("  ")
    assertFalse(FP:IsShown(), "the second hides it")
  end)
end)

test("FarmPanel: visibility hides it at the combat edge and the next allowing edge shows it again (F9)", function()
  world(function()
    local s = NS.db.profile.settings
    local before = s.visibility
    s.visibility = "outOfCombat"
    local ok, err = pcall(function()
      FP:Show()
      assertTrue(FP:IsShown())
      FP:ApplyVisibility(true)
      assertFalse(FP:IsShown(), "hidden at the pull")
      FP:ApplyVisibility(false)
      assertTrue(FP:IsShown(), "back at the combat end")
      -- A panel the player closed is not brought back.
      FP:Hide()
      FP:ApplyVisibility(false)
      assertFalse(FP:IsShown(), "a closed panel stays closed")
      s.visibility = "never"
      local lines = chat(function() FP:Show() end)
      assertFalse(FP:IsShown())
      assertEqual(table.concat(lines), "the farm panel is hidden by the General visibility setting.")
      s.visibility = "always"
      NS.Browser:OnSettingsChanged()
      assertTrue(FP:IsShown(), "the refused show comes up once the setting allows it")
    end)
    s.visibility = before
    if not ok then error(err, 0) end
  end)
end)

test("FarmPanel: the lock mark repaints on SETTINGS_CHANGED through the Browser fan-out", function()
  world(function()
    local before = NS.db.profile.settings.locked
    FP:Show()
    local mark, path = win().lockButton, nil
    rawset(mark.icon, "SetTexture", function(_, p) path = p end)
    local ok, err = pcall(function()
      NS.Schema:Set("settings.locked", true)
      NS.Browser:OnSettingsChanged()
      assertEqual(path, NS.Icon("lock")); assertEqual(mark.__tip, "Unlock the window")
      NS.Schema:Set("settings.locked", false)
      NS.Browser:OnSettingsChanged()
      assertEqual(path, NS.Icon("unlock")); assertEqual(mark.__tip, "Lock the window")
    end)
    rawset(mark.icon, "SetTexture", nil)
    NS.Schema:Set("settings.locked", before)
    if not ok then error(err, 0) end
  end)
end)

test("FarmPanel: the title drag is refused while locked", function()
  world(function()
    FP:Show()
    local f, moved = win(), 0
    rawset(f, "StartMoving", function() moved = moved + 1 end)
    with(NS.Browser, { IsLocked = function() return true end }, function()
      f.titleBar:__fire("OnDragStart")
    end)
    assertEqual(moved, 0, "locked: no drag")
    f.titleBar:__fire("OnDragStart")
    assertEqual(moved, 1, "unlocked: the drag starts")
    rawset(f, "StartMoving", nil)
  end)
end)

-- ── the sim strip and badge ──────────────────────────────────────────────────────────────────

test("FarmPanel: a simulation shows its strip while expanded and the title badge while minimized", function()
  world(function()
    FP:Show()
    local f = win()
    assertTrue(f.simStrip ~= nil, "the panel builds a sim strip")
    assertFalse(f.simStrip:IsShown()); assertFalse(f.simBadge:IsShown())
    with(NS.Sim, { IsActive = function() return true end }, function()
      FP:UpdateStrip()
      assertTrue(f.simStrip:IsShown(), "expanded: the strip")
      assertFalse(f.simBadge:IsShown())
      FP:ToggleMinimized()
      assertFalse(f.simStrip:IsShown(), "minimized: no strip")
      assertTrue(f.simBadge:IsShown(), "minimized: the badge")
      assertEqual(f.simBadge:GetText(), "SIM")
      FP:ToggleMinimized()
    end)
    FP:UpdateStrip()
    assertFalse(f.simStrip:IsShown()); assertFalse(f.simBadge:IsShown())
  end)
end)

-- ── the ticker ───────────────────────────────────────────────────────────────────────────────

test("FarmPanel: the OnUpdate runs only while shown and running, at 1 Hz, and goes on hide", function()
  world(function()
    local s = mockSession()
    local f = win()
    local tick = f:GetScript("OnUpdate")
    assertTrue(tick ~= nil, "shown and running: armed")
    local painted = 0
    with(FP, { PaintNumbers = function() painted = painted + 1 end }, function()
      FP._acc = 0
      tick(f, 0.4); tick(f, 0.4)
      assertEqual(painted, 0, "under a second: no repaint")
      tick(f, 0.3)
      assertEqual(painted, 1, "the second's repaint")
    end)
    FM.Pause(s, "manual", clock.t)
    FP:Refresh()
    assertEqual(f:GetScript("OnUpdate"), nil, "paused: cleared")
    FM.Resume(s, clock.t)
    FP:Refresh()
    assertTrue(f:GetScript("OnUpdate") ~= nil)
    FP:Hide()
    assertEqual(f:GetScript("OnUpdate"), nil, "hidden: cleared")
  end)
end)

test("FarmPanel: the elapsed clock moves on the tick", function()
  world(function()
    mockSession()
    withTotals(MOCK_TOTALS, function()
      FP:Refresh()
      clock.t = clock.t + 3
      FP:PaintNumbers()
      assertEqual(win().kv[1].v:GetText(), "00:42:20")
    end)
  end)
end)

-- ── stand-down and the bus ───────────────────────────────────────────────────────────────────

test("FarmPanel: stood down, Show refuses silently; the Disable and Hide steps take it all down", function()
  world(function()
    mockSession()
    assertTrue(FP:IsShown())
    local lines
    with(NS, { IsStoodDown = function() return true end }, function()
      FP:Hide()
      lines = chat(function() FP:Show() end)
    end)
    assertFalse(FP:IsShown(), "no show while stood down")
    assertEqual(#lines, 0, "silent: the verb gate already spoke")
    local ev = FP.__ev
    assertTrue(ev ~= nil, "enabled with the addon")
    FP:Disable()
    assertEqual(FP.__ev, nil, "Disable drops the bus target")
    FP:Enable()
    assertTrue(FP.__ev ~= nil, "Enable brings it back")
  end)
end)

test("FarmPanel: the panel sits on WINDOW_PERSISTENT, toplevel and clamped", function()
  world(function()
    FP:Show()
    assertEqual(NS.Constants.LAYERS.STRATA.WINDOW_PERSISTENT, "MEDIUM")
    assertEqual(win():GetName() or win().__name, "LootHistoryFarmPanel")
  end)
end)

-- ── modules/FarmList.lua ─────────────────────────────────────────────────────────────────────

local COLS = {
  { key = "name", label = "Name", text = function(e) return e.name end },
  { key = "n", label = "N", width = 60, align = "RIGHT", text = function(e) return tostring(e.n) end,
    sort = function(e) return e.n end },
}

local function newList(spec)
  local host = M.CreateFrame("Frame", nil, M.UIParent)
  spec.columns = spec.columns or COLS
  return FL.New(host, spec)
end

local function names(list)
  local out = {}
  for i, e in ipairs(list:Visible()) do out[i] = e.name end
  return table.concat(out, ",")
end

test("FarmList: SetData sorts by the opening sort and binds the slice", function()
  local list = newList({ sortKey = "n", sortAsc = false })
  list:SetData({ { name = "a", n = 1 }, { name = "b", n = 3 }, { name = "c", n = 2 } })
  assertEqual(names(list), "b,c,a")
end)

test("FarmList: a header click sorts, a second flips the direction, ties keep the data's order", function()
  local sorts = {}
  local list = newList({ sortKey = "n", sortAsc = false,
    onSort = function(k, asc) sorts[#sorts + 1] = k .. ":" .. tostring(asc) end })
  list:SetData({ { name = "a", n = 2 }, { name = "b", n = 1 }, { name = "c", n = 2 } })
  assertEqual(names(list), "a,c,b", "desc, the tie in data order")
  list:HeaderClick("name")
  assertEqual(names(list), "c,b,a", "a new column starts at its default (descending)")
  list:HeaderClick("name")
  assertEqual(names(list), "a,b,c", "the same column again flips it")
  assertEqual(table.concat(sorts, ","), "name:false,name:true")
end)

test("FarmList: a fixed-order list ignores the header", function()
  local list = newList({ sortable = false })
  list:SetData({ { name = "z", n = 1 }, { name = "a", n = 2 } })
  list:HeaderClick("name")
  assertEqual(names(list), "z,a")
end)

test("FarmList: a 2000-row list binds only the visible slice onto pooled rows", function()
  local list = newList({ sortable = false })
  local data = {}
  for i = 1, 2000 do data[i] = { name = "r" .. i, n = i } end
  list:SetData(data)
  assertEqual(#list:Visible(), list:NumVisible(), "one screen of rows")
  assertTrue(list:NumVisible() < 50)
  local _, active = NS.Pool.Counts(list.pool)
  assertEqual(active, list:NumVisible(), "one pooled row per visible line")
  list:Bind()
  local free, active2 = NS.Pool.Counts(list.pool)
  assertEqual(active2, list:NumVisible())
  assertEqual(free, 0, "a rebind reuses the same rows")
end)

test("FarmList: the empty line, and the row click routes", function()
  local got = {}
  local list = newList({ empty = "Nothing yet.",
    onClick = function(e, button) got[#got + 1] = e.name .. ":" .. button end,
    onDoubleClick = function(e) got[#got + 1] = "dbl:" .. e.name end })
  list:SetData({})
  assertTrue(list.emptyText:IsShown()); assertEqual(list.emptyText:GetText(), "Nothing yet.")
  list:SetData({ { name = "a", n = 1 } })
  assertFalse(list.emptyText:IsShown())
  local row = list.pool.active[1]
  row:__fire("OnClick", "LeftButton")
  row:__fire("OnClick", "RightButton")
  row:__fire("OnDoubleClick", "LeftButton")
  assertEqual(table.concat(got, ","), "a:LeftButton,a:RightButton,dbl:a")
end)
