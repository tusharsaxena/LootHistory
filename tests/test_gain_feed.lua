-- tests/test_gain_feed.lua — modules/GainFeed.lua (toast spec
-- docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §4, §5, §13.2): the one GAIN sender, its
-- scratch payload, `wants` and `on`, the feed claims, the Collector's three chat taps and the
-- Reconciler's diff tap. Every case spies the bus for GAIN (copying each payload, since the scratch
-- is reused) and puts back what it touched.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local G = function() return NS.GainFeed end
local LINK = "|cffa335ee|Hitem:211296::::::::80:::::|h[Vial of Fun]|h|r"
local CURRENCY_LINK = "|cffffffff|Hcurrency:3008::|h[Valorstones]|h|r"
local KINDS = { "ITEM", "GOLD", "CURRENCY", "REPUTATION", "APPEARANCE", "XP", "SKILL" }

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

--- Run `fn(sent)` with every GAIN captured into `sent` (copies), the gain feed wanting `kinds` (a set
--- of GainKind, or all), the claims empty and the Collector's and Reconciler's state put back.
local function withFeed(kinds, fn)
  local g, s, R = G(), NS.db.profile.settings, NS.Reconciler
  local savedWants, savedOn, savedClaims = copy(g.wants), g.on, g.claims
  local savedSend = NS.bus.SendMessage
  local savedS = { s.qualityThreshold, s.recordCurrency, s.recordGold, s.trackLedger, s.excludedSources }
  local savedR = { R.claims, R._enabled }
  local savedH, savedNow = NS.db.global.history, M.__now
  local sent = {}
  NS.bus.SendMessage = function(self, msg, a, ...)
    if msg == NS.MSG.GAIN then sent[#sent + 1] = copy(a); return end
    return savedSend(self, msg, a, ...)
  end
  for _, k in ipairs(KINDS) do g.wants[k] = kinds == nil or kinds[k] == true end
  g.on, g.claims = true, {}
  R.claims, R._enabled = {}, true
  NS.db.global.history = {}
  M.__now = 100
  NS.State.lootContext, NS.State.lootWindow = nil, nil
  local ok, err = pcall(fn, sent)
  NS.bus.SendMessage = savedSend
  for k, v in pairs(savedWants) do g.wants[k] = v end
  g.on, g.claims = savedOn, savedClaims
  s.qualityThreshold, s.recordCurrency, s.recordGold, s.trackLedger, s.excludedSources =
    savedS[1], savedS[2], savedS[3], savedS[4], savedS[5]
  R.claims, R._enabled = savedR[1], savedR[2]
  NS.db.global.history, M.__now = savedH, savedNow
  NS.Collector:RefreshUpvalues()
  if not ok then error(err, 0) end
end

local function loot(link, qty)
  NS.Collector:OnChatMsgLoot(nil, qty and string.format(M.LOOT_ITEM_SELF_MULTIPLE, link, qty)
    or string.format(M.LOOT_ITEM_SELF, link))
end

-- ── the sender and the payload ───────────────────────────────────────────────────────────────

test("GainFeed: no shipped file but modules/GainFeed.lua sends NS.MSG.GAIN", function()
  local offenders = {}
  for _, path in ipairs(T.addonFiles) do
    if path ~= "modules/GainFeed.lua" then
      local n = 0
      for line in T.Loader.readFile(path):gmatch("[^\r\n]+") do
        n = n + 1
        if not line:match("^%s*%-%-") and line:find("SendMessage%s*%(%s*[%w_.]*MSG%.GAIN") then offenders[#offenders + 1] = path .. ":" .. n end
      end
    end
  end
  assertEqual(table.concat(offenders, ", "), "", "the gain feed is the one GAIN sender (docs/message-bus.md)")
end)

test("GainFeed: Begin answers the one scratch table with every field cleared, kind and dir set", function()
  local a = G():Begin("ITEM")
  for _, f in ipairs(G().FIELDS) do a[f] = f end
  local b = G():Begin("GOLD")
  assertTrue(a == b, "the same table on every send (no allocation)")
  for _, f in ipairs(G().FIELDS) do
    if f ~= "kind" and f ~= "dir" and f ~= "sim" then assertEqual(b[f], nil, f .. " was cleared") end
  end
  assertEqual(b.kind, "GOLD"); assertEqual(b.dir, "IN"); assertEqual(b.sim, false)
end)

test("GainFeed: the sim flag says whether a simulation is running", function()
  local savedActive = NS.Sim.IsActive
  NS.Sim.IsActive = function() return true end
  local g = G():Begin("XP")
  NS.Sim.IsActive = savedActive
  assertEqual(g.sim, true)
end)

-- ── wants and Recompute ──────────────────────────────────────────────────────────────────────

test("GainFeed: Recompute takes wants from each enabled feed's kinds, appearances by feature", function()
  local g, feeds = G(), NS.db.profile.settings.toasts.feeds
  local saved = {}
  for fid, f in pairs(feeds) do saved[fid] = f.enabled end
  local savedWants, savedOn = copy(g.wants), g.on
  local ok, err = pcall(function()
    for _, f in pairs(feeds) do f.enabled = false end
    g:Recompute()
    assertFalse(g.on, "no feed enabled: nothing wanted")
    for _, k in ipairs(KINDS) do assertFalse(g.wants[k], k) end
    feeds.progress.enabled = true
    g:Recompute()
    assertTrue(g.on)
    assertEqual(tostring(g.wants.REPUTATION) .. tostring(g.wants.XP) .. tostring(g.wants.SKILL), "truetruetrue")
    assertEqual(tostring(g.wants.ITEM) .. tostring(g.wants.GOLD) .. tostring(g.wants.CURRENCY), "falsefalsefalse")
    feeds.progress.enabled, feeds.main.enabled = false, true
    g:Recompute()
    assertEqual(g.wants.APPEARANCE, NS.Constants.FEATURE.appearances == true, "appearances only where a feature")
    assertTrue(g.toastWants.ITEM, "toastWants is the feeds' part")
    g:SetFarm({ GOLD = true })
    feeds.main.enabled = false
    g:Recompute()
    assertTrue(g.wants.GOLD and g.on, "the farm set keeps its kinds wanted")
    assertFalse(g.toastWants.GOLD, "and it is not the feeds'")
    g:SetFarm(nil)
    assertFalse(g.on)
  end)
  for fid, v in pairs(saved) do feeds[fid].enabled = v end
  g._farm = nil
  for k, v in pairs(savedWants) do g.wants[k] = v end
  g.on = savedOn
  if not ok then error(err, 0) end
end)

test("GainFeed: Recompute runs SyncCapture on the three observers and ToastBlizz:Apply", function()
  local calls = {}
  local saved = { NS.Reputation.SyncCapture, NS.Appearance.SyncCapture, NS.Progress.SyncCapture, NS.ToastBlizz }
  local savedWants, savedOn = copy(G().wants), G().on
  NS.Reputation.SyncCapture = function() calls[#calls + 1] = "Reputation" end
  NS.Appearance.SyncCapture = function() calls[#calls + 1] = "Appearance" end
  NS.Progress.SyncCapture = function() calls[#calls + 1] = "Progress" end
  NS.ToastBlizz = { Apply = function() calls[#calls + 1] = "ToastBlizz" end }
  local ok, err = pcall(function() G():Recompute() end)
  NS.Reputation.SyncCapture, NS.Appearance.SyncCapture, NS.Progress.SyncCapture, NS.ToastBlizz =
    saved[1], saved[2], saved[3], saved[4]
  for k, v in pairs(savedWants) do G().wants[k] = v end
  G().on = savedOn
  if not ok then error(err, 0) end
  assertEqual(table.concat(calls, ","), "Reputation,Appearance,Progress,ToastBlizz")
end)

test("GainFeed: with `on` false no chat line sends a gain", function()
  withFeed({}, function(sent)
    G().on = false
    loot(LINK)
    NS.Collector:OnChatMsgMoney(nil, "You loot 5 Copper")
    assertEqual(#sent, 0)
  end)
end)

-- ── the chat taps and the feed claims ────────────────────────────────────────────────────────

test("GainFeed: a recorded loot line sends ITEM with its row and posts no feed claim", function()
  withFeed(nil, function(sent)
    NS.db.profile.settings.qualityThreshold = 1; NS.Collector:RefreshUpvalues()
    NS.Attribution:Stamp("KILL", { npcID = 5 }, "CERTAIN")
    loot(LINK, 2)
    assertEqual(#sent, 1)
    local g = sent[1]
    assertEqual(g.kind, "ITEM"); assertEqual(g.id, 211296); assertEqual(g.qty, 2); assertEqual(g.link, LINK)
    assertEqual(g.name, NS.db.global.history[1].itemName); assertEqual(g.source, "KILL"); assertEqual(g.origin, "chat")
    assertTrue(g.recorded); assertTrue(g.record == NS.db.global.history[1]); assertEqual(g.gated, nil)
    assertEqual(next(G().claims), nil, "a recorded gain needs no feed claim")
  end)
end)

test("GainFeed: a quality-gated loot line still sends, gated, and posts a feed claim only with the ledger on", function()
  withFeed(nil, function(sent)
    local s = NS.db.profile.settings
    s.qualityThreshold = 5; NS.Collector:RefreshUpvalues()
    loot(LINK, 3)
    assertEqual(#sent, 1)
    assertFalse(sent[1].recorded); assertEqual(sent[1].gated, "quality")
    assertEqual(#NS.db.global.history, 0, "no row")
    assertEqual(G().claims["i:211296"][1].qty, 3, "the diff's sighting of it is claimed")
    G().claims = {}
    s.trackLedger = false; NS.Collector:RefreshUpvalues()
    loot(LINK, 3)
    assertEqual(#sent, 2)
    assertEqual(next(G().claims), nil, "no ledger, no diff, no claim")
  end)
end)

test("GainFeed: currency and money lines send whatever their switches decide", function()
  withFeed(nil, function(sent)
    local s = NS.db.profile.settings
    s.recordCurrency, s.recordGold = false, false; NS.Collector:RefreshUpvalues()
    NS.Collector:OnChatMsgCurrency(nil, string.format(M.CURRENCY_GAINED_MULTIPLE, CURRENCY_LINK, 9))
    NS.Collector:OnChatMsgMoney(nil, "You loot 5 Copper")
    assertEqual(#sent, 2)
    assertEqual(sent[1].kind, "CURRENCY"); assertEqual(sent[1].id, 3008); assertEqual(sent[1].qty, 9)
    assertEqual(sent[1].gated, "recordCurrency-off"); assertFalse(sent[1].recorded)
    assertEqual(sent[2].kind, "GOLD"); assertEqual(sent[2].qty, 5); assertEqual(sent[2].gated, "gold-off")
    assertEqual(G().claims["c:3008"][1].qty, 9); assertEqual(G().claims.g[1].qty, 5)
    s.recordCurrency, s.recordGold = true, true; NS.Collector:RefreshUpvalues()
    NS.Collector:OnChatMsgMoney(nil, "You loot 7 Copper")
    assertTrue(sent[3].recorded); assertEqual(sent[3].gated, nil)
  end)
end)

test("GainFeed: a kind not wanted sends nothing on its line", function()
  withFeed({ GOLD = true }, function(sent)
    loot(LINK)
    NS.Collector:OnChatMsgMoney(nil, "You loot 5 Copper")
    assertEqual(#sent, 1); assertEqual(sent[1].kind, "GOLD")
  end)
end)

-- ── the diff tap ─────────────────────────────────────────────────────────────────────────────

test("GainFeed: FromDiff sends the unclaimed rest with the diff's reason, recorded by RowAllowed", function()
  withFeed(nil, function(sent)
    G().claims = {}
    NS.Ledger.PostClaim(G().claims, "i:211296", 2, nil, 100)
    G():FromDiff("i:211296", 2, "OTHER", 100, LINK)
    assertEqual(#sent, 0, "a diff the feed claim covers sends nothing")
    NS.Ledger.PostClaim(G().claims, "i:211296", 1, nil, 100)
    G():FromDiff("i:211296", 3, "MAIL", 100, LINK)
    assertEqual(#sent, 1)
    local g = sent[1]
    assertEqual(g.qty, 2); assertEqual(g.source, "MAIL"); assertEqual(g.origin, "diff"); assertEqual(g.link, LINK)
    assertEqual(g.confidence, "CERTAIN"); assertEqual(g.recorded, NS.Reconciler:RowAllowed("ITEM", 211296))
    G():FromDiff("g", 50, "OTHER", 100)
    assertEqual(sent[2].kind, "GOLD"); assertEqual(sent[2].qty, 50); assertEqual(sent[2].confidence, "INFERRED")
    G().wants.CURRENCY = false
    G():FromDiff("c:3008", 4, "OTHER", 100)
    assertEqual(#sent, 2, "an unwanted kind sends nothing")
  end)
end)

test("GainFeed: the row writer's tap skips other holders, moves, forced passes and losses", function()
  local R = NS.Reconciler
  local savedWrite, savedReason, savedFrom = R.Write, R.ReasonFor, G().FromDiff
  local seen, reason = {}, "OTHER"
  R.Write = function() end
  R.ReasonFor = function() return reason end
  withFeed(nil, function()
    G().FromDiff = function(_, key, dlt, why) seen[#seen + 1] = key .. "=" .. dlt .. ":" .. why end
    local me = NS.Util.PlayerKey()
    local function rows(net, force, drift)
      R.forceReason, R.drift = force, drift
      R:WriteRows({ moves = {}, pairs = {}, net = net }, 1000, 100)
      R.forceReason, R.drift = nil, nil
    end
    rows({ [me] = { g = 10, ["i:5"] = -1 }, ["Alt-Realm"] = { g = 7 } })
    assertEqual(table.concat(seen, ","), "g=10:OTHER", "only my own gain")
    seen = {}
    reason = "ALT_MAIL"; rows({ [me] = { g = 10 } })
    reason = "OTHER"; rows({ [me] = { g = 10 } }, "UNTRACKED")
    rows({ [me] = { g = 10 } }, nil, true)
    assertEqual(#seen, 0, "a holder move, a forced login pass and a drift pass send nothing")
    local WB = NS.Constants.WARBAND_HOLDER
    rows({ [WB] = { ["c:3008"] = 4, g = 9, ["i:5"] = 2 } })
    assertEqual(table.concat(seen, ","), "c:3008=4:OTHER", "an account-wide currency's gain is mine; the warband's gold and items are not")
    seen = {}
    reason = "CURRENCY_TRANSFER"; rows({ [WB] = { ["c:3008"] = 4 } })
    assertEqual(#seen, 0, "a currency transfer is a holder move")
  end)
  R.Write, R.ReasonFor, G().FromDiff = savedWrite, savedReason, savedFrom
end)

test("GainFeed: gainSend notes the parent each sender ran inside (performance-§3)", function()
  -- red under: a bracket that notes no parent, so gainSend's time reads as disjoint from the capture
  -- buckets it runs inside.
  local P, notes = NS.Perf, {}
  local savedOn, savedNote = P.on, P.Note
  local ok, err = pcall(withFeed, nil, function(sent)
    P.on = true
    P.Note = function(key, _, parent) if key == "gainSend" then notes[#notes + 1] = tostring(parent) end end
    G():SendEvent(G():Begin("XP"), "xpEvent")
    local gold = G():Begin("GOLD")
    gold.qty = 5
    G():SendChat(gold, "moneyLine")
    G():FromDiff("g", 50, "OTHER", 100)
    assertEqual(#sent, 3)
    assertEqual(G().sending, nil, "the in-send mark is cleared after the bracket")
  end)
  P.on, P.Note = savedOn, savedNote
  if not ok then error(err, 0) end
  assertEqual(table.concat(notes, ","), "xpEvent,moneyLine,false", "the observer's bucket; the diff's tap at top level")
end)

test("GainFeed: HoldClaims carries a feed claim through a combat deferral", function()
  withFeed(nil, function(sent)
    NS.Ledger.PostClaim(G().claims, "g", 5, nil, 100)
    G():HoldClaims(100, 110)
    G():PruneClaims(110)
    assertTrue(G().claims.g ~= nil, "the claim outlived its TTL by the deferral")
    G():FromDiff("g", 5, "OTHER", 111)
    assertEqual(#sent, 0, "the chat line's gain is not sent a second time")
  end)
end)

-- ── lifecycle ────────────────────────────────────────────────────────────────────────────────

test("GainFeed: Disable drops wants, the farm set, the claims and the listener; ResetState the claims", function()
  local g = G()
  local savedWants, savedOn, savedEv, savedFarm = copy(g.wants), g.on, g.__ev, g._farm
  local unregistered = false
  g.__ev = { UnregisterAllMessages = function() unregistered = true end }
  g._farm = { GOLD = true }
  for k in pairs(g.wants) do g.wants[k] = true end
  g.on = true
  NS.Ledger.PostClaim(g.claims, "g", 1, nil, 100)
  g:Disable()
  local wanted = false
  for _, v in pairs(g.wants) do wanted = wanted or v end
  local after = { wanted, g.on, g._farm, next(g.claims), g.__ev, unregistered }
  NS.Ledger.PostClaim(g.claims, "g", 1, nil, 100)
  g:ResetState()
  local reset = next(g.claims)
  for k, v in pairs(savedWants) do g.wants[k] = v end
  g.on, g.__ev, g._farm = savedOn, savedEv, savedFarm
  assertEqual(after[1], false); assertEqual(after[2], false); assertEqual(after[3], nil)
  assertEqual(after[4], nil); assertEqual(after[5], nil); assertTrue(after[6], "the listener went")
  assertEqual(reset, nil, "ResetState wipes the claims")
end)
