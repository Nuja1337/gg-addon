# Guild Golem addon

The in-game addon for [Guild Golem](https://guildgolem.com), a guild management site for WoW Forever. It records
attendance, pugs, loot and the guild bank in game, and brings in each night's plan, loot priorities and boss
assignments from the site.

## Status

Not released yet. The core of the addon is built in `GuildGolem/` (Oct 25): the codec for the site's strings, the saved
variables, the imports, the launch adapter that is the one file to name the game's functions, and the event bus. All of
it is tested outside the game. The roster snapshots, the export and the window come next (docs/PLAN.md, M1). Which
lines still follow retail's documented shape and wait for the launch-day pass on Forever's client are marked
`unverified on Forever` in `GuildGolem/Client.lua`. The probe answered several in-game questions on Oct 22, outside
instances (docs/RESEARCH.md, "Probe results"). The ones inside a raid are still to run.

## What's here

| Path | What's in it |
|---|---|
| `GuildGolemProbe/` | A small test addon that records what Forever's client allows. Its README explains how to run it |
| `GuildGolem/` | The addon: three TOCs (`_Forever`, `_Camelot` and a plain one), `Client.lua` (the only file that names the game), `Core/` (`Codec`, `Base64`, `ZlibSize`, `Store`, `Import`, `Events`), `Main.lua`, and `Libs/` with LibStub, LibDeflate and json.lua, their licenses and checksums (`Libs/README.md`). `LICENSE.txt` and `NOTICES.txt` ship with it. This is the folder a release packages |
| `contract/` | The strings the addon and the site trade (`README.md`, version 1) and a fixture of each, as JSON and as a `GG1:` string |
| `docs/PLAN.md` | What the addon will do and the milestones, and which parts of the contract are decided or still proposals |
| `docs/RESEARCH.md` | What Forever's client lets an addon do |
| `tools/` | `interface.json` holds the client's interface number, the one place the tests read it from. `probe-diff.mjs` compares two probe saved files and prints what changed, with names and GUIDs replaced. `GuildGolemProbe/README.md` and `docs/RESEARCH.md` ("Launch-day probe") say when to use it |
| `LISTING.md` | The text for the CurseForge and Wago project pages |
| `test/` | The contract's fixtures against its spec (`contract.test.mjs`). Checks that every addon here is Lua 5.1 the game can read, with TOC files named after their folder, that the three TOCs of `GuildGolem/` agree (`toc.test.mjs`), that the libraries are the files their README names (`libs.test.mjs`), and that the addon's codec and the reference JavaScript read each other's strings (`codec.test.mjs`) (`npm test`, on Node 22 or newer). They run on every push and pull request (`.github/workflows/test.yml`). `test/lua/` is a harness that runs the addon's Lua in Node, with the game's functions stubbed: a Lua 5.1 shim, fengari (a Lua VM in JavaScript), a fake clock and roster, specs for every module of the addon, and a check that only `GuildGolem/Client.lua` calls the game. Its README says how to write a test. CI also runs the same Lua tests on real Lua 5.1 |

## Working with the site

The addon and the site trade one kind of text string. Its format is in contract/README.md, with fixtures in
contract/fixtures/ that `npm test` checks. The site's side lives in the site's own repository, which is private. Both
follow the contract, and the site's tests read the same fixtures.

## Releasing

Push a version tag. The release workflow (`.github/workflows/release.yml`) checks the addons, packages `GuildGolem/`
as that version and uploads it to CurseForge (project 1757198) and Wago (`v63QDLGb`). It only runs on tags that start
with `v` and a digit.

The tag also sets the file type. A tag with `beta` in it uploads a beta file, one with `alpha` an alpha file, and any
other a release. Tag the first release `v0.1.0-beta`, since the first file goes out as a beta (LISTING.md, "First
file"). A tag like `v1.0.0` uploads a release.

It needs two repository secrets, under Settings › Secrets and variables › Actions:

| Secret | Where to get it |
|---|---|
| `CF_API_TOKEN` | CurseForge: Account settings › API tokens |
| `WAGO_API_TOKEN` | Wago Addons: Account › API keys |

If either is missing, the release stops at its first step, before anything is packaged.

## Problems and ideas

Open an [issue](../../issues) here and pick "Something's wrong" or "An idea", or use Feedback on any page of
[guildgolem.com](https://guildgolem.com).

## License

All rights reserved. The addon is free to download and use, and you may read and change its code for your own use.
You may not redistribute it. The full terms are in [LICENSE.txt](LICENSE.txt). The addon's release folder carries a copy
of them too.
