-- Makes the export string: what Attendance.lua recorded since the last export (or all of it), the pugs, and the meta the
-- contract wants, kept under the writers' size limits and packed by Core/Codec (contract/README.md, "Exports" and
-- "Size"). The result goes into the Store's outbox, which nothing drops until the officer says it was pasted.
--
--   Export.make(opts)      builds, fits and stores an export. opts.all repeats everything the addon holds; opts.limit
--                          changes the text limit (for tests). Gives { entries, snapshots, raids, pugs, characters },
--                          or nil, a reason and the words to show
--   Export.build(all)      the export object before it is fitted, and what it covers; or nil and a reason
--   Export.fit(object, limit)   the object as a list of { object, text }, each under both limits (the contract's `fit`,
--                          test/contract-lib.mjs is the reference)
--   Export.id(madeMs)      a new meta.id
--
-- Loot is not in M1 (docs/PLAN.md, M4), so `loot` is left out. An export marks what it covered (a raid's `sent`), so the
-- next one holds only what is new; if a string is lost the contract's rules make a repeat harmless, and `all` makes one.
-- Plain Lua: the clock, the build and the player come from ns.Client.

local ADDON, ns = ...

local Export = {}
ns.Export = Export

local Codec = ns.Codec
local floor, ceil = math.floor, math.ceil
local format = string.format

Export.SAYS = {
  nothing = "Nothing new to export. Type /gg export all to export everything again.",
  ["read-only"] = "The saved data is from a newer addon, so nothing can be kept. Update the addon.",
  ["not-ready"] = "The addon has not finished loading. Try again in a moment.",
  ["no-player"] = "The game did not say who you are, so the export cannot name its recorder.",
  ["no-build"] = "The game did not say its version or realm, so the export cannot be made.",
  ["no-clock"] = "The game did not say the server's time, so the export cannot be dated.",
  ["too-big"] = "The export could not be made small enough.",
}

local function client() return ns.Client end

-- The meta.id -----------------------------------------------------------------------------------------------------------

local ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"

local function base36(n)
  if n < 1 then return "0" end
  local out = ""
  while n >= 1 do
    local d = n % 36
    out = ALPHABET:sub(d + 1, d + 1) .. out
    n = floor(n / 36)
  end
  return out
end

local counter = 0

-- Eight hex digits that differ between two presses of Export, from a small generator seeded with the time, the uptime, the
-- player and a count. The game's math.random is left alone: another addon may be relying on its sequence. Floats throughout,
-- since the numbers pass 2^31.
local function randomHex(seedText)
  local x = 2166136261.0
  for i = 1, #seedText do x = (x * 31.0 + seedText:byte(i)) % 4294967296.0 end
  for _ = 1, 3 do x = (x * 1664525.0 + 1013904223.0) % 4294967296.0 end
  local out = ""
  for _ = 1, 8 do
    local d = x % 16
    out = ("0123456789abcdef"):sub(d + 1, d + 1) .. out
    x = floor(x / 16)
  end
  return out
end

-- `<made in base 36>.<8 random hex digits>`, like mgq1k2zt.4fa91c07 (contract/README.md, `meta`).
function Export.id(madeMs)
  counter = counter + 1
  local c = client()
  local seed = (c.player().guid or "") .. format("%.0f", madeMs) .. format("%.3f", c.uptime() or 0) .. format("%d", counter)
  return base36(madeMs) .. "." .. randomHex(seed)
end

-- What goes in ----------------------------------------------------------------------------------------------------------

-- Everyone the imports name: by GUID and by full name (an import may know a character's name before its GUID). Nil when
-- nothing was imported, since then there is no roster to tell a pug from.
local function rosterIndex()
  local db = ns.Store.db()
  local byGuid, byName, any = {}, {}, false
  local function add(people)
    for _, person in pairs(people or {}) do
      for _, ch in ipairs(person.chars or {}) do
        any = true
        if ch.guid then byGuid[ch.guid] = true end
        if ch.name then byName[ch.name] = true end
      end
    end
  end
  for _, night in pairs(db.nights or {}) do add(night.people) end
  for _, entry in pairs(db.priorities or {}) do add(entry.people) end
  if not any then return nil end
  return { guid = byGuid, name = byName }
end

-- Players in the snapshots who are not on the imported roster and are not the recorder, each once, with the time they were
-- first seen.
local function pugsOf(entries, byGuid)
  local roster = rosterIndex()
  if not roster then return {} end
  local pugs, seen = {}, {}
  for _, entry in ipairs(entries) do
    for _, snap in ipairs(entry.snapshots) do
      for _, m in ipairs(snap.members) do
        if not seen[m.guid] and m.guid ~= byGuid and not roster.guid[m.guid] and not roster.name[m.name] then
          seen[m.guid] = true
          local pug = { guid = m.guid, name = m.name, at = snap.at }
          if m.cls then pug.cls = m.cls end
          pugs[#pugs + 1] = pug
        end
      end
    end
  end
  return pugs
end

local function meta(madeMs)
  local c = client()
  local build, me = c.build(), c.player()
  if not me.guid or not me.name then return nil, "no-player" end
  if not (build.version and build.build and build.interface and build.locale and build.realm) then return nil, "no-build" end
  local db = ns.Store.db()
  local m = {
    id = Export.id(madeMs),
    made = madeMs,
    addon = ns.version or c.addonVersion(),
    client = { version = build.version, build = build.build, interface = build.interface, locale = build.locale },
    by = { guid = me.guid, name = me.name },
    realm = build.realm,
  }
  local guild = c.guild()
  if guild then m.guildName = guild.name end
  if db.guild and db.guild.handle then m.guild = db.guild.handle end
  -- The night of the import last given: the one made most recently. A hint only.
  local newest
  for handle, night in pairs(db.nights or {}) do
    if not newest or (night.made or 0) > (newest.made or 0) or ((night.made or 0) == (newest.made or 0) and handle < newest.handle) then
      newest = night
    end
  end
  if newest then m.night = newest.handle end
  m.skew = c.skewMs()
  return m
end

-- The export before it is fitted, and what it covers: { object, marks = { { raid, count } }, snapshots }. Gives nil and a
-- reason ("nothing" and the others in Export.SAYS) when there is nothing to make or it cannot be dated or signed.
function Export.build(all)
  local store = ns.Store
  if not store.db() then return nil, "not-ready" end
  local madeMs = client().serverTimeMs()
  if not madeMs then return nil, "no-clock" end

  local attendance, marks, snapshots = {}, {}, 0
  for _, raid in ipairs(store.raids() or {}) do
    local from = all and 0 or (raid.sent or 0)
    local total = #raid.snapshots
    if total > from then
      -- Benched people who never came into the group are on `standby`; the ones who did are in the snapshots already.
      local inside = {}
      for _, snap in ipairs(raid.snapshots) do
        for _, m in ipairs(snap.members) do inside[m.guid] = true end
      end
      local standby = {}
      for _, p in ipairs(raid.standby or {}) do
        if not inside[p.guid] then standby[#standby + 1] = { guid = p.guid, name = p.name, cls = p.cls } end
      end
      local list = {}
      for i = from + 1, total do list[#list + 1] = raid.snapshots[i] end
      attendance[#attendance + 1] = {
        id = raid.id, zone = raid.zone, name = raid.name, difficulty = raid.difficulty, size = raid.size,
        night = raid.night, leader = raid.leader, lockout = raid.lockout,
        standby = #standby > 0 and standby or nil,
        snapshots = list,
      }
      marks[#marks + 1] = { raid = raid, count = total }
      snapshots = snapshots + #list
    end
  end
  if #attendance == 0 then return nil, "nothing" end

  local m, why = meta(madeMs)
  if not m then return nil, why end
  local object = { v = Codec.VERSION, kind = "export", meta = m, attendance = attendance }
  local pugs = pugsOf(attendance, m.by.guid)
  if #pugs > 0 then object.pugs = pugs end
  return { object = object, marks = marks, snapshots = snapshots }
end

-- Fitting ---------------------------------------------------------------------------------------------------------------------

-- Whether the object, written, is under both limits; and its string if so. The JSON is measured before anything is packed,
-- since packing is the slow part.
local function sized(object, limit)
  local text = Codec.json(object)
  if not text or #text > Codec.WRITE_JSON then return false end
  local packed = Codec.pack(text)
  if not packed or #packed > limit then return false end
  return true, packed
end

local function copyTable(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function sameSnapshotState(a, b) return ns.Attendance.sameState(a, b) end

-- Each raid with the interval snapshots `keep(snapshot, the one kept before it, how many intervals came before)` says to
-- keep; every other kind stays.
local function thin(base, keep)
  local out = {}
  for _, r in ipairs(base) do
    local snapshots, interval = {}, 0
    for _, s in ipairs(r.snapshots) do
      if s.why ~= "interval" then
        snapshots[#snapshots + 1] = s
      else
        if keep(s, snapshots[#snapshots], interval) then snapshots[#snapshots + 1] = s end
        interval = interval + 1
      end
    end
    local entry = copyTable(r)
    entry.snapshots = snapshots
    out[#out + 1] = entry
  end
  return out
end

-- The contract's `fit` (README, "Size"; contract-lib.mjs `fit` is the reference). In order, until every string fits: leave
-- out each interval snapshot that matches the one before it; keep every fourth of the rest; make a string for each raid
-- and one for the pugs; keep every sixteenth instead; cut what is still too big in halves by snapshots. Halves of one raid
-- share its id. The other kinds of snapshot and `standby` are never left out. Gives a list of { object, text }.
function Export.fit(object, limit)
  limit = limit or Codec.WRITE_TEXT
  local ok, text = sized(object, limit)
  if ok then return { { object = object, text = text } } end

  local rest = { v = object.v, kind = object.kind, meta = object.meta }
  local loot, pugs = object.loot, object.pugs
  local function withRaids(attendance)
    local o = copyTable(rest)
    if #attendance > 0 then o.attendance = attendance end
    o.loot, o.pugs = loot, pugs
    return o
  end
  local function pieces(attendance)
    local list = {}
    for _, r in ipairs(attendance) do
      local o = copyTable(rest)
      o.attendance = { r }
      list[#list + 1] = o
    end
    if loot or pugs then
      local o = copyTable(rest)
      o.loot, o.pugs = loot, pugs
      list[#list + 1] = o
    end
    return list
  end
  local function numbered(list)
    for i, o in ipairs(list) do
      local m = copyTable(o.meta)
      m.id = object.meta.id .. "." .. format("%d", i)
      o.meta = m
    end
    return list
  end

  local deduped = thin(object.attendance or {}, function(s, before) return before == nil or not sameSnapshotState(s, before) end)
  local candidate = withRaids(deduped)
  ok, text = sized(candidate, limit)
  if ok then return { { object = candidate, text = text } } end

  local quarter = thin(deduped, function(_, _, i) return i % 4 == 0 end)
  candidate = withRaids(quarter)
  ok, text = sized(candidate, limit)
  if ok then return { { object = candidate, text = text } } end

  local sixteenth = thin(deduped, function(_, _, i) return i % 16 == 0 end)
  for _, attendance in ipairs({ quarter, sixteenth }) do
    local list = numbered(pieces(attendance))
    local out = {}
    for _, o in ipairs(list) do
      local fits, packed = sized(o, limit)
      if not fits then
        out = nil
        break
      end
      out[#out + 1] = { object = o, text = packed }
    end
    if out then return out end
  end

  local function halves(o)
    local fits, packed = sized(o, limit)
    if fits then return { { object = o, text = packed } } end
    local r = o.attendance and o.attendance[1]
    if r and #r.snapshots > 1 then
      local at = ceil(#r.snapshots / 2)
      local first, second = {}, {}
      for i, s in ipairs(r.snapshots) do
        if i <= at then first[#first + 1] = s else second[#second + 1] = s end
      end
      local a, b = copyTable(o), copyTable(o)
      local ra, rb = copyTable(r), copyTable(r)
      ra.snapshots, rb.snapshots = first, second
      a.attendance, b.attendance = { ra }, { rb }
      local out = halves(a)
      for _, item in ipairs(halves(b)) do out[#out + 1] = item end
      return out
    end
    if o.loot and #o.loot > 1 then
      local at = ceil(#o.loot / 2)
      local first, second = {}, {}
      for i, award in ipairs(o.loot) do
        if i <= at then first[#first + 1] = award else second[#second + 1] = award end
      end
      local a, b = copyTable(o), copyTable(o)
      a.loot, b.loot, b.pugs = first, second, nil
      local out = halves(a)
      for _, item in ipairs(halves(b)) do out[#out + 1] = item end
      return out
    end
    -- Nothing left to cut: it goes out as it is (and the caller finds it over the limit).
    return { { object = o, text = nil } }
  end

  local cut = {}
  for _, o in ipairs(pieces(sixteenth)) do
    for _, item in ipairs(halves(o)) do cut[#cut + 1] = item end
  end
  local objects = {}
  for i, item in ipairs(cut) do objects[i] = item.object end
  numbered(objects)
  for _, item in ipairs(cut) do
    local fits, packed = sized(item.object, limit)
    item.text = fits and packed or nil
  end
  return cut
end

-- Making ----------------------------------------------------------------------------------------------------------------------

-- Builds, fits and stores an export. See the top of the file.
function Export.make(opts)
  opts = opts or {}
  local store = ns.Store
  if store.readOnly() then return nil, "read-only", Export.SAYS["read-only"] end
  local built, why = Export.build(opts.all)
  if not built then return nil, why, Export.SAYS[why] or why end

  local fitted = Export.fit(built.object, opts.limit)
  for _, item in ipairs(fitted) do
    if not item.text then return nil, "too-big", Export.SAYS["too-big"] end
  end

  local entries, characters = {}, 0
  for _, item in ipairs(fitted) do
    local entry, added = store.outboxAdd({ id = item.object.meta.id, text = item.text, kind = "attendance", made = built.object.meta.made })
    if not entry then return nil, added, Export.SAYS[added] or added end
    entries[#entries + 1] = entry
    characters = characters + #item.text
  end
  for _, mark in ipairs(built.marks) do mark.raid.sent = mark.count end

  return {
    entries = entries,
    count = #entries,
    raids = #built.object.attendance,
    snapshots = built.snapshots,
    pugs = built.object.pugs and #built.object.pugs or 0,
    characters = characters,
  }
end
