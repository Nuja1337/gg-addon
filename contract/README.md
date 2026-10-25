# The contract with the site, version 1

What Guild Golem's addon and its site put in the strings they trade, and what each does with a string it reads. This
file is the contract. docs/PLAN.md says why the addon exists and in what order it gets built.

A **string** is text a person copies and pastes. The site makes **imports** (loot priorities, a night's plan, boss
assignments) that a player pastes into the addon. The addon makes **exports** (attendance, loot awarded, pugs) that an
officer pastes back into the site. Both are the same kind of string.

Once players hold these strings, and the addon's saved file holds them, the format is costly to change. So version 1
is meant to be complete: every field below is either required, or optional with a stated meaning. New optional fields
can be added later without a new version (below, "Versions").

**Status marks.** A rule marked **Proposal** is not yet agreed with the owner. Every other rule is decided: the
site's code does it today, docs/PLAN.md says so, an architect's review of this contract settled it, or it follows
from them. The list of proposals is in docs/PLAN.md, "The contract with the site".

**Files here.** `fixtures/` holds one example of every import and export, each as `name.json` and `name.gg1.txt`
(below, "Fixtures"). `schema-v1.json` is the frozen list of every field and its type (below, "Versions").
`test/contract.test.mjs` checks them against this file (`npm test`). `test/contract-lib.mjs` is this file as code: the
packing, a reader, a validator, what a reader makes of an unknown value, the addon's loot key recipe, the site's
matching of two recorders and the size rules. It is the reference both sides' code is checked against, and nothing
ships from it.

## The string

```
GG1:eJwtjrkOwjAQRH8FTe1YuxwB3NHQIVHRO3gBi8QJjrmVf0eOmPJp5mm+eMCwwtUHBwN5dW1MUGgkWZgvfKbN+cbX6Sdp+...
```

**Writing a string.** Take the JSON text of one object. Then:

1. Encode it as UTF-8, with no byte order mark.
2. Compress it as a **zlib stream** (RFC 1950): a 2-byte header, the deflate data (RFC 1951), and a 4-byte Adler-32
   checksum. It is not raw deflate and not gzip. The compression level doesn't matter to a reader. (A browser's
   `"deflate"` stream format, Node's `zlib.deflateSync` and LibDeflate's `CompressZlib` all write this.)
3. Encode the bytes as **standard base64** (RFC 4648 section 4): the alphabet `A-Z a-z 0-9 + /`, padded with `=` to a
   multiple of 4 characters, with no line breaks. The URL-safe alphabet (`-` and `_`) is not used.
4. Put `GG1:` in front.

**Reading a string**, in this order, stopping at the first failure:

1. Strip leading and trailing whitespace. The text must start with `GG1:` exactly (capital letters, the digit one).
   Otherwise: `not-ours`.
2. If the text is longer than **524,288 characters**: `too-long`.
3. Remove all whitespace (space, tab, CR, LF) from the rest, since chat boxes and editors wrap lines. What remains must
   be only base64 alphabet characters, with at most two `=` at the end. A reader accepts a string whose padding was
   lost. Anything else: `bad-text`.
4. Decode the base64 and unpack the zlib stream. A stream that is cut short, has a mistyped character, or whose
   Adler-32 doesn't match: `bad-zlib`. The reader stops unpacking at **1,048,576 bytes** (1 MiB) of JSON and refuses:
   `too-big`.
5. The bytes must be valid UTF-8 holding JSON whose top level is an object. Otherwise: `bad-json`.
6. The object must have `v`, an integer of 1 or more. Otherwise: `malformed`.
7. If `v` is more than the reader knows (below, "Versions"): `newer`. This comes before any other field is looked
   at, since a newer version may have changed them.
8. The object must have `kind` (`import` or `export`) and `meta` (an object). Otherwise: `malformed`.
9. If the string is the wrong way round for the reader (an import pasted into the site, an export pasted into the
   addon): `wrong-way`.

The `1` in `GG1:` is the envelope's generation, and `v` is the data's. A change to the packing itself (a different
compression or encoding) would be `GG2:`, and no reader of `GG1:` would read it. Nothing is planned.

**Why this packing.** The site writes and reads it with what browsers and Workers have built in, the addon with three
small libraries (LibDeflate, a base64 decoder, rxi's json.lua), and a decoded string is readable text when something
goes wrong. The Adler-32 makes a string cut short or mistyped in pasting fail as one, instead of reading wrong.

## The JSON

- **One object**, with the top-level fields `v`, `kind` and `meta`, and then the **parts** that kind has. Every part
  but those three is optional unless a table below says it's required.
- **Numbers are integers** (no fractions, no exponents) with an absolute value under 10^14. The addon's JSON library
  writes numbers with 14 digits, and a time in milliseconds has 13.
- **Booleans** are `true` and `false`. Flags that are only ever true (`key`, `free`, `offspec`, `test`) are left out instead of
  written `false`, and a reader reads a `false` as absent.
- **No `null`.** The addon's Lua has no null, so a writer leaves out a field that has no value. A reader treats `null`
  as the same as absent.
- **No empty objects.** Lua can't tell `{}` from `[]`, so a writer never writes `{}`. An empty list may be written
  `[]` or left out, and a reader treats both the same. Arrays have no gaps and no `null` in them.
- **Unknown fields are ignored** by every reader, at every depth. They are never an error, and a reader never passes
  them on as if it understood them.
- **An unknown enum value reads as its documented default and is never a refusal.** The enums are `how` (default
  `other`), a snapshot's `why` (default `interval`), `effort.expects` (a value it doesn't know is ignored), `lootBy`
  (ignored) and `meta.from` (the reader still reads the parts it knows). A refusal is only for a missing required
  field, a value of the wrong type, or a string that doesn't unpack.
- **A field's type never changes.** A field that is a string stays a string, an integer an integer, in every version.
  `schema-v1.json` and a test hold the line (below, "Versions").
- **Strings** are kept as the game gave them: no trimming, no case change, no Unicode normalizing. Names are labels,
  and are compared exactly.

### Keys

| Thing | Key | Form |
|---|---|---|
| A player | The game's GUID, `guid` | `Player-<server id>-<hex id>`, like `Player-9101-0F00AA11`. Kept whole: the one realm has more than one server id (docs/RESEARCH.md, "Probe results") |
| A player's name | `name`, a label only | As the game gives it: first name, a space, the surname ("Vex Moonwhisper"). Never a key when a GUID is known |
| A person on the site | `p` | The site's person id, a positive integer. The addon never makes one |
| An item | `id` or `item` | The pack's item id, the one in the item link |
| A boss | `encounter` | The game's encounter id (`ENCOUNTER_START`'s first value) |
| A raid (an instance) | `zone` | The game's instance id (`GetInstanceInfo`'s eighth value). A name next to it is a label |
| A class | `cls` | The class token in lowercase (`mage`, `warrior`). A label |
| A guild or night on the site | `handle` | The site's short handle, 4 to 16 lowercase letters and digits |
| A time | any field named `at`, `made` or `startsAt` | Epoch milliseconds, UTC |

### Times

Every time is **epoch milliseconds, UTC**, an integer. The addon makes its times from the server's clock,
`GetServerTime() * 1000`, never `time()` or the computer's clock (the two agreed within a second in the probe, but a
raid leader's clock can be wrong). That makes every time the addon writes a multiple of 1000. The site writes its own
with `Date.now()`. A reader takes any positive integer as a time, whole second or not, and `meta.skew` says how far the
computer's clock was from the server's.

## Top level and `meta`

| Field | Type | Imports | Exports | Meaning |
|---|---|---|---|---|
| `v` | integer | required, `1` | required, `1` | The version of the data |
| `kind` | string | `"import"` | `"export"` | Which way the string goes |
| `meta` | object | required | required | Below |

`meta`:

| Field | Type | Imports | Exports | Meaning |
|---|---|---|---|---|
| `made` | integer | required | required | When the string was made, epoch ms (the addon: `GetServerTime() * 1000`) |
| `site` | string | required | | The site's version, semver like `0.36.2`, for display and for bug reports |
| `latest` | string | required | | The newest addon version the site knows, `1.2.3` or `1.2.3-beta`. The addon says "A newer addon is out" when its own is older (compared as numbers by dot; a suffix is ignored) |
| `from` | string | required | | Which import this is (below). A reader that doesn't know the value still reads the parts it knows |
| `officer` | boolean | optional | | `true` when the string carries the officers' loot tiers (best in slot, wishlist). The addon shows them only while the player is an officer in the game too |
| `id` | string | | required | Names this export, so pasting it twice adds nothing. 1 to 64 characters of `A-Z a-z 0-9 . _ : -`. **Proposal:** `<made in base 36>.<8 random hex digits>`, like `mgq1k2zt.4fa91c07`. A new id for each press of Export, so the same *string* pasted twice is the repeat |
| `addon` | string | | required | The addon's version, `1.2.3` or `1.2.3-beta` |
| `client` | object | | required | `GetBuildInfo()` and `GetLocale()`: `version` (string, `"1.60.1"`), `build` (integer; the game returns it as text, so the addon converts it), `interface` (integer, `16001`), `locale` (string, `"enUS"`) |
| `by` | object | | required | Who recorded it: `guid` and `name` of the player pressing Export. **Proposal:** the plan said the raid leader's GUID, but the leader may not be the one with the addon |
| `realm` | string | | required | `GetRealmName()`, a label |
| `guildName` | string | | optional | The guild's name from `GetGuildInfo`, a label. Left out when the player has no guild |
| `guild` | string | | optional | The guild's handle, copied from the last import. Left out when the addon never had one |
| `night` | string | | optional | A hint only: the night's handle from the import the addon was last given. The raid's own `night` (below) says which night it was |
| `skew` | integer | | optional | `GetServerTime() * 1000 - time() * 1000` when the export was made, so a computer clock that is off can be told. Negative when the computer runs ahead |

**The guild.** An export whose `guild` is present and isn't the guild it is pasted into is **refused**, naming the guild
it is for. An export with no `guild` is read, with a warning in the preview that shows `guildName`, since the officer
has to say whose it is.

## Imports (site to addon)

`kind` is `"import"`. `meta.from` says which page the string was copied from, and so which parts it holds:

| `meta.from` | Copied from | Parts (R: required) |
|---|---|---|
| `priorities` | Loot › Priorities, the raid on show | `guild` R, `raids` R (one raid, with `loot`), `people` R (each by their main) |
| `night-loot` | A night's Loot | `guild` R, `night` R, `raids` R (the raid on show, with `loot` for those coming), `people` R (each by the character they answered with) |
| `night-assignments` | A night's Assignments | `guild` R, `night` R, `raids` R (each raid that has any, with `assignments`), `people` R (each by the character that does a slot) |
| `night` | A night's page (M2) | `guild` R, `night` R, `raids` R (every raid of the night, with all of `effort`, `picks`, `groups`, `bench`, `loot`, `assignments`), `people` R |

Other `from` values may come later. Pugs' lists (M3), points for DKP and EPGP (M5) and the guild bank (M6) will be new
optional parts, without a new `v`.

### `guild`, `night`, `people`

| Part | Field | Type | Meaning |
|---|---|---|---|
| `guild` | `handle`, `name` | strings, required | The guild |
| `night` | `handle`, `title` | strings, required | The night |
| | `startsAt` | integer, required | Planned start, epoch ms |
| `people[]` | `p` | integer, required | The person's id on the site |
| | `name` | string, required | Their name on the site (a label, not a character name) |
| | `rank` | string, optional | Their guild rank's name |
| | `chars[]` | array, required, may be empty | The characters the plan uses for them: `name` (required), `cls` and `guid` (optional, left out when unknown). In `priorities` it is their main. The first is the default |

A person who is named anywhere in the string (a pick, a group, a place in line, an assignment, a hard reserve) is in
`people`.

### `raids[]`

A night is a block of raids (an officer plans each at an effort level and picks who plays on which character).
Everything that belongs to one raid is in that raid's entry. A string of one raid (`priorities`, `night-loot`) has
one entry. Entries are in the night's order.

| Field | Type | Meaning |
|---|---|---|
| `zone` | integer, required | The raid's instance id. Required for `priorities`. A night's open raid (planned with no zone) leaves it out, and the addon takes whichever raid the group enters |
| `name` | string, required | The raid's name, a label |
| `size` | integer, optional | 10, 20 or 40 |
| `lootBy` | string, optional | How this raid's loot is given: `soft` (soft reserves: each item's `sr`), `hard` (hard reserves) or `system` (the guild's priorities, council, DKP or EPGP: each item's `order`). A value it doesn't know is ignored |
| `effort` | object, optional | The level the raid is played at: `name` (string, required) and `expects` (list of `flask`, `food`, `weapon`, `potions`, `engineering`, `misc`: the consumables expected at its pulls, empty for none). The site writes the level in force, so a raid that follows the night's level carries the night's |
| `optional` | boolean, optional | `true` when it only adds to attendance and never counts against anyone |
| `picks[]` | optional | Who plays which character in this raid, as an officer picked: `p` (a person in `people`), `name` (the character's name), `cls` and `guid` (optional) |
| `groups` | optional | The planned subgroups: up to 8 lists of person ids, in subgroup order (the first list is group 1) |
| `bench` | optional | Person ids planned to sit this raid out |
| `loot` | object, optional | `{ "items": [...] }`, below |
| `assignments[]` | optional | Boss assignments, below |

A person in `groups` or `bench` has a pick in the same raid, or else their `people` entry's first character plays.

### `loot.items[]`

| Field | Type | Meaning |
|---|---|---|
| `id` | integer, required | The item's id |
| `order` | list of lists of person ids | Places in line, best first. People sharing a place are tied |
| `sr` | list of objects | The soft reserves on the item, in no order: `p` (a person in `people`, required) and `plus` (integer from 0, optional: the weeks they have reserved it in a row, for SR+ rules) |
| `key` | `true` | One of the raid's key items |
| `specs` | list of lists of strings | The spec order: tiers of `class:tab` (like `mage:1`), best first. On an open roll the first tier anyone in the raid plays rolls first |
| `free` | `true` | An open roll |
| `hard` | integer | A hard reserve. The person's id, or `0` for the guild's |
| `note` | string | A note for the officers |

An item that has no `order`, no `sr`, no `free` and no `hard` is listed but nobody is in line for it.

### `assignments[]`

| Field | Type | Meaning |
|---|---|---|
| `encounter` | integer, optional | The boss's encounter id, left out for what the game has none for (trash, a pull the guild named) |
| `boss` | string, required | The boss's name, a label |
| `lists[]` | required | Named groups of slots: `name` (string), `slots[]` |
| `slots[]` | | `label` (string, required), `p` (list of person ids, required, empty when nobody fits tonight), `note` (string, optional) |

A slot kept for officers only is not in the string.

## Exports (addon to site)

`kind` is `"export"`. The addon makes one whenever an officer presses Export, for the night it has recorded since its
last export, or for everything it holds. Every part is optional, so an export with nothing in it (`meta` alone) is
valid, and so is one with only loot.

### `attendance[]`: one entry for each raid the addon was in

A raid here means one run of one instance by one group. Two lockouts on the same night are two entries.

| Field | Type | Meaning |
|---|---|---|
| `id` | string, required | Names the run, so the same run exported twice has the same id. **Proposal:** `<recorder's GUID>:<instance id>:<epoch seconds of the first snapshot>`, like `Player-9101-0F00AA11:5011:1796846700` |
| `zone` | integer, required | The instance id |
| `name` | string, required | The instance's name, a label. The site files raids by name, so it is always there |
| `difficulty` | integer, required | `GetInstanceInfo()`'s difficulty id |
| `size` | integer, required | 10, 20 or 40 |
| `night` | string, optional | The site's handle of the night this raid was run for, from the import. With `zone` it names one raid of a night. Left out when the addon was not given one |
| `leader` | string, optional | The raid leader's GUID at zone-in |
| `lockout` | integer, optional | The saved lockout's id from `GetSavedInstanceInfo`, once the raid is saved |
| `test` | `true`, optional | The addon recorded this run under its test setting (`/gg test on`), which makes it record a party in a 5-man dungeon like a raid, so the addon can be tried before any raid is open. `zone` is then a dungeon's instance id and `size` is 5. The site keeps the entry apart from real raids (it should not count it as attendance) and may drop it. Left out for a real raid. Added after the first draft of version 1, as any optional field may be |
| `standby` | list of objects, optional | People the leader marked "on standby" for this raid: `guid` and `name` (required), `cls` (optional). They count as there, and are not in the snapshots |
| `snapshots[]` | required, at least one | Any order; a reader sorts them by `at`. A snapshot is identified by its raid `id` and its `at`; the same pair twice is the same snapshot, so a raid may be sent in pieces that share its `id` |

A snapshot:

| Field | Type | Meaning |
|---|---|---|
| `at` | integer, required | When it was taken. Writers: whole seconds, oldest first |
| `why` | string, required | `zonein`, `pull`, `kill`, `wipe`, `interval` (every five minutes) or `leave` (the player left or the group disbanded). A reader reads another value as `interval` |
| `encounter` | integer | The boss's encounter id. Required for `pull`, `kill` and `wipe` |
| `members[]` | required | Everyone on the raid roster, below |

A member of the roster, from `GetRaidRosterInfo` and `UnitGUID("raidN")`:

| Field | Type | Meaning |
|---|---|---|
| `guid` | string, required | The player's GUID |
| `name` | string, required | The roster's name for them |
| `cls` | string, optional | Their class |
| `grp` | integer 1 to 8, optional | Their subgroup |
| `online` | boolean, required | `false` for someone who is in the group but disconnected |
| `zone` | string, optional | The zone the roster shows, as the client's language writes it (a label). Left out when offline or unknown |

A **disconnect** is a member who is `online: false` in some snapshots and `true` in later ones. A player who left the
group is simply no longer in the roster. The bench is `standby`: the people the plan benched who were never in the
group.

**A raid with no `leave` snapshot is still open.** The addon may be exported mid-raid, or the game may have crashed.
The site treats the raid as running until a `leave` snapshot arrives for it (in any piece of it, from any recorder), and
closes it at the end of its raid day if none does.

### `loot[]`: every item the addon saw handed out

| Field | Type | Meaning |
|---|---|---|
| `dedupe` | string, required | The award's key, an opaque text of 1 to 120 characters with no control characters (below, "Loot keys"). The site stores it and compares it, and never parses it or makes one |
| `at` | integer, required | When the award was recorded, epoch ms. Writers: a whole second |
| `item` | integer, required | The item's id |
| `link` | string, required | The item link's payload as the game wrote it, from `item:` up to but not including the closing `|h`, without color codes. Its id must be `item` |
| `name` | string, required | The item's name from the link |
| `quality` | integer 0 to 7, optional | The game's quality: 2 uncommon, 3 rare, 4 epic, 5 legendary |
| `winner` | object, required | Who ended up with it: `name` (required) and `guid` (optional). For a disenchant, the disenchanter |
| `how` | string, required | `reserve`, `roll`, `council`, `master`, `trade`, `disenchant`, `bank` or `other`. A reader reads another value as `other` |
| `zone` | integer, optional | The instance id |
| `encounter` | integer, optional | The boss's encounter id, when known |
| `boss` | string, optional | The boss's name as the game showed it, a label |
| `count` | integer from 1, optional | How many of the item went to the winner in this award. Read as 1 when absent |
| `offspec` | `true`, optional | The winner took it for an off spec |
| `drop` | string, optional | `<encounter id>:<loot list key>` from `C_LootHistory`, naming the drop the award came from. **Proposal**, pending the launch-day probe (docs/RESEARCH.md) |
| `note` | string, optional | |

**The winner's GUID.** The addon takes it from `C_LootHistory`'s `playerGUID` whenever the history has the drop. Where
only a name is known (`ENCOUNTER_LOOT_RECEIVED` gives a name), it fills in the GUID from the raid roster only when the
name matches exactly one member's full name ("First Surname") exactly. Otherwise it leaves `guid` out. A name is never
guessed at.

`how` may gain values later (`hard` for a hard reserve and `bid` for an auction, both M5) without a new `v`.

### `pugs[]`: players seen in the group who aren't in the guild

`guid` (required), `name` (required), `cls` (optional), `at` (optional: when first seen in this export). The site
decides which list, if any, a pug is on.

Later parts, such as `bank` (M6), are new optional parts.

### Exports are facts that are only added to

An export says what the addon saw, and the site adds it. It never edits or removes what an earlier export said.
Corrections happen on the site: an officer changes an award or an attendance there. Two names are reserved for a later
addition, so nothing else uses them: a top-level `undo[]` and a `replaces` field on a loot award. A reader ignores them
today, as it ignores any field it doesn't know.

## Loot keys

**The key is opaque.** The site stores `dedupe` as the text it is and compares it for equality. It never parses one,
never recomputes one, and puts no meaning in its parts. So the addon may change how it makes keys without a new `v`.
**One award can have several keys.** The site keeps the ones it has seen for an award as aliases.

**What the site does with an award it is given**, in order:

1. If it knows the key (as an award's key or an alias): skip it.
2. Otherwise look for an award from the addon in the guild that is the same award recorded by another player's addon:
   - the same item id;
   - the same winner: the GUID when both have one, else the exact name;
   - the same encounter id, or neither has one;
   - `at` within **10 seconds** for an award with an encounter, and within **120 seconds** for a `trade`, a
     `disenchant` or a `bank` award (and for any award with no encounter);
   - a different recorder: its `meta.by.guid` is not one that already gave that award.

   Of several like awards, the k-th like award in the string matches the k-th candidate not yet matched (in time
   order), so two tokens to one player match two tokens, never one twice.
3. A match keeps the new key as an alias of the matched award and adds nothing. No match: the award is added.
4. The preview says how many awards were added, how many matched an award already held, and how many were skipped as
   known.

The reference is `importLoot` in `test/contract-lib.mjs`.

### The addon's own recipe for its keys

**Proposal.** The addon needs some way to make a key. This is the recipe it uses, `L1`. The site does not depend on
it (above).

The key is text, with these fields in this order, joined by `|`, with no hashing:

```
L1 | <item> | <winner> | <seconds> | <encounter> | <n>
```

| Part | Value |
|---|---|
| `L1` | The recipe's name and version. A changed recipe would be `L2` |
| `<item>` | The item's id, in decimal |
| `<winner>` | The winner's GUID. Without one: `~` and the winner's name exactly as given |
| `<seconds>` | `at` divided by 1000, dropping any fraction, in decimal |
| `<encounter>` | The encounter id, or `0` when none |
| `<n>` | 1, 2, 3, ... The place of this award among the awards the addon recorded for this guild that have every other part the same, in the order recorded |

So the same boss giving one player two of the same token in the same second makes `...|1` and `...|2`, and a trade of
that item later is a different award, since its time is different.

`n` counts over everything the addon has recorded, not only the awards in one string, so an award that is exported
twice (in two exports) has the same key both times. The key is at most about 80 characters. A GUID and a name never
contain `|`. The reference is `dedupeKey` in `test/contract-lib.mjs`, and every fixture is checked against it.

Two players' addons that record one raid make keys whose seconds may differ by one, so the keys differ. That is what
the matching above is for.

## Two recorders of one raid

Two or more officers may export the same raid. The site files the entries as one **run**, and takes the union.

- **A raid's `id` is a key for one recorder's entry, not the raid's identity.** Snapshots are stored by recorder
  (`meta.by.guid`), raid `id` and `at`: the same snapshot again changes nothing, and a new one is added. So an export
  sent twice, or a raid sent in pieces that share an `id`, joins up.
- **Entries from different recorders are one run** when all of these hold: the same `zone` and `difficulty`; the
  `lockout` ids are the same, or either is missing; their spans (first to last snapshot) overlap or are no more than 10
  minutes apart; at least one GUID is in both; and no encounter that both killed was killed more than 90 seconds apart
  (a shared `kill` snapshot of one encounter within 90 seconds is the strongest sign they are one). Entries are joined
  through others, so three recorders make one run. A recorder's own entries are never joined to each other: two groups
  at once share no one, and two lockouts back to back are two runs.
- **Attendance for a run is the union:** everyone in any recorder's snapshots, and everyone on any recorder's
  `standby`. The run is open until some entry has a `leave` snapshot.

The reference is `runsOf`, `sameRun` and `upsertAttendance` in `test/contract-lib.mjs`.

## Size

| Limit | Value | Who keeps it |
|---|---|---|
| JSON unpacked | at most **1,048,576 bytes** (1 MiB) | Readers refuse more (`too-big`). This is the site's limit today |
| Text of a string | at most **524,288 characters** | Readers refuse more before unpacking (`too-long`) |
| JSON unpacked, written | at most **786,432 bytes** (768 KiB) | **Proposal.** Writers, so a reader has room |
| Text of a string, written | at most **65,536 characters** | **Proposal.** Writers. The launch-day probe's 64 KB paste box (docs/RESEARCH.md) says whether the game's edit box takes this. If it takes less, this limit becomes that |

An import is a few KB. An export is bounded by snapshots: a 40-player roster is about 4.5 KB of JSON per snapshot, so
768 KiB holds about 170, while a long night of three raids is about 130 (a snapshot every five minutes for four hours,
and one for each pull). The text is much smaller than the JSON, since the same GUIDs and names repeat (about 7 KB of
text for 120 snapshots in the tests).

**How a long night is kept under the limit.** When the addon's string would pass a written limit, it does these in
order, stopping at the first that makes every string fit:

1. Leave out each `interval` snapshot whose roster, online states, zones and subgroups match the snapshot before it.
2. Keep only every fourth of the `interval` snapshots that remain.
3. Make several strings: one for each raid, then one for `loot` and `pugs`. Each is a complete export on its own, with
   its own `meta.id` and the same other `meta`, and they can be pasted in any order.
4. Keep only every sixteenth of the `interval` snapshots instead of every fourth.
5. Cut a string that is still too big in halves by snapshots (then by awards), until each fits. The pieces of one raid
   keep its `id`, so the site joins them (above).

The other kinds of snapshot (`zonein`, `pull`, `kill`, `wipe`, `leave`) and a raid's `standby` are never left out. Every
string is under both written limits. The reference is `fit` in `test/contract-lib.mjs`.

## What a reader does

| Case | Addon reading an import | Site reading an export |
|---|---|---|
| Not ours, bad text, cut short or mistyped, too long, bad JSON, `malformed` | Refuses and says the string is damaged; asks the player to copy it again | The same |
| A field it doesn't know | Ignores it | Ignores it |
| An enum value it doesn't know | Reads its default (above, "The JSON"); never refuses | The same |
| A time that is not a whole second, or snapshots out of order | n/a | Reads the time; sorts the snapshots |
| A `v` it knows or an older one | Reads it | Reads it (the site reads every version it ever shipped) |
| A `v` newer than it knows | Refuses: **"Update the addon"** | Refuses: **"The site is behind"** |
| The wrong way round | "That is an export; paste it on the site" | "That is an import; paste it in the addon" |
| A required field missing or the wrong type | Refuses the whole string and names the field. Nothing in it is used | The same |
| An optional field the wrong type | Ignores that field | The same |
| A person id, in a group or a pick, that isn't in `people` | Ignores that entry | n/a |
| The same `meta.id` again | n/a | Adds nothing; says it was imported already |
| A `dedupe` already stored, or an award matching one from another recorder | n/a | Adds nothing for that award; the rest of the string is still read (above, "Loot keys") |
| An export whose `meta.guild` differs from the guild it is pasted into | n/a | Refuses, naming the guild it is for |
| An export with no `meta.guild` | n/a | Reads it, with a warning in the preview that shows `meta.guildName` |

A reader checks a string field by field before using any of it, and never runs anything in it. A string is data.
Both sides show the player the preview of what they are about to import before it's saved.

**Readers accept at least what writers may write.** Every value a writer is allowed to write above (an enum value, a
time, an order, a flag, an optional field left out or `null`) is one a reader reads. The limits are the same shape: a
reader accepts more than a writer makes (524,288 characters against 65,536; 1 MiB against 768 KiB).

**Site text is drawn safely.** The addon escapes `|` as `||` in any text from the site (names, notes, labels, titles)
before it puts it in a window, a tooltip or a chat line, so a note cannot draw a texture, a color or a link.

**One `v` serves both ways.** A string's direction is its `kind`. Imports and exports share one `v`, and a break to
either is a new `v` for both.

## Versions

- **`v` changes only for a break.** A break is a change after which a reader of the old version would read the string
  wrong: a field removed or renamed, a field's type or meaning changed, a required field added, or a value of an enum
  taken out.
- **Not breaks:** a new optional field, a new part, a new `from`, a new value for `how` or `why`. They never change `v`.
  Readers ignore what they don't know, or read it as the default, so an older reader just doesn't see them.
- **A field's type never changes**, not even in a new `v` if the field keeps its name: a new type is a new field.
  `schema-v1.json` lists every field of the fixtures and its type, and `npm test` fails when a fixture holds a field
  with a type other than the one listed, or one that isn't listed. `node tools/contract-fixtures.mjs --schema` adds new
  fields to the list and refuses to change one.
- **A new `v` is a new major version of the addon** (docs/PLAN.md, "How it's built and tested"). The site then writes
  the old `v` for imports until the addon that reads the new one is out, and reads every `v` it ever shipped.
- **The addon reads imports of its own `v` and older.** It refuses a newer one with "Update the addon". **The site reads
  exports of every `v` it ever shipped.** It refuses a newer one with "The site is behind".

## Fixtures

All of the names, GUIDs, item ids, instance ids and encounter ids in `fixtures/` are made up. There are no real
players. The guild is "Molten Raiders", and every GUID is `Player-9101-0F00AA11` in form.

| Fixture | What it is |
|---|---|
| `import-priorities` | Priorities for one raid, with a key item, a spec order, an open roll, a hard reserve for the guild, and people with and without GUIDs |
| `import-night-loot` | A night's loot for the raid on show, as a soft-reserve night: each item's `sr`, with SR+ weeks on some |
| `import-night-assignments` | Assignments for two raids, with a boss that has no encounter id and a slot nobody fills |
| `import-night` | A night of three raids: three effort levels (the third optional), a `lootBy` on two, picks (one on an alternate character), groups, a bench in the first raid, loot and assignments |
| `export-empty` | An export with nothing in it |
| `export-attendance` | One raid's snapshots, with a disconnect and a person on standby |
| `export-loot` | Six awards, including two of the same token to the same player (`...|1` and `...|2`) and a disenchant |
| `export-pugs` | Two pugs |
| `export-test-dungeon` | A 5-man dungeon recorded under the addon's test setting: one raid entry with `test: true`, a wipe and a kill |
| `export-night` | A night of three raids, with a disconnect in the first, a person on standby, a pug in the third, awards of every kind including a winner with no GUID, a trade, a count of three and an off-spec roll, and the pugs |
| `export-night-second-recorder` | The same night from another player's addon: its own raid ids, every time a second later, so its loot keys differ from `export-night`'s, and a `meta.skew` |
| `export-night-split-1` to `-4` | `export-night` cut for size: a string for each raid, then one for the loot and pugs, each with its own `meta.id` |

`node tools/contract-fixtures.mjs` writes each `.gg1.txt` from its `.json`. The strings are one line of text and a
newline, packed with Node's own zlib. A different zlib writes different bytes for the same JSON, so a reader checks
that a fixture's string unpacks to the fixture's JSON, never that it matches byte for byte.

Both sides run these: the addon's tests read `fixtures/*.gg1.txt`, and the site's tests are given the same files.
