# Guild Golem addon

The in-game addon for [Guild Golem](https://guildgolem.com), a guild management site for WoW Forever. It records
attendance, pugs, loot and the guild bank in game, and brings in each night's plan, loot priorities and boss
assignments from the site.

## Status

Not released yet. Milestone M1, core and attendance, is built in `GuildGolem/` (Oct 25) and tested outside the game: the
codec for the site's strings, the saved variables, the imports, the launch adapter that is the one file to name the
game's functions, the event bus, and now the roster snapshots of a raid (zone-in, every pull and its kill or wipe, every
five minutes, leaving), the export string with the contract's size rules, and a small window with `/gg` to paste an
import and copy an export. It turns combat logging on when you enter a raid. It has not run in the game yet: the
first run is the "M1 smoke test in game" in docs/RESEARCH.md. Recording needs a raid instance, which Forever opens about
Dec 9, so on launch day it is tried in a 5-man dungeon with `/gg test on`. Which lines still follow retail's documented shape and wait for the launch-day pass on Forever's
client are marked `unverified on Forever` in `GuildGolem/Client.lua`. The probe answered several in-game questions on
Oct 22, outside instances (docs/RESEARCH.md, "Probe results"). The ones inside a raid are still to run.

## Using it

`/gg` opens the window. Paste an import from guildgolem.com into the top box: it says what it read, or why it cannot, and
**Import** keeps it. In a raid the addon records on its own. **Export** (or `/gg export`) makes the string of what was
recorded since the last export and shows it, selected, in the lower box: press Ctrl+C and paste it on the site, then press
**Pasted on the site**. `/gg status` says what the addon has and does, `/gg log off` stops it turning combat logging on
when you enter a raid (it never turns it off). `/gg test on` is for trying the addon before any raid is open: a party in a
5-man dungeon is then recorded like a raid and its export is marked as a test (off by default; `/gg test off` stops it).

## What's here

| Path | What's in it |
|---|---|
| `GuildGolemProbe/` | A small test addon that records what Forever's client allows. Its README explains how to run it |
| `.pkgmeta` | What the release packager puts in the zip: `GuildGolem/` alone, as the addon's folder. Everything else in the repository is ignored. `test/pkgmeta.test.mjs` works out the zip's file list from it |
| `GuildGolem/` | The addon: three TOCs (`_Forever`, `_Camelot` and a plain one), `Client.lua` (the only file that names the game), `Core/` (`Codec`, `Base64`, `ZlibSize`, `Store`, `Import`, `Events`), `Attendance.lua` (the snapshots), `Export.lua` (the export string), `UI.lua` (the window and `/gg`), `Main.lua`, and `Libs/` with LibStub, LibDeflate and json.lua, their licenses and checksums (`Libs/README.md`). `LICENSE.txt` and `NOTICES.txt` ship with it. This is the folder a release packages |
| `contract/` | The strings the addon and the site trade (`README.md`, version 1) and a fixture of each, as JSON and as a `GG1:` string |
| `docs/PLAN.md` | What the addon will do and the milestones, and which parts of the contract are decided or still proposals |
| `docs/RESEARCH.md` | What Forever's client lets an addon do |
| `tools/` | `interface.json` holds the client's interface number, the one place the tests read it from. `probe-diff.mjs` compares two probe saved files and prints what changed, with names and GUIDs replaced. `GuildGolemProbe/README.md` and `docs/RESEARCH.md` ("Launch-day probe") say when to use it |
| `LISTING.md` | The text for the CurseForge and Wago project pages |
| `test/` | The contract's fixtures against its spec (`contract.test.mjs`). Checks that every addon here is Lua 5.1 the game can read, with TOC files named after their folder, that the three TOCs of `GuildGolem/` agree (`toc.test.mjs`), that the libraries are the files their README names (`libs.test.mjs`), and that the addon's codec and the reference JavaScript read each other's strings (`codec.test.mjs`). A scripted raid night (forty players, three raids, four hours) is played through the addon and its export read by the reference validator (`night.test.mjs`), and the addon's size rules are compared with the reference's (`export-fit.test.mjs`) (`npm test`, on Node 22 or newer). They run on every push and pull request (`.github/workflows/test.yml`). `test/lua/` is a harness that runs the addon's Lua in Node, with the game's functions stubbed: a Lua 5.1 shim, fengari (a Lua VM in JavaScript), a fake clock and roster, specs for every module of the addon, and a check that only `GuildGolem/Client.lua` calls the game. Its README says how to write a test. CI also runs the same Lua tests on real Lua 5.1 |

## Working with the site

The addon and the site trade one kind of text string. Its format is in contract/README.md, with fixtures in
contract/fixtures/ that `npm test` checks. The site's side lives in the site's own repository, which is private. Both
follow the contract, and the site's tests read the same fixtures.

## Releasing

The release workflow (`.github/workflows/release.yml`) builds the addon's zip with the
[BigWigs packager](https://github.com/BigWigsMods/packager), following `.pkgmeta`. The zip holds the `GuildGolem`
folder and nothing else. There are two ways to start it.

**A dry run, before any release.** Open the repository's Actions tab, pick Release, press Run workflow, choose a branch
(or main) and run it. The workflow runs all the tests first, then packages with the packager's `-d` flag, which skips
every upload. Nothing goes to CurseForge, Wago or GitHub's releases, and it needs no tokens. When it finishes, open the
run and download `GuildGolem-zip` under Artifacts. GitHub wraps that in a zip of its own, so unzip it once to get
the addon's zip (named for the commit, such as `GuildGolem-258936c.zip`), then unzip that into the game's
`Interface\AddOns` folder so that the `GuildGolem` folder sits inside `AddOns`. The button appears once this
workflow is on the default branch. The artifact is kept for 30 days.

**A tag, which is a release.** Push a version tag that starts with `v` and a digit. The workflow runs the same tests
(the Lua 5.1 job as well as `npm test`) and stops if one fails. Then it packages `GuildGolem/` as that version,
uploads it to CurseForge (project 1757198) and Wago (`v63QDLGb`), and attaches the same zip to a GitHub release for the
tag, so players can download it from here too. A tag with `beta` or `alpha` in it makes the GitHub release a
pre-release. Only the last job, which creates the release, has permission to write to the repository.

The tag also sets the file type on the two sites. A tag with `beta` in it uploads a beta file, one with `alpha` an
alpha file, and any other a release. Tag the first release `v0.1.0-beta`, since the first file goes out as a beta
(LISTING.md, "First file"). A tag like `v1.0.0` uploads a release.

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
