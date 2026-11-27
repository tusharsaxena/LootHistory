-- tests/test_progress.lua — modules/Progress.lua and its core/CompatGain.lua reads (toast spec
-- docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §3.1, §5.5, §13.2): the pure XP delta,
-- the experience and skill-up sends, the Forever skill walk, and the rows registered only while the
-- gain feed wants each kind. Every case stubs the Compat reads it needs and puts them back.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local P = function() return NS.Progress end
local Delta = function(...) return NS.Progress.XPDelta(...) end

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

local function xp(cur, max, level) return { cur = cur, max = max, level = level } end

-- ── XPDelta (pure) ───────────────────────────────────────────────────────────────────────────

test("Progress XPDelta: same level, one level up, two levels (short), level down, unseeded, zero", function()
  assertEqual(Delta(xp(100, 1000, 10), xp(350, 1000, 10)), 250)
  assertEqual(Delta(xp(900, 1000, 10), xp(50, 1100, 11)), 150, "(max - cur) + new cur")
  assertEqual(Delta(xp(900, 1000, 10), xp(50, 1200, 12)), 150, "a two-level jump reads short")
  local d, why = Delta(xp(900, 1000, 10), xp(50, 900, 9))
  assertEqual(d, nil); assertEqual(why, "level-down")
  d, why = Delta(nil, xp(50, 900, 9))
  assertEqual(d, nil); assertEqual(why, "unseeded")
  d, why = Delta(xp(50, 900, 9), xp(50, 900, 9))
  assertEqual(d, nil); assertEqual(why, "none")
end)

-- ── the harness ──────────────────────────────────────────────────────────────────────────────

--- Run `fn(state, sent)` with the Compat reads answering `state` (xp = { cur, max, level, capped },
--- skills = { [line] = { name, rank, max } }, forever, combat), the gain feed wanting every kind and
--- each GAIN copied into `sent`. Progress's state is reset before and after.
local function withProgress(fn)
  local C, g = NS.Compat, NS.GainFeed
  local state = { xp = { cur = 100, max = 1000, level = 10 }, skills = {}, forever = false, combat = false }
  local saved = { C.PlayerXP, C.ProfessionSkills, C.ListSkillLines, C.IsForever, C.PlayerInCombat }
  local savedWants, savedOn, savedSend = {}, g.on, NS.bus.SendMessage
  for k, v in pairs(g.wants) do savedWants[k] = v; g.wants[k] = true end
  g.on = true
  local sent = {}
  NS.bus.SendMessage = function(self, msg, a, ...)
    if msg == NS.MSG.GAIN then
      local c = {}
      for k, v in pairs(a) do c[k] = v end
      sent[#sent + 1] = c
      return
    end
    return savedSend(self, msg, a, ...)
  end
  local function fill(out)
    if not state.skills then return nil end
    for line, s in pairs(state.skills) do
      local e = out[line]
      if not e then e = {}; out[line] = e end
      e.name, e.rank, e.max = s.name, s.rank, s.max
    end
    return out
  end
  C.PlayerXP = function()
    local x = state.xp
    if not x then return nil end
    return x.cur, x.max, x.level, x.capped == true
  end
  C.ProfessionSkills, C.ListSkillLines = fill, function(out) state.walked = (state.walked or 0) + 1; return fill(out) end
  C.IsForever = function() return state.forever end
  C.PlayerInCombat = function() return state.combat end
  NS.Attribution:ResetContexts()
  P():ResetState()
  local ok, err = pcall(fn, state, sent)
  C.PlayerXP, C.ProfessionSkills, C.ListSkillLines, C.IsForever, C.PlayerInCombat =
    saved[1], saved[2], saved[3], saved[4], saved[5]
  for k, v in pairs(savedWants) do g.wants[k] = v end
  g.on, NS.bus.SendMessage = savedOn, savedSend
  P():ResetState()
  NS.Attribution:ResetContexts()
  if not ok then error(err, 0) end
end

-- ── experience ───────────────────────────────────────────────────────────────────────────────

test("Progress XP: the first read seeds; a gain sends XP with qty, level and the read", function()
  withProgress(function(state, sent)
    P():OnXP("player")
    assertEqual(#sent, 0, "the first read only seeds")
    state.xp.cur = 400
    P():OnXP("player")
    assertEqual(#sent, 1)
    local g = sent[1]
    assertEqual(g.kind, "XP"); assertEqual(g.qty, 300); assertEqual(g.level, 10); assertEqual(g.levelUp, false)
    assertEqual(g.cur, 400); assertEqual(g.max, 1000); assertEqual(g.origin, "event"); assertFalse(g.recorded)
    state.xp = { cur = 50, max = 1100, level = 11 }
    P():OnXP("player")
    assertEqual(sent[2].qty, 650); assertTrue(sent[2].levelUp)
    P():OnXP("target")
    assertEqual(#sent, 2, "another unit's event is not the player's")
  end)
end)

test("Progress XP: at the cap nothing is sent", function()
  withProgress(function(state, sent)
    P():OnXP("player")
    state.xp.cur, state.xp.capped = 500, true
    P():OnXP("player")
    assertEqual(#sent, 0)
  end)
end)

test("Progress XP: a secret read keeps the baseline and the regen edge reseeds it", function()
  withProgress(function(state, sent)
    P():OnXP("player")
    local plain = state.xp
    state.xp = nil
    P():OnXP("player")
    assertTrue(P()._xpStale, "marked stale")
    state.xp = { cur = 900, max = 1000, level = 10 }
    P():OnRegen()
    assertEqual(P()._xpStale, nil)
    state.xp.cur = 950
    P():OnXP("player")
    assertEqual(#sent, 1); assertEqual(sent[1].qty, 50, "diffs against the regen's reseed, not " .. plain.cur)
  end)
end)

test("Progress XP: the source is the quest's with its detail, a kill's in combat, else OTHER", function()
  withProgress(function(state, sent)
    P():OnXP("player")
    NS.Attribution:Stamp("QUEST", { questID = 42 }, "CERTAIN")
    state.xp.cur = 200; P():OnXP("player")
    NS.Attribution:ResetContexts()
    state.combat = true
    state.xp.cur = 300; P():OnXP("player")
    state.combat = false
    state.xp.cur = 400; P():OnXP("player")
    assertEqual(sent[1].source, "QUEST"); assertEqual(sent[1].sourceDetail.questID, 42)
    assertEqual(sent[1].confidence, "CERTAIN")
    assertEqual(sent[2].source, "KILL"); assertEqual(sent[2].confidence, "INFERRED")
    assertEqual(sent[3].source, "OTHER")
  end)
end)

-- ── skill-ups ────────────────────────────────────────────────────────────────────────────────

test("Progress skills: the first scan only seeds; a rise sends SKILL with old, new and max", function()
  withProgress(function(state, sent)
    state.skills = { [186] = { name = "Mining", rank = 100, max = 150 }, [185] = { name = "Cooking", rank = 5, max = 75 } }
    P()._scan()
    assertEqual(#sent, 0, "the first scan seeds (the first skill-up is never the whole rank)")
    state.skills[186].rank = 102
    P()._scan()
    assertEqual(#sent, 1)
    local g = sent[1]
    assertEqual(g.kind, "SKILL"); assertEqual(g.id, 186); assertEqual(g.name, "Mining")
    assertEqual(g.old, 100); assertEqual(g.new, 102); assertEqual(g.max, 150); assertEqual(g.qty, 2)
    P()._scan()
    assertEqual(#sent, 1, "no change, no send")
  end)
end)

test("Progress skills: on WoW Forever the walk waits out combat and runs on the regen edge", function()
  withProgress(function(state, sent)
    state.forever = true
    state.skills = { [186] = { name = "Mining", rank = 100, max = 150 } }
    P()._scan()
    state.skills[186].rank = 101
    state.combat = true
    local walked = state.walked
    P()._scan()
    assertEqual(state.walked, walked, "no walk in combat (it expands skill headers)")
    assertTrue(P()._scanOwed)
    state.combat = false
    P():OnRegen()
    assertEqual(#sent, 1); assertEqual(sent[1].new, 101)
    assertEqual(P()._scanOwed, nil)
  end)
end)

-- ── the Compat reads ─────────────────────────────────────────────────────────────────────────

test("CompatGain PlayerXP: plain reads, a secret answers nil, capped by IsXPUserDisabled or the max level", function()
  local C = NS.Compat
  local fields = { UnitXP = function() return 10 end, UnitXPMax = function() return 100 end,
    UnitLevel = function() return 5 end, IsXPUserDisabled = function() return false end,
    GetMaxPlayerLevel = function() return 60 end, issecretvalue = function(v) return T.isSecret(v) end }
  with(M, fields, function()
    local a, b, c, d = C.PlayerXP()
    assertEqual(table.concat({ a, b, c, tostring(d) }, ","), "10,100,5,false")
    with(M, { UnitLevel = function() return 60 end }, function() assertTrue(select(4, C.PlayerXP())) end)
    with(M, { IsXPUserDisabled = function() return true end }, function() assertTrue(select(4, C.PlayerXP())) end)
    with(M, { UnitXP = function() return T.secret(10) end }, function() assertEqual(C.PlayerXP(), nil) end)
    with(M, { UnitXPMax = NIL }, function() assertEqual(C.PlayerXP(), nil) end)
  end)
end)

test("CompatGain ListSkillLines: keeps profession lines, dedupes a pair on the parent, restores headers", function()
  local C, calls = NS.Compat, {}
  local rows = {
    { isHeader = true, isCollapsed = true, name = "Professions" },
    { skillID = 186, rank = 120, maxRank = 150, name = "Mining" },
    { skillID = 2575, parentSkillLineID = 186, rank = 125, maxRank = 150, name = "Mining (child)" },
    { skillID = 43, rank = 200, maxRank = 300, name = "Swords" },
  }
  local SI = {
    GetNumSkillLines = function() return #rows end,
    GetSkillLineInfo = function(i) return rows[i] end,
    ExpandSkillHeader = function(i) calls[#calls + 1] = "expand:" .. i end,
    CollapseSkillHeader = function(i) calls[#calls + 1] = "collapse:" .. i end,
  }
  with(M, { C_SkillInfo = SI }, function()
    local out = C.ListSkillLines({})
    assertEqual(out[43], nil, "a weapon skill is not a profession")
    assertEqual(out[2575], nil, "the child line is keyed on its parent")
    assertEqual(out[186].rank, 125, "the pair keeps the larger rank")
    assertEqual(out[186].max, 150)
    assertEqual(table.concat(calls, ","), "expand:1,collapse:1")
  end)
  with(M, { C_SkillInfo = NIL }, function() assertEqual(C.ListSkillLines({}), nil) end)
end)

test("CompatGain ProfessionSkills: each profession by its skill line, nil without the API", function()
  local C = NS.Compat
  local info = { [3] = { "Mining", 1, 120, 150, 0, 0, 186 }, [7] = { "Cooking", 1, 40, 75, 0, 0, 185 } }
  with(M, { GetProfessions = function() return 3, nil, nil, 7 end,
            GetProfessionInfo = function(i) return unpack(info[i]) end }, function()
    local out = C.ProfessionSkills({})
    assertEqual(out[186].rank, 120); assertEqual(out[186].name, "Mining"); assertEqual(out[185].max, 75)
  end)
  with(M, { GetProfessions = NIL }, function() assertEqual(C.ProfessionSkills({}), nil) end)
end)

test("CompatGain: alert suppression records and restores exactly the registered events, in order", function()
  local C, log = NS.Compat, {}
  local reg = { A = true, C = true }
  local AF = {
    IsEventRegistered = function(_, e) return reg[e] == true end,
    UnregisterEvent = function(_, e) reg[e] = nil; log[#log + 1] = "-" .. e end,
    RegisterEvent = function(_, e) reg[e] = true; log[#log + 1] = "+" .. e end,
  }
  with(M, { AlertFrame = AF }, function()
    local into = {}
    assertEqual(C.SuppressAlertEvents({ "A", "B", "C" }, into), 2)
    assertEqual(C.RestoreAlertEvents(into), 2)
    assertEqual(table.concat(log, ","), "-A,-C,+A,+C")
    assertEqual(#into, 0, "restore wipes the record")
  end)
  with(M, { AlertFrame = NIL }, function() assertEqual(C.SuppressAlertEvents({ "A" }, {}), 0) end)
end)

-- ── the rows and the lifecycle ───────────────────────────────────────────────────────────────

local function registered(owner)
  local n, total = 0, 0
  for _, row in ipairs(NS.EVENT_ROWS) do
    if row.owner == owner then
      total = total + 1
      if row.registered then n = n + 1 end
    end
  end
  return n, total
end

test("Progress: each owner's rows are registered only while the gain feed wants its kind", function()
  local p, g = P(), NS.GainFeed
  local savedUp, savedXP, savedSkill = p._up, p._xpOn, p._skillOn
  local savedWants = {}
  for k, v in pairs(g.wants) do savedWants[k] = v end
  local ok, err = pcall(function()
    NS.UnregisterRows("ProgressXP"); NS.UnregisterRows("ProgressSkill"); NS.UnregisterRows("ProgressRegen")
    p._up, p._xpOn, p._skillOn = true, nil, nil
    g.wants.XP, g.wants.SKILL = true, false
    p:SyncCapture()
    assertEqual(table.concat({ registered("ProgressXP") }, "/"), "2/2")
    assertEqual((registered("ProgressSkill")), 0)
    assertEqual(table.concat({ registered("ProgressRegen") }, "/"), "1/1", "the regen row rides with either kind")
    g.wants.XP, g.wants.SKILL = false, true
    p:SyncCapture()
    assertEqual((registered("ProgressXP")), 0)
    assertEqual(table.concat({ registered("ProgressSkill") }, "/"), "2/2")
    assertEqual((registered("ProgressRegen")), 1)
    g.wants.SKILL = false
    p:SyncCapture()
    assertEqual((registered("ProgressSkill")) + (registered("ProgressRegen")), 0, "nothing wanted, nothing registered")
    g.wants.XP = true
    p:SyncCapture()
    p:Disable()
    assertEqual((registered("ProgressXP")) + (registered("ProgressRegen")), 0, "Disable unregisters every row")
    assertEqual(p._up, nil)
  end)
  for k, v in pairs(savedWants) do g.wants[k] = v end
  NS.UnregisterRows("ProgressXP"); NS.UnregisterRows("ProgressSkill"); NS.UnregisterRows("ProgressRegen")
  -- Back to what the module had: its rows re-registered from the wants as they were.
  p._up, p._xpOn, p._skillOn = savedUp, nil, nil
  if savedUp and (savedXP or savedSkill) then p:SyncCapture() end
  if not ok then error(err, 0) end
end)
