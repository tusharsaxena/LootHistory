local _, NS = ...
NS.Panel = NS.Panel or {}
local P = NS.Panel

-- The LibKa0s-Options-1.0 instance: the canvas shell, the page registry, the lazy Defaults button,
-- the five widget makers, the two-column flow engine and the always-shown scrollbar patch. Wired in
-- settings/OptionsSetup.lua, which loads above this file (settings/Schema.lua and settings/Slash.lua
-- load between them) and is where every descriptor decision (and every declined surface) is written
-- down.
local O = NS.Options

-- Ka0s settings-panel pattern (shared across Ka0s addons; see WowAddonStandards):
--   * A parent canvas category renders the LANDING PAGE — logo + one-liner +
--     slash-command list — with the same gold header every subcategory uses.
--   * Each settings group is a canvas SUBCATEGORY ("General") with a breadcrumb
--     header ("Ka0s Loot History ▸ General"), a Defaults button, and a gold divider.
--   * Bodies render schema rows into a TWO-COLUMN grid (50%/50% Flow rows);
--     section headings (AceGUI Heading, centered label flanked by dividers) group them.
-- All of the above is now the library's. Writes still route through NS.Schema:Set (validate → write
-- → onChange); reads via :Get — the descriptor points at both.

local ADDON_TAGLINE = "Records every item you loot, attributes its source, and lets you browse and analyze it."
local LOGO_PATH     = "Interface\\AddOns\\LootHistory\\media\\logos\\loothistory.logo.tga"
local LOGO_SIZE     = 300  -- landing-page logo display size

-- The layout constants moved to LibKa0s-Options-1.0's own LAYOUT table, which carries the SAME
-- numbers this file used to declare (PADDING_X 16, HEADER_TOP 20, HEADER_HEIGHT 54, DEFAULTS_W 110,
-- ROW_VSPACER 8, the 10/6/26 section triple, BUTTON_PAIR_REL 0.492). The three this file's own page
-- code still needs are re-exported on the instance so host layout stays in lockstep with the engine.

-- Every AceGUI widget this file acquires itself, painted for this addon's skin (skinning-§3).
-- NS.AceGUI is normally the Options instance's owner proxy, which paints on Create already; the
-- explicit NS.SkinPaintAce repaints in place for the same owner, so the host does not depend on
-- which handle it was given. Nothing is painted while the Scope's Ignore settings panel is on, and
-- the release puts the widget back in AceGUI's shared pool stock (the library chains its restore
-- onto the widget's OnRelease).
local function acquire(wtype)
  local w = NS.AceGUI:Create(wtype)
  NS.SkinPaintAce(w)
  return w
end
P._acquire = acquire   -- settings/PanelAuction.lua binds it at its file load

-- ── Shared maker for a paired action button (Purge) ─────────────────────────────────────
-- Insets to BUTTON_PAIR_REL rather than a flat 0.5 so the right border isn't shaved by the
-- ScrollFrame clip (options-ui-§6/§8). Kept host-side: the library's InlineButtonPair builds its own
-- Flow row, and both of this addon's uses need a bare button to drop into a row someone else owns.
local function makePairButton(text, onClick)
  local btn = acquire("Button")
  btn:SetText(text)
  btn:SetRelativeWidth(O.BUTTON_PAIR_REL)
  if onClick then btn:SetCallback("OnClick", onClick) end
  return btn
end

-- ── The inverted set picker (host-drawn) ────────────────────────────────────────
-- A set-map rendered full-width as a wrapping checkbox grid. With row.invert, a *checked* box means
-- the source is recorded (i.e. NOT in the muted set), so the stored value is the logical inverse of
-- the checkbox state.
--
-- DECLINED from the library, deliberately: its five makers are checkbox / slider / dropdown /
-- editbox / color picker, and an inverted set picker is none of them. The row stays in the schema,
-- so the CLI and every reset still see it, and it is drawn from `afterGroup` below — which fires
-- after its group's last row is flushed, i.e. exactly where it used to sit.
--
-- It does NOT carry `skipRender`, and why it draws nothing on the generic path is worth knowing: it
-- is `type = "table"`, and `O.RenderField` dispatches on `row.type` over bool/number/string/color,
-- deliberately returning nil for a type it does not know. So the row IS walked and IS handed to the
-- renderer, which silently produces no widget. The visible result is identical to `skipRender`; the
-- mechanism is not. If the library ever grows a `table` maker this row starts drawing twice — once
-- generically, once here. `settings.auction.capture` is the row that really does carry
-- `skipRender`.
local function makeMultiCheck(ctx, row, scroll)
  local invert = row.invert
  local group = acquire("InlineGroup")
  group:SetTitle(row.label); group:SetFullWidth(true); group:SetLayout("Flow")
  local boxes = {}
  for _, opt in ipairs(row.values) do
    local cb = acquire("CheckBox")
    cb:SetLabel(opt.text); cb:SetWidth(150)
    cb:SetCallback("OnValueChanged", function(_, _, v)
      local cur = NS.Schema:Get(row.path) or {}
      local copy = {}
      for k, val in pairs(cur) do copy[k] = val end
      -- muted = checked when inverted, unchecked otherwise
      copy[opt.value] = ((invert and not v) or (not invert and v)) or nil
      NS.Schema:Set(row.path, copy)
    end)
    group:AddChild(cb)
    boxes[opt.value] = cb
  end
  scroll:AddChild(group)
  ctx.refreshers[#ctx.refreshers + 1] = function()
    local cur = NS.Schema:Get(row.path) or {}
    for value, cb in pairs(boxes) do
      local muted = cur[value] and true or false
      cb:SetValue(invert and not muted or (not invert and muted))
    end
  end
end


-- ── The History tab's body: live DB stats and Purge ────────────────────────────
--
-- Drawn from RenderTabbedSchema's `afterGroup` hook, keyed to the History group, rather than
-- appended by the page renderer. That is not decoration: a tab click re-enters RenderTabbedSchema
-- directly (ClearScroll, then the active tab's rows), never the page renderer, so anything the
-- renderer appended AFTER the schema rows would be drawn once and then vanish on the first click.
-- The hook is the seam that survives the click. There is no before-group hook, which is fine —
-- this block belongs under the retention row anyway.
--
-- NO O.Section heading any more. Under a strip the tab IS the heading, and a "History" heading
-- inside a tab called History is the page saying the same thing twice.
local function renderHistory(ctx)
  local scroll = O.EnsureScroll(ctx)
  if not scroll then return end

  local rowFrame = acquire("SimpleGroup")
  rowFrame:SetLayout("Flow"); rowFrame:SetFullWidth(true)

  local statsLabel = acquire("Label")
  statsLabel:SetRelativeWidth(0.5)
  rowFrame:AddChild(statsLabel)

  -- "Purge history…" — ellipsis: opens a confirm dialog.
  local purgeBtn = makePairButton("Purge history\226\128\166", function()
    if NS.SimBlocks("Purge") then return end
    if type(StaticPopup_Show) == "function" then StaticPopup_Show("KA0S_LOOTHISTORY_PURGE")
    elseif NS.Database and NS.Database.Purge then NS.Database:Purge() end
  end)
  rowFrame:AddChild(purgeBtn)
  scroll:AddChild(rowFrame)

  -- "Reset Everything" is NOT here any more. The global reset (options-ui-§12) is the Master controls
  -- tab's "Reset all settings" (options-ui-§15), drawn by the composer's own afterGroup hook, and it
  -- is a PROFILE reset that never touches the history. Purge history… above is the one act that
  -- clears the account-wide record.

  local function refreshStats()
    local s = NS.Database:StorageStats()
    local line1
    if s.count == 0 then
      line1 = "No items collected yet."
    else
      local count = (BreakUpLargeNumbers and BreakUpLargeNumbers(s.count)) or s.count
      line1 = string.format("%s %s collected over %d %s.",
        tostring(count), s.count == 1 and "item" or "items", s.days, s.days == 1 and "day" or "days")
    end
    -- "~" marks the estimate (real SavedVariables file size can't be read in-game). Not U+2248, which
    -- two skin faces cannot draw (ruling D-19, tests/test_glyphs.lua).
    statsLabel:SetText(line1 .. "\nDatabase size: ~" ..
      NS.Util.FormatBytes(s.bytes) .. "  (estimated)")
  end
  ctx.refreshers[#ctx.refreshers + 1] = refreshStats
  refreshStats()

  -- Live-refresh while the panel is open. Uses a private bus target (NOT NS.bus-as-self) so it
  -- can't clobber the Browser/Analytics consumers registered for the same messages. See
  -- NS.NewBusTarget.
  --
  -- The listener is registered ONCE but the label is not: every tab click builds a new statsLabel
  -- and a new refreshStats over it, and the old widget goes back to AceGUI's pool. So the
  -- registration closes over `P.__stats`, reassigned on every render, instead of over the
  -- refreshStats of whichever render happened to be first — which would have kept a released
  -- widget alive and repainted it forever while the live label went stale. (Latent before the
  -- strip too: O.SetRenderer re-runs a renderer whose page was dirtied off-screen.)
  P.__stats = refreshStats
  if not P.__ev then
    local ev = NS.NewBusTarget()
    if ev then
      local onChange = function()
        if P.general and P.general.panel:IsShown() and P.__stats then P.__stats() end
      end
      ev:RegisterMessage(NS.MSG.HISTORY_CHANGED, onChange)
      -- COALESCED, and only this one — the same split the Browser's and Analytics' own
      -- RecordAdded subscriptions already make (issue #27). `refreshStats` is a StorageStats pass
      -- over the WHOLE history with a per-record byte estimate, and `Database:Add` fires
      -- RecordAdded once per looted item, mid-pull. A multi-drop kill with this page open bought
      -- one full-history walk per drop for a readout nobody can read that fast.
      --
      -- HistoryChanged above stays immediate on purpose: a delete, a prune or a blacklist edit is
      -- one deliberate action that arrives on its own, and the size it changes should update at
      -- once. Only the automatic, bursty message needs collapsing.
      ev:RegisterMessage(NS.MSG.RECORD_ADDED,
        NS.Coalesce(onChange, NS.Constants.RECORD_ADDED_COALESCE))
      P.__ev = ev
    end
  end
end

-- Run a page's structural rebuilders (list rows) + relayout, and clear its dirty flag. Called on
-- first paint, on an on-screen edit, and on the next OnShow after an off-screen change — the gate
-- that keeps AceGUI teardown+rebuild off every tab click (options-ui-§11 / anti-pattern #39).
--
-- The flag is the LIBRARY's `ctx._dirty` — the one O.SetRenderer's OnShow actually reads — and not
-- a private `ctx.dirty` alongside it. A page-local flag is written and never read: the library
-- returns early on `_rendered and not _dirty`, so an off-screen change would never repaint.
--
-- A rebuilder that raises is swallowed so one broken list cannot blank the page, and logged once
-- per distinct message (debug-logging-§8, errors caught): a repaint runs on every list edit, and the
-- same fault would otherwise be one line per repaint or no line at all. The memory is the console's
-- DebugOnce gate (debug-logging-§9), re-armed by a Clear or a fresh `debug on`.
local function traceRebuildError(err)
  if not (NS.State.debug and NS.DebugOnce) then return end
  NS.DebugOnce("Cfg.rebuild\0" .. NS.SafeToString(err), "Cfg", "panel rebuilder failed: %s", err)
end

local function runRebuilders(ctx)
  for _, fn in ipairs(ctx.rebuilders or {}) do
    local ok, err = pcall(fn)
    if not ok then traceRebuildError(err) end
  end
  ctx._dirty = false
  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end
P._runRebuilders = runRebuilders   -- settings/PanelAuction.lua binds it at its file load

-- ── Filters sub-page: blacklist / whitelist item-id management ────────────────────
-- A single sub-page, three TABS (item blacklist, item whitelist, currency blacklist), one on screen.
-- Each: a short description, then one LibKa0s-Options IdList -- an add box (an id, a shift-clicked
-- link, or a name, with matching names listed as the player types) over one line per stored id with
-- Remove -- then a confirm-gated Clear all… LAST, the shape Ka0s Bank Ledger's Filters tab shares
-- (item 020, XC-26). The lists are core app logic and act point-in-time: blacklisted ids are
-- dropped at loot time and whitelisted ids are always recorded — neither list ever hides or
-- restores an already-stored row.
--
-- THE WIDGET NEVER WRITES. NS.Filters is these sets' one named writer (architecture-§5), so the
-- IdList's onAdd / onRemove call the same verbs the old add row and Remove buttons called, and the
-- stored shape — `db.profile.<list>[id] = true` — does not move.

--- Repaint the Filters tab: at once while the page is on screen, else on its next OnShow through the
--- library's own dirty flag. The HistoryChanged listener and the IdList's `ctx.rebuild` (an add, a
--- remove, an item load landing) both come through here.
local function repaintFilters(ctx)
  if ctx.panel:IsShown() then runRebuilders(ctx) else ctx._dirty = true end
end

--- Call one NS.Filters writer with the page's HistoryChanged repaint held off.
---
--- The writer fires HistoryChanged SYNCHRONOUSLY and the listener in buildFiltersTab repaints the
--- whole page on it — releasing the very edit box and status line the IdList clears once onAdd
--- returns, just before the IdList asks for its own redraw anyway. Held off for the call, one click
--- costs exactly one repaint: the widget's, after it has finished with its widgets.
local function filterWrite(ctx, verb, id)
  ctx.__filterWrite = true
  local ok, err = pcall(NS.Filters[verb], NS.Filters, id)
  ctx.__filterWrite = nil
  if not ok then error(err, 0) end
end

--- The ordered entries an IdList draws for `tab`: the stored set, sorted by id.
local function filterEntries(tab)
  local out = {}
  for i, id in ipairs(NS.Filters:SortedIDs(NS.Filters[tab.set](NS.Filters))) do
    out[i] = { id = id }
  end
  return out
end

--- The ids a list's add box can name, for its suggestions and its name lookup (issue #31): every id
--- on the lists `tab.candidateSets` names (both item lists for an item list), then every distinct id
--- the loot history holds in `tab.historyField`, newest first.
---
--- WHY THESE AND NOTHING ELSE. The client has no item-name search -- GetItemInfoInstant(name)
--- answers only for an item the player carries or carried this session -- and no currency-name
--- lookup at all. So a name the player does not carry resolves, and is listed, only through ids
--- something already knows, and the lists and the history are what this addon knows. Newest first
--- because the widget pre-warms at most 200 uncached candidates a build: recent loot is what a
--- player most likely means.
---
--- No new state: both are read as they stand, on every call. The widget calls this at every draw,
--- every submit and a render's first keystroke, and caps what it does with the answer itself.
local function filterCandidates(tab)
  local out, seen = {}, {}
  local function take(id)
    if type(id) == "number" and not seen[id] then seen[id] = true; out[#out + 1] = id end
  end
  for _, set in ipairs(tab.candidateSets) do
    for _, id in ipairs(NS.Filters:SortedIDs(NS.Filters[set](NS.Filters))) do take(id) end
  end
  local history = NS.Database:History() or {}
  for i = #history, 1, -1 do
    local r = history[i]
    if r then take(r[tab.historyField]) end
  end
  return out
end

-- Bulk "Clear all…" for one list (confirm-gated; the ellipsis says it opens a dialog, XC-17). The
-- list repaints itself through the HistoryChanged listener Filters:ClearList fires, so the button
-- only shows the popup. Drawn AFTER the IdList (item 020, LOO-L-new2): the list is what the tab is
-- for, and the destructive bulk act closes it rather than standing between the reader and it.
local function addClearAll(scroll, tab)
  local clearRow = acquire("SimpleGroup")
  clearRow:SetLayout("Flow"); clearRow:SetFullWidth(true)
  local clearBtn = acquire("Button")
  clearBtn:SetText("Clear all\226\128\166"); clearBtn:SetRelativeWidth(0.30)
  clearBtn:SetCallback("OnClick", function()
    if type(StaticPopup_Show) == "function" then
      StaticPopup_Show(tab.popup)
    elseif NS.Filters and NS.Filters.ClearList then
      NS.Filters:ClearList(tab.key)
    end
  end)
  clearRow:AddChild(clearBtn)
  O.AddSpacer(scroll, 6)
  scroll:AddChild(clearRow)
end

-- One list: its description, then the IdList (the add box and the entries), then Clear all….
local function makeFilterSection(ctx, tab)
  local scroll = O.EnsureScroll(ctx)
  -- No O.Section heading: the page is a tab strip now (options-ui-§13) and the tab IS the heading.
  -- A "Blacklist" heading under a tab called Blacklist is the page saying it twice.
  local descLabel = acquire("Label")
  descLabel:SetFullWidth(true); descLabel:SetText(tab.desc)
  scroll:AddChild(descLabel)
  O.AddSpacer(scroll, 6)

  -- `columns` (LibKa0s v1.47.0, OptionsWidgets minor 24; fitted to the canvas since v1.50.0,
  -- minor 27) comes from the LIST, not from here. All three ask for two.
  --
  -- WHY TWO. The blacklist and the whitelist are the lists that grow -- a loot blacklist is fed one
  -- junk item at a time out of a long history -- and this page has already paid for that length
  -- once: rebuilding every list on every OnShow stalled the client for about a second on a large
  -- blacklist (anti-pattern #39; docs/settings-panel.md, "The Filters tab -- blacklist /
  -- whitelist"). That rebuild is fixed and this is not about it; what the incident records is that
  -- these lists really do get long, and one entry per line is a scroll the player re-reads every
  -- time they open the tab. Two a line halves it.
  --
  -- CURRENCIES ASKED FOR ONE UNTIL THE OWNER SAW IT (2026-09-21). The reservation was that currency
  -- names are the long ones on this page -- "Weathered Harbinger Crest" -- and that above one
  -- column the library turns word wrap OFF on an entry's label (entryNoWrap,
  -- libs/LibKa0s/OptionsIdList.lua, called from idLine), because one name
  -- wrapping in the left column pushes the whole right column down and the grid stops lining up.
  -- The client truncates the TAIL instead, and the name and the gray `(id)` are ONE FontString
  -- (entryLabel), so an entry too long for its column loses the id ENTIRELY rather than
  -- shortening it (:1178-1183 states that cost).
  --
  -- That cost is real and still applies. What the reservation got wrong was the premise: the
  -- currency ids a player actually mutes are crest and stone names -- "Veteran Mistcrest (3443)",
  -- "Myth Mistcrest (3446)" -- which fit a column with room to spare, and the tab reading one-per-
  -- line beside two-per-line siblings looked like an omission rather than a decision. A list whose
  -- entries fit is the case columns was built for; the long-name worry belongs to the entries that
  -- are long, and those truncate on the item lists too. Uniform two, and the tooltip still carries
  -- the full name wherever one is cut.
  --
  -- IT IS A MAXIMUM, NOT A COUNT. Since v1.50.0 the list measures the content width it is actually
  -- drawn into and drops a column at a time while that width cannot pay for the layout -- 520px of
  -- content for two entries in the `removeStyle = "icon"` style this page asks for, against 584 in
  -- the default one (fitIdColumns :3165-3174, entryMinContent :3136-3144, the floors tabulated
  -- under ID_COLUMNS_MAX at :1893-1896). So a narrow settings canvas draws this page exactly as it
  -- drew before, nothing here has to know how wide Blizzard's canvas is, and a test that asserts
  -- the packing has to say what canvas it packs into (tests/panel_support.lua's withCanvas).
  O.IdList(ctx, {
    kind      = tab.kind,
    label     = tab.addLabel,
    tooltip   = tab.addTooltip,
    strings   = tab.strings,
    -- The empty-list line's gray is the skin's text.disabled (|cff808080 on Ka0s Default), read on
    -- every render so a skin switch reaches it with the page's own re-render (LH-05).
    emptyText = NS.SkinEscape("text.disabled") .. "(none)|r",
    entries   = function() return filterEntries(tab) end,
    candidates = function() return filterCandidates(tab) end,
    onAdd     = function(id) filterWrite(ctx, tab.add, id) end,
    onRemove  = function(id) filterWrite(ctx, tab.remove, id) end,
    removeStyle = "icon",
    columns     = tab.columns,
  })
  addClearAll(scroll, tab)

  -- A structural rebuild (lines added/removed), so it registers as a *rebuilder*: it runs on an
  -- on-screen edit and on the next OnShow after an off-screen change — never on every OnShow. The
  -- IdList draws its lines straight into the page scroll, so there is no list group to rebuild on
  -- its own: the rebuild is the page's structural refresh. Registered on every render, because
  -- renderGeneral reassigns ctx.rebuilders; run by repaintFilters.
  ctx.rebuilders[#ctx.rebuilders + 1] = function() O.RefreshPanel(ctx, true) end
end

-- The Filters TAB's three SUB-tabs, in strip order. The tab is called Filters, so none of them
-- repeats the word. Blacklist and Whitelist name the list type, as Ka0s Bank Ledger's two do; the
-- third was Currencies, which named the object type instead, and is Currency blacklist since item
-- 020 (LOO-L17) so all three name a list. Items first (both item lists adjacent, because they are
-- read together — an id on one is off the other), the currency list last.
--
-- Each description closes with the shared sentences (item 020, XC-26), word for word as Bank
-- Ledger's: the point-in-time rule on all three, and the one-list rule only on the two item lists,
-- whose add path really enforces it (NS.Filters:_move); the currency list has no sibling.
--
-- SECONDARY, not primary (options-ui-§13). Filters was its own canvas sub-page with its own
-- three-tab strip until R6 deprecated it into General; three id-lists are a list of like subjects
-- inside one category, which is exactly the division a secondary strip is for. O.SubTabStrip draws
-- it as ordinary page content inside the scroll, so it scrolls with the lists it divides rather
-- than pinning a second chrome band and pushing every page down twice.
--
-- Not schema groups either way: there is no Schema row for a dynamic list of item ids, so this
-- tab's body cannot come from the flow engine — it partitions ROWS, and this tab has none.
--
-- The PRIMARY tab's key, spelled once: it is both this tab's entry in GENERAL_TABS below and the
-- key `ctx.activeSubTab` is filed under, and the convention only works while the two agree.
local FILTERS_TAB = "Filters"

-- The add box's words. An item or a currency resolves by id, link or name, and the box lists the
-- matching names as the player types, every rank its own row. The name hints say where a name can
-- come from. They replace the widget's defaults ("ones this list knows") because this page's
-- candidates are the lists AND the loot history (filterCandidates), and the currency refusal's own
-- first sentence says "this page" for the same reason. Each hint is both the refusal's `{hint}` and
-- the end of its box's tooltip, so the two cannot disagree (a test_panel case pins both ends).
-- English literals, per the ratified English-only row (docs/ARCHITECTURE.md, localization-§1).
local ITEM_NAME_HINT = "Names work for items you carry (or carried this session), items in your loot "
  .. "history and ones on these lists; otherwise use the id or shift-click a link."
local CURRENCY_NAME_HINT = "Currency names work for currencies in your loot history and ones on this "
  .. "list; otherwise use the id or shift-click a currency link."
local ITEM_ADD_LABEL   = "Add item id, link or name"
local ITEM_ADD_TOOLTIP = "Type an item id or name, or shift-click an item link, then press Enter or "
  .. "Add. As you type, matching items are listed, every rank its own row: click one to add it. "
  .. ITEM_NAME_HINT
local ITEM_STRINGS = { nameHint = ITEM_NAME_HINT }
local CURRENCY_STRINGS = {
  empty    = "Type a currency id or name, or shift-click a currency link.",
  -- The library's "that this list knows" undersells where this page looks: the history too.
  notFound = "No currency named '{text}' that this page knows. {hint}",
  nameHint = CURRENCY_NAME_HINT,
}

-- Per list: the IdList kind, the NS.Filters reader (`set`) and writers (`add` / `remove`) it calls,
-- the Clear all popup, and `columns` -- how many entries this list asks the library to pack onto
-- one line. The writers are NS.Filters method names, called by filterWrite.
--
-- `columns` is PER LIST rather than one number on the shared spec. All three lists ask for two
-- today, so the key could be hoisted onto the shared spec -- it is kept per list because the count
-- is a statement about THAT list's entries, and the Currencies entry has already changed its answer
-- once. An absent `columns` reads as one (idColumns, libs/LibKa0s/OptionsIdList.lua), so dropping
-- the key is how a list opts back out. Why two is at the O.IdList call in makeFilterSection,
-- beside the `removeStyle` the trade depends on.
local FILTER_TABS = {
  { key = "blacklist", label = "Blacklist",
    desc = "Items here are never recorded when looted. Applies to future loots only; rows already "
      .. "recorded stay. An item can be on one list only; adding it here takes it off the other.",
    kind = "item", set = "Blacklist", add = "AddBlacklist", remove = "RemoveBlacklist",
    popup = "KA0S_LOOTHISTORY_CLEAR_BLACKLIST",
    addLabel = ITEM_ADD_LABEL, addTooltip = ITEM_ADD_TOOLTIP, strings = ITEM_STRINGS, columns = 2,
    candidateSets = { "Blacklist", "Whitelist" }, historyField = "itemID" },
  { key = "whitelist", label = "Whitelist",
    desc = "Items here are always recorded, even if they fall below Minimum quality, come from a "
      .. "source unticked under Capture > Record data from, or are quest items. Applies to future loots "
      .. "only; rows already recorded stay. An item can be on one list only; adding it here takes it "
      .. "off the other.",
    kind = "item", set = "Whitelist", add = "AddWhitelist", remove = "RemoveWhitelist",
    popup = "KA0S_LOOTHISTORY_CLEAR_WHITELIST",
    addLabel = ITEM_ADD_LABEL, addTooltip = ITEM_ADD_TOOLTIP, strings = ITEM_STRINGS, columns = 2,
    candidateSets = { "Blacklist", "Whitelist" }, historyField = "itemID" },
  { key = "currencyBlacklist", label = "Currency blacklist",
    desc = "Currencies here are never recorded when looted (Valorstones, crests, Honor, etc.). "
      .. "Applies to future loots only; rows already recorded stay.",
    kind = "currency", set = "CurrencyBlacklist", add = "AddCurrencyBlacklist",
    remove = "RemoveCurrencyBlacklist", popup = "KA0S_LOOTHISTORY_CLEAR_CURRENCY",
    addLabel = "Add currency id, link or name",
    addTooltip = "Type a currency id or name, or shift-click a currency link, then press Enter or "
      .. "Add. As you type, matching currencies are listed: click one to add it. " .. CURRENCY_NAME_HINT,
    strings = CURRENCY_STRINGS, columns = 2,
    candidateSets = { "CurrencyBlacklist" }, historyField = "currencyID" },
}

--- The Filters tab: a secondary strip over the three id-lists, then the selected list.
---
--- THE SUB-TAB SELECTION IS THE HOST'S STATE, and the convention the library establishes for the
--- collection is `ctx.activeSubTab` as a TABLE keyed by the PRIMARY tab's key — so switching
--- category and back returns to the list you were on, and a stale pointer heals per category. It is
--- session state and is never persisted (options-ui-§13), exactly like `ctx.activeTab`.
local function buildFiltersTab(ctx)
  local scroll = O.EnsureScroll(ctx)
  if not scroll then return end

  ctx.activeSubTab = ctx.activeSubTab or {}
  local key = ctx.activeSubTab[FILTERS_TAB]
  -- A pointer naming a list this tab no longer has would render blank, so a stale one heals to the
  -- first rather than being trusted — the same cheap check the library's own strip does.
  local known = false
  for _, tab in ipairs(FILTER_TABS) do if tab.key == key then known = true end end
  if not known then key = FILTER_TABS[1].key end
  ctx.activeSubTab[FILTERS_TAB] = key

  -- The strip's buttons are raw frames, so they need a frame to live on: a layout-suppressed
  -- SimpleGroup added as an ordinary scroll child, sized to whatever height the strip reports.
  -- ClearScroll drains the library's __subTabKids ledger BEFORE it releases this group, which is
  -- what stops the buttons riding a pooled frame into somebody else's page.
  local host = acquire("SimpleGroup")
  host:SetLayout(nil); host:SetFullWidth(true)
  scroll:AddChild(host)

  local tabs = {}
  for i, tab in ipairs(FILTER_TABS) do tabs[i] = { key = tab.key, label = tab.label } end
  local _, height = O.SubTabStrip(ctx, host.frame, {
    tabs  = tabs,
    value = key,
    onSelect = function(k)
      if k == ctx.activeSubTab[FILTERS_TAB] then return end
      ctx.activeSubTab[FILTERS_TAB] = k
      -- Structural: re-enter the page renderer, which clears the scroll and draws the newly
      -- selected list. It needs no combat guard of its own and must not carry one: the library's
      -- combat lock refuses a sub-tab switch on a covered page (options-ui-§2 / §13).
      O.RefreshPanel(ctx, true)
    end,
  })
  host:SetHeight(height or 0)
  O.AddSpacer(scroll, 6)

  -- ONE section, the selected one. Three stacked lists were three AceGUI teardown-and-rebuilds on
  -- every paint and a page a player scrolled past two lists to reach the third; a sub-tab click now
  -- rebuilds exactly the list on screen (anti-pattern #39 is why that matters here of all pages).
  for _, tab in ipairs(FILTER_TABS) do
    if tab.key == key then makeFilterSection(ctx, tab) end
  end

  -- Where the IdList redraws after an add, a remove, or an item load landing: this page's own
  -- rebuilders, gated on visibility like every other repaint here. Left unset, the widget would fall
  -- back to O.RefreshAllPanels and repaint every rendered page to service this one.
  ctx.rebuild = function() repaintFilters(ctx) end

  -- Live-update the lists when they change from elsewhere (the History right-click Blacklist, Clear
  -- all, a reset), on a private bus target (never NS.bus-as-self) so it can't clobber other
  -- consumers. While the page is on screen we repaint immediately; while it is hidden we only flag it
  -- dirty, so the next OnShow repaints once instead of every tab click paying an AceGUI
  -- teardown+rebuild (options-ui-§11). A change this page's own IdList made is skipped here: the
  -- widget repaints for it (filterWrite).
  if not P.__evFilters then
    local ev = NS.NewBusTarget()
    if ev then
      local onChange = function()
        if not ctx.__filterWrite then repaintFilters(ctx) end
      end
      ev:RegisterMessage(NS.MSG.HISTORY_CHANGED, onChange)
      P.__evFilters = ev
    end
  end
  -- No first-paint rebuilder call: the IdList drew the selected list's lines above, and the rebuilder
  -- is a structural refresh of this very page, so running it from inside the render would recurse.
end

-- ── Landing page: logo + tagline + slash-command list ───────────────────────────
-- Through the library's builder (options-ui-§5): logo, the tagline, then the Slash Commands heading
-- and one row per NS.COMMANDS entry (the rows go through lib.FormatRow; see closed issue #24,
-- LIBKA0S-09). It replaced a private body that drew the logo as a texture straight on a pooled
-- AceGUI SimpleGroup frame and never took it off: after a re-render the frame came back as another
-- SimpleGroup (the spacer under the heading) still carrying the logo, so the page showed it twice.
-- The builder owns the clear, keeps one texture per frame and hides it in the group's OnRelease.
local function buildMainContent(ctx)
  O.BuildLandingPage(ctx, {
    logo     = LOGO_PATH,
    logoSize = LOGO_SIZE,
    notes    = ADDON_TAGLINE,
    sections = { {
      heading = "Slash Commands",
      rows    = function() return NS.Slash.LandingRows and NS.Slash:LandingRows() or {} end,
    } },
  })
end

-- ── Flow-engine hooks ───────────────────────────────────────────────────────────
--
-- Hoisted to file scope rather than rebuilt per render, which the library explicitly supports: it
-- keeps its one-shot bookkeeping in call-local sets, so a second render of the same page fires both
-- again instead of silently dropping them.

-- No `pairWith` table any more. The one entry it ever held attached "Reset Everything" to the
-- right half of the Window scale row; that button is the Master controls tab's "Reset all settings"
-- now, drawn by the composer's own afterGroup hook (settings/Schema.lua). `pairWith` fires only
-- while its path is the lone widget on its line, and Window scale is paired with Row height on the
-- Interface tab — so the hook would silently never fire, which is the worst of the two outcomes.

-- The host-drawn blocks the flow engine cannot draw itself, one per tab that has one.
--
--   Master controls — the closing button pair (Reset position | Reset all settings). NOT this
--                     file's: `O.MasterControls` returned it beside the rows, and it is passed
--                     through under the group name the composer used, because the group name IS
--                     the hook key (settings/Schema.lua).
--   AH price        — the pooled price-source table, under the "Price sources" subsection heading
--                     the `settings.auction.capture` row declares.
--   History         — the storage readout and "Purge history…".
--
-- afterGroup is the ONLY seam that survives a tab click: the strip's onSelect re-enters the page
-- renderer, and while that does re-run this file, a block appended after the rows would land at the
-- BOTTOM of every tab rather than inside the one it belongs to.
local AFTER_GROUP = {
  -- settings/PanelAuction.lua loads after this file, so the tab resolves it when it renders.
  ["AH price"]   = function(ctx) return P._buildAuctionTable(ctx) end,
  ["History"] = renderHistory,
}
AFTER_GROUP[NS.Schema.MASTER_GROUP] = NS.Schema.MasterAfterGroup

-- The afterSubgroup seam (OptionsFlow minor 2, LibKa0s#59). Capture's muted-source picker closes its
-- Loot subsection (item 020, LOO-L04), above Ledger. The `settings.excludedSources` row it represents
-- is walked by the generic path and produces no widget (type = "table"; see makeMultiCheck above),
-- so this lands exactly where that path would have put it: after that row, on a fresh line.
local RENDER_OPTS = {
  noHeadings = true,
  afterSubgroup = {
    ["Loot"] = function(ctx)
      local row = NS.Schema:FindRow("settings.excludedSources")
      local scroll = O.EnsureScroll(ctx)
      if row and scroll then makeMultiCheck(ctx, row, scroll) end
    end,
  },
}

-- ── The General page's strip ────────────────────────────────────────────────────
--
-- ONE page now. Filters and AH price were canvas sub-pages of their own until R6 deprecated them
-- into General: three pages, each with its own strip, made a player hunt for which of the three
-- held the setting they wanted, and one of the three (AH price) drew no strip at all.
--
-- THE STRIP IS DRAWN BY HAND rather than by O.RenderTabbedSchema, and the reason is that two of the
-- eight tabs (Filters and the library's Keybindings) hold no schema rows to partition, and a third
-- (the library's Appearance) draws its two rows as choice grids of its own.
-- RenderTabbedSchema derives its tab list from `group`,
-- which is exactly right for a page whose every section is rows — and cannot name a tab whose body
-- is a dynamic list of item ids. So the tab list is declared here, each entry is either a schema
-- GROUP (rendered by the same O.RenderRows call the library would have made, `noHeadings` and all)
-- or a `build` function, and tests/test_panel.lua pins the two against each other so a group added
-- to the schema and not to this list cannot go unnoticed.
-- THE NAMES AND THE ORDER ARE SHARED WITH KA0S BANK LEDGER, whose strip is these minus AH
-- price: Master controls, Capture, Filters, Interface, History, Keybindings. The two addons keep the
-- same shape of record and a player compares their panels directly, so one subject carries one name
-- across both — Collection became Capture and Maintenance became History. Filters was moved last
-- once so the shared tabs sat in the shared order; item 020 (LOO-L08 with Bank Ledger's BAN-L-new1,
-- XC-26) moved it back to third IN BOTH, so "what gets recorded" is two adjacent tabs (Capture,
-- then the lists that override it) instead of four tabs apart. AH price is this addon's alone and
-- directly follows the two recording tabs it qualifies: it prices what capture recorded.
--
-- A tab name is a `group`, never a stored path, so the convergence was a rename throughout and
-- carried no migration (options-ui-§15).
local GENERAL_TABS = {
  -- options-ui-§15: the FIRST tab, under that exact name, in every Ka0s addon.
  { key = "Master controls" },
  { key = "Capture" },
  { key = FILTERS_TAB, build = buildFiltersTab },
  -- "AH price", sentence case (item 020, LOO-L10; XC-06). It is the schema GROUP of the two auction
  -- rows and the AFTER_GROUP key above as well, so all three move together; a group is never a
  -- stored path, so no SavedVariables key is involved.
  { key = "AH price" },
  { key = "Interface" },
  { key = "History" },
}

-- skinning-§3: the Skin tab, after History and before Keybindings, which stays last. The
-- library's own entry (O.AppearanceTab): the skin source, the nine skins, "Copy to every Ka0s
-- addon..." and the note, drawn from LibKa0s-Skin-1.0 for the owner core/SkinSetup.lua registered.
-- `get` and `set` are that file's read and write seams, so a pick lands through NS.Schema:Set like
-- every other setting; the tab calls Skin:SetChoice first, so the live repaint is the library's and
-- the rows' onChange finds nothing left to apply. The tab is the group of the two skipRender rows
-- (settings/Schema.lua). On the degraded path the stub's entry draws nothing, and the tab is still
-- there. Eight tabs, the options-ui-§13 budget.
do
  local at = O.AppearanceTab({ owner = NS.Skin and NS.Skin.owner, get = NS.SkinChoice, set = NS.WriteSkinChoice })
  GENERAL_TABS[#GENERAL_TABS + 1] = { key = at.key, label = at.label, tooltip = at.tooltip, build = at.render }
end

-- options-ui-§20: the Keybindings tab, LAST, after every other tab. The library's own entry
-- (O.KeybindingsTab): its key, its label and tooltip, and its render, which draws the rows of
-- NS.BINDINGS (core/LauncherSetup.lua) through O.KeybindRows. Nothing here draws a row or holds a key:
-- both surfaces, this tab and Options -> Keybindings, read and write the client's one store. On the
-- degraded path the stub's entry draws nothing, and the tab is still there.
do
  local kb = O.KeybindingsTab({ bindings = NS.BINDINGS })
  GENERAL_TABS[#GENERAL_TABS + 1] = { key = kb.key, label = kb.label, tooltip = kb.tooltip, build = kb.render }
end

--- The rows of one schema group, in declaration order.
local function rowsOfGroup(group)
  local out = {}
  for _, row in ipairs(NS.Schema.Schema) do
    if row.page == "General" and row.group == group then out[#out + 1] = row end
  end
  return out
end

--- Render one schema tab's rows.
local function renderGroupRows(ctx, group)
  -- `noHeadings`, exactly as RenderTabbedSchema renders an active tab: under a strip the tab IS the
  -- group's heading. A row's `subgroup` is NOT suppressed by it, which is what gives the Capture,
  -- AH price and Interface tabs their subsection headings.
  O.RenderRows(ctx, rowsOfGroup(group), AFTER_GROUP, nil, RENDER_OPTS)
end

-- ── Renderers ───────────────────────────────────────────────────────────────────
--
-- Each is declared through O.SetRenderer, which owns WHEN it runs: the page's first show, and again
-- after a structural refresh marked it dirty while hidden. Every one starts by releasing the
-- previous render's children, because a renderer the library may re-run must be idempotent.

-- No banner (options-ui-§14): the page edits ONE thing, the active profile, and the profile is
-- chosen on the Profiles page (settings/Profiles.lua), as in every Ka0s addon with profiles; there
-- is no per-window or per-unit state for a banner to be a picker FOR. It draws no page-header block
-- either: nothing on this page applies to every tab.
local function renderGeneral(ctx)
  -- FIRST, before ClearScroll and before the first widget of the new pass exists. The reorder
  -- controller's handles and boxes are pooled and are parented to frames ClearScroll is about to
  -- hand back to AceGUI (options-ui-§18).
  P._cancelReorder(ctx)
  -- The pooled price host is this addon's own frame and is NOT released by ClearScroll. The rule's
  -- undo is the placeholder's own OnRelease in buildAuctionTable (options-ui-§19); this park is the
  -- second line, kept as belt-and-braces so the host never stays visible over whichever tab is
  -- drawn next or rides a placeholder that has gone back to the pool.
  if ctx._priHost then
    ctx._priHost:Hide()
    ctx._priHost:SetParent(ctx.panel)
    ctx._priHost:ClearAllPoints()
  end

  O.ClearScroll(ctx)
  ctx.rebuilders = {}   -- ClearScroll reassigns the library's refreshers; these are this addon's

  -- A stale pointer heals to the first tab rather than being trusted, exactly as the library's own
  -- RenderTabbedSchema does: a tab naming a section this page no longer has would render blank.
  local known = false
  for _, tab in ipairs(GENERAL_TABS) do if tab.key == ctx.activeTab then known = true end end
  if not known then ctx.activeTab = GENERAL_TABS[1].key end

  local tabs = {}
  for i, tab in ipairs(GENERAL_TABS) do
    tabs[i] = { key = tab.key, label = tab.label or tab.key, tooltip = tab.tooltip }
  end
  O.TabStrip(ctx, {
    tabs  = tabs,
    value = ctx.activeTab,
    onSelect = function(key)
      if key == ctx.activeTab then return end
      ctx.activeTab = key
      -- Structural: re-enter this renderer, which clears the scroll and draws the newly selected
      -- tab. It needs no combat guard of its own and must not carry one: the library's combat lock
      -- covers a page shown in combat and refuses the tab switch (options-ui-§2 / §13), and
      -- O.OpenOptionsPanel refuses the protected category switch.
      O.RefreshPanel(ctx, true)
    end,
  })

  for _, tab in ipairs(GENERAL_TABS) do
    if tab.key == ctx.activeTab then
      if tab.build then
        tab.build(ctx)
      else
        renderGroupRows(ctx, tab.key)
      end
    end
  end

  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end

function P.BuildMain(ctx)
  buildMainContent(ctx)
  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end

-- ── Refresh / Defaults ──────────────────────────────────────────────────────────

--- Scalar re-sync across every registered page: widgets re-read their values, nothing is rebuilt.
function P:Refresh()
  O.RefreshScalars()
end

--- The General page's Defaults button — page-wide, and the page is the whole panel now
--- (options-ui-§13: a per-page Defaults button's blast radius MUST NOT narrow to the visible tab).
--- It is options-ui-§12's ONE global reset, the act `/lh resetall` and Reset all settings reach:
--- Sl:CliResetAll, the active profile back to its defaults. The profile holds every schema row,
--- the three id-lists, the auction cascade, the saved view and the window geometry, so nothing is
--- left for a second walk here, and O.RestoreAllDefaults re-renders every panel itself.
function P:RestoreDefaults()
  if NS.Slash and NS.Slash.CliResetAll then NS.Slash:CliResetAll() end
end

-- ── Registration ────────────────────────────────────────────────────────────────
local registered

function P:Register()
  if registered then return end
  -- The library registers the MAIN canvas itself and survives a missing Settings API silently, but
  -- the builder below calls RegisterCanvasLayoutSubcategory directly — and a builder that raises is
  -- pcall'd and REPORTED by key, so a client without the API would print an error instead of doing
  -- nothing. Bail once, up front, exactly as this function always did.
  if not (Settings and Settings.RegisterCanvasLayoutCategory
          and Settings.RegisterCanvasLayoutSubcategory) then return end
  registered = true

  -- TWO sub-pages: General, then Profiles. Filters and AH price were sub-pages of their own until R6
  -- folded them into General's strip; their bodies are unchanged and their two registrations are
  -- gone.
  O.RegisterOptionsPage("General", "General", function(mainCategory)
    -- The Defaults button IS options-ui-§12's global reset (P:RestoreDefaults -> CliResetAll), so
    -- its tooltip is Reset all settings' own, read from the descriptor by O.ResetAllTooltip exactly
    -- as the composed button reads it (U-04; item 020, LOO-L-new4), and no host words sit around
    -- it. O.KEYBINDS_UNCHANGED follows (options-ui-§20): the reset is the active profile's, and a
    -- key is the client's, never a setting this addon stores.
    local ctx = O.CreatePanel(nil, "General", {
      pageKey = "General", defaultsButton = true,
      defaultsTooltip = O.ResetAllTooltip(O.KEYBINDS_UNCHANGED),
    })
    P.general = ctx
    ctx.rebuilders = {}
    ctx.panel.defaultsOnClick = function() P:RestoreDefaults() end
    O.SetRenderer(ctx, renderGeneral)
    Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "General")
  end)
  -- Profiles LAST in the Settings tree (options-ui-§3), registered here rather than at its own file
  -- load so the order is this function's and not the TOC's. The builder answers nil -- the page
  -- opts out -- when AceDBOptions or AceConfig is missing.
  if NS.ProfilesPage then
    O.RegisterOptionsPage("Profiles", NS.L["Profiles"], NS.ProfilesPage.Build)
  end

  -- Resolves AceGUI, hands it over as NS.AceGUI, registers the main canvas (whose body is the
  -- landing page, drawn on its first OnShow through the descriptor's buildMain) and then runs the
  -- builder above.
  O.CreateOptionsPanel()
end
function P:Open()
  -- The combat refusal lives in the library, and it is wider than a guard here could be: a page the
  -- Blizzard AddOns sidebar reaches directly in combat is covered and locked, never closed
  -- (options-ui-§2). It refuses rather than deferring-and-replaying, and no guard sits beside it.
  O.OpenOptionsPanel()
end
