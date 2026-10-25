-- Launch-day tests (probe 0.2). Probe.lua holds the checks from 0.1 and the helpers; this file adds what the first
-- 20 minutes on the live client should record in one pass. See README.md ("The launch-day pass").
--
-- Every API is looked up and checked with type(x) == "function" before it is called, and every call runs in pcall, so
-- a missing function is recorded as missing and a refused call as its error. Everything is Lua 5.1.
--
--   combat logging  LoggingCombat() read and toggled, the advancedCombatLogging setting read, set and read back
--   boxes           copy boxes filled with 16, 64 and 256 KB (timed), and a paste box that records what was pasted
--   instance        GetInstanceInfo() on entering, BOSS_KILL, INSTANCE_ENCOUNTER_ENGAGE_UNIT (the other encounter
--                   events and the loot calls are in Probe.lua)
--   addon messages  a burst of 50 over party and raid, counted on arrival, and the C_ChatInfo results
--   api             which functions exist in the tables that matter, and the enums that name results and states

local _, ns = ...
if type(ns) ~= "table" or type(ns.record) ~= "function" then return end

local record, describe, isSecret, pack = ns.record, ns.describe, ns.isSecret, ns.pack
local lookup, after, say, where = ns.lookup, ns.after, ns.say, ns.where
local PREFIX = ns.PREFIX

local frame = CreateFrame("Frame")
local handlers = {}

-- Helpers ---------------------------------------------------------------------------------------------------------

-- Milliseconds, from the finest clock the client has.
local clockName = "GetTime"
local function clock()
  if type(debugprofilestop) == "function" then
    clockName = "debugprofilestop"
    return debugprofilestop()
  end
  if type(GetTimePreciseSec) == "function" then
    clockName = "GetTimePreciseSec"
    return GetTimePreciseSec() * 1000
  end
  return GetTime() * 1000
end

local function ms(value)
  return string.format("%.1f ms", value)
end

-- Runs a function found by its dotted name, or records that it is missing.
local function tryNamed(section, key, name, ...)
  local fn = lookup(name)
  if type(fn) ~= "function" then
    record(section, key, "missing: " .. name)
    return nil
  end
  return ns.try(section, key, fn, ...)
end

-- Api -------------------------------------------------------------------------------------------------------------

local TABLES = { "C_LootHistory", "C_CombatLog", "C_CombatLogSecure", "C_ChatInfo", "C_RestrictedActions", "C_Secrets", "C_CVar", "C_PartyInfo" }
local ENUMS = { "Enum.SendAddonMessageResult", "Enum.AddOnRestrictionType", "Enum.AddOnRestrictionState", "Enum.LootMethod" }
local SINGLES = {
  "LoggingCombat", "GetCVar", "SetCVar", "GetCVarInfo", "debugprofilestop", "GetTimePreciseSec", "GetLootMethod",
  "GetLootThreshold", "IsEncounterInProgress", "GetInstanceInfo", "GetDifficultyInfo", "GetLootRollItemLink", "GetNumLootItems",
}

local function listFunctions(path)
  local t = lookup(path)
  if type(t) ~= "table" then
    record("api", path, "missing (it is " .. type(t) .. ")")
    return
  end
  local names = {}
  local ok = pcall(function()
    for k, v in pairs(t) do
      if type(v) == "function" then names[#names + 1] = tostring(k) end
    end
  end)
  table.sort(names)
  record("api", path, (ok and "" or "(stopped early) ") .. #names .. " functions: " .. table.concat(names, ", "), nil, 4000)
end

local function dumpEnum(path)
  local t = lookup(path)
  if type(t) ~= "table" then
    record("api", path, "missing (it is " .. type(t) .. ")")
    return
  end
  local rows = {}
  for k, v in pairs(t) do rows[#rows + 1] = tostring(k) .. "=" .. tostring(v) end
  table.sort(rows)
  record("api", path, table.concat(rows, ", "), nil, 2000)
end

local function checkApis()
  for _, path in ipairs(TABLES) do listFunctions(path) end
  for _, path in ipairs(ENUMS) do dumpEnum(path) end
  local present, missing = {}, {}
  for _, name in ipairs(SINGLES) do
    if type(lookup(name)) == "function" then present[#present + 1] = name else missing[#missing + 1] = name end
  end
  record("api", "single functions present", #present == 0 and "none" or table.concat(present, ", "))
  record("api", "single functions missing", #missing == 0 and "none" or table.concat(missing, ", "))
  clock()
  record("api", "timer used for timings", clockName)
end

-- The results C_ChatInfo gives for the things the real addon will do.
local function checkChatInfo()
  tryNamed("addon messages", "prefix registered (IsAddonMessagePrefixRegistered)", "C_ChatInfo.IsAddonMessagePrefixRegistered", PREFIX)
  local list = lookup("C_ChatInfo.GetRegisteredAddonMessagePrefixes")
  if type(list) == "function" then
    local ok, prefixes = pcall(list)
    record("addon messages", "prefixes registered by all addons", ok and type(prefixes) == "table" and #prefixes or describe(prefixes))
  else
    record("addon messages", "prefixes registered by all addons", "missing: C_ChatInfo.GetRegisteredAddonMessagePrefixes")
  end
  tryNamed("addon messages", "chat messaging lockdown @ " .. where(), "C_ChatInfo.InChatMessagingLockdown")
  record("addon messages", "restriction states @ " .. where(), ns.restrictionStates())
end

-- Combat logging ----------------------------------------------------------------------------------------------------

local CVAR = "advancedCombatLogging"

-- Reads the logging switch. Retail gives a boolean, older clients 1 or nil.
local function readLogging(fn)
  local ok, value = pcall(fn)
  if not ok then return nil, "error: " .. tostring(value) end
  return value == true or value == 1, describe(value)
end

local function checkLogging()
  local section, suffix = "combat logging", " @ " .. where()
  local fn = lookup("LoggingCombat")
  if type(fn) ~= "function" then
    record(section, "LoggingCombat", "missing")
    return
  end
  local before, text = readLogging(fn)
  record(section, "LoggingCombat() read" .. suffix, text)
  if before == nil then return end
  local target = not before
  local set = pack(pcall(fn, target))
  local middle, middleText = readLogging(fn)
  record(section, "LoggingCombat(" .. tostring(target) .. ") toggled" .. suffix,
    "call " .. (set[1] and "ran" or ("failed: " .. tostring(set[2]))) .. ", returned " .. describe(pack(select(2, unpack(set, 1, set.n)))) ..
    ", read back " .. tostring(middleText) .. ", " .. (middle == target and "it changed" or "it did not change"))
  -- Put it back.
  local restore = pack(pcall(fn, before))
  local after_, afterText = readLogging(fn)
  record(section, "LoggingCombat restored" .. suffix,
    "call " .. (restore[1] and "ran" or ("failed: " .. tostring(restore[2]))) .. ", read back " .. tostring(afterText) ..
    ", " .. (after_ == before and "back as it was" or "NOT back as it was"))
end

local function getCVar(name)
  local get = lookup("C_CVar.GetCVar")
  if type(get) ~= "function" then get = lookup("GetCVar") end
  if type(get) ~= "function" then return nil, "no GetCVar" end
  local ok, value = pcall(get, name)
  if not ok then return nil, "error: " .. tostring(value) end
  return value, nil
end

local function checkCVar()
  local section, suffix = "combat logging", " @ " .. where()
  local info = lookup("C_CVar.GetCVarInfo")
  if type(info) ~= "function" then info = lookup("GetCVarInfo") end
  if type(info) == "function" then
    -- Current value, default, stored on the server (account, character), locked, secure, read only.
    record(section, CVAR .. " info (current, default, account, character, locked, secure, read only)", pack(pcall(info, CVAR)))
  else
    record(section, CVAR .. " info", "missing: GetCVarInfo")
  end
  local value, problem = getCVar(CVAR)
  if problem then
    record(section, CVAR .. " read" .. suffix, problem)
    return
  end
  if value == nil then
    record(section, CVAR .. " read" .. suffix, "nil: the setting does not exist, or cannot be read")
  else
    record(section, CVAR .. " read" .. suffix, describe(value))
  end
  local set = lookup("C_CVar.SetCVar")
  if type(set) ~= "function" then set = lookup("SetCVar") end
  if type(set) ~= "function" then
    record(section, CVAR .. " set" .. suffix, "missing: SetCVar")
    return
  end
  local other = (value == "1" or value == 1 or value == true) and "0" or "1"
  local result = pack(pcall(set, CVAR, other))
  local back = getCVar(CVAR)
  record(section, CVAR .. " set to " .. other .. suffix,
    "call " .. (result[1] and "ran" or ("failed: " .. tostring(result[2]))) .. ", returned " .. describe(pack(select(2, unpack(result, 1, result.n)))) ..
    ", read back " .. describe(back) .. ", " .. (tostring(back) == other and "it changed" or "it did not change"))
  if value ~= nil then
    pcall(set, CVAR, value)
    local final = getCVar(CVAR)
    record(section, CVAR .. " restored" .. suffix, "read back " .. describe(final) .. ", " .. (tostring(final) == tostring(value) and "back as it was" or "NOT back as it was"))
  end
end

local function checkCombatLogging()
  checkLogging()
  checkCVar()
end

-- Boxes -----------------------------------------------------------------------------------------------------------

local SIZES = { { "16 KB", 16 * 1024 }, { "64 KB", 64 * 1024 }, { "256 KB", 256 * 1024 } }
local CHUNK = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_-" -- 64 bytes
local STALL = 250 -- a frame this many milliseconds long counts as a stall

local boxes
local gaps = { last = nil, longest = 0 }
local fillBytes = 0 -- what the copy box held after the last fill
local running = false
local paste = { length = 0, changes = 0, pending = false, biggest = 0 }

local function makeText(bytes, shape)
  local chunk = shape == "lines" and (CHUNK:sub(1, 63) .. "\n") or CHUNK
  return string.rep(chunk, math.floor(bytes / 64))
end

local function showStatus(text)
  if not boxes then return end
  boxes.lines[#boxes.lines + 1] = text
  while #boxes.lines > 7 do table.remove(boxes.lines, 1) end
  boxes.status:SetText(table.concat(boxes.lines, "\n"))
end

-- One fill of the copy box: SetText, select all, read it back, then wait for a couple of frames to see whether the
-- client stalled.
local function fill(label, bytes, shape, done)
  local edit = boxes.copy
  local key = "copy box " .. label .. (shape == "lines" and ", short lines" or ", one long line")
  local text = makeText(bytes, shape)
  say("filling the copy box with " .. label .. " (" .. shape .. "). The game may freeze for a moment.")
  record("boxes", key, "started, not finished (the client stalled for good, or the fill failed before it recorded)")
  local parts = {}
  gaps.longest = 0
  gaps.last = clock()
  local t0 = clock()
  local setOk, setErr = pcall(edit.SetText, edit, text)
  local t1 = clock()
  parts[#parts + 1] = "SetText " .. (setOk and ms(t1 - t0) or ("failed: " .. tostring(setErr)))
  pcall(edit.SetFocus, edit)
  local t2 = clock()
  local selOk, selErr = pcall(edit.HighlightText, edit)
  local t3 = clock()
  parts[#parts + 1] = "select all " .. (selOk and ms(t3 - t2) or ("failed: " .. tostring(selErr)))
  local t4 = clock()
  local getOk, back = pcall(edit.GetText, edit)
  local t5 = clock()
  if getOk and type(back) == "string" then
    parts[#parts + 1] = "GetText " .. ms(t5 - t4)
    parts[#parts + 1] = "read back " .. #back .. " of " .. #text .. " bytes (" .. (#back == #text and "intact" or "CUT OR CHANGED") .. ")"
    fillBytes = #back
  else
    parts[#parts + 1] = "GetText failed: " .. tostring(back)
  end
  if type(edit.GetNumLetters) == "function" then
    local okLetters, letters = pcall(edit.GetNumLetters, edit)
    if okLetters then parts[#parts + 1] = letters .. " letters" end
  end
  -- The frames after the fill carry the layout and drawing time, so wait for them.
  after(2, function()
    local longest = gaps.longest
    parts[#parts + 1] = "longest frame after the fill " .. ms(longest) .. " (" .. (longest >= STALL and "STALLED" or "no stall") .. ")"
    local line = table.concat(parts, ", ")
    record("boxes", key, line, nil, 1200)
    showStatus(label .. ", " .. shape .. ": " .. line)
    done()
  end)
end

local function runFills(list)
  if running then return say("the copy tests are still running.") end
  running = true
  local i = 0
  local function nextFill()
    i = i + 1
    local item = list[i]
    if not item then
      running = false
      say("copy tests finished. See /ggprobe, section [boxes].")
      return
    end
    fill(item[1], item[2], item[3], function() after(0.5, nextFill) end)
  end
  nextFill()
end

local function allFills()
  local list = {}
  for _, size in ipairs(SIZES) do
    list[#list + 1] = { size[1], size[2], "one line" }
    list[#list + 1] = { size[1], size[2], "lines" }
  end
  return list
end

local function finishPaste()
  paste.pending = false
  local p = paste.latest
  if not p then return end
  paste.latest = nil
  local copyNote = fillBytes > 0 and (p.added == fillBytes and ", the same size as the copy box" or (", the copy box held " .. fillBytes .. " bytes")) or ""
  local line = string.format("added %d bytes (the box holds %d, %d letters), GetText took %s, %d text changes in the second after, longest frame after the paste %s (%s)%s",
    p.added, p.bytes, p.letters or -1, ms(p.readMs), p.changes, ms(gaps.longest), gaps.longest >= STALL and "STALLED" or "no stall", copyNote)
  record("boxes", "paste box: last paste", line, nil, 800)
  if p.added > paste.biggest then
    paste.biggest = p.added
    record("boxes", "paste box: largest paste", line, nil, 800)
  end
  showStatus("pasted: " .. line)
end

-- A paste arrives as one big change; typing arrives a letter at a time and is ignored.
local function pasteChanged(edit, userInput)
  local t0 = clock()
  local ok, text = pcall(edit.GetText, edit)
  local t1 = clock()
  if not ok or type(text) ~= "string" then return end
  local added = #text - paste.length
  paste.length = #text
  paste.changes = paste.changes + 1
  if added < 32 then return end
  gaps.longest = 0
  local letters
  if type(edit.GetNumLetters) == "function" then
    local okLetters, count = pcall(edit.GetNumLetters, edit)
    if okLetters then letters = count end
  end
  paste.latest = { added = added, bytes = #text, letters = letters, readMs = t1 - t0, changes = paste.changes, user = userInput }
  paste.changes = 0
  if not paste.pending then
    paste.pending = true
    after(1.5, finishPaste)
  end
end

local function newButton(parent, label, width, onClick)
  local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
  if not ok or not b then
    b = CreateFrame("Button", nil, parent)
    b:SetNormalFontObject("GameFontNormal")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
  end
  b:SetSize(width, 22)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function buildBoxes()
  local f = ns.newWindow("GuildGolemProbeBoxes", 720, 580, "Guild Golem Probe: copy and paste boxes")
  local intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  intro:SetPoint("TOPLEFT", 14, -30)
  intro:SetWidth(690)
  intro:SetJustifyH("LEFT")
  intro:SetText("The top box is filled with test text and timed. To test pasting, click a size, click in the top box, press Ctrl+A then Ctrl+C, click in the lower box and press Ctrl+V. The length of what you pasted is recorded.")

  local copy, copyScroll = ns.newTextBox(f, "GuildGolemProbeCopyScroll", 640)
  copyScroll:SetPoint("TOPLEFT", 12, -92)
  copyScroll:SetSize(650, 150)
  local pasteBox, pasteScroll = ns.newTextBox(f, "GuildGolemProbePasteScroll", 640)
  pasteScroll:SetPoint("TOPLEFT", 12, -280)
  pasteScroll:SetSize(650, 150)
  pasteBox:SetScript("OnTextChanged", pasteChanged)

  local pasteLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  pasteLabel:SetPoint("TOPLEFT", 14, -246)
  pasteLabel:SetText("Paste box (Ctrl+V here)")

  local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", 14, -440)
  status:SetWidth(690)
  status:SetJustifyH("LEFT")
  status:SetJustifyV("TOP")

  f.copy, f.paste, f.status, f.lines = copy, pasteBox, status, {}

  local x = 14
  local function add(label, width, onClick)
    local b = newButton(f, label, width, onClick)
    b:SetPoint("TOPLEFT", x, -64)
    x = x + width + 6
  end
  add("Run all", 70, function() runFills(allFills()) end)
  for _, size in ipairs(SIZES) do
    add(size[1], 60, function() runFills({ { size[1], size[2], "one line" }, { size[1], size[2], "lines" } }) end)
  end
  add("Clear both", 80, function()
    pcall(copy.SetText, copy, "")
    pcall(pasteBox.SetText, pasteBox, "")
    paste.length, fillBytes = 0, 0
  end)

  -- The frame clock: the gap between two frames shows a stall.
  local watch = CreateFrame("Frame", nil, f)
  watch:SetScript("OnUpdate", function()
    local t = clock()
    if gaps.last and t - gaps.last > gaps.longest then gaps.longest = t - gaps.last end
    gaps.last = t
  end)

  f:SetScript("OnHide", function()
    pcall(copy.SetText, copy, "")
    pcall(pasteBox.SetText, pasteBox, "")
    paste.length, fillBytes = 0, 0
  end)
  return f
end

local function openBoxes()
  if not boxes then boxes = buildBoxes() end
  boxes:Show()
  after(0.5, function() runFills(allFills()) end)
  say("copy and paste boxes open. The six fills run by themselves; the game may freeze for a few seconds at a time.")
end

-- Instances -------------------------------------------------------------------------------------------------------

local function instanceEntry(reason)
  local ok, inside, kind = pcall(IsInInstance)
  if not ok or not inside then return false end
  local info = pack(pcall(GetInstanceInfo))
  local name = info[2]
  record("instance", "GetInstanceInfo on entering " .. (isSecret(name) and "<secret>" or tostring(name)), {
    info = info, kind = kind, groupSize = GetNumGroupMembers(), chatLockdown = ns.lockdown(), restrictions = ns.restrictionStates(), reason = reason,
  }, 3, 1500)
  return true
end

local function bossUnits()
  local out = {}
  for i = 1, 8 do
    local unit = "boss" .. i
    local ok, exists = pcall(UnitExists, unit)
    if ok and not isSecret(exists) and exists then
      local row = { unit = unit }
      local named, name = pcall(UnitName, unit)
      row.name = named and name or "error"
      local guided, guid = pcall(UnitGUID, unit)
      row.guid = guided and guid or "error"
      out[#out + 1] = row
    end
  end
  return out
end

handlers.BOSS_KILL = function(...)
  record("encounters", "BOSS_KILL #" .. ns.nextN("BOSS_KILL"), { args = pack(...), clock = date("%H:%M:%S") }, 3, 1500)
end

-- It fires several times in a pull; the newest answer of each pull is kept, with how many times it fired.
handlers.INSTANCE_ENCOUNTER_ENGAGE_UNIT = function(...)
  local db = ns.db()
  local pull = db and db.counters and db.counters.ENCOUNTER_START or 0
  local fires = ns.nextN("INSTANCE_ENCOUNTER_ENGAGE_UNIT in pull " .. pull)
  record("encounters", "INSTANCE_ENCOUNTER_ENGAGE_UNIT in pull #" .. pull .. " (newest)", {
    fires = fires, args = pack(...), bosses = bossUnits(), clock = date("%H:%M:%S"),
  }, 4, 1500)
end

handlers.PLAYER_ENTERING_WORLD = function(initial, reloading)
  if initial or reloading then
    after(5, checkApis)
    after(7, checkChatInfo)
    after(12, checkCombatLogging)
  end
  after(4, function()
    -- The combat logging answer can differ inside an instance, so ask again there.
    if instanceEntry("entering") then after(5, checkCombatLogging) end
  end)
end

-- Addon messages --------------------------------------------------------------------------------------------------

local nonce = tostring(math.random(100000, 999999)) -- tells this load's bursts from another player's
local bursts = {}
local fromOthers = {}

local function resultName(result)
  if result == nil then return "no result" end
  if result == true then return "true" end
  return ns.enumName("Enum.SendAddonMessageResult", result) or describe(result)
end

local function sentWell(entry)
  return entry.ok and (entry.result == true or resultName(entry.result) == "Success")
end

local function finishBurst(b, when)
  local codes, accepted, firstRefused = {}, 0, nil
  for seq = 1, b.count do
    local entry = b.sent[seq]
    local name = entry.ok and resultName(entry.result) or ("error: " .. tostring(entry.result))
    codes[name] = (codes[name] or 0) + 1
    if sentWell(entry) then
      accepted = accepted + 1
    elseif not firstRefused then
      firstRefused = seq
    end
  end
  local codeList = {}
  for name, n in pairs(codes) do codeList[#codeList + 1] = name .. " x" .. n end
  table.sort(codeList)

  local received, firstAt, lastAt, missing, arrivals = 0, nil, nil, {}, {}
  for seq = 1, b.count do
    local at = b.got[seq]
    if at then
      received = received + 1
      if not firstAt or at < firstAt then firstAt = at end
      if not lastAt or at > lastAt then lastAt = at end
      arrivals[#arrivals + 1] = seq .. ":" .. math.floor(at + 0.5)
    elseif #missing < 12 then
      missing[#missing + 1] = seq
    end
  end
  local sendLoop = b.sent[b.count].at
  local text = string.format("sent %d, the game accepted %d (%s), first refused at message %s, the send loop took %s, received back %d of %d%s%s (%s)",
    b.count, accepted, table.concat(codeList, ", "), firstRefused and tostring(firstRefused) or "none", ms(sendLoop), received, b.count,
    firstAt and (", first after " .. ms(firstAt) .. ", last after " .. ms(lastAt)) or "",
    #missing > 0 and (", first missing " .. table.concat(missing, " ")) or "", when)
  record("addon messages", b.key, text, nil, 1500)
  if #arrivals > 0 then record("addon messages", b.key .. " arrival ms by message", table.concat(arrivals, " "), nil, 1800) end
end

local function runBurst(chatType, count, label, target)
  local key = "burst " .. label .. " on " .. tostring(chatType) .. " @ " .. where()
  local send = lookup("C_ChatInfo.SendAddonMessage")
  if type(send) ~= "function" then return record("addon messages", key, "missing: C_ChatInfo.SendAddonMessage") end
  if not chatType then return record("addon messages", key, "not in a group or guild") end
  local id = ns.nextN("burst")
  local b = { key = key, count = count, sent = {}, got = {}, startedAt = clock() }
  bursts[id] = b
  for seq = 1, count do
    local at = clock() - b.startedAt
    local r = pack(pcall(send, PREFIX, string.format("b:%s:%d:%d:%d", nonce, id, seq, count), chatType, target))
    b.sent[seq] = { ok = r[1], result = r[2], at = at }
  end
  after(10, function() finishBurst(b, "after 10 s") end)
  after(40, function() finishBurst(b, "after 40 s") end)
end

-- What the game does with a message or a prefix that is too long.
local function checkLimits(chatType)
  local send = lookup("C_ChatInfo.SendAddonMessage")
  if type(send) ~= "function" or not chatType then return end
  local long = pack(pcall(send, PREFIX, string.rep("x", 256), chatType))
  local prefix = pack(pcall(send, string.rep("p", 17), "x", chatType))
  record("addon messages", "limits on " .. chatType .. " @ " .. where(),
    "a 256 byte message gives " .. (long[1] and resultName(long[2]) or ("error: " .. tostring(long[2]))) ..
    ", a 17 character prefix gives " .. (prefix[1] and resultName(prefix[2]) or ("error: " .. tostring(prefix[2]))))
end

handlers.CHAT_MSG_ADDON = function(prefix, text, chatType, sender)
  if prefix ~= PREFIX or type(text) ~= "string" or isSecret(text) then return end
  local who, id, seq, count = text:match("^b:(%d+):(%d+):(%d+):(%d+)$")
  if not who then return end
  local at = clock()
  id, seq, count = tonumber(id), tonumber(seq), tonumber(count)
  if who == nonce then
    local b = bursts[id]
    if b and b.got[seq] == nil then b.got[seq] = at - b.startedAt end
    return
  end
  if isSecret(sender) then return end
  local key = tostring(sender) .. " " .. who .. " " .. id
  local other = fromOthers[key]
  if not other then
    other = { count = 0, first = at, total = count, chatType = chatType, sender = sender }
    fromOthers[key] = other
    after(12, function()
      record("addon messages", "burst from another player #" .. ns.nextN("burst from another player"),
        string.format("%s sent %d on %s, %d arrived over %s (first at %s)", tostring(other.sender), other.total, tostring(other.chatType), other.count, ms(other.last - other.first), date("%H:%M:%S")), nil, 600)
    end)
  end
  other.count = other.count + 1
  other.last = at
end

-- The channels a burst should try: the party, the raid when in one, and the instance group.
local function burstChannels()
  local list = {}
  if IsInGroup() then list[#list + 1] = "PARTY" end
  if IsInRaid() then list[#list + 1] = "RAID" end
  if type(LE_PARTY_CATEGORY_INSTANCE) == "number" and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then list[#list + 1] = "INSTANCE_CHAT" end
  return list
end

ns.burst = runBurst

-- Commands --------------------------------------------------------------------------------------------------------

ns.commands.combatlog = function()
  checkCombatLogging()
  say("combat logging read, toggled and put back; see /ggprobe, section [combat logging].")
end

ns.commands.boxes = openBoxes

ns.commands.api = function()
  checkApis()
  checkChatInfo()
  say("api lists written; see /ggprobe, section [api].")
end

ns.commands.instance = function()
  if instanceEntry("asked") then say("instance read; see /ggprobe, section [instance].") else say("you are not in an instance.") end
end

ns.commands.loot = function()
  ns.readLootMethod()
  ns.readLootHistory()
  say("loot method and loot history read; see /ggprobe, sections [loot] and [loot history].")
end

ns.commands.burst = function(rest)
  local channels = rest:lower() == "guild" and { "GUILD" } or burstChannels()
  if #channels == 0 then return say("join a party first (or type /ggprobe burst guild).") end
  checkLimits(channels[1])
  -- The sending allowance refills slowly, so each channel waits for the one before it.
  for i, chatType in ipairs(channels) do
    after(1 + (i - 1) * 13, function() runBurst(chatType, 50, "asked") end)
  end
  say("sending 50 messages on " .. table.concat(channels, ", ") .. ". The counts are ready after 40 seconds; see /ggprobe, section [addon messages].")
end

ns.help[#ns.help + 1] = "/ggprobe boxes - open the copy and paste boxes and time them"
ns.help[#ns.help + 1] = "/ggprobe burst - 50 addon messages over your party (and raid), counted when they arrive"
ns.help[#ns.help + 1] = "/ggprobe combatlog - read, toggle and restore combat logging and the advancedCombatLogging setting"
ns.help[#ns.help + 1] = "/ggprobe loot - read the loot method, the master looter and the loot history"
ns.help[#ns.help + 1] = "/ggprobe instance - GetInstanceInfo() and the restriction states, when in an instance"
ns.help[#ns.help + 1] = "/ggprobe api - which functions exist in the tables that matter"

ns.onReset[#ns.onReset + 1] = function()
  bursts, fromOthers = {}, {}
  paste.length, paste.changes, paste.biggest, paste.latest = 0, 0, 0, nil
end

frame:SetScript("OnEvent", function(_, event, ...)
  local handler = handlers[event]
  if not handler then return end
  local ok, err = pcall(handler, ...)
  if not ok then record("errors", event, tostring(err)) end
end)
ns.register(frame, handlers)
