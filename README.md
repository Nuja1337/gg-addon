# Guild Golem addon

The in-game addon for [Guild Golem](https://guildgolem.com), a guild management site for WoW Forever. It records
attendance, pugs, loot and the guild bank in game, and brings in each night's plan, loot priorities and boss
assignments from the site.

## Status

Not released yet. The addon itself (`GuildGolem/`) gets built once the in-game tests in docs/RESEARCH.md ("To test in
game before building") have been run on the live client. The probe answered several of them on Oct 22, outside
instances (docs/RESEARCH.md, "Probe results"). The ones inside a raid are still to run.

## What's here

| Path | What's in it |
|---|---|
| `GuildGolemProbe/` | A small test addon that records what Forever's client allows. Its README explains how to run it |
| `GuildGolem/` | The addon, once it's built |
| `contract/` | The strings the addon and the site trade (`README.md`, version 1) and a fixture of each, as JSON and as a `GG1:` string |
| `docs/PLAN.md` | What the addon will do and the milestones, and which parts of the contract are decided or still proposals |
| `docs/RESEARCH.md` | What Forever's client lets an addon do |
| `tools/` | `probe-diff.mjs` compares two probe saved files and prints what changed, with names and GUIDs replaced. `GuildGolemProbe/README.md` and `docs/RESEARCH.md` ("Launch-day probe") say when to use it |
| `LISTING.md` | The text for the CurseForge and Wago project pages |
| `test/` | The contract's fixtures against its spec (`contract.test.mjs`). Checks that every addon here is Lua 5.1 the game can read, with TOC files named after their folder (`npm test`, on Node 22 or newer). They run on every push and pull request (`.github/workflows/test.yml`). `test/lua/` is a harness that runs the addon's Lua in Node, with the game's functions stubbed: a Lua 5.1 shim, fengari (a Lua VM in JavaScript), a fake clock and roster, and a check that only `GuildGolem/Client.lua` calls the game. Its README says how to write a test. CI also runs the same Lua tests on real Lua 5.1 |

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
