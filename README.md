# Guild Golem addon

The in-game addon for [Guild Golem](https://guildgolem.com), a guild management site for WoW Forever. It records
attendance, pugs, loot and the guild bank in game, and brings in each night's plan, loot priorities and boss
assignments from the site.

**Not released yet.** The addon itself (`GuildGolem/`) gets built once the in-game tests in docs/RESEARCH.md ("To
test in game before building") have been run on the live client.

| Path | What's in it |
|---|---|
| `GuildGolemProbe/` | A small test addon that records what Forever's client allows. Its README explains how to run it |
| `GuildGolem/` | The addon, once it's built |
| `docs/PLAN.md` | What the addon will do, the text it trades with the site, and the milestones |
| `docs/RESEARCH.md` | What Forever's client lets an addon do |
| `LISTING.md` | The text for the CurseForge and Wago project pages |
| `test/` | Checks that every addon here is Lua 5.1 the game can read, with TOC files named after their folder (`npm test`) |

## Working with the site

The addon and the site trade one kind of text string. Its format is in docs/PLAN.md ("The contract with the site").
The site's side lives in the site's own repository, which is private. Both follow the format in docs/PLAN.md.

## Releasing

Push a tag like `v1.2.3`. The release workflow (`.github/workflows/release.yml`) checks the addons, packages
`GuildGolem/` as that version and uploads it to CurseForge (project 1757198) and Wago (`v63QDLGb`). It only runs on
those tags.

It needs two repository secrets, under Settings › Secrets and variables › Actions:

| Secret | Where to get it |
|---|---|
| `CF_API_TOKEN` | CurseForge: Account settings › API tokens |
| `WAGO_API_TOKEN` | Wago Addons: Account › API keys |

## Problems and ideas

Open an [issue](../../issues), or send feedback from any page of [guildgolem.com](https://guildgolem.com).

## Licence

There's no licence yet, so all rights are reserved.
