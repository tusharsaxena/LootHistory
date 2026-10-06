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
