-- English client but the player chose German in the settings (saved before login).
local SL = NS
test("saved language wins over the client language", function()
  eq(SL.language, "deDE")
  eq(SL.L.ALARM_ML_TITLE, "Der Anführer hat auf PLÜNDERMEISTER umgestellt!")
  eq(SL.L.TAB_PLAYERS, "Spieler")
end)
test("existing saved settings are kept and missing ones filled", function()
  eq(SafeLootDB.settings.language, "deDE")
  eq(SafeLootDB.settings.alarmSound, true)
  eq(SafeLootDB.schema, 1)
end)
