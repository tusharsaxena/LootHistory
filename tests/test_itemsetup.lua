-- tests/test_itemsetup.lua — core/ItemSetup.lua, the LibKa0s-Item-1.0 seam.
--
-- What is asserted here is THE SEAM, not the library. The library's own suite covers the
-- primitives; a second copy of those cases here is the consumer-side duplication testing-§8
-- forbids. What only this repo can check is that the four primitives answer what the deleted Compat
-- shims answered, that the shims are gone, and — the case this addon exists to protect — that the
-- RESOLVER did not move and still guesses when the client has not cached an item.

local T = _G.LH_TEST
local NS = T.NS
local mocks = T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- The link shape the client hands out since patch 11.1.5: quality by NUMBER, `|cnIQ<n>:`.
-- LibKa0s-Item-1.0 minor 2 reads that rung first, so no palette is needed to answer it.
local EPIC_LINK =
  "|cnIQ4:|Hitem:258586::::::::80:250::5:3:10356:10355:1540:1:28:2462:::|h[Bloodfeather Chestguard]|h|r"

-- The pre-11.1.5 shape, colored by hex. A stored row captured before the patch still holds it.
local LEGACY_EPIC_LINK =
  "|cffa335ee|Hitem:258586::::::::80:250::5:3:10356:10355:1540:1:28:2462:::|h[Bloodfeather Chestguard]|h|r"

-- The hex rung is now the FALLBACK, reached only by a link with no `|cnIQ<n>` prefix, and it needs
-- a client whose ITEM_QUALITY_COLORS actually distinguishes qualities. tests/wow_mock.lua:95
-- answers a white swatch for EVERY index on purpose — the addon's coloring code only ever reads
-- r/g/b and a per-quality palette would pin cosmetics no suite cares about — but a reverse
-- hex→quality map built from that table maps one hex to one quality and answers nil for every real
-- link. So the real Retail palette is installed for the duration of those cases.
--
-- The map inside LibKa0s-Item-1.0 is built lazily, on the first hex-rung lookup, and (Item minor 2)
-- committed only when NON-EMPTY (libs/LibKa0s/Item.lua:55-75): a build that found nothing is
-- retried on the next call rather than pinned nil. A non-empty map is then cached for the life of
-- the Lua state, which is why this suite runs early in tests/run.lua's SUITES and why a poisoned
-- map would fail loudly here rather than silently somewhere else.
local RETAIL_QUALITY_HEX = {
  [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd",
  [4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80", [7] = "ff00ccff", [8] = "ff00ccff",
}

local function withQualityPalette(fn)
  local saved = mocks.ITEM_QUALITY_COLORS
  local palette = {}
  for q, hex in pairs(RETAIL_QUALITY_HEX) do palette[q] = { r = 1, g = 1, b = 1, hex = hex } end
  mocks.ITEM_QUALITY_COLORS = palette
  local ok, err = pcall(fn)
  mocks.ITEM_QUALITY_COLORS = saved
  if not ok then error(err, 0) end
end

-- A client that has not cached the item: C_Item.GetItemInfo answers nothing at all. The default
-- mock always answers a cached Epic (tests/wow_mock.lua:34), which never reaches the fallback this
-- addon's whole uncached policy lives in.
local function withUncachedClient(fn)
  local saved = mocks.C_Item
  local stub = {}
  for k, v in pairs(saved) do stub[k] = v end
  stub.GetItemInfo = function() return nil end
  mocks.C_Item = stub
  local ok, err = pcall(fn)
  mocks.C_Item = saved
  if not ok then error(err, 0) end
end

test("ItemSetup: the seam is published", function()
  assertTrue(type(NS.Item) == "table")
  assertTrue(type(NS.Item.ItemIDFromLink) == "function")
  assertTrue(type(NS.Item.QualityFromLink) == "function")
  assertTrue(type(NS.Item.QualityLabel) == "function")
  assertTrue(type(NS.Item.LoadItem) == "function")
end)

test("ItemSetup: the primitives answer what the deleted shims answered", function()
  -- Moved here whole from tests/test_compat.lua, where they pinned Compat.QualityLabel.
  assertEqual(NS.Item.QualityLabel(0), "Poor")
  assertEqual(NS.Item.QualityLabel(2), "Uncommon")
  assertEqual(NS.Item.QualityLabel(4), "Epic")
  assertEqual(NS.Item.QualityLabel(nil), "Poor")
  withQualityPalette(function()
    assertEqual(NS.Item.QualityFromLink(EPIC_LINK), 4)
  end)
end)

test("ItemSetup: this addon now HAS the id parser it lacked", function()
  -- ItemIDFromLink was BankLedger-only before the library.
  assertEqual(NS.Item.ItemIDFromLink(EPIC_LINK), 258586)
end)

test("ItemSetup: the moved shims are gone from Compat", function()
  -- A seam that leaves the old copy in place is a second answer nobody removed, and the next caller
  -- reaches for whichever one autocomplete offers first.
  assertEqual(NS.Compat.QualityLabel, nil)
  assertEqual(NS.Compat.QualityFromLink, nil)
  assertEqual(NS.Compat.LoadItem, nil)
end)

test("ItemSetup: the resolver did NOT move, and still guesses when uncached", function()
  -- This addon's policy, opposite to BankLedger's and deliberately so: a browsable capture log
  -- would rather show an approximate row than lose the drop. Only the primitive under the guess
  -- moved into the library; the guess itself stays in core/Compat.lua.
  assertTrue(type(NS.Compat.GetItemInfo) == "function")
  withQualityPalette(function()
    withUncachedClient(function()
      local _, name, quality = NS.Compat.GetItemInfo(EPIC_LINK)
      assertEqual(quality, 4, "the color fallback still answers for an uncached item")
      assertEqual(name, "Bloodfeather Chestguard", "and the bracketed name still stands in")
    end)
  end)
end)

test("ItemSetup: an uncached |cnIQ link answers its quality with no palette installed", function()
  -- Pins the Item minor 2 adoption: the number rung needs no ITEM_QUALITY_COLORS, so a cold-cache
  -- epic looted on a current client records Epic, not the Poor a nil quality would degrade to.
  withUncachedClient(function()
    local _, name, quality = NS.Compat.GetItemInfo(EPIC_LINK)
    assertEqual(quality, 4, "the |cnIQ4 prefix answers without the hex map")
    assertEqual(name, "Bloodfeather Chestguard")
  end)
end)

test("ItemSetup: a stored pre-11.1.5 |cff link still reads through the hex rung", function()
  withQualityPalette(function()
    assertEqual(NS.Item.QualityFromLink(LEGACY_EPIC_LINK), 4)
  end)
end)
