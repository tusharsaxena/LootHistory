-- LibKa0s-IconBrowser-1.0 — IconBrowserWindow.lua: the window an icon browser is built in, the skin
-- it wears, and the edge a game icon's art takes in it. IconBrowser.lua builds every browser in one
-- of these, once, on its first Open.
--
-- Promoted from Ka0s Quick Comms with the browser (`settings/ModalWindow.lua`, the part the browser
-- uses, and `modules/IconStyle.lua`'s window icons), and peeled out of IconBrowser.lua on the seam
-- `layout-§1`'s size band asks for: the window is the frames around the page, the browser is what is
-- drawn on it. A file of the IconBrowser major, paired on the shell's minor (IconBrowserSources.lua
-- registers the major), as WidgetsCopyWindow.lua is on Widgets'.
--
--     catcher  a full-screen button that swallows every click and wheel, with a dim over what it
--              covers: the window is MODAL to whatever is under it
--     window   Blizzard's own SettingsFrameTemplate (its background, its border with the window
--              title, its close X), the catcher's child, so it draws above it
--     page     the host's LibKa0s Options instance's panel factory (CreatePanel): a settings page's
--              header (title and gold rule) and its body, set inside the template's background
--
-- A client without the template, or a template that lost a part used here (NineSlice with its
-- title, Bg, ClosePanelButton), gets the older shape: a plain frame, the owner's window fill, edge
-- and band under the page, a title and the shared close mark (Core.MakeCloseButton). Either close
-- calls the caller's `onClose`. The window is a special frame (Escape hides it); what a hide means
-- is the browser's (its own OnHide hook).
--
-- THE HEADER. Both shapes wear the full title band: the owner's Shell band, flush inside the edge.
-- The title and the close are anchored to that band's middle (the facade's Header), never to the
-- template's own TOP and TOPRIGHT anchors, and the page starts under the band (its top is the
-- band's bottom edge, laid again on every looks change), so no page covers the band's lower edge.
--
-- THE SKIN. The template's chrome is painted through the owner's facade (`Skin:For(owner)`, asked
-- through Core's `__SkinFacade`, so only a registered owner is painted): the template's Bg art faded
-- under the skin's fill, its NineSlice faded, the title and close X in the skin's colors. The page
-- inside and its controls follow the owner's skin as every settings page of its does. A host that
-- registered no skin owner gets the template as Blizzard draws it, and the fallback window the
-- Options instance's plain look; the four colors below then read their Ka0s Default values.
--
-- THE OWNER TOKENS (`lib.SKIN_TOKENS`). Four colors the browser draws that no library token holds
-- exactly, at the pixels Quick Comms drew them, each following the nearest library role token so
-- every other skin draws it in its own palette: `ib.selStrong` (the selected cell, gold at 0.7;
-- follows `list.sel`), `ib.note` (the footer's empty line, |cffaaaaaa; `text.muted`), `ib.markGray`
-- (the search box's clear mark; `icon.dim`) and `ib.modalDim` (the catcher's dim, black at 0.45;
-- `cover.dim`). They are laid onto the host's own owner with `Skin:RegisterOwner(owner, { tokens })`
-- on the browser's first build, once the host has registered (a second RegisterOwner adds tokens
-- and keeps the host's hooks and choice). The `ib.` namespace is the library's, so a host's own
-- tokens never collide with it.
--
-- STACKING. The catcher and the window are in `layers.strata`; inside it the window's parts sit in a
-- BAND of levels whose base is UIParent's level plus `layers.over` (a browser over another modal of
-- the host's, Quick Comms' over its callout popup) or `layers.level`: the catcher at the base, the
-- template's Bg at base + 1 (the template declares it at absolute level 0, which would put it under
-- the catcher's dim), the window with its border at base + 2, the page at base + 3 and the close X
-- at base + 5 (it overlaps the page's top edge). The strata above `layers.strata` (or
-- `layers.popup`) is left free for what must sit over the browser: AceGUI's pull-outs, the color
-- picker, the library's menu and the browser's link window. The window is clamped to the screen
-- (frame-layering-§4) but NOT toplevel: a toplevel window is raised to the top of its strata on every
-- mouse-down, which would let an opener's own window rise through the browser's band.
--
-- WINDOW ICONS. Game icon art in the window is cropped NATIVE_CROP a side and edged 1 physical px in
-- `icon.outline` (the facade's IconBorder), on a frame of the browser's own laid over the art, never
-- on the art itself. The edge follows the settings page's scope: none while the owner ignores its
-- settings panel. A glyph and a raid marker carry no native edge, so they are drawn whole and bare.
--
-- Depends on LibStub, the IconBrowser shell (IconBrowserSources.lua) and LibKa0s-Core-1.0; reads
-- LibKa0s-Skin-1.0 at call time when present.

local lib = LibStub and LibStub("LibKa0s-IconBrowser-1.0", true)
if not lib then return end   -- the shell refused (no Core or Media): nothing to attach to

-- Minor 1: the window, the four owner tokens and the window icon edge, lifted from Quick Comms.
local WINDOW_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own, as WidgetsCopyWindow.lua is.
if lib.__windowMinor and lib.__windowMinor >= WINDOW_MINOR
  and lib.__windowShellMinor == lib.MINOR then return end
lib.__windowMinor      = WINDOW_MINOR
lib.__windowShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.IconBrowserWindow = WINDOW_MINOR

local function byte(n) return n / 255 end

lib.SKIN_TOKENS = {
  ["ib.selStrong"] = { default = { 1, 0.82, 0, 0.7 }, follow = "list.sel" },
  ["ib.note"]      = { default = { byte(170), byte(170), byte(170), 1 }, follow = "text.muted" },
  ["ib.markGray"]  = { default = { 0.54, 0.54, 0.54, 1 }, follow = "icon.dim" },
  ["ib.modalDim"]  = { default = { 0, 0, 0, 0.45 }, follow = "cover.dim" },
}

-- The internal seam IconBrowser.lua reads at call time. Not a published member.
local W = {}
lib.__window = W

local TEMPLATE = "SettingsFrameTemplate"
-- Where the page sits in the window: inside the template's background (its Bg is inset 7,-18 /
-- -3,3) on the left, right and bottom; the fallback window is the page alone there. Its top is the
-- band's bottom edge in both (THE HEADER above): `top` is the fallback when no band answers.
W.INSET_TEMPLATE = { left = 8, top = 31, right = 4, bottom = 5 }
W.INSET_PLAIN = { left = 0, top = 31, right = 0, bottom = 0 }
-- Each part's level over the band's base (STACKING above).
W.OFFSET = { BG = 1, WINDOW = 2, PAGE = 3, CLOSE = 5 }
-- The client's strata, bottom to top: what `layers.popup` defaults to is the one over `strata`.
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

-- ── the skin ────────────────────────────────────────────────────────────────────────────────

local function noop() end

-- The facade a host with no registered skin owner is drawn through: every primitive does nothing,
-- and a color is an owner token's Ka0s Default value or nothing (the caller keeps its own).
local BARE = setmetatable({
  Color = function() return nil end,
  Token = function() return nil end,
  Band = function() return nil end,
}, { __index = function() return noop end })

--- The owner's facade, or BARE: asked through Core at call time, so a host that registers its owner
--- after building a browser is painted from then on.
function W.Facade(owner)
  local core = LibStub("LibKa0s-Core-1.0", true)
  local S = core and type(core.__SkinFacade) == "function" and core.__SkinFacade(owner) or nil
  return S or BARE
end

local tokened = {}

--- Lay the owner tokens onto `owner`, once, when it is a registered skin owner.
function W.EnsureTokens(owner)
  if tokened[owner] then return true end
  local Skin = LibStub("LibKa0s-Skin-1.0", true)
  if not (Skin and type(Skin.IsOwner) == "function" and Skin:IsOwner(owner)) then return false end
  Skin:RegisterOwner(owner, { tokens = lib.SKIN_TOKENS })
  tokened[owner] = true
  return true
end

--- A color token's r, g, b, a for `owner`: the facade's answer, else (an owner token the facade
--- cannot answer) its follow token's, else its Ka0s Default value; nil for a library token the
--- skin leaves alone.
function W.Color(owner, token)
  local S = W.Facade(owner)
  local r, g, b, a = S.Color(token)
  if r ~= nil then return r, g, b, a or 1 end
  local def = lib.SKIN_TOKENS[token]
  if not def then return nil end
  if def.follow then
    r, g, b, a = S.Color(def.follow)
    if r ~= nil then return r, g, b, a or 1 end
  end
  local c = def.default
  return c[1], c[2], c[3], c[4] or 1
end

--- A color token as a "|cffrrggbb" escape, each channel rounded to the byte, or nil.
function W.Escape(owner, token)
  local r, g, b = W.Color(owner, token)
  if r == nil then return nil end
  local function toByte(v) return math.floor(v * 255 + 0.5) end
  return ("|cff%02x%02x%02x"):format(toByte(r), toByte(g), toByte(b))
end

--- True while `owner` ignores its settings panel (Skin:GetIgnore's panel half); false without the
--- skin library.
function W.PanelIgnored(owner)
  local Skin = LibStub("LibKa0s-Skin-1.0", true)
  if not (Skin and type(Skin.GetIgnore) == "function" and type(Skin.IsOwner) == "function") then return false end
  if not Skin:IsOwner(owner) then return false end
  return (Skin:GetIgnore(owner)) == true
end

--- How far down from `frame`'s top its title band ends, in px: the band the owner's Shell lays, read
--- off the band itself, else `title.height` (30) under a 1 px edge.
function W.BandBottom(owner, frame)
  local S = W.Facade(owner)
  local tall = tonumber(S.Token("title.height")) or 30
  local band = S.Band(frame)
  if type(band) ~= "table" then return 1 + tall end
  local _, _, _, _, y = band:GetPoint(1)
  local h = band:GetHeight()
  return -(tonumber(y) or -1) + ((type(h) == "number" and h > 0) and h or tall)
end

-- ── window icons ────────────────────────────────────────────────────────────────────────────

W.NATIVE_CROP = 0.07
W.CROP = { W.NATIVE_CROP, 1 - W.NATIVE_CROP, W.NATIVE_CROP, 1 - W.NATIVE_CROP }
local MARKER = "UI%-RaidTargetingIcon_"
local EDGE_OPTS = { fromSkin = true, zoom = false }
local spareEdges = {}

--- Whether icon `v` is art with Blizzard's native edge: anything but a LibKa0s glyph or a raid marker.
function W.NativeEdge(v)
  if v == nil or v == false then return false end
  if lib.IsGlyph(v) then return false end
  return not (type(v) == "string" and v:find(MARKER) ~= nil)
end

--- Lay `holder`'s edge frame over `tex` (a child of `parent`) while `on`, else hand it back. The
--- frame is kept on `holder.ibIconEdge`; one handed back is hidden and reused by the next icon.
function W.Edge(owner, holder, parent, tex, on)
  local e = holder.ibIconEdge
  if on and not W.PanelIgnored(owner) then
    if not e then
      e = table.remove(spareEdges) or CreateFrame("Frame")
      holder.ibIconEdge = e
    end
    e:SetParent(parent)
    e:ClearAllPoints()
    e:SetAllPoints(tex)
    e:Show()
    W.Facade(owner).IconBorder(e, EDGE_OPTS)
    return
  end
  if not e then return end
  holder.ibIconEdge = nil
  e:Hide()
  e:ClearAllPoints()
  spareEdges[#spareEdges + 1] = e
end

--- Texture `tex` drawing `icon`: cropped and edged when it is game icon art, whole and bare
--- otherwise. `holder` keeps the edge (the cell, the footer's holder).
function W.Icon(owner, holder, parent, tex, icon)
  local native = W.NativeEdge(icon)
  if native then tex:SetTexCoord(unpack(W.CROP)) else tex:SetTexCoord(0, 1, 0, 1) end
  W.Edge(owner, holder, parent, tex, native)
  return native
end

-- ── the window ──────────────────────────────────────────────────────────────────────────────

local function isTable(v) return type(v) == "table" end

--- True when the client has the template, false when it says it has not, nil when it cannot say.
local function hasTemplate(name)
  local x = C_XMLUtil
  if type(x) ~= "table" or type(x.GetTemplateInfo) ~= "function" then return nil end
  local ok, info = pcall(x.GetTemplateInfo, name)
  return ok and type(info) == "table"
end

--- The strata over `strata` (FULLSCREEN_DIALOG over FULLSCREEN), or `strata` itself at the top.
function W.Above(strata)
  for i, s in ipairs(STRATA) do
    if s == strata then return STRATA[i + 1] or s end
  end
  return "FULLSCREEN_DIALOG"
end

-- The template's Bg is a FRAME (FlatPanelBackgroundTemplate), and Shell's `opts.stock` takes
-- textures only, so its art is handed over as the Bg's texture regions.
local function bgArt(bg)
  local out = {}
  if not (bg and type(bg.GetRegions) == "function") then return out end
  for _, r in ipairs({ bg:GetRegions() }) do out[#out + 1] = r end
  return out
end

-- The template's chrome through the facade. Each primitive is recorded, so a skin switch repaints
-- it with no call here.
local function skinTemplate(S, chrome)
  local f = chrome.window
  S.Shell(f, { stock = bgArt(chrome.bg) })
  S.FadeNineSlice(f)
  if isTable(chrome.nineSlice.Text) then
    S.TitleBar(chrome.nineSlice, { text = chrome.nineSlice.Text, noBg = true })
  end
  S.CloseButton(chrome.close)
  S.Header(f, { title = chrome.nineSlice.Text, right = { chrome.close } })
end

-- The window: the template when the client has it and it still has the parts used here, else a
-- plain frame. Answers the window and its chrome.
local function makeWindow(name, parent, title)
  local f
  if hasTemplate(TEMPLATE) ~= false then
    local ok, made = pcall(CreateFrame, "Frame", name, parent, TEMPLATE)
    if ok then f = made end
  end
  if f and isTable(f.NineSlice) and isTable(f.ClosePanelButton) then
    if isTable(f.NineSlice.Text) then f.NineSlice.Text:SetText(title) end
    return f, { template = true, window = f, nineSlice = f.NineSlice,
      bg = isTable(f.Bg) and f.Bg or nil, close = f.ClosePanelButton }
  end
  return f or CreateFrame("Frame", name, parent), { template = false }
end

-- The fallback's chrome: the owner's window fill, edge and band under the page, the host's title on
-- the band, and the shared close mark at the band's right.
local function plainChrome(spec, window, panel, chrome, at)
  local S = W.Facade(spec.owner)
  local bg = CreateFrame("Frame", nil, window, "BackdropTemplate")
  bg:SetAllPoints(window)
  bg:SetFrameLevel(at(W.OFFSET.BG))
  bg.title = bg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bg.title:SetText(spec.title or "")
  S.Shell(bg)
  local core = LibStub("LibKa0s-Core-1.0", true)
  local closeButton = core and type(core.MakeCloseButton) == "function"
    and core.MakeCloseButton(panel, function() spec.onClose() end, spec.owner) or nil
  S.Header(bg, { title = bg.title, right = { closeButton } })
  chrome.window, chrome.bg, chrome.close, chrome.title = window, bg, closeButton, bg.title
end

-- The page under the band: its top is the band's bottom edge, read off the frame that wears it.
local function layPage(owner, pg)
  pg.inset.top = W.BandBottom(owner, pg.banded)
  pg.panel:ClearAllPoints()
  pg.panel:SetPoint("TOPLEFT", pg.window, "TOPLEFT", pg.inset.left, -pg.inset.top)
  pg.panel:SetPoint("BOTTOMRIGHT", pg.window, "BOTTOMRIGHT", -pg.inset.right, pg.inset.bottom)
end

local function paintDim(owner, dim)
  dim:SetColorTexture(W.Color(owner, "ib.modalDim"))
end

local function makeCatcher(owner, strata, base)
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata(strata)
  catcher:SetFrameLevel(base)
  catcher:EnableMouse(true)
  catcher:EnableMouseWheel(true)
  catcher:SetScript("OnMouseWheel", noop)
  local dim = catcher:CreateTexture(nil, "BACKGROUND")
  dim:SetAllPoints(catcher)
  paintDim(owner, dim)
  catcher:Hide()
  return catcher, dim
end

--- Build a modal window, hidden. `spec` = { owner (the skin owner), name (the window's global name,
--- also its special-frame entry), pageName (the page panel's), title (the window's title: the
--- host's brand), header (the page header's), width, height, layers ({ strata, level, over }),
--- helpers (the host's Options instance), onClose (the close X's or the close mark's click) }.
--- @return table { catcher, frame, chrome, ctx (the page's panel context), inset }
function W.Build(spec)
  local layers = spec.layers
  local strata = layers.strata
  local base = UIParent:GetFrameLevel() + (tonumber(layers.over) or tonumber(layers.level) or 0)
  local function at(offset) return base + offset end
  local catcher, dim = makeCatcher(spec.owner, strata, base)
  local window, chrome = makeWindow(spec.name, catcher, spec.title or "")
  local baseInset = chrome.template and W.INSET_TEMPLATE or W.INSET_PLAIN
  local inset = { left = baseInset.left, top = baseInset.top, right = baseInset.right,
    bottom = baseInset.bottom }
  -- The strata again: a template may name its own, and the window must stay above the catcher.
  window:SetFrameStrata(strata)
  window:SetFrameLevel(at(W.OFFSET.WINDOW))
  window:SetSize(spec.width, spec.height)
  window:ClearAllPoints()
  window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  window:EnableMouse(true)
  window:SetClampedToScreen(true)

  local ctx = spec.helpers.CreatePanel(spec.pageName, spec.header, { isMain = true })
  local panel = ctx.panel
  panel:SetParent(window)
  panel:SetFrameLevel(at(W.OFFSET.PAGE))
  if chrome.template then
    if chrome.bg then chrome.bg:SetFrameLevel(at(W.OFFSET.BG)) end
    chrome.close:SetScript("OnClick", function() spec.onClose() end)
    chrome.close:SetFrameLevel(at(W.OFFSET.CLOSE))
    skinTemplate(W.Facade(spec.owner), chrome)
  else
    plainChrome(spec, window, panel, chrome, at)
  end
  local pg = { window = window, panel = panel, inset = inset, banded = chrome.template and window or chrome.bg }
  layPage(spec.owner, pg)
  -- A skin switch: the dim in the new skin, and the page under its band again (the chrome and the
  -- header are the library's recorded paint, laid before this fires).
  W.Facade(spec.owner).OnLooksChanged(function()
    paintDim(spec.owner, dim)
    layPage(spec.owner, pg)
  end)
  -- Escape hides a special frame.
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, spec.name) end
  return { catcher = catcher, frame = window, chrome = chrome, ctx = ctx, inset = inset, dim = dim }
end
