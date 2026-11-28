-- Players you marked, everywhere you meet them (0.5.0): right-click menu on any player, a badge under the target's
-- portrait, and a notice when someone you marked badly whispers you. The tooltip, the Group Finder, invitations and
-- people joining are in MemoryHooks. Everything shows an icon AND a word, never only a colour.
local _, SL = ...
local PL = SL:NewModule("Players")
SL.Players = PL
local API, Memory, Names, UI, T, L = SL.API, SL.Memory, SL.Names, SL.UI, SL.Theme, SL.L

-- The opinions offered everywhere, in this order.
PL.TAGS = { "tag_trusted", "tag_ninja", "tag_extortion", "tag_quitter" }
local BAD = { ninja = true, extortion = true, quitter = true, warned = true }
PL.BAD = BAD

-- Category of a remembered player: category, record. nil when nothing is known (or the memory is off).
function PL:Category(name)
  if not SL.settings.memory or type(name) ~= "string" then
    return nil
  end
  local record = Memory.Get(SL.db.players, name)
  if not record then
    return nil
  end
  return Memory.Category(record, API.Now(), SL.settings.memoryDays), record
end

-- "|Ticon|t NINJA" in its colour.
function PL:Label(category, size, upper)
  local c = T.category[category] or T.category.seen
  local key = string.upper(category)
  local word = L["LABEL_" .. key] or L["CAT_" .. key] or category
  return "|T" .. c.icon .. ":" .. (size or 14) .. ":" .. (size or 14) .. "|t " .. T.Paint(upper and Memory.Upper(word) or word, c.color)
end

function PL:TagLabel(kind, size)
  return self:Label(Memory.TAG_CATEGORY[kind], size)
end

-- Put or remove an opinion, from anywhere.
function PL:Tag(name, kind, quiet)
  local short = Names.Short(name)
  if not short or Names.IsMe(short) then
    return nil
  end
  local active = Memory.SetTag(SL.db.players, short, kind, API.Now(), API.PlaceName())
  SL:Fire("MEMORY_CHANGED", short)
  if not quiet then
    SL:Print(active and (short .. ": " .. self:TagLabel(active)) or string.format(L.TAG_REMOVED, short))
  end
  return active
end

-- The opinions and the card, inside any of the game's menus.
function PL:FillMenu(root, name)
  local short = Names.Short(name)
  for _, kind in ipairs(PL.TAGS) do
    root:CreateRadio(PL:TagLabel(kind), function()
      local record = Memory.Get(SL.db.players, short)
      return record ~= nil and Memory.ActiveTag(record) == kind
    end, function()
      PL:Tag(short, kind)
    end)
  end
  root:CreateButton(L.MENU_CARD, function()
    SL.MainFrame:OpenPlayer(short)
  end)
end

-- 1. Right click on a player: party, raid, target, chat, friends, guild ------------------------------------------
local MENUS = { "PLAYER", "PARTY", "RAID_PLAYER", "RAID", "ENEMY_PLAYER", "TARGET", "FOCUS", "FRIEND", "FRIEND_OFFLINE", "GUILD",
  "GUILD_OFFLINE", "CHAT_ROSTER", "RECENT_ALLY", "RECENT_ALLY_OFFLINE", "COMMUNITIES_GUILD_MEMBER", "COMMUNITIES_WOW_MEMBER" }

-- The player a unit menu is about; nil for creatures, for yourself and for names the game hides.
function PL.MenuName(context)
  if type(context) ~= "table" then
    return nil
  end
  local unit = context.unit
  if unit ~= nil and not API.IsSecret(unit) then
    if not API.UnitIsPlayer(unit) then
      return nil
    end
    local name = Names.Unit(unit)
    return name and not Names.IsMe(name) and name or nil
  end
  local first, second = context.name, context.surname
  if API.IsSecret(first) or API.IsSecret(second) or type(first) ~= "string" or first == "" then
    return nil
  end
  local name = first
  if type(second) == "string" and second ~= "" and not first:find(" ", 1, true) then
    name = first .. " " .. second
  end
  return not Names.IsMe(name) and Names.Short(name) or nil
end

local function onUnitMenu(root, context)
  if not SL.settings.memory or not SL.settings.showUnitMenu then
    return
  end
  local name = PL.MenuName(context)
  if not name then
    return
  end
  local category = PL:Category(name)
  local sub = root:CreateButton(L.ADDON_NAME .. (category and category ~= "seen" and (": " .. PL:Label(category)) or ""))
  PL:FillMenu(sub, name)
end

function PL:HookMenus()
  if not (Menu and Menu.ModifyMenu) then
    return
  end
  for _, which in ipairs(MENUS) do
    pcall(Menu.ModifyMenu, "MENU_UNIT_" .. which, function(_, root, context)
      SL.SafeCall("unit menu", onUnitMenu, root, context)
      if SL.Diagnostics then
        SL.Diagnostics:Observe("unit_menu", { named = PL.MenuName(context) ~= nil })
      end
    end)
  end
end

-- 2. Badge under the target's portrait --------------------------------------------------------------------------------
function PL:BuildBadge()
  local anchor = TargetFrame and ((TargetFrame.TargetFrameContainer and TargetFrame.TargetFrameContainer.Portrait) or TargetFrame)
  if not anchor then
    return
  end
  local f = CreateFrame("Frame", "SafeLootTargetBadge", UIParent, "BackdropTemplate")
  f:SetSize(96, 22)
  f:SetFrameStrata("MEDIUM")
  f:EnableMouse(false) -- never in the way of a click on the target
  f:SetPoint("TOP", anchor, "BOTTOM", 0, 4)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0, 0, 0, 0.85)
  end
  f.Text = UI.Text(f, "small", "", "CENTER")
  f.Text:SetPoint("CENTER", 0, 0)
  f.Text:SetWordWrap(false)
  f:Hide()
  self.badge = f
end

function PL:UpdateBadge()
  local f = self.badge
  if not f then
    return
  end
  local category
  if SL.settings.showTarget and API.UnitIsPlayer("target") then
    local name = Names.Unit("target")
    category = name and not Names.IsMe(name) and self:Category(name) or nil
  end
  if not category or category == "seen" or category == "noted" then
    f:Hide()
    return
  end
  f.Text:SetText(self:Label(category, 14, true))
  f:SetWidth((f.Text:GetStringWidth() or 70) + 18)
  local color = T.category[category].color
  if f.SetBackdropBorderColor then
    f:SetBackdropBorderColor(color.r, color.g, color.b, 1)
  end
  f:Show()
end

-- 3. A whisper from someone you marked badly --------------------------------------------------------------------------
function PL:OnWhisper(_, _, sender)
  if not SL.settings.showWhisper or API.IsSecret(sender) then
    return
  end
  local name = Names.Short(sender)
  local category, record = self:Category(name)
  if not category or not BAD[category] or not SL:Cooldown("whisper-" .. name, 900) then
    return
  end
  local summary = Memory.Summary(record, API.Now(), SL.settings.memoryDays)
  SL.Alert:Toast({
    tone = category == "warned" and "warn" or "bad",
    title = string.format(L.WHISPER_TITLE, name) .. " · " .. self:Label(category, 14, true),
    body = SL.MemoryHooks.NoticeBody(record, summary),
    seconds = 15,
  })
end

function PL:OnEnable()
  self:HookMenus()
  self:BuildBadge()
  SL:RegisterEvent("PLAYER_TARGET_CHANGED", self, self.UpdateBadge)
  SL:RegisterEvent("CHAT_MSG_WHISPER", self, self.OnWhisper)
  SL:On("MEMORY_CHANGED", self, function()
    PL:UpdateBadge()
  end)
  SL:On("SETTING_CHANGED", self, function(_, key)
    if key == "showTarget" or key == "memory" then
      PL:UpdateBadge()
    end
  end)
end
