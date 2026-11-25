-- The rules indicator (docs/PROMPT_MAESTRO.md §5.2): a small bar, only while you are in a group, with the rules
-- in force and whether they were broken. Hover: the full rules and who agreed. Click: the Rules tab. Drag: move.
-- Native look: the game's tooltip border over a dark background, ready-check icons, game fonts.
local _, SL = ...
local I = SL:NewModule("Indicator")
SL.Indicator = I
local API, UI, T, L = SL.API, SL.UI, SL.Theme, SL.L

I.deviation = 0

function I:Build()
  local bar = UI.Create("Button", UIParent, nil, "SafeLootIndicator")
  bar:SetSize(240, 28)
  bar:SetFrameStrata("MEDIUM")
  bar:SetClampedToScreen(true)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 3, -3)
  bg:SetPoint("BOTTOMRIGHT", -3, 3)
  bg:SetColorTexture(0, 0, 0, 0.82) -- seen in the client: at 0.6 the text was lost over bright scenery
  local border = UI.Create("Frame", bar, "NineSlicePanelTemplate")
  border:SetAllPoints()
  if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
    pcall(NineSliceUtil.ApplyLayoutByName, border, "TooltipDefaultLayout")
  end
  bar.Icon = UI.Icon(bar, 16, T.tex.wait, "OVERLAY")
  bar.Icon:SetPoint("LEFT", 8, 0)
  bar.Text = UI.Text(bar, "body", "", "LEFT")
  bar.Text:SetPoint("LEFT", bar.Icon, "RIGHT", 6, 0)
  bar.Text:SetWordWrap(false)
  UI.Movable(bar, "indicator", { "TOPRIGHT", UIParent, "TOPRIGHT", -250, -14 })
  -- a drag must not count as a click
  bar:HookScript("OnDragStart", function(self)
    self.dragging = true
  end)
  bar:HookScript("OnDragStop", function(self)
    if C_Timer and C_Timer.After then
      C_Timer.After(0.1, function()
        self.dragging = false
      end)
    else
      self.dragging = false
    end
  end)
  bar:RegisterForClicks("LeftButtonUp")
  bar:SetScript("OnClick", function(self)
    if self.dragging then
      return
    end
    SL.MainFrame:Open("contract")
  end)
  bar:SetScript("OnEnter", function(self)
    I:ShowTooltip(self)
  end)
  bar:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  bar:Hide()
  self.bar = bar
end

function I:ShowTooltip(owner)
  if not GameTooltip then
    return
  end
  local c = SL.Contract:Get()
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
  GameTooltip:SetText(L.IND_TOOLTIP_TITLE, T.color.gold.r, T.color.gold.g, T.color.gold.b)
  if self.deviation >= 2 then
    GameTooltip:AddLine("|T" .. T.tex.bad .. ":14:14|t " .. L.IND_CHANGED_LONG, T.color.red.r, T.color.red.g, T.color.red.b, true)
  end
  GameTooltip:AddLine(SL.Contract:Summary(c), 1, 1, 1, true)
  for _, reserve in ipairs(c and c.reserves or {}) do
    GameTooltip:AddLine("• " .. (reserve.kind == "soft" and "SR " or "HR ") .. reserve.item
      .. (reserve.owner and (" > " .. reserve.owner) or ""), 1, 1, 1, true)
  end
  if c and c.publishedAt then
    local names = {}
    for name in pairs(c.accepted or {}) do
      names[#names + 1] = name
    end
    table.sort(names)
    GameTooltip:AddLine(#names > 0 and (L.ACCEPTED_BY .. " " .. table.concat(names, ", ")) or L.ACCEPTED_NONE,
      T.color.green.r, T.color.green.g, T.color.green.b, true)
  end
  GameTooltip:AddLine(L.IND_TOOLTIP_HINT, T.color.gray.r, T.color.gray.g, T.color.gray.b, true)
  GameTooltip:Show()
end

function I:Update()
  if not self.bar then
    return
  end
  if not SL.settings.showIndicator or not API.InGroup() then
    self.bar:Hide()
    return
  end
  local c = SL.Contract:Get()
  -- the bar works the state out itself (outside combat), so "Use the game's rules" or "Accept the change" turn it
  -- back to normal at once; in combat it keeps the last known state
  if c and not SL:InCombat() then
    local state = API.LootState()
    if state then
      self.deviation = SL.Rules.MaxSeverity(SL.Rules.Diff(c, state))
    end
  end
  local text = T.Paint(SL.Contract:ShortSummary(c), T.color.white)
  if self.deviation >= 2 then
    self.bar.Icon:SetTexture(T.tex.bad)
    text = T.Paint(L.IND_CHANGED, T.color.red) .. "  " .. text
  else
    self.bar.Icon:SetTexture(c and T.tex.ok or T.tex.wait)
  end
  self.bar.Text:SetText(text)
  local width = (self.bar.Text:GetStringWidth() or 160) + 44
  self.bar:SetWidth(math.min(340, math.max(150, width)))
  self.bar:Show()
end

function I:OnInitialize()
  self:Build()
end

function I:OnEnable()
  SL:On("CONTRACT_CHANGED", self, function()
    I:Update()
  end)
  SL:On("RULES_STATUS", self, function(_, severity)
    I.deviation = severity or 0
    I:Update()
  end)
  SL:On("SETTING_CHANGED", self, function(_, key)
    if key == "showIndicator" or key == "largeText" then
      I:Update()
    end
  end)
  SL:RegisterEvent("GROUP_ROSTER_UPDATE", self, function()
    SL:Debounce("indicator-roster", 0.5, function()
      if not API.InGroup() then
        I.deviation = 0
      end
      I:Update()
    end)
  end)
  self:Update()
end
