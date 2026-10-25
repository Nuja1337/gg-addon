# Guild Golem Probe

A small test addon for WoW Forever. It checks what the game lets the Guild Golem addon do, and writes down what it
finds. It sends nothing outside the game. It changes nothing that stays changed. Two things are switched and put back,
combat logging and the `advancedCombatLogging` setting. You copy its results and send them yourself.

It records what it sees, including the names of people in your group and guild, so share the results only with the
Guild Golem team. The comparison tool in this repository (`tools/probe-diff.mjs`) replaces those names before it prints
anything, so its output is safe to paste into the public docs.

This is version 0.2. The saved file has a `probeVersion` field (`0.2.0`), so a run can be told from an older one.

## Install

1. Close the game.
2. Copy the `GuildGolemProbe` folder into your Forever game folder's `Interface\AddOns` folder. If an older copy is
   there, delete it first so no old file is left behind.
   **Write down that folder's full path.** We need it.
3. Start the game. At the character screen, open AddOns and make sure Guild Golem Probe is ticked.
4. Log in. After a few seconds, chat says "Guild Golem Probe: loaded".

## The launch-day pass

This is the one run for launch day. It takes about 20 minutes and covers the open world, a party and a dungeon with one
wipe and one kill. Do the steps in order. The probe does most of the recording itself, and the steps say when you have
to type something.

1. **Start clean.** Before the game opens, copy `WTF\Account\<your account>\SavedVariables\GuildGolemProbe.lua` to a
   safe place if you want to keep an older run to compare with. Log in, wait for the "loaded" line, type
   `/ggprobe reset`, then `/reload`. The saved file now starts empty.
2. **Open world, about 3 minutes.** Wait 15 seconds after the reload. In that time the probe lists the client's
   functions, reads the chat limits, reads combat logging, switches it on or off and puts it back, and does the same for
   the `advancedCombatLogging` setting. Then type `/ggprobe boxes`. A window opens and fills its top box six times, with
   16 KB, 64 KB and 256 KB of text, each as one long line and as short lines. The game may freeze for a few seconds at a
   time. Don't click until chat says "copy tests finished". For the paste test, click the **64 KB** button, click in the
   top box, press Ctrl+A and then Ctrl+C, click in the lower box and press Ctrl+V. Wait three seconds, then press Escape
   to close the window.
3. **Party, about 4 minutes.** Form a party of up to five. Other people running the probe make the message test better,
   since their copies count your messages, but it also works with only you. If you lead the party, set the loot method to
   master looter, then type `/ggprobe loot`. Then set it to group loot (or need before greed) and type `/ggprobe loot`
   again. Last, type `/ggprobe burst`. It sends 50 short addon messages over the party and counts how many arrive and
   when. The result is written 10 seconds later and again after 40 seconds. If everyone else types `/ggprobe burst` too,
   wait a minute between people.
4. **Dungeon, about 10 minutes.** Enter the dungeon with the party and wait 10 seconds after the loading screen. The
   probe records `GetInstanceInfo()`, the restriction states and combat logging again. Type `/ggprobe burst` once before
   the first pull. Then pull the first boss and wipe on purpose. Don't type anything during the fight. The probe records
   the `ENCOUNTER_START` and `ENCOUNTER_END` arguments, `BOSS_KILL`, `INSTANCE_ENCOUNTER_ENGAGE_UNIT`, every
   restriction event, and a short burst of messages at the pull and 3 seconds after it. Wait 10 seconds after the wipe,
   run back, pull the same boss again and kill it. Roll on at least one item that drops, and hand out one by master
   loot if the party has it. Ten seconds after the kill, type `/ggprobe loot`. Then type `/ggprobe burst` once more,
   out of combat.
5. **Save.** Type `/ggprobe`, press Ctrl+A and Ctrl+C, and paste the whole text into a message to the Guild Golem team.
   Then type `/reload`, or log out. The game writes the saved file only then, so it is not written if the game crashes.
   If the game freezes for good or crashes, say what you were doing when it happened.
6. **Find the saved file.** It is `WTF\Account\<your account>\SavedVariables\GuildGolemProbe.lua`, in the same game
   folder that holds `Interface`. For Forever that folder is `_classic_beta_`. Rename a copy after the build and the
   date, for example `probe-<build>-<date>.lua`, and keep it.
7. **Two clients.** To check what two players' addons will agree on (the contract's matching of one raid or one award
   recorded twice), run the dungeon step with two people in the party, each with the probe, and keep both saved files.
   `docs/RESEARCH.md`, "Launch-day probe", lists what to compare between them.
8. **Compare.** To see what changed against an earlier run, type
   `node tools/probe-diff.mjs older.lua newer.lua` in the repository. The section "Launch-day probe" in
   `docs/RESEARCH.md` says where to write the result down.

What the pass records, section by section in the results:

| Section | What is in it |
|---|---|
| `combat logging` | Whether `LoggingCombat()` can be read and switched, and whether `advancedCombatLogging` exists, can be set, and reads back as set. Both are put back as they were |
| `boxes` | How long `SetText` and select all took for 16, 64 and 256 KB, whether the text came back whole, whether a frame took 250 ms or more, and the length and read time of what you pasted |
| `instance` | `GetInstanceInfo()` on entering, with the chat lockdown and restriction states |
| `encounters` | Every argument of `ENCOUNTER_START`, `ENCOUNTER_END`, `BOSS_KILL` and `INSTANCE_ENCOUNTER_ENGAGE_UNIT`, numbered per pull. `ENCOUNTER_END` also has `serverTime` (`GetServerTime()`), the computer's `time()` and `GetTime()` |
| `loot`, `loot history` | The loot method and master looter in a party, `ENCOUNTER_LOOT_RECEIVED` (with the winner's name format, how many group members have exactly that full name, the quantity and its type, and `serverTime`), rolls, and what the loot history functions return after a group roll. For each of the first drops, an "identity of drop" row: its `encounterID` and `lootListID`, the field names each call returns, and whether the winner has a `playerGUID` |
| `lockouts` | The saved instances, and a numbered "lockout ids" row (name, lockout id, difficulty, locked) after each `UPDATE_INSTANCE_INFO`. The probe asks for the list again 8 seconds after each `ENCOUNTER_END`, so the row after a kill shows the new lockout |
| `addon messages` | How many of 50 messages were accepted, how many arrived and when, what the game says to a message or prefix that is too long, and the `C_ChatInfo` results |
| `restrictions` | `ADDON_RESTRICTION_STATE_CHANGED` and similar events, with the state of every restriction type |
| `api`, `events` | Which functions exist in the tables that matter, and which events this client has |

An API the client does not have is recorded as `missing`, not as an error.

## Other tests

Most checks run by themselves. The ones below need you.

| Where | Do this |
|---|---|
| Anywhere | Type `/ggprobe`. A window opens with the results so far |
| With a friend who also runs the probe | Both type `/ggprobe ping`, once in a party and once in a raid group |
| A raid group, inside a raid | Type `/ggprobe roster`, then `/ggprobe auras` (out of combat), then `/ggprobe ping` |
| A boss pull | Pull a boss (a wipe is fine). Wait 10 seconds after it ends, then `/ggprobe ping` |
| Loot | Let a boss drop loot. If you can, hand out one item with master loot and roll on another. Trade a looted item to a friend |
| Inspect | Target a raid member, out of combat, and type `/ggprobe inspect` |
| Raid leader or assistant | `/ggprobe invite Name Surname` (a friend's full name), then `/ggprobe group 2 3` (moves raid member 2 to group 3) |
| Guild bank | Open the guild bank (if Forever has one), then type `/ggprobe bank` |
| Lockouts | `/ggprobe lockouts` |
| A profession | Open one of your professions' windows |

### The reload test

1. With the game running, open `Interface\AddOns\GuildGolemProbe\Data.lua` in Notepad.
2. Change `as shipped` to `changed by hand` and save.
3. In game, type `/reload`, then `/ggprobe`. Look at the line under `[reload test]`.

### The browser test (Chrome or Edge)

Open `SyncCheck.html` from the probe's folder in Chrome or Edge, and follow its two steps with the game running.
It only writes the probe's own `Data.lua`, and refuses any other file.

Chrome and Edge can't open files under Program Files, where the game installs by default. If your game is there,
skip this test and say so with your results.

## Send the results

1. Type `/ggprobe`. Press Ctrl+A, then Ctrl+C, and paste the whole thing into a message to the Guild Golem team.
2. Also send the file `WTF\Account\<your account>\SavedVariables\GuildGolemProbe.lua` from your game folder. It's
   written when you log out or reload.
3. Add the folder path from step 2 of Install, what SyncCheck.html said, and anything that looked wrong.

`/ggprobe help` lists every command. `/ggprobe reset` clears the results to start over.
