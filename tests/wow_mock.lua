-- LootHistory's WoW-API mock: a thin EXTENDER over the shared LibKa0s test kit.
--
-- `tests/_kit/mock_base.lua` owns the universal half — frames, timers, LibStub (with a real
-- NewLibrary, which the vendored LibKa0s modules register through), the Ace fakes, the fireable
-- AceGUI widget factory and the Blizzard Settings canvas recorder. Everything below is what only
-- this addon touches: the loot/currency global strings, the item and currency APIs, the inline
-- markup helpers, and the character/zone identity its suites assert on.
--
-- Never edit tests/_kit/ — it is vendored byte-for-byte from ../LibKa0s/testkit (see docs/testing.md).

local base = dofile("tests/_kit/mock_base.lua")

return function()
  local M = base()

  -- ── identity the suites assert on ───────────────────────────────────────────
  -- The kit's defaults are "Testchar"/"Testrealm"; LootHistory's suites were written against
  -- Mock-Realm and a Mage, and the stored `char` column is part of the export contract.
  M.UnitName = function() return "Mock" end
  M.UnitClass = function() return "Mage", "MAGE", 8 end
  M.GetRealmName = function() return "Realm" end
  M.GetNormalizedRealmName = function() return "Realm" end
  M.GetZoneText = function() return "Testville" end
  M.GetSubZoneText = function() return "" end

  -- ── item / map / loot APIs ─────────────────────────────────────────────────
  M.C_Map = { GetBestMapForUnit = function() return 2657 end }
  M.__itemClassID = 0   -- overridable per-test item class (Enum.ItemClass); 0 = Consumable
  -- Per-item Enum.ItemBind value (GetItemInfo's 14th return), keyed by the id or link a test
  -- passes. Empty by default, so an item the test hasn't described reads as uncached-for-binding.
  M.__itemBindTypes = {}
  M.C_Item = {
    GetItemInfoInstant = function() return 211296, nil, nil, nil, nil, M.__itemClassID end,
    GetItemInfo = function(link)
      return "Item Name", link, 4, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        M.__itemBindTypes[link]
    end,
  }
  M.GetLootSourceInfo = function() return nil end

  -- Currency API mock. GetCurrencyListSize / GetCurrencyListInfo / GetCurrencyListLink model a tiny
  -- currency window: one expansion header ("The War Within") then two currencies under it, so the
  -- category resolver has headers to walk. GetCurrencyInfoFromLink returns name + icon by id.
  M.__currencyNames = { [3008] = "Valorstones", [2914] = "Weathered Harbinger Crest" }
  M.__currencyTransferable = { [3008] = true }   -- 3008 is Warband-transferable; 2914 is not
  M.C_CurrencyInfo = {
    GetCurrencyListSize = function() return 3 end,
    GetCurrencyListInfo = function(i)
      if i == 1 then return { name = "The War Within", isHeader = true } end
      if i == 2 then return { name = M.__currencyNames[3008], isHeader = false } end
      if i == 3 then return { name = M.__currencyNames[2914], isHeader = false } end
      return nil
    end,
    GetCurrencyListLink = function(i)
      if i == 2 then return "|Hcurrency:3008::|h[Valorstones]|h" end
      if i == 3 then return "|Hcurrency:2914::|h[Weathered Harbinger Crest]|h" end
      return nil
    end,
    GetCurrencyInfoFromLink = function(link)
      local id = tonumber(link and link:match("|?H?currency:(%d+)"))
      if not id then return nil end
      return { name = M.__currencyNames[id], iconFileID = 100000 + id }
    end,
    GetCurrencyInfo = function(id)
      local name = M.__currencyNames[id]
      if not name then return nil end
      return { name = name, iconFileID = 100000 + id, quantity = 0, quality = 4,
        isAccountTransferable = M.__currencyTransferable[id] or false }
    end,
  }

  -- ── loot / currency global strings ─────────────────────────────────────────
  M.LOOT_ITEM_SELF = "You receive loot: %s."
  M.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
  M.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
  M.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
  -- Bonus-roll self strings carry NO trailing period in live GlobalStrings.lua.
  M.LOOT_ITEM_BONUS_ROLL_SELF = "You receive bonus loot: %s"
  M.LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE = "You receive bonus loot: %sx%d"
  -- Created (crafted) and refunded self strings — these DO carry a trailing period in live GlobalStrings.
  M.LOOT_ITEM_CREATED_SELF = "You create: %s."
  M.LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
  M.LOOT_ITEM_REFUND = "You are refunded: %s."
  M.LOOT_ITEM_REFUND_MULTIPLE = "You are refunded: %sx%d."
  -- Roll-won line ("You won: <item>", no trailing period), used to stamp ROLL context.
  M.LOOT_ROLL_YOU_WON = "You won: %s"
  -- Currency gain strings (CHAT_MSG_CURRENCY). Single has no qty; multiples carry xN, and the
  -- bonus/overflow variants append a parenthetical (the overflow one embeds a second %s = the
  -- currency name, which the parser ignores).
  M.CURRENCY_GAINED = "You receive currency: %s"
  M.CURRENCY_GAINED_MULTIPLE = "You receive currency: %sx%d"
  M.CURRENCY_GAINED_MULTIPLE_BONUS = "You receive currency: %sx%d (Bonus Objective)"
  M.CURRENCY_GAINED_MULTIPLE_OVERFLOW = "You receive currency: %sx%d (You've earned the maximum amount of %s)"

  M.ITEM_QUALITY_COLORS = setmetatable({}, {
    __index = function() return { r = 1, g = 1, b = 1, hex = "ffffffff" } end,
  })
  -- Real class colors for the four tokens the suites exercise; any other token misses to nil so
  -- the addon's neutral-gray fallback is the one under test, exactly as in-game for an unknown class.
  M.RAID_CLASS_COLORS = {
    MAGE    = { r = 0.25, g = 0.78, b = 0.92 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    ROGUE   = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
  }

  -- ── inline markup ──────────────────────────────────────────────────────────
  -- GetAtlasInfo knows only the atlases this client would actually ship, so an unknown atlas takes
  -- the addon's fallback branch here exactly as it would in game — that branching is the point (the
  -- class icon and the Insights star both depend on it).
  M.__atlases = { ["classicon-mage"] = true, ["classicon-warrior"] = true,
                  ["classicon-rogue"] = true, ["classicon-priest"] = true,
                  ["PetJournal-FavoritesIcon"] = true }
  M.C_Texture = { GetAtlasInfo = function(a) return M.__atlases[a] and { width = 14, height = 14 } or nil end }
  M.CreateAtlasMarkup = function(a, w, h) return ("|A:%s:%d:%d|a"):format(a, w or 0, h or 0) end
  M.CreateTextureMarkup = function(file, _, _, w, h) return ("|T%s:%d:%d|t"):format(file, w or 0, h or 0) end
  M.CLASS_ICON_TCOORDS = {
    MAGE = { 0.25, 0.49, 0, 0.25 }, WARRIOR = { 0, 0.25, 0, 0.25 },
    ROGUE = { 0.49, 0.74, 0, 0.25 }, PRIEST = { 0.49, 0.74, 0.25, 0.5 },
  }

  -- WoW string helpers the kit deliberately omits (see tests/_kit/mock_base.lua's header): this
  -- addon calls both, so they live here with the suites that exercise them.
  M.strtrim = function(s) return (tostring(s):gsub("^%s*(.-)%s*$", "%1")) end
  M.strsplit = function(sep, s)
    local parts = {}
    for p in string.gmatch(s, "([^" .. sep .. "]+)") do parts[#parts + 1] = p end
    return unpack(parts)
  end

  -- ── FauxScrollFrame ────────────────────────────────────────────────────────
  -- Real client globals the kit does not carry, and modules/BrowserTable.lua's Bind() calls all
  -- three the moment the History pane is attached. Without them any suite that opens the window
  -- raises on a global that EXISTS in the client -- a mock gap, not addon behavior. The offset is
  -- a fixed 0: nothing headless scrolls, and a suite that needs a scrolled view would set it here
  -- rather than being handed a lie by default.
  M.FauxScrollFrame_Update = function() end
  M.FauxScrollFrame_GetOffset = function() return 0 end
  M.FauxScrollFrame_OnVerticalScroll = function() end

  -- ── frames that remember their size ────────────────────────────────────────
  -- The kit's stub answers 0 from GetWidth forever and deliberately leaves the setters undefined
  -- (so a suite can spy on them by rawsetting a recorder). Nothing here spies on a setter, and one
  -- contract this addon depends on is only observable through the pair: LibKa0s-DebugLog-1.0
  -- DERIVES the console's Copy/Clear title-bar offsets from the width of the close button
  -- `makeCloseButton` returns, and this addon's button is 24 wide where Core's is 18. With a
  -- GetWidth stuck at 0 the library falls back to 18 and the derivation — the entire reason that
  -- descriptor field matters to this host — is untestable.
  local kitFrame = M.__stubFrame
  M.__stubFrame = function()
    local f = kitFrame()
    local w, h = 0, 0
    function f:SetSize(width, height) w, h = width or w, height or h; return self end
    function f:SetWidth(width) w = width or w; return self end
    function f:SetHeight(height) h = height or h; return self end
    function f:GetWidth() return w end
    function f:GetHeight() return h end
    -- A FontString getter used in ARITHMETIC: settings/Panel.lua positions each AH-table row's
    -- info icon at `ACOL.module + r.module:GetStringWidth() + 6`, and the kit's blanket
    -- "any PascalCase method returns the frame" hands that a table. Same class of fidelity gap the
    -- kit already fixes for GetWidth/GetHeight; this addon is the first to need the third.
    function f:GetStringWidth() return 0 end
    return f
  end

  -- ── a FontString is not its parent frame, and it raises before it has a face ─────────────
  --
  -- The kit's stub answers every PascalCase key from its metatable, so `CreateFontString` hands
  -- back THE FRAME ITSELF and `SetText` is a silent no-op. Both are friendlier than the client,
  -- and both hide real bugs this addon can now ship:
  --
  --   * a label and its glyph are two FontStrings on ONE pooled menu row
  --     (LibKa0s-Widgets-1.0's makeMenuRow). With the aliasing, writing the label and writing
  --     the glyph write the same object, and a suite cannot tell the two columns apart at all.
  --   * a FontString created BARE has no font, and the live client answers
  --     `FontString:SetText(): Font not set` on the very next call. LibKa0s v1.11.0 and v1.11.1
  --     shipped exactly that crash on the first click of a dropdown, and 553 green library cases
  --     sailed over it because none of them built a real row.
  --
  -- So: a distinct object per call, its face taken from the template argument (nil when created
  -- bare, and settable afterwards by SetFont/SetFontObject), and SetText RAISES while the face is
  -- nil. `GetStringWidth` stays 0, as the kit's does and as settings/Panel.lua's row arithmetic
  -- was written against -- fidelity here is about the font and the identity, not the metrics.
  local function stubFontString(template)
    local fs = M.__stubFrame()
    fs.__isFontString = true
    fs.__font = template   -- a template argument IS a face; nil means the client has none yet
    function fs:SetFont(path, size, flags)
      self.__font, self.__fontSize, self.__fontFlags = path, size, flags
      return self
    end
    function fs:SetFontObject(o) self.__font = o; return self end
    function fs:GetFont() return self.__font, self.__fontSize, self.__fontFlags end
    function fs:SetText(t)
      if self.__font == nil then
        error("FontString:SetText(): Font not set", 2)
      end
      self.__text = (t ~= nil) and tostring(t) or nil
      return self
    end
    function fs:GetText() return self.__text end
    function fs:SetTextColor(r, g, b, a) self.__color = { r, g, b, a }; return self end
    function fs:GetTextColor()
      local c = self.__color or {}
      return c[1], c[2], c[3], c[4]
    end
    function fs:GetStringWidth() return 0 end
    return fs
  end
  M.__stubFontString = stubFontString
  local baseFrame = M.__stubFrame
  M.__stubFrame = function()
    local f = baseFrame()
    function f:CreateFontString(_, _, template) return stubFontString(template) end
    return f
  end
  M.CreateFrame = function() return M.__stubFrame() end
  M.UIParent = M.__stubFrame()

  -- ── AceGUI container methods this addon uses ───────────────────────────────
  -- The kit's widget factory models the setters LibKa0s's own makers call. The inverted set picker
  -- in settings/Panel.lua draws into an AceGUI InlineGroup, whose SetTitle has no LibKa0s consumer
  -- and so is not modeled. Added by wrapping Create rather than by registering a widget type, so
  -- every widget keeps the base's recorders and __fire.
  local aceGUI = M.__libs["AceGUI-3.0"]
  local stockCreate = aceGUI.Create
  function aceGUI:Create(wtype)
    local w = stockCreate(self, wtype)
    if w.SetTitle == nil then
      function w:SetTitle(v) self.titleText = v; return self end
    end
    -- A widget's `frame` comes from the kit's own stubFrame, not from the one extended above, so
    -- the arithmetic-safe getter has to be stamped on here too. settings/Panel.lua's AH table
    -- parents raw FontStrings to an AceGUI SimpleGroup's frame and measures them.
    -- rawget, not a plain index: the frame stub's metatable answers EVERY PascalCase key with a
    -- function, so a plain `== nil` guard is never true and this stamp would silently never happen.
    if w.frame and rawget(w.frame, "GetStringWidth") == nil then
      function w.frame:GetStringWidth() return 0 end
    end
    return w
  end

  -- ── the message bus ────────────────────────────────────────────────────────
  -- The kit's AceAddon fake does not embed AceEvent, because not every host asks for it. This addon
  -- does: `AceAddon:NewAddon(NS, name, "AceEvent-3.0", ...)` embeds the (message, target) bus onto
  -- the addon object, and NS.bus IS that object. Wrap NewAddon so the mock models the real embed —
  -- including the clobber semantics the kit's AceEvent fake already reproduces.
  local aceAddon = M.__libs["AceAddon-3.0"]
  local stockNewAddon = aceAddon.NewAddon
  aceAddon.NewAddon = function(self, target, ...)
    local obj = stockNewAddon(self, target, ...)
    return M.__libs["AceEvent-3.0"]:Embed(obj)
  end

  return M
end
