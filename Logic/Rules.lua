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
  -- (item links of the Forever client use named colours, "|cnIQ3:", besides the classic "|cff0070dd")
  text = text:gsub("|cn[%w_]+:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
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
  text = text:gsub("|cn[%w_]+:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
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

-- Like Clean, but keeps well-formed item links ("|c..|Hitem:..|h[Name]|h|r") so a published line shows real,
-- hoverable items. Any other "|" code is still removed; if the links make it too long, plain names are sent.
local ITEM_LINK = "|c[%w_:]+|Hitem:[%d:%-]+|h%[[^%]|]+%]|h|r"
function R.CleanChat(text, maxBytes)
  if type(text) ~= "string" then
    return nil
  end
  local links = {}
  local masked = text:gsub(ITEM_LINK, function(link)
    links[#links + 1] = link
    return "{{SL" .. #links .. "}}"
  end)
  local clean = R.Clean(masked, 4000)
  if not clean then
    return nil
  end
  clean = clean:gsub("{{SL(%d+)}}", function(i)
    return links[tonumber(i)] or ""
  end)
  if #clean > (maxBytes or 255) then
    return R.Clean(text, maxBytes or 255)
  end
  return clean
end

-- Item links in a message: { { name, id } }.
function R.ItemLinks(text)
  local links = {}
  if type(text) ~= "string" then
    return links
  end
  for id, name in text:gmatch("|Hitem:(%d+)[^|]*|h%[(.-)%]|h") do
    links[#links + 1] = { name = name, id = tonumber(id) }
  end
  return links
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
--   reserves = { { item = "Hand of Dal'Rend", itemID = 12940 | nil, owner = "Krag Hierro", kind = "hard" | "soft" } },
--   instance = mapID | nil (the dungeon or raid the group is going to),
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
    -- master loot (one person decides) and free for all (anyone loots anything, no roll) are the risky ones
    if state.method == R.MASTER or state.method == R.FREEFORALL then
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
-- (no bare "res": in WoW it means a resurrection, "res pls")
local P_HARD = { "%f[%w]hr%f[%W]", "hard ?res", "reserva fija", "reservad[oa]", "reserviert", "reserve pour",
  "reserva fixa" }
local P_SOFT = { "%f[%w]sr%f[%W]", "soft ?res", "reserva blanda" }
local P_MSOS = { "ms ?> ?os", "main ?> ?off", "principal antes", "ms ?over ?os", "%f[%w]msos%f[%W]", "haupt ?> ?neben",
  "principale avant", "principal antes da" }
local P_MASTER = { "%f[%w]ml%f[%W]", "master ?loot", "botin maestro", "maestro despojador", "plundermeister",
  "maitre du butin", "mestre saqueador" }
-- (no bare "libre": "estoy libre" is not a loot rule)
local P_FREE = { "%f[%w]ffa%f[%W]", "free ?roll", "tirada libre", "roll libre", "botin libre", "todo libre",
  "rolagem livre", "jet libre" }
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
    local items = R.ItemLinks(text)
    if #items == 0 then
      -- "HR Hand of Dal'Rend, MS>OS" -> text after the keyword up to a separator
      local after = text:match("[Hh][Rr]%s+([^,;/|]+)") or text:match("[Ss][Rr]%s+([^,;/|]+)")
        or text:match("[Rr]eserva%s+%a*%s*:?%s*([^,;/|]+)")
      if after then
        after = after:gsub("%s+$", "")
        local lowered = R.Normalize(after)
        if lowered ~= "" and not has(lowered, P_MSOS) then
          items = { { name = after } }
        end
      end
    end
    for _, item in ipairs(items) do
      local clean = R.Clean(item.name, 60)
      if clean then
        found.reserves[#found.reserves + 1] = { item = clean, itemID = item.id, owner = R.Clean(owner, 48), kind = kind }
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
      reserve.itemID = type(reserve.itemID) == "number" and reserve.itemID or nil
      local duplicate
      for _, existing in ipairs(contract.reserves) do
        local sameItem = (existing.itemID and reserve.itemID and existing.itemID == reserve.itemID)
          or R.Normalize(existing.item) == R.Normalize(reserve.item)
        if sameItem and existing.owner == reserve.owner then
          duplicate = existing
        end
      end
      if duplicate then
        -- the same item for the same person again: the newest choice (HR / SR) wins, nothing is listed twice
        duplicate.kind = reserve.kind or duplicate.kind
        duplicate.itemID = duplicate.itemID or reserve.itemID
      else
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
  ["claro"] = true, ["guay"] = true, ["acepto"] = true, ["yap"] = true, ["ya"] = true, ["va"] = true,
  ["okis"] = true, ["oke"] = true, ["okk"] = true, ["okay!"] = true, ["vale vale"] = true, ["si si"] = true,
  ["por mi bien"] = true, ["me vale"] = true, ["bien"] = true, ["yeah"] = true, ["yea"] = true, ["kk"] = true,
  -- de / fr / pt
  ["ja"] = true, ["jo"] = true, ["jap"] = true, ["passt"] = true, ["einverstanden"] = true, ["klar"] = true,
  ["oui"] = true, ["ouais"] = true, ["d'accord"] = true, ["dac"] = true, ["ca marche"] = true, ["parfait"] = true,
  ["sim"] = true, ["beleza"] = true, ["blz"] = true, ["fechado"] = true, ["certo"] = true, ["combinado"] = true,
}

local STRONG_FIRST = {
  ok = true, okay = true, okey = true, oki = true, okis = true, vale = true, si = true, sip = true, yes = true,
  yep = true, yup = true, yap = true, sure = true, ["+1"] = true, oui = true, ja = true, sim = true, claro = true,
  perfecto = true, acepto = true, agreed = true,
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
  -- a longer message counts only if it starts with an unambiguous yes ("ok vamos", "sí claro"); words such as
  -- "ya" or "va" also start sentences that are not a yes ("ya voy", "va bien el pull")
  local word = norm:match("^(%S+)")
  return word ~= nil and STRONG_FIRST[word] == true and #norm <= 14
end

-- Reserve lookup -------------------------------------------------------------------------------------
-- Returns the reserves for an item: same item ID when both are known, otherwise the same name.
function R.ReservesFor(contract, itemName, itemID)
  local result = {}
  if not contract or not contract.reserves or (type(itemName) ~= "string" and type(itemID) ~= "number") then
    return result
  end
  local target = type(itemName) == "string" and R.Normalize(itemName) or nil
  for _, reserve in ipairs(contract.reserves) do
    local byID = reserve.itemID and itemID and reserve.itemID == itemID
    local byName = target and R.Normalize(reserve.item) == target
    if byID or byName then
      result[#result + 1] = reserve
    end
  end
  return result
end

-- The chat line (<= 255 bytes) -----------------------------------------------------------------------
-- L supplies the words: L.CHAT_PREFIX, L.METHOD_n, L.NEED_<rule>, L.BOE_GREED, L.CHAT_RESERVE, L.CHAT_ASK.
-- linkFor(reserve) may return the item's link: reserves are then shown as real items, as long as the whole line
-- fits (links are never cut: a cut link makes the game reject the line).
function R.ChatLine(contract, L, linkFor)
  local parts = {}
  if contract.method ~= nil then
    parts[#parts + 1] = L["METHOD_" .. contract.method] or tostring(contract.method)
  end
  if contract.method == R.MASTER and contract.masterLooter then
    parts[#parts] = parts[#parts] .. " (" .. contract.masterLooter .. ")"
  end
  if contract.needRule then
    parts[#parts + 1] = L["NEED_SHORT_" .. contract.needRule] or L["NEED_" .. contract.needRule] or contract.needRule
  end
  if contract.boe == "greed" then
    parts[#parts + 1] = L.BOE_GREED
  end
  local reserves = {}
  for _, reserve in ipairs(contract.reserves or {}) do
    local who = reserve.owner and (reserve.owner .. " → ") or ""
    local label = (reserve.kind == "soft" and "SR " or "HR ") .. who
    local link = linkFor and linkFor(reserve)
    reserves[#reserves + 1] = { plain = label .. reserve.item, linked = type(link) == "string" and (label .. link) or nil }
  end
  local function build(links)
    local all = {}
    for _, part in ipairs(parts) do
      all[#all + 1] = part
    end
    for i, reserve in ipairs(reserves) do
      all[#all + 1] = (i <= links and reserve.linked) or reserve.plain
    end
    return L.CHAT_PREFIX .. " " .. table.concat(all, " · ") .. ". " .. L.CHAT_ASK
  end
  for links = #reserves, 1, -1 do
    local line = build(links)
    if #line <= 255 then
      return line
    end
  end
  return R.Truncate(build(0), 255, "...")
end
