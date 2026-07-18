local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- Provider globals are injected per-test and torn down so cases don't leak into each other.
local function withGlobals(g, fn)
  local saved = {}
  for k, v in pairs(g) do saved[k] = _G[k]; _G[k] = v end
  local ok, err = pcall(fn)
  for k in pairs(g) do _G[k] = saved[k] end
  if not ok then error(err, 0) end
end

local LINK = "|cffa335ee|Hitem:210501:::::::::::::|h[Test]|h|r"

-- Auctionator stub: returns a price only for itemID 210501.
local function auctionatorStub(price)
  return { Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function(_, id) return id == 210501 and price or nil end,
    GetAuctionPriceByItemLink = function(_, _link) return price end,
  } } } }
end

test("AuctionPrice: Auctionator hit returns price + tag", function()
  withGlobals(auctionatorStub(1234), function()
    local p, tag = NS.AuctionPrice:Lookup(LINK, 210501)
    assertEqual(p, 1234)
    assertEqual(tag, "auctionator")
  end)
end)

test("AuctionPrice: falls through Auctionator(nil) to TSM", function()
  withGlobals({
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return nil end } } },
    TSM_API = {
      ToItemString = function(_link) return "i:210501" end,
      GetCustomPriceValue = function(key, itemStr)
        if key == "dbmarket" and itemStr == "i:210501" then return 5000 end
        return nil
      end,
    },
  }, function()
    local p, tag = NS.AuctionPrice:Lookup(LINK, 210501)
    assertEqual(p, 5000)
    assertEqual(tag, "tsm:dbmarket")
  end)
end)

test("AuctionPrice: falls through to OribosExchange", function()
  withGlobals({
    OEMarketInfo = function(_item, tbl) tbl.market = 777; tbl.region = 999 end,
  }, function()
    local p, tag = NS.AuctionPrice:Lookup(LINK, 210501)
    assertEqual(p, 777)
    assertEqual(tag, "oribos:market")
  end)
end)

test("AuctionPrice: no providers present returns nil, nil", function()
  local p, tag = NS.AuctionPrice:Lookup(LINK, 210501)
  assertEqual(p, nil)
  assertEqual(tag, nil)
end)

test("AuctionPrice: a provider that errors is skipped, not fatal", function()
  withGlobals({
    TSM_API = { ToItemString = function() error("boom") end, GetCustomPriceValue = function() end },
    OEMarketInfo = function(_item, tbl) tbl.market = 42 end,
  }, function()
    local p, tag = NS.AuctionPrice:Lookup(LINK, 210501)
    assertEqual(p, 42)
    assertEqual(tag, "oribos:market")
  end)
end)

test("AuctionPrice: disabled master switch returns nil", function()
  NS.db.global.settings.auction = { enabled = false }
  withGlobals(auctionatorStub(1234), function()
    local p = NS.AuctionPrice:Lookup(LINK, 210501)
    assertEqual(p, nil)
  end)
  NS.db.global.settings.auction = nil
end)

test("AuctionPrice: priority reorder puts TSM first", function()
  NS.db.global.settings.auction = {
    enabled = true, tsmSource = "dbmarket",
    auctionator = true, tsm = true, oribos = true,
    priorityAuctionator = 2, priorityTSM = 1, priorityOribos = 3,
  }
  withGlobals({
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 111 end } } },
    TSM_API = { ToItemString = function() return "i:1" end, GetCustomPriceValue = function() return 222 end },
  }, function()
    local p, tag = NS.AuctionPrice:Lookup(LINK, 210501)
    assertEqual(p, 222)
    assertEqual(tag, "tsm:dbmarket")
  end)
  NS.db.global.settings.auction = nil
end)
