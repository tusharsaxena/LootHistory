local addonName, NS = ...
NS.Attribution = NS.Attribution or {}
local Attribution = NS.Attribution

-- Source-resolution engine. Stamps a short-lived loot context from peripheral events and
-- consumes it on CHAT_MSG_LOOT (see docs/TECHNICAL_DESIGN §4).

local State = NS.State
local Constants = NS.Constants

-- Stamp the single-slot loot context. Consumed by the collector on the next self-loot line(s)
-- within CONTEXT_TTL. Not cleared on consume: one loot window emits many lines sharing a source.
function Attribution:Stamp(source, name, detail, confidence)
  State.lootContext = {
    source = source,
    name = name,
    detail = detail,
    confidence = confidence or Constants.Confidence.CERTAIN,
    expires = GetTime() + Constants.CONTEXT_TTL,
  }
end

-- Read the current context. Returns source, name, detail, confidence when fresh;
-- OTHER / nil / nil / INFERRED when stale or unstamped.
function Attribution:Consume()
  local c = State.lootContext
  if c and c.expires >= GetTime() then
    return c.source, c.name, c.detail, c.confidence
  end
  return Constants.SourceType.OTHER, nil, nil, Constants.Confidence.INFERRED
end
