-- Player names on WoW: Forever. Adapted from BlazonGuild Core/Names.lua (same author, MIT), which was
-- verified in the real client (probe 2026-11-12):
--   * names are "First Surname" and unique across the region;
--   * UnitName("player") gives only "El"; UnitFullName gives "El", "Peregrino" (surname where a realm would go);
--   * the server writes names as "El Peregrino", "El Peregrino-Realm" or "El-Peregrino".
-- SafeLoot keys its memory by the short form "First Surname".
local _, SL = ...
local Names = {}
SL.Names = Names

local function secret(v)
  return issecretvalue ~= nil and issecretvalue(v)
end

local function homeRealm()
  local realm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
  if secret(realm) or type(realm) ~= "string" then
    return ""
  end
  return realm
end

-- "El Peregrino-Realm" -> "El Peregrino"; "El-Peregrino" -> "El Peregrino"; "El" -> "El".
function Names.Short(name)
  if type(name) ~= "string" or secret(name) or name == "" then
    return nil
  end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if not name:find(" ", 1, true) then
    local first, rest = name:match("^([^%-]+)%-(.+)$")
    if first and rest ~= homeRealm() then
      name = first .. " " .. rest
    end
  end
  local base = name:match("^(.-)%-[^%s%-]+$")
  if base and base ~= "" then
    return base
  end
  return name
end

function Names.Same(a, b)
  local sa, sb = Names.Short(a), Names.Short(b)
  return sa ~= nil and sa == sb
end

-- First part only ("El Peregrino" -> "El"), for weak matches when the game only gives the first name.
function Names.First(name)
  local short = Names.Short(name)
  return short and short:match("^(%S+)") or nil
end

function Names.HasSurname(name)
  local short = Names.Short(name)
  return short ~= nil and short:find(" ", 1, true) ~= nil
end

-- A unit's name ("target", "party1"...) as "First Surname", or nil (not available or secret).
function Names.Unit(unit)
  if not UnitFullName then
    if UnitName then
      local ok, n = pcall(UnitName, unit)
      if ok and not secret(n) and type(n) == "string" and n ~= "" then
        return n
      end
    end
    return nil
  end
  local ok, first, second = pcall(UnitFullName, unit)
  if not ok or secret(first) or secret(second) or type(first) ~= "string" or first == "" then
    return nil
  end
  if first:find(" ", 1, true) then
    return first
  end
  if type(second) == "string" and second ~= "" and second ~= homeRealm() then
    return first .. " " .. second
  end
  return first
end

function Names.Me()
  return Names.Unit("player")
end

function Names.IsMe(name)
  local me = Names.Me()
  return me ~= nil and Names.Same(name, me)
end
