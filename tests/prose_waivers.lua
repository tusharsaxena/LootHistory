-- Prose-gate waivers (localization-§5), per file AND per word, each with its reason.
-- Read by tests/_kit/test_prose.lua; nothing loads this file in the client.
return {
  waived = {
    -- `FulfillCraftingOrder` is a Blizzard enum member name (Enum.CurrencyDestroyReason), keyed by
    -- name in C.CURRENCY_SOURCE_REASON. Game data: the US-spelled identifier lowercases into one
    -- token that contains the British substring, so the whole-word allowance cannot catch it.
    ["core/Constants.lua"] = { fulfil = true },
  },
}
