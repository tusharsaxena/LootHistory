-- tests/test_reputation.lua — modules/Reputation.lua (rep/appearance spec §3.3-§3.4, §4, §5): the
-- pure delta, the FACTION_STANDING_CHANGED capture path, the in-memory seed, coalescing, the source
-- read and the switch's lifecycle. Every capture case runs on tests/mock_progress.lua's double with
-- the history, the baseline and the settings it touches swapped out and put back.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local PM = dofile("tests/mock_progress.lua")
local Rep = function() return NS.Reputation end
local Delta = function(...) return NS.Reputation.Delta(...) end

-- ── Delta (pure) ─────────────────────────────────────────────────────────────────────────────

local function base(standing) return { repType = "base", rank = 5, standing = standing } end
local function renown(rank, standing, threshold)
  return { repType = "renown", rank = rank, standing = standing, threshold = threshold }
end

test("Reputation Delta: a base gain and a base loss are the absolute difference", function()
  assertEqual(Delta(base(3000), "base", 5, 3250), 250)
  assertEqual(Delta(base(3000), "base", 5, 2975), -25)
end)

test("Reputation Delta: a loss across a rank boundary is negative and the right size", function()
  -- Honored (rank 6) at 9010 absolute falls to Friendly (rank 5) at 8990: 20 lost, never the
  -- progress inside the new rank (RLF's wrong-sign rank-down, ruling A5).
  assertEqual(Delta({ repType = "base", rank = 6, standing = 9010 }, "base", 5, 8990), -20)
end)

test("Reputation Delta: renown on the same level, a level-up and a two-level jump", function()
  assertEqual(Delta(renown(10, 500, 2500), "renown", 10, 750, 2500), 250)
  assertEqual(Delta(renown(10, 2400, 2500), "renown", 11, 150, 2500), 250, "(t - s0) + s1")
  assertEqual(Delta(renown(10, 2400, 2500), "renown", 12, 150, 2500), 2750, "(t - s0) + t + s1")
end)

test("Reputation Delta: renown that falls, a type change and no baseline are reseeds", function()
  local d, why = Delta(renown(10, 500, 2500), "renown", 9, 500, 2500)
  assertEqual(d, nil); assertEqual(why, "renown-drop")
  d, why = Delta(base(3000), "renown", 1, 0, 2500)
  assertEqual(d, nil); assertEqual(why, "type-change")
  d, why = Delta(nil, "base", 5, 3000)
  assertEqual(d, nil); assertEqual(why, "unseeded")
end)

test("Reputation Delta: paragon accrues at the cap and a paragon rollover is a reseed", function()
  local old = { repType = "base", rank = 8, standing = 42000, paragon = 4000 }
  assertEqual(Delta(old, "base", 8, 42000, nil, 4250), 250)
  local d, why = Delta(old, "base", 8, 42000, nil, 100)
  assertEqual(d, nil); assertEqual(why, "paragon-reset")
  assertEqual(Delta({ repType = "base", rank = 8, standing = 42000 }, "base", 8, 42000, nil, 300), 300,
    "the switch to paragon at the cap counts from zero")
end)

test("Reputation Delta: an unchanged standing is 0", function()
  assertEqual(Delta(base(3000), "base", 5, 3000), 0)
end)

-- ── the capture harness ──────────────────────────────────────────────────────────────────────

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

--- Run `fn(h, rows)` with the double planted, two seeded factions (Stormwind 72 base, Council of
--- Dornogal 2590 renown), an empty history and the settings at their defaults; everything is put back.
local function withCapture(fn)
  local h = PM.install(M)
  local s = NS.db.profile.settings
  local savedH, savedS = NS.db.global.history, { s.trackLedger, s.excludedSources, s.recordReputation }
  local savedNow, savedCombat, savedTime = M.__now, M.__inCombat, rawget(M, "time")
  local A = NS.Attribution
  local ok, err = pcall(function()
    NS.db.global.history = {}
    s.trackLedger, s.excludedSources, s.recordReputation = true, {}, true
    M.__now, M.__inCombat = 1000, false
    local clock = 1700000000
    M.time = function() return clock end
    h.advance = function(sec) clock = clock + sec end
    h.faction(72, { name = "Stormwind", reaction = 5, standing = 3000 })
    h.faction(2590, { name = "Council of Dornogal", kind = "renown", level = 10, earned = 500, threshold = 2500,
                      accountWide = true })
    h.list = { { id = 1, header = true, depth = 0 }, { id = 72, depth = 1 }, { id = 2590, depth = 1 } }
    A:ResetContexts()
    Rep():ResetState()
    Rep():RefreshUpvalues()
    assertTrue(Rep():Seed(true), "the seed walked")
    with(_G, { FACTION_STANDING_LABEL5 = "Friendly", FACTION_STANDING_LABEL4 = "Neutral",
               FACTION_STANDING_LABEL6 = "Honored" }, function() fn(h, NS.db.global.history) end)
  end)
  Rep():ResetState()
  A:ResetContexts()
  NS.db.global.history = savedH
  s.trackLedger, s.excludedSources, s.recordReputation = savedS[1], savedS[2], savedS[3]
  Rep():RefreshUpvalues()
  M.__now, M.__inCombat = savedNow, savedCombat
  rawset(M, "time", savedTime)
  h.uninstall()
  if not ok then error(err, 0) end
end

local function fire(id) Rep():OnStandingChanged(nil, id) end
local function gain(h, id, n) h.factions[id].standing = h.factions[id].standing + n; fire(id) end

test("Reputation capture: a gain writes one REPUTATION row with every field", function()
  withCapture(function(h, rows)
    gain(h, 72, 250)
    assertEqual(#rows, 1)
    local r = rows[1]
    assertEqual(r.ts, 1700000000); assertEqual(r.char, NS.Util.PlayerKey()); assertEqual(r.holder, r.char, "A1")
    assertEqual(r.classFile, NS.Compat.PlayerClassFile())
    assertEqual(r.dir, "IN"); assertEqual(r.kind, "REPUTATION"); assertEqual(r.factionID, 72)
    assertEqual(r.itemName, "Stormwind"); assertEqual(r.itemType, "Reputation"); assertEqual(r.itemSubType, "Friendly")
    assertEqual(r.quantity, 250); assertEqual(r.repType, "base"); assertEqual(r.rank, 5); assertEqual(r.standing, 3250)
    assertEqual(r.accountWide, nil, "nil, never false, for a character faction")
    assertEqual(r.source, "OTHER"); assertEqual(r.confidence, "INFERRED")
    assertEqual(r.zone, (NS.Zone())); assertEqual(r.mapID, NS.PlayerMapID())
    for _, k in ipairs({ "itemID", "currencyID", "itemLink", "quality", "bound", "vendorPrice", "auctionPrice",
                         "itemLevel" }) do
      assertEqual(r[k], nil, k .. " is not set on a reputation row")
    end
  end)
end)

test("Reputation capture: a renown level-up and a warband faction", function()
  withCapture(function(h, rows)
    local f = h.factions[2590]
    f.level, f.earned = 11, 250
    fire(2590)
    assertEqual(#rows, 1)
    local r = rows[1]
    assertEqual(r.quantity, 2250, "(2500 - 500) + 250"); assertEqual(r.repType, "renown"); assertEqual(r.rank, 11)
    assertEqual(r.standing, 250); assertEqual(r.itemSubType, "Renown 11"); assertEqual(r.accountWide, true)
    assertEqual(r.holder, NS.Util.PlayerKey(), "a warband faction is still the earning character's row (A1)")
  end)
end)

test("Reputation capture: a loss writes OUT, and with trackLedger off it is dropped", function()
  withCapture(function(h, rows)
    gain(h, 72, -25)
    assertEqual(#rows, 1); assertEqual(rows[1].dir, "OUT"); assertEqual(rows[1].quantity, 25)
    NS.db.profile.settings.trackLedger = false
    Rep():RefreshUpvalues()
    h.advance(120)
    gain(h, 72, -25)
    assertEqual(#rows, 1, "A2: a loss needs Track holdings and losses")
    gain(h, 72, 100)
    assertEqual(#rows, 2, "a gain still records with trackLedger off"); assertEqual(rows[2].dir, "IN")
  end)
end)

test("Reputation capture: a fresh quest stamp gives QUEST with its quest id and CERTAIN", function()
  withCapture(function(h, rows)
    NS.Attribution:Stamp("QUEST", { questID = 4242 }, "CERTAIN")
    gain(h, 72, 250)
    assertEqual(rows[1].source, "QUEST"); assertEqual(rows[1].confidence, "CERTAIN")
    assertEqual(rows[1].sourceDetail.questID, 4242)
  end)
end)

test("Reputation capture: in combat it is a KILL, out of combat OTHER, and a VENDOR stamp is ignored", function()
  withCapture(function(h, rows)
    M.__inCombat = true
    gain(h, 72, 10)
    assertEqual(rows[1].source, "KILL"); assertEqual(rows[1].confidence, "INFERRED"); assertEqual(rows[1].sourceDetail, nil)
    M.__inCombat = false
    NS.Attribution:Stamp("VENDOR", nil, "CERTAIN")
    gain(h, 72, 10)
    assertEqual(#rows, 2); assertEqual(rows[2].source, "OTHER", "a purchase is not why a standing moved")
  end)
end)

test("Reputation capture: the source read never spends the loot window or the fishing cast", function()
  withCapture(function(h, rows)
    NS.State.lootWindow = { source = "KILL", detail = { npcID = 1 }, confidence = "CERTAIN", left = 2,
                            expires = M.__now + 10 }
    NS.State.fishingUntil = M.__now + 10
    gain(h, 72, 10)
    assertEqual(NS.State.lootWindow.left, 2, "Peek, never Consume")
    assertEqual(NS.State.fishingUntil, M.__now + 10)
    assertEqual(rows[1].source, "OTHER", "a kill's loot window is not a quest; out of combat reads OTHER")
    NS.State.fishingUntil = nil
  end)
end)

test("Reputation capture: a muted source drops the change", function()
  withCapture(function(h, rows)
    NS.db.profile.settings.excludedSources = { OTHER = true }
    Rep():RefreshUpvalues()
    gain(h, 72, 10)
    assertEqual(#rows, 0, "A8: Record data from")
    assertEqual(Rep():Baseline(72).standing, 3010, "the baseline still moved")
  end)
end)

test("Reputation capture: same faction, direction and source inside 60 s grow one row", function()
  withCapture(function(h, rows)
    M.__inCombat = true
    gain(h, 72, 10)
    h.advance(30)
    h.factions[72].reaction, h.factions[72].standing = 6, 9010
    fire(72)
    assertEqual(#rows, 1, "A3: coalesced")
    assertEqual(rows[1].quantity, 6010); assertEqual(rows[1].standing, 9010); assertEqual(rows[1].rank, 6)
    assertEqual(rows[1].itemSubType, "Honored", "the standing words follow the amend")
  end)
end)

test("Reputation capture: a direction change, a source change or 61 s start a new row", function()
  withCapture(function(h, rows)
    M.__inCombat = true
    gain(h, 72, 10)
    gain(h, 72, -5)
    assertEqual(#rows, 2, "direction change")
    M.__inCombat = false
    gain(h, 72, -5)
    assertEqual(#rows, 3, "source change (KILL -> OTHER)")
    h.advance(61)
    gain(h, 72, -5)
    assertEqual(#rows, 4, "past the window")
    gain(h, 72, -5)
    assertEqual(#rows, 4, "and the next one coalesces again"); assertEqual(rows[4].quantity, 10)
  end)
end)

test("Reputation capture: a row no longer at its index is not amended", function()
  withCapture(function(h, rows)
    gain(h, 72, 10)
    rows[1] = { ts = 1, itemName = "someone else" }
    gain(h, 72, 10)
    assertEqual(#rows, 2); assertEqual(rows[2].quantity, 10)
  end)
end)

test("Reputation capture: a faction first seen at an event is seed-only, and a reseed writes nothing", function()
  withCapture(function(h, rows)
    h.faction(21, { name = "Booty Bay", reaction = 4, standing = 1500 })
    fire(21)
    assertEqual(#rows, 0, "unseeded: never a whole standing as a gain")
    assertEqual(Rep():Baseline(21).standing, 1500)
    gain(h, 21, 25)
    assertEqual(#rows, 1); assertEqual(rows[1].quantity, 25)
    fire(21)
    assertEqual(#rows, 1, "a duplicate event is unchanged")
  end)
end)

test("Reputation capture: a reload (ResetState then Seed) writes nothing", function()
  withCapture(function(h, rows)
    h.factions[72].standing = 5000
    Rep():ResetState()
    assertTrue(Rep():Seed(true))
    fire(72)
    assertEqual(#rows, 0)
    assertEqual(Rep():Baseline(72).standing, 5000)
  end)
end)

test("Reputation capture: the seed waits out combat and retries", function()
  withCapture(function(h)
    local R = Rep()
    R._enabled = true
    local ok, err = pcall(function()
      h.factions[72].standing = 7000
      M.__inCombat = true
      local queued = #M.__timers
      assertFalse(R:Seed(), "no walk in combat")
      assertEqual(R:Baseline(72).standing, 3000, "the old baseline stands")
      assertEqual(#M.__timers, queued + 1, "one retry was armed")
      local retry = M.__timers[#M.__timers]
      assertEqual(retry.delay, NS.Constants.REP_SEED_RETRY)
      M.__inCombat = false
      retry.fn()
      assertEqual(R:Baseline(72).standing, 7000, "and it walked")
    end)
    R._enabled = nil
    if not ok then error(err, 0) end
  end)
end)

test("Reputation capture: the seed opens collapsed headers and shuts them in reverse", function()
  withCapture(function(h)
    h.faction(21, { name = "Booty Bay", reaction = 4, standing = 1500 })
    h.list = { { id = 1, header = true, collapsed = true, depth = 0 }, { id = 72, depth = 1 },
               { id = 2, header = true, collapsed = true, depth = 1 }, { id = 21, depth = 2 } }
    h.calls = {}
    Rep():ResetState()
    Rep():Seed(true)
    assertEqual(table.concat(h.calls, ","), "expand:1@1,expand:2@3,collapse:2@3,collapse:1@1")
    assertEqual(Rep():Baseline(21).standing, 1500, "the nested child was seeded")
  end)
end)

test("Reputation capture: a secret or missing faction id and a secret name drop", function()
  withCapture(function(h, rows)
    with(M, { issecretvalue = function(v) return T.isSecret(v) end }, function()
      fire(T.secret(72))
      fire(nil)
      h.factions[72].standing = 3100
      h.factions[72].name = T.secret("Stormwind")
      fire(72)
    end)
    assertEqual(#rows, 0)
    assertEqual(Rep():Baseline(72).standing, 3000, "an unreadable faction leaves the baseline")
  end)
end)

test("Reputation capture: the unchanged path allocates nothing beyond the client's own reads", function()
  -- The double's C API answers are fresh tables, as the client's are; what is pinned is that the
  -- capture's own Lua adds nothing on top of the snapshot it takes.
  withCapture(function()
    for _ = 1, 10 do fire(72) end   -- warm every path
    local function kb(fn)
      collectgarbage("collect"); collectgarbage("stop")
      local before = collectgarbage("count")
      for _ = 1, 100 do fn() end
      local grew = collectgarbage("count") - before
      collectgarbage("restart")
      return grew
    end
    local reads = kb(function() NS.Compat.FactionSnapshot(72) end)
    local event = kb(function() Rep()._repEvent(nil, 72) end)
    assertTrue(event - reads < 0.5, ("the unchanged path allocated %.2f KB over 100 events beyond the reads' %.2f")
      :format(event - reads, reads))
  end)
end)

test("Reputation capture: Database:HistoryRow answers the store's row", function()
  withCapture(function(h, rows)
    gain(h, 72, 10)
    assertTrue(NS.Database:HistoryRow(1) == rows[1]); assertEqual(NS.Database:HistoryRow(2), nil)
  end)
end)

-- ── the drop lines (debug-logging-§8) ────────────────────────────────────────────────────────

test("Reputation capture: each drop reason writes its [Drop] line, only while logging", function()
  withCapture(function(h)
    local lines, saved, savedFlag = {}, NS.Debug, NS.State.debug
    NS.Debug = function(tag, fmt, ...) lines[#lines + 1] = "[" .. tag .. "] " .. fmt:format(...) end
    local ok, err = pcall(function()
      NS.State.debug = false
      fire(nil)
      assertEqual(#lines, 0, "nothing while logging is off")
      NS.State.debug = true
      with(M, { issecretvalue = function(v) return T.isSecret(v) end }, function() fire(T.secret(1)) end)
      fire(nil)
      fire(999)                                    -- unreadable
      h.faction(21, { name = "Booty Bay", reaction = 4, standing = 1500 }); fire(21)   -- unseeded
      fire(72)                                     -- unchanged
      NS.db.profile.settings.trackLedger = false; Rep():RefreshUpvalues()
      gain(h, 72, -5)                              -- ledger-off
      NS.db.profile.settings.trackLedger = true
      NS.db.profile.settings.excludedSources = { OTHER = true }; Rep():RefreshUpvalues()
      gain(h, 72, 5)                               -- source
      NS.db.profile.settings.excludedSources = {}; Rep():RefreshUpvalues()
      h.faction(72, { name = "Stormwind", kind = "renown", level = 1, earned = 0, threshold = 2500 }); fire(72)
      local f = h.factions[2590]; f.level = 9; fire(2590)
      h.faction(73, { name = "Para", reaction = 8, standing = 42000, paragon = 500 })
      fire(73); h.factions[73].paragon = 10; fire(73)
      gain(h, 21, 5)
    end)
    NS.Debug, NS.State.debug = saved, savedFlag
    if not ok then error(err, 0) end
    local want = {
      "[Drop] rep reason=secret", "[Drop] rep reason=no-id", "[Drop] rep 999 reason=unreadable",
      "[Drop] rep 21 reason=unseeded", "[Drop] rep 72 reason=unchanged", "[Drop] rep 72 reason=ledger-off",
      "[Drop] rep 72 reason=source", "[Drop] rep 72 reason=type-change", "[Drop] rep 2590 reason=renown-drop",
      "[Drop] rep 73 reason=unseeded", "[Drop] rep 73 reason=paragon-reset",
      "[Rep] Booty Bay +5 (Neutral) src=OTHER",
    }
    assertEqual(table.concat(lines, "\n"), table.concat(want, "\n"))
  end)
end)

-- ── Read side (rep-appearance spec §6.1) ─────────────────────────────────────────────────────

local TT_METHODS = { "SetOwner", "SetHyperlink", "SetItemByID", "AddLine", "AddDoubleLine", "Show", "Hide" }
local function recordTooltip(fn)
  local tt, calls, saved = M.GameTooltip, {}, {}
  for _, m in ipairs(TT_METHODS) do
    saved[m] = rawget(tt, m)
    tt[m] = function(_, a, b)
      calls[#calls + 1] = m .. "(" .. tostring(a) .. (m == "AddDoubleLine" and ("," .. tostring(b)) or "") .. ")"
      return tt
    end
  end
  local ok, err = pcall(fn)
  for _, m in ipairs(TT_METHODS) do tt[m] = saved[m] end
  if not ok then error(err, 0) end
  return table.concat(calls, " ")
end

test("Reputation rows: the History hover names the faction over its standing", function()
  local BT = NS.BrowserTable
  local row = BT:BuildRow()
  local rep = { kind = "REPUTATION", itemName = "Stormwind", itemSubType = "Honored", quantity = 250, dir = "IN" }
  BT:BindRow(row, { kind = "row", record = rep }, 1)
  local got = recordTooltip(function() row:GetScript("OnEnter")(row) end)
  assertTrue(got:find("AddLine(Stormwind)", 1, true) ~= nil, got)
  assertTrue(got:find("AddDoubleLine(Honored," .. NS.LedgerFormat.QtyText(rep) .. ")", 1, true) ~= nil, got)
  assertTrue(got:find("SetHyperlink", 1, true) == nil and got:find("SetItemByID", 1, true) == nil, got)
end)

test("Reputation rows: the Item cell is painted sem.info (A9); other rows keep their quality color", function()
  local fs = { SetText = function() end, SetTextColor = function(self, r, g, b) self.c = { r, g, b } end }
  NS.BrowserTable:PaintCell(fs, "item", { kind = "REPUTATION", itemName = "Stormwind", quantity = 1 })
  local ir, ig, ib = NS.SkinColor("sem.info")
  assertEqual(fs.c[1], ir); assertEqual(fs.c[2], ig); assertEqual(fs.c[3], ib)
  NS.BrowserTable:PaintCell(fs, "item", { kind = "APPEARANCE", itemName = "Hood", quality = 4, quantity = 1 })
  local qr, qg, qb = NS.QualityColor(4)
  assertEqual(fs.c[1], qr); assertEqual(fs.c[2], qg); assertEqual(fs.c[3], qb)
end)

test("Reputation rows: the row menu offers no Blacklist item and no Show in Timeline", function()
  local by = {}
  for _, it in ipairs(NS.BrowserTable:RowMenuItems({ kind = "REPUTATION", factionID = 72, itemName = "Stormwind",
    quantity = 1 })) do by[it.label] = it.enabled end
  assertFalse(by["Blacklist item"]); assertFalse(by["Show in Timeline"])
end)
