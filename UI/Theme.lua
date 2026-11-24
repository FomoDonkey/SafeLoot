-- Native look (docs/PROMPT_MAESTRO.md §6): only the game's own fonts, colours, textures and sounds, so Botín
-- Seguro inherits Forever's skin. Nothing here is custom art.
local _, SL = ...
local T = {}
SL.Theme = T

local function rgb(c, r, g, b)
  if type(c) == "table" and c.r then
    return { r = c.r, g = c.g, b = c.b }
  end
  return { r = r, g = g, b = b }
end

T.color = {
  gold = rgb(NORMAL_FONT_COLOR, 1, 0.82, 0),
  white = rgb(HIGHLIGHT_FONT_COLOR, 1, 1, 1),
  red = rgb(RED_FONT_COLOR, 1, 0.1, 0.1),
  green = rgb(GREEN_FONT_COLOR, 0.1, 1, 0.1),
  orange = rgb(ORANGE_FONT_COLOR, 1, 0.5, 0.25),
  gray = rgb(GRAY_FONT_COLOR, 0.5, 0.5, 0.5),
  yellow = rgb(YELLOW_FONT_COLOR, 1, 1, 0),
}

function T.Hex(color)
  return string.format("ff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
end

function T.Paint(text, color)
  return "|c" .. T.Hex(color) .. tostring(text) .. "|r"
end

-- Font objects of the game; the "large text" accessibility option picks bigger ones.
local FONTS = {
  normal = {
    title = "GameFontNormalLarge", header = "GameFontNormal", body = "GameFontHighlight",
    small = "GameFontHighlightSmall", muted = "GameFontDisableSmall", alert = "GameFontNormalLarge",
  },
  large = {
    title = "GameFontNormalHuge", header = "GameFontNormalLarge", body = "GameFontHighlightLarge",
    small = "GameFontHighlight", muted = "GameFontDisable", alert = "GameFontNormalHuge",
  },
}

function T.Font(role)
  local set = (SL.settings and SL.settings.largeText) and FONTS.large or FONTS.normal
  local name = set[role] or FONTS.normal[role] or "GameFontHighlight"
  if _G[name] then
    return name
  end
  return FONTS.normal[role] or "GameFontHighlight"
end

-- Classic textures every player recognises (ready-check marks: the SHAPE tells the state, not only the colour).
T.tex = {
  ok = "Interface\\RaidFrame\\ReadyCheck-Ready",
  bad = "Interface\\RaidFrame\\ReadyCheck-NotReady",
  wait = "Interface\\RaidFrame\\ReadyCheck-Waiting",
  alert = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
  skull = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
  minimap = "Interface\\AddOns\\SafeLoot\\Media\\Minimap",
  portrait = "Interface\\AddOns\\SafeLoot\\Media\\Portrait",
  dialogBg = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
  remove = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
  removeDown = "Interface\\Buttons\\UI-GroupLoot-Pass-Down",
  removeHighlight = "Interface\\Buttons\\UI-GroupLoot-Pass-Highlight",
}

-- tone -> icon + colour (+ a word for colour-blind players, see Locales TONE_*)
T.tone = {
  bad = { icon = T.tex.bad, color = T.color.red },
  warn = { icon = T.tex.alert, color = T.color.orange },
  mixed = { icon = T.tex.wait, color = T.color.yellow },
  good = { icon = T.tex.ok, color = T.color.green },
  neutral = { icon = T.tex.wait, color = T.color.gray },
}

local S = SOUNDKIT or {}
T.sound = {
  alarm = S.RAID_WARNING or 8959,
  agreed = S.READY_CHECK or 8960,
  open = S.IG_MAINMENU_OPEN or 850,
  close = S.IG_MAINMENU_CLOSE or 851,
  tab = S.IG_CHARACTER_INFO_TAB or 841,
  checkOn = S.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,
  checkOff = S.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857,
  toast = S.TELL_MESSAGE or 3081,
}

function T.Play(which)
  if which ~= "alarm" and SL.settings and SL.settings.sounds == false then
    return
  end
  SL.API.PlaySound(T.sound[which])
end
