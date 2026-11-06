-- LibKa0s-Core-1.0 — CorePixel: pixel edges, the one mechanism Widgets and the Skin major share.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Core.lua ─────────────────────────────────────
--
-- Because of `layout-§1`. Core minor 16's pixel edges took Core.lua from 945 to 1080 lines, into
-- the band, and this section was the seam its census row named (FU-L2 of Ka0sAddonsCommonTasks
-- docs/2026-11-06-FOLLOWUPS_V1_91). It moved here at Core minor 17, unchanged: the same internal
-- members (`__PixelSize`, `__OnPixelScale`, `__WatchPixels`, `__PixelBackdrop`,
-- `__RefreshPixelBackdrops`) on the same table. It is NOT a major of its own: it is part of
-- `LibKa0s-Core-1.0`, guarded with the multi-file idiom, so a pixel file from one vendored copy
-- never pairs with a shell from another without saying so.
--
-- Depends on LibStub and the Core shell, and on nothing else. A payload without this file loads
-- whole and has no pixel members; every reader feature-detects them and draws in UI units.

local lib = LibStub and LibStub("LibKa0s-Core-1.0", true)
if not lib then return end

local MAJOR = "LibKa0s-Core-1.0"
local PIXEL_MINOR = 1
-- Minor 1: the pixel edges section of Core minor 16, moved unchanged.
-- Paired on the SHELL's minor as well as this file's own, as WidgetsCopyWindow.lua is.
if lib.__pixelMinor and lib.__pixelMinor >= PIXEL_MINOR
  and lib.__pixelShellMinor == lib.MINOR then return end
lib.__pixelMinor      = PIXEL_MINOR
lib.__pixelShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.CorePixel = PIXEL_MINOR

-- ── pixel edges (minor 16) ─────────────────────────────────────────────────────────────────
--
-- SF1-L1 of Ka0sAddonsCommonTasks docs/2026-11-06-REVENDOR_LIBKA0S_V1_89: a backdrop's `edgeSize = 1`
-- is one UI UNIT, so at most UI scales it drew 1 or 2 px by the frame's sub-pixel position (the
-- owner measured DropWatcher's dropdown at 2 px on top and 1 at the bottom). Here, so that Widgets
-- (no Skin dependency) and the Skin major share one mechanism: the size (Skin's P.px calls it), and
-- the re-size on a UI scale, display size or ancestor SetScale change (Skin's P.pxWatch calls it).
-- Hooks, never an event: a library-wide registration would outlive every host's stand-down.
-- Internal (`__`), not host contract.

lib.__pxScales = lib.__pxScales or setmetatable({}, { __mode = "k" })     -- hooked frame -> last scale
lib.__pxBackdrops = lib.__pxBackdrops or setmetatable({}, { __mode = "k" })  -- frame -> its record
lib.__pxListeners = lib.__pxListeners or {}                                -- key -> fn, run on a change

local function isFrame(f) return type(f) == "table" and type(f.GetObjectType) == "function" end

--- `n` physical pixels (1 by default) in the UI units of `frame`: the client's PixelUtil factor over
--- the frame's effective scale. `n` itself where the client has no PixelUtil or the frame no scale.
function lib.__PixelSize(frame, n)
  n = type(n) == "number" and n or 1
  local pu = PixelUtil
  local scale = isFrame(frame) and type(frame.GetEffectiveScale) == "function" and frame:GetEffectiveScale()
  if type(pu) ~= "table" or type(pu.GetPixelToUIUnitFactor) ~= "function" or type(scale) ~= "number"
    or scale <= 0 then return n end
  return n * pu.GetPixelToUIUnitFactor() / scale
end

--- Run `fn` on every pixel-scale change, one per `key`, so a newer copy's listener replaces its own.
function lib.__OnPixelScale(key, fn) lib.__pxListeners[key] = fn end

local function pxChanged()
  local live = LibStub and LibStub(MAJOR, true) or lib
  for _, fn in pairs(live.__pxListeners or {}) do
    local ok, err = pcall(fn)
    if not ok and type(geterrorhandler) == "function" then geterrorhandler()(err) end
  end
end

--- Watch `frame`'s pixel scale: UIParent's OnSizeChanged once, and a post-hook on SetScale of the
--- frame and each ancestor, once each; the same scale again costs one comparison.
function lib.__WatchPixels(frame)
  local ui = UIParent
  if not lib.__pxScreenHooked and type(ui) == "table" and type(ui.HookScript) == "function" then
    lib.__pxScreenHooked = true
    ui:HookScript("OnSizeChanged", pxChanged)
  end
  if type(hooksecurefunc) ~= "function" then return end
  local f, guard = frame, 0
  while isFrame(f) and guard < 32 do
    if lib.__pxScales[f] == nil and type(f.SetScale) == "function" then
      lib.__pxScales[f] = type(f.GetScale) == "function" and f:GetScale() or 1
      hooksecurefunc(f, "SetScale", function(self, s)
        if lib.__pxScales[self] == s then return end
        lib.__pxScales[self] = s
        pxChanged()
      end)
    end
    f, guard = type(f.GetParent) == "function" and f:GetParent() or nil, guard + 1
  end
end

local PX_PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }

--- `info` with its edgeSize and insets read as physical pixels of `frame`.
local function pxInfo(frame, info)
  local out = {}
  for k, v in pairs(info) do out[k] = v end
  if type(info.edgeSize) == "number" then out.edgeSize = lib.__PixelSize(frame, info.edgeSize) end
  if type(info.insets) == "table" then
    out.insets = {}
    for k, v in pairs(info.insets) do out.insets[k] = type(v) == "number" and lib.__PixelSize(frame, v) or v end
  end
  return out
end

--- Snap the backdrop's pieces to the pixel grid: the template turns snapping off, which smears a
--- 1 px edge at a fractional position over two pixels.
local function pxSnap(frame)
  for _, k in ipairs(PX_PIECES) do
    local p = rawget(frame, k)
    if type(p) == "table" and type(p.SetSnapToPixelGrid) == "function" then p:SetSnapToPixelGrid(true) end
  end
end

--- Lay `e.info` on `frame` at its scale now, snapped.
local function pxApply(frame, e)
  e.px = lib.__PixelSize(frame, 1)
  e.set(frame, type(e.info) == "table" and pxInfo(frame, e.info) or e.info)
  pxSnap(frame)
end

--- Re-lay one backdrop whose pixel size moved, its two colors kept.
local function pxRefresh(frame, e)
  if not e.info or e.px == lib.__PixelSize(frame, 1) then return end
  local c, b = { frame:GetBackdropColor() }, { frame:GetBackdropBorderColor() }
  pxApply(frame, e)
  if c[1] then frame:SetBackdropColor(unpack(c)) end
  if b[1] then frame:SetBackdropBorderColor(unpack(b)) end
end

local function pxRefreshAll()
  for frame, e in pairs(lib.__pxBackdrops) do pxRefresh(frame, e) end
end
lib.__OnPixelScale(MAJOR, function()
  local live = LibStub and LibStub(MAJOR, true) or lib
  if live.__RefreshPixelBackdrops then live.__RefreshPixelBackdrops() end
end)
lib.__RefreshPixelBackdrops = pxRefreshAll

--- Make `frame`'s backdrop pixel-exact (a BackdropTemplate frame; any other is left alone): from
--- now on every SetBackdrop on it, a skin's included, reads `edgeSize` and `insets` as PHYSICAL
--- pixels, GetBackdrop answers the table as given, and the backdrop is laid again on a pixel-scale
--- change and on each show (a reparent). Its current backdrop, laid in UI units, is laid again at
--- once where a pixel is not one unit. Idempotent.
function lib.__PixelBackdrop(frame)
  local set = isFrame(frame) and rawget(frame, "SetBackdrop")
  if type(set) ~= "function" or lib.__pxBackdrops[frame] then return frame end
  local get = rawget(frame, "GetBackdrop")
  local e = { set = set, info = type(get) == "function" and get(frame) or nil, px = 1 }
  lib.__pxBackdrops[frame] = e
  rawset(frame, "SetBackdrop", function(self, info)
    e.info = info
    pxApply(self, e)
  end)
  rawset(frame, "GetBackdrop", function() return e.info end)
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", function(self) pxRefresh(self, e) end) end
  lib.__WatchPixels(frame)
  pxSnap(frame)
  pxRefresh(frame, e)
  return frame
end
