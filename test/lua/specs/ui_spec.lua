-- UI.lua and the window Client.window builds: /gg and its commands, the paste box (what was read, or why not), the copy box
-- (selected, read-only, one export at a time) and the status line.

local function start()
  WOW.declareSavedVariables("GuildGolemDB")
  local ns = WOW.loadAddon("GuildGolem")
  WOW.login()
  return ns
end

local function fixtureText(kind) return assert(WOW.readFile("contract/fixtures/" .. kind .. ".gg1.txt")) end

local function guid(i) return string.format("Player-9101-%08X", 0x0F000000 + i) end

local function roster(n, zone)
  local list = { { name = "Rhona Tester", class = "MAGE", guid = WOW.player.guid, rank = 2, zone = zone } }
  for i = 2, n do list[i] = { name = "Tolvar Ashgrove" .. string.rep("x", i), class = "WARRIOR", guid = guid(i), zone = zone } end
  return list
end

local function enterVault()
  WOW.setInstance({ name = "Ember Vault", type = "raid", difficultyID = 9, maxPlayers = 40, instanceID = 5011, instanceGroupSize = 40 })
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
end

local function chatHas(pattern)
  for _, line in ipairs(WOW.chat) do
    if line:find(pattern) then return line end
  end
  return nil
end

-- The window's parts, by the names Client.window gives them.
local function parts()
  return {
    window = _G.GuildGolemWindow,
    paste = _G.GuildGolemWindowPaste,
    copy = _G.GuildGolemWindowCopy,
    import = _G.GuildGolemWindowButtonimport,
    export = _G.GuildGolemWindowButtonexport,
    prev = _G.GuildGolemWindowButtonprev,
    next = _G.GuildGolemWindowButtonnext,
    pasted = _G.GuildGolemWindowButtonpasted,
  }
end

T.test("/gg opens the window, and again closes it", function()
  local ns = start()
  T.eq(_G.GuildGolemWindow, nil, "nothing is built until it is asked for")
  WOW.slash("/gg")
  local p = parts()
  T.truthy(p.window)
  T.eq(WOW.frameState(p.window).shown, true)
  T.truthy(p.window.TitleText:GetText() == "Guild Golem")
  WOW.slash("/gg")
  T.eq(WOW.frameState(p.window).shown, false)
  WOW.slash("/guildgolem")
  T.eq(WOW.frameState(p.window).shown, true)
  WOW.slash("/gg hide")
  T.eq(WOW.frameState(p.window).shown, false)
  T.eq(#WOW.errors, 0)
  T.truthy(ns.UI.window())
end)

T.test("Escape closes the window: it is among the special frames", function()
  start()
  WOW.slash("/gg")
  local found = false
  for _, name in ipairs(UISpecialFrames) do
    if name == "GuildGolemWindow" then found = true end
  end
  T.eq(found, true)
end)

T.test("a client that lacks the window's templates still gets a window", function()
  start()
  WOW.missingTemplates = { BasicFrameTemplateWithInset = true, UIPanelScrollFrameTemplate = true, UIPanelButtonTemplate = true }
  WOW.slash("/gg")
  local p = parts()
  T.truthy(p.window)
  T.eq(WOW.frameState(p.window).shown, true)
  T.truthy(p.paste and p.copy and p.import)
end)

T.test("a client that cannot make frames gets the commands in chat, and one message about it", function()
  local ns = start()
  WOW.hide("CreateFrame")
  CreateFrame = function() error("no frames today") end
  WOW.slash("/gg")
  T.truthy(chatHas("The window could not be made"))
  local n = #WOW.chat
  WOW.slash("/gg")
  T.eq(#WOW.chat, n, "and it does not keep trying")
  WOW.slash("/gg status")
  T.truthy(chatHas("Guild Golem 0.1.0%-beta"))
  T.truthy(ns.UI)
end)

-- The paste box ----------------------------------------------------------------------------------------------------------------

T.test("a pasted import is read once the paste settles, and the note says what it holds", function()
  local ns = start()
  WOW.slash("/gg")
  local p = parts()
  T.eq(WOW.frameState(p.import).enabled, false, "nothing to import yet")
  WOW.userText(p.paste, fixtureText("import-night"))
  WOW.advance(0.2)
  T.eq(WOW.frameState(p.import).enabled, false, "it waits for the paste to settle")
  WOW.advance(0.4)
  T.eq(WOW.frameState(p.import).enabled, true)
  local note = ns.UI.window().noteText()
  T.truthy(note:find("A night's plan for \"Weekend raids\" %(Molten Raiders%)"), note)
  T.truthy(note:find("3 raids"), note)
  T.truthy(note:find("Press Import"), note)
  T.eq(next(GuildGolemDB.nights), nil, "and nothing is kept until the player presses Import")
end)

T.test("pressing Import keeps what was read and clears the box", function()
  local ns = start()
  WOW.slash("/gg")
  local p = parts()
  WOW.userText(p.paste, fixtureText("import-night"))
  WOW.advance(1)
  T.truthy(WOW.click(p.import))
  T.truthy(GuildGolemDB.nights.efgh6789)
  T.eq(GuildGolemDB.nights.efgh6789.title, "Weekend raids")
  T.eq(GuildGolemDB.guild.handle, "abcd2345")
  T.eq(WOW.frameState(p.paste).text, "")
  T.eq(WOW.frameState(p.import).enabled, false)
  T.truthy(ns.UI.window().noteText():find("^Imported%."))
  T.eq(WOW.click(p.import), false, "and the button is off again")
end)

T.test("a string that cannot be read is refused in plain words, and nothing is kept", function()
  local ns = start()
  WOW.slash("/gg")
  local p = parts()
  local function paste(text)
    WOW.userText(p.paste, text)
    WOW.advance(1)
    return ns.UI.window().noteText()
  end
  T.eq(paste("hello there"), "That isn't a Guild Golem string.")
  T.eq(WOW.frameState(p.import).enabled, false)
  T.eq(paste(fixtureText("export-night")), "That is an export; paste it on the site.")
  local good = fixtureText("import-night")
  T.eq(paste(good:sub(1, #good - 30)), "The string is cut short or mistyped. Copy it again.")
  T.eq(paste("GG1:!!!!"), "The string has a character that isn't base64. Copy it again.")
  local newer = ns.Codec.encode({ v = 2, kind = "import", meta = { made = 1 } })
  -- Codec.encode writes any v; the reader refuses the newer one.
  T.eq(paste(newer), "Update the addon")
  local broken = ns.Codec.encode({ v = 1, kind = "import", meta = { made = 1796843700000, site = "0.1.0", latest = "0.1.0", from = "night" } })
  T.truthy(paste(broken):find("^The string is damaged: "), "a required field missing names it")
  T.eq(next(GuildGolemDB.nights), nil)
  -- Clearing the box clears the note.
  T.eq(paste("   "), "")
  T.eq(WOW.frameState(p.import).enabled, false)
end)

T.test("the note says when a newer addon is out, and draws a title's | safely", function()
  local ns = start()
  WOW.slash("/gg")
  local p = parts()
  local object = ns.Codec.decode(fixtureText("import-night"))
  object.night.title = "Friday |cffff0000raids|r"
  object.meta.latest = "0.2.0"
  WOW.userText(p.paste, ns.Codec.encode(object))
  WOW.advance(1)
  local note = ns.UI.window().noteText()
  T.truthy(note:find("Friday ||cffff0000raids||r", 1, true), note)
  T.truthy(note:find("A newer addon is out (0.2.0)", 1, true), note)
end)

T.test("versions are compared as numbers by dot", function()
  local ns = start()
  T.eq(ns.UI.older("0.1.0-beta", "0.2.0"), true)
  T.eq(ns.UI.older("0.9.0", "0.10.0"), true)
  T.eq(ns.UI.older("1.0.0", "0.10.0"), false)
  T.eq(ns.UI.older("1.2.3", "1.2.3"), false)
  T.eq(ns.UI.older("v1.2.3-beta", "1.2.4"), true)
  T.eq(ns.UI.older("0.0.0-dev", "garbage"), false)
end)

-- The copy box ----------------------------------------------------------------------------------------------------------------

-- A recorded raid with a pull and a kill, so there is something to export.
local function recorded(ns)
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  WOW.advance(60)
  WOW.fire("ENCOUNTER_START", 1101, "Warden of Cinders", 9, 40)
  WOW.advance(100)
  WOW.fire("ENCOUNTER_END", 1101, "Warden of Cinders", 9, 40, 1)
end

T.test("/gg export makes the string, says so, and shows it selected in the copy box", function()
  local ns = start()
  recorded(ns)
  WOW.slash("/gg export")
  T.truthy(chatHas("Made 1 export string from 1 raid and 3 snapshots"), table.concat(WOW.chat, " | "))
  local p = parts()
  T.eq(WOW.frameState(p.window).shown, true)
  local copy = WOW.frameState(p.copy)
  T.eq(copy.text, GuildGolemDB.outbox[1].text)
  T.truthy(copy.text:find("^GG1:"))
  T.eq(copy.highlighted, true)
  T.eq(copy.focused, true)
  T.truthy(ns.UI.window().copyLabelText():find("Export 1 of 1 waiting"))
  T.truthy(ns.UI.window().copyLabelText():find("Ctrl%+C"))
end)

T.test("the copy box gives back what it held if the player types in it", function()
  start()
  recorded()
  WOW.slash("/gg export")
  local p = parts()
  local text = WOW.frameState(p.copy).text
  WOW.userText(p.copy, text .. "x")
  T.eq(WOW.frameState(p.copy).text, text)
  WOW.userText(p.copy, "")
  T.eq(WOW.frameState(p.copy).text, text)
end)

T.test("/gg export with nothing new says so, and /gg export all repeats", function()
  start()
  recorded()
  WOW.slash("/gg export")
  WOW.chat = {}
  WOW.slash("/gg export")
  T.truthy(chatHas("Nothing new to export"))
  T.eq(#GuildGolemDB.outbox, 1)
  WOW.slash("/gg export all")
  T.eq(#GuildGolemDB.outbox, 2)
  T.truthy(chatHas("Made 1 export string"))
end)

T.test("the buttons step through the exports waiting, and Pasted on the site takes one off", function()
  local ns = start()
  recorded()
  WOW.slash("/gg export")
  WOW.slash("/gg export all")
  WOW.slash("/gg export all")
  T.eq(#GuildGolemDB.outbox, 3)
  local p = parts()
  local w = ns.UI.window()
  -- The newest is shown first.
  T.eq(WOW.frameState(p.copy).text, GuildGolemDB.outbox[3].text)
  T.truthy(w.copyLabelText():find("Export 3 of 3"))
  T.eq(WOW.frameState(p.next).enabled, false)
  T.eq(WOW.frameState(p.prev).enabled, true)
  WOW.click(p.prev)
  T.eq(WOW.frameState(p.copy).text, GuildGolemDB.outbox[2].text)
  T.truthy(w.copyLabelText():find("Export 2 of 3"))
  WOW.click(p.pasted)
  T.truthy(GuildGolemDB.outbox[2].pasted)
  T.eq(#ns.Store.outboxPending(), 2)
  T.truthy(w.copyLabelText():find("of 2 waiting"))
  WOW.click(p.pasted)
  WOW.click(p.pasted)
  T.eq(#ns.Store.outboxPending(), 0)
  T.eq(WOW.frameState(p.copy).text, "")
  T.eq(WOW.frameState(p.pasted).enabled, false)
  T.truthy(w.copyLabelText():find("Nothing is waiting"))
  T.eq(#GuildGolemDB.outbox, 3, "the exports stay in the outbox, marked")
end)

T.test("the Export button makes an export too", function()
  start()
  recorded()
  WOW.slash("/gg")
  local p = parts()
  T.truthy(WOW.click(p.export))
  T.eq(#GuildGolemDB.outbox, 1)
  T.eq(WOW.frameState(p.copy).text, GuildGolemDB.outbox[1].text)
end)

T.test("the status line follows the recording while the window is open", function()
  local ns = start()
  WOW.slash("/gg")
  local w = ns.UI.window()
  T.eq(w.statusText(), "Not recording.")
  WOW.setRoster(roster(10, "Ember Vault"))
  enterVault()
  T.eq(w.statusText(), "Recording Ember Vault: 1 snapshot.")
  WOW.advance(60)
  WOW.fire("ENCOUNTER_START", 1101, "Warden of Cinders", 9, 40)
  T.eq(w.statusText(), "Recording Ember Vault: 2 snapshots.")
  WOW.slash("/gg export")
  T.eq(w.statusText(), "Recording Ember Vault: 2 snapshots. 1 export waiting.")
end)

-- /gg status and the rest --------------------------------------------------------------------------------------------------------

T.test("/gg status says the version, the night, the recording, the outbox and the client's gaps", function()
  local ns = start()
  WOW.slash("/gg status")
  local text = table.concat(WOW.chat, "\n")
  T.truthy(text:find("Guild Golem 0.1.0%-beta"))
  T.truthy(text:find("No night imported"))
  T.truthy(text:find("Not recording. 0 raids kept."), text)
  T.truthy(text:find("Outbox: nothing waiting"))
  T.truthy(text:find("Combat logging: off; the addon turns it on in a raid: yes."), text)
  T.truthy(text:find("The client lacks: encounterInProgress, lootHistory%."), text)

  WOW.chat = {}
  local import = ns.Import.load(fixtureText("import-night"))
  T.truthy(import)
  WOW.setRoster(roster(10, "Ember Vault"))
  WOW.setInstance({ name = "Ember Vault", type = "raid", difficultyID = 9, maxPlayers = 10, instanceID = 5011, instanceGroupSize = 10 })
  WOW.setServerTime(1796846700)
  WOW.fire("PLAYER_ENTERING_WORLD", false, false)
  WOW.slash("/gg export")
  WOW.hide("RequestRaidInfo")
  WOW.hide("LoggingCombat")
  WOW.chat = {}
  WOW.slash("/gg status")
  text = table.concat(WOW.chat, "\n")
  T.truthy(text:find("Imported night: \"Weekend raids\", 3 raids %(Ember Vault, "), text)
  T.truthy(text:find("Recording Ember Vault %(10 players, difficulty 9%): 1 snapshot, the last at "), text)
  T.truthy(text:find("Outbox: 1 export waiting to be pasted on the site."), text)
  T.truthy(text:find("Combat logging: this client cannot turn it on."), text)
  T.truthy(text:find("The client lacks: encounterInProgress, loggingCombat, lootHistory, raidInfo%."), text)
end)

T.test("/gg status draws a night's title safely", function()
  local ns = start()
  local object = ns.Codec.decode(fixtureText("import-night"))
  object.night.title = "|cffff0000Red|r"
  T.truthy(ns.Import.load(ns.Codec.encode(object)))
  WOW.slash("/gg status")
  T.truthy(chatHas("||cffff0000Red||r"))
  T.eq(chatHas("Imported night: \"|cff"), nil)
end)

T.test("/gg log turns the combat logging option on and off and says what it is", function()
  local ns = start()
  WOW.slash("/gg log")
  T.truthy(chatHas("Combat logging is turned on at zone%-in to a raid: yes"))
  WOW.slash("/gg log off")
  T.eq(GuildGolemDB.settings.autoLog, false)
  T.truthy(chatHas("will not turn combat logging on"))
  WOW.slash("/gg log")
  T.truthy(chatHas("raid: no%."))
  WOW.setRoster(roster(5, "Ember Vault"))
  enterVault()
  T.same(WOW.loggingCalls, {})
  WOW.slash("/gg log ON")
  T.eq(GuildGolemDB.settings.autoLog, true)
  T.truthy(ns.Store.setting("autoLog", false))
  -- The option survives a logout.
  local saved = WOW.logout()
  T.eq(saved.GuildGolemDB.settings.autoLog, true)
end)

T.test("an unknown command prints the help", function()
  start()
  WOW.slash("/gg frobnicate")
  T.truthy(chatHas("/gg status"))
  T.truthy(chatHas("/gg export"))
  T.truthy(chatHas("/gg log on|off"))
end)

T.test("a failing command is recorded and says so, and the next one still works", function()
  local ns = start()
  recorded()
  local make = ns.Export.make
  ns.Export.make = function() error("export broke") end
  WOW.slash("/gg export")
  T.truthy(chatHas("That did not work %(.*export broke"))
  T.eq(GuildGolemDB.errors[1].where, "slash /gg")
  ns.Export.make = make
  WOW.slash("/gg export")
  T.truthy(chatHas("Made 1 export string"))
end)
