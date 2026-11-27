-- tests/test_probe.lua — the WoW Forever port's probe verbs (ruling R4, modules/Probe.lua).
--
-- `/lh debug probe start|stop|status|clear` records the client facts the port's safe defaults rest
-- on into db.global.probe, capped and stamped with the client. Each case runs under whichever kit
-- profile is active and checks that profile's own answers, so the Forever run proves the Forever
-- shapes (a surname, regional names) and the Retail run the Retail ones. Every case stops the probe
-- and puts db.global.probe back.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local P = NS.Probe
local FOREVER = T.forever

local function capture(fn)
  local out = {}
  local cf = M.DEFAULT_CHAT_FRAME
  local old = cf.AddMessage
  cf.AddMessage = function(_, msg) out[#out + 1] = msg end
  local ok, err = pcall(fn)
  cf.AddMessage = old
  if not ok then error(err, 0) end
  return out
end

--- Run `fn` with an empty probe record; stop the probe and restore the record after, pass or fail.
local function fresh(fn)
  local g = NS.db.global
  local saved = g.probe
  g.probe = nil
  local ok, err = pcall(fn)
  if P.IsRunning() then P.Stop() end
  M.__fireTimers()
  g.probe = saved
  if not ok then error(err, 0) end
end

local function entries() return (P.Store(false) or { entries = {} }).entries end

local function ofKind(kind)
  local out = {}
  for _, e in ipairs(entries()) do if e.kind == kind then out[#out + 1] = e end end
  return out
end

-- ── the verbs ─────────────────────────────────────────────────────────────────────────────

test("probe: bare and status print the status line; an unknown word prints the usage", function()
  fresh(function()
    local out = capture(function() NS.Slash:OnSlash("debug probe") end)
    assertEqual(out[#out], NS.PREFIX .. " probe: stopped, 0 entries (cap " .. P.CAP .. ")")
    out = capture(function() NS.Slash:OnSlash("debug probe status") end)
    assertEqual(out[#out], NS.PREFIX .. " probe: stopped, 0 entries (cap " .. P.CAP .. ")")
    out = capture(function() NS.Slash:OnSlash("debug probe frobnicate") end)
    assertEqual(out[#out], NS.PREFIX .. " usage: /lh debug probe start|stop|status|clear")
    assertEqual(NS.db.global.probe, nil, "status and usage write nothing")
  end)
end)

test("probe: /lh debug probe start records under db.global.probe, stamped with the client", function()
  -- red under: the verb unrouted, a stamp that is not the running client's, or a new SV global.
  fresh(function()
    local out = capture(function() NS.Slash:OnSlash("debug probe start") end)
    assertTrue(P.IsRunning(), "started")
    assertTrue(out[#out]:find("probe started", 1, true) ~= nil, "the start line")
    local store = NS.db.global.probe
    assertTrue(type(store) == "table", "the record lives in db.global.probe")
    assertEqual(store.client, NS.Compat.ClientKey())
    assertEqual(store.client, FOREVER and "forever" or "retail")
    local version, build = M.GetBuildInfo()
    assertEqual(store.version, version); assertEqual(store.build, build)
    assertTrue(type(store.started) == "number", "started stamped")
    local start = ofKind("start")[1]
    assertTrue(start ~= nil, "a start entry")
    assertEqual(start.client, store.client); assertEqual(start.build, build)
    out = capture(function() NS.Slash:OnSlash("debug probe status") end)
    assertTrue(out[#out]:find("probe: running, 1 entry", 1, true) ~= nil, out[#out])
    assertTrue(out[#out]:find(store.client .. " " .. version .. " " .. build, 1, true) ~= nil, out[#out])
    out = capture(function() NS.Slash:OnSlash("debug probe stop") end)
    assertFalse(P.IsRunning(), "stopped")
    assertTrue(out[#out]:find("probe: stopped, 2 entries", 1, true) ~= nil, out[#out])
    assertTrue(type(store.stopped) == "number", "stopped stamped")
    assertEqual(entries()[#entries()].kind, "stop")
  end)
end)

test("probe: start registers every probe event on its own frame and stop unregisters them", function()
  fresh(function()
    assertTrue(P.Start())
    local f = P._state.frame
    assertTrue(f ~= nil and f ~= NS.addon, "a private frame, never the capture bus")
    for _, event in ipairs(P.EVENTS) do assertTrue(f:IsEventRegistered(event), event .. " registered") end
    assertTrue(P.Stop())
    for _, event in ipairs(P.EVENTS) do assertFalse(f:IsEventRegistered(event), event .. " unregistered") end
  end)
end)

test("probe: a second start and a stop while stopped are refused with a reason", function()
  fresh(function()
    assertTrue(P.Start())
    local ok, why = P.Start()
    assertFalse(ok); assertEqual(why, "already running")
    local out = capture(function() NS.Slash:OnSlash("debug probe start") end)
    assertEqual(out[#out], NS.PREFIX .. " probe not started: already running")
    assertTrue(P.Stop())
    ok, why = P.Stop()
    assertFalse(ok); assertEqual(why, "not running")
  end)
end)

test("probe: clear drops every entry; while running the record is stamped again and goes on", function()
  fresh(function()
    assertTrue(P.Start())
    P.Record("note", {})
    local out = capture(function() NS.Slash:OnSlash("debug probe clear") end)
    assertTrue(out[#out]:find("probe: running, 0 entries", 1, true) ~= nil, out[#out])
    assertEqual(NS.db.global.probe.client, NS.Compat.ClientKey(), "stamped again")
    P.Record("note", {})
    assertEqual(#entries(), 1, "recording goes on")
    assertTrue(P.Stop())
    P.Clear()
    assertEqual(NS.db.global.probe, nil, "stopped: the record is gone")
  end)
end)

-- LH-REV: the cap drops the oldest entry that is not a `start` one; the start facts (P3, P5, P8,
-- P9) are read once per start, so a long session must never push them out.
test("probe: the record is capped at P.CAP, the oldest non-start entries dropped and counted", function()
  -- red under: a cap that drops entry 1, which is always the start entry.
  fresh(function()
    assertTrue(P.Start())
    for i = 1, P.CAP + 5 do P.Record("note", { i = i }) end
    assertEqual(#entries(), P.CAP)
    assertEqual(NS.db.global.probe.dropped, 6, "the six oldest notes")
    assertEqual(entries()[1].kind, "start", "the start entry is kept")
    assertEqual(entries()[2].i, 7); assertEqual(entries()[P.CAP].i, P.CAP + 5)
    assertTrue(P.StatusLine():find("6 dropped", 1, true) ~= nil, P.StatusLine())
  end)
end)

test("probe: nothing is recorded while stopped, or while a simulation runs", function()
  fresh(function()
    assertEqual(P.Record("note", {}), nil, "stopped")
    assertEqual(NS.db.global.probe, nil)
    assertTrue(P.Start())
    local saved = NS.Sim.IsActive
    NS.Sim.IsActive = function() return true end
    local ok, err = pcall(function()
      assertEqual(P.Record("note", {}), nil, "a simulation runs")
      P.Stop(); P.Clear()
      local out = capture(function() NS.Slash:OnSlash("debug probe start") end)
      assertFalse(P.IsRunning(), "the start is refused while a simulation runs")
      assertEqual(out[#out], NS.PREFIX .. " The probe is not available while a simulation runs.")
    end)
    NS.Sim.IsActive = saved
    if not ok then error(err, 0) end
  end)
end)

-- ── the start facts ───────────────────────────────────────────────────────────────────────

test("probe: the start entry carries this client's name forms, money text and strings", function()
  fresh(function()
    assertTrue(P.Start())
    local s = ofKind("start")[1]
    assertEqual(s.identity.unitName, "Mock")
    assertEqual(s.identity.unitNameSecond, FOREVER and "Mockley" or nil, "Forever's surname")
    assertEqual(s.identity.regionalNames, FOREVER)
    assertEqual(s.identity.playerKey, NS.Util.PlayerKey())
    assertEqual(s.money.GetMoneyString, M.GetMoneyString and "function" or "absent")
    assertEqual(s.money.formatted, NS.Util.FormatMoney(P.MONEY_SAMPLE))
    assertEqual(s.strings.LOOT_ROLL_YOU_WON, M.LOOT_ROLL_YOU_WON)
    assertTrue(s.keyring ~= nil and s.keyring.slots == 0, "the keyring read, empty in the mock")
  end)
end)

test("probe: the keyring's slots, contents and inventory slot are read (P3)", function()
  fresh(function()
    local savedSlots, savedBag = M.__bagSlots[-1], M.__bags[-1]
    M.__bagSlots[-1] = 2
    M.__bags[-1] = { [1] = { itemID = 5396, link = "|cffffffff|Hitem:5396|h[Key]|h|r", count = 1 } }
    local ok, err = pcall(function()
      assertTrue(P.Start())
      local k = ofKind("start")[1].keyring
      assertEqual(k.slots, 2)
      assertEqual(#k.items, 1); assertEqual(k.items[1].itemID, 5396); assertEqual(k.items[1].slot, 1)
    end)
    M.__bagSlots[-1], M.__bags[-1] = savedSlots, savedBag
    if not ok then error(err, 0) end
  end)
end)

-- ── the bank visit (P1, P2, P10) ──────────────────────────────────────────────────────────

test("probe: a banker visit records the bank at open, +1 s and +3 s, and its cues", function()
  fresh(function()
    local bank = NS.Constants.BANK_IDS[1]
    local savedSlots = M.__bagSlots[bank]
    M.__bagSlots[bank] = 0
    local ok, err = pcall(function()
      assertTrue(P.Start())
      M.__fireTimers()
      local t0 = M.__now
      P.OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", M.Enum.PlayerInteractionType.CharacterBanker)
      local inter = ofKind("interaction")[1]
      assertEqual(inter.type, 67); assertEqual(inter.banker, "CharacterBanker")
      local open = ofKind("bank")[1]
      assertEqual(open.phase, "open"); assertEqual(open.via, "CharacterBanker")
      local seen
      for _, row in ipairs(open.slots) do if row.id == bank then seen = row.slots end end
      assertEqual(seen, 0, "a bank container that answers 0 is still recorded")
      assertEqual(open.model.canViewCharacter[1], true, "CanViewBank(0)")
      assertEqual(open.model.canViewAccount[1], not FOREVER, "CanViewBank(2), the profile's answer")
      assertEqual(#open.sockets, P.SOCKETS, "the -2 socket reads")
      -- A second open signal in the same visit is a cue, not a second snapshot.
      M.__now = t0 + 0.5
      P.OnEvent("BANKFRAME_OPENED")
      M.__bagSlots[bank] = 28
      P.OnEvent("BAG_CONTAINER_UPDATE")
      local cues = ofKind("cue")
      assertEqual(#cues, 2)
      assertEqual(cues[1].event, "BANKFRAME_OPENED"); assertEqual(cues[2].dt, 0.5)
      M.__fireTimers()
      local snaps = ofKind("bank")
      assertEqual(#snaps, 3)
      assertEqual(snaps[2].phase, "+1s"); assertEqual(snaps[3].phase, "+3s")
      for _, row in ipairs(snaps[3].slots) do if row.id == bank then seen = row.slots end end
      assertEqual(seen, 28, "the later read sees the loaded container")
      -- Past the window a cue is not recorded; the close ends the visit.
      M.__now = t0 + P.BANK_WINDOW + 1
      P.OnEvent("PLAYERBANKSLOTS_CHANGED", 3)
      assertEqual(#ofKind("cue"), 2)
      P.OnEvent("BANKFRAME_CLOSED")
      assertEqual(P._state.bankOpenAt, nil)
      M.__now = t0
    end)
    M.__bagSlots[bank] = savedSlots
    if not ok then error(err, 0) end
  end)
end)

test("probe: a non-banker interaction is recorded and takes no bank snapshot", function()
  fresh(function()
    assertTrue(P.Start())
    P.OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", M.Enum.PlayerInteractionType.Merchant)
    assertEqual(ofKind("interaction")[1].banker, nil)
    assertEqual(#ofKind("bank"), 0)
  end)
end)

-- ── the capture-side facts (P4, P5, P7, P8, P11) ──────────────────────────────────────────

test("probe: a loot, money or currency chat line is kept raw with its sender fields and GUID", function()
  fresh(function()
    assertTrue(P.Start())
    local line = T.rollWonLine("|cffffffff|Hitem:2589|h[Linen Cloth]|h|r", 7)
    P.OnEvent("CHAT_MSG_LOOT", line, "Mock", "", "", "Mock", "", 0, 0, "", 0, 1, "Player-1-0001")
    P.OnEvent("CHAT_MSG_MONEY", "You loot 5 Copper", "", "", "", "")
    local chat = ofKind("chat")
    assertEqual(#chat, 2)
    assertEqual(chat[1].event, "CHAT_MSG_LOOT"); assertEqual(chat[1].text, line)
    assertEqual(chat[1].sender, "Mock"); assertEqual(chat[1].sender2, "Mock")
    assertEqual(chat[1].guid, "Player-1-0001")
    assertEqual(chat[2].event, "CHAT_MSG_MONEY")
  end)
end)

test("probe: a secret or long string never reaches the record as is", function()
  fresh(function()
    assertTrue(P.Start())
    local saved = NS.IsConcatSafe
    NS.IsConcatSafe = function(v) return v ~= "SECRET" end
    local ok, err = pcall(function()
      P.OnEvent("CHAT_MSG_LOOT", "SECRET", "SECRET")
      local c = ofKind("chat")[1]
      assertEqual(c.text, "<secret>"); assertEqual(c.sender, "<secret>")
    end)
    NS.IsConcatSafe = saved
    if not ok then error(err, 0) end
    assertEqual(#P.plain(("x"):rep(P.TEXT_MAX + 50)), P.TEXT_MAX)
    assertEqual(P.plain({}), "<table>"); assertEqual(P.plain(print), "<function>")
    assertEqual(P.plain(3), 3); assertEqual(P.plain(false), false)
  end)
end)

test("probe: a trade records the partner's name forms and the key the addon builds (P7)", function()
  fresh(function()
    local savedName, savedSecond = M.__tradeTarget, M.__tradeTargetSecond
    M.__tradeTarget, M.__tradeTargetSecond = "Traxex", FOREVER and "Silentshot" or nil
    local ok, err = pcall(function()
      assertTrue(P.Start())
      P.OnEvent("TRADE_SHOW")
      local t = ofKind("trade")[1]
      assertEqual(t.unitName, "Traxex")
      assertEqual(t.unitNameSecond, FOREVER and "Silentshot" or nil)
      assertEqual(t.tradeTargetKey, NS.Compat.TradeTargetKey())
    end)
    M.__tradeTarget, M.__tradeTargetSecond = savedName, savedSecond
    if not ok then error(err, 0) end
  end)
end)

test("probe: the newest currency transfer is recorded field by field (P5)", function()
  fresh(function()
    local saved = M.__currencyTransfers
    M.__currencyTransfers = { { currencyType = 1792, quantityTransferred = 5, destinationCharacterName = "Alt" } }
    local ok, err = pcall(function()
      assertTrue(P.Start())
      assertEqual(ofKind("start")[1].transfer.destinationCharacterName, "Alt")
      P.OnEvent("CURRENCY_TRANSFER_LOG_UPDATE")
      local tr = ofKind("transfer")[1].transfer
      assertEqual(tr.currencyType, 1792); assertEqual(tr.quantityTransferred, 5); assertEqual(tr.count, 1)
    end)
    M.__currencyTransfers = saved
    if not ok then error(err, 0) end
  end)
end)

test("probe: the mail hook records the recipient as typed and as the addon keys it (P7)", function()
  fresh(function()
    assertTrue(P.Start())
    -- The hook body, called as the client's post-hook would call it. The install is once per session.
    local saved = NS.Compat.HookSecure
    local got
    NS.Compat.HookSecure = function(name, fn) if name == "SendMail" then got = fn end; return true end
    P._state.hooked = false
    P.Stop()
    local ok, err = pcall(function()
      assertTrue(P.Start())
      assertTrue(type(got) == "function", "SendMail hooked through Compat.HookSecure")
      local name = FOREVER and "Traxex Silentshot" or "Traxex"
      got(name, "subject", "body")
      local m = ofKind("mail")[1]
      assertEqual(m.recipient, name); assertEqual(m.qualified, NS.Util.QualifyName(name))
      P.Stop()
      got(name)
      assertEqual(#ofKind("mail"), 1, "the hook body records nothing while stopped")
    end)
    NS.Compat.HookSecure = saved
    if not ok then error(err, 0) end
  end)
end)

test("probe: a handler that raises is recorded as an error entry, never thrown", function()
  fresh(function()
    assertTrue(P.Start())
    local saved = P._handlers.TRADE_SHOW
    P._handlers.TRADE_SHOW = function() error("boom", 0) end
    local ok = pcall(P.OnEvent, "TRADE_SHOW")
    P._handlers.TRADE_SHOW = saved
    assertTrue(ok, "the raise stays inside the probe")
    assertEqual(ofKind("error")[1].err, "boom")
  end)
end)

test("probe: a reputation or appearance event is kept with its arguments (P13)", function()
  fresh(function()
    assertTrue(P.Start())
    P.OnEvent("FACTION_STANDING_CHANGED", 72, 3250)
    P.OnEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Stormwind increased by 250.")
    P.OnEvent("TRANSMOG_COLLECTION_SOURCE_ADDED", 77)
    local got = ofKind("progress")
    assertEqual(#got, 3)
    assertEqual(got[1].event, "FACTION_STANDING_CHANGED")
    assertEqual(got[1].args[1], 72); assertEqual(got[1].args[2], 3250); assertEqual(got[1].args.n, 2)
    assertEqual(got[2].args[1], "Reputation with Stormwind increased by 250.")
    assertEqual(got[3].event, "TRANSMOG_COLLECTION_SOURCE_ADDED"); assertEqual(got[3].args[1], 77)
  end)
end)

test("probe: P.EVENTS ends with the five P13 events, and docs/forever-probes.md names every probe event", function()
  local tail = {}
  for i = #P.EVENTS - 4, #P.EVENTS do tail[#tail + 1] = P.EVENTS[i] end
  assertEqual(table.concat(tail, ","), "FACTION_STANDING_CHANGED,UPDATE_FACTION,CHAT_MSG_COMBAT_FACTION_CHANGE," ..
    "TRANSMOG_COLLECTION_SOURCE_ADDED,TRANSMOG_COLLECTION_SOURCE_REMOVED")
  local doc = T.Loader.readFile("docs/forever-probes.md")
  for _, event in ipairs(P.EVENTS) do
    assertTrue(doc:find("`" .. event .. "`", 1, true) ~= nil, "docs/forever-probes.md names " .. event)
  end
  local row = doc:match("\n| `progress` |([^\n]*)")
  assertTrue(row ~= nil, "the kinds table has its `progress` row")
  local at, order = 0, {}
  for i = #P.EVENTS - 4, #P.EVENTS do
    local here = row:find("`" .. P.EVENTS[i] .. "`", 1, true)
    assertTrue(here ~= nil and here > at, P.EVENTS[i] .. " in P.EVENTS order in the progress row")
    at = here or at
    order[#order + 1] = P.EVENTS[i]
  end
  assertEqual(#order, 5)
end)
