# In-game addon: plan

What the Codex addon is made of, how it talks to the site, and the order to build it in. **A plan, not a build**
(owner, Oct 8: "draft me a plan for our warcraft addon and what it needs to consist of - dont build it yet"): no Lua,
no addon files, until the owner says. What Forever's client allows is in docs/RESEARCH.md; this plan rests on
it and must be re-checked against the client before building, since it changes weekly.

**The current plan (Oct 20)** is the owner's Claude Doc "Bot, addon and site plan"
(https://claude.ai/code/artifact/849ea47a-33f1-4ee3-922f-18c3889e1621). It ties the addon to the bot and the site and
wins where the two differ: the addon's name in game (Guild Golem, folder `GuildGolem`, `/gg`, the owner's to confirm),
players downloading it from the site's Addon page, no reloads in normal use (a pasted string loads at once; logout
writes the file), Sync in place of a desktop uploader (on hold), what's already built (the guild bank is; pug lists
aren't), and 41 edge cases. The string format below stands.

## What it's for

The site already plans the raid (signups, groups, soft reserves, pug lists) and reads it afterwards (logs, loot,
attendance). The addon closes the loop inside the game, where the site can't see:

| Job | Today, without the addon | With it |
|---|---|---|
| Who was there | Answers, and logs when someone shares one | Roster snapshots at zone-in, every pull and the end: late arrivals, early leavers, the bench, pugs |
| Pugs | A white and black list on the site | Flagged the moment they join the group; every pug seen comes back to the site |
| Loot | Typed in by hand on the night's Loot page | Every drop, roll, trade and disenchant recorded; soft reserves and priorities shown in game; rolls or a council run from the addon |
| Guild bank | Nothing | Deposits, withdrawals and gold as a ledger on the site |
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

One addon, `Codex`, in modules that can be turned off. Libraries: Ace3 (AceAddon, AceDB, AceEvent, AceComm,
AceConsole, AceGUI), LibDeflate, a base64 decoder and rxi's json.lua (the import and export strings), LibDataBroker and
LibDBIcon (the minimap button). All MIT or similar; vendored in `Libs/`. It reads and writes no other addon's formats
(the owner, Oct 19): what others did for the site (Gargul's priorities, MRT's notes) is its own (below, "Instead of
other addons").

### Core
- **Saved variables:** one account-wide table (imports, pug lists, settings, and each character's bank snapshots
  keyed by GUID): a per-character file lands in a folder Sync doesn't read (Oct 20). A schema version, with migrations
  when it changes.
- **Identity:** the player's GUID, guild name, and the guild's Codex handle (from the last import), so exports are
  tied to one guild.
- **Strings:** `GG1:` + base64 of the zlib-deflated JSON of one object (below, "The string"), its Adler-32 checked
  and its size limited. Imports are validated field by field before use; anything unknown is ignored, never run.
- **Event bus** over the client's events, with a queue for anything that must wait out an encounter.
- **UI:** a minimap button and a slash command (`/codex`) that open one window with tabs: Tonight, Attendance, Loot,
  Bank, Pugs, Import/Export, Settings. Everything works from the slash command too (`/codex import`, `/codex export`).
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
  uses, and how much to keep (raids older than a month are dropped once exported).

## The contract with the site

The addon and the site talk in one kind of string, both ways, and integrate with no other addon (the owner, Oct 19:
"instead of gargul/mrt or whatever other addons, lets design these imports/exports/integrations for our own wow addon
instead"). Its reader on the site is the site repo's `app/features/guild/addon.ts` (`addonString`, `readAddonString`), and its fixtures
are shared with the addon's tests, so both ends agree.

### The string

- **`GG1:`, then base64 of the zlib-deflated UTF-8 JSON of one object.** Base64 is the standard alphabet (RFC 4648)
  without line breaks; zlib (RFC 1950) carries an Adler-32, so a string cut short or mistyped in pasting fails as one
  instead of reading wrong.
- **Why JSON, not LibSerialize:** the site writes and reads it with what browsers and Workers have built in
  (`CompressionStream("deflate")`, `JSON`); the addon reads it with three small MIT libraries (LibDeflate's
  `DecompressZlib`, a base64 decoder, rxi's json.lua); and a decoded string is readable when something goes wrong.
- **`v`, the format version** (1). The addon refuses a version it doesn't know ("Update the addon"); the site reads
  every version it ever shipped. A new field is not a new version: both ends ignore what they don't know.
- **`kind`:** `import` (site to addon) or `export` (addon to site). Every other part is optional.
- **Keys:** people by the site's person id (`p`), characters by GUID once known and their full name until then, items
  by the pack's item id, bosses by the game's encounter id. Names are labels, never keys (Forever's carry surnames, and
  there is one mega-realm).
- **Size:** an import is a few KB. The site refuses a pasted export past 1 MB unpacked.

### Import (site to addon)

"Copy for the addon", wherever the plan is kept. Each copy carries the parts its page holds:

| Copied from | Parts |
|---|---|
| Loot › Priorities (the raid on show) | `guild`, `raid`, `people` (each by their main), `loot` |
| A night's Loot | `guild`, `night`, `people` (by the character each answered with), `loot` (those coming) |
| A night's page (M2) | all of them: `night` with its groups and bench, `people`, `loot`, `points`, `pugs`, `assignments` |
| A night's Assignments (round 28, stage 5; `from: "night-assignments"`) | `guild`, `night`, `raid`, `people` (by the character that does each slot), `assignments` (a strat for officers only stays on the site) |

```json
{
  "v": 1,
  "kind": "import",
  "at": 1760918400000,
  "from": "night-loot",
  "guild": { "handle": "abcd2345", "name": "Molten Raiders" },
  "night": { "handle": "efgh6789", "title": "Naxx, team A", "startsAt": 1760925600000, "size": 40, "groups": [[12, 7], [9]], "bench": [3] },
  "raid": { "zone": "Naxxramas" },
  "people": [{ "p": 12, "name": "Vex", "chars": [{ "name": "Vex Moonwhisper", "cls": "mage", "guid": "Player-6103-029CF08B" }] }],
  "loot": { "items": [{ "id": 22812, "key": true, "specs": [["mage:1", "warlock:3"], ["priest:3"]], "order": [[12], [7, 9]], "note": "" }] },
  "assignments": [{ "encounter": 1120, "boss": "Thaddius", "lists": [{ "name": "Tanks", "slots": [{ "label": "Left platform", "p": [7], "note": "Pull him to the left" }, { "label": "Right platform", "p": [] }] }] }]
}
```

| Part | Fields |
|---|---|
| `guild` | handle, name |
| `night` | handle, title, starts at, raid size, `groups` (subgroups 1–8, person ids), `bench` |
| `raid` | the zone the copy is of |
| `people` | `p`, name, rank, `chars` (name, class, GUID when known): the character the plan names first |
| `loot.items` | `id`; `order`, places best first, each place's people (a tie shares one); `key`, one of the raid's key items; `specs`, the spec order (tiers of `class:tab`, best first; on an open roll the first tier anyone in the raid plays rolls first); `free`, an open roll; `hard`, a hard reserve's person (0: the guild's); `note` |
| `points` | for DKP or EPGP: the system, each person's standing (DKP, or EP and GP), the minimum bid and its step, items' GP (M5) |
| `pugs` | GUID or name, list (white or black), note (M3) |
| `assignments` | per boss (`encounter`, left out for what the game has none for: trash, a pull the guild named; `boss`): named `lists` of `slots`, each a `label`, its people (`p`, empty when nobody fits tonight) and an optional `note`, as the night filled them from its groups (app/features/guild/assignments.ts). The addon shows each player their own slots when the boss is targeted or pulled, and the leader the whole sheet; nothing goes to chat |

### Export (addon to site), one per raid

"Paste from the addon" on the night's page, checked and previewed before it's saved. The same string, `kind: "export"`:

| Part | Fields |
|---|---|
| `meta` | addon version, guild handle, night handle (from the import), the leader's GUID, when it was made |
| `snapshots` | when, why (zone-in, pull, kill, wipe, interval, leave), encounter id, members (GUID, name, class, subgroup, online, zone) |
| `loot` | the ledger (above, "Loot") |
| `pugs` | every pug seen: GUID, name, class, when |
| `bank` | log lines since the cursor, the latest snapshot |

Every part is optional, so a raid with no loot or a bank-only export still imports.

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
  when it changes reads it and posts what is new, as the paste box would have. Nothing to install.
- **The other way round:** with leave to write, the page keeps the night's import (roster, reserves, priorities, pug
  lists) in a data file in the addon's own folder, which the game reads at the next reload.
- **Its limits:** Chromium browsers only (others keep the paste box, or the desktop uploader of M7); a tab must be
  open; the browser asks again for the file after a restart, one click; a reload takes the screen for a few seconds,
  so it is for between pulls.
- **To test before building it:** that the browser can read the file while the game has it; that a data file the page
  rewrote is read on a reload without restarting the client (a file the TOC lists should be; a new one needs a
  restart).
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
- **A guild bank ledger:** new tables (transactions and snapshots), a Bank tab under the guild for officers.
- **Bot:** the night's Discord post gains "Attendance recorded" and a loot summary once the export is in.

## Milestones

| | Milestone | Done when |
|---|---|---|
| M0 | **In-game tests** (docs/RESEARCH.md, "To test in game") | Name formats, guild bank on or off, loot methods and master loot, secret restrictions in raid zones: answered on the live client |
| M1 | **Core and attendance** | The addon records a raid's snapshots and exports them; the site imports them as attendance |
| M2 | **Tonight** | Import the plan; invite the raid and arrange its groups in one click each; each player's assignments for the boss |
| M3 | **Pugs** | Pug lists in game with warnings; pugs seen flow back to the site |
| M4 | **Loot recording and seeding** | Every drop, trade and disenchant in the export; reserves and priorities in tooltips and the loot window |
| M5 | **Loot distribution** | Rolls, council voting and DKP or EPGP bidding in the addon (and master loot if Forever allows it); the site charges the bids from the export |
| M6 | **Guild bank** | The bank's log or a bank character's snapshot becomes the site's ledger |
| M7 | **Sync** | An open Guild Golem tab reads the addon's saved file when the game writes it (logout or reload) and writes the next import beside it, so nobody pastes (a desktop app is on hold, Oct 20) |

M1 and the site's import come first: attendance is the owner's first ask, and it proves the strings end to end.

## How it's built and tested

- **Repo:** this one (guildgolem-addon, moved out of the site's repo Oct 22): the addon in `GuildGolem/`, with the
  packager's `.pkgmeta`, released to CurseForge (project 1757198) and Wago (`v63QDLGb`) by
  `.github/workflows/release.yml` when a `v1.2.3` tag is pushed (the folder is packaged as a checkout of its own,
  version `v1.2.3`; tokens in the repository secrets `CF_API_TOKEN` and
  `WAGO_API_TOKEN`), with `_Camelot` and `_Mainline` TOCs. Its TOCs carry `## X-Curse-Project-ID: 1757198` and
  `## X-Wago-ID: v63QDLGb`; the projects' page text is `LISTING.md`. Versions follow the export format: a new format version means a new major version,
  and the site reads every format it ever shipped.
- **Pure Lua cores** (strings, snapshots to attendance, the loot ledger) tested outside the game with busted, against
  fixtures shared with the site's tests, so both ends agree on the format.
- **In game:** a checklist per milestone on the live client, in a raid group, before each release; the client changes
  weekly, so the research is re-checked first.
- **The site's side** gets worker tests for every import, including bad, old and duplicate strings.

## Open questions for the owner

1. **Name:** "Guild Golem" in game (the `GuildGolem` folder and saved variables the Sync button reads, `GG1:`
   strings), or "Codex"?
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
