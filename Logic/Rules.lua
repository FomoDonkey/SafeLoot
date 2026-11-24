-- PURE (no game API). The loot "contract": model, snapshot, comparison, parsing of chat/listing text,
-- agreement detection and the chat line everyone can read (docs/PROMPT_MAESTRO.md §4.1, §4.4, §10.2).
local _, SL = ...
local R = {}
SL.Rules = R

-- Enum.LootMethod (verified in Forever).
R.FREEFORALL, R.ROUNDROBIN, R.MASTER, R.GROUP, R.NEEDBEFOREGREED, R.PERSONAL = 0, 1, 2, 3, 4, 5

R.SEVERITY_INFO, R.SEVERITY_WARN, R.SEVERITY_ALERT = 1, 2, 3

-- Text normalisation (UTF-8 aware for Spanish accents) --------------------------------------------
-- Spanish, German, French and Portuguese letters (the five supported languages).
local ACCENTS = {
  ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n",
  ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ü"] = "u", ["Ñ"] = "n",
  ["ä"] = "a", ["ö"] = "o", ["Ä"] = "a", ["Ö"] = "o", ["ß"] = "ss",
  ["à"] = "a", ["â"] = "a", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["î"] = "i", ["ï"] = "i", ["ô"] = "o",
  ["û"] = "u", ["ù"] = "u", ["ç"] = "c", ["À"] = "a", ["È"] = "e", ["Ç"] = "c",
  ["ã"] = "a", ["õ"] = "o", ["Ã"] = "a", ["Õ"] = "o",
}

function R.Normalize(text)
  if type(text) ~= "string" then
    return ""
  end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  -- one pass over the two-byte UTF-8 letters (all the accents above start with byte 0xC3); skipped for ASCII text
  if text:find("[\128-\255]") then
    text = text:gsub("\195[\128-\191]", ACCENTS)
  end
  -- ASCII-only lowercase: string.lower depends on the C locale and can corrupt UTF-8 bytes on some systems.
  text = text:gsub("[A-Z]", function(c)
    return string.char(c:byte() + 32)
  end)
  -- explicit ASCII whitespace: %s can match bytes of accented letters under some C locales
  text = text:gsub("[ \t\r\n]+", " "):gsub("^ ", ""):gsub(" $", "")
  return text
end

-- Text from other players is untrusted: drop every UI escape sequence (|c colour, |r, |H link, |h, |T texture,
-- |A atlas, |K), any stray "|" (an invalid escape makes the game reject a chat line), control bytes and extra
-- spaces, and cap the length. Used for anything stored or re-sent from chat or Group Finder text.
function R.Clean(text, maxBytes)
  if type(text) ~= "string" then
    return nil
  end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    :gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", ""):gsub("|", ""):gsub("[%z\1-\31\127]", " ")
    :gsub(" +", " "):gsub("^ ", ""):gsub(" $", "")
  if text == "" then
    return nil
  end
  return R.Truncate(text, maxBytes or 80)
end

-- Cut to maxBytes without splitting a multi-byte UTF-8 letter (a broken letter makes the line invalid).
function R.Truncate(text, maxBytes, ellipsis)
  if type(text) ~= "string" or #text <= maxBytes then
    return text
  end
  local suffix = ellipsis or ""
  local cut = maxBytes - #suffix
  while cut > 0 do
    local byte = text:byte(cut + 1)
    if not byte or byte < 128 or byte >= 192 then
      break -- the next byte starts a letter: safe to cut here
    end
    cut = cut - 1
  end
  return text:sub(1, cut) .. suffix
end

-- Item names from links "|Hitem:...|h[Name]|h" in a message.
function R.ItemNames(text)
  local names = {}
  if type(text) ~= "string" then
    return names
  end
  for name in text:gmatch("|h%[(.-)%]|h") do
    names[#names + 1] = name
  end
  return names
end

-- Contract -----------------------------------------------------------------------------------------
-- contract = {
--   source = "auto" | "copied" | "proposed" | "received",
--   method, masterLooter, threshold, leader,           -- loot state the group agreed on (or found)
--   needRule = "msos" | "greed" | "upgrade" | "free" | nil,
--   boe = "greed" | nil,
--   reserves = { { item = "Hand of Dal'Rend", owner = "Krag Hierro", kind = "hard" | "soft" } },
--   accepted = { ["Krag Hierro"] = timestamp },
--   createdAt = timestamp,
-- }
function R.New(source, now)
  return { source = source or "auto", reserves = {}, accepted = {}, createdAt = now or 0 }
end

function R.FromState(state, now)
  local c = R.New("auto", now)
  if state then
    c.method, c.masterLooter, c.threshold, c.leader = state.method, state.masterLooter, state.threshold, state.leader
  end
  return c
end

local function same(a, b)
  return a == b
end

-- Compare the agreed contract (or the last state seen) with the current state.
-- Returns a list of changes { field, from, to, severity } (empty if nothing relevant changed).
function R.Diff(reference, state)
  local changes = {}
  if not reference or not state then
    return changes
  end
  local function add(field, from, to, severity)
    changes[#changes + 1] = { field = field, from = from, to = to, severity = severity }
  end
  if reference.method ~= nil and state.method ~= nil and not same(reference.method, state.method) then
    local severity = R.SEVERITY_INFO
    if state.method == R.MASTER then
      severity = R.SEVERITY_ALERT
    elseif reference.method == R.MASTER then
      severity = R.SEVERITY_INFO
    else
      severity = R.SEVERITY_WARN
    end
    add("method", reference.method, state.method, severity)
  end
  if state.method == R.MASTER and reference.method == R.MASTER and reference.masterLooter and state.masterLooter
    and not same(reference.masterLooter, state.masterLooter) then
    add("masterLooter", reference.masterLooter, state.masterLooter, R.SEVERITY_ALERT)
  end
  if reference.threshold and state.threshold and state.threshold > reference.threshold then
    add("threshold", reference.threshold, state.threshold, R.SEVERITY_WARN)
  end
  if state.method == R.MASTER and reference.leader and state.leader and not same(reference.leader, state.leader) then
    add("leader", reference.leader, state.leader, R.SEVERITY_WARN)
  end
  return changes
end

function R.MaxSeverity(changes)
  local max = 0
  for _, change in ipairs(changes or {}) do
    if change.severity > max then
      max = change.severity
    end
  end
  return max
end

-- Parsing chat / listing text ------------------------------------------------------------------------
local function has(text, patterns)
  for _, pattern in ipairs(patterns) do
    if text:find(pattern) then
      return true
    end
  end
  return false
end

-- %f[%w] frontier patterns keep "sr" from matching inside words ("señor" is normalised to "senor").
-- English abbreviations are understood everywhere; the rest covers es / de / fr / pt players.
local P_HARD = { "%f[%w]hr%f[%W]", "hard ?res", "reserva fija", "reservad[oa]", "%f[%w]res%f[%W]", "reserviert",
  "reserve pour", "reserva fixa" }
local P_SOFT = { "%f[%w]sr%f[%W]", "soft ?res", "reserva blanda" }
local P_MSOS = { "ms ?> ?os", "main ?> ?off", "principal antes", "ms ?over ?os", "%f[%w]msos%f[%W]", "haupt ?> ?neben",
  "principale avant", "principal antes da" }
local P_MASTER = { "%f[%w]ml%f[%W]", "master ?loot", "botin maestro", "maestro despojador", "plundermeister",
  "maitre du butin", "mestre saqueador" }
local P_FREE = { "%f[%w]ffa%f[%W]", "free ?roll", "%f[%w]libre%f[%W]", "%f[%w]livre%f[%W]" }
local P_GREED = { "todo codicia", "all greed", "greed all", "solo codicia", "alles gier", "nur gier", "tout en cupidite",
  "tudo ganancia", "tudo em ganancia" }
local P_BOE_GREED = { "boe ?greed", "boe a codicia", "boes? codicia", "boe gier", "lqe cupidite", "vae ganancia" }

-- Returns a partial contract (only the fields found) or nil if the text carries no rules.
-- owner: who wrote it (the reserve owner when the message says "HR <item>").
function R.Parse(text, owner)
  if type(text) ~= "string" then
    return nil
  end
  local norm = R.Normalize(text)
  if norm == "" then
    return nil
  end
  local found = {}
  local any = false
  if has(norm, P_MASTER) then
    found.method = R.MASTER
    any = true
  end
  if has(norm, P_MSOS) then
    found.needRule = "msos"
    any = true
  elseif has(norm, P_GREED) then
    found.needRule = "greed"
    any = true
  elseif has(norm, P_FREE) then
    found.needRule = "free"
    any = true
  end
  if has(norm, P_BOE_GREED) then
    found.boe = "greed"
    any = true
  end
  local kind
  if has(norm, P_HARD) then
    kind = "hard"
  elseif has(norm, P_SOFT) then
    kind = "soft"
  end
  if kind then
    any = true
    found.reserves = {}
    local items = R.ItemNames(text)
    if #items == 0 then
      -- "HR Hand of Dal'Rend, MS>OS" -> text after the keyword up to a separator
      local after = text:match("[Hh][Rr]%s+([^,;/|]+)") or text:match("[Ss][Rr]%s+([^,;/|]+)")
        or text:match("[Rr]eserva%s+%a*%s*:?%s*([^,;/|]+)")
      if after then
        after = after:gsub("%s+$", "")
        local lowered = R.Normalize(after)
        if lowered ~= "" and not has(lowered, P_MSOS) then
          items = { after }
        end
      end
    end
    for _, item in ipairs(items) do
      local clean = R.Clean(item, 60)
      if clean then
        found.reserves[#found.reserves + 1] = { item = clean, owner = R.Clean(owner, 48), kind = kind }
      end
    end
  end
  if not any then
    return nil
  end
  return found
end

-- Merge a parsed partial contract into a contract (parsed fields win).
function R.Apply(contract, partial)
  if not contract or not partial then
    return contract
  end
  for _, field in ipairs({ "method", "needRule", "boe", "masterLooter" }) do
    if partial[field] ~= nil then
      contract[field] = partial[field]
    end
  end
  if partial.reserves then
    contract.reserves = contract.reserves or {}
    for _, reserve in ipairs(partial.reserves) do
      reserve.item = R.Clean(reserve.item, 60) or "?"
      reserve.owner = R.Clean(reserve.owner, 48)
      local duplicate = false
      for _, existing in ipairs(contract.reserves) do
        if R.Normalize(existing.item) == R.Normalize(reserve.item) and existing.owner == reserve.owner then
          duplicate = true
        end
      end
      if not duplicate then
        contract.reserves[#contract.reserves + 1] = reserve
      end
    end
  end
  return contract
end

local AGREE = {
  ["ok"] = true, ["okay"] = true, ["okey"] = true, ["oki"] = true, ["vale"] = true, ["si"] = true, ["sip"] = true,
  ["yes"] = true, ["y"] = true, ["yep"] = true, ["yup"] = true, ["sure"] = true, ["+1"] = true, ["k"] = true,
  ["de acuerdo"] = true, ["perfecto"] = true, ["dale"] = true, ["np"] = true, ["agreed"] = true, ["fine"] = true,
  ["claro"] = true, ["guay"] = true, ["acepto"] = true,
  -- de / fr / pt
  ["ja"] = true, ["jo"] = true, ["jap"] = true, ["passt"] = true, ["einverstanden"] = true, ["klar"] = true,
  ["oui"] = true, ["ouais"] = true, ["d'accord"] = true, ["dac"] = true, ["ca marche"] = true, ["parfait"] = true,
  ["sim"] = true, ["beleza"] = true, ["blz"] = true, ["fechado"] = true, ["certo"] = true, ["combinado"] = true,
}

-- True if a chat line is a short "yes" (the whole message, ignoring punctuation and emoji).
function R.IsAgreement(text)
  if type(text) ~= "string" then
    return false
  end
  local norm = R.Normalize(text)
  if #norm > 24 then
    return false
  end
  -- (multi-byte "¡" removed on its own: inside a [] class its bytes would cut other UTF-8 letters)
  norm = norm:gsub("¡", ""):gsub("[!%.,]+", ""):gsub("%s+$", ""):gsub("^%s+", "")
  if AGREE[norm] then
    return true
  end
  local word = norm:match("^(%S+)")
  return word ~= nil and AGREE[word] == true and #norm <= 10
end

-- Reserve lookup -------------------------------------------------------------------------------------
-- Returns the reserves whose item matches the given item name.
function R.ReservesFor(contract, itemName)
  local result = {}
  if not contract or not contract.reserves or type(itemName) ~= "string" then
    return result
  end
  local target = R.Normalize(itemName)
  for _, reserve in ipairs(contract.reserves) do
    if R.Normalize(reserve.item) == target then
      result[#result + 1] = reserve
    end
  end
  return result
end

-- The chat line (<= 255 bytes) -----------------------------------------------------------------------
-- L supplies the words: L.CHAT_PREFIX, L.METHOD_n, L.NEED_<rule>, L.BOE_GREED, L.CHAT_RESERVE, L.CHAT_ASK.
function R.ChatLine(contract, L)
  local parts = {}
  if contract.method ~= nil then
    parts[#parts + 1] = L["METHOD_" .. contract.method] or tostring(contract.method)
  end
  if contract.method == R.MASTER and contract.masterLooter then
    parts[#parts] = parts[#parts] .. " (" .. contract.masterLooter .. ")"
  end
  if contract.needRule then
    parts[#parts + 1] = L["NEED_" .. contract.needRule] or contract.needRule
  end
  if contract.boe == "greed" then
    parts[#parts + 1] = L.BOE_GREED
  end
  for _, reserve in ipairs(contract.reserves or {}) do
    local who = reserve.owner and (reserve.owner .. " → ") or ""
    parts[#parts + 1] = (reserve.kind == "soft" and "SR " or "HR ") .. who .. reserve.item
  end
  local line = L.CHAT_PREFIX .. " " .. table.concat(parts, " · ") .. ". " .. L.CHAT_ASK
  return R.Truncate(line, 255, "...")
end
