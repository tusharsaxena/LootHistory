local _, NS = ...
NS.Reputation = NS.Reputation or {}
local Rep = NS.Reputation
local Perf = NS.Perf -- load-time upvalue (performance-§2); core/PerfSetup.lua loads above
-- The gain feed (#38): the tap tests `GainFeed.on` (events-frames-taint-§7); modules/GainFeed.lua loads above.
local GainFeed = NS.GainFeed
local C = NS.Constants

-- Owns the reputation capture (rep/appearance spec docs/superpowers/specs/
-- 2026-11-27-rep-appearance-capture-design.md §3.3-§3.4): one FACTION_STANDING_CHANGED row on the
-- shared bus, an in-memory baseline of every faction's progress, and a REPUTATION History row per
-- change, a gain or a loss. Nothing is held, so no claim is posted (an appearance is the same; a
-- claim on the Reconciler would cancel a real holdings row).
--
-- THE BASELINE LIVES IN MEMORY ONLY (ruling A4). It is seeded from a full faction walk
-- (Compat.ListFactions) a moment after the capture comes up, and again after every reset, so a login
-- or /reload writes no row: the first sight of a faction is seed-only. No SavedVariables store, so
-- no migration and no stale baseline across sessions.
--
-- PROGRESS IS ONE SCALAR BUILT FROM ABSOLUTE VALUES (ruling A5, Rep.Delta below): a base, guild or
-- friendship standing is absolute, a renown level's earned value is added up across a level-up, and
-- the cumulative paragon value rides on top at the cap. A loss across a rank boundary is a plain
-- negative difference, never "the progress inside the new rank".

-- Hot-path upvalues, refreshed on Ka0s_LootHistory_SettingsChanged (events-frames-taint-§7).
-- `recordRep` is the record switch: since the gain feed (#38, toast spec §5.4) the row is registered
-- while the switch is on OR the feed wants reputation, and the switch then gates only the History row.
local trackLedger, excludedSources, recordRep = true, {}, true

-- The capture state (H4: cleared by ResetState, never unregistered by it). `baseline[factionID]` is
-- { repType, rank, standing, threshold, paragon }, made once per faction and updated in place;
-- `last[factionID]` is { record, index, ts, dir, source }, the row a coalescing change grows.
-- `saved` is the real baseline set aside while a simulation runs (SuspendBaseline / RestoreBaseline);
-- `baseline` is reassigned then, so every reader below reads the upvalue at call time.
local baseline, last = {}, {}
local saved

local function clear(t) for k in pairs(t) do t[k] = nil end end

-- ── Pure seam (unit-tested) ──────────────────────────────────────────────────────────────────

--- The change between a faction's baseline and its new progress, or nil and why (a reseed). 0 means
--- unchanged. The new threshold is taken for symmetry with the baseline entry; only the old one is read. Renown cannot fall; a level-up takes the old level's threshold for every level it
--- crossed (one event rarely crosses more than one). A paragon value that fell is a rollover.
--- @return number|nil delta
--- @return string|nil reason "unseeded" | "type-change" | "paragon-reset" | "renown-drop"
function Rep.Delta(old, repType, rank, standing, _threshold, paragon)
  if old == nil then return nil, "unseeded" end
  if old.repType ~= repType then return nil, "type-change" end
  local para = (paragon or 0) - (old.paragon or 0)
  if para < 0 then return nil, "paragon-reset" end
  local d
  if repType == "renown" then
    local r0, r1 = old.rank or 0, rank or 0
    if r1 == r0 then
      d = standing - old.standing
    elseif r1 > r0 and old.threshold and old.threshold > 0 then
      d = (old.threshold - old.standing) + (r1 - r0 - 1) * old.threshold + standing
    else
      return nil, "renown-drop"
    end
  else
    d = standing - old.standing   -- base, guild, friendship: the standing is absolute
  end
  return d + para
end

-- ── Runtime path ─────────────────────────────────────────────────────────────────────────────

function Rep.RefreshUpvalues()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  if not s then return end
  trackLedger = s.trackLedger ~= false
  excludedSources = s.excludedSources or {}
  recordRep = s.recordReputation ~= false
end

local function recordOn()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return s ~= nil and s.recordReputation ~= false
end

-- Write `baseline[id]` from the new progress, making the entry only the first time.
local function remember(id, repType, rank, standing, threshold, paragon)
  local b = baseline[id]
  if not b then b = {}; baseline[id] = b end
  b.repType, b.rank, b.standing, b.threshold, b.paragon = repType, rank, standing, threshold, paragon
end

-- The [Drop] line for a change not written. `id` is a plain number or nil (a secret never reaches
-- the format). Builds nothing while logging is off.
local function traceDrop(id, reason)
  if not (NS.State.debug and NS.Debug) then return end
  if id then NS.Debug("Drop", "rep %s reason=%s", tostring(id), reason)
  else NS.Debug("Drop", "rep reason=%s", reason) end
end

-- source, sourceDetail, confidence (spec §4). A fresh QUEST stamp is the turn-in's, with its quest
-- id and CERTAIN; rep earned in combat is a kill's (no kill stamp exists before LOOT_OPENED); any
-- other stamp (a purchase, a mail) is not why a standing moved. Peek, never Consume: Consume would
-- spend the loot window's lines and answer FISHING inside a cast.
local function repSource()
  local ST, CF = C.SourceType, C.Confidence
  local s, d, c = NS.Attribution:Peek()
  if s == ST.QUEST then return s, d, c end
  if NS.Compat.PlayerInCombat() then return ST.KILL, nil, CF.INFERRED end
  return ST.OTHER, nil, CF.INFERRED
end

-- Grow the faction's last row when the change continues it: same direction and source, inside
-- C.REP_COALESCE seconds, and the row is still the one at that index (a simulation's session store
-- or a delete may have moved it). Answers true when it amended.
local function coalesce(factionID, dir, source, qty, now, label, rank, standing)
  local l = last[factionID]
  if not (l and l.dir == dir and l.source == source and now - l.ts <= C.REP_COALESCE) then return false end
  local r = NS.Database:HistoryRow(l.index)
  if r == nil or r ~= l.record then return false end
  r.itemSubType, r.rank, r.standing = label, rank, standing
  NS.Database:Amend(l.index, qty)
  l.ts = now
  return true
end

-- The values are Compat.FactionSnapshot's, passed as arguments so the row is the only table built.
local function buildRecord(factionID, name, repType, rank, standing, wide, label, dir, qty, now, source, detail,
                           confidence)
  local me = NS.Util.PlayerKey()
  local zone, subzone = NS.Zone()
  return {
    ts = now, char = me, classFile = NS.Compat.PlayerClassFile(),
    holder = me, dir = dir, kind = C.Kind.REPUTATION,   -- holder is the earning character (A1)
    factionID = factionID, itemName = name, itemType = C.REPUTATION_TYPE, itemSubType = label,
    quantity = qty, repType = repType, rank = rank, standing = standing,
    accountWide = wide == true or nil,
    source = source, sourceDetail = detail, confidence = confidence,
    zone = zone, mapID = NS.PlayerMapID(), subzone = subzone,
  }
end

-- The write half, past the delta: the ledger rule (A2), the source mute (A8), the record switch,
-- coalescing (A3), then one new row. Runs only for a real change, so its one allocation is the row
-- itself. Answers the row written or grown, else nil and the drop reason (the gain feed's `gated`).
local function writeChange(factionID, d, dir, name, repType, rank, standing, accountWide, label, source, detail,
                           confidence)
  if dir == C.Dir.OUT and not trackLedger then traceDrop(factionID, "ledger-off"); return nil, "ledger-off" end
  if excludedSources[source] then traceDrop(factionID, "source"); return nil, "source" end
  if not recordRep then traceDrop(factionID, "record-off"); return nil, "record-off" end
  local qty, now = math.abs(d), time()
  if coalesce(factionID, dir, source, qty, now, label, rank, standing) then return last[factionID].record end
  local record = buildRecord(factionID, name, repType, rank, standing, accountWide, label, dir, qty, now, source,
    detail, confidence)
  local index = NS.Database:Add(record)
  local l = last[factionID]
  if not l then l = {}; last[factionID] = l end
  l.record, l.index, l.ts, l.dir, l.source = record, index, now, dir, source
  if NS.State.debug and NS.Debug then
    NS.Debug("Rep", "%s %s%d (%s) src=%s", name, dir == C.Dir.IN and "+" or "-", qty, tostring(label), source)
  end
  return record
end

-- The reputation gain (toast spec §5.4): every real change, a gain or a loss, whatever the record
-- path decided (`record` the row written, `gated` the drop reason). The rep source rule is the row's.
local function feedRep(factionID, d, dir, name, repType, rank, standing, threshold, accountWide, label, source,
                       detail, confidence, record, gated)
  local g = GainFeed:Begin("REPUTATION")
  g.dir, g.id, g.qty, g.name = dir, factionID, math.abs(d), name
  g.label, g.rank, g.standing, g.threshold, g.repType, g.accountWide = label, rank, standing, threshold, repType,
    accountWide == true
  g.source, g.sourceDetail, g.confidence, g.record, g.gated = source, detail, confidence, record, gated
  GainFeed:SendEvent(g, "repEvent")
end

-- One FACTION_STANDING_CHANGED (spec §3.4 gate order). The unchanged and reseed paths allocate
-- nothing: a snapshot is values, the delta is pure, and the baseline entry already exists.
local function repEvent(_, factionID)
  if NS.Compat.IsSecret(factionID) then return traceDrop(nil, "secret") end
  if type(factionID) ~= "number" then return traceDrop(nil, "no-id") end
  local name, repType, rank, standing, threshold, paragon, accountWide, label = NS.Compat.FactionSnapshot(factionID)
  if not name then return traceDrop(factionID, "unreadable") end
  local d, why = Rep.Delta(baseline[factionID], repType, rank, standing, threshold, paragon)
  remember(factionID, repType, rank, standing, threshold, paragon)
  if d == nil then return traceDrop(factionID, why) end
  if d == 0 then return traceDrop(factionID, "unchanged") end
  local dir = d > 0 and C.Dir.IN or C.Dir.OUT
  local source, detail, confidence = repSource()
  local record, gated = writeChange(factionID, d, dir, name, repType, rank, standing, accountWide, label, source,
    detail, confidence)
  if GainFeed.on and GainFeed.wants.REPUTATION then
    feedRep(factionID, d, dir, name, repType, rank, standing, threshold, accountWide, label, source, detail,
      confidence, record, gated)
  end
end

-- Shape A bracket (performance-§2): one exit, so the dormant cost is one upvalue read, one field read
-- and one test. The body is a file-local function so the bracket wraps every early return.
function Rep:OnStandingChanged(_, factionID)
  local t0 = Perf.on and debugprofilestop()
  repEvent(self, factionID)
  if t0 then Perf.Note("repEvent", debugprofilestop() - t0) end
end
Rep._repEvent = repEvent   -- the unbracketed body

-- The capture row (core/Dispatch.lua), appended at FILE LOAD so its order is TOC order. Only the
-- faction id is read: the payload's other values are not on every client.
NS.EventRow("Reputation", "bus", "FACTION_STANDING_CHANGED", function(_, factionID)
  Rep:OnStandingChanged(nil, factionID)
end)

-- ── Seeding ──────────────────────────────────────────────────────────────────────────────────

-- The seed two seconds out (canceled by NS.CancelDeferrals on a stand-down), replacing any pending one.
local function armSeed(self)
  NS.CancelDeferral(self._seedTimer)
  self._seedTimer = NS.After(2, function()
    self._seedTimer = nil
    self:Seed()
  end)
end

--- Fill the baseline from a full faction walk. Out of combat only, unless `immediate`: the walk opens
--- and shuts the player's Reputation headers, which is UI state, so a seed due in combat re-arms
--- itself after C.REP_SEED_RETRY. `immediate` (the simulator's Prepare) also skips the deferral and
--- seeds with the capture off. Answers true when it walked.
function Rep:Seed(immediate)
  if not (immediate or self._enabled) then return false end
  if not immediate and NS.Compat.PlayerInCombat() then
    NS.CancelDeferral(self._seedTimer)
    self._seedTimer = NS.After(C.REP_SEED_RETRY, function()
      self._seedTimer = nil
      self:Seed()
    end)
    return false
  end
  clear(baseline)
  for _, f in ipairs(NS.Compat.ListFactions()) do
    remember(f.id, f.repType, f.rank, f.standing, f.threshold, f.paragon)
  end
  return true
end

--- Every piece of capture state, cleared without unregistering: the baseline (and one set aside by
--- SuspendBaseline), the coalescing map and the pending seed. DisableCapture runs it on the way down.
function Rep:ResetState()
  NS.CancelDeferral(self._seedTimer)
  self._seedTimer, self._seedWasPending = nil, nil
  saved = nil
  clear(baseline)
  clear(last)
end

--- The simulator's start: the real baseline is set aside whole and a fresh one takes its place (the
--- caller seeds it from the world), the coalescing map is cleared and a pending seed is canceled and
--- remembered. A real FACTION_STANDING_CHANGED always stops a session, so nothing real lands meanwhile.
function Rep:SuspendBaseline()
  if saved == nil then
    saved = baseline
    self._seedWasPending = self._seedTimer ~= nil
  end
  NS.CancelDeferral(self._seedTimer)
  self._seedTimer = nil
  baseline = {}
  clear(last)
end

--- The simulator's stop: the real baseline set aside at the start comes back as it was, so the real
--- change that stopped the session diffs against it and is written, and no faction walk runs (none at
--- a stand-down, and no baseline left empty by a stop in combat). With nothing set aside (the switch
--- was cycled mid-session) or a seed that was pending at the start, the seed is armed again.
function Rep:RestoreBaseline()
  local reseed = saved == nil or self._seedWasPending
  if saved ~= nil then baseline, saved = saved, nil else clear(baseline) end
  self._seedWasPending = nil
  clear(last)
  NS.CancelDeferral(self._seedTimer)
  self._seedTimer = nil
  if reseed and self._enabled then armSeed(self) end
end

--- The baseline entry for `factionID` (tests and the simulator's stop check), or nil.
function Rep.Baseline(_, factionID)
  return baseline[factionID]
end

-- ── Lifecycle (the Reconciler's two-target shape) ────────────────────────────────────────────

--- `_settings` hears SettingsChanged for as long as the addon is up: every reason re-reads the
--- upvalues (excludedSources, trackLedger, the switch), and the switch's own reason or a profile
--- event re-runs SyncCapture. The row is live only while the switch is on or the gain feed wants
--- reputation, so with both off it is a real unregister, never a draw gate (slash-commands-§7).
function Rep:Enable()
  if not NS.addon then return end
  if not self._settings then
    self._settings = NS.NewBusTarget()
    self._settings:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, reason)
      self:RefreshUpvalues()
      if reason ~= "reputation" and reason ~= "profile" then return end
      self:SyncCapture()
    end)
  end
  self:RefreshUpvalues()
  self:SyncCapture()
end

--- Register or unregister the row to match `recordReputation or GainFeed.wants.REPUTATION` (toast
--- spec §5.4, the amendment to M2 §5). A no-op until Enable has stood the module up; GainFeed's
--- Recompute calls it whenever what the feed wants changes.
function Rep:SyncCapture()
  if not self._settings then return end
  local want = recordOn() or GainFeed.wants.REPUTATION == true
  if want and not self._enabled then self:EnableCapture()
  elseif not want and self._enabled then self:DisableCapture() end
end

--- Register the row and arm the first seed (two seconds on, so the login data is ready; canceled by
--- NS.CancelDeferrals on a stand-down). A change that lands before it is seed-only.
function Rep:EnableCapture()
  if self._enabled or not NS.addon then return end
  NS.RegisterRows("Reputation", NS.addon, "bus")
  self._enabled = true
  armSeed(self)
end

--- Capture off (the switch unticked) while the module keeps listening for it coming back.
function Rep:DisableCapture()
  NS.UnregisterRows("Reputation")
  self:ResetState()
  self._enabled = nil
end

--- The full stand-down (slash-commands-§7): the row and the settings listener. Called from
--- NS.StandDown.
function Rep:Disable()
  self:DisableCapture()
  if self._settings then self._settings:UnregisterAllMessages(); self._settings = nil end
end
