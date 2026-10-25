-- A scripted run of a 5-man dungeon through the stubs, for test/lua/specs/dungeon_spec.lua and test/dungeon.test.mjs: five
-- players in a party, a wipe and a kill, out again, then the export. DUNGEON.run(testOn) plays it with the addon's test
-- recording (`/gg test on`) on or off and returns what happened as plain data. Every name and id is made up.
--
-- Minutes from the start: 0 the party forms outside; 1 it enters Cinder Hollow (801); 6 boss 9001 pulled, 9 wipe (one
-- player disconnects), 13 pulled again, 17 killed; 21 out of the dungeon.

DUNGEON = {}

local PLAYERS = {
  { "Rhona Tester", "MAGE" }, { "Kael Ashgrove", "WARRIOR" }, { "Mira Stonebrook", "PRIEST" },
  { "Fenn Ashdown", "ROGUE" }, { "Sable Ironmere", "HUNTER" },
}

function DUNGEON.run(testOn)
  WOW.reset()
  WOW.declareSavedVariables("GuildGolemDB")
  local ns = WOW.loadAddon("GuildGolem")
  WOW.login()
  WOW.setGuild({ name = "Ashen Wardens", rank = "Officer" })
  if testOn then WOW.slash("/gg test on") end

  local offline
  local function publish()
    local list = {}
    for i, p in ipairs(PLAYERS) do
      list[i] = {
        name = p[1], class = p[2], online = i ~= offline,
        guid = i == 1 and WOW.player.guid or string.format("Player-9101-%08X", 0x0F000000 + i),
      }
    end
    WOW.setRoster(list, "party")
    WOW.fire("GROUP_ROSTER_UPDATE")
  end
  local minute = 0
  local function at(m)
    WOW.advance((m - minute) * 60)
    minute = m
  end

  publish()
  at(1)
  WOW.setInstance({ name = "Cinder Hollow", type = "party", difficultyID = 1, difficultyName = "Normal", maxPlayers = 5, instanceID = 801, instanceGroupSize = 5 })
  publish()
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  at(6); WOW.fire("ENCOUNTER_START", 9001, "Boss 9001", 1, 5)
  at(9)
  offline = 4
  publish()
  WOW.fire("ENCOUNTER_END", 9001, "Boss 9001", 1, 5, 0)
  at(13)
  offline = nil
  publish()
  WOW.fire("ENCOUNTER_START", 9001, "Boss 9001", 1, 5)
  at(17); WOW.fire("ENCOUNTER_END", 9001, "Boss 9001", 1, 5, 1)
  at(21)
  WOW.setInstance()
  publish()
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)

  local raids = {}
  for k, raid in ipairs(GuildGolemDB.raids or {}) do
    local whys = {}
    for i, s in ipairs(raid.snapshots) do whys[i] = s.why end
    raids[k] = { id = raid.id, zone = raid.zone, size = raid.size, test = raid.test == true, whys = table.concat(whys, ",") }
  end
  local result, why = ns.Export.make()
  local export = {}
  for i, entry in ipairs(result and result.entries or {}) do export[i] = entry.text end
  WOW.slash("/gg status")
  return {
    raids = raids, made = result ~= nil, why = why, export = export,
    logging = WOW.loggingCalls, chat = WOW.chat, outbox = #GuildGolemDB.outbox,
    testSetting = GuildGolemDB.settings.testDungeons,
  }
end
