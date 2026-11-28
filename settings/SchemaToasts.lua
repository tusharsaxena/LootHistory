local _, NS = ...
NS.SchemaToasts = NS.SchemaToasts or {}
local ST = NS.SchemaToasts
local C = NS.Constants
-- Load-time reads: settings/OptionsSetup.lua (the composers) and defaults/ load above this file, and
-- settings/Schema.lua below it appends ST.Rows() before its runtime is built (LootHistory.toc).
local O = NS.Options
local PD = NS.defaults.profile

-- The Toasts page's rows (#38, toast spec docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md
-- §9.3). ONE ROW PER FEED AND SETTING: feedRows(fid) emits the same leaves, in the same order, for
-- each of the three fixed feeds (T15), stored at `settings.toasts.feeds.<fid>.<leaf>` and stamped
-- `feed = fid`. The page's banner picks a feed (session state, settings/PanelToasts.lua) and the
-- descriptor's rowsForPage keeps only that feed's rows (settings/OptionsSetup.lua), so the CLI, the
-- resets and the Defaults reach every feed as ordinary rows. One page-wide row (no `feed`) closes the
-- set: hiding Blizzard's alert toasts, drawn under every feed's Behavior tab.
--
-- `group` is the TAB (options-ui-§13): General, Content, Style, Motion, Behavior. Every row's default
-- READS defaults/Profile.lua (savedvariables-§2), and every write sends SETTINGS_CHANGED `toasts`,
-- which the gain feed, the feeds and the alert hiding all hear.
--
-- COMPOSED BLOCKS (options-ui-§16/§17): the background swatch and the gradient end are O.ColorPair,
-- the border O.BorderGroup on the bar family, the text O.FontGroup with From skin flags. Each color
-- a skin describes carries its `<key>FromSkin` companion. The kind colors are a palette (one color
-- per kind, options-ui-§17's exemption): a swatch and a From skin companion, no class color. No
-- color swatch is ever disabled (anti-pattern #74).

local PAGE = "Toasts"
ST.PAGE = PAGE
ST.TABS = { "General", "Content", "Style", "Motion", "Behavior" }

local function changed()
  if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "toasts") end
end

local function prefix(fid) return "settings.toasts.feeds." .. fid .. "." end
ST.Prefix = prefix

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

--- The shipped default of `leaf` (dotted) on feed `fid`, a copy for a table.
local function default(fid, leaf)
  local v = PD.settings.toasts.feeds[fid]
  for part in leaf:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return copy(v)
end

-- The host's widget word, declarative (docs/schema.md): a media picker, a dropdown, else by type.
local WIDGET = { bool = "CheckBox", number = "Slider", string = "EditBox", color = "ColorPicker", table = "MultiCheck" }
local function widgetOf(row)
  if row.dialogControl and row.dialogControl ~= "EditBox" then return "MediaPicker" end
  if row.values then return "Dropdown" end
  return WIDGET[row.type]
end

--- Every field a Toasts row shares, stamped onto a hand-written or a composed row alike.
local function finish(row, fid)
  row.page = PAGE
  row.feed = fid
  row.onChange = row.onChange or changed
  row.widget = row.widget or widgetOf(row)
  return row
end

local function sounds()
  local lsm = O.LSMValues("sound")
  return function()
    local out = { [""] = "None" }
    for k, v in pairs(lsm() or {}) do out[k] = v end
    return out
  end
end

-- ── the per-feed builder ─────────────────────────────────────────────────────────────────────

--- One hand-written row of feed `fid`: `spec` carries the leaf and the row's own fields.
local function row(fid, group, subgroup, leaf, spec)
  spec.path = prefix(fid) .. leaf
  spec.default = default(fid, leaf)
  spec.group, spec.subgroup = group, subgroup
  return finish(spec, fid)
end

local function add(out, rows, fid)
  for _, r in ipairs(rows) do out[#out + 1] = finish(r, fid) end
end

local function generalRows(out, fid)
  local P = prefix(fid)
  local function r(sub, leaf, spec) out[#out + 1] = row(fid, "General", sub, leaf, spec) end
  r(nil, "enabled", { type = "bool", label = "Enable this feed",
    tooltip = "Show this feed. Off, it draws nothing, and gains it would show are not watched for it." })
  r("Placement", "slot", { type = "string", values = C.TOAST_SLOT_OPTIONS, solo = true, label = "Screen slot",
    tooltip = "One of nine places on screen; the nudge moves it from there. Picking a slot sets its growth "
      .. "direction and clears the nudge.",
    onChange = function(v)
      local grow = C.TOAST_SLOT_GROW[v]
      if grow and NS.Schema and NS.Schema.SetMany then
        NS.Schema:SetMany({ { path = P .. "grow", value = grow }, { path = P .. "x", value = 0 },
                            { path = P .. "y", value = 0 } })
      end
      changed()
    end })
  local nudge = "Pixels from the slot. Dragging the unlocked feed writes this."
  r("Placement", "x", { type = "number", min = -C.TOAST_NUDGE_MAX, max = C.TOAST_NUDGE_MAX, step = 1,
    label = "Nudge X", tooltip = nudge })
  r("Placement", "y", { type = "number", min = -C.TOAST_NUDGE_MAX, max = C.TOAST_NUDGE_MAX, step = 1,
    label = "Nudge Y", tooltip = nudge })
  r("Placement", "grow", { type = "string", values = C.TOAST_GROW_OPTIONS, label = "Grow",
    tooltip = "Which way older toasts move as new ones arrive. The newest is always nearest the slot." })
  r("Placement", "align", { type = "string", values = C.TOAST_SIDE_OPTIONS, label = "Text alignment",
    tooltip = "Left is the default. Right flips each line." })
  r("Placement", "iconSide", { type = "string", values = C.TOAST_SIDE_OPTIONS, label = "Icon side",
    tooltip = "Left is the default." })
end

-- The kind toggles, in the settings order (C.TOAST_KIND_KEYS' leaves), with their labels.
local KINDS = {
  { "item", "Items" }, { "money", "Money" }, { "currency", "Currencies" }, { "reputation", "Reputation" },
  { "appearance", "Appearances" }, { "xp", "Experience" }, { "skill", "Skill-ups" },
}
local APPEARANCE_CLIENTS = C.FEATURE_CLIENTS.appearances

-- The four highlights: leaf, label, tooltip, Retail only.
local HIGHLIGHTS = {
  { "mount", "Mounts", "Glow on a mount you loot." },
  { "legendary", "Legendaries", "Glow on a legendary item." },
  { "upgrade", "Upgrades", "An item above what you wear in its slot, of an armor type you wear." },
  { "appearance", "New appearances", "Glow on an item whose appearance you do not have yet.", true },
}

local function contentRows(out, fid)
  local P = prefix(fid)
  local function r(sub, leaf, spec) out[#out + 1] = row(fid, "Content", sub, leaf, spec) end
  for _, k in ipairs(KINDS) do
    r("Kinds on this feed", "kinds." .. k[1], { type = "bool", label = k[2],
      tooltip = "Show " .. k[2]:lower() .. " on this feed.",
      clients = k[1] == "appearance" and APPEARANCE_CLIENTS or nil })
  end
  r("Details", "price", { type = "string", values = C.TOAST_PRICE_OPTIONS, solo = true, label = "Prices",
    tooltip = "The value line on item toasts. AH needs a pricing addon. Highest is the larger of the two.",
    shownWhen = { path = P .. "kinds.item", equals = true } })
  r("Details", "ilvl", { type = "bool", label = "Item level badge",
    tooltip = "Draw the item level over the icon of gear." })
  r("Details", "counts", { type = "bool", label = "Counts",
    tooltip = "How many you now hold in your bags, bank and warband bank." })
  r("Details", "source", { type = "bool", label = "Source tag",
    tooltip = "Where the gain came from: a kill, a quest, a vendor." })
  r("Details", "minQuality", { type = "number", values = C.QUALITY_OPTIONS, label = "Minimum quality",
    tooltip = "Items below this never toast here. Recording is not changed." })
  -- Host-drawn (settings/PanelToasts.lua, the Details subsection's afterSubgroup hook), the same set
  -- picker as settings.excludedSources: type = "table" draws nothing on the generic path. LAST of
  -- its subsection, so the hook lands it where the row would sit.
  local hide = row(fid, "Content", "Details", "hideSources", { type = "table", widget = "MultiCheck",
    wide = true, invert = false, values = C.SOURCE_OPTIONS, label = "Hide sources",
    tooltip = "Gains from a ticked source never toast on this feed. Recording is not changed." })
  hide.default = {}
  out[#out + 1] = hide
  local snd = sounds()
  for _, h in ipairs(HIGHLIGHTS) do
    local clients = h[4] and APPEARANCE_CLIENTS or nil
    r("Highlights and sounds", "hl." .. h[1], { type = "bool", label = h[2], tooltip = h[3], clients = clients })
    r("Highlights and sounds", "hl." .. h[1] .. "Sound", { type = "string", dialogControl = "Ka0sMedia_Sound",
      values = snd, label = "Sound", clients = clients,
      tooltip = "Played when this highlight shows, at most once a second per feed. None plays nothing.",
      shownWhen = { path = P .. "hl." .. h[1], equals = true } })
  end
end

--- The leaf -> shipped default map the composers take, for the leaves named.
local function defaultsOf(fid, leaves)
  local d = {}
  for _, leaf in ipairs(leaves) do d[leaf] = default(fid, leaf) end
  return d
end

local function backgroundRows(out, fid)
  local P = prefix(fid)
  local base = { prefix = P, page = PAGE, group = "Style", subgroup = "Background" }
  local function spec(over)
    local s = {}
    for k, v in pairs(base) do s[k] = v end
    for k, v in pairs(over) do s[k] = v end
    return s
  end
  add(out, O.ColorPair(spec{ key = "bgColor", label = "Background color",
    defaults = defaultsOf(fid, { "bgColor", "useClassColorBgColor", "bgColorFromSkin" }),
    extra = { { path = P .. "bgType", type = "string", values = C.TOAST_BG_TYPE_OPTIONS, label = "Type",
      default = default(fid, "bgType"), disabledIf = P .. "bgColorFromSkin",
      tooltip = "How the background is filled. Not read while Use the skin's color is on." } } }), fid)
  -- The gradient's second stop: a swatch of its own, so its own class companion (options-ui-§17).
  -- No From skin companion: the first one rules the whole fill (LibKa0s-Feed-1.0's style).
  local gradient = { path = P .. "bgType", equals = "gradient" }
  local second = O.ColorPair(spec{ key = "bgColor2", label = "Gradient end color", fromSkin = false,
    defaults = defaultsOf(fid, { "bgColor2", "useClassColorBgColor2" }) })
  for _, r in ipairs(second) do r.shownWhen = gradient end
  add(out, second, fid)
  out[#out + 1] = row(fid, "Style", "Background", "bgTexture", { type = "string",
    dialogControl = "Ka0sMedia_Background", values = O.LSMValues("background"), label = "Texture",
    tooltip = "The background texture.", shownWhen = { path = P .. "bgType", equals = "texture" } })
end

local function styleRows(out, fid)
  local P = prefix(fid)
  backgroundRows(out, fid)
  add(out, O.BorderGroup{ prefix = P, fromSkin = "bar", page = PAGE, group = "Style", subgroup = "Border",
    defaults = defaultsOf(fid, { "borderStyle", "borderSize", "borderColor", "useClassColorBorder",
      "borderStyleFromSkin", "borderColorFromSkin" }),
    extra = { { path = P .. "borderByQuality", type = "bool", label = "Use the quality color",
      default = default(fid, "borderByQuality"),
      tooltip = "Item and currency toasts take their quality's color; it wins over the class color." } } }, fid)
  add(out, O.FontGroup{ prefix = P, fromSkin = true, flagsFromSkin = true, page = PAGE, group = "Style",
    subgroup = "Text",
    defaults = defaultsOf(fid, { "font", "fontSize", "fontColor", "useClassColorFont", "fontFlags", "fontShadow",
      "fontFromSkin", "fontColorFromSkin", "fontShadowFromSkin" }),
    extra = { { path = P .. "fontSize2", type = "number", min = 8, max = 24, step = 1, label = "Secondary size",
      default = default(fid, "fontSize2"), tooltip = "Height of every line under the title, in points." } } }, fid)
  local function r(sub, leaf, s) out[#out + 1] = row(fid, "Style", sub, leaf, s) end
  r("Size", "width", { type = "number", min = 200, max = 600, step = 1, label = "Width",
    tooltip = "How wide each toast is, in pixels." })
  r("Size", "rowHeight", { type = "number", min = 24, max = 96, step = 1, label = "Row height",
    tooltip = "The least height; a toast with more lines is taller." })
  r("Size", "iconSize", { type = "number", min = 16, max = 64, step = 1, label = "Icon size",
    tooltip = "The icon's edge, in pixels." })
  r("Size", "padding", { type = "number", min = 0, max = 16, step = 1, label = "Padding",
    tooltip = "Space inside each toast, in pixels." })
  r("Size", "gap", { type = "number", min = 0, max = 20, step = 1, label = "Gap",
    tooltip = "Space between toasts, in pixels." })
  for _, k in ipairs({ { "xp", "Experience" }, { "rep", "Reputation" }, { "skill", "Skill-ups" } }) do
    r("Kind colors", "colors." .. k[1], { type = "color", hasAlpha = true, startsLine = true, label = k[2],
      tooltip = "The color of " .. k[2]:lower() .. " toasts' title. Not read while Use the skin's color is on." })
    r("Kind colors", "colors." .. k[1] .. "FromSkin", { type = "bool", label = "Use the skin's color",
      tooltip = "Draw this kind in the skin's color for it. The swatch beside it is not read while this is on." })
  end
end

local function motionRows(out, fid)
  local P = prefix(fid)
  local function r(leaf, s) out[#out + 1] = row(fid, "Motion", nil, leaf, s) end
  local entering = { path = P .. "enter", equals = { "fade", "right", "left", "up", "down" } }
  r("enter", { type = "string", values = C.TOAST_ENTER_OPTIONS, label = "Enter",
    tooltip = "How a new toast arrives." })
  r("enterTime", { type = "number", min = 0, max = 1, step = 0.05, label = "Enter time",
    tooltip = "Seconds the arrival takes.", shownWhen = entering })
  r("hold", { type = "number", min = 1, max = 30, step = 0.5, label = "Hold",
    tooltip = "Seconds a toast stays before it fades. A repeat starts it again." })
  r("fade", { type = "number", min = 0, max = 5, step = 0.1, label = "Then fade over",
    tooltip = "Seconds the fade-out takes." })
  r("pulse", { type = "bool", label = "Pulse when a count rises",
    tooltip = "A toast that takes a repeat pulses once." })
  r("timerBar", { type = "bool", label = "Countdown timer bar",
    tooltip = "A thin bar along the foot of each toast runs down until it fades." })
  r("smooth", { type = "bool", label = "Slide rows smoothly when they move",
    tooltip = "Older toasts glide to their new place instead of jumping." })
end

local function behaviorRows(out, fid)
  local function r(leaf, s) out[#out + 1] = row(fid, "Behavior", nil, leaf, s) end
  r("shown", { type = "number", min = 1, max = C.TOAST_SHOWN_MAX, step = 1, label = "Shown at once",
    tooltip = "The most toasts on screen; a new one past it drops the oldest." })
  r("merge", { type = "number", min = 0, max = 10, step = 0.5, label = "Merge repeats within",
    tooltip = "Seconds a repeat of the same gain adds to its toast. 0 turns merging off." })
  r("showInCombat", { type = "bool", label = "Show in combat",
    tooltip = "Off: gains in combat wait and show when it ends." })
  r("clickThrough", { type = "bool", label = "Click-through in combat",
    tooltip = "Toasts take no clicks while you are in combat." })
  r("pin", { type = "bool", label = "Pin a row while hovered",
    tooltip = "The whole feed holds still while the pointer is over it." })
end

--- Every row of feed `fid`, in the page's order (the order is the layout).
local function feedRows(fid)
  local out = {}
  generalRows(out, fid)
  contentRows(out, fid)
  styleRows(out, fid)
  motionRows(out, fid)
  behaviorRows(out, fid)
  return out
end
ST.FeedRows = feedRows

-- The one page-wide row: no `feed`, so every feed's Behavior tab draws it, under a heading that says
-- so (toast spec §15.2).
ST.ALERTS_SUBGROUP = "Hide Blizzard alerts (all feeds)"
local function alertRow()
  return { path = "settings.toasts.hideAlerts", default = PD.settings.toasts.hideAlerts, type = "bool",
    widget = "CheckBox", page = PAGE, group = "Behavior", subgroup = ST.ALERTS_SUBGROUP,
    label = "Loot and money alert toasts",
    tooltip = "Hide the game's own loot and money pop-ups. Turned off, or with the addon disabled, they come back.",
    onChange = changed }
end

--- The paths of feed `fid`'s Style companions, `<key>FromSkin`, read off its emitted rows: the
--- set Reset style to skin turns on (D12).
function ST.StyleCompanions(fid)
  local out = {}
  for _, r in ipairs(NS.Schema and NS.Schema.Schema or {}) do
    if r.page == PAGE and r.feed == fid and r.group == "Style" and r.type == "bool"
       and r.path:sub(-8) == "FromSkin" then
      out[#out + 1] = r.path
    end
  end
  return out
end

--- Every Toasts row: the three feeds in C.TOAST_FEEDS order, then the page-wide row. A fresh array
--- (settings/Schema.lua appends it once, at its file load).
function ST.Rows()
  local out = {}
  for _, fid in ipairs(C.TOAST_FEEDS) do
    for _, r in ipairs(feedRows(fid)) do out[#out + 1] = r end
  end
  out[#out + 1] = alertRow()
  return out
end
