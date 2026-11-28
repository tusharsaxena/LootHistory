-- tests/test_toast_blizz.lua — modules/ToastBlizz.lua (toast spec
-- docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §10.2, §13.2): Blizzard's loot and money
-- alert toasts hidden while the switch is on and a feed is enabled, and restored exactly (the events
-- AlertFrame had, in the order they were taken) when the switch goes off, the gain feed goes off or
-- the addon stands down. Runs after tests/test_toast_feed.lua with the addon brought up; every case
-- puts the switch, the feeds and AlertFrame back.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local C = NS.Constants
local TB = NS.ToastBlizz

--- A recording AlertFrame that has registered `names`.
local function alertFrame(names)
  local reg, log = {}, {}
  for _, n in ipairs(names) do reg[n] = true end
  return {
    reg = reg, log = log,
    IsEventRegistered = function(_, e) return reg[e] == true end,
    UnregisterEvent = function(_, e) reg[e] = nil; log[#log + 1] = "-" .. e end,
    RegisterEvent = function(_, e) reg[e] = true; log[#log + 1] = "+" .. e end,
  }
end

--- Run `fn(af)` with AlertFrame stood in by `af`, the switch at `hide`, and everything put back.
local function withAlerts(af, hide, fn)
  local s = NS.db.profile.settings.toasts
  local savedAF, savedHide = rawget(M, "AlertFrame"), s.hideAlerts
  rawset(M, "AlertFrame", af)
  TB.Apply()                    -- anything suppressed before the case is restored onto the stand-in
  for i = #af.log, 1, -1 do af.log[i] = nil end
  s.hideAlerts = hide
  local ok, err = pcall(fn, af)
  s.hideAlerts = savedHide
  TB.Apply()
  rawset(M, "AlertFrame", savedAF)
  if not ok then error(err, 0) end
end

test("ToastBlizz: the switch on hides exactly the alert events AlertFrame has, and off restores them in order", function()
  local af = alertFrame({ "SHOW_LOOT_TOAST", "SHOW_LOOT_TOAST_LEGENDARY_LOOTED", "OTHER_EVENT" })
  withAlerts(af, true, function()
    assertTrue(NS.GainFeed.on, "the Main feed is on by default, so the gain feed is")
    assertEqual(TB.Apply(), 2, "two of the three named events were registered")
    assertEqual(table.concat(af.log, ","), "-SHOW_LOOT_TOAST,-SHOW_LOOT_TOAST_LEGENDARY_LOOTED")
    assertTrue(af.reg.OTHER_EVENT, "an event the list does not name is never touched")
    assertEqual(TB.Apply(), 2, "a second Apply suppresses nothing again")
    assertEqual(#af.log, 2)
    NS.db.profile.settings.toasts.hideAlerts = false
    assertEqual(TB.Apply(), 0)
    assertEqual(table.concat(af.log, ","),
      "-SHOW_LOOT_TOAST,-SHOW_LOOT_TOAST_LEGENDARY_LOOTED,+SHOW_LOOT_TOAST,+SHOW_LOOT_TOAST_LEGENDARY_LOOTED")
    assertTrue(af.reg.SHOW_LOOT_TOAST and af.reg.SHOW_LOOT_TOAST_LEGENDARY_LOOTED)
    assertFalse(af.reg.SHOW_LOOT_TOAST_UPGRADE == true, "an event AlertFrame never had is not added")
  end)
end)

test("ToastBlizz: off by default", function()
  assertEqual(NS.defaults.profile.settings.toasts.hideAlerts, false)
  local row = NS.Schema:FindRow("settings.toasts.hideAlerts")
  assertTrue(row ~= nil and row.default == false and row.feed == nil, "a page-wide row, off by default")
end)

test("ToastBlizz: the switch written through the Schema seam applies at once", function()
  local af = alertFrame(C.BLIZZ_ALERT_EVENTS)
  withAlerts(af, false, function()
    assertTrue(NS.Schema:Set("settings.toasts.hideAlerts", true))
    assertEqual(#TB._suppressed, #C.BLIZZ_ALERT_EVENTS, "the write's SETTINGS_CHANGED reached Recompute -> Apply")
    assertTrue(NS.Schema:Set("settings.toasts.hideAlerts", false))
    assertEqual(#TB._suppressed, 0)
    for _, e in ipairs(C.BLIZZ_ALERT_EVENTS) do assertTrue(af.reg[e], e .. " restored") end
  end)
end)

test("ToastBlizz: the gain feed off (no feed enabled) restores the alerts", function()
  local af = alertFrame(C.BLIZZ_ALERT_EVENTS)
  local feeds = NS.db.profile.settings.toasts.feeds
  local saved = {}
  for _, fid in ipairs(C.TOAST_FEEDS) do saved[fid] = feeds[fid].enabled end
  withAlerts(af, true, function()
    NS.GainFeed:Recompute()
    assertEqual(#TB._suppressed, 3)
    for _, fid in ipairs(C.TOAST_FEEDS) do feeds[fid].enabled = false end
    NS.GainFeed:Recompute()
    assertFalse(NS.GainFeed.on)
    assertEqual(#TB._suppressed, 0, "nothing toasts, so nothing of Blizzard's is hidden")
    for _, e in ipairs(C.BLIZZ_ALERT_EVENTS) do assertTrue(af.reg[e], e .. " restored") end
    for fid, v in pairs(saved) do feeds[fid].enabled = v end
    NS.GainFeed:Recompute()
    assertEqual(#TB._suppressed, 3, "a feed back on hides them again")
  end)
  for fid, v in pairs(saved) do feeds[fid].enabled = v end
  NS.GainFeed:Recompute()
end)

test("ToastBlizz: the addon stood down restores the alerts, and stood up hides them again", function()
  local af = alertFrame(C.BLIZZ_ALERT_EVENTS)
  withAlerts(af, true, function()
    TB.Apply()
    assertEqual(#TB._suppressed, 3)
    NS.Schema:Set("settings.enabled", false)
    assertEqual(#TB._suppressed, 0, "the stand-down step restored them")
    for _, e in ipairs(C.BLIZZ_ALERT_EVENTS) do assertTrue(af.reg[e], e .. " is the client's again") end
    NS.Schema:Set("settings.enabled", true)
    assertEqual(#TB._suppressed, 3, "the stand-up hides them again")
  end)
  if NS.Schema:Get("settings.enabled") ~= true then NS.Schema:Set("settings.enabled", true) end
end)

test("ToastBlizz: no AlertFrame suppresses nothing and raises nothing", function()
  local s = NS.db.profile.settings.toasts
  local savedAF, savedHide = rawget(M, "AlertFrame"), s.hideAlerts
  TB.Apply()
  rawset(M, "AlertFrame", nil)
  s.hideAlerts = true
  local ok, n = pcall(TB.Apply)
  s.hideAlerts = savedHide
  local ok2 = pcall(TB.Apply)
  rawset(M, "AlertFrame", savedAF)
  assertTrue(ok and ok2, "a client without AlertFrame raises nothing")
  assertEqual(n, 0)
end)

test("ToastBlizz: the alert event list is the three loot toasts AlertFrameMixin registers", function()
  -- Cited per client in docs/ARCHITECTURE.md Taint notes (events-frames-taint-§9).
  assertEqual(table.concat(C.BLIZZ_ALERT_EVENTS, ","),
    "SHOW_LOOT_TOAST,SHOW_LOOT_TOAST_UPGRADE,SHOW_LOOT_TOAST_LEGENDARY_LOOTED")
  local doc = T.Loader.readFile("docs/ARCHITECTURE.md")
  for _, e in ipairs(C.BLIZZ_ALERT_EVENTS) do
    assertTrue(doc:find(e, 1, true) ~= nil, "docs/ARCHITECTURE.md cites " .. e)
  end
  assertTrue(doc:find("AlertFrames.xml", 1, true) ~= nil, "and where AlertFrame is declared")
end)
