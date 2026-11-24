-- The Contract: the rules agreed before the run (docs/PROMPT_MAESTRO.md §4.4). Works when you are the only one
-- with the addon:
--   1. automatic: the snapshot of the loot rules when you join (Watcher);
--   2. copied: rules found in the leader's chat line or in the Group Finder listing you looked at -> a suggestion;
--   3. proposed: you fill the card and publish it as a NORMAL chat line everyone reads; "ok"/"sí"/"+1" replies are
--      recorded with the time. Nothing is ever sent without a click.
local _, SL = ...
local C = SL:NewModule("Contract")
SL.Contract = C
local API, Rules, Names, T, L = SL.API, SL.Rules, SL.Names, SL.Theme, SL.L

function C:Get()
  return self.current
end

C.AGREE_WINDOW = 180 -- seconds after publishing during which "ok" counts as agreeing

function C:Reset(contract)
  self.current = contract
  self.awaiting = false
  self:Save()
  SL:Fire("CONTRACT_CHANGED", contract)
end

-- The agreed rules survive a /reload: saved per character with the leader they were agreed with.
function C:Save()
  if SL.char then
    SL.char.contract = self.current and { contract = self.current, leader = API.LeaderName(), t = API.Now() } or nil
  end
end

function C:Restore()
  local saved = SL.char and SL.char.contract
  if type(saved) ~= "table" or type(saved.contract) ~= "table" then
    return false
  end
  local fresh = (API.Now() - (saved.t or 0)) < 4 * 3600
  if fresh and saved.leader and Names.Same(saved.leader, API.LeaderName()) then
    self.current = saved.contract
    self.current.accepted = type(self.current.accepted) == "table" and self.current.accepted or {}
    local reserves = {}
    for _, reserve in ipairs(type(self.current.reserves) == "table" and self.current.reserves or {}) do
      if type(reserve) == "table" and type(reserve.item) == "string" then
        reserve.itemID = type(reserve.itemID) == "number" and reserve.itemID or nil
        reserves[#reserves + 1] = reserve
      end
    end
    self.current.reserves = reserves
    if type(self.current.instance) ~= "number" then
      self.current.instance = nil
    end
    return true
  end
  SL.char.contract = nil
  return false
end

function C:Awaiting()
  local c = self.current
  return self.awaiting and c and c.publishedAt and (API.Now() - c.publishedAt) <= C.AGREE_WINDOW or false
end

-- Applies parsed rules on top of the current contract and marks its source.
-- When rules are agreed (adopted or published), the agreed loot method is the one the group has at that moment,
-- unless the text itself names one.
local function syncMethod(contract)
  local state = API.LootState()
  if state then
    contract.method, contract.masterLooter, contract.threshold, contract.leader =
      state.method, state.masterLooter, state.threshold, state.leader
  end
end

function C:Adopt(partial, source)
  local contract = self.current or Rules.New(source, API.Now())
  if partial.method == nil then
    syncMethod(contract)
  end
  Rules.Apply(contract, partial)
  contract.source = source or contract.source
  self.current = contract
  self:Save()
  SL.Run:Log("contract", { text = T.Paint(L.CONTRACT_ADOPTED, T.color.gold) .. " " .. self:Summary(contract) })
  SL:Fire("CONTRACT_CHANGED", contract)
end

function C:Summary(contract)
  contract = contract or self.current
  if not contract then
    return L.CONTRACT_NONE
  end
  local parts = {}
  if contract.method ~= nil then
    parts[#parts + 1] = L["METHOD_" .. contract.method] or tostring(contract.method)
  end
  if contract.needRule then
    parts[#parts + 1] = L["NEED_" .. contract.needRule]
  end
  if contract.boe then
    parts[#parts + 1] = L.BOE_GREED
  end
  local n = contract.reserves and #contract.reserves or 0
  if n > 0 then
    parts[#parts + 1] = string.format(n == 1 and L.RESERVES_ONE or L.RESERVES_N, n)
  end
  return #parts > 0 and table.concat(parts, " · ") or L.CONTRACT_NONE
end

-- Short form for the rules bar: "Botín de grupo · MS>OS · 1 reserva · 2/4 ✓".
function C:ShortSummary(contract)
  contract = contract or self.current
  if not contract then
    return L.CONTRACT_NONE
  end
  local parts = {}
  if contract.method ~= nil then
    parts[#parts + 1] = L["METHOD_" .. contract.method] or tostring(contract.method)
  end
  if contract.needRule then
    parts[#parts + 1] = L["NEED_SHORT_" .. contract.needRule] or L["NEED_" .. contract.needRule]
  end
  if contract.boe then
    parts[#parts + 1] = "BoE"
  end
  local n = contract.reserves and #contract.reserves or 0
  if n > 0 then
    parts[#parts + 1] = string.format(n == 1 and L.RESERVES_ONE or L.RESERVES_N, n)
  end
  if contract.publishedAt then
    local agreed = 0
    for _ in pairs(contract.accepted or {}) do
      agreed = agreed + 1
    end
    local others = math.max(0, API.GroupSize() - 1)
    parts[#parts + 1] = string.format(L.AGREED_COUNT, agreed, others)
  end
  return #parts > 0 and table.concat(parts, " · ") or L.CONTRACT_NONE
end

-- What the game says right now (method, quality threshold, who hands out the loot), for the Rules tab.
function C:GameStateLine()
  local state = API.LootState()
  if not state then
    return L.GAME_STATE_UNKNOWN
  end
  local parts = { L["METHOD_" .. state.method] or tostring(state.method) }
  if state.method == Rules.MASTER and state.masterLooter then
    parts[#parts] = parts[#parts] .. " (" .. state.masterLooter .. ")"
  end
  if state.threshold then
    local name = _G["ITEM_QUALITY" .. state.threshold .. "_DESC"] or tostring(state.threshold)
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[state.threshold]
    if color and color.hex then
      name = color.hex .. name .. "|r"
    end
    parts[#parts + 1] = string.format(L.THRESHOLD_FMT, name)
  end
  if state.leader then
    parts[#parts + 1] = string.format(L.LEADER_FMT, state.leader)
  end
  return table.concat(parts, " · ")
end

-- The group really agreed to the new loot method (e.g. master loot for the last boss): it becomes the reference,
-- keeping the need rule and the reserves. Logic audit: before this the bar stayed red for the rest of the run.
function C:AcceptGameState()
  local c = self.current
  if not c then
    return
  end
  syncMethod(c)
  self:Save()
  SL.Run:Log("rules_changed", { severity = 1, text = T.Paint(L.RULES_ACCEPTED, T.color.green) .. " " .. self:Summary(c) })
  SL:Fire("CONTRACT_CHANGED", c)
end

-- Any change made in the Rules tab turns the contract into an unpublished draft: what the group agreed to was the
-- published line, so a later local edit must not keep the old "ok" answers (logic audit).
function C:Edit(fn)
  local c = self.current or Rules.New("proposed", API.Now())
  fn(c)
  if c.publishedAt then
    c.publishedAt, c.accepted = nil, {}
    self.awaiting = false
  end
  c.source = "proposed"
  self.current = c
  self:Save()
  SL:Fire("CONTRACT_CHANGED", c)
end

-- Publishing ------------------------------------------------------------------------------------------------
local function linkFor(reserve)
  local info = reserve.itemID and SL.Catalog and SL.Catalog:ItemInfo(reserve.itemID)
  return info and info.link or nil
end

function C:ChatLine(contract)
  return Rules.ChatLine(contract or self.current or Rules.New("proposed"), L, linkFor)
end

-- The game's current method, looter, threshold and leader, written into the contract in place (rules, reserves
-- and destination stay). Used for rules prepared before the group formed and for the leader's own changes.
function C:SyncGame()
  if not self.current then
    return
  end
  syncMethod(self.current)
  self:Save()
  SL:Fire("CONTRACT_CHANGED", self.current)
end

-- Where the group is going. Not a rule: changing it never turns published rules into a draft.
function C:SetDestination(mapID)
  local c = self.current
  if not c then
    -- in a group the game's rules are the base; alone it is something prepared in advance (kept when you join)
    local state = API.InGroup() and API.LootState()
    c = state and Rules.FromState(state, API.Now()) or Rules.New("proposed", API.Now())
    self.current = c
  end
  if c.instance == mapID then
    return
  end
  c.instance = mapID
  self:Save()
  SL:Fire("CONTRACT_CHANGED", c)
  if mapID and SL.Catalog then
    SL.Catalog:Ask(mapID)
  end
end

-- Only from a click.
function C:Publish(contract)
  contract = contract or self.current
  if not contract or not API.InGroup() then
    SL:Print(L.CONTRACT_NOGROUP)
    return false
  end
  syncMethod(contract)
  local sent = API.SendGroupChat(self:ChatLine(contract))
  if not sent then
    return false -- cooldown or chat refused: nothing is recorded as published
  end
  contract.source = "proposed"
  contract.accepted = {}
  contract.publishedAt = API.Now()
  self.current = contract
  self.awaiting = true
  self:Save()
  SL.Theme.Play("agreed")
  SL.Run:Log("contract", { text = T.Paint(L.CONTRACT_PUBLISHED, T.color.gold) .. " " .. self:Summary(contract) })
  SL:Fire("CONTRACT_CHANGED", contract)
  return sent
end

function C:MarkAccepted(name)
  local contract = self.current
  if not contract or not name then
    return
  end
  local short = Names.Short(name)
  if not short or contract.accepted[short] then
    return
  end
  contract.accepted[short] = API.Now()
  self:Save()
  SL.Run:Log("agreed", { text = string.format(L.CONTRACT_AGREED, short, date and date("%H:%M") or "") })
  SL:Fire("CONTRACT_CHANGED", contract)
end

-- Chat -----------------------------------------------------------------------------------------------------
local GROUP_CHAT = {
  CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
  CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
}

function C:OnGroupChat(event, text, sender)
  if API.IsSecret(text) or API.IsSecret(sender) or type(text) ~= "string" then
    if SL.Diagnostics then
      SL.Diagnostics:Observe("chat_group_secret")
    end
    return
  end
  if SL.Diagnostics then
    SL.Diagnostics:Observe("chat_group_plain")
  end
  if Names.IsMe(sender) then
    return
  end
  -- replies to a published contract
  if self:Awaiting() and Rules.IsAgreement(text) then
    self:MarkAccepted(sender)
    return
  end
  -- rules written by the leader -> suggestion (never applied silently)
  local isLeader = event:find("LEADER") ~= nil or Names.Same(sender, API.LeaderName())
  if isLeader and SL.settings.suggestRules then
    local partial = Rules.Parse(text, Names.Short(sender))
    if partial then
      self:Suggest(partial, string.format(L.SUGGEST_FROM_CHAT, Names.Short(sender) or "?"))
    end
  end
end

local function signature(partial)
  local parts = { tostring(partial.method), tostring(partial.needRule), tostring(partial.boe) }
  for _, reserve in ipairs(partial.reserves or {}) do
    parts[#parts + 1] = Rules.Normalize(reserve.item) .. "@" .. tostring(reserve.owner)
  end
  return table.concat(parts, "|")
end

function C:Suggest(partial, origin)
  -- the same rules repeated in chat (leaders often paste them several times) are offered only once
  local sig = signature(partial)
  if self.lastSuggestion == sig and (API.Now() - (self.lastSuggestionAt or 0)) < 300 then
    return
  end
  self.lastSuggestion, self.lastSuggestionAt = sig, API.Now()
  local preview = Rules.New("copied", API.Now())
  Rules.Apply(preview, partial)
  SL.Alert:Toast({
    tone = "neutral",
    title = L.SUGGEST_TITLE,
    body = origin .. "\n" .. self:Summary(preview),
    seconds = 25,
    action = { label = L.SUGGEST_USE, fn = function()
      C:Adopt(partial, "copied")
    end },
  })
end

-- Group Finder listing you looked at: remember its rules per leader; offered when you join that leader.
-- Group Finder rows refresh often: each listing text is parsed once (bounded cache) and at most 100 listings
-- are remembered.
function C:RememberListing(leaderName, comment)
  if not leaderName or not comment or API.IsSecret(comment) or API.IsSecret(leaderName) then
    return
  end
  local short = Names.Short(leaderName)
  if not short then
    return
  end
  self.listings = self.listings or {}
  local known = self.listings[short]
  if known and known.comment == comment then
    known.t = API.Now()
    return
  end
  local partial = Rules.Parse(comment, short)
  if not partial then
    return
  end
  self.listingCount = (self.listingCount or 0) + 1
  if self.listingCount > 100 then
    self.listings, self.listingCount = {}, 1
  end
  self.listings[short] = { partial = partial, comment = comment, t = API.Now() }
end

function C:OfferListingRules()
  local leader = API.LeaderName()
  local entry = leader and self.listings and self.listings[Names.Short(leader)]
  if entry and (API.Now() - entry.t) < 1800 then
    self:Suggest(entry.partial, string.format(L.SUGGEST_FROM_LISTING, Names.Short(leader)))
    self.listings[Names.Short(leader)] = nil
  end
end

function C:OnEnable()
  for event in pairs(GROUP_CHAT) do
    SL:RegisterEvent(event, self, self.OnGroupChat)
  end
  SL:On("RUN_STARTED", self, function()
    C:OfferListingRules()
  end)
  SL:RegisterEvent("GROUP_JOINED", self, function()
    if C_Timer and C_Timer.After then
      C_Timer.After(2, function()
        SL.SafeCall("Contract.listing", C.OfferListingRules, C)
      end)
    end
  end)
end
