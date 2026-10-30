-- LibKa0s-Skin-1.0 — AceGUI rows: the settings widgets a Ka0s page acquires, painted for that page's
-- skin owner and handed back to AceGUI's shared pool exactly as stock as they came out of it.
--
-- ── WHY IT IS ITS OWN FILE, AND NOT A PRIMITIVE ──────────────────────────────────────────────
--
-- AceGUI keeps ONE pool per widget type for the whole client: a CheckBox one Ka0s page releases can
-- be the next one WeakAuras' options or another Ka0s addon acquires. The primitives (SkinPaint*.lua)
-- record what they painted so a skin switch replays it; a pooled widget must not be replayed after
-- it left its page, and must not carry one addon's skin into the next acquirer (the spec's first
-- anti-goal). So an AceGUI row is painted here, outside the frame registry, with a lifetime of
-- exactly one acquisition:
--
--   * PAINT at acquisition, for the page's owner, when that owner is registered, under every skin
--     (Ka0s Default too since minor 2: it was stock AceGUI, the client's look, until the owner ruled
--     that Ka0s Default sets and paints everything). Stock regions are FADED by alpha, prior alpha recorded; fonts, text and
--     vertex colors and backdrops are recorded before the first change; Ka0s overlays are textures
--     made ONCE per widget object and reused by every later acquisition.
--   * RESTORE on release: the widget's per-instance OnRelease is wrapped (Skin:OnRelease, below) so
--     that, before AceGUI's own OnRelease runs, every recorded value goes back, every overlay hides
--     and the owner entry clears. The wrapper puts the original OnRelease back first, restores
--     under pcall, and always calls the original, because AceGUI:Release calls OnRelease raw: a
--     failing restore must never keep a widget out of the pool.
--   * NO REPAINT IN PLACE. A skin switch does not walk AceGUI rows: the Options instance re-renders
--     its owner's open pages one frame later (OptionsScroll.lua minor 6), and a re-render releases
--     every row (restored to stock) and acquires fresh ones (painted in the new skin).
--
-- WHERE IT IS CALLED. One choke point: `Skin.__AttachSkinAce(O, d)` wraps an Options instance's
-- `O.AceGUI` in a proxy whose `Create(type)` calls AceGUI's own Create and then paints the widget
-- for `d.addonName`, so no widget maker grows. A host that acquires a widget itself (through the
-- proxy it is handed as `O.AceGUI`, or straight from AceGUI) paints it with `Skin:PaintAce(owner,
-- widget)` or a whole container with `Skin:PaintAceTree(owner, container)`. A host that registers
-- an AceGUI widget type of its own built from a stock one (AuraMaster's AuraMasterDropdown is the
-- Dropdown under a second pool name) names that base once with `Skin:AliasAceType(hostType,
-- baseType)`: the base's painter paints it, the base's durability hooks keep it, and its release
-- gives it back stock like the base (minor 4).
--
-- DURABILITY. AceGUI recolors a widget's text from SetDisabled (and a CheckBox's SetValue calls it),
-- the Slider recolors its edit box's edge on enter and leave, and a Label's SetFontObject sets a
-- new font. Each is post-hooked ONCE per widget object (hooksecurefunc / HookScript), and the hook
-- re-applies the owner's tokens only while the widget is owned per the weak state table; otherwise
-- it does nothing, so a hook that rides the widget into another addon's hands is inert there.
--
-- WHAT IT NEVER DOES. No SetTexture('') and no method replaced with a no-op (the stock art is only
-- faded, so it comes back); nothing written onto a frame's table, and onto a widget's only the
-- OnRelease wrapper (taken back on release) and the post-hooks above (state lives in the weak
-- `lib.__ace`); no widget is ever handed to an EllesmereUI primitive (under `eui` the colors
-- come from the provider's derived tokens and the painting is this file's, LK-05's ruling); a
-- widget another skinning addon already skinned (ElvUI's `backdrop` / `template`, AddOnSkins'
-- `isSkinned`) is left to it; LSM30_* widgets and their pull-out lists, TabGroup and Blizzard's
-- ColorPickerFrame stay stock (the spec's non-goals). TreeGroup is painted since minor 4: both
-- panes, the row buttons, the selection and the tree's scroll bar, in the `nav.*` family whose Ka0s
-- Default values are the TreeGroup's own; its plus/minus toggles, row icons and dragger stay stock. Every field is guarded: a widget type or a
-- field a later AceGUI drops is skipped, never raised on.
--
-- Draws no LibKa0s-Media icon: every overlay is WHITE8X8 or the skin's own art.

local lib = LibStub and LibStub("LibKa0s-Skin-1.0", true)
if not lib then return end   -- the shell refused (no Core, or below its floor): nothing to attach to
if lib.__paintShellMinor ~= lib.MINOR or not lib.__P then return end   -- no helpers from this copy

-- Minor 2: Ka0s Default's rows are painted too (SkinPaint minor 6).
-- Minor 3: nothing is painted while the owner ignores its settings panel (Skin minor 5's
-- __PanelSkinned, the Appearance tab's "Ignore settings panel"); a widget acquired then stays stock,
-- and one this owner painted before is handed back stock when PaintAce is asked again.
-- Minor 4: Skin:AliasAceType, a host widget type painted as the stock type it is built from, and a
-- TreeGroup painter (LK-03 of Ka0sAddonsCommonTasks docs/2026-10-29-SKINNING_ROLLOUT).
local ACE_MINOR = 4
if lib.__aceMinor and lib.__aceMinor >= ACE_MINOR
  and lib.__aceShellMinor == lib.MINOR then return end
lib.__aceMinor      = ACE_MINOR
lib.__aceShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SkinAce = ACE_MINOR

local P = lib.__P
local rgba = P.rgba
local WEAK = { __mode = "k" }

-- Each painted widget's state, weakly: { owner, parts = { [key] = rec }, hooks = {}, armed }. A
-- part is one frame of the widget with its own record (`regions`, `saved`), the shape SkinPaint.lua's
-- helpers read, kept for the widget's lifetime so its overlays are made once.
lib.__ace = lib.__ace or setmetatable({}, WEAK)
-- The AceGUI proxies handed out (proxy -> AceGUI), so an instance is never wrapped twice.
lib.__aceProxy = lib.__aceProxy or setmetatable({}, WEAK)
-- The failure lines written this session, so each is written once.
lib.__aceLogged = lib.__aceLogged or {}
-- Host widget types painted as a stock type (hostType -> baseType), shared by every copy: an
-- alias names a fact about AceGUI's client-wide pools, not about one owner.
lib.__aceAlias = lib.__aceAlias or {}

local SIDES = { "Top", "Bottom", "Left", "Right" }
local PIECES = { "Left", "Middle", "Right" }
-- Another skinning addon's marks on a frame it skinned: ElvUI's CreateBackdrop / SetTemplate and
-- AddOnSkins' guard.
local OTHER_MARKS = { "isSkinned", "backdrop", "template" }
local MARKED_FRAMES = { "frame", "slider", "editbox", "dropdown", "button", "scrollBG", "scrollbar" }

--- Hand `err` to the client's error handler once per distinct message.
local function logOnce(err)
  local msg = tostring(err)
  if lib.__aceLogged[msg] then return end
  lib.__aceLogged[msg] = true
  local h = type(geterrorhandler) == "function" and geterrorhandler()
  if type(h) == "function" then h("LibKa0s-Skin-1.0 SkinAce: " .. msg) end
end

-- ── reading a widget ─────────────────────────────────────────────────────────────────────────

--- A widget's own field when it is a region of `want` ("Texture" / "FontString"), else nil.
local function region(w, key, want)
  local v = rawget(w, key)
  if P.kind(v) == want then return v end
  return nil
end

--- A widget's own field when it is a frame, else nil.
local function frameOf(w, key)
  local v = rawget(w, key)
  if P.isFrame(v) then return v end
  return nil
end

--- The template pieces of `frame`: SkinPaint's stock regions, plus the legacy `<name>Left/Middle/
--- Right` globals a named template frame carries.
local function pieces(frame)
  local out = P.stockRegions(frame)
  local name = type(frame.GetName) == "function" and frame:GetName() or nil
  if type(name) == "string" and type(_G) == "table" then
    for _, s in ipairs(PIECES) do
      local t = _G[name .. s]
      if P.isTexture(t) then out[#out + 1] = t end
    end
  end
  return out
end

--- True when another skinning addon already skinned this widget.
local function otherSkin(w)
  if rawget(w, "isSkinned") ~= nil then return true end
  for _, key in ipairs(MARKED_FRAMES) do
    local f = rawget(w, key)
    if type(f) == "table" then
      for _, mark in ipairs(OTHER_MARKS) do
        if rawget(f, mark) ~= nil then return true end
      end
    end
  end
  return false
end

--- True while the widget is drawn disabled.
local function disabled(w) return rawget(w, "disabled") and true or false end

--- The token a field of typed text takes: `input.text`, else the body text.
local function inputTok(T) return T["input.text"] and "input.text" or "text.body" end

--- The painter type of a widget type: its own when the library paints it, else the base type a
--- host aliased it to, else nil.
local function paintType(t)
  if type(t) ~= "string" then return nil end
  local paint = lib.__acePaint
  if type(paint) == "table" and paint[t] then return t end
  local base = lib.__aceAlias[t]
  if type(paint) == "table" and type(base) == "string" and paint[base] then return base end
  return nil
end

--- The painter of widget `w`: its type's, or its aliased base type's.
local function painterOf(w)
  local t = paintType(rawget(w, "type"))
  return t and lib.__acePaint[t] or nil
end

-- ── state ────────────────────────────────────────────────────────────────────────────────────

local function stateOf(w)
  local st = lib.__ace[w]
  if not st then
    st = { parts = {}, hooks = {} }
    lib.__ace[w] = st
  end
  return st
end

--- The record of `frame`, part `key` of the widget: made once, kept with the widget.
local function part(st, key, frame)
  local rec = st.parts[key]
  if not rec then
    rec = { regions = { stock = true } }
    st.parts[key] = rec
  end
  rec.frame, rec.owner = frame, st.owner
  return rec
end

-- ── drawing ──────────────────────────────────────────────────────────────────────────────────

--- `tex` in the skin's art `artTok` when it names one, else the color `colorTok`; hidden with neither.
local function artOr(tex, T, artTok, colorTok)
  local path = artTok and P.media("background", T[artTok])
  if path then
    tex:SetTexture(path)
    tex:SetVertexColor(1, 1, 1, 1)
  elseif T[colorTok] then
    tex:SetColorTexture(rgba(T[colorTok]))
  else
    return tex:Hide()
  end
  tex:Show()
end

local function edgePoints(t, side, anchor, l, top, r, b, size)
  t:ClearAllPoints()
  if side == "Top" or side == "Bottom" then
    local y = side == "Top" and -top or b
    local p = side == "Top" and "TOP" or "BOTTOM"
    t:SetPoint(p .. "LEFT", anchor, p .. "LEFT", l, y)
    t:SetPoint(p .. "RIGHT", anchor, p .. "RIGHT", -r, y)
    t:SetHeight(size)
  else
    local x = side == "Left" and l or -r
    local p = side == "Left" and "LEFT" or "RIGHT"
    t:SetPoint("TOP" .. p, anchor, "TOP" .. p, x, -top)
    t:SetPoint("BOTTOM" .. p, anchor, "BOTTOM" .. p, x, b)
    t:SetWidth(size)
  end
end

--- A flat box in regions of `host` over `anchor`, inset `ins` ({ l, t, r, b }, negative outsets):
--- the fill token `fill` (its gradient when the skin sets one), and a one-color edge from `edge`
--- (`<ctl>.borderSize` pixels, default 1). A nil token draws no fill or no edge.
local function box(rec, host, anchor, T, spec, ins)
  local l, t, r, b = 0, 0, 0, 0
  if ins then l, t, r, b = ins[1], ins[2], ins[3], ins[4] end
  local f = spec.fill and P.tex(rec, "aceFill", host, "BACKGROUND", 1)
  if f then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor, "TOPLEFT", l, -t)
    f:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -r, b)
    if spec.art then artOr(f, T, spec.art, spec.fill) else P.fill(rec, f, T, spec.fill) end
  else
    P.hide(rec, "aceFill")
  end
  local c = spec.edge and T[spec.edge]
  local size = spec.size and T[spec.size] or 1
  for _, side in ipairs(SIDES) do
    local e = c and P.tex(rec, "aceEdge" .. side, host, "BORDER", 1)
    if e then
      edgePoints(e, side, anchor, l, t, r, b, size)
      e:SetColorTexture(rgba(c))
      e:Show()
    else
      P.hide(rec, "aceEdge" .. side)
    end
  end
end

--- Recolor a box's edge (a focus or hover state), when it has one.
local function edgeColor(rec, c)
  if not c then return end
  for _, side in ipairs(SIDES) do
    local e = rec.regions["aceEdge" .. side]
    if e then e:SetColorTexture(rgba(c)) end
  end
end

--- A frame that wears a backdrop, flattened into the skin's fill and edge (its backdrop recorded
--- first and put back on release). Nothing when the frame has no backdrop or the fill token is nil.
local function flat(rec, frame, T, fillTok, edgeTok)
  if not P.hasBackdrop(frame) or not T[fillTok] then return end
  P.backdrop(rec, frame, T[fillTok], T[edgeTok], 1)
end

--- A font string in the skin's text role `tok` (`text.disabled` while `dis`) and the body font.
local function text(owner, rec, fs, T, tok, dis)
  if not P.isFS(fs) then return end
  P.tint(rec, fs, T, dis and "text.disabled" or tok)
  P.font(owner, rec, fs, "body")
end

-- ── hooks, once per widget object ────────────────────────────────────────────────────────────

--- The painter of `w`'s type, run again for its owner (a durability hook), under pcall.
local function repaint(w, st)
  local paint = painterOf(w)
  if type(paint) ~= "function" or not st.owner then return end
  local ok, err = pcall(paint, st.owner, w, st, P.T(st.owner))
  if not ok then logOnce(err) end
end

--- Post-hook the widget's method `name` once: it repaints while the widget is owned.
local function hookMethod(w, st, name)
  if st.hooks[name] or type(hooksecurefunc) ~= "function" or type(w[name]) ~= "function" then return end
  st.hooks[name] = true
  hooksecurefunc(w, name, function(self)
    local s = lib.__ace[self]
    if s and s.owner then repaint(self, s) end
  end)
end

--- HookScript `script` on `frame` once, as hook `key`: `fn(w, st)` runs while the widget is owned.
local function hookScript(w, st, key, frame, script, fn)
  if st.hooks[key] or type(frame.HookScript) ~= "function" then return end
  st.hooks[key] = true
  frame:HookScript(script, function()
    local s = lib.__ace[w]
    if not (s and s.owner) then return end
    local ok, err = pcall(fn, w, s)
    if not ok then logOnce(err) end
  end)
end

-- ── the painters, by widget type ─────────────────────────────────────────────────────────────

local PAINT = {}

local function buttonDisabled(btn)
  return type(btn.IsEnabled) == "function" and btn:IsEnabled() == false
end

-- Hover on a painted button's label, read at call time: the label and the disabled state are the
-- current acquisition's, never the first one's the hook was installed under.
local function buttonHover(key, on)
  return function(w, s)
    local r = s.parts[key]
    local fs = r and r.aceLabel
    if not fs then return end
    local dis = key == "frame" and disabled(w) or buttonDisabled(r.frame)
    if not dis then P.tint(r, fs, P.T(s.owner), on and "btn.hover" or "btn.text") end
  end
end

--- A push button frame (the Button widget's, an EditBox's "Okay", a MultiLineEditBox's "Accept"):
--- template art faded, the `btn.*` box, the label in `btn.text` (`btn.hover` under the pointer).
local function button(owner, w, st, key, btn, fs, dis)
  local rec = part(st, key, btn)
  local T = P.T(owner)
  P.fadeAll(rec, pieces(btn))
  box(rec, btn, btn, T, { fill = "btn.bg", edge = "btn.border", size = "btn.borderSize" })
  fs = fs or P.call(btn, "GetFontString", "FontString")
  rec.aceLabel = fs
  text(owner, rec, fs, T, "btn.text", dis)
  if not fs then return end
  hookScript(w, st, key .. ":OnEnter", btn, "OnEnter", buttonHover(key, true))
  hookScript(w, st, key .. ":OnLeave", btn, "OnLeave", buttonHover(key, false))
end

PAINT.Button = function(owner, w, st)
  local btn = frameOf(w, "frame")
  if btn then button(owner, w, st, "frame", btn, region(w, "text", "FontString"), disabled(w)) end
end

--- The check mark: the skin's mark art or color over the box, shown while AceGUI shows its own
--- check (half alpha while disabled or in the tri-state's unknown value, as AceGUI desaturates).
local function checkMark(rec, frame, T, bg, check, inset)
  local m = P.tex(rec, "aceMark", frame, "OVERLAY", 2)
  if not m then return end
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", bg, "TOPLEFT", inset, -inset)
  m:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -inset, inset)
  artOr(m, T, "check.markTexture", "check.mark")
  if not (check and check:IsShown()) then m:Hide() end
end

PAINT.CheckBox = function(owner, w, st, T)
  local frame = frameOf(w, "frame")
  if not frame then return end
  local rec = part(st, "frame", frame)
  local bg, check = region(w, "checkbg", "Texture"), region(w, "check", "Texture")
  P.fade(rec, bg)
  P.fade(rec, check)
  P.fade(rec, region(w, "highlight", "Texture"))
  if bg then
    local inset = math.floor((bg:GetWidth() or 24) / 6)
    box(rec, frame, bg, T, { fill = "check.bg", art = "check.texture", edge = "check.border",
                             size = "check.borderSize" }, { inset, inset, inset, inset })
    checkMark(rec, frame, T, bg, check, inset + 3)
    local m = rec.regions.aceMark
    local dim = disabled(w) or (rawget(w, "tristate") and rawget(w, "checked") == nil)
    if m then m:SetAlpha(dim and 0.5 or 1) end
  end
  local dis = disabled(w)
  text(owner, rec, region(w, "text", "FontString"), T, "text.body", dis)
  text(owner, rec, region(w, "desc", "FontString"), T, "text.muted", dis)
end

-- AceGUI's Slider recolors its edit box's backdrop edge on enter and leave: the skin's edge again.
local function sliderEditHover(on)
  return function(_, s)
    local r = s.parts.editbox
    local c = r and P.T(s.owner)[on and "input.focus" or "input.border"]
    if c and P.hasBackdrop(r.frame) then r.frame:SetBackdropBorderColor(rgba(c)) end
  end
end

PAINT.Slider = function(owner, w, st, T)
  local frame = frameOf(w, "frame")
  if not frame then return end
  local rec, dis = part(st, "frame", frame), disabled(w)
  text(owner, rec, region(w, "label", "FontString"), T, "text.body", dis)
  text(owner, rec, region(w, "lowtext", "FontString"), T, "text.muted", dis)
  text(owner, rec, region(w, "hightext", "FontString"), T, "text.muted", dis)
  local sl = frameOf(w, "slider")
  if sl then
    local r = part(st, "slider", sl)
    flat(r, sl, T, "slider.track", "slider.trackBorder")
    local thumb = P.call(sl, "GetThumbTexture", "Texture")
    if thumb then P.tint(r, thumb, T, "slider.thumb", "SetVertexColor") end
  end
  local eb = frameOf(w, "editbox")
  if not eb then return end
  local r = part(st, "editbox", eb)
  if P.hasBackdrop(eb) then P.backdrop(r, eb, T["input.bg"], T["input.border"], 1) end
  P.tint(r, eb, T, dis and "text.disabled" or inputTok(T))
  P.font(owner, r, eb, "body")
  hookScript(w, st, "editbox:OnEnter", eb, "OnEnter", sliderEditHover(true))
  hookScript(w, st, "editbox:OnLeave", eb, "OnLeave", sliderEditHover(false))
end

local function focusHook(on)
  return function(_, s)
    local r = s.parts.editbox
    if r then edgeColor(r, P.T(s.owner)[on and "input.focus" or "input.border"]) end
  end
end

-- InputBoxTemplate's art starts five pixels left of the edit box.
local EDIT_INSET = { -5, 0, 0, 0 }

PAINT.EditBox = function(owner, w, st, T)
  local frame = frameOf(w, "frame")
  if not frame then return end
  local dis = disabled(w)
  text(owner, part(st, "frame", frame), region(w, "label", "FontString"), T, "text.body", dis)
  local eb = frameOf(w, "editbox")
  if eb then
    local r = part(st, "editbox", eb)
    P.fadeAll(r, pieces(eb))
    box(r, eb, eb, T, { fill = "input.bg", edge = "input.border", size = "input.borderSize" }, EDIT_INSET)
    P.tint(r, eb, T, dis and "text.disabled" or inputTok(T))
    P.font(owner, r, eb, "body")
    hookScript(w, st, "editbox:focus", eb, "OnEditFocusGained", focusHook(true))
    hookScript(w, st, "editbox:blur", eb, "OnEditFocusLost", focusHook(false))
  end
  local btn = frameOf(w, "button")
  if btn then button(owner, w, st, "button", btn, nil, buttonDisabled(btn)) end
end

PAINT.MultiLineEditBox = function(owner, w, st, T)
  local frame = frameOf(w, "frame")
  if not frame then return end
  local dis = disabled(w)
  text(owner, part(st, "frame", frame), region(w, "label", "FontString"), T, "text.body", dis)
  local bg = frameOf(w, "scrollBG")
  if bg then flat(part(st, "scrollBG", bg), bg, T, "input.bg", "input.border") end
  local eb = frameOf(w, "editBox")
  if eb then
    local r = part(st, "editBox", eb)
    P.tint(r, eb, T, dis and "text.disabled" or inputTok(T))
    P.font(owner, r, eb, "body")
  end
  local btn = frameOf(w, "button")
  if btn then button(owner, w, st, "button", btn, nil, buttonDisabled(btn)) end
end

PAINT.Heading = function(owner, w, st, T)
  local frame = frameOf(w, "frame")
  if not frame then return end
  local rec = part(st, "frame", frame)
  text(owner, rec, region(w, "label", "FontString"), T, "text.heading", false)
  for _, key in ipairs({ "left", "right" }) do
    local t = region(w, key, "Texture")
    local line = t and T["section.rule"] and P.tex(rec, "aceRule" .. key, frame, "BACKGROUND", 1)
    if t then P.fade(rec, t) end
    if line then
      line:ClearAllPoints()
      line:SetPoint("LEFT", t, "LEFT")
      line:SetPoint("RIGHT", t, "RIGHT")
      line:SetHeight(1)
      line:SetColorTexture(rgba(T["section.rule"]))
      line:Show()
    end
  end
end

--- Label, InteractiveLabel and Icon: their text in the body role and font.
local function label(owner, w, st, T)
  local frame = frameOf(w, "frame")
  if not frame then return end
  text(owner, part(st, "frame", frame), region(w, "label", "FontString"), T, "text.body", disabled(w))
end
PAINT.Label = label
PAINT.InteractiveLabel = label
PAINT.Icon = label

PAINT.ColorPicker = function(owner, w, st, T)
  local frame = frameOf(w, "frame")
  if not frame then return end
  local rec = part(st, "frame", frame)
  text(owner, rec, region(w, "text", "FontString"), T, "text.body", disabled(w))
  local swatch = region(w, "colorSwatch", "Texture")
  if swatch then box(rec, frame, swatch, T, { edge = "input.border" }, { -1, -1, -1, -1 }) end
end

PAINT.InlineGroup = function(owner, w, st, T)
  local frame = frameOf(w, "frame")
  if not frame then return end
  text(owner, part(st, "frame", frame), region(w, "titletext", "FontString"), T, "text.heading", false)
  local content = frameOf(w, "content")
  local border = content and type(content.GetParent) == "function" and content:GetParent() or nil
  if P.isFrame(border) and border ~= frame then flat(part(st, "border", border), border, T, "panel.bg", "panel.border") end
end

--- A scroll bar's track in `scroll.track`: its stock BACKGROUND art faded, the skin's track drawn
--- over the bar. Nothing when the skin sets no track.
local function scrollTrack(st, sb, T)
  if not (sb and T["scroll.track"]) then return end
  local rec = part(st, "scrollbar", sb)
  if type(sb.GetRegions) == "function" then
    for _, r in ipairs({ sb:GetRegions() }) do
      local layer = P.isTexture(r) and not lib.__ours[r] and r:GetDrawLayer()
      if layer == "BACKGROUND" then P.fade(rec, r) end
    end
  end
  local t = P.tex(rec, "aceTrack", sb, "BACKGROUND", 0)
  if not t then return end
  t:SetAllPoints(sb)
  t:SetColorTexture(rgba(T["scroll.track"]))
  t:Show()
end

PAINT.ScrollFrame = function(_, w, st, T)
  scrollTrack(st, frameOf(w, "scrollbar"), T)
end

-- ── the tree ─────────────────────────────────────────────────────────────────────────────────
--
-- AceGUI's TreeGroup: a tree pane and a content pane (each a BackdropTemplate frame), the tree's
-- row buttons (OptionsListButtonTemplate, made as the tree first needs them and kept with the widget
-- for every later acquisition), and a UIPanelScrollBarTemplate bar. UpdateButton re-dresses each row
-- on every RefreshTree (its font object by level, LockHighlight for the selection), so RefreshTree
-- is a durability hook and a row's record is checked against what the painter last left on it.

--- A row's label: its template `text`, else its font string.
local function rowLabel(btn)
  local fs = rawget(btn, "text")
  if P.isFS(fs) then return fs end
  return P.call(btn, "GetFontString", "FontString")
end

local function sameColor(a, b)
  for i = 1, 4 do
    if math.abs((a[i] or 1) - (b[i] or 1)) > 0.001 then return false end
  end
  return true
end

--- When AceGUI re-dressed `fs` since the painter last left it (UpdateButton set its level's font or
--- color), what it set is the stock a release puts back: the older records are forgotten, so the
--- repaint records the new ones.
local function redressed(rec, fs)
  local left = rec.aceLeft and rec.aceLeft[fs]
  local s = rec.regions.saved
  if not (left and s) then return end
  local path = fs:GetFont()
  if s.font and (fs:GetFontObject() ~= left.obj or path ~= left.path) then s.font[fs] = nil end
  if s.SetTextColor and not sameColor({ fs:GetTextColor() }, left.color) then s.SetTextColor[fs] = nil end
end

--- Remember what the painter left on `fs`, for `redressed`.
local function leave(rec, fs)
  rec.aceLeft = rec.aceLeft or setmetatable({}, WEAK)
  local path = fs:GetFont()
  rec.aceLeft[fs] = { obj = fs:GetFontObject(), path = path, color = { fs:GetTextColor() } }
end

--- The token a row's label takes: `nav.text` for a first-level row at rest; `nav.selText` for a
--- deeper row (AceGUI draws every level below the first white), the selected row and the hovered one.
local function rowToken(btn, hover)
  if hover or rawget(btn, "selected") then return "nav.selText" end
  local level = tonumber(rawget(btn, "level")) or 1
  return level > 1 and "nav.selText" or "nav.text"
end

--- Paint row button `btn` (row `i` of the tree), its label read as hovered while `hover`.
local function paintRow(owner, st, T, i, btn, hover)
  local rec = part(st, "row" .. i, btn)
  local fs = rowLabel(btn)
  if fs then
    redressed(rec, fs)
    P.tint(rec, fs, T, rowToken(btn, hover))
    P.font(owner, rec, fs, "body")
    leave(rec, fs)
  end
  local hl = P.call(btn, "GetHighlightTexture", "Texture")
  if hl then P.tint(rec, hl, T, "nav.selBg", "SetVertexColor") end
end

-- The pointer on a row: the label in nav.selText, then back to its resting token. Read at call time
-- from the row's current state, so the hook installed under one acquisition serves every later one.
local function rowHover(i, on)
  return function(w, s)
    local buttons = rawget(w, "buttons")
    local btn = type(buttons) == "table" and buttons[i] or nil
    if P.isFrame(btn) then paintRow(s.owner, s, P.T(s.owner), i, btn, on) end
  end
end

--- A pane: the TreeGroup's tooltip-edged backdrop flattened into `nav.bg` under a `nav.border` edge.
local function pane(st, key, frame, T)
  if not (frame and P.hasBackdrop(frame) and T["nav.bg"]) then return end
  P.backdrop(part(st, key, frame), frame, T["nav.bg"], T["nav.border"], T["nav.borderSize"] or 1)
end

PAINT.TreeGroup = function(owner, w, st, T)
  pane(st, "treeframe", frameOf(w, "treeframe"), T)
  pane(st, "border", frameOf(w, "border"), T)
  scrollTrack(st, frameOf(w, "scrollbar"), T)
  local buttons = rawget(w, "buttons")
  for i, btn in ipairs(type(buttons) == "table" and buttons or {}) do
    if P.isFrame(btn) then
      paintRow(owner, st, T, i, btn, false)
      hookScript(w, st, "row" .. i .. ":OnEnter", btn, "OnEnter", rowHover(i, true))
      hookScript(w, st, "row" .. i .. ":OnLeave", btn, "OnLeave", rowHover(i, false))
    end
  end
end

-- ── the dropdown and its pull-out ────────────────────────────────────────────────────────────

--- Put a pull-out back: its frame, its scroll bar and every item it painted.
local function restorePullout(po)
  local pst = lib.__ace[po]
  if not (pst and pst.owner) then return end
  for key, rec in pairs(pst.parts) do
    P.unpaint(rec, rec.frame)
    if type(key) ~= "string" then pst.parts[key] = nil end   -- an item: pooled on its own
  end
  pst.owner = nil
end

--- Paint an open pull-out for `owner`: the menu fill and edge, its items' text and highlight.
local function paintPullout(owner, po)
  local frame = frameOf(po, "frame")
  if not frame then return end
  local pst = stateOf(po)
  pst.owner = owner
  local T = P.T(owner)
  flat(part(pst, "frame", frame), frame, T, "menu.bg", "menu.border")
  local sl = frameOf(po, "slider")
  local thumb = sl and P.call(sl, "GetThumbTexture", "Texture")
  if thumb then P.tint(part(pst, "slider", sl), thumb, T, "scroll.thumb", "SetVertexColor") end
  for _, item in ipairs(type(rawget(po, "items")) == "table" and po.items or {}) do
    local f = type(item) == "table" and frameOf(item, "frame")
    if f then
      local r = part(pst, item, f)
      local fs = region(item, "text", "FontString")
      if fs then P.tint(r, fs, T, rawget(item, "disabled") and "text.disabled" or "menu.text") end
      local hl = region(item, "highlight", "Texture")
      if hl then P.tint(r, hl, T, "menu.hover", "SetVertexColor") end
    end
  end
end

--- The dropdown that owns `po` while it is acquired, and that dropdown's owner.
local function pulloutOwner(po)
  local ud = rawget(po, "userdata")
  local dd = type(ud) == "table" and ud.obj or nil
  local s = type(dd) == "table" and lib.__ace[dd] or nil
  return s and s.owner or nil
end

local function hookPullout(po)
  if type(hooksecurefunc) ~= "function" then return end
  local pst = stateOf(po)
  if pst.hooks.pullout then return end
  pst.hooks.pullout = true
  local function onOpen(self)
    local owner = pulloutOwner(self)
    local ok, err = pcall(function()
      if owner then paintPullout(owner, self) else restorePullout(self) end
    end)
    if not ok then logOnce(err) end
  end
  local function onClose(self)
    local ok, err = pcall(restorePullout, self)
    if not ok then logOnce(err) end
  end
  if type(po.Open) == "function" then hooksecurefunc(po, "Open", onOpen) end
  if type(po.Close) == "function" then hooksecurefunc(po, "Close", onClose) end
  if type(po.Clear) == "function" then hooksecurefunc(po, "Clear", onClose) end
end

-- The dropdown's visible bar is the 25px at the bottom of the widget, where AceGUI lays its own
-- click cover (`button_cover`); the template frame overhangs it by its art's padding.
PAINT.Dropdown = function(owner, w, st, T)
  local frame = frameOf(w, "frame")
  if not frame then return end
  local rec, dis = part(st, "frame", frame), disabled(w)
  local dd = frameOf(w, "dropdown")
  if dd then P.fadeAll(part(st, "dropdown", dd), pieces(dd)) end
  local bar = frameOf(w, "button_cover") or frame
  box(rec, frame, bar, T, { fill = "input.bg", edge = "input.border", size = "input.borderSize" })
  text(owner, rec, region(w, "text", "FontString"), T, inputTok(T), dis)
  text(owner, rec, region(w, "label", "FontString"), T, "text.body", dis)
  local po = rawget(w, "pullout")
  if type(po) == "table" then hookPullout(po) end
end

-- A newer minor's painters replace these: the hooks look them up at call time.
lib.__acePaint = PAINT

-- Durability hooks per type, beyond SetDisabled (every painted type has it when AceGUI does).
local EXTRA_HOOKS = { CheckBox = { "SetType" }, Label = { "SetFontObject" }, InteractiveLabel = { "SetFontObject" },
                      TreeGroup = { "RefreshTree" } }

-- ── restore, and the release chain ───────────────────────────────────────────────────────────

--- Put a widget back as stock: every part's faded art, fonts, colors and backdrops, its pull-out,
--- and every overlay hidden. The overlays are kept for the next acquisition.
local function restore(w, st)
  local po = rawget(w, "pullout")
  if type(po) == "table" then restorePullout(po) end
  for _, rec in pairs(st.parts) do P.unpaint(rec, rec.frame) end
  st.owner = nil
end
lib.__aceRestore = restore

--- Chain `fn(widget)` onto the widget's OWN OnRelease, once for its next release: the wrapper puts
--- the previous OnRelease back first, runs `fn` under pcall (a failure is logged once), and then
--- always calls the previous one, so AceGUI's own release and the widget's return to the pool
--- never depend on `fn`. AceGUI keeps one CALLBACK per event name (options-ui-§19), so a skin, a
--- host and the library cannot all use SetCallback("OnRelease"); this chain lets them coexist.
--- Answers fn.
function lib:OnRelease(widget, fn)
  if type(widget) ~= "table" or type(fn) ~= "function" then return nil end
  local had = rawget(widget, "OnRelease")
  widget.OnRelease = function(self, ...)
    rawset(self, "OnRelease", had)
    local ok, err = pcall(fn, self)
    if not ok then logOnce(err) end
    local orig = self.OnRelease
    if type(orig) == "function" then return orig(self, ...) end
  end
  return fn
end

local function releaseHook(w)
  local st = lib.__ace[w]
  if not st then return end
  st.armed = false
  if st.owner then restore(w, st) end
end

local function arm(w, st)
  if st.armed then return end
  st.armed = true
  lib:OnRelease(w, releaseHook)
end

-- A Label's font object changed by its host: that is the stock font a release puts back, so the
-- recorded one is forgotten before the repaint records the new one.
local function forgetFont(w)
  local st = lib.__ace[w]
  local rec = st and st.parts.frame
  local fonts = rec and rec.regions.saved and rec.regions.saved.font
  local fs = region(w, "label", "FontString")
  if fonts and fs then fonts[fs] = nil end
end

-- Installed BEFORE the generic SetFontObject repaint hook: hooksecurefunc runs the hooks in the
-- order they were installed, and the font must be forgotten before it is re-recorded.
local function hookLabelFont(w, st)
  if st.hooks.fontFirst or type(hooksecurefunc) ~= "function" or type(w.SetFontObject) ~= "function" then return end
  st.hooks.fontFirst = true
  hooksecurefunc(w, "SetFontObject", function(self)
    local s = lib.__ace[self]
    if s and s.owner then forgetFont(self) end
  end)
end

local function installHooks(w, st)
  local t = paintType(rawget(w, "type"))
  if t == "Label" or t == "InteractiveLabel" then hookLabelFont(w, st) end
  hookMethod(w, st, "SetDisabled")
  for _, name in ipairs(EXTRA_HOOKS[t] or {}) do hookMethod(w, st, name) end
end

-- ── the members ──────────────────────────────────────────────────────────────────────────────

--- Paint an AceGUI widget the host acquired for `owner`'s page: its stock regions faded and its
--- text, fonts and backdrops in the owner's skin, restored on its next release. Paints nothing
--- (answers false) for an owner that is not registered, a widget type with no painter, or a widget
--- another skinning addon already skinned.
--- Calling it again for the same owner repaints in place; for another owner, gives the widget back
--- first. Answers true when it painted.
function lib:PaintAce(owner, widget)
  if type(widget) ~= "table" or type(rawget(widget, "frame")) ~= "table" then return false end
  local paint = painterOf(widget)
  if type(paint) ~= "function" or not self:IsOwner(owner) then return false end
  if type(self.__PanelSkinned) == "function" and not self:__PanelSkinned(owner) then
    local held = lib.__ace[widget]
    if held and held.owner == owner then restore(widget, held) end
    return false
  end
  local st = lib.__ace[widget]
  if st and st.owner and (st.owner ~= owner or otherSkin(widget)) then restore(widget, st) end
  if otherSkin(widget) then return false end
  st = stateOf(widget)
  st.owner = owner
  arm(widget, st)
  installHooks(widget, st)
  local ok, err = pcall(paint, owner, widget, st, P.T(owner))
  if not ok then logOnce(err) end
  return ok
end

--- Paint AceGUI widget type `hostType`, a host's own type built from the stock type `baseType`
--- (AuraMaster's AuraMasterDropdown is AceGUI's Dropdown under a second pool name), with
--- `baseType`'s painter: PaintAce, the proxy, the durability hooks and the release restore all treat
--- it as the base. One alias per host type for the session, shared by every copy of a host; saying
--- the same alias again answers true. Refused (false, logged once per refusal) when either name is
--- not a string, `baseType` has no painter, `hostType` has a painter of its own, or `hostType` is
--- already aliased to another base. Answers true when the alias holds.
function lib:AliasAceType(hostType, baseType)
  local why
  if type(hostType) ~= "string" or hostType == "" or type(baseType) ~= "string" then
    why = "a host type and a base type are strings"
  elseif lib.__acePaint[hostType] then
    why = hostType .. " has a painter of its own"
  elseif not lib.__acePaint[baseType] then
    why = baseType .. " has no painter"
  elseif lib.__aceAlias[hostType] and lib.__aceAlias[hostType] ~= baseType then
    why = hostType .. " is already painted as " .. lib.__aceAlias[hostType]
  end
  if why then
    logOnce("AliasAceType(" .. tostring(hostType) .. ", " .. tostring(baseType) .. ") refused: " .. why)
    return false
  end
  lib.__aceAlias[hostType] = baseType
  return true
end

--- PaintAce over `container` and every widget under it (its `children`, depth first). Answers how
--- many widgets it painted.
function lib:PaintAceTree(owner, container)
  if type(container) ~= "table" then return 0 end
  local n = self:PaintAce(owner, container) and 1 or 0
  local kids = rawget(container, "children")
  for _, child in ipairs(type(kids) == "table" and kids or {}) do n = n + self:PaintAceTree(owner, child) end
  return n
end

--- For the proxy: a widget just handed out by AceGUI's Create. A widget that comes back from the
--- pool still owned (its release never reached the wrapper: a host replaced OnRelease outright) is
--- put back first, then painted for `owner`.
function lib:__AceAcquired(owner, widget)
  local st = lib.__ace[widget]
  if st and st.owner then
    st.armed = false
    restore(widget, st)
  end
  return self:PaintAce(owner, widget)
end

-- ── the AceGUI proxy (the Options choke point) ───────────────────────────────────────────────

local function bind(real, proxy, fn)
  return function(self, ...)
    if self == proxy then self = real end
    return fn(self, ...)
  end
end

--- A stand-in for AceGUI-3.0 bound to `owner`: `Create` is AceGUI's own Create, then PaintAce for
--- the owner while it is registered; every other field and method is AceGUI's (a method called on
--- the proxy runs on AceGUI itself), and a write lands on AceGUI.
local function makeProxy(real, owner)
  local proxy, cache = {}, setmetatable({}, WEAK)
  proxy.Create = function(self, wtype, ...)
    local base = self == proxy and real or self
    local w = base:Create(wtype, ...)
    if type(w) == "table" and lib:IsOwner(owner) then
      local ok, err = pcall(lib.__AceAcquired, lib, owner, w)
      if not ok then logOnce(err) end
    end
    return w
  end
  setmetatable(proxy, {
    __index = function(_, k)
      local v = real[k]
      if type(v) ~= "function" then return v end
      local b = cache[v]
      if not b then
        b = bind(real, proxy, v)
        cache[v] = b
      end
      return b
    end,
    __newindex = function(_, k, v) real[k] = v end,
  })
  lib.__aceProxy[proxy] = real
  return proxy
end

--- Wrap an Options instance's `O.AceGUI` in the proxy for its descriptor's `addonName`, once that
--- addon is a registered skin owner. Called by the Options major when it resolves AceGUI (lib:New
--- and CreateOptionsPanel); a handle already wrapped, no AceGUI and no registered owner leave
--- `O.AceGUI` exactly as it was. Internal.
function lib.__AttachSkinAce(O, d)
  if type(O) ~= "table" or type(d) ~= "table" then return end
  local owner, ace = d.addonName, O.AceGUI
  if type(owner) ~= "string" or type(ace) ~= "table" or lib.__aceProxy[ace] then return end
  if not lib:IsOwner(owner) then return end
  O.AceGUI = makeProxy(ace, owner)
end
