local _, NS = ...
NS.Panel = NS.Panel or {}
local P = NS.Panel

-- The LibKa0s-Options-1.0 instance: the canvas shell, the page registry, the lazy Defaults button,
-- the five widget makers, the two-column flow engine and the always-shown scrollbar patch. Wired in
-- settings/OptionsSetup.lua, which loads immediately before this file and is where every descriptor
-- decision (and every declined surface) is written down.
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

-- ── Shared maker for a paired action button (Reset Everything, Purge) ───────────────────
-- Insets to BUTTON_PAIR_REL rather than a flat 0.5 so the right border isn't shaved by the
-- ScrollFrame clip (options-ui-§6/§8). Kept host-side: the library's InlineButtonPair builds its own
-- Flow row, and both of this addon's uses need a bare button to drop into a row someone else owns.
local function makePairButton(text, onClick)
  local btn = NS.AceGUI:Create("Button")
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
  local group = NS.AceGUI:Create("InlineGroup")
  group:SetTitle(row.label); group:SetFullWidth(true); group:SetLayout("Flow")
  local boxes = {}
  for _, opt in ipairs(row.values) do
    local cb = NS.AceGUI:Create("CheckBox")
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


-- ── The History tab's body: live DB stats, Purge, Reset Everything ─────────────
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

  local rowFrame = NS.AceGUI:Create("SimpleGroup")
  rowFrame:SetLayout("Flow"); rowFrame:SetFullWidth(true)

  local statsLabel = NS.AceGUI:Create("Label")
  statsLabel:SetRelativeWidth(0.5)
  rowFrame:AddChild(statsLabel)

  -- "Purge history…" — ellipsis: opens a confirm dialog.
  local purgeBtn = makePairButton("Purge history\226\128\166", function()
    if type(StaticPopup_Show) == "function" then StaticPopup_Show("KA0S_LOOTHISTORY_PURGE")
    elseif NS.Database and NS.Database.Purge then NS.Database:Purge() end
  end)
  rowFrame:AddChild(purgeBtn)
  scroll:AddChild(rowFrame)

  -- "Reset Everything" is NOT here any more. It is the confirm-gated global reset (options-ui-§12)
  -- and options-ui-§15 puts that on the Master controls tab as the closing button pair's
  -- "Reset all settings", drawn by the composer's own afterGroup hook. Same popup, same
  -- Sl:ResetEverything, same blast radius — two buttons over one act is the thing this pass exists
  -- to remove, so this one is gone rather than duplicated.

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
    -- \226\137\136 = "≈"  (real SavedVariables file size can't be read in-game; estimated)
    statsLabel:SetText(line1 .. "\nDatabase size: \226\137\136 " ..
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
      ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", onChange)
      -- COALESCED, and only this one — the same split the Browser's and Analytics' own
      -- RecordAdded subscriptions already make (issue #27). `refreshStats` is a StorageStats pass
      -- over the WHOLE history with a per-record byte estimate, and `Database:Add` fires
      -- RecordAdded once per looted item, mid-pull. A multi-drop kill with this page open bought
      -- one full-history walk per drop for a readout nobody can read that fast.
      --
      -- HistoryChanged above stays immediate on purpose: a delete, a prune or a blacklist edit is
      -- one deliberate action that arrives on its own, and the size it changes should update at
      -- once. Only the automatic, bursty message needs collapsing.
      ev:RegisterMessage("Ka0s_LootHistory_RecordAdded",
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
local function runRebuilders(ctx)
  for _, fn in ipairs(ctx.rebuilders or {}) do pcall(fn) end
  ctx._dirty = false
  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end

-- ── Filters sub-page: blacklist / whitelist item-id management ────────────────────
-- A single sub-page, three TABS (item blacklist, item whitelist, currency blacklist), one on screen.
-- Each: a short description, a confirm-gated Clear all, then one LibKa0s-Options IdList: an add box
-- (an id, a shift-clicked link, or a name, with matching names listed as the player types) over one
-- line per stored id with Remove. The lists are core app logic and act point-in-time: blacklisted ids are
-- dropped at loot time and whitelisted ids are always recorded — neither list ever hides or
-- restores an already-stored row.
--
-- THE WIDGET NEVER WRITES. NS.Filters is these sets' one named writer (architecture-§5), so the
-- IdList's onAdd / onRemove call the same verbs the old add row and Remove buttons called, and the
-- stored shape — `db.global.<list>[id] = true` — does not move.

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

-- Bulk "Clear all" for one list (confirm-gated). The list repaints itself through the
-- HistoryChanged listener Filters:ClearList fires, so the button only shows the popup.
local function addClearAll(scroll, tab)
  local clearRow = NS.AceGUI:Create("SimpleGroup")
  clearRow:SetLayout("Flow"); clearRow:SetFullWidth(true)
  local clearBtn = NS.AceGUI:Create("Button")
  clearBtn:SetText("Clear all"); clearBtn:SetRelativeWidth(0.30)
  clearBtn:SetCallback("OnClick", function()
    if type(StaticPopup_Show) == "function" then
      StaticPopup_Show(tab.popup)
    elseif NS.Filters and NS.Filters.ClearList then
      NS.Filters:ClearList(tab.key)
    end
  end)
  clearRow:AddChild(clearBtn)
  scroll:AddChild(clearRow)
  O.AddSpacer(scroll, 4)
end

-- One list: its description, Clear all, then the IdList (the add box and the entries).
local function makeFilterSection(ctx, tab)
  local scroll = O.EnsureScroll(ctx)
  -- No O.Section heading: the page is a tab strip now (options-ui-§13) and the tab IS the heading.
  -- A "Blacklist" heading under a tab called Blacklist is the page saying it twice.
  local descLabel = NS.AceGUI:Create("Label")
  descLabel:SetFullWidth(true); descLabel:SetText(tab.desc)
  scroll:AddChild(descLabel)
  O.AddSpacer(scroll, 6)
  addClearAll(scroll, tab)

  -- `columns` (LibKa0s v1.47.0, OptionsWidgets minor 24; fitted to the canvas since v1.50.0,
  -- minor 27) comes from the LIST, not from here: the
  -- two item lists ask for two entries a line and Currencies asks for nothing, which reads as one.
  --
  -- WHY TWO, AND ON THE ITEM LISTS ONLY. The blacklist and the whitelist are the lists that grow --
  -- a loot blacklist is fed one junk item at a time out of a long history -- and this page has
  -- already paid for that length once: rebuilding every list on every OnShow stalled the client for
  -- about a second on a large blacklist (anti-pattern #39; docs/settings-panel.md, "The Filters tab
  -- -- blacklist / whitelist"). That rebuild is fixed and this is not about it; what the incident
  -- records is that these lists really do get long, and one entry per line is a scroll the player
  -- re-reads every time they open the tab. Two a line halves it. The Currencies list is not in that
  -- class: a player mutes a handful of currency ids, so a second column there would buy almost
  -- nothing.
  --
  -- AND IT WOULD COST SOMETHING THERE. At more than one column the library turns word wrap OFF on
  -- an entry's label -- entryNoWrap, libs/LibKa0s/OptionsWidgets.lua:2924, called from idLine at
  -- :3003-3007 -- because one name wrapping to two lines in the left column pushes the whole right
  -- column down and the grid stops lining up. The client truncates the TAIL instead, and the name
  -- and the gray `(id)` are ONE FontString (entryLabel, :2643-2654), so an entry too long for its
  -- column loses the id ENTIRELY rather than shortening it (the contract states this cost at
  -- :3296-3305). Currency names are the long ones on this page -- "Weathered Harbinger Crest" --
  -- and the id is exactly what a player reads back when they are checking what they muted. One
  -- column still wraps, so it keeps both.
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
    emptyText = "|cff808080(none)|r",
    entries   = function() return filterEntries(tab) end,
    candidates = function() return filterCandidates(tab) end,
    onAdd     = function(id) filterWrite(ctx, tab.add, id) end,
    onRemove  = function(id) filterWrite(ctx, tab.remove, id) end,
    removeStyle = "icon",
    columns     = tab.columns,
  })

  -- A structural rebuild (lines added/removed), so it registers as a *rebuilder*: it runs on an
  -- on-screen edit and on the next OnShow after an off-screen change — never on every OnShow. The
  -- IdList draws its lines straight into the page scroll, so there is no list group to rebuild on
  -- its own: the rebuild is the page's structural refresh. Registered on every render, because
  -- renderGeneral reassigns ctx.rebuilders; run by repaintFilters.
  ctx.rebuilders[#ctx.rebuilders + 1] = function() O.RefreshPanel(ctx, true) end
end

-- The Filters TAB's three SUB-tabs, in strip order. The tab is called Filters, so none of them
-- repeats the word: "Blacklisted currencies" is Currencies here, because the only currency list
-- there is IS a blacklist and the qualifier was carrying nothing. Items first (both item lists
-- adjacent, because they are read together — an id on one is off the other), currencies last.
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
-- `columns` is PER LIST rather than one number on the shared spec, and the Currencies entry leaves
-- it out deliberately: an absent `columns` reads as one and draws what every list here drew before
-- (libs/LibKa0s/OptionsWidgets.lua:3041-3051). Why two on the item lists and not on this one is at
-- the O.IdList call in makeFilterSection, beside the `removeStyle` the trade depends on.
local FILTER_TABS = {
  { key = "blacklist", label = "Blacklist",
    desc = "Items here are never recorded when looted from now on. Existing rows are left untouched "
      .. "(this only affects future loots — delete old rows from the history table if you want them gone).",
    kind = "item", set = "Blacklist", add = "AddBlacklist", remove = "RemoveBlacklist",
    popup = "KA0S_LOOTHISTORY_CLEAR_BLACKLIST",
    addLabel = ITEM_ADD_LABEL, addTooltip = ITEM_ADD_TOOLTIP, strings = ITEM_STRINGS, columns = 2,
    candidateSets = { "Blacklist", "Whitelist" }, historyField = "itemID" },
  { key = "whitelist", label = "Whitelist",
    desc = "Items here are always recorded, even if they fall below your quality threshold, come from a "
      .. "muted source, or are quest items. Adding an id to one list removes it from the other.",
    kind = "item", set = "Whitelist", add = "AddWhitelist", remove = "RemoveWhitelist",
    popup = "KA0S_LOOTHISTORY_CLEAR_WHITELIST",
    addLabel = ITEM_ADD_LABEL, addTooltip = ITEM_ADD_TOOLTIP, strings = ITEM_STRINGS, columns = 2,
    candidateSets = { "Blacklist", "Whitelist" }, historyField = "itemID" },
  { key = "currencyBlacklist", label = "Currencies",
    desc = "Currencies here are never recorded when looted from now on (Valorstones, crests, Honor, etc.). "
      .. "Point-in-time — existing rows are left untouched.",
    kind = "currency", set = "CurrencyBlacklist", add = "AddCurrencyBlacklist",
    remove = "RemoveCurrencyBlacklist", popup = "KA0S_LOOTHISTORY_CLEAR_CURRENCY",
    addLabel = "Add currency id, link or name",
    addTooltip = "Type a currency id or name, or shift-click a currency link, then press Enter or "
      .. "Add. As you type, matching currencies are listed: click one to add it. " .. CURRENCY_NAME_HINT,
    strings = CURRENCY_STRINGS,
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
  local host = NS.AceGUI:Create("SimpleGroup")
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
      ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", onChange)
      P.__evFilters = ev
    end
  end
  -- No first-paint rebuilder call: the IdList drew the selected list's lines above, and the rebuilder
  -- is a structural refresh of this very page, so running it from inside the render would recurse.
end

-- ── Auction House price table (unified collect + priority) ───────────────────────
-- ONE frame-light table replaces the old Data Collection + Priority sections. Every text column is a
-- FontString (a region, not a frame); only the genuinely-interactive cells (enable checkbox, ⓘ info)
-- plus the library's drag handle are real frames, and the row slots + their frames are created ONCE
-- and reused on every refresh — never re-allocated. This is load-bearing: the Blizzard Settings
-- canvas runs a super-linear pass over a panel's frames on tab-transition, so the previous ~213-frame
-- AH page froze the client ~1.7s when you navigated away from it (see docs/settings-panel.md).
-- The leading tick and the row's info button are LibKa0s-Media marks now, with the Blizzard art
-- beneath them as the fallback rung. This addon still ships no art files of its own.
--
-- ── WHAT R6 CHANGED, AND WHAT IT DELIBERATELY DID NOT ─────────────────────────────────────────
--
-- The ▲▼ arrows are gone (anti-pattern #75, options-ui-§18): the cascade is dragged now, through
-- LibKa0s-Widgets-1.0's shared ReorderList. That needed a REAL FRAME per row — the widget anchors
-- its handle to it, fades it to 0.35 while it is carried, and draws the bounded box behind it — so
-- each slot is a Frame with its FontStrings parented to it instead of eleven sets of regions on one
-- host. THE POOLING IS UNCHANGED: the slots are still created once and repainted in place, which is
-- the whole reason this page does not freeze the client.
--
-- The host draws NO row background and NO row border. The library owns both now, and a host copy
-- beside them is double chrome (options-ui-§18). It never had one, so there was nothing to delete.

-- THESE THREE BLIZZARD PATHS ARE THE FALLBACK RUNG, NOT THE ART. LibKa0s-Media ships all three
-- marks — `circle-check`, `ban` and `info` — so the catalog is what draws on a working
-- install and these are what the ladder walks down to when the library is absent, exactly as
-- every other art site in this addon does (core/MediaSetup.lua). They are spelled out rather
-- than deleted because NS.Icon answers nil twice over — no library, or no such name — and a
-- nil spliced into a `|T` escape is not a blank square, it is a swallowed escape.
local READY     = "Interface\\RaidFrame\\ReadyCheck-Ready"      -- fallback for `circle-check`
local NOTREADY  = "Interface\\RaidFrame\\ReadyCheck-NotReady"   -- fallback for `ban`
local INFO_ICON = "Interface\\FriendsFrame\\InformationIcon"    -- fallback for `info`

-- Shared column x-offsets, in px from each ROW's content origin — which is the far side of the drag
-- handle's gutter, not the row's left edge: the handle owns a fixed-width gutter at the far left and
-- row contents start beyond it (options-ui-§18). Headers and every cell add the same gutter, so the
-- columns line up: [handle] [tick] [Addon] [Price Module] [On ☑] [Status]. The ⓘ is NOT a fixed
-- column — it trails each row's Price Module text (positioned per-row in the refresh).
--
-- The old `order` column is gone with the arrows it held.
local ACOL = { tick = 2, addon = 26, module = 148, enabled = 330, status = 362 }
local AROW_H, AHEAD_H = 22, 32   -- row pitch; AHEAD_H = header→first-row gap (roomy header band)
local HEAD_Y = -8                -- header baseline inside the host (gap above the header)
local GOLD_RGB = { 0.91, 0.77, 0.42 }
-- Status colors: collecting = green, not collecting = yellow, not installed = red.
--
-- SATURATED, NOT MUTED, and that is a correction rather than a preference. These read
-- {0.46,0.60,0.46} / {0.66,0.62,0.42} / {0.62,0.45,0.45} and the comment above them called them
-- "extremely muted" approvingly -- but desaturated that far, on this panel's near-black backdrop,
-- the three are three shades of grey-brown, and being legible at a glance is the entire job of a
-- status column.
--
-- The reference is the collection's own marks: ConsumableMaster's legend draws Blizzard's
-- ReadyCheck-Ready, ReadyCheck-NotReady and FavoritesIcon, which are vivid because the ART is
-- vivid. This column tints WHITE catalog art instead, so the saturation has to come from here; a
-- muted tint on white art just yields a muted mark.
--
-- These carry TWICE -- the Status column's text color, and the tick marks below, whose tint is
-- baked into the |T escape because an inline texture is not reached by SetTextColor. A value
-- changed here moves both, which is the point of their being one table.
local STATUS_RGB = {
  collecting    = { 0.30, 0.95, 0.35 },
  notcollecting = { 1.00, 0.82, 0.10 },
  notinstalled  = { 1.00, 0.32, 0.32 },
}

-- The tick column's two states, built ONCE at file load the way modules/BrowserTable.lua builds
-- its sort arrows — the row loop repaints pooled slots on every refresh and has no business
-- reformatting a constant string each time.
--
-- THE TINT IS LOAD-BEARING, and it is why these are NS.IconMarkup calls rather than bare paths.
-- Catalog art is white by contract (the shape lives entirely in the alpha channel), and white is
-- not a status: green-means-collecting / red-means-not is the whole signal this column carries.
-- An inline texture is drawn white and is NOT reached by the FontString's SetTextColor, so the
-- tint has to be baked into the escape's own vertex fields. On the fallback rung it multiplies
-- Blizzard's already-green tick by a green and its already-red mark by a red, so a degraded
-- install still reads green-or-red, a shade darker.
local TICK_ON  = NS.IconMarkup("circle-check", READY, 16,
  STATUS_RGB.collecting[1], STATUS_RGB.collecting[2], STATUS_RGB.collecting[3])
local TICK_OFF = NS.IconMarkup("ban", NOTREADY, 16,
  STATUS_RGB.notinstalled[1], STATUS_RGB.notinstalled[2], STATUS_RGB.notinstalled[3])

--- The handle gutter, READ off the library rather than restated (options-ui-§8/§18).
---
--- Zero without the library, and that is the honest answer rather than a fallback constant: the
--- degraded path draws no handle at all, so reserving a gutter for it would indent every column
--- past nothing.
local function handleGutter()
  local box = NS.ReorderRowBox and NS.ReorderRowBox()
  return (box and box.HANDLE_W) or 0
end

-- Human name for the addon behind a "provider:key" tag (e.g. "auctionator:minbuyout" → "Auctionator").
local function providerNameOf(tag)
  local prov = tag:match("^(.-):")
  return (prov and NS.Constants.AUCTION_PROVIDER_NAMES[prov]) or prov or tag
end

-- Short data-point label for a "provider:key" tag (the `data` column form from AUCTION_KEYS).
local function dataLabelOf(tag)
  local prov, key = tag:match("^(.-):(.+)$")
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do
    if k.provider == prov and k.key == key then return k.data or k.label end
  end
  return key or tag
end

-- Label/desc for a tag's ⓘ tooltip.
local function keyMetaOf(tag)
  local prov, key = tag:match("^(.-):(.+)$")
  for _, k in ipairs(NS.Constants.AUCTION_KEYS) do
    if k.provider == prov and k.key == key then return k.label, k.desc end
  end
  return tag, nil
end

-- GameTooltip on hover, shared by the ⓘ buttons. `getTitle`/`getBody` are read on enter so a reused
-- slot always shows its current tag's text.
local function tipScripts(btn, getTitle, getBody)
  btn:SetScript("OnEnter", function()
    if not GameTooltip then return end
    local title = getTitle and getTitle()
    if not title or title == "" then return end
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    local body = getBody and getBody()
    if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

--- Release the live reorder controller, if there is one.
---
--- CALLED AT THE TOP OF THE PAGE RENDER, before the first widget is created — not merely before the
--- list is rebuilt. Handles and row boxes are POOLED, and releasing one is what takes it off the
--- host frame it was parented to; that frame goes back to AceGUI's pool the moment ClearScroll runs,
--- so a Cancel that ran afterwards would be reclaiming chrome from a widget that already belongs to
--- something else. This is the single most common way an adoption of this widget goes wrong
--- (options-ui-§18), so it is a named function called from exactly two places rather than a line
--- someone can move.
local function cancelReorder(ctx)
  local list = ctx._priList
  ctx._priList = nil
  if list then list:Cancel() end
end

-- Re-partition the tags into three groups and repaint the reused row slots. Group order (each keeps
-- the natural priority-array order within it): Collecting → Not collecting → Addon not installed.
-- Only the Collecting group (top) is draggable, and `boundary` is what stops a drag leaving it.
local function refreshAuctionTable(ctx)
  local rows = ctx._priRows
  if not rows then return end
  local hf = ctx._priHost
  local priority = NS.AuctionPrice:ReconcilePriority()
  local capture = NS.db.global.settings.auction.capture or {}

  local collecting, notCollecting, notInstalled = {}, {}, {}
  for _, tag in ipairs(priority) do
    local prov = tag:match("^(.-):")
    if not NS.AuctionPrice:IsProviderAvailable(prov) then notInstalled[#notInstalled + 1] = tag
    elseif capture[tag] then collecting[#collecting + 1] = tag
    else notCollecting[#notCollecting + 1] = tag end
  end
  local order = {}
  for _, t in ipairs(collecting)    do order[#order + 1] = t end
  for _, t in ipairs(notCollecting) do order[#order + 1] = t end
  for _, t in ipairs(notInstalled)  do order[#order + 1] = t end
  local nActive = #collecting

  -- A repaint is a NEW controller: it holds the rows of the pass that built it (the library says so
  -- in as many words), and the old one is describing a partition that no longer exists. Safe here
  -- without the top-of-render rule above, because a repaint creates no AceGUI widget and releases
  -- none — the handles go back to the pool and come straight out of it again.
  cancelReorder(ctx)
  local list = NS.MakeReorderList{
    stride   = AROW_H,
    boundary = nActive,
    handleTooltip = "Drag to re-rank",
    -- ONE WRITE, not a run of adjacent swaps. `from`/`to` are display indices, and the collecting
    -- group occupies display slots 1..nActive, so they are indices into `collecting` directly.
    onMove = function(from, to)
      NS.AuctionPrice:MovePriorityWithin(collecting, from, to)
      runRebuilders(ctx)
    end,
  }
  ctx._priList = list

  for i, tag in ipairs(order) do
    local r = rows[i]
    local prov = tag:match("^(.-):")
    local avail = NS.AuctionPrice:IsProviderAvailable(prov)
    local on = capture[tag] and true or false
    local live = on and avail          -- collecting right now
    r._tag = tag

    r.tick:SetText(live and TICK_ON or TICK_OFF)

    -- Addon name: no per-provider color any more — just near-white, dimmed when inactive.
    r.addon:SetText(providerNameOf(tag))
    local ag = live and 0.86 or 0.5
    r.addon:SetTextColor(ag, ag, ag)

    local mg = live and 0.9 or 0.5
    r.module:SetText(dataLabelOf(tag)); r.module:SetTextColor(mg, mg, mg)
    -- ⓘ trails the Price Module text with a small gap (per-row, since the text width varies).
    local mw = r.module:GetStringWidth() or 0
    r.info:ClearAllPoints()
    r.info:SetPoint("LEFT", r.frame, "LEFT", r._gutter + ACOL.module + mw + 6, 0)

    local sc = (not avail) and STATUS_RGB.notinstalled
      or (on and STATUS_RGB.collecting or STATUS_RGB.notcollecting)
    r.status:SetText((not avail) and "Addon not installed" or (on and "Collecting data" or "Not collecting data"))
    r.status:SetTextColor(sc[1], sc[2], sc[3])

    r.info.tex:SetVertexColor(live and 1 or 0.55, live and 1 or 0.55, live and 1 or 0.55)

    -- Enabled box: checked only when actually collecting (an uninstalled source reads unchecked),
    -- and non-interactive when the addon isn't present.
    r.check:SetValue(live)
    r.check:SetDisabled(not avail)

    -- Registered in DISPLAY order, every row, draggable or not: an inert row is still a place a drag
    -- can LAND, still counts for the index arithmetic, and still wants the bounded box — a stack
    -- where only some rows have an edge reads as a rendering fault rather than as a rule.
    if list then
      list:AddRow(r.frame, {
        draggable = i <= nActive,
        dimmed    = i > nActive,
        ghostText = providerNameOf(tag) .. " — " .. dataLabelOf(tag),
      })
    end
  end

  if list then list:Finish(hf) end
end

-- Build the unified AH Price table: gold left-aligned column headers and 11 reusable row slots (one
-- per known price source). Slots + their frames are created ONCE here; refreshAuctionTable repaints
-- them in place on every enable-toggle / drag / Defaults, so no frame is ever re-allocated. Native
-- FontStrings carry all text; only the checkbox, the ⓘ and the library's handle are frames.
--
-- THE HOST IS A RAW FRAME THIS ADDON OWNS FOR THE SESSION, not an AceGUI child. That is the whole of
-- how the pooling survives a tab strip: the tab body is re-rendered on every click, and ClearScroll
-- hands every AceGUI child back to the pool — which would orphan eleven slots of raw FontStrings
-- parented to a SimpleGroup and put the ~1.7s freeze back. So the host is created once, parked on
-- the panel while another tab is on screen, and RE-PARENTED to a fresh full-width placeholder each
-- time this tab is drawn. Nothing is ever allocated twice and nothing is ever released.
local function buildAuctionTable(ctx)
  local scroll = O.EnsureScroll(ctx)
  if not scroll then return end

  local descLabel = NS.AceGUI:Create("Label")
  descLabel:SetFullWidth(true)
  descLabel:SetText("Tick a source to collect its price at loot time; ticked sources are ranked "
    .. "top-to-bottom (drag by the handle) and the highest-ranked one you have a price for is the "
    .. "value shown. Sources you don't collect, or whose addon isn't installed, drop to the bottom.")
  scroll:AddChild(descLabel)
  O.AddSpacer(scroll, 8)

  local N = #NS.Constants.AUCTION_KEYS
  local placeholder = NS.AceGUI:Create("SimpleGroup")
  placeholder:SetLayout(nil); placeholder:SetFullWidth(true)
  placeholder:SetHeight(AHEAD_H + AROW_H * N + 8)
  scroll:AddChild(placeholder)

  local hf = ctx._priHost
  if not hf then
    hf = CreateFrame("Frame", nil, ctx.panel)
    ctx._priHost = hf
  end
  hf:SetParent(placeholder.frame)
  hf:ClearAllPoints()
  hf:SetAllPoints(placeholder.frame)
  hf:Show()

  if not ctx._priRows then
    local gutter = handleGutter()

    -- Gold, left-aligned column headers at the shared offsets (a roomy band above the first row).
    local function header(x, text)
      local fs = hf:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
      fs:SetPoint("TOPLEFT", hf, "TOPLEFT", gutter + x, HEAD_Y); fs:SetJustifyH("LEFT")
      fs:SetText(text); fs:SetTextColor(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3])
    end
    header(ACOL.addon, "Addon"); header(ACOL.module, "Price Module")
    header(ACOL.enabled, "On"); header(ACOL.status, "Status")

    -- Reusable row slots (created once). Each is a real Frame, because that is what ReorderList
    -- anchors its handle and its bounded box to and what it fades while the row is carried; the
    -- cells inside it are FontStrings plus the ⓘ and an AceGUI checkbox.
    local rows = {}
    for i = 1, N do
      local rf = CreateFrame("Frame", nil, hf)
      rf:SetPoint("TOPLEFT",  hf, "TOPLEFT",  0, -(AHEAD_H + (i - 1) * AROW_H))
      rf:SetPoint("TOPRIGHT", hf, "TOPRIGHT", 0, -(AHEAD_H + (i - 1) * AROW_H))
      rf:SetHeight(AROW_H)
      local r = { frame = rf, _gutter = gutter }

      local function fs(x)
        local f = rf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        f:SetPoint("LEFT", rf, "LEFT", gutter + x, 0); f:SetJustifyH("LEFT"); return f
      end
      r.tick = fs(ACOL.tick); r.addon = fs(ACOL.addon)
      r.module = fs(ACOL.module); r.status = fs(ACOL.status)

      local info = CreateFrame("Button", nil, rf)
      info:SetSize(16, 16)
      info:SetPoint("LEFT", rf, "LEFT", gutter + ACOL.module, 0)   -- repositioned per row
      local itex = info:CreateTexture(nil, "ARTWORK"); itex:SetAllPoints()
      -- White catalog art is what the per-row SetVertexColor below wants: it dims the mark to 0.55
      -- for an inactive row, and a multiply only reads as "dimmed" against white.
      itex:SetTexture((NS.Icon and NS.Icon("info")) or INFO_ICON)
      info.tex = itex; r.info = info
      tipScripts(info, function() return (keyMetaOf(r._tag or "")) end,
                       function() return (select(2, keyMetaOf(r._tag or ""))) end)

      -- AceGUI CheckBox (the standard gold-tick control used across the panel) rather than a raw
      -- UICheckButtonTemplate — the template left a scaling artifact at this size. Parented to the
      -- ROW, never added as a scroll child, so ClearScroll cannot reclaim it either.
      local cb = NS.AceGUI:Create("CheckBox")
      cb:SetLabel("")
      cb.frame:SetParent(rf); cb.frame:ClearAllPoints()
      cb.frame:SetPoint("LEFT", rf, "LEFT", gutter + ACOL.enabled, 0); cb.frame:SetWidth(26)
      cb.frame:Show()
      cb:SetCallback("OnValueChanged", function(_, _, val)
        local tag = r._tag
        if not tag then return end
        local src = NS.Schema:Get("settings.auction.capture") or {}
        local c = {}
        for k, v in pairs(src) do c[k] = v end
        c[tag] = val or nil
        NS.Schema:Set("settings.auction.capture", c)
        runRebuilders(ctx)
      end)
      r.check = cb

      rows[i] = r
    end
    ctx._priRows = rows
  end

  -- REGISTERED ON EVERY RENDER, not only on the pass that built the slots. renderGeneral reassigns
  -- ctx.rebuilders each time (ClearScroll reassigns the library's refreshers beside it), so a
  -- rebuilder added once inside the build branch above would be dropped the first time the reader
  -- left this tab and came back — and with it the repaint every enable-toggle and every drag needs.
  ctx.rebuilders[#ctx.rebuilders + 1] = function() refreshAuctionTable(ctx) end

  refreshAuctionTable(ctx)   -- first paint, and every later paint of this tab
end
-- ── Landing page: logo + tagline + slash-command list ───────────────────────────
local function buildMainContent(ctx)
  local scroll = O.EnsureScroll(ctx)

  local logoGroup = NS.AceGUI:Create("SimpleGroup")
  logoGroup:SetLayout(nil); logoGroup:SetFullWidth(true); logoGroup:SetHeight(LOGO_SIZE)
  local tex = logoGroup.frame:CreateTexture(nil, "ARTWORK")
  tex:SetTexture(LOGO_PATH)
  tex:SetSize(LOGO_SIZE, LOGO_SIZE)
  tex:SetPoint("TOPLEFT", logoGroup.frame, "TOPLEFT", 0, 0)
  scroll:AddChild(logoGroup)
  O.AddSpacer(scroll, 8)

  local desc = NS.AceGUI:Create("Label")
  desc:SetFullWidth(true); desc:SetText(ADDON_TAGLINE)
  if desc.label and desc.label.SetFontObject and _G.GameFontHighlight then
    desc.label:SetFontObject(_G.GameFontHighlight)
  end
  scroll:AddChild(desc)
  O.AddSpacer(scroll, 12)

  local heading = NS.AceGUI:Create("Heading")
  heading:SetFullWidth(true); heading:SetHeight(O.SECTION_HEADING_H); heading:SetText("Slash Commands")
  if heading.label and heading.label.SetFontObject and _G.GameFontNormalLarge then
    heading.label:SetFontObject(_G.GameFontNormalLarge)
  end
  scroll:AddChild(heading)
  O.AddSpacer(scroll, 6)

  -- CONVERGENCE (LibKa0s adoption). This page used to carry its OWN command-row formatter — double
  -- spaces around the em dash, the dash explicitly white-wrapped, the description left bare — while
  -- settings/Slash.lua two files away already rendered the same data another way. Both now go
  -- through lib.FormatRow: single spaces, no color span on the dash, the description white.
  -- Deliberate and user-visible; do not "fix" it back. See closed issue #24 (LIBKA0S-09).
  for _, line in ipairs(NS.Slash.LandingRows and NS.Slash:LandingRows() or {}) do
    local labelRow = NS.AceGUI:Create("Label")
    labelRow:SetFullWidth(true)
    labelRow:SetText(line)
    scroll:AddChild(labelRow)
  end
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
--   Capture         — the muted-source picker. The `settings.excludedSources` row it represents is
--                     walked by the generic path and produces no widget (type = "table"; see
--                     makeMultiCheck above), so this lands exactly where that path would have put
--                     it: after the group's last row, on a fresh line.
--   AH Price        — the pooled price-source table, under the "Price sources" subsection heading
--                     the `settings.auction.capture` row declares.
--   History         — the storage readout and "Purge history…".
--
-- afterGroup is the ONLY seam that survives a tab click: the strip's onSelect re-enters the page
-- renderer, and while that does re-run this file, a block appended after the rows would land at the
-- BOTTOM of every tab rather than inside the one it belongs to.
local AFTER_GROUP = {
  ["Capture"] = function(ctx)
    local row = NS.Schema:FindRow("settings.excludedSources")
    local scroll = O.EnsureScroll(ctx)
    if row and scroll then makeMultiCheck(ctx, row, scroll) end
  end,
  ["AH Price"]   = buildAuctionTable,
  ["History"] = renderHistory,
}
AFTER_GROUP[NS.Schema.MASTER_GROUP] = NS.Schema.MasterAfterGroup

-- ── The General page's strip ────────────────────────────────────────────────────
--
-- ONE page now. Filters and AH Price were canvas sub-pages of their own until R6 deprecated them
-- into General: three pages, each with its own strip, made a player hunt for which of the three
-- held the setting they wanted, and one of the three (AH Price) drew no strip at all.
--
-- THE STRIP IS DRAWN BY HAND rather than by O.RenderTabbedSchema, and the reason is that two of the
-- six tabs hold no schema rows to partition. RenderTabbedSchema derives its tab list from `group`,
-- which is exactly right for a page whose every section is rows — and cannot name a tab whose body
-- is a dynamic list of item ids. So the tab list is declared here, each entry is either a schema
-- GROUP (rendered by the same O.RenderRows call the library would have made, `noHeadings` and all)
-- or a `build` function, and tests/test_panel.lua pins the two against each other so a group added
-- to the schema and not to this list cannot go unnoticed.
-- THE NAMES AND THE ORDER ARE SHARED WITH KA0S BANK LEDGER, whose strip is these six minus AH
-- Price: Master controls, Capture, Interface, History, Filters. The two addons keep the same shape
-- of record and a player compares their panels directly, so one subject carries one name across
-- both — Collection became Capture, Maintenance became History, and Filters moved from third to
-- last so the five shared tabs sit in the shared order. AH Price is this addon's alone and goes
-- directly after Capture, which is the tab it qualifies: it prices what capture recorded.
--
-- A tab name is a `group`, never a stored path, so the convergence was a rename throughout and
-- carried no migration (options-ui-§15).
local GENERAL_TABS = {
  -- options-ui-§15: the FIRST tab, under that exact name, in every Ka0s addon.
  { key = "Master controls" },
  { key = "Capture" },
  { key = "AH Price" },
  { key = "Interface" },
  { key = "History" },
  { key = FILTERS_TAB, build = buildFiltersTab },
}

--- The rows of one schema group, in declaration order.
local function rowsOfGroup(group)
  local out = {}
  for _, row in ipairs(NS.Schema.Schema) do
    if row.page == "General" and row.group == group then out[#out + 1] = row end
  end
  return out
end

-- ── Renderers ───────────────────────────────────────────────────────────────────
--
-- Each is declared through O.SetRenderer, which owns WHEN it runs: the page's first show, and again
-- after a structural refresh marked it dirty while hidden. Every one starts by releasing the
-- previous render's children, because a renderer the library may re-run must be idempotent.

-- No banner (options-ui-§14): this addon is account-wide — every path resolves against db.global
-- and there is no profile, no per-window state and nothing for a banner to be a picker FOR. It
-- draws no page-header block either: nothing on this page applies to every tab.
local function renderGeneral(ctx)
  -- FIRST, before ClearScroll and before the first widget of the new pass exists. The reorder
  -- controller's handles and boxes are pooled and are parented to frames ClearScroll is about to
  -- hand back to AceGUI (options-ui-§18).
  cancelReorder(ctx)
  -- The pooled price host is this addon's own frame and is NOT released by ClearScroll, so it has
  -- to be taken off the placeholder it was anchored to by hand — otherwise it stays visible over
  -- whichever tab is drawn next, and its anchor rides a placeholder that has gone back to the pool.
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
  for i, tab in ipairs(GENERAL_TABS) do tabs[i] = { key = tab.key, label = tab.key } end
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
        -- `noHeadings`, exactly as RenderTabbedSchema renders an active tab: under a strip the tab
        -- IS the group's heading. A row's `subgroup` is NOT suppressed by it, which is what gives
        -- the AH Price tab its two subsection headings.
        O.RenderRows(ctx, rowsOfGroup(tab.key), AFTER_GROUP, nil, { noHeadings = true })
      end
    end
  end

  if ctx.scroll and ctx.scroll.DoLayout then ctx.scroll:DoLayout() end
end

function P.BuildMain(ctx)
  O.ClearScroll(ctx)
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
--- It therefore covers what the Filters and AH Price pages' own Defaults buttons used to:
---
---   * every schema row plus the three id-lists          — Slash:CliResetAll
---   * the auction cascade, a carve-out array with no schema row that the walk cannot see
---
--- It does NOT recentre the window any more. That was folded in here when there was nowhere else to
--- put it; "Reset position" is a real button on the Master controls tab now, and a player asking for
--- defaults no longer gets their window moved as a side effect (options-ui-§12/§15).
function P:RestoreDefaults()
  if NS.Slash and NS.Slash.CliResetAll then NS.Slash:CliResetAll() end
  -- Clear-and-refill the SAME table so the price table's closures see the new contents.
  if NS.AuctionPrice and NS.AuctionPrice.GetPriority then
    local p = NS.AuctionPrice:GetPriority()
    for i = #p, 1, -1 do p[i] = nil end
    for i, tag in ipairs(NS.Constants.AUCTION_PRIORITY_DEFAULT) do p[i] = tag end
  end
  P:Refresh()
  -- Structural as well as scalar: the price table repaints off the cascade, and the id-lists off
  -- their rebuilders, neither of which a refresher sweep touches.
  if P.general then O.RefreshPanel(P.general, true) end
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

  -- ONE sub-page. Filters and AH Price were sub-pages of their own until R6 folded them into
  -- General's strip; their bodies are unchanged and their two registrations are gone.
  O.RegisterOptionsPage("General", "General", function(mainCategory)
    local ctx = O.CreatePanel(nil, "General", { pageKey = "General", defaultsButton = true })
    P.general = ctx
    ctx.rebuilders = {}
    ctx.panel.defaultsOnClick = function() P:RestoreDefaults() end
    O.SetRenderer(ctx, renderGeneral)
    Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "General")
  end)

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
