-- tests/test_browser_footer.lua — the History window's footer is the library's W.Footer (AD-89-LH).
--
-- Standard v2.110.0, standalone-windows' *The footer* and *Window chrome geometry*: a window's footer
-- is LibKa0s-Widgets-1.0's `Footer` (Widgets minor 27), FOOTER.HEIGHT (24) tall under every skin, no
-- fill of its own under a hairline, its lines in `text.muted`, the resize grip in its corner with the
-- right line clear of it. The host owns the words: "Showing X of Y" (B:UpdateFooter) on the left and
-- "Database ~<size>" (B:UpdateDbSize) on the right. Until this adoption the window drew its own 18 px
-- band (FOOTER_H, the Shell's bottomBar) and two loose font strings. The panes end FOOTER.HEIGHT above
-- the window's bottom edge, so nothing the body draws passes under the hairline.
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local W = T.mocks.LibStub("LibKa0s-Widgets-1.0")

-- The last anchor recorded for `point` on `f` (the mock's __points list).
local function pointOf(f, point)
  local found
  for _, p in ipairs(f.__points or {}) do
    if p.point == point then found = p end
  end
  return found
end

local function withWindow(ns, fn)
  local B = ns.Browser
  local s = ns.db.profile.settings
  local savedVis = s.visibility
  s.visibility = "always"
  local ok, err = pcall(function()
    B:Show()
    fn(B, B:GetWindow())
  end)
  B:Hide()
  s.visibility = savedVis
  if not ok then error(err, 0) end
end

test("footer: the History window's footer is the library's W.Footer across its bottom edge", function()
  withWindow(NS, function(B, f)
    local foot = f.footer
    assertTrue(foot ~= nil, "the window keeps its footer as f.footer")
    assertTrue(foot.line ~= nil and foot.left ~= nil and foot.right ~= nil,
      "the footer is W.Footer's (its hairline and its two lines)")
    -- The height is the library's constant (its own suite pins the frame at it); the shared mock
    -- answers a texture with its frame, so the hairline's 1px SetHeight lands on the footer here.
    assertEqual(W.FOOTER.HEIGHT, 24, "the published footer height")
    local bl, br = pointOf(foot, "BOTTOMLEFT"), pointOf(foot, "BOTTOMRIGHT")
    assertTrue(bl and bl.relativeTo == f and br and br.relativeTo == f, "it spans the window's bottom edge")
    assertTrue(B._footer == foot.left, "the record count is the footer's left line")
    assertTrue(B._dbFooter == foot.right, "the database size is the footer's right line")
  end)
end)

test("footer: its lines keep their words, the count on the left and the database size on the right", function()
  withWindow(NS, function(B)
    B:UpdateFooter()
    B:UpdateDbSize()
    assertTrue(B._footer:GetText():find("^Showing ") ~= nil, "left: " .. tostring(B._footer:GetText()))
    assertTrue(B._dbFooter:GetText():find("^Database ~") ~= nil, "right: " .. tostring(B._dbFooter:GetText()))
  end)
end)

test("footer: every pane ends FOOTER.HEIGHT above the window's bottom edge", function()
  withWindow(NS, function(_, f)
    for name, pane in pairs(f.panes) do
      local p = pointOf(pane, "BOTTOMRIGHT")
      assertTrue(p ~= nil and p.relativeTo == f, name .. " pane is anchored to the window's bottom right")
      assertEqual(p.y, W.FOOTER.HEIGHT, name .. " pane clears the footer")
    end
  end)
end)

test("footer: the resize grip sits in the footer's corner, and the right line clears it", function()
  withWindow(NS, function(_, f)
    local grip = f.resizeGrip
    assertTrue(grip ~= nil, "the window resizes")
    local p = pointOf(grip, "BOTTOMRIGHT")
    assertTrue(p ~= nil and p.relativeTo == f.footer, "the grip is built on the footer (gripParent)")
    local r = pointOf(f.footer.right, "RIGHT")
    assertTrue(r ~= nil, "the right line has a RIGHT anchor")
    assertEqual(r.x, -W.FOOTER.GRIP, "the right line starts FOOTER.GRIP in, clear of the grip")
  end)
end)
