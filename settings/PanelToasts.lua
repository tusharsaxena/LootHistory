local _, NS = ...
NS.ToastsPage = NS.ToastsPage or {}
local TP = NS.ToastsPage
local C = NS.Constants
local O = NS.Options
-- Load-time upvalue: settings/Panel.lua loads above this file and publishes the set picker.
local makeMultiCheck = NS.Panel._makeMultiCheck

-- The Toasts page (#38, toast spec docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §9.1;
-- D23, options-ui-§13/§14). The BANNER picks the feed every tab edits, and is the page's only picker:
-- the mockup's feed tabs became the banner, and the strip holds the sections (General, Content,
-- Style, Motion, Behavior). The pick is session state, never stored; each render hands it to the
-- rows filter as the page ctx's `unit` (settings/OptionsSetup.lua rowsForPage), so every control on
-- screen is bound to that feed's own path. Picking a feed keeps the tab.
--
-- THE ACTS sit on the General tab (options-ui-§14's escape): Test, Unlock/Lock and Reset feed.
-- Reset style to skin closes the Style tab. The Hide sources picker is host-drawn under the Content
-- tab's Details subsection, as General's Record data from is. The page Defaults resets all three feeds and the
-- alert row; the addon's global reset resets them as part of the profile.

local L = NS.L
local selected = "main"   -- the banner's pick: session state

--- The feed the page edits now.
function TP.Selected() return selected end

local function redraw()
  if TP.ctx then O.RefreshPanel(TP.ctx, true) end
end

--- Pick feed `fid` in the banner (an unknown key is refused); the tab is kept.
function TP.Select(fid)
  if not C.TOAST_FEED_LABEL[fid] then return false end
  selected = fid
  redraw()
  return true
end

local function prefix(fid) return "settings.toasts.feeds." .. fid .. "." end

--- The banner's *Add feed*: the first feed that is off is turned on and selected. With none left it
--- says so and changes nothing.
function TP.AddFeed()
  for _, fid in ipairs(C.TOAST_FEEDS) do
    if NS.Schema:Get(prefix(fid) .. "enabled") ~= true then
      NS.Schema:Set(prefix(fid) .. "enabled", true)
      return TP.Select(fid)
    end
  end
  NS.Print(L["All three feeds are on."])
  return false
end

--- Every row of feed `fid` back to its default, as one bulk reset (debug-logging-§10).
function TP.ResetFeed(fid)
  local S = NS.Schema
  S.BulkBegin("reset", fid)
  local ok, err = pcall(function()
    for _, row in ipairs(S.Schema) do
      if row.page == NS.SchemaToasts.PAGE and row.feed == fid then S:ApplyDefault(row) end
    end
  end)
  S.BulkEnd("reset", fid, not ok)
  redraw()
  if not ok then error(err, 0) end
  return true
end

--- Reset style to skin (D12): every Style `FromSkin` companion of feed `fid` on, in one batch. The
--- stored picks stay where they are.
function TP.ResetStyle(fid)
  local entries = {}
  for _, path in ipairs(NS.SchemaToasts.StyleCompanions(fid)) do
    entries[#entries + 1] = { path = path, value = true }
  end
  local ok = NS.Schema:SetMany(entries)
  if TP.ctx and O.RefreshScalars then O.RefreshScalars() end
  return ok
end

--- The Unlock act: unlock (or lock) the feed; a refused unlock says it could not, and redraws nothing.
function TP.ToggleUnlock(fid)
  local want = not NS.State.toastUnlocked[fid]
  local unlocked = NS.Toasts:SetUnlocked(fid, want)
  if want and not unlocked then
    NS.Print(L["The feed cannot be unlocked now."])
    return false   -- nothing changed, so the page keeps its Unlock button
  end
  redraw()   -- the button now reads Lock, or Unlock again
  return unlocked
end

if type(StaticPopupDialogs) == "table" then
  StaticPopupDialogs["KA0S_LOOTHISTORY_RESET_FEED"] = {
    text = "Put every setting of the %s back to its default?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data) if data and data.fid then TP.ResetFeed(data.fid) end end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
  }
end

local function confirmReset(fid)
  local label = C.TOAST_FEED_LABEL[fid]:lower()
  if type(StaticPopup_Show) == "function" then
    StaticPopup_Show("KA0S_LOOTHISTORY_RESET_FEED", label, nil, { fid = fid })
  else
    TP.ResetFeed(fid)
  end
end

-- ── the host-drawn blocks ────────────────────────────────────────────────────────────────────

local function generalActs(ctx)
  local fid = selected
  local unlocked = NS.State.toastUnlocked[fid] and true or false
  O.InlineButtonPair(ctx,
    { text = L["Test"], tooltip = L["Show one sample toast of each kind this feed shows, even while it is off."],
      onClick = function() NS.Toasts:Test(fid) end },
    { text = unlocked and L["Lock"] or L["Unlock"],
      tooltip = unlocked and L["Stop moving this feed. Its place is saved as the nudge."]
        or L["Show this feed with a handle, and drag it where you want it."],
      onClick = function() TP.ToggleUnlock(fid) end })
  O.InlineButtonPair(ctx,
    { text = L["Reset feed\226\128\166"],
      tooltip = L["Put every setting of this feed back to its default. Asks first."],
      onClick = function() confirmReset(fid) end }, nil)
end

local function styleActs(ctx)
  local fid = selected
  O.InlineButtonPair(ctx,
    { text = L["Reset style to skin"],
      tooltip = L["Turn every Use the skin's option of this feed back on. The picks you made are kept."],
      onClick = function() TP.ResetStyle(fid) end }, nil)
end

TP.AFTER_GROUP = { General = generalActs, Style = styleActs }

local function drawHideSources(ctx)
  local row = NS.Schema:FindRow(prefix(selected) .. "hideSources")
  local scroll = O.EnsureScroll(ctx)
  if row and scroll and makeMultiCheck then makeMultiCheck(ctx, row, scroll) end
end

-- ── the render ───────────────────────────────────────────────────────────────────────────────

local TAB_OPTS = {
  afterSubgroup = { Details = drawHideSources },
  disabledFor = function() return NS.AddonIsOff and NS.AddonIsOff() end,
  disabledNotice = "Loot History is disabled. Nothing here takes effect until Enable Loot History is ticked on the General page.",
  rerender = function(ctx) O.RefreshPanel(ctx, true) end,
}

local function render(ctx)
  O.ClearScroll(ctx)
  ctx.unit = selected
  O.PageBanner(ctx, {
    label = L["Feed"], list = C.TOAST_FEED_LABEL, order = C.TOAST_FEEDS, value = selected,
    tooltip = L["The feed every tab below edits."],
    onSelect = function(fid) TP.Select(fid) end,
    action = { text = L["Add feed"], tooltip = L["Turn on the next feed that is off, and edit it."],
               onClick = function() TP.AddFeed() end },
  })
  O.RenderTabbedSchema(ctx, NS.SchemaToasts.PAGE, TP.AFTER_GROUP, nil, TAB_OPTS)
  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end
TP._render = render   -- tests only

TP.DEFAULTS_TOOLTIP = "Restore every setting of all three toast feeds, and the Blizzard alert option, to "
  .. "their defaults. Other pages are not changed."

--- The page builder (settings/Panel.lua P:Register, between General and Profiles).
function TP.Build(mainCategory)
  local ctx = O.CreatePanel(nil, "Toasts", {
    pageKey = NS.SchemaToasts.PAGE, defaultsButton = true,
    defaultsTooltip = TP.DEFAULTS_TOOLTIP .. " " .. O.KEYBINDS_UNCHANGED,
  })
  TP.ctx = ctx
  ctx.rebuilders = {}
  ctx.panel.defaultsOnClick = function() O.RestoreDefaults(NS.SchemaToasts.PAGE, ctx); redraw() end
  O.SetRenderer(ctx, render)
  Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "Toasts")
end
