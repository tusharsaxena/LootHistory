-- tests/test_toast_feed.lua — modules/ToastFeed.lua (toast spec
-- docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §8, §13.2): the three feeds built through
-- the seam, the GAIN subscription and routing, the payload hand-back on a refused push, the click actions, the combat
-- rows, unlock and drag, the settings refresh, the stand-down and the library-absent stub path.
--
-- The feeds are LIVE LibKa0s-Feed-1.0 instances (the headless loader loads LibKa0s.xml). Their own
-- behavior (phases, geometry, the merge mechanics, the pin) is the library's suite's; these cases
-- assert only what the host decides and what it passes in. This slot runs after tests/test_dispatch.lua,
-- with the whole addon brought up; every case clears what it showed and puts back what it touched.
--
-- The routing cases HOLD every live feed, so a push waits (merging there) and is read back through
-- Get and Stats().waiting with no clock to step. The paint cases (below "the live paint") build a
-- fresh instance on the host's own descriptor and watch the rows it builds: a real Push presents
-- and paints a row, the unlock Preview paints its samples, and a Release drains held gains onto
-- the screen. tests/wow_mock.lua refuses SetText on a FontString with no font ("Font not set", as
-- the client does), so a first paint that set text before a font would raise there.

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

test("Toasts: a bus GAIN reaches the feeds through the receiver, and none after the stand-down", function()
  withFeeds(nil, function()
    NS.bus:SendMessage(NS.MSG.GAIN, gold(500))
    assertTrue(feed("main"):Get("g") ~= nil, "the bus GAIN reached the Main feed")
    assertEqual(feed("main"):Stats().waiting, 1)
    Toasts:Disable()
    NS.bus:SendMessage(NS.MSG.GAIN, item(7))
    assertEqual(feed("main"):Get("i:7"), nil, "a stood-down receiver hears nothing")
    Toasts:Enable()
    holdAll()
    NS.bus:SendMessage(NS.MSG.GAIN, item(7))
    assertTrue(feed("main"):Get("i:7") ~= nil, "and the stand-up subscribes it again")
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

-- ── the highlight sounds (§8.3) ──────────────────────────────────────────────────────────────

--- Run `fn(played, setNow)` with Compat.PlayMediaSound recorded, the mock clock (M.__now) under the case's control and
--- the feeds' last-sound clock emptied before and after.
local function withSounds(fn)
  local Compat, played = NS.Compat, {}
  local savedPlay, savedNow = Compat.PlayMediaSound, M.__now
  local last = Toasts._lastSound
  for k in pairs(last) do last[k] = nil end
  Compat.PlayMediaSound = function(key) played[#played + 1] = key; return true end
  M.__now = 100
  local ok, err = pcall(fn, played, function(t) M.__now = t end)
  Compat.PlayMediaSound, M.__now = savedPlay, savedNow
  for k in pairs(last) do last[k] = nil end
  if not ok then error(err, 0) end
end

local function mountSound(key)
  local hl = NS.Util.DeepCopy(feedRow("main").hl)
  hl.mountSound = key
  return { main = { hl = hl } }
end

test("Toasts: a new highlighted toast plays its sound, at most once per C.TOAST_SOUND_GAP", function()
  withFeeds(mountSound("Ka0s Chime"), function()
    withSounds(function(played, setNow)
      local f = fakeFeed("new", function(p) p.highlight = "mount" end)
      withFake(f, function()
        Toasts:OnGain(item(7))
        assertEqual(table.concat(played, ","), "Ka0s Chime", "the content's highlight names the sound row")
        setNow(100 + C.TOAST_SOUND_GAP)
        Toasts:OnGain(item(8))
        assertEqual(#played, 1, "a second one inside the gap is quiet")
        setNow(100 + C.TOAST_SOUND_GAP + 0.01)
        Toasts:OnGain(item(9))
        assertEqual(#played, 2, "past the gap it plays again")
      end)
    end)
  end)
end)

test("Toasts: a merged, queued or plain toast plays no sound, nor one whose sound row is None", function()
  withFeeds(mountSound("Ka0s Chime"), function()
    withSounds(function(played)
      for _, res in ipairs({ "merged", "queued" }) do
        withFake(fakeFeed(res, function(p) p.highlight = "mount" end), function() Toasts:OnGain(item(7)) end)
      end
      withFake(fakeFeed("new"), function() Toasts:OnGain(item(7)) end)
      assertEqual(#played, 0)
    end)
  end)
  withFeeds(mountSound(""), function()
    withSounds(function(played)
      withFake(fakeFeed("new", function(p) p.highlight = "mount" end), function() Toasts:OnGain(item(7)) end)
      assertEqual(#played, 0, "the default None")
    end)
  end)
end)

test("Toasts: an appearance folds into its item's toast instead of a toast of its own", function()
  withFeeds(nil, function()
    if not C.FEATURE.appearances then return end
    Toasts:OnGain(item(7, 1, 3))
    local p = feed("main"):Get("i:7")
    Toasts:OnGain({ kind = "APPEARANCE", dir = "IN", id = 900, itemID = 7, qty = 1, name = "Look" })
    assertEqual(feed("main"):Get("a"), nil, "no appearance toast")
    assertTrue(p.newLook, "the item's toast took the look")
    assertEqual(feed("main"):Stats().waiting, 1)
  end)
end)

test("Toasts: the descriptor's motion getter passes the counts settle through", function()
  local d = Toasts._descriptor("main")
  assertEqual(d.motion().settle, C.TOAST_COUNT_SETTLE)
end)

test("Toasts: the content closure is the toastPaint bracket around ToastContent", function()
  local P, notes = NS.Perf, {}
  local savedOn, savedNote = P.on, P.Note
  P.on = true
  P.Note = function(key) notes[#notes + 1] = key end
  local ok, err = pcall(function()
    local spec = { lines = { {}, {}, {} } }
    Toasts._descriptor("main").content(spec, gold(500), "g")
    assertEqual(spec.title, NS.Util.FormatMoney(500))
  end)
  P.on, P.Note = savedOn, savedNote
  if not ok then error(err, 0) end
  assertEqual(table.concat(notes, ","), "toastPaint")
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
    Toasts:OnCombatEnd()
    s = feed("main"):Stats()
    assertFalse(s.clickThrough); assertFalse(s.held)
    assertEqual(s.waiting, 0, "the regen edge drained the held gain")
    assertEqual(s.live, 1, "onto the screen")
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

-- A recording stand-in for the unlock cases, which assert the host's calls and their order (the
-- live Preview's paint is a case of its own, under "the live paint").
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

test("Toasts: NS.Schema:SetMany refuses a batch holding a path no row owns, and stores nothing", function()
  -- The Toasts rows exist since the settings page (M3.6): the nudge is a row, so a batch with one
  -- unknown path is still refused whole, by that entry's index, before anything is stored.
  local before = feedRow("main").x
  local ok, _, _, index = NS.Schema:SetMany({ { path = "settings.toasts.feeds.main.x", value = 1 },
                                              { path = "settings.toasts.feeds.main.nosuch", value = 1 } })
  assertFalse(ok == true)
  assertEqual(index, 2)
  assertEqual(feedRow("main").x, before, "the valid entry is not stored either")
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

-- ── the live paint (§8.3, §8.6) ─────────────────────────────────────────────────────────────

--- Run `fn(f, strings, errors)` with a fresh Feed instance on the host's descriptor for `fid` in the
--- feed's place. `strings` collects every FontString a frame built during the case makes (the rows'),
--- `errors` every raise the library handed to the error handler. Everything is put back after.
local function withPaintedFeed(fid, fn)
  local saved, savedCF, savedEH = Toasts._feeds[fid], M.CreateFrame, M.geterrorhandler
  local strings, errors = {}, {}
  M.CreateFrame = function(...)
    local fr = savedCF(...)
    local make = fr.CreateFontString
    fr.CreateFontString = function(self, ...)
      local fs = make(self, ...)
      strings[#strings + 1] = fs
      return fs
    end
    return fr
  end
  M.geterrorhandler = function() return function(err) errors[#errors + 1] = tostring(err) end end
  local d = Toasts._descriptor(fid)
  d.name = d.name .. "_Paint"
  local f
  local ok, err = pcall(function()
    f = NS.NewFeed(d)
    Toasts._feeds[fid] = f
    fn(f, strings, errors)
  end)
  if f then f:ClearPreview(); f:Clear(); f:SetLocked(true) end
  for k in pairs(NS.State.toastUnlocked) do NS.State.toastUnlocked[k] = nil end
  Toasts._feeds[fid] = saved
  M.CreateFrame, M.geterrorhandler = savedCF, savedEH
  if not ok then error(err, 0) end
end

--- How many collected strings show `text` with a font set.
local function painted(strings, text)
  local n = 0
  for _, fs in ipairs(strings) do
    if fs:GetText() == text and fs:GetFont() ~= nil then n = n + 1 end
  end
  return n
end

test("Toasts: a bus GAIN presents a row on the live Feed and paints its title", function()
  withFeeds(nil, function()
    clearAll()
    withPaintedFeed("main", function(f, strings, errors)
      NS.bus:SendMessage(NS.MSG.GAIN, gold(500))
      local s = f:Stats()
      assertEqual(s.live, 1, "the push presented at once")
      assertEqual(s.waiting, 0)
      assertTrue(s.built, "the first push built the feed")
      assertTrue(#strings > 0, "the row built its strings")
      assertEqual(painted(strings, NS.Util.FormatMoney(500)), 1, "the row's title reads the money")
      assertEqual(#errors, 0, table.concat(errors, "; "))
      assertEqual(f:Push("i:7", NS.ToastModel.NewPayload(item(7, 2))), "new", "a direct Push presents too")
      assertEqual(painted(strings, "Item 7"), 1, "and paints the item's name")
      assertEqual(f:Stats().live, 2)
    end)
  end)
end)

test("Toasts: the unlock Preview paints a sample row per kind the feed shows, up to its cap", function()
  withFeeds(nil, function()
    clearAll()
    withPaintedFeed("main", function(f, strings, errors)
      assertTrue(Toasts:SetUnlocked("main", true), "the live Feed unlocks out of combat")
      local s, n = f:Stats(), #NS.ToastSample.ForFeed("main")
      assertTrue(s.shown > 0, "the built feed has a cap")
      assertEqual(s.live, math.min(n, s.shown), "the samples present, the feed's cap of them")
      local titled = 0
      for _, pair in ipairs(NS.ToastSample.ForFeed("main")) do
        local spec = { lines = { {}, {}, {} } }
        NS.ToastContent.Content("main", spec, pair[2], pair[1])
        if spec.title and spec.title ~= "" and painted(strings, spec.title) > 0 then titled = titled + 1 end
      end
      assertEqual(titled, n, "every sample went through the paint (the oldest past the cap then drop)")
      assertEqual(#errors, 0, table.concat(errors, "; "))
      assertFalse(Toasts:SetUnlocked("main", false))
      assertEqual(f:Stats().live, 0, "the lock frees the preview rows")
    end)
  end)
end)

test("Toasts: a Release drains the held gains onto painted rows", function()
  withFeeds(nil, function()
    clearAll()
    withPaintedFeed("main", function(f, strings, errors)
      f:Hold()
      NS.bus:SendMessage(NS.MSG.GAIN, gold(500))
      NS.bus:SendMessage(NS.MSG.GAIN, item(7))
      NS.bus:SendMessage(NS.MSG.GAIN, item(7, 2))
      local s = f:Stats()
      assertEqual(s.waiting, 2, "the repeat merged while waiting")
      assertEqual(s.live, 0, "nothing shows while held")
      assertEqual(painted(strings, NS.Util.FormatMoney(500)), 0)
      Toasts:OnCombatEnd()
      s = f:Stats()
      assertEqual(s.waiting, 0); assertEqual(s.live, 2, "the regen edge drained both")
      assertFalse(s.held)
      assertEqual(painted(strings, NS.Util.FormatMoney(500)), 1)
      assertEqual(painted(strings, "Item 7"), 1)
      assertEqual(f:Get("i:7").qty, 3, "the drained row carries the merged count")
      assertEqual(#errors, 0, table.concat(errors, "; "))
    end)
  end)
end)

--- The first collected string that shows `text`.
local function stringOf(strings, text)
  for _, fs in ipairs(strings) do
    if fs:GetText() == text then return fs end
  end
  return nil
end

local function near(a, b) return math.abs((tonumber(a) or -1) - b) < 0.002 end

--- A string's font size, through its font object when it draws from one (the Feed's HUD fonts).
local function sizeOf(fs)
  local font, size = fs:GetFont()
  if type(font) == "string" and type(_G[font]) == "table" then font = _G[font] end
  if type(font) == "table" and font.GetFont then size = select(2, font:GetFont()) end
  return size
end

test("Toasts: a feed's style override reaches its painted row, and a Refresh re-reads it", function()
  local FACE = "Fonts\\FRIZQT__.TTF"
  local over = { fontColorFromSkin = false, fontColor = { r = 0.25, g = 0.5, b = 0.75, a = 1 }, fontSize = 17,
                 fontFromSkin = false, font = FACE }
  withFeeds({ main = over }, function()
    clearAll()
    withPaintedFeed("main", function(f, strings, errors)
      NS.bus:SendMessage(NS.MSG.GAIN, gold(500))
      local fs = stringOf(strings, NS.Util.FormatMoney(500))
      assertTrue(fs ~= nil, "the money row painted")
      local r, g, b = fs:GetTextColor()
      assertTrue(near(r, 0.25) and near(g, 0.5) and near(b, 0.75),
        ("the stored font color draws while its FromSkin is off: %s %s %s"):format(tostring(r), tostring(g), tostring(b)))
      assertEqual(sizeOf(fs), 17, "the stored title size draws")
      local face = fs:GetFont()
      if type(face) == "table" then face = face:GetFont() end
      assertEqual(face, FACE, "the stored face draws while fontFromSkin is off")
      local row = feedRow("main")
      row.fontColor = { r = 0.5, g = 0.25, b = 0.125, a = 1 }
      row.fontSize = 19
      f:Refresh()
      r = fs:GetTextColor()
      assertTrue(near(r, 0.5), "Refresh re-read the style getter: " .. tostring(r))
      assertEqual(sizeOf(fs), 19, "and the new title size")
      assertEqual(#errors, 0, table.concat(errors, "; "))
    end)
  end)
end)

test("Toasts: a feed whose text color is from the skin draws the skin's HUD text color", function()
  withFeeds({ main = { fontColorFromSkin = true, fontColor = { r = 0.25, g = 0.5, b = 0.75, a = 1 } } }, function()
    clearAll()
    withPaintedFeed("main", function(f, strings, errors)
      NS.bus:SendMessage(NS.MSG.GAIN, gold(500))
      local fs = stringOf(strings, NS.Util.FormatMoney(500))
      assertTrue(fs ~= nil, "the money row painted")
      local r = fs:GetTextColor()
      assertFalse(near(r, 0.25), "the stored swatch does not draw while FromSkin is on")
      assertTrue(f:Stats().live == 1)
      assertEqual(#errors, 0, table.concat(errors, "; "))
    end)
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
    -- The spare list emptied first: a payload taken off it and handed back would leave its count
    -- unchanged (a merge earlier in this file leaves one there).
    local list, kept = NS.ToastModel._spares, {}
    while #list > 0 do kept[#kept + 1] = table.remove(list) end
    Toasts:OnGain(gold(500))
    local handedBack = #list
    NS.ToastModel.NewPayload(gold(1))
    for _, p in ipairs(kept) do list[#list + 1] = p end
    assertEqual(handedBack, 1, "the stub's refusal hands the payload back")
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

-- ── test mode, the Test act and the strips (§8.7, M3.6) ──────────────────────────────────────

--- A stand-in on the stub's surface that records Preview, ClearPreview, SetStrip and Push.
local function stripFake()
  local f, log = {}, {}
  for k, v in pairs(NS.FeedStub) do f[k] = v end
  f.Preview = function(_, list) log[#log + 1] = "Preview:" .. #list; return #list end
  f.ClearPreview = function() log[#log + 1] = "ClearPreview" end
  f.SetStrip = function(_, kind, text) log[#log + 1] = "Strip:" .. tostring(kind) .. ":" .. tostring(text) end
  f.Push = function(_, key, p) log[#log + 1] = "Push:" .. tostring(key) .. ":" .. tostring(p and p.kind); return "new" end
  return f, log
end

local function has(log, entry)
  for _, e in ipairs(log) do if e == entry then return true end end
  return false
end

test("Toasts: test mode previews each enabled feed's samples under the test strip; off clears both", function()
  local f, log = stripFake()
  withFake(f, function()
    Toasts:SetTestMode(true)
    local n = #NS.ToastSample.ForFeed("main")
    assertTrue(has(log, "Preview:" .. n), "one sticky sample per kind the feed shows")
    assertTrue(has(log, "Strip:test:Test mode"), "the test strip")
    for i = #log, 1, -1 do log[i] = nil end
    Toasts:SetTestMode(false)
    assertTrue(has(log, "ClearPreview")); assertTrue(has(log, "Strip:nil:nil"), "the strip hidden")
  end)
  assertEqual(Toasts._testMode, nil)
end)

test("Toasts: test mode leaves a disabled feed alone", function()
  withFeeds({ extra = { enabled = false } }, function()
    Toasts:SetTestMode(true)
    local ok, err = pcall(function()
      assertEqual(feed("extra"):Stats().live, 0, "no samples on a feed that is off")
      assertTrue(feed("main"):Stats().live > 0, "the enabled Main feed shows them")
    end)
    Toasts:SetTestMode(false)
    assertEqual(feed("main"):Stats().live, 0, "test mode off clears the samples")
    if not ok then error(err, 0) end
  end)
end)

test("Toasts: BrowserTable's test mode switch drives the feeds, and combat start ends both", function()
  local seen, saved = {}, Toasts.SetTestMode
  Toasts.SetTestMode = function(self, on) seen[#seen + 1] = tostring(on); return saved(self, on) end
  local ok, err = pcall(function()
    assertTrue(NS.BrowserTable:SetTestMode(true))
    assertTrue(Toasts._testMode == true)
    NS.BrowserTable:EndTestModeForCombat()
    assertEqual(Toasts._testMode, nil, "the existing end of test mode reaches the feeds")
  end)
  Toasts.SetTestMode = saved
  if NS.BrowserTable.testMode then NS.BrowserTable:SetTestMode(false) end
  clearAll()
  if not ok then error(err, 0) end
  assertEqual(table.concat(seen, ","), "true,false")
end)

test("Toasts: the Test act pushes each sample once with no key, works on a disabled feed, refused in combat", function()
  local f, log = stripFake()
  local saved = NS.db.profile.settings.toasts.feeds.main.enabled
  NS.db.profile.settings.toasts.feeds.main.enabled = false
  NS.ToastModel.Rebuild()
  local ok, err = pcall(withFake, f, function()
    local n = Toasts:Test("main")
    assertEqual(n, #NS.ToastSample.ForFeed("main"), "every sample pushed")
    assertTrue(has(log, "Push:nil:ITEM"), "with no key, so it never merges")
    for i = #log, 1, -1 do log[i] = nil end
    local lines, savedPrint = {}, NS.Print
    NS.Print = function(l) lines[#lines + 1] = l end
    local savedCombat = rawget(M, "UnitAffectingCombat")
    M.UnitAffectingCombat = function() return true end
    local refused = Toasts:Test("main")
    M.UnitAffectingCombat = savedCombat
    NS.Print = savedPrint
    assertEqual(refused, 0); assertEqual(#log, 0, "nothing pushed in combat")
    assertEqual(lines[1], "Test toasts cannot show in combat.")
  end)
  NS.db.profile.settings.toasts.feeds.main.enabled = saved
  NS.ToastModel.Rebuild()
  if not ok then error(err, 0) end
end)

test("Toasts: a Test push is a copy, never the shared sample", function()
  local pushed
  local f = stripFake()
  f.Push = function(_, _, p) pushed = pushed or p; return "new" end
  withFake(f, function() Toasts:Test("main") end)
  local sample = NS.ToastSample.ForFeed("main")[1][2]
  assertTrue(pushed ~= nil and pushed ~= sample, "the Feed gets its own payload")
  assertEqual(pushed.kind, sample.kind)
end)

test("Toasts: the sim strip wins over the test strip while a session runs", function()
  local f, log = stripFake()
  local savedSim = NS.Sim.IsActive
  local ok, err = pcall(withFake, f, function()
    Toasts:SetTestMode(true)
    NS.Sim.IsActive = function() return true end
    Toasts.SyncStrips()
    assertEqual(log[#log], "Strip:sim:Sim mode")
    NS.Sim.IsActive = savedSim
    Toasts.SyncStrips()
    assertEqual(log[#log], "Strip:test:Test mode", "the test strip back when the session ends")
    Toasts:SetTestMode(false)
  end)
  NS.Sim.IsActive = savedSim
  Toasts._testMode = nil
  if not ok then error(err, 0) end
end)
