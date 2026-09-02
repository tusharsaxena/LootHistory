-- LibKa0s-Options-1.0 — the Blizzard settings-canvas shell: the panel factory, the page registry,
-- the lazy Defaults button, and the reset/refresh trio every Ka0s addon's options UI runs on.
--
-- Three files, one major. This one is the shell; OptionsWidgets.lua is the schema-row -> AceGUI
-- translation and the two-column flow engine; OptionsScroll.lua is the always-shown scrollbar
-- patch. They are one major because they are one feature: a host that ended up with a shell from
-- one vendored copy and a flow engine from another would build panels that lay out wrong, and
-- there is no version negotiation that would catch it.
--
-- The basenames are namespaced (OptionsWidgets, not Widgets) because tests/test_versioning.lua
-- searches one shared CHANGELOG.md for "<FileBasename> minor <N>". Two majors owning a file called
-- Widgets.lua would satisfy each other's assertion, silently.
--
-- What the host keeps: which pages exist, what each one draws, and where a value lives. All of
-- that arrives as descriptor callbacks, so the library never learns a path, a page name or a
-- database. Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework — AceGUI-3.0 is
-- resolved through LibStub at panel-build time and its absence is survivable, which is not the
-- same thing as a dependency.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Options-1.0", 14
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Which version of each FILE in this major is actually live, so version skew is discoverable at
-- runtime rather than by reading source. See docs/releasing.md.
lib.MODULES = lib.MODULES or {}
lib.MODULES.Options = MINOR

-- ── layout ─────────────────────────────────────────────────────────────────────────────────
--
-- One table for the whole module rather than a split between the shell's metrics and the flow
-- engine's spacing. The two halves are not independent: HEADER_HEIGHT decides where the body
-- starts and ROW_VSPACER decides how it fills, and a page whose header moved without its rows
-- following looks broken in exactly the way nobody files a bug about. OptionsWidgets.lua reads
-- this table rather than keeping its own copy.
--
-- PUBLISHED VS INTERNAL. `lib.LAYOUT` itself is never handed to a host — not as `O.LAYOUT = L`,
-- because one host's mutation of a shared table would retune every other host's panels, which is a
-- worse failure than the copying that publishing fixes. Individual scalars are published on the
-- instance instead, and a key is published on a DEMONSTRATED NEED: a host that has to align a
-- bespoke widget with the library's own header, divider or body has no other way to read the
-- number, and options-ui-§8's MUST NOT against host copies cannot be complied with for a constant
-- the library keeps to itself.
--
-- Every other key carries an `INTERNAL:` line saying why it is not published, and
-- tests/test_options.lua fails if a key is neither published nor annotated. That is the durable
-- half: publishing on repetition rather than on a demonstrated need is anti-pattern #55
-- (library-stack-§7) — under the additive-only rule a wrong shared abstraction is surface the
-- library keeps forever — and an annotation is what keeps "not yet" a visible decision rather than
-- a forgotten one. Each internal key is published the day a host demonstrates it needs it.

lib.LAYOUT = {
  -- Horizontal padding from the panel's edges to its header, divider and body. One value for both
  -- edges so the layout stays symmetric. PUBLISHED as O.PADDING_X: a host aligning its own widget
  -- with the header or the divider has to know this number, and one that could not read it
  -- restated it as its own constant.
  PADDING_X     = 16,
  -- Vertical inset of the title (and the Defaults button beside it) from the top of the panel.
  -- INTERNAL: HEADER_TOP — the header block is drawn entirely by buildHeader; no host in the
  -- collection reads or re-declares it.
  HEADER_TOP    = 20,
  -- Top of the panel to the divider under the title. In lockstep with HEADER_TOP so the
  -- title-to-divider and divider-to-body gaps survive the header block being moved.
  -- INTERNAL: HEADER_HEIGHT — same reason as HEADER_TOP, and it moves with it.
  HEADER_HEIGHT = 54,
  -- Width of the per-page "Defaults" button.
  -- INTERNAL: DEFAULTS_W — the button is created by the library and by nobody else.
  DEFAULTS_W    = 110,

  -- Inter-row spacing inside the two-column flow.
  -- INTERNAL: SECTION_TOP_SPACER — emitted by O.Section; a host draws sections through that
  -- function rather than measuring them.
  -- INTERNAL: SECTION_BOTTOM_SPACER — same, and it is pinned equal to LANDING_GAP_HEAD below.
  ROW_VSPACER           = 8,
  SECTION_TOP_SPACER    = 10,
  SECTION_BOTTOM_SPACER = 6,
  SECTION_HEADING_H     = 26,

  -- The landing page's block sizing, promoted from three hosts that each declared these four
  -- verbatim and agreed on every value. They lived host-side only because the BODY did; the body
  -- is O.BuildLandingPage now, so the constants follow it — which is exactly why none of the four
  -- is published: the function that consumes them is the library's.
  --
  -- LANDING_GAP_HEAD is the gap under a landing heading. O.Section already emits exactly that as
  -- SECTION_BOTTOM_SPACER, so BuildLandingPage does not draw a second one — the two values must
  -- stay equal, which tests/test_options.lua pins.
  --
  -- INTERNAL: LANDING_LOGO — consumed by O.BuildLandingPage, which every host now calls.
  -- INTERNAL: LANDING_GAP_LOGO — consumed by O.BuildLandingPage; no host draws that gap itself.
  -- INTERNAL: LANDING_GAP_DESC — consumed by O.BuildLandingPage; no host draws that gap itself.
  -- INTERNAL: LANDING_GAP_HEAD — same, and pinned equal to SECTION_BOTTOM_SPACER.
  LANDING_LOGO          = 300,
  LANDING_GAP_LOGO      = 8,
  LANDING_GAP_DESC      = 12,
  LANDING_GAP_HEAD      = 6,

  -- Relative width of each button in a cell-filling paired-button row (options-ui-§8). A flat
  -- 0.5/0.5 lets AceGUI's Flow layout push the right button's border into the ScrollFrame's clip
  -- rectangle, shaving it; the 0.492 inset clears the clip while staying visually a 50/50 split.
  BUTTON_PAIR_REL       = 0.492,

  -- The gap between the bottom of the pinned chrome band (options-ui-§13/§14) and the top of
  -- the scroll. Equal to the literal 8 EnsureScroll used before the band existed, so a page
  -- that reserves nothing anchors its scroll exactly where it always did. PUBLISHED as
  -- O.CHROME_GAP: a host drawing bespoke chrome of its own has to know where its band ends.
  CHROME_GAP    = 8,
  -- Height of one row of tabs. PUBLISHED as O.TAB_H: a host that measures its own strip -- to
  -- reserve the band before drawing into it -- has no other way to read the number.
  --
  -- Taller than the art it carries, on purpose. The bottom of a tab is a FOOT that overlaps the
  -- content panel's top edge, which is what makes the selected tab merge into the page instead of
  -- floating above it; the label is therefore anchored to the tab's bottom rather than centred.
  -- OPie's number, from the reference implementation named in OptionsWidgets.lua's art section.
  TAB_H         = 37,
  -- Floor and fallback for the page banner's height. PUBLISHED as O.BANNER_H, same reason as
  -- TAB_H. PageBanner measures the dropdown's own frame and uses that when it is a taller
  -- number than this; this is what a headless harness (GetHeight answers 0) and any real
  -- measurement below the floor fall back to. Roughly an AceGUI Dropdown WITH a label, whose
  -- label renders above the control and pushes the whole widget past a bare control's height.
  BANNER_H      = 44,
  -- INTERNAL: TAB_PAD_X — horizontal padding inside one tab, consumed by O.TabStrip when it
  -- sizes a button around its measured label; no host draws a tab itself. 20 a side is OPie's
  -- `GetStringWidth() + 40`, and it is the number that stops a label sitting on the atlas's end
  -- cap. It has been too small twice: at 12 the text sat on the cap outright, at 18 it cleared it
  -- but left the tabs looking cramped next to every other tab strip in the client.
  TAB_PAD_X     = 20,
  -- INTERNAL: TAB_GAP — horizontal gap between two tabs on one row, consumed by O.TabStrip and
  -- by O.__layoutTabs; a host that needed it would be laying out its own strip.
  TAB_GAP       = 4,
  -- INTERNAL: TAB_MIN_W — floor width of one tab, and the width every tab takes when the label
  -- cannot be measured (a headless harness, a font not yet loaded); never read by a host.
  TAB_MIN_W     = 60,

  -- The gap below the banner, the hairline rule under it, and the gap below THAT before the tab
  -- strip begins (options-ui-§14). Three numbers rather than one, because the rule wants to sit
  -- clear of the banner's own art on one side and the first tab's border on the other.
  -- INTERNAL: CHROME_DIVIDER_GAP_TOP — consumed by O.PageBanner alone, which draws the rule
  -- immediately under its own measured height; no host draws a banner divider itself.
  -- INTERNAL: CHROME_DIVIDER_H — same reason, and it is also the rule TEXTURE's height, not
  -- just a spacing number.
  -- INTERNAL: CHROME_DIVIDER_GAP_BOTTOM — same reason as CHROME_DIVIDER_GAP_TOP.
  CHROME_DIVIDER_GAP_TOP    = 6,
  CHROME_DIVIDER_H          = 1,
  CHROME_DIVIDER_GAP_BOTTOM = 6,
  -- The scroll's bottom inset within the body.
  -- INTERNAL: CONTENT_BOTTOM — anchorScroll is the only consumer; no host anchors its own scroll.
  CONTENT_BOTTOM = 8,

  -- The content box's own insets within the body (options-ui-§13), and they are deliberately
  -- SMALLER than the content column's. The box has to sit OUTSIDE everything it contains: the
  -- page's widgets start at CONTENT_LEFT, and AceGUI's always-shown scrollbar sits outboard of
  -- CONTENT_RIGHT, so a box drawn on the content column's own edges is a box the scrollbar is
  -- painted on top of and the left-hand labels butt against. That is what shipped at 12.11.3.
  --
  -- The tab strip stays on the content column, which puts the leftmost tab a few pixels inside
  -- the box's left edge -- OPie's arrangement, and the reason its tabs read as sitting ON the
  -- panel rather than as being the panel's top row.
  -- INTERNAL: PANEL_LEFT — drawContentPanel in OptionsWidgets.lua is the only consumer; no host
  -- draws its own content box.
  -- INTERNAL: PANEL_RIGHT — same reason as PANEL_LEFT.
  -- INTERNAL: PANEL_BOTTOM — same reason as PANEL_LEFT.
  PANEL_LEFT    = 4,
  PANEL_RIGHT   = 4,
  PANEL_BOTTOM  = 2,
}

local L = lib.LAYOUT

-- The chrome band's and the scroll's shared horizontal insets, so the banner and the tab strip
-- span exactly the content column beneath them rather than a wider guess restated at
-- CreatePanel's chrome anchor AND at anchorScroll. CONTENT_RIGHT is wider than PADDING_X because
-- anchorScroll's right inset leaves room for AceGUI's always-shown scrollbar (which AceGUI nudges
-- 20px right of the scrollframe when visible); CONTENT_LEFT is narrower than PADDING_X for the
-- same reason __scrollTopInset exists -- one seam, computed once here and read at both anchor
-- sites, so the two cannot drift the way they had.
-- INTERNAL: CONTENT_LEFT — no host draws its own chrome or scroll; both consumers (CreatePanel's
-- chrome anchor and anchorScroll) are in this file.
-- INTERNAL: CONTENT_RIGHT — same reason as CONTENT_LEFT.
L.CONTENT_LEFT  = L.PADDING_X - 4
L.CONTENT_RIGHT = L.PADDING_X + 12

-- ── strings ────────────────────────────────────────────────────────────────────────────────

lib.STRINGS = {
  DEFAULTS_LABEL = "Defaults",
  NO_ACEGUI      = "AceGUI-3.0 not available; settings panel unavailable.",
  -- Gray, because a refusal is not an error the user caused. The em dash is a byte escape: a
  -- literal would depend on the file's encoding surviving every editor between here and a client.
  COMBAT_REFUSED = "|cffaaaaaacannot open settings during combat \226\128\148 Blizzard's " ..
                   "category-switch is protected|r",
  BUTTON_FAILED  = "button onClick failed: %s",
  HEADER_FAILED  = "page header failed to build: %s",
  PAGE_FAILED    = "settings page '%s' failed to build: %s",
  RENDER_FAILED  = "settings page '%s' failed to render: %s",
  ROW_FAILED     = "settings row '%s' failed to render: %s",
  -- Every row on every page carries a `group` (options-ui-§13). A page whose rows do not cannot
  -- draw a strip, and that is an authoring defect (anti-patterns #69) rather than a shape the
  -- library absorbs -- but it is REPORTED and the page still renders, because a blank page under
  -- an empty strip is a worse failure than a strip-less one.
  NO_GROUPS      = "settings page '%s' has no grouped rows; rendering untabbed",
  -- A `string` row with neither `values` nor `dialogControl` reaches the dropdown maker and opens
  -- on nothing. The opt-in stays (see makeEditBox's note on why free text is not inferred); this
  -- line is what makes forgetting it visible the first time the page is opened, instead of
  -- shipping as a control that does nothing.
  EMPTY_DROPDOWN = "settings row '%s' is a string with no values and no dialogControl; it renders "
                   .. "as an empty dropdown",
  -- The only option a media dropdown can offer when the media library is absent or has nothing
  -- registered yet. A literal rather than a locale key: it is also the STORED value, so a
  -- translated one would be written into the host's SavedVariables.
  LSM_NONE       = "None",
  -- The sub-page breadcrumb separator. An inline atlas escape rather than a font glyph, so it
  -- renders identically regardless of the FontString's font or any locale fallback.
  BREADCRUMB_SEP = " |A:common-icon-forwardarrow:16:16|a ",
}

-- ── the instance ───────────────────────────────────────────────────────────────────────────

--- Build one host's options surface.
---
--- Descriptor (`d`):
---   parentTitle     string     brand shown on the main page and in every sub-page breadcrumb.
---   mainPanelName   string     frame name for the main canvas, so /framestack attributes it.
---   print(line)                where a user-facing line goes. Pass the host's tagged printer.
---   get(path)                  read a stored value.
---   set(path, value)           write one. Route it through the host's single write seam, so a
---                              panel change takes the same path a slash command does.
---   applyDefault(row)          reset one row. Same reasoning.
---   rowsForPage(pageKey, filter)  the rows of one page, in render order.
---   allRows()                  every row, for RestoreAllDefaults.
---   resetProfile()             optional, and the one a host on AceDB wants. Supply it and a global
---                              reset becomes what the house standard calls for (options-ui-§12):
---                              the session-only rows are swept row by row, then THIS is called to
---                              reset the active profile, then every panel refreshes. Pass
---                              `function() NS.db:ResetProfile() end` and stop restating the policy.
---                              With it supplied, the library skips every row that is not
---                              `sessionOnly` on its own — a profile reset covers them, and writing
---                              each one's default first would refresh the panel once per row for
---                              values about to be discarded whole.
---   skipRestoreAll(row)        optional. Return true to exclude a row from a global reset. With
---                              `resetProfile` supplied this is only needed for a row that is
---                              sessionOnly AND must still be left alone; the profiles-page veto
---                              the field was invented for is implied, because an AceDBOptions row
---                              is not sessionOnly. Without it, the host owns the whole policy.
---   afterRestoreAll()          optional. Runs after the rows are reset and after `resetProfile`,
---                              and BEFORE the panels are refreshed, for state that is in neither
---                              the schema nor the profile. Ordering matters: a refresh first would
---                              paint the pre-hook values. A dragged frame's position is NOT an
---                              example — a position lives in the profile and comes back with it.
---   scheduleTimer(fn, delay)   optional. Backs the color picker's 50 ms drag throttle. A
---                              descriptor field rather than an AceTimer embed, because embedding
---                              would be this library's second dependency-budget breach.
---   getLSM()                   optional. Returns LibSharedMedia-3.0, for LSMValues.
---   validate()                 optional. Runs once, before the page builders.
---   onAceGUI(AceGUI)           optional. Handed the resolved AceGUI so the host can stash it
---                              (library-stack-§4) for its own page files.
---   buildMain(ctx)             optional. Draws the main page's body on its first OnShow. A host
---                              that wants the shared landing page writes
---                              `buildMain = function(ctx) O.BuildLandingPage(ctx, spec) end`
---                              itself — the shell reads no other field and installs no renderer of
---                              its own, so what draws the main page is answerable from the host's
---                              own source.
---   colorDecode(stored)        optional. -> r, g, b, a. Defaults to the {r=,g=,b=,a=} shape.
---   colorEncode(r, g, b, a)    optional. -> stored. Defaults to the same.
---   debug(tag, fmt, ...)       optional. Developer log line.
function lib:New(d)
  -- The one field validated here, deliberately and alone. The rest of the descriptor surfaces a
  -- page-build away with a stack that names the missing callback, whereas a nil mainPanelName just
  -- yields CreateFrame("Frame", nil): an anonymous canvas that /framestack cannot attribute to the
  -- host and that two addons can collide on, with no error and nothing visible in game. Silence is
  -- what makes it worth a raise; the README documents the rest of the gap as intentional.
  d = type(d) == "table" and d or {}
  if type(d.mainPanelName) ~= "string" then
    error(MAJOR .. ":New requires descriptor.mainPanelName (a string)", 2)
  end

  local O = {}
  -- Defaulted to the chat frame, like Core, DebugLog and Slash, because the two lines that reach
  -- this sink — the combat refusal (options-ui-§2) and the missing-AceGUI notice — are the whole
  -- explanation for a panel that will not open, and discarding them leaves nothing to grep for.
  -- The library cannot supply the host's cyan tag (that is the host's PREFIX, not ours), so the
  -- descriptor's `print` stays the intended path: this fallback exists to make the line VISIBLE,
  -- not to make it tagged.
  local print = type(d.print) == "function" and d.print or function(line)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) end
  end

  -- Every ctx CreatePanel hands out. Per INSTANCE, never per library: a lib-level registry would
  -- have one addon's Defaults button run another addon's refreshers.
  local renderedPanels = {}

  local pendingPages = {}      -- file-load-time queue; page files register into it
  local builtPages  = {}       -- the ones that actually built, in build order
  local built       = false    -- has CreateOptionsPanel drained the queue yet?
  local mainCategory           -- Settings.RegisterCanvasLayoutCategory return
  local mainCategoryID         -- numeric ID for OpenToCategory

  -- Resolved once and re-read at CreateOptionsPanel time. Held on the instance rather than in an
  -- upvalue because the widget makers and the host's own page files both need it, and a second
  -- LibStub call per builder is exactly what library-stack-§4 exists to stop.
  O.AceGUI = LibStub and LibStub("AceGUI-3.0", true) or nil

  -- Individual scalars, deliberately not `O.LAYOUT = L`: the lib-level table is shared by every
  -- instance, so handing it out lets one host's mutation retune every other host's panels. Which
  -- keys belong here and why is at the lib.LAYOUT declaration above.
  O.PADDING_X         = L.PADDING_X
  O.ROW_VSPACER       = L.ROW_VSPACER
  O.SECTION_HEADING_H = L.SECTION_HEADING_H
  O.BUTTON_PAIR_REL   = L.BUTTON_PAIR_REL
  O.CHROME_GAP        = L.CHROME_GAP
  O.TAB_H             = L.TAB_H
  O.BANNER_H          = L.BANNER_H

  -- ── panel factory ────────────────────────────────────────────────────────────────────────

  local function buildHeader(panel, title, opts)
    -- Sub-pages render with a "<Brand> > <Page>" breadcrumb. The main page opts out via
    -- opts.isMain, or it would read "<Brand> > <Brand>". The Blizzard left-tree label is driven by
    -- panel.name below and stays unprefixed, so the tree indents under the parent without visual
    -- repetition.
    local displayTitle = title
    if not opts.isMain then
      displayTitle = (d.parentTitle or "") .. lib.STRINGS.BREADCRUMB_SEP .. title
    end

    local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleFS:SetPoint("TOPLEFT", panel, "TOPLEFT", L.PADDING_X, -L.HEADER_TOP)
    titleFS:SetText(displayTitle)
    -- Recorded as a plain field as well, and not only for the harness: a headless mock's
    -- CreateFontString cannot be read back, so without this the rendered breadcrumb is
    -- unassertable and a regression in it ships green. Same seam DebugLog's title uses.
    panel.titleText = displayTitle

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOPLEFT",  panel, "TOPLEFT",   L.PADDING_X, -L.HEADER_HEIGHT)
    divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -L.PADDING_X, -L.HEADER_HEIGHT)
    -- Tint to the title's own font color rather than a hardcoded gold, so a future theme retune
    -- carries the divider with it.
    divider:SetVertexColor(titleFS:GetTextColor())

    -- The Defaults button is DECLARED here and never created; EnsureDefaultsButton builds it on
    -- the panel's first OnShow. Read that function's comment before "simplifying" this.
    panel.wantsDefaultsButton = opts.defaultsButton and true or false
    panel.defaultsTooltip     = opts.defaultsTooltip

    return titleFS, divider
  end

  --- A canvas Frame compatible with RegisterCanvasLayoutSubcategory, with the unified header
  --- stamped on top. Returns the `ctx` the caller threads through every render call.
  function O.CreatePanel(name, title, opts)
    opts = opts or {}

    local panel = CreateFrame("Frame", name)
    panel.name = title
    panel:Hide()

    -- The Blizzard canvas contract. The Settings window calls all three on a frame handed to
    -- RegisterCanvasLayout(Sub)category: OnCommit when the user applies, OnDefault from the
    -- window's own FOOTER defaults control, OnRefresh on re-show. This library declared none of
    -- them until minor 5, so every host on it shipped a canvas whose footer Defaults control did
    -- nothing — and three did, without noticing, because the header Defaults button this library
    -- DOES build kept working and looks equivalent to the user.
    --
    -- OnCommit and OnRefresh are inert BY DESIGN rather than by omission. A host's writes land
    -- immediately through its own single write seam (options-ui-§1), so there is no staged state
    -- to apply; and SetRenderer already owns re-show, so a second refresh path would race the
    -- renderer it duplicates.
    panel.OnCommit  = function() end
    panel.OnRefresh = function() end

    -- A FORWARDER, not `panel.OnDefault = panel.defaultsOnClick`, and the ordering is the whole
    -- reason: every host parks its click handler on the panel AFTER this function returns, because
    -- the Defaults button does not exist yet (EnsureDefaultsButton builds it on first OnShow). An
    -- assignment here would capture nil forever while looking perfectly correct.
    --
    -- Resolving through the panel at call time also keeps the footer control and the header button
    -- ONE implementation — which is what matters — rather than two that can drift. A page with no
    -- defaults action (a landing page) gets a callable no-op, which is the point: the footer
    -- control is not per-page and can be clicked while such a page is open.
    panel.OnDefault = function()
      if panel.defaultsOnClick then panel.defaultsOnClick() end
    end

    local titleFS, divider = buildHeader(panel, title, opts)
    panel.title   = titleFS
    panel.divider = divider

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT",     panel, "TOPLEFT",     0, -(L.HEADER_HEIGHT + 8))
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    panel.body = body

    -- The chrome slot (options-ui-§13, §14): pinned page furniture between the header and the
    -- scroll. A frame rather than a bare number because a banner and a strip need something to
    -- parent to that a page-wide release can empty; the NUMBER is what moves the scroll, and it
    -- starts at zero so a page that reserves nothing is byte-identical to one built before the
    -- slot existed.
    local chrome = CreateFrame("Frame", nil, body)
    chrome:SetPoint("TOPLEFT",  body, "TOPLEFT",   L.CONTENT_LEFT, 0)
    chrome:SetPoint("TOPRIGHT", body, "TOPRIGHT", -L.CONTENT_RIGHT, 0)
    panel.chrome = chrome

    local ctx = {
      panel        = panel,
      body         = body,
      scroll       = nil,          -- lazy AceGUI ScrollFrame
      refreshers   = {},
      lastGroup    = nil,
      lastSubgroup = nil,
      pageKey      = opts.pageKey,
      chrome       = chrome,
      chromeHeight = 0,
    }
    renderedPanels[#renderedPanels + 1] = ctx
    return ctx
  end

  -- WHY the Defaults button is lazy, and why it must stay that way (options-ui-§5,
  -- anti-patterns #42):
  --
  -- AceGUI-3.0 is a SHARED library — whichever copy loads first serves every addon in the session.
  -- UI-skinning addons (ElvUI, AddOnSkins, Masque-likes) restyle AceGUI widgets by hooking
  -- `AceGUI:RegisterAsWidget`. A widget created BEFORE that hook is installed never passes through
  -- it, so it keeps Blizzard's stock UI-Panel-Button-Up art — the red stone button — for the rest
  -- of the session, while every widget created afterwards comes out skinned.
  --
  -- Page builders run at enable time, i.e. still inside the load window. Creating the button there
  -- is a straight race against every other addon's load order: a host wins it only because it
  -- happens to sort after the skinner today. Rename the folder, or add a skin, and the identical
  -- code renders red.
  --
  -- First OnShow is after every addon has loaded, so the race is gone. It is also the same
  -- deferral the panel BODY uses, for the separate reason that ctx.body has zero width at enable
  -- time — two unrelated causes with the same fix. Do not collapse the reasoning.
  function O.EnsureDefaultsButton(panel)
    if not panel then return end
    if panel.defaultsBtn or not panel.wantsDefaultsButton then return end

    local AceGUI = O.AceGUI
    if not AceGUI then return end

    local btn = AceGUI:Create("Button")
    if not (btn and btn.frame) then return end
    btn:SetText(lib.STRINGS.DEFAULTS_LABEL)
    btn:SetWidth(L.DEFAULTS_W)
    btn.frame:SetParent(panel)
    btn.frame:ClearAllPoints()
    btn.frame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -L.PADDING_X, -L.HEADER_TOP)
    btn.frame:Show()
    -- Guarded like the scroll patch below, and for the same reason: AttachTooltip arrives from
    -- OptionsWidgets.lua, and a copy vendored without that file must degrade (a button with no
    -- tooltip) rather than raise from inside the library's own shell on the first panel OnShow.
    if O.AttachTooltip then
      O.AttachTooltip(btn, lib.STRINGS.DEFAULTS_LABEL, panel.defaultsTooltip)
    end

    panel.defaultsBtn = btn

    -- The page builder parks its click handler on the panel (the button did not exist when the
    -- builder ran), so it is wired up here.
    if panel.defaultsOnClick then
      btn:SetCallback("OnClick", panel.defaultsOnClick)
    end
  end

  --- Where the scroll's top edge sits: the fixed gap plus whatever the page reserved.
  ---
  --- A named seam rather than the sum written out at both call sites, because the two sites are
  --- EnsureScroll (first render) and SetChromeHeight (every render after a strip wrapped), and
  --- a page whose two answers disagreed would move its own first row on the second render.
  function O.__scrollTopInset(ctx)
    return L.CHROME_GAP + ((ctx and ctx.chromeHeight) or 0)
  end

  --- Anchor a page's scroll under whatever chrome the page reserved.
  ---
  --- BOTH anchors in one place, not just the top one. EnsureScroll and SetChromeHeight each need
  --- the full pair -- the second re-anchors a live scroll -- and a bottom inset restated at two
  --- sites is the same drift __scrollTopInset exists to prevent, one edge over.
  ---
  --- The horizontal insets are L.CONTENT_LEFT / L.CONTENT_RIGHT -- the SAME two numbers
  --- CreatePanel's chrome anchor uses -- so the chrome band and the scroll beneath it can never
  --- drift apart the way they once did (the chrome ran 12px wider than the content on the
  --- right).
  local function anchorScroll(ctx)
    local f = ctx.scroll and ctx.scroll.frame
    if not f then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT",     ctx.body, "TOPLEFT",     L.CONTENT_LEFT, -O.__scrollTopInset(ctx))
    f:SetPoint("BOTTOMRIGHT", ctx.body, "BOTTOMRIGHT", -L.CONTENT_RIGHT, L.CONTENT_BOTTOM)
  end

  --- Reserve `height` pixels of pinned furniture above the scroll, and move a live scroll to
  --- match. Idempotent: reserving the same height twice reserves it once.
  function O.SetChromeHeight(ctx, height)
    if not ctx then return end
    ctx.chromeHeight = tonumber(height) or 0
    if ctx.chrome and ctx.chrome.SetHeight then
      -- Zero is not a height a frame can hold, and a slot with nothing in it has nothing to
      -- show anyway, so the frame is hidden rather than sized to nothing.
      if ctx.chromeHeight > 0 then
        ctx.chrome:SetHeight(ctx.chromeHeight)
        ctx.chrome:Show()
      else
        ctx.chrome:Hide()
      end
    end
    anchorScroll(ctx)
  end

  --- Lazy AceGUI ScrollFrame parented to ctx.body, patched for an always-visible scrollbar.
  function O.EnsureScroll(ctx)
    if ctx.scroll then return ctx.scroll end
    local AceGUI = O.AceGUI
    if not AceGUI then return nil end

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll.frame:SetParent(ctx.body)
    ctx.scroll = scroll
    -- The right-edge inset of L.CONTENT_RIGHT leaves room for the scrollbar (which AceGUI nudges
    -- 20px right of the scrollframe when visible) without it sitting flush against the panel
    -- border.
    anchorScroll(ctx)
    scroll.frame:Show()

    -- AceGUI normally has a parent AceGUI container set a ScrollFrame's size during DoLayout; this
    -- one is parented to a Blizzard frame instead, so OnWidthSet/OnHeightSet never fire. Forward
    -- the real size in and re-run DoLayout + FixScroll, so the scrollbar tracks a body resize.
    scroll.frame:SetScript("OnSizeChanged", function(_, w, h)
      if scroll.OnWidthSet  then scroll:OnWidthSet(w)  end
      if scroll.OnHeightSet then scroll:OnHeightSet(h) end
      if scroll.DoLayout    then scroll:DoLayout()     end
      if scroll.FixScroll   then scroll:FixScroll()    end
    end)

    if O.PatchAlwaysShowScrollbar then O.PatchAlwaysShowScrollbar(scroll) end

    return scroll
  end

  --- Release every AceGUI child out of ctx.scroll and reset the section-heading tracker, so the
  --- next Section call starts a fresh group instead of treating the first re-rendered row as a
  --- continuation of whatever was last drawn. The SAME ScrollFrame is reused — AceGUI's
  --- ReleaseChildren tears down children, not the container.
  function O.ClearScroll(ctx)
    -- BEFORE ReleaseChildren, not after: a secondary tab strip's buttons are parented to a frame
    -- the host added as an AceGUI child, and ReleaseChildren returns that frame to the pool. Drain
    -- the ledger while those buttons still have a parent to be unparented FROM, or the next page to
    -- take that pooled frame inherits a stack of live buttons on top of its own content.
    -- Guarded because __AttachWidgets runs after this file and a ctx may be built before it.
    if O.__releaseSubTabs then O.__releaseSubTabs(ctx) end
    if ctx.scroll and ctx.scroll.ReleaseChildren then
      ctx.scroll:ReleaseChildren()
    end
    ctx.lastGroup = nil
    -- BOTH trackers, because they are one family (options-ui-§7). startGroup clears the subgroup
    -- whenever the group changes, which covers every page whose rows carry a `group` -- but a page
    -- that uses `subgroup` alone has no group boundary to ride on, and its first subsection heading
    -- would be swallowed on every render after the first.
    ctx.lastSubgroup = nil
    -- Every RenderField call appends a refresher closure capturing widgets just released above.
    -- Without this reset a released widget's refresher survives forever, so every write and every
    -- profile change pcalls an ever-growing pile of dead closures. REASSIGNED, not wiped in place:
    -- renderedPanels holds this ctx table, not a separate reference to ctx.refreshers, so a fresh
    -- table is observed by RefreshAllPanels immediately and nothing else can still be holding the
    -- old one.
    ctx.refreshers = {}
  end

  -- ── reset / refresh ──────────────────────────────────────────────────────────────────────

  --- Reset every row on `pageKey` to its default. The per-page Defaults button. Deliberately
  --- refreshes only the ctx it was given: a page-scoped button that swept every open panel would
  --- re-read values the user never asked about.
  function O.RestoreDefaults(pageKey, ctx)
    -- The page filter (ctx.unit) is omitted ON PURPOSE, and this is the asymmetry with
    -- O.RenderSchema, which passes it. A Defaults button resets the whole PAGE — every filter
    -- value — while rendering shows one filter value at a time. Pass ctx.unit through here and a
    -- host's page reset silently narrows to the unit that happens to be on screen: AbsorbTracker
    -- pins the current behavior across all three units in its tests/test_helpers.lua, and it is
    -- where /at reset <page> went when the CLI form was removed. Pinned here too.
    for _, row in ipairs(d.rowsForPage(pageKey) or {}) do
      d.applyDefault(row)
    end
    if ctx and ctx.refreshers then
      for _, fn in ipairs(ctx.refreshers) do pcall(fn) end
    end
  end

  --- Reset every schema row the host does not veto, run the host's own after-hook, then refresh
  --- every open panel. The single "reset all" implementation: a host's popup and its slash verb
  --- both call this, so the two can never diverge (in one consumer they historically did).
  ---
  --- WITH `resetProfile` SUPPLIED THIS IS A PROFILE RESET, which is what the house standard makes
  --- it (options-ui-§12) and what every AceDB host wants. Two things follow, and both used to be
  --- restated in every consumer's own descriptor:
  ---
  ---   * the row walk narrows to the `sessionOnly` rows. They are the only settings a profile reset
  ---     cannot reach — their storage is their own `set()` rather than the db — and writing every
  ---     OTHER row's default first would refresh the panel once per row for values that are about
  ---     to be discarded whole. It also would not help: a row-by-row sweep cannot reach a stored
  ---     ARRAY (a column list, a spell list, a category list) at all, because an array is
  ---     addressable as a whole and its members deliberately are not.
  ---   * `skipRestoreAll` stops being load-bearing for the profiles page. An AceDBOptions row is
  ---     not `sessionOnly`, so it is already outside the narrowed walk. A host may still supply the
  ---     veto and it is still honored — belt and braces, and it is what a host with no
  ---     `resetProfile` relies on entirely.
  ---
  --- Without `resetProfile` the behavior is exactly what it always was: every unvetoed row, then
  --- the hook, then the refresh. A host that owns its own reset keeps owning it.
  function O.RestoreAllDefaults()
    local veto        = d.skipRestoreAll
    local resetProfile = d.resetProfile
    local profileReset = type(resetProfile) == "function"

    for _, row in ipairs(d.allRows() or {}) do
      local skip = false
      -- The narrowing comes FIRST, so a host that supplies both does not have to make its veto
      -- agree with a rule the library is already applying.
      if profileReset and not row.sessionOnly then skip = true end
      if not skip and type(veto) == "function" then skip = veto(row) and true or false end
      if not skip then d.applyDefault(row) end
    end

    -- THE RESET ITSELF, and before the after-hook: the hook is for state in neither the schema nor
    -- the profile, so it must see the profile already reset. AceDB empties the ACTIVE profile in
    -- place, the defaults merge back, and the host's own profile-changed handler runs off
    -- `OnProfileReset` — migrations, re-seeding, and the host's config-changed message, off which
    -- its windows rebuild. The library neither knows nor needs to know any of that.
    if profileReset then resetProfile() end

    -- Before the refresh, not after: the hook exists to clear state neither the schema nor the
    -- profile owns, and a refresh that ran first would paint the panel from the pre-hook values.
    if type(d.afterRestoreAll) == "function" then d.afterRestoreAll() end
    -- STRUCTURAL: a global reset can change which rows a page draws (a category re-enabled, a
    -- list emptied), so re-running the renderer is the honest refresh here.
    O.RefreshAllPanels()
  end

  --- Re-run every registered panel's refreshers. Called after a slash write so an open panel
  --- reflects it immediately, and after a profile change so widgets re-read the new profile.
  ---
  --- TWO TIERS, and the distinction is the whole reason SetRenderer exists:
  ---
  ---   RefreshAllPanels  STRUCTURAL. Re-runs the page's renderer, so rows that appeared or
  ---                     disappeared are drawn. What a mutation that changes the SHAPE of a page
  ---                     needs (an item added to a list, a category enabled).
  ---   RefreshScalars    IN PLACE. Runs the refreshers only, so widgets re-read their values
  ---                     without a rebuild. What a plain value write needs, and what every
  ---                     widget maker's own `set()` calls.
  ---
  --- A page that is not on screen is not refreshed either way — it is flagged dirty and re-renders
  --- on its next OnShow. Rebuilding fifteen hidden pages on every keystroke is the cost that
  --- motivated the split.
  ---
  --- A ctx that never went through SetRenderer has no renderer to re-run, so BOTH tiers fall back
  --- to running its refreshers ungated. That is the migration seam: a host adopting the registry
  --- one page at a time keeps working, and so does one that never adopts it at all.

  local function isShown(ctx)
    local panel = ctx.panel
    if not (panel and panel.IsShown) then return true end
    return panel:IsShown() and true or false
  end

  local function runRefreshers(ctx)
    for _, fn in ipairs(ctx.refreshers) do pcall(fn) end
  end

  --- Re-render one ctx through its declared renderer, reporting rather than propagating a failure:
  --- a raising renderer inside AceGUI's own dispatch would take the click handling of every widget
  --- on the frame down with it.
  local function renderCtx(ctx)
    if type(ctx._renderFn) ~= "function" then return end
    ctx._rendered = true
    ctx._dirty    = false
    local ok, err = pcall(ctx._renderFn, ctx)
    if not ok then
      print(lib.STRINGS.RENDER_FAILED:format(tostring(ctx.pageKey or "?"), tostring(err)))
    end
  end

  --- Declare how a page draws itself. The library owns WHEN — first show, and again after a
  --- refresh marked it dirty while it was hidden — because those are the two moments only the
  --- registry can see. It also builds the Defaults button here rather than at registration time,
  --- for the AceGUI skinning reason above, and refuses to render during combat.
  function O.SetRenderer(ctx, fn)
    ctx._renderFn = fn
    ctx.panel:SetScript("OnShow", function()
      O.EnsureDefaultsButton(ctx.panel)
      -- The Blizzard AddOns sidebar reaches a panel without going through OpenOptionsPanel, so
      -- its combat guard is bypassed on exactly the path a user is most likely to take mid-fight.
      -- Closing the window is what makes the refusal legible; a silent no-render reads as a bug.
      if InCombatLockdown and InCombatLockdown() then
        if SettingsPanel and SettingsPanel.Close then
          SettingsPanel:Close()
        elseif HideUIPanel and SettingsPanel then
          HideUIPanel(SettingsPanel)
        end
        print(lib.STRINGS.COMBAT_REFUSED)
        return
      end
      if ctx._rendered and not ctx._dirty then return end
      renderCtx(ctx)
    end)
  end

  local function refreshCtx(ctx, structural)
    -- No renderer declared: the legacy shape, refreshed ungated exactly as it always was.
    if type(ctx._renderFn) ~= "function" then return runRefreshers(ctx) end
    if not isShown(ctx) then
      ctx._dirty = true
      return
    end
    if structural then renderCtx(ctx) else runRefreshers(ctx) end
  end

  function O.RefreshAllPanels()
    for _, ctx in ipairs(renderedPanels) do refreshCtx(ctx, true) end
  end

  function O.RefreshScalars()
    for _, ctx in ipairs(renderedPanels) do refreshCtx(ctx, false) end
  end

  --- Refresh ONE ctx — the per-page half of the two sweeps above.
  ---
  --- PUBLISHED ON A DEMONSTRATED NEED (see the PUBLISHED VS INTERNAL note at the top of this file).
  --- A host whose page repaints off its OWN message bus rather than off a library widget's `set()`
  --- has a page the library never hears about: the two sweeps are wrong for it (they repaint every
  --- registered page to service one), and the only alternative left was to hand-roll the
  --- shown/hidden branch against `ctx._dirty` — a private field, under a name the host has to guess.
  --- PanelMaster guessed `ctx.dirty`, so its Panels page marked a flag nothing read and never
  --- re-rendered after a profile switch. That is the failure this exists to make unavailable: the
  --- dirty flag is the library's, the timing decision is the library's, and a host that needs to say
  --- "this page's contents changed" now has a way to say exactly that.
  ---
  --- `structural` true means the page's shape changed (a row appeared or vanished, a list's contents
  --- differ) and it re-renders; false means only widget VALUES are stale and the refreshers run in
  --- place. Same distinction, and the same code, as RefreshAllPanels vs RefreshScalars.
  ---
  --- A hidden page is marked dirty and repaints on its next OnShow — the caller does not have to
  --- know whether it is on screen, which is the whole point.
  function O.RefreshPanel(ctx, structural)
    if type(ctx) ~= "table" then return end
    refreshCtx(ctx, structural)
  end

  -- ── LibSharedMedia ───────────────────────────────────────────────────────────────────────

  --- A DEFERRED closure that pulls the live LSM hash at dropdown-render time.
  ---
  --- Deferred and not a snapshot, and this is load-bearing: every LSM-backed row evaluates this
  --- inside a schema-row literal at FILE LOAD, long before the addons that register media have
  --- run. A table here would freeze the list at whatever happened to be registered first.
  function O.LSMValues(mediaType)
    return function()
      local LSM = type(d.getLSM) == "function" and d.getLSM() or nil
      local list = (LSM and LSM.HashTable) and LSM:HashTable(mediaType) or {}
      local out, any = {}, false
      for k in pairs(list) do out[k] = k; any = true end
      -- Never hand back an EMPTY list. A dropdown with no options cannot be opened, and the CLI's
      -- allowed-values check refuses every value including the one already stored — so a row whose
      -- media library has not loaded yet becomes unusable rather than merely unpopulated.
      if not any then out[lib.STRINGS.LSM_NONE] = lib.STRINGS.LSM_NONE end
      return out
    end
  end

  -- ── the page registry ────────────────────────────────────────────────────────────────────

  --- Register a sub-page builder.
  --- @param key      unique short key ("general", "bar", ...)
  --- @param name     display name in Blizzard Settings
  --- @param builder  function(mainCategory) -> subcategory | nil. Called once at
  ---                 CreateOptionsPanel time, after the db is ready. nil means the page opted out
  ---                 (an optional dependency the host did not find).
  --- Build one page, reporting rather than propagating. The key is in the message because a
  --- builder's own stack rarely names the page a user would recognize.
  local function buildPage(page)
    local ok, err = pcall(page.builder, mainCategory)
    if ok then
      builtPages[#builtPages + 1] = page
      return true
    end
    print(lib.STRINGS.PAGE_FAILED:format(tostring(page.key or "?"), tostring(err)))
    return false
  end

  function O.RegisterOptionsPage(key, name, builder)
    local page = { key = key, name = name, builder = builder }
    -- A page registered AFTER the build is built immediately rather than queued behind a drain
    -- that has already happened — otherwise it silently never appears.
    if built and mainCategory then return buildPage(page) end
    pendingPages[#pendingPages + 1] = page
  end

  --- Every page that built successfully, for a host's own diagnostics and for the suite.
  function O.__pages() return builtPages end

  local function registerMain()
    if not (Settings and Settings.RegisterCanvasLayoutCategory
            and Settings.RegisterAddOnCategory) then
      return
    end

    local mainCtx = O.CreatePanel(d.mainPanelName, d.parentTitle or "", { isMain = true })

    -- Deferred to first OnShow through the same seam every sub-page uses: AceGUI's ScrollFrame
    -- lays children out against the parent's CURRENT width, which is zero at enable time. Routing
    -- it through SetRenderer rather than a private flag also gives the main page the combat guard
    -- and the dirty-re-render, which it had neither of.
    --
    -- d.buildMain is the ONLY main-page seam. O.BuildLandingPage is a renderer a host may call from
    -- its own buildMain; the shell does not sniff the descriptor for a spec and wire one up on the
    -- host's behalf. A shell that installs a renderer the host never asked for makes "what draws my
    -- main page?" unanswerable from the host's own source, and it is a change to what lib:New DOES
    -- rather than an addition to what it offers.
    if type(d.buildMain) == "function" then
      O.SetRenderer(mainCtx, d.buildMain)
    end

    mainCategory   = Settings.RegisterCanvasLayoutCategory(mainCtx.panel, d.parentTitle)
    Settings.RegisterAddOnCategory(mainCategory)
    mainCategoryID = mainCategory:GetID()
  end

  --- Build the whole options surface: resolve AceGUI, validate, register the main canvas, then run
  --- every page builder.
  function O.CreateOptionsPanel()
    -- Idempotent: a second call is a no-op. The function is public and cheap to reach twice (a
    -- login plus a profile change), and re-running it would register a SECOND Blizzard category
    -- for the same addon and append a second ctx per page to renderedPanels, permanently doubling
    -- the RefreshAllPanels fan-out. The guard is on RE-registration only; the lazy body render at
    -- first OnShow is untouched.
    if mainCategory then return end

    -- Re-resolved rather than trusting the handle taken at New time. A host builds its panel at
    -- PLAYER_LOGIN, by which point an AceGUI that was absent at load may be present (and vice
    -- versa on a broken install), and this is the one place that can report it.
    O.AceGUI = LibStub and LibStub("AceGUI-3.0", true) or nil
    if not O.AceGUI then
      print(lib.STRINGS.NO_ACEGUI)
      return
    end
    if type(d.onAceGUI) == "function" then d.onAceGUI(O.AceGUI) end

    if type(d.validate) == "function" then d.validate() end

    registerMain()
    if not mainCategory then return end

    -- Each builder registers its own Blizzard subcategory as a side effect, and each is pcall'd
    -- SEPARATELY. Unguarded, one raising builder killed every page after it in the list — and the
    -- user sees a half-registered options tree with no error naming which page did it.
    for _, page in ipairs(pendingPages) do
      buildPage(page)
    end
    -- Drained, so a page registered before the build cannot be built twice. REASSIGNED rather than
    -- wiped in place: nothing outside this closure holds the table.
    pendingPages = {}
    built = true
  end

  -- Expand the parent category in the Blizzard left tree so every sub-page is visible. Wrapped in
  -- pcall: SettingsPanel internals are private API and could shift between patches.
  local function expandMainCategory()
    if not (mainCategory and SettingsPanel) then return end
    pcall(function()
      local list = SettingsPanel.GetCategoryList
        and SettingsPanel:GetCategoryList()
        or SettingsPanel.CategoryList
      if not (list and list.GetCategoryEntry) then return end
      local entry = list:GetCategoryEntry(mainCategory)
      if entry and entry.SetExpanded then
        entry:SetExpanded(true)
      end
    end)
  end

  --- Open the host's settings category.
  ---
  --- REFUSES under combat, and does not defer-and-replay. Blizzard's category switch is protected,
  --- so calling it under lockdown taints the panel for the rest of the session (options-ui-§2).
  --- Replaying on PLAYER_REGEN_ENABLED is the other wrong answer: a panel that opens itself the
  --- instant combat drops steals focus during post-pull recovery. The user re-runs the command.
  ---
  --- The gate lives HERE rather than in a host's slash dispatcher, so every caller is refused —
  --- the config verb, a /run script, a future internal caller.
  function O.OpenOptionsPanel()
    if InCombatLockdown and InCombatLockdown() then
      if type(d.debug) == "function" then d.debug("Cfg", "open refused (in combat)") end
      print(lib.STRINGS.COMBAT_REFUSED)
      return
    end
    if not (Settings and Settings.OpenToCategory) then return end
    if not mainCategoryID then return end
    if type(d.debug) == "function" then d.debug("Cfg", "opened") end
    Settings.OpenToCategory(mainCategoryID)
    expandMainCategory()
  end

  -- ── test seams ───────────────────────────────────────────────────────────────────────────
  --
  -- Following Perf's P.__buckets() idiom, and for the same reason it exists there: a host suite
  -- otherwise has no handle on a live ctx, because the registry is private. AbsorbTracker's mock
  -- records that a real bug shipped precisely because one page's ctx was unreachable and therefore
  -- never asserted on.

  function O.__panels() return renderedPanels end

  function O.__panelFor(pageKey)
    for _, ctx in ipairs(renderedPanels) do
      if ctx.pageKey == pageKey then return ctx end
    end
  end

  -- The widget makers, the flow engine and the scrollbar patch attach here, so every host gets
  -- them on the same instance the shell lives on. Both are guarded: a file that failed to load
  -- leaves its half absent rather than erroring at :New, which is why the shell's own members
  -- reach for O.AttachTooltip and O.PatchAlwaysShowScrollbar at CALL time and never at load time.
  if lib.__AttachWidgets then lib.__AttachWidgets(O, d) end
  if lib.__AttachCompose then lib.__AttachCompose(O)    end
  if lib.__AttachScroll  then lib.__AttachScroll(O, d)  end

  return O
end
