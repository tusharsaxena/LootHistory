local _, NS = ...
NS.Progress = NS.Progress or {}
local Progress = NS.Progress
local Perf = NS.Perf -- load-time upvalue (performance-§2); core/PerfSetup.lua loads above
local C = NS.Constants
-- The gain feed (#38): the sends test `GainFeed.on` (events-frames-taint-§7); modules/GainFeed.lua loads above.
local GainFeed = NS.GainFeed

-- The experience and profession skill-up observer (#38 D7, toast spec
-- docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §5.5). Neither is a record kind (D8):
-- this module writes no History row and holds no saved state, it only feeds GAIN. Its rows are
-- registered ONLY while the gain feed wants the kind (SyncCapture), so with no feed taking XP or
-- skill-ups the client delivers none of these events to the addon (slash-commands-§7, never a draw
-- gate).
--
--   ProgressXP     PLAYER_XP_UPDATE, PLAYER_LEVEL_UP                    while wants.XP
--   ProgressSkill  SKILL_LINES_CHANGED, CHAT_MSG_SKILL (a trigger only)  while wants.SKILL
--   ProgressRegen  PLAYER_REGEN_ENABLED                                 while either: the XP reseed
--                                                                        and the owed Forever scan
--
-- THE BASELINES LIVE IN MEMORY ONLY and are reused tables. The first read after a seed only seeds,
-- so a login, a /reload or a feed switched on mid-session sends nothing (the first skill-up is never
-- zero, nor the whole rank).

-- The XP baseline and the new read, reused. `seeded` is false until the first plain read.
local xpOld, xpNew = { seeded = false }, {}
-- The skill baselines: `cur` is filled by the client read, then copied into `prev`; one entry per
-- profession, made once.
local prev, cur = {}, {}

local function clear(t) for k in pairs(t) do t[k] = nil end end

-- ── Pure seam (unit-tested) ──────────────────────────────────────────────────────────────────

--- The experience gained between two reads { cur, max, level }, or nil and why. One level-up adds
--- what was left of the old level to the new level's progress; a jump of more than one level in one
--- event reads short (Known limitations).
--- @return number|nil delta
--- @return string|nil reason "unseeded" | "level-down" | "none"
function Progress.XPDelta(old, new)
  if not (old and new and old.level and new.level) then return nil, "unseeded" end
  local d
  if new.level > old.level then
    d = (old.max - old.cur) + new.cur
  elseif new.level == old.level then
    d = new.cur - old.cur
  else
    return nil, "level-down"
  end
  if d <= 0 then return nil, "none" end
  return d
end

-- ── Experience ───────────────────────────────────────────────────────────────────────────────

-- The [Drop] line for an experience or skill read not sent. `what` and `reason` are constants, so the
-- call builds nothing while logging is off.
local function traceDrop(what, reason)
  if NS.State.debug and NS.Debug then NS.Debug("Drop", "%s reason=%s", what, reason) end
end

-- source, sourceDetail, confidence (the M2 reputation rule): a fresh QUEST stamp is the turn-in's,
-- with its quest id; experience in combat is a kill's; anything else is OTHER. Peek, never Consume.
local function progressSource()
  local ST, CF = C.SourceType, C.Confidence
  local s, d, c = NS.Attribution:Peek()
  if s == ST.QUEST then return s, d, c end
  if NS.Compat.PlayerInCombat() then return ST.KILL, nil, CF.INFERRED end
  return ST.OTHER, nil, CF.INFERRED
end

local function remember(cur_, max, level)
  xpOld.cur, xpOld.max, xpOld.level, xpOld.seeded = cur_, max, level, true
end

local function sendXP(d)
  local g = GainFeed:Begin("XP")
  g.qty, g.level, g.levelUp, g.cur, g.max = d, xpNew.level, xpNew.level > xpOld.level, xpNew.cur, xpNew.max
  g.source, g.sourceDetail, g.confidence = progressSource()
  GainFeed:SendEvent(g)
end

local function xpEvent(self, unit)
  if unit ~= "player" then return end
  local xcur, xmax, level, capped = NS.Compat.PlayerXP()
  if not xcur then
    self._xpStale = true
    return traceDrop("xp", "unreadable")
  end
  xpNew.cur, xpNew.max, xpNew.level = xcur, xmax, level
  local d, why = Progress.XPDelta(xpOld.seeded and xpOld or nil, xpNew)
  if d and not capped and GainFeed.on and GainFeed.wants.XP then sendXP(d) end
  remember(xcur, xmax, level)
  self._xpStale = nil
  if not d then traceDrop("xp", why) elseif capped then traceDrop("xp", "capped") end
end

--- PLAYER_XP_UPDATE / PLAYER_LEVEL_UP. Shape-A bracket `xpEvent` (performance-§2): one exit, so the
--- dormant cost is one upvalue read, one field read and one test.
function Progress:OnXP(unit)
  local t0 = Perf.on and debugprofilestop()
  xpEvent(self, unit)
  if t0 then Perf.Note("xpEvent", debugprofilestop() - t0) end
end
Progress._xpEvent = xpEvent   -- the unbracketed body

--- The XP baseline from a plain read now; a secret or absent read leaves it unseeded.
local function seedXP()
  local xcur, xmax, level = NS.Compat.PlayerXP()
  if xcur then remember(xcur, xmax, level) else xpOld.seeded = false end
end

-- ── Skill-ups ────────────────────────────────────────────────────────────────────────────────

local function sendSkill(line, e, p)
  local g = GainFeed:Begin("SKILL")
  g.id, g.name, g.old, g.new, g.max, g.qty = line, e.name, p.rank, e.rank, e.max, e.rank - p.rank
  g.source, g.confidence = C.SourceType.OTHER, C.Confidence.INFERRED
  GainFeed:SendEvent(g)
end

-- Copy each read profession into `prev` (entries made once), sending each rise when seeded.
local function diffSkills(self)
  local send = self._skillSeeded and GainFeed.on and GainFeed.wants.SKILL
  for line, e in pairs(cur) do
    if e.rank then
      local p = prev[line]
      if send and p and p.rank and e.rank > p.rank then sendSkill(line, e, p) end
      if not p then p = {}; prev[line] = p end
      p.name, p.rank, p.max = e.name, e.rank, e.max
    end
  end
  self._skillSeeded = true
end

-- One read of the professions. Retail reads GetProfessions with no UI state; WoW Forever walks the
-- skill list (it expands headers, so never in combat: the scan is owed to the regen edge).
local function scanBody(self)
  for _, e in pairs(cur) do e.rank = nil end
  local got
  if NS.Compat.IsForever() then
    if NS.Compat.PlayerInCombat() then self._scanOwed = true; return end
    got = NS.Compat.ListSkillLines(cur)
  else
    got = NS.Compat.ProfessionSkills(cur)
  end
  self._scanOwed = nil
  if not got then return traceDrop("skill", "unreadable") end
  diffSkills(self)
end

--- Shape-A bracket `skillScan` (performance-§2).
local function scan()
  local t0 = Perf.on and debugprofilestop()
  scanBody(Progress)
  if t0 then Perf.Note("skillScan", debugprofilestop() - t0) end
end
Progress._scan = scan

--- SKILL_LINES_CHANGED / CHAT_MSG_SKILL: one scan half a second after a burst (NS.Coalesce, built on
--- first use; its deferral is canceled by NS.CancelDeferrals on a stand-down).
function Progress:RequestScan()
  self._coalesced = self._coalesced or NS.Coalesce(scan, 0.5)
  self._coalesced()
end

--- PLAYER_REGEN_ENABLED: a stale XP read reseeds, and a Forever scan put off by combat runs.
function Progress:OnRegen()
  if self._xpStale then seedXP(); self._xpStale = nil end
  if self._scanOwed then scan() end
end

-- The capture rows (core/Dispatch.lua), appended at FILE LOAD so their order is TOC order. The unit
-- filter is read in the handler: a "bus" row registers on the AceAddon target, which takes no unit.
NS.EventRow("ProgressXP", "bus", "PLAYER_XP_UPDATE", function(_, unit) Progress:OnXP(unit) end)
NS.EventRow("ProgressXP", "bus", "PLAYER_LEVEL_UP", function() Progress:OnXP("player") end)
NS.EventRow("ProgressSkill", "bus", "SKILL_LINES_CHANGED", function() Progress:RequestScan() end)
-- A trigger only: the chat payload is never read.
NS.EventRow("ProgressSkill", "bus", "CHAT_MSG_SKILL", function() Progress:RequestScan() end)
NS.EventRow("ProgressRegen", "bus", "PLAYER_REGEN_ENABLED", function() Progress:OnRegen() end)

-- ── Seeding, reset, lifecycle ────────────────────────────────────────────────────────────────

--- Both baselines from the client now (PLAYER_ENTERING_WORLD, a stand-up, the simulator's Prepare
--- and stop, whose reads the seam answers from the world while a session runs). `immediate` seeds
--- with the capture off. The skill baseline is marked unseeded and read once, so the next rise
--- diffs against it; a Forever read owed to combat seeds on the regen edge instead.
function Progress:Seed(immediate)
  if not (immediate or self._xpOn or self._skillOn) then return false end
  seedXP()
  self._skillSeeded = nil
  scanBody(self)
  return true
end

--- Every piece of capture state, cleared without unregistering: both baselines and the owed scan.
function Progress:ResetState()
  xpOld.seeded, xpOld.cur, xpOld.max, xpOld.level = false, nil, nil, nil
  clear(prev)
  clear(cur)
  self._skillSeeded, self._scanOwed, self._xpStale = nil, nil, nil
end

-- One owner's rows on or off to match `want`; answers whether it went on just now.
local function syncOwner(owner, want, on)
  if want and not on then
    NS.RegisterRows(owner, NS.addon, "bus")
    return true
  elseif not want and on then
    NS.UnregisterRows(owner)
  end
  return false
end

--- Register or unregister each owner to match GainFeed.wants.XP / .SKILL (and the regen row to
--- either). A kind switched on is seeded first, so its first event diffs against now. A no-op until
--- Enable has stood the module up.
function Progress:SyncCapture()
  if not (self._up and NS.addon) then return end
  local xp, skill = GainFeed.wants.XP == true, GainFeed.wants.SKILL == true
  if syncOwner("ProgressXP", xp, self._xpOn) then seedXP() end
  if syncOwner("ProgressSkill", skill, self._skillOn) then self._skillSeeded = nil; scanBody(self) end
  syncOwner("ProgressRegen", xp or skill, self._xpOn or self._skillOn)
  self._xpOn, self._skillOn = xp or nil, skill or nil
end

--- Stand-up (core/LifecycleSetup.lua, after the Appearance owner): the rows GainFeed's wants call for.
function Progress:Enable()
  if not NS.addon or self._up then return end
  self._up = true
  self:SyncCapture()
end

--- The full stand-down (slash-commands-§7): every row unregistered and every baseline dropped.
function Progress:Disable()
  NS.UnregisterRows("ProgressXP")
  NS.UnregisterRows("ProgressSkill")
  NS.UnregisterRows("ProgressRegen")
  self._xpOn, self._skillOn, self._up = nil, nil, nil
  self:ResetState()
end
