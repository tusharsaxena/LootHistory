-- LibKa0s-Perf-1.0 — the command surface a host wires into its own slash table.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Perf.lua ─────────────────────────────────────
--
-- Because of `layout-§1`. Perf.lua stood at 1319 lines, in the 1000–1500 band, and issue #7 asked
-- for a peel. The issue named the sampler as the seam, but the sampler reads about ten of
-- lib:New's closure locals (the sampler frame, the FPS arms, the windows, the buckets), and every
-- one would have to be threaded through. The command surface reads four things — the instance, the
-- descriptor, the lifecycle latch on it and the host's `showLog` sink — and calls everything else
-- through members of the instance, so it moved here unchanged at Perf minor 14 instead.
--
-- It is NOT a major of its own: it is part of `LibKa0s-Perf-1.0`, guarded with PerfPanel.lua's
-- multi-file idiom, so a command surface from one vendored copy never pairs with a probe from
-- another without saying so. lib:New calls lib.__installCommands(P, ctx) where the block used to
-- be. A payload without this file still builds instances, and P.OnCommand, P.Usage and
-- P.StatusLines each answer one line naming the missing file (Perf.lua's stub).

local lib = LibStub and LibStub("LibKa0s-Perf-1.0", true)
if not lib then return end

local COMMANDS_MINOR = 1
-- Paired on the PROBE's minor as well as this file's own, as PerfPanel.lua is: a command surface
-- that attached to an older probe would install handlers written against members that probe may
-- not have, and nothing would say the two came from different vendored copies.
if lib.__commandsMinor and lib.__commandsMinor >= COMMANDS_MINOR
  and lib.__commandsShellMinor == lib.MINOR then return end
lib.__commandsMinor      = COMMANDS_MINOR
lib.__commandsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.PerfCommands = COMMANDS_MINOR

--- Install the command surface on one instance. Called by lib:New with the instance and the
--- closure values the surface reads: `ctx.d` (the descriptor, whose `lifecycle` is the latch) and
--- `ctx.showLog` (the host's sink, or a no-op).
function lib.__installCommands(P, ctx)
  local d, showLog = ctx.d, ctx.showLog
  local lc = d.lifecycle

  -- ── Command surface ──────────────────────────────────────────────────────────────────────
  --
  -- The lib MUST NOT register a slash command of its own — the Ka0s standard mandates schema-driven
  -- dispatch through each addon's own COMMANDS table, and third-party hosts do not use that pattern
  -- at all. What the lib supplies is behavior and help text; the host owns its slash surface and
  -- decides how `perf` is reached. OnCommand returns lines rather than printing them, which is also
  -- what lets a panel click and a typed command run the identical code path.

  --- Help text for the host to print. Returned rather than printed, so a host can fold it into its
  --- own help output however it likes.
  function P.Usage()
    local s = P.slash
    -- ONE ROW PER VERB, through lib.FormatRow -- the same formatter the slash-command help uses,
    -- which is why that block reads cleanly and this one did not. It hand-aligned a second column
    -- with leading spaces and pushed the rest of each description onto a continuation line; chat is
    -- a PROPORTIONAL font and wraps on its own, so the columns never lined up and the continuations
    -- arrived as orphaned fragments under the wrong verb.
    --
    -- THE PIPES ARE DOUBLED, and that is a real bug rather than tidiness. `<...|cancel|report|...>`
    -- put `|r` in a chat string, which the client reads as a color RESET and removes -- the words
    -- fused into "canceleport", `show|hide|toggle` lost `|h` and `|t` the same way, and the eaten
    -- reset left the whole line gold because the run it was meant to close never closed. `||` is
    -- the escape for a literal pipe.
    -- Reached through LibStub rather than duplicated: the Slash major's API document calls
    -- FormatRow "the one command-row formatter in the collection", and a second copy here would
    -- make that sentence false. Optional, in the idiom this file already uses for Core -- and
    -- degrading to an uncolored row rather than to a second gold format, because a duplicate that
    -- only appears when a library is missing is still a duplicate.
    local slash = LibStub and LibStub("LibKa0s-Slash-1.0", true)
    local row = (slash and slash.FormatRow)
      or function(c, dsc) return ("%s \226\128\148 %s"):format(tostring(c), tostring(dsc)) end
    return {
      ("usage: |cFFFFFF00%s perf <start||measure||finish||cancel||report||show||hide||toggle>|r")
        :format(s) .. " \226\128\148 or just click the panel",
      "  " .. row("start [label]",
        "begin a run; zeroes the counters and records who and where you are"),
      "  " .. row("measure a",
        "arm Experiment A, addon ACTIVE \226\128\148 records only while combat lasts"),
      "  " .. row("measure b",
        "arm Experiment B \226\128\148 the same, with the addon suspended first"),
      "  " .. row("finish",
        ("end the run and save it to %s; prints nothing, and `/reload` flushes it"):format(d.sv)),
      "  " .. row("cancel",
        "abandon a run in flight \226\128\148 discards it unsaved and restores the addon"),
      "  " .. row("report",
        "print the summary and the JSON line to copy; opens the log window if hidden"),
      "  " .. row("show / hide / toggle",
        "the step panel \226\128\148 hiding it never touches the run"),
    }
  end

  -- Sub-verb handlers, one entry each. A dispatch table rather than an if/elseif ladder: the ladder
  -- form measured CCN 24 under `lizard`, the worst in the addon this was extracted from, purely
  -- from the shape of the dispatch. Each handler here is CCN 1-3 and reads on its own.
  --
  -- Handlers take (out, rest) and append chat lines to `out`. Returning lines rather than printing
  -- them is what lets the host own its output — and is why the lib needs no chat frame of its own.
  local SUBS = {}

  -- `rest` is the free text after the sub-verb: an optional capture label. Captures accumulate in a
  -- ring across sessions, so an auto-timestamp alone makes two runs from the same afternoon
  -- near-impossible to tell apart when reading the SavedVariables file later. A supplied label is
  -- appended to the timestamp, never replaces it.
  function SUBS.start(out, rest)
    local stamp = date and date("%Y-%m-%d %H:%M") or "capture"
    local label = (rest or ""):match("^%s*(.-)%s*$")
    P.Start(label ~= "" and (stamp .. " " .. label) or stamp)
    P.Announce("perf run |cff40ff40STARTED|r \226\128\148 %s", P.label or "unlabeled")
    for _, line in ipairs(P.ContextLines(P.context)) do out[#out + 1] = line end
    showLog()
    -- The clickable equivalent of the steps just printed. Chat scrolls away the moment combat
    -- starts; the panel does not.
    P.ShowPanel()
  end

  function SUBS.measure(out, rest)
    local token = (rest or ""):match("^(%S*)")
    local armName, err = P.Measure(token)
    if not armName then
      if err == "no experiment" then
        out[#out + 1] = ("start one first \226\128\148 `%s perf start`"):format(P.slash)
      else
        out[#out + 1] = ("unknown window '%s' \226\128\148 use `measure a` or `measure b`")
          :format(token ~= "" and token or "?")
      end
      return
    end
    out[#out + 1] = ("Experiment |cFFFFFF00%s|r |cffffff00ARMED|r (%s) \226\128\148 recording starts "
      .. "when combat does, and ends when combat does"):format(token:upper(),
      armName == "suspended" and "addon |cffff4040SUSPENDED|r" or "addon |cff40ff40active|r")
  end

  function SUBS.show()   P.ShowPanel()   end
  function SUBS.hide()   P.HidePanel()   end
  function SUBS.toggle() P.TogglePanel() end

  function SUBS.cancel(out)
    if not P.Cancel() then
      out[#out + 1] = "no perf run to cancel"
      return
    end
    out[#out + 1] = "perf run |cffcc5252CANCELED|r \226\128\148 nothing saved"
  end

  function SUBS.finish(out)
    if not P.run then
      out[#out + 1] = ("no perf run is active \226\128\148 `%s perf start`"):format(P.slash)
      return
    end
    local record = P.Stop()
    -- RELEASE THE PERF HOLD BEFORE SAVING OR FORMATTING (performance-§6). Experiment B leaves the
    -- hold taken, and with no manual resume verb the only other way back is a /reload — so a raise
    -- inside Save or FormatReport must not be able to strand the hold for the rest of the session.
    -- Ordering is what guarantees that, not a pcall: by the time anything below can fail, the hold
    -- is already gone and the latch has already decided whether the addon stands up.
    --
    -- Whether it DID stand up is the latch's answer, and the line follows it. A run finished on an
    -- addon the player disabled mid-capture releases `perf`, keeps `disabled`, and stays down;
    -- announcing "restored" there would be the bare stand-up the latch exists to prevent, written
    -- as chat text.
    if P.suspended then
      P.Resume()
      out[#out + 1] = (not lc:IsDown())
        and "addon |cff40ff40RESUMED|r \226\128\148 restored"
        or "perf hold |cffffff00RELEASED|r \226\128\148 the addon stays down"
    end
    P.Save(record)
    -- Deliberately does NOT print the summary. `finish` fires the moment a fight ends, when the log
    -- is buried under combat output and the numbers scroll past unread.
    P.Announce("perf run |cffff4040FINISHED|r \226\128\148 saved; `Report` or `Dump` in the panel "
      .. "to read it, `/reload` to flush it to SavedVariables")
    -- One line about the budgets (issue #1), and only for a host that declares any: an un-adopted
    -- host's acknowledgment is unchanged. Report-only — the run is already saved and nothing here
    -- refuses or raises on OVER; `report` names which buckets and by how much.
    local over = lib.__budgetOver and lib.__budgetOver(P, record)
    if over then
      out[#out + 1] = ("%d bucket(s) over budget \226\128\148 `report` for which"):format(over)
    end
  end

  -- ONE STEP, TWO ARTIFACTS. `dump` was a verb and a panel step of its own until 2026-09-09. Both
  -- halves go to the same log, both describe the same finished run, and the perf-analysis workflow
  -- asks for BOTH -- so splitting them was a second click, a second thing to remember, and a run
  -- reported without its dump was the easy mistake to make.
  --
  -- The summary first and the JSON last, deliberately: the summary is what a person reads and the
  -- JSON is what they copy, and a copy-paste starts at the bottom of the window.
  function SUBS.report()
    showLog()
    local record = P.BuildRecord(P.label)
    for _, line in ipairs(P.FormatReport(record)) do P.Log(line) end
    P.Log(lib.EncodeJSON(record))
    P.MarkReviewed("report")
  end

  --- Phase summary plus the usage. Bare `<slash> perf` IS the entry point: the panel's first row
  --- starts a run, so this is how someone who remembers one command reaches all of them.
  function P.StatusLines()
    local phase = "|cffff4040stopped|r"
    if P.recording then
      phase = ("|cff40ff40SAMPLING window %s|r"):format(P.recording)
    elseif P.armed then
      phase = ("|cffffff00window %s armed|r \226\128\148 waiting for combat"):format(P.armed)
    elseif P.run then
      phase = "|cffffff00run active|r \226\128\148 no experiment armed"
    end
    local out = { ("perf %s, addon %s"):format(phase,
      P.suspended and "|cffff4040SUSPENDED|r" or "|cff40ff40active|r") }
    for _, line in ipairs(P.Usage()) do out[#out + 1] = line end
    return out
  end

  --- Run one perf sub-command. `args` is everything after the host's own `perf` verb. Returns the
  --- chat lines the host should print — never nil, so a caller can always ipairs() the result.
  function P.OnCommand(args)
    args = tostring(args or "")
    -- A panel row hands back its full command ("perf measure a"); a slash handler hands back only
    -- what followed its own verb. Accept both so the two paths cannot diverge.
    args = args:gsub("^%s*perf%s*", "")
    local sub = (args:match("^(%S*)") or ""):lower()
    local handler = SUBS[sub]
    if not handler then
      P.ShowPanel()
      return P.StatusLines()
    end
    local out = {}
    handler(out, args:match("^%S*%s+(.*)$"))
    return out
  end

end
