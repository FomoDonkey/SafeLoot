-- Screenshot mode (/safeloot shots): shows every part of SafeLoot with an invented group, on this screen only, over a
-- plain background, and takes the pictures by itself. For the add-on's page: real windows, no real player's name.
-- Everything is swapped for copies while it runs and put back at the end; nothing is saved, nothing is sent. It stops
-- at once if combat starts. (Not listed in the help: it is a tool for the author.)
local _, SL = ...
local Demo = SL:NewModule("Demo")
SL.Demo = Demo
local API, Names, Rules, UI, T, L = SL.API, SL.Names, SL.Rules, SL.UI, SL.Theme, SL.L

local ME = "Alaric Stormhand"
local GROUP = {
  { name = ME, class = "PALADIN", unit = "player" }, { name = "Borin Ironbelly", class = "WARRIOR", unit = "party1" },
  { name = "Elowen Brightwater", class = "PRIEST", unit = "party2" }, { name = "Runa Frostvale", class = "MAGE", unit = "party3" },
  { name = "Pip Fastfeet", class = "HUNTER", unit = "party4" },
}
-- English names for the items that appear, whatever the language of the game (the icon, colour and tooltip are real)
local ITEMS = {
  [13335] = "Deathcharger's Reins", [13505] = "Runeblade of Baron Rivendare", [22411] = "Helm of the Executioner", [22412] = "Thuzadin Mantle",
  [13340] = "Cape of the Black Baron", [13346] = "Robes of the Exalted", [22409] = "Tunic of the Crescent Moon", [13344] = "Dracorian Gauntlets",
  [22410] = "Gauntlets of Deftness", [13345] = "Seal of Rivendare", [22408] = "Ritssyn's Wand of Bad Mojo", [13349] = "Scepter of the Unholy",
  [13368] = "Bonescraper", [13361] = "Skullforge Reaver", [16694] = "Devout Skirt", [16687] = "Magister's Leggings", [16699] = "Dreadmist Leggings",
  [16709] = "Shadowcraft Pants", [16719] = "Wildheart Kilt", [16678] = "Beaststalker's Pants", [16668] = "Kilt of Elements",
  [16728] = "Lightforge Legplates", [16732] = "Legplates of Valor", [280062] = "Cloak of the Fleshborer", [280063] = "Bloodfur Bulwark",
  [280064] = "Withering Grips", [280056] = "Flameslash Crescent", [280057] = "Robes of Dark Summons", [280058] = "Impish Chain Hood",
  [280059] = "Tuskblade Halberd", [280060] = "Lucky Shovelnose Tuft", [280061] = "Spike Crested Bracers", [280065] = "Behemoth Bones",
  [280066] = "Trousers of the Ebon Giant", [280067] = "Blackmaw Chain Belt", [280068] = "Bloody Claws of Attack", [280070] = "Veilpiercer Girdle",
  [280074] = "Scalding Flamehoof", [280075] = "Bleak Eye Shoulderplates", [280076] = "Horns of Varrox", [280071] = "Flamebreak Talisman",
  [280072] = "Cowl of Dark Ambition", [280073] = "Burnished Pridescales", [280077] = "Fist of Revelation", [280078] = "Apprentice's Protective Treads",
  [280079] = "Lunarlight Robe", [280080] = "Claymore of Two Moons", [280085] = "Tunnelweb Pincer", [280086] = "Octofinger Gauntlets",
  [287032] = "Den Champion's Binding", [251453] = "Plans: Breastplate of Salvation", [287034] = "Grove Subjugator's Blade", [287028] = "Tormented Cuffs",
}
local STRATHOLME, BLACKMAW, RIVENDARE = 329, 2974, 484
local DAY = 86400

local function item(id)
  local info = SL.Catalog:ItemInfo(id)
  return info and info.link or ("[" .. (ITEMS[id] or "?") .. "]")
end

local function players(now)
  local list = {}
  local function add(name, class, seen, daysAgo, ...)
    list[name] = { class = class, seen = seen, first = now - 60 * DAY, last = now - daysAgo * DAY, events = { ... } }
  end
  local function tag(kind, daysAgo, place)
    return { kind = kind, t = now - daysAgo * DAY, place = place }
  end
  local function note(text, daysAgo)
    return { kind = "note", t = now - daysAgo * DAY, note = text }
  end
  add("Grimtooth Vale", "ROGUE", 1, 2, { kind = "need_impossible", t = now - 2 * DAY, place = "Stratholme", item = ITEMS[13346], link = item(13346), class = "ROGUE" },
    note("Rolled Need on a cloth robe and left the group.", 2), tag("tag_ninja", 2, "Stratholme"))
  add("Marrow Quill", "MAGE", 1, 9, tag("tag_ninja", 9, "Scholomance"))
  add("Dorn Blacktusk", "SHAMAN", 2, 31, tag("tag_ninja", 31, "Blackmaw Hold"))
  add("Silas Goldgrin", "WARRIOR", 1, 5, note("Asked 80 gold for the ring after it dropped.", 5), tag("tag_extortion", 5, "Blackrock Depths"))
  add("Nim Quickstep", "DRUID", 2, 12, tag("tag_quitter", 12, "Dire Maul"))
  add("Vexen Duskmire", "WARLOCK", 1, 1, { kind = "need_impossible", t = now - DAY, place = "Blackmaw Hold", item = ITEMS[280063], link = item(280063), class = "WARLOCK" })
  add("Elowen Brightwater", "PRIEST", 14, 0, note("Calm healer. Fridays and Sundays.", 20), tag("tag_trusted", 20, "Stratholme"))
  add("Borin Ironbelly", "WARRIOR", 9, 0, tag("tag_trusted", 15, "Scholomance"))
  add("Thistle Mossbeard", "DRUID", 6, 3, tag("tag_trusted", 18, "Maraudon"))
  add("Kaela Dawnspear", "PALADIN", 4, 6, tag("tag_trusted", 6, "Stratholme"))
  add("Runa Frostvale", "MAGE", 3, 0, note("Knows every pull in Dire Maul.", 8))
  add("Pip Fastfeet", "HUNTER", 2, 0)
  for i, p in ipairs({ { "Orla Stormcall", "SHAMAN" }, { "Hale Redbrook", "WARRIOR" }, { "Sable Nightwell", "WARLOCK" }, { "Tamsin Reed", "ROGUE" }, { "Osric Vane", "PALADIN" } }) do
    add(p[1], p[2], i % 3 + 1, i * 2)
  end
  return list
end

local function runs(now)
  local start = now - DAY - 4000
  local function text(color, title, rest)
    return T.Paint(title, color) .. (rest and (" " .. rest) or "")
  end
  local strat = {
    id = "demo-1", place = "Stratholme", instance = true, startedAt = start, endedAt = start + 3600, members = {},
    events = {
      { kind = "contract", t = start + 60, text = text(T.color.gold, L.CONTRACT_PUBLISHED, L.METHOD_3 .. " · " .. L.NEED_SHORT_msos) },
      { kind = "agreed", t = start + 75, text = string.format(L.CONTRACT_AGREED, "Elowen Brightwater", date("%H:%M", start + 75)) },
      { kind = "agreed", t = start + 80, text = string.format(L.CONTRACT_AGREED, "Runa Frostvale", date("%H:%M", start + 80)) },
      { kind = "mark", t = start + 1900, text = "|T" .. T.tex.bad .. ":14:14|t " .. string.format(L.MARK_LINE, "Grimtooth Vale", item(13346), string.format(L.REASON_CLASS_ARMOR, API.LocalizedClass("ROGUE") or "Rogue")) },
      { kind = "rules_changed", t = start + 3200, severity = 3, text = T.Paint(L.ALARM_ML_TITLE, T.color.red) },
      { kind = "rules_changed", t = start + 3260, severity = 1, text = L.RULES_RESTORED_TITLE },
    },
    drops = {
      a = { item = item(13340), winner = "Pip Fastfeet", class = "HUNTER", t = start + 1500 },
      b = { item = item(13349), winner = "Elowen Brightwater", class = "PRIEST", t = start + 2600 },
      c = { item = item(22411), winner = "Borin Ironbelly", class = "WARRIOR", t = start + 3400 },
    },
  }
  local black = {
    id = "demo-2", place = "Blackmaw Hold", instance = true, startedAt = start + 30000, endedAt = start + 33000, members = {},
    events = { { kind = "contract", t = start + 30050, text = text(T.color.gold, L.CONTRACT_PUBLISHED, L.METHOD_3 .. " · " .. L.BOE_GREED) } },
    drops = {
      a = { item = item(280062), winner = "Thistle Mossbeard", class = "DRUID", t = start + 30900 },
      b = { item = item(280065), winner = ME, class = "PALADIN", t = start + 32100 },
    },
  }
  return { strat, black }, strat
end

local function contract(now)
  return {
    source = "proposed", createdAt = now - 600, publishedAt = now - 300, method = Rules.GROUP, threshold = 2, leader = "Borin Ironbelly",
    needRule = "msos", boe = "greed", instance = STRATHOLME,
    accepted = { ["Borin Ironbelly"] = now - 280, ["Elowen Brightwater"] = now - 270, ["Runa Frostvale"] = now - 240 },
    reserves = {
      { item = ITEMS[13346], itemID = 13346, owner = "Elowen Brightwater", kind = "hard" },
      { item = ITEMS[13340], itemID = 13340, owner = "Pip Fastfeet", kind = "soft" },
      { item = ITEMS[22411], itemID = 22411, owner = "Borin Ironbelly", kind = "soft" },
    },
  }
end

-- Swap in / out -----------------------------------------------------------------------------------------------------
local function backdrop()
  if not Demo.back then
    local f = CreateFrame("Frame", "SafeLootDemoBackdrop", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("MEDIUM") -- above the bars, the chat and the minimap; our windows are higher
    f:SetFrameLevel(9000)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(0.055, 0.04, 0.085, 1)
    f:Hide()
    Demo.back = f
  end
  return Demo.back
end

function Demo:Begin()
  local now = API.Now()
  local saved = { db = SL.db, char = SL.char, contract = SL.Contract.current, awaiting = SL.Contract.awaiting, inGroup = SL.Watcher.inGroup,
    lastState = SL.Watcher.lastState, deviation = SL.Indicator.deviation, functions = {} }
  self.saved = saved
  local function patch(owner, name, fn)
    saved.functions[#saved.functions + 1] = { owner, name, owner[name] }
    owner[name] = fn
  end
  local real = SL.Catalog.ItemInfo
  patch(SL.Catalog, "ItemInfo", function(catalog, id)
    local info = real(catalog, id)
    local english = ITEMS[id]
    if not english or not info then
      return info
    end
    local link = info.link and info.link:gsub("%[.-%]", function()
      return "[" .. english .. "]"
    end)
    return { id = id, name = english, link = link, quality = info.quality or 3, icon = info.icon }
  end)
  patch(API, "GroupMembers", function() return GROUP end)
  patch(API, "InGroup", function() return true end)
  patch(API, "InRaid", function() return false end)
  patch(API, "GroupSize", function() return #GROUP end)
  patch(API, "LeaderName", function() return "Borin Ironbelly" end)
  patch(API, "IsLeader", function() return false end)
  patch(API, "LootState", function()
    return { method = self.method or Rules.GROUP, threshold = 2, leader = "Borin Ironbelly" }
  end)
  patch(API, "PlaceName", function() return "Stratholme" end)
  patch(API, "SendGroupChat", function() return false end)
  patch(API, "SendAddon", function() return false end)
  patch(Names, "Me", function() return ME end)
  SL.db = setmetatable({ players = {}, runs = {}, loot = { [STRATHOLME] = { [RIVENDARE] = { [13340] = now, [13346] = now, [13349] = now, [22411] = now } } } }, { __index = saved.db })
  SL.char = { positions = {}, run = nil }
  SL.db.players = players(now)
  local list, last = runs(now)
  SL.db.runs, self.lastRun = list, last
  SL.Watcher.inGroup = true
  SL.Contract.current, SL.Contract.awaiting = contract(now), false
  for _, frame in ipairs(UI.movables) do
    frame:RestorePosition()
  end
  SL.Alert.queue = {}
  backdrop():Show()
  self.running = true
end

function Demo:End()
  if not self.saved then
    return
  end
  local saved = self.saved
  self.saved, self.running, self.method = nil, false, nil
  for i = #saved.functions, 1, -1 do
    local f = saved.functions[i]
    f[1][f[2]] = f[3]
  end
  SL.db, SL.char = saved.db, saved.char
  SL.Contract.current, SL.Contract.awaiting = saved.contract, saved.awaiting
  SL.Watcher.inGroup, SL.Watcher.lastState = saved.inGroup, saved.lastState
  SL.Indicator.deviation = saved.deviation
  self:Clear()
  self.back:Hide()
  for _, frame in ipairs(UI.movables) do
    frame:RestorePosition()
  end
  if SL.MainFrame.frame then
    local pages = SL.MainFrame.pages
    pages.contract.owner, pages.contract.picked = Names.Me(), nil
    pages.players.selected, pages.players.category = nil, "all"
  end
  SL:Fire("CONTRACT_CHANGED", SL.Contract.current)
  SL:Fire("MEMORY_CHANGED")
end

function Demo:Clear()
  SL.Alert.queue = {}
  SL.Alert:HidePanel()
  if SL.Alert.toast then
    SL.Alert.toast:Hide()
  end
  if SL.Run.summary then
    SL.Run.summary:Hide()
  end
  SL.LootPicker:Hide()
  if SL.MainFrame.frame then
    SL.MainFrame.frame:Hide()
  end
  if _G.SafeLootWelcome then
    _G.SafeLootWelcome:Hide()
  end
  if GameTooltip then
    GameTooltip:Hide()
  end
end

-- The pictures ------------------------------------------------------------------------------------------------------
local function raise(frame)
  if frame and frame.SetFrameStrata then
    frame:SetFrameStrata("DIALOG") -- above the plain background
  end
end

local function playersPage(category, selected)
  SL.MainFrame:Open("players")
  local page = SL.MainFrame.pages.players
  page.category = category
  page.Search:SetText("")
  page.selected = selected
  SL.MainFrame:Refresh()
end

Demo.STEPS = {
  { "rules", function() SL.MainFrame:Open("contract") end },
  { "dungeons", function()
    SL.MainFrame:Open("contract")
    SL.LootPicker:Open(nil)
  end },
  { "loot", function()
    SL.MainFrame:Open("contract")
    SL.LootPicker:Open(STRATHOLME)
    SL.LootPicker.frame.Search:SetText("Rivendare")
    SL.LootPicker.frame.Search.Refresh()
    SL.LootPicker:Refresh()
  end },
  { "loot-new", function()
    SL.MainFrame:Open("contract")
    SL.LootPicker:Open(BLACKMAW)
  end },
  { "players", function() playersPage("all", "Grimtooth Vale") end },
  { "players-ninja", function() playersPage("ninja", "Marrow Quill") end },
  { "players-trusted", function() playersPage("trusted", "Elowen Brightwater") end },
  { "journal", function() SL.MainFrame:Open("journal") end },
  { "alarm", function()
    Demo.method = Rules.MASTER
    SL.Indicator:Update()
    raise(_G.SafeLootIndicator)
    SL.Alert:ShowPanel({
      severity = 3, title = L.ALARM_ML_TITLE, body = string.format(L.ALARM_ML_BODY, date("%H:%M"), "Borin Ironbelly", L.METHOD_3),
      actions = { { label = L.ACTION_ASK, fn = function() end }, { label = L.ACTION_SAVE, fn = function() end }, { label = L.ACTION_ACCEPT, fn = function() end } },
    })
    API.CenterWarning(L.ALARM_ML_TITLE, T.color.red, 3)
  end },
  { "bar", function()
    SL.Indicator:Update()
    raise(_G.SafeLootIndicator)
    SL.Indicator:ShowTooltip(_G.SafeLootIndicator)
  end },
  { "mark", function()
    SL.Alert:ShowToast({
      tone = "bad", title = L.MARK_IMPOSSIBLE, seconds = 15,
      body = string.format(L.MARK_LINE, "Grimtooth Vale", item(13346), string.format(L.REASON_CLASS_ARMOR, API.LocalizedClass("ROGUE") or "Rogue")),
      action = { label = L.ACTION_TELL_GROUP, fn = function() end }, action2 = { label = L.ACTION_MISTAKE, fn = function() end },
    })
  end },
  { "joined", function()
    SL.Alert:ShowToast({
      tone = "bad", title = SL.Players:Label("ninja", 16, true) .. " · " .. string.format(L.JOINED_TITLE, "Grimtooth Vale"), seconds = 15,
      body = SL.MemoryHooks.EventText(SL.db.players["Grimtooth Vale"].events[3]),
    })
  end },
  { "tooltip", function()
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    GameTooltip:SetText("Grimtooth Vale", 1, 0.96, 0.41)
    for _, line in ipairs(SL.MemoryHooks:TooltipLines("Grimtooth Vale") or {}) do
      GameTooltip:AddLine(line, 1, 1, 1, true)
    end
    GameTooltip:Show()
  end },
  { "summary", function()
    SL.Run:ShowSummary(Demo.lastRun)
  end },
  { "help", function() SL.MainFrame:Open("help") end },
  { "welcome", function() SL:HandleSlash("welcome") end },
}

-- Takes every picture with the game's own screenshot function. The names of the files are the game's; the order is
-- the one of STEPS.
function Demo:Shots()
  if self.running then
    self:Stop(L.SHOTS_STOPPED)
    return
  end
  if SL:InCombat() or not (C_Timer and C_Timer.After) then
    SL:Print(L.SHOTS_COMBAT)
    return
  end
  SL:Print(L.SHOTS_START)
  -- build the window and ask the game for the items before starting
  SL.MainFrame:Open("contract")
  for id in pairs(ITEMS) do
    SL.Catalog:ItemInfo(id)
  end
  C_Timer.After(5, function()
    if SL:InCombat() or self.running then
      return
    end
    self:Begin()
    self.token = (self.token or 0) + 1
    self:Step(1, self.token)
  end)
end

function Demo:Step(i, token)
  if not self.running or token ~= self.token then
    return
  end
  local step = self.STEPS[i]
  if not step then
    self:Stop(string.format(L.SHOTS_DONE, #self.STEPS))
    return
  end
  self:Clear()
  self.method = nil
  SL.SafeCall("shot " .. step[1], step[2])
  C_Timer.After(1.8, function()
    if not self.running or token ~= self.token then
      return
    end
    if type(Screenshot) == "function" then
      pcall(Screenshot)
    end
    C_Timer.After(1.2, function()
      self:Step(i + 1, token)
    end)
  end)
end

function Demo:Stop(message)
  self:End()
  if _G.SafeLootIndicator then
    _G.SafeLootIndicator:SetFrameStrata("MEDIUM")
  end
  SL.Indicator:Update()
  SL:Print(message)
end

function Demo:OnEnable()
  SL:RegisterCommand("shots", function()
    Demo:Shots()
  end, nil, { "capturas" })
  SL:RegisterEvent("PLAYER_REGEN_DISABLED", self, function()
    if Demo.running then
      Demo:Stop(L.SHOTS_STOPPED)
    end
  end)
end
