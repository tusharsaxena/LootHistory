local _, NS = ...
NS.GainFeed = NS.GainFeed or {}
local GainFeed = NS.GainFeed
local Perf = NS.Perf -- load-time upvalue (performance-§2); core/PerfSetup.lua loads above
local C = NS.Constants
local L = NS.Ledger

-- The pre-gate gain feed (#38 D6, toast spec docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md
-- §4): every gain the addon can observe, BEFORE the capture filters and the minimum quality, as one
-- bus message, NS.MSG.GAIN. This file is its ONLY sender (docs/message-bus.md): the observers
-- (Collector, Reputation, Appearance, Progress, the Reconciler's diff) fill the scratch payload
-- through Begin and hand it to Send, as Filters hands its changes to Database:FireHistoryChanged.
--
-- THE TAP IS ONE FIELD TEST WHILE NOTHING WANTS IT. `wants[kind]` says whether some enabled toast feed
-- (or, from M4, the farm session) takes that kind, and `on` whether any does. Every observer's tap is
-- `if GainFeed.on and GainFeed.wants.K then ... end` over a load-time upvalue of this table, so a feed
-- that is off costs one upvalue read, one field read and one test (events-frames-taint-§7).
--
-- THE FEED CLAIMS (T9). A chat gain that wrote no History row (a quality-gated item, a currency or
-- money line its switch dropped) posts a claim here, separate from the Reconciler's own `claims`;
-- the holdings diff's tap consumes it, so the same gain does not reach the feed twice.

-- Every payload field (toast spec §4.2). Begin clears each one, so no field outlives its send.
GainFeed.FIELDS = {
  "kind", "dir", "id", "qty", "link", "name", "quality", "icon", "classID",
  "source", "sourceDetail", "confidence", "origin", "recorded", "record", "gated", "sim",
  "label", "rank", "standing", "threshold", "repType", "accountWide",
  "itemID", "newLook", "level", "levelUp", "cur", "max", "old", "new",
}
local FIELDS = GainFeed.FIELDS

-- The one payload, reused for every send (no allocation on the hot path). Valid only during the
-- synchronous send: a receiver copies what it keeps.
local scratch = {}

-- The table identities never change (the taps hold this table, not these fields).
GainFeed.wants = { ITEM = false, GOLD = false, CURRENCY = false, REPUTATION = false, APPEARANCE = false,
                   XP = false, SKILL = false }
GainFeed.toastWants = { ITEM = false, GOLD = false, CURRENCY = false, REPUTATION = false, APPEARANCE = false,
                        XP = false, SKILL = false }
GainFeed.on = false
GainFeed.claims = {}

local function wipe(t) for k in pairs(t) do t[k] = nil end end

-- ── The payload and the send ─────────────────────────────────────────────────────────────────

--- The scratch payload, every field cleared, `kind` set, `dir` "IN" and `sim` the session flag.
function GainFeed.Begin(_, kind)
  for i = 1, #FIELDS do scratch[FIELDS[i]] = nil end
  scratch.kind, scratch.dir = kind, "IN"
  scratch.sim = (NS.Sim and NS.Sim:IsActive()) == true
  return scratch
end

-- The one [Gain] line per send. Builds nothing while logging is off.
local function traceGain(g)
  if not (NS.State.debug and NS.Debug) then return end
  NS.Debug("Gain", "%s %s x%d src=%s origin=%s rec=%s gated=%s", tostring(g.kind), tostring(g.dir),
    tonumber(g.qty) or 0, tostring(g.source), tostring(g.origin), tostring(g.recorded == true), tostring(g.gated))
end

local function send(g)
  traceGain(g)
  if NS.bus then NS.bus:SendMessage(NS.MSG.GAIN, g) end
end

--- Send `g` (the Begin payload) to every GAIN receiver. Shape-A bracket `gainSend` (performance-§2):
--- the receivers' work is inside it. `parent` is the bucket the send ran inside, the observed
--- containment (performance-§3): each observer passes its own bracket's key, the holdings diff's
--- tap passes `false` (the flush is not a bucket). While bracketed, `GainFeed.sending` is set, so
--- the toast feeds' `toastPaint` names `gainSend` as its parent on a push.
function GainFeed.Send(_, g, parent)
  local t0 = Perf.on and debugprofilestop()
  if t0 then GainFeed.sending = true end
  send(g)
  if t0 then
    GainFeed.sending = nil
    Perf.Note("gainSend", debugprofilestop() - t0, parent)
  end
end

-- ── The feed claims (T9, toast spec §4.4) ────────────────────────────────────────────────────

local function trackLedger()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return s ~= nil and s.trackLedger ~= false
end

--- A chat gain's send. A gain that wrote no row posts a feed claim while the ledger is on, so the
--- holdings diff's own sighting of it is not sent again. A recorded gain needs none: the
--- Reconciler's claim takes its delta before the diff's tap (modules/Reconciler.lua, COMMIT_STEPS).
function GainFeed:SendChat(g, parent)
  g.origin = "chat"
  g.recorded = g.record ~= nil
  if not g.recorded and trackLedger() and (g.id or g.kind == C.GainKind.GOLD) then
    L.PostClaim(self.claims, L.ThingKey(g.kind, g.id), g.qty, nil, GetTime())
  end
  self:Send(g, parent)
end

--- An event observer's send (reputation, appearances, experience, skill-ups): nothing is held, so
--- nothing reaches the holdings diff and no claim is posted. `parent` as for Send.
function GainFeed:SendEvent(g, parent)
  g.origin = "event"
  g.recorded = g.record ~= nil
  self:Send(g, parent)
end

--- Combat held the flush: the feed claims wait it out too (Ledger.HoldClaims). R:Flush calls this
--- beside its own L.HoldClaims.
function GainFeed:HoldClaims(since, now)
  L.HoldClaims(self.claims, since, now)
end

--- Expired feed claims dropped. Runs at the top of each flush, beside the Reconciler's own prune.
function GainFeed:PruneClaims(clock)
  L.PruneClaims(self.claims, clock)
end

-- The CURRENCY/ITEM payload fields the diff tap fills from the client.
local function fillThing(g, kind, id, link)
  g.id = id
  if kind == C.GainKind.ITEM then
    g.link = link
    local _, name, quality, classID = NS.Compat.GetItemInfo(link)
    g.name, g.quality, g.classID = name, quality, classID
  elseif kind == C.GainKind.CURRENCY then
    g.name, g.quality = NS.Compat.CurrencyName(id), NS.Compat.CurrencyQuality(id)
  end
end

--- The holdings diff's tap (toast spec §5.3): a positive own-holder delta of `key` the Reconciler is
--- about to write. The feed claims take what a chat line already sent; only the rest is sent, with
--- the diff's reason as its source. `link` is the item's, nil for the others.
function GainFeed:FromDiff(key, dlt, reason, clock, link)
  local kind, id = L.ParseThingKey(key)
  if not (kind and self.wants[kind]) then return end
  local rest = L.ConsumeClaim(self.claims, key, dlt, clock)
  if not rest or rest <= 0 then return end
  local g = self:Begin(kind)
  fillThing(g, kind, id, link)
  g.qty, g.source, g.origin = rest, reason, "diff"
  g.confidence = (reason == "OTHER" or reason == "UNTRACKED") and C.Confidence.INFERRED or C.Confidence.CERTAIN
  g.recorded = NS.Reconciler ~= nil and NS.Reconciler.RowAllowed ~= nil and NS.Reconciler:RowAllowed(kind, id) or false
  self:Send(g, false)
end

-- ── wants, Recompute and the farm entry (toast spec §4.3) ────────────────────────────────────

local function feedWants(feeds, leaf)
  for _, fid in ipairs(C.TOAST_FEEDS) do
    local f = feeds and feeds[fid]
    if f and f.enabled and f.kinds and f.kinds[leaf] then return true end
  end
  return false
end

-- Each observer that registers by `wants`, looked up at call time and presence-checked.
local function syncObservers()
  for _, key in ipairs({ "Reputation", "Appearance", "Progress" }) do
    local m = NS[key]
    if m and m.SyncCapture then m:SyncCapture() end
  end
  if NS.ToastBlizz and NS.ToastBlizz.Apply then NS.ToastBlizz:Apply() end
end

--- Rebuild `toastWants`, `wants` and `on` from the feeds' settings and the farm's set, then let each
--- observer register or unregister to match. Appearances are wanted only where they are a feature.
function GainFeed:Recompute()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  local feeds = s and s.toasts and s.toasts.feeds
  local farm, any = self._farm, false
  for leaf, kind in pairs(C.TOAST_KIND_KEYS) do
    local want = feedWants(feeds, leaf)
    if kind == C.GainKind.APPEARANCE and not C.FEATURE.appearances then want = false end
    self.toastWants[kind] = want
    local w = want or (farm ~= nil and farm[kind] == true and (kind ~= C.GainKind.APPEARANCE or C.FEATURE.appearances))
    self.wants[kind] = w
    any = any or w
  end
  self.on = any
  syncObservers()
end

--- The farm session's entry (#39): `kinds` is a set keyed by C.GainKind, or nil for none.
function GainFeed:SetFarm(kinds)
  self._farm = kinds
  self:Recompute()
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────────────────────

--- Stand-up: the settings listener (`toasts`, `profile`, `enabled`), then the first Recompute. Runs
--- before every observer's Enable (core/LifecycleSetup.lua), so `wants` is known before they register.
function GainFeed:Enable()
  if not NS.addon or self.__ev then return end
  self.__ev = NS.NewBusTarget()
  self.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, reason)
    if reason == "toasts" or reason == "profile" or reason == "enabled" then self:Recompute() end
  end)
  self:Recompute()
end

--- Stand-down: nothing wanted, the farm set and the claims dropped, the listener gone. It does not
--- call SyncCapture: the stand-down disables those modules itself.
function GainFeed:Disable()
  for k in pairs(self.wants) do self.wants[k] = false end
  for k in pairs(self.toastWants) do self.toastWants[k] = false end
  self.on, self._farm = false, nil
  wipe(self.claims)
  if self.__ev then
    self.__ev:UnregisterAllMessages()
    self.__ev = nil
  end
end

--- Session state cleared (the simulator's Prepare and stop): the feed claims.
function GainFeed:ResetState()
  wipe(self.claims)
end
