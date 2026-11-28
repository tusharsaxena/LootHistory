local _, NS = ...
NS.Toasts = NS.Toasts or {}
local Toasts = NS.Toasts
local C = NS.Constants
-- Load-time upvalues: modules/ToastModel.lua and modules/ToastContent.lua load above (LootHistory.toc).
local M = NS.ToastModel
local TC = NS.ToastContent

-- The toast feeds (#38, toast spec docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §8). The
-- three feeds are LibKa0s-Feed-1.0 instances built through the seam (NS.NewFeed, core/FeedSetup.lua),
-- which owns every frame, the motion and the look. This file is the host's half:
--
--   * the GAIN receiver (Toasts:OnGain): each feed whose filter accepts a gain gets its own payload
--     copy, pushed under the gain's merge key (the Feed does the merge, the queue and the drop),
--     subscribed to NS.MSG.GAIN on its private target `__gain`;
--   * the click actions behind the Feed's onClick (shift/ctrl link, plain click opens History);
--   * the combat rows "Toasts" (registered while any feed is enabled): lock, click-through, hold;
--   * unlock and drag (session state, NS.State.toastUnlocked), the drag's nudge written through
--     the Schema seam, the sample preview while an unlocked feed is empty;
--   * the settings listener (`__ev`): the config snapshot dropped and every feed Refresh()ed.
--
-- Nothing here draws, ticks or sets a strata: the containers are the Feed's (STRATA HIGH).

local L = NS.L
local feeds = {}           -- fid -> Feed instance (or NS.FeedStub), built once at the first Enable
Toasts._feeds = feeds      -- tests only

local function prefix(fid) return "settings.toasts.feeds." .. fid .. "." end

local function descriptor(fid)
  return {
    name    = "LootHistoryToastFeed_" .. fid,
    content = function(spec, p, key) return TC.Content(fid, spec, p, key) end,
    merge   = M.Merge,
    layout  = function() return M.LayoutFor(fid) end,
    motion  = function() return M.MotionFor(fid) end,
    style   = function() return M.StyleFor(fid) end,
    onClick = function(p, button, key) Toasts:_Click(fid, p, button, key) end,
    onMoved = function(x, y) Toasts:_Moved(fid, x, y) end,
    strings = { HANDLE = L[C.TOAST_FEED_LABEL[fid]],
                HANDLE_TIP = L["Drag to move this feed. Lock it again on the Toasts page."] },
    debug   = function(tag, fmt, ...) if NS.State.debug and NS.Debug then NS.Debug(tag, fmt, ...) end end,
  }
end

Toasts._descriptor = descriptor   -- tests only: a fresh instance on the host's own descriptor

--- The Feed instance of `fid` (nil before the first Enable).
function Toasts.Feed(_, fid) return feeds[fid] end

-- ── The receiver (§8.3) ──────────────────────────────────────────────────────────────────────

-- One push of `g` into feed `fid`. A refused push hands its payload back to the spare list, unless
-- the merge reducer already did (a merged payload whose content skipped it): a freed payload is
-- wiped, so it has no kind left.
local function pushInto(feed, g)
  local key = M.Key(g)
  if not key then return nil end
  local p = M.NewPayload(g)
  local res = feed:Push(key, p)
  if res == false and p.kind ~= nil then M.FreePayload(p) end
  return res
end

--- The GAIN handler: every feed that accepts `g`, in feed order.
function Toasts.OnGain(_, g)
  for _, fid in ipairs(C.TOAST_FEEDS) do
    local feed = feeds[fid]
    if feed and M.Accepts(M.Config(fid), g) then pushInto(feed, g) end
  end
end

-- ── Clicks (§8.5) ────────────────────────────────────────────────────────────────────────────

--- The Feed's onClick (a right-click dismiss and an unlocked left button never reach here). Shift or
--- ctrl hands the link to the client (chat link, dressing room); a plain left click opens History
--- searched for the gain (T12).
function Toasts._Click(_, _, p, button)
  if button ~= "LeftButton" or type(p) ~= "table" then return end
  local Compat = NS.Compat
  if Compat.ModifierDown("shift") or Compat.ModifierDown("ctrl") then
    local link = p.link
    if not link and p.kind == C.GainKind.CURRENCY then link = Compat.CurrencyLink(p.id) end
    Compat.ModifiedLinkClick(link)
    return
  end
  if NS.Browser and NS.Browser.ShowGain then NS.Browser:ShowGain(p) end
end

-- ── Unlock and drag (§8.6) ───────────────────────────────────────────────────────────────────

--- Unlock (`on`) or lock feed `fid`. Answers whether it is unlocked now: the Feed refuses an unlock in
--- combat and without LibKa0s-Widgets-1.0. An unlocked, empty feed previews its samples; a lock
--- clears them.
function Toasts.SetUnlocked(_, fid, on)
  local feed = feeds[fid]
  if not feed then return false end
  local unlocked = not feed:SetLocked(not on)
  NS.State.toastUnlocked[fid] = unlocked or nil
  if unlocked then
    if feed:Stats().live == 0 and NS.ToastSample then feed:Preview(NS.ToastSample.ForFeed(fid)) end
  else
    feed:ClearPreview()
  end
  return unlocked
end

--- The Feed's onMoved: the clamped nudge for the current slot, written through the single write seam.
--- The SETTINGS_CHANGED it causes re-reads the same values on Refresh().
function Toasts._Moved(_, fid, x, y)
  if not (NS.Schema and NS.Schema.SetMany) then return false end
  local P = prefix(fid)
  return NS.Schema:SetMany({ { path = P .. "x", value = x }, { path = P .. "y", value = y } })
end

-- ── Combat (§8.5) ────────────────────────────────────────────────────────────────────────────

--- PLAYER_REGEN_DISABLED: every feed locked again (the host owns the re-lock), click-through and the
--- hold per the feed's settings.
function Toasts:OnCombatStart()
  for _, fid in ipairs(C.TOAST_FEEDS) do
    local feed = feeds[fid]
    if feed then
      if NS.State.toastUnlocked[fid] then self:SetUnlocked(fid, false) else feed:SetLocked(true) end
      local cfg = M.Config(fid)
      if cfg.clickThrough then feed:SetClickThrough(true) end
      if not cfg.showInCombat then feed:Hold() end
    end
  end
end

--- PLAYER_REGEN_ENABLED: the mouse back and the held gains drained.
function Toasts.OnCombatEnd()
  for _, fid in ipairs(C.TOAST_FEEDS) do
    local feed = feeds[fid]
    if feed then
      feed:SetClickThrough(false)
      feed:Release()
    end
  end
end

-- The combat rows (core/Dispatch.lua) on the private `__rows` target, appended at FILE LOAD so their
-- order is TOC order. Not capture rows: they only steer the feeds.
NS.EventRow("Toasts", "toasts", "PLAYER_REGEN_DISABLED", function() Toasts:OnCombatStart() end)
NS.EventRow("Toasts", "toasts", "PLAYER_REGEN_ENABLED", function() Toasts:OnCombatEnd() end)

local function anyEnabled()
  for _, fid in ipairs(C.TOAST_FEEDS) do
    if M.Config(fid).enabled then return true end
  end
  return false
end

--- The combat rows on while any feed is enabled, off otherwise. A no-op until Enable.
function Toasts:SyncRows()
  if not self._up then return end
  local want = anyEnabled()
  if want and not self._rowsOn then
    self.__rows = self.__rows or NS.NewBusTarget()
    if self.__rows then NS.RegisterRows("Toasts", self.__rows, "toasts") end
    self._rowsOn = true
  elseif not want and self._rowsOn then
    NS.UnregisterRows("Toasts")
    self._rowsOn = nil
  end
end

-- ── Settings and lifecycle (§10.1) ───────────────────────────────────────────────────────────

--- A settings write or a profile switch: the snapshot dropped, every feed re-reads its getters, and
--- the combat rows follow the enabled set.
function Toasts:RefreshConfig()
  M.Rebuild()
  for _, fid in ipairs(C.TOAST_FEEDS) do
    if feeds[fid] then feeds[fid]:Refresh() end
  end
  self:SyncRows()
end

--- Stand-up (core/LifecycleSetup.lua, after the Timeline): the three feeds built once (later Enables
--- reuse them; Clear() left them reusable), the GAIN receiver on `__gain` (§8.3), the settings
--- listener, the combat rows.
function Toasts:Enable()
  if not NS.addon or self._up then return end
  self._up = true
  for _, fid in ipairs(C.TOAST_FEEDS) do
    if not feeds[fid] then feeds[fid] = NS.NewFeed(descriptor(fid)) end
  end
  M.Rebuild()
  self.__gain = self.__gain or NS.NewBusTarget()
  if self.__gain then
    self.__gain:RegisterMessage(NS.MSG.GAIN, function(_, g) Toasts:OnGain(g) end)
  end
  self.__ev = self.__ev or NS.NewBusTarget()
  if self.__ev then
    self.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, reason)
      if reason == "toasts" or reason == "profile" or reason == "enabled" then Toasts:RefreshConfig() end
    end)
  end
  self:SyncRows()
end

--- Stand-down (slash-commands-§7): the GAIN receiver, the listener and the combat rows gone, and every feed Clear()ed
--- (rows released and hidden, the waiting list emptied, the clock disarmed, locked again). Clear
--- keeps a combat Hold and click-through, so both are ended here too: a stand-down in combat must not
--- come back up holding every gain (the emptied waiting list drains nothing).
function Toasts:Disable()
  if self.__gain then self.__gain:UnregisterAllMessages() end
  if self.__ev then self.__ev:UnregisterAllMessages() end
  NS.UnregisterRows("Toasts")
  self._rowsOn, self._up = nil, nil
  for _, fid in ipairs(C.TOAST_FEEDS) do
    local feed = feeds[fid]
    if feed then
      feed:Clear()
      feed:SetClickThrough(false)
      feed:Release()
    end
  end
  for k in pairs(NS.State.toastUnlocked) do NS.State.toastUnlocked[k] = nil end
end
