-- PURE (no game API). Judges one roll: "impossible" | "doubtful" | nil (docs/PROMPT_MAESTRO.md §4.2).
-- Principle: when in doubt, "doubtful", never "impossible". Transmog rolls are never faults.
local _, SL = ...
local J = {}
SL.Judge = J

-- Enum.EncounterLootDropRollState (verified in Forever): NeedMainSpec=0 NeedOffSpec=1 Transmog=2 Greed=3
-- NoRoll=4 Pass=5.
J.NEED_MAIN, J.NEED_OFF, J.TRANSMOG, J.GREED, J.NOROLL, J.PASS = 0, 1, 2, 3, 4, 5

J.IMPOSSIBLE, J.DOUBTFUL = "impossible", "doubtful"

local CASTERS = { MAGE = true, WARLOCK = true, PRIEST = true }
local PHYSICAL = { WARRIOR = true, ROGUE = true }

local function statKeys(stats)
  local has = {}
  for key in pairs(stats or {}) do
    local k = tostring(key)
    if k:find("STRENGTH") then has.str = true end
    if k:find("AGILITY") then has.agi = true end
    if k:find("INTELLECT") then has.int = true end
    if k:find("SPIRIT") then has.spi = true end
    if k:find("SPELL") then has.spell = true end
  end
  return has
end

function J.IsNeed(state)
  return state == J.NEED_MAIN or state == J.NEED_OFF
end

-- roll = { playerName, playerClass, state, isSelf }
-- item = { name, classID, subClassID, equipLoc, bindType, stats }
-- contract = Logic/Rules contract or nil
-- opts = { exceptions = {...} }
-- Returns verdict { level, reason, detail } or nil.
function J.Evaluate(roll, item, contract, opts)
  if type(roll) ~= "table" or type(item) ~= "table" or not J.IsNeed(roll.state) then
    return nil
  end
  local class = roll.playerClass
  local usable, why = SL.Proficiency.CanUse(class, item, opts and opts.exceptions)
  if usable == "no" then
    return { level = J.IMPOSSIBLE, reason = "class_" .. (why or "item"), class = class }
  end
  if contract then
    local Rules = SL.Rules
    if contract.needRule == "greed" then
      return { level = J.DOUBTFUL, reason = "contract_greed" }
    end
    if contract.boe == "greed" and item.bindType == 2 then -- Enum bind type 2 = OnEquip (BoE)
      return { level = J.DOUBTFUL, reason = "contract_boe" }
    end
    local reserves = Rules.ReservesFor(contract, item.name)
    if #reserves > 0 then
      local mine, hard, soft = false, false, false
      for _, reserve in ipairs(reserves) do
        if reserve.owner and SL.Names and SL.Names.Same(reserve.owner, roll.playerName) then
          mine = true
        end
        if reserve.kind == "hard" then hard = true else soft = true end
      end
      if not mine and hard then
        return { level = J.DOUBTFUL, reason = "reserved_hard" }
      end
      if not mine and soft then
        return { level = J.DOUBTFUL, reason = "reserved_soft" }
      end
    end
  end
  if usable ~= "yes" and item.stats and class then
    local s = statKeys(item.stats)
    if CASTERS[class] and (s.str or s.agi) and not (s.int or s.spi or s.spell) then
      return { level = J.DOUBTFUL, reason = "stats_physical" }
    end
    if PHYSICAL[class] and (s.int or s.spell) and not (s.str or s.agi) then
      return { level = J.DOUBTFUL, reason = "stats_caster" }
    end
  end
  return nil
end
