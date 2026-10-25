-- Export.lua: what an export holds (the contract's meta, attendance and pugs), what it leaves out, what it marks as covered,
-- how it is kept under the writers' limits (`fit`), and what happens when it cannot be made.

local FIRST = { "Tolvar", "Mirel", "Quill", "Sable", "Kestrel", "Brannoch", "Ysolde", "Fenwick", "Orla", "Dunstan" }
local LAST = { "Ashgrove", "Dawnwhisper", "Brightwater", "Ironmere" }

local function guid(i) return string.format("Player-9101-%08X", 0x0F000000 + i) end
local function name(i) return FIRST[(i - 1) % 10 + 1] .. " " .. LAST[math.floor((i - 1) / 10) + 1] end

local function roster(n, zone)
  local list = { { name = "Rhona Tester", class = "MAGE", guid = WOW.player.guid, rank = 2, subgroup = 1, zone = zone } }
  for i = 2, n do
    list[i] = { name = name(i), class = "WARRIOR", guid = guid(i), subgroup = math.floor((i - 1) / 5) + 1, zone = zone }
  end
  return list
end

local function enterVault()
  WOW.setInstance({ name = "Ember Vault", type = "raid", difficultyID = 9, maxPlayers = 40, instanceID = 5011, instanceGroupSize = 40 })
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
end

local function start()
  WOW.declareSavedVariables("GuildGolemDB")
  local ns = WOW.loadAddon("GuildGolem")
  WOW.login()
  return ns
end

-- A night's import of the guild's people (all but the last of `n`, who is a pug), kept as the store keeps it.
local function importPeople(ns, n, bench)
  local people, raidBench = {}, {}
  for i = 1, n do
    people[i] = { p = i, name = "Person " .. i, chars = { { name = name(i), cls = "warrior", guid = guid(i) } } }
  end
  people[1].chars[1] = { name = "Rhona Tester", cls = "mage", guid = WOW.player.guid }
  for _, p in ipairs(bench or {}) do raidBench[#raidBench + 1] = p end
  GuildGolemDB.guild = { handle = "abcd2345", name = "Ashen Wardens" }
  GuildGolemDB.nights = {
    efgh6789 = {
      handle = "efgh6789", title = "Friday", startsAt = GetServerTime() * 1000, made = GetServerTime() * 1000, people = people,
      raids = { { zone = 5011, name = "Ember Vault", bench = raidBench } }, parts = {},
    },
  }
end

local function read(text)
  local object, reason, says = GuildGolem.Codec.read(text, "site")
  T.truthy(object, tostring(reason) .. " " .. tostring(says))
  return object
end

-- Takes a roster of `n` into the vault and records a pull and a kill: a raid of three snapshots.
local function aRaid(ns, n)
  WOW.setRoster(roster(n, "Ember Vault"))
  enterVault()
  WOW.advance(60)
  WOW.fire("ENCOUNTER_START", 1101, "Warden of Cinders", 9, 40)
  WOW.advance(100)
  WOW.fire("ENCOUNTER_END", 1101, "Warden of Cinders", 9, 40, 1)
end

T.test("an export holds the meta the contract asks for, the raid and its snapshots", function()
  local ns = start()
  WOW.setGuild({ name = "Ashen Wardens", rank = "Officer" })
  importPeople(ns, 10)
  aRaid(ns, 10)
  local result = ns.Export.make()
  T.truthy(result)
  T.eq(result.count, 1)
  T.eq(result.raids, 1)
  T.eq(result.snapshots, 3)
  T.eq(result.pugs, 0)

  local out = read(result.entries[1].text)
  T.eq(out.v, 1)
  T.eq(out.kind, "export")
  local meta = out.meta
  T.truthy(meta.id:find("^%w+%.%x%x%x%x%x%x%x%x$"), meta.id)
  T.eq(meta.made, GetServerTime() * 1000)
  T.eq(meta.addon, "0.1.0-beta")
  T.same(meta.client, { version = "1.60.1", build = 70532, interface = 16001, locale = "enUS" })
  T.same(meta.by, { guid = WOW.player.guid, name = "Rhona Tester" })
  T.eq(meta.realm, "Classic Beta PvP")
  T.eq(meta.guildName, "Ashen Wardens")
  T.eq(meta.guild, "abcd2345")
  T.eq(meta.night, "efgh6789")
  T.eq(meta.skew, 0)
  T.eq(out.loot, nil, "loot is M4")
  T.eq(out.pugs, nil)

  T.eq(#out.attendance, 1)
  local raid = out.attendance[1]
  T.eq(raid.id, GuildGolemDB.raids[1].id)
  T.eq(raid.zone, 5011)
  T.eq(raid.name, "Ember Vault")
  T.eq(raid.difficulty, 9)
  T.eq(raid.size, 40)
  T.eq(raid.night, "efgh6789")
  T.eq(raid.leader, WOW.player.guid)
  T.eq(raid.sent, nil, "what is ours stays ours")
  T.eq(raid.seen, nil)
  T.eq(#raid.snapshots, 3)
  T.eq(raid.snapshots[2].encounter, 1101)
  T.eq(#raid.snapshots[1].members, 10)
  T.eq(GuildGolem.Store.outboxPending()[1].id, meta.id)
  T.eq(GuildGolemDB.outbox[1].kind, "attendance")
end)

T.test("the guild and the night are left out when the addon was never given them, and the guild name when there is no guild", function()
  local ns = start()
  aRaid(ns, 5)
  local out = read(ns.Export.make().entries[1].text)
  T.eq(out.meta.guild, nil)
  T.eq(out.meta.guildName, nil)
  T.eq(out.meta.night, nil)
  T.eq(out.attendance[1].night, nil)
  T.eq(out.pugs, nil, "with no roster imported, no one can be told for a pug")
end)

T.test("an export marks what it covered, so the next holds only what is new, and 'all' holds everything", function()
  local ns = start()
  aRaid(ns, 10)
  local first = ns.Export.make()
  T.eq(first.snapshots, 3)
  T.eq(GuildGolemDB.raids[1].sent, 3)

  local again, why, says = ns.Export.make()
  T.eq(again, nil)
  T.eq(why, "nothing")
  T.truthy(says:find("Nothing new"))
  T.eq(#GuildGolemDB.outbox, 1)

  -- Someone leaves; the next interval and the leave are new.
  WOW.setRoster(roster(9, "Ember Vault"))
  WOW.advance(300)
  WOW.setInstance()
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  local second = ns.Export.make()
  T.eq(second.snapshots, 2)
  local out = read(second.entries[1].text)
  T.eq(out.attendance[1].id, GuildGolemDB.raids[1].id, "the same raid, in pieces")
  T.eq(#out.attendance[1].snapshots, 2)
  T.eq(out.attendance[1].snapshots[1].why, "interval")
  T.eq(out.attendance[1].snapshots[2].why, "leave")
  T.eq(#GuildGolemDB.outbox, 2)

  local everything = ns.Export.make({ all = true })
  T.eq(everything.snapshots, 5)
  T.eq(#GuildGolemDB.outbox, 3)
  T.truthy(everything.entries[1].id ~= first.entries[1].id)
end)

T.test("an export made while the raid is still going holds what there is, and the raid goes on", function()
  local ns = start()
  aRaid(ns, 10)
  T.truthy(ns.Export.make())
  WOW.setRoster(roster(8, "Ember Vault"))
  WOW.advance(300)
  local raid = GuildGolemDB.raids[1]
  T.eq(raid.closed, nil)
  T.eq(#raid.snapshots, 4)
  local out = read(ns.Export.make().entries[1].text)
  T.eq(#out.attendance[1].snapshots, 1)
  T.eq(out.attendance[1].snapshots[1].why, "interval")
end)

T.test("pugs are the players in the snapshots who are not on the imported roster, once each, and never the recorder", function()
  local ns = start()
  importPeople(ns, 9)
  -- Person 4's GUID is not known to the import yet: it knows the name.
  GuildGolemDB.nights.efgh6789.people[4].chars[1].guid = nil
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  WOW.advance(60)
  WOW.fire("ENCOUNTER_START", 1101, "Warden of Cinders", 9, 40)
  local result = ns.Export.make()
  T.eq(result.pugs, 1)
  local out = read(result.entries[1].text)
  T.eq(#out.pugs, 1)
  T.eq(out.pugs[1].guid, guid(10))
  T.eq(out.pugs[1].name, name(10))
  T.eq(out.pugs[1].cls, "warrior")
  T.eq(out.pugs[1].at, GuildGolemDB.raids[1].snapshots[1].at)
end)

T.test("a benched player who never came into the group is on standby, one who did is not", function()
  local ns = start()
  importPeople(ns, 12, { 11, 12, 3 })
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  T.eq(#GuildGolemDB.raids[1].standby, 3)
  local out = read(ns.Export.make().entries[1].text)
  T.same(out.attendance[1].standby, {
    { guid = guid(11), name = name(11), cls = "warrior" },
    { guid = guid(12), name = name(12), cls = "warrior" },
  })
end)

T.test("an id differs from one press to the next, even in the same second", function()
  local ns = start()
  local seen = {}
  for i = 1, 20 do
    local id = ns.Export.id(GetServerTime() * 1000)
    T.truthy(id:find("^%w+%.%x%x%x%x%x%x%x%x$"), id)
    T.eq(seen[id], nil)
    seen[id] = true
  end
end)

T.test("the made-in-base-36 half of an id is the time as the contract's example writes it", function()
  local ns = start()
  local function base36(n)
    local digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    while n >= 1 do
      local d = n % 36
      out = digits:sub(d + 1, d + 1) .. out
      n = math.floor(n / 36)
    end
    return out
  end
  T.eq(ns.Export.id(1796864400000):match("^(%w+)%."), base36(1796864400000))
  T.eq(ns.Export.id(1796864400000):match("^(%w+)%."):len(), 8)
end)

T.test("it will not make an export without a player, a build, a clock or a writable store, and says why", function()
  local ns = start()
  aRaid(ns, 5)
  WOW.hide("GetBuildInfo")
  local result, why, says = ns.Export.make()
  T.eq(result, nil)
  T.eq(why, "no-build")
  T.truthy(says:find("version or realm"))
  T.eq(#GuildGolemDB.outbox, 0)
  T.eq(GuildGolemDB.raids[1].sent, 0, "and marks nothing")

  WOW.reset()
  ns = start()
  aRaid(ns, 5)
  WOW.hide("GetServerTime")
  _, why = ns.Export.make()
  T.eq(why, "no-clock")

  WOW.reset()
  ns = start()
  aRaid(ns, 5)
  GuildGolemDB.schema = 99
  ns.Store.init()
  _, why = ns.Export.make()
  T.eq(why, "read-only")
end)

-- fit -----------------------------------------------------------------------------------------------------------------------------
--
-- The rosters here are small (a few players) and the limits low, so that what each snapshot adds is large next to the roster
-- itself and thinning shows in the size, and so that packing stays quick under fengari. The limits were chosen between the
-- sizes of two steps with a margin of a sixth or more either way. test/export-fit.test.mjs compares these cuts with the
-- reference `fit` on the same kind of night.

local function member(i, online, zone)
  return { guid = guid(i), name = name(i), cls = "warrior", grp = math.floor((i - 1) / 5) + 1, online = online ~= false, zone = zone or "Ember Vault" }
end

-- A raid of `snapshots` snapshots of `players`: a zone-in, intervals (with a different player offline in each if `churn`, so
-- none repeats the one before) and a leave.
local function bigRaid(id, zone, players, snapshots, churn)
  local snaps = {}
  for k = 1, snapshots do
    local members = {}
    for i = 1, players do members[i] = member(i, not (churn and i == 1 + k % players)) end
    snaps[k] = { at = 1796846700000 + k * 300000.0, why = k == 1 and "zonein" or (k == snapshots and "leave" or "interval"), members = members }
  end
  return { id = id, zone = zone, name = "Raid " .. zone, difficulty = 9, size = 40, snapshots = snaps }
end

local function exportOf(attendance, extra)
  local o = {
    v = 1, kind = "export",
    meta = { id = "mgq1k2zt.00000001", made = 1796864400000, addon = "0.1.0", client = { version = "1.60.1", build = 70532, interface = 16001, locale = "enUS" },
      by = { guid = guid(1), name = name(1) }, realm = "Classic Beta PvP" },
    attendance = attendance,
  }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

local PUG = { { guid = guid(99), name = "Pug One", cls = "mage", at = 1796846700000 } }

local function snapshotsOf(o)
  local out = {}
  for _, r in ipairs(o.attendance or {}) do
    for _, s in ipairs(r.snapshots) do out[#out + 1] = s end
  end
  return out
end

local function count(list, why)
  local n = 0
  for _, s in ipairs(list) do
    if why == nil or s.why == why then n = n + 1 end
  end
  return n
end

local function sizes(list, limit)
  for _, item in ipairs(list) do
    T.truthy(item.text and #item.text <= limit, "a string of " .. tostring(item.text and #item.text) .. " characters")
    T.truthy(#GuildGolem.Codec.json(item.object) <= GuildGolem.Codec.WRITE_JSON)
    T.eq(GuildGolem.Codec.read(item.text, "site") ~= nil, true)
  end
end

T.test("fit leaves an export that is short enough alone", function()
  local ns = start()
  local o = exportOf({ bigRaid("r1", 5011, 12, 4, true) })
  local list = ns.Export.fit(o)
  T.eq(#list, 1)
  T.truthy(list[1].object == o)
  T.same(read(list[1].text), GuildGolem.Codec.decode(list[1].text))
end)

T.test("fit drops an interval that repeats the one before first, and keeps every other kind", function()
  local ns = start()
  local o = exportOf({ bigRaid("r1", 5011, 6, 30, false) })
  local limit = 700
  T.truthy(#ns.Codec.encode(o) > limit, "too long to send as it is")
  local list = ns.Export.fit(o, limit)
  T.eq(#list, 1)
  sizes(list, limit)
  local got = list[1].object
  T.eq(got.meta.id, o.meta.id, "one string keeps its id")
  T.eq(count(snapshotsOf(got), "interval"), 0)
  T.eq(count(snapshotsOf(got), "zonein"), 1)
  T.eq(count(snapshotsOf(got), "leave"), 1)
end)

T.test("fit then keeps a quarter of the intervals that did change", function()
  local ns = start()
  local o = exportOf({ bigRaid("r1", 5011, 3, 120, true) })
  local limit = 1100
  T.truthy(#ns.Codec.encode(o) > limit)
  local list = ns.Export.fit(o, limit)
  T.eq(#list, 1)
  sizes(list, limit)
  T.eq(count(snapshotsOf(list[1].object), "interval"), 30, "every fourth of 118")
  T.eq(count(snapshotsOf(list[1].object)), 32)
end)

T.test("fit then makes a string for each raid and one for the pugs, each with its own id and readable alone", function()
  local ns = start()
  local o = exportOf({ bigRaid("r1", 5011, 3, 80, true), bigRaid("r2", 5012, 3, 80, true), bigRaid("r3", 5013, 3, 80, true) }, { pugs = PUG })
  local limit = 850
  local list = ns.Export.fit(o, limit)
  T.eq(#list, 4)
  sizes(list, limit)
  local ids = {}
  for _, item in ipairs(list) do
    ids[item.object.meta.id] = true
    T.eq(item.object.meta.by.guid, guid(1))
    T.eq(read(item.text).meta.id, item.object.meta.id)
  end
  T.eq(ids["mgq1k2zt.00000001.1"], true)
  T.eq(ids["mgq1k2zt.00000001.4"], true)
  T.eq(list[1].object.attendance[1].id, "r1")
  T.eq(list[3].object.attendance[1].id, "r3")
  T.eq(list[4].object.attendance, nil)
  T.eq(#list[4].object.pugs, 1)
end)

T.test("fit keeps every sixteenth interval when a quarter is still too much for a string", function()
  local ns = start()
  local o = exportOf({ bigRaid("r1", 5011, 3, 130, true), bigRaid("r2", 5012, 3, 130, true) }, { pugs = PUG })
  -- What a raid comes to in a string when every fourth, and when every sixteenth, interval is kept.
  local function alone(keep)
    local raid, n = {}, 0
    for k, v in pairs(o.attendance[1]) do raid[k] = v end
    raid.snapshots = {}
    for _, s in ipairs(o.attendance[1].snapshots) do
      if s.why ~= "interval" then
        raid.snapshots[#raid.snapshots + 1] = s
      else
        if n % keep == 0 then raid.snapshots[#raid.snapshots + 1] = s end
        n = n + 1
      end
    end
    return #ns.Codec.encode(exportOf({ raid }))
  end
  local quarter, sixteenth = alone(4), alone(16)
  T.truthy(sixteenth < quarter * 0.8, sixteenth .. " against " .. quarter)
  local limit = math.floor((quarter + sixteenth) / 2)
  local list = ns.Export.fit(o, limit)
  sizes(list, limit)
  T.eq(#list, 3, "a string for each raid and one for the pugs")
  for r = 1, 2 do
    T.eq(count(list[r].object.attendance[1].snapshots, "interval"), math.ceil(128 / 16), "every sixteenth of 128")
  end
end)

T.test("fit cuts a raid that is still too big in halves that share its id, and loses no pull, kill or wipe", function()
  local ns = start()
  local raid = bigRaid("r1", 5011, 3, 80, true)
  for k = 2, 79 do
    raid.snapshots[k].why = k % 2 == 0 and "pull" or "wipe"
    raid.snapshots[k].encounter = 1100 + k % 7
  end
  local o = exportOf({ raid })
  local limit = 1150
  local list = ns.Export.fit(o, limit)
  T.truthy(#list >= 2, #list .. " strings")
  sizes(list, limit)
  local times, n = {}, 0
  local ids = {}
  for _, item in ipairs(list) do
    T.eq(#item.object.attendance, 1)
    T.eq(item.object.attendance[1].id, "r1")
    ids[item.object.meta.id] = true
    for _, s in ipairs(item.object.attendance[1].snapshots) do
      n = n + 1
      times[n] = s.at
    end
  end
  T.eq(n, 80, "all the snapshots, none repeated")
  for i = 2, n do T.truthy(times[i] > times[i - 1], "in order") end
  local distinct = 0
  for _ in pairs(ids) do distinct = distinct + 1 end
  T.eq(distinct, #list, "each has an id of its own")
end)

T.test("fit keeps the JSON under the writers' limit as well as the text, whatever the text would be", function()
  local ns = start()
  -- The limit is lowered so a small export can pass it: 40 players for 30 snapshots is far over 20,000 bytes of JSON,
  -- though it is a few thousand characters of text.
  ns.Codec.WRITE_JSON = 20000
  local o = exportOf({ bigRaid("r1", 5011, 40, 30, false) })
  T.truthy(#ns.Codec.json(o) > 20000)
  local list = ns.Export.fit(o)
  T.eq(#list, 1)
  T.truthy(#ns.Codec.json(list[1].object) <= 20000)
  T.eq(count(snapshotsOf(list[1].object), "interval"), 0, "the repeats went first")
  ns.Codec.WRITE_JSON = 786432
end)

T.test("fit gives up on one snapshot that is over the limit by itself, and says so by giving no string for it", function()
  local ns = start()
  local o = exportOf({ bigRaid("r1", 5011, 40, 1, false) })
  local list = ns.Export.fit(o, 200)
  T.eq(#list >= 1, true)
  T.eq(list[1].text, nil)
end)
