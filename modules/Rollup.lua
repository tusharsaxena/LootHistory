local _, NS = ...
-- luacheck: ignore 212/self
NS.Rollup = NS.Rollup or {}
local Rollup = NS.Rollup

-- The daily rollup writer (timeline-ledger spec §4.3). Two seams feed it, and the choice is the
-- plan's "Phase 2 contract":
--   * CLOSES come from NS.Holdings' write methods (NoteClose), because a close is a holdings fact
--     and those methods are the only place a total changes -- genesis, drift, moves, both sides of
--     a transfer and escrow credits included -- with nothing to know about the Reconciler.
--   * IN / OUT TALLIES come from NS.Database:OnWrite (OnWrite), because a row is where direction
--     lives and the hook hands over the quantity that CHANGED, so an amended row is counted once per
--     delta. RECORD_ADDED is not used for this: it is re-sent on every amend and is a repaint signal
--     only (Phase 2 plan, S2).
-- Both are O(1) per change. Pruning and the one-time seed run off the login deferral
-- (core/LootHistory.lua), never on an event.

local Ledger = NS.Ledger

function Rollup:Store()
  local g = NS.db and NS.db.global
  if not g then return {} end
  g.daily = g.daily or {}
  return g.daily
end

local function learnKey(self, key)
  if self._keys then self._keys[key] = true end
end

function Rollup:NoteClose(holder, key, ts, close)
  Ledger.RollupClose(self:Store(), Ledger.DayKey(ts), holder, key, close)
  learnKey(self, key)
end

function Rollup:NoteFlow(holder, key, ts, dir, qty)
  Ledger.RollupFlow(self:Store(), Ledger.DayKey(ts), holder, key, dir, qty)
  learnKey(self, key)
end

local function ledgerOn()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return not s or s.trackLedger ~= false
end

-- The Database write hook. `delta` is what this write changed (the whole quantity for a new row,
-- the added amount for an amend). A new row is tallied on its own day; an amend on today, because
-- the 60 s coalescing window may straddle midnight.
function Rollup:OnWrite(row, delta, isNew)
  if not (row and ledgerOn()) then return end
  local dir = NS.Util.RowDir(row)
  if dir == "MOVE" then return end
  local key, holder = Ledger.RowThingKey(row), NS.Util.RowHolder(row)
  if not (key and holder) then return end
  local ts = (isNew ~= false) and (row.ts or time()) or time()
  self:NoteFlow(holder, key, ts, dir, delta or 0)
end

function Rollup:ForgetHolder(holder)
  self._keys = nil
  return Ledger.ForgetHolderDaily(self:Store(), holder)
end

-- Every thing the rollup has a cell for. Built once per session from the store and kept current by
-- NoteClose/NoteFlow, so the Timeline's picker can offer a thing nobody holds any more without
-- walking every day on every keystroke.
function Rollup:Keys()
  if self._keys then return self._keys end
  local keys = {}
  for _, holders in pairs(self:Store()) do
    for _, things in pairs(holders) do
      for key in pairs(things) do keys[key] = true end
    end
  end
  self._keys = keys
  return keys
end

-- A write hook, not a bus subscription: it holds no event or message registration, so the
-- disabled-state survey has nothing of it to find, and the stand-down proof is behavioral (a row
-- written while stood down tallies nothing -- tests/test_rollup.lua, tests/test_disabled.lua).
function Rollup:Enable()
  if self._hook or not (NS.Database and NS.Database.OnWrite) then return end
  self._hook = NS.Database:OnWrite(function(row, delta, isNew) Rollup:OnWrite(row, delta, isNew) end)
end

function Rollup:Disable()
  if not self._hook then return end
  NS.Database:RemoveWriteHook(self._hook)
  self._hook = nil
end

-- ── Retention and the one-time seed (both run from the login deferral, core/LootHistory.lua) ──

local DAY = 86400

local function seedCell(daily, day, holder, key, n)
  local d = daily[day]
  local c = d and d[holder] and d[holder][key]
  if c and c.c ~= nil then return 0 end
  Ledger.RollupClose(daily, day, holder, key, n)
  return 1
end

local function seedHolder(daily, day, holder, e)
  local n = 0
  for id, row in pairs(e.items or {}) do
    local total = 0
    for _, k in pairs(row) do total = total + k end
    n = n + seedCell(daily, day, holder, "i:" .. id, total)
  end
  for id, q in pairs(e.currency or {}) do n = n + seedCell(daily, day, holder, "c:" .. id, q) end
  if e.money then n = n + seedCell(daily, day, holder, "g", e.money) end
  return n
end

-- Once per account. Holdings that existed before the rollup was written (the Phase 1/2 releases)
-- have no cell anywhere, and a thing that never changes again would never get one, so its line would
-- never draw. Today's close of everything held is the honest starting point; a close already written
-- today (a change this session) is the fresher fact and is never overwritten.
function Rollup:SeedOnce(ts)
  local g = NS.db and NS.db.global
  if not g or g.rollupSeeded then return 0 end
  local daily, day, n = self:Store(), Ledger.DayKey(ts), 0
  for holder, e in pairs(NS.Holdings:Store()) do n = n + seedHolder(daily, day, holder, e) end
  g.rollupSeeded = ts
  self._keys = nil
  if NS.State.debug and NS.Debug then NS.Debug("Rollup", "seeded %d cells", n) end
  return n
end

-- db.global.rollupRetentionDays: 0 = Always, a no-op. Days before the cutoff go, and each thing's
-- last close among them is carried onto the cutoff day (Ledger.PruneDaily), so a line still starts
-- from its last known value.
function Rollup:Prune(now)
  local days = NS.db and NS.db.global and NS.db.global.rollupRetentionDays
  if not days or days == 0 then
    if NS.State.debug and NS.Debug then NS.Debug("Rollup", "prune skipped: retention is Always") end
    return 0
  end
  local removed = Ledger.PruneDaily(self:Store(), Ledger.DayKey((now or time()) - days * DAY))
  if removed > 0 then self._keys = nil end
  if NS.State.debug and NS.Debug then NS.Debug("Rollup", "retention %dd: removed %d days", days, removed) end
  return removed
end
