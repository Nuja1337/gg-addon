# In-game addon: plan

What the Guild Golem addon is made of, how it talks to the site, and the order to build it in. It started as **a plan,
not a build** (owner, Oct 8: "draft me a plan for our warcraft addon and what it needs to consist of - dont build it
yet"). **Building began Oct 25 with the core** (the codec, the saved variables, the imports, the launch adapter and the
event bus, in `GuildGolem/`; below, "What the core is") **and M1 followed** (the attendance snapshots, the export and the
window); the rest is still this plan. What
Forever's client allows is in docs/RESEARCH.md; this plan rests on it and must be re-checked against the client before
each milestone, since it changes weekly.

**Decided on Oct 20**, when the owner planned the addon, the bot and the site together. Where the rest of this file
differs, these win:
- **The name** in game is Guild Golem, in the folder `GuildGolem`, with the slash command `/gg` (the owner's to
  confirm).
- **Players download it** from the site's Addon page.
- **No reloads in normal use.** A pasted string loads at once, and logging out writes the file.
- **Sync** takes the place of a desktop uploader, which is on hold. The probe has since found (Oct 22) that a
  browser tab can do this only when the game is installed outside Program Files (below, "A Sync button").
- **On the site,** the guild bank is built already, and pug lists aren't.
- **The string format** stands, and is now written out as contract version 1 (contract/README.md; below, "The contract with the site").

## What it's for

The site already plans the raid (signups, groups, soft reserves) and reads it afterwards (logs, loot, attendance).
The addon closes the loop inside the game, where the site can't see:

| Job | Today, without the addon | With it |
|---|---|---|
| Who was there | Answers, and logs when someone shares one | Roster snapshots at zone-in, every pull and the end: late arrivals, early leavers, the bench, pugs |
| Pugs | None yet (the site's pug lists aren't built) | Flagged the moment they join the group; every pug seen comes back to the site |
| Loot | Typed in by hand on the night's Loot page | Every drop, roll, trade and disenchant recorded; soft reserves and priorities shown in game; rolls or a council run from the addon |
| Guild bank | Bankers count it by hand on the site's Bank page | Deposits, withdrawals and gold as a ledger on the site |
| Raid set-up | Officers invite and arrange groups by hand from the planner | One click invites the planned raid and puts everyone in their planned group |

## Ground rules from the client (docs/RESEARCH.md)

- **No combat log for addons** (Midnight's restrictions on the 12.x engine): attendance is roster snapshots, never
  damage; performance stays with the logs the site already parses.
- **Chat can turn secret in raids**, and addon messages lock down during encounters: nothing depends on reading chat,
  and addon-to-addon messages queue during a boss and go out after `ENCOUNTER_END`.
- **No network:** data moves as text a person copies and pastes (an import string before the raid, an export string
  after). A desktop uploader can come later.
- **Identity by GUID.** Forever's names carry surnames and there's one mega-realm, so every player is keyed by
  `UnitGUID`; names are labels only.
- **TOC files** (corrected Oct 20): `<Addon>_Forever.toc`, `<Addon>_Camelot.toc` and a plain `<Addon>.toc`, named
  after the addon's folder, with `## Interface: 16001`; no `_Mainline.toc` (docs/RESEARCH.md).

## What it consists of

One addon, `GuildGolem`, in modules that can be turned off. Libraries (vendored in `GuildGolem/Libs/`, each from its
author's repository with its license, version and SHA-256 in `Libs/README.md`): LibStub, LibDeflate and rxi's json.lua
(the import and export strings). The base64 reader and writer are the addon's own (`Core/Base64.lua`, forty lines),
and there is **no Ace3**: the event bus, saved variables and addon messages are small enough to own. LibDataBroker and
LibDBIcon come in with the minimap button. It reads and writes no other addon's formats (the owner, Oct 19): what others
did for the site (Gargul's priorities, MRT's notes) is its own (below, "Instead of other addons").

### Core
- **Saved variables:** one account-wide table (imports, pug lists, settings, and each character's bank snapshots
  keyed by GUID): a per-character file lands in a folder Sync doesn't read (Oct 20). A schema version, with migrations
  when it changes.
- **Identity:** the player's GUID, guild name, and the guild's handle on the site (from the last import), so exports
  are tied to one guild.
- **Strings:** `GG1:` + base64 of the zlib-deflated JSON of one object (contract/README.md), its Adler-32 checked
  and its size limited. Imports are validated field by field before use; anything unknown is ignored, never run.
- **Event bus** over the client's events, with a queue for anything that must wait out an encounter.
- **UI:** a minimap button and a slash command (`/gg`) that open one window with tabs: Tonight, Attendance, Loot,
  Bank, Pugs, Import/Export, Settings. Everything works from the slash command too (`/gg import`, `/gg export`).
- **Version check:** addons in the raid tell each other their version (AceComm, RAID), so the leader sees who's out
  of date.

### Tonight (the raid plan, from the site)
- **Import** the night from the site: its title and time, the planned groups and bench, each person's characters
  (GUIDs once known, names until then), soft reserves, loot priorities and council notes, the pug lists.
- **Invite** everyone planned who's online (`C_PartyInfo.InviteUnit`), with a list of who isn't online.
- **Arrange groups:** move each member to their planned subgroup (`SetRaidSubgroup`, `SwapRaidSubgroup`, out of
  combat, as leader or assistant), and show who's in the wrong group.
- **Readiness** before a pull, out of combat only: who's in the instance, who's offline, and (if auras stay readable
  outside encounters) who's missing a flask or a raid buff.
- **Assignments** (the site's boss assignments, round 28 stage 5, in place of MRT notes): each player sees their own
  for the boss they target or pull (`ENCOUNTER_START`), the leader the whole sheet; nothing is posted to chat.

### Attendance
- **Snapshots** of the raid (`GetRaidRosterInfo`: GUID, name, class, subgroup, online, zone) at zone-in, at every
  `ENCOUNTER_START` and `ENCOUNTER_END` (with the encounter id, difficulty, size and whether it was a kill), every five
  minutes in between, and at leaving or disbanding.
- **Per person:** first and last seen, the pulls and kills they were in, time offline, and their group. Late and
  early fall out of it; the night's start time comes from the import.
- **The bench:** people the plan benched, plus anyone the leader marks "on standby" in the window, count as there.
- **Pugs:** anyone not in the guild (`GetGuildInfo`, or not on the imported roster) is recorded as a pug with GUID,
  name and class.

### Pugs
- The site's white and black lists, imported. A blacklisted GUID (or, before GUIDs are known, name) joining the group
  raises a warning for the leader only (no chat), with the site's note.
- Every pug seen goes back in the export, so the site's list fills itself; the site keeps deciding who's on which list.

### Loot
- **Recording** without chat: `C_LootHistory` and `ENCOUNTER_LOOT_RECEIVED` (each boss's drops, winners and rolls by
  GUID), `LOOT_ITEM_ROLL_WON`, and trades (`TRADE_*`, the trade window's items) so a drop handed on is credited to whoever
  ends up with it; disenchants and bank deposits marked as such.
- **Seeding:** soft reserves, wishlists, priorities and council notes from the import, shown in the loot window and in
  item tooltips ("Reserved by Thrall, Jaina").
- **Distribution**, by the guild's method:
  - **Rolls:** the window lists who reserved the item and who rolled, from the client's roll events, not chat.
  - **Council:** officers' addons share a vote per item over OFFICER/RAID addon messages, queued during encounters;
    the master looter sees the votes and the notes.
  - **Master loot**, only if Forever allows it (to test): one click gives the item (`GiveMasterLoot`) and records it.
  - **Bidding, for a guild on DKP or EPGP** (the owner, Oct 16: "in our addon we would have a bidding mode for it"):
    - **DKP:** the master looter opens an item for bids with the guild's minimum and step (from the import). Raiders
      bid from a small window, never chat; each bid is checked against the bidder's standing from the import, less
      what they've already won tonight. Bids go over RAID addon messages, queued during encounters. The looter sees
      the bids, closes the auction and gives the item; ties go to the earlier bid, or a roll if the guild says so.
    - **EPGP:** no bids. Whoever wants the item says need or greed in the window; the highest priority (EP over GP,
      from the import, with tonight's wins added) wins, and the item's GP is charged.
    - **Hard reserves skip the auction:** an item the site hard reserves (and that's still reserved: not on farm, if
      the guild ended it there) goes to its holder at no cost, as on the site; any charge is the officers' to make by
      hand afterwards.
    - **The site keeps the standings:** the addon only proposes charges. The export carries each item's winner, bid
      or GP and the auction's bids; the site charges them when the officer saves the preview, so a mistake in game is
      fixed on the site, not in the addon.
- **The officers' line stays the officers'** (the owner, Oct 20: raiders see the priorities part of a council's loot
  line, the best-in-slot and wishlist tiers are officers-only; "how will we make it so only officers can for the in game
  addon"). The addon shows only what its string carries, and the site makes each string for whoever asks:
  - an officer who hands out loot gets the whole line;
  - a raider's import has the priorities alone, so the officers' tiers never reach their client.
  - **Officer strings are marked as such.** The addon shows the officer view only while the player is the guild's
    officer in game too, so a string passed to a raider shows them nothing more.
  - **Addon-to-addon sharing** (the leader's changes passed round the raid) sends the raider-safe part to RAID. The
    officers' tiers go to OFFICER alone, or nowhere.
  - **Council votes and notes** travel on OFFICER messages only.
- **The ledger** in the export: item id and name, boss, winner GUID, how (reserve, hard reserve, roll, council, bid,
  master, trade, disenchant, bank), the winning bid or GP when there was one, and a dedupe key, so importing the same
  raid twice adds nothing (the site's ledger already dedupes).

### Guild bank
- **If Forever turns guild banks on** (`C_GuildBank.IsGuildBankEnabled()`, to test): read the bank log
  (`QueryGuildBankLog`, `GetGuildBankTransaction`, the money log) when an officer opens the bank, and its tabs' contents.
- **Otherwise:** a bank character's bags, bank, mail and gold, snapshotted when they're opened.
- **The export** carries new log lines since the last export (by a cursor) and the latest snapshot; the site turns
  them into a ledger (who deposited or withdrew what, and when) and a current inventory.

### Settings
- Which modules are on, the five-minute snapshot interval, whether pug warnings sound, which loot method the guild
  uses, and how much to keep (raids older than a month are dropped once exported). **Built in M1:** whether combat
  logging is turned on at zone-in to a raid (`autoLog`, on by default, `/gg log on|off`) and test recording
  (`testDungeons`, off by default, `/gg test on|off`); the rest wait for their milestones.

## The contract with the site

The addon and the site talk in one kind of string, both ways, and integrate with no other addon (the owner, Oct 19:
"instead of gargul/mrt or whatever other addons, lets design these imports/exports/integrations for our own wow addon
instead"). **The format is in [contract/README.md](../contract/README.md)**, version 1, with a fixture of every import
and export in `contract/fixtures/` (each as `.json` and `.gg1.txt`). `npm test` checks the fixtures against it
(`test/contract.test.mjs`). The site's tests read the same files, so both ends agree. It replaces the sketch that was
here, and where this file still describes a field of the string, contract/README.md wins.

What the string holds, in short: `GG1:` and standard base64 of the zlib-wrapped deflate (RFC 1950) of UTF-8 JSON of one
object with `v` (1), `kind` (`import` or `export`) and `meta`. Imports (`meta.from`: `priorities`, `night-loot`,
`night-assignments`, `night`) carry `guild`, `night`, `people` and `raids[]`: each raid with its instance id, effort
level, picks, groups, bench, loot priorities and assignments. Exports carry `attendance` (snapshots grouped by raid),
`loot` (each with a `dedupe` key) and `pugs`. More than one player's addon may export the same raid, and the contract
says how the site joins them.

### What is decided, and what is a proposal

**Decided** (the site's code makes it today, an earlier decision here says so, an architect's review settled it, or it
follows):
- The packing: `GG1:`, standard base64 with padding, zlib-wrapped deflate (what the site writes now, not raw deflate),
  UTF-8 JSON; readers strip whitespace.
- `v` is an integer that changes only for a break. New fields, parts and `meta.from` values never change it. Readers
  ignore unknown fields. The addon refuses a newer `v` with "Update the addon", the site with "The site is behind", and
  both read older ones.
- Keys: players by GUID (names are labels, "First Surname"), items by id, bosses by encounter id, raids by instance
  id, times in epoch ms. The addon takes times from the server clock.
- The 1 MiB limit on unpacked JSON (the site's today).
- The four imports and their parts. A night is `raids[]`, and everything that differs by raid (effort, picks, groups,
  bench, loot, assignments) sits in that raid's entry.
- The export's three parts and their fields. `meta`: `made`, `site` (the site's semver), `latest` (imports); `id`,
  `addon`, `client` (with `locale`), `by`, `realm` (exports).
- **Open enums:** an unknown `how` reads as `other`, an unknown `why` as `interval`, an unknown `expects` or `lootBy`
  value is ignored, an unknown `from` still reads its known parts, and none is a refusal. A field's type never changes
  (a frozen list of fields and types, `contract/schema-v1.json`, and a test hold it).
- **Exports are facts that are only added to.** Corrections happen on the site. `undo[]` and `loot[].replaces` are
  reserved. A raid with no `leave` snapshot is open until the end of its raid day. Readers accept at least what
  writers may write. The addon escapes `|` in site text. One `v` serves both directions.
- **Two recorders:** loot keys are opaque to the site, which keeps aliases and matches a like award from another
  recorder (same item, winner and encounter, within 10 s, or 120 s for trades, disenchants and bank). Raids from
  several recorders join into runs, and snapshots are stored by recorder, raid `id` and time. A raid's `id` is a
  per-recorder key, not its identity.
- **The guild:** an export whose `meta.guild` differs from the guild it is pasted into is refused; one with none is
  read, with a warning that shows `meta.guildName`.
- **Fields:** `standby` as `{guid, name, cls?}` objects; an attendance raid's `name` (required), `night`, `leader`
  and `lockout`; `lootBy` and `sr` (soft reserves, with SR+ weeks) in imports; a loot award's `boss`, `count`,
  `offspec` and the winner's `guid` from `C_LootHistory` first (the roster only on an exact, unique full-name match);
  `meta.skew`, `meta.realm`, `meta.guildName`. `meta.night` is a hint only.
- **How a long night is kept under the size limit:** drop repeated intervals, keep a quarter, one string for each raid,
  keep a sixteenth, then cut a raid in pieces that share its `id`.

**Proposals for the owner:**
1. **The addon's loot key recipe,** `L1|item|winner|seconds|encounter|n`, joined and not hashed (contract/README.md,
   "The addon's own recipe for its keys"). The site doesn't depend on it.
2. **The ids:** an export's `meta.id` (`<made in base 36>.<8 random hex digits>`) and a raid's `id` in `attendance`
   (`<recorder's GUID>:<instance id>:<epoch seconds of the first snapshot>`).
3. **Written size limits:** 65,536 characters of text and 768 KiB of JSON. The text limit waits on the launch-day
   probe's paste boxes (docs/RESEARCH.md).
4. **`meta.by`** is whoever recorded the export, not the raid leader (the leader may not run the addon).
5. **`drop`**, `"<encounter id>:<loot list key>"` from `C_LootHistory`, waits on the launch-day probe, which records
   what identifies a drop (docs/RESEARCH.md).
6. **The run rule's numbers:** adjacent means a gap of 10 minutes or less, and a shared kill is within 90 seconds.

**Left to the site, not in the contract:** how it shows a run's attendance, and how it closes a raid left open.

**Changes from the string the site makes today** (nothing has shipped; it is locked until the addon is out): `at`
becomes `meta.made`, `from` becomes `meta.from`, `meta.site` and `meta.latest` are new, `raid` and the per-raid parts
become `raids[]`, a missing GUID or class is left out instead of `null`, and `night.groups` and `night.bench` (in the
sketch, never sent) are per raid.

### Instead of other addons

| Another addon's job | Ours |
|---|---|
| Gargul's loot priority import | The import's `loot`: "Copy for the addon" on Priorities and a night's Loot (round 28, stage 1; locked until the addon ships) |
| MRT notes for boss assignments | The import's `assignments`, each player's own in game (round 28, stage 5) |
| Invite and group-sorting addons | Tonight: invite the raid and arrange its groups (M2) |
| RCLootCouncil's or Gargul's loot CSV, pasted on the site | The export's loot ledger (M4). The site's CSV import stays until then |

### A Sync button, with nothing pasted (the owner's question, Oct 13)

"is there any way that if we have an addon, i can click a button and itll make an api call to the website like for
example the loot or bank rather than having to do it manually via imports/exports?"

An addon can't call the site: the game gives addons no network. What it can do is write its saved variables, and the
game writes those to disk when the interface reloads (or on logout). So the call is made by the site's own open page:

- **In game, the button is "Sync":** it stores what is new (loot, attendance, the bank) and reloads the interface.
  The file `WTF/Account/<account>/SavedVariables/GuildGolem.lua` is on disk a few seconds later.
- **The site reads that file itself.** Once, the officer points a Guild Golem page at the file (the browser's File
  System Access API: Chrome and Edge on a desktop). While a Guild Golem tab is open the page watches the file, and
  when it changes reads it and posts what is new, as the paste box would have.
- **The other way round:** with leave to write, the page keeps the night's import (roster, reserves, priorities, pug
  lists) in a data file in the addon's own folder, which the game reads at the next reload.
- **Only with the game outside Program Files** (docs/RESEARCH.md, "Probe results", Oct 22). Chrome and Edge refuse a
  page any file under `Program Files`, and Battle.net installs the game there by default. So a tab can read and
  write these files only when the game is installed somewhere else. For a default install, the desktop app is the
  way to do it (gg-desktop, on hold).
- **Its other limits:** Chromium browsers only (others keep the paste box); a tab must be open; the browser asks
  again for the file after a restart, one click; a reload takes the screen for a few seconds, so it is for between
  pulls.
- **To test before building it:** with the game outside Program Files, that the browser can read the saved file while
  the game has it, and rewrite the data file. The probe found that a file the TOC lists, rewritten on disk, is read
  on a `/reload` without restarting the client (docs/RESEARCH.md, "Probe results").
- **Blizzard's API for Forever** (the owner: "there will be a forever api") will give characters, their gear and the
  guild's roster with no addon at all. Loot as it is handed out, attendance by the minute and the bank's ledger stay
  the addon's.

## What the site needs (when the addon is built)

- **The night's page:** "Copy for the addon" (the import string) and "Paste from the addon" (with a preview: who was
  there, what dropped, which pugs). Loot › Priorities and a night's Loot copy theirs already (round 28, locked until the
  addon ships: `UNLOCKED` "addon").
- **Attendance from the addon** as a third source beside answers and logs (server/attendance.ts): present by
  snapshots, late and early from first and last seen, the bench counting as there. Logs stay the proof of who played;
  the addon is the proof of who was in the group.
- **GUIDs:** a GUID on roster characters where the addon (or a log) sees one, and on pugs (`pugs.guid`, the migration
  docs/RESEARCH.md foresaw), so names stop mattering.
- **Loot imports** into the existing ledger with `source = 'addon'` and its dedupe keys.
- **Pug lists:** pages for the white and black lists the addon imports (M3). The site's `pugs` table has their
  states (seen, white, black), but nothing reads or writes it yet.
- **A guild bank ledger:** new tables (transactions and snapshots) behind the Bank page the site already has, which
  bankers fill by hand today.
- **Bot:** the night's Discord post gains "Attendance recorded" and a loot summary once the export is in.

## Milestones

| | Milestone | Done when |
|---|---|---|
| M0 | **In-game tests** (docs/RESEARCH.md, "To test in game") | Name formats, guild bank on or off, loot methods and master loot, secret restrictions in raid zones: answered on the live client |
| M1 | **Core and attendance** | The addon records a raid's snapshots and exports them; the site imports them as attendance. **Built (Oct 25), not yet run in the game.** `Core/Codec.lua` reads and writes the strings, `Core/Store.lua` keeps the saved variables with migrations and an outbox, `Core/Import.lua` reads the four imports, `Client.lua` is the launch adapter and `Core/Events.lua` the event bus. `Attendance.lua` takes the snapshots (zone-in, pull, kill, wipe, every five minutes, leave), `Export.lua` makes the export with the contract's `fit`, and `UI.lua` is the window and `/gg`. It turns combat logging on at zone-in to a raid. A scripted night of forty players in three raids over four hours exports 37 snapshots in one string of about 4.5 KB that the reference validator accepts (`test/night.test.mjs`). **What is left is the first run in the game**, "M1 smoke test in game" in docs/RESEARCH.md: on launch day in a 5-man dungeon with test recording on, then inside a raid instance (Forever opens its first about Dec 9), what `GetInstanceInfo`, `GetRaidRosterInfo` and the `ENCOUNTER_*` events give, whether the roster's zone for a player inside is the instance's name, whether the edit boxes take a 64 KB string, and that the site's import reads what the addon wrote |
| M2 | **Tonight** | Import the plan; invite the raid and arrange its groups in one click each; each player's assignments for the boss |
| M3 | **Pugs** | Pug lists in game with warnings; pugs seen flow back to the site |
| M4 | **Loot recording and seeding** | Every drop, trade and disenchant in the export; reserves and priorities in tooltips and the loot window |
| M5 | **Loot distribution** | Rolls, council voting and DKP or EPGP bidding in the addon (and master loot if Forever allows it); the site charges the bids from the export |
| M6 | **Guild bank** | The bank's log or a bank character's snapshot becomes the site's ledger |
| M7 | **Sync** | An open Guild Golem tab reads the addon's saved file when the game writes it (logout or reload) and writes the next import beside it, so nobody pastes. A tab can reach those files only when the game is installed outside Program Files. A default install needs the desktop app, which is on hold (Oct 20) |

M1 and the site's import come first: attendance is the owner's first ask, and it proves the strings end to end.

## How it's built and tested

- **Repo:** this one (gg-addon, moved out of the site's repo Oct 22): the addon in `GuildGolem/`, with the
  packager's `.pkgmeta`, released to CurseForge (project 1757198) and Wago (`v63QDLGb`) by
  `.github/workflows/release.yml` when a version tag is pushed (the folder is packaged as a checkout of its own, with
  the tag as its version, and a tag with `beta` in it uploads a beta, as the first, `v0.1.0-beta`, will; tokens in
  the repository secrets `CF_API_TOKEN` and `WAGO_API_TOKEN`), with the TOCs above ("Ground rules from the client").
  Its TOCs carry `## X-Curse-Project-ID: 1757198` and `## X-Wago-ID: v63QDLGb`; the projects' page text is
  `LISTING.md`. Versions follow the export format, so a new format version means a new major version, and the site
  reads every format it ever shipped.
- **Pure Lua cores** (strings, snapshots to attendance, the loot ledger) tested outside the game, against fixtures
  shared with the site's tests, so both ends agree on the format. The harness is in `test/lua/` (its README explains
  it): fengari runs the Lua in Node under `npm test`, with the game's functions stubbed (`wow.lua`: a roster, an instance,
  a fake clock and timers, an addon message outbox, saved variables written at a fake logout) and a Lua 5.1 shim. A job in
  CI runs the same specs on real Lua 5.1, which has the last word on whether code stays in what 5.1 and 5.3 share.
  A test checks that only `GuildGolem/Client.lua` (and `Libs/`) reads a game global, so the rest of the addon can be
  tested with a fake Client and none of the game's functions.
- **In game:** a checklist per milestone on the live client, in a raid group, before each release; the client changes
  weekly, so the research is re-checked first.
- **The site's side** gets worker tests for every import, including bad, old and duplicate strings.

### What the core is (Oct 25)

All of it plain Lua 5.1 with specs in `test/lua/specs/`, run in Node and on real Lua 5.1 in CI; `Client.lua` is the one
file that names the game.

| File | What it does |
|---|---|
| `Client.lua` | The launch adapter. Detects each API before using it, wraps every call in pcall, drops secret values, and returns plain rows (roster, instance, lockouts, guild, encounter start and end, loot received, build, server time). `Client.caps()` says what the client has. Each line that follows retail's documented shape and has not been seen on Forever is marked `unverified on Forever`: `grep -n "unverified on Forever" GuildGolem/Client.lua` is the launch-day probe pass's list |
| `Core/Codec.lua`, `Base64.lua`, `ZlibSize.lua` | The `GG1:` strings exactly as contract/README.md reads and writes them, with every refusal (`not-ours`, `too-long`, `bad-text`, `bad-zlib`, `too-big`, `bad-json`, `malformed`, `newer`, `wrong-way`) and the size limits. `ZlibSize` counts what a stream would unpack to before LibDeflate (which has no limit) unpacks it, so a small string cannot grow to hundreds of MB |
| `Core/Store.lua` | `GuildGolemDB` with a `schema` (1) and forward-only migrations, a capped error list, and the outbox of exports not yet pasted, which nothing drops. A table from a newer addon is left as it is, with a warning, and the session works on a scratch copy |
| `Core/Import.lua` | Reads the four imports into the store by the reader rules (unknown fields ignored, unknown enums read as their default, unknown people ignored, a missing required field refuses the whole string and names it) |
| `Core/Events.lua` | The event bus: handlers under pcall (an error is recorded and never breaks the others), and addon messages queued through an encounter, a lockdown or the client's rate limit, sent after `ENCOUNTER_END` or when a restriction clears |
| `Attendance.lua` (M1) | Records a raid's roster snapshots into `db.raids` as the contract's attendance entries: at zone-in to a raid instance (with a group), at `ENCOUNTER_START` and `ENCOUNTER_END` with the boss's id and kill or wipe, every five minutes by a timer, and on leaving the instance or the group. Each raid also has the instance, difficulty, size, the raid leader at zone-in, the lockout once the game has one, the bench from the import as `standby` and the night's handle when an import plans this instance. Turns combat logging on at zone-in, if the client can and the player has not said no |
| `Export.lua` (M1) | Builds an export of what was recorded since the last one (or all of it), with `meta` and the pugs (players in the snapshots who are not on the imported roster), fits it to the writers' limits with the contract's `fit`, packs it with the codec, puts it in the outbox and marks the raids as covered |
| `UI.lua` (M1) | `/gg`: the window (a paste box with a preview or the reader's refusal, a copy box with the export selected, a status line) and `/gg status`, `/gg export [all]`, `/gg log on\|off`. It names no frame: `Client.window` builds the window from a description, so `Client.lua` is still the only file that touches the game |

**What the core chose where the contract is silent** (each is one place in the code, easy to change; M1's choices follow in the next list):
1. **How the imports of one night combine.** Kept by the night's handle; each part of a raid (loot, assignments, groups
   and so on) is replaced by an import of the same or a newer `meta.made`, never by an older one, and a whole `night`
   string replaces the night and drops the raids it doesn't list. A person's name comes from the newest import and their
   characters are every character any import named.
2. **Officer tiers.** `meta.officer` is kept with each import, but no item field is marked officer-only in the contract, so
   the core hides nothing yet. The window (M2) decides what to show, from that flag and the player's guild rank.
3. **A string for another guild.** An import's guild replaces the saved guild; the contract only refuses exports for
   another guild, on the site.
4. **`meta` as an empty list.** json.lua cannot tell `[]` from `{}`, so `"meta": []` passes the codec and is refused by
   the import for lacking `from`. json.lua also reads a trailing comma and hex numbers, which strict JSON does not.
   Neither can come from a writer that follows the contract.

**What M1 chose where the contract is silent** (`Attendance.lua` unless it says otherwise; the numbers are constants at its top):
1. **Where it records.** Only in a raid instance (`GetInstanceInfo`'s type is `raid`) with a group (a raid or a party). A
   solo player in one records nothing. A 5-man dungeon records nothing, unless **test recording** is on (`testDungeons`,
   `/gg test on`, off by default): then a party in a dungeon is recorded exactly like a raid, so the whole path can be tried
   on launch day, weeks before a raid opens. `/gg status` and the window say plainly that it is on, and the raid entry it
   makes carries `test: true` in the export (contract/README.md, `attendance[]`, an optional field the site reads as
   "keep apart from real raids"; fixture `export-test-dungeon`). A raid recorded while the setting is on is not marked.
   Turning it off in a dungeon ends the recording.
2. **One raid, or two.** A player who leaves the instance and comes back to the same one (same instance id and difficulty)
   within 30 minutes goes on with the same raid entry, with another `zonein` snapshot, because a second entry from the
   same recorder would be a second raid on the site. After 30 minutes, or into another instance or difficulty, it is a new
   raid. A `/reload` in the raid goes on with it too. A login anywhere else ends a raid the last session left open,
   with no `leave` snapshot (nobody knows when the player left; the site closes it at the end of its raid day).
3. **Leaving the group** takes a `leave` snapshot with whoever the roster then shows, which is nobody: `members` is the
   empty list the contract allows. Leaving the instance with the group takes a full one, whose `zone` labels show where
   each player went.
4. **"In the instance or not"** is each member's `zone` label from the roster (the contract has no flag for it): the site
   compares it with the raid's `name`. Whether the roster's zone for a player inside is the instance's name is the
   first thing to check in game.
5. **Two snapshots never share a second** (the site keys a snapshot by raid `id` and `at`). An `interval` that would is
   dropped; any other kind is moved one second later than the one before.
6. **Repeats are dropped at record time.** An `interval` snapshot whose people, online states, zones and subgroups match
   the one before it (of any kind) is not kept, which is the contract's `fit` step 1 done early to keep the saved file
   small. The export's `fit` still runs step 1 and finds nothing more to drop.
7. **The night.** An imported night that starts within a day of now and plans the instance (or has a raid with no zone)
   names the raid: the nearest wins. Its bench becomes `standby`, by the pick for that raid or else the person's first
   character; a benched character whose GUID the import does not know is left out, since `guid` is required. A benched
   player who then came into the group is in the snapshots and not in `standby`.
8. **Pugs** are the players in the exported snapshots who are on none of the imports' rosters (by GUID, or by exact name where
   the import knows only the name) and are not the recorder. With nothing imported there is no roster, so no pugs.
   Whether someone is in the guild (`GetGuildInfo` per unit) is not asked in M1.
9. **The export's marks.** A raid keeps `sent`, the count of its snapshots an export covered. The next export holds the
   rest, as a piece of the same raid `id`. `/gg export all` repeats everything, with a new `meta.id`. `meta.night` is
   the handle of the night most recently imported. `meta.skew` is the server's clock less `time()`.
10. **Packing.** `Codec.LEVEL` is 8. LibDeflate's default level leaves an export a third larger than zlib's does (the
    roster repeats from one snapshot to the next and the higher levels find it); at 8 it is within about 10% of Node's zlib on
    these exports and takes well under a second for a night. Readers do not care how a stream was made.
11. **Ids.** `meta.id` is `<made in base 36>.<8 hex digits>` from a small generator seeded with the time, the uptime, the
    player and a count, so the game's `math.random` is left alone. A piece of a cut export is `<id>.<n>`. A raid's `id` is
    `<recorder's GUID>:<instance id>:<epoch seconds of its first snapshot>`, as proposed.
12. **The outbox.** An export waits there until the officer presses "Pasted on the site", which marks it (it is kept a
    month and then goes). Nothing else drops it. The window steps through what waits, newest first.
13. **Combat logging.** `LoggingCombat(true)` once per entry to a raid instance, when it is available, the saved option
    `autoLog` is not `false` (`/gg log off`) and it is not on already; one line in chat says so. Nothing in the addon calls
    it with `false`; a spec reads `Client.lua` to keep it so.
14. **A raid of the saved file** older than 30 days and fully exported is dropped at login (`Attendance.prune`).

**Contract questions M1 raised** (the contract still reads as it did; none changed it): the `leave` snapshot with an empty
`members` (3); a flag for "in the instance" in place of reading `zone` (4); what a recorder who leaves and re-enters an
instance should send (2: one raid, or two that the site joins, which the contract says a recorder's own entries never are);
and whether a `standby` entry may leave `guid` out for a character the import knows by name only (7).

## Open questions for the owner

1. **Name:** is it "Guild Golem" in game, with the `GuildGolem` folder and saved variables the Sync button reads,
   the `/gg` command and `GG1:` strings?
2. **Loot:** which method does the guild want first: soft reserves with rolls, loot council, DKP or EPGP bidding, or
   master loot?
3. **Bench credit:** does a benched or standby raider count as attending?
4. **Guild bank:** worth building if Forever's guild bank is off and it means a bank character?
5. **Uploader:** copy and paste only, or plan the desktop uploader from the start?

## Risks

- **The client changes weekly**, and Midnight's restrictions may tighten: everything rests on events and APIs that
  are documented, checked again before each milestone.
- **Master loot and guild banks may be off** on Forever's servers: both have fallbacks above.
- **Addon messages lock down during encounters:** council votes and version checks queue and send after the pull.
- **Copy and paste is friction:** keep strings small (deflate), make the paste box forgiving, and preview before saving.
