local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- itemString field layout: itemID(1) : 11 fields : numBonusIDs(13) : bonusID1..N.
-- Fixtures below keep exactly 11 fields between itemID and the bonus count.

test("Export: BoundLabel maps tokens and nil", function()
  assertEqual(NS.Export:BoundLabel(nil), "Not Bound")
  assertEqual(NS.Export:BoundLabel("NONE"), "Not Bound")
  assertEqual(NS.Export:BoundLabel("BOE"), "Bind on Equip")
  assertEqual(NS.Export:BoundLabel("WARBAND"), "Warbound")
end)

test("Export: WowheadLink with bonus IDs", function()
  local link = "|cffa335ee|Hitem:210501:0:0:0:0:0:0:0:0:0:0:0:3:6652:1498:11144:::|h[X]|h|r"
  assertEqual(NS.Export:WowheadLink({ itemLink = link }),
    "https://www.wowhead.com/item=210501?bonus=6652:1498:11144")
end)

test("Export: WowheadLink without bonuses is bare", function()
  local link = "|cff9d9d9d|Hitem:6948:0:0:0:0:0:0:0:0:0:0:0:0:::|h[Hearthstone]|h|r"
  assertEqual(NS.Export:WowheadLink({ itemLink = link }), "https://www.wowhead.com/item=6948")
end)

test("Export: WowheadLink falls back to itemID, then empty", function()
  assertEqual(NS.Export:WowheadLink({ itemID = 12345 }), "https://www.wowhead.com/item=12345")
  assertEqual(NS.Export:WowheadLink({}), "")
end)

test("Export: CSV header order — ts,date,time first; computed + per-key auction cols; link last", function()
  local csv = NS.Export:CSV({})
  local header = csv:match("^(.-)\r\n")
  assertEqual(header,
    "ts,date,time,char,classFile,itemID,currencyID,itemName,quality,qualityRaw,itemLevel,bound," ..
    "vendorPrice,vendorPriceRaw,auctionPrice,auctionPriceRaw,value,valueRaw,auctionSource," ..
    "itemType,itemSubType,quantity,source,zone," ..
    "auc_auctionator_minbuyout,auc_tsm_dbmarket,auc_tsm_dbminbuyout,auc_tsm_dbregionmarketavg," ..
    "auc_tsm_dbregionminbuyoutavg,auc_tsm_dbhistorical,auc_tsm_dbrecent,auc_tsm_dbregionhistorical," ..
    "auc_tsm_dbregionsaleavg,auc_oribos_market,auc_oribos_region," ..
    "wowheadLink")
end)

test("Export: AICSV header keeps computed price cols but drops the raw auc_ columns", function()
  local header = NS.Export:AICSV({}):match("^(.-)\r\n")
  assertEqual(header,
    "ts,date,time,char,classFile,itemID,itemName,quality,qualityRaw,itemLevel,bound," ..
    "vendorPrice,vendorPriceRaw,auctionPrice,auctionPriceRaw,value,valueRaw,auctionSource," ..
    "itemType,itemSubType,quantity,source,zone," ..
    "wowheadLink")
  assertTrue(header:find("auc_", 1, true) == nil, "no raw auc_ columns in the AI CSV")
end)

test("Export: AICSV still emits the picked auction price/source, just not the raw sub-columns", function()
  local csv = NS.Export:AICSV({
    { vendorPrice = 10, auctionPrice = { tsm = { dbmarket = 500 } }, quantity = 1 },
  })
  assertTrue(csv:find("0g 5s 0c", 1, true) ~= nil, "picked auction price formatted")
  assertTrue(csv:find("tsm:dbmarket", 1, true) ~= nil, "auctionSource present")
  assertTrue(csv:find(",500,", 1, true) ~= nil, "auctionPriceRaw present")
end)

test("Export: CSV auction/value columns — auction present and vendor fallback", function()
  local withAuc = NS.Export:CSV({
    { vendorPrice = 10, auctionPrice = { tsm = { dbmarket = 500 } }, quantity = 1 },
  })
  assertTrue(withAuc:find("0g 5s 0c", 1, true) ~= nil, "auction 500c formatted")
  assertTrue(withAuc:find("tsm:dbmarket", 1, true) ~= nil, "auctionSource present")
  -- value falls back to vendor when no auction price
  local noAuc = NS.Export:CSV({ { vendorPrice = 10, quantity = 1 } })
  local dataLine = select(2, noAuc:match("^(.-)\r\n(.-)\r\n"))
  assertTrue(dataLine:find(",10,", 1, true) ~= nil or dataLine:find("10$", 1) ~= nil, "valueRaw == vendorPrice")
end)

test("Export: CSV emits picked price/tag + matching raw sub-columns for a nested auctionPrice map", function()
  local rec = {
    vendorPrice = 10,
    auctionPrice = {
      auctionator = { minbuyout = 400 },
      tsm = { dbmarket = 500, dbminbuyout = 450 },
      oribos = { market = 480 },
    },
    quantity = 1,
  }
  local csv = NS.Export:CSV({ rec })
  local dataLine = select(2, csv:match("^(.-)\r\n(.-)\r\n"))
  local cells = {}
  for cell in (dataLine .. ","):gmatch("(.-),") do cells[#cells + 1] = cell end
  -- header index: auctionPriceRaw=15 (1-based), auctionSource=17, auc_auctionator_minbuyout=21
  local header = csv:match("^(.-)\r\n")
  local hcells = {}
  for cell in (header .. ","):gmatch("(.-),") do hcells[#hcells + 1] = cell end
  local function cellFor(name)
    for i, h in ipairs(hcells) do if h == name then return cells[i] end end
    return nil
  end
  -- default priority (Constants.AUCTION_PRIORITY_DEFAULT) picks tsm:dbmarket first
  assertEqual(cellFor("auctionPriceRaw"), "500")
  assertEqual(cellFor("auctionSource"), "tsm:dbmarket")
  assertEqual(cellFor("auc_auctionator_minbuyout"), "400")
  assertEqual(cellFor("auc_tsm_dbmarket"), "500")
  assertEqual(cellFor("auc_tsm_dbminbuyout"), "450")
  assertEqual(cellFor("auc_oribos_market"), "480")
  assertEqual(cellFor("auc_tsm_dbregionmarketavg"), "")
end)

test("Export: CSV omits itemLink, sourceDetail, mapID, subzone, confidence", function()
  local header = NS.Export:CSV({}):match("^(.-)\r\n")
  for _, col in ipairs({ "itemLink", "sourceDetail", "mapID", "subzone", "confidence" }) do
    assertTrue(header:find(col, 1, true) == nil, col .. " must not be a column")
  end
end)

test("Export: CSV row emits friendly bound + quotes commas", function()
  local rec = { ts = 1000, itemName = "Sword, Big", bound = "BOP", itemID = 7 }
  local csv = NS.Export:CSV({ rec })
  assertTrue(csv:find('"Sword, Big"', 1, true) ~= nil, "quotes the comma field")
  assertTrue(csv:find("Bind on Pickup", 1, true) ~= nil, "friendly bound label")
end)

test("Export: CSV date + time columns are FormatDate/FormatClock(ts)", function()
  local csv = NS.Export:CSV({ { ts = 1000, itemID = 1 } })
  assertTrue(csv:find(NS.Util.FormatDate(1000), 1, true) ~= nil, "date column present")
  assertTrue(csv:find(NS.Util.FormatClock(1000), 1, true) ~= nil, "time column present")
end)

test("Export: CSV quality is human label beside numeric qualityRaw", function()
  local row = NS.Export:CSV({ { ts = 1, quality = 4, itemID = 1 } }):match("\r\n(.-)\r\n")
  assertTrue(row:find(NS.Compat.QualityLabel(4), 1, true) ~= nil, "human quality label present")
  assertTrue(row:find(",4,", 1, true) ~= nil, "numeric qualityRaw present")
end)

test("Export: CSV vendorPrice is 'Ng Ns Nc' beside raw copper", function()
  -- 12g 34s 56c = 123456 copper.
  local row = NS.Export:CSV({ { ts = 1, vendorPrice = 123456, itemID = 1 } }):match("\r\n(.-)\r\n")
  assertTrue(row:find("12g 34s 56c", 1, true) ~= nil, "formatted money present")
  assertTrue(row:find(",123456,", 1, true) ~= nil, "raw copper present")
end)

test("Export: CSV emits one header + one row per record, CRLF-terminated", function()
  local csv = NS.Export:CSV({ { ts = 1, itemID = 1 }, { ts = 2, itemID = 2 } })
  local n = select(2, csv:gsub("\r\n", "\r\n"))
  assertEqual(n, 3)  -- header + 2 rows, each CRLF-terminated
end)

-- ── Insights CSV (issue #15) ─────────────────────────────────────────────────────
-- Build a Stats result off a tiny known history so the analytics-CSV assertions are deterministic.
local function insightsStats()
  NS.db.global.blacklist = {}
  NS.db.global.history = {
    { ts = 1000, char = "A-Realm", itemID = 1, itemName = "Red, Potion",
      quality = 4, source = "KILL",      mapID = 10, zone = "Zone A", vendorPrice = 500, quantity = 1 },
    { ts = 2000, char = "A-Realm", itemID = 2, itemName = "Blue Cloak",
      quality = 2, source = "KILL",      mapID = 10, zone = "Zone A", vendorPrice = 100, quantity = 2 },
    { ts = 3000, char = "B-Realm", itemID = 3, itemName = "Green Ring",
      quality = 3, source = "CONTAINER", mapID = 20, zone = "Zone B", vendorPrice = 50,  quantity = 1 },
  }
  return NS.Database:Stats({})
end

test("Export: InsightsCSV header is Section,Label,Count,Value; CRLF-terminated", function()
  local csv = NS.Export:InsightsCSV(insightsStats())
  assertEqual(csv:match("^(.-)\r\n"), "Section,Label,Count,Value")
  assertTrue(csv:sub(-2) == "\r\n", "CRLF-terminated")
end)

test("Export: InsightsCSV summary reports the record count", function()
  local csv = NS.Export:InsightsCSV(insightsStats())
  assertTrue(csv:find("Summary,Records,3,", 1, true) ~= nil, "records row present")
end)

test("Export: InsightsCSV By Source uses labels + carries the value column", function()
  local csv = NS.Export:InsightsCSV(insightsStats())
  -- Kill has 2 records; value = 500*1 + 100*2 = 700 copper → "0g 7s 0c" (Export money format).
  assertTrue(csv:find("By Source,Kill,2,0g 7s 0c", 1, true) ~= nil, "source label + count + value")
  assertTrue(csv:find("By Source,Container,1,", 1, true) ~= nil, "second source present")
end)

test("Export: InsightsCSV quotes a label containing a comma", function()
  local csv = NS.Export:InsightsCSV(insightsStats())
  assertTrue(csv:find('"Red, Potion"', 1, true) ~= nil, "comma-bearing item name quoted")
end)

test("Export: InsightsCSV includes already-stored rows regardless of blacklist (point-in-time)", function()
  NS.db.global.blacklist = {}
  NS.db.global.history = {
    { ts = 1, char = "A-Realm", itemID = 1, itemName = "Kept",   quality = 3, source = "KILL", quantity = 1 },
    { ts = 2, char = "A-Realm", itemID = 2, itemName = "Blacklisted after capture", quality = 3, source = "KILL", quantity = 1 },
  }
  NS.db.global.blacklist = { [2] = true }
  local csv = NS.Export:InsightsCSV(NS.Database:Stats({}))
  assertTrue(csv:find("Summary,Records,2,", 1, true) ~= nil, "both stored records still present")
  NS.db.global.blacklist = {}
end)

test("Export: CSV emits a currency row with currencyID and blank item cells", function()
  local rows = { { ts = 1000, char = "A-R", currencyID = 3008, itemName = "Valorstones",
                   itemType = "Currency", itemSubType = "The War Within", quantity = 40,
                   source = "MPLUS", zone = "Z1" } }
  local csv = NS.Export:CSV(rows)
  local header = csv:match("^[^\r\n]+")
  assertTrue(header:find("currencyID", 1, true) ~= nil, "header has currencyID column")
  local dataLine = select(3, csv:find("\r\n(.-)\r\n"))
  assertTrue(csv:find(",3008,", 1, true) ~= nil or csv:find(",3008\r", 1, true) ~= nil, "currencyID value present")
  assertTrue(csv:find("Valorstones", 1, true) ~= nil, "currency name present")
  -- quality label must be blank (not "Poor") for the currency row
  assertTrue(csv:find(",Poor,", 1, true) == nil, "no misleading Poor quality for currency")
end)

test("Export: AICSV omits the currencyID column", function()
  local csv = NS.Export:AICSV({ { ts = 1, itemID = 1, itemName = "x", quantity = 1, source = "KILL" } })
  local header = csv:match("^[^\r\n]+")
  assertTrue(header:find("currencyID", 1, true) == nil, "AI CSV must not carry currencyID")
end)

test("Export: AICSV drops currency rows entirely (item-only, currency AI support deferred)", function()
  local rows = {
    { ts = 1, itemID = 1, itemName = "Red Sword", quantity = 1, source = "KILL" },
    { ts = 2, currencyID = 3008, itemName = "Valorstones", itemType = "Currency",
      quantity = 40, source = "MPLUS" },
  }
  local csv = NS.Export:AICSV(rows)
  local header = csv:match("^[^\r\n]+")
  assertTrue(header:find("currencyID", 1, true) == nil, "no currencyID column")
  assertTrue(csv:find("Red Sword", 1, true) ~= nil, "item row present")
  assertTrue(csv:find("Valorstones", 1, true) == nil, "currency row excluded")
end)

test("Export: InsightsCSV includes currency sections", function()
  local stats = {
    totals = { records = 0 },
    byCurrency = { Valorstones = 50 },
    currencySourceMatrix = { Valorstones = { MPLUS = 40, QUEST = 10 } },
    currencyByChar = { ["A-R"] = { char = "A-R", quantity = 43 } },
    currencyByDay = { ["2026-07-21"] = 53 },
    currencyTotals = { distinct = 1, events = 2, biggestHaul = { name = "Valorstones", quantity = 40 } },
  }
  local csv = NS.Export:InsightsCSV(stats)
  assertTrue(csv:find("Currency Collected,Valorstones,50", 1, true) ~= nil, "top currencies row")
  assertTrue(csv:find("Currency by Source,Valorstones / Mythic+,40", 1, true) ~= nil, "currency x source row")
  assertTrue(csv:find("Distinct currencies", 1, true) ~= nil, "summary distinct row")
  assertTrue(csv:find("Biggest haul", 1, true) ~= nil, "summary biggest-haul row")
end)

test("Export: AIPrompt embeds guideline URL, both CSV blocks, and framing", function()
  local p = NS.Export:AIPrompt("H1,H2\r\nx,y\r\n", "Section,Label\r\nSummary,Records\r\n", {})
  assertTrue(p:find("ai-export-guideline.md", 1, true) ~= nil, "references the guideline")
  assertTrue(p:find("=== HISTORY (CSV) ===", 1, true) ~= nil, "history marker")
  assertTrue(p:find("=== INSIGHTS (CSV) ===", 1, true) ~= nil, "insights marker")
  assertTrue(p:find("H1,H2", 1, true) ~= nil, "history csv embedded")
  assertTrue(p:find("Summary,Records", 1, true) ~= nil, "insights csv embedded")
  assertTrue(p:find("self-contained", 1, true) ~= nil, "self-contained rule stated")
  assertTrue(p:find("<date range>", 1, true) == nil, "no hand-title instruction (F2)")
  assertTrue(p:find("engine derives", 1, true) ~= nil, "states the engine derives the title (F2)")
  assertTrue(p:find("build_report.py", 1, true) ~= nil,
    "points code-capable agents at the shipped assembler")
  assertTrue(p:find("stale", 1, true) ~= nil,
    "warns that a guideline copy without the tool is a stale cache")
  assertTrue(p:find("web_fetch", 1, true) ~= nil,
    "forbids web_fetch of the template in the prompt itself")
  assertTrue(p:find("cache%-buster") ~= nil or p:find("curl", 1, true) ~= nil,
    "stale-cache recovery names a cache-bypassing fetch, not a plain re-fetch")
end)

test("Export: AIPrompt large-dataset note gated on opts.rows", function()
  local small = NS.Export:AIPrompt("h\r\n", "i\r\n", { rows = 10 })
  assertTrue(small:find("Current View", 1, true) == nil, "no note for small exports")
  local big = NS.Export:AIPrompt("h\r\n", "i\r\n", { rows = 99999 })
  assertTrue(big:find("Current View", 1, true) ~= nil, "note appears for large exports")
end)

test("Export: AIPrompt explains three price types and when to use value", function()
  local p = NS.Export:AIPrompt("h\r\n", "i\r\n", {})
  assertTrue(p:find("THREE prices", 1, true) ~= nil, "mentions THREE prices")
  assertTrue(p:find("vendor", 1, true) ~= nil, "explains vendor (v)")
  assertTrue(p:find("auction", 1, true) ~= nil, "explains auction (a)")
  assertTrue(p:find("Use VALUE", 1, true) ~= nil, "directs to use VALUE for worth figures")
  assertTrue(p:find("Σ(val", 1, true) ~= nil or p:find("aggregates", 1, true) ~= nil,
    "explains the aggregation method")
end)
