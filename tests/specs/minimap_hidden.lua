-- 0.4.1: a saved "hidden" choice is respected, and a damaged angle does not break anything.
local SL = NS
test("hidden stays hidden after a restart; a broken angle is reset", function()
  eq(_G.SafeLootMinimapButton, nil, "not even created")
  eq(SafeLootDB.settings.minimapAngle, 182)
  SL:HandleSlash("minimap")
  ok(_G.SafeLootMinimapButton:IsShown(), "comes back")
end)
