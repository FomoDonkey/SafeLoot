-- Small builders over the game's own templates (verified in the Forever source, docs/PROMPT_MAESTRO.md §6.1).
-- Every template is checked first (C_XMLUtil.GetTemplateInfo); if one is missing we fall back instead of failing.
local _, SL = ...
local UI = {}
SL.UI = UI
local T = SL.Theme

function UI.Create(kind, parent, template, name)
  if template and not SL.API.TemplateExists(template) then
    SL:ReportError("UI.Create", "missing template " .. template)
    template = nil
  end
  local ok, frame = pcall(CreateFrame, kind, name, parent, template)
  if ok and frame then
    return frame
  end
  return CreateFrame(kind, name, parent)
end

function UI.Text(parent, role, text, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", T.Font(role or "body"))
  fs.role = role or "body"
  if justify then
    fs:SetJustifyH(justify)
  end
  if text then
    fs:SetText(text)
  end
  UI.fonts = UI.fonts or {}
  UI.fonts[#UI.fonts + 1] = fs
  return fs
end

-- Re-apply fonts after the "large text" option changes.
function UI.RefreshFonts()
  for _, fs in ipairs(UI.fonts or {}) do
    if fs.role and fs.SetFontObject then
      fs:SetFontObject(T.Font(fs.role))
    end
  end
end

function UI.Icon(parent, size, texture, layer)
  local icon = parent:CreateTexture(nil, layer or "ARTWORK")
  icon:SetSize(size, size)
  if texture then
    icon:SetTexture(texture)
  end
  return icon
end

-- Tooltip with a title and optional body lines on any frame.
function UI.Tooltip(frame, title, body)
  frame:HookScript("OnEnter", function(self)
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(type(title) == "function" and title() or title, T.color.gold.r, T.color.gold.g, T.color.gold.b)
    local text = type(body) == "function" and body() or body
    if text and text ~= "" then
      GameTooltip:AddLine(text, 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
end

function UI.Button(parent, text, width, onClick, tipTitle, tipBody)
  local button = UI.Create("Button", parent, "UIPanelButtonTemplate")
  button:SetSize(width or 140, 24)
  button:SetText(text)
  button:SetScript("OnClick", function(self, mouse)
    SL.SafeCall("button " .. tostring(text), onClick, self, mouse)
  end)
  if tipTitle then
    UI.Tooltip(button, tipTitle, tipBody)
  end
  return button
end

function UI.Check(parent, label, getValue, setValue, tipBody)
  local check = UI.Create("CheckButton", parent, "UICheckButtonTemplate")
  check:SetSize(26, 26)
  local fs = check.Text
  if not fs then
    fs = UI.Text(check, "body")
    fs:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.Text = fs
  else
    fs:SetFontObject(T.Font("body"))
  end
  fs:SetText(label)
  check:SetChecked(getValue() and true or false)
  check:SetScript("OnClick", function(self)
    local value = self:GetChecked() and true or false
    T.Play(value and "checkOn" or "checkOff")
    SL.SafeCall("check " .. tostring(label), setValue, value)
  end)
  if tipBody then
    UI.Tooltip(check, label, tipBody)
  end
  check.Refresh = function(self)
    self:SetChecked(getValue() and true or false)
  end
  return check
end

-- A card with the game's "Dialog" frame (diamond metal border, as StaticPopup) over a dark dialog background.
function UI.Card(parent, width, height, name)
  local card = UI.Create("Frame", parent or UIParent, nil, name)
  card:SetSize(width, height)
  local bg = card:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(T.tex.dialogBg)
  bg:SetPoint("TOPLEFT", 6, -6)
  bg:SetPoint("BOTTOMRIGHT", -6, 6)
  bg:SetAlpha(0.92)
  card.Bg = bg
  local border = UI.Create("Frame", card, "NineSlicePanelTemplate")
  border:SetAllPoints()
  border:SetFrameLevel(card:GetFrameLevel() + 1)
  if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
    pcall(NineSliceUtil.ApplyLayoutByName, border, "Dialog")
  end
  card.Border = border
  card:EnableMouse(true)
  return card
end

-- Smooth appearance (0.2 s alpha + slight rise) unless "reduce motion" is on.
function UI.FadeIn(frame)
  if SL.settings and SL.settings.reduceMotion then
    frame:SetAlpha(1)
    frame:Show()
    return
  end
  if not frame.fadeIn then
    local group = frame:CreateAnimationGroup()
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.2)
    local move = group:CreateAnimation("Translation")
    move:SetOffset(0, 6)
    move:SetDuration(0.2)
    group:SetScript("OnFinished", function()
      frame:SetAlpha(1)
    end)
    frame.fadeIn = group
  end
  frame:SetAlpha(0)
  frame:Show()
  frame.fadeIn:Play()
end

-- Draggable frame that remembers where the player left it (per character).
function UI.Movable(frame, key, defaultPoint)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    if SL.char then
      SL.char.positions[key] = { point, relPoint, x, y }
    end
  end)
  frame.RestorePosition = function(self)
    self:ClearAllPoints()
    local saved = SL.char and SL.char.positions[key]
    if saved then
      self:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
      self:SetPoint(unpack(defaultPoint))
    end
  end
  frame:RestorePosition()
end

-- Icon + coloured word for a memory tone (never colour alone).
function UI.ToneLine(tone)
  local info = T.tone[tone] or T.tone.neutral
  local word = SL.L["TONE_" .. string.upper(tone or "neutral")] or ""
  return "|T" .. info.icon .. ":14:14|t " .. T.Paint(word, info.color), info
end

function UI.FormatDate(t)
  if not t or t == 0 then
    return ""
  end
  return date and date("%d-%m %H:%M", t) or tostring(t)
end
