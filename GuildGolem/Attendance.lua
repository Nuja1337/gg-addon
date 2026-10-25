-- Records who was in the raid (docs/PLAN.md, "Attendance"; contract/README.md, "attendance[]"): a roster snapshot at
-- zone-in to a raid instance, at every pull and its kill or wipe, every five minutes in between, and on leaving the
-- instance or the group. The rows come from ns.Client; this file names no game function, so it runs in a test.
--
--   Attendance.init()               listens to the game's events; Main.lua calls it once the saved variables are in
--   Attendance.evaluate()           looks at the instance and the group, and starts, keeps or ends the recording
--   Attendance.snapshot(why, encounter)   takes one snapshot of the current raid (why: zonein, pull, kill, wipe,
--                                   interval or leave). Gives it, or nil and why not
--   Attendance.current()            the raid being recorded, or nil
--   Attendance.state()              what /gg status shows: { recording, raid = { name, zone, snapshots, ... } }
--   Attendance.prune()              drops raids that were exported more than a month ago
--
-- What is recorded is db.raids (Store.raids()), a list oldest first. A raid is the contract's attendance entry plus
-- three fields of ours:
--   id, zone, name, difficulty, size, night?, leader?, lockout?, standby?, snapshots   as the contract has them
--   sent       how many of its snapshots an export has covered already (Export.lua)
--   seen       the server time (ms) of the last look at it, even when the snapshot was dropped as a repeat
--   closed     true once the recording ended
-- A snapshot is { at, why, encounter?, members = { { guid, name, cls?, grp?, online, zone? } } }.
--
-- Where the contract is silent, the core chose (one place each, listed in docs/PLAN.md):
--   * A snapshot is recorded only in a raid instance with a group. A solo player in one records nothing.
--   * One raid is one run of one instance: the player leaving the instance and coming back to the same one (same
--     instance id and difficulty) within REJOIN_MS of the last look goes on with the same raid, with a new zone-in
--     snapshot, instead of starting a second one, which the site would file as a second raid.
--   * A reload, or a login back in the raid, goes on with the raid the same way. A login anywhere else ends it without a
--     leave snapshot, since nobody knows when the player left; the site closes it at the end of its raid day.
--   * Two snapshots may not share a second (the site keys them by raid id and time). An interval snapshot that would is
--     dropped; any other kind is put one second after the one before.
--   * An interval snapshot that matches the one before it (same people, online states, zones and subgroups) is not kept:
--     the contract's `fit` would drop it from the export anyway (Export.lua), and this keeps the saved file small.
--   * The night comes from the imported night that starts within a day of now and plans this instance.

local ADDON, ns = ...

local Attendance = {}
ns.Attendance = Attendance

local floor, abs = math.floor, math.abs
local format = string.format

-- Seconds between interval snapshots.
Attendance.INTERVAL = 300
-- How long after its last look a raid can be gone on with (milliseconds; 30 minutes).
Attendance.REJOIN_MS = 1800000
-- An imported night this close to now (milliseconds; a day either side) is the night of a raid that starts.
Attendance.NIGHT_MS = 86400000
-- An exported raid is kept this long after its last snapshot (milliseconds; 30 days, written out for fengari).
Attendance.KEEP_MS = 2592000000

local function client() return ns.Client end
local function store() return ns.Store end

local function record(where, err)
  local s = ns.Store
  if s and s.recordError then pcall(s.recordError, where, err) end
end

-- Whole seconds as text; a time in milliseconds is past what fengari's integers hold, so nothing here formats it with %d.
local function whole(n) return format("%.0f", n) end

-- The raid being recorded: the last in the list, if it is not closed.
function Attendance.current()
  local raids = store().raids()
  local raid = raids and raids[#raids]
  if raid and not raid.closed then return raid end
  return nil
end

-- Text the contract can carry: a name with a byte that is not UTF-8 would make the whole export refuse to be written.
local function clean(text)
  if type(text) ~= "string" then return nil end
  if ns.Codec.validUtf8(text) then return text end
  return (text:gsub("[\128-\255]", "?"))
end

-- The roster rows as the contract's members. A row with no GUID cannot be one (the GUID is the key), so it is left out.
local function members(rows)
  local out = {}
  for _, row in ipairs(rows) do
    if row.guid then
      local m = { guid = row.guid, name = clean(row.name) or "Unknown", online = row.online == true }
      if row.cls then m.cls = row.cls end
      if row.group then m.grp = row.group end
      if row.online and row.zone then m.zone = clean(row.zone) end
      out[#out + 1] = m
    end
  end
  return out
end

-- Whether two snapshots show the same people in the same state (Export.lua's `fit` uses the same test, from
-- contract/README.md, "Size": roster, online states, zones and subgroups).
local function sameState(a, b)
  if #a.members ~= #b.members then return false end
  for i, m in ipairs(a.members) do
    local o = b.members[i]
    if m.guid ~= o.guid or m.online ~= o.online or m.zone ~= o.zone or m.grp ~= o.grp then return false end
  end
  return true
end
Attendance.sameState = sameState

-- The imported plan ----------------------------------------------------------------------------------------------------

-- The night and the bench the imports name for a raid of this instance that starts at `nowMs`: the night whose start is
-- nearest (within NIGHT_MS) and that plans this zone, or has a raid with no zone, which takes whichever the group enters.
-- Returns { night = handle, size, standby = { { guid, name, cls } } } or nil.
local function plan(zone, nowMs)
  local db = store().db()
  if not db or type(db.nights) ~= "table" then return nil end
  local best, bestRaid, bestDiff
  local handles = {}
  for handle in pairs(db.nights) do handles[#handles + 1] = handle end
  table.sort(handles)
  for _, handle in ipairs(handles) do
    local night = db.nights[handle]
    local diff = type(night.startsAt) == "number" and abs(nowMs - night.startsAt) or nil
    if diff and diff <= Attendance.NIGHT_MS and (not bestDiff or diff < bestDiff) then
      local found
      for _, raid in ipairs(night.raids or {}) do
        if raid.zone == zone then
          found = raid
          break
        end
        if raid.zone == nil and not found then found = raid end
      end
      if found then best, bestRaid, bestDiff = night, found, diff end
    end
  end
  if not best then return nil end

  local out = { night = best.handle, size = bestRaid.size, standby = {} }
  for _, p in ipairs(bestRaid.bench or {}) do
    local who
    for _, pick in ipairs(bestRaid.picks or {}) do
      if pick.p == p then who = pick end
    end
    if not who then
      local person = (best.people or {})[p]
      who = person and person.chars and person.chars[1]
    end
    -- A benched character whose GUID the import doesn't know cannot be named in the contract's standby (guid is
    -- required), so the person is left out.
    if who and who.guid then out.standby[#out.standby + 1] = { guid = who.guid, name = who.name, cls = who.cls } end
  end
  return out
end

-- Lockouts ----------------------------------------------------------------------------------------------------------------

-- The saved lockout's id for this raid, once the game has one (after a kill, as a rule). Sets raid.lockout.
local function refreshLockout(raid)
  if raid.lockout then return end
  for _, l in ipairs(client().lockouts()) do
    if l.raid and l.locked and l.id and l.name == raid.name and l.difficulty == raid.difficulty then
      raid.lockout = l.id
      return
    end
  end
end

-- Snapshots -----------------------------------------------------------------------------------------------------------------

-- Takes one snapshot of the current raid. `why` is zonein, pull, kill, wipe, interval or leave; the three in the middle
-- take the encounter's id. Gives the snapshot, or nil and why: "not-recording", "no-clock", "repeat" (an interval
-- snapshot like the one before it) or "same-second".
function Attendance.snapshot(why, encounter)
  local raid = Attendance.current()
  if not raid then return nil, "not-recording" end
  local nowMs = client().serverTimeMs()
  if not nowMs then return nil, "no-clock" end

  local rows = client().roster()
  local snap = { at = nowMs, why = why, members = members(rows) }
  if encounter and (why == "pull" or why == "kill" or why == "wipe") then snap.encounter = encounter end
  raid.seen = nowMs

  local last = raid.snapshots[#raid.snapshots]
  if last then
    if why == "interval" then
      if snap.at <= last.at then return nil, "same-second" end
      if sameState(snap, last) then return nil, "repeat" end
    elseif snap.at <= last.at then
      -- Not before or at the one before: the site keys snapshots by raid id and time.
      snap.at = last.at + 1000
    end
  end
  raid.snapshots[#raid.snapshots + 1] = snap

  if why == "zonein" and not raid.leader then
    for _, row in ipairs(rows) do
      if row.rank == 2 and row.guid then raid.leader = row.guid end
    end
  end
  if why == "zonein" or why == "kill" or why == "leave" then refreshLockout(raid) end
  ns.Events.emit("GG_SNAPSHOT", raid, snap)
  return snap
end

-- The five-minute timer ---------------------------------------------------------------------------------------------------

local generation = 0   -- a timer from before the last start or stop stops itself
local timerRaid        -- the raid the running timer is for

local function stopTimer()
  generation = generation + 1
  timerRaid = nil
end

local function startTimer(raid)
  if timerRaid == raid then return end
  generation = generation + 1
  timerRaid = raid
  local mine = generation
  local function tick()
    if mine ~= generation then return end
    local ok, err = pcall(function()
      Attendance.evaluate()
      if mine ~= generation or Attendance.current() ~= raid then return end
      Attendance.snapshot("interval")
    end)
    if not ok then record("attendance timer", err) end
    if mine == generation and Attendance.current() == raid then client().after(Attendance.INTERVAL, tick) end
  end
  client().after(Attendance.INTERVAL, tick)
end

-- Starting and ending ---------------------------------------------------------------------------------------------------

local function sizeOf(inst, planned, rows)
  local size = inst.maxPlayers
  if not size or size < 1 then size = inst.groupSize end
  if not size or size < 1 then size = planned and planned.size end
  if not size or size < 1 then size = #rows end
  if size > 40 then size = 40 end
  if size < 1 then size = 1 end
  return size
end

-- Starts recording a raid in this instance, or goes on with the one the player just left (see the choices above).
local function start(inst)
  local nowMs = client().serverTimeMs()
  local me = client().player()
  if not nowMs or not me.guid then return nil end
  local raids = store().raids()
  if not raids then return nil end

  local last = raids[#raids]
  if last and last.closed and last.zone == inst.instanceID and last.difficulty == (inst.difficulty or 0)
      and last.seen and nowMs - last.seen <= Attendance.REJOIN_MS then
    last.closed = nil
    Attendance.snapshot("zonein")
    startTimer(last)
    return last
  end

  local rows = client().roster()
  local planned = plan(inst.instanceID, nowMs)
  local raid = {
    id = me.guid .. ":" .. whole(inst.instanceID) .. ":" .. whole(floor(nowMs / 1000)),
    zone = inst.instanceID,
    name = clean(inst.name) or "Unknown",
    difficulty = inst.difficulty or 0,
    size = sizeOf(inst, planned, rows),
    sent = 0,
    seen = nowMs,
    snapshots = {},
  }
  if planned then
    raid.night = planned.night
    if #planned.standby > 0 then raid.standby = planned.standby end
  end
  raids[#raids + 1] = raid
  Attendance.snapshot("zonein")
  startTimer(raid)
  return raid
end

-- Ends the recording with a leave snapshot, unless `quiet` (a session that began elsewhere).
local function finish(raid, quiet)
  if not quiet then
    -- The snapshot reads the current raid, which is this one.
    Attendance.snapshot("leave")
  end
  raid.closed = true
  stopTimer()
end

-- Combat logging -------------------------------------------------------------------------------------------------------

local loggedFor   -- the instance the combat log was last looked at for

-- Turns combat logging on at zone-in to a raid instance, if the client can and the player has not said no. Once for each
-- time the player enters; if it is on already nothing is said. It is never turned off.
local function combatLogging(inst)
  local key = whole(inst.instanceID) .. ":" .. whole(inst.difficulty or 0)
  if loggedFor == key then return end
  loggedFor = key
  if store().setting("autoLog", true) == false then return end
  if not client().caps().loggingCombat then return end
  if client().loggingCombat() == true then return end
  if client().enableCombatLogging() then
    print("|cffff8800Guild Golem:|r Combat logging is on for this raid. Type /gg log off to stop doing that.")
  end
end

-- Looking ----------------------------------------------------------------------------------------------------------------------

local firstLook = true   -- the first evaluation of a session decides what to do with a raid the saved file left open

-- Looks at where the player is and starts, goes on with or ends the recording to match. Cheap: it reads the instance and
-- the kind of group, and the roster only when it takes a snapshot.
function Attendance.evaluate()
  if not store().db() then return end
  local inst = client().instance()
  local inRaid = inst ~= nil and inst.type == "raid" and (inst.instanceID or 0) > 0
  if inRaid then combatLogging(inst) else loggedFor = nil end
  local grouped = client().groupKind() ~= "none"

  local raid = Attendance.current()
  if raid then
    local same = inRaid and inst.instanceID == raid.zone and (inst.difficulty or 0) == raid.difficulty
    if firstLook and not (same and grouped) then
      -- Left open by an earlier session, and the player is not in it now: nobody knows when they left.
      finish(raid, true)
    elseif not same or not grouped then
      finish(raid)
    else
      startTimer(raid)
      if firstLook then Attendance.snapshot("interval") end
    end
    raid = Attendance.current()
  end
  firstLook = false

  if not raid and inRaid and grouped then start(inst) end
end

-- Events -----------------------------------------------------------------------------------------------------------------------

local function onEncounterStart(_, ...)
  local row = client().encounterStart(...)
  Attendance.evaluate()
  if not Attendance.current() then return end
  if row.id then Attendance.snapshot("pull", row.id) else Attendance.snapshot("interval") end
end

local function onEncounterEnd(_, ...)
  local row = client().encounterEnd(...)
  Attendance.evaluate()
  local raid = Attendance.current()
  if not raid then return end
  if row.id then
    Attendance.snapshot(row.kill and "kill" or "wipe", row.id)
  else
    Attendance.snapshot("interval")
  end
  -- The lockout appears once a boss is dead; the game says so with UPDATE_INSTANCE_INFO.
  if row.kill and not raid.lockout then client().requestRaidInfo() end
end

local function onInstanceInfo()
  local raid = Attendance.current()
  if raid then refreshLockout(raid) end
end

local started = false

function Attendance.init()
  if started then return end
  started = true
  local on = ns.Events.on
  on("PLAYER_ENTERING_WORLD", Attendance.evaluate, "attendance")
  on("ZONE_CHANGED_NEW_AREA", Attendance.evaluate, "attendance")
  on("GROUP_ROSTER_UPDATE", Attendance.evaluate, "attendance")
  on("ENCOUNTER_START", onEncounterStart, "attendance")
  on("ENCOUNTER_END", onEncounterEnd, "attendance")
  on("UPDATE_INSTANCE_INFO", onInstanceInfo, "attendance")
  Attendance.prune()
end

-- A test, or a second session in one Lua state, starts from nothing.
function Attendance.reset()
  started = false
  firstLook = true
  loggedFor = nil
  stopTimer()
end

-- Keeping ------------------------------------------------------------------------------------------------------------------

-- Drops the raids whose snapshots were all exported and whose last one is over KEEP_MS old. Returns how many went.
function Attendance.prune(atMs)
  local raids = store().raids()
  atMs = atMs or client().serverTimeMs()
  if not raids or not atMs or store().readOnly() then return 0 end
  local keep, removed = {}, 0
  for i, raid in ipairs(raids) do
    local last = raid.snapshots and raid.snapshots[#raid.snapshots]
    local old = last and atMs - last.at > Attendance.KEEP_MS
    if raid.closed and old and (raid.sent or 0) >= #raid.snapshots then
      removed = removed + 1
    else
      keep[#keep + 1] = raid
    end
  end
  if removed > 0 then
    local db = store().db()
    db.raids = keep
  end
  return removed
end

-- What /gg status shows.
function Attendance.state()
  local raids = store().raids() or {}
  local raid = Attendance.current()
  local out = { recording = raid ~= nil, raids = #raids }
  if raid then
    out.raid = {
      id = raid.id, name = raid.name, zone = raid.zone, difficulty = raid.difficulty, size = raid.size,
      night = raid.night, snapshots = #raid.snapshots, sent = raid.sent or 0, lockout = raid.lockout,
      last = raid.snapshots[#raid.snapshots] and raid.snapshots[#raid.snapshots].at or nil,
    }
  end
  return out
end
