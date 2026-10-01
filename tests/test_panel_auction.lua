-- tests/test_panel_auction.lua — the AH Price table's repaint, every row (characterization).
--
-- Pinned before settings/Panel.lua's refreshAuctionTable, CCN 36 once lizard could see it, was
-- split into a partition, a per-row paint and the reorder registration (GI-LH-02). tests/test_panel.lua
-- pins the table's structure (one slot per source, the pooled host, the reorder controller, a drag);
-- this suite pins what each row SAYS and how it is colored, across three provider states, against
-- tests/panel_auction_golden.txt, generated from the pre-refactor code. Its own file because
-- tests/test_panel.lua sits just under layout-§1's 1000-line band.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual = T.test, T.assertEqual

local S = dofile("tests/panel_support.lua")
local clickTab, homeTab, tabAt = S.clickTab, S.homeTab, S.tabAt
local checkGolden = dofile("tests/golden.lua").file("tests/panel_auction_golden.txt")

local function num(v) return type(v) == "number" and ("%.3f"):format(v) or tostring(v) end
local function rgb(c) return c and (num(c[1]) .. "," .. num(c[2]) .. "," .. num(c[3])) or "-" end

local function fsText(f) return ("%q/%s"):format(tostring(f.__text), rgb(f.__color)) end

--- Render the AH Price tab under a provider-availability stub and a capture set, with the ⓘ
--- textures recording their tint, and describe every row and the reorder controller.
local function paint(available, capture)
  local ctx = NS.Panel.general
  local savedAvail = NS.AuctionPrice.IsProviderAvailable
  local savedCapture = NS.Schema:Get("settings.auction.capture")
  NS.AuctionPrice.IsProviderAvailable = function(_, prov) return available[prov] == true end
  NS.Schema:Set("settings.auction.capture", capture)
  local ok, out = pcall(function()
    clickTab(mocks.__subcategories["General"], ctx, tabAt("AH Price"))
    for _, r in ipairs(ctx._priRows) do
      rawset(r.info.tex, "SetVertexColor", function(self, a, b, c) self.__vc = { a, b, c }; return self end)
    end
    -- Repaint with the recorders in place: a second visit re-runs the same refresh.
    homeTab(ctx)
    clickTab(mocks.__subcategories["General"], ctx, tabAt("AH Price"))
    local lines = {}
    local list = ctx._priList
    lines[#lines + 1] = ("list boundary=%s rows=%d handles=%d"):format(tostring(list.boundary),
      #list.rows, #list.handles)
    for i, r in ipairs(ctx._priRows) do
      local p = r.info.__lastPoint and r.info:__lastPoint()
      lines[#lines + 1] = ("row%d tag=%s tick=%s addon=%s module=%s status=%s info.x=%s vc=%s check=%s disabled=%s ghost=%q")
        :format(i, tostring(r._tag), fsText(r.tick), fsText(r.addon), fsText(r.module), fsText(r.status),
          p and num(p.x) or "-", rgb(r.info.tex.__vc), tostring(r.check.value), tostring(r.check.disabled),
          tostring(list.rows[i] and list.rows[i].ghostText))
    end
    return table.concat(lines, "\n")
  end)
  NS.AuctionPrice.IsProviderAvailable = savedAvail
  NS.Schema:Set("settings.auction.capture", savedCapture)
  homeTab(ctx)
  if not ok then error(out, 0) end
  return out
end

test("AH table: two providers present, some sources collecting, one captured but absent", function()
  checkGolden("mixed", paint({ tsm = true, auctionator = true },
    { ["auctionator:minbuyout"] = true, ["tsm:dbmarket"] = true, ["oribos:market"] = true }))
end)

test("AH table: every provider present and nothing captured", function()
  checkGolden("present, idle", paint({ tsm = true, auctionator = true, oribos = true }, {}))
end)

test("AH table: no provider present", function()
  local got = paint({}, { ["tsm:dbmarket"] = true })
  checkGolden("absent", got)
  assertEqual(got:match("^list boundary=(%d+)"), "0", "nothing is draggable with no provider")
end)
