-- Shows your memory where you decide (docs/PROMPT_MAESTRO.md §4.3): the player tooltip, the Group Finder rows
-- and their tooltip, the invitation, and when someone you remember joins your group.
-- Only hooksecurefunc / TooltipDataProcessor / HookScript: no Blizzard function is replaced (no taint).
local _, SL = ...
local MH = SL:NewModule("MemoryHooks")
SL.MemoryHooks = MH
local API, Memory, Names, UI, T, L = SL.API, SL.Memory, SL.Names, SL.UI, SL.Theme, SL.L

local function summaryFor(name)
  if not SL.settings.memory or not name then
    return nil
  end
  local record = Memory.Get(SL.db.players, name)
  if not record then
    return nil
  end
  local summary = Memory.Summary(record, API.Now(), SL.settings.memoryDays)
  return summary, record
end

local function eventText(event)
  if not event then
    return ""
  end
  local text = L["EVENT_" .. string.upper(event.kind)] or event.kind
  local where = event.place and (" · " .. event.place) or ""
  local what = (event.link or event.item) and (" · " .. (event.link or event.item)) or ""
  local note = event.note and (" · \"" .. event.note .. "\"") or ""
  return text .. what .. where .. note .. " (" .. UI.FormatDate(event.t) .. ")"
end
MH.EventText = eventText

-- Without date or place: for the second line of a list row.
function MH.ShortEvent(event)
  if not event then
    return ""
  end
  if event.kind == "note" then
    return "\"" .. (event.note or "") .. "\""
  end
  local what = event.link or event.item
  return (L["EVENT_" .. string.upper(event.kind)] or event.kind) .. (what and (" · " .. what) or "")
end

-- Lines to add to any tooltip for a remembered player.
function MH:TooltipLines(name)
  local summary, record = summaryFor(name)
  if not summary then
    return nil
  end
  local lines = {}
  local category = Memory.Category(record, API.Now(), SL.settings.memoryDays)
  if summary.tone then
    -- the word first and big: you must see at a glance what this player is to you
    lines[#lines + 1] = SL.Players:Label(category, 18, true) .. "  " .. T.Paint(L.ADDON_NAME, T.color.gray)
    lines[#lines + 1] = eventText(summary.latest)
    if category == "trusted" and summary.bad > 0 then
      lines[#lines + 1] = SL.Players:Label("warned", 14) -- trusted by you, but the addon saw something
    end
    if summary.count > 1 then
      lines[#lines + 1] = string.format(L.TOOLTIP_MORE, summary.count - 1)
    end
  elseif summary.latestAny then
    -- only notes: show the newest one (it is what the player wrote to remember this person)
    lines[#lines + 1] = SL.Players:Label("noted", 16) .. "  " .. T.Paint(L.ADDON_NAME, T.color.gray)
    lines[#lines + 1] = eventText(summary.latestAny)
  elseif record.seen and record.seen > 0 then
    lines[#lines + 1] = "|T" .. T.tex.wait .. ":14:14|t " .. T.Paint(string.format(L.TOOLTIP_SEEN, record.seen), T.color.gray)
  end
  return #lines > 0 and lines or nil
end

-- 1. Unit tooltips ------------------------------------------------------------------------------------------
local function onUnitTooltip(tooltip)
  if not SL.settings.showTooltip or tooltip ~= GameTooltip then
    return
  end
  local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
  if not ok or not unit or API.IsSecret(unit) then
    return
  end
  if not API.UnitIsPlayer(unit) then
    return
  end
  local name = Names.Unit(unit)
  if SL.Diagnostics then
    SL.Diagnostics:Observe("unit_tooltip", { named = name ~= nil })
  end
  local lines = name and MH:TooltipLines(name)
  if lines then
    for _, line in ipairs(lines) do
      tooltip:AddLine(line, 1, 1, 1, true)
    end
  end
end

-- 2. Group Finder (Blizzard_GroupFinder_VanillaStyle, load-on-demand) ---------------------------------------
local function rowBadge(row)
  if not row.SafeLootBadge then
    local badge = row:CreateTexture(nil, "OVERLAY")
    badge:SetSize(16, 16)
    badge:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.SafeLootBadge = badge
  end
  return row.SafeLootBadge
end

local function onFinderRow(row)
  if not SL.settings.showFinder or not row or not row.resultID then
    return
  end
  local info = API.LFGResult(row.resultID)
  local badge = rowBadge(row)
  badge:Hide()
  if not info or API.IsSecret(info.leaderName) then
    return
  end
  if SL.Diagnostics then
    SL.Diagnostics:Observe("finder_row_hook", { leader = info.leaderName ~= nil, comment = info.comment ~= nil })
  end
  SL.Contract:RememberListing(info.leaderName, info.comment)
  local summary, record = summaryFor(info.leaderName)
  if summary and summary.tone then
    badge:SetTexture(T.category[Memory.Category(record, API.Now(), SL.settings.memoryDays)].icon)
    -- right after the visible text of the listing name, so it never covers the role/count icons
    if row.Name and row.Name.GetStringWidth then
      local width = math.min(row.Name:GetStringWidth() or 0, row.Name:GetWidth() or 0)
      badge:ClearAllPoints()
      badge:SetPoint("LEFT", row.Name, "LEFT", width + 4, 0)
    end
    badge:Show()
  end
end

local function finderCard()
  if not MH.card then
    local card = UI.Card(UIParent, 300, 80, "SafeLootFinderCard")
    card:SetFrameStrata("TOOLTIP")
    card:EnableMouse(false)
    card.Text = UI.Text(card, "small", "", "LEFT")
    card.Text:SetPoint("TOPLEFT", 16, -14)
    card.Text:SetPoint("RIGHT", -16, 0)
    card.Text:SetSpacing(2)
    card:Hide()
    MH.card = card
  end
  return MH.card
end

local function onFinderTooltip(tooltipFrame, resultID)
  if not SL.settings.showFinder or not tooltipFrame or not resultID then
    return
  end
  local info = API.LFGResult(resultID)
  if SL.Diagnostics then
    SL.Diagnostics:Observe("finder_tooltip_hook")
  end
  local card = finderCard()
  card:Hide()
  if not info or API.IsSecret(info.leaderName) then
    return
  end
  local lines = MH:TooltipLines(info.leaderName)
  if not lines then
    return
  end
  card.Text:SetText(T.Paint(Names.Short(info.leaderName) or "", T.color.gold) .. "\n" .. table.concat(lines, "\n"))
  card:SetHeight((card.Text:GetStringHeight() or 40) + 30)
  card:ClearAllPoints()
  card:SetPoint("TOPLEFT", tooltipFrame, "BOTTOMLEFT", 0, -2)
  card:Show()
  if not tooltipFrame.SafeLootHooked then
    tooltipFrame:HookScript("OnHide", function()
      card:Hide()
    end)
    tooltipFrame.SafeLootHooked = true
  end
end

function MH:HookFinder()
  if self.finderHooked then
    return
  end
  if type(LFGBrowseSearchEntry_Update) == "function" then
    hooksecurefunc("LFGBrowseSearchEntry_Update", function(row)
      SL.SafeCall("finder row", onFinderRow, row)
    end)
    self.finderHooked = true
  end
  if type(LFGBrowseSearchEntryTooltip_UpdateAndShow) == "function" then
    hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", function(frame, resultID)
      SL.SafeCall("finder tooltip", onFinderTooltip, frame, resultID)
    end)
  end
end

-- 3. Invitations and 4. people joining --------------------------------------------------------------------
function MH:OnInvite(_, name)
  if SL.Diagnostics then
    SL.Diagnostics:Observe("invite_event", { named = type(name) == "string" and not API.IsSecret(name) })
  end
  if not SL.settings.showInvite or API.IsSecret(name) then
    return
  end
  local summary = summaryFor(name)
  if summary and summary.tone then
    SL.Alert:Toast({
      tone = summary.tone,
      title = string.format(L.INVITE_TITLE, Names.Short(name) or "?") .. " · " .. SL.Players:Label((SL.Players:Category(name)) or "seen", 14, true),
      body = eventText(summary.latest),
      seconds = 30,
    })
  end
end

function MH:OnRoster()
  if not SL.settings.showGroupJoin or not API.InGroup() then
    self.known = {}
    return
  end
  self.known = self.known or {}
  for _, member in ipairs(API.GroupMembers()) do
    local short = Names.Short(member.name)
    if short and not self.known[short] and not Names.IsMe(short) then
      self.known[short] = true
      local summary = summaryFor(short)
      if summary and (summary.tone == "bad" or summary.tone == "mixed" or summary.tone == "warn") then
        SL.Alert:Toast({
          tone = summary.tone,
          title = SL.Players:Label((SL.Players:Category(short)) or "seen", 16, true) .. " · " .. string.format(L.JOINED_TITLE, short),
          body = eventText(summary.latest),
          seconds = 20,
        })
      end
    end
  end
end

function MH:OnEnable()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
      SL.SafeCall("unit tooltip", onUnitTooltip, tooltip)
    end)
  end
  self:HookFinder()
  SL:RegisterEvent("ADDON_LOADED", self, function(_, _, name)
    if name == "Blizzard_GroupFinder_VanillaStyle" then
      MH:HookFinder()
    end
  end)
  SL:RegisterEvent("PARTY_INVITE_REQUEST", self, self.OnInvite)
  SL:RegisterEvent("GROUP_ROSTER_UPDATE", self, function()
    SL:Debounce("memory-roster", 0.6, function()
      MH:OnRoster()
    end)
  end)
end
