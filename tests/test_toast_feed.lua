-- tests/test_toast_feed.lua — modules/ToastFeed.lua (toast spec
-- docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §8, §13.2): the three feeds built through
-- the seam, the GAIN routing, the payload hand-back on a refused push, the click actions, the combat
-- rows, unlock and drag, the settings refresh, the stand-down and the library-absent stub path.
--
-- The feeds are LIVE LibKa0s-Feed-1.0 instances (the headless loader loads LibKa0s.xml). Their own
-- behavior (phases, geometry, the merge mechanics, the pin) is the library's suite's; these cases
-- assert only what the host decides and what it passes in. This slot runs after tests/test_dispatch.lua,
-- with the whole addon brought up; every case clears what it showed and puts back what it touched.
--
-- NO CASE PAINTS A ROW. The vendored Feed (v1.119.0, unreleased) sets a new row's text before its
-- fonts, which the client (and tests/wow_mock.lua) refuses with "Font not set", so every live feed
-- here is HELD: a push waits (merging there) and is read back through Get and Stats().waiting. The
-- unlock preview, which presents at once, is driven against a recording stand-in instead.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local C = NS.Constants
local Toasts = NS.Toasts
local function feed(fid) return Toasts:Feed(fid) end
local function feedRow(fid) return NS.db.profile.settings.toasts.feeds[fid] end

local function clearAll()
  for _, fid in ipairs(C.TOAST_FEEDS) do
    local f = feed(fid)
    if f then f:Clear(); f:SetClickThrough(false); f:Release() end
  end
  for k in pairs(NS.State.toastUnlocked) do NS.State.toastUnlocked[k] = nil end
end

local function holdAll()
  for _, fid in ipairs(C.TOAST_FEEDS) do feed(fid):Hold() end
end

--- Run `fn` with the feeds' stored settings deep-copied (and patched per feed by `over`), every feed
--- cleared and held before, cleared and released after, and the profile and the snapshot put back.
local function withFeeds(over, fn)
  local feeds = NS.db.profile.settings.toasts.feeds
  local saved = {}
  for _, fid in ipairs(C.TOAST_FEEDS) do
    saved[fid] = feeds[fid]
    feeds[fid] = NS.Util.DeepCopy(saved[fid])
    for k, v in pairs((over or {})[fid] or {}) do feeds[fid][k] = v end
  end
  Toasts:RefreshConfig()
  clearAll()
  holdAll()
  local ok, err = pcall(fn)
  clearAll()
  for fid, f in pairs(saved) do feeds[fid] = f end
  M.InCombatLockdown = function() return false end
  Toasts:RefreshConfig()
  if not ok then error(err, 0) end
end

local function gold(qty) return { kind = "GOLD", dir = "IN", qty = qty or 500 } end
local function item(id, qty, quality)
  return { kind = "ITEM", dir = "IN", id = id, qty = qty or 1, quality = quality or 1, name = "Item " .. id,
           link = "|cffffffff|Hitem:" .. id .. "::|h[Item " .. id .. "]|h|r" }
end

-- A stand-in instance on the stub's surface whose Push answers `res` (after `before(p)`), recording
-- each push.
local function fakeFeed(res, before)
  local f = { pushed = {} }
  for k, v in pairs(NS.FeedStub) do f[k] = v end
  f.Push = function(_, key, p) f.pushed[#f.pushed + 1] = { key, p }; if before then before(p) end; return res end
  return f
end

local function withFake(f, fn)
  local saved = Toasts._feeds.main
  Toasts._feeds.main = f
  local ok, err = pcall(fn)
  Toasts._feeds.main = saved
  if not ok then error(err, 0) end
end

-- ── the build (§8.2) ─────────────────────────────────────────────────────────────────────────

test("Toasts: the stand-up builds the three feeds through NS.NewFeed with the host's descriptor", function()
  local saved, savedNew = {}, NS.NewFeed
  for _, fid in ipairs(C.TOAST_FEEDS) do saved[fid] = Toasts._feeds[fid] end
  local seen = {}
  local ok, err = pcall(function()
    Toasts:Disable()
    for _, fid in ipairs(C.TOAST_FEEDS) do Toasts._feeds[fid] = nil end
    NS.NewFeed = function(d) seen[#seen + 1] = d; return savedNew(d) end
    Toasts:Enable()
    assertEqual(#seen, 3, "one NS.NewFeed per feed")
    for i, fid in ipairs(C.TOAST_FEEDS) do
      local d = seen[i]
      assertEqual(d.name, "LootHistoryToastFeed_" .. fid)
      assertEqual(d.owner, "LootHistory", "the seam stamps the skin owner, the folder name")
      for _, k in ipairs({ "content", "merge", "layout", "motion", "style", "onClick", "onMoved", "debug" }) do
        assertEqual(type(d[k]), "function", fid .. ": d." .. k)
      end
      assertTrue(d.merge == NS.ToastModel.Merge, "the merge reducer is the model's")
      assertEqual(d.strings.HANDLE, C.TOAST_FEED_LABEL[fid])
      assertEqual(type(d.strings.HANDLE_TIP), "string")
      assertEqual(d.onEnter, nil, "no item tooltip on hover (scope 1.2)")
      assertTrue(d.layout() == NS.ToastModel.LayoutFor(fid), "the layout getter is the model's, per feed")
      assertTrue(d.motion() == NS.ToastModel.MotionFor(fid), "and so is the motion getter")
      assertTrue(d.style() == NS.ToastModel.StyleFor(fid), "and the style getter")
    end
    -- The Feed's onClick and onMoved are closures over their feed id, handing the host everything.
    local savedClick, savedMoved, calls = Toasts._Click, Toasts._Moved, {}
    Toasts._Click = function(_, fid, p, button, key) calls[#calls + 1] = { fid, p, button, key } end
    Toasts._Moved = function(_, fid, x, y) calls[#calls + 1] = { fid, x, y } end
    local p = item(7)
    seen[3].onClick(p, "LeftButton", "i:7")
    seen[2].onMoved(10, -20)
    Toasts._Click, Toasts._Moved = savedClick, savedMoved
    assertEqual(calls[1][1], "extra"); assertTrue(calls[1][2] == p)
    assertEqual(calls[1][3], "LeftButton"); assertEqual(calls[1][4], "i:7")
    assertEqual(table.concat(calls[2], ","), "progress,10,-20")
    local spec = { lines = { {}, {}, {} } }
    assertEqual(seen[1].content(spec, gold(500), "g"), nil, "the content closure draws a known kind")
    assertEqual(spec.title, NS.Util.FormatMoney(500))
    Toasts:Disable(); Toasts:Enable()
    assertEqual(#seen, 3, "a second stand-up reuses the instances")
  end)
  NS.NewFeed = savedNew
  Toasts:Disable()
  for fid, f in pairs(saved) do Toasts._feeds[fid] = f end
  Toasts:Enable()
  if not ok then error(err, 0) end
end)

test("Toasts: an idle feed is asleep", function()
  withFeeds(nil, function()
    local s = feed("extra"):Stats()
    assertFalse(s.awake, "a feed at rest arms no clock")
    assertEqual(s.live, 0)
  end)
end)

-- ── the receiver (§8.3) ──────────────────────────────────────────────────────────────────────

test("Toasts: the receiver is not subscribed to GAIN yet (the Feed's first paint raises)", function()
  -- Pins the held-back half of M3.3 (modules/ToastFeed.lua, Toasts:Enable): it flips when the library
  -- sets a row's fonts before its text and the subscription lands.
  withFeeds(nil, function()
    NS.bus:SendMessage(NS.MSG.GAIN, gold(500))
    assertEqual(feed("main"):Get("g"), nil, "a bus GAIN reached a feed")
    assertEqual(feed("main"):Stats().waiting, 0)
  end)
end)

test("Toasts: a gain reaches only the feeds that accept it", function()
  withFeeds({ extra = { enabled = true, kinds = { item = true, money = false, currency = false, reputation = false,
                                                   appearance = false, xp = false, skill = false } } }, function()
    Toasts:OnGain(gold(500))
    assertTrue(feed("main"):Get("g") ~= nil, "the Main feed takes money")
    assertEqual(feed("extra"):Get("g"), nil, "the third feed takes items only")
    assertEqual(feed("progress"):Get("g"), nil, "the disabled Progress feed takes nothing")
    Toasts:OnGain(item(7))
    assertEqual(feed("main"):Stats().waiting, 2)
    assertTrue(feed("extra"):Get("i:7") ~= nil)
    assertEqual(feed("extra"):Stats().waiting, 1)
  end)
end)

test("Toasts: each feed keeps its own payload copy, and a repeat merges into it", function()
  withFeeds({ extra = { enabled = true } }, function()
    Toasts:OnGain(item(7, 2))
    local a, b = feed("main"):Get("i:7"), feed("extra"):Get("i:7")
    assertTrue(a ~= nil and b ~= nil and a ~= b, "two feeds, two payloads")
    Toasts:OnGain(item(7, 3))
    assertEqual(feed("main"):Get("i:7").qty, 5, "the repeat inside the merge window summed")
    assertEqual(feed("main"):Stats().waiting, 1, "and took no entry of its own")
    assertEqual(feed("extra"):Get("i:7").qty, 5)
  end)
end)

test("Toasts: the minimum quality and hidden sources are the feed's own", function()
  withFeeds({ main = { minQuality = 3, hideSources = { VENDOR = true } } }, function()
    Toasts:OnGain(item(7, 1, 2))
    assertEqual(feed("main"):Get("i:7"), nil, "below the feed's minimum quality")
    local g = item(8, 1, 4); g.source = "VENDOR"
    Toasts:OnGain(g)
    assertEqual(feed("main"):Get("i:8"), nil, "a hidden source")
    Toasts:OnGain(item(9, 1, 4))
    assertTrue(feed("main"):Get("i:9") ~= nil)
  end)
end)

test("Toasts: a refused push hands its payload back to the spare list", function()
  withFeeds(nil, function()
    local f = fakeFeed(false)
    withFake(f, function()
      local spares = #NS.ToastModel._spares
      Toasts:OnGain(gold(500))
      local p = f.pushed[1][2]
      assertEqual(f.pushed[1][1], "g")
      assertEqual(next(p), nil, "the refused payload is wiped")
      assertEqual(#NS.ToastModel._spares, spares + 1, "and back on the spare list")
      NS.ToastModel.NewPayload(gold(1))   -- take it back off, so the list is as it was
    end)
  end)
end)

test("Toasts: a merged push the content then skips is not handed back twice", function()
  withFeeds(nil, function()
    -- The Feed's merge path: the reducer frees `new` onto the spare list, then the merged payload's
    -- content skips it and Push answers false. The host must not free the same table again.
    local old = NS.ToastModel.NewPayload(gold(1))
    local f = fakeFeed(false, function(p) NS.ToastModel.Merge(old, p) end)
    withFake(f, function()
      local spares = #NS.ToastModel._spares
      Toasts:OnGain(gold(500))
      assertEqual(#NS.ToastModel._spares, spares + 1, "the reducer's free, and no second one")
      local a, b = NS.ToastModel.NewPayload(gold(1)), NS.ToastModel.NewPayload(gold(2))
      assertFalse(a == b, "no table sits on the spare list twice")
      NS.ToastModel.FreePayload(b)
    end)
    NS.ToastModel.FreePayload(old)
  end)
end)

-- ── clicks (§8.5) ────────────────────────────────────────────────────────────────────────────

local function withClickSpies(fn)
  local Compat, B = NS.Compat, NS.Browser
  local saved = { Compat.ModifierDown, Compat.ModifiedLinkClick, Compat.CurrencyLink, B.ShowGain }
  local calls = { link = {}, show = {} }
  local mods = {}
  Compat.ModifierDown = function(k) return mods[k] == true end
  Compat.ModifiedLinkClick = function(link) calls.link[#calls.link + 1] = link; return true end
  Compat.CurrencyLink = function(id) return "currency-link-" .. tostring(id) end
  B.ShowGain = function(_, p) calls.show[#calls.show + 1] = p; return true end
  local ok, err = pcall(fn, calls, mods)
  Compat.ModifierDown, Compat.ModifiedLinkClick, Compat.CurrencyLink, B.ShowGain = saved[1], saved[2], saved[3], saved[4]
  if not ok then error(err, 0) end
end

test("Toasts: shift- and ctrl-click hand the link to the client; a currency builds its link", function()
  withClickSpies(function(calls, mods)
    local p = item(7)
    mods.shift = true
    Toasts:_Click("main", p, "LeftButton", "i:7")
    assertEqual(calls.link[1], p.link)
    mods.shift, mods.ctrl = nil, true
    Toasts:_Click("main", { kind = "CURRENCY", id = 3008 }, "LeftButton", "c:3008")
    assertEqual(calls.link[2], "currency-link-3008")
    assertEqual(#calls.show, 0, "a modified click opens nothing")
  end)
end)

test("Toasts: a plain left click opens History on the gain; other buttons do nothing", function()
  withClickSpies(function(calls)
    local p = item(7)
    Toasts:_Click("main", p, "LeftButton", "i:7")
    assertTrue(calls.show[1] == p, "B:ShowGain gets the payload")
    Toasts:_Click("main", p, "MiddleButton", "i:7")
    Toasts:_Click("main", p, "RightButton", "i:7")
    assertEqual(#calls.show, 1)
    assertEqual(#calls.link, 0)
  end)
end)

-- ── combat (§8.5) ────────────────────────────────────────────────────────────────────────────

test("Toasts: the combat rows are registered while any feed is enabled", function()
  local function registered()
    local n = 0
    for _, row in ipairs(NS.EVENT_ROWS) do if row.owner == "Toasts" and row.registered then n = n + 1 end end
    return n
  end
  withFeeds(nil, function()
    assertEqual(registered(), 2, "the Main feed is on by default")
    for _, fid in ipairs(C.TOAST_FEEDS) do feedRow(fid).enabled = false end
    NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "toasts")
    assertEqual(registered(), 0, "no feed on: the rows come down")
    feedRow("progress").enabled = true
    NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "toasts")
    assertEqual(registered(), 2, "any feed on brings them back")
  end)
end)

test("Toasts: combat locks every feed, and click-through and the hold follow each feed's settings", function()
  withFeeds({ main = { clickThrough = true, showInCombat = false } }, function()
    clearAll()   -- no case-wide hold here: the hold under test is the combat row's own
    Toasts:OnCombatStart()
    local s = feed("main"):Stats()
    assertTrue(s.locked); assertTrue(s.clickThrough); assertTrue(s.held)
    local e = feed("extra"):Stats()
    assertFalse(e.clickThrough, "the third feed keeps its mouse"); assertFalse(e.held, "and shows in combat")
    Toasts:OnGain(gold(500))
    assertEqual(feed("main"):Stats().waiting, 1, "a held feed queues the gain")
    feed("main"):Clear()   -- so the release below presents nothing (no row is painted here)
    Toasts:OnCombatEnd()
    s = feed("main"):Stats()
    assertFalse(s.clickThrough); assertFalse(s.held)
  end)
end)

test("Toasts: the combat rows deliver to the handlers", function()
  local saved, seen = { Toasts.OnCombatStart, Toasts.OnCombatEnd }, {}
  Toasts.OnCombatStart = function() seen[#seen + 1] = "start" end
  Toasts.OnCombatEnd = function() seen[#seen + 1] = "end" end
  local ok, err = pcall(function()
    for _, row in ipairs(NS.EVENT_ROWS) do
      if row.owner == "Toasts" then NS.Deliver(row, row.event) end
    end
  end)
  Toasts.OnCombatStart, Toasts.OnCombatEnd = saved[1], saved[2]
  if not ok then error(err, 0) end
  assertEqual(table.concat(seen, ","), "start,end", "PLAYER_REGEN_DISABLED then _ENABLED, in row order")
end)

-- ── unlock and drag (§8.6) ───────────────────────────────────────────────────────────────────

-- A recording stand-in for the unlock cases: the live Preview presents at once, which paints.
local function lockFake(live, refuse)
  local f, log = {}, {}
  for k, v in pairs(NS.FeedStub) do f[k] = v end
  f.locked = true
  f.SetLocked = function(_, v)
    log[#log + 1] = "SetLocked:" .. tostring(v)
    if not v and refuse then return true end
    f.locked = v
    return v
  end
  f.Stats = function()
    local st = NS.FeedStub.Stats()
    st.live, st.locked = live or 0, f.locked
    return st
  end
  f.Preview = function(_, list) log[#log + 1] = "Preview:" .. #list; return #list end
  f.ClearPreview = function() log[#log + 1] = "ClearPreview" end
  return f, log
end

test("Toasts: an unlocked, empty feed previews its samples; a lock clears them", function()
  local f, log = lockFake(0)
  withFake(f, function()
    assertTrue(Toasts:SetUnlocked("main", true))
    assertTrue(NS.State.toastUnlocked.main)
    assertFalse(Toasts:SetUnlocked("main", false))
    assertEqual(NS.State.toastUnlocked.main, nil)
  end)
  assertEqual(table.concat(log, ","), "SetLocked:false,Preview:" .. #NS.ToastSample.ForFeed("main")
    .. ",SetLocked:true,ClearPreview", "one sample per kind the feed shows, cleared on the lock")
  assertEqual(#NS.ToastSample.ForFeed("main"), C.FEATURE.appearances and 7 or 6, "the Main feed shows every kind")
end)

test("Toasts: an unlock over live rows previews nothing", function()
  local f, log = lockFake(1)
  withFake(f, function() assertTrue(Toasts:SetUnlocked("main", true)) end)
  NS.State.toastUnlocked.main = nil
  assertEqual(table.concat(log, ","), "SetLocked:false")
end)

test("Toasts: a refused unlock reads as locked and previews nothing", function()
  local f, log = lockFake(0, true)
  withFake(f, function() assertFalse(Toasts:SetUnlocked("main", true)) end)
  assertEqual(NS.State.toastUnlocked.main, nil)
  assertEqual(table.concat(log, ","), "SetLocked:false,ClearPreview")
end)

test("Toasts: the live Feed refuses an unlock in combat", function()
  withFeeds(nil, function()
    M.InCombatLockdown = function() return true end
    assertFalse(Toasts:SetUnlocked("main", true), "the Feed refuses an unlock in combat")
    assertEqual(NS.State.toastUnlocked.main, nil)
    assertEqual(feed("main"):Stats().live, 0, "and a refused unlock previews nothing")
  end)
end)

test("Toasts: combat re-locks an unlocked feed and clears its preview", function()
  local f, log = lockFake(0)
  withFake(f, function()
    Toasts:SetUnlocked("main", true)
    Toasts:OnCombatStart()
    Toasts:OnCombatEnd()
  end)
  assertEqual(NS.State.toastUnlocked.main, nil, "the host re-locks at the pull")
  assertEqual(log[3], "SetLocked:true"); assertEqual(log[4], "ClearPreview")
end)

test("Toasts: a drag's nudge is written through the Schema seam as one batch", function()
  local saved, seen = NS.Schema.SetMany, nil
  NS.Schema.SetMany = function(_, entries) seen = entries; return true end
  local ok, err = pcall(function()
    assertTrue(Toasts:_Moved("progress", 40, -120))
    assertEqual(#seen, 2)
    assertEqual(seen[1].path, "settings.toasts.feeds.progress.x"); assertEqual(seen[1].value, 40)
    assertEqual(seen[2].path, "settings.toasts.feeds.progress.y"); assertEqual(seen[2].value, -120)
  end)
  NS.Schema.SetMany = saved
  if not ok then error(err, 0) end
end)

test("Toasts: NS.Schema:SetMany refuses a path no row owns and stores nothing", function()
  -- The Toasts rows arrive with the settings page (M3.6); until then the batch is refused whole.
  local before = feedRow("main").x
  local ok, _, _, index = NS.Schema:SetMany({ { path = "settings.toasts.feeds.main.x", value = 1 } })
  assertFalse(ok == true)
  assertEqual(index, 1)
  assertEqual(feedRow("main").x, before)
end)

-- ── settings and lifecycle (§10.1) ───────────────────────────────────────────────────────────

test("Toasts: SETTINGS_CHANGED (toasts, profile, enabled) re-snapshots and refreshes every feed", function()
  local counts, saved = {}, {}
  for _, fid in ipairs(C.TOAST_FEEDS) do
    local f = feed(fid)
    saved[fid] = f.Refresh
    f.Refresh = function(self) counts[fid] = (counts[fid] or 0) + 1; return saved[fid](self) end
  end
  local ok, err = pcall(function()
    for _, reason in ipairs({ "toasts", "profile", "enabled", "auction" }) do
      NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, reason)
    end
    for _, fid in ipairs(C.TOAST_FEEDS) do assertEqual(counts[fid], 3, fid .. ": one Refresh per reason it hears") end
  end)
  for fid, fn in pairs(saved) do feed(fid).Refresh = fn end
  if not ok then error(err, 0) end
end)

test("Toasts: a settings write reaches the next gain without a reload", function()
  withFeeds(nil, function()
    feedRow("main").kinds.money = false
    NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "toasts")
    Toasts:OnGain(gold(500))
    assertEqual(feed("main"):Get("g"), nil, "the snapshot was rebuilt")
  end)
end)

test("Toasts: Disable clears every feed and ends its hold; Enable reuses the instances", function()
  withFeeds(nil, function()
    Toasts:OnGain(gold(500))
    NS.State.toastUnlocked.extra = true
    local main = feed("main")
    Toasts:Disable()
    for _, fid in ipairs(C.TOAST_FEEDS) do
      local s = feed(fid):Stats()
      assertEqual(s.live + s.waiting + s.dropping, 0, fid)
      assertFalse(s.awake, fid .. ": the clock is disarmed")
      assertTrue(s.locked, fid .. ": locked again")
      assertFalse(s.held, fid .. ": no hold survives the stand-down")
    end
    assertEqual(next(NS.State.toastUnlocked), nil, "the unlock state is gone")
    Toasts:Enable()
    assertTrue(feed("main") == main)
  end)
end)

-- ── the degraded install (§8.1) ──────────────────────────────────────────────────────────────

test("Toasts: with NS.NewFeed answering the stub, every path runs and nothing raises", function()
  local saved, savedNew = {}, NS.NewFeed
  for _, fid in ipairs(C.TOAST_FEEDS) do saved[fid] = Toasts._feeds[fid] end
  local ok, err = pcall(function()
    Toasts:Disable()
    for _, fid in ipairs(C.TOAST_FEEDS) do Toasts._feeds[fid] = nil end
    NS.NewFeed = function() return NS.FeedStub end
    Toasts:Enable()
    assertTrue(feed("main") == NS.FeedStub)
    local spares = #NS.ToastModel._spares
    Toasts:OnGain(gold(500))
    assertEqual(#NS.ToastModel._spares, spares + 1, "the stub's refusal hands the payload back")
    NS.ToastModel.NewPayload(gold(1))
    assertFalse(Toasts:SetUnlocked("main", true), "the stub never unlocks")
    Toasts:OnCombatStart(); Toasts:OnCombatEnd()
    Toasts:RefreshConfig()
    Toasts:_Click("main", item(7), "RightButton", "i:7")
    Toasts:Disable()
  end)
  NS.NewFeed = savedNew
  for fid, f in pairs(saved) do Toasts._feeds[fid] = f end
  Toasts:Enable()
  if not ok then error(err, 0) end
end)

-- ── B:ShowGain (T12) ─────────────────────────────────────────────────────────────────────────

test("B:ShowGain opens History on the History tab with the gain's name in Search", function()
  local B = NS.Browser
  local seen = {}
  local saved = { B.Show, B.SelectTab, B.ActiveTab, B.SetSearchText }
  local tab = "Insights"
  B.Show = function() seen[#seen + 1] = "show" end
  B.SelectTab = function(_, name) seen[#seen + 1] = "tab:" .. name; tab = name end
  B.ActiveTab = function() return tab end
  B.SetSearchText = function(_, text) seen[#seen + 1] = "search:" .. text end
  local ok, err = pcall(function()
    assertTrue(B:ShowGain({ kind = "ITEM", name = "Apple" }))
    assertEqual(table.concat(seen, ","), "show,tab:History,search:Apple")
    seen = {}
    assertTrue(B:ShowGain({ kind = "GOLD", qty = 5 }))
    assertEqual(seen[3], "search:Gold", "money searches for Gold")
    seen = {}
    assertFalse(B:ShowGain({ kind = "XP", qty = 5 }))
    assertFalse(B:ShowGain({ kind = "SKILL", qty = 1 }))
    assertEqual(#seen, 0, "experience and skill-ups have no rows: nothing opens")
    tab = "Insights"
    B.SelectTab = function() end   -- the window refused (stood down or hidden): History never became active
    assertFalse(B:ShowGain({ kind = "ITEM", name = "Apple" }))
    assertFalse(seen[#seen] == "search:Apple", "no search is written into a tab that did not open")
  end)
  B.Show, B.SelectTab, B.ActiveTab, B.SetSearchText = saved[1], saved[2], saved[3], saved[4]
  if not ok then error(err, 0) end
end)

test("B:ShowGain on the real window opens History and searches it", function()
  local B = NS.Browser
  local ok, err = pcall(function()
    assertTrue(B:ShowGain({ kind = "ITEM", name = "Apple" }))
    assertEqual(B:ActiveTab(), "History")
  end)
  if B.SetSearchText then B:SetSearchText("") end
  B:Hide()
  if not ok then error(err, 0) end
end)
