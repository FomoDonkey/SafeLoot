-- 0.3.1: every bug found by the full audit after the first real test, each one reproduced as it happened.
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
  SIM.units.party3 = { first = "Lia", second = "Sombra", class = "ROGUE" }
  SIM.leaderUnit, SIM.lootMethod = "party1", 3
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
end

local function typeSearch(text)
  local page = SL.MainFrame.pages.players
  page.Search:SetText(text)
  page.Search:Fire("OnTextChanged")
end

_G.SafeLootWelcome:Hide()
joinGroup()

-- Links ------------------------------------------------------------------------------------------------------------
test("item links in lists, toasts, the alarm panel and the summary are clickable", function()
  SL.MainFrame:Open("journal")
  local view = SIM.lastView
  ok(view, "list view")
  local row = SIM.newWidget("Button")
  view.init(row, { text = "|cff0070dd|Hitem:9001::::|h[Coraza]|h|r" })
  local click = row:GetScript("OnHyperlinkClick")
  ok(click, "row handles link clicks")
  click(row, "item:9001::::", "[Coraza]", "LeftButton")
  eq(SIM.itemRefs[#SIM.itemRefs], "item:9001::::", "opened through the game's SetItemRef")
  ok(row:GetScript("OnHyperlinkEnter"), "row shows the item on hover")
  ok(_G.SafeLootToast:GetScript("OnHyperlinkClick"), "toast")
  ok(_G.SafeLootAlarmPanel:GetScript("OnHyperlinkClick"), "alarm panel")
  SL.SettingsPanel:DemoSummary()
  ok(_G.SafeLootSummary:GetScript("OnHyperlinkClick"), "summary")
  _G.SafeLootSummary:Hide()
end)

-- Players tab --------------------------------------------------------------------------------------------------
test("the people in your group are listed even with no notes, your group first", function()
  SL.MainFrame:Open("players")
  typeSearch("")
  local items = SL.MainFrame.pages.players.List.provider.items
  local names = {}
  for _, item in ipairs(items) do
    names[item.name] = item
  end
  ok(names["Krag Hierro"] and names["Krag Hierro"].inGroup, "Krag listed as in your group")
  ok(names["Zarn Brasa"] and names["Lia Sombra"], "everyone listed")
  ok(items[1].inGroup, "group first")
end)

test("BUG (real client): typing a new name after selecting someone tags the TYPED name", function()
  local page = SL.MainFrame.pages.players
  page.selected = "Krag Hierro" -- clicked in the list before
  typeSearch("Vex-Nuevo")
  page.tagButtons[2]:Click() -- Ninja
  ok(SL.Memory.Get(SafeLootDB.players, "Vex Nuevo"), "the typed player got the tag")
  local krag = SL.Memory.Get(SafeLootDB.players, "Krag Hierro")
  ok(not krag or SL.Memory.ActiveTag(krag) == nil, "the previously selected player was NOT tagged")
end)

test("one opinion per player: a new tag replaces the old one, the lit one again removes it", function()
  local page = SL.MainFrame.pages.players
  typeSearch("Vex Nuevo")
  eq(page.selected, "Vex Nuevo", "typing an existing name selects it")
  page.tagButtons[1]:Click() -- Trusted
  local rec = SL.Memory.Get(SafeLootDB.players, "Vex Nuevo")
  eq(SL.Memory.ActiveTag(rec), "tag_trusted")
  eq(SL.Memory.Summary(rec, SIM.now, 90).tone, "good", "not 'mixed'")
  page.tagButtons[1]:Click() -- Trusted again: removes it
  eq(SL.Memory.ActiveTag(rec), nil)
  page.tagButtons[2]:Click()
  page.tagButtons[2]:Click()
  page.tagButtons[2]:Click()
  local count = 0
  for _, event in ipairs(rec.events) do
    if event.kind == "tag_ninja" then
      count = count + 1
    end
  end
  eq(count, 1, "repeated clicks never pile up")
end)

test("a player with only a written note shows it in the list and in the tooltip", function()
  SL.Memory.Add(SafeLootDB.players, "Lia Sombra", { kind = "note", t = SIM.now, note = "Buena tanque" })
  typeSearch("")
  local items = SL.MainFrame.pages.players.List.provider.items
  local lia
  for _, item in ipairs(items) do
    if item.name == "Lia Sombra" then
      lia = item
    end
  end
  ok(lia and lia.summary.latestAny and lia.summary.latestAny.note == "Buena tanque", "note is the latest thing")
  local lines = SL.MemoryHooks:TooltipLines("Lia Sombra")
  ok(lines and contains(table.concat(lines, " "), "Buena tanque"), "tooltip shows the note")
end)

test("search ignores accents and case", function()
  SL.Memory.Add(SafeLootDB.players, "Peña Brava", { kind = "note", t = SIM.now, note = "x" })
  typeSearch("pena")
  local found = false
  for _, item in ipairs(SL.MainFrame.pages.players.List.provider.items) do
    if item.name == "Peña Brava" then
      found = true
    end
  end
  ok(found, "'pena' finds 'Peña Brava'")
  typeSearch("")
end)

-- Chat understanding --------------------------------------------------------------------------------------------
test("no false 'yes': 'ya voy' and 'va bien el pull' are not agreements", function()
  ok(not SL.Rules.IsAgreement("ya voy"), "ya voy")
  ok(not SL.Rules.IsAgreement("va bien el pull"), "va bien")
  ok(SL.Rules.IsAgreement("ok vamos"), "ok vamos")
  ok(SL.Rules.IsAgreement("sí claro"), "sí claro")
  ok(SL.Rules.IsAgreement("yap"), "yap alone")
end)

test("no false rules: 'res pls' is a resurrection, 'estoy libre' is not a loot rule", function()
  eq(SL.Rules.Parse("res pls"), nil)
  eq(SL.Rules.Parse("estoy libre ahora"), nil)
  eq(SL.Rules.Parse("tirada libre en todo").needRule, "free")
end)

-- Accepting a real change --------------------------------------------------------------------------------------
test("'Accept the change' makes the new method the agreed one (bar back to normal, need rule kept)", function()
  SL.Contract:Adopt({ needRule = "msos" }, "copied")
  SIM.lootMethod, SIM.masterPartyID = 2, 1
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  ok(contains(_G.SafeLootIndicator.Text:GetText(), L.IND_CHANGED), "red first")
  local accept = _G.SafeLootAlarmPanel.buttons[3]
  eq(accept:GetText(), L.ACTION_ACCEPT)
  accept:Click()
  local c = SL.Contract:Get()
  eq(c.method, 2, "master loot is now the agreed method")
  eq(c.needRule, "msos", "need rule kept")
  ok(not contains(_G.SafeLootIndicator.Text:GetText(), L.IND_CHANGED), "bar back to normal")
  SIM.lootMethod = 3
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
end)

test("'Use the game's rules' also clears the red bar", function()
  SL.Contract:Reset(SL.Rules.FromState({ method = 3, leader = "Krag Hierro" }, SIM.now))
  SIM.lootMethod = 0
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  ok(contains(_G.SafeLootIndicator.Text:GetText(), L.IND_CHANGED), "red")
  SL.Contract:Reset(SL.Rules.FromState(SL.API.LootState(), SIM.now))
  ok(not contains(_G.SafeLootIndicator.Text:GetText(), L.IND_CHANGED), "normal")
  SIM.lootMethod = 3
  SL.Contract:Reset(SL.Rules.FromState(SL.API.LootState(), SIM.now))
end)

test("'Save evidence' twice in a row writes one note", function()
  SL.Contract:Reset(SL.Rules.FromState({ method = 3, leader = "Krag Hierro" }, SIM.now))
  SIM.lootMethod = 2
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  local before = #(SL.Memory.Get(SafeLootDB.players, "Krag Hierro") or { events = {} }).events
  _G.SafeLootAlarmPanel.buttons[2]:Click()
  SIM.lootMethod = 3
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  SIM.lootMethod = 2
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  _G.SafeLootAlarmPanel.buttons[2]:Click()
  eq(#SL.Memory.Get(SafeLootDB.players, "Krag Hierro").events, before + 1)
  SIM.lootMethod = 3
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
end)

-- Contract drafts -------------------------------------------------------------------------------------------------
test("editing after publishing turns the rules into an unpublished draft (old 'ok' cleared)", function()
  SIM.now = SIM.now + 10
  SL.Contract:Publish()
  SIM.Fire("CHAT_MSG_PARTY", "ok", "Zarn-Brasa")
  ok(SL.Contract:Get().accepted["Zarn Brasa"], "agreed")
  SL.Contract:Edit(function(c) c.boe = "greed" end)
  local c = SL.Contract:Get()
  eq(c.publishedAt, nil, "not published any more")
  eq(next(c.accepted), nil, "old answers cleared")
  SL.MainFrame:Open("contract")
  ok(contains(SL.MainFrame.pages.contract.Source:GetText(), L.SOURCE_DRAFT), "says it is a draft")
end)

test("publishing during the anti-spam pause records nothing", function()
  SIM.now = SIM.now + 10
  SL.Contract:Publish()
  local at = SL.Contract:Get().publishedAt
  SL.Contract:Edit(function(c) c.boe = nil end)
  SL.Contract:Publish() -- within 4 s: refused
  eq(SL.Contract:Get().publishedAt, nil, "the refused publish is not recorded")
  ok(at, "the first one was")
end)

-- Journal, places, summary -------------------------------------------------------------------------------------
test("outside instances the place is the zone, not the continent", function()
  SIM.inInstance = false
  eq(SL.API.PlaceName(), "Ventormenta")
end)

test("people from a quiet group are remembered as 'seen' when the group ends", function()
  SL.Contract:Reset(SL.Rules.FromState(SL.API.LootState(), SIM.now))
  SIM.units.party4 = { first = "Tim", second = "Callado", class = "PRIEST" }
  SIM.groupSize = 5
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
  SIM.inGroup = false
  SIM.Fire("GROUP_LEFT")
  settle()
  local tim = SL.Memory.Get(SafeLootDB.players, "Tim Callado")
  ok(tim and (tim.seen or 0) >= 1, "seen counted even though nothing happened")
end)

test("an orange change says the rules changed in the summary (same threshold as the popup)", function()
  local run = { place = "X", startedAt = SIM.now, events = { { kind = "rules_changed", severity = 2, t = SIM.now, text = "x" } }, drops = {} }
  ok(SL.Run:HasIssues(run), "pops up")
  local lines = table.concat(SL.Run:SummaryLines(run), "\n")
  ok(contains(lines, L.SUMMARY_BROKEN), "and says so")
end)

test("toasts can be closed with their own button (the next queued one then shows)", function()
  clearToasts()
  SL.Alert:Toast({ tone = "bad", title = "first", body = "y" })
  SL.Alert:Toast({ tone = "warn", title = "second", body = "z" })
  ok(_G.SafeLootToast:IsShown(), "shown")
  eq(_G.SafeLootToast.Title:GetText(), "first")
  _G.SafeLootToast.Close:Click()
  eq(_G.SafeLootToast.Title:GetText(), "second", "closing shows the waiting one")
  _G.SafeLootToast.Close:Click()
  ok(not _G.SafeLootToast:IsShown(), "closed when nothing is waiting")
end)
