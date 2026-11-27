local _, NS = ...
NS.HoldingsTip = NS.HoldingsTip or {}
local HT = NS.HoldingsTip

-- The holdings block on every item and currency tooltip (#34, spec sections 6 and 7): who on the
-- account holds the thing under the mouse, and where. The tally is NS.HoldingsTally's; this file is
-- the two post calls, the guard ladder, the never-twice marks, the re-entrancy guard, the block's
-- rows and their paint through NS.Compat.AppendTooltipRows, the hot-path settings cache, and the
-- `tooltipBlock` perf bracket.
--
-- THE POST CALLS ARE A ONE-WAY FUNNEL (slash-commands-§7). TooltipDataProcessor.AddTooltipPostCall
-- and the OnHide / OnTooltipCleared HookScripts have no removal, so they are installed once per
-- session and every body gates itself on NS.IsStoodDown() first. The HookScript bodies only clear a
-- weak mark: they draw nothing and write nothing, so they carry no gate.
--
-- IT OWNS NO PLACEMENT (standalone-windows, Tooltip placement): it appends lines to a tooltip
-- someone else owns and never calls SetOwner or PlaceTooltip. It reads only data.id and
-- data.hyperlink, each through the secret guard (client-quirks-§5 Q17); a line's text is never read.
--
-- THE REPLAY FAST PATH (spec section 6.3). The client rebuilds a hovered tooltip about five times a
-- second. The tally entry memoizes the lines last painted, under four signatures -- the live tuple,
-- the settings version, the tint triples and the minute -- and a refresh that matches all of them
-- repaints those lines with no tally compose, no icon markup and no concatenation.
--
-- Reads NS.Compat, NS.Constants, NS.HoldingsTab and NS.Skin at call time; binds
-- NS.HoldingsTally and NS.Perf at load (the TOC places this file below both).

local Tally = NS.HoldingsTally
local Perf = NS.Perf
local C = NS.Constants
local CONT = C.Container
local ITEM, CURRENCY = 1, 2

-- The containers drawn, in the Holdings tab's order (modules/HoldingsTab.lua ORDER); the warband
-- bank's tabs only where it is a feature (clients-§4).
local ORDER = { CONT.BAGS, CONT.EQUIPPED, CONT.BANK, CONT.MAIL, CONT.AUCTIONS }
if C.FEATURE.warbandBank then ORDER[#ORDER + 1] = CONT.TABS end
HT.ORDER = ORDER

-- The hot-path settings cache (events-frames-taint-§7), refreshed by HT:RefreshConfig.
local cfg = { active = false, containers = true, warband = true, totalMin2 = true, modifier = "none", cfgVer = 0 }
HT._cfg = cfg

-- Never twice per show: the last mark written on a tooltip (an itemID, or minus a currencyID),
-- cleared by the tooltip's own OnHide / OnTooltipCleared. Both maps are weak-keyed.
local shownOn = setmetatable({}, { __mode = "k" })
local watched = setmetatable({}, { __mode = "k" })
local busy = false

HT._icons, HT._mutedIcons = {}, {}

-- ── settings ──────────────────────────────────────────────────────────────────────────────────

local function settings()
  local p = NS.db and NS.db.profile
  return p and p.settings or nil
end

--- Re-read the five rows (and trackLedger, D3) into the hot-path cache; the version moves on, so
--- every replay memo rebuilds.
function HT.RefreshConfig()
  local s = settings()
  local t = s and s.tooltip or {}
  cfg.active = s ~= nil and t.enabled ~= false and s.trackLedger ~= false
  cfg.containers = t.containers ~= false
  cfg.warband = t.warband ~= false
  cfg.totalMin2 = t.totalMin2 ~= false
  cfg.modifier = type(t.modifier) == "string" and t.modifier or "none"
  cfg.cfgVer = cfg.cfgVer + 1
end

-- ── icons (D4) ────────────────────────────────────────────────────────────────────────────────

local tint = { vr = nil, vg = nil, vb = nil, mr = nil, mg = nil, mb = nil, wr = nil, wg = nil, wb = nil }

local function color(token)
  local r, g, b = NS.Skin.Color(token)
  return r, g, b
end

-- The value and muted tint triples, and the warband's meaning color: a skin switch changes them, so
-- they are a signature of the memo and of the icon markup (tokens read at call time, skinning-§9).
local function readTints(out)
  out.vr, out.vg, out.vb = color("gtip.value")
  out.mr, out.mg, out.mb = color("gtip.muted")
  out.wr, out.wg, out.wb = color("sem.warbandAlt")
end

local function sameTints(a, b)
  return a.vr == b.vr and a.vg == b.vg and a.vb == b.vb and a.mr == b.mr and a.mg == b.mg
    and a.mb == b.mb and a.wr == b.wr and a.wg == b.wg and a.wb == b.wb
end

local function copyTints(from, to)
  to.vr, to.vg, to.vb, to.mr, to.mg, to.mb = from.vr, from.vg, from.vb, from.mr, from.mg, from.mb
  to.wr, to.wg, to.wb = from.wr, from.wg, from.wb
end

local iconTint = {}

-- Build both icon sets once per tint: only the containers ORDER draws, so WoW Forever never builds
-- the warband bank's mark.
local function refreshIcons()
  if HT._icons[ORDER[1]] and sameTints(iconTint, tint) then return end
  copyTints(tint, iconTint)
  local icons, muted = {}, {}
  for i = 1, #ORDER do
    local c = ORDER[i]
    icons[c] = NS.IconMarkup(C.TIP_ICONS[c], C.TIP_ICON_FALLBACK, C.TIP_ICON_SIZE, tint.vr, tint.vg, tint.vb)
    muted[c] = NS.IconMarkup(C.TIP_ICONS[c], C.TIP_ICON_FALLBACK, C.TIP_ICON_SIZE, tint.mr, tint.mg, tint.mb)
  end
  HT._icons, HT._mutedIcons = icons, muted
end

-- ── the lines ─────────────────────────────────────────────────────────────────────────────────

-- One reused line table on the entry's memo, every field set on each build.
local function line(lines, i, left, right, lt, rt)
  local l = lines[i]
  if not l then l = {}; lines[i] = l end
  l.left, l.right, l.lt, l.rt, l.lr, l.lg, l.lb = left, right, lt, rt, nil, nil, nil
  return l
end

local function shortName(holder)
  return holder:match("^[^-]+") or holder
end

-- How many shown rows share each short name: two alts called Ann on two realms show full keys.
local SHORTS = {}
local function countShorts(rows, n)
  for k in pairs(SHORTS) do SHORTS[k] = nil end
  for i = 1, n do
    local r = rows[i]
    if not r.isWarband then
      local s = shortName(r.holder)
      SHORTS[s] = (SHORTS[s] or 0) + 1
    end
  end
end

-- The name column: the account holder in sem.warbandAlt, a character in its class color, else body.
local function nameLine(l, r)
  if r.isWarband then
    l.left = C.ACCOUNT.holder
    if tint.wr then l.lr, l.lg, l.lb = tint.wr, tint.wg, tint.wb else l.lt = "gtip.body" end
    return
  end
  local s = shortName(r.holder)
  l.left = (SHORTS[s] or 0) > 1 and r.holder or s
  local cr, cg, cb = NS.Compat.ClassColor(r.classFile)
  if cr then l.lr, l.lg, l.lb = cr, cg, cb else l.lt = "gtip.body" end
end

local PARTS = {}

-- The count column: per container icons and counts, or one count.
local function countText(r)
  if not (cfg.containers and r.containers) then return NS.Compat.FormatCount(r.count) end
  local n = 0
  for i = 1, #ORDER do
    local c = ORDER[i]
    local v = r.containers[c]
    if v and v > 0 then
      n = n + 1
      PARTS[n] = HT._icons[c] .. " " .. NS.Compat.FormatCount(v)
    end
  end
  for i = n + 1, #PARTS do PARTS[i] = nil end
  -- Only containers ORDER leaves out (WoW Forever's tabs): the count alone, never an empty column.
  if n == 0 then return NS.Compat.FormatCount(r.count) end
  return table.concat(PARTS, "  ")
end

-- The dim age of the oldest stale stored container: its muted icon (an item) and the age.
local function staleText(r, now)
  local age = NS.HoldingsTab.FormatAge(r.staleAt, now)
  local icon = r.staleContainer and HT._mutedIcons[r.staleContainer]
  return NS.Compat.TooltipTint("gtip.muted", icon and (icon .. " " .. age) or age)
end

local function holderLine(lines, i, r, now)
  local l = line(lines, i, nil, nil, nil, "gtip.value")
  nameLine(l, r)
  local right = countText(r)
  if r.staleAt then right = right .. "  " .. staleText(r, now) end
  l.right = right
end

-- Fill memo.lines from the tally's rows; answers the line count (0: no block).
local function buildLines(memo, rows, n, now)
  local lines = memo.lines
  countShorts(rows, n)
  local k, shown, sum = 2, 0, 0
  for i = 1, n do
    local r = rows[i]
    if not (r.isWarband and not cfg.warband) then
      k, shown, sum = k + 1, shown + 1, sum + r.count
      holderLine(lines, k, r, now)
    end
  end
  if shown == 0 then return 0 end
  line(lines, 1, " ")
  line(lines, 2, NS.BRAND, nil, "gtip.title")
  if not cfg.totalMin2 or shown >= 2 then
    k = k + 1
    line(lines, k, "Total", NS.Compat.FormatCount(sum), "gtip.title", "gtip.value")
  end
  return k
end

-- ── the replay memo (spec section 6.3) ────────────────────────────────────────────────────────

-- The live tuple: an item's four counts under the names HoldingsTally:Item takes them by (so a
-- rebuild hands this table over and reads the client once), or a currency's quantity in `bags`.
local LIVE = { bags = nil, bank = nil, account = nil, worn = nil, rb = nil, rt = nil }

-- The live tuple a build depends on: the four item counts and the two bank readabilities (the
-- zero-suspect rule turns on them, HoldingsTally.Readable), or the currency's quantity.
local function readLive(kind, id)
  if kind == ITEM then
    LIVE.bags, LIVE.bank, LIVE.account, LIVE.worn = NS.Compat.LiveItemCounts(id)
    LIVE.rb, LIVE.rt = Tally.Readable("bank"), Tally.Readable("tabs")
  else
    LIVE.bags, LIVE.bank, LIVE.account, LIVE.worn = NS.Compat.CurrencyQuantity(id), nil, nil, nil
    LIVE.rb, LIVE.rt = nil, nil
  end
end

local function memoMatches(m, minute)
  return m.cfgVer == cfg.cfgVer and m.minute == minute and m.bags == LIVE.bags and m.bank == LIVE.bank
    and m.account == LIVE.account and m.worn == LIVE.worn and m.rb == LIVE.rb and m.rt == LIVE.rt
    and sameTints(m, tint)
end

local function stamp(m, minute)
  m.cfgVer, m.minute = cfg.cfgVer, minute
  m.bags, m.bank, m.account, m.worn = LIVE.bags, LIVE.bank, LIVE.account, LIVE.worn
  m.rb, m.rt = LIVE.rb, LIVE.rt
  copyTints(tint, m)
end

HT._builds = 0

-- The memo's lines for thing `id`, rebuilt only when a signature moved.
local function linesFor(kind, id)
  local entry = kind == ITEM and Tally:ItemEntry(id) or Tally:CurrencyEntry(id)
  local m = entry.memo
  if not m then m = { lines = {}, nLines = 0 }; entry.memo = m end
  local now = time()
  local minute = math.floor(now / 60)
  readLive(kind, id)
  readTints(tint)
  if memoMatches(m, minute) then return m.lines, m.nLines end
  HT._builds = HT._builds + 1
  refreshIcons()
  local _, rows, n
  if kind == ITEM then _, rows, n = Tally:Item(id, now, LIVE) else _, rows, n = Tally:Currency(id, now) end
  m.nLines = buildLines(m, rows, n, now)
  stamp(m, minute)
  return m.lines, m.nLines
end

-- ── the post call ─────────────────────────────────────────────────────────────────────────────

local function clearMark(tip) shownOn[tip] = nil end

local function watch(tip)
  if watched[tip] or type(tip.HookScript) ~= "function" then return end
  watched[tip] = true
  tip:HookScript("OnHide", clearMark)
  if type(tip.HasScript) == "function" and tip:HasScript("OnTooltipCleared") then
    tip:HookScript("OnTooltipCleared", clearMark)
  end
end

local function thingID(kind, data)
  if kind == ITEM then return NS.Compat.TooltipItemID(data) end
  return NS.Compat.TooltipCurrencyID(data)
end

-- The guard ladder, cheapest first (spec section 6.1); answers whether a block was written.
local function onTooltip(tip, data, kind)
  if NS.IsStoodDown() then return false end
  if not cfg.active then return false end
  local Compat = NS.Compat
  if not Compat.TooltipWritable(tip) then return false end
  if Compat.IsComparisonTooltip(tip) then return false end
  local id = thingID(kind, data)
  if not id then return false end
  local mark = kind == ITEM and id or -id
  if shownOn[tip] == mark then return false end
  if cfg.modifier ~= "none" and not Compat.ModifierDown(cfg.modifier) then return false end
  local lines, n = linesFor(kind, id)
  if n == 0 then return false end
  Compat.AppendTooltipRows(tip, lines, n)
  watch(tip)
  shownOn[tip] = mark
  return true
end

--- One post call: re-entrancy guarded (a post call that arrives while one runs writes nothing), the
--- busy flag released before an error is raised again, and the whole body in the tooltipBlock
--- bracket (performance-§2 Shape A).
--- @param kind number  1 = item, 2 = currency
--- @return boolean  a block was written
function HT.OnTooltip(tip, data, kind)
  local t0 = Perf.on and debugprofilestop()
  local wrote = false
  if not busy then
    busy = true
    local ok, res = pcall(onTooltip, tip, data, kind)
    busy = false
    if not ok then error(res, 0) end
    wrote = res
  end
  if t0 then Perf.Note("tooltipBlock", debugprofilestop() - t0) end
  return wrote
end

local function fnItem(tip, data) HT.OnTooltip(tip, data, ITEM) end
local function fnCurrency(tip, data) HT.OnTooltip(tip, data, CURRENCY) end

--- Register the two post calls, each once per session (the client keeps them; there is no removal).
--- A type the client lacks answers false and is tried again on the next call.
function HT:InstallHooks()
  local Compat = NS.Compat
  if not self._hookedItem then self._hookedItem = Compat.HookTooltipType("Item", fnItem) end
  if not self._hookedCurrency then self._hookedCurrency = Compat.HookTooltipType("Currency", fnCurrency) end
end

-- ── lifecycle (slash-commands-§7) ─────────────────────────────────────────────────────────────

--- One private bus target, SETTINGS_CHANGED for the `tooltip`, `ledger` and `profile` reasons; the
--- settings cache; and the post calls on first use.
function HT:Enable()
  self:InstallHooks()
  self:RefreshConfig()
  if self.__ev or not NS.bus then return end
  self.__ev = NS.NewBusTarget()
  self.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, reason)
    if reason == "tooltip" or reason == "ledger" or reason == "profile" then HT:RefreshConfig() end
  end)
end

--- The stand-down half: the bus target goes, the marks and the icon memo are dropped. The post
--- calls stay (they cannot be removed) and return at their IsStoodDown rung.
function HT:Disable()
  for tip in pairs(shownOn) do shownOn[tip] = nil end
  HT._icons, HT._mutedIcons = {}, {}
  if not self.__ev then return end
  self.__ev:UnregisterAllMessages()
  self.__ev:UnregisterAllEvents()
  self.__ev = nil
end
