-- tests/test_toast_model.lua — modules/ToastModel.lua and modules/ToastContent.lua's first cut (toast
-- spec docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §7, §13.2): the config snapshot, the
-- filter, the merge keys, the payload copy and its spare list, the merge reducer, the three Feed
-- descriptor getters, and the host constants pinned to LibKa0s-Feed-1.0's. Pure: no frame is built.
-- Every case that writes the profile puts it back.

local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function M() return NS.ToastModel end
local C = NS.Constants

local function feedRow(fid) return NS.db.profile.settings.toasts.feeds[fid] end

--- Run `fn(f)` with feed `fid`'s stored settings swapped for a deep copy patched by `over`, then put
--- the original back and drop the snapshot.
local function withFeed(fid, over, fn)
  local feeds = NS.db.profile.settings.toasts.feeds
  local saved = feeds[fid]
  local f = NS.Util.DeepCopy(saved)
  for k, v in pairs(over or {}) do f[k] = v end
  feeds[fid] = f
  M().Rebuild()
  local ok, err = pcall(fn, f)
  feeds[fid] = saved
  M().Rebuild()
  if not ok then error(err, 0) end
end

local function gain(t)
  local g = { dir = "IN", qty = 1 }
  for k, v in pairs(t) do g[k] = v end
  return g
end

-- ── the host constants (§8.1) ────────────────────────────────────────────────────────────────

test("ToastModel: C.TOAST_SLOTS, TOAST_NUDGE_MAX and TOAST_SHOWN_MAX equal the Feed's own", function()
  local Feed = NS.FeedLib
  assertTrue(Feed ~= nil, "LibKa0s-Feed-1.0 did not resolve")
  assertEqual(table.concat(C.TOAST_SLOTS, ","), table.concat(Feed.SLOTS, ","))
  assertEqual(C.TOAST_NUDGE_MAX, Feed.NUDGE_MAX)
  assertEqual(C.TOAST_SHOWN_MAX, Feed.SHOWN_MAX)
end)

-- ── the config snapshot (§7.1) ───────────────────────────────────────────────────────────────

test("ToastModel: Config flattens a feed's settings, kinds keyed by GainKind", function()
  withFeed("main", { minQuality = 2, hideSources = { VENDOR = true, MAIL = false }, clickThrough = true,
                     showInCombat = false }, function()
    local c = M().Config("main")
    assertTrue(c.enabled)
    assertTrue(c.kinds.ITEM and c.kinds.GOLD and c.kinds.XP and c.kinds.SKILL)
    assertEqual(c.kinds.APPEARANCE, C.FEATURE.appearances == true, "appearances only where they are a feature")
    assertEqual(c.minQuality, 2)
    assertTrue(c.hideSources.VENDOR)
    assertEqual(c.hideSources.MAIL, nil, "a false entry hides nothing")
    assertTrue(c.clickThrough)
    assertFalse(c.showInCombat)
    assertTrue(M().Config("main") == c, "the snapshot is cached")
  end)
end)

test("ToastModel: Rebuild makes the next Config re-read the profile", function()
  withFeed("progress", nil, function(f)
    assertFalse(M().Config("progress").enabled)
    f.enabled = true
    assertFalse(M().Config("progress").enabled, "the cached snapshot does not see the write")
    M().Rebuild()
    assertTrue(M().Config("progress").enabled, "after Rebuild it does")
  end)
end)

test("ToastModel: a feed with no stored settings is disabled and takes no kind", function()
  local c = M().Config("nope")
  assertFalse(c.enabled)
  for _, kind in pairs(C.TOAST_KIND_KEYS) do assertFalse(c.kinds[kind], kind) end
end)

-- ── the filter (§7.2) ────────────────────────────────────────────────────────────────────────

test("ToastModel: Accepts takes an enabled feed's kinds and refuses the rest", function()
  withFeed("main", { kinds = { item = true, money = false, currency = true, reputation = true,
                               appearance = true, xp = true, skill = true } }, function()
    local c = M().Config("main")
    assertTrue(M().Accepts(c, gain{ kind = "ITEM", quality = 1 }))
    assertFalse(M().Accepts(c, gain{ kind = "GOLD" }), "money is off on this feed")
    assertFalse(M().Accepts(nil, gain{ kind = "ITEM" }))
    assertFalse(M().Accepts(c, nil))
    c.enabled = false
    assertFalse(M().Accepts(c, gain{ kind = "ITEM", quality = 1 }), "a disabled feed takes nothing")
  end)
end)

test("ToastModel: Accepts gates only items on the minimum quality", function()
  withFeed("main", { minQuality = 3 }, function()
    local c = M().Config("main")
    assertFalse(M().Accepts(c, gain{ kind = "ITEM", quality = 2 }))
    assertTrue(M().Accepts(c, gain{ kind = "ITEM", quality = 3 }))
    assertFalse(M().Accepts(c, gain{ kind = "ITEM" }), "an unknown quality reads as Poor")
    assertTrue(M().Accepts(c, gain{ kind = "CURRENCY", quality = 1 }), "a currency is not gated")
  end)
end)

test("ToastModel: Accepts drops a hidden source and every loss but a reputation one", function()
  withFeed("main", { hideSources = { VENDOR = true } }, function()
    local c = M().Config("main")
    assertFalse(M().Accepts(c, gain{ kind = "ITEM", quality = 1, source = "VENDOR" }))
    assertTrue(M().Accepts(c, gain{ kind = "ITEM", quality = 1, source = "KILL" }))
    assertFalse(M().Accepts(c, gain{ kind = "ITEM", quality = 1, dir = "OUT" }))
    assertFalse(M().Accepts(c, gain{ kind = "GOLD", dir = "OUT" }))
    assertTrue(M().Accepts(c, gain{ kind = "REPUTATION", dir = "OUT", id = 72 }), "a reputation loss shows")
  end)
end)

-- ── keys, payloads and the merge reducer (§7.3) ──────────────────────────────────────────────

test("ToastModel: Key per kind", function()
  local K = M().Key
  assertEqual(K(gain{ kind = "ITEM", id = 7 }), "i:7")
  assertEqual(K(gain{ kind = "CURRENCY", id = 3008 }), "c:3008")
  assertEqual(K(gain{ kind = "GOLD" }), "g")
  assertEqual(K(gain{ kind = "REPUTATION", id = 72 }), "r:72:IN")
  assertEqual(K(gain{ kind = "REPUTATION", id = 72, dir = "OUT" }), "r:72:OUT")
  assertEqual(K(gain{ kind = "XP" }), "x")
  assertEqual(K(gain{ kind = "SKILL", id = 186 }), "s:186")
  assertEqual(K(gain{ kind = "APPEARANCE", id = 1 }), "a")
  assertEqual(K(gain{ kind = "APPEARANCE", id = 2 }), "a", "every appearance shares one key")
  assertEqual(K(gain{ kind = "BOGUS" }), nil)
end)

test("ToastModel: NewPayload copies every GAIN field and never aliases the scratch", function()
  local g = NS.GainFeed:Begin("ITEM")
  g.id, g.qty, g.link, g.name, g.quality, g.source = 7, 2, "|cff|Hitem:7|h[Apple]|h|r", "Apple", 1, "KILL"
  local p = M().NewPayload(g)
  assertFalse(p == g, "the payload is its own table")
  for _, k in ipairs(NS.GainFeed.FIELDS) do assertEqual(p[k], g[k], k) end
  NS.GainFeed:Begin("GOLD")
  assertEqual(p.kind, "ITEM", "the next send's reset does not reach the payload")
  assertEqual(p.qty, 2)
  M().FreePayload(p)
end)

test("ToastModel: FreePayload wipes a payload onto the spare list, and NewPayload reuses it", function()
  local p = M().NewPayload(gain{ kind = "ITEM", id = 7 })
  p.value = 10
  M().FreePayload(p)
  assertEqual(next(p), nil, "the freed payload is wiped")
  local q = M().NewPayload(gain{ kind = "GOLD", qty = 5 })
  assertTrue(q == p, "the spare is taken")
  assertEqual(q.kind, "GOLD")
  assertEqual(q.value, nil, "no field outlives the free")
  M().FreePayload(q)
  M().FreePayload(nil)   -- nothing to free, nothing raised
end)

test("ToastModel: Merge sums qty into old, frees new and answers old", function()
  local old = M().NewPayload(gain{ kind = "ITEM", id = 7, qty = 2 })
  local new = M().NewPayload(gain{ kind = "ITEM", id = 7, qty = 3 })
  local spares = #M()._spares
  local out = M().Merge(old, new, "i:7")
  assertTrue(out == old)
  assertEqual(old.qty, 5)
  assertEqual(next(new), nil, "the newer payload is wiped")
  assertEqual(#M()._spares, spares + 1, "and handed back to the spare list")
  M().FreePayload(old)
end)

test("ToastModel: Merge sums a cached price only when both sides carry one", function()
  local old = M().NewPayload(gain{ kind = "ITEM", id = 7, qty = 1 })
  local new = M().NewPayload(gain{ kind = "ITEM", id = 7, qty = 1 })
  old.value, old.vendor, new.value = 100, 40, 100
  M().Merge(old, new)
  assertEqual(old.value, 200)
  assertEqual(old.vendor, nil, "a side that never priced leaves the sum unknown: the next paint prices it")
  M().FreePayload(old)
end)

test("ToastModel: Merge refreshes the moving fields and keeps a skill-up's first rank", function()
  local old = M().NewPayload(gain{ kind = "SKILL", id = 186, qty = 1, old = 150, new = 151, max = 300 })
  local new = M().NewPayload(gain{ kind = "SKILL", id = 186, qty = 1, old = 151, new = 152, max = 300 })
  M().Merge(old, new)
  assertEqual(old.qty, 2)
  assertEqual(old.old, 150, "the first rank is kept")
  assertEqual(old.new, 152, "the newest rank wins")
  local rep = M().NewPayload(gain{ kind = "REPUTATION", id = 72, qty = 10, standing = 100, threshold = 3000 })
  M().Merge(rep, M().NewPayload(gain{ kind = "REPUTATION", id = 72, qty = 15, standing = 115, threshold = 3000 }))
  assertEqual(rep.qty, 25)
  assertEqual(rep.standing, 115)
  M().FreePayload(old)
  M().FreePayload(rep)
end)

test("ToastModel: Merge keeps a level-up gained inside the window (levelUp is ORed, level moves)", function()
  -- red under: levelUp among the moving fields, so a kill's levelUp = false after a turn-in's ding
  -- wipes the toast's "Level N" line.
  local old = M().NewPayload(gain{ kind = "XP", qty = 500, level = 11, levelUp = true, cur = 50, max = 1100 })
  M().Merge(old, M().NewPayload(gain{ kind = "XP", qty = 30, level = 11, levelUp = false, cur = 80, max = 1100 }))
  assertEqual(old.qty, 530)
  assertTrue(old.levelUp, "the level gained stays gained")
  assertEqual(old.cur, 80, "the newest read still moves")
  local plain = M().NewPayload(gain{ kind = "XP", qty = 10, level = 11, levelUp = false })
  M().Merge(plain, M().NewPayload(gain{ kind = "XP", qty = 900, level = 12, levelUp = true }))
  assertTrue(plain.levelUp, "a later ding marks the merged toast")
  assertEqual(plain.level, 12)
  M().FreePayload(old)
  M().FreePayload(plain)
end)

test("ToastModel: Merge shows an appearance burst's latest look and carries a highlight forward", function()
  local old = M().NewPayload(gain{ kind = "APPEARANCE", id = 1, itemID = 10, name = "First" })
  local new = M().NewPayload(gain{ kind = "APPEARANCE", id = 2, itemID = 20, name = "Second" })
  new.highlight = "appearance"
  M().Merge(old, new)
  assertEqual(old.qty, 2)
  assertEqual(old.name, "Second")
  assertEqual(old.itemID, 20)
  assertEqual(old.highlight, "appearance")
  local item = M().NewPayload(gain{ kind = "ITEM", id = 7, name = "Apple" })
  M().Merge(item, M().NewPayload(gain{ kind = "ITEM", id = 7, name = "Renamed" }))
  assertEqual(item.name, "Apple", "an item keeps its own name")
  M().FreePayload(old)
  M().FreePayload(item)
end)

test("ToastModel: Merge with a non-table side answers the newer payload untouched", function()
  local new = { kind = "ITEM", qty = 1 }
  assertTrue(M().Merge(nil, new) == new)
  assertEqual(new.qty, 1)
end)

-- ── the descriptor getters (§7.1) ────────────────────────────────────────────────────────────

test("ToastModel: LayoutFor maps the placement and size leaves, grow upper-cased", function()
  withFeed("main", { slot = "TOP", x = 12, y = -34, grow = "down", shown = 7, width = 300, rowHeight = 40,
                     iconSize = 30, padding = 4, gap = 3, align = "right", iconSide = "right" }, function()
    local t = M().LayoutFor("main")
    assertEqual(t.slot, "TOP"); assertEqual(t.x, 12); assertEqual(t.y, -34)
    assertEqual(t.grow, "DOWN")
    assertEqual(t.shown, 7); assertEqual(t.width, 300); assertEqual(t.rowHeight, 40)
    assertEqual(t.iconSize, 30); assertEqual(t.padding, 4); assertEqual(t.gap, 3)
    assertEqual(t.align, "right"); assertEqual(t.iconSide, "right")
    assertTrue(M().LayoutFor("main") == t, "the same table each call")
  end)
  withFeed("main", { grow = "up" }, function() assertEqual(M().LayoutFor("main").grow, "UP") end)
end)

test("ToastModel: the Main feed's default layout is Bottom Right, growing up, nudged clear of the bars", function()
  local t = M().LayoutFor("main")
  assertEqual(t.slot, "BOTTOMRIGHT"); assertEqual(t.grow, "UP")
  assertEqual(t.x, -220); assertEqual(t.y, 180)
  assertTrue(math.abs(t.x) <= C.TOAST_NUDGE_MAX and math.abs(t.y) <= C.TOAST_NUDGE_MAX,
    "the default nudge sits inside the Feed's clamp")
end)

test("ToastModel: MotionFor renames fade and merge, fixes right-click dismiss and the settle", function()
  withFeed("main", { enter = "left", enterTime = 0.4, hold = 7, fade = 2, merge = 4, pulse = false,
                     timerBar = true, smooth = false, pin = false }, function()
    local t = M().MotionFor("main")
    assertEqual(t.enter, "left", "stored in the Feed's own vocabulary")
    assertEqual(t.enterTime, 0.4); assertEqual(t.hold, 7)
    assertEqual(t.fadeTime, 2); assertEqual(t.mergeWindow, 4)
    assertFalse(t.pulse); assertTrue(t.timerBar); assertFalse(t.smooth); assertFalse(t.pin)
    assertTrue(t.rightDismiss, "right-click dismiss is not a setting (D14)")
    assertEqual(t.settle, C.TOAST_COUNT_SETTLE)
    assertEqual(t.fade, nil, "no stored leaf name leaks into the Feed's table")
    assertEqual(t.merge, nil)
    assertTrue(M().MotionFor("main") == t, "the same table each call")
  end)
end)

test("ToastModel: StyleFor passes the stored leaves through and maps the three toggles", function()
  withFeed("main", { borderByQuality = true, useClassColorBorder = true, useClassColorFont = false,
                     bgType = "gradient", fontSize = 15, fontSize2 = 9 }, function()
    local t = M().StyleFor("main")
    assertEqual(t.bgType, "gradient"); assertEqual(t.fontSize, 15); assertEqual(t.fontSize2, 9)
    assertTrue(t.bgColorFromSkin); assertTrue(t.fontFromSkin)
    assertTrue(t.bgColor == feedRow("main").bgColor, "a stored color is handed over as is")
    assertTrue(t.borderTint, "borderByQuality -> borderTint")
    assertTrue(t.borderClass, "useClassColorBorder -> borderClass")
    assertFalse(t.fontClass, "useClassColorFont -> fontClass")
    assertFalse(t.fontSizeFromSkin, "the stored font sizes always draw")
    assertEqual(t.borderByQuality, nil, "no stored leaf name leaks into the Feed's table")
    assertEqual(t.barTextureFromSkin, nil, "the bar and glow keys are left to the Feed's skin defaults")
    assertTrue(M().StyleFor("main") == t, "the same table each call")
  end)
end)

-- Every style key the Feed reads from the profile, with the value the fixture stores (§7.1).
local STYLE_FIXTURE = {
  bgType = "texture", bgColor = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 }, bgColor2 = { r = 0.5, g = 0.6, b = 0.7, a = 0.8 },
  bgTexture = "Blizzard Tooltip", borderStyle = "Blizzard Tooltip", borderSize = 3,
  borderColor = { r = 0.9, g = 0.8, b = 0.7, a = 1 }, font = "Friz Quadrata TT", fontSize = 16, fontSize2 = 12,
  fontFlags = "OUTLINE", fontShadow = false, fontColor = { r = 0.25, g = 0.5, b = 0.75, a = 1 },
}
local STYLE_COMPANIONS = { "bgColorFromSkin", "borderStyleFromSkin", "borderColorFromSkin", "fontFromSkin",
                           "fontShadowFromSkin", "fontColorFromSkin" }

local function styleFixture(fromSkin, toggles)
  local over = {}
  for k, v in pairs(STYLE_FIXTURE) do over[k] = v end
  for _, k in ipairs(STYLE_COMPANIONS) do over[k] = fromSkin end
  over.borderByQuality, over.useClassColorBorder, over.useClassColorFont = toggles, toggles, toggles
  return over
end

test("ToastModel: StyleFor maps every style key from a fixture, FromSkin off (every override)", function()
  withFeed("main", styleFixture(false, true), function(f)
    local t = M().StyleFor("main")
    for k, v in pairs(STYLE_FIXTURE) do assertTrue(t[k] == v, k .. " handed over as stored") end
    for _, k in ipairs(STYLE_COMPANIONS) do assertEqual(t[k], false, k) end
    assertTrue(t.borderTint); assertTrue(t.borderClass); assertTrue(t.fontClass)
    assertFalse(t.fontSizeFromSkin)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    local want = 0
    for _ in pairs(STYLE_FIXTURE) do want = want + 1 end
    assertEqual(n, want + #STYLE_COMPANIONS + 4, "no key beyond the mapped ones")
    assertTrue(t.fontColor == f.fontColor)
  end)
end)

test("ToastModel: StyleFor with every FromSkin on keeps the overrides stored but drawn from the skin", function()
  withFeed("main", styleFixture(true, false), function()
    local t = M().StyleFor("main")
    for _, k in ipairs(STYLE_COMPANIONS) do assertEqual(t[k], true, k) end
    assertFalse(t.borderTint); assertFalse(t.borderClass); assertFalse(t.fontClass)
    assertFalse(t.fontSizeFromSkin, "font size is a stored value under the skin too (cause L11)")
    assertEqual(t.fontSize, 16, "the stored size still draws")
  end)
end)

test("ToastModel: the default style draws the skin, an empty font is left to the Feed", function()
  local t = M().StyleFor("main")
  for _, k in ipairs(STYLE_COMPANIONS) do assertEqual(t[k], true, k .. " on by default (skin by default, D12)") end
  assertFalse(t.borderTint); assertFalse(t.borderClass); assertFalse(t.fontClass)
  assertEqual(feedRow("main").font, "", "the profile stores the skin's own as an empty name")
  assertEqual(t.font, nil, "and the Feed sees no font name")
  assertEqual(t.fontSize, 13); assertEqual(t.fontSize2, 11)
end)

test("ToastModel: MotionFor maps the defaults and every enter word, and leaves an unknown one out", function()
  local t = M().MotionFor("main")
  assertEqual(t.enter, "right"); assertEqual(t.enterTime, 0.3); assertEqual(t.hold, 5)
  assertEqual(t.fadeTime, 1); assertEqual(t.mergeWindow, 3)
  assertTrue(t.pulse); assertFalse(t.timerBar); assertTrue(t.smooth); assertTrue(t.pin)
  for _, word in ipairs({ "none", "fade", "left", "right", "up", "down" }) do
    withFeed("main", { enter = word }, function() assertEqual(M().MotionFor("main").enter, word) end)
  end
  withFeed("main", { enter = "slideRight" }, function()
    assertEqual(M().MotionFor("main").enter, nil, "a word the Feed does not know: its default applies")
  end)
end)

test("ToastModel: each feed's getters answer its own table from its own leaves", function()
  withFeed("extra", { bgColorFromSkin = false, fontSize = 18, enter = "up", hold = 9 }, function()
    assertEqual(M().StyleFor("extra").bgColorFromSkin, false)
    assertEqual(M().StyleFor("main").bgColorFromSkin, true, "Main keeps the skin")
    assertEqual(M().StyleFor("extra").fontSize, 18)
    assertEqual(M().MotionFor("extra").enter, "up"); assertEqual(M().MotionFor("extra").hold, 9)
    assertTrue(M().StyleFor("extra") ~= M().StyleFor("main"), "one table per feed")
    assertTrue(M().MotionFor("extra") ~= M().MotionFor("main"))
  end)
end)

test("ToastModel: a getter for a feed with no stored settings answers an empty table", function()
  assertEqual(next(M().LayoutFor("nope")), nil)
  assertEqual(next(M().MotionFor("nope")), nil)
  assertEqual(next(M().StyleFor("nope")), nil)
end)

-- ── the first content cut (§7.4) ─────────────────────────────────────────────────────────────

local function content(p)
  local spec = { lines = { {}, {}, {} } }
  local res = NS.ToastContent.Content("main", spec, p, M().Key(p))
  return spec, res
end

test("ToastContent: an item fills its icon, quality tint, title and count", function()
  local spec, res = content({ kind = "ITEM", id = 7, qty = 3, name = "Apple", quality = 2, icon = 1234 })
  assertEqual(res, nil, "drawn")
  assertEqual(spec.icon, 1234)
  assertEqual(spec.title, "Apple")
  assertEqual(spec.count, "x3")
  local r, g, b = NS.QualityColor(2)
  if r then
    assertEqual(spec.tint.r, r); assertEqual(spec.tint.g, g); assertEqual(spec.tint.b, b)
    assertTrue(spec.titleColor == spec.tint, "the name is drawn in its quality color")
  end
  assertEqual(spec.countColor, nil, "the Feed draws the count in the glow color while it pulses")
end)

test("ToastContent: an item with no icon falls back to the client, then the question mark", function()
  local saved = NS.Compat.ItemIcon
  NS.Compat.ItemIcon = function() return nil end
  local ok, err = pcall(function()
    assertEqual(content({ kind = "ITEM", id = 7, qty = 1, name = "Apple" }).icon, C.TOAST_ICON_UNKNOWN)
    NS.Compat.ItemIcon = function(id) return id == 7 and 5555 or nil end
    assertEqual(content({ kind = "ITEM", id = 7, qty = 1, name = "Apple" }).icon, 5555)
  end)
  NS.Compat.ItemIcon = saved
  if not ok then error(err, 0) end
end)

test("ToastContent: money, experience and reputation take the kind art and their own titles", function()
  local spec = content({ kind = "GOLD", qty = 12345 })
  assertEqual(spec.icon, C.TOAST_KIND_ICON.GOLD)
  assertEqual(spec.title, NS.Util.FormatMoney(12345))
  assertEqual(spec.count, nil, "money carries no count chip")
  spec = content({ kind = "XP", qty = 1500 })
  assertEqual(spec.icon, C.TOAST_KIND_ICON.XP)
  assertEqual(spec.title, "+" .. NS.Compat.FormatCount(1500) .. " XP")
  spec = content({ kind = "REPUTATION", id = 72, qty = 250, name = "Stormwind" })
  assertEqual(spec.icon, C.TOAST_KIND_ICON.REPUTATION)
  assertTrue(spec.title:find("Stormwind", 1, true) ~= nil, "the faction's name, after its delta (§7.4)")
  assertEqual(spec.tint, nil, "reputation carries no quality")
end)

test("ToastContent: a payload of no known kind is skipped", function()
  local _, res = content({ kind = "BOGUS" })
  assertEqual(res, false)
  local _, res2 = content(nil)
  assertEqual(res2, false)
end)

-- ── the appearance absorb (§7.3) ─────────────────────────────────────────────────────────────

--- A live feed, held (a push waits, so Get answers it with no clock to step), whose Repaint and
--- Dismiss are recorded on the way through.
local function heldFeed()
  local f = NS.FeedLib:New({ content = function() end })
  f:Hold()
  local calls = { repaint = {}, dismiss = {} }
  local repaint, dismiss = f.Repaint, f.Dismiss
  f.Repaint = function(self, key) calls.repaint[#calls.repaint + 1] = key; return repaint(self, key) end
  f.Dismiss = function(self, key) calls.dismiss[#calls.dismiss + 1] = key; return dismiss(self, key) end
  return f, calls
end

test("ToastModel: Absorb folds a new appearance into its item already on the feed", function()
  local f, calls = heldFeed()
  local p = M().NewPayload(gain({ kind = "ITEM", id = 7, quality = 3 }))
  assertEqual(f:Push("i:7", p), "queued")
  local used = M().Absorb(f, gain({ kind = "APPEARANCE", id = 900, itemID = 7, newLook = true }))
  assertTrue(used, "the appearance is consumed")
  assertTrue(p.lookGot, "collected")
  assertTrue(p.newLook, "the item's payload gains the look")
  assertEqual(p.highlight, "appearance")
  assertEqual(table.concat(calls.repaint, ","), "i:7", "and the item's toast is repainted")
  assertFalse(M().Absorb(f, gain({ kind = "APPEARANCE", id = 901, itemID = 8 })), "no toast for item 8")
  assertFalse(M().Absorb(f, gain({ kind = "APPEARANCE", id = 902 })), "no item named")
  f:Clear()
end)

test("ToastModel: Absorb of a known visual's other source marks it collected, never new", function()
  -- red under: an absorb that sets newLook and the appearance highlight whatever g.newLook says,
  -- so a second source of a look the player owns lights the "New appearances" glow.
  local f = heldFeed()
  local p = M().NewPayload(gain({ kind = "ITEM", id = 7, quality = 3 }))
  f:Push("i:7", p)
  assertTrue(M().Absorb(f, gain({ kind = "APPEARANCE", id = 900, itemID = 7, newLook = false })))
  assertTrue(p.lookGot, "the item still says the appearance was collected")
  assertEqual(p.newLook, nil, "not a new look")
  assertEqual(p.highlight, nil, "no appearance highlight")
  f:Clear()
  local g = heldFeed()
  g:Push("a", M().NewPayload(gain({ kind = "APPEARANCE", id = 900, itemID = 7, newLook = false })))
  local used, look, new = M().Absorb(g, gain({ kind = "ITEM", id = 7 }))
  assertFalse(used); assertTrue(look, "the item takes the look over")
  assertFalse(new, "and is told it was a known visual")
  g:Clear()
end)

test("ToastModel: Absorb lets an item take over a one-look appearance toast for it", function()
  local f, calls = heldFeed()
  assertEqual(f:Push("a", M().NewPayload(gain({ kind = "APPEARANCE", id = 900, itemID = 7, newLook = true }))), "queued")
  local used, look, new = M().Absorb(f, gain({ kind = "ITEM", id = 8 }))
  assertFalse(used); assertEqual(look, nil, "another item leaves the appearance alone")
  assertEqual(#calls.dismiss, 0)
  assertEqual(new, nil)
  used, look, new = M().Absorb(f, gain({ kind = "ITEM", id = 7 }))
  assertFalse(used, "the item itself still pushes")
  assertTrue(look, "with the look marked")
  assertTrue(new, "a new look")
  assertEqual(table.concat(calls.dismiss, ","), "a", "and the appearance toast is dismissed")
  assertEqual(f:Get("a"), nil)
  f:Clear()
  -- A burst of looks under the one key is not one item's.
  local g, calls2 = heldFeed()
  local a = M().NewPayload(gain({ kind = "APPEARANCE", id = 900, itemID = 7, qty = 2 }))
  g:Push("a", a)
  local _, look2 = M().Absorb(g, gain({ kind = "ITEM", id = 7 }))
  assertEqual(look2, nil, "two looks are not absorbed")
  assertEqual(#calls2.dismiss, 0)
  g:Clear()
end)

test("ToastModel: Absorb ignores every other kind and a missing feed", function()
  local f = heldFeed()
  assertFalse(M().Absorb(f, gain({ kind = "GOLD", qty = 5 })))
  assertFalse(M().Absorb(nil, gain({ kind = "APPEARANCE", itemID = 7 })))
  assertFalse(M().Absorb(NS.FeedStub, gain({ kind = "APPEARANCE", itemID = 7 })), "the stub answers no payload")
  f:Clear()
end)
