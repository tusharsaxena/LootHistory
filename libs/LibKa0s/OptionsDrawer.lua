-- LibKa0s-Options-1.0 -- the drawer: a header bar per subject, with a chevron, the subject's name
-- (gold while it is set) and a one-line summary of its value at the right, which opens a bordered
-- box joined under it. The host fills the box with ordinary rows (O.RenderGrid, O.IdList,
-- O.TextRow, O.InlineButtonPair, its own `make` items), and may put action buttons on its last
-- line, right-aligned. A page of conditions or filters reads as a list of what is set, and opens
-- only what the player is editing.
--
-- An eleventh file of the Options major (minor 1), guarded with the same multi-file idiom as
-- OptionsNav.lua. A new file rather than an append because OptionsWidgets.lua is at its accepted
-- size and its re-check trigger is "the next maker added" (CLAUDE.md's census): Options.lua carries
-- only the guarded attach and RefreshPanel's read of `__drawerPage`, so a copy vendored without
-- this file draws every page exactly as it did before the drawer existed.
--
-- BUILT FROM AceGUI's OWN SimpleGroup, NOT A REGISTERED WIDGET TYPE. AceGUI's widget registry is
-- process-global (Options.lua's note above `lib.__PatchLSM30Border`), and a type registered under a
-- new name would be this library's for the whole session, versioned against every other vendored
-- copy. Three SimpleGroups (the drawer, its header, its box) are what any page already draws, and
-- the decoration rides on their frames, taken off again on release.
--
-- THE OPEN STATE IS THE HOST'S, as a tab strip's selection is (`spec.open` / `spec.onToggle`).
-- The library reads neither back: a click hands the host the other state and re-renders the page
-- (a drawer that opens changes the page's shape), so any number may be open at once and the host
-- decides how long the state lives. Session state, never persisted (options-ui-§13's rule for a
-- sub-strip's selection, applied to the same kind of view state).

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: O.Drawer, the body ctx that draws into the box and writes through to the page, and the
-- box's padding (lib.__drawerPad).
local DRAWER_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own -- see OptionsScroll.lua for why.
if lib.__drawerMinor and lib.__drawerMinor >= DRAWER_MINOR
  and lib.__drawerShellMinor == lib.MINOR then return end
lib.__drawerMinor      = DRAWER_MINOR
lib.__drawerShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsDrawer = DRAWER_MINOR

-- File-local, not lib.LAYOUT, for OptionsNav.lua's reason: tests/test_options.lua's LAYOUT gate
-- reads Options.lua alone, and no host sizes anything off these.
local HEADER_H     = 26
local CHEVRON_X    = 8
local CHEVRON_SIZE = 12
local LABEL_X      = 26
local SUMMARY_GAP  = 12
local SUMMARY_PAD  = 10
-- The space after a drawer, open or closed, before the next one.
local DRAWER_GAP   = 4
-- The box's inner padding. The left one lines the box's rows up under the header's label, past the
-- chevron. Library-level and `__`-prefixed for the suite alone: the padding is applied by patched
-- methods only a real AceGUI layout pass calls.
lib.__drawerPad = { left = LABEL_X, right = 10, top = 8, bottom = 8 }
local PAD = lib.__drawerPad
-- An action button's share of the box's last line, and what the filler gives back so the line
-- never sums to 1 (the ScrollFrame's clip, options-ui-§8, as BUTTON_PAIR_REL's inset).
local ACTION_REL   = 0.22
local CLIP_INSET   = 0.02

-- The settings panel's own palette: the gold of every section heading and selected tab, white text,
-- dark fills under thin borders (the AceGUI tree pane OptionsNav.lua draws, a shade warmer).
local GOLD         = { 1, 0.82, 0 }
local WHITE        = { 1, 1, 1 }
local SUMMARY_SET  = { 0.91, 0.85, 0.66 }
local SUMMARY_ANY  = { 0.5, 0.5, 0.5 }
local HEAD_FILL    = { 0.08, 0.07, 0.06, 0.9 }
local HEAD_FILL_OPEN = { 0.13, 0.11, 0.08, 0.95 }
local HEAD_EDGE    = { 0.18, 0.16, 0.14, 1 }
local HEAD_EDGE_OPEN = { 0.42, 0.33, 0.13, 1 }
local BOX_FILL     = { 0.08, 0.07, 0.05, 0.9 }
local BOX_EDGE     = { 0.24, 0.2, 0.13, 1 }
local HOVER_TEX    = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local CHEVRON_TEX  = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local FLAT_TEX     = "Interface\\Buttons\\WHITE8X8"

-- ── the frames' decoration ───────────────────────────────────────────────────────────────────

--- Four 1px edges and a fill, as textures on `frame`; `noTop` leaves the top edge off (the box
--- joins the header above it).
local function newEdges(frame, noTop)
  local e = {}
  e.fill = frame:CreateTexture(nil, "BACKGROUND")
  e.fill:SetTexture(FLAT_TEX)
  e.fill:SetAllPoints(frame)
  local function edge(p1, p2, horizontal)
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetTexture(FLAT_TEX)
    t:SetPoint(p1, frame, p1, 0, 0)
    t:SetPoint(p2, frame, p2, 0, 0)
    if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    return t
  end
  e.left   = edge("TOPLEFT", "BOTTOMLEFT", false)
  e.right  = edge("TOPRIGHT", "BOTTOMRIGHT", false)
  e.bottom = edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  if not noTop then e.top = edge("TOPLEFT", "TOPRIGHT", true) end
  return e
end

local function paintEdges(e, fill, edge)
  e.fill:SetVertexColor(fill[1], fill[2], fill[3], fill[4])
  for _, k in ipairs({ "left", "right", "bottom", "top" }) do
    if e[k] then e[k]:SetVertexColor(edge[1], edge[2], edge[3], edge[4]) end
  end
end

--- The header's button, built once per pooled frame and re-dressed on every draw, as a rail entry is
--- (OptionsNav.lua's newEntry): nothing here depends on WHICH drawer it will be.
local function newHead(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetAllPoints(parent)
  b.__ka0sDrawerEdges = newEdges(b, false)
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetTexture(HOVER_TEX)
  hover:SetBlendMode("ADD")
  hover:SetAlpha(0.35)
  hover:SetAllPoints(b)
  local chev = b:CreateTexture(nil, "ARTWORK")
  chev:SetTexture(CHEVRON_TEX)
  chev:SetSize(CHEVRON_SIZE, CHEVRON_SIZE)
  chev:SetPoint("LEFT", b, "LEFT", CHEVRON_X, 0)
  local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("LEFT", b, "LEFT", LABEL_X, 0)
  label:SetJustifyH("LEFT")
  -- One line, cut with an ellipsis by the client where it meets the right edge: a summary is a
  -- glance, and the box holds the whole value.
  local summary = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  summary:SetPoint("LEFT", label, "RIGHT", SUMMARY_GAP, 0)
  summary:SetPoint("RIGHT", b, "RIGHT", -SUMMARY_PAD, 0)
  summary:SetJustifyH("RIGHT")
  if summary.SetWordWrap then summary:SetWordWrap(false) end
  b.__ka0sDrawerChevron, b.__ka0sDrawerLabelFS, b.__ka0sDrawerSummaryFS = chev, label, summary
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return b
end

--- The box's decoration, kept on its pooled frame the way the header's button is.
local function boxEdges(frame)
  local e = frame.__ka0sDrawerBox
  if not e then
    e = newEdges(frame, true)
    frame.__ka0sDrawerBox = e
  end
  for _, t in pairs(e) do t:Show() end
  paintEdges(e, BOX_FILL, BOX_EDGE)
  return e
end

-- ── the box's padding ────────────────────────────────────────────────────────────────────────
--
-- A SimpleGroup lays its children out across its whole frame and sizes itself to exactly their
-- height (AceGUIContainer-SimpleGroup.lua's OnWidthSet and LayoutFinished), so a box with room
-- inside its border needs three of its methods told about the padding. AceGUI sets a widget's
-- methods on the widget table itself and POOLS the table, so a patched method left in place would
-- pad the next SimpleGroup any addon in the session asks for: every one is put back on release,
-- the way OptionsScroll.lua puts its scrollbar patch back.

local PATCHED = { "OnWidthSet", "OnHeightSet", "LayoutFinished" }

local function padBox(body)
  local saved = {}
  for _, k in ipairs(PATCHED) do saved[k] = body[k] end
  body.__ka0sDrawerSaved = saved
  local function inner(content)
    if type(content) ~= "table" or not content.ClearAllPoints then return end
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", body.frame, "TOPLEFT", PAD.left, -PAD.top)
    content:SetPoint("BOTTOMRIGHT", body.frame, "BOTTOMRIGHT", -PAD.right, PAD.bottom)
  end
  inner(body.content)
  body.OnWidthSet = function(self, width)
    local content, w = self.content, math.max(0, (width or 0) - PAD.left - PAD.right)
    if content then
      content:SetWidth(w)
      content.width = w
    end
  end
  body.OnHeightSet = function(self, height)
    local content, h = self.content, math.max(0, (height or 0) - PAD.top - PAD.bottom)
    if content then
      content:SetHeight(h)
      content.height = h
    end
  end
  body.LayoutFinished = function(self, _, height)
    if self.noAutoHeight then return end
    self:SetHeight((height or 0) + PAD.top + PAD.bottom)
  end
end

--- Undo padBox: the three methods, the content's two anchors (SimpleGroup's constructor's own), and
--- the decoration hidden on the frame the pool keeps.
local function unpadBox(body)
  local saved = body.__ka0sDrawerSaved
  if saved then
    for _, k in ipairs(PATCHED) do body[k] = saved[k] end
    body.__ka0sDrawerSaved = nil
  end
  local content = body.content
  if type(content) == "table" and content.ClearAllPoints then
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT")
    content:SetPoint("BOTTOMRIGHT")
  end
  local e = body.frame and body.frame.__ka0sDrawerBox
  if e then for _, t in pairs(e) do t:Hide() end end
end

-- ── the body ctx ─────────────────────────────────────────────────────────────────────────────

--- The ctx a drawer's body is drawn with: its scroll is the box, so every helper that draws into
--- `O.EnsureScroll(ctx)` draws there, and every other field is the PAGE's -- read through, and
--- written through, so a refresher, a host's per-page list or a heading tracker set while drawing
--- the box lands on the ctx the registry holds and is not lost with the view. `__drawerPage` names
--- that page, for the toggle below and for O.RefreshPanel (Options minor 29), which takes a body
--- ctx back to its page rather than rendering the whole page into one box.
local function bodyCtx(ctx, body)
  local page = rawget(ctx, "__drawerPage") or ctx
  return setmetatable({ scroll = body, __drawerPage = page }, { __index = ctx, __newindex = page })
end

--- Attach O.Drawer to one instance. Called from the end of lib:New, after OptionsNav.lua's attach.
function lib.__AttachDrawer(O)
  local function print(line) if O.__print then O.__print(line) end end
  local function refused(kind, subject)
    return O.__combatRefused ~= nil and O.__combatRefused(kind, subject)
  end

  --- A spec field that may be a function, read now; a raise reads as nil and is reported.
  local function readField(v, label)
    if type(v) ~= "function" then return v end
    local ok, got = pcall(v)
    if ok then return got end
    print(lib.STRINGS.ROW_FAILED:format("drawer " .. tostring(label), tostring(got)))
    return nil
  end

  local function dressHead(head, spec, open, set, summary)
    local label = spec.label or ""
    head.__ka0sDrawerLabel, head.__ka0sDrawerSummary = label, summary
    head.__ka0sDrawerSet, head.__ka0sDrawerOpen = set, open
    head.__ka0sDrawerLabelRGB = set and GOLD or WHITE
    head.__ka0sDrawerSummaryRGB = set and SUMMARY_SET or SUMMARY_ANY
    local lr, sr = head.__ka0sDrawerLabelRGB, head.__ka0sDrawerSummaryRGB
    head.__ka0sDrawerLabelFS:SetText(label)
    head.__ka0sDrawerLabelFS:SetTextColor(lr[1], lr[2], lr[3])
    head.__ka0sDrawerSummaryFS:SetText(summary)
    head.__ka0sDrawerSummaryFS:SetTextColor(sr[1], sr[2], sr[3])
    -- Right while closed, down while open: the same art turned a quarter.
    if head.__ka0sDrawerChevron.SetRotation then
      head.__ka0sDrawerChevron:SetRotation(open and -math.pi / 2 or 0)
    end
    paintEdges(head.__ka0sDrawerEdges, open and HEAD_FILL_OPEN or HEAD_FILL, open and HEAD_EDGE_OPEN or HEAD_EDGE)
    head:Show()
  end

  local function wireHead(head, ctx, spec, open)
    local page = rawget(ctx, "__drawerPage") or ctx
    head:SetScript("OnClick", function()
      -- A toggle re-renders the page, refused in combat as a tab click is (options-ui-§2). The
      -- library owns the refusal; a host adds no guard of its own.
      if refused("drawer", spec.label or "?") then return end
      if type(spec.onToggle) ~= "function" then return end
      local ok, err = pcall(spec.onToggle, not open)
      if not ok then
        print(lib.STRINGS.BUTTON_FAILED:format(tostring(err)))
        return
      end
      -- RefreshPanel carries the scroll offset across the re-render (Options.lua's keepScroll): a
      -- toggle is navigation, so the player stays where they were.
      O.RefreshPanel(page, true)
    end)
    head:SetScript("OnEnter", function()
      if not (GameTooltip and spec.tooltip) then return end
      GameTooltip:SetOwner(head, "ANCHOR_RIGHT")
      GameTooltip:SetText(spec.label or "", 1, 1, 1)
      GameTooltip:AddLine(spec.tooltip, nil, nil, nil, true)
      GameTooltip:Show()
    end)
  end

  local function drawHeader(group, ctx, spec, open)
    local header = O.AceGUI:Create("SimpleGroup")
    header:SetLayout(nil)
    header:SetFullWidth(true)
    header:SetHeight(HEADER_H)
    local frame = header.frame
    local head = frame.__ka0sDrawerHead
    if not head then
      head = newHead(frame)
      frame.__ka0sDrawerHead = head
    end
    local set = readField(spec.set, spec.label) and true or false
    local summary = readField(spec.summary, spec.label)
    dressHead(head, spec, open, set, summary ~= nil and tostring(summary) or "")
    wireHead(head, ctx, spec, open)
    -- The pooled frame goes back with the button hidden and deaf, so the next SimpleGroup any addon
    -- takes from the pool neither shows a stale header nor fires a stale toggle.
    header:SetCallback("OnRelease", function()
      head:Hide()
      head:SetScript("OnClick", nil)
      head:SetScript("OnEnter", nil)
    end)
    group:AddChild(header)
    return header, head
  end

  --- The box's last line: a filler, then each action, so the buttons end at the right edge.
  local function drawActions(body, spec, disabled)
    local actions = type(spec.actions) == "table" and spec.actions or nil
    if not actions or #actions == 0 then return nil end
    local row = O.AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    local filler = O.AceGUI:Create("Label")
    filler:SetText("")
    filler:SetRelativeWidth(math.max(0, 1 - #actions * ACTION_REL - CLIP_INSET))
    row:AddChild(filler)
    for _, a in ipairs(actions) do
      local btn = O.AceGUI:Create("Button")
      btn:SetText(a.text or "")
      btn:SetRelativeWidth(ACTION_REL)
      if disabled or a.disabled then btn:SetDisabled(true) end
      btn:SetCallback("OnClick", function()
        if type(a.onClick) ~= "function" then return end
        if refused("button", a.text or "?") then return end
        local ok, err = pcall(a.onClick)
        if not ok then print(lib.STRINGS.BUTTON_FAILED:format(tostring(err))) end
      end)
      if O.AttachTooltip then O.AttachTooltip(btn, a.text, a.tooltip) end
      row:AddChild(btn)
    end
    body:AddChild(row)
    return row
  end

  --- The box, filled: the host's body under the render-disabled flag when `spec.disabled`, then the
  --- actions. The flag is the PAGE's and is put back on the way out, a raise included, as
  --- RenderRows puts back its own. A drawer drawn while the page is already render-disabled (a
  --- disabled tab, RenderRows' `opts.disabled`) draws its actions disabled too, as
  --- InlineButtonPair and IdList honor the same flag.
  local function drawBody(group, ctx, spec)
    local body = O.AceGUI:Create("SimpleGroup")
    body:SetLayout("Flow")
    body:SetFullWidth(true)
    boxEdges(body.frame)
    padBox(body)
    body:SetCallback("OnRelease", function() unpadBox(body) end)
    group:AddChild(body)
    local view = bodyCtx(ctx, body)
    local page = view.__drawerPage
    local outer = page.__renderDisabled
    page.__renderDisabled = (spec.disabled or outer) and true or nil
    if type(spec.body) == "function" then
      local ok, err = pcall(spec.body, view, body)
      if not ok then
        print(lib.STRINGS.ROW_FAILED:format("drawer " .. tostring(spec.label or "?"), tostring(err)))
      end
    end
    page.__renderDisabled = outer
    local actions = drawActions(body, spec, spec.disabled or outer)
    if body.DoLayout then body:DoLayout() end
    return body, view, actions
  end

  --- One drawer, added to `O.EnsureScroll(ctx)` -- the page, or the box of the drawer whose body
  --- ctx `ctx` is.
  ---
  --- `spec`:
  ---   label     string               the header's name.
  ---   summary   string | function()  the value at a glance, right of the name, cut with an
  ---                                  ellipsis where it meets the edge. The host words "nothing
  ---                                  set" itself ("Any").
  ---   set       boolean | function() the name is gold while true, white otherwise; the summary
  ---                                  is a pale gold while true and gray otherwise.
  ---   tooltip   string               the header's tooltip body, under the name.
  ---   open      boolean              the box is drawn.
  ---   onToggle  function(open)       a header click hands the host the other state; the library
  ---                                  then re-renders the page (O.RefreshPanel(page, true)),
  ---                                  keeping the page's scroll offset. A raise is reported and
  ---                                  nothing is redrawn. Refused in combat.
  ---   body      function(ctx, box)   fills the box. `ctx` draws into the box and is the page's
  ---                                  for every other field; never ClearScroll it. pcall'd and
  ---                                  reported, so a raise costs the box, not the page.
  ---   actions   { { text, tooltip, onClick, disabled } }  buttons on the box's last line,
  ---                                  right-aligned; onClick pcall'd and refused in combat.
  ---   disabled  boolean              the body is drawn under the render-disabled flag the
  ---                                  library's own rows honor (a host's `make` widget reads
  ---                                  `ctx.__renderDisabled` itself), and every action is disabled.
  ---                                  A drawer drawn while the page's flag is already set is
  ---                                  drawn the same way.
  ---
  --- Returns `{ group, header, head, body, ctx, actions, open }` (body, ctx and actions nil while
  --- closed), or nil having drawn nothing with no AceGUI.
  function O.Drawer(ctx, spec)
    local scroll = O.EnsureScroll(ctx)
    if not (scroll and O.AceGUI) then return nil end
    spec = spec or {}
    local open = spec.open and true or false
    local group = O.AceGUI:Create("SimpleGroup")
    group:SetLayout("List")
    group:SetFullWidth(true)
    local header, head = drawHeader(group, ctx, spec, open)
    local drawer = { group = group, header = header, head = head, open = open }
    if open then
      drawer.body, drawer.ctx, drawer.actions = drawBody(group, ctx, spec)
    end
    O.AddSpacer(group, DRAWER_GAP)
    scroll:AddChild(group)
    if group.DoLayout then group:DoLayout() end
    return drawer
  end
end
