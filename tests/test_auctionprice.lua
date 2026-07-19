local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual = T.test, T.assertEqual

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

test("AuctionPrice: MovePriority swaps adjacent entries and respects bounds", function()
  NS.db.global.settings.auction = { enabled = true, priority = { "a", "b", "c" } }
  local ok = NS.AuctionPrice:MovePriority(1, 1)
  assertEqual(ok, true)
  local p = NS.AuctionPrice:GetPriority()
  assertEqual(p[1], "b"); assertEqual(p[2], "a"); assertEqual(p[3], "c")

  assertEqual(NS.AuctionPrice:MovePriority(1, -1), false)  -- can't move first entry up
  assertEqual(NS.AuctionPrice:MovePriority(3, 1), false)   -- can't move last entry down
  assertEqual(NS.AuctionPrice:MovePriority(0, 1), false)   -- out of range low
  assertEqual(NS.AuctionPrice:MovePriority(4, -1), false)  -- out of range high
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
