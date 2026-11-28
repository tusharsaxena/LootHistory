local _, NS = ...
NS.ToastModel = NS.ToastModel or {}
local M = NS.ToastModel
local C = NS.Constants

-- The toast feeds' pure model (#38, toast spec docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md
-- §7.1-§7.3). No frames: the geometry and the lifecycle are LibKa0s-Feed-1.0's (core/FeedSetup.lua).
-- This file decides WHICH feed takes a gain and WHAT it keeps of it:
--
--   M.Config(fid)        the host's flat snapshot of one feed's settings (M.Rebuild drops it)
--   M.LayoutFor / MotionFor / StyleFor(fid)
--                        the Feed descriptor's `layout`, `motion` and `style` getters: one reused table
--                        per feed, filled from the profile. The Feed reads them on its first build and
--                        on Refresh() only, never per frame
--   M.Accepts(cfg, g)    the toast-only filter (D6, D7)
--   M.Key(g)             the Feed's merge key for a gain
--   M.NewPayload(g)      a copy of the reused GAIN scratch (the Feed stores a payload untouched)
--   M.FreePayload(p)     wiped back onto the spare list
--   M.Merge(old, new)    the descriptor's `d.merge` reducer: sums into `old`, frees `new`
--   M.Absorb(feed, g)    a new appearance folded into its item's toast, either order
--
-- Binds NS.Constants at load only; everything else (the profile, GainFeed.FIELDS) at call time.

local function wipe(t) for k in pairs(t) do t[k] = nil end end

local function feedSettings(fid)
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  local feeds = s and s.toasts and s.toasts.feeds
  return feeds and feeds[fid]
end

-- ── The host's config snapshot (§7.1) ────────────────────────────────────────────────────────

local cfgCache = {}

local function setOf(src, into)
  wipe(into)
  if type(src) == "table" then
    for k, v in pairs(src) do if v then into[k] = true end end
  end
  return into
end

local function fillKinds(src, into)
  wipe(into)
  for leaf, kind in pairs(C.TOAST_KIND_KEYS) do
    local on = type(src) == "table" and src[leaf] == true
    if kind == C.GainKind.APPEARANCE and not C.FEATURE.appearances then on = false end
    into[kind] = on
  end
  return into
end

local function fillConfig(c, f)
  c.enabled = f.enabled == true
  fillKinds(f.kinds, c.kinds)
  c.minQuality = tonumber(f.minQuality) or 0
  setOf(f.hideSources, c.hideSources)
  c.price, c.ilvl, c.counts, c.source = f.price, f.ilvl ~= false, f.counts ~= false, f.source ~= false
  c.hl, c.colors = type(f.hl) == "table" and f.hl or {}, type(f.colors) == "table" and f.colors or {}
  c.showInCombat, c.clickThrough = f.showInCombat ~= false, f.clickThrough == true
end

--- The flat snapshot of feed `fid` (cached until M.Rebuild). Draw paths read this, never the profile.
--- A feed with no stored settings is a disabled one with no kinds.
function M.Config(fid)
  local c = cfgCache[fid]
  if c and c.fresh then return c end
  c = c or { kinds = {}, hideSources = {} }
  cfgCache[fid] = c
  local f = feedSettings(fid)
  if f then
    fillConfig(c, f)
  else
    c.enabled = false
    fillKinds(nil, c.kinds)
    wipe(c.hideSources)
    c.hl, c.colors = {}, {}
  end
  c.fresh = true
  return c
end

--- Drop every cached snapshot (a settings write, a profile switch); the next Config re-reads.
function M.Rebuild()
  for _, c in pairs(cfgCache) do c.fresh = nil end
end

-- ── The descriptor getters (§7.1) ────────────────────────────────────────────────────────────

local layouts, motions, styles = {}, {}, {}

local function reused(cache, fid)
  local t = cache[fid]
  if not t then t = {}; cache[fid] = t end
  wipe(t)
  return t
end

--- The Feed's `layout` for feed `fid` (Feed doc *layout keys*). The stored leaves are the Feed's own
--- words apart from `grow`, which is stored lower case.
function M.LayoutFor(fid)
  local t, f = reused(layouts, fid), feedSettings(fid)
  if not f then return t end
  t.slot, t.x, t.y = f.slot, f.x, f.y
  t.grow = f.grow == "down" and "DOWN" or "UP"
  t.shown, t.width, t.rowHeight, t.iconSize = f.shown, f.width, f.rowHeight, f.iconSize
  t.padding, t.gap, t.align, t.iconSide = f.padding, f.gap, f.align, f.iconSide
  return t
end

-- The Feed's enter words (Feed doc *motion keys*), which the profile stores as is.
local ENTER = { none = true, fade = true, left = true, right = true, up = true, down = true }

--- The Feed's `motion` for feed `fid` (Feed doc *motion keys*). `enter` is stored in the Feed's own
--- vocabulary, and a word outside it (a hand-edited profile) is left out, so the Feed's default
--- applies; right-click dismiss is not a setting (D14); `settle` re-reads the counts (§7.4).
function M.MotionFor(fid)
  local t, f = reused(motions, fid), feedSettings(fid)
  if not f then return t end
  t.enter = ENTER[f.enter] and f.enter or nil
  t.enterTime, t.hold, t.fadeTime, t.mergeWindow = f.enterTime, f.hold, f.fade, f.merge
  t.pulse, t.timerBar, t.smooth, t.pin = f.pulse ~= false, f.timerBar == true, f.smooth ~= false, f.pin ~= false
  t.rightDismiss = true
  t.settle = C.TOAST_COUNT_SETTLE
  return t
end

-- The style leaves stored under the Feed's own key names (§7.1).
local STYLE_SAME = {
  "bgColorFromSkin", "bgType", "bgColor", "bgColor2", "bgTexture",
  "borderStyleFromSkin", "borderStyle", "borderSize", "borderColorFromSkin", "borderColor",
  "fontFromSkin", "font", "fontSize", "fontSize2", "fontFlags", "fontShadowFromSkin", "fontShadow",
  "fontColorFromSkin", "fontColor",
}

local bgClass, bgClass2 = {}, {}   -- fid -> the reused class color of its fill (one per feed: alphas differ)

--- `stored` in the player's class color, its own alpha kept (options-ui-§17), in feed `fid`'s reused
--- table of `cache`; nil when the class does not resolve, so the caller falls through to the skin,
--- then the swatch.
local function classColor(stored, cache, fid)
  local into = cache[fid]
  if not into then into = {}; cache[fid] = into end
  local r, g, b = NS.Compat.ClassColor(NS.Compat.PlayerClassFile())
  if not r then return nil end
  into.r, into.g, into.b = r, g, b
  into.a = type(stored) == "table" and tonumber(stored.a) or 1
  return into
end

--- The background's two Use class color companions (options-ui-§17): the Feed's style has no class
--- fill, so the host resolves it. Class comes first, before the skin: a resolved class color turns the
--- fill's FromSkin off and draws as the swatch would. The gradient end takes its own companion while
--- the fill is not the skin's.
local function classFill(t, f, fid)
  if f.useClassColorBgColor == true then
    local c = classColor(f.bgColor, bgClass, fid)
    if c then t.bgColor, t.bgColorFromSkin = c, false end
  end
  if f.useClassColorBgColor2 == true and t.bgColorFromSkin == false then
    local c = classColor(f.bgColor2, bgClass2, fid)
    if c then t.bgColor2 = c end
  end
end

--- The Feed's `style` for feed `fid` (Feed doc *Style over the skin*): the stored leaves passed
--- through, the three renamed toggles mapped, and the stored font sizes always drawn (Options' cause
--- L11). An empty `font` (the profile's "the skin's own", as settings.appearance.font stores it) is
--- left out, so the Feed's own resolution applies. The bar and glow keys are left out, so the
--- Feed's skin defaults apply.
function M.StyleFor(fid)
  local t, f = reused(styles, fid), feedSettings(fid)
  if not f then return t end
  for i = 1, #STYLE_SAME do
    local k = STYLE_SAME[i]
    t[k] = f[k]
  end
  if t.font == "" then t.font = nil end
  t.borderTint, t.borderClass, t.fontClass = f.borderByQuality == true, f.useClassColorBorder == true,
    f.useClassColorFont == true
  t.fontSizeFromSkin = false
  classFill(t, f, fid)
  return t
end

-- ── The filter (§7.2) ────────────────────────────────────────────────────────────────────────

local IN_ONLY = { ITEM = true, GOLD = true, APPEARANCE = true }

--- True when feed config `cfg` shows gain `g`: the feed is on and takes the kind, an item clears the
--- feed's minimum quality, its source is not hidden, and it is a gain (only reputation shows a loss).
function M.Accepts(cfg, g)
  if not (cfg and cfg.enabled and g and cfg.kinds[g.kind]) then return false end
  if g.kind == C.GainKind.ITEM and (tonumber(g.quality) or 0) < (cfg.minQuality or 0) then return false end
  if g.source and cfg.hideSources[g.source] then return false end
  if IN_ONLY[g.kind] and g.dir ~= "IN" then return false end
  return true
end

-- ── Keys, payloads and the merge reducer (§7.3) ──────────────────────────────────────────────

local KEY_PREFIX = { ITEM = "i:", CURRENCY = "c:", SKILL = "s:" }

--- The Feed's merge key for `g`: one per thing, reputation split by direction, every appearance on
--- one key (a burst reads "x3" with the latest name). nil for a kind the feeds do not know.
function M.Key(g)
  local kind = g and g.kind
  if kind == C.GainKind.GOLD then return "g" end
  if kind == C.GainKind.XP then return "x" end
  if kind == C.GainKind.APPEARANCE then return "a" end
  if kind == C.GainKind.REPUTATION then return "r:" .. tostring(g.id) .. ":" .. tostring(g.dir) end
  local prefix = KEY_PREFIX[kind]
  return prefix and (prefix .. tostring(g.id)) or nil
end

local spares = {}
M._spares = spares   -- tests only: the spare list's identity

--- A payload of its own for one feed: every GAIN field copied out of the reused scratch (the Feed
--- stores it untouched). Takes a spare when one is there.
function M.NewPayload(g)
  local p = table.remove(spares) or {}
  local fields = NS.GainFeed.FIELDS
  for i = 1, #fields do
    local k = fields[i]
    p[k] = g[k]
  end
  return p
end

--- Wipe `p` back onto the spare list (a refused push, a merged-away payload).
function M.FreePayload(p)
  if type(p) ~= "table" then return end
  wipe(p)
  spares[#spares + 1] = p
end

-- The fields a later gain of the same key moves forward (the newest read wins).
local MOVING = { "standing", "threshold", "rank", "label", "level", "levelUp", "cur", "max", "new" }
-- An appearance burst shows the latest look.
local LATEST_LOOK = { "id", "itemID", "link", "name", "quality", "icon" }

local function addNumber(old, new, k)
  old[k] = (tonumber(old[k]) or 0) + (tonumber(new[k]) or 0)
end

-- A cached price (§7.4, filled lazily by the content) is summed only when both sides carry one; a
-- side that never painted leaves the sum unknown, so the cache is dropped and the next paint
-- prices the summed quantity.
local function addCached(old, new, k)
  local a, b = tonumber(old[k]), tonumber(new[k])
  old[k] = (a and b) and (a + b) or nil
end

local function copyFields(old, new, list)
  for i = 1, #list do
    local k = list[i]
    if new[k] ~= nil then old[k] = new[k] end
  end
end

--- The descriptor's `d.merge`: `new` summed into `old` (qty and the cached values), the moving
--- fields refreshed (a skill-up keeps its first `old` rank), the highlight carried forward, `new`
--- freed onto the spare list. Answers `old`.
function M.Merge(old, new)
  if type(old) ~= "table" or type(new) ~= "table" then return new end
  addNumber(old, new, "qty")
  addCached(old, new, "value")
  addCached(old, new, "vendor")
  addCached(old, new, "ah")
  copyFields(old, new, MOVING)
  if old.kind == C.GainKind.APPEARANCE then copyFields(old, new, LATEST_LOOK) end
  old.newLook = old.newLook or new.newLook
  old.highlight = old.highlight or new.highlight
  M.FreePayload(new)
  return old
end

-- ── Absorbing an appearance into its item (§7.3) ─────────────────────────────────────────────

local function itemKey(id) return "i:" .. tostring(id) end

--- Fold an appearance and the item that taught it into one toast on `feed`. An APPEARANCE gain whose
--- item is already on the feed marks that item's payload (a new look, the appearance highlight) and
--- repaints it: answers true, the gain is consumed. An ITEM gain arriving while the feed's appearance
--- toast names that item, one look only, dismisses the appearance toast: answers false, true (push
--- the item with the look marked). Anything else answers false. `Repaint` carries no pulse (Feed
--- doc), so an absorb shows as the glow and the extra line.
function M.Absorb(feed, g)
  if not (feed and type(g) == "table") then return false end
  if g.kind == C.GainKind.APPEARANCE then
    if g.itemID == nil then return false end
    local key = itemKey(g.itemID)
    local p = feed:Get(key)
    if type(p) ~= "table" then return false end
    p.newLook, p.highlight = true, "appearance"
    feed:Repaint(key)
    return true
  end
  if g.kind == C.GainKind.ITEM and g.id ~= nil then
    local a = feed:Get("a")
    if type(a) == "table" and a.itemID == g.id and tonumber(a.qty) == 1 then
      feed:Dismiss("a")
      return false, true
    end
  end
  return false
end
