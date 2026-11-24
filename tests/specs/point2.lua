-- 0.2.0: rules indicator, welcome card, "It's a mistake", notes and new players, help tab.
local SL = NS
local L = SL.L

local function settle()
  for _ = 1, 6 do
    if #SIM.timers == 0 then
      return
    end
    SIM.RunTimers()
  end
end

local function clearToasts()
  SL.Alert.queue = {}
  _G.SafeLootToast:Hide()
end

local function joinGroup()
  SIM.inGroup, SIM.groupSize = true, 4
  SIM.units.party1 = { first = "Krag", second = "Hierro", class = "WARRIOR" }
  SIM.units.party2 = { first = "Zarn", second = "Brasa", class = "MAGE" }
  SIM.leaderUnit, SIM.lootMethod = "party1", 3
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
end

test("welcome card appears once on the first login", function()
  ok(_G.SafeLootWelcome and _G.SafeLootWelcome:IsShown(), "shown")
  ok(SafeLootDB.settings.onboarded, "remembered")
  _G.SafeLootWelcome:Hide()
  SL:HandleSlash("welcome")
  ok(_G.SafeLootWelcome:IsShown(), "/safeloot welcome shows it again")
  _G.SafeLootWelcome:Hide()
end)

test("rules indicator: hidden alone, shown in a group with the rules", function()
  ok(not _G.SafeLootIndicator:IsShown(), "hidden when not grouped")
  joinGroup()
  ok(_G.SafeLootIndicator:IsShown(), "shown in group")
  ok(contains(_G.SafeLootIndicator.Text:GetText(), L.METHOD_3), "shows the method: " .. tostring(_G.SafeLootIndicator.Text:GetText()))
end)

test("rules indicator turns red when the rules change, and back when restored", function()
  SIM.lootMethod, SIM.masterPartyID = 2, 1
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  ok(contains(_G.SafeLootIndicator.Text:GetText(), L.IND_CHANGED), "red warning")
  SIM.lootMethod = 3
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  ok(not contains(_G.SafeLootIndicator.Text:GetText(), L.IND_CHANGED), "back to normal")
end)

test("rules indicator: click opens the Rules tab, tooltip explains", function()
  _G.SafeLootIndicator:Click()
  ok(_G.SafeLootMainFrame:IsShown(), "window open")
  eq(SL.MainFrame.tab, "contract")
  _G.SafeLootMainFrame:Hide()
  GameTooltip._lines = {}
  SL.Indicator:ShowTooltip(_G.SafeLootIndicator)
  ok(#GameTooltip._lines >= 2, "tooltip lines")
end)

test("rules indicator can be turned off", function()
  SafeLootDB.settings.showIndicator = false
  SL:Fire("SETTING_CHANGED", "showIndicator", false)
  ok(not _G.SafeLootIndicator:IsShown(), "hidden by the option")
  SafeLootDB.settings.showIndicator = true
  SL:Fire("SETTING_CHANGED", "showIndicator", true)
  ok(_G.SafeLootIndicator:IsShown(), "back")
end)

local MAIL = "|cff0070dd|Hitem:9001::::::::60:::::|h[Coraza de malla]|h|r"
test("'It's a mistake' teaches the detector and takes the note back", function()
  clearToasts()
  SIM.items[MAIL] = { itemID = 9001, equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 3, name = "Coraza de malla", quality = 3, bindType = 1 }
  SIM.lootDrops["20:1"] = { itemHyperlink = MAIL, rollInfos = { { playerName = "Zarn-Brasa", playerClass = "MAGE", isSelf = false, state = 0 } } }
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 20, 1)
  local toast = _G.SafeLootToast
  eq(toast.Title:GetText(), L.MARK_IMPOSSIBLE)
  ok(toast.Action2:IsShown(), "mistake button offered")
  local rec = SL.Memory.Get(SafeLootDB.players, "Zarn Brasa")
  local before = #rec.events
  toast.Action2:Click()
  ok(SafeLootDB.settings.exceptions["MAGE:4:3"], "exception saved")
  eq(#rec.events, before - 1, "automatic note removed")
  clearToasts()
  SIM.lootDrops["21:1"] = { itemHyperlink = MAIL, rollInfos = { { playerName = "Zarn-Brasa", playerClass = "MAGE", isSelf = false, state = 0 } } }
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 21, 1)
  ok(not _G.SafeLootToast:IsShown(), "not flagged again")
  SL:HandleSlash("exceptions")
  eq(next(SafeLootDB.settings.exceptions), nil, "/safeloot exceptions clears them")
end)

test("doubtful (rules-based) marks do not offer 'It's a mistake'", function()
  clearToasts()
  SL.Contract:Adopt({ needRule = "greed" }, "copied")
  local link = "|cff0070dd|Hitem:9003::::::::60:::::|h[Hacha]|h|r"
  SIM.items[link] = { itemID = 9003, equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 1, name = "Hacha", quality = 3, bindType = 1 }
  SIM.lootDrops["22:1"] = { itemHyperlink = link, rollInfos = { { playerName = "Krag-Hierro", playerClass = "WARRIOR", isSelf = false, state = 0 } } }
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 22, 1)
  eq(_G.SafeLootToast.Title:GetText(), L.MARK_DOUBTFUL)
  ok(not _G.SafeLootToast.Action2:IsShown(), "no mistake button")
  clearToasts()
end)

test("notes: free text on a player, cleaned and saved", function()
  SL.MainFrame:Open("players")
  local page = SL.MainFrame.pages.players
  page.selected = "Krag Hierro"
  page.Note:SetText("Pidió |cffff0000oro|r por la reserva")
  page.NoteButton:Click()
  local rec = SL.Memory.Get(SafeLootDB.players, "Krag Hierro")
  local last = rec.events[#rec.events]
  eq(last.kind, "note")
  eq(last.note, "Pidió oro por la reserva")
end)

test("someone not in the memory yet can be added from the search box", function()
  local page = SL.MainFrame.pages.players
  page.selected = nil
  page.Search:SetText("Vex-Oscuro")
  SL.MainFrame:Refresh()
  ok(contains(page.Detail:GetText(), "Vex Oscuro"), "hint names the new player: " .. tostring(page.Detail:GetText()))
  page.tagButtons[2]:Click() -- "Ninja"
  local rec = SL.Memory.Get(SafeLootDB.players, "Vex Oscuro")
  ok(rec and rec.events[1].kind == "tag_ninja", "created with the tag")
  page.Search:SetText("")
end)

test("help tab lists the glossary and the commands", function()
  SL.MainFrame:Open("help")
  local items = SL.MainFrame.pages.help.List.provider.items
  ok(#items > 15, "help lines: " .. #items)
  local all = {}
  for _, item in ipairs(items) do
    all[#all + 1] = item.text
  end
  local text = table.concat(all, "\n")
  ok(contains(text, L.GLOSS_ML), "glossary")
  ok(contains(text, "/safeloot test"), "commands")
  SL:HandleSlash("ayuda")
  eq(SL.MainFrame.tab, "help")
end)

test("settings include the indicator and the exceptions button", function()
  ok(SIM.settingsRegistered.showIndicator, "showIndicator registered")
end)
