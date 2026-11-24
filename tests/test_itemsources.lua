-- tests/test_itemsources.lua — the History table's item tooltip, and what ForeverDB adds to it.
--
-- SF-LH-02 (Ka0sAddonsCommonTasks docs/2026-11-25-SEEDS_AND_FOREVERDB, LibKa0s#105). The first
-- case is the CHARACTERIZATION written before the feature: an item row's hover, call for call, as
-- it stands with no ForeverDB. Every case after it must leave that sequence alone wherever the
-- feature is off, absent or on Retail.

local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual = T.test, T.assertEqual

local function dataEntry(rec) return { kind = "row", record = rec } end

-- Record GameTooltip's calls, each as `Method(arg1[,arg2])`, for the length of `fn`.
local TT_METHODS = { "SetOwner", "SetHyperlink", "SetCurrencyByID", "AddLine", "AddDoubleLine", "Show", "Hide" }
local function recordTooltip(fn)
  local tt, calls, saved = T.mocks.GameTooltip, {}, {}
  for _, m in ipairs(TT_METHODS) do
    saved[m] = rawget(tt, m)
    tt[m] = function(_, a, b)
      -- SetOwner's argument is the row frame, whose tostring changes from run to run.
      if m == "SetOwner" then a = "row" end
      calls[#calls + 1] = m .. "(" .. tostring(a) .. (m == "AddDoubleLine" and ("," .. tostring(b)) or "") .. ")"
      return tt
    end
  end
  local ok, err = pcall(fn)
  for _, m in ipairs(TT_METHODS) do tt[m] = saved[m] end
  if not ok then error(err, 0) end
  return calls
end

local function hover(record)
  local BT = NS.BrowserTable
  local row = BT:BuildRow()
  BT:BindRow(row, dataEntry(record), 1)
  return recordTooltip(function() row:GetScript("OnEnter")(row) end)
end

local APPLE = "|Hitem:7|h[Apple]|h"
local HINT = "AddLine(Shift-click to link \194\183 right-click for options)"

test("ItemSources: characterization, an item row's hover with no ForeverDB, call for call", function()
  local calls = hover({ itemName = "Apple", itemLink = APPLE, itemID = 7, quantity = 1 })
  assertEqual(table.concat(calls, " "), "SetOwner(row) SetHyperlink(" .. APPLE .. ") " .. HINT .. " Show(nil)")
  calls = hover({ itemName = "Apple", itemLink = APPLE, itemID = 7, quantity = 1, confidence = "INFERRED" })
  assertEqual(calls[3], "AddLine(Source inferred (uncertain).)")
  assertEqual(calls[4], HINT)
  assertEqual(#calls, 5)
end)
