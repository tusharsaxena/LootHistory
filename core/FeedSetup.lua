local addonName, NS = ...

-- core/FeedSetup.lua — wires the addon into LibKa0s-Feed-1.0 (library-stack-§7; #38, plan D24).
--
-- The toast feeds (modules/ToastFeed.lua) are drawn by the library: the containers, the slots, grow,
-- alignment and icon side, the merge window, the stack and its full-feed drop, the hover pin, the
-- countdown bar, enter/hold/fade/slide, the pulse, smooth reposition, the glow, style over the skin,
-- unlock and drag, the strips and the preview (LibKa0s docs/api/Feed/version-1.1.1.1-docs.md). This
-- file only leases the major and stamps every descriptor with this addon's skin owner.
--
--   NS.FeedLib    the resolved major (its constants: SLOTS, NUDGE_MAX, SHOWN_MAX, ...), or nil
--   NS.NewFeed(d) d.owner = addonName (the folder name), then Feed:New(d); NS.FeedStub without it
--   NS.FeedStub   the Feed doc's *The degradation stub*, member for member: what an empty, locked
--                 feed answers. One stub serves every feed, because it holds no state.
--
-- CONVENTIONAL position (LootHistory.toc): nothing here resolves at load besides the LibStub lookup,
-- and nothing calls NS.NewFeed at load (Toasts:Enable builds the feeds).

local Feed = LibStub and LibStub("LibKa0s-Feed-1.0", true)   -- silent: a missing major degrades

NS.FeedLib = Feed

NS.FeedStub = {
  Push = function() return false end, Get = function() return nil end,
  Update = function() return false end, Repaint = function() return false end,
  RepaintAll = function() end, Dismiss = function() return false end,
  Clear = function() end, Hold = function() end, Release = function() end,
  Refresh = function() end, Preview = function() return 0 end, ClearPreview = function() end,
  SetLocked = function() return true end, IsLocked = function() return true end,
  SetClickThrough = function() end, SetStrip = function() end,
  Visible = function() return {} end, Frame = function() return nil end,
  Stats = function() return { live = 0, waiting = 0, dropping = 0, frozen = false,
    held = false, locked = true, clickThrough = false, awake = false, shown = 0,
    built = false } end,
}

--- One feed instance for descriptor `d`, its rows, handle and strips following this addon's skin
--- owner; the stateless stub when the major is absent.
function NS.NewFeed(d)
  if not Feed then return NS.FeedStub end
  d.owner = addonName
  return Feed:New(d)
end
