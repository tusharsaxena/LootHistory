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
  },
}
