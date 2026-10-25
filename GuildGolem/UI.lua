-- The window and the slash commands (docs/PLAN.md, "Core"): one small window with a paste box for imports, a copy box for
-- the exports waiting to be pasted on the site, and a status line; and /gg. This file names no frame and no game function:
-- the window is built by ns.Client.window from a description, so everything here runs in a test with the window as plain
-- data.
--
--   /gg                  opens or closes the window
--   /gg status           prints the version, the imported night, what is being recorded, the outbox and the client's gaps
--   /gg export [all]     makes an export from what was recorded since the last one (or everything) and shows it
--   /gg test on|off      test recording: while on, a party in a 5-man dungeon is recorded like a raid and its export is marked
--                        as a test, so the whole path can be tried before any raid is open
--   /gg log on|off       whether the addon turns combat logging on when you enter a raid (it never turns it off)
--   /gg help
--
--   UI.init()            registers the slash command; Main.lua calls it
--   UI.slash(text)       what /gg does with the words after it
--   UI.statusLines()     the lines /gg status prints
--   UI.window()          the window's handle, made when first asked for (nil if the client would not build it)
--   UI.refresh()         redraws the status line and the copy box

local ADDON, ns = ...

local UI = {}
ns.UI = UI

local format = string.format

local PREFIX = "|cffff8800Guild Golem:|r "

local function client() return ns.Client end

local function say(text)
  print(PREFIX .. text)
end

-- Site text is drawn safely: a | in a title would start a colour or a link.
local function safe(text)
  return ns.Import.escape(text or "")
end

local function plural(n, one, many)
  if n == 1 then return format("%d %s", n, one) end
  return format("%d %s", n, many or (one .. "s"))
end

-- 1.2.3 against 1.10.0, as numbers by dot, a suffix ignored (contract/README.md, `latest`). True when `a` is older.
function UI.older(a, b)
  local function parts(v)
    local x, y, z = tostring(v or ""):match("^v?(%d+)%.(%d+)%.(%d+)")
    if not x then return nil end
    return { tonumber(x), tonumber(y), tonumber(z) }
  end
  local pa, pb = parts(a), parts(b)
  if not pa or not pb then return false end
  for i = 1, 3 do
    if pa[i] ~= pb[i] then return pa[i] < pb[i] end
  end
  return false
end

-- What was read -------------------------------------------------------------------------------------------------------------

local KIND = {
  priorities = "Loot priorities",
  ["night-loot"] = "A night's loot",
  ["night-assignments"] = "A night's assignments",
  night = "A night's plan",
}

-- A summary (Import.summary) in plain words.
local function describe(summary, parsed)
  local what = KIND[summary.from] or "An import"
  local parts = { plural(summary.raids, "raid"), plural(summary.people, "person", "people") }
  if summary.items > 0 then parts[#parts + 1] = plural(summary.items, "item") end
  if summary.assignments > 0 then parts[#parts + 1] = plural(summary.assignments, "boss assignment") end
  local text = what
  if summary.night then text = text .. " for \"" .. safe(summary.night) .. "\"" end
  if summary.guild then text = text .. " (" .. safe(summary.guild) .. ")" end
  text = text .. ": " .. table.concat(parts, ", ") .. "."
  if parsed and parsed.latest and UI.older(ns.version, parsed.latest) then
    text = text .. " A newer addon is out (" .. safe(parsed.latest) .. ")."
  end
  return text
end
UI.describe = describe

local SAVE_FAILED = {
  ["read-only"] = "Nothing was saved: the saved data is from a newer addon. Update the addon.",
  ["not-ready"] = "Nothing was saved: the addon has not finished loading.",
  older = "Nothing was saved: you already hold a newer copy of this.",
}

local pending   -- the import read from the paste box and not yet kept

-- Runs when the paste box has settled: reads what is in it and says what it is, or why it is not.
local function onPaste(text)
  local w = UI.window()
  if not w then return end
  if text == nil or text:find("^%s*$") then
    pending = nil
    w.setNote("")
    w.setEnabled("import", false)
    return
  end
  local parsed, _, says = ns.Import.read(text)
  if not parsed then
    pending = nil
    w.setNote(safe(says))
    w.setEnabled("import", false)
    return
  end
  pending = parsed
  w.setNote(describe(ns.Import.summary(parsed), parsed) .. " Press Import to keep it.")
  w.setEnabled("import", true)
end
UI.onPaste = onPaste

local function onImport()
  local w = UI.window()
  if not w or not pending then return end
  local summary, why = ns.Import.save(pending)
  if not summary then
    w.setNote(SAVE_FAILED[why] or ("Nothing was saved (" .. tostring(why) .. ")."))
    return
  end
  local parsed = pending
  pending = nil
  w.setPaste("")
  w.setEnabled("import", false)
  w.setNote("Imported. " .. describe(summary, parsed))
  UI.refresh()
end

-- The exports waiting --------------------------------------------------------------------------------------------------------

local view = 1   -- which waiting export the copy box shows
local newExport = false   -- an export was just made, so the next showing selects it

local function waiting()
  return ns.Store.outboxPending()
end

-- Shows the export at `view` in the copy box. `select` selects it and puts the keyboard there, for when the player has just
-- asked for an export or stepped to another.
local function showExport(w, select)
  local list = waiting()
  if #list == 0 then
    w.setCopyLabel("Nothing is waiting to be pasted on the site. Press Export to make one.")
    w.setCopy("")
    w.setEnabled("pasted", false)
    w.setEnabled("prev", false)
    w.setEnabled("next", false)
    return
  end
  if view > #list then view = #list end
  if view < 1 then view = 1 end
  w.setCopyLabel(format("Export %d of %d waiting. It is selected: press Ctrl+C, then paste it on guildgolem.com.", view, #list))
  w.setCopy(list[view].text, select)
  w.setEnabled("pasted", true)
  w.setEnabled("prev", view > 1)
  w.setEnabled("next", view < #list)
end

local function onExport(all)
  local result, _, says = ns.Export.make({ all = all })
  if not result then
    say(says)
    local w = UI.window()
    if w then w.setNote(says) end
    return nil
  end
  local list = waiting()
  view = math.max(1, #list - result.count + 1)
  newExport = true
  say(format("Made %s from %s and %s (%d characters). Open /gg to copy %s.",
    plural(result.count, "export string"), plural(result.raids, "raid"), plural(result.snapshots, "snapshot"),
    result.characters, result.count == 1 and "it" or "them"))
  UI.refresh()
  return result
end

-- The status ---------------------------------------------------------------------------------------------------------------------

local function clock(ms)
  if not ms then return "?" end
  return os.date("!%H:%M", ms / 1000) .. " UTC"
end

-- Whether test recording is on (the `testDungeons` setting).
local function testing()
  return ns.Store.setting("testDungeons", false) == true
end

-- The client's gaps: the capabilities Client.caps() says are missing.
function UI.gaps()
  local missing = {}
  for name, have in pairs(client().caps()) do
    if not have then missing[#missing + 1] = name end
  end
  table.sort(missing)
  return missing
end

-- The night the imports gave, as one line, or nil.
local function nightLine()
  local db = ns.Store.db()
  local newest
  for _, night in pairs(db and db.nights or {}) do
    if not newest or (night.made or 0) > (newest.made or 0) then newest = night end
  end
  if not newest then return nil end
  local names = {}
  for _, raid in ipairs(newest.raids or {}) do names[#names + 1] = safe(raid.name) end
  return format("Imported night: \"%s\", %s%s.", safe(newest.title), plural(#names, "raid"),
    #names > 0 and (" (" .. table.concat(names, ", ") .. ")") or "")
end

function UI.statusLines()
  local lines = {}
  lines[#lines + 1] = "Guild Golem " .. tostring(ns.version)
  lines[#lines + 1] = nightLine() or "No night imported. Paste an import from guildgolem.com in /gg."

  if testing() then
    lines[#lines + 1] = "TEST RECORDING IS ON: a party in a 5-man dungeon is recorded like a raid, and its export is marked as a test. /gg test off stops it."
  end

  local state = ns.Attendance.state()
  if state.recording then
    local r = state.raid
    lines[#lines + 1] = format("Recording %s%s (%d players, difficulty %d): %s, the last at %s.", safe(r.name), r.test and " as a test" or "",
      r.size, r.difficulty, plural(r.snapshots, "snapshot"), clock(r.last))
  else
    lines[#lines + 1] = format("Not recording. %s kept.", plural(state.raids, "raid"))
  end

  local waitingCount = #waiting()
  lines[#lines + 1] = waitingCount == 0 and "Outbox: nothing waiting to be pasted on the site."
    or ("Outbox: " .. plural(waitingCount, "export") .. " waiting to be pasted on the site.")

  local caps = client().caps()
  local logging = "Combat logging: "
  if not caps.loggingCombat then
    logging = logging .. "this client cannot turn it on."
  else
    logging = logging .. (client().loggingCombat() and "on" or "off") .. "; the addon turns it on in a raid: "
      .. (ns.Store.setting("autoLog", true) == false and "no" or "yes") .. "."
  end
  lines[#lines + 1] = logging

  local gaps = UI.gaps()
  lines[#lines + 1] = #gaps == 0 and "The client has everything the addon asks of it."
    or ("The client lacks: " .. table.concat(gaps, ", ") .. ".")

  -- Game events the client would not let the addon listen to (Events.on found no such event).
  local unknown = {}
  for event in pairs(ns.Events.unknown) do unknown[#unknown + 1] = event end
  table.sort(unknown)
  if #unknown > 0 then lines[#lines + 1] = "The client would not register these events: " .. table.concat(unknown, ", ") .. "." end
  return lines
end

function UI.statusLine()
  local state = ns.Attendance.state()
  local text
  if state.recording then
    text = format("Recording %s: %s.", safe(state.raid.name), plural(state.raid.snapshots, "snapshot"))
  else
    text = "Not recording."
  end
  local n = #waiting()
  if n > 0 then text = text .. " " .. plural(n, "export") .. " waiting." end
  if testing() then text = "TEST RECORDING IS ON (dungeons count). " .. text end
  return text
end

-- The window ---------------------------------------------------------------------------------------------------------------------

local window, failed

-- The window's handle; built on first use. Nil if the client would not build one.
function UI.window()
  if window then return window end
  if failed then return nil end
  local w, why = client().window({
    name = "GuildGolemWindow",
    title = "Guild Golem",
    width = 580,
    height = 380,
    pasteLabel = "Import: paste a string from guildgolem.com here",
    copyLabel = "",
    buttons = {
      { key = "import", label = "Import", width = 80 },
      { key = "export", label = "Export", width = 80 },
      { key = "prev", label = "<", width = 30 },
      { key = "next", label = ">", width = 30 },
      { key = "pasted", label = "Pasted on the site", width = 140 },
    },
  })
  if not w then
    failed = why or true
    say("The window could not be made (" .. tostring(why) .. "). /gg status and /gg export still work.")
    return nil
  end
  window = w
  w.onPaste(onPaste)
  w.onClick("import", onImport)
  w.onClick("export", function() onExport(false) end)
  w.onClick("prev", function()
    view = view - 1
    showExport(w, true)
  end)
  w.onClick("next", function()
    view = view + 1
    showExport(w, true)
  end)
  w.onClick("pasted", function()
    local list = waiting()
    if list[view] then ns.Store.outboxMarkPasted(list[view].id) end
    UI.refresh(true)
  end)
  w.setEnabled("import", false)
  return w
end

-- Redraws the status line and the copy box. `select` is for the copy box: select it and give it the keyboard.
function UI.refresh(select)
  if not window then return end
  window.setStatus(UI.statusLine())
  showExport(window, select or newExport)
  newExport = false
end

local function toggle()
  local w = UI.window()
  if not w then return end
  if w.isShown() then
    w.hide()
  else
    UI.refresh()
    w.show()
  end
end

local function open()
  local w = UI.window()
  if not w then return end
  UI.refresh()
  w.show()
end

-- Slash commands -----------------------------------------------------------------------------------------------------------------

local HELP = {
  "/gg: open or close the window (paste an import, copy an export)",
  "/gg status: what the addon has and is doing",
  "/gg export: make an export of what was recorded since the last one (/gg export all: everything)",
  "/gg log on|off: whether the addon turns combat logging on when you enter a raid",
  "/gg test on|off: test recording, for trying the addon in a 5-man dungeon: it is recorded like a raid and exported as a test",
}

function UI.slash(text)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local command, rest = text:match("^(%S+)%s*(.*)$")
  command = command and command:lower() or ""
  rest = (rest or ""):lower()

  if command == "" or command == "show" or command == "toggle" then
    toggle()
  elseif command == "hide" then
    if window then window.hide() end
  elseif command == "status" then
    for _, line in ipairs(UI.statusLines()) do say(line) end
  elseif command == "export" then
    if onExport(rest == "all") then open() end
  elseif command == "log" then
    if rest == "on" or rest == "off" then
      local ok = ns.Store.setSetting("autoLog", rest == "on")
      if ok then
        say(rest == "on" and "Combat logging will be turned on when you enter a raid." or "The addon will not turn combat logging on.")
      else
        say("That could not be saved.")
      end
    else
      say("Combat logging is turned on at zone-in to a raid: " .. (ns.Store.setting("autoLog", true) == false and "no" or "yes")
        .. ". /gg log on or /gg log off changes it. The addon never turns it off.")
    end
  elseif command == "test" then
    if rest == "on" or rest == "off" then
      if ns.Store.setSetting("testDungeons", rest == "on") then
        say(rest == "on"
          and "TEST RECORDING IS ON: a party in a 5-man dungeon is now recorded like a raid, and its export is marked as a test. /gg test off stops it."
          or "Test recording is off. Only raids are recorded.")
        UI.refresh()
      else
        say("That could not be saved.")
      end
    else
      say("Test recording is " .. (testing() and "ON" or "off") .. ". /gg test on or /gg test off changes it.")
    end
  else
    for _, line in ipairs(HELP) do say(line) end
  end
end

-- A command that fails is recorded with the other errors and does not raise one in the player's face.
local function run(text)
  local ok, err = pcall(UI.slash, text)
  if ok then return end
  ns.Store.recordError("slash /gg", err)
  say("That did not work (" .. tostring(err):match("^[^\n]*") .. "). It is in the saved error list.")
end

function UI.init()
  client().registerSlash("GUILDGOLEM", { "/gg", "/guildgolem" }, run)
end

-- The window keeps up with the recording while it is open.
function UI.listen()
  -- Only the status line: the copy box is not touched while someone may be reading from it.
  ns.Events.on("GG_SNAPSHOT", function()
    if window and window.isShown() then window.setStatus(UI.statusLine()) end
  end, "ui")
end

-- A test, or a second session in one Lua state, starts from nothing.
function UI.reset()
  window, failed, pending, view, newExport = nil, nil, nil, 1, false
end
