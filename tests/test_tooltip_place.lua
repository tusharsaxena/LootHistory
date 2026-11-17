-- tests/test_tooltip_place.lua — where this addon's tooltips open (AD-92-LH, LibKa0s#92).
--
-- WowAddonStandards standalone-windows, *Tooltip placement* (v2.112.0, the chrome side v2.113.0): a
-- BODY element's tooltip opens beside the window group, right when it fits and otherwise left, its
-- top level with the element's top, 2 px off the group's outer edge; a CHROME element's is attached
-- and centered above the element, below it only without room above; never the cursor, never a
-- corner offset. core/Compat.lua's PlaceTooltip is the one host seam onto LibKa0s-Tooltip-1.0's
-- placers, and every Show* helper there owns at ANCHOR_NONE, shows, then places.
--
-- The geometry cases drive the kit's fake screen (tests/_kit/mock_screen.lua, kit revision 57)
-- through a right-fits and a right-does-not-fit layout, as the rule's Verification bullet asks. The
-- per-surface cases live beside each surface's own suite (tests/tip_spy.lua); the last case here is
-- the static guard over the shipped source.

local T = _G.LH_TEST
local NS, M, Loader = T.NS, T.mocks, T.Loader
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local Tip = M.LibStub("LibKa0s-Tooltip-1.0", true)

-- Build a fake screen and a recording tooltip in GameTooltip's place for the length of `fn`.
local function onScreen(fn)
  local scr = dofile("tests/_kit/mock_screen.lua")(M, { width = 1920, height = 1080 })
  local saved = M.GameTooltip
  local tip = scr.tooltip{ width = 200, height = 80 }
  M.GameTooltip = tip
  local ok, err = pcall(fn, scr, tip)
  M.GameTooltip = saved
  scr.restore()
  if not ok then error(err, 0) end
end

test("tooltip placement: LibKa0s-Tooltip-1.0 is loaded for core/Compat.lua to place through", function()
  assertTrue(Tip ~= nil, "the vendored Tooltip major is loaded headless")
  assertEqual(Tip.TIP_GAP, 2, "the gap the rule names")
  for _, m in ipairs({ "OwnTooltip", "PlaceTooltip" }) do
    assertTrue(type(NS.Compat[m]) == "function", "core/Compat.lua publishes " .. m)
  end
  assertEqual(NS.Compat.ShowCursorTooltip, nil, "the cursor-pinned helper is retired")
end)

test("tooltip placement: a body tooltip opens right of the window, level with the row, 2 px off", function()
  onScreen(function(scr, tip)
    local win = scr.frame{ left = 100, bottom = 300, width = 600, height = 400 }
    local row = scr.frame{ left = 100, bottom = 600, width = 600, height = 20, parent = win }
    NS.Compat.OwnTooltip(row)
    assertEqual(tip.__anchor, "ANCHOR_NONE", "owned at ANCHOR_NONE, never a corner or the cursor")
    assertEqual(NS.Compat.PlaceTooltip(row), "right")
    local l, _, _, t = scr.rectOf(tip)
    assertEqual(l, 702, "the tooltip's left edge is the window's right edge + 2")
    assertEqual(t, 620, "its top is level with the row's top")
    assertEqual(tip:GetAnchorType(), "ANCHOR_RIGHT", "comparison tooltips open further right")
  end)
end)

test("tooltip placement: with no room on the right a body tooltip opens left of the window", function()
  onScreen(function(scr, tip)
    local win = scr.frame{ left = 1300, bottom = 300, width = 600, height = 400 }
    local row = scr.frame{ left = 1300, bottom = 400, width = 600, height = 20, parent = win }
    NS.Compat.OwnTooltip(row)
    assertEqual(NS.Compat.PlaceTooltip(row, "body"), "left")
    local _, _, r, t = scr.rectOf(tip)
    assertEqual(r, 1298, "the tooltip's right edge is the window's left edge - 2")
    assertEqual(t, 420, "its top is level with the row's top")
    assertEqual(tip:GetAnchorType(), "ANCHOR_LEFT")
  end)
end)

test("tooltip placement: a chrome tooltip is centered 2 px above its control, below only at the top", function()
  onScreen(function(scr, tip)
    local win = scr.frame{ left = 100, bottom = 300, width = 600, height = 400 }
    local btn = scr.frame{ left = 300, bottom = 640, width = 100, height = 20, parent = win }
    NS.Compat.OwnTooltip(btn)
    assertEqual(NS.Compat.PlaceTooltip(btn, "chrome"), "above")
    local l, b, r = scr.rectOf(tip)
    assertEqual(b, 662, "its bottom is the control's top + 2")
    assertEqual((l + r) / 2, 350, "centered on the control")
    btn:__place(300, 1040, 100, 20)
    assertEqual(NS.Compat.PlaceTooltip(btn, "chrome"), "below", "no room above: flipped below")
    local _, _, _, t = scr.rectOf(tip)
    assertEqual(t, 1038, "its top is the control's bottom - 2")
  end)
end)

test("tooltip placement: a function place (the Charts host's ctx:PlaceTip) places it instead", function()
  onScreen(function(scr, tip)
    local mark = scr.frame{ left = 300, bottom = 500, width = 10, height = 10 }
    local seen
    local side = NS.Compat.PlaceTooltip(mark, function(tt, owner) seen = { tt, owner }; return "left" end)
    assertEqual(side, "left", "the function's answer is the side")
    assertTrue(seen and seen[1] == tip and seen[2] == mark, "called with the tooltip and the element")
  end)
end)

-- Late growth (the Tooltip docs' step 4): an item whose data was not cached grows its tooltip after
-- Show, and the placement is one absolute TOPLEFT point, so it grows downward. Each time the tooltip
-- changes size while the element it was placed for still owns it, core/Compat.lua runs the library's
-- Replace, which re-runs the same placer and re-clamps. red under: a placement made once and never
-- again (the bottom runs off the screen), or a re-place of a tooltip someone else now owns.
test("tooltip placement: a tooltip that grows after Show is placed again, only while still ours", function()
  onScreen(function(scr, tip)
    local win = scr.frame{ left = 100, bottom = 10, width = 600, height = 400 }
    local row = scr.frame{ left = 100, bottom = 30, width = 600, height = 20, parent = win }
    assertTrue(NS.Compat.ShowItemTooltip(row, "|Hitem:7|h[Apple]|h"), "the item tooltip drew")
    local _, b, _, t = scr.rectOf(tip)
    assertEqual(t, 80, "first placed with its 80 px clamped onto the screen, its bottom on 0")
    assertEqual(b, 0)
    tip:__size(200, 300)
    tip:__fire("OnSizeChanged", 200, 300)
    _, b, _, t = scr.rectOf(tip)
    assertEqual(b, 0, "grown to 300 px: placed again, its bottom kept on the screen")
    assertEqual(t, 300, "and its top moved up to make room")
    -- Owned by something else now (another addon's hover): its growth is not ours to place.
    local other = scr.frame{ left = 900, bottom = 500, width = 20, height = 20 }
    tip:SetOwner(other, "ANCHOR_NONE")
    local before = #tip.__log
    tip:__size(200, 400)
    tip:__fire("OnSizeChanged", 200, 400)
    assertEqual(#tip.__log, before, "a tooltip another owner holds is left where that owner put it")
    -- Ours again, then hidden: nothing to place either.
    assertTrue(NS.Compat.ShowItemTooltip(row, "|Hitem:7|h[Apple]|h"), "the item tooltip drew again")
    tip:Hide()
    before = #tip.__log
    tip:__fire("OnSizeChanged", 200, 400)
    assertEqual(#tip.__log, before, "a hidden tooltip is not placed")
  end)
end)

-- The fallback: unreadable geometry, or no Tooltip major at all (a degraded install). red under: the
-- cursor, a corner anchor, or nothing placed at all.
test("tooltip placement: unreadable geometry or no Tooltip major attaches it above the element", function()
  local tt = M.GameTooltip
  local points, stock = {}, { SetPoint = rawget(tt, "SetPoint"), ClearAllPoints = rawget(tt, "ClearAllPoints") }
  rawset(tt, "SetPoint", function(self, ...) points[#points + 1] = { ... }; return self end)
  rawset(tt, "ClearAllPoints", function(self) points = {}; return self end)
  local savedLS = M.LibStub
  local ok, err = pcall(function()
    local el = M.CreateFrame("Frame")   -- the base mock's geometry reads answer no numbers
    assertEqual(NS.Compat.PlaceTooltip(el), "attached", "a placer that read nothing falls back")
    assertEqual(#points, 1)
    local p = points[1]
    assertTrue(p[1] == "BOTTOM" and p[2] == el and p[3] == "TOP" and p[4] == 0 and p[5] == 2,
      "BOTTOM on the element's TOP, 2 px up")
    points = {}
    M.LibStub = setmetatable({}, { __call = function(_, major, silent)
      if major == "LibKa0s-Tooltip-1.0" then return nil end
      return savedLS(major, silent)
    end, __index = savedLS })
    assertEqual(NS.Compat.PlaceTooltip(el, "chrome"), "attached", "no Tooltip major: attached all the same")
    assertTrue(points[1] and points[1][1] == "BOTTOM" and points[1][3] == "TOP", "above the element")
  end)
  M.LibStub = savedLS
  rawset(tt, "SetPoint", stock.SetPoint); rawset(tt, "ClearAllPoints", stock.ClearAllPoints)
  if not ok then error(err, 0) end
end)

-- Every Show* helper: owned at ANCHOR_NONE, filled, shown, and only then placed, with the caller's
-- `place` passed through. red under: the helpers' old ANCHOR_RIGHT default, or a place before Show.
test("tooltip placement: every Compat Show* helper owns at ANCHOR_NONE and places after Show", function()
  local tipSpy = dofile("tests/tip_spy.lua")(NS, M)
  local C, owner = NS.Compat, M.CreateFrame("Frame")
  local cases = {
    { "ShowItemTooltip", function(p) return C.ShowItemTooltip(owner, "|Hitem:7|h[Apple]|h", p) end },
    { "ShowCurrencyTooltip", function(p) return C.ShowCurrencyTooltip(owner, 3008, p) end },
    { "ShowTextTooltip", function(p) return C.ShowTextTooltip(owner, "Title", "Body", p) end },
    { "ShowLineTooltip", function(p) return C.ShowLineTooltip(owner, "3 drops", nil, p) end },
    { "ShowAmountTooltip", function(p) return C.ShowAmountTooltip(owner, "Gold", nil, "Amount", "5g", nil, p) end },
    { "ShowLinesTooltip", function(p) return C.ShowLinesTooltip(owner, "Day", { { label = "Net", text = "0" } }, p) end },
    { "ShowTintedTooltip", function(p) return C.ShowTintedTooltip(owner, { { "Name" } }, p) end },
  }
  for _, c in ipairs(cases) do
    M.GameTooltip:Hide()
    local got = tipSpy(function() assertTrue(c[2](nil), c[1] .. " drew") end)
    tipSpy.assertBody(got, owner, c[1] .. " by default")
    M.GameTooltip:Hide()
    got = tipSpy(function() c[2]("chrome") end)
    tipSpy.assertChrome(got, owner, c[1] .. " with place = \"chrome\"")
  end
  M.GameTooltip:Hide()
end)

-- The static guard (anti-pattern #119): no shipped file of this addon anchors a tooltip anywhere but
-- ANCHOR_NONE, and none reads the cursor to place one. Comments are stripped first, because the
-- modules explain these very anchors in prose. The allowlist is closed, each entry with its reason:
local ALLOWED = {
  -- The Blizzard Settings canvas, which the rule does not bind (*What it does not bind*): the AH
  -- price tab's (i) marks keep their ANCHOR_RIGHT (docs/ARCHITECTURE.md, *Tooltip placement*).
  ["settings/PanelAuction.lua"] = { ANCHOR_RIGHT = true },
  -- Not a placement: LibKa0s-Charts-1.0 still hands a host's `tip` its legacy anchor, and a strip
  -- column is the mark it names ANCHOR_TOP; the tooltip itself goes through ctx:PlaceTip.
  ["modules/AnalyticsCharts.lua"] = { ANCHOR_TOP = true },
}

test("tooltip placement: no shipped file anchors a tooltip at a corner or the cursor", function()
  local files, hits = Loader.tocFiles("LootHistory.toc"), {}
  local seen = 0
  for _, path in ipairs(files) do
    if path:match("%.lua$") and not path:match("^libs/") then
      seen = seen + 1
      local n = 0
      for line in (Loader.readFile(path) .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local code = line:gsub("\r$", ""):gsub("%-%-.*$", "")
        for anchor in code:gmatch("ANCHOR_[%u_]+") do
          if anchor ~= "ANCHOR_NONE" and not (ALLOWED[path] and ALLOWED[path][anchor]) then
            hits[#hits + 1] = path .. ":" .. n .. " " .. anchor
          end
        end
        if code:find("GetCursorPosition", 1, true) then hits[#hits + 1] = path .. ":" .. n .. " GetCursorPosition" end
      end
    end
  end
  assertTrue(seen > 20, "the TOC lists the addon's files, so the guard read them")
  assertEqual(#hits, 0, "tooltip anchors the placement rule retires:\n  " .. table.concat(hits, "\n  "))
end)
