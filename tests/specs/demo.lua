-- 0.5.1: what the real client showed, and the screenshot mode.
local SL = NS
local L = SL.L
_G.SafeLootWelcome:Hide()
local function settle(n)
  for _ = 1, n or 200 do
    if #SIM.timers == 0 then return end
    SIM.RunTimers()
  end
end

test("BUG: no character the game's font lacks (arrows were empty boxes)", function()
  for key, text in pairs(L) do
    if type(text) == "string" then ok(not text:find("→", 1, true), key) end
  end
  local c = SL.Rules.New("proposed", 1)
  SL.Rules.Apply(c, { reserves = { { item = "X", owner = "Krag Hierro", kind = "hard" } } })
  ok(not SL.Rules.ChatLine(c, L):find("→", 1, true))
end)

test("BUG: drops in the order they fell, every time", function()
  local run = { place = "X", startedAt = SIM.now, events = {}, drops = {} }
  for i = 1, 12 do run.drops["k" .. (i * 7919 % 13)] = { item = "[Item " .. i .. "]", winner = "W", t = SIM.now + i * 60 } end
  local list = SL.Run.SortedDrops(run)
  for i = 2, #list do ok(list[i - 1].t < list[i].t, "sorted") end
  local lines = SL.Run:SummaryLines(run)
  ok(contains(lines[3], "[Item 1]") and lines[3]:match("^%d%d:%d%d"), lines[3])
end)

test("BUG: no loose dot in the chat line when nothing is chosen", function()
  eq(SL.Rules.ChatLine(SL.Rules.New("proposed", 1), L), L.CHAT_PREFIX .. " " .. L.CHAT_ASK)
end)

test("BUG: plain text on the red buttons", function()
  SL.MainFrame:Open("players")
  for _, b in ipairs(SL.MainFrame.pages.players.tagButtons) do
    ok(not b:GetText():find("|cff", 1, true), b:GetText())
    ok(b:GetText():find("|T", 1, true), "icon")
  end
  SL.MainFrame:Open("contract")
  ok(not SL.MainFrame.pages.contract.OwnerButton:GetText():find("|cff", 1, true))
end)

test("the author's tools are not listed in the help", function()
  SIM.chatOutput = {}
  SL:HandleSlash("whatisthis")
  local all = table.concat(SIM.chatOutput, "\n")
  ok(contains(all, "/safeloot minimap"))
  ok(not contains(all, "/safeloot shots"))
end)

test("screenshot mode: one picture per screen, all drawn, nothing real touched, everything back", function()
  SafeLootDB.players["Persona Real"] = { events = {}, seen = 2, last = SIM.now }
  SL.Contract:SetDestination(43)
  local realDB, realChar, realContract, me = SL.db, SL.char, SL.Contract:Get(), SL.Names.Me()
  local sent, addon = #SIM.sent, #SIM.addonSent
  local seen = {}
  SIM.shots = 0
  SIM.onShot = function(n)
    local step = SL.Demo.STEPS[n][1]
    seen[#seen + 1] = step
    if step == "players" then
      local text = {}
      for _, item in ipairs(SL.MainFrame.pages.players.List.provider.items) do text[#text + 1] = item.name end
      text = table.concat(text, ",")
      ok(contains(text, "Grimtooth Vale"), "invented players")
      ok(not contains(text, "Persona Real"), "never a real one")
    elseif step == "rules" then
      eq(#SL.MainFrame.pages.contract.ReserveList.provider.items, 3)
      ok(contains(SL.MainFrame.pages.contract.OwnerButton:GetText(), "Alaric"), "not my name")
    elseif step == "loot" then
      local n2 = 0
      for _, row in ipairs(SL.LootPicker.frame.List.provider.items) do if row.kind == "item" then n2 = n2 + 1 end end
      ok(n2 > 10, "items: " .. n2)
    elseif step == "alarm" then
      ok(_G.SafeLootAlarmPanel:IsShown())
      ok(contains(_G.SafeLootIndicator.Text:GetText(), L.IND_CHANGED), "red bar")
    elseif step == "journal" then
      ok(#SL.MainFrame.pages.journal.List.provider.items > 10)
    elseif step == "mark" or step == "joined" then
      ok(_G.SafeLootToast:IsShown())
    elseif step == "summary" then
      ok(_G.SafeLootSummary:IsShown())
    elseif step == "tooltip" then
      ok(contains(table.concat(GameTooltip._lines, "\n"), "NINJA"))
    end
  end
  GameTooltip._lines = {}
  SL:HandleSlash("shots")
  settle()
  SIM.onShot = nil
  eq(SIM.shots, #SL.Demo.STEPS)
  eq(#seen, #SL.Demo.STEPS)
  eq(SL.db, realDB)
  eq(SL.char, realChar)
  eq(SL.Contract:Get(), realContract)
  eq(SL.Names.Me(), me)
  ok(SafeLootDB.players["Persona Real"], "real player there")
  eq(SafeLootDB.players["Grimtooth Vale"], nil, "nothing invented was saved")
  eq(#SIM.sent, sent, "nothing in chat")
  eq(#SIM.addonSent, addon, "nothing to other add-ons")
  ok(not _G.SafeLootDemoBackdrop:IsShown(), "background gone")
  eq(#(SafeLootDB.errors or {}), 0)
end)

test("screenshot mode stops at once when combat starts, and by asking again", function()
  local realDB = SL.db
  SL:HandleSlash("capturas")
  SIM.RunTimers()
  ok(SL.Demo.running, "running")
  ok(SL.db ~= realDB)
  SIM.Fire("PLAYER_REGEN_DISABLED")
  ok(not SL.Demo.running)
  eq(SL.db, realDB, "real data back at once")
  local shots = SIM.shots
  settle()
  eq(SIM.shots, shots, "no more pictures")
  SL:HandleSlash("shots")
  SIM.RunTimers()
  ok(SL.Demo.running)
  SL:HandleSlash("shots")
  ok(not SL.Demo.running)
  eq(SL.db, realDB)
  settle()
  SIM.combat = true
  SL:HandleSlash("shots")
  settle()
  ok(not SL.Demo.running, "never in combat")
  SIM.combat = false
end)

test("the pictures are in English even if the game is not", function()
  LOCALIZED_CLASS_NAMES_MALE = LOCALIZED_CLASS_NAMES_MALE or {}
  local before = LOCALIZED_CLASS_NAMES_MALE.ROGUE
  LOCALIZED_CLASS_NAMES_MALE.ROGUE = "Pícaro"
  _G.ITEM_QUALITY2_DESC = "Poco común"
  eq(SL.API.LocalizedClass("ROGUE"), "Pícaro")
  SL.Demo:Begin()
  eq(SL.API.LocalizedClass("ROGUE"), "Rogue")
  eq(SL.API.QualityName(2), "Uncommon")
  ok(contains(SL.Contract:GameStateLine(), "Uncommon"), SL.Contract:GameStateLine())
  local texts = {}
  for _, run in ipairs(SL.db.runs) do
    for _, e in ipairs(run.events) do texts[#texts + 1] = e.text end
  end
  ok(contains(table.concat(texts, " "), "Rogue") and not contains(table.concat(texts, " "), "Pícaro"), "journal")
  SL.Demo:End()
  eq(SL.API.LocalizedClass("ROGUE"), "Pícaro", "the game's words are back")
  eq(SL.API.QualityName(2), "Poco común")
  LOCALIZED_CLASS_NAMES_MALE.ROGUE, _G.ITEM_QUALITY2_DESC = before, nil
end)
