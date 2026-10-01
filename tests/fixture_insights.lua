-- tests/fixture_insights.lua — the loot histories the Insights characterization cases run over.
--
-- Shared by tests/test_analytics_layout.lua (the chart render) and tests/test_export.lua (the
-- Insights CSV), so both pin the same data. Written for GI-LH-01 / GI-LH-02 (LootHistory#32).

local T = _G.LH_TEST
local NS = T.NS

local F = {}

-- ── fixtures ──────────────────────────────────────────────────────────────────────────────────
--
-- Timestamps sit at 12:00 UTC, so a day key is the same date in every timezone from UTC-11 to
-- UTC+11. byHour and byWeekday are overwritten with fixed buckets after Stats, so the hour and
-- weekday charts do not depend on the machine's timezone either.

local DAY = 86400
local NOON = 1600000000 - (1600000000 % DAY) + 12 * 3600

local SOURCES = { "KILL", "CONTAINER", "MPLUS", "ROLL", "BONUS_ROLL", "QUEST", "TRADE", "MAIL",
                  "AH", "VENDOR", "CRAFT", "DISENCHANT" }
local TYPES = { "Armor", "Weapon", "Consumable", "Tradeskill", "Recipe", "Gem", "Miscellaneous" }
local BOUNDS = { "BOP", "BOE", "WARBAND", "WARBAND_UE", nil }

function F.richHistory()
  local h = {}
  local chars = { { "Alpha-Realm", "WARRIOR" }, { "Beta-Realm", "MAGE" }, { "Gamma-Realm", "PRIEST" } }
  for i = 1, 40 do
    local c = chars[(i % 3) + 1]
    h[#h + 1] = {
      ts = NOON + (i % 9) * DAY, char = c[1], classFile = c[2],
      itemID = 100 + (i % 14), itemName = "Item " .. (i % 14),
      quality = i % 6, itemLevel = 400 + i, bound = BOUNDS[(i % 5) + 1],
      itemType = TYPES[(i % 7) + 1], vendorPrice = (i % 4 == 0) and 0 or i * 1234,
      quantity = (i % 3) + 1, source = SOURCES[(math.floor(i / 3) % 12) + 1],
      zone = (i % 2 == 0) and "Valley" or ((i % 3 == 0) and "Cavern" or "Spire"),
    }
  end
  -- Currency, including a character who looted only currency (byChar count 0).
  for i = 1, 8 do
    h[#h + 1] = {
      ts = NOON + (i % 4) * DAY, char = (i % 2 == 0) and "Delta-Realm" or "Alpha-Realm",
      classFile = (i % 2 == 0) and "ROGUE" or "WARRIOR",
      currencyID = 3000 + (i % 3), itemName = "Coin " .. (i % 3), quantity = i * 5,
      source = SOURCES[(i % 4) + 1], zone = "Valley",
    }
  end
  return h
end

-- Items only, every value zero: the Value By Source section and the Top Items By Value panel
-- draw nothing, and the CURRENCY section takes its hidden branch. Spread over 70 days, so the
-- per-day strips trim to the 60 most recent.
function F.plainHistory()
  local h = {}
  for i = 1, 12 do
    h[#h + 1] = {
      ts = NOON + (i - 1) * 6 * DAY, char = "Solo-Realm", classFile = "HUNTER",
      itemID = 500 + (i % 3), itemName = "Plain " .. (i % 3), quality = 1 + (i % 2),
      itemType = "Junk", vendorPrice = 0, source = (i % 2 == 0) and "KILL" or "QUEST",
    }
  end
  return h
end

local FIXED_HOURS = { [0] = 2, [7] = 5, [13] = 9, [22] = 1 }
local FIXED_WEEKDAYS = { [0] = 3, [2] = 7, [5] = 4 }

function F.statsFor(history)
  local saved = NS.db.global.history
  NS.db.global.history = history
  local savedTest = NS.State.testRecords
  NS.State.testRecords = nil
  local stats = NS.Database:Stats({})
  NS.db.global.history = saved
  NS.State.testRecords = savedTest
  if stats.totals.records > 0 then
    stats.byHour, stats.byWeekday = FIXED_HOURS, FIXED_WEEKDAYS
  end
  return stats
end

return F
