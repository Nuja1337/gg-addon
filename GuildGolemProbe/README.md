# Guild Golem Probe

A small test addon for WoW Forever. It checks what the game lets the Guild Golem addon do, and writes down what it
finds. It changes nothing in the game and sends nothing anywhere: you copy its results and send them yourself.

It records what it sees, including the names of people in your group and guild, so share the results only with the
Guild Golem team.

## Install

1. Close the game.
2. Copy the `GuildGolemProbe` folder into your Forever game folder's `Interface\AddOns` folder.
   **Write down that folder's full path**: it's one of the answers we need.
3. Start the game. At the character screen, open AddOns and make sure Guild Golem Probe is ticked.
4. Log in. After a few seconds, chat says "Guild Golem Probe: loaded".

## What to do

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

## Send the results

1. Type `/ggprobe`. Press Ctrl+A, then Ctrl+C, and paste the whole thing into a message to the Guild Golem team.
2. Also send the file `WTF\Account\<your account>\SavedVariables\GuildGolemProbe.lua` from your game folder. It's
   written when you log out.
3. Add the folder path from step 2 of Install, what SyncCheck.html said, and anything that looked wrong.

`/ggprobe help` lists every command. `/ggprobe reset` clears the results to start over.
