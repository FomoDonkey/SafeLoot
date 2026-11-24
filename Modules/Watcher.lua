-- The Watcher: alarm when the loot rules change (docs/PROMPT_MAESTRO.md §4.1). The star feature.
-- Reference = the agreed contract, or the snapshot taken when you joined the group if nobody agreed anything.
local _, SL = ...
local W = SL:NewModule("Watcher")
SL.Watcher = W
local API, Rules, T, L = SL.API, SL.Rules, SL.Theme, SL.L

local function methodName(method)
  return method ~= nil and (L["METHOD_" .. method] or tostring(method)) or L.UNKNOWN
end

-- Builds the alarm text for a list of changes against the reference.
function W:Describe(changes, reference, state)
  local main = changes[1]
  for _, change in ipairs(changes) do
    if change.severity > main.severity then
      main = change
    end
  end
  local clock = date and date("%H:%M") or ""
  if main.field == "method" and state.method == Rules.MASTER then
    local who = state.masterLooter or state.leader or L.UNKNOWN
    return L.ALARM_ML_TITLE, string.format(L.ALARM_ML_BODY, clock, who, methodName(reference.method)), L.VOICE_ML
  elseif main.field == "masterLooter" then
    return L.ALARM_LOOTER_TITLE, string.format(L.ALARM_LOOTER_BODY, clock, tostring(main.from), tostring(main.to)), L.VOICE_LOOTER
  elseif main.field == "threshold" then
    return L.ALARM_THRESHOLD_TITLE, string.format(L.ALARM_THRESHOLD_BODY, clock), nil
  elseif main.field == "leader" then
    return L.ALARM_LEADER_TITLE, string.format(L.ALARM_LEADER_BODY, clock, tostring(main.to)), nil
  end
  return L.ALARM_METHOD_TITLE, string.format(L.ALARM_METHOD_BODY, clock, methodName(main.from), methodName(main.to)), nil
end

function W:Check(reason)
  local state = API.LootState()
  if SL.Diagnostics then
    SL.Diagnostics:Observe("loot_method_read", { ok = state ~= nil, method = state and state.method, reason = reason })
  end
  if not state then
    return
  end
  local previous = self.lastState
  self.lastState = state
  local contract = SL.Contract:Get()
  if not contract then
    SL.Contract:Reset(Rules.FromState(state, API.Now()))
    -- decision-time information: the group you just joined already uses master loot
    if state.method == Rules.MASTER and not API.IsLeader("player") then
      SL.Alert:Toast({
        tone = "warn", title = L.JOIN_ML_TITLE,
        body = string.format(L.JOIN_ML_BODY, state.masterLooter or state.leader or L.UNKNOWN), seconds = 20,
      })
    end
    return
  end
  if not previous then
    return
  end
  local now = Rules.Diff(previous, state)
  if #now == 0 then
    return
  end
  -- you changed it yourself (you lead): no alarm; an automatic contract follows you
  if API.IsLeader("player") then
    if contract.source == "auto" then
      SL.Contract:Reset(Rules.FromState(state, API.Now()))
    end
    return
  end
  local deviation = Rules.Diff(contract, state)
  local severity = Rules.MaxSeverity(deviation)
  SL:Fire("RULES_STATUS", severity)
  if severity == 0 then
    SL.Alert:Toast({ tone = "good", title = L.RULES_RESTORED_TITLE, body = L.RULES_RESTORED_BODY, seconds = 8 })
    SL.Run:Log("rules_changed", { severity = 1, text = L.RULES_RESTORED_TITLE })
    return
  end
  local title, body, voice = self:Describe(deviation, contract, state)
  local leader = state.leader
  SL.Run:Log("rules_changed", {
    severity = severity, text = T.Paint(title, severity >= 3 and T.color.red or T.color.orange), who = leader,
    from = contract.method, to = state.method,
  })
  if severity == Rules.SEVERITY_INFO then
    SL.Alert:Toast({ tone = "neutral", title = title, body = body, seconds = 10 })
    return
  end
  SL.Alert:Alarm({
    severity = severity, title = title, body = body, voice = voice,
    actions = {
      { label = L.ACTION_ASK, fn = function()
        API.SendGroupChat(L.CHAT_ASK_METHOD)
      end },
      { label = L.ACTION_SAVE, fn = function()
        if leader and SL.settings.memory then
          SL.Memory.Add(SL.db.players, leader, { kind = "rules_changed", t = API.Now(), place = API.PlaceName() })
          SL:Fire("MEMORY_CHANGED", leader)
        end
        SL:Print(L.SAVED_EVIDENCE)
      end },
      { label = L.ACTION_OK, fn = function() end },
    },
  })
end

function W:OnGroupChanged()
  local inGroup = API.InGroup()
  if inGroup and not self.inGroup then
    -- just joined: take the snapshot a moment later (the loot rules may not be ready yet)
    self.lastState = nil
    SL.Contract:Reset(nil)
    if C_Timer and C_Timer.After then
      C_Timer.After(1.5, function()
        SL.SafeCall("Watcher.join", W.Check, W, "join")
      end)
    else
      self:Check("join")
    end
  elseif not inGroup and self.inGroup then
    self.lastState = nil
    SL.Contract:Reset(nil)
  end
  self.inGroup = inGroup
end

function W:OnMethodChanged(event)
  if SL.Diagnostics then
    SL.Diagnostics:Observe(event == "PARTY_LOOT_METHOD_CHANGED" and "loot_method_event" or "leader_event")
  end
  -- Forever blocks some reads in combat; a loot change mid-fight is checked the moment combat ends.
  SL:AfterCombat("watcher-check", function()
    W:Check(event)
  end)
end

function W:OnEnable()
  self.inGroup = false
  -- after a /reload inside a group, keep the rules that were agreed instead of taking a new snapshot
  if API.InGroup() and SL.Contract:Restore() then
    self.inGroup = true
    self.lastState = API.LootState()
  end
  SL:RegisterEvent("GROUP_ROSTER_UPDATE", self, function()
    SL:Debounce("watcher-roster", 0.3, function()
      W:OnGroupChanged()
    end)
  end)
  SL:RegisterEvent("PARTY_LOOT_METHOD_CHANGED", self, self.OnMethodChanged)
  SL:RegisterEvent("PARTY_LEADER_CHANGED", self, self.OnMethodChanged)
  SL:RegisterEvent("PLAYER_ENTERING_WORLD", self, function()
    if API.InGroup() then
      SL:AfterCombat("watcher-world", function()
        W:Check("world")
      end)
    end
  end)
  self:OnGroupChanged()
end
