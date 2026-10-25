# Testing the addon's Lua outside the game

The addon is Lua 5.1 that runs inside the game, and the game cannot be run in a test. This folder lets its code run in
Node (`npm test`) and, in CI, on real Lua 5.1, against stand-ins for the parts of the game it touches.

## What's here

| File | What it does |
|---|---|
| `run.mjs` | Makes a fresh Lua state in Node with [fengari](https://fengari.io) (a Lua 5.3 VM in JavaScript), loads the shim, the stubs and the harness, and lets a test call Lua and read its tables as plain data |
| `compat51.lua` | Gives a 5.3 state what Lua 5.1 had and 5.3 dropped. It does nothing on real 5.1 |
| `wow.lua` | The game's globals, driven by data the test sets (below) |
| `harness.lua` | A small test framework (`T.test`, `T.eq`, `T.same`, `T.truthy`, `T.raises`) that runs the same on both VMs |
| `specs/*.lua` | Tests written once in Lua. `npm test` runs each under fengari, one Node test for each; CI runs all of them on Lua 5.1 |
| `run51.lua` | The entry point for real Lua 5.1 |
| `globals-lib.mjs` | The globals check (below) |
| `fixtures/` | `sample.lua` proves the harness; `globals_ok.lua` and `globals_bad.lua` test the globals check |

The tests that use them: `test/lua-harness.test.mjs` (the specs under fengari, and the sample driven from Node) and
`test/globals.test.mjs`.

## The rule: stay in the common subset

Fengari is Lua 5.3 and the game is Lua 5.1. They agree on most code and differ on some, listed below. **Write code that
means the same in both, and when they disagree, real Lua 5.1 is right.** A test that passes in Node proves the logic,
and the `lua51` job in `.github/workflows/test.yml` (which runs `run51.lua` on Lua 5.1.5) is the one that says the code
works as the game will run it. Run it before a push if you changed Lua (below, "Running it on Lua 5.1").

Every Lua file under `test/lua/` is also parsed as Lua 5.1 by luaparse in `npm test`, so syntax that only 5.3 has (`//`,
`goto`, the bitwise operators, `\z`) fails there at once.

## What the shim covers

`compat51.lua` defines, when the state is not 5.1: `unpack`, `loadstring`, `gcinfo`, `table.getn`, `table.setn` (raises
as 5.1 does), `table.maxn`, `math.mod`, `math.pow`, `math.log10`, `math.ldexp`, `math.frexp`, `math.cosh`, `math.sinh`,
`math.tanh`, `string.gfind`, `getfenv` and `setfenv`, and a `tostring` that prints a whole float as 5.1 does (`5`, not
`5.0`).

`setfenv` and `getfenv` work on Lua functions, by level (`setfenv(1, env)`) or by function, because 5.3 keeps a
function's environment in its `_ENV` upvalue. They cannot change a function that never uses a global (nothing in it
would notice), a function in C, or an inner function made before the change.

## What cannot be shimmed

These differ, and the shim cannot hide them. The first column says whether a mistake shows up in Node or only on Lua 5.1.

| Difference | Lua 5.1 | Lua 5.3 (fengari) | Do this |
|---|---|---|---|
| Numbers in text (only in 5.3) | `10 / 2 .. ""` is `"5"` | `"5.0"`: `/` always gives a float, and `..` and `%s` print it with `.0`. Only `tostring` is shimmed | Build text from numbers with `string.format("%d", n)` or `("%.14g")`, or `math.floor` first |
| Integers and floats | One number type, a double, exact to 2^53 | Integer and float subtypes; integers wrap at 2^63 | Don't depend on either. Never compare a large count by overflow |
| `string.format("%d", 3.5)` | `"3"` | An error | Floor first (loud in Node, so it is caught) |
| `#` on a table with holes | Some border, by its own rule | Another border | Keep a count (`n`) or never leave holes |
| `goto`, labels, `//`, the bitwise operators, `\z` | Syntax errors (`goto` is a plain name) | Work | luaparse's 5.1 mode fails them in `npm test` |
| The escapes `\x41` and `\u{41}` in a string | The text `x41` and `u{41}`, silently (luaparse accepts them) | The character `A` | Write `\65` or `string.char(65)` |
| `_ENV` | An ordinary name | The environment | The globals check fails any use outside Client.lua |
| Library functions 5.2 and later added: `table.unpack`, `table.pack`, `table.move`, `math.type`, `math.tointeger`, `utf8`, `bit32`, `string.pack` | Missing | Present | Use `unpack`, `{ n = select("#", ...), ... }`, and nothing else. Real 5.1 fails them |
| `%g` in a pattern | The letter `g` (silently) | A printable character | Use `[%w%p]` or similar |
| `xpcall(f, handler, ...)` | Drops the extra arguments | Passes them | Wrap the call in a closure |
| `__len`, `__pairs` and `__gc` on tables; `ipairs` reading `__index` | Not honored | Honored | Don't use them |
| `load(text)` | Takes a function only | Takes text too | Use `loadstring` (the game has it) |
| Coroutines across `pcall` | A yield can't cross it | It can | Don't yield across a protected call |

Beyond these, the game's own Lua is 5.1 with parts added and taken away (the globals check, below, covers what the
addon may use). Size and speed limits (the saved variables' size, the game's script time limit) are not tested here;
they need a check in game.

## The game's stubs (`wow.lua`)

`wow.lua` defines the globals the addon touches, and the `WOW` table to drive them. `WOW.reset()` runs before every
test, so a test starts from one player in the open world and a clock that stands still.

| What | How a test sets it | What the addon sees |
|---|---|---|
| The clock | `WOW.advance(seconds)` moves it and runs the timers that come due; `WOW.reset({ time, uptime })`; `WOW.setServerTime(t)` moves the server's clock alone | `GetTime`, `GetServerTime`, `time`, `os.time`, `debugprofilestop`, `C_Timer.After`, `NewTimer`, `NewTicker` |
| The player | `WOW.setPlayer({ name, class, level, guid, zone })` | `UnitName("player")`, `UnitGUID`, `UnitClass` |
| The group | `WOW.setRoster({ { name, class, subgroup, rank, online, guid, ... } }, "raid" or "party")` | `IsInRaid`, `IsInGroup`, `GetNumGroupMembers`, `GetRaidRosterInfo`, `UnitName("raidN")` and the like |
| The instance | `WOW.setInstance({ name, type, difficultyID, difficultyName, maxPlayers, instanceID, instanceGroupSize })` | `GetInstanceInfo` |
| The guild | `WOW.setGuild({ name, rank, rankIndex, realm })` | `GetGuildInfo` |
| Events | `WOW.fire(event, ...)`, `WOW.login()`, `WOW.receive(prefix, text, channel, sender)` | `CreateFrame`'s frames: `RegisterEvent`, `UnregisterEvent`, `SetScript`, `GetScript`, `HookScript`, `Show`, `Hide` |
| Addon messages | `WOW.lockdown = true` refuses all; the limits are the game's | `C_ChatInfo.SendAddonMessage` fills `WOW.outbox`; `RegisterAddonMessagePrefix` |
| Chat | `WOW.slash("/gg export")` | `print` and `DEFAULT_CHAT_FRAME:AddMessage` fill `WOW.chat`; `SlashCmdList` and `SLASH_*` |
| Saved variables | `WOW.declareSavedVariables("Name")`, then `WOW.saved.Name = {...}` to start from a file or `WOW.readSavedFile(text)` | A global `Name` at `ADDON_LOADED`. `WOW.logout()` fires `PLAYER_LOGOUT`, writes `WOW.savedFile` as Lua text and returns the table read back from it |
| An addon | `WOW.loadAddon("Name", { "GuildGolem/Core/Store.lua", ... })` runs the files in order as the game does (`local ADDON, ns = ...`), then loads the saved variables and fires `ADDON_LOADED` | |

An error in a handler or a timer reaches the test, unless `WOW.catchErrors = true`, which records it in `WOW.errors`
as the game's error handler would.

The values follow docs/RESEARCH.md ("Probe results"): names are "First Surname" with a space, `UnitName` returns the
first name and the surname as two values, GUIDs are `Player-<server>-<id>`, the realm is "Classic Beta PvP", the build
is 1.60.1 (70532), interface 16001 and `WOW_PROJECT_ID` 18. Names, guilds, instance ids and server numbers in tests are
made up. Use no real player's name in a test or a fixture: this repository is public.

What the stubs do not have yet: frame methods beyond events, scripts and visibility, `OnUpdate`, the loot, guild bank
and container APIs, `issecretvalue`, and the `bit` library (the game has it; neither Lua 5.1 nor fengari does). A stub
is added when the first test needs it. Add the next one to `wow.lua`, with a test in `specs/wow_spec.lua`.

## The globals check

Only `GuildGolem/Client.lua` may call the game (docs/PLAN.md). `test/globals.test.mjs` reads the syntax tree of every
other file in `GuildGolem/`, except `GuildGolem/Libs/`, and fails if one uses a global that is not on the allowlist in
`globals-lib.mjs`: Lua's own (`pairs`, `string`, `table`, `pcall` and so on) and the addon's own names (`GuildGolem`
and `GuildGolemDB`; add a name there when the addon makes another global). A write to a global counts as a use. So do
`_G`, `getfenv`, `setfenv`, `loadstring`, `require` and `io`, which would get round the check or do not exist in the
game. A local or parameter that has a game function's name is fine.

Until `GuildGolem/` exists, the check is tested on `fixtures/globals_ok.lua` (passes) and `fixtures/globals_bad.lua`
(reads `GetRaidRosterInfo`, fails).

## Writing a test

A spec is a Lua file in `specs/`. Make the game, load the files, drive them and check:

```lua
T.test("a roster change is saved", function()
  WOW.declareSavedVariables("GuildGolemDB")
  WOW.setRoster({ { name = "Tolvar Ashgrove", class = "WARRIOR" } })
  WOW.loadAddon("GuildGolem", { "GuildGolem/Core/Store.lua", "GuildGolem/Attendance.lua" })
  WOW.login()
  WOW.fire("GROUP_ROSTER_UPDATE")
  WOW.advance(300)
  local saved = WOW.logout()
  T.eq(#saved.GuildGolemDB.raids, 1)
end)
```

A test of a pure module (the codec, the store's migrations) needs none of this: load the file with `WOW.dofile(path,
"GuildGolem", ns)` and call its functions. Drive it from Node instead when that reads better, as the last block of
`test/lua-harness.test.mjs` does: `lua.call("WOW.fire", "GROUP_ROSTER_UPDATE")`, `lua.get("WOW.saved")`.

Specs run in the order of their file names, in one Lua state each under fengari. In CI they all share one state, so a
test must not rely on a global another test left behind. `WOW.reset()` clears what the stubs own.

## Running it on Lua 5.1

```
npm test                                          # everything, under Node
lua5.1 test/lua/run51.lua test/lua/specs/*.lua    # the specs on real Lua 5.1, from the repository's folder
```

On Ubuntu, `sudo apt install lua5.1` provides both `lua5.1` and `luac5.1`. On Windows, use WSL for the same.
