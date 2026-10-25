-- A scripted raid night through the stubs, for test/lua/specs/night_spec.lua and test/night.test.mjs: forty players in three
-- raids over about four hours, with wipes and kills, a disconnect and a reconnect, a player who leaves early, a bench from
-- the import and a pug. It defines NIGHT.run(), which plays the night, makes the export and returns what happened as plain
-- data. Every name, GUID, instance id and encounter id is made up.
--
-- The night, in minutes from the start (the server's clock moves by WOW.advance, so the addon's five-minute timer runs):
--    0  the group stands in Hearthfire Square; the night's plan (three raids, a bench of two) is imported
--   10  Ember Vault (5011): the recorder zones in with 30 of 40; the rest arrive by minute 14
--   20  boss 1101: pull, wipe at 23, pull at 27, kill at 30 (the game then has a lockout)
--   31  one player disconnects (back at 47)       40  boss 1102 killed at 44
--   48  one player leaves the group for good      55  boss 1103: pull, wipe, pull, kill at 65
--   70  out of the instance
--   85  Cinder Spire (5012): 95 pull and kill at 99; 110 pull, wipe 113, pull 118, kill 123; one disconnect 100 to 124; out at 130
--  135  the pug leaves the group
--  145  Glass Foundry (5013): bosses 3301, 3302, 3303 with a wipe each; 235 the leader disbands the group inside

NIGHT = {}

local FIRST = { "Tolvar", "Mirel", "Quill", "Sable", "Kestrel", "Brannoch", "Ysolde", "Fenwick", "Orla", "Dunstan" }
local LAST = { "Ashgrove", "Dawnwhisper", "Brightwater", "Ironmere" }
local CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "HUNTER", "SHAMAN", "WARLOCK", "DRUID" }

-- Two server ids on the one realm, as the probe found.
local function guid(i) return string.format("Player-910%d-%08X", 1 + i % 2, 0x0F000000 + i) end
local function nameOf(i) return FIRST[(i - 1) % 10 + 1] .. " " .. LAST[math.floor((i - 1) / 10) + 1] end

local LEAVER, DISCONNECTER, DISCONNECTER2, PUG = 17, 9, 22, 40
local BENCH = { { 41, "Ottoline Vale", "priest" }, { 42, "Wren Hollis", "mage" } }

local RAIDS = {
  { zone = 5011, name = "Ember Vault" },
  { zone = 5012, name = "Cinder Spire" },
  { zone = 5013, name = "Glass Foundry" },
}

-- The plan the site would send: all of the guild's people but the pug, and the bench, in the night's first raid.
local function planObject(startMs)
  local people = {}
  for i = 1, 39 do
    local chars = { { name = i == 1 and "Rhona Tester" or nameOf(i), cls = CLASSES[i % 8 + 1]:lower(), guid = i == 1 and WOW.player.guid or guid(i) } }
    people[#people + 1] = { p = i, name = "Person " .. i, chars = chars }
  end
  for k, b in ipairs(BENCH) do
    people[#people + 1] = { p = 39 + k, name = "Person " .. (39 + k), chars = { { name = b[2], cls = b[3], guid = guid(b[1]) } } }
  end
  local raids = {}
  for k, r in ipairs(RAIDS) do
    raids[k] = { zone = r.zone, name = r.name, size = 40, bench = k == 1 and { 40, 41 } or nil }
  end
  return {
    v = 1, kind = "import",
    meta = { site = "0.36.2", made = startMs - 3600000, latest = "0.1.0", from = "night" },
    guild = { handle = "abcd2345", name = "Ashen Wardens" },
    night = { handle = "efgh6789", title = "Friday raids", startsAt = startMs },
    people = people,
    raids = raids,
  }
end

-- Plays the night and the export. Leaves the game where the night ended (the addon loaded, the group gone), so the caller
-- can log out and in again. Returns the facts.
function NIGHT.run()
  WOW.reset()
  WOW.declareSavedVariables("GuildGolemDB")
  local ns = WOW.loadAddon("GuildGolem")
  WOW.login()
  WOW.setGuild({ name = "Ashen Wardens", rank = "Officer" })
  local startMs = GetServerTime() * 1000

  assert(ns.Import.load(ns.Codec.encode(planObject(startMs))), "the plan did not import")

  -- The group: 40 players, the recorder first and leading, the pug last.
  local group = {}
  for i = 1, 40 do
    group[i] = {
      i = i, name = i == 1 and "Rhona Tester" or nameOf(i), class = i == 1 and "MAGE" or CLASSES[i % 8 + 1],
      guid = i == 1 and WOW.player.guid or guid(i), sub = math.floor((i - 1) / 5) + 1, present = true, online = true, inside = false,
    }
  end
  local zoneName = "Hearthfire Square"

  local function publish()
    local list = {}
    for _, g in ipairs(group) do
      if g.present then
        list[#list + 1] = {
          name = g.name, class = g.class, guid = g.guid, subgroup = g.sub, rank = g.i == 1 and 2 or 0, online = g.online,
          zone = g.inside and zoneName or "Hearthfire Square",
        }
      end
    end
    WOW.setRoster(list)
    WOW.fire("GROUP_ROSTER_UPDATE")
  end

  local minute = 0
  local function at(m)
    assert(m >= minute, "the night runs forward")
    WOW.advance((m - minute) * 60)
    minute = m
  end
  local function insideUpTo(n)
    for _, g in ipairs(group) do g.inside = g.i <= n end
  end
  local function enter(raid)
    zoneName = raid.name
    WOW.setInstance({ name = raid.name, type = "raid", difficultyID = 9, difficultyName = "Heroic", maxPlayers = 40, instanceID = raid.zone, instanceGroupSize = 40 })
    publish()
    WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  end
  local function leave()
    for _, g in ipairs(group) do g.inside = false end
    zoneName = "Hearthfire Square"
    WOW.setInstance()
    publish()
    WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  end
  local function pull(id) WOW.fire("ENCOUNTER_START", id, "Boss " .. id, 9, 40) end
  local function ended(id, success) WOW.fire("ENCOUNTER_END", id, "Boss " .. id, 9, 40, success) end

  publish()

  -- Raid 1.
  at(10)
  insideUpTo(30)
  enter(RAIDS[1])
  at(12)
  insideUpTo(36)
  publish()
  at(14)
  insideUpTo(40)
  publish()
  at(20); pull(1101)
  at(23); ended(1101, 0)
  at(27); pull(1101)
  at(30); ended(1101, 1)
  WOW.setSavedInstances({ { name = "Ember Vault", id = 770011, difficulty = 9, locked = true, raid = true } })
  WOW.fire("UPDATE_INSTANCE_INFO")
  at(31)
  group[DISCONNECTER].online = false
  publish()
  at(40); pull(1102)
  at(44); ended(1102, 1)
  at(47)
  group[DISCONNECTER].online = true
  publish()
  at(48)
  group[LEAVER].present = false
  publish()
  at(55); pull(1103)
  at(57); ended(1103, 0)
  at(61); pull(1103)
  at(65); ended(1103, 1)
  at(70)
  leave()

  -- Raid 2.
  at(85)
  insideUpTo(40)
  enter(RAIDS[2])
  at(95); pull(2201)
  at(99); ended(2201, 1)
  at(100)
  group[DISCONNECTER2].online = false
  publish()
  at(110); pull(2202)
  at(113); ended(2202, 0)
  at(118); pull(2202)
  at(123); ended(2202, 1)
  at(124)
  group[DISCONNECTER2].online = true
  publish()
  at(130)
  leave()
  at(135)
  group[PUG].present = false
  publish()

  -- Raid 3.
  at(145)
  insideUpTo(40)
  enter(RAIDS[3])
  at(160); pull(3301)
  at(165); ended(3301, 1)
  at(175); pull(3302)
  at(178); ended(3302, 0)
  at(185); pull(3302)
  at(190); ended(3302, 1)
  at(200); pull(3303)
  at(205); ended(3303, 0)
  at(215); pull(3303)
  at(222); ended(3303, 1)
  at(235)
  -- The leader disbands the group inside the instance.
  WOW.setRoster()
  WOW.fire("GROUP_ROSTER_UPDATE")

  local raids = {}
  local stored = 0
  for k, raid in ipairs(GuildGolemDB.raids) do
    local whys = {}
    for i, s in ipairs(raid.snapshots) do whys[i] = s.why end
    raids[k] = { id = raid.id, zone = raid.zone, count = #raid.snapshots, whys = table.concat(whys, ","), closed = raid.closed == true,
      lockout = raid.lockout, night = raid.night, leader = raid.leader }
    stored = stored + #raid.snapshots
  end

  -- The export.
  local result, why = ns.Export.make()
  local export = {}
  for i, entry in ipairs(result and result.entries or {}) do export[i] = { id = entry.id, text = entry.text, characters = #entry.text } end
  local second, secondWhy = ns.Export.make()
  local outboxAfterSecond = #GuildGolemDB.outbox
  local all = ns.Export.make({ all = true })
  local allTexts = {}
  for i, entry in ipairs(all and all.entries or {}) do allTexts[i] = entry.text end

  return {
    startMs = startMs,
    minutes = minute,
    ok = result ~= nil,
    why = why,
    export = export,
    exported = result and result.snapshots or 0,
    pugs = result and result.pugs or 0,
    stored = stored,
    raids = raids,
    secondMade = second ~= nil,
    secondWhy = secondWhy,
    outboxAfterSecond = outboxAfterSecond,
    allTexts = allTexts,
    people = {
      recorder = WOW.player.guid, pug = guid(PUG), leaver = guid(LEAVER), disconnecter = guid(DISCONNECTER),
      disconnecter2 = guid(DISCONNECTER2), benched = { guid(41), guid(42) },
    },
  }
end
