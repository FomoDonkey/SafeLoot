-- 0.5.0: the address book, recognising players in the world, and movable windows.
local SL = NS
local L = SL.L
local M, PL, PT = SL.Memory, SL.Players, SL.PlayersTab
_G.SafeLootWelcome:Hide()

local function settle()
  for _ = 1, 8 do
    if #SIM.timers == 0 then return end
    SIM.RunTimers()
  end
end
local function clearToasts()
  SL.Alert.queue = {}
  _G.SafeLootToast:Hide()
end
local DAY = 86400
local db = SafeLootDB.players
local function add(name, kind, daysAgo, extra)
  local e = { kind = kind, t = SIM.now - (daysAgo or 0) * DAY }
  for k, v in pairs(extra or {}) do e[k] = v end
  M.Add(db, name, e)
end
local function page() return SL.MainFrame.pages.players end
local function names()
  local out = {}
  for _, item in ipairs(page().List.provider.items) do out[#out + 1] = item.name end
  return table.concat(out, ",")
end

add("Nina Ladrona", "tag_ninja", 3)
add("Vara Vendedora", "tag_extortion", 2)
add("Quico Huido", "tag_quitter", 5)
add("Tito Fiel", "tag_trusted", 400)
add("Dudo Dudoso", "need_impossible", 1, { item = "Ironfoe", class = "MAGE" })
add("Nota Sola", "note", 200, { note = "buen sanador" })
for _ = 1, 4 do add("Visto Antes", "grouped", 10) end
add("Viejo Aviso", "need_impossible", 120)
add("Viejo Aviso", "grouped", 1)

-- Categories --------------------------------------------------------------------------------------------------------
test("one clear category per player", function()
  local function cat(n) return M.Category(db[n], SIM.now, 90) end
  eq(cat("Nina Ladrona"), "ninja")
  eq(cat("Vara Vendedora"), "extortion")
  eq(cat("Quico Huido"), "quitter")
  eq(cat("Tito Fiel"), "trusted", "marks never expire")
  eq(cat("Dudo Dudoso"), "warned")
  eq(cat("Nota Sola"), "noted")
  eq(cat("Visto Antes"), "seen")
  eq(cat("Viejo Aviso"), "seen", "old automatic alerts do")
end)

test("your opinion wins over what the addon saw, but the tooltip says both", function()
  add("Tito Fiel", "need_impossible", 1, { item = "Ironfoe" })
  eq(M.Category(db["Tito Fiel"], SIM.now, 90), "trusted")
  local lines = table.concat(SL.MemoryHooks:TooltipLines("Tito Fiel"), "\n")
  ok(contains(lines, M.Upper(L.CAT_TRUSTED)), "trusted")
  ok(contains(lines, L.LABEL_WARNED), "and the alert")
end)

test("a mark is never pushed out by many notes or alerts", function()
  for i = 1, 40 do add("Nina Ladrona", i % 2 == 0 and "note" or "need_doubtful", 0, { note = "n" .. i }) end
  eq(#db["Nina Ladrona"].events, M.MAX_EVENTS)
  eq(M.ActiveTag(db["Nina Ladrona"]), "tag_ninja")
end)

test("with the memory full, players with your marks are the last to go", function()
  local many = {}
  M.Add(many, "Marca Vieja", { kind = "tag_ninja", t = SIM.now - 80 * DAY })
  for i = 1, 20 do M.Add(many, "Uno N" .. string.char(64 + i), { kind = "grouped", t = SIM.now }) end
  M.Prune(many, SIM.now, 90, 10)
  ok(many["Marca Vieja"], "kept")
end)

test("capital letters respect accents", function()
  eq(M.Upper("Vende botín"), "VENDE BOTÍN")
  eq(M.Upper("Verkauft größer"), "VERKAUFT GRÖßER")
end)

-- The tab ---------------------------------------------------------------------------------------------------------------
test("sidebar: every category with its number; a click filters", function()
  SL.MainFrame:Open("players")
  local side = page().side
  ok(contains(side.ninja.Count:GetText(), "1"), side.ninja.Count:GetText())
  ok(contains(side.all.Count:GetText(), "8"), side.all.Count:GetText())
  side.ninja:Click()
  eq(names(), "Nina Ladrona")
  ok(side.ninja.Lit:IsShown() and not side.all.Lit:IsShown(), "lit")
  side.trusted:Click()
  eq(names(), "Tito Fiel")
  side.warned:Click()
  eq(names(), "Dudo Dudoso")
  side.group:Click()
  eq(#page().List.provider.items, 0)
  ok(contains(page().Empty:GetText(), L.CAT_EMPTY), "says it is empty")
  side.all:Click()
  eq(#page().List.provider.items, 8)
end)

test("searching looks everywhere, whatever the category", function()
  page().side.ninja:Click()
  page().Search:SetText("tito")
  page().Search:Fire("OnTextChanged")
  eq(names(), "Tito Fiel")
  page().Search:SetText("zzz")
  page().Search:Fire("OnTextChanged")
  ok(contains(page().Empty:GetText(), L.PLAYERS_NO_MATCH))
  page().side.all:Click()
  eq(page().Search:GetText(), "", "a category click clears the search")
end)

test("order: recent, A-Z, most runs; remembered", function()
  eq(page().Sort:GetText(), L.SORT_RECENT)
  page().Sort:Click()
  eq(SafeLootDB.settings.playerSort, "name")
  eq(names():match("^[^,]+"), "Dudo Dudoso")
  page().Sort:Click()
  eq(names():match("^[^,]+"), "Visto Antes", "4 runs together")
  page().Sort:Click()
  eq(SafeLootDB.settings.playerSort, "recent")
  SafeLootDB.settings.playerSort = "nonsense"
  SL.MainFrame:Refresh()
  eq(page().Sort:GetText(), L.SORT_RECENT, "a damaged setting does not break it")
  SafeLootDB.settings.playerSort = "recent"
end)

test("rows draw for every player, with icon and word, not only colour", function()
  for _, data in ipairs(page().List.provider.items) do
    local row = SIM.newWidget("Button")
    page().List.view.init(row, data)
    ok(contains(row.Text:GetText(), data.name), data.name)
    if data.category ~= "seen" then
      ok(contains(row.Tag:GetText(), "|T") and contains(row.Tag:GetText(), L["LABEL_" .. data.category:upper()] or L["CAT_" .. data.category:upper()]), data.category)
    end
    ok(#row.Sub:GetText() > 10, "second line")
  end
end)

test("card: badge, opinion lit, notes removed one by one", function()
  page().side.all:Click()
  page().selected = "Dudo Dudoso"
  SL.MainFrame:Refresh()
  ok(contains(page().Badge:GetText(), M.Upper(L.LABEL_WARNED)))
  page().tagButtons[2]:Click()
  eq(M.ActiveTag(db["Dudo Dudoso"]), "tag_ninja")
  ok(contains(page().Badge:GetText(), M.Upper(L.CAT_NINJA)))
  local items = page().Notes.provider.items
  eq(#items, 2)
  local row = SIM.newWidget("Button")
  page().Notes.view.init(row, items[2]) -- the automatic alert
  row.Remove:Click()
  eq(#db["Dudo Dudoso"].events, 1)
  eq(M.ActiveTag(db["Dudo Dudoso"]), "tag_ninja", "only that one")
  row.Remove:Click() -- the same stale row again
  eq(#db["Dudo Dudoso"].events, 1, "a stale click removes nothing else")
end)

test("'Forget' asks twice", function()
  page().selected = "Visto Antes"
  SL.MainFrame:Refresh()
  page().Forget:Click()
  ok(db["Visto Antes"], "not yet")
  eq(page().Forget:GetText(), L.FORGET_SURE)
  page().selected = "Quico Huido"
  SL.MainFrame:Refresh()
  eq(page().Forget:GetText(), L.FORGET, "changing player disarms it")
  page().Forget:Click()
  ok(db["Quico Huido"], "asks again for the other one")
  page().selected = "Visto Antes"
  SL.MainFrame:Refresh()
  page().Forget:Click()
  page().Forget:Click()
  eq(db["Visto Antes"], nil, "gone after the second click")
  settle()
end)

test("right click on a row gives the same menu", function()
  local row = SIM.newWidget("Button")
  for _, data in ipairs(page().List.provider.items) do
    if data.name == "Nina Ladrona" then page().List.view.init(row, data) end
  end
  SIM.lastMenu = nil
  row:GetScript("OnClick")(row, "RightButton")
  eq(SIM.lastMenu.title, "Nina Ladrona")
  eq(#SIM.lastMenu.entries, 5)
  ok(SIM.lastMenu.entries[2].radio(), "ninja is marked")
  SIM.lastMenu.entries[1].fn()
  eq(M.ActiveTag(db["Nina Ladrona"]), "tag_trusted")
  SIM.lastMenu.entries[2].fn()
  eq(M.ActiveTag(db["Nina Ladrona"]), "tag_ninja")
end)

-- In the world ----------------------------------------------------------------------------------------------------------
test("right-click menu of the game: mark anyone, open the card", function()
  local hook = SIM.menuHooks["MENU_UNIT_PARTY"]
  ok(hook and SIM.menuHooks["MENU_UNIT_PLAYER"] and SIM.menuHooks["MENU_UNIT_FRIEND"] and SIM.menuHooks["MENU_UNIT_GUILD"], "hooked")
  SIM.units.party1 = { first = "Krag", second = "Hierro", class = "WARRIOR" }
  local root = SIM.menuRoot()
  hook(nil, root, { unit = "party1" })
  eq(#root.entries, 1)
  local sub = root.entries[1]
  eq(#sub.entries, 5)
  sub.entries[2].fn()
  eq(M.ActiveTag(db["Krag Hierro"]), "tag_ninja")
  root = SIM.menuRoot()
  hook(nil, root, { unit = "party1" })
  ok(contains(root.entries[1].text, L.CAT_NINJA), "the menu itself already says it")
  sub.entries[5].fn()
  eq(page().selected, "Krag Hierro")
end)

test("menu without unit (chat, friends): first name + surname; never for me, creatures or hidden names", function()
  eq(PL.MenuName({ name = "Zarn", surname = "Brasa" }), "Zarn Brasa")
  eq(PL.MenuName({ name = "Zarn Brasa", surname = "Brasa" }), "Zarn Brasa")
  eq(PL.MenuName({ unit = "player" }), nil, "me")
  eq(PL.MenuName({ unit = "target" }), nil, "a creature")
  eq(PL.MenuName({ name = "" }), nil)
  eq(PL.MenuName(nil), nil)
  SIM.secrets["Oculto"] = true
  eq(PL.MenuName({ name = "Oculto", surname = "X" }), nil, "hidden by the game")
  SIM.secrets["Oculto"] = nil
  SafeLootDB.settings.showUnitMenu = false
  local root = SIM.menuRoot()
  SIM.menuHooks["MENU_UNIT_PARTY"](nil, root, { unit = "party1" })
  eq(#root.entries, 0, "can be turned off")
  SafeLootDB.settings.showUnitMenu = true
end)

test("badge under the target's portrait: only for marked players", function()
  local badge = _G.SafeLootTargetBadge
  ok(badge and not badge:IsShown(), "hidden")
  SIM.units.target = SIM.units.party1
  SIM.Fire("PLAYER_TARGET_CHANGED")
  ok(badge:IsShown() and contains(badge.Text:GetText(), M.Upper(L.CAT_NINJA)), "NINJA")
  eq(badge._mouse, false, "never blocks a click")
  SIM.units.target = { first = "Otro", second = "Cualquiera", class = "MAGE" }
  SIM.Fire("PLAYER_TARGET_CHANGED")
  ok(not badge:IsShown(), "unknown player")
  SIM.units.target = SIM.units.party1
  SafeLootDB.settings.showTarget = false
  SL:Fire("SETTING_CHANGED", "showTarget", false)
  ok(not badge:IsShown(), "option")
  SafeLootDB.settings.showTarget = true
  SL:Fire("SETTING_CHANGED", "showTarget", true)
  ok(badge:IsShown())
  PL:Tag("Krag Hierro", "tag_ninja", true)
  ok(not badge:IsShown(), "unmarked: gone at once")
  PL:Tag("Krag Hierro", "tag_ninja", true)
  SIM.units.target = nil
  SIM.Fire("PLAYER_TARGET_CHANGED")
  ok(not badge:IsShown())
end)

test("a whisper from someone you marked badly: one notice, not a flood", function()
  clearToasts()
  SIM.now = SIM.now + 2000
  SIM.Fire("CHAT_MSG_WHISPER", "hola", "Krag-Hierro")
  ok(_G.SafeLootToast:IsShown() and contains(_G.SafeLootToast.Title:GetText(), "Krag Hierro"))
  ok(contains(_G.SafeLootToast.Title:GetText(), M.Upper(L.CAT_NINJA)))
  clearToasts()
  SIM.Fire("CHAT_MSG_WHISPER", "hola", "Krag-Hierro")
  ok(not _G.SafeLootToast:IsShown(), "not again for 15 minutes")
  SIM.Fire("CHAT_MSG_WHISPER", "hola", "Tito-Fiel")
  ok(not _G.SafeLootToast:IsShown(), "not for trusted players")
  SIM.Fire("CHAT_MSG_WHISPER", "hola", "Nadie-Nuevo")
  ok(not _G.SafeLootToast:IsShown(), "not for strangers")
end)

test("someone marked who joins or invites you: the word comes first", function()
  clearToasts()
  SIM.inGroup, SIM.groupSize, SIM.leaderUnit = true, 2, "party1"
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
  ok(contains(_G.SafeLootToast.Title:GetText() or "", M.Upper(L.CAT_NINJA)), _G.SafeLootToast.Title:GetText())
  SL.MainFrame:Open("players")
  eq(page().List.provider.items[1].name, "Krag Hierro", "your group first")
  ok(contains(page().side.group.Count:GetText(), "1"))
end)

test("memory off: nothing is shown anywhere", function()
  SafeLootDB.settings.memory = false
  eq(PL:Category("Krag Hierro"), nil)
  eq(SL.MemoryHooks:TooltipLines("Krag Hierro"), nil)
  local root = SIM.menuRoot()
  SIM.menuHooks["MENU_UNIT_PARTY"](nil, root, { unit = "party1" })
  eq(#root.entries, 0)
  SafeLootDB.settings.memory = true
end)

-- Windows --------------------------------------------------------------------------------------------------------------
test("BUG: the main window could not be moved. Every window takes the mouse, drags and remembers its place", function()
  SL.MainFrame:Open("contract")
  SL.LootPicker:Open(nil)
  SL.SettingsPanel:DemoSummary()
  for _, name in ipairs({ "SafeLootMainFrame", "SafeLootLootPicker", "SafeLootSummary", "SafeLootToast", "SafeLootAlarmPanel", "SafeLootIndicator", "SafeLootWelcome" }) do
    local f = _G[name]
    ok(f._mouse, name .. " takes the mouse")
    ok(f._movable and f._drag == "LeftButton", name .. " can be dragged")
    ok(f:GetScript("OnDragStart") and f:GetScript("OnDragStop"), name)
  end
  local f = _G.SafeLootMainFrame
  f.GetPoint = function() return "TOPLEFT", nil, "TOPLEFT", 120, -80 end
  f:Fire("OnDragStart")
  f:Fire("OnDragStop")
  eq(SafeLootCharDB.positions.main[3], 120)
  f:RestorePosition()
  eq(f._points[#f._points][4], 120, "comes back there")
  SL:HandleSlash("reset")
  eq(next(SafeLootCharDB.positions), nil)
  eq(f._points[#f._points][1], "CENTER", "/safeloot reset")
  _G.SafeLootSummary:Hide()
  eq(#(SafeLootDB.errors or {}), 0)
end)
