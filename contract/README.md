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
site's code does it today, docs/PLAN.md says so, or it follows from them. The list of proposals is in docs/PLAN.md,
"The contract with the site".

**Files here.** `fixtures/` holds one example of every import and export, each as `name.json` and `name.gg1.txt`
(below, "Fixtures"). `test/contract.test.mjs` checks them against this file (`npm test`). `test/contract-lib.mjs` is
this file as code: the packing, a reader, a validator, the dedupe recipe and the size rules. It is the reference both
sides' code is checked against, and nothing ships from it.

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
- **Booleans** are `true` and `false`. Flags that are only ever true (`key`, `free`) are left out instead of written
  `false`.
- **No `null`.** The addon's Lua has no null, so a writer leaves out a field that has no value. A reader treats `null`
  as the same as absent.
- **No empty objects.** Lua can't tell `{}` from `[]`, so a writer never writes `{}`. An empty list may be written
  `[]` or left out, and a reader treats both the same. Arrays have no gaps and no `null` in them.
- **Unknown fields are ignored** by every reader, at every depth. They are never an error, and a reader never passes
  them on as if it understood them.
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
with `Date.now()`.

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
| `site` | string | required | | The site's version, up to 32 characters, for display and for bug reports. **Proposal:** the date of the site's deploy, `2026.10.25` |
| `latest` | string | required | | The newest addon version the site knows, `1.2.3` or `1.2.3-beta`. The addon says "A newer addon is out" when its own is older (compared as numbers by dot; a suffix is ignored) |
| `from` | string | required | | Which import this is (below). A reader that doesn't know the value still reads the parts it understands |
| `officer` | boolean | optional | | `true` when the string carries the officers' loot tiers (best in slot, wishlist). The addon shows them only while the player is an officer in the game too |
| `id` | string | | required | Names this export, so pasting it twice adds nothing. 1 to 64 characters of `A-Z a-z 0-9 . _ : -`. **Proposal:** `<made in base 36>.<8 random hex digits>`, like `mgq1k2zt.4fa91c07`. A new id for each press of Export, so the same *string* pasted twice is the repeat |
| `addon` | string | | required | The addon's version, `1.2.3` or `1.2.3-beta` |
| `client` | object | | required | `GetBuildInfo()`: `version` (string, `"1.60.1"`), `build` (integer; the game returns it as text, so the addon converts it), `interface` (integer, `16001`) |
| `by` | object | | required | Who recorded it: `guid` and `name` of the player pressing Export. **Proposal:** the plan said the raid leader's GUID, but the leader may not be the one with the addon |
| `guild` | string | | optional | The guild's handle, copied from the last import. Left out when the addon never had one |
| `night` | string | | optional | The night's handle, copied from the import the raid was run from. Left out when none |

**Proposal:** an export whose `guild` isn't the one it is pasted into is refused, naming the guild it is for, since a
string tied to another guild is almost always a mistake.

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
| `key` | `true` | One of the raid's key items |
| `specs` | list of lists of strings | The spec order: tiers of `class:tab` (like `mage:1`), best first. On an open roll the first tier anyone in the raid plays rolls first |
| `free` | `true` | An open roll |
| `hard` | integer | A hard reserve. The person's id, or `0` for the guild's |
| `note` | string | A note for the officers |

An item that has no `order`, no `free` and no `hard` is listed but nobody is in line for it.

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
| `name` | string, optional | The instance's name, a label |
| `difficulty` | integer, required | `GetInstanceInfo()`'s difficulty id |
| `size` | integer, required | 10, 20 or 40 |
| `standby` | list of GUIDs, optional | People the leader marked "on standby" for this raid. They count as there, and are not in the snapshots |
| `snapshots[]` | required, at least one | Oldest first. A snapshot is identified by its raid `id` and its `at`; the same pair twice is the same snapshot |

A snapshot:

| Field | Type | Meaning |
|---|---|---|
| `at` | integer, required | When it was taken |
| `why` | string, required | `zonein`, `pull`, `kill`, `wipe`, `interval` (every five minutes) or `leave` (the player left or the group disbanded) |
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

### `loot[]`: every item the addon saw handed out

| Field | Type | Meaning |
|---|---|---|
| `dedupe` | string, required | The award's key, below. The site stores it as given and adds an award only once per key |
| `at` | integer, required | When the award was recorded, a whole second in epoch ms |
| `item` | integer, required | The item's id |
| `link` | string, required | The item link's payload as the game wrote it, from `item:` up to but not including the closing `|h`, without color codes. Its id must be `item` |
| `name` | string, required | The item's name from the link |
| `quality` | integer 0 to 7, optional | The game's quality: 2 uncommon, 3 rare, 4 epic, 5 legendary |
| `winner` | object, required | Who ended up with it: `name` (required) and `guid` (optional: the loot events give a name only, and the addon fills in the GUID from the raid roster when the name matches one). For a disenchant, the disenchanter |
| `how` | string, required | `reserve`, `roll`, `council`, `master`, `trade`, `disenchant`, `bank` or `other` |
| `zone` | integer, optional | The instance id |
| `encounter` | integer, optional | The boss's encounter id, when known |
| `note` | string, optional | |

`how` may gain values later (`hard` for a hard reserve and `bid` for an auction, both M5). A reader that gets a `how` it
doesn't know reads it as `other`.

### `pugs[]`: players seen in the group who aren't in the guild

`guid` (required), `name` (required), `cls` (optional), `at` (optional: when first seen in this export). The site
decides which list, if any, a pug is on.

Later parts, such as `bank` (M6), are new optional parts.

## The loot dedupe key

**Proposal.** The site's ledger has a place for a key and a rule that a key is stored once for a guild, but no recipe
for one yet. This is a recipe.

The key is text, with these fields in this order, joined by `|`, with no hashing:

```
L1 | <item> | <winner> | <seconds> | <encounter> | <n>
```

| Part | Value |
|---|---|
| `L1` | The recipe's name and version. A changed recipe would be `L2` |
| `<item>` | The item's id, in decimal |
| `<winner>` | The winner's GUID. Without one: `~` and the winner's name exactly as given |
| `<seconds>` | `at` divided by 1000, in decimal |
| `<encounter>` | The encounter id, or `0` when none |
| `<n>` | 1, 2, 3, ... The place of this award among the awards the addon recorded for this guild that have every other part the same, in the order recorded |

So the same boss giving one player two of the same token in the same second makes `...|1` and `...|2`, and a trade of
that item later is a different award, since its time is different.

`n` counts over everything the addon has recorded, not only the awards in one string, so an award that is exported
twice (in two exports) has the same key both times. The key is carried in each award as `dedupe`, so a reader never
recomputes it, and a recipe change never breaks an old string. The key is at most about 80 characters. A GUID and a
name never contain `|`. The reference is `dedupeKey` in `test/contract-lib.mjs`, and every fixture is checked against
it.

What this does not do: two officers each running the addon in one raid make two sets of awards whose seconds may
differ by one. Their awards are not merged by key. The site is free to flag awards for the same item and winner within
a minute as probable repeats.

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
order, stopping when it fits:

1. Leave out each `interval` snapshot whose roster, online states, zones and subgroups match the snapshot before it.
2. Keep only every second `interval` snapshot, then every third, and so on up to every sixteenth.
3. Make several strings: one for each raid, then one for `loot` and `pugs`. Each is a complete export on its own, with
   its own `meta.id` and the same other `meta`, and they can be pasted in any order.

The other kinds of snapshot (`zonein`, `pull`, `kill`, `wipe`, `leave`) and a raid's `standby` are never left out. The
reference is `fit` in `test/contract-lib.mjs`.

## What a reader does

| Case | Addon reading an import | Site reading an export |
|---|---|---|
| Not ours, bad text, cut short or mistyped, too long, bad JSON, `malformed` | Refuses and says the string is damaged; asks the player to copy it again | The same |
| A field it doesn't know | Ignores it | Ignores it |
| A `v` it knows or an older one | Reads it | Reads it (the site reads every version it ever shipped) |
| A `v` newer than it knows | Refuses: **"Update the addon"** | Refuses: **"The site is behind"** |
| The wrong way round | "That is an export; paste it on the site" | "That is an import; paste it in the addon" |
| A required field missing or the wrong type | Refuses the whole string and names the field. Nothing in it is used | The same |
| An optional field the wrong type | Ignores that field | The same |
| A person id, in a group or a pick, that isn't in `people` | Ignores that entry | n/a |
| The same `meta.id` again | n/a | Adds nothing; says it was imported already |
| A `dedupe` already stored | n/a | Adds nothing for that award; the rest of the string is still read |
| A `how`, `why` or `from` it doesn't know | Reads `from` for the parts it understands | `how` is read as `other`; a snapshot with an unknown `why` is kept as an `interval` |

A reader checks a string field by field before using any of it, and never runs anything in it. A string is data.
Both sides show the player the preview of what they are about to import before it's saved.

## Versions

- **`v` changes only for a break.** A break is a change after which a reader of the old version would read the string
  wrong: a field removed or renamed, a field's type or meaning changed, a required field added, or a value of an enum
  taken out.
- **Not breaks:** a new optional field, a new part, a new `from`, a new value for `how`. They never change `v`. Readers
  ignore what they don't know, so an older reader just doesn't see them.
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
| `import-night-loot` | A night's loot for the raid on show |
| `import-night-assignments` | Assignments for two raids, with a boss that has no encounter id and a slot nobody fills |
| `import-night` | A night of three raids: three effort levels (the third optional), picks (one on an alternate character), groups, a bench in the first raid, loot and assignments |
| `export-empty` | An export with nothing in it |
| `export-attendance` | One raid's snapshots, with a disconnect and a person on standby |
| `export-loot` | Six awards, including two of the same token to the same player (`...|1` and `...|2`) and a disenchant |
| `export-pugs` | Two pugs |
| `export-night` | A night of three raids, with a disconnect in the first, a person on standby, a pug in the third, awards of every kind including a winner with no GUID and a trade, and the pugs |

`node tools/contract-fixtures.mjs` writes each `.gg1.txt` from its `.json`. The strings are one line of text and a
newline, packed with Node's own zlib. A different zlib writes different bytes for the same JSON, so a reader checks
that a fixture's string unpacks to the fixture's JSON, never that it matches byte for byte.

Both sides run these: the addon's tests read `fixtures/*.gg1.txt`, and the site's tests are given the same files.
