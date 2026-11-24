-- 0.4.1: the minimap button.
local SL = NS
local L = SL.L
local MB = SL.MinimapButton
local b = _G.SafeLootMinimapButton
_G.SafeLootWelcome:Hide()

local function settle()
  for _ = 1, 8 do
    if #SIM.timers == 0 then return end
    SIM.RunTimers()
  end
end
local function near(a, e, msg) ok(math.abs(a - e) < 0.6, (msg or "") .. " expected " .. e .. ", got " .. a) end

test("the button is there at login, on the edge of the minimap, with our own icon", function()
  ok(b and b:IsShown(), "shown")
  eq(b:GetParent(), Minimap)
  local p = b._points[1]
  eq(p[1], "CENTER")
  eq(p[2], Minimap)
  near(math.sqrt(p[4] ^ 2 + p[5] ^ 2), 109, "on the rim")
  ok(#b.Icon._points > 0, "icon anchored")
end)

test("left click opens and closes the window", function()
  b:Click()
  ok(_G.SafeLootMainFrame:IsShown(), "open")
  b:Click()
  ok(not _G.SafeLootMainFrame:IsShown(), "closed")
end)

test("right click gives the quick menu and every entry works", function()
  SIM.lastMenu = nil
  b:GetScript("OnClick")(b, "RightButton")
  local menu = SIM.lastMenu
  ok(menu and menu.title == L.ADDON_NAME, "menu")
  eq(#menu.entries, 7)
  menu.entries[3].fn()
  eq(SL.MainFrame.tab, "players")
  ok(_G.SafeLootMainFrame:IsShown())
  menu.entries[5].fn()
  ok(_G.SafeLootLootPicker:IsShown(), "loot by boss")
  menu.entries[6].fn()
  ok(SIM.openedSettings, "settings")
  _G.SafeLootMainFrame:Hide()
end)

test("dragging moves it around the edge, is remembered, and is not a click", function()
  b:Fire("OnDragStart")
  SIM.cursorX, SIM.cursorY = 1000, 900 -- straight above
  b:GetScript("OnUpdate")(b)
  eq(SafeLootDB.settings.minimapAngle, 90)
  near(b._points[1][5], 109, "top")
  SIM.cursorX, SIM.cursorY = 700, 600 -- left
  b:GetScript("OnUpdate")(b)
  eq(SafeLootDB.settings.minimapAngle, 180)
  SIM.cursorX, SIM.cursorY = 1000, 300 -- below: angles never go negative
  b:GetScript("OnUpdate")(b)
  eq(SafeLootDB.settings.minimapAngle, 270)
  b:Fire("OnDragStop")
  eq(b:GetScript("OnUpdate"), nil, "nothing runs every frame afterwards")
  b:Click()
  ok(not _G.SafeLootMainFrame:IsShown(), "the release of the drag does not open the window")
  settle()
  b:Click()
  ok(_G.SafeLootMainFrame:IsShown(), "the next click does")
  b:Click()
end)

test("square minimaps: it stays on the edge at every angle; round ones keep the circle", function()
  for angle = 0, 350, 10 do
    local x, y = MB.Offset(angle, 198, 198, "SQUARE")
    ok(math.abs(x) <= 109.01 and math.abs(y) <= 109.01, "inside the square")
    ok(math.max(math.abs(x), math.abs(y)) > 100, "on its edge: " .. angle)
    local rx, ry = MB.Offset(angle, 198, 198, "ROUND")
    near(math.sqrt(rx * rx + ry * ry), 109, "circle")
    local ux, uy = MB.Offset(angle, 198, 198, "SOMETHING-NEW")
    near(ux, rx)
    near(uy, ry)
  end
end)

test("it warns while the rules are not the agreed ones, and stops when they are", function()
  SIM.inGroup, SIM.groupSize = true, 3
  SIM.units.party1 = { first = "Krag", second = "Hierro", class = "WARRIOR" }
  SIM.units.party2 = { first = "Zarn", second = "Brasa", class = "MAGE" }
  SIM.leaderUnit, SIM.lootMethod = "party1", 3
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
  ok(not b.Alert:IsShown(), "calm")
  SIM.lootMethod, SIM.masterPartyID = 2, 1
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  ok(b.Alert:IsShown(), "warns")
  GameTooltip._lines = {}
  b:Fire("OnEnter")
  ok(contains(table.concat(GameTooltip._lines, "\n"), L.IND_CHANGED), "and says so")
  SL.Contract:AcceptGameState()
  ok(not b.Alert:IsShown(), "accepted: calm again")
  SIM.lootMethod = 3
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  SIM.lootMethod = 0
  SIM.Fire("PARTY_LOOT_METHOD_CHANGED")
  ok(b.Alert:IsShown())
  SIM.inGroup = false
  SIM.Fire("GROUP_ROSTER_UPDATE")
  settle()
  ok(not b.Alert:IsShown(), "no warning outside a group")
end)

test("it can be hidden and brought back: menu, command and settings", function()
  b:GetScript("OnClick")(b, "RightButton")
  SIM.lastMenu.entries[7].fn()
  ok(not b:IsShown(), "hidden from its menu")
  ok(contains(SIM.chatOutput[#SIM.chatOutput], "minimap"), "says how to get it back")
  SL:HandleSlash("minimapa")
  ok(b:IsShown(), "command")
  SafeLootDB.settings.showMinimap = false
  SL:Fire("SETTING_CHANGED", "showMinimap", false)
  ok(not b:IsShown(), "settings")
  SafeLootDB.settings.showMinimap = true
  SL:Fire("SETTING_CHANGED", "showMinimap", true)
  ok(b:IsShown())
  ok(SIM.settingsRegistered.showMinimap, "in the settings panel")
end)
