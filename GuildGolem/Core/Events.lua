-- The event bus: one frame takes every game event the addon listens to, and hands it to the handlers registered
-- here. A handler runs under pcall, so one that fails is recorded (Store.recordError, in GuildGolemDB.errors, capped)
-- and the others still run. It also holds addon messages back while the game would refuse them, and sends them when
-- it will take them again (docs/PLAN.md, "Event bus"; docs/RESEARCH.md, "Addon messages").
--
--   Events.init()                       makes the frame; call once, as the files load
--   Events.on(event, fn, owner)         fn(event, ...) runs when the game fires `event`. `owner` names the module, for
--                                       the error list. Gives false when the client has no such event
--   Events.off(event, fn)
--   Events.emit(name, ...)              runs the handlers of an event of the addon's own (a name starting GG_)
--   Events.dispatch(event, ...)         what the frame does for every game event; tests call it too
--   Events.send(prefix, text, chatType, target)   sends an addon message, or queues it. Gives true when it went, or
--                                       false and "queued", or false and why it failed for good
--   Events.flush()                      sends what is queued; it runs by itself on ENCOUNTER_END and when a restriction
--                                       clears, and again a second later when the client says it is sending too fast
--   Events.queued()                     how many messages wait
--
-- A message is queued while an encounter is on (between ENCOUNTER_START and ENCOUNTER_END, or an Encounter restriction
-- that has not cleared), and when the client answers "lockdown" or "throttled". Order is kept. Plain Lua: the game is
-- only reached through ns.Client.

local ADDON, ns = ...

local Events = {}
ns.Events = Events

Events.MAX_QUEUE = 200
-- How long to wait before sending again after the client said it was sending too fast, in seconds.
Events.RETRY = 1

local handlers = {}      -- event -> list of { fn, owner }
local registered = {}    -- game events the frame has taken
local queue = {}         -- messages waiting: { prefix, text, chatType, target }
local active = {}        -- restriction types that have not cleared
local inEncounter = false
local retrying = false
local frame

Events.unknown = {}      -- game events the client would not register

local function client() return ns.Client end

-- Recording an error must not raise one: if the store cannot take it, the bus carries on.
local function record(where, err)
  local store = ns.Store
  if store and store.recordError then pcall(store.recordError, where, err) end
end

local function trace(err)
  if debug and debug.traceback then return debug.traceback(tostring(err), 2) end
  return tostring(err)
end

-- Handlers ---------------------------------------------------------------------------------------------------------

function Events.on(event, fn, owner)
  if type(event) ~= "string" or type(fn) ~= "function" then error("Events.on(event, fn, owner)", 2) end
  local list = handlers[event]
  if not list then
    list = {}
    handlers[event] = list
  end
  list[#list + 1] = { fn = fn, owner = owner or "?" }
  if frame and not registered[event] and not event:find("^GG_") then
    if client().registerEvent(frame, event) then
      registered[event] = true
    else
      Events.unknown[event] = true
      return false
    end
  end
  return true
end

function Events.off(event, fn)
  local list = handlers[event]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i].fn == fn then table.remove(list, i) end
  end
end

function Events.dispatch(event, ...)
  local list = handlers[event]
  if not list then return end
  local args = { n = select("#", ...), ... }
  -- A copy, so a handler that adds or removes a handler does not change who runs now.
  local run = {}
  for i, h in ipairs(list) do run[i] = h end
  for _, h in ipairs(run) do
    local ok, err = xpcall(function() return h.fn(event, unpack(args, 1, args.n)) end, trace)
    if not ok then record("handler " .. event .. " (" .. h.owner .. ")", err) end
  end
end

function Events.emit(name, ...)
  Events.dispatch(name, ...)
end

-- Addon messages -----------------------------------------------------------------------------------------------------

-- True while the client would refuse an addon message.
local function mustWait()
  return inEncounter or active.Encounter == true
end

local function enqueue(message)
  queue[#queue + 1] = message
  while #queue > Events.MAX_QUEUE do
    table.remove(queue, 1)
    record("queue", "addon message queue is over " .. Events.MAX_QUEUE .. "; the oldest message was dropped")
  end
end

local function retryLater()
  if retrying then return end
  retrying = true
  if not client().after(Events.RETRY, function()
    retrying = false
    Events.flush()
  end) then
    retrying = false
  end
end

function Events.flush()
  local sent = 0
  while #queue > 0 do
    if mustWait() then return sent end
    local m = queue[1]
    local ok, why = client().send(m.prefix, m.text, m.chatType, m.target)
    if ok then
      table.remove(queue, 1)
      sent = sent + 1
    elseif why == "lockdown" then
      -- The client is still holding messages; ENCOUNTER_END or the restriction event will bring us back.
      return sent
    elseif why == "throttled" then
      retryLater()
      return sent
    else
      table.remove(queue, 1)
      record("send", "an addon message was refused: " .. tostring(why))
    end
  end
  return sent
end

function Events.send(prefix, text, chatType, target)
  local message = { prefix = prefix, text = text, chatType = chatType, target = target }
  -- Behind anything already waiting, so messages keep their order.
  if mustWait() or #queue > 0 then
    enqueue(message)
    if not mustWait() then Events.flush() end
    return false, "queued"
  end
  local ok, why = client().send(prefix, text, chatType, target)
  if ok then return true end
  if why == "lockdown" or why == "throttled" then
    enqueue(message)
    if why == "throttled" then retryLater() end
    return false, "queued"
  end
  return false, why
end

function Events.queued()
  return #queue
end

-- The frame -----------------------------------------------------------------------------------------------------------

function Events.init()
  if frame then return true end
  frame = client().createFrame()
  if not frame then return false end
  client().setEventHandler(frame, function(_, event, ...) Events.dispatch(event, ...) end)

  -- What the bus itself needs to know about an encounter.
  Events.on("ENCOUNTER_START", function() inEncounter = true end, "events")
  Events.on("ENCOUNTER_END", function()
    inEncounter = false
    Events.flush()
  end, "events")
  Events.on("ADDON_RESTRICTION_STATE_CHANGED", function(_, kind, state)
    local r = client().restriction(kind, state)
    local key = tostring(r.type)
    if r.cleared then
      active[key] = nil
      Events.flush()
    else
      active[key] = true
    end
  end, "events")
  return true
end

-- True while the bus is holding addon messages back for an encounter.
function Events.holding()
  return mustWait()
end
