-- tests/prose_waivers.lua -- what the kit's US-English gate MUST NOT correct here.
--
-- Read by `tests/_kit/test_prose.lua` (localization-5). Per FILE and per WORD, never per file
-- alone: a whole-file waiver hides every OTHER British spelling in a file this repo edits often,
-- and `core/LifecycleSetup.lua` is one of them.
--
-- Every entry carries its reason. A waiver with no stated reason is indistinguishable from a
-- spelling nobody got round to fixing, and the next sweep either re-fixes it or widens it.
--
-- This file replaced tests/test_prose.lua, the hand-written copy of the gate this repo kept beside
-- the kit's. localization-5 says wire one or the other, never both, and the runner's bare
-- "test_prose" entry was running the local copy while the kit's loaded nothing (kit revision 25's
-- pair-keyed inventory calls that a shadow). The one waiver below is the one that copy carried.

return {
    waived = {
        -- `cancelled` is AceTimer-3.0's field name, not this repo's prose. `NS.After` records the
        -- flag on its own handle as `h.cancelled` (`:66`, `:79`) because that is the field
        -- `tests/_kit/mock_record.lua`'s live-timer survey reads off a handle, and what AceTimer
        -- calls the same field. A US respelling would not be a correction: the survey would stop
        -- seeing a canceled deferral as canceled, and tests/test_disabled.lua's timer assertion
        -- would go quietly unfalsifiable, which slash-commands-7 forbids. localization-5 names
        -- this exact case as its first legitimate waiver shape.
        ["core/LifecycleSetup.lua"] = { cancelled = true },
    },
}
