-- Full-addon scenarios against the simulated client (Spanish client, language "auto").
local SL = NS
local L = SL.L

-- timers (debounce, delayed snapshot) run until none is left
local function settle()
  for _ = 1, 6 do
    if #SIM.timers == 0 then
      return
    end
    SIM.RunTimers()
  end
end

-- a toast queue exists now: start each check from a clean screen
local function clearToasts()
  SL.Alert.queue = {}
  _G.SafeLootToast:Hide()
end

local function joinGroup()
  SIM.inGroup, SIM.groupSize = true, 4
  SIM.units.party1 = { first = "Krag", second = "Hierro", class = "WARRIOR" }
  SIM.units.party2 = { first = "Zarn", second = "Brasa", class = "MAGE" }
  SIM.units.party3 = { first = "Lia", second = "Sombra", class = "ROGUE" }
  SIM.leaderUnit, SIM.lootMethod = "party1", 3
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
end

test("language: Spanish client gets Spanish texts", function()
  eq(SL.language, "esES")
  eq(L.ALARM_ML_TITLE, "¡El líder ha cambiado a BOTÍN MAESTRO!")
end)

test("joining a group takes the automatic snapshot", function()
  joinGroup()
  local c = SL.Contract:Get()
  ok(c, "contract exists")
  eq(c.source, "auto")
  eq(c.method, 3)
  eq(#SIM.warnings, 0, "no alarm on join")
end)

test("switch to master loot fires the alarm (warning, sound, panel)", function()
  SIM.lootMethod, SIM.masterPartyID = 2, 1
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  eq(#SIM.warnings, 1)
  eq(last(SIM.warnings), L.ALARM_ML_TITLE)
  ok(SIM.sounds[#SIM.sounds] == 8959 or SIM.sounds[#SIM.sounds - 1] == 8959, "raid warning sound")
  local panel = _G.SafeLootAlarmPanel
  ok(panel:IsShown(), "panel shown")
  eq(panel.Title:GetText(), L.ALARM_ML_TITLE)
  ok(contains(panel.Body:GetText(), "Krag Hierro"), "names the looter: " .. tostring(panel.Body:GetText()))
end)

test("'Ask the group' sends a polite line to the party (only on click)", function()
  eq(#SIM.sent, 0, "nothing sent before the click")
  _G.SafeLootAlarmPanel.buttons[1]:Click()
  eq(#SIM.sent, 1)
  eq(SIM.sent[1].chatType, "PARTY")
  eq(SIM.sent[1].text, L.CHAT_ASK_METHOD)
  ok(not _G.SafeLootAlarmPanel:IsShown(), "panel closes")
end)

test("'Save evidence' notes the leader in memory", function()
  SIM.lootMethod = 3
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED") -- back to group loot: info toast, no alarm
  eq(#SIM.warnings, 1, "no new alarm when the rules come back")
  SIM.lootMethod = 2
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  eq(#SIM.warnings, 2)
  _G.SafeLootAlarmPanel.buttons[2]:Click()
  local rec = SL.Memory.Get(SafeLootDB.players, "Krag Hierro")
  ok(rec and rec.events[1] and rec.events[1].kind == "rules_changed", "leader remembered")
end)

test("a change during combat waits for the end of combat", function()
  SIM.lootMethod = 3
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  local before = #SIM.warnings
  SIM.combat = true
  SIM.lootMethod = 2
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  eq(#SIM.warnings, before, "nothing read in combat")
  SIM.combat = false
  SIM.Fire("PLAYER_REGEN_ENABLED")
  eq(#SIM.warnings, before + 1, "checked when combat ended")
end)

test("no alarm when you lead and change it yourself", function()
  SIM.lootMethod = 3
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  local before = #SIM.warnings
  SIM.leaderUnit = "player"
  SIM.lootMethod = 2
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  eq(#SIM.warnings, before)
  SIM.leaderUnit = "party1"
  SIM.lootMethod = 3
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
end)

test("secret loot method is ignored without errors", function()
  SIM.secretToken = {}
  SIM.secrets[SIM.secretToken] = true
  SIM.lootMethodSecret = true
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  SIM.lootMethodSecret = false
  eq(SL.API.LootMethod(), 3)
end)

local MAIL = "|cff0070dd|Hitem:9001::::::::60:::::|h[Coraza de malla]|h|r"
local RING = "|cff0070dd|Hitem:9002::::::::60:::::|h[Anillo del Alba]|h|r"

test("entering an instance starts a run", function()
  SIM.inInstance, SIM.instanceType = true, "party"
  SIM.Fire("PLAYER_ENTERING_WORLD")
  ok(SL.Run:Current(), "run started")
  eq(SL.Run:Current().place, "Cumbre de Roca Negra")
end)

test("mage Need on mail: impossible mark, toast and memory", function()
  clearToasts()
  SIM.items[MAIL] = { itemID = 9001, equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 3, name = "Coraza de malla", quality = 3, bindType = 1 }
  SIM.lootDrops["10:1"] = {
    itemHyperlink = MAIL,
    rollInfos = {
      { playerName = "Zarn-Brasa", playerClass = "MAGE", isSelf = false, state = 0 },
      { playerName = "Krag-Hierro", playerClass = "WARRIOR", isSelf = false, state = 0 },
      { playerName = "Ana-Paciente", playerClass = "PRIEST", isSelf = true, state = 0 },
    },
    winner = { playerName = "Zarn-Brasa", playerClass = "MAGE" },
  }
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 10, 1)
  local toast = _G.SafeLootToast
  ok(toast:IsShown(), "toast shown")
  eq(toast.Title:GetText(), L.MARK_IMPOSSIBLE)
  ok(contains(toast.Body:GetText(), "Zarn Brasa"), "names the roller")
  local rec = SL.Memory.Get(SafeLootDB.players, "Zarn Brasa")
  ok(rec and rec.events[#rec.events].kind == "need_impossible", "remembered")
  eq(SL.Memory.Get(SafeLootDB.players, "Krag Hierro").events[2], nil, "warrior on mail is fine")
  local run = SL.Run:Current()
  local drop = run.drops["10:1"]
  eq(drop.winner, "Zarn Brasa")
end)

test("the same drop event twice does not duplicate marks", function()
  local rec = SL.Memory.Get(SafeLootDB.players, "Zarn Brasa")
  local n = #rec.events
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 10, 1)
  eq(#rec.events, n)
end)

test("'Tell the group' on a mark sends a neutral line only on click", function()
  SIM.now = SIM.now + 5 -- past the anti-spam cooldown of the previous message
  local before = #SIM.sent
  _G.SafeLootToast.Action:Click()
  eq(#SIM.sent, before + 1)
  ok(contains(last(SIM.sent).text, "Zarn Brasa"), "line names the roller")
end)

test("leader's rules in chat become a suggestion, adopted on click", function()
  clearToasts()
  SIM.Fire("CHAT_MSG_PARTY_LEADER", "HR Anillo del Alba, MS>OS", "Krag-Hierro")
  local toast = _G.SafeLootToast
  eq(toast.Title:GetText(), L.SUGGEST_TITLE)
  toast.Action:Click()
  local c = SL.Contract:Get()
  eq(c.source, "copied")
  eq(c.needRule, "msos")
  eq(c.reserves[1].item, "Anillo del Alba")
  eq(c.reserves[1].owner, "Krag Hierro")
end)

test("Need on an item reserved for the leader is doubtful", function()
  clearToasts()
  SIM.items[RING] = { itemID = 9002, equipLoc = "INVTYPE_FINGER", classID = 4, subClassID = 0, name = "Anillo del Alba", quality = 3, bindType = 1 }
  SIM.lootDrops["11:1"] = {
    itemHyperlink = RING,
    rollInfos = { { playerName = "Lia-Sombra", playerClass = "ROGUE", isSelf = false, state = 0 } },
  }
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 11, 1)
  eq(_G.SafeLootToast.Title:GetText(), L.MARK_DOUBTFUL)
  -- doubtful marks are NOT written to memory automatically
  eq(SL.Memory.Get(SafeLootDB.players, "Lia Sombra"), nil)
end)

test("publishing the rules writes one normal chat line; 'ok' replies are recorded", function()
  SIM.now = SIM.now + 5
  local before = #SIM.sent
  SL.Contract:Publish()
  eq(#SIM.sent, before + 1)
  local line = last(SIM.sent).text
  ok(contains(line, L.CHAT_PREFIX), "prefix: " .. line)
  ok(#line <= 255, "fits")
  SIM.Fire("CHAT_MSG_PARTY", "ok!", "Zarn-Brasa")
  SIM.Fire("CHAT_MSG_PARTY", "no me gusta", "Lia-Sombra")
  local c = SL.Contract:Get()
  ok(c.accepted["Zarn Brasa"], "Zarn agreed")
  eq(c.accepted["Lia Sombra"], nil)
end)

test("player tooltip shows the memory line", function()
  SIM.tooltipUnit = "party2"
  GameTooltip._lines = {}
  for _, call in ipairs(SIM.tooltipPostCalls) do
    call.fn(GameTooltip)
  end
  ok(#GameTooltip._lines >= 2, "lines added")
  ok(contains(GameTooltip._lines[1], L.TONE_BAD) or contains(GameTooltip._lines[1], L.TONE_MIXED), GameTooltip._lines[1])
end)

test("group finder row gets a badge for a remembered leader", function()
  ok(SIM.hooks.LFGBrowseSearchEntry_Update, "hooked")
  SIM.lfgResults = { [5] = { leaderName = "Zarn-Brasa", comment = "HR Varita del Sol" } }
  local row = SIM.newWidget("Button")
  row.resultID = 5
  row.Name = SIM.newWidget("FontString")
  SIM.hooks.LFGBrowseSearchEntry_Update(row)
  ok(row.SafeLootBadge and row.SafeLootBadge:IsShown(), "badge shown")
  -- the listing rules are remembered for when we join that leader
  ok(SL.Contract.listings and SL.Contract.listings["Zarn Brasa"], "listing remembered")
end)

test("group finder tooltip shows the memory card", function()
  local tip = SIM.newWidget("Frame")
  SIM.hooks.LFGBrowseSearchEntryTooltip_UpdateAndShow(tip, 5)
  ok(_G.SafeLootFinderCard:IsShown(), "card shown")
  tip:Hide()
  ok(not _G.SafeLootFinderCard:IsShown(), "card hides with the tooltip")
end)

test("invitation from a remembered player shows a notice", function()
  clearToasts()
  SIM.Fire("PARTY_INVITE_REQUEST", "Zarn-Brasa")
  ok(_G.SafeLootToast:IsShown(), "toast")
  ok(contains(_G.SafeLootToast.Title:GetText(), "Zarn Brasa"), "names the inviter")
end)

test("main window opens and every tab renders", function()
  SL.MainFrame:Open("contract")
  ok(_G.SafeLootMainFrame:IsShown(), "shown")
  ok(contains(SL.MainFrame.pages.contract.Status:GetText(), L.NEED_SHORT_msos), "contract summary (short: always one line)")
  SL.MainFrame:Open("journal")
  ok(#SL.MainFrame.pages.journal.List.provider.items > 1, "journal has lines")
  SL.MainFrame:Open("players")
  ok(#SL.MainFrame.pages.players.List.provider.items >= 2, "players listed")
  SL.MainFrame:Toggle()
  ok(not _G.SafeLootMainFrame:IsShown(), "toggle closes")
end)

test("self-test stores a report and receives its own addon echo", function()
  SL:HandleSlash("test")
  local report = SafeLootDB.diagnostics.report
  ok(report and report.functions, "report saved")
  eq(report.me, "Ana Paciente")
  local ping = SIM.addonSent[#SIM.addonSent - 1]
  eq(ping.chatType, "WHISPER")
  eq(ping.target, "Ana Paciente")
  SIM.Fire("CHAT_MSG_ADDON", "SafeLoot", ping.message, "WHISPER", "Ana Paciente")
  ok(report.addonEcho and report.addonEcho.WHISPER, "echo recorded")
  ok(_G.SafeLootDiagnostics:IsShown(), "window shown")
  ok(SafeLootDB.diagnostics.observed.loot_method_event.count >= 5, "observations counted")
end)

test("Spanish command aliases work", function()
  _G.SafeLootAlarmPanel:Hide()
  SL:HandleSlash("alarma")
  ok(_G.SafeLootAlarmPanel:IsShown(), "demo alarm")
  SL:HandleSlash("resumen")
  ok(_G.SafeLootSummary:IsShown(), "demo summary")
end)

test("dying and running back as a ghost does NOT end the run", function()
  SIM.inInstance = false
  SIM.Fire("PLAYER_ENTERING_WORLD")
  ok(SL.Run:Current(), "run still going while outside")
  SIM.now = SIM.now + 120
  SIM.inInstance = true
  SIM.Fire("PLAYER_ENTERING_WORLD")
  ok(SL.Run:Current() and SL.Run:Current().outsideSince == nil, "back inside, same run")
  eq(#SafeLootDB.runs, 0, "nothing finished")
end)

test("leaving the instance for good ends the run and shows the summary", function()
  -- a switch to master loot DURING the run (the earlier ones happened before entering)
  SIM.lootMethod = 2
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  _G.SafeLootSummary:Hide()
  SIM.inInstance = false
  SIM.Fire("PLAYER_ENTERING_WORLD")
  SIM.now = SIM.now + 601
  settle()
  eq(SL.Run:Current(), nil)
  eq(#SafeLootDB.runs, 1)
  ok(_G.SafeLootSummary:IsShown(), "summary shown")
  ok(contains(_G.SafeLootSummary.Body:GetText(), L.SUMMARY_BROKEN), "says the rules changed")
  ok(not contains(_G.SafeLootSummary.text, "|T"), "copy text has no texture codes")
end)

test("settings are registered in Options > AddOns, language included", function()
  ok(SIM.settingsCategory, "category")
  ok(SIM.settingsRegistered.alarmSound, "alarmSound")
  ok(SIM.settingsRegistered.language, "language")
  eq(#SIM.languageOptions, 6, "auto + 5 languages")
end)

test("changing the language asks to reload", function()
  SafeLootDB.settings.language = "frFR"
  SIM.settingsRegistered.language.cb()
  ok(_G.SafeLootReload:IsShown(), "reload prompt")
end)


-- Audit 0.1.1 ---------------------------------------------------------------------------------------------------
test("untrusted chat text is cleaned before it is stored or re-sent", function()
  local c = SL.Rules.Parse("HR |cffff0000|Hitem:1|h[Daga|Tfake:0|t]|h|r", "Kr|cffffffffag")
  ok(c and c.reserves[1], "parsed")
  ok(not c.reserves[1].item:find("|", 1, true), "no escape left: " .. c.reserves[1].item)
  ok(not c.reserves[1].owner:find("|", 1, true), "owner cleaned")
  eq(SL.Rules.Clean("a|b||c"), "abc")
  eq(SL.Rules.Clean("   "), nil)
end)

test("chat lines are cut without breaking an accented letter", function()
  local text = string.rep("á", 200) -- 400 bytes
  local cut = SL.Rules.Truncate(text, 255, "...")
  ok(#cut <= 255, "fits")
  local body = cut:sub(1, #cut - 3)
  eq(#body % 2, 0, "only whole two-byte letters")
end)

test("sending to the group has a cooldown (no flooding)", function()
  SIM.now = SIM.now + 100
  local before = #SIM.sent
  SL.API.SendGroupChat("uno")
  SL.API.SendGroupChat("dos")
  eq(#SIM.sent, before + 1, "second click within 4 s is refused")
  SIM.now = SIM.now + 5
  SL.API.SendGroupChat("tres")
  eq(#SIM.sent, before + 2)
end)

test("'ok' only counts for 3 minutes after publishing", function()
  joinGroup()
  SIM.now = SIM.now + 10
  SL.Contract:Publish()
  SIM.now = SIM.now + 200
  SIM.Fire("CHAT_MSG_PARTY", "ok", "Lia-Sombra")
  eq(SL.Contract:Get().accepted["Lia Sombra"], nil, "too late")
end)

test("the same rules pasted twice are suggested once", function()
  clearToasts()
  SIM.now = SIM.now + 10
  SIM.Fire("CHAT_MSG_PARTY_LEADER", "SR Varita del Sol", "Krag-Hierro")
  ok(_G.SafeLootToast:IsShown(), "first suggestion")
  clearToasts()
  SIM.Fire("CHAT_MSG_PARTY_LEADER", "SR Varita del Sol", "Krag-Hierro")
  ok(not _G.SafeLootToast:IsShown(), "not repeated")
end)

test("toasts queue instead of replacing each other", function()
  clearToasts()
  SL.Alert:Toast({ tone = "bad", title = "uno", body = "" })
  SL.Alert:Toast({ tone = "bad", title = "dos", body = "" })
  eq(_G.SafeLootToast.Title:GetText(), "uno")
  _G.SafeLootToast:Hide()
  eq(_G.SafeLootToast.Title:GetText(), "dos", "next one after the first hides")
  clearToasts()
end)

test("a burst of roster updates is handled once (debounce)", function()
  local calls = 0
  local original = SL.API.GroupMembers
  SL.API.GroupMembers = function() calls = calls + 1; return original() end
  for _ = 1, 30 do
    SIM.Fire("GROUP_ROSTER_UPDATE")
  end
  settle()
  SL.API.GroupMembers = original
  ok(calls <= 3, "30 updates -> " .. calls .. " roster reads")
end)

test("agreed rules survive a /reload in the same group", function()
  joinGroup()
  SL.Contract:Adopt({ needRule = "greed" }, "copied")
  local saved = SafeLootCharDB.contract
  ok(saved and saved.contract.needRule == "greed", "saved per character")
  SL.Contract.current = nil
  ok(SL.Contract:Restore(), "restored")
  eq(SL.Contract:Get().needRule, "greed")
end)

test("joining a group that already uses master loot shows the information", function()
  SIM.inGroup = false
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
  clearToasts()
  -- join a group whose leader already set master loot (joinGroup() would set group loot)
  SIM.inGroup, SIM.groupSize, SIM.leaderUnit = true, 4, "party1"
  SIM.lootMethod, SIM.masterPartyID = 2, 1
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
  ok(_G.SafeLootToast:IsShown(), "toast")
  -- it may wait in the queue behind "Krag joined your group" (Krag is remembered): both are shown, in turn
  local found = _G.SafeLootToast.Title:GetText() == SL.L.JOIN_ML_TITLE
  for _, queued in ipairs(SL.Alert.queue or {}) do
    if queued.title == SL.L.JOIN_ML_TITLE then
      found = true
    end
  end
  ok(found, "master loot information shown or queued")
end)

test("a roll whose class the game hides (secret) is skipped without errors", function()
  clearToasts()
  local hidden = {}
  SIM.secrets[hidden] = true
  SIM.lootDrops["12:1"] = {
    itemHyperlink = MAIL,
    rollInfos = { { playerName = "Otro-Jugador", playerClass = hidden, isSelf = false, state = 0 } },
    winner = { playerName = "Otro-Jugador", playerClass = hidden },
  }
  SIM.inInstance = true
  SIM.Fire("PLAYER_ENTERING_WORLD")
  SIM.Fire("LOOT_HISTORY_UPDATE_DROP", 12, 1)
  ok(not _G.SafeLootToast:IsShown(), "no mark from hidden data")
  local drop = SL.Run:Current() and SL.Run:Current().drops["12:1"]
  ok(drop and drop.class == nil, "secret class not stored")
end)

test("player tooltips stay cheap: context is sampled", function()
  local before = SafeLootDB.diagnostics.observed.unit_tooltip and SafeLootDB.diagnostics.observed.unit_tooltip.count or 0
  SIM.tooltipUnit = "party2"
  for _ = 1, 100 do
    for _, call in ipairs(SIM.tooltipPostCalls) do
      call.fn(GameTooltip)
    end
  end
  local entry = SafeLootDB.diagnostics.observed.unit_tooltip
  eq(entry.count, before + 100, "every tooltip counted")
  ok((entry.inInstance or 0) + (entry.outside or 0) < 60, "but context taken only sometimes")
end)
