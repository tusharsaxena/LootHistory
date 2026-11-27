local _, NS = ...
NS.Appearance = NS.Appearance or {}
local App = NS.Appearance
local Perf = NS.Perf -- load-time upvalue (performance-§2); core/PerfSetup.lua loads above
local C = NS.Constants

-- Owns the appearance capture (rep/appearance spec docs/superpowers/specs/
-- 2026-11-27-rep-appearance-capture-design.md §2.2, §3.5): the two TRANSMOG_COLLECTION_SOURCE_ADDED /
-- _REMOVED rows on the shared bus, and an APPEARANCE History row per source collected (IN) or
-- removed (OUT, a refund). RETAIL ONLY BY DECLARATION (C.FEATURE.appearances, clients-§4): WoW
-- Forever exposes C_TransmogCollection, so the API's presence is not the gate. There the rows are
-- never declared and Enable stands nothing up.
--
-- Every SOURCE is a row (ruling A6), as Blizzard's own "added to your appearance collection" line
-- works; `newLook` marks the first collected source of its visual. Nothing is held, so no claim is
-- posted: an itemID claim would cancel the real item's holdings row. No price is stamped either:
-- the item row from the same loot already carries the value.

-- Hot-path upvalues, refreshed on Ka0s_LootHistory_SettingsChanged (events-frames-taint-§7).
local trackLedger, excludedSources = true, {}

-- The capture state (H4: cleared by ResetState, never unregistered by it). `seen[sourceID]` is the
-- last direction seen for that source and `seenAt[sourceID]` its GetTime(): the client can repeat
-- one change, and a repeat inside DUPLICATE_SPAN seconds (spec §3.5: 5 s) is the same change.
local seen, seenAt = {}, {}
local DUPLICATE_SPAN = 5

local function clear(t) for k in pairs(t) do t[k] = nil end end

function App.RefreshUpvalues()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  if not s then return end
  trackLedger = s.trackLedger ~= false
  excludedSources = s.excludedSources or {}
end

local function recordOn()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return s ~= nil and s.recordAppearances ~= false
end

-- The [Drop] line for a change not written. `id` is a plain number or nil (a secret never reaches
-- the format). Builds nothing while logging is off.
local function traceDrop(id, reason)
  if not (NS.State.debug and NS.Debug) then return end
  if id then NS.Debug("Drop", "appearance %s reason=%s", tostring(id), reason)
  else NS.Debug("Drop", "appearance reason=%s", reason) end
end

-- True when this source already moved this way inside the span; otherwise it is remembered.
local function duplicate(sourceID, dir)
  local now = GetTime()
  if seen[sourceID] == dir and now - (seenAt[sourceID] or -math.huge) <= DUPLICATE_SPAN then return true end
  seen[sourceID], seenAt[sourceID] = dir, now
  return false
end

-- The values are Compat.AppearanceSource's, passed as arguments so the row is the only table built.
local function buildRecord(sourceID, itemID, itemLink, name, quality, visualID, itemSubType, dir, source, detail,
                           newLook)
  local me = NS.Util.PlayerKey()
  local zone, subzone = NS.Zone()
  return {
    ts = time(), char = me, classFile = NS.Compat.PlayerClassFile(),
    holder = me, dir = dir, kind = C.Kind.APPEARANCE,
    sourceID = sourceID, appearanceID = visualID, itemID = itemID, itemLink = itemLink,
    itemName = name or ("Appearance " .. sourceID), quality = quality,
    itemType = C.APPEARANCE_TYPE, itemSubType = itemSubType, quantity = 1, newLook = newLook,
    -- The tie between a stamp and a collected look is circumstantial: never more than INFERRED.
    source = source, sourceDetail = detail, confidence = C.Confidence.INFERRED,
    zone = zone, mapID = NS.PlayerMapID(), subzone = subzone,
  }
end

-- One TRANSMOG_COLLECTION_SOURCE_ADDED / _REMOVED (spec §3.5 gate order). Minimum quality is not a
-- gate here (ruling A7): an appearance row is not an item loot record.
local function appearanceEvent(_, sourceID, dir)
  if NS.Compat.IsSecret(sourceID) then return traceDrop(nil, "secret") end
  if type(sourceID) ~= "number" then return traceDrop(nil, "no-id") end
  if duplicate(sourceID, dir) then return traceDrop(sourceID, "duplicate") end
  if dir == C.Dir.OUT and not trackLedger then return traceDrop(sourceID, "ledger-off") end
  local itemID, itemLink, name, quality, visualID, itemSubType = NS.Compat.AppearanceSource(sourceID)
  -- Peek, never Consume: Consume would spend the loot window's lines and answer FISHING in a cast.
  local source, detail = NS.Attribution:Peek()
  if excludedSources[source] then return traceDrop(sourceID, "source") end
  local newLook = dir == C.Dir.IN and visualID ~= nil and NS.Compat.IsNewLook(visualID, sourceID) or nil
  local record = buildRecord(sourceID, itemID, itemLink, name, quality, visualID, itemSubType, dir, source, detail,
    newLook)
  NS.Database:Add(record)
  if NS.State.debug and NS.Debug then
    NS.Debug("Appearance", "%s %s src=%s new=%s", dir == C.Dir.IN and "+" or "-", record.itemName, source,
      tostring(newLook == true))
  end
end

-- Shape A brackets (performance-§2): one exit each, so the dormant cost is one upvalue read, one
-- field read and one test. The body is a file-local function so the bracket wraps every early return.
function App:OnSourceAdded(_, sourceID)
  local t0 = Perf.on and debugprofilestop()
  appearanceEvent(self, sourceID, C.Dir.IN)
  if t0 then Perf.Note("appearanceEvent", debugprofilestop() - t0) end
end
function App:OnSourceRemoved(_, sourceID)
  local t0 = Perf.on and debugprofilestop()
  appearanceEvent(self, sourceID, C.Dir.OUT)
  if t0 then Perf.Note("appearanceEvent", debugprofilestop() - t0) end
end
App._appearanceEvent = appearanceEvent   -- the unbracketed body

-- The capture rows (core/Dispatch.lua), appended at FILE LOAD so their order is TOC order, and only
-- where the feature is declared (clients-§4: gated at registration, never registered and ignored).
-- Only the source id is read.
if C.FEATURE.appearances then
  NS.EventRow("Appearance", "bus", "TRANSMOG_COLLECTION_SOURCE_ADDED", function(_, sourceID)
    App:OnSourceAdded(nil, sourceID)
  end)
  NS.EventRow("Appearance", "bus", "TRANSMOG_COLLECTION_SOURCE_REMOVED", function(_, sourceID)
    App:OnSourceRemoved(nil, sourceID)
  end)
end

--- Every piece of capture state, cleared without unregistering: the duplicate maps. DisableCapture
--- runs it on the way down; the simulator at start and stop. Dot-declared (it reads no field) and
--- still callable with a colon.
function App.ResetState()
  clear(seen)
  clear(seenAt)
end

-- ── Lifecycle (the Reconciler's two-target shape, as modules/Reputation.lua) ─────────────────

--- `_settings` hears SettingsChanged for as long as the addon is up: every reason re-reads the
--- upvalues (excludedSources, trackLedger), and the switch's own reason or a profile event registers
--- or unregisters the rows to match settings.recordAppearances. The rows are live only while the
--- switch is on, so turning it off is a real unregister, never a draw gate (slash-commands-§7).
--- Where the feature is not declared (WoW Forever) there is nothing to stand up.
function App:Enable()
  if not (NS.addon and C.FEATURE.appearances) then return end
  if not self._settings then
    self._settings = NS.NewBusTarget()
    self._settings:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, reason)
      self:RefreshUpvalues()
      if reason ~= "appearance" and reason ~= "profile" then return end
      if recordOn() then self:EnableCapture() else self:DisableCapture() end
    end)
  end
  self:RefreshUpvalues()
  if recordOn() then self:EnableCapture() end
end

--- Register the two rows.
function App:EnableCapture()
  if self._enabled or not NS.addon then return end
  NS.RegisterRows("Appearance", NS.addon, "bus")
  self._enabled = true
end

--- Capture off (the switch unticked) while the module keeps listening for it coming back.
function App:DisableCapture()
  NS.UnregisterRows("Appearance")
  self:ResetState()
  self._enabled = nil
end

--- The full stand-down (slash-commands-§7): the rows and the settings listener. Called from
--- NS.StandDown.
function App:Disable()
  self:DisableCapture()
  if self._settings then self._settings:UnregisterAllMessages(); self._settings = nil end
end
