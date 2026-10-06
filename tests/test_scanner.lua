local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual = T.test, T.assertEqual

local function withBags(bags, fn)
  local m = T.mocks
  local savedB, savedS = m.__bags, m.__bagSlots
  m.__bags, m.__bagSlots = {}, {}
  for id, slots in pairs(bags) do
    m.__bags[id] = slots
    local n = 0; for s in pairs(slots) do if s > n then n = s end end
    m.__bagSlots[id] = n
  end
  fn()
  m.__bags, m.__bagSlots = savedB, savedS
end

test("Scanner: variants sum by itemID across slots and bags", function()
  withBags({
    [0] = { [1] = { itemID = 50, link = "|Hitem:50::::::::1:::1:100|h[Blade]|h", count = 1 },
            [3] = { itemID = 50, link = "|Hitem:50::::::::1:::1:200|h[Blade]|h", count = 1 } },
    [1] = { [2] = { itemID = 60, link = "|Hitem:60|h[Herb]|h", count = 20 } },
  }, function()
    local counts, links = NS.Scanner.ScanContainers({ 0, 1, 2 })
    assertEqual(counts[50], 2)
    assertEqual(counts[60], 20)
    assertEqual(links[60], "|Hitem:60|h[Herb]|h")
  end)
end)

test("Scanner: equipped slots and equipped bags", function()
  local m = T.mocks
  m.__inventory = { [1] = { itemID = 900, link = "L900" }, [31] = { itemID = 901, link = "L901" } }
  local counts = NS.Scanner.ScanEquipped()
  assertEqual(counts[900], 1)
  assertEqual(counts[901], 1)
  m.__inventory = {}
end)

test("Scanner: currencies split account-wide to warband", function()
  local m = T.mocks
  local saved = m.__currencyList
  m.__currencyList = {
    { header = true, name = "H" },
    { id = 3008, quantity = 40, accountWide = false },
    { id = 2032, quantity = 5, accountWide = true },
    { id = 1, quantity = 0, accountWide = false },
  }
  local char, wb = NS.Scanner.ScanCurrencies()
  assertEqual(char[3008], 40); assertEqual(char[2032], nil)
  assertEqual(wb[2032], 5)
  assertEqual(char[1], nil)   -- zero quantities are not holdings
  m.__currencyList = saved
end)

test("Scanner: money reads", function()
  T.mocks.__money, T.mocks.__warbandMoney = 12345, 999
  assertEqual(NS.Scanner.ReadMoney(), 12345)
  assertEqual(NS.Scanner.ReadWarbandMoney(), 999)
  T.mocks.__money, T.mocks.__warbandMoney = 0, 0
end)
