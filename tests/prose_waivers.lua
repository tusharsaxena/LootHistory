-- Prose-gate waivers (localization-§5), per file AND per word, each with its reason.
-- Read by tests/_kit/test_prose.lua; nothing loads this file in the client.
return {
  waived = {
    -- `FulfillCraftingOrder` is a Blizzard enum member name (Enum.CurrencyDestroyReason), keyed by
    -- name in C.CURRENCY_SOURCE_REASON. Game data: the US-spelled identifier lowercases into one
    -- token that contains the British substring, so the whole-word allowance cannot catch it.
    ["core/Constants.lua"] = { fulfil = true },
    -- `Compat.AuctionMailKind` returns the kind "cancelled": the task-5 contract string the ledger
    -- reason map keys on, and the spelling of Blizzard's own enUS AUCTION_REMOVED_MAIL_SUBJECT
    -- ("Auction cancelled: %s"). Game data, not authored prose.
    ["core/Compat.lua"] = { cancelled = true },
    ["docs/compat-layer.md"] = { cancelled = true },   -- the shim row quotes the returned kind
    -- The mock mirrors the same two game strings: that subject text and the Enum member name.
    ["tests/wow_mock.lua"] = { cancelled = true, fulfil = true },
    -- The simulator suites' clock reads the kit mock's timer field `cancelled` (AceTimer's own
    -- name for it, set by tests/_kit/mock_record.lua): a library's field name, not authored prose.
    ["tests/sim_support.lua"] = { cancelled = true },
    -- `minimise` is a LibKa0s-Media catalog name (the Open Iconic mark's file name, minimise.tga):
    -- the icon declaration line and its prose name the file, not authored text.
    ["CLAUDE.md"] = { minimis = true },
    ["modules/FarmPanel.lua"] = { minimis = true },      -- the panel's minimize mark names that file
    ["tests/test_farm_panel.lua"] = { minimis = true },  -- ...and its suite asserts the art
    ["tests/test_mediasetup.lua"] = { minimis = true },  -- ...and the drawn-icon list records it
  },
}
