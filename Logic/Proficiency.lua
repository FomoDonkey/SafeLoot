-- PURE (no game API). Which items a class can NEVER use, used to flag impossible Need rolls.
-- Baseline: vanilla proficiencies. TO VERIFY IN FOREVER (classes were reworked). Rule of the project:
-- "unknown" is not "impossible" -- only list here what a class can certainly never equip at level 60.
local _, SL = ...
local P = {}
SL.Proficiency = P

-- Enum.ItemClass (verified in Forever ItemConstantsDocumentation): Weapon=2, Armor=4.
P.CLASS_WEAPON = 2
P.CLASS_ARMOR = 4

-- Enum.ItemArmorSubclass: Generic=0 Cloth=1 Leather=2 Mail=3 Plate=4 Cosmetic=5 Shield=6 Libram=7 Idol=8 Totem=9
-- Sigil=10 Relic=11.
local CLOTH, LEATHER, MAIL, PLATE = 1, 2, 3, 4
local SHIELD, LIBRAM, IDOL, TOTEM = 6, 7, 8, 9

-- Enum.ItemWeaponSubclass: Axe1H=0 Axe2H=1 Bows=2 Guns=3 Mace1H=4 Mace2H=5 Polearm=6 Sword1H=7 Sword2H=8
-- Warglaive=9 Staff=10 Bearclaw=11 Catclaw=12 Unarmed=13 Generic=14 Dagger=15 Thrown=16 Obsolete3=17 Crossbow=18
-- Wand=19 Fishingpole=20.
local W = {
  Axe1H = 0, Axe2H = 1, Bows = 2, Guns = 3, Mace1H = 4, Mace2H = 5, Polearm = 6, Sword1H = 7, Sword2H = 8,
  Staff = 10, Unarmed = 13, Dagger = 15, Thrown = 16, Crossbow = 18, Wand = 19,
}
P.WEAPON = W

-- Heaviest armour each class can wear at level 60.
local MAX_ARMOR = {
  WARRIOR = PLATE, PALADIN = PLATE,
  HUNTER = MAIL, SHAMAN = MAIL,
  ROGUE = LEATHER, DRUID = LEATHER,
  PRIEST = CLOTH, MAGE = CLOTH, WARLOCK = CLOTH,
}
P.MAX_ARMOR = MAX_ARMOR

local SHIELD_USERS = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local RELIC_USER = { [LIBRAM] = "PALADIN", [IDOL] = "DRUID", [TOTEM] = "SHAMAN" }

local function set(list)
  local s = {}
  for _, v in ipairs(list) do
    s[v] = true
  end
  return s
end

-- Weapons a class can certainly never learn (conservative: doubtful cases are left out).
local NEVER_WEAPON = {
  WARRIOR = set({ W.Wand }),
  PALADIN = set({ W.Bows, W.Guns, W.Crossbow, W.Thrown, W.Wand, W.Dagger, W.Unarmed, W.Staff }),
  HUNTER = set({ W.Wand }),
  ROGUE = set({ W.Axe2H, W.Mace2H, W.Sword2H, W.Polearm, W.Staff, W.Wand }),
  PRIEST = set({ W.Axe1H, W.Axe2H, W.Sword1H, W.Sword2H, W.Mace2H, W.Polearm, W.Bows, W.Guns, W.Crossbow,
    W.Thrown, W.Unarmed }),
  SHAMAN = set({ W.Sword1H, W.Sword2H, W.Polearm, W.Bows, W.Guns, W.Crossbow, W.Thrown, W.Wand }),
  MAGE = set({ W.Axe1H, W.Axe2H, W.Mace1H, W.Mace2H, W.Polearm, W.Sword2H, W.Bows, W.Guns, W.Crossbow, W.Thrown,
    W.Unarmed }),
  WARLOCK = set({ W.Axe1H, W.Axe2H, W.Mace1H, W.Mace2H, W.Polearm, W.Sword2H, W.Bows, W.Guns, W.Crossbow,
    W.Thrown, W.Unarmed }),
  DRUID = set({ W.Sword1H, W.Sword2H, W.Axe1H, W.Axe2H, W.Bows, W.Guns, W.Crossbow, W.Thrown, W.Wand }),
}
P.NEVER_WEAPON = NEVER_WEAPON

-- Equip slots any class can wear regardless of armour type (cloaks are "Cloth" but everyone wears them).
local ANY_CLASS_SLOT = {
  INVTYPE_CLOAK = true, INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true,
  INVTYPE_HOLDABLE = true, INVTYPE_BODY = true, INVTYPE_TABARD = true,
}

-- item = { classID, subClassID, equipLoc }. Returns "no" | "yes" | "unknown", plus a reason code when "no".
-- exceptions = optional { ["MAGE:2:4"] = true } to silence a combination reported as a false positive.
function P.CanUse(classFile, item, exceptions)
  if type(classFile) ~= "string" or type(item) ~= "table" then
    return "unknown"
  end
  local classID, sub, slot = item.classID, item.subClassID, item.equipLoc
  if classID ~= P.CLASS_ARMOR and classID ~= P.CLASS_WEAPON then
    return "unknown" -- recipes, materials, consumables: never judged
  end
  if exceptions and exceptions[classFile .. ":" .. tostring(classID) .. ":" .. tostring(sub)] then
    return "unknown"
  end
  if slot and ANY_CLASS_SLOT[slot] then
    return "yes"
  end
  if classID == P.CLASS_ARMOR then
    local max = MAX_ARMOR[classFile]
    if not max then
      return "unknown"
    end
    if sub == SHIELD then
      return SHIELD_USERS[classFile] and "yes" or "no", "shield"
    end
    if RELIC_USER[sub] then
      return RELIC_USER[sub] == classFile and "yes" or "no", "relic"
    end
    if sub == CLOTH or sub == LEATHER or sub == MAIL or sub == PLATE then
      if sub > max then
        return "no", "armor"
      end
      return "yes"
    end
    return "unknown"
  end
  local never = NEVER_WEAPON[classFile]
  if not never then
    return "unknown"
  end
  if never[sub] then
    return "no", "weapon"
  end
  return "unknown"
end
