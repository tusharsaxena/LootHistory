local _, NS = ...
NS.Diagnostics = NS.Diagnostics or {}
local Dx = NS.Diagnostics

-- The diagnostics report's sections (debug-logging-§14, the DX-LH content contract).
--
-- `/lh diagnostics` and `/lh debug diagnostics` both call `NS.DebugLog:RunDiagnostics()`, and
-- LibKa0s-DebugLog-1.0's helper (DebugLogDiagnostics.lua, key 14.1) writes everything AROUND the
-- sections below: the two markers with the brand, its half of the identity header (client build,
-- locale, debug flag, combat state, the running LibKa0s minors and NS.InitSummary's line), a pcall
-- per section, the cap and the `truncated` line, and the one append loop into the console. This file
-- writes sections only, and that split is the rule rather than a convenience: the buffer, the
-- markers, the pcall and the cap are what eleven hand copies would drift in (anti-patterns #47, #90).
--
-- ── WHAT THE REPORT READS, AND WHAT IT MUST NOT CALL ──────────────────────────────────────────
--
-- Stored state and module fields only. A section never calls GetItemInfo, Compat.ScanBound, a
-- tooltip build or C_ChallengeMode: those are the calls that are slow, that can raise on a secret,
-- or that answer differently than they did when the record was written, and a report exists to say
-- what the addon was working with, not to re-derive it. So the history tail prints the item NAME
-- the record stored, never its link (which is escapes) and never a fresh lookup; the keystone line
-- prints the stored context, never a live read; and no raw loot or currency chat text is printed,
-- because the addon never keeps any.
--
-- It changes nothing either: no hold taken or released, no event registered, no timer armed, no
-- cache rebuilt (the loot patterns are reported from the globals they are built from rather than by
-- building them), and no `GetPriority()`, which writes an empty cascade into a store that has none.
-- tests/test_diagnostics.lua spies on each of those.
--
-- Every value reaches a line through `out:add`'s `%s`, which stringifies through NS.SafeToString
-- first, and a stored number is compared only after `out:readable` says it can be. The body is
-- English diagnostic text and does not go through NS.L, like every trace line (STD-13).
--
-- WHILE STOOD DOWN every section still runs. The one whose runtime state the stand-down released,
-- the capture wiring, says so instead of printing an empty registration set; stored configuration
-- prints as normal, because that is usually what a disabled addon's report is for.

-- nil on purpose: `out:add` then writes the helper's own report tag, so every section line wears the
-- same tag as the markers without this file spelling it (and without a quoted short name here for
-- the standard's alias check to trip over).
local TAG = nil

-- The newest records the tail prints. Aggregates cover the whole history; the tail is for reading
-- the last few loots a player is asking about.
local TAIL = 25

-- The DX-LH always-print rows: printed whatever their value, beside every row that differs.
local ALWAYS = { "settings.enabled", "settings.retentionDays", "settings.auction.enabled" }

-- The client globals core/Util.lua compiles the self-loot, self-currency and roll-won patterns from.
-- Reported as present/absent by NAME, so a client that renamed one is visible without building
-- (and so caching) a pattern set from a report. Kept in step with Util.BuildLootPatterns and
-- Util.BuildCurrencyPatterns; a name missing here reads as absent, never as a raise.
local LOOT_GLOBALS = {
  "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
  "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_REFUND_MULTIPLE", "LOOT_ITEM_SELF",
  "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_BONUS_ROLL_SELF", "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_REFUND",
}
local CURRENCY_GLOBALS = {
  "CURRENCY_GAINED_MULTIPLE_OVERFLOW", "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED_MULTIPLE",
  "LOOT_ITEM_REFUND_MULTIPLE", "CURRENCY_GAINED", "LOOT_ITEM_REFUND",
}

-- The record fields the history summary tallies, as { lead, field }. A nil field counts as `none`.
local TALLIES = {
  { "history: by source",     "source" },
  { "history: by confidence", "confidence" },
  { "history: by quality",    "quality" },
  { "history: by type",       "itemType" },
  { "history: by bound",      "bound" },
}

local function store() return NS.db and NS.db.global end
local function yn(v) return v and "yes" or "no" end

--- `{ "NAME=n", ... }` for a tally table, keys sorted, for `out:joined`.
local function tallyParts(t)
  local keys, parts = {}, {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  for i, k in ipairs(keys) do parts[i] = k .. "=" .. tostring(t[k]) end
  return parts
end

--- How many of `names` are strings in _G, and the ones that are not.
local function present(names)
  local n, missing = 0, {}
  for _, name in ipairs(names) do
    if type(_G[name]) == "string" then n = n + 1 else missing[#missing + 1] = name end
  end
  return n, missing
end

-- ── the sections ──────────────────────────────────────────────────────────────────────────────

--- The host half of the identity header (STD-10 (b)): what the library cannot know. The library
--- has already printed the client, locale, debug flag, combat state and NS.InitSummary's line.
local function identity(out)
  local g = store()
  out:add(TAG, "identity: %s %s (folder %s)", NS.BRAND, NS.Version and NS.Version() or NS.version,
    NS.name)
  out:add(TAG, "identity: schema stored v%s, code v%s", g and g.schemaVersion or "?",
    NS.SCHEMA_VERSION)
  out:add(TAG, "identity: profile: account-wide (this addon stores everything under db.global)")
  local BT = NS.BrowserTable
  out:add(TAG, "identity: enabled=%s stoodDown=%s testMode=%s",
    tostring(not NS.AddonIsOff()), tostring(NS.IsStoodDown()), tostring(BT and BT.testMode == true))
end

local function patterns(out)
  local n, missing = present(LOOT_GLOBALS)
  out:add(TAG, "patterns: self-loot source globals %s of %s present", n, #LOOT_GLOBALS)
  if #missing > 0 then out:joined(TAG, "patterns: missing", missing) end
  n, missing = present(CURRENCY_GLOBALS)
  out:add(TAG, "patterns: self-currency source globals %s of %s present", n, #CURRENCY_GLOBALS)
  if #missing > 0 then out:joined(TAG, "patterns: missing", missing) end
  out:add(TAG, "patterns: roll-won global present=%s", yn(type(_G.LOOT_ROLL_YOU_WON) == "string"))
end

local function lifecycle(out)
  local lc = NS.Lifecycle
  local holds = lc and lc.Holds and lc:Holds() or {}
  out:joined(TAG, "lifecycle: holds", holds)
  out:add(TAG, "lifecycle: stood down=%s, latch=%s", yn(NS.IsStoodDown()),
    LibStub and LibStub("LibKa0s-Lifecycle-1.0", true) and "LibKa0s" or "local fallback")
end

local function capture(out)
  if NS.IsStoodDown() then
    out:add(TAG, "capture: stood down (the loot, currency and context events are unregistered)")
  else
    local C, A = NS.Collector, NS.Attribution
    out:add(TAG, "capture: collector wired=%s, attribution wired=%s, attribution events %s",
      yn(C and C._enabled), yn(A and A._enabled), A and type(A.__events) == "table" and #A.__events or 0)
  end
  local names = NS.RejectedEvents or {}
  if #names == 0 then
    out:add(TAG, "capture: rejected events: none")
  else
    out:list(TAG, "capture: rejected events:", names)
  end
end

--- A value as the report shows a setting: a set as its sorted keys (the CLI's own shape), anything
--- else as itself.
local function settingValue(row, v)
  if type(v) == "table" and NS.Slash and NS.Slash.FormatSchemaValue then
    return NS.Slash.FormatSchemaValue(row, v)
  end
  return v
end

local function settingRead(row)
  if type(row.get) == "function" then return row.get() end
  return NS.Schema:Get(row.path)
end

local function settings(out)
  local S = NS.Schema
  out:add(TAG, "settings: rows that differ from their defaults, plus %s", table.concat(ALWAYS, ", "))
  local n = out:nonDefaults(S and S.Schema or {}, settingRead, nil, settingValue, { always = ALWAYS })
  out:add(TAG, "settings: %s row(s) printed", n)
end

local function auction(out)
  local g = store()
  local a = g and g.settings and g.settings.auction or {}
  local keys = 0
  for _, on in pairs(type(a.capture) == "table" and a.capture or {}) do
    if on then keys = keys + 1 end
  end
  out:add(TAG, "auction: enabled=%s, capturing %s key(s)", tostring(a.enabled ~= false), keys)
  -- Read raw: AuctionPrice:GetPriority() writes an empty cascade into a store that has none.
  out:joined(TAG, "auction: priority", type(a.priority) == "table" and a.priority or {})
  local AP = NS.AuctionPrice
  local function has(p) return yn(AP and AP.IsProviderAvailable and AP:IsProviderAvailable(p)) end
  out:add(TAG, "auction: providers auctionator=%s tsm=%s oribos=%s", has("auctionator"), has("tsm"),
    has("oribos"))
end

local function filters(out)
  local F = NS.Filters
  local lists = {
    { "blacklist", F:Blacklist() }, { "whitelist", F:Whitelist() },
    { "currency blacklist", F:CurrencyBlacklist() },
  }
  for _, l in ipairs(lists) do
    local ids = F:SortedIDs(l[2])
    out:list(TAG, "filters: " .. l[1] .. " (" .. tostring(#ids) .. ")", ids)
  end
end

--- A context's `detail` as `key=value` pairs, keys sorted. Attribution:Stamp stores a TABLE here
--- for a kill, a boss or a quest ({ npcID, encounterID, difficulty, keystoneLevel, questID }), and
--- a table through `out:plain` is only its address. Anything else prints as itself.
local function detailText(out, d)
  if type(d) ~= "table" then return out:plain(d) end
  local keys, byKey = {}, {}
  for k, v in pairs(d) do
    local name = out:str(k)
    keys[#keys + 1], byKey[name] = name, v
  end
  table.sort(keys)
  for i, name in ipairs(keys) do keys[i] = name .. "=" .. out:str(byKey[name]) end
  return #keys > 0 and table.concat(keys, " ") or "-"
end

--- The stored loot context: what the next CHAT_MSG_LOOT would be attributed to. Its expiry is
--- printed as seconds left only when both it and the clock read as numbers.
local function context(out, ctx)
  if type(ctx) ~= "table" then return out:add(TAG, "attribution: context none") end
  local now = type(GetTime) == "function" and GetTime() or nil
  local left = "?"
  if out:readable(ctx.expires) and out:readable(now) then
    left = ("%.1f"):format(ctx.expires - now)
  end
  out:add(TAG, "attribution: context source=%s detail=%s confidence=%s expires in %s s",
    ctx.source, detailText(out, ctx.detail), ctx.confidence, left)
end

local function attribution(out)
  local S = NS.State
  context(out, S.lootContext)
  local e = S.encounter
  if type(e) == "table" then
    out:add(TAG, "attribution: encounter id=%s name=%s difficulty=%s", e.id, e.name, e.difficulty)
  else
    out:add(TAG, "attribution: encounter none")
  end
  local k = S.keystone
  out:add(TAG, "attribution: keystone %s", type(k) == "table" and ("level " .. out:str(k.level)) or "none")
end

--- One pass over the stored history: every tally in TALLIES, the characters, the AH-priced count
--- and the oldest and newest timestamps.
local function aggregate(history)
  local agg = { tallies = {}, chars = {}, nchars = 0, priced = 0 }
  for i = 1, #TALLIES do agg.tallies[i] = {} end
  for _, r in ipairs(history) do
    for i, t in ipairs(TALLIES) do
      local key = tostring(r[t[2]] == nil and "none" or r[t[2]])
      agg.tallies[i][key] = (agg.tallies[i][key] or 0) + 1
    end
    if r.char ~= nil and not agg.chars[r.char] then
      agg.chars[r.char] = true
      agg.nchars = agg.nchars + 1
    end
    if type(r.auctionPrice) == "table" and next(r.auctionPrice) then agg.priced = agg.priced + 1 end
  end
  return agg
end

local function history(out)
  local g = store()
  local h = g and type(g.history) == "table" and g.history or {}
  local first, last = h[1], h[#h]
  out:add(TAG, "history: %s records, oldest ts %s, newest ts %s", #h, first and first.ts or "-",
    last and last.ts or "-")
  local agg = aggregate(h)
  for i, t in ipairs(TALLIES) do out:joined(TAG, t[1], tallyParts(agg.tallies[i])) end
  out:add(TAG, "history: %s distinct characters", agg.nchars)
  out:add(TAG, "history: AH-priced %s of %s", agg.priced, #h)
end

--- The newest TAIL records, newest first, stored fields only.
local function tail(out)
  local g = store()
  local h = g and type(g.history) == "table" and g.history or {}
  local stop = math.max(1, #h - TAIL + 1)
  out:add(TAG, "tail: newest %s of %s, newest first", math.max(0, #h - stop + 1), #h)
  for i = #h, stop, -1 do
    local r = h[i]
    out:add(TAG, "tail: #%s ts=%s %s id=%s x%s q=%s src=%s conf=%s bound=%s zone=%s char=%s", i,
      r.ts, out:plain(r.itemName), r.itemID or r.currencyID, r.quantity, r.quality, r.source,
      r.confidence, r.bound or "none", r.zone, r.char)
  end
end

local function boundRepair(out)
  local g = store() or {}
  out:add(TAG, "bound repair: pending=%s attempts=%s revision=%s", yn(g.boundRepairPending),
    g.boundRepairAttempts or 0, g.boundRepairRevision or "-")
end

local function browser(out)
  local B, BT = NS.Browser, NS.BrowserTable
  local w = B and B.GetWindow and B:GetWindow()
  out:add(TAG, "browser: window built=%s shown=%s locked=%s", yn(w), yn(w and w:IsShown()),
    yn(B and B.IsLocked and B:IsLocked()))
  if BT then
    out:add(TAG, "browser: sort %s %s, groupBy %s, matched %s, test records %s", BT.sortKey,
      BT.sortAsc and "asc" or "desc", BT.groupBy, BT.matchCount or "-",
      type(NS.State.testRecords) == "table" and #NS.State.testRecords or "-")
  end
  local g = store()
  local view = g and type(g.savedView) == "table" and g.savedView or nil
  local keys = {}
  for k in pairs(view or {}) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  if view then out:joined(TAG, "browser: saved view keys", keys) else out:add(TAG, "browser: saved view none") end
end

local function launcher(out)
  local g = store()
  local mm = g and g.minimap or {}
  out:add(TAG, "launcher: present=%s minimap hide=%s", yn(NS.Launcher), tostring(mm.hide == true))
end

local function pools(out)
  local BT, A, P = NS.BrowserTable, NS.Analytics, NS.Pool
  if BT and BT.rowPool and P and P.Counts then
    out:add(TAG, "pools: history rows free=%s active=%s", P.Counts(BT.rowPool))
  else
    out:add(TAG, "pools: history rows not built")
  end
  local n = 0
  for _ in pairs(A and type(A.pool) == "table" and A.pool or {}) do n = n + 1 end
  out:add(TAG, "pools: insights chart pools %s", n > 0 and n or "not built")
end

-- The sections in report order (STD-10: identity, then settings, then domain state, then the
-- error record, which here is the rejected-event list inside `capture`).
local SECTIONS = {
  { "identity", identity }, { "patterns", patterns }, { "lifecycle", lifecycle },
  { "capture", capture }, { "settings", settings }, { "auction", auction },
  { "filters", filters }, { "attribution", attribution }, { "history", history },
  { "tail", tail }, { "bound repair", boundRepair }, { "browser", browser },
  { "launcher", launcher }, { "pools", pools },
}

--- The descriptor's `diagnostics` hook (core/DebugLogSetup.lua) answers this, at run time.
function Dx.Sections() return SECTIONS end
