-- Attendance.lua: the roster snapshots of a raid, each trigger in turn (zone-in, pull, kill, wipe, interval, leave), what a
-- raid entry holds, the choices the contract leaves to the core, and combat logging at zone-in.

local FIRST = { "Tolvar", "Mirel", "Quill", "Sable", "Kestrel", "Brannoch", "Ysolde", "Fenwick", "Orla", "Dunstan" }
local LAST = { "Ashgrove", "Dawnwhisper", "Brightwater", "Ironmere" }
local CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "HUNTER", "SHAMAN", "WARLOCK", "DRUID" }

local function guid(i) return string.format("Player-9101-%08X", 0x0F000000 + i) end

-- `n` players, the first the recorder (Rhona Tester, the raid leader), in the Ember Vault or elsewhere.
local function roster(n, zone)
  local list = { { name = "Rhona Tester", class = "MAGE", guid = WOW.player.guid, rank = 2, subgroup = 1, zone = zone } }
  for i = 2, n do
    list[i] = {
      name = FIRST[(i - 1) % 10 + 1] .. " " .. LAST[math.floor((i - 1) / 10) + 1],
      class = CLASSES[i % 8 + 1],
      guid = guid(i),
      subgroup = math.floor((i - 1) / 5) + 1,
      zone = zone,
    }
  end
  return list
end

local function enterVault()
  WOW.setInstance({ name = "Ember Vault", type = "raid", difficultyID = 9, maxPlayers = 40, instanceID = 5011, instanceGroupSize = 40 })
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
end

local function leaveVault()
  WOW.setInstance()
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
end

local function start()
  WOW.declareSavedVariables("GuildGolemDB")
  local ns = WOW.loadAddon("GuildGolem")
  WOW.login()
  return ns
end

local function raids() return GuildGolemDB.raids or {} end

local function whys(raid)
  local out = {}
  for i, s in ipairs(raid.snapshots) do out[i] = s.why end
  return out
end

local function member(snap, name)
  for _, m in ipairs(snap.members) do
    if m.name == name then return m end
  end
end

T.test("zone-in to a raid instance in a group records a snapshot of the raid and a raid entry", function()
  local ns = start()
  WOW.setRoster(roster(10, "Ember Vault"))
  WOW.setGuild({ name = "Ashen Wardens" })
  enterVault()
  T.eq(#raids(), 1)
  local raid = raids()[1]
  local at = GetServerTime() * 1000
  T.eq(raid.id, WOW.player.guid .. ":5011:" .. string.format("%.0f", GetServerTime()))
  T.eq(raid.zone, 5011)
  T.eq(raid.name, "Ember Vault")
  T.eq(raid.difficulty, 9)
  T.eq(raid.size, 40)
  T.eq(raid.leader, WOW.player.guid)
  T.eq(raid.night, nil)
  T.eq(raid.closed, nil)
  T.same(whys(raid), { "zonein" })
  local snap = raid.snapshots[1]
  T.eq(snap.at, at)
  T.eq(snap.encounter, nil)
  T.eq(#snap.members, 10)
  T.same(snap.members[1], { guid = WOW.player.guid, name = "Rhona Tester", cls = "mage", grp = 1, online = true, zone = "Ember Vault" })
  T.same(snap.members[2], { guid = guid(2), name = "Mirel Ashgrove", cls = "mage", grp = 1, online = true, zone = "Ember Vault" })
  T.truthy(ns.Attendance.current() == raid)
  T.eq(ns.Attendance.state().recording, true)
end)

T.test("a member who is not in the instance yet shows the zone he is in, and an offline one has none", function()
  start()
  local list = roster(6, "Ember Vault")
  list[3].zone = "Hearthfire Square"
  list[4].online = false
  WOW.setRoster(list)
  enterVault()
  local snap = raids()[1].snapshots[1]
  T.eq(snap.members[3].zone, "Hearthfire Square")
  T.eq(snap.members[3].online, true)
  T.eq(snap.members[4].online, false)
  T.eq(snap.members[4].zone, nil)
end)

T.test("nothing is recorded in the open world, in a dungeon, or in a raid instance with no group", function()
  local ns = start()
  WOW.setRoster(roster(10))
  WOW.fire("GROUP_ROSTER_UPDATE")
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  WOW.setInstance({ name = "Cinder Hollow", type = "party", difficultyID = 1, maxPlayers = 5, instanceID = 801 })
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  T.eq(#raids(), 0)
  WOW.setRoster()
  enterVault()
  T.eq(#raids(), 0)
  T.eq(ns.Attendance.state().recording, false)
end)

T.test("a group formed after the player is already inside starts the recording", function()
  start()
  enterVault()
  T.eq(#raids(), 0)
  WOW.setRoster(roster(5, "Ember Vault"))
  WOW.fire("GROUP_ROSTER_UPDATE")
  T.eq(#raids(), 1)
  T.same(whys(raids()[1]), { "zonein" })
end)

T.test("a pull, a wipe and a kill each take a snapshot with the encounter's id", function()
  start()
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  WOW.advance(60)
  WOW.fire("ENCOUNTER_START", 1101, "Warden of Cinders", 9, 40)
  WOW.advance(120)
  WOW.fire("ENCOUNTER_END", 1101, "Warden of Cinders", 9, 40, 0)
  WOW.advance(60)
  WOW.fire("ENCOUNTER_START", 1101, "Warden of Cinders", 9, 40)
  WOW.advance(100)
  WOW.fire("ENCOUNTER_END", 1101, "Warden of Cinders", 9, 40, 1)
  local raid = raids()[1]
  T.same(whys(raid), { "zonein", "pull", "wipe", "pull", "kill" })
  T.eq(raid.snapshots[2].encounter, 1101)
  T.eq(raid.snapshots[3].encounter, 1101)
  T.eq(raid.snapshots[5].encounter, 1101)
  T.eq(raid.snapshots[2].at - raid.snapshots[1].at, 60000)
  T.eq(raid.snapshots[3].at - raid.snapshots[2].at, 120000)
  T.eq(raid.snapshots[5].at - raid.snapshots[4].at, 100000)
end)

T.test("an encounter with no id in the event is an interval snapshot, since the contract needs an id for a pull", function()
  start()
  WOW.setRoster(roster(5, "Ember Vault"))
  enterVault()
  WOW.advance(10)
  local list = roster(5, "Ember Vault")
  list[2].online = false
  WOW.setRoster(list)
  WOW.fire("ENCOUNTER_START", nil, "Unknown", 9, 40)
  T.eq(raids()[1].snapshots[2].why, "interval")
  T.eq(raids()[1].snapshots[2].encounter, nil)
end)

T.test("an interval snapshot is taken every five minutes, and one that repeats the one before is not kept", function()
  start()
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  WOW.advance(300)
  T.eq(#raids()[1].snapshots, 1, "nothing changed")
  WOW.advance(300)
  T.eq(#raids()[1].snapshots, 1, "still nothing")
  -- Someone disconnects: the next interval shows it.
  local list = roster(10, "Ember Vault")
  list[5].online = false
  WOW.setRoster(list)
  WOW.advance(300)
  T.same(whys(raids()[1]), { "zonein", "interval" })
  T.eq(raids()[1].snapshots[2].members[5].online, false)
  T.eq(raids()[1].snapshots[2].at - raids()[1].snapshots[1].at, 900000)
  WOW.advance(300)
  T.eq(#raids()[1].snapshots, 2, "the same state again")
  -- And back.
  WOW.setRoster(roster(10, "Ember Vault"))
  WOW.advance(300)
  T.eq(#raids()[1].snapshots, 3)
  T.eq(raids()[1].snapshots[3].members[5].online, true)
  T.eq(raids()[1].snapshots[3].members[5].zone, "Ember Vault")
end)

T.test("a change of subgroup, of zone or of who is there is a change", function()
  start()
  local list = roster(10, "Ember Vault")
  WOW.setRoster(list)
  enterVault()
  list[3].subgroup = 8
  WOW.setRoster(list)
  WOW.advance(300)
  T.eq(#raids()[1].snapshots, 2, "a subgroup")
  list[3].zone = "Hearthfire Square"
  WOW.setRoster(list)
  WOW.advance(300)
  T.eq(#raids()[1].snapshots, 3, "a zone")
  table.remove(list, 10)
  WOW.setRoster(list)
  WOW.advance(300)
  T.eq(#raids()[1].snapshots, 4, "someone left")
  T.eq(#raids()[1].snapshots[4].members, 9)
end)

T.test("an interval snapshot that matches a pull's is dropped too, since it is compared with the one before of any kind", function()
  start()
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  WOW.advance(100)
  WOW.fire("ENCOUNTER_START", 1101, "Warden of Cinders", 9, 40)
  WOW.advance(300)
  T.same(whys(raids()[1]), { "zonein", "pull" })
end)

T.test("leaving the instance takes a leave snapshot of the group, who show where they are now", function()
  start()
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  WOW.advance(500)
  local list = roster(10, "Hearthfire Square")
  WOW.setRoster(list)
  leaveVault()
  local raid = raids()[1]
  T.same(whys(raid), { "zonein", "leave" })
  T.eq(raid.closed, true)
  T.eq(#raid.snapshots[2].members, 10)
  T.eq(raid.snapshots[2].members[2].zone, "Hearthfire Square")
  T.eq(raid.snapshots[2].at - raid.snapshots[1].at, 500000)
  -- Time passes and the timer does nothing more.
  WOW.advance(900)
  T.eq(#raid.snapshots, 2)
end)

T.test("leaving the group while inside takes a leave snapshot, with nobody on the roster", function()
  start()
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  WOW.advance(100)
  WOW.setRoster()
  WOW.fire("GROUP_ROSTER_UPDATE")
  local raid = raids()[1]
  T.same(whys(raid), { "zonein", "leave" })
  T.eq(raid.closed, true)
  T.same(raid.snapshots[2].members, {})
end)

T.test("coming back to the same instance soon goes on with the same raid, and later starts another", function()
  start()
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  WOW.advance(600)
  leaveVault()
  T.eq(#raids(), 1)
  WOW.advance(600)
  enterVault()
  T.eq(#raids(), 1, "ten minutes away is the same raid")
  T.same(whys(raids()[1]), { "zonein", "leave", "zonein" })
  T.eq(raids()[1].closed, nil)
  -- The timer runs again.
  WOW.setRoster(roster(11, "Ember Vault"))
  WOW.advance(300)
  T.eq(#raids()[1].snapshots, 4)
  leaveVault()
  WOW.advance(1801)
  enterVault()
  T.eq(#raids(), 2, "more than half an hour away is another raid")
  T.eq(raids()[1].closed, true)
  T.eq(raids()[2].closed, nil)
  T.truthy(raids()[2].id ~= raids()[1].id)
end)

T.test("a different instance, or the same one at another difficulty, is another raid", function()
  start()
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  WOW.advance(100)
  WOW.setInstance({ name = "Cinder Spire", type = "raid", difficultyID = 9, maxPlayers = 40, instanceID = 5012, instanceGroupSize = 40 })
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  T.eq(#raids(), 2)
  T.same(whys(raids()[1]), { "zonein", "leave" })
  T.same(whys(raids()[2]), { "zonein" })
  T.eq(raids()[2].zone, 5012)
  WOW.advance(100)
  WOW.setInstance({ name = "Cinder Spire", type = "raid", difficultyID = 5, maxPlayers = 20, instanceID = 5012, instanceGroupSize = 20 })
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  T.eq(#raids(), 3)
  T.eq(raids()[3].difficulty, 5)
  T.eq(raids()[3].size, 20)
end)

T.test("two snapshots never share a second: an interval is dropped, anything else goes one second later", function()
  local ns = start()
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  WOW.fire("ENCOUNTER_START", 1101, "Warden of Cinders", 9, 40)
  local raid = raids()[1]
  T.eq(#raid.snapshots, 2)
  T.eq(raid.snapshots[2].at - raid.snapshots[1].at, 1000)
  T.eq(raid.snapshots[2].why, "pull")
  local list = roster(10, "Ember Vault")
  list[2].online = false
  WOW.setRoster(list)
  local snap, why = ns.Attendance.snapshot("interval")
  T.eq(snap, nil)
  T.eq(why, "same-second")
  T.eq(#raid.snapshots, 2)
end)

T.test("a reload in the raid goes on with the raid; a login elsewhere ends it with no leave snapshot", function()
  start()
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  WOW.advance(100)
  WOW.fire("ENCOUNTER_START", 1101, "Warden of Cinders", 9, 40)
  local saved = WOW.logout()
  local id = saved.GuildGolemDB.raids[1].id

  -- /reload in the instance: the same raid, and its timer starts again.
  WOW.reset({ time = GetServerTime() + 20 })
  WOW.setRoster(roster(10, "Ember Vault"))
  WOW.setInstance({ name = "Ember Vault", type = "raid", difficultyID = 9, maxPlayers = 40, instanceID = 5011, instanceGroupSize = 40 })
  WOW.declareSavedVariables("GuildGolemDB")
  WOW.saved = saved
  WOW.loadAddon("GuildGolem")
  WOW.login(true)
  T.eq(#raids(), 1)
  T.eq(raids()[1].id, id)
  T.eq(raids()[1].closed, nil)
  WOW.setRoster(roster(9, "Ember Vault"))
  WOW.advance(300)
  T.eq(raids()[1].snapshots[#raids()[1].snapshots].why, "interval", "the timer runs")

  -- Logging in somewhere else: nobody knows when the player left.
  local saved2 = WOW.logout()
  WOW.reset({ time = GetServerTime() + 7200 })
  WOW.declareSavedVariables("GuildGolemDB")
  WOW.saved = saved2
  WOW.loadAddon("GuildGolem")
  WOW.login()
  local raid = raids()[1]
  T.eq(raid.closed, true)
  T.eq(raid.snapshots[#raid.snapshots].why ~= "leave", true)
  T.eq(#raids(), 1)
end)

T.test("the raid leader at zone-in is kept, and an entry is made without one when no one has the rank", function()
  start()
  local list = roster(10, "Ember Vault")
  list[1].rank = 0
  list[4].rank = 2
  WOW.setRoster(list)
  enterVault()
  T.eq(raids()[1].leader, guid(4))
  WOW.reset()
  start()
  list[4].rank = 0
  WOW.setRoster(list)
  enterVault()
  T.eq(raids()[#raids()].leader, nil)
end)

T.test("a party in a raid instance records, with everyone in group 1", function()
  start()
  WOW.setRoster(roster(5, "Ember Vault"), "party")
  enterVault()
  T.eq(#raids(), 1)
  T.eq(#raids()[1].snapshots[1].members, 5)
  T.eq(raids()[1].snapshots[1].members[3].grp, 1)
end)

T.test("a roster row with no GUID is left out, and a name that is not UTF-8 is made safe", function()
  start()
  WOW.setRoster(roster(5, "Ember Vault"))
  local realGuid, realRoster = UnitGUID, GetRaidRosterInfo
  WOW.hide("UnitGUID")
  UnitGUID = function(unit)
    if unit == "raid3" then return nil end
    return realGuid(unit)
  end
  WOW.hide("GetRaidRosterInfo")
  GetRaidRosterInfo = function(i)
    local name, a, b, c, d, e, f, g = realRoster(i)
    if i == 2 then name = "Bad " .. string.char(255) .. " Name" end
    return name, a, b, c, d, e, f, g
  end
  enterVault()
  local snap = raids()[1].snapshots[1]
  T.eq(#snap.members, 4)
  T.eq(snap.members[2].name, "Bad ? Name")
end)

T.test("the saved lockout is kept once the game has one: after a kill, when it answers", function()
  start()
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  T.eq(raids()[1].lockout, nil)
  WOW.fire("ENCOUNTER_START", 1101, "Warden of Cinders", 9, 40)
  WOW.advance(100)
  WOW.fire("ENCOUNTER_END", 1101, "Warden of Cinders", 9, 40, 1)
  T.eq(WOW.raidInfoRequests, 1, "the addon asked")
  T.eq(raids()[1].lockout, nil, "and the game has not answered")
  WOW.setSavedInstances({
    { name = "Cinder Spire", id = 770010, difficulty = 9, locked = true, raid = true },
    { name = "Ember Vault", id = 770011, difficulty = 5, locked = true, raid = true },
    { name = "Ember Vault", id = 770012, difficulty = 9, locked = true, raid = true },
  })
  WOW.fire("UPDATE_INSTANCE_INFO")
  T.eq(raids()[1].lockout, 770012, "this raid's name and difficulty")
  WOW.fire("ENCOUNTER_START", 1102, "Second Warden", 9, 40)
  WOW.fire("ENCOUNTER_END", 1102, "Second Warden", 9, 40, 1)
  T.eq(WOW.raidInfoRequests, 1, "no need to ask again")
end)

T.test("a lockout the game already had at zone-in is kept at once", function()
  start()
  WOW.setSavedInstances({ { name = "Ember Vault", id = 770012, difficulty = 9, locked = true, raid = true } })
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  T.eq(raids()[1].lockout, 770012)
end)

T.test("the night and the bench come from the import that plans this instance, within a day of now", function()
  local ns = start()
  local function person(p, name, chars) return { p = p, name = name, chars = chars } end
  local now = GetServerTime() * 1000
  GuildGolemDB.nights = {
    farther = { handle = "farther", title = "Last week", startsAt = now - 7 * 86400000.0, made = 1, people = {}, raids = { { zone = 5011, name = "Ember Vault", bench = { 1 } } }, parts = {} },
    tonight = {
      handle = "tonight", title = "Friday", startsAt = now - 3600000, made = 2,
      people = {
        [1] = person(1, "Ysolde", { { name = "Ysolde Ironmere", cls = "priest", guid = guid(90) }, { name = "Ysolde Alt", guid = guid(91) } }),
        [2] = person(2, "Orla", { { name = "Orla Ashgrove", cls = "mage" } }),
        [3] = person(3, "Fenwick", { { name = "Fenwick Brightwater", cls = "rogue", guid = guid(92) } }),
      },
      raids = {
        { zone = 5012, name = "Cinder Spire", bench = { 3 } },
        { zone = 5011, name = "Ember Vault", size = 40, bench = { 1, 2, 3 }, picks = { { p = 1, name = "Ysolde Alt", cls = "druid", guid = guid(91) } } },
      },
      parts = {},
    },
  }
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  local raid = raids()[1]
  T.eq(raid.night, "tonight")
  -- The pick replaces the first character; Orla has no GUID the contract's standby can carry; Fenwick has one.
  T.same(raid.standby, { { guid = guid(91), name = "Ysolde Alt", cls = "druid" }, { guid = guid(92), name = "Fenwick Brightwater", cls = "rogue" } })

  -- An instance that no import plans has no night.
  WOW.reset()
  start()
  GuildGolemDB.nights = { tonight = { handle = "tonight", title = "Friday", startsAt = now, made = 2, people = {}, raids = { { zone = 5099, name = "Elsewhere" } }, parts = {} } }
  WOW.setRoster(roster(5, "Ember Vault"))
  enterVault()
  T.eq(raids()[1].night, nil)
  T.eq(raids()[1].standby, nil)
end)

T.test("a raid planned with no zone takes whichever instance the group enters", function()
  start()
  local now = GetServerTime() * 1000
  GuildGolemDB.nights = { tonight = { handle = "tonight", title = "Friday", startsAt = now, made = 2, people = {}, raids = { { name = "Open raid", size = 20 } }, parts = {} } }
  WOW.setRoster(roster(5, "Ember Vault"))
  WOW.setInstance({ name = "Ember Vault", type = "raid", difficultyID = 9, instanceID = 5011 })
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  T.eq(raids()[1].night, "tonight")
  T.eq(raids()[1].size, 20, "the plan's size when the game does not give one")
end)

T.test("raids that were exported and are over a month old are pruned, and nothing else", function()
  local ns = start()
  local now = GetServerTime() * 1000
  local old = now - 40 * 86400000.0
  local function raid(at, sent, closed)
    return { id = "r" .. string.format("%.0f", at), zone = 1, name = "R", difficulty = 9, size = 40, sent = sent, closed = closed,
      snapshots = { { at = at, why = "zonein", members = {} } } }
  end
  GuildGolemDB.raids = { raid(old, 1, true), raid(old + 1000, 0, true), raid(now - 86400000.0, 1, true), raid(old + 2000, 1, nil) }
  T.eq(ns.Attendance.prune(), 1)
  T.eq(#GuildGolemDB.raids, 3)
  T.eq(GuildGolemDB.raids[1].sent, 0, "the one never exported stays")
end)

-- Combat logging ---------------------------------------------------------------------------------------------------------------

local function said(pattern)
  for _, line in ipairs(WOW.chat) do
    if line:find(pattern) then return true end
  end
  return false
end

T.test("combat logging is turned on at zone-in to a raid instance, and the addon says so once", function()
  start()
  WOW.setRoster(roster(10, "Ember Vault"))
  T.eq(WOW.logging, false)
  enterVault()
  T.eq(WOW.logging, true)
  T.same(WOW.loggingCalls, { true })
  local n = 0
  for _, line in ipairs(WOW.chat) do
    if line:find("Combat logging is on") then n = n + 1 end
  end
  T.eq(n, 1)
  -- More events in the same instance do nothing and say nothing.
  WOW.fire("GROUP_ROSTER_UPDATE")
  WOW.fire("ZONE_CHANGED_NEW_AREA")
  WOW.advance(300)
  T.same(WOW.loggingCalls, { true })
end)

T.test("combat logging is turned on with no group too: the raid instance is what counts", function()
  start()
  enterVault()
  T.eq(WOW.logging, true)
end)

T.test("combat logging is left alone when the player turned the option off", function()
  local ns = start()
  T.truthy(ns.Store.setSetting("autoLog", false))
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  T.eq(WOW.logging, false)
  T.same(WOW.loggingCalls, {})
  T.eq(said("Combat logging"), false)
  T.eq(#raids(), 1, "the attendance is recorded all the same")
end)

T.test("combat logging that is on already is not touched and not announced", function()
  start()
  WOW.logging = true
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  T.same(WOW.loggingCalls, {})
  T.eq(said("Combat logging"), false)
end)

T.test("combat logging is not turned on outside a raid instance, and never turned off", function()
  start()
  WOW.setInstance({ name = "Cinder Hollow", type = "party", difficultyID = 1, maxPlayers = 5, instanceID = 801 })
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  T.same(WOW.loggingCalls, {})
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  leaveVault()
  WOW.advance(3600)
  T.same(WOW.loggingCalls, { true })
  T.eq(WOW.logging, true, "still on after the raid")
  -- The next raid: it is on, so nothing is asked.
  enterVault()
  T.same(WOW.loggingCalls, { true })
end)

T.test("a client without LoggingCombat, or one that refuses, makes no fuss", function()
  start()
  WOW.hide("LoggingCombat")
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  T.eq(said("Combat logging"), false)
  T.eq(#raids(), 1)

  WOW.reset()
  start()
  WOW.loggingRefused = true
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  T.eq(WOW.logging, false)
  T.eq(said("Combat logging is on"), false)
end)
