local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local F = function() return NS.LedgerFormat end

test("LedgerFormat: glyph and color per direction, legacy reads as a gain", function()
  assertEqual(F().Glyph("OUT"), NS.Constants.DirGlyph.OUT)
  assertEqual(F().Glyph(nil), NS.Constants.DirGlyph.IN)
  local r, g, b = F().Color("OUT")
  assertEqual(r, 1.00); assertEqual(g, 0.33); assertEqual(b, 0.33)
end)

test("LedgerFormat: quantity text is signed; transfers unsigned; gold as money", function()
  assertEqual(F().QtyText({ itemID = 1, quantity = 3 }), "+3")
  assertEqual(F().QtyText({ itemID = 1, quantity = 3, dir = "OUT" }), "-3")
  assertEqual(F().QtyText({ itemID = 1, quantity = 3, dir = "MOVE" }), "3")
  assertEqual(F().QtyText({ kind = "GOLD", dir = "OUT", quantity = 10203 }), "-" .. NS.Util.FormatMoney(10203))
  assertEqual(F().SignedQty({ dir = "OUT", quantity = 4 }), -4)
end)

test("LedgerFormat: gold quantity is pale gold; others take the direction color", function()
  local r, _, b = F().QtyColor({ kind = "GOLD", dir = "OUT", quantity = 1 })
  assertEqual(r, NS.Constants.GOLD_RGB[1]); assertEqual(b, NS.Constants.GOLD_RGB[3])
  r = F().QtyColor({ itemID = 1, dir = "IN" })
  assertEqual(r, 0.35)
end)

test("LedgerFormat: signed count and money; zero is a gray dash", function()
  assertEqual(F().SignedCount(3), "|cff40ff40+3|r")
  assertEqual(F().SignedCount(-2), "|cffff4040-2|r")
  assertTrue(F().SignedCount(0):find("\226\128\148", 1, true) ~= nil)
  assertEqual(F().SignedMoney(-500), "|cffff4040-" .. NS.Util.FormatMoney(500) .. "|r")
end)

test("LedgerFormat: the warband holder reads as Warband", function()
  assertEqual(F().HolderLabel("§warband"), "Warband")
  assertEqual(F().HolderLabel("A-Realm"), "A-Realm")
end)
