-- tests/test_appearance.lua — modules/Appearance.lua (rep/appearance spec §2.2, §3.5, §4, §5): the
-- TRANSMOG_COLLECTION_SOURCE_ADDED / _REMOVED capture path, its duplicate guard, the source read
-- and the switch's client gate. Every capture case runs on tests/mock_progress.lua's double with the
-- history, the duplicate maps and the settings it touches swapped out and put back. The capture
-- cases are Retail's (C.FEATURE.appearances); on WoW Forever they answer early and the client-shape
-- case below asserts the feature is absent there.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual = T.test, T.assertEqual

local PM = dofile("tests/mock_progress.lua")
local App = function() return NS.Appearance end
local LINK = "|cff1eff00|Hitem:2589::::::::|h[Linen Robe]|h|r"

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

--- Run `fn(h, rows)` with the double planted, two sources of visual 9 (77 collected by the event,
--- 78 not yet collected) and one of visual 10, an empty history and the settings at their defaults;
--- everything is put back. Retail only: WoW Forever has no appearance capture to run.
local function withCapture(fn)
  if T.forever then return end
  local h = PM.install(M)
  local s = NS.db.profile.settings
  local savedH = NS.db.global.history
  local savedS = { s.trackLedger, s.excludedSources, s.recordAppearances, s.qualityThreshold }
  local savedNow, savedTime = M.__now, rawget(M, "time")
  local A = NS.Attribution
  local ok, err = pcall(function()
    NS.db.global.history = {}
    s.trackLedger, s.excludedSources, s.recordAppearances = true, {}, true
    M.__now = 1000
    M.time = function() return 1700000000 end
    h.source(77, { itemID = 2589, name = "Linen Robe", quality = 2, visualID = 9, link = LINK, collected = true })
    h.source(78, { itemID = 2590, name = "Linen Robe of the Owl", quality = 2, visualID = 9 })
    h.source(80, { itemID = 2600, name = "Plate Helm", quality = 3, visualID = 10, collected = true })
    A:ResetContexts()
    App():ResetState()
    App():RefreshUpvalues()
    with(M.C_Item, { GetItemInfoInstant = function() return 2589, "Armor", "Cloth" end },
      function() fn(h, NS.db.global.history) end)
  end)
  App():ResetState()
  A:ResetContexts()
  NS.db.global.history = savedH
  s.trackLedger, s.excludedSources, s.recordAppearances, s.qualityThreshold = savedS[1], savedS[2], savedS[3], savedS[4]
  App():RefreshUpvalues()
  M.__now = savedNow
  rawset(M, "time", savedTime)
  h.uninstall()
  if not ok then error(err, 0) end
end

local function added(id) App():OnSourceAdded(nil, id) end
local function removed(id) App():OnSourceRemoved(nil, id) end

test("Appearance capture: a collected source writes one APPEARANCE row with every field", function()
  withCapture(function(_, rows)
    added(77)
    assertEqual(#rows, 1)
    local r = rows[1]
    assertEqual(r.ts, 1700000000); assertEqual(r.char, NS.Util.PlayerKey()); assertEqual(r.holder, r.char)
    assertEqual(r.classFile, NS.Compat.PlayerClassFile())
    assertEqual(r.dir, "IN"); assertEqual(r.kind, "APPEARANCE"); assertEqual(r.sourceID, 77)
    assertEqual(r.appearanceID, 9); assertEqual(r.itemID, 2589); assertEqual(r.itemLink, LINK)
    assertEqual(r.itemName, "Linen Robe"); assertEqual(r.quality, 2)
    assertEqual(r.itemType, "Appearance"); assertEqual(r.itemSubType, "Cloth"); assertEqual(r.quantity, 1)
    assertEqual(r.newLook, true, "no other source of visual 9 is collected")
    assertEqual(r.source, "OTHER"); assertEqual(r.confidence, "INFERRED")
    assertEqual(r.zone, (NS.Zone())); assertEqual(r.mapID, NS.PlayerMapID())
    for _, k in ipairs({ "currencyID", "bound", "vendorPrice", "auctionPrice", "itemLevel" }) do
      assertEqual(r[k], nil, k .. " is not set on an appearance row (A6: the item row carries the value)")
    end
  end)
end)

test("Appearance capture: newLook is set only for the first collected source of its visual", function()
  withCapture(function(h, rows)
    added(77)
    h.sources[78].collected = true
    added(78)
    assertEqual(#rows, 2, "A6: every source is a row")
    assertEqual(rows[1].newLook, true)
    assertEqual(rows[2].newLook, nil, "77 already shows visual 9: nil, never false")
  end)
end)

test("Appearance capture: a removed source writes OUT without newLook, and with trackLedger off it is dropped", function()
  withCapture(function(_, rows)
    removed(80)
    assertEqual(#rows, 1); assertEqual(rows[1].dir, "OUT"); assertEqual(rows[1].quantity, 1)
    assertEqual(rows[1].newLook, nil, "a removal is never a new look")
    NS.db.profile.settings.trackLedger = false
    App():RefreshUpvalues()
    removed(77)
    assertEqual(#rows, 1, "A2: a removal needs Track holdings and losses")
    added(78)
    assertEqual(#rows, 2, "a collection still records with trackLedger off"); assertEqual(rows[2].dir, "IN")
  end)
end)

test("Appearance capture: the same change inside 5 s is a duplicate; later, or the other way, it is not", function()
  withCapture(function(_, rows)
    added(77)
    M.__now = M.__now + 4
    added(77)
    assertEqual(#rows, 1, "repeated inside 5 s")
    removed(77)
    assertEqual(#rows, 2, "a refund right after is a real loss")
    M.__now = M.__now + 6
    removed(77)
    assertEqual(#rows, 3, "past the span the same direction is a new change")
  end)
end)

test("Appearance capture: an unreadable source still records under its id", function()
  withCapture(function(_, rows)
    added(4242)
    assertEqual(#rows, 1)
    assertEqual(rows[1].itemName, "Appearance 4242"); assertEqual(rows[1].itemID, nil)
    assertEqual(rows[1].appearanceID, nil); assertEqual(rows[1].newLook, nil, "no visual, no new-look read")
  end)
end)

test("Appearance capture: a loot window gives KILL through Peek, INFERRED, and is never spent", function()
  withCapture(function(_, rows)
    NS.State.lootWindow = { source = "KILL", detail = { npcID = 1 }, confidence = "CERTAIN", left = 2,
                            expires = M.__now + 10 }
    NS.State.fishingUntil = M.__now + 10
    added(77)
    assertEqual(rows[1].source, "KILL"); assertEqual(rows[1].sourceDetail.npcID, 1)
    assertEqual(rows[1].confidence, "INFERRED", "the tie between a stamp and a look is circumstantial")
    assertEqual(NS.State.lootWindow.left, 2, "Peek, never Consume")
    assertEqual(NS.State.fishingUntil, M.__now + 10)
    NS.State.fishingUntil = nil
  end)
end)

test("Appearance capture: a fresh vendor stamp gives VENDOR", function()
  withCapture(function(_, rows)
    NS.Attribution:Stamp("VENDOR", nil, "CERTAIN")
    added(77)
    assertEqual(rows[1].source, "VENDOR"); assertEqual(rows[1].confidence, "INFERRED")
  end)
end)

test("Appearance capture: a muted source drops the change", function()
  withCapture(function(_, rows)
    NS.db.profile.settings.excludedSources = { OTHER = true }
    App():RefreshUpvalues()
    added(77)
    assertEqual(#rows, 0, "A8: Record data from")
  end)
end)

test("Appearance capture: Minimum quality is not a gate (A7)", function()
  withCapture(function(_, rows)
    NS.db.profile.settings.qualityThreshold = 5
    added(77)
    assertEqual(#rows, 1, "a quality-2 source records under an Epic floor")
  end)
end)

test("Appearance capture: no claim is posted and the write raises nothing", function()
  -- An itemID claim would cancel the real item's holdings diff row (spec §6.3). RowThingKey answers
  -- nil for the kind (M2.1), so Database:Add's write hook passes it by.
  withCapture(function(_, rows)
    local R = NS.Reconciler
    local before = 0
    for _ in pairs(R.claims or {}) do before = before + 1 end
    added(77)
    local after = 0
    for _ in pairs(R.claims or {}) do after = after + 1 end
    assertEqual(#rows, 1); assertEqual(after, before, "no claim")
  end)
end)

test("Appearance capture: a secret or missing source id drops", function()
  withCapture(function(_, rows)
    with(M, { issecretvalue = function(v) return T.isSecret(v) end }, function()
      added(T.secret(77))
      added(nil)
      removed("77")
    end)
    assertEqual(#rows, 0)
  end)
end)

-- ── the drop lines (debug-logging-§8) ────────────────────────────────────────────────────────

test("Appearance capture: each drop reason writes its [Drop] line, only while logging", function()
  withCapture(function()
    local lines, saved, savedFlag = {}, NS.Debug, NS.State.debug
    NS.Debug = function(tag, fmt, ...) lines[#lines + 1] = "[" .. tag .. "] " .. fmt:format(...) end
    local ok, err = pcall(function()
      NS.State.debug = false
      added(nil)
      assertEqual(#lines, 0, "nothing while logging is off")
      NS.State.debug = true
      with(M, { issecretvalue = function(v) return T.isSecret(v) end }, function() added(T.secret(1)) end)
      added(nil)
      added(77)                                    -- written
      added(77)                                    -- duplicate
      NS.db.profile.settings.trackLedger = false; App():RefreshUpvalues()
      removed(80)                                  -- ledger-off
      NS.db.profile.settings.trackLedger = true
      NS.db.profile.settings.excludedSources = { OTHER = true }; App():RefreshUpvalues()
      added(78)                                    -- source
      NS.db.profile.settings.excludedSources = {}; App():RefreshUpvalues()
      removed(77)                                  -- written
    end)
    NS.Debug, NS.State.debug = saved, savedFlag
    if not ok then error(err, 0) end
    local want = {
      "[Drop] appearance reason=secret", "[Drop] appearance reason=no-id",
      "[Appearance] + Linen Robe src=OTHER new=true", "[Drop] appearance 77 reason=duplicate",
      "[Drop] appearance 80 reason=ledger-off", "[Drop] appearance 78 reason=source",
      "[Appearance] - Linen Robe src=OTHER new=false",
    }
    assertEqual(table.concat(lines, "\n"), table.concat(want, "\n"))
  end)
end)

-- ── the client gate (clients-§4, §6) ─────────────────────────────────────────────────────────

test("Appearance: the feature is Retail's, declared, and absent on WoW Forever", function()
  -- red under: the TRANSMOG rows declared on WoW Forever (C_TransmogCollection exists there, so an
  -- API-presence gate would register them), the switch drawn there, or a settings listener stood up
  -- for a feature the client does not have.
  local C = NS.Constants
  assertEqual(C.FEATURE.appearances, not T.forever)
  local rows = 0
  for _, row in ipairs(NS.EVENT_ROWS) do if row.owner == "Appearance" then rows = rows + 1 end end
  assertEqual(rows, T.forever and 0 or 2, "the TRANSMOG rows exist only where the feature is declared")
  local lib = M.LibStub("LibKa0s-Options-1.0")
  local row = NS.Schema:FindRow("settings.recordAppearances")
  assertEqual(lib.__ClientOk(row.clients), not T.forever, "the registry builds no widget on WoW Forever")
  -- Retail's listener and its switch are tests/test_dispatch.lua's case, with the addon up.
  if T.forever then
    NS.Appearance:Enable()
    assertEqual(NS.Appearance._settings, nil, "Enable stands nothing up on WoW Forever")
  end
end)
