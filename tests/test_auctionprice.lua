local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- Provider globals are injected per-test and torn down so cases don't leak into each other.
local function withGlobals(g, fn)
  local saved = {}
  for k, v in pairs(g) do saved[k] = _G[k]; _G[k] = v end
  local ok, err = pcall(fn)
  for k in pairs(g) do _G[k] = saved[k] end
  if not ok then error(err, 0) end
end

local LINK = "|cffa335ee|Hitem:210501:::::::::::::|h[Test]|h|r"

test("AuctionPrice: GatherAll collects all captured keys into a nested map", function()
  withGlobals({
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 48000 end } } },
    TSM_API = {
      ToItemString = function() return "i:1" end,
      GetCustomPriceValue = function(k) return ({ dbmarket=50000, dbminbuyout=47000,
        dbregionmarketavg=52000, dbregionminbuyoutavg=51500 })[k] end,
    },
    OEMarketInfo = function(_i, t) t.market = 51000; t.region = 53000 end,
  }, function()
    local m = NS.AuctionPrice:GatherAll(LINK, 210501)
    assertEqual(m.auctionator.minbuyout, 48000)
    assertEqual(m.tsm.dbmarket, 50000)
    assertEqual(m.tsm.dbregionminbuyoutavg, 51500)
    assertEqual(m.oribos.region, 53000)
  end)
end)

test("AuctionPrice: Pick walks the priority list, first present wins", function()
  local map = { tsm = { dbminbuyout = 47000 }, oribos = { market = 51000 } }
  -- default priority is tsm:dbmarket, auctionator:minbuyout, oribos:market, tsm:dbminbuyout, ...
  local price, tag = NS.AuctionPrice:Pick(map)
  assertEqual(price, 51000); assertEqual(tag, "oribos:market")  -- dbmarket/auctionator absent
end)

test("AuctionPrice: the shipped cascade reaches a non-default-collected key without the panel",
  function()
    -- LH-R-01. defaults/Global.lua used to ship only the 7 default-collected tags, so a fresh
    -- install's stored cascade could not name tsm:dbhistorical at all: `/lh set` on that key
    -- captured a price that Pick then refused to select, until opening the AH Price page ran
    -- ReconcilePriority and appended the missing four. The stored default now IS the one
    -- declaration, so the key is reachable with the panel never opened.
    local shipped = {}
    for i, tag in ipairs(NS.defaults.global.settings.auction.priority) do shipped[i] = tag end
    NS.db.global.settings.auction = { enabled = true, priority = shipped }
    local price, tag = NS.AuctionPrice:Pick({ tsm = { dbhistorical = 39000 } })
    assertEqual(price, 39000); assertEqual(tag, "tsm:dbhistorical")
    NS.db.global.settings.auction = nil
  end)

test("AuctionPrice: Pick respects a reordered priority list", function()
  NS.db.global.settings.auction = { enabled = true, priority = { "tsm:dbminbuyout", "oribos:market" } }
  local price, tag = NS.AuctionPrice:Pick({ tsm = { dbminbuyout = 47000 }, oribos = { market = 51000 } })
  assertEqual(price, 47000); assertEqual(tag, "tsm:dbminbuyout")
  NS.db.global.settings.auction = nil
end)

test("AuctionPrice: GatherAll only captures keys in the capture set", function()
  NS.db.global.settings.auction = { enabled = true, capture = { ["oribos:market"] = true } }
  withGlobals({ OEMarketInfo = function(_i, t) t.market = 51000; t.region = 53000 end,
                Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 48000 end } } } },
  function()
    local m = NS.AuctionPrice:GatherAll(LINK, 210501)
    assertEqual(m.oribos.market, 51000)
    assertEqual(m.auctionator, nil)       -- not in capture set
    assertEqual(m.oribos.region, nil)     -- not in capture set
  end)
  NS.db.global.settings.auction = nil
end)

test("AuctionPrice: GatherAll returns nil when nothing gathered / disabled", function()
  assertEqual(NS.AuctionPrice:GatherAll(LINK, 210501), nil)
  NS.db.global.settings.auction = { enabled = false }
  withGlobals({ OEMarketInfo = function(_i, t) t.market = 1 end }, function()
    assertEqual(NS.AuctionPrice:GatherAll(LINK, 210501), nil)
  end)
  NS.db.global.settings.auction = nil
end)

test("AuctionPrice: IsProviderAvailable reflects addon globals", function()
  assertFalse(NS.AuctionPrice:IsProviderAvailable("tsm"))
  withGlobals({ TSM_API = { GetCustomPriceValue = function() end, ToItemString = function() end } }, function()
    assertTrue(NS.AuctionPrice:IsProviderAvailable("tsm"))
  end)
  withGlobals({ OEMarketInfo = function() end }, function()
    assertTrue(NS.AuctionPrice:IsProviderAvailable("oribos"))
  end)
end)

test("AuctionPrice: ReconcilePriority appends missing tags and drops unknown", function()
  NS.db.global.settings.auction = { priority = { "tsm:dbmarket", "bogus:x" } }
  local p = NS.AuctionPrice:ReconcilePriority()
  assertEqual(p[1], "tsm:dbmarket")                 -- kept, order preserved
  local set = {}; for _, t in ipairs(p) do set[t] = true end
  assertEqual(set["bogus:x"], nil)                  -- unknown dropped
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do  -- every known tag present
    assertTrue(set[k.provider .. ":" .. k.key], "missing " .. k.provider .. ":" .. k.key)
  end
  NS.db.global.settings.auction = nil
end)

-- ── MovePriorityWithin: the drag's one write ──────────────────────────────────
--
-- Replaces the pairwise SwapPriorityTags the ▲▼ arrows drove. The panel drags now (options-ui-§18),
-- and the rule a drag has to satisfy that a swap never did is that a FOUR-POSITION move is ONE
-- mutation: a run of adjacent swaps writes and announces every intermediate order.

test("AuctionPrice: MovePriorityWithin splices a tag to an index, not a run of swaps", function()
  -- red under: reimplementing this as repeated adjacent swaps (the intermediate orders would still
  -- land on the same final array, so the ASSERTION that catches it is the four-position move below
  -- landing in one call rather than the end state).
  NS.db.global.settings.auction = { priority = { "a:1", "b:2", "c:3", "d:4", "e:5" } }
  local subset = { "a:1", "b:2", "c:3", "d:4", "e:5" }
  assertTrue(NS.AuctionPrice:MovePriorityWithin(subset, 1, 5))
  local p = NS.AuctionPrice:GetPriority()
  assertEqual(table.concat(p, ","), "b:2,c:3,d:4,e:5,a:1", "a four-position move, in one write")

  assertTrue(NS.AuctionPrice:MovePriorityWithin({ "b:2", "c:3", "d:4", "e:5", "a:1" }, 5, 2))
  assertEqual(table.concat(NS.AuctionPrice:GetPriority(), ","), "b:2,a:1,c:3,d:4,e:5",
    "and back up, four positions, in one more")
  NS.db.global.settings.auction = nil
end)

test("AuctionPrice: MovePriorityWithin leaves the tags OUTSIDE the subset exactly where they are",
  function()
    -- red under: rebuilding the whole array from the subset, or splicing against the array's own
    -- indices instead of the subset's slots. The panel drags within the COLLECTING partition only,
    -- and a reorder there must not silently re-rank a source you are not collecting.
    NS.db.global.settings.auction = { priority = { "a:1", "x:9", "b:2", "y:8", "c:3" } }
    assertTrue(NS.AuctionPrice:MovePriorityWithin({ "a:1", "b:2", "c:3" }, 3, 1))
    assertEqual(table.concat(NS.AuctionPrice:GetPriority(), ","), "c:3,x:9,a:1,y:8,b:2",
      "the subset re-lays into its OWN slots; x:9 and y:8 never move")
    NS.db.global.settings.auction = nil
  end)

test("AuctionPrice: MovePriorityWithin refuses a no-op and an out-of-range index", function()
  NS.db.global.settings.auction = { priority = { "a:1", "b:2", "c:3" } }
  local subset = { "a:1", "b:2", "c:3" }
  assertFalse(NS.AuctionPrice:MovePriorityWithin(subset, 2, 2), "a drag that landed where it started")
  assertFalse(NS.AuctionPrice:MovePriorityWithin(subset, 0, 2))
  assertFalse(NS.AuctionPrice:MovePriorityWithin(subset, 1, 9))
  assertFalse(NS.AuctionPrice:MovePriorityWithin(nil, 1, 2))
  assertEqual(table.concat(NS.AuctionPrice:GetPriority(), ","), "a:1,b:2,c:3", "nothing was written")
  NS.db.global.settings.auction = nil
end)

-- ── Pick: robustness against partial or absent price maps ─────────────────────

test("AuctionPrice: Pick on a record with no price map yields nothing", function()
  local price, tag = NS.AuctionPrice:Pick(nil)
  assertEqual(price, nil); assertEqual(tag, nil)
  assertEqual((NS.AuctionPrice:Pick("not a map")), nil)
  assertEqual((NS.AuctionPrice:Pick({})), nil, "an empty map is not a price of 0")
end)

test("AuctionPrice: Pick ignores a provider present but empty", function()
  local price, tag = NS.AuctionPrice:Pick({ tsm = {}, oribos = { market = 51000 } })
  assertEqual(price, 51000); assertEqual(tag, "oribos:market")
end)

test("AuctionPrice: Pick skips a tag the map does not carry", function()
  -- Every key the cascade names but the map lacks must be stepped over, not returned as nil.
  local price = NS.AuctionPrice:Pick({ tsm = { dbregionsaleavg = 900 } })
  assertEqual(price, 900, "the last-ranked key is still reachable")
end)

test("AuctionPrice: Pick still works when the stored priority list is empty", function()
  local saved = NS.db.global.settings.auction
  NS.db.global.settings.auction = { enabled = true, priority = {} }
  assertEqual((NS.AuctionPrice:Pick({ tsm = { dbmarket = 5 } })), nil,
    "an empty cascade selects nothing")
  NS.db.global.settings.auction = saved
end)

test("AuctionPrice: the default cascade prefers TSM market value over a min buyout", function()
  local saved = NS.db.global.settings.auction
  NS.db.global.settings.auction = nil
  local _, tag = NS.AuctionPrice:Pick({
    tsm = { dbmarket = 50000, dbminbuyout = 47000 },
    auctionator = { minbuyout = 48000 },
  })
  assertEqual(tag, "tsm:dbmarket", "the 'what's it worth' number leads the stock cascade")
  NS.db.global.settings.auction = saved
end)

-- ── GatherAll: third-party boundary ───────────────────────────────────────────

test("AuctionPrice: a provider that throws cannot break the capture", function()
  -- The pcall guard is the whole point of the third-party boundary.
  withGlobals({
    OEMarketInfo = function() error("Oribos blew up") end,
    TSM_API = { ToItemString = function() return "i:1" end,
                GetCustomPriceValue = function(k) return k == "dbmarket" and 50000 or nil end },
  }, function()
    local m = NS.AuctionPrice:GatherAll(LINK, 210501)
    assertEqual(m.tsm.dbmarket, 50000, "the healthy provider still reports")
    assertEqual(m.oribos, nil, "the throwing provider is simply absent")
  end)
end)

test("AuctionPrice: a provider returning zero or negative prices records nothing", function()
  withGlobals({
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 0 end } } },
    OEMarketInfo = function(_i, t) t.market = -1; t.region = 0 end,
  }, function()
    assertEqual(NS.AuctionPrice:GatherAll(LINK, 210501), nil,
      "a nonsense price must not become a stored value")
  end)
end)

test("AuctionPrice: GatherAll with no pricing addon installed returns nil", function()
  withGlobals({ Auctionator = nil, TSM_API = nil, OEMarketInfo = nil }, function()
    assertEqual(NS.AuctionPrice:GatherAll(LINK, 210501), nil)
  end)
end)

test("AuctionPrice: Auctionator falls back to the item link when there is no id", function()
  local sawLink
  withGlobals({
    Auctionator = { API = { v1 = {
      GetAuctionPriceByItemLink = function(_, link) sawLink = link; return 48000 end } } },
  }, function()
    local m = NS.AuctionPrice:GatherAll(LINK, nil)
    assertEqual(m.auctionator.minbuyout, 48000)
    assertEqual(sawLink, LINK)
  end)
end)

test("AuctionPrice: IsProviderAvailable is false for an unknown provider name", function()
  assertFalse(NS.AuctionPrice:IsProviderAvailable("nosuchaddon"))
  assertFalse(NS.AuctionPrice:IsProviderAvailable(nil))
end)

-- ── Priority list maintenance ─────────────────────────────────────────────────

test("AuctionPrice: ReconcilePriority de-duplicates without reordering the survivors", function()
  local saved = NS.db.global.settings.auction
  NS.db.global.settings.auction = { priority = { "oribos:market", "tsm:dbmarket", "oribos:market" } }
  local p = NS.AuctionPrice:ReconcilePriority()
  assertEqual(p[1], "oribos:market")
  assertEqual(p[2], "tsm:dbmarket")
  assertEqual(p[3] ~= "oribos:market", true, "the duplicate is dropped, the first wins")
  NS.db.global.settings.auction = saved
end)

test("AuctionPrice: ReconcilePriority always ends up covering every known key once", function()
  local saved = NS.db.global.settings.auction
  NS.db.global.settings.auction = { priority = { "tsm:dbmarket" } }
  local p, seen = NS.AuctionPrice:ReconcilePriority(), {}
  for _, tag in ipairs(p) do
    assertFalse(seen[tag], tag .. " appears twice after reconcile")
    seen[tag] = true
  end
  assertEqual(#p, #NS.Constants.AUCTION_KEYS)
  NS.db.global.settings.auction = saved
end)

test("AuctionPrice: ReconcilePriority rewrites in place, keeping the same table", function()
  -- The panel holds a reference to this array; replacing it would strand the UI on a stale list.
  local saved = NS.db.global.settings.auction
  NS.db.global.settings.auction = { priority = { "bogus:key" } }
  local before = NS.AuctionPrice:GetPriority()
  assertTrue(NS.AuctionPrice:ReconcilePriority() == before, "the array identity is preserved")
  NS.db.global.settings.auction = saved
end)

test("AuctionPrice: GetPriority creates the array on first use", function()
  local saved = NS.db.global.settings.auction
  NS.db.global.settings.auction = { enabled = true }
  assertEqual(type(NS.AuctionPrice:GetPriority()), "table")
  NS.db.global.settings.auction = saved
end)

test("AuctionPrice: MovePriorityWithin refuses a subset naming a tag the cascade does not carry",
  function()
    local saved = NS.db.global.settings.auction
    NS.db.global.settings.auction = { priority = { "tsm:dbmarket", "oribos:market" } }
    assertFalse(NS.AuctionPrice:MovePriorityWithin({ "tsm:dbmarket", "nosuch:tag" }, 1, 2))
    assertEqual(NS.AuctionPrice:GetPriority()[1], "tsm:dbmarket", "the list is left alone")
    NS.db.global.settings.auction = saved
  end)
