-- LibKa0s-Skin-1.0 — the Ka0s paint primitives, part four: the navigation. EllesmereUI's Tab and
-- SetTabSelection, and the Ka0s NavItem, Drawer and ListRow.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF SkinPaintControls.lua ────────────────────────
--
-- Because of `layout-§1`. LibKa0s#97's bar texture took SkinPaintControls.lua to 1114 lines, past
-- the 1100-line trigger its census entry set, and the owner ruled the band files peeled
-- (FU-LK-PAINTCTL of Ka0sAddonsCommonTasks docs/2026-11-21-SYNC_FOLLOWUPS). The navigation, drawer
-- and list-row section, the seam that entry named, moved here at SkinPaintControls minor 20,
-- unchanged, with the tabs section beside it, because the named seam alone would have left the file
-- at about 1020 lines, in the band. `S.Tab`, `S.SetTabSelection`, `S.NavItem`, `S.Drawer` and
-- `S.ListRow` are the same primitives with the same opts; their history is SkinPaintControls.lua's
-- header. It is NOT a major of its own: it is part of `LibKa0s-Skin-1.0`, paired on the shell's
-- minor, and it paints with SkinPaint.lua's helpers (`lib.__P`), as the controls do.
--
-- WHAT CROSSES THE CUT. SkinPaintControls.lua publishes `lib.__controlsKit` (`labelOf`, a button's
-- label, which a tab reads too). A payload without this file has every other primitive and no tab,
-- nav item, drawer or list row paint.
--
-- Depends on the Skin shell, SkinPaint.lua's helpers and SkinPaintControls.lua.

local lib = LibStub and LibStub("LibKa0s-Skin-1.0", true)
if not lib then return end   -- the shell refused (no Core, or below its floor): nothing to attach to
if lib.__paintShellMinor ~= lib.MINOR or not lib.__P then return end   -- no helpers from this copy
if type(lib.__controlsKit) ~= "table" then return end   -- no controls file from this copy

local PAINTNAV_MINOR = 1
-- Minor 1: the tabs and the navigation, drawer and list-row sections of SkinPaintControls minor 19,
-- moved unchanged (SkinPaintControls minor 20).
-- Paired on the SHELL's minor as well as this file's own, as SkinPaintControls.lua is.
if lib.__paintNavMinor and lib.__paintNavMinor >= PAINTNAV_MINOR
  and lib.__paintNavShellMinor == lib.MINOR then return end
lib.__paintNavMinor      = PAINTNAV_MINOR
lib.__paintNavShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SkinPaintNav = PAINTNAV_MINOR

local prim, P = lib.prim, lib.__P
local rgba = P.rgba
local labelOf = lib.__controlsKit.labelOf

-- ── tabs ─────────────────────────────────────────────────────────────────────────────────────

local function tabFill(rec, tab, T, opts, selected)
  local fill = P.isTexture(opts.fill) and opts.fill or P.tex(rec, "fill", tab, "BACKGROUND", 0)
  if not fill then return end
  if not opts.fill then fill:SetAllPoints(tab) end
  local art = P.media("background", T[selected and "tab.onTexture" or "tab.texture"])
  if art then
    fill:SetTexture(art)
    fill:SetVertexColor(1, 1, 1, 1)
    return fill:Show()
  end
  P.fill(rec, fill, T, (selected and T["tab.onBg"]) and "tab.onBg" or "tab.bg")
end

local function tabLine(rec, tab, T, selected)
  local c = selected and T["tab.onLine"]
  local h = c and P.holder(rec, tab)
  local t = h and P.tex(rec, "line", h, "ARTWORK")
  if not t then return P.hide(rec, "line") end
  t:ClearAllPoints()
  t:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT")
  t:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT")
  t:SetHeight(2)
  t:SetColorTexture(rgba(c))
  t:Show()
end

--- The tab's edge, on its own holder so the selected underline stays on the tab's. A tab drawn in
--- the skin's art has no other edge than the art's; a named fill is the tab's face, which a settings
--- strip's button is taller than.
local function tabEdge(rec, tab, T, opts, selected)
  local c = T["tab.border"]
  if not c or P.media("background", T[selected and "tab.onTexture" or "tab.texture"]) then
    return P.hideEdges(rec, tab)
  end
  local h = P.edgeHolder(rec, tab)
  P.edges(rec, tab, c, T["tab.borderStyle"], T["tab.borderSize"], h)
  if h and P.isTexture(opts.fill) and not rec.regions.nine then
    h:ClearAllPoints()
    h:SetAllPoints(opts.fill)
  end
end

--- The two glow textures the caller drew (`opts.glow`: `hover`, `sel`, and its stock gradient's
--- `bottom` and `top`) in `tab.glow`, fading to the same top. Only one is lit at a time, by the
--- caller's own color, so this moves neither. P.unpaint puts the stock gradient back.
local function tabGlow(rec, T, glow)
  if type(glow) ~= "table" then return end
  local c, prior = T["tab.glow"], P.saved(rec, "glow")
  local bottom = c and P.asColor(c) or glow.bottom
  for _, tex in ipairs({ glow.hover or false, glow.sel or false }) do
    if tex and tex.SetGradient then
      tex:SetGradient("VERTICAL", bottom, glow.top)
      prior[tex] = glow
    end
  end
end

--- S.Tab(tab, opts): a tab. The stock art faded (with `opts.stock`, regions the caller drew from
--- the client's art, such as the settings strip's atlases); the backing (`opts.fill`, else a region)
--- `tab.onTexture` / `tab.texture` art, else `tab.onBg` / `tab.bg` and its gradient; a `tab.onLine`
--- underline on the holder while selected; a `tab.border` edge at `tab.borderSize` and
--- `tab.borderStyle`, around `opts.fill` when it names one, and none on a tab in the skin's art;
--- `opts.glow`'s textures in `tab.glow`; the label (`opts.text`, else the tab's own) in
--- `tab.onText` / `tab.text` and the body font. `opts.selected` is the first state;
--- `S.SetTabSelection` moves it. Draws no Media icon.
prim.Tab = function(owner, tab, opts)
  if not P.isFrame(tab) then return end
  local rec = P.track(owner, tab, "Tab", opts)
  opts = type(opts) == "table" and opts or {}
  if opts.selected ~= nil and (rec.regions.selected == nil
    or not (lib.__repainting or rec.regions.keepSelection)) then
    rec.regions.selected = opts.selected == true
  end
  P.markStock(rec, tab, opts)
  local T, selected = P.T(owner), rec.regions.selected == true
  P.fadeAll(rec, P.stockRegions(tab, opts))
  tabFill(rec, tab, T, opts, selected)
  tabLine(rec, tab, T, selected)
  tabEdge(rec, tab, T, opts, selected)
  tabGlow(rec, T, opts.glow)
  local fs = P.isFS(opts.text) and opts.text or labelOf(tab)
  if fs then
    P.label(owner, rec, fs, T, selected and "tab.onText" or "tab.text")
  end
end

--- S.SetTabSelection(tab, selected): move a painted tab to selected or not, and repaint it. Not
--- recorded: the state lives in the tab's record, so a skin switch keeps it.
prim.SetTabSelection = function(owner, tab, selected)
  local rec = lib.painted[tab]
  if not rec then return end
  rec.regions.selected = selected == true
  local args = rec.calls.Tab
  if not args then return end
  rec.regions.keepSelection = true
  local ok, err = pcall(prim.Tab, owner, tab, unpack(args, 1, args.n))
  rec.regions.keepSelection = nil
  if not ok then error(err, 0) end
end

-- ── navigation, drawers, list rows ───────────────────────────────────────────────────────────

--- S.NavItem(item, opts): a nav-rail entry. Its label (`opts.label`) in `nav.selText` while
--- `opts.selected`, `nav.text` otherwise (OptionsNav's white and gold); its selection texture
--- (`opts.sel`) in `nav.selBg` (OptionsNav's select tint); a `nav.selBar` on the holder while
--- selected (nil in Ka0s Default); its hover art (`opts.hover`, minor 10) desaturated and colored
--- `list.hoverArt`, left as the client draws it where that is `false` (Ka0s Default, WoW Default).
--- Draws no Media icon.
prim.NavItem = function(owner, item, opts)
  if type(item) ~= "table" then return end
  local rec = P.track(owner, item, "NavItem", opts)
  opts = type(opts) == "table" and opts or {}
  local T = P.T(owner)
  if P.isFS(opts.label) then P.label(owner, rec, opts.label, T, opts.selected and "nav.selText" or "nav.text") end
  if P.isTexture(opts.sel) then P.tint(rec, opts.sel, T, "nav.selBg", "SetVertexColor") end
  if P.isTexture(opts.hover) then P.glyph(rec, opts.hover, T, "list.hoverArt") end
  local c = opts.selected and T["nav.selBar"] or nil
  P.edges(rec, item, c, "flat", 2)
end

-- OptionsDrawer's four-edge set: the fill, then the left, right, bottom and top edges, each a
-- texture colored by SetVertexColor, four components.
local DRAWER_EDGES = { "left", "right", "bottom", "top" }
local function paintEdgeSet(e, fill, edge)
  if type(e) ~= "table" then return end
  if fill and P.isTexture(e.fill) then e.fill:SetVertexColor(rgba(fill)) end
  if not edge then return end
  for _, k in ipairs(DRAWER_EDGES) do
    if P.isTexture(e[k]) then e[k]:SetVertexColor(rgba(edge)) end
  end
end

local DRAWER_HEAD = { fill = "drawer.bg", border = "drawer.border", style = "drawer.borderStyle",
                      size = "drawer.borderSize", extra = true }
local DRAWER_HEAD_OPEN = { fill = "drawer.bgOpen", border = "drawer.borderOpen",
                           style = "drawer.borderStyle", size = "drawer.borderSize", extra = true }

--- S.Drawer(head, opts): a settings drawer's header (and box). Its label (`opts.label`) in
--- `drawer.textSet` when `opts.set`, `drawer.text` otherwise; its summary (`opts.summary`) in
--- `drawer.summarySet` / `drawer.summary`, both in the body face (minor 10, LK-06c: so Ignore fonts
--- reaches them; the summary keeps its smaller stock size, scaled); its chevron (`opts.chevron`)
--- desaturated and colored `icon.arrow`, as every arrow; its hover art (`opts.hover`) in
--- `list.hoverArt`, the client's art where that is `false`; then its edge set (`opts.edges`, OptionsDrawer's
--- `{ fill, left, right, bottom, top }`) in `drawer.bgOpen` / `drawer.borderOpen` while `opts.open`,
--- else `drawer.bg` / `drawer.border`, and the box's (`opts.box`) in `drawer.boxBg` /
--- `drawer.boxBorder`. A header with no edge set is boxed on its holders (the fill under its text,
--- the edge over it). Draws no Media icon.
local function drawerText(owner, rec, T, opts)
  local set = opts.set and true or false
  P.label(owner, rec, opts.label, T, set and "drawer.textSet" or "drawer.text")
  P.label(owner, rec, opts.summary, T, set and "drawer.summarySet" or "drawer.summary")
  if P.isTexture(opts.chevron) then P.glyph(rec, opts.chevron, T, "icon.arrow") end
  if P.isTexture(opts.hover) then P.glyph(rec, opts.hover, T, "list.hoverArt") end
end

prim.Drawer = function(owner, head, opts)
  if type(head) ~= "table" then return end
  local rec = P.track(owner, head, "Drawer", opts)
  opts = type(opts) == "table" and opts or {}
  local T, open = P.T(owner), opts.open and true or false
  drawerText(owner, rec, T, opts)
  if type(opts.edges) == "table" then
    paintEdgeSet(opts.edges, T[open and "drawer.bgOpen" or "drawer.bg"],
      T[open and "drawer.borderOpen" or "drawer.border"])
  elseif P.isFrame(head) then
    P.box(rec, head, T, open and DRAWER_HEAD_OPEN or DRAWER_HEAD)
  end
  paintEdgeSet(opts.box, T["drawer.boxBg"], T["drawer.boxBorder"])
end

local ROW_STATE = { stripe = { stripe = true }, hover = { hover = true }, selected = { selected = true },
                    normal = {} }

local function rowWash(rec, row, key, c)
  local t = c and P.subTex(rec, key, row, P.SUB[key])
  if not t then return P.hide(rec, key) end
  t:SetAllPoints(row)
  t:SetColorTexture(rgba(c))
  t:Show()
end

--- S.ListRow(row, state): a list row's washes, regions of the row under its text and art:
--- `list.stripe` when `state.stripe`, `list.hover` when `state.hover`, `list.sel` when
--- `state.selected`, with a `list.selOutline` edge on the holder over it.
--- `state` is a table or one of "stripe", "hover", "selected", "normal". Call it from the row's
--- bind step: the latest state is what a skin switch repaints. Draws no Media icon.
prim.ListRow = function(owner, row, state)
  if not P.isFrame(row) then return end
  local rec = P.track(owner, row, "ListRow", state)
  local s = type(state) == "table" and state or ROW_STATE[state] or ROW_STATE.normal
  local T = P.T(owner)
  rowWash(rec, row, "stripe", s.stripe and T["list.stripe"] or nil)
  rowWash(rec, row, "hover", s.hover and T["list.hover"] or nil)
  rowWash(rec, row, "sel", s.selected and T["list.sel"] or nil)
  P.edges(rec, row, s.selected and T["list.selOutline"] or nil, "flat", 1)
end
