local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local ELL = "\226\128\166" -- "…"
local A = NS.Analytics

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
  assertEqual(a[1], b[1]); assertEqual(a[2], b[2]); assertEqual(a[3], b[3]) -- 21-color palette wraps
end)

-- ── _tipText (hover text = full label + the value it encodes) ───────────────────────
test("Analytics._tipText: joins the full label and its value", function()
  assertEqual(NS.Analytics._tipText("Artisan Enchanter's Moxie", "412"),
    "Artisan Enchanter's Moxie:  412")
end)
test("Analytics._tipText: label alone when there is no value", function()
  assertEqual(NS.Analytics._tipText("Valorstones", nil), "Valorstones")
  assertEqual(NS.Analytics._tipText("Valorstones", ""), "Valorstones")
end)
test("Analytics._tipText: value alone when there is no label", function()
  assertEqual(NS.Analytics._tipText("", "17"), "17")
  assertEqual(NS.Analytics._tipText(nil, "17"), "17")
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

-- ── _charStackSegments: ordering and edge cases ────────────────────────────────

test("Analytics._charStackSegments: kept segments follow the global category order", function()
  -- Input arrives biggest-first, but the drawn order must be the chart's shared category order so
  -- one category occupies the same band on every character's row.
  local segs = A._charStackSegments({ c = 10, a = 5, b = 1 }, { "a", "b", "c" }, 5)
  assertEqual(segs[1].key, "a")
  assertEqual(segs[2].key, "b")
  assertEqual(segs[3].key, "c")
end)

test("Analytics._charStackSegments: __OTHER__ always draws last", function()
  local segs = A._charStackSegments({ a = 1, b = 2, c = 3, d = 4 }, { "d", "c", "b", "a" }, 3)
  assertEqual(#segs, 3)
  assertEqual(segs[#segs].key, "__OTHER__")
  assertEqual(segs[#segs].mag, 1 + 2, "the two smallest magnitudes are lumped together")
end)

test("Analytics._charStackSegments: a category outside the order sinks to the end", function()
  local segs = A._charStackSegments({ known = 1, stray = 9 }, { "known" }, 5)
  assertEqual(segs[1].key, "known")
  assertEqual(segs[2].key, "stray")
end)

test("Analytics._charStackSegments: the total counts every magnitude, kept or lumped", function()
  local segs, total = A._charStackSegments({ a = 1, b = 2, c = 3, d = 4 }, { "a", "b", "c", "d" }, 2)
  assertEqual(total, 10, "the total is of the raw input, not of the kept segments")
  local sum = 0
  for _, s in ipairs(segs) do sum = sum + s.mag end
  assertEqual(sum, total, "collapsing into __OTHER__ must not lose magnitude")
end)

test("Analytics._charStackSegments: zero and negative magnitudes are dropped", function()
  local segs, total = A._charStackSegments({ a = 5, b = 0, c = -3 }, { "a", "b", "c" }, 5)
  assertEqual(#segs, 1)
  assertEqual(segs[1].key, "a")
  assertEqual(total, 5)
end)

test("Analytics._charStackSegments: an empty character yields no segments", function()
  local segs, total = A._charStackSegments({}, { "a" }, 5)
  assertEqual(#segs, 0)
  assertEqual(total, 0)
end)

test("Analytics._charStackSegments: equal magnitudes break the tie by key, not by chance", function()
  -- table.sort is unstable, so an explicit tiebreak is what keeps the chart from flickering.
  local segs = A._charStackSegments({ b = 5, a = 5, c = 5 }, {}, 2)
  assertEqual(#segs, 2)
  assertEqual(segs[1].key, "a", "'a' wins the tie and is the one kept")
  assertEqual(segs[2].key, "__OTHER__")
end)

-- ── _buildCharStackRows ────────────────────────────────────────────────────────

local MATRIX = {
  ["Ka0z-Realm"] = { KILL = 30, AH = 10 },
  ["Alt-Realm"]  = { KILL = 5 },
}
local BYCHAR = {
  ["Ka0z-Realm"] = { classFile = "MAGE" },
  ["Alt-Realm"]  = { classFile = "WARRIOR" },
}
local ORDER = { "KILL", "AH" }
local function color() return { 1, 0, 0 } end
local function fmt(v) return tostring(v) end

test("Analytics._buildCharStackRows: rows run by total descending", function()
  local rows = A._buildCharStackRows(MATRIX, BYCHAR, ORDER, color, fmt)
  assertEqual(rows[1].label, "Ka0z")
  assertEqual(rows[2].label, "Alt")
end)

test("Analytics._buildCharStackRows: labels are shortened and class-colored", function()
  local rows = A._buildCharStackRows(MATRIX, BYCHAR, ORDER, color, fmt)
  assertEqual(rows[1].label, "Ka0z", "the realm is dropped from the bar label")
  assertEqual(#rows[1].labelColor, 3)
  assertFalse(rows[1].labelColor[1] == rows[2].labelColor[1],
    "a Mage and a Warrior must not share a bar-label color")
end)

test("Analytics._buildCharStackRows: the busiest character's bar is full width", function()
  local rows = A._buildCharStackRows(MATRIX, BYCHAR, ORDER, color, fmt)
  local top = 0
  for _, s in ipairs(rows[1].segments) do top = top + s.frac end
  assertTrue(math.abs(top - 1) < 1e-9, "the leading row fills the track")
end)

test("Analytics._buildCharStackRows: every row is scaled against that same maximum", function()
  local rows = A._buildCharStackRows(MATRIX, BYCHAR, ORDER, color, fmt)
  -- Alt has 5 of Ka0z's 40, so its bar must be an eighth as long — not full width.
  assertTrue(math.abs(rows[2].segments[1].frac - 5 / 40) < 1e-9)
end)

test("Analytics._buildCharStackRows: each segment's tip states the category and its value", function()
  local rows = A._buildCharStackRows(MATRIX, BYCHAR, ORDER, color, fmt,
    function(k) return NS.Constants.SourceLabel[k] end)
  assertEqual(rows[1].segments[1].tip, "Kill: 30")
  assertEqual(rows[1].segments[2].tip, "Auction House: 10")
end)

test("Analytics._buildCharStackRows: the row value is the character's total", function()
  local rows = A._buildCharStackRows(MATRIX, BYCHAR, ORDER, color, fmt)
  assertEqual(rows[1].value, "40")
  assertEqual(rows[2].value, "5")
end)

test("Analytics._buildCharStackRows: an unknown class falls back to neutral gray", function()
  local rows = A._buildCharStackRows({ ["Ghost-Realm"] = { KILL = 1 } }, {}, ORDER, color, fmt)
  assertEqual(rows[1].labelColor[1], 0.7)
end)

test("Analytics._buildCharStackRows: an empty matrix yields no rows", function()
  assertEqual(#A._buildCharStackRows({}, {}, ORDER, color, fmt), 0)
end)

-- ── Palette map ────────────────────────────────────────────────────────────────

test("Analytics._paletteMap: colors are assigned by list position", function()
  local m = A._paletteMap({ "Cloth", "Herb", "Ore" })
  assertEqual(m.Cloth[1], A.paletteColor(1)[1])
  assertEqual(m.Ore[1], A.paletteColor(3)[1])
end)

test("Analytics._paletteMap: a key outside the list has no color", function()
  assertEqual(A._paletteMap({ "Cloth" }).Ore, nil)
end)

test("Analytics._paletteMap: an empty or missing list maps nothing", function()
  assertEqual(next(A._paletteMap({})), nil)
  assertEqual(next(A._paletteMap(nil)), nil)
end)

test("Analytics._paletteMap: the same ordering yields the same colors across charts", function()
  -- This is what keeps a currency the same color in both currency charts.
  local a, b = A._paletteMap({ "x", "y" }), A._paletteMap({ "x", "y" })
  assertEqual(a.y[1], b.y[1]); assertEqual(a.y[2], b.y[2]); assertEqual(a.y[3], b.y[3])
end)

test("Analytics.paletteColor: every entry is a valid rgb triple", function()
  for rank = 1, 21 do
    local c = A.paletteColor(rank)
    assertEqual(#c, 3)
    for _, v in ipairs(c) do assertTrue(v >= 0 and v <= 1, "channels are 0..1 fractions") end
  end
end)

-- ── Color + label helpers ─────────────────────────────────────────────────────

test("Analytics._shortChar: drops the realm from a Name-Realm key", function()
  assertEqual(A._shortChar("Ka0z-Ravencrest"), "Ka0z")
  assertEqual(A._shortChar("Ka0z"), "Ka0z")
end)

test("Analytics._shortChar: a missing character reads '?'", function()
  assertEqual(A._shortChar(nil), "?")
end)

test("Analytics._classColor: a known class returns its class color", function()
  local c = A._classColor("MAGE")
  assertEqual(#c, 3)
  assertFalse(c[1] == 0.7 and c[2] == 0.7, "a known class must not use the fallback")
end)

test("Analytics._classColor: an unknown or missing class falls back to neutral gray", function()
  assertEqual(A._classColor("NOTACLASS")[1], 0.7)
  assertEqual(A._classColor(nil)[1], 0.7)
end)

test("Analytics._qualityColor: returns an rgb triple for a real quality", function()
  assertEqual(#A._qualityColor(4), 3)
end)

-- ── Money ──────────────────────────────────────────────────────────────────────

test("Analytics._money: zero and negative values read as a plain '0'", function()
  -- An empty string would leave the card blank; the chart must always state a number.
  assertEqual(A._money(0), "0")
  assertEqual(A._money(-5), "0")
  assertEqual(A._money(nil), "0")
end)

test("Analytics._money: a real amount renders its gold/silver/copper parts", function()
  assertEqual(A._money(1 * 10000 + 23 * 100 + 45), "1g 23s 45c")
end)

test("Analytics._money: zero-valued denominations are omitted", function()
  assertEqual(A._money(50000), "5g")
end)

-- ── Day-strip helpers ──────────────────────────────────────────────────────────

local DAY = 86400

test("Analytics._dayKeyList: spans first to last day inclusive", function()
  local now = os.time({ year = 2026, month = 3, day = 10, hour = 12 })
  local keys = A._dayKeyList(now, now + 2 * DAY)
  assertEqual(#keys, 3)
  assertEqual(keys[1], os.date("%Y-%m-%d", now))
  assertEqual(keys[3], os.date("%Y-%m-%d", now + 2 * DAY))
end)

test("Analytics._dayKeyList: a day with no loot still gets a (zero) bar", function()
  -- Gaps are included on purpose, so the strip reads as a calendar rather than a dense list.
  local now = os.time({ year = 2026, month = 3, day = 10, hour = 12 })
  assertEqual(#A._dayKeyList(now, now + 4 * DAY), 5)
end)

test("Analytics._dayKeyList: a single day yields exactly one key", function()
  local now = os.time({ year = 2026, month = 3, day = 10, hour = 12 })
  assertEqual(#A._dayKeyList(now, now + 3600), 1)
end)

test("Analytics._dayKeyList: caps a long range to the 60 most recent days", function()
  local now = os.time({ year = 2026, month = 3, day = 10, hour = 12 })
  local keys = A._dayKeyList(now - 200 * DAY, now)
  assertEqual(#keys, 60)
  assertEqual(keys[#keys], os.date("%Y-%m-%d", now), "the cap trims the OLD end, not the recent one")
end)

test("Analytics._dayKeyList: an empty history yields no keys", function()
  assertEqual(#A._dayKeyList(nil, nil), 0)
  assertEqual(#A._dayKeyList(os.time(), nil), 0)
end)

test("Analytics._shortDay: a day key shortens to M/D with no leading zeros", function()
  assertEqual(A._shortDay("2026-03-07"), "3/7")
  assertEqual(A._shortDay("2026-11-21"), "11/21")
end)

test("Analytics._shortDay: an unrecognized key passes through untouched", function()
  assertEqual(A._shortDay("Unknown"), "Unknown")
end)

-- ── sortedByCount ──────────────────────────────────────────────────────────────

test("Analytics._sortedByCount: orders by count descending", function()
  local rows = A._sortedByCount({ a = 1, b = 9, c = 5 })
  assertEqual(rows[1].key, "b"); assertEqual(rows[1].count, 9)
  assertEqual(rows[2].key, "c")
  assertEqual(rows[3].key, "a")
end)

test("Analytics._sortedByCount: equal counts break the tie by key ascending", function()
  local rows = A._sortedByCount({ zebra = 3, apple = 3, mango = 3 })
  assertEqual(rows[1].key, "apple")
  assertEqual(rows[2].key, "mango")
  assertEqual(rows[3].key, "zebra")
end)

test("Analytics._sortedByCount: an empty map yields no rows", function()
  assertEqual(#A._sortedByCount({}), 0)
end)

test("Analytics._sortedByCount: numeric keys sort without a type error", function()
  -- Quality buckets are keyed by number; the tiebreak stringifies rather than comparing raw keys.
  local rows = A._sortedByCount({ [4] = 2, [2] = 2 })
  assertEqual(#rows, 2)
  assertEqual(rows[1].key, 2)
end)

-- ── _truncate edges ────────────────────────────────────────────────────────────

test("Analytics._truncate: reports whether it cut", function()
  local _, cut = A._truncate("Short", 20)
  assertFalse(cut)
  local _, cut2 = A._truncate("A very long chart label indeed", 10)
  assertTrue(cut2)
end)

test("Analytics._truncate: a nil label becomes an empty string", function()
  assertEqual((A._truncate(nil, 5)), "")
end)

test("Analytics._truncate: the cut keeps maxChars-1 glyphs plus the ellipsis", function()
  local text = A._truncate("Explosive Sheep", 10)
  assertEqual(text, "Explosive" .. "\226\128\166")
  assertEqual(#text, 9 + 3, "9 kept characters + the 3-byte ellipsis")
end)
