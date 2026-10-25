# Testing the addon's Lua outside the game

The addon is Lua 5.1 that runs inside the game, and the game cannot be run in a test. This folder lets its code run in
Node (`npm test`) and, in CI, on real Lua 5.1, against stand-ins for the parts of the game it touches.

## What's here

| File | What it does |
|---|---|
| `run.mjs` | Makes a fresh Lua state in Node with [fengari](https://fengari.io) (a Lua 5.3 VM in JavaScript), loads the shim, the stubs and the harness, and lets a test call Lua and read its tables as plain data. It also gives the state `GG_READ(path)`, since fengari has no `io.open` |
| `compat51.lua` | Gives a 5.3 state what Lua 5.1 had and 5.3 dropped. It does nothing on real 5.1 |
| `wow.lua` | The game's globals, driven by data the test sets (below) |
| `harness.lua` | A small test framework (`T.test`, `T.eq`, `T.same`, `T.truthy`, `T.raises`) that runs the same on both VMs |
| `specs/*.lua` | Tests written once in Lua: a spec for each module of the addon (`codec`, `base64`, `zlibsize`, `store`, `import`, `client`, `events`) and for the stubs themselves. `npm test` runs each under fengari, one Node test for each; CI runs all of them on Lua 5.1 |
| `run51.lua` | The entry point for real Lua 5.1 |
| `globals-lib.mjs` | The globals check (below) |
| `fixtures/` | `sample.lua` proves the harness; `globals_ok.lua` and `globals_bad.lua` test the globals check; `saved/schema-<n>.lua` is a saved file as the addon wrote it at schema n, frozen, for the store's migration test |

The tests that use them: `test/lua-harness.test.mjs` (the specs under fengari, and the sample driven from Node),
`test/globals.test.mjs`, and `test/codec.test.mjs`, which drives the addon's codec from Node and checks it against the
reference JavaScript and Node's own zlib.

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
`math.tanh`, `string.gfind`, `getfenv` and `setfenv`, a `tostring` that prints a whole float as 5.1 does (`5`, not `5.0`), and a
`string.byte` that returns doubles (below, "Fengari's integers are 32 bits").

`setfenv` and `getfenv` work on Lua functions, by level (`setfenv(1, env)`) or by function, because 5.3 keeps a
function's environment in its `_ENV` upvalue. They cannot change a function that never uses a global (nothing in it
would notice), a function in C, or an inner function made before the change.

## What cannot be shimmed

These differ, and the shim cannot hide them. The first column says whether a mistake shows up in Node or only on Lua 5.1.

| Difference | Lua 5.1 | Lua 5.3 (fengari) | Do this |
|---|---|---|---|
| Numbers in text (only in 5.3) | `10 / 2 .. ""` is `"5"` | `"5.0"`: `/` always gives a float, and `..` and `%s` print it with `.0`. Only `tostring` is shimmed | Build text from numbers with `string.format("%d", n)` or `("%.14g")`, or `math.floor` first |
| Integers and floats | One number type, a double, exact to 2^53 | Integer and float subtypes. **Fengari's integers are 32 bits** and wrap silently: `65521 * 65536` is negative, and `string.format("%d", 2^40)` is an error | See "Fengari's integers are 32 bits", below |
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

### Fengari's integers are 32 bits

Every number in Lua 5.1 is a double, exact to 2^53. Fengari has integers of 32 bits, so an integer sum or product past
2^31 wraps without a word (in fengari only: Node shows it and Lua 5.1 does not). The addon works with times in
milliseconds (1.8e12), Adler-32 sums and base64 groups, which are all past that, so the harness keeps numbers doubles
where it can:

- the shim's `string.byte` returns doubles, so everything computed from a byte (LibDeflate, `Core/Base64.lua`,
  `Core/ZlibSize.lua`) is exact, as in 5.1;
- the stubs' `GetServerTime()` and `time()` return doubles, so `GetServerTime() * 1000` is a time in milliseconds;
- `lua.call` from Node sends a whole number past 2^31 as a double;
- the saved-variable writer writes a whole number with `%.0f`.

What is left is yours. Don't multiply integer *literals* or counts to a result past 2^31 (`30 * 24 * 3600 * 1000`):
write the result as one literal (`2592000000`, which fengari reads as a double), as `Store.KEEP_PASTED_MS` does. Never
use `%d` for a number that may pass 2^31: use `%.0f`. A literal past 2^31 is a double in fengari and in 5.1 alike.
Real Lua 5.1 in CI cannot catch this class of mistake, since 5.1 never wraps: only a test that runs the code in Node
does, so write the test with the real magnitudes.

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
| Addon messages | `WOW.lockdown = true` refuses all; the limits are the game's | `C_ChatInfo.SendAddonMessage` fills `WOW.outbox`; `RegisterAddonMessagePrefix`; `InChatMessagingLockdown`; the `Enum.AddOnRestrictionType` and `Enum.AddOnRestrictionState` for `ADDON_RESTRICTION_STATE_CHANGED` (the names are docs/RESEARCH.md's, the numbers the stub's own) |
| Chat | `WOW.slash("/gg export")` | `print` and `DEFAULT_CHAT_FRAME:AddMessage` fill `WOW.chat`; `SlashCmdList` and `SLASH_*` |
| Saved variables | `WOW.declareSavedVariables("Name")`, then `WOW.saved.Name = {...}` to start from a file or `WOW.readSavedFile(text)` | A global `Name` at `ADDON_LOADED`. `WOW.logout()` fires `PLAYER_LOGOUT`, writes `WOW.savedFile` as Lua text and returns the table read back from it |
| An addon | `WOW.loadAddon("GuildGolem")` runs the files its TOC lists, in the TOC's order, as the game does (`local ADDON, ns = ...`), then loads the saved variables and fires `ADDON_LOADED`. A list of paths as the second argument runs those instead. `WOW.tocFiles("GuildGolem")` gives the list | |
| A file | `WOW.readFile("contract/fixtures/export-pugs.gg1.txt")` reads a file of the repository (a path from its root) as text, on fengari and on Lua 5.1 | |
| Secret values | `WOW.secret()` makes a value the game would call secret | `issecretvalue(v)` is true for it and `canaccessvalue(v)` false. Compare, join or `tostring` it and a test sees no error, so check what the addon keeps instead |
| An API gone | `WOW.hide("GetRaidRosterInfo")` or `WOW.hide("C_ChatInfo.SendAddonMessage")` takes it away, as a client without it. Assign a new function after hiding to make one that raises an error | The next `WOW.reset()` puts the game's own back, even for an API hidden twice |
| Lockouts, add-on data | `WOW.setSavedInstances({ { name, id, difficulty, locked, raid, maxPlayers } })`, `WOW.metadata.GuildGolem.Version = "v1.2.3"` | `GetNumSavedInstances`, `GetSavedInstanceInfo`, `C_AddOns.GetAddOnMetadata` |

An error in a handler or a timer reaches the test, unless `WOW.catchErrors = true`, which records it in `WOW.errors`
as the game's error handler would.

The values follow docs/RESEARCH.md ("Probe results"): names are "First Surname" with a space, `UnitName` returns the
first name and the surname as two values, GUIDs are `Player-<server>-<id>`, the realm is "Classic Beta PvP", the build
is 1.60.1 (70532), interface 16001 and `WOW_PROJECT_ID` 18. Names, guilds, instance ids and server numbers in tests are
made up. Use no real player's name in a test or a fixture: this repository is public.

What the stubs do not have yet: frame methods beyond events, scripts and visibility, `OnUpdate`, the loot, guild bank
and container APIs, and the `bit` library (the game has it; neither Lua 5.1 nor fengari does). Nothing in the addon or in
LibDeflate uses `bit`, so there is no stub; if a library ever does, add a pure-Lua one to `wow.lua`. A stub is added
when the first test needs it. Add the next one to `wow.lua`, with a test in `specs/wow_spec.lua`.

## The globals check

Only `GuildGolem/Client.lua` may call the game (docs/PLAN.md). `test/globals.test.mjs` reads the syntax tree of every
other file in `GuildGolem/`, except `GuildGolem/Libs/`, and fails if one uses a global that is not on the allowlist in
`globals-lib.mjs`: Lua's own (`pairs`, `string`, `table`, `pcall` and so on) and the addon's own names (`GuildGolem`
and `GuildGolemDB`; add a name there when the addon makes another global). A write to a global counts as a use. So do
`_G`, `getfenv`, `setfenv`, `loadstring`, `require` and `io`, which would get round the check or do not exist in the
game. A local or parameter that has a game function's name is fine.

`LibStub` is on the allowlist too: it is the loader of the libraries in `Libs/`, not a game function, and the codec asks it
for LibDeflate and json.lua. The check is live on `GuildGolem/` (every file but `Client.lua` and `Libs/`) and is also
tested on `fixtures/globals_ok.lua` (passes) and `fixtures/globals_bad.lua` (reads `GetRaidRosterInfo`, fails), so a
check that stopped catching things would fail.

## Writing a test

A spec is a Lua file in `specs/`. Make the game, load the files, drive them and check:

```lua
T.test("a roster change is saved", function()
  WOW.declareSavedVariables("GuildGolemDB")
  WOW.setRoster({ { name = "Tolvar Ashgrove", class = "WARRIOR" } })
  local ns = WOW.loadAddon("GuildGolem")   -- the TOC's files, in the TOC's order
  WOW.login()
  WOW.fire("GROUP_ROSTER_UPDATE")
  WOW.advance(300)
  local saved = WOW.logout()
  T.eq(#saved.GuildGolemDB.raids, 1)
end)
```

A test of a pure module (the codec, the store's migrations) needs none of this: load the file with `WOW.dofile(path,
"GuildGolem", ns)` and call its functions, or load the whole addon as above and use `ns.Codec`. Drive it from Node instead when that reads better, as the last block of
`test/lua-harness.test.mjs` does: `lua.call("WOW.fire", "GROUP_ROSTER_UPDATE")`, `lua.get("WOW.saved")`.

Specs run in the order of their file names, in one Lua state each under fengari. In CI they all share one state, so a
test must not rely on a global another test left behind. `WOW.reset()` clears what the stubs own.

## Running it on Lua 5.1

```
npm test                                          # everything, under Node
lua5.1 test/lua/run51.lua test/lua/specs/*.lua    # the specs on real Lua 5.1, from the repository's folder
```

On Ubuntu, `sudo apt install lua5.1` provides both `lua5.1` and `luac5.1`. On Windows, use WSL for the same.
