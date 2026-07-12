# Debug Window Overhaul — Design

**Date:** 2026-07-12
**Addon:** Ka0s Loot History
**Status:** Approved for planning

## Goal

Make the debug console more usable and consistent, and establish a debug
convention worth promoting to the Ka0s standard (`../WowAddonStandards`) once
proven here. Four changes:

1. Ship and use a monospace font in the debug window.
2. Adopt a fixed-format, tagged log line convention.
3. Decouple debug *state* from debug *window visibility*.
4. Add an in-window debug on/off toggle in the header.

Non-goals: no persistence of debug state across reloads (stays session-only,
default off); no changes to the History browser, analytics, or collection
pipeline beyond updating debug call sites.

---

## 1. Ship & use a monospace font

- **Font:** JetBrains Mono (OFL). Vendor the **static** `JetBrainsMono-Regular.ttf`
  (not the variable font — WoW's font engine needs a static TTF) plus its
  `OFL.txt` license under `media/fonts/`.
- **Sourcing:** download the TTF from the official JetBrains Mono release (OFL,
  freely redistributable). **Fallback:** if this environment has no network,
  vendor DejaVu Sans Mono (present locally under `/usr/share/fonts`, also freely
  redistributable) and flag the substitution to the user before settling.
- **Registration:** register with LibSharedMedia-3.0 (already vendored) at init:
  `LSM:Register("font", "JetBrains Mono", NS.Constants.FONT_MONO)`. This makes the
  font reusable and makes the standards follow-up trivial.
- **Constant:** add `NS.Constants.FONT_MONO` = vendored TTF path.
- **Application:** apply via `SetFont(path, 12, "")` to:
  - the debug **log** (`ScrollingMessageFrame`), and
  - the **Copy** window edit box.
  Title bar and header text buttons keep the default WoW UI font.
- **TOC:** the `.ttf` and `OFL.txt` are data files (not `.lua`), so no TOC load
  entry is required; they ship in the addon folder and are referenced by path.

---

## 2. Tagged log-line convention

**Format:** `<HH:MM:SS>  |  [<Tag>] <content>`

- `NS.Debug` gains an explicit tag argument: **`NS.Debug(tag, fmt, ...)`**.
- The tag renders inside the brackets, left-justified and padded/truncated to a
  fixed 10 characters: Lua `("[%-10.10s]"):format(tag)`. Padding is **inside**
  the brackets so the closing `]` and all following content align.
- One space separates the `]` from the content.

Example:

```
15:04:36  |  [Debug    ] logging enabled
15:04:43  |  [Cast     ] player spell=3365 craft=false
15:04:43  |  [Attr     ] consume -> OTHER (INFERRED) — no fresh context
15:04:43  |  [Loot     ] Tome of Polymorph q1 ilvl=- src=OTHER conf=INFERRED
15:05:25  |  [Open     ] slot=1 guid=GameObject-…-0000D2D2D2 -> CONTAINER
15:05:25  |  [Attr     ] stamp CONTAINER via LOOT_OPENED
15:05:25  |  [Loot     ] Tome of Polymorph q1 ilvl=- src=CONTAINER conf=CERTAIN
15:05:43  |  [Quest    ] stamp QUEST via QUEST_TURNED_IN [quest=92120]
```

**Convention rule (documented, later promoted to the standard):** a tag is one
word, ≤10 characters, giving a good idea of what the debug statement is doing.
The set is open — modules add/remove tags as needed. Anything longer than 10
chars is truncated by the format, so authors must pick a tag that fits.

**Call-site mapping** (16 existing `NS.Debug` sites):

| Current inline prefix                     | New tag   |
|-------------------------------------------|-----------|
| `cast:`                                   | `Cast`    |
| `loot:`                                   | `Loot`    |
| `consume` / `stamp` / `context:`          | `Attr`    |
| `LOOT_OPENED …`                           | `Open`    |
| `UseContainerItem …`                      | `Open`    |
| `mail-take …`                             | `Mail`    |
| `debug logging enabled`                   | `Debug`   |

The plain-text Copy buffer mirrors the exact same formatted line (minus colour
codes), so copied logs read identically to the on-screen log.

---

## 3. Decouple debug state from window visibility

Today `NS.State.debug` is driven by the window's `OnShow`/`OnHide` hooks:
showing the console enables logging, closing it disables logging. This change
makes state **independent** so logging can run in the background with the window
closed.

- Remove the `OnShow`/`OnHide` hooks in `DebugLog.lua` that mutate `NS.State.debug`.
- `NS.State.debug` remains a **session-only** flag: default off, reset on every
  `/reload` and fresh login. Not persisted, not a Schema row (unchanged).
- Slash `/lh debug` dispatch (`settings/Schema.lua` COMMANDS + `Slash.lua`):
  - `/lh debug` → **toggle the window only**; state untouched.
  - `/lh debug on` → set `NS.State.debug = true`, print the chat confirmation.
  - `/lh debug off` → set `NS.State.debug = false`, print the chat confirmation.
- The `debug` command's `fn` receives the remainder (`rest`) already, so it can
  branch on `on`/`off`/empty.
- A single internal seam sets debug state (e.g. `NS.DebugLog:SetEnabled(bool)`)
  so the slash path, the header toggle, and any future caller all print the same
  chat message and refresh the header the same way.

Chat messages on state change are preserved exactly as today (e.g.
`Ka0s Loot History debug on` / `… off`).

---

## 4. Header debug toggle

- A flat text control on the **left** side of the title bar, left-aligned,
  styled like the existing Copy/Clear text buttons (same `makeTextButton` look:
  small font, grey idle, gold on hover).
- Label reflects state: **`Debug: ON`** in green (`0, 1, 0`-ish) when on,
  **`Debug: OFF`** in red (`1, 0.2, 0.2`-ish) when off. The colour is the resting
  colour; hover still lightens as with the other buttons.
- Click flips `NS.State.debug` via the same `SetEnabled` seam used by the slash
  command → prints the chat message and re-renders the label.
- The label refreshes on **every** state change, whether triggered by the click
  or by `/lh debug on|off`, so the header is always accurate even if state was
  changed from the slash line while the window was open.
- Because state no longer follows visibility, opening/closing the window does
  **not** change the toggle or logging.

---

## Files touched

- `media/fonts/JetBrainsMono-Regular.ttf`, `media/fonts/OFL.txt` — new (vendored).
- `core/Constants.lua` — add `FONT_MONO` path constant.
- `core/LootHistory.lua` (or init seam) — register font with LibSharedMedia.
- `modules/DebugLog.lua` — mono font on log + copy box; remove OnShow/OnHide
  state hooks; add `SetEnabled` seam; add header toggle; update `D:Add` to the
  tagged format with a `tag` argument.
- `core/*` / `modules/Attribution.lua` / `modules/Collector.lua` — update all 16
  `NS.Debug(...)` call sites to pass a tag.
- `settings/Schema.lua` (`COMMANDS.debug`) + `settings/Slash.lua` — parse
  `on`/`off`/empty for `/lh debug`.
- `tests/` — cover the tag formatting helper and the `on`/`off`/toggle dispatch.
- Docs: update `CLAUDE.md` convention note (§8 debug behaviour) to match the new
  `/lh debug on|off|toggle` semantics.

## Testing

- Headless (`lua tests/run.lua`): unit-test the tag-format helper (padding,
  truncation of >10-char tags, separator) and the `/lh debug` dispatch branching
  (`on` → state true, `off` → state false, empty → window toggle only, state
  unchanged).
- `luacheck .` → 0 errors.
- In-client smoke: `/lh debug on` with window closed captures lines in the
  background; open window shows them; header reads `Debug: ON` green; click →
  `Debug: OFF` red + chat message; `/lh debug` toggles the window without
  touching state; `/reload` resets state to off.

## Follow-up (separate, after user is satisfied)

Promote the font-shipping pattern, the tagged log-line convention, and the
decoupled debug-state + header-toggle behaviour into
`../WowAddonStandards/standards/` so all Ka0s addons can adopt it. Not part of
this implementation; done only once the user confirms the look and behaviour.
