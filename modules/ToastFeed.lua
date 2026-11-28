local _, NS = ...
NS.Toasts = NS.Toasts or {}
local Toasts = NS.Toasts
local C = NS.Constants
-- Load-time upvalues: modules/ToastModel.lua and modules/ToastContent.lua load above, and
-- core/PerfSetup.lua far above (LootHistory.toc; performance-§2).
local M = NS.ToastModel
local TC = NS.ToastContent
local Perf = NS.Perf

-- The toast feeds (#38, toast spec docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §8). The
-- three feeds are LibKa0s-Feed-1.0 instances built through the seam (NS.NewFeed, core/FeedSetup.lua),
-- which owns every frame, the motion and the look. This file is the host's half:
--
--   * the GAIN receiver (Toasts:OnGain): each feed whose filter accepts a gain gets its own payload
--     copy, pushed under the gain's merge key (the Feed does the merge, the queue and the drop),
--     subscribed to NS.MSG.GAIN on its private target `__gain`; an appearance and its item fold into
--     one toast first (M.Absorb), and a new highlighted toast plays its sound (C.TOAST_SOUND_GAP);
--   * the content closure, bracketed as the perf bucket `toastPaint` (performance-§2);
--   * the click actions behind the Feed's onClick (shift/ctrl link, plain click opens History);
--   * the combat rows "Toasts" (registered while any feed is enabled): lock, click-through, hold;
--   * unlock and drag (session state, NS.State.toastUnlocked), the drag's nudge written through
--     the Schema seam, the sample preview while an unlocked feed is empty;
--   * test mode (the samples and the test strip on each enabled feed), the per-feed Test act and
--     the sim strip, which wins over the test strip while a session runs;
--   * the settings listener (`__ev`): the config snapshot dropped and every feed Refresh()ed.
--
-- Nothing here draws, ticks or sets a strata: the containers are the Feed's (STRATA HIGH).

local L = NS.L
local feeds = {}           -- fid -> Feed instance (or NS.FeedStub), built once at the first Enable
Toasts._feeds = feeds      -- tests only

local function prefix(fid) return "settings.toasts.feeds." .. fid .. "." end

-- The Feed's content call for feed `fid`, Shape-A bracketed `toastPaint`: the Feed calls it on present,
-- merge, repaint and the settle re-read, never per frame; the lazy price and extras reads sit inside.
-- A push runs inside `gainSend` (GainFeed.sending), a repaint, settle or refresh at top level: the
-- observed parent is passed (performance-§3), so the record says which.
local function paint(fid, spec, p, key)
  local t0 = Perf.on and debugprofilestop()
  local res = TC.Content(fid, spec, p, key)
  if t0 then Perf.Note("toastPaint", debugprofilestop() - t0, NS.GainFeed.sending and "gainSend" or false) end
  return res
end

local function descriptor(fid)
  return {
    name    = "LootHistoryToastFeed_" .. fid,
    content = function(spec, p, key) return paint(fid, spec, p, key) end,
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

local lastSound = {}        -- fid -> GetTime() of its last highlight sound
Toasts._lastSound = lastSound   -- tests only

-- A new toast's highlight sound (§8.3): the highlight the content found (p.highlight), its sound row
-- set, and the feed's last sound more than C.TOAST_SOUND_GAP ago.
local function playHighlight(fid, cfg, p)
  local name = p.highlight
  local key = name and type(cfg.hl) == "table" and cfg.hl[name .. "Sound"]
  if type(key) ~= "string" or key == "" then return false end
  local now, last = GetTime(), lastSound[fid]
  if last and now - last <= C.TOAST_SOUND_GAP then return false end
  if not NS.Compat.PlayMediaSound(key) then return false end
  lastSound[fid] = now
  return true
end

-- One push of `g` into feed `fid`, after the appearance absorb. A refused push hands its payload back
-- to the spare list, unless the merge reducer already did (a merged payload whose content skipped
-- it): a freed payload is wiped, so it has no kind left.
local function pushInto(fid, feed, cfg, g)
  local absorbed, look, new = M.Absorb(feed, g)
  if absorbed then return "absorbed" end
  local key = M.Key(g)
  if not key then return nil end
  local p = M.NewPayload(g)
  if look then M.MarkLook(p, new) end
  local res = feed:Push(key, p)
  if res == "new" then
    playHighlight(fid, cfg, p)
  elseif res == false and p.kind ~= nil then
    M.FreePayload(p)
  end
  return res
end

--- The GAIN handler: every feed that accepts `g`, in feed order.
function Toasts.OnGain(_, g)
  for _, fid in ipairs(C.TOAST_FEEDS) do
    local feed, cfg = feeds[fid], M.Config(fid)
    if feed and M.Accepts(cfg, g) then pushInto(fid, feed, cfg, g) end
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
--- clears them. An unlock puts the combat rows on, even with every feed off, so combat locks it
--- again; a lock leaves them for the next SyncRows (never unregistered from inside OnCombatStart).
function Toasts:SetUnlocked(fid, on)
  local feed = feeds[fid]
  if not feed then return false end
  local unlocked = not feed:SetLocked(not on)
  NS.State.toastUnlocked[fid] = unlocked or nil
  if unlocked then self:SyncRows() end
  if unlocked and feed:Stats().live ~= 0 then return unlocked end
  self:SyncPreview(fid)
  return unlocked
end

-- ── Test mode, the Test act and the strips (§8.7) ────────────────────────────────────────────

--- Whether feed `fid` shows the sticky samples now: test mode on an enabled feed, or an unlocked one.
local function previewWanted(fid)
  if Toasts._testMode and M.Config(fid).enabled then return true end
  return NS.State.toastUnlocked[fid] == true
end

--- The samples shown, or cleared, as `previewWanted` says (preview-mode: the same present and paint
--- path as a live toast).
function Toasts.SyncPreview(_, fid)
  local feed = feeds[fid]
  if not feed then return end
  if previewWanted(fid) and NS.ToastSample then
    feed:Preview(NS.ToastSample.ForFeed(fid))
  else
    feed:ClearPreview()
  end
end

--- The strip an enabled feed carries: the sim's while a session runs (it wins), else test mode's.
local function stripFor(fid)
  if not M.Config(fid).enabled then return nil end
  if NS.Sim and NS.Sim.IsActive and NS.Sim:IsActive() then return "sim", L["Sim mode"] end
  if Toasts._testMode then return "test", L["Test mode"] end
  return nil
end

--- Every feed's strip set from the state it reflects; a feed with none hides it.
function Toasts.SyncStrips()
  for _, fid in ipairs(C.TOAST_FEEDS) do
    local feed = feeds[fid]
    if feed then feed:SetStrip(stripFor(fid)) end
  end
end

--- Test mode (BrowserTable:SetTestMode calls this after its own switch succeeded): each enabled feed
--- shows one sticky sample per kind under the test strip; off clears both. Live gains still push.
function Toasts:SetTestMode(on)
  self._testMode = on and true or nil
  if not self._up then return end
  for _, fid in ipairs(C.TOAST_FEEDS) do self:SyncPreview(fid) end
  self:SyncStrips()
end

--- The per-feed Test act: each sample this feed shows pushed once with no key (never merging, the
--- normal lifecycle, not sticky), even while the feed is off. Refused in combat. Answers how many.
function Toasts.Test(_, fid)
  local feed = feeds[fid]
  if not (feed and NS.ToastSample) then return 0 end
  if NS.Compat.PlayerInCombat() then
    NS.Print(L["Test toasts cannot show in combat."])
    return 0
  end
  local n = 0
  for _, pair in ipairs(NS.ToastSample.ForFeed(fid)) do
    if feed:Push(nil, M.NewPayload(pair[2])) then n = n + 1 end
  end
  return n
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

--- The combat rows on while any feed is enabled or unlocked (an unlocked feed is re-locked in combat
--- whether it is enabled or not), off otherwise. A no-op until Enable.
function Toasts:SyncRows()
  if not self._up then return end
  local want = anyEnabled() or next(NS.State.toastUnlocked) ~= nil
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
--- the combat rows follow the enabled set. A feed turned on or off in test mode gains or loses its
--- samples and its strip.
function Toasts:RefreshConfig()
  M.Rebuild()
  for _, fid in ipairs(C.TOAST_FEEDS) do
    if feeds[fid] then feeds[fid]:Refresh() end
  end
  self:SyncRows()
  if self._testMode then
    for _, fid in ipairs(C.TOAST_FEEDS) do self:SyncPreview(fid) end
  end
  self.SyncStrips()
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
  -- The sim strip follows a session's start and end. modules/Sim.lua loads below this file, so the
  -- listener is added here, once; it fires on every step too, and SetStrip of the same strip is cheap.
  if not self._simListen and NS.Sim and NS.Sim.AddListener then
    self._simListen = true
    NS.Sim:AddListener(function() if Toasts._up then Toasts.SyncStrips() end end)
  end
  if self._testMode then
    for _, fid in ipairs(C.TOAST_FEEDS) do self:SyncPreview(fid) end
  end
  self.SyncStrips()
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
