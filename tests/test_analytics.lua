local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local ELL = "\226\128\166" -- "…"

-- ── _fitFontSize (headline shrink-to-fit) ───────────────────────────────────────────
test("Analytics._fitFontSize: fits within width returns base size", function()
  assertEqual(NS.Analytics._fitFontSize(50, 100, 24, 11), 24)
end)
test("Analytics._fitFontSize: overflow scales down proportionally", function()
  assertEqual(NS.Analytics._fitFontSize(200, 100, 24, 11), 12) -- 24 * 100/200
end)
test("Analytics._fitFontSize: clamps to the minimum floor", function()
  assertEqual(NS.Analytics._fitFontSize(1000, 100, 24, 11), 11)
end)
test("Analytics._fitFontSize: zero/negative width returns base", function()
  assertEqual(NS.Analytics._fitFontSize(0, 100, 24, 11), 24)
end)

-- ── paletteColor (standard categorical palette) ─────────────────────────────────────
test("Analytics.paletteColor: rank 1 is the first palette entry", function()
  local a = NS.Analytics.paletteColor(1)
  assertTrue(a[1] ~= nil and a[2] ~= nil and a[3] ~= nil, "returns an {r,g,b} triple")
end)
test("Analytics.paletteColor: adjacent ranks differ", function()
  local a, b = NS.Analytics.paletteColor(1), NS.Analytics.paletteColor(2)
  assertTrue(a[1] ~= b[1] or a[2] ~= b[2] or a[3] ~= b[3], "consecutive ranks must differ")
end)
test("Analytics.paletteColor: cycles past the palette length", function()
  local a, b = NS.Analytics.paletteColor(1), NS.Analytics.paletteColor(22)
  assertEqual(a[1], b[1]); assertEqual(a[2], b[2]); assertEqual(a[3], b[3]) -- 21-colour palette wraps
end)

-- ── _truncate ───────────────────────────────────────────────────────────────────────
test("Analytics._truncate: short text passes through", function()
  local s, t = NS.Analytics._truncate("Valorstones", 16)
  assertEqual(s, "Valorstones"); assertFalse(t)
end)
test("Analytics._truncate: long text is cut with an ellipsis", function()
  local s, t = NS.Analytics._truncate("Artisan Enchanter's Moxie", 16)
  assertEqual(s, "Artisan Enchant" .. ELL); assertTrue(t)
  assertEqual(#("Artisan Enchant"), 15) -- 15 glyphs + ellipsis == 16 visual chars
end)
test("Analytics._truncate: exactly maxChars passes through", function()
  local s, t = NS.Analytics._truncate("1234567890123456", 16)
  assertFalse(t); assertEqual(s, "1234567890123456")
end)

-- ── _charStackSegments (top-N + Other collapse) ─────────────────────────────────────
test("Analytics._charStackSegments: keeps all when within cap", function()
  local segs, total = NS.Analytics._charStackSegments({ KILL = 3, QUEST = 1 }, { "KILL", "QUEST" }, 9)
  assertEqual(total, 4)
  assertEqual(#segs, 2)
  assertEqual(segs[1].key, "KILL"); assertEqual(segs[2].key, "QUEST") -- catOrder order
end)
test("Analytics._charStackSegments: collapses overflow into __OTHER__", function()
  local mags, order = {}, {}
  for i = 1, 12 do local k = "C" .. i; mags[k] = 13 - i; order[#order + 1] = k end -- C1 biggest
  local segs, total = NS.Analytics._charStackSegments(mags, order, 9)
  assertEqual(total, 78) -- 12+11+...+1
  assertEqual(#segs, 9)  -- 8 kept + 1 OTHER
  assertEqual(segs[#segs].key, "__OTHER__")
  assertEqual(segs[#segs].mag, 4 + 3 + 2 + 1) -- the 4 smallest (C9..C12)
end)
