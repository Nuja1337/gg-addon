-- Stubs for the parts of the game the addon touches, so its Lua runs in a test (README.md in this folder).
--
-- The stubs are data-driven. A test sets the roster, the instance, the player and the clock through the WOW table,
-- drives the addon (WOW.fire, WOW.advance, WOW.slash, WOW.logout) and reads what it did (WOW.outbox, WOW.chat,
-- WOW.saved). Payloads follow docs/RESEARCH.md ("Probe results"): names are "First Surname" with a space, GUIDs are
-- Player-<server>-<id>, and UnitName gives the first name and the surname as two values.
--
-- Written in Lua 5.1 syntax so that Lua 5.1 and, with compat51.lua loaded first, fengari's 5.3 can both run it. A
-- stub exists only for something the addon calls: add the next one here when a test needs it. Only Client.lua may
-- call the game's functions (docs/PLAN.md), so these stubs are what Client.lua sees and nothing else does.

WOW = WOW or {}
local WOW = WOW

local rawprint = print
local realTime = os.time

-- The folder that addon files are loaded from. The runners set GG_ROOT to the repository's folder.
WOW.root = GG_ROOT or "."

-- Helpers -------------------------------------------------------------------------------------------------------

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
  return out
end
WOW.copy = copy

local function fail(message)
  error(message, 3)
end

-- The class tokens and ids the game uses; a roster entry names its class by token.
local CLASSES = {
  WARRIOR = { 1, "Warrior" }, PALADIN = { 2, "Paladin" }, HUNTER = { 3, "Hunter" }, ROGUE = { 4, "Rogue" },
  PRIEST = { 5, "Priest" }, DEATHKNIGHT = { 6, "Death Knight" }, SHAMAN = { 7, "Shaman" }, MAGE = { 8, "Mage" },
  WARLOCK = { 9, "Warlock" }, MONK = { 10, "Monk" }, DRUID = { 11, "Druid" }, DEMONHUNTER = { 12, "Demon Hunter" },
  EVOKER = { 13, "Evoker" },
}

-- Reset ---------------------------------------------------------------------------------------------------------

-- A fresh game: no frames or timers, a clock that starts at a fixed time, the player alone in the open world.
-- The harness calls this before every test. `opts` may hold `time` (the server's epoch seconds) and `uptime`
-- (what GetTime returns), both numbers.
function WOW.reset(opts)
  opts = opts or {}

  -- The globals an addon registers or declares are taken out, so the next test starts clean.
  if WOW.savedNames then
    for _, name in ipairs(WOW.savedNames) do _G[name] = nil end
  end
  for key in pairs(_G) do
    if type(key) == "string" and key:find("^SLASH_") then _G[key] = nil end
  end
  if SlashCmdList then
    for key in pairs(SlashCmdList) do SlashCmdList[key] = nil end
  end

  -- An API a test hid with WOW.hide comes back. The last one hidden goes back first, so an API hidden twice (taken
  -- away, then replaced by the test) ends as the game's own.
  local hiddenList = WOW.hidden or {}
  for i = #hiddenList, 1, -1 do hiddenList[i].owner[hiddenList[i].key] = hiddenList[i].value end
  WOW.hidden = {}

  -- Frames a test named are global; they go with the test.
  for _, name in ipairs(WOW.frameNames or {}) do _G[name] = nil end
  WOW.frameNames = {}
  WOW.errors = {}
  WOW.catchErrors = false
  WOW.frames = {}
  WOW.timers = {}
  WOW.timerSeq = 0
  WOW.chat = {}
  WOW.outbox = {}
  WOW.prefixes = {}
  WOW.lockdown = false
  WOW.buckets = {}
  WOW.saved = {}
  WOW.savedFile = ""
  WOW.savedNames = {}
  WOW.logging = false
  WOW.loggingCalls = {}
  WOW.loggingRefused = false
  WOW.raidInfoRequests = 0
  WOW.missingTemplates = {}
  UISpecialFrames = {}

  -- GetTime counts up from `uptime`; the server's time is GetTime plus a fixed offset (setServerTime moves it).
  -- 1793998800 is a Friday evening in November 2026, UTC: a raid night.
  WOW.uptime = opts.uptime or 5000.0
  WOW.offset = (opts.time or 1793998800) - WOW.uptime

  WOW.player = { name = "Rhona Tester", class = "MAGE", level = 60, guid = "Player-9001-0000AAAA", zone = "Test Zone" }
  WOW.group = { kind = nil, members = {} }
  WOW.instance = {}
  WOW.build = { version = "1.60.1", build = "70532", date = "Oct 20 2026", toc = 16001 }
  WOW.metadata = { GuildGolem = { Version = "0.1.0-beta", Title = "Guild Golem" } }
  WOW.secrets = setmetatable({}, { __mode = "k" })
  WOW.savedInstances = {}
  WOW.locale = "enUS"
  WOW.realm = "Classic Beta PvP"
end

-- Frames and events ---------------------------------------------------------------------------------------------

-- What a frame holds that an addon must not see (its table is the addon's to put fields on).
local frameData = setmetatable({}, { __mode = "k" })

-- Calls fn, and what happens to an error depends on WOW.catchErrors: false (the default) lets it reach the test,
-- true records it in WOW.errors the way the game's error handler would, and carries on.
local function protected(fn, ...)
  if not WOW.catchErrors then return fn(...) end
  local ok, err = pcall(fn, ...)
  if not ok then WOW.errors[#WOW.errors + 1] = tostring(err) end
end

local Frame = {}
Frame.__index = Frame

local function data(frame) return frameData[frame] end

function Frame:RegisterEvent(event) data(self).events[event] = true end
function Frame:RegisterUnitEvent(event) data(self).events[event] = true end
function Frame:UnregisterEvent(event) data(self).events[event] = nil end
function Frame:UnregisterAllEvents() data(self).events = {} end
function Frame:IsEventRegistered(event) return data(self).events[event] == true end
function Frame:SetScript(name, fn) data(self).scripts[name] = fn end
function Frame:GetScript(name) return data(self).scripts[name] end
function Frame:HasScript(name) return data(self).scripts[name] ~= nil end
function Frame:HookScript(name, fn)
  local hooks = data(self).hooks
  hooks[name] = hooks[name] or {}
  hooks[name][#hooks[name] + 1] = fn
end
function Frame:Show() data(self).shown = true end
function Frame:Hide() data(self).shown = false end
function Frame:IsShown() return data(self).shown end
function Frame:IsVisible() return data(self).shown end
function Frame:GetName() return data(self).name end
function Frame:GetObjectType() return data(self).kind end
function Frame:SetParent(parent) data(self).parent = parent end
function Frame:GetParent() return data(self).parent end

-- What the addon's window uses (Client.window). Layout calls are accepted and forgotten; text, enabled state and scripts
-- are kept so a test can read and drive them (WOW.userText, WOW.click).
for _, name in ipairs({ "SetSize", "SetWidth", "SetHeight", "SetPoint", "SetAllPoints", "ClearAllPoints", "SetFrameStrata",
  "SetMovable", "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetScrollChild", "SetMultiLine",
  "SetFontObject", "SetAutoFocus", "SetMaxLetters", "SetNormalFontObject" }) do
  Frame[name] = function() end
end

function Frame:SetText(text)
  local d = data(self)
  d.text = tostring(text)
  -- The game tells a script the text changed, and that it was not the player who changed it.
  if d.scripts.OnTextChanged then protected(d.scripts.OnTextChanged, self, false) end
end
function Frame:GetText() return data(self).text or "" end
function Frame:GetNumLetters() return #(data(self).text or "") end
function Frame:HighlightText() data(self).highlighted = true end
function Frame:SetFocus() data(self).focused = true end
function Frame:ClearFocus() data(self).focused = false end
function Frame:HasFocus() return data(self).focused == true end
function Frame:Enable() data(self).enabled = true end
function Frame:Disable() data(self).enabled = false end
function Frame:IsEnabled() return data(self).enabled ~= false end
function Frame:GetFontString() return data(self).fontString end

local FontString = {}
FontString.__index = FontString
for _, name in ipairs({ "SetPoint", "SetWidth", "SetJustifyH", "SetJustifyV", "SetTextColor", "SetAllPoints" }) do
  FontString[name] = function() end
end
function FontString:SetText(text) self.text = tostring(text) end
function FontString:GetText() return self.text or "" end

local Texture = {}
Texture.__index = Texture
Texture.SetAllPoints = function() end
Texture.SetColorTexture = function() end

function Frame:CreateFontString()
  return setmetatable({}, FontString)
end
function Frame:CreateTexture()
  return setmetatable({}, Texture)
end

-- The templates the addon asks for. A template a test lists in WOW.missingTemplates is refused, as a client without it
-- would (an error from CreateFrame).
local TEMPLATES = { BasicFrameTemplateWithInset = true, UIPanelScrollFrameTemplate = true, UIPanelButtonTemplate = true }

function CreateFrame(kind, name, parent, template)
  if type(kind) ~= "string" then fail("CreateFrame: the frame type must be a string") end
  if template ~= nil and (not TEMPLATES[template] or WOW.missingTemplates[template]) then
    fail("CreateFrame: couldn't find inherited node \"" .. tostring(template) .. "\"")
  end
  local frame = setmetatable({}, Frame)
  frameData[frame] = { kind = kind, name = name, parent = parent, events = {}, scripts = {}, hooks = {}, shown = true }
  WOW.frames[#WOW.frames + 1] = frame
  if name then
    _G[name] = frame
    WOW.frameNames[#WOW.frameNames + 1] = name
  end
  if template == "BasicFrameTemplateWithInset" then frame.TitleText = setmetatable({}, FontString) end
  if template == "UIPanelButtonTemplate" then frameData[frame].fontString = setmetatable({}, FontString) end
  return frame
end

UIParent = setmetatable({}, Frame)
frameData[UIParent] = { kind = "Frame", name = "UIParent", events = {}, scripts = {}, hooks = {}, shown = true }
ChatFontNormal = {}

local function runScript(frame, name, ...)
  local d = data(frame)
  if d.scripts[name] then protected(d.scripts[name], frame, ...) end
  for _, hook in ipairs(d.hooks[name] or {}) do protected(hook, frame, ...) end
end

-- Types into an edit box as the player does: sets the text and tells its OnTextChanged script that the player changed it.
function WOW.userText(frame, text)
  data(frame).text = text
  if data(frame).scripts.OnTextChanged then protected(data(frame).scripts.OnTextChanged, frame, true) end
end

-- Presses a button: runs its OnClick script, unless the button is disabled. Returns whether it ran.
function WOW.click(frame)
  local d = data(frame)
  if d.enabled == false or not d.scripts.OnClick then return false end
  protected(d.scripts.OnClick, frame, "LeftButton")
  return true
end

-- What a frame holds that a test may look at: its text, whether it is shown, enabled, focused and highlighted.
function WOW.frameState(frame)
  local d = data(frame)
  return { text = d.text, shown = d.shown, enabled = d.enabled ~= false, focused = d.focused == true, highlighted = d.highlighted == true }
end

-- Fires a game event at every frame registered for it, in the order the frames were made, and returns how many
-- frames got it.
function WOW.fire(event, ...)
  local targets = {}
  for _, frame in ipairs(WOW.frames) do
    if data(frame).events[event] then targets[#targets + 1] = frame end
  end
  for _, frame in ipairs(targets) do runScript(frame, "OnEvent", event, ...) end
  return #targets
end

-- The clock and timers ------------------------------------------------------------------------------------------

function GetTime() return WOW.uptime end
function debugprofilestop() return WOW.uptime * 1000 end
-- Like every number in Lua 5.1 this is a double, so GetServerTime() * 1000 does not wrap in fengari, whose integers
-- are 32 bits (README.md, "What cannot be shimmed").
function GetServerTime() return math.floor(WOW.uptime + WOW.offset) + 0.0 end

-- The game's time() and Lua's os.time() both read the fake clock when asked for the time now.
function time(t)
  if t ~= nil then return realTime(t) end
  return GetServerTime()
end
os.time = time

-- Moves the server's clock without moving GetTime, as when the PC and the server disagree.
function WOW.setServerTime(seconds)
  WOW.offset = seconds - WOW.uptime
end

C_Timer = {}

local function addTimer(delay, fn, interval, count, passHandle)
  if type(delay) ~= "number" or delay < 0 then fail("C_Timer: the delay must be a number of seconds, 0 or more") end
  if type(fn) ~= "function" then fail("C_Timer: the callback must be a function") end
  WOW.timerSeq = WOW.timerSeq + 1
  local timer = { due = WOW.uptime + delay, seq = WOW.timerSeq, fn = fn, interval = interval, left = count,
    passHandle = passHandle }
  WOW.timers[#WOW.timers + 1] = timer
  local handle = {}
  timer.handle = handle
  function handle:Cancel() timer.cancelled = true end
  function handle:IsCancelled() return timer.cancelled == true end
  return handle
end

function C_Timer.After(delay, fn)
  addTimer(delay, fn)
end

function C_Timer.NewTimer(delay, fn)
  return addTimer(delay, fn, nil, nil, true)
end

-- `count` is how many times the ticker runs; nil means until it is cancelled.
function C_Timer.NewTicker(interval, fn, count)
  if type(interval) ~= "number" or interval <= 0 then fail("C_Timer.NewTicker: the interval must be above 0") end
  return addTimer(interval, fn, interval, count, true)
end

-- Moves the clock forward by `seconds` and runs every timer that comes due on the way, in order, with GetTime
-- reading each timer's own time while it runs. A timer set to 0 seconds runs on the next advance, even advance(0).
-- Returns how many callbacks ran.
function WOW.advance(seconds)
  if type(seconds) ~= "number" or seconds < 0 then fail("WOW.advance: seconds must be a number, 0 or more") end
  local target = WOW.uptime + seconds
  local ran = 0
  while true do
    local nextIndex, nextTimer
    for i, timer in ipairs(WOW.timers) do
      if timer.cancelled then
        -- dropped below
      elseif timer.due <= target and (not nextTimer or timer.due < nextTimer.due
          or (timer.due == nextTimer.due and timer.seq < nextTimer.seq)) then
        nextIndex, nextTimer = i, timer
      end
    end
    -- Cancelled timers go, so a cancelled ticker is not scanned again.
    for i = #WOW.timers, 1, -1 do
      if WOW.timers[i].cancelled then table.remove(WOW.timers, i) end
    end
    if not nextTimer then break end
    if nextTimer.due > WOW.uptime then WOW.uptime = nextTimer.due end
    if nextTimer.interval then
      nextTimer.due = nextTimer.due + nextTimer.interval
      if nextTimer.left then
        nextTimer.left = nextTimer.left - 1
        if nextTimer.left <= 0 then nextTimer.cancelled = true end
      end
    else
      nextTimer.cancelled = true
    end
    ran = ran + 1
    if ran > 100000 then fail("WOW.advance: over 100000 timer callbacks, a timer loop?") end
    -- After passes nothing to its callback; a timer and a ticker pass themselves.
    if nextTimer.passHandle then
      protected(nextTimer.fn, nextTimer.handle)
    else
      protected(nextTimer.fn)
    end
  end
  WOW.uptime = target
  return ran
end

-- Build, locale, realm -------------------------------------------------------------------------------------------

WOW_PROJECT_ID = 18
LE_EXPANSION_LEVEL_CURRENT = 0

function GetBuildInfo()
  local b = WOW.build
  return b.version, b.build, b.date, b.toc, "", "Release"
end

function GetLocale() return WOW.locale end
function GetRealmName() return WOW.realm end
function GetNormalizedRealmName() return (WOW.realm:gsub("%s", "")) end

-- Players, the group, the instance -----------------------------------------------------------------------------

-- A roster entry as the game would report it. `spec` holds name ("First Surname"), class (a token such as "MAGE"),
-- and may hold rank (0 member, 1 assistant, 2 leader), subgroup, level, zone, online, isDead, role, combatRole,
-- isML, guid, guild (a table as for WOW.setGuild). The rest is filled in.
local function member(spec, index)
  local info = CLASSES[spec.class or "WARRIOR"]
  if not info then fail("unknown class token " .. tostring(spec.class)) end
  if type(spec.name) ~= "string" then fail("a roster entry needs a name") end
  local m = copy(spec)
  m.class = spec.class or "WARRIOR"
  m.classID = info[1]
  m.className = info[2]
  m.rank = spec.rank or 0
  m.subgroup = spec.subgroup or (math.floor((index - 1) / 5) + 1)
  m.level = spec.level or 60
  m.zone = spec.zone or "Test Zone"
  if spec.online == nil then m.online = true end
  m.isDead = spec.isDead or false
  m.role = spec.role
  m.combatRole = spec.combatRole or "NONE"
  m.isML = spec.isML or false
  m.guid = spec.guid or string.format("Player-9001-%08X", 0x1000 + index)
  return m
end

-- Sets the player (the character the addon runs on): name, class, level, guid, zone.
function WOW.setPlayer(spec)
  for k, v in pairs(spec) do WOW.player[k] = v end
end

-- Sets who is in the group. `members` is a list of roster entries (see `member`), `kind` is "raid" (the default)
-- or "party". The player is always in the group: if no entry carries the player's name, the player is added first,
-- as the raid leader. No members, or none given, leaves the group.
function WOW.setRoster(members, kind)
  WOW.group = { kind = nil, members = {} }
  if not members or #members == 0 then return end
  kind = kind or "raid"
  if kind ~= "raid" and kind ~= "party" then fail("WOW.setRoster: kind is \"raid\" or \"party\"") end
  local list = {}
  local hasPlayer = false
  for _, spec in ipairs(members) do
    if spec.name == WOW.player.name then hasPlayer = true end
  end
  if not hasPlayer then
    list[1] = { name = WOW.player.name, class = WOW.player.class, level = WOW.player.level, guid = WOW.player.guid,
      zone = WOW.player.zone, rank = 2 }
  end
  for _, spec in ipairs(members) do list[#list + 1] = spec end
  local built = {}
  for i, spec in ipairs(list) do built[i] = member(spec, i) end
  WOW.group = { kind = kind, members = built }
end

-- Sets the instance GetInstanceInfo reports: name, type ("none", "party", "raid"), difficultyID, difficultyName,
-- maxPlayers, instanceID, instanceGroupSize. These values are the test's; the game's ids are in the probe's
-- results, not here. No argument puts the player back in the open world.
function WOW.setInstance(spec)
  WOW.instance = spec and copy(spec) or {}
end

-- Sets the player's guild: name, rank (a name), rankIndex, realm. No argument takes the player out of a guild.
function WOW.setGuild(spec)
  WOW.player.guild = spec and copy(spec) or nil
end

function IsInRaid() return WOW.group.kind == "raid" end
function IsInGroup() return WOW.group.kind ~= nil end

function GetNumGroupMembers()
  return #WOW.group.members
end

-- name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole
function GetRaidRosterInfo(index)
  local m = WOW.group.kind == "raid" and WOW.group.members[index]
  if not m then return end
  return m.name, m.rank, m.subgroup, m.level, m.className, m.class, m.zone, m.online, m.isDead, m.role, m.isML,
    m.combatRole
end

-- "player", "raidN" in a raid, "partyN" in a party (the others, not the player), nothing else.
local function unitMember(unit)
  if unit == "player" then return WOW.player end
  if type(unit) ~= "string" then return nil end
  local kind, n = unit:match("^(%a+)(%d+)$")
  n = tonumber(n)
  if not n then return nil end
  if kind == "raid" and WOW.group.kind == "raid" then return WOW.group.members[n] end
  if kind == "party" and WOW.group.kind == "party" then
    local seen = 0
    for _, m in ipairs(WOW.group.members) do
      if m.name ~= WOW.player.name then
        seen = seen + 1
        if seen == n then return m end
      end
    end
  end
  return nil
end

function UnitGUID(unit)
  local m = unitMember(unit)
  return m and m.guid or nil
end

-- The first name and the surname, as two values (the probe, Oct 22).
function UnitName(unit)
  local m = unitMember(unit)
  if not m then return nil end
  local first, surname = m.name:match("^(%S+)%s+(.+)$")
  if first then return first, surname end
  return m.name, nil
end
UnitFullName = UnitName

-- localized class, token, id
function UnitClass(unit)
  local m = unitMember(unit)
  if not m then return nil end
  local token = m.class
  local info = CLASSES[token]
  return info[2], token, info[1]
end

-- name, rankName, rankIndex, realm; nothing for a unit that is not in a guild.
function GetGuildInfo(unit)
  local m = unitMember(unit or "player")
  local g = m and m.guild
  if not g then return nil end
  return g.name, g.rank, g.rankIndex, g.realm
end

-- name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID,
-- instanceGroupSize, LfgDungeonID
function GetInstanceInfo()
  local i = WOW.instance
  return i.name or "Test Zone", i.type or "none", i.difficultyID or 0, i.difficultyName or "", i.maxPlayers or 0,
    0, false, i.instanceID or 0, i.instanceGroupSize or 0, nil
end

-- The combat log switch: LoggingCombat() reads it, LoggingCombat(true or false) sets it and gives the new state. Every call
-- with an argument is kept in WOW.loggingCalls; WOW.loggingRefused = true makes the client ignore the request.
function LoggingCombat(flag)
  if flag == nil then return WOW.logging end
  WOW.loggingCalls[#WOW.loggingCalls + 1] = flag
  if not WOW.loggingRefused then WOW.logging = flag == true end
  return WOW.logging
end

-- Asks for the saved instances to be refreshed; counted, and the answer (UPDATE_INSTANCE_INFO) is the test's to fire.
function RequestRaidInfo() WOW.raidInfoRequests = WOW.raidInfoRequests + 1 end

-- Connection, saved instances, secret values, add-on metadata --------------------------------------------------------

function UnitIsConnected(unit)
  local m = unitMember(unit)
  if not m then return false end
  return m.online ~= false
end

-- Sets the saved lockouts GetSavedInstanceInfo reports: a list of { name, id, difficulty, locked, instanceID, raid,
-- maxPlayers, difficultyName }. These are the test's values, not the game's.
function WOW.setSavedInstances(list)
  WOW.savedInstances = list and copy(list) or {}
end

function GetNumSavedInstances() return #WOW.savedInstances end

-- name, lockoutId, reset, difficultyId, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName,
-- numEncounters, encounterProgress
function GetSavedInstanceInfo(index)
  local r = WOW.savedInstances[index]
  if not r then return end
  return r.name, r.id, r.reset or 0, r.difficulty or 0, r.locked ~= false, false, r.instanceID or 0, r.raid ~= false,
    r.maxPlayers or 0, r.difficultyName or "", 0, 0
end

-- A value the game would make secret. The addon may hold it but not compare it, join it or turn it to text; the
-- stub is a table that issecretvalue knows, so a test can hand one to the addon where the game would.
function WOW.secret(label)
  local value = { secret = label or true }
  WOW.secrets[value] = true
  return value
end

local function isSecret(value)
  return type(value) == "table" and WOW.secrets[value] == true
end

function issecretvalue(value) return isSecret(value) end
function canaccessvalue(value) return not isSecret(value) end

C_AddOns = {}

function C_AddOns.GetAddOnMetadata(addon, field)
  local data = WOW.metadata[addon]
  return data and data[field] or nil
end

-- Takes an API away for the rest of the test, as a client that lacks it would: "GetRaidRosterInfo", or
-- "C_ChatInfo.SendAddonMessage" for a function in a table. WOW.reset puts it back.
function WOW.hide(path)
  local owner, key = _G, path
  local head, tail = path:match("^(.-)%.(.+)$")
  if head then owner, key = _G[head], tail end
  if type(owner) ~= "table" or owner[key] == nil then fail("WOW.hide: there is no " .. path) end
  WOW.hidden[#WOW.hidden + 1] = { owner = owner, key = key, value = owner[key] }
  owner[key] = nil
end

-- Addon messages -------------------------------------------------------------------------------------------------

Enum = Enum or {}
Enum.SendAddonMessageResult = {
  Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3, InvalidChatType = 4,
  NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9,
  NotInGuild = 10, AddOnMessageLockdown = 11, TargetOffline = 12,
}
local Result = Enum.SendAddonMessageResult

local CHAT_TYPES = { PARTY = true, RAID = true, GUILD = true, OFFICER = true, WHISPER = true, INSTANCE_CHAT = true,
  CHANNEL = true, SAY = true, YELL = true }

C_ChatInfo = {}

-- A prefix is up to 16 characters (docs/RESEARCH.md, "Addon messages").
function C_ChatInfo.RegisterAddonMessagePrefix(prefix)
  if type(prefix) ~= "string" or #prefix == 0 or #prefix > 16 then return false end
  WOW.prefixes[prefix] = true
  return true
end

function C_ChatInfo.IsAddonMessagePrefixRegistered(prefix)
  return WOW.prefixes[prefix] == true
end

-- True during an encounter or in a restricted zone (WOW.lockdown), when the game turns chat secret.
function C_ChatInfo.InChatMessagingLockdown()
  return WOW.lockdown == true
end

-- ADDON_RESTRICTION_STATE_CHANGED(type, state): the type and state are numbers from these enums. The names are
-- docs/RESEARCH.md's; the numbers are the test's, since the probe has not recorded the client's.
Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
Enum.AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 }

-- A message is up to 255 bytes, a prefix has 10 messages and refills one a second (the fake clock), and
-- WOW.lockdown = true is an encounter: the message is refused and not sent. Returns the result code.
function C_ChatInfo.SendAddonMessage(prefix, text, chatType, target)
  if type(prefix) ~= "string" or #prefix == 0 or #prefix > 16 then return Result.InvalidPrefix end
  if type(text) ~= "string" or #text > 255 then return Result.InvalidMessage end
  chatType = chatType or "PARTY"
  if not CHAT_TYPES[chatType] then return Result.InvalidChatType end
  if chatType == "WHISPER" and not target then return Result.TargetRequired end
  if (chatType == "PARTY" or chatType == "RAID") and not IsInGroup() then return Result.NotInGroup end
  if chatType == "RAID" and not IsInRaid() then return Result.NotInGroup end
  if chatType == "GUILD" or chatType == "OFFICER" then
    if not WOW.player.guild then return Result.NotInGuild end
  end
  if WOW.lockdown then return Result.AddOnMessageLockdown end

  local bucket = WOW.buckets[prefix]
  if not bucket then
    bucket = { tokens = 10, at = WOW.uptime }
    WOW.buckets[prefix] = bucket
  end
  bucket.tokens = math.min(10, bucket.tokens + (WOW.uptime - bucket.at))
  bucket.at = WOW.uptime
  if bucket.tokens < 1 then return Result.AddonMessageThrottle end
  bucket.tokens = bucket.tokens - 1

  WOW.outbox[#WOW.outbox + 1] = { prefix = prefix, text = text, chatType = chatType, target = target,
    at = GetServerTime() }
  return Result.Success
end

-- Delivers a message from another player: fires CHAT_MSG_ADDON(prefix, text, channel, sender) as the game does.
function WOW.receive(prefix, text, channel, sender)
  return WOW.fire("CHAT_MSG_ADDON", prefix, text, channel or "RAID", sender)
end

-- Chat and slash commands ----------------------------------------------------------------------------------------

local function say(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  WOW.chat[#WOW.chat + 1] = table.concat(parts, " ")
end

-- print writes to the fake chat window (WOW.chat), not to the test's output. WOW.rawprint is the real one.
WOW.rawprint = rawprint
print = say

DEFAULT_CHAT_FRAME = {}
function DEFAULT_CHAT_FRAME:AddMessage(text)
  WOW.chat[#WOW.chat + 1] = tostring(text)
end

SlashCmdList = {}

-- Types a line into the chat box: finds the SLASH_<KEY><n> that matches the command and calls
-- SlashCmdList[KEY](rest). Returns true if a command ran.
function WOW.slash(line)
  local command, rest = line:match("^(/%S+)%s*(.*)$")
  if not command then return false end
  command = command:lower()
  for key, value in pairs(_G) do
    if type(key) == "string" and type(value) == "string" and value:lower() == command then
      local name = key:match("^SLASH_(.-)%d+$")
      if name and SlashCmdList[name] then
        protected(SlashCmdList[name], rest)
        return true
      end
    end
  end
  return false
end

-- Saved variables -----------------------------------------------------------------------------------------------

-- Names what the TOC's ## SavedVariables line names. The test calls this before WOW.loadAddon.
function WOW.declareSavedVariables(...)
  WOW.savedNames = { ... }
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta == "number" end
    if ta == "boolean" then return tostring(a) < tostring(b) end
    return a < b
  end)
  return keys
end

local function literal(value, indent, seen)
  local t = type(value)
  if t == "string" then return string.format("%q", value) end
  if t == "boolean" then return tostring(value) end
  if t == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      fail("a saved variable holds " .. tostring(value) .. ", which the game cannot write")
    end
    -- %d would fail in fengari past 2^31 (a time in milliseconds is 1.8e12), and %.0f is exact to 2^53.
    if value == math.floor(value) and math.abs(value) < 1e15 then return string.format("%.0f", value) end
    return string.format("%.17g", value)
  end
  if t ~= "table" then return nil end
  if seen[value] then fail("a saved variable holds a table that contains itself") end
  seen[value] = true
  local lines = {}
  for _, k in ipairs(sortedKeys(value)) do
    local kt = type(k)
    if kt ~= "string" and kt ~= "number" and kt ~= "boolean" then
      fail("a saved variable has a " .. kt .. " as a key")
    end
    local v = literal(value[k], indent .. "\t", seen)
    -- The game leaves out functions and userdata; so does this.
    if v then lines[#lines + 1] = indent .. "\t[" .. literal(k, "", seen) .. "] = " .. v .. "," end
  end
  seen[value] = nil
  if #lines == 0 then return "{}" end
  return "{\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "}"
end

-- Reads the saved file the way the game does when an addon loads: each declared variable becomes a global. A name
-- the file does not have stays nil.
function WOW.loadSavedVariables()
  for _, name in ipairs(WOW.savedNames) do _G[name] = copy(WOW.saved[name]) end
end

-- Writes the declared globals out as the game does at logout, to WOW.savedFile as Lua text, and reads that text
-- back into WOW.saved. So what a test sees is what the file would hold: a function is gone, a number that cannot be
-- written raises an error, and a table is a copy.
function WOW.writeSavedVariables()
  local out = {}
  for _, name in ipairs(WOW.savedNames) do
    local v = literal(_G[name], "", {})
    if v then out[#out + 1] = name .. " = " .. v .. "\n" end
  end
  return WOW.readSavedFile(table.concat(out))
end

-- Sets WOW.savedFile to `text`, a saved variables file, and WOW.saved to what it holds. A test uses it to start a
-- session from a file an earlier session wrote, or from an older one.
function WOW.readSavedFile(text)
  WOW.savedFile = text
  local env = {}
  local chunk = assert(loadstring(text, "=SavedVariables"))
  setfenv(chunk, env)()
  WOW.saved = env
  return env
end

-- Loading an addon and a session ---------------------------------------------------------------------------------

-- Runs one file of the repository (a path from its root) as the game runs an addon's files: with the addon's name
-- and its shared table as the arguments, which `local ADDON, ns = ...` reads.
function WOW.dofile(path, addon, ns)
  local chunk, err = loadfile(WOW.root .. "/" .. path)
  if not chunk then error(err, 2) end
  return chunk(addon, ns)
end

-- The bytes of a file of the repository (a path from its root, with forward slashes), as text; or nil and why.
-- Fengari has no io.open, so test/lua/run.mjs gives the state GG_READ; real Lua 5.1 uses io.open.
function WOW.readFile(path)
  if GG_READ then return GG_READ(path) end
  local handle, err = io.open(WOW.root .. "/" .. path, "rb")
  if not handle then return nil, err end
  local text = handle:read("*a")
  handle:close()
  return text
end

-- The files an addon's TOC lists, in the order the game loads them, as paths from the repository's root:
-- WOW.tocFiles("GuildGolem") reads GuildGolem/GuildGolem.toc, and a second argument names another TOC in the folder
-- ("GuildGolem_Camelot.toc"). Lines that are empty or start with # are not files. Backslashes become slashes.
function WOW.tocFiles(addon, toc)
  toc = toc or (addon .. ".toc")
  local text, err = WOW.readFile(addon .. "/" .. toc)
  if not text then error("WOW.tocFiles: " .. tostring(err), 2) end
  local files = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then files[#files + 1] = addon .. "/" .. line:gsub("\\", "/") end
  end
  return files
end

-- Loads an addon: runs its files in order, then loads its saved variables and fires ADDON_LOADED, as the game does.
-- Returns the shared table. Call WOW.login next to fire PLAYER_LOGIN. `files` is a list of paths from the
-- repository's root, or nil to read the list from the addon's TOC (WOW.tocFiles), so a test loads what the game
-- would, in the order the game would.
function WOW.loadAddon(addon, files, ns)
  files = files or WOW.tocFiles(addon)
  ns = ns or {}
  for _, path in ipairs(files) do WOW.dofile(path, addon, ns) end
  WOW.loadSavedVariables()
  WOW.fire("ADDON_LOADED", addon)
  return ns
end

-- PLAYER_LOGIN and PLAYER_ENTERING_WORLD, as a login (isInitialLogin true) or a reload (isReloadingUi true).
function WOW.login(isReload)
  WOW.fire("PLAYER_LOGIN")
  WOW.fire("PLAYER_ENTERING_WORLD", not isReload, isReload == true)
end

-- Logs out: fires PLAYER_LOGOUT, then writes the saved variables. Returns WOW.saved.
function WOW.logout()
  WOW.fire("PLAYER_LOGOUT")
  return WOW.writeSavedVariables()
end

WOW.reset()
