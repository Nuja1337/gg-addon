-- Reads the site's four imports into the saved variables (contract/README.md, "Imports" and "What a reader does"):
--   priorities, night-loot, night-assignments and night.
--
--   Import.parse(object)        an import object (what Codec.read gave) as clean data, or nil and what is wrong
--   Import.read(text)           Codec.read, then parse: the data, or nil, a reason and the words to show
--   Import.save(parsed)         puts it in GuildGolemDB (Store.db()), and returns a summary
--   Import.load(text)           read then save
--   Import.summary(parsed)      the counts a preview shows before anything is saved
--   Import.escape(text)         site text made safe to draw: | becomes ||
--
-- The rules the contract gives a reader, all kept here:
--   * A required field that is missing or the wrong type refuses the whole string and names the field. Nothing in it
--     is used.
--   * An optional field of the wrong type is ignored. A field it doesn't know is ignored, at every depth.
--   * An enum value it doesn't know reads as its default: an unknown `lootBy` or `expects` is dropped, and an
--     unknown `from` still reads the parts it knows.
--   * A person id (in a pick, a group, the bench, a place in line, a reserve, a slot) that is not in `people` is
--     ignored.
--   * `null` reads as absent, `false` for a flag that is only ever true reads as absent, and an empty list is the
--     same as none.
--
-- What is stored (see Store.lua for the rest). Each import is kept as clean data:
--   import = { from, made, site, latest, officer, guild = { handle, name }, night = { handle, title, startsAt },
--              people = { [p] = { p, name, rank, chars = { { name, cls, guid }, ... } } },
--              raids = { { zone, name, size, lootBy, effort = { name, expects }, optional, picks = { { p, name,
--              cls, guid } }, groups = { { p, ... }, ... }, bench = { p, ... }, loot = { items = { { id, order, sr,
--              key, specs, free, hard, note } } }, assignments = { { encounter, boss, lists = { { name,
--              slots = { { label, p, note } } } } } } } } }
-- Priorities are kept for each raid by its zone: db.priorities[zone] = { made, officer, guild, people, raid }.
-- A night is kept by its handle: db.nights[handle] = { handle, title, startsAt, made, people, raids, parts }, where
-- the imports of one night are combined as Import.save explains.
--
-- Plain Lua, no game calls.

local ADDON, ns = ...

local Import = {}
ns.Import = Import

local Codec = ns.Codec
local Store = ns.Store

local floor, abs = math.floor, math.abs
local type, rawget, next, pairs, ipairs = type, rawget, next, pairs, ipairs

local KNOWN_FROM = { priorities = true, ["night-loot"] = true, ["night-assignments"] = true, night = true }
local LOOT_BY = { soft = true, hard = true, system = true }
local EXPECTS = { flask = true, food = true, weapon = true, potions = true, engineering = true, misc = true }

local MAX_NUMBER = 1e14

-- A refusal is raised as a table and caught in Import.parse.
local function refuse(path, why)
  -- Fields of the top level are named without the $ the readers use for the root: "guild.handle".
  error({ path = (path:gsub("^%$%.", "")), why = why }, 0)
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[copy(k)] = copy(v) end
  return out
end

-- Reading values -------------------------------------------------------------------------------------------------

local function isInt(v, min)
  return type(v) == "number" and v == floor(v) and abs(v) < MAX_NUMBER and v >= (min or 0)
end

-- A table that came from a JSON array. json.lua makes no difference between an empty array and an empty object, so
-- an empty table is both; an object has no [1].
local function isList(t)
  return type(t) == "table" and (rawget(t, 1) ~= nil or next(t) == nil)
end

local function isObject(t)
  return type(t) == "table" and rawget(t, 1) == nil
end

local GUID_FORM = "^Player%-%d+%-%x+$"

local function guid(v)
  if type(v) == "string" and v:find(GUID_FORM) then return v end
  return nil
end

-- A required field.
local function reqInt(obj, key, path, min)
  local v = obj[key]
  if v == nil then refuse(path .. "." .. key, "is required") end
  if not isInt(v, min) then refuse(path .. "." .. key, "is not a whole number") end
  return v
end

local function reqStr(obj, key, path)
  local v = obj[key]
  if v == nil then refuse(path .. "." .. key, "is required") end
  if type(v) ~= "string" or v == "" then refuse(path .. "." .. key, "is not text") end
  return v
end

local function reqList(obj, key, path)
  local v = obj[key]
  if v == nil then refuse(path .. "." .. key, "is required") end
  if not isList(v) then refuse(path .. "." .. key, "is not a list") end
  return v
end

local function reqObject(obj, key, path)
  local v = obj[key]
  if v == nil then refuse(path .. "." .. key, "is required") end
  if not isObject(v) then refuse(path .. "." .. key, "is not an object") end
  return v
end

-- An optional field: nil when absent or the wrong type.
local function optInt(obj, key, min)
  local v = obj[key]
  if isInt(v, min) then return v end
  return nil
end

local function optStr(obj, key)
  local v = obj[key]
  if type(v) == "string" then return v end
  return nil
end

local function optFlag(obj, key)
  if obj[key] == true then return true end
  return nil
end

-- Parts ---------------------------------------------------------------------------------------------------------------

local function readPeople(list)
  local people = {}
  for i, entry in ipairs(list) do
    local path = "people[" .. i .. "]"
    if not isObject(entry) then refuse(path, "is not an object") end
    local p = reqInt(entry, "p", path, 1)
    local person = { p = p, name = reqStr(entry, "name", path), rank = optStr(entry, "rank"), chars = {} }
    for j, ch in ipairs(reqList(entry, "chars", path)) do
      local cpath = path .. ".chars[" .. j .. "]"
      if not isObject(ch) then refuse(cpath, "is not an object") end
      person.chars[#person.chars + 1] = { name = reqStr(ch, "name", cpath), cls = optStr(ch, "cls"), guid = guid(ch.guid) }
    end
    people[p] = person
  end
  return people
end

-- A list of person ids, with the ones that aren't in `people` left out.
local function personIds(list, people)
  local out = {}
  if not isList(list) then return out end
  for _, p in ipairs(list) do
    if isInt(p, 1) and people[p] then out[#out + 1] = p end
  end
  return out
end

local function readEffort(raw, path)
  if not isObject(raw) then return nil end
  local effort = { name = reqStr(raw, "name", path), expects = {} }
  for _, e in ipairs(reqList(raw, "expects", path)) do
    if type(e) == "string" and EXPECTS[e] then effort.expects[#effort.expects + 1] = e end
  end
  return effort
end

local function readPicks(raw, people, path)
  if not isList(raw) then return nil end
  local picks = {}
  for i, entry in ipairs(raw) do
    local epath = path .. "[" .. i .. "]"
    if not isObject(entry) then refuse(epath, "is not an object") end
    local p = reqInt(entry, "p", epath, 1)
    local name = reqStr(entry, "name", epath)
    if people[p] then picks[#picks + 1] = { p = p, name = name, cls = optStr(entry, "cls"), guid = guid(entry.guid) } end
  end
  return picks
end

local function readGroups(raw, people)
  if not isList(raw) then return nil end
  local groups = {}
  for i, group in ipairs(raw) do
    if i > 8 then break end
    groups[i] = personIds(group, people)
  end
  return groups
end

local function readItem(raw, people, path)
  if not isObject(raw) then refuse(path, "is not an object") end
  local item = { id = reqInt(raw, "id", path, 1) }

  if isList(raw.order) then
    item.order = {}
    for _, place in ipairs(raw.order) do
      local ids = personIds(place, people)
      if #ids > 0 then item.order[#item.order + 1] = ids end
    end
  end
  if isList(raw.sr) then
    item.sr = {}
    for _, entry in ipairs(raw.sr) do
      if isObject(entry) and isInt(entry.p, 1) and people[entry.p] then
        item.sr[#item.sr + 1] = { p = entry.p, plus = optInt(entry, "plus", 0) }
      end
    end
  end
  item.key = optFlag(raw, "key")
  item.free = optFlag(raw, "free")
  item.note = optStr(raw, "note")
  -- The person's id, or 0 for the guild's.
  local hard = optInt(raw, "hard", 0)
  if hard and (hard == 0 or people[hard]) then item.hard = hard end
  if isList(raw.specs) then
    item.specs = {}
    for _, tier in ipairs(raw.specs) do
      local names = {}
      if isList(tier) then
        for _, spec in ipairs(tier) do
          if type(spec) == "string" and spec:find("^[a-z]+:%d$") then names[#names + 1] = spec end
        end
      end
      if #names > 0 then item.specs[#item.specs + 1] = names end
    end
  end
  return item
end

local function readLoot(raw, people, path)
  if not isObject(raw) then return nil end
  local loot = { items = {} }
  for i, entry in ipairs(reqList(raw, "items", path)) do
    loot.items[#loot.items + 1] = readItem(entry, people, path .. ".items[" .. i .. "]")
  end
  return loot
end

local function readAssignments(raw, people, path)
  if not isList(raw) then return nil end
  local out = {}
  for i, entry in ipairs(raw) do
    local apath = path .. "[" .. i .. "]"
    if not isObject(entry) then refuse(apath, "is not an object") end
    local assignment = { encounter = optInt(entry, "encounter", 1), boss = reqStr(entry, "boss", apath), lists = {} }
    for j, list in ipairs(reqList(entry, "lists", apath)) do
      local lpath = apath .. ".lists[" .. j .. "]"
      if not isObject(list) then refuse(lpath, "is not an object") end
      local out_list = { name = reqStr(list, "name", lpath), slots = {} }
      for k, slot in ipairs(reqList(list, "slots", lpath)) do
        local spath = lpath .. ".slots[" .. k .. "]"
        if not isObject(slot) then refuse(spath, "is not an object") end
        out_list.slots[#out_list.slots + 1] = {
          label = reqStr(slot, "label", spath),
          p = personIds(reqList(slot, "p", spath), people),
          note = optStr(slot, "note"),
        }
      end
      assignment.lists[#assignment.lists + 1] = out_list
    end
    out[#out + 1] = assignment
  end
  return out
end

local function readRaid(raw, people, from, path)
  if not isObject(raw) then refuse(path, "is not an object") end
  local raid = {}
  if from == "priorities" then
    raid.zone = reqInt(raw, "zone", path, 1)
  else
    raid.zone = optInt(raw, "zone", 1)
  end
  raid.name = reqStr(raw, "name", path)
  local size = optInt(raw, "size", 1)
  if size and size <= 40 then raid.size = size end
  if type(raw.lootBy) == "string" and LOOT_BY[raw.lootBy] then raid.lootBy = raw.lootBy end
  raid.effort = readEffort(raw.effort, path .. ".effort")
  raid.optional = optFlag(raw, "optional")
  raid.picks = readPicks(raw.picks, people, path .. ".picks")
  raid.groups = readGroups(raw.groups, people)
  if isList(raw.bench) then raid.bench = personIds(raw.bench, people) end

  local needsLoot = from == "priorities" or from == "night-loot"
  if needsLoot then
    reqObject(raw, "loot", path)
  end
  raid.loot = readLoot(raw.loot, people, path .. ".loot")
  raid.assignments = readAssignments(raw.assignments, people, path .. ".assignments")
  return raid
end

-- Parsing ----------------------------------------------------------------------------------------------------------

-- A part of the string. For a `from` the addon knows, a part that is wrong refuses the string. For one it doesn't
-- know, the parts it can read are read and the others skipped.
local function part(known, fn, ...)
  if known then return fn(...) end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

local function readGuild(obj)
  local guild = reqObject(obj, "guild", "$")
  return { handle = reqStr(guild, "handle", "guild"), name = reqStr(guild, "name", "guild") }
end

local function readNight(obj)
  local night = reqObject(obj, "night", "$")
  return {
    handle = reqStr(night, "handle", "night"),
    title = reqStr(night, "title", "night"),
    startsAt = reqInt(night, "startsAt", "night", 1),
  }
end

local function readRaids(obj, people, from, known)
  local raids = {}
  local raw = obj.raids
  if known then raw = reqList(obj, "raids", "$") elseif not isList(raw) then raw = {} end
  for i, entry in ipairs(raw) do
    local raid = part(known, readRaid, entry, people, from, "raids[" .. i .. "]")
    if raid then raids[#raids + 1] = raid end
  end
  return raids
end

local function parseInner(obj)
  local meta = obj.meta
  local from = reqStr(meta, "from", "meta")
  local known = KNOWN_FROM[from] == true
  local parsed = {
    from = from,
    made = reqInt(meta, "made", "meta", 1),
    site = reqStr(meta, "site", "meta"),
    latest = reqStr(meta, "latest", "meta"),
    officer = optFlag(meta, "officer"),
  }
  parsed.guild = part(known, readGuild, obj)
  -- A priorities string has no night. If one carries it anyway, it is not read.
  if from ~= "priorities" then parsed.night = part(known, readNight, obj) end
  parsed.people = part(known, function() return readPeople(reqList(obj, "people", "$")) end) or {}
  parsed.raids = readRaids(obj, parsed.people, from, known)
  return parsed
end

-- An import object (what Codec.read gives for an import) as clean data. Returns it, or nil and the path of the field
-- that refused it and why.
function Import.parse(obj)
  if type(obj) ~= "table" or not isObject(obj.meta) then return nil, "meta", "is required" end
  local ok, result = pcall(parseInner, obj)
  if ok then return result end
  if type(result) == "table" and result.path then return nil, result.path, result.why end
  -- A mistake in this file, not in the string.
  return nil, "$", "could not be read (" .. tostring(result) .. ")"
end

Import.SAYS_INVALID = "The string is damaged: %s %s. Copy it again."

-- A string as clean data. Returns it, or nil, a reason (the codec's, or "invalid" when a field refused it) and the
-- words to show the player.
function Import.read(text)
  local obj, reason, says = Codec.read(text, "addon")
  if not obj then return nil, reason, says end
  local parsed, path, why = Import.parse(obj)
  if not parsed then return nil, "invalid", string.format(Import.SAYS_INVALID, path, why), path end
  return parsed
end

-- The counts a preview shows.
function Import.summary(parsed)
  local people = 0
  for _ in pairs(parsed.people) do people = people + 1 end
  local items, assignments = 0, 0
  for _, raid in ipairs(parsed.raids) do
    if raid.loot then items = items + #raid.loot.items end
    if raid.assignments then assignments = assignments + #raid.assignments end
  end
  return {
    from = parsed.from,
    guild = parsed.guild and parsed.guild.name,
    night = parsed.night and parsed.night.title,
    raids = #parsed.raids,
    people = people,
    items = items,
    assignments = assignments,
    officer = parsed.officer == true,
  }
end

-- Site text drawn in a window or a tooltip: a | would start a color, a link or a texture, so it is doubled.
function Import.escape(text)
  if type(text) ~= "string" then return text end
  return (text:gsub("|", "||"))
end

-- Saving ---------------------------------------------------------------------------------------------------------

local PARTS = { "name", "size", "lootBy", "effort", "optional", "picks", "groups", "bench", "loot", "assignments" }

-- Which parts of a raid each import replaces. A part an import carries replaces the saved one if the import is not
-- older than the saved one. A `night` carries them all: a part it leaves out is a part the site has none of, so it
-- clears the saved one.
local REPLACES = {
  ["night-loot"] = { "name", "size", "lootBy", "loot" },
  ["night-assignments"] = { "name", "assignments" },
  night = PARTS,
}

local function raidKey(raid)
  if raid.zone then return "z" .. string.format("%.0f", raid.zone) end
  return "n" .. raid.name
end

-- People of one night, joined: a person's name and rank come from the newest import that names them, and their
-- characters are every character any import named, in the order first met (the first stays the default). The
-- contract doesn't say how the imports of one night combine; this is the addon's choice.
local function mergePeople(into, from)
  for p, person in pairs(from) do
    local have = into[p]
    if not have then
      into[p] = copy(person)
    else
      have.name = person.name
      have.rank = person.rank or have.rank
      for _, ch in ipairs(person.chars) do
        local found
        for _, known in ipairs(have.chars) do
          if known.name == ch.name then found = known end
        end
        if found then
          found.cls = ch.cls or found.cls
          found.guid = ch.guid or found.guid
        else
          have.chars[#have.chars + 1] = copy(ch)
        end
      end
    end
  end
end

local function newest(stamps)
  local most = 0
  for _, made in pairs(stamps) do
    if made > most then most = made end
  end
  return most
end

local function saveNight(db, parsed)
  local handle = parsed.night.handle
  local night = db.nights[handle]
  if not night then
    night = { handle = handle, title = parsed.night.title, startsAt = parsed.night.startsAt, made = 0, people = {}, raids = {}, parts = {} }
    db.nights[handle] = night
  end
  if parsed.made >= night.made then
    night.title, night.startsAt, night.made = parsed.night.title, parsed.night.startsAt, parsed.made
  end
  mergePeople(night.people, parsed.people)

  local replaces = REPLACES[parsed.from] or PARTS
  local clears = parsed.from == "night"
  local listed = {}
  for _, raid in ipairs(parsed.raids) do
    local key = raidKey(raid)
    listed[key] = true
    local have
    for _, existing in ipairs(night.raids) do
      if raidKey(existing) == key then have = existing end
    end
    if not have then
      have = { zone = raid.zone, name = raid.name }
      night.raids[#night.raids + 1] = have
    end
    local stamps = night.parts[key]
    if not stamps then
      stamps = {}
      night.parts[key] = stamps
    end
    for _, name in ipairs(replaces) do
      local stamped = stamps[name]
      if (raid[name] ~= nil or clears) and (stamped == nil or parsed.made >= stamped) then
        have[name] = copy(raid[name])
        stamps[name] = parsed.made
      end
    end
  end

  -- A whole night drops the raids it doesn't list, unless something newer put them there.
  if clears then
    local kept = {}
    for _, raid in ipairs(night.raids) do
      local key = raidKey(raid)
      if listed[key] or newest(night.parts[key] or {}) > parsed.made then
        kept[#kept + 1] = raid
      else
        night.parts[key] = nil
      end
    end
    night.raids = kept
  end
end

-- Puts a parsed import in the saved variables. Returns the summary and `true`, or nil and why: "read-only" when the
-- saved data is from a newer addon, "not-ready" before Store.init, or "older" when the saved copy of what this
-- import carries is newer.
function Import.save(parsed)
  if Store.readOnly() then return nil, "read-only" end
  local db = Store.db()
  if not db then return nil, "not-ready" end

  local summary = Import.summary(parsed)
  local saved = false

  if parsed.guild then db.guild = copy(parsed.guild) end
  local site = db.site
  if not site or parsed.made >= (site.made or 0) then
    db.site = { version = parsed.site, latest = parsed.latest, made = parsed.made }
  end

  if parsed.from == "priorities" then
    saved = #parsed.raids == 0
    for _, raid in ipairs(parsed.raids) do
      local have = db.priorities[raid.zone]
      if not have or parsed.made >= have.made then
        db.priorities[raid.zone] = {
          made = parsed.made,
          officer = parsed.officer,
          guild = copy(parsed.guild),
          people = copy(parsed.people),
          raid = copy(raid),
        }
        saved = true
      end
    end
  elseif parsed.night then
    saveNight(db, parsed)
    saved = true
  else
    -- An import of a kind this addon doesn't know, with no night: only the guild and the site's version are kept.
    saved = true
  end

  if not saved then return nil, "older" end
  return summary, true
end

-- Reads a string and saves it. Returns the summary and true, or nil, a reason and the words to show.
function Import.load(text)
  local parsed, reason, says = Import.read(text)
  if not parsed then return nil, reason, says end
  local summary, why = Import.save(parsed)
  if not summary then return nil, why, "Nothing was saved (" .. tostring(why) .. ")." end
  return summary, true
end
