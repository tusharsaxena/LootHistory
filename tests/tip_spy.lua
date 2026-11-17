-- tests/tip_spy.lua — where a hover placed its tooltip (AD-92-LH, LibKa0s#92; WowAddonStandards
-- standalone-windows, *Tooltip placement*). Shared by every suite that owns a tooltip surface.
--
--   local tipSpy = dofile("tests/tip_spy.lua")(NS, mocks)
--   local got = tipSpy(function() row:GetScript("OnEnter")(row) end)
--   tipSpy.assertBody(got, row, "a History row")      -- beside the window group
--   tipSpy.assertChrome(got, strip, "the mode strip") -- attached above the element
--
-- It records, for the length of `fn`, every NS.Compat.PlaceTooltip call (owner, how, and whether
-- GameTooltip was already shown, since a placer measures a shown tooltip) and every anchor
-- GameTooltip:SetOwner was handed. Both are put back after `fn`, raise or not. PlaceTooltip is a
-- PURE Compat member (core/SimSeam.lua), so swapping it leaves the Sim seam's wrap list untouched.
return function(NS, M)
  local spy = {}

  local function run(fn)
    local C, tt = NS.Compat, M.GameTooltip
    local got = { places = {}, anchors = {} }
    local place, own = C.PlaceTooltip, rawget(tt, "SetOwner")
    C.PlaceTooltip = function(owner, how)
      got.places[#got.places + 1] = { owner = owner, how = how, shown = tt:IsShown() }
      return place(owner, how)
    end
    rawset(tt, "SetOwner", function(self, owner, anchor)
      got.anchors[#got.anchors + 1] = anchor
      if own then return own(self, owner, anchor) end
      return self
    end)
    local ok, err = pcall(fn, got)
    C.PlaceTooltip = place
    rawset(tt, "SetOwner", own)
    if not ok then error(err, 0) end
    return got
  end

  local function check(got, owner, label, want)
    assert(#got.places >= 1, label .. ": the hover placed no tooltip through Compat.PlaceTooltip")
    local p = got.places[#got.places]
    assert(p.owner == owner, label .. ": the tooltip was placed against another element")
    assert(p.shown, label .. ": placed before Show, so the placer measured an empty tooltip")
    if want == "chrome" then
      assert(p.how == "chrome", label .. ": a chrome element's tooltip must be attached (got "
        .. tostring(p.how) .. ")")
    else
      assert(p.how == nil or p.how == "body" or type(p.how) == "function",
        label .. ": a body element's tooltip must open beside the window (got " .. tostring(p.how) .. ")")
    end
    assert(#got.anchors >= 1, label .. ": GameTooltip was never owned")
    for _, a in ipairs(got.anchors) do
      assert(a == "ANCHOR_NONE", label .. ": owned at " .. tostring(a) .. ", not ANCHOR_NONE (a cursor or "
        .. "corner anchor, anti-pattern #119)")
    end
    return p
  end

  function spy.assertBody(got, owner, label) return check(got, owner, label, "body") end
  function spy.assertChrome(got, owner, label) return check(got, owner, label, "chrome") end

  return setmetatable(spy, { __call = function(_, fn) return run(fn) end })
end
