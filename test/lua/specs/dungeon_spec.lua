-- Test recording (`/gg test on`): a party in a 5-man dungeon is recorded like a raid, and exported as a test, only while the
-- setting is on (test/lua/fixtures/dungeon.lua; test/dungeon.test.mjs reads the export with the reference validator).

WOW.dofile("test/lua/fixtures/dungeon.lua")

local function chatHas(chat, pattern)
  for _, line in ipairs(chat) do
    if line:find(pattern) then return line end
  end
  return nil
end

T.test("with test recording off, a dungeon is not recorded, there is nothing to export, and combat logging is left alone", function()
  local r = DUNGEON.run(false)
  T.eq(#r.raids, 0)
  T.eq(r.made, false)
  T.eq(r.why, "nothing")
  T.eq(r.outbox, 0)
  T.same(r.logging, {})
  T.eq(chatHas(r.chat, "TEST RECORDING"), nil)
end)

T.test("with it on, the dungeon is recorded as a raid is, marked as a test, and exported", function()
  local r = DUNGEON.run(true)
  T.eq(r.testSetting, true)
  T.eq(#r.raids, 1)
  T.eq(r.raids[1].zone, 801)
  T.eq(r.raids[1].size, 5)
  T.eq(r.raids[1].test, true)
  T.eq(r.raids[1].whys, "zonein,pull,wipe,pull,kill,leave")
  T.eq(r.made, true)
  T.eq(r.outbox, 1)
  local out = GuildGolem.Codec.read(r.export[1], "site")
  T.eq(out.attendance[1].test, true)
  T.eq(out.attendance[1].size, 5)
  T.eq(out.attendance[1].snapshots[3].members[4].online, false)
  T.same(r.logging, { true }, "combat logging is turned on at the dungeon's zone-in too")
end)

T.test("the status and the window say plainly that test recording is on", function()
  local r = DUNGEON.run(true)
  T.truthy(chatHas(r.chat, "TEST RECORDING IS ON: a party in a 5%-man dungeon is now recorded like a raid"))
  T.truthy(chatHas(r.chat, "TEST RECORDING IS ON: a party in a 5%-man dungeon is recorded like a raid, and its export is marked"))
  WOW.slash("/gg")
  T.truthy(GuildGolem.UI.window().statusText():find("^TEST RECORDING IS ON"))
  WOW.slash("/gg test off")
  T.truthy(chatHas(WOW.chat, "Test recording is off"))
  T.eq(GuildGolem.UI.window().statusText():find("TEST"), nil)
  WOW.slash("/gg test")
  T.truthy(chatHas(WOW.chat, "Test recording is off%."))
end)

T.test("a real raid under the setting is not marked, and turning the setting off in a dungeon ends the recording", function()
  local ns
  WOW.declareSavedVariables("GuildGolemDB")
  ns = WOW.loadAddon("GuildGolem")
  WOW.login()
  WOW.slash("/gg test on")
  WOW.setRoster({ { name = "Kael Ashgrove", class = "WARRIOR" } }, "raid")
  WOW.setInstance({ name = "Ember Vault", type = "raid", difficultyID = 9, maxPlayers = 40, instanceID = 5011 })
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  T.eq(GuildGolemDB.raids[1].test, nil)
  WOW.setInstance({ name = "Cinder Hollow", type = "party", difficultyID = 1, maxPlayers = 5, instanceID = 801 })
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  T.eq(#GuildGolemDB.raids, 2)
  T.eq(GuildGolemDB.raids[2].test, true)
  WOW.slash("/gg test off")
  WOW.fire("GROUP_ROSTER_UPDATE")
  T.eq(GuildGolemDB.raids[2].closed, true)
  T.eq(GuildGolemDB.raids[2].snapshots[#GuildGolemDB.raids[2].snapshots].why, "leave")
  T.truthy(ns.Attendance)
end)

T.test("the setting survives a logout, and is off by default", function()
  local ns
  WOW.declareSavedVariables("GuildGolemDB")
  ns = WOW.loadAddon("GuildGolem")
  WOW.login()
  T.eq(ns.Store.setting("testDungeons", false), false)
  WOW.slash("/gg test on")
  local saved = WOW.logout()
  T.eq(saved.GuildGolemDB.settings.testDungeons, true)
end)
