# Debug Window Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a monospace font in the debug console, adopt a fixed tagged log-line format, decouple debug state from window visibility, and add an in-window on/off toggle.

**Architecture:** `NS.Debug` gains an explicit tag argument and formats every line as `<ts>  |  [<tag>] <content>` via a pure, unit-tested helper. Debug state (`NS.State.debug`) becomes an independent session flag driven by a single `NS.DebugLog:SetEnabled` seam that the slash command and a new header toggle both call; the window's show/hide no longer touches state. JetBrains Mono is vendored and applied to the log and copy surfaces.

**Tech Stack:** Lua 5.1, Ace3, LibSharedMedia-3.0 (all vendored). Headless tests via `lua tests/run.lua`; lint via `luacheck .`.

## Global Constraints

- **Lua 5.1** — WoW runtime; tests target it. No 5.2+ syntax.
- **Every file begins** `local addonName, NS = ...`. No `_G[addonName]`.
- **Compat firewall** — no inline `WOW_PROJECT_ID` branching in modules.
- **Debug state is session-only** — `NS.State.debug`, default `false`, reset every reload; NOT persisted, NOT a Schema row.
- **Closed message bus** — `Ka0s_LootHistory_*` messages only; no cross-module table reach.
- **Files capped at 1500 LOC.**
- **`luacheck .` must report 0 errors** and `lua tests/run.lua` must be green before every commit.
- **Tag rule:** a tag is one word, ≤10 chars; the format truncates anything longer.
- **Commit message trailer:** end every commit body with
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

### Task 1: Vendor JetBrains Mono and apply it to the debug surfaces

**Files:**
- Create: `media/fonts/JetBrainsMono-Regular.ttf` (downloaded, binary)
- Create: `media/fonts/OFL.txt` (downloaded license)
- Modify: `core/Constants.lua` (add `FONT_MONO`)
- Modify: `core/LootHistory.lua:8-13` (register font with LibSharedMedia in `OnInitialize`)
- Modify: `modules/DebugLog.lua:77` (log font), `modules/DebugLog.lua:161` (copy edit-box font)
- Test: `tests/test_debuglog.lua` (new; asserts the constant is wired)

**Interfaces:**
- Produces: `NS.Constants.FONT_MONO` — string path to the vendored TTF, usable by any module via `SetFont(NS.Constants.FONT_MONO, size, flags)`.

- [ ] **Step 1: Download the font and license into `media/fonts/`**

Run:
```bash
cd "$(mktemp -d)" && \
curl -sSL -o jbm.zip "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip" && \
unzip -o jbm.zip "fonts/ttf/JetBrainsMono-Regular.ttf" "OFL.txt" -d . && \
mkdir -p "$OLDPWD/media/fonts" && \
cp fonts/ttf/JetBrainsMono-Regular.ttf "$OLDPWD/media/fonts/JetBrainsMono-Regular.ttf" && \
cp OFL.txt "$OLDPWD/media/fonts/OFL.txt" && \
cd "$OLDPWD" && ls -l media/fonts/
```
Expected: `JetBrainsMono-Regular.ttf` (~273 KB) and `OFL.txt` (~4 KB) present under `media/fonts/`.

- [ ] **Step 2: Add the `FONT_MONO` constant**

In `core/Constants.lua`, after the `C.Confidence` block (line 40), add:
```lua
-- Vendored monospace font (JetBrains Mono, OFL) used by the debug console. Path is the in-game
-- addon-relative form; the file lives at media/fonts/ in the repo.
C.FONT_MONO = "Interface\\AddOns\\LootHistory\\media\\fonts\\JetBrainsMono-Regular.ttf"
```

- [ ] **Step 3: Register the font with LibSharedMedia at init**

In `core/LootHistory.lua`, inside `OnInitialize` (currently lines 8-13), add the registration as the first line of the body:
```lua
function addon:OnInitialize()
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM then LSM:Register("font", "JetBrains Mono", NS.Constants.FONT_MONO) end
  NS:InitDB()
  if NS.Schema and NS.Schema.Register then NS.Schema:Register() end
  if NS.Slash and NS.Slash.Register then NS.Slash:Register() end
  if NS.Panel and NS.Panel.Register then NS.Panel:Register() end
end
```

- [ ] **Step 4: Apply the mono font to the log and copy box**

In `modules/DebugLog.lua`, replace line 77:
```lua
  log:SetFontObject(GameFontHighlightSmall)
```
with:
```lua
  log:SetFont(NS.Constants.FONT_MONO, 12, "")
```
and replace line 161:
```lua
  edit:SetFontObject(GameFontHighlightSmall)
```
with:
```lua
  edit:SetFont(NS.Constants.FONT_MONO, 12, "")
```

- [ ] **Step 5: Write the failing test for the constant**

Create `tests/test_debuglog.lua`:
```lua
local T = _G.LH_TEST
local NS, test, assertTrue = T.NS, T.test, T.assertTrue

test("FONT_MONO constant is a JetBrains Mono TTF path", function()
  assertTrue(type(NS.Constants.FONT_MONO) == "string", "FONT_MONO must be a string")
  assertTrue(NS.Constants.FONT_MONO:match("JetBrainsMono.-%.ttf$") ~= nil,
    "FONT_MONO must point at the vendored JetBrainsMono TTF")
end)
```

Register it in `tests/run.lua` by adding this line to the `-- load test suites` block (after `dofile("tests/test_browsertable.lua")`):
```lua
dofile("tests/test_debuglog.lua")
```

- [ ] **Step 6: Run tests to verify the new test passes and nothing regressed**

Run: `lua tests/run.lua`
Expected: all tests PASS, including `FONT_MONO constant is a JetBrains Mono TTF path`. Final line shows `N passed, 0 failed`.

- [ ] **Step 7: Lint**

Run: `luacheck .`
Expected: `0 warnings / 0 errors` (or the repo's established baseline — no NEW warnings).

- [ ] **Step 8: Commit**

```bash
git add media/fonts/JetBrainsMono-Regular.ttf media/fonts/OFL.txt \
  core/Constants.lua core/LootHistory.lua modules/DebugLog.lua \
  tests/test_debuglog.lua tests/run.lua
git commit -m "feat(debug): vendor JetBrains Mono and use it in the debug console

Adds media/fonts/JetBrainsMono-Regular.ttf (OFL), registers it with
LibSharedMedia, exposes NS.Constants.FONT_MONO, and applies it to the
debug log and copy box.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Tagged log-line format + `NS.Debug(tag, fmt, ...)` and migrate call sites

**Files:**
- Modify: `modules/DebugLog.lua` (add `D.FormatPlain`, change `D:Add` and `NS.Debug` signatures)
- Modify: `modules/Attribution.lua` (13 call sites), `modules/Collector.lua` (1 call site)
- Test: `tests/test_debuglog.lua` (add format tests)

**Interfaces:**
- Produces: `NS.DebugLog.FormatPlain(ts, tag, msg) -> string` — pure formatter, no frames. Returns `"<ts>  |  [<tag padded/truncated to 10>] <msg>"`.
- Produces: `NS.Debug(tag, fmt, ...)` — new signature; `tag` is the category word, `fmt`/`...` are the message (string.format applied only when varargs present).
- Produces: `NS.DebugLog:Add(tag, msg)` — new signature.
- Consumes: `NS.Constants.FONT_MONO` (from Task 1, already applied).

- [ ] **Step 1: Write the failing format tests**

Append to `tests/test_debuglog.lua`:
```lua
test("FormatPlain pads a short tag to 10 chars inside brackets", function()
  local out = NS.DebugLog.FormatPlain("15:04:43", "Cast", "player spell=3365")
  assertEqual(out, "15:04:43  |  [Cast      ] player spell=3365")
end)

test("FormatPlain truncates a tag longer than 10 chars", function()
  local out = NS.DebugLog.FormatPlain("15:04:43", "Prospecting", "x")
  assertEqual(out, "15:04:43  |  [Prospectin] x")
end)

test("FormatPlain tolerates a nil tag", function()
  local out = NS.DebugLog.FormatPlain("15:04:43", nil, "hi")
  assertEqual(out, "15:04:43  |  [          ] hi")
end)
```
Add `assertEqual` to the locals pulled from `T` at the top of the file:
```lua
local NS, test, assertTrue, assertEqual = T.NS, T.test, T.assertTrue, T.assertEqual
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: the three new `FormatPlain …` tests FAIL with an error about calling a nil value (`FormatPlain` not defined yet).

- [ ] **Step 3: Add the pure formatter and re-signature `D:Add` / `NS.Debug`**

In `modules/DebugLog.lua`, replace the current `D:Add` (lines 101-109):
```lua
function D:Add(msg)
  local f = EnsureFrame()
  local ts = date("%H:%M:%S")
  -- Grey, fixed-width timestamp + a "|" separator ("||" renders one literal pipe).
  f.log:AddMessage(("|cff888888%s  ||  |r%s"):format(ts, tostring(msg)))
  -- Mirror a plain-text copy into the buffer (for the Copy window), capped like the log.
  D.buffer[#D.buffer + 1] = ts .. "  |  " .. tostring(msg)
  if #D.buffer > MAX_BUFFER then table.remove(D.buffer, 1) end
end
```
with:
```lua
-- Pure line formatter (no frames): "<ts>  |  [<tag>] <msg>". The tag is left-justified and
-- padded/truncated to a fixed 10 chars INSIDE the brackets so the closing ] and all content align.
function D.FormatPlain(ts, tag, msg)
  return ("%s  |  [%-10.10s] %s"):format(tostring(ts), tostring(tag or ""), tostring(msg))
end

function D:Add(tag, msg)
  local f = EnsureFrame()
  local ts = date("%H:%M:%S")
  -- Grey the timestamp / separator / bracketed tag; content in the default colour.
  -- "||" renders one literal pipe inside a colour-coded segment.
  f.log:AddMessage(("|cff888888%s  ||  [%-10.10s]|r %s"):format(ts, tostring(tag or ""), tostring(msg)))
  -- Mirror a plain-text copy into the buffer (for the Copy window), capped like the log.
  D.buffer[#D.buffer + 1] = D.FormatPlain(ts, tag, msg)
  if #D.buffer > MAX_BUFFER then table.remove(D.buffer, 1) end
end
```
Then replace `NS.Debug` (lines 194-198):
```lua
function NS.Debug(fmt, ...)
  if not (NS.State and NS.State.debug) then return end
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  D:Add(msg)
end
```
with:
```lua
function NS.Debug(tag, fmt, ...)
  if not (NS.State and NS.State.debug) then return end
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  D:Add(tag, msg)
end
```

- [ ] **Step 4: Run the format tests to verify they pass**

Run: `lua tests/run.lua`
Expected: the three `FormatPlain …` tests PASS. Other suites may still be green (callers not yet migrated do not run during tests), but proceed to migrate them now for a clean commit.

- [ ] **Step 5: Migrate the 14 module call sites to `(tag, ...)`**

In `modules/Attribution.lua`, apply these exact replacements (old → new):

```lua
-- line 79
    NS.Debug("stamp %s%s%s", source, trigger and (" via " .. trigger) or "", detailStr(detail))
-- →
    NS.Debug("Attr", "stamp %s%s%s", source, trigger and (" via " .. trigger) or "", detailStr(detail))
```
```lua
-- line 89
      NS.Debug("consume -> %s (%s)%s", c.source, c.confidence, detailStr(c.detail))
-- →
      NS.Debug("Attr", "consume -> %s (%s)%s", c.source, c.confidence, detailStr(c.detail))
```
```lua
-- line 94
    NS.Debug("consume -> OTHER (INFERRED) — no fresh context")
-- →
    NS.Debug("Attr", "consume -> OTHER (INFERRED) — no fresh context")
```
```lua
-- line 137
    if NS.State.debug and NS.Debug then NS.Debug("LOOT_OPENED kept %s (deconstruct mat window)", c.source) end
-- →
    if NS.State.debug and NS.Debug then NS.Debug("Open", "LOOT_OPENED kept %s (deconstruct mat window)", c.source) end
```
```lua
-- line 146
        NS.Debug("LOOT_OPENED slot=%d guid=%s -> %s", slot, tostring(guid), source)
-- →
        NS.Debug("Open", "LOOT_OPENED slot=%d guid=%s -> %s", slot, tostring(guid), source)
```
```lua
-- line 152
  if NS.State.debug and NS.Debug then NS.Debug("LOOT_OPENED (%d slots, no source GUID)", n) end
-- →
  if NS.State.debug and NS.Debug then NS.Debug("Open", "LOOT_OPENED (%d slots, no source GUID)", n) end
```
```lua
-- lines 158-159 (strip the redundant "context: " prefix; tag conveys it)
    NS.Debug("context: encounter start id=%s diff=%s (KILL loot now carries it)",
      tostring(encounterID), tostring(difficultyID))
-- →
    NS.Debug("Attr", "encounter start id=%s diff=%s (KILL loot now carries it)",
      tostring(encounterID), tostring(difficultyID))
```
```lua
-- line 165
  if NS.State.debug and NS.Debug then NS.Debug("context: encounter end") end
-- →
  if NS.State.debug and NS.Debug then NS.Debug("Attr", "encounter end") end
```
```lua
-- line 171
    NS.Debug("context: keystone start +%s (GameObject loot → MPLUS)", tostring(State.keystone.level))
-- →
    NS.Debug("Attr", "keystone start +%s (GameObject loot → MPLUS)", tostring(State.keystone.level))
```
```lua
-- line 180
      NS.Debug("context: keystone completed +%s (reward chest still MPLUS)", tostring(State.keystone.level))
-- →
      NS.Debug("Attr", "keystone completed +%s (reward chest still MPLUS)", tostring(State.keystone.level))
```
```lua
-- lines 200-201
    NS.Debug("UseContainerItem bag=%s slot=%s hasLoot=%s spellTargeting=%s",
      tostring(bag), tostring(slot), tostring(hasLoot), tostring(targeting))
-- →
    NS.Debug("Open", "UseContainerItem bag=%s slot=%s hasLoot=%s spellTargeting=%s",
      tostring(bag), tostring(slot), tostring(hasLoot), tostring(targeting))
```
```lua
-- lines 216-217 (strip the redundant "cast: " prefix)
    NS.Debug("cast: player spell=%s name=%s deconstruct=%s",
      tostring(spellID), tostring(name), tostring(src or false))
-- →
    NS.Debug("Cast", "player spell=%s name=%s deconstruct=%s",
      tostring(spellID), tostring(name), tostring(src or false))
```
```lua
-- lines 237-238
    NS.Debug("mail-take idx=%s sender=%s subject=%s -> %s",
      tostring(mailIndex), tostring(sender), tostring(subject), isAH and "AH" or "MAIL")
-- →
    NS.Debug("Mail", "mail-take idx=%s sender=%s subject=%s -> %s",
      tostring(mailIndex), tostring(sender), tostring(subject), isAH and "AH" or "MAIL")
```

In `modules/Collector.lua`, lines 81-82 (strip the redundant "loot: " prefix):
```lua
    NS.Debug("loot: %s q%d ilvl=%s src=%s conf=%s",
      tostring(itemName), quality or 0, tostring(itemLevel or "-"), source, confidence)
-- →
    NS.Debug("Loot", "%s q%d ilvl=%s src=%s conf=%s",
      tostring(itemName), quality or 0, tostring(itemLevel or "-"), source, confidence)
```

> NOTE: `settings/Schema.lua:145` (`NS.Debug("debug logging enabled")`) is intentionally left for Task 3, where that command handler is rewritten and the line moves into `SetEnabled`. It does not crash in the interim (nil `fmt`, no varargs → `msg` is `nil`, formatted harmlessly), and no test exercises it.

- [ ] **Step 6: Verify no old-signature call site remains in modules**

Run:
```bash
grep -rn 'NS\.Debug("' modules/ | grep -vE 'NS\.Debug\("(Attr|Open|Cast|Mail|Loot|Debug)"'
```
Expected: no output (every module call now leads with a tag literal).

- [ ] **Step 7: Run tests and lint**

Run: `lua tests/run.lua && luacheck .`
Expected: `N passed, 0 failed`; luacheck `0 errors`.

- [ ] **Step 8: Commit**

```bash
git add modules/DebugLog.lua modules/Attribution.lua modules/Collector.lua tests/test_debuglog.lua
git commit -m "feat(debug): tagged fixed-width log lines via NS.Debug(tag, ...)

Adds D.FormatPlain and re-signatures NS.Debug/D:Add to take an explicit
1-word tag rendered as [%-10.10s]. Migrates all module call sites to
Attr/Open/Cast/Mail/Loot tags.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Decouple debug state from window visibility; `/lh debug on|off|toggle`

**Files:**
- Modify: `core/State.lua:15` (comment only — state is now independent)
- Modify: `modules/DebugLog.lua` (remove OnShow/OnHide state hooks; add `SetEnabled` + `RefreshHeader` stub)
- Modify: `settings/Schema.lua:140-146` (`debug` command parses `on`/`off`/empty)
- Test: `tests/test_debuglog.lua` (add dispatch tests)

**Interfaces:**
- Produces: `NS.DebugLog:SetEnabled(on)` — sets `NS.State.debug` to the boolean, refreshes the header, prints the chat confirmation, and (when turning on) emits the `[Debug] logging enabled` line.
- Produces: `NS.DebugLog:RefreshHeader()` — updates the header toggle label if the frame exists (no-op otherwise). Fully implemented in Task 4; a safe stub here.
- Consumes: `NS.Debug(tag, fmt, ...)` (Task 2), `NS.PREFIX`.

- [ ] **Step 1: Write the failing dispatch tests**

Append to `tests/test_debuglog.lua`:
```lua
local function debugCmd(rest)
  for _, c in ipairs(NS.COMMANDS) do
    if c.name == "debug" then return c.fn(rest) end
  end
  error("no debug command")
end

test("/lh debug on enables state", function()
  NS.State.debug = false
  debugCmd("on")
  assertTrue(NS.State.debug == true, "state should be on")
end)

test("/lh debug off disables state", function()
  NS.State.debug = true
  debugCmd("off")
  assertTrue(NS.State.debug == false, "state should be off")
end)

test("/lh debug (no arg) toggles the window, not state", function()
  NS.State.debug = true
  debugCmd("")
  assertTrue(NS.State.debug == true, "bare toggle must not change state")
  NS.State.debug = false
  debugCmd("")
  assertTrue(NS.State.debug == false, "bare toggle must not change state")
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: `/lh debug on enables state` and `/lh debug off disables state` FAIL — the current command only toggles the window and follows visibility, so `NS.State.debug` will not match. (The bare-toggle test may already pass.)

- [ ] **Step 3: Remove the visibility→state hooks and add the `SetEnabled` seam**

In `modules/DebugLog.lua`, delete the OnShow/OnHide state hooks (current lines 89-92):
```lua
  -- Debug state tracks window visibility (session-only): showing the console enables logging;
  -- closing it (X button or ESC via UISpecialFrames) disables logging. Reset every reload.
  frame:HookScript("OnShow", function() NS.State.debug = true end)
  frame:HookScript("OnHide", function() NS.State.debug = false end)
```
Replace them with a header refresh on show (so the label is correct whenever the window appears):
```lua
  -- State no longer follows visibility; just keep the header label accurate when shown.
  frame:HookScript("OnShow", function() D:RefreshHeader() end)
```
Then add these functions just above `function NS.Debug` (near line 193):
```lua
-- Single seam for changing debug state. Slash command and header toggle both call this so the
-- chat message and header label stay consistent. Session-only: NS.State.debug resets on reload.
function D:SetEnabled(on)
  on = not not on
  NS.State.debug = on
  D:RefreshHeader()
  print(NS.PREFIX .. " debug " .. (on and "on" or "off"))
  if on and NS.Debug then NS.Debug("Debug", "logging enabled") end
end

-- Updates the header toggle label to match NS.State.debug. Fully wired in the header task;
-- safe no-op until the toggle fontstring exists.
function D:RefreshHeader()
  if not (frame and frame.debugToggle) then return end
  local on = NS.State and NS.State.debug
  frame.debugToggle:SetText(on and "Debug: ON" or "Debug: OFF")
  if on then frame.debugToggle:SetTextColor(0.30, 0.85, 0.30)
  else frame.debugToggle:SetTextColor(0.90, 0.30, 0.30) end
end
```

- [ ] **Step 4: Rewrite the `debug` command to parse `on`/`off`/empty**

In `settings/Schema.lua`, replace the `debug` command entry (current lines 140-146):
```lua
  { name = "debug",    desc = "Toggle the debug console",  fn = function()
      -- Toggles the console; NS.State.debug follows the window's show/hide (session-only).
      if NS.DebugLog then NS.DebugLog:Toggle() end
      local on = NS.State and NS.State.debug
      print(NS.PREFIX .. " debug " .. (on and "on" or "off"))
      if on and NS.Debug then NS.Debug("debug logging enabled") end
    end },
```
with:
```lua
  { name = "debug",    desc = "Toggle window; 'on'/'off' set logging",  fn = function(rest)
      -- `/lh debug` toggles the window only (state untouched); `/lh debug on|off` sets the
      -- session-only logging flag via the DebugLog seam. Logging runs even with the window closed.
      local arg = rest and tostring(rest):lower():match("^%s*(%S*)") or ""
      if not NS.DebugLog then return end
      if arg == "on" then NS.DebugLog:SetEnabled(true)
      elseif arg == "off" then NS.DebugLog:SetEnabled(false)
      else NS.DebugLog:Toggle() end
    end },
```

- [ ] **Step 5: Update the State.lua comment**

In `core/State.lua`, replace line 15:
```lua
State.debug = false         -- debug console visibility == logging; toggled by /lh debug, default off
```
with:
```lua
State.debug = false         -- session-only logging flag; independent of window visibility. /lh debug on|off; default off
```

- [ ] **Step 6: Run tests and lint**

Run: `lua tests/run.lua && luacheck .`
Expected: all dispatch tests PASS; `0 failed`; luacheck `0 errors`.

- [ ] **Step 7: Commit**

```bash
git add core/State.lua modules/DebugLog.lua settings/Schema.lua tests/test_debuglog.lua
git commit -m "feat(debug): decouple debug state from window visibility

NS.State.debug is now an independent session flag set via a single
DebugLog:SetEnabled seam. /lh debug toggles the window only; /lh debug
on|off set logging (captures in the background with the window closed).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Header on/off toggle

**Files:**
- Modify: `modules/DebugLog.lua` (add the left-aligned header toggle in `EnsureFrame`)
- Test: `tests/test_debuglog.lua` (add a click-toggles-state test)

**Interfaces:**
- Consumes: `NS.DebugLog:SetEnabled(on)` and `NS.DebugLog:RefreshHeader()` (Task 3).
- Produces: `frame.debugToggle` — the fontstring the `RefreshHeader` seam updates; and `frame.debugToggleBtn` — the clickable button. Exposed on the frame for testability.

- [ ] **Step 1: Write the failing toggle test**

The mock `CreateFrame` returns a universal stub whose `GetScript` is a no-op, so the test cannot fetch the real handler off the button. Instead, Step 3 exposes the click closure as `NS.DebugLog._toggleClickForTest`; the test calls that directly. Append to `tests/test_debuglog.lua`:
```lua
test("header toggle click flips debug state", function()
  NS.State.debug = false
  NS.DebugLog:Show()
  local click = NS.DebugLog._toggleClickForTest
  assertTrue(type(click) == "function", "toggle click closure must be exposed")
  click(); assertTrue(NS.State.debug == true, "click should turn state on")
  click(); assertTrue(NS.State.debug == false, "second click should turn state off")
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/run.lua`
Expected: `header toggle click flips debug state` FAILS — `_toggleClickForTest` is nil.

- [ ] **Step 3: Build the header toggle in `EnsureFrame`**

In `modules/DebugLog.lua`, inside `EnsureFrame`, after the `copy` button is created (current line 71, `copy:SetPoint(...)`), add the left-aligned toggle. It reuses the flat look of `makeTextButton` but manages its own resting colour (green/red) instead of grey:
```lua
  -- Left-aligned debug on/off toggle. Same flat look as Copy/Clear, but the resting colour
  -- reflects state (green ON / red OFF); clicking flips state through the shared SetEnabled seam.
  local toggleBtn = CreateFrame("Button", nil, titleBar)
  toggleBtn:SetSize(80, 18)
  toggleBtn:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
  local toggleFS = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  toggleFS:SetPoint("LEFT")
  toggleBtn:SetScript("OnEnter", function() toggleFS:SetTextColor(1, 0.82, 0) end)
  toggleBtn:SetScript("OnLeave", function() D:RefreshHeader() end)
  local function onToggleClick() D:SetEnabled(not (NS.State and NS.State.debug)) end
  toggleBtn:SetScript("OnClick", onToggleClick)
  frame.debugToggle = toggleFS
  frame.debugToggleBtn = toggleBtn
  D._toggleClickForTest = onToggleClick   -- test seam (mock stubs GetScript)
```
Then, just before `frame:Hide()` (current line 94), initialise the label:
```lua
  D:RefreshHeader()
```

- [ ] **Step 4: Run tests to verify pass**

Run: `lua tests/run.lua`
Expected: `header toggle click flips debug state` PASSES; `0 failed`.

- [ ] **Step 5: Lint**

Run: `luacheck .`
Expected: `0 errors`.

- [ ] **Step 6: Commit**

```bash
git add modules/DebugLog.lua tests/test_debuglog.lua
git commit -m "feat(debug): header on/off toggle in the debug console

Left-aligned title-bar control reading Debug: ON (green) / OFF (red),
styled like Copy/Clear. Clicking flips state via SetEnabled; the label
refreshes on every state change and whenever the window shows.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Docs — update CLAUDE.md debug behaviour note

**Files:**
- Modify: `CLAUDE.md` (convention cheat-sheet item 8)

**Interfaces:** none (documentation only).

- [ ] **Step 1: Update the debug convention note**

In `CLAUDE.md`, replace the item-8 sentence describing debug (currently: "Session-only debug toggle … It tracks the debug console's visibility: `/lh debug` toggles the console; closing the console (X or ESC) turns debug off.") with:
```markdown
8. **Session-only debug** flag (`NS.State.debug`, default off, resets every reload — not persisted), zero-allocation when off. State is **independent of window visibility**: `/lh debug` toggles the console window only; `/lh debug on|off` set the logging flag (capture runs even with the window closed); the header's `Debug: ON`/`OFF` toggle flips the same flag. Log lines use the tagged format `<ts>  |  [<tag>] <content>` via `NS.Debug(tag, fmt, ...)` — tag is one word, ≤10 chars. The same session-only rule applies to `/lh test` (`BrowserTable.testMode`).
```

- [ ] **Step 2: Verify the repo is still green (docs change is inert)**

Run: `lua tests/run.lua && luacheck .`
Expected: `0 failed`; `0 errors`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: describe decoupled debug state and tagged log format

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation (manual, before the standards follow-up)

Run the in-client smoke checks from the spec's Testing section:
1. `/lh debug on` with the window closed → lines accumulate in the background.
2. Open the window (`/lh debug`) → captured lines visible, mono font, header reads `Debug: ON` in green.
3. Click the header toggle → `Debug: OFF` red + chat message; `/lh debug` again toggles the window without changing state.
4. `/reload` → state resets to off.

Only once the user confirms the look and behaviour: promote the font-shipping pattern, the tagged log convention, and the decoupled-state + header-toggle behaviour into `../WowAddonStandards/standards/`. That is a separate effort, not part of this plan.
