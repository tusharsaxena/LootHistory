-- LibKa0s-Callout-1.0 — CalloutSound.lua: what a call-out says, a pack line or the client's speech.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Callout.lua ──────────────────────────────────
--
-- Because of `layout-§1`. Callout.lua reached 1416 lines (FU-LK-CALLOUT of Ka0sAddonsCommonTasks
-- docs/2026-11-21-SYNC_FOLLOWUPS); the write route left for CalloutRoute.lua, and the sound section,
-- the second seam its census entry named, moved here at Callout minor 6, unchanged, with the one
-- verb that reads it (`TtsVoices`). The voice setting and its packs are the shell's header (SOUND)
-- and the shell's `lib.PACKS`. It is NOT a major of its own: it is part of `LibKa0s-Callout-1.0`,
-- paired on the shell's minor.
--
-- WHAT CROSSES THE CUT. Callout.lua publishes `lib.__methods` and `lib.__calloutKit` (the readers,
-- the stored settings and the voice the instance speaks); this file publishes `lib.__sound`, which the
-- shell's present() calls at call time. A payload without this file shows call-outs silently, and its
-- instances have no TtsVoices.
--
-- Depends on LibStub and the Callout shell. PlaySoundFile and C_VoiceChat are read at call time and
-- optional, as before.

local lib = LibStub and LibStub("LibKa0s-Callout-1.0", true)
if not lib or type(lib.__methods) ~= "table" or type(lib.__calloutKit) ~= "table" then return end

local SOUND_MINOR = 1
-- Minor 1: the sound section and TtsVoices of Callout minor 5, moved unchanged (Callout minor 6).
-- Paired on the SHELL's minor as well as this file's own, as CalloutSettings.lua is.
if lib.__soundMinor and lib.__soundMinor >= SOUND_MINOR
  and lib.__soundShellMinor == lib.MINOR then return end
lib.__soundMinor      = SOUND_MINOR
lib.__soundShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.CalloutSound = SOUND_MINOR

local METHODS = lib.__methods
local kit = lib.__calloutKit
local nonEmpty, finite, logOnce, get, voiceOf = kit.nonEmpty, kit.finite, kit.logOnce, kit.get, kit.voiceOf
local PACK = kit.PACK

-- ── the sound ────────────────────────────────────────────────────────────────────────────────

local function soundsBase(S)
  if nonEmpty(S.d.soundsBase) then return S.d.soundsBase end
  if not nonEmpty(S.d.addon) then return nil end
  return "Interface\\AddOns\\" .. S.d.addon .. "\\" .. (S.d.vendorPath or "libs\\LibKa0s")
    .. "\\media\\sounds\\callout"
end

local function playFile(S, file)
  if type(PlaySoundFile) ~= "function" then
    logOnce(S, "no PlaySoundFile: call-outs are silent")
    return false
  end
  if PlaySoundFile(file, get(S, "channel")) == false then
    logOnce(S, "sound file missing, silent: " .. tostring(file))
    return false
  end
  return true
end

local function playLine(S, voice, line)
  local base = soundsBase(S)
  if not base then
    logOnce(S, "no d.addon or d.soundsBase: the voice packs cannot be found")
    return false
  end
  return playFile(S, base .. "\\" .. PACK[voice].folder .. "\\" .. line .. lib.SOUND_EXT)
end

--- The player's TTS voice when the client still has it, else the client's first voice.
local function ttsVoiceId(S, voices)
  local want = get(S, "ttsVoice")
  for _, v in ipairs(voices) do
    if v.voiceID == want then return want end
  end
  return voices[1] and voices[1].voiceID
end

local function ttsVoices()
  local vc = C_VoiceChat
  local list = vc and vc.GetTtsVoices and vc.GetTtsVoices()
  local out = {}
  if type(list) ~= "table" then return out end
  for _, v in ipairs(list) do
    if type(v) == "table" and finite(v.voiceID) then
      out[#out + 1] = { voiceID = v.voiceID, name = tostring(v.name or v.voiceID) }
    end
  end
  return out
end

local function speak(S, text)
  local vc = C_VoiceChat
  if not (vc and vc.SpeakText) then
    logOnce(S, "no C_VoiceChat.SpeakText: text to speech is silent")
    return false
  end
  local id = ttsVoiceId(S, ttsVoices())
  if not id then
    logOnce(S, "no text to speech voice installed")
    return false
  end
  vc.SpeakText(id, text, get(S, "ttsRate"), get(S, "ttsVolume"), true)
  return true
end

--- What an entry says, by the voice setting. Answers whether anything was played.
local function sound(S, entry)
  if entry.voice == false then return false end
  if entry.stock and get(S, "muted")[entry.key] then return false end
  local voice = voiceOf(S)
  if voice == lib.OFF then return false end
  if entry.sound then return playFile(S, entry.sound) end
  if entry.number and entry.number > get(S, "speakFrom") then return false end
  if voice == lib.TTS then return speak(S, entry.say or entry.text) end
  if entry.line then return playLine(S, voice, entry.line) end
  return false
end

--- The client's text to speech voices, { voiceID, name } each; empty without C_VoiceChat.
function METHODS:TtsVoices()   -- luacheck: ignore 212/self
  return ttsVoices()
end

-- What the shell's present() plays an entry with, read at call time.
lib.__sound = sound
