-- tests/test_glyphs.lua — display text uses only characters every shipped skin face draws (LH-02 of
-- Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, owner item 5b, ruling D-19).
--
-- The owner's image-19: the History window's footer read "Database [] 1.6 MB" under Obsidian,
-- because the string carried U+2248 (written as an escape, so a grep missed it) and Expressway has no
-- such glyph. The guard is the kit's (testkit/glyphs.lua, kit revision 45): it reads every tracked
-- .lua file outside libs/ and tests/, decodes the escapes, and fails on a character outside the safe
-- set (ASCII plus what all fifteen shipped faces draw). Strings drawn in the mono face carry a
-- `glyph: mono` marker (core/Constants.lua's C.DirGlyph). The other cases pin the four sites D-19
-- changed, so the words stay what the owner reads.
--
-- After test_skin_literals; reads the checkout and the built General page, writes nothing.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local P = dofile("tests/panel_support.lua")
local clickTab, homeTab, tabAt = P.clickTab, P.homeTab, P.tabAt

test("glyphs: every display string uses only characters every shipped skin face draws", function()
  -- red under: "\226\137\136" (≈) back in a footer, "→" in a tooltip, or a mono string that lost
  -- its `glyph: mono` marker.
  T.assertDisplayGlyphs{ label = "LootHistory" }
end)

test("glyphs: the History window's footer reads \"Database ~1.6 MB\"", function()
  -- image-19's string. red under: the U+2248 escape back in modules/Browser.lua.
  local DB = NS.Database
  local real = DB.StorageStats
  DB.StorageStats = function() return { bytes = math.floor(1.6 * 1024 * 1024) } end
  local got
  local ok, err = pcall(NS.Browser.UpdateDbSize, { _dbFooter = { SetText = function(_, t) got = t end } })
  DB.StorageStats = real
  if not ok then error(err, 0) end
  assertEqual(got, "Database ~1.6 MB")
  T.assertGlyphSafe(got, "the footer")
end)

test("glyphs: the History tab's storage line reads \"Database size: ~\"", function()
  local ctx = NS.Panel.general
  local created = clickTab(mocks.__subcategories["General"], ctx, tabAt("History"))
  local stats
  for _, w in ipairs(created) do
    if w.type == "Label" and type(w.text) == "string" and w.text:find("Database size", 1, true) then
      stats = w.text
    end
  end
  homeTab(ctx)
  assertTrue(stats ~= nil, "the live storage readout must be drawn")
  assertTrue(stats:find("Database size: ~", 1, true) ~= nil, "the estimate reads ~: " .. stats)
  T.assertGlyphSafe(stats, "the storage line")
end)

test("glyphs: the Transfer glyph is \226\134\148, which the mono face draws", function()
  -- ⇄ (U+21C4) is in no shipped face, JetBrains Mono included: the owner's 160 MOVE rows drew a box.
  -- ↔ (U+2194) is in JetBrains Mono, the face the Direction cell's glyph pins (BrowserTable.lua).
  local C = NS.Constants
  assertEqual(C.DirGlyph.MOVE, "\226\134\148")
  assertEqual(C.DirGlyph.IN, "\226\150\178", "▲ unchanged")
  assertEqual(C.DirGlyph.OUT, "\226\150\188", "▼ unchanged")
end)

test("glyphs: the Quality column's tooltip reads \"Poor to Legendary\"", function()
  local desc
  for _, col in ipairs(NS.BrowserTable.COLUMNS or {}) do
    if col.key == "quality" then desc = col.desc end
  end
  assertTrue(desc ~= nil, "no Quality column description")
  assertEqual(desc, "Item quality (Poor to Legendary).")
  T.assertGlyphSafe(desc, "the Quality tooltip")
end)
