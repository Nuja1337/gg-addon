-- Core/Import.lua: each import kind in contract/fixtures read into the saved variables, and what a reader does with
-- an unknown field, an unknown enum value and a bad string (contract/README.md, "What a reader does").

local KINDS = { "priorities", "night-loot", "night-assignments", "night" }

local function start()
  WOW.declareSavedVariables("GuildGolemDB")
  local ns = WOW.loadAddon("GuildGolem")
  WOW.login()
  return ns
end

local function fixtureText(kind) return assert(WOW.readFile("contract/fixtures/import-" .. kind .. ".gg1.txt")) end
local function fixtureJson(kind) return assert(WOW.readFile("contract/fixtures/import-" .. kind .. ".json")) end

-- The fixture as a table, to change and write again.
local function fixtureObject(kind)
  return LibStub("json.lua").decode(fixtureJson(kind))
end

-- A string made from JSON text, for a change the Lua table cannot say (null, false).
local function pack(ns, jsonText)
  return "GG1:" .. ns.Base64.encode(LibStub("LibDeflate"):CompressZlib(jsonText))
end

local function write(ns, object)
  return assert(ns.Codec.encode(object))
end

local function read(ns, object)
  return ns.Import.read(write(ns, object))
end

T.test("every import fixture reads, with the counts its JSON has", function()
  local ns = start()
  local json = LibStub("json.lua")
  for _, kind in ipairs(KINDS) do
    local parsed, reason, says = ns.Import.read(fixtureText(kind))
    T.truthy(parsed, kind .. ": " .. tostring(reason) .. " " .. tostring(says))
    T.eq(parsed.from, kind)
    local raw = json.decode(fixtureJson(kind))
    T.eq(#parsed.raids, #raw.raids, kind .. " raids")
    local people = 0
    for _ in pairs(parsed.people) do people = people + 1 end
    T.eq(people, #raw.people, kind .. " people")
    local items, assignments = 0, 0
    for _, raid in ipairs(raw.raids) do
      if raid.loot then items = items + #raid.loot.items end
      if raid.assignments then assignments = assignments + #raid.assignments end
    end
    local summary = ns.Import.summary(parsed)
    T.eq(summary.items, items, kind .. " items")
    T.eq(summary.assignments, assignments, kind .. " assignments")
    T.eq(summary.guild, "Molten Raiders")
    T.eq(parsed.made, raw.meta.made)
    T.eq(parsed.site, raw.meta.site)
    T.eq(parsed.latest, raw.meta.latest)
  end
end)

T.test("priorities: one raid with its loot, and each person by their main", function()
  local ns = start()
  local p = ns.Import.read(fixtureText("priorities"))
  T.eq(p.guild.handle, "abcd2345")
  T.eq(p.night, nil)
  T.eq(p.officer, true)
  local raid = p.raids[1]
  T.eq(raid.zone, 5011)
  T.eq(raid.name, "Ember Vault")
  T.eq(raid.lootBy, "system")
  local items = raid.loot.items
  T.eq(#items, 4)
  T.eq(items[1].id, 288101)
  T.same(items[1].order, { { 1 }, { 2, 3 } })
  T.same(items[1].specs, { { "mage:1", "warlock:3" }, { "priest:3" } })
  T.eq(items[1].key, true)
  T.eq(items[1].note, "Cinderjaw's ring")
  T.eq(items[2].free, true)
  T.eq(items[3].hard, 0, "a hard reserve for the guild is 0, not absent")
  T.same(items[4].order, { { 5 }, { 9 } })
  T.eq(p.people[1].name, "Vex")
  T.eq(p.people[1].chars[1].guid, "Player-9101-0F00AA11")
  T.eq(p.people[3].chars[1].guid, nil, "a character with no GUID yet")
  T.eq(p.people[3].chars[1].name, "Mira Stonebrook")
  T.eq(p.people[4], nil, "a person the string doesn't name")
end)

T.test("night-loot: soft reserves, with the weeks of an SR+", function()
  local ns = start()
  local p = ns.Import.read(fixtureText("night-loot"))
  T.eq(p.night.handle, "efgh6789")
  T.eq(p.night.title, "Weekend raids")
  T.eq(p.night.startsAt, 1796846400000)
  local sr = p.raids[1].loot.items[1].sr
  T.truthy(sr and #sr >= 2, "the first item has reserves")
  local withPlus = 0
  for _, entry in ipairs(sr) do
    T.truthy(p.people[entry.p], "a reserve names someone in people")
    if entry.plus then withPlus = withPlus + 1 end
  end
  T.truthy(withPlus >= 1)
end)

T.test("night-assignments: bosses with and without an encounter id, and a slot nobody fills", function()
  local ns = start()
  local p = ns.Import.read(fixtureText("night-assignments"))
  T.eq(#p.raids, 2)
  local sawNoEncounter, sawEmptySlot = false, false
  for _, raid in ipairs(p.raids) do
    for _, a in ipairs(raid.assignments) do
      T.truthy(a.boss ~= "")
      if a.encounter == nil then sawNoEncounter = true end
      for _, list in ipairs(a.lists) do
        for _, slot in ipairs(list.slots) do
          T.truthy(slot.label ~= "")
          if #slot.p == 0 then sawEmptySlot = true end
        end
      end
    end
  end
  T.truthy(sawNoEncounter)
  T.truthy(sawEmptySlot)
end)

T.test("night: three raids, with effort, picks, groups, bench, loot and assignments each", function()
  local ns = start()
  local p = ns.Import.read(fixtureText("night"))
  T.eq(#p.raids, 3)
  T.same({ p.raids[1].effort.name, p.raids[2].effort.name, p.raids[3].effort.name }, { "Locked in", "Steady", "Casual" })
  T.same(p.raids[1].effort.expects, { "flask", "food", "weapon", "potions", "engineering", "misc" })
  T.eq(p.raids[3].optional, true)
  T.eq(p.raids[1].optional, nil)
  T.eq(p.raids[1].lootBy, "system")
  T.eq(p.raids[2].lootBy, "hard")
  T.eq(#p.raids[1].picks, 9)
  T.same(p.raids[1].groups, { { 2, 7, 3, 8, 1 }, { 4, 5, 6, 9 } })
  T.same(p.raids[1].bench, { 10 })
  T.same(p.raids[2].bench, {}, "an empty bench is an empty list")
  T.eq(#p.raids[1].assignments, 2)
  T.eq(p.raids[1].assignments[1].lists[1].slots[1].note, "Face him away from the raid")
  T.same(p.raids[1].assignments[1].lists[2].slots[1].p, { 4, 1 })
  T.same(p.raids[1].assignments[1].lists[2].slots[2].p, {})
  -- Someone playing an alternate: the pick names the character, and the person has another one.
  local alternates = 0
  for _, raid in ipairs(p.raids) do
    for _, pick in ipairs(raid.picks) do
      if pick.name ~= p.people[pick.p].chars[1].name then alternates = alternates + 1 end
    end
  end
  T.truthy(alternates >= 1)
end)

T.test("the summary is what a preview shows", function()
  local ns = start()
  local s = ns.Import.summary(ns.Import.read(fixtureText("night")))
  T.eq(s.from, "night")
  T.eq(s.night, "Weekend raids")
  T.eq(s.raids, 3)
  T.eq(s.people, 10)
  T.eq(s.officer, true)
end)

-- Saving ----------------------------------------------------------------------------------------------------------

T.test("priorities are kept for each raid by its zone, with the people they name", function()
  local ns = start()
  local summary, ok = ns.Import.load(fixtureText("priorities"))
  T.truthy(ok)
  T.eq(summary.items, 4)
  local db = GuildGolemDB
  local saved = db.priorities[5011]
  T.eq(saved.raid.loot.items[1].id, 288101)
  T.eq(saved.people[2].name, "Kael")
  T.eq(saved.officer, true)
  T.eq(saved.made, 1796843700000)
  T.eq(db.guild.handle, "abcd2345")
  T.eq(db.guild.name, "Molten Raiders")
  T.eq(db.site.version, "0.36.2")
  T.eq(db.site.latest, "0.1.0")
  T.same(db.nights, {})
end)

T.test("a night is kept by its handle; each import of the night adds its part and takes nothing else away", function()
  local ns = start()
  local I = ns.Import
  T.truthy(select(2, I.load(fixtureText("night-loot"))))
  local night = GuildGolemDB.nights.efgh6789
  T.eq(night.title, "Weekend raids")
  T.eq(night.startsAt, 1796846400000)
  T.eq(#night.raids, 1)
  T.truthy(night.raids[1].loot.items[1].sr)
  T.eq(night.raids[1].assignments, nil)

  -- The assignments come next, for two raids: the loot stays, the raids they name are added.
  T.truthy(select(2, I.load(fixtureText("night-assignments"))))
  night = GuildGolemDB.nights.efgh6789
  local byZone = {}
  for _, raid in ipairs(night.raids) do byZone[raid.zone] = raid end
  local lootRaid = byZone[ns.Import.read(fixtureText("night-loot")).raids[1].zone]
  T.truthy(lootRaid.loot, "the loot is still there")
  T.truthy(lootRaid.assignments, "and now the assignments")
  T.truthy(#night.raids >= 2)

  -- The whole night replaces what it carries, and drops the raids it doesn't list.
  T.truthy(select(2, I.load(fixtureText("night"))))
  night = GuildGolemDB.nights.efgh6789
  T.eq(#night.raids, 3)
  T.eq(night.raids[1].effort.name, "Locked in")
  T.same(night.raids[1].groups, { { 2, 7, 3, 8, 1 }, { 4, 5, 6, 9 } })
  T.eq(night.raids[1].loot.items[1].sr, nil, "the night's loot is the site's priorities, with no reserves")
  T.eq(night.made, 1796843700000)
end)

T.test("an older import never replaces a newer one, but an equal one does, and saving twice changes nothing", function()
  local ns = start()
  local I = ns.Import
  I.load(fixtureText("night"))
  local before = WOW.copy(GuildGolemDB)

  I.load(fixtureText("night"))
  T.same(GuildGolemDB, before, "the same string again")

  -- A loot string made a minute earlier: its loot is older than the night's, so the night's stands.
  local older = fixtureObject("night-loot")
  older.meta.made = older.meta.made - 60000
  older.raids[1].loot.items = { { id = 999999 } }
  T.truthy(select(2, I.load(write(ns, older))))
  local first = GuildGolemDB.nights.efgh6789.raids[1]
  T.eq(first.loot.items[1].id, 288101, "the newer loot stays")

  -- Made later, it replaces the loot of that raid and nothing else of it.
  local newer = fixtureObject("night-loot")
  newer.meta.made = newer.meta.made + 60000
  newer.raids[1].loot.items = { { id = 999999 } }
  T.truthy(select(2, I.load(write(ns, newer))))
  first = GuildGolemDB.nights.efgh6789.raids[1]
  T.eq(first.loot.items[1].id, 999999)
  T.eq(first.effort.name, "Locked in", "the effort is still the night's")
  T.truthy(first.assignments)

  -- Priorities for a raid are replaced the same way.
  I.load(fixtureText("priorities"))
  local priorities = fixtureObject("priorities")
  priorities.meta.made = priorities.meta.made - 1000
  priorities.raids[1].loot.items = { { id = 5 } }
  local _, why = I.load(write(ns, priorities))
  T.eq(why, "older")
  T.eq(GuildGolemDB.priorities[5011].raid.loot.items[1].id, 288101)
end)

T.test("people of one night are joined across imports: names from the newest, characters from all", function()
  local ns = start()
  local I = ns.Import
  I.load(fixtureText("night-loot"))
  local people = GuildGolemDB.nights.efgh6789.people
  local firstPerson
  for _, person in pairs(people) do firstPerson = firstPerson or person end
  local p = firstPerson.p
  local before = #firstPerson.chars

  local more = fixtureObject("night-loot")
  more.meta.made = more.meta.made + 1000
  for _, person in ipairs(more.people) do
    if person.p == p then
      person.name = "Renamed"
      person.chars[#person.chars + 1] = { name = "An Alternate", cls = "mage" }
    end
  end
  I.load(write(ns, more))
  local after = GuildGolemDB.nights.efgh6789.people[p]
  T.eq(after.name, "Renamed")
  T.eq(#after.chars, before + 1)
  T.eq(after.chars[1].name, firstPerson.chars[1].name, "the first character stays the default")
  T.eq(after.chars[#after.chars].name, "An Alternate")
end)

T.test("a string that is refused saves nothing", function()
  local ns = start()
  local before = WOW.copy(GuildGolemDB)
  local broken = fixtureObject("night")
  broken.raids[2].name = nil
  local summary, reason, says = ns.Import.load(write(ns, broken))
  T.eq(summary, nil)
  T.eq(reason, "invalid")
  T.truthy(says:find("raids[2].name", 1, true), says)
  T.same(GuildGolemDB, before)
end)

T.test("saving needs the store ready and writable", function()
  WOW.declareSavedVariables("GuildGolemDB")
  WOW.readSavedFile('GuildGolemDB = { ["schema"] = 9 }\n')
  local ns = WOW.loadAddon("GuildGolem")
  local parsed = ns.Import.read(fixtureText("priorities"))
  local summary, why = ns.Import.save(parsed)
  T.eq(summary, nil)
  T.eq(why, "read-only")
  T.eq(GuildGolemDB.schema, 9)
  T.eq(GuildGolemDB.priorities, nil)

  WOW.reset()
  local bare = {}
  WOW.dofile("GuildGolem/Core/Store.lua", "GuildGolem", bare)
  WOW.dofile("GuildGolem/Core/Import.lua", "GuildGolem", bare)
  T.eq(select(2, bare.Import.save(parsed)), "not-ready")
end)

-- What a reader does ----------------------------------------------------------------------------------------------

T.test("unknown fields are ignored at every depth, and kept out of what is saved", function()
  local ns = start()
  local o = fixtureObject("night")
  o.surprise = { deeper = { 1, 2 } }
  o.meta.later = "x"
  o.guild.crest = "red"
  o.people[1].mood = "fine"
  o.people[1].chars[1].level = 60
  o.raids[1].weather = "rain"
  o.raids[1].effort.tier = 3
  o.raids[1].picks[1].spec = "fire"
  o.raids[1].loot.items[1].tags = { "a" }
  o.raids[1].loot.extra = true
  o.raids[1].assignments[1].lists[1].slots[1].icon = 4
  local p = read(ns, o)
  T.truthy(p)
  T.eq(p.surprise, nil)
  T.eq(p.raids[1].weather, nil)
  T.eq(p.raids[1].loot.items[1].tags, nil)
  T.eq(p.people[1].mood, nil)
  T.eq(p.raids[1].picks[1].spec, nil)
  T.eq(p.raids[1].loot.items[1].id, 288101)
end)

T.test("an unknown enum reads as its default and is never a refusal", function()
  local ns = start()
  local o = fixtureObject("night")
  o.raids[1].lootBy = "auction"
  o.raids[1].effort.expects = { "flask", "scroll", "food" }
  o.meta.from = "pug-lists"
  local p = read(ns, o)
  T.truthy(p, "an unknown from still reads")
  T.eq(p.from, "pug-lists")
  T.eq(p.raids[1].lootBy, nil, "an unknown lootBy is ignored")
  T.same(p.raids[1].effort.expects, { "flask", "food" }, "an unknown expects value is ignored")
  T.eq(p.guild.name, "Molten Raiders")
  T.eq(p.night.handle, "efgh6789")
  T.eq(#p.raids, 3)
  -- It is saved as far as it is known.
  local summary, ok = ns.Import.save(p)
  T.truthy(ok)
  T.eq(#GuildGolemDB.nights.efgh6789.raids, 3)
end)

T.test("an unknown import with parts that are wrong still reads the parts that aren't", function()
  local ns = start()
  local o = fixtureObject("night")
  o.meta.from = "bank"
  o.guild = "not an object"
  o.night = nil
  o.people = { { p = "x" } }
  o.raids = { { name = "No zone needed" }, "not an object", { zone = 5011 } }
  local p = read(ns, o)
  T.truthy(p)
  T.eq(p.guild, nil)
  T.eq(p.night, nil)
  T.eq(#p.raids, 1)
  T.eq(p.raids[1].name, "No zone needed")
  local summary, ok = ns.Import.save(p)
  T.truthy(ok, "nothing but the site's version to keep")
  T.eq(GuildGolemDB.site.version, "0.36.2")
end)

T.test("a person who isn't in people is ignored wherever they appear", function()
  local ns = start()
  local o = fixtureObject("night")
  local raid = o.raids[1]
  raid.picks[#raid.picks + 1] = { p = 99, name = "Nobody Atall" }
  raid.groups[1][#raid.groups[1] + 1] = 77
  raid.bench[#raid.bench + 1] = 88
  raid.loot.items[1].order[1][#raid.loot.items[1].order[1] + 1] = 66
  raid.loot.items[4].order[#raid.loot.items[4].order + 1] = { 55 }
  raid.loot.items[3].hard = 44
  raid.loot.items[2].sr = { { p = 33, plus = 2 }, { p = 1 } }
  raid.assignments[1].lists[1].slots[1].p = { 2, 22 }
  local p = read(ns, o)
  local r = p.raids[1]
  T.eq(#r.picks, 9)
  T.same(r.groups[1], { 2, 7, 3, 8, 1 })
  T.same(r.bench, { 10 })
  T.same(r.loot.items[1].order, { { 1 }, { 2, 3 } })
  T.same(r.loot.items[4].order, { { 5 }, { 9 } }, "a place left empty is dropped")
  T.eq(r.loot.items[3].hard, nil)
  T.same(r.loot.items[2].sr, { { p = 1 } })
  T.same(r.assignments[1].lists[1].slots[1].p, { 2 })
end)

T.test("an optional field of the wrong type is ignored, and null and false read as absent", function()
  local ns = start()
  local o = fixtureObject("night")
  o.meta.officer = "yes"
  o.people[1].rank = 7
  o.people[1].chars[1].cls = 5
  o.people[1].chars[1].guid = "not-a-guid"
  o.raids[1].size = "big"
  o.raids[1].optional = "sometimes"
  o.raids[1].picks[1].cls = {}
  o.raids[1].groups = "none"
  o.raids[1].bench = 4
  o.raids[1].loot.items[1].note = 12
  o.raids[1].loot.items[1].key = false
  o.raids[1].loot.items[2].free = 1
  o.raids[1].loot.items[4].order = "first"
  o.raids[1].assignments[1].lists[1].slots[1].note = false
  o.raids[2].size = 99
  local p = read(ns, o)
  T.truthy(p)
  T.eq(p.officer, nil)
  T.eq(p.people[1].rank, nil)
  T.eq(p.people[1].chars[1].cls, nil)
  T.eq(p.people[1].chars[1].guid, nil)
  T.eq(p.raids[1].size, nil)
  T.eq(p.raids[1].optional, nil)
  T.eq(p.raids[1].picks[1].cls, nil)
  T.eq(p.raids[1].groups, nil)
  T.eq(p.raids[1].bench, nil)
  T.eq(p.raids[1].loot.items[1].note, nil)
  T.eq(p.raids[1].loot.items[1].key, nil)
  T.eq(p.raids[1].loot.items[2].free, nil)
  T.eq(p.raids[1].loot.items[4].order, nil)
  T.eq(p.raids[1].assignments[1].lists[1].slots[1].note, nil)
  T.eq(p.raids[2].size, nil)

  -- null, written out as text since a Lua table cannot hold one.
  local text = fixtureJson("night"):gsub('"note":"Cinderjaw\'s ring"', '"note":null'):gsub('"bench": %[10%]', '"bench": null')
  local q = ns.Import.read(pack(ns, text))
  T.truthy(q)
  T.eq(q.raids[1].loot.items[1].note, nil)
  T.eq(q.raids[1].bench, nil)
end)

T.test("a list may be left out or empty; they read the same", function()
  local ns = start()
  local o = fixtureObject("night")
  o.raids[1].bench = nil
  o.raids[1].groups = {}
  o.raids[1].loot.items[1].order = {}
  o.raids[1].loot.items[1].specs = {}
  o.raids[1].picks = {}
  o.people[10].chars = {}
  local p = read(ns, o)
  T.truthy(p)
  T.eq(p.raids[1].bench, nil)
  T.same(p.raids[1].groups, {})
  T.same(p.raids[1].loot.items[1].order, {})
  T.same(p.raids[1].picks, {})
  T.same(p.people[10].chars, {})
end)

T.test("a required field that is missing or the wrong type refuses the whole string, and names the field", function()
  local ns = start()
  local cases = {
    { "meta.from", function(o) o.meta.from = nil end },
    { "meta.from", function(o) o.meta.from = 4 end },
    { "meta.made", function(o) o.meta.made = "now" end },
    { "meta.made", function(o) o.meta.made = 0 end },
    { "meta.site", function(o) o.meta.site = nil end },
    { "meta.latest", function(o) o.meta.latest = false end },
    { "guild", function(o) o.guild = nil end },
    { "guild.handle", function(o) o.guild.handle = nil end },
    { "guild.name", function(o) o.guild.name = "" end },
    { "night", function(o) o.night = nil end },
    { "night.startsAt", function(o) o.night.startsAt = "soon" end },
    { "people", function(o) o.people = nil end },
    { "people[2].p", function(o) o.people[2].p = 0 end },
    { "people[3].name", function(o) o.people[3].name = nil end },
    { "people[1].chars", function(o) o.people[1].chars = nil end },
    { "people[1].chars[1].name", function(o) o.people[1].chars[1].name = nil end },
    { "raids", function(o) o.raids = nil end },
    { "raids[1].name", function(o) o.raids[1].name = nil end },
    { "raids[3].name", function(o) o.raids[3].name = 12 end },
    { "raids[1].effort.name", function(o) o.raids[1].effort.name = nil end },
    { "raids[1].picks[1].p", function(o) o.raids[1].picks[1].p = "1" end },
    { "raids[1].loot.items[2].id", function(o) o.raids[1].loot.items[2].id = nil end },
    { "raids[1].loot.items", function(o) o.raids[1].loot.items = nil end },
    { "raids[1].assignments[1].boss", function(o) o.raids[1].assignments[1].boss = nil end },
    { "raids[1].assignments[1].lists[1].slots[1].label", function(o) o.raids[1].assignments[1].lists[1].slots[1].label = nil end },
    { "raids[1].assignments[1].lists[1].slots[1].p", function(o) o.raids[1].assignments[1].lists[1].slots[1].p = nil end },
  }
  for _, case in ipairs(cases) do
    local o = fixtureObject("night")
    case[2](o)
    local parsed, reason, says, path = ns.Import.read(write(ns, o))
    T.eq(parsed, nil, case[1])
    T.eq(reason, "invalid", case[1])
    T.eq(path:sub(1, #case[1]), case[1], "names the field: " .. tostring(path) .. " for " .. case[1])
    T.truthy(says:find(path, 1, true), says)
  end
  -- Priorities need a zone and loot in the raid; the other imports don't need a zone.
  local priorities = fixtureObject("priorities")
  priorities.raids[1].zone = nil
  T.eq(select(4, ns.Import.read(write(ns, priorities))), "raids[1].zone")
  priorities = fixtureObject("priorities")
  priorities.raids[1].loot = nil
  T.eq(select(4, ns.Import.read(write(ns, priorities))), "raids[1].loot")
  local loot = fixtureObject("night-loot")
  loot.raids[1].zone = nil
  T.truthy(ns.Import.read(write(ns, loot)), "a night's open raid has no zone")
  local assignments = fixtureObject("night-assignments")
  assignments.night = nil
  T.eq(select(4, ns.Import.read(write(ns, assignments))), "night")
end)

T.test("a meta that is an empty list reads as an empty object, and is refused for what it lacks", function()
  local ns = start()
  local text = pack(ns, '{"v":1,"kind":"import","meta":[]}')
  local parsed, reason, _, path = ns.Import.read(text)
  T.eq(parsed, nil)
  T.eq(reason, "invalid")
  T.eq(path, "meta.from")
end)

T.test("the codec's refusals come through with the words to show", function()
  local ns = start()
  local export = assert(WOW.readFile("contract/fixtures/export-pugs.gg1.txt"))
  local parsed, reason, says = ns.Import.read(export)
  T.eq(parsed, nil)
  T.eq(reason, "wrong-way")
  T.eq(says, "That is an export; paste it on the site.")
  T.eq(select(2, ns.Import.read("hello")), "not-ours")
  T.eq(select(2, ns.Import.read(pack(ns, '{"v":2,"kind":"import","meta":{}}'))), "newer")
  T.eq(select(3, ns.Import.read(pack(ns, '{"v":2,"kind":"import","meta":{}}'))), "Update the addon")
  local summary, why, words = ns.Import.load("GG1:eJwDAAAAAAE=")
  T.eq(summary, nil)
  T.truthy(words)
end)

T.test("site text is made safe to draw: a | is doubled", function()
  local ns = start()
  T.eq(ns.Import.escape("plain"), "plain")
  T.eq(ns.Import.escape("|cffff0000red|r"), "||cffff0000red||r")
  T.eq(ns.Import.escape("a||b"), "a||||b")
  T.eq(ns.Import.escape(12), 12)
end)
