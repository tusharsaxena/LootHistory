local _, NS = ...
NS.State = NS.State or {}
local State = NS.State

-- Short-lived source context, stamped by peripheral events and consumed by CHAT_MSG_LOOT.
-- Shape: { source, detail, confidence, expires }
State.lootContext = nil

-- Rolling instance context for enriching KILL/MPLUS attribution.
State.encounter = nil   -- { id, name, difficulty }
State.keystone  = nil   -- { level }

-- Session flags (runtime only; reset every load/reload — never persisted to SavedVariables).
State.cleanupDone = false   -- retention prune runs once per session
State.debug = false         -- session-only logging flag; independent of window visibility. /lh debug on|off; default off
State.testRecords = nil     -- session-only synthetic dataset published by /lh test; when set, all read-path
                            -- queries (table + Insights) resolve against it instead of the live history
State.testHoldings = nil    -- its Holdings / Timeline half (modules/TestData.lua): db.global.holdings' and
State.testDaily = nil       -- db.global.daily's shapes, read through Holdings/Rollup:ActiveStore, never written

-- Outbound (loss-side) context for the ledger (timeline-ledger spec §5.4). A SECOND single slot
-- beside lootContext, same TTL engine: one BuyMerchantItem must stamp an inbound VENDOR for the
-- item AND an outbound BUY for the gold, and one slot would let either clobber the other.
-- Shape: { reason, expires, dirs = {IN|OUT|MOVE=true}|nil, kinds = {ITEM|CURRENCY|GOLD=true}|nil }
State.outContext = nil
State.scopes = {}          -- open interaction frames: merchant/trainer/taxi/mailbox/auction/bank/guildBank
State.pendingMail = nil    -- { to, items, money, sent, expires } staged by the SendMail hook
State.pendingPost = {}     -- [itemID] = qty posted to the auction house, not yet seen in `auctions`
State.craftUntil = nil     -- GetTime() until which item losses read as CRAFT_REAGENT
State.soldMail = nil       -- { itemName, expires } from taking an "Auction successful" mail's money
State.mailTaken = nil      -- { own, expires } from any mail money take: was the sender an own holder
State.tradeTarget = nil    -- holder key of the last completed trade's partner
