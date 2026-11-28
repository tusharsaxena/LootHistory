local _, NS = ...
NS.SchemaFarm = NS.SchemaFarm or {}
local SF = NS.SchemaFarm
local C = NS.Constants
-- Load-time reads: defaults/ loads above this file, and settings/Schema.lua below it appends SF.Rows()
-- beside the Toasts rows, before its runtime is built (LootHistory.toc).
local PD = NS.defaults.profile
local GD = NS.defaults.global

-- The Farm page's rows (#39, farm spec docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §9.2;
-- D23). Two tabs, General first (options-ui-§13/§14): how the session counts and keeps, then which
-- activity lines the panel and the summary draw. Every row's default READS defaults/Profile.lua, or
-- defaults/Global.lua for the account-wide cap (savedvariables-§2), and every write sends
-- SETTINGS_CHANGED `farm`, which the companion panel, the Details window and the Farm tab repaint on.
--
-- `settings.farm.keep` is ACCOUNT-WIDE (D18, the D6 reasoning): it deletes saved sessions every
-- profile shares, so its own get/set read and write `global.farmKeep`, S.RESET_EXEMPT names it, and no
-- profile event, profile reset or page Defaults moves it. Lowering it past what is saved asks first
-- (SF.OnKeepChanged, the `S:OnRetentionChanged` / `ConfirmRetention` shape).

local PAGE = "Farm"
SF.PAGE = PAGE
SF.TABS = { "General", "Activity" }

local function farmDefault(key) return PD.settings.farm[key] end

--- The row's reaction: the session's own (Farm:OnSettingChanged re-arms the idle ticker, resumes an AFK
--- pause), then the one message the farm windows repaint on.
local function changed(leaf, v)
  if NS.Farm and NS.Farm.OnSettingChanged then NS.Farm:OnSettingChanged(leaf, v) end
  if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "farm") end
end

local function row(group, leaf, spec)
  spec.path = "settings.farm." .. leaf
  spec.page, spec.group = PAGE, group
  spec.onChange = spec.onChange or function(v) changed(leaf, v) end
  return spec
end

-- ── General ──────────────────────────────────────────────────────────────────────────────────

SF.BASIS_OPTIONS = { { value = "gross", text = "Gross" }, { value = "net", text = "Net" } }
SF.VALUE_OPTIONS = { { value = "money", text = "Money only" }, { value = "vendor", text = "Vendor value" },
  { value = "ah", text = "AH value" } }

local function generalRows(out)
  local function r(leaf, spec)
    if spec.default == nil then spec.default = farmDefault(leaf) end
    out[#out + 1] = row("General", leaf, spec)
  end
  r("headlineBasis", { type = "string", widget = "Dropdown", values = SF.BASIS_OPTIONS, label = "Headline",
    tooltip = "Whether the headline and the per-hour rate subtract costs." })
  r("headlineValue", { type = "string", widget = "Dropdown", values = SF.VALUE_OPTIONS, label = "Headline value",
    tooltip = "What the headline counts: money alone, or money plus items at vendor or AH value. AH value "
      .. "uses the vendor price for an item with no AH price." })
  r("pauseOnAFK", { type = "bool", widget = "CheckBox", label = "Pause when AFK",
    tooltip = "Stops the clock while you are flagged AFK and starts it again when the flag clears." })
  r("idleMinutes", { type = "number", widget = "Slider", min = 0, max = 30, step = 1,
    label = "Pause after idle (minutes, 0 = off)",
    tooltip = "Stops the clock after this many minutes without a gain, and takes those minutes off the "
      .. "clock. Your next gain or Resume starts it again." })
  r("showPanelOnStart", { type = "bool", widget = "CheckBox", label = "Show the panel when a session starts",
    tooltip = "Opens the farm panel each time a session starts. /lh farm shows or hides it at any time." })
  r("keep", { type = "number", widget = "Slider", min = 0, max = 500, step = 10, default = GD.farmKeep,
    label = "Sessions kept per character (0 = all)",
    tooltip = "Account-wide: shared by every profile. When a session finishes, the oldest sessions past "
      .. "this count are deleted. Lowering it asks first.",
    get = function()
      local g = NS.db and NS.db.global
      return g and g.farmKeep
    end,
    set = function(v)
      local g = NS.db and NS.db.global
      if not g then return end
      if SF._confirmed == nil then SF._confirmed = g.farmKeep end
      g.farmKeep = v
    end,
    onChange = function(v) SF.OnKeepChanged(v) end })
end

-- ── Activity (§6, D22) ───────────────────────────────────────────────────────────────────────

-- The fourteen lines in the panel's order (modules/FarmModel.lua M.ACTIVITY): key, label, tooltip.
SF.ACTIVITY = {
  { "mobs", "Mobs looted", "Shows the distinct corpses you looted, taken from the loot window. Retail 12.x "
    .. "gives addons no reliable kill count." },
  { "items", "Items looted", "Shows how many items you looted, each stack counted by its size." },
  { "nodes", "Nodes gathered", "Shows the herb, ore and other gathering nodes you looted." },
  { "fish", "Fish caught", "Shows the catches you looted while fishing." },
  { "quests", "Quests turned in", "Shows the quests you turned in." },
  { "questRewards", "Quest rewards", "Shows the rewards quests gave you: items, money and currencies." },
  { "containers", "Containers opened", "Shows the chests, lockboxes and bag items you opened." },
  { "quality", "Drops by quality", "Shows your epic and better drops on the panel. The Details window "
    .. "lists every quality." },
  { "rep", "Reputation gained", "Shows the reputation you gained, less any you lost." },
  { "xp", "Experience gained", "Shows the experience you gained." },
  { "skill", "Skill-ups", "Shows the profession skill-ups you gained." },
  { "looks", "New appearances", "Shows the appearances you collected for the first time.", true },
  { "currency", "Currencies gained", "Shows how much currency you gained, every currency together." },
  { "deaths", "Deaths", "Your own deaths." },
}

local function activityRows(out)
  local defaults = PD.settings.farm.activity
  for _, a in ipairs(SF.ACTIVITY) do
    out[#out + 1] = row("Activity", "activity." .. a[1], { type = "bool", widget = "CheckBox",
      default = defaults[a[1]], label = a[2], tooltip = a[3],
      clients = a[4] and C.FEATURE_CLIENTS.appearances or nil })
  end
  out[#out + 1] = row("Activity", "hideZero", { type = "bool", widget = "CheckBox",
    default = farmDefault("hideZero"), label = "Hide lines that read 0",
    tooltip = "The panel and the summary leave out an activity line while it reads 0. The Details window "
      .. "still lists it." })
end

--- Every Farm row, General then Activity. A fresh array (settings/Schema.lua appends it once, at its
--- file load).
function SF.Rows()
  local out = {}
  generalRows(out)
  activityRows(out)
  return out
end

-- ── Sessions kept per character: confirm before a lower cap deletes (§9.2) ───────────────────
--
-- The write still goes through Schema:Set first (architecture-§5); the row's onChange counts what
-- the new cap would drop over every character in the saved store (Farm:CountOverCap) and, when that
-- is anything, raises KA0S_LOOTHISTORY_FARM_TRIM naming the count. Accept trims every character
-- (Farm:OnKeepChanged). Cancel writes the last CONFIRMED cap back, quietly, and says so. With no
-- StaticPopup_Show (headless) it trims at once. `SF._confirmed` is the cap the player last agreed
-- to, seeded by the row's own `set` from the store it is about to overwrite; `restoring` keeps the
-- write-back from raising a second confirm.
local restoring = false
local TRIM_REFUSED = "Trim farm sessions"

local function keepLabel(v)
  if v == 0 then return "all" end
  return tostring(v)
end

local function kept()
  if SF._confirmed == nil then return GD.farmKeep end
  return SF._confirmed
end

--- Write `v` through the seam without re-entering OnKeepChanged, then redraw the settings panel.
local function writeQuietly(v)
  restoring = true
  local ok, err = pcall(NS.Schema.Set, NS.Schema, "settings.farm.keep", v)
  restoring = false
  if not ok then error(err, 0) end
  if NS.Panel and NS.Panel.Refresh then NS.Panel:Refresh() end
end
SF._writeQuietly = writeQuietly   -- tests only

local function sendChanged()
  if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "farm") end
end

--- The keep row's onChange. Trims only once the player has confirmed, or when nothing can ask.
function SF.OnKeepChanged(v)
  if restoring then return end
  local Farm = NS.Farm
  local n = (Farm and v and v > 0) and Farm:CountOverCap(v) or 0
  if n == 0 then SF._confirmed = v; return sendChanged() end
  if NS.SimBlocks(TRIM_REFUSED) then return writeQuietly(kept()) end
  if type(StaticPopup_Show) ~= "function" then
    Farm:OnKeepChanged(v)
    SF._confirmed = v
    return sendChanged()
  end
  StaticPopup_Show("KA0S_LOOTHISTORY_FARM_TRIM", v, n, { keep = v })
end

--- KA0S_LOOTHISTORY_FARM_TRIM's two answers. Accept stores the cap the player agreed to (the store may
--- have moved while the popup was open) and trims to it; cancel restores the last confirmed cap.
function SF.ConfirmKeep(v, accepted)
  if accepted and NS.SimBlocks(TRIM_REFUSED) then return writeQuietly(kept()) end
  if accepted then
    local g = NS.db and NS.db.global
    if g and g.farmKeep ~= v then writeQuietly(v) end
    if NS.Farm then NS.Farm:OnKeepChanged(v) end
    SF._confirmed = v
    return sendChanged()
  end
  local keep = kept()
  writeQuietly(keep)
  NS.Format("sessions kept at %s; no sessions were deleted.", keepLabel(keep))
end

if type(StaticPopupDialogs) == "table" then
  -- %d = the new cap, %d = the saved sessions it deletes. Cancel is not a mere dismissal: it writes
  -- the previous cap back, so the next finish trims nothing either.
  StaticPopupDialogs["KA0S_LOOTHISTORY_FARM_TRIM"] = {
    text = "Keep %d sessions per character? This deletes %d saved sessions.",
    button1 = NS.L["Delete"],
    button2 = NS.L["Cancel"],
    OnAccept = function(_, data) SF.ConfirmKeep(data.keep, true) end,
    -- A newer value re-shows this popup with reason "override": not the player's Cancel.
    OnCancel = function(_, data, reason)
      if reason == "override" then return end
      SF.ConfirmKeep(data.keep, false)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
  }
end
