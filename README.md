# Guild Golem addon

The in-game addon for [Guild Golem](https://guildgolem.com), the WoW Forever guild companion: attendance, pugs, loot
and the guild bank recorded in game, and the night's plan, priorities and assignments brought in from the site.

**Not released yet.** The addon itself (`GuildGolem/`) is built once the in-game tests (docs/RESEARCH.md, "To test
in game before building") are answered on the live client.

| Path | What it holds |
|---|---|
| `GuildGolemProbe/` | A small test addon that records what Forever's client allows (its README says how to run it) |
| `GuildGolem/` | The addon, once it's built |
| `docs/PLAN.md` | What the addon consists of, its import and export strings, and its milestones |
| `docs/RESEARCH.md` | What Forever's client lets an addon do |
| `LISTING.md` | The CurseForge and Wago project pages' text |
| `test/` | Every addon here must be Lua 5.1 the game reads, with TOC files named after their folder (`npm test`) |

## The site's side

The addon and the site talk in one kind of string (docs/PLAN.md, "The contract with the site"). The site's reader and
writer of it live in the site's own repository, which is private; the format in docs/PLAN.md is the contract both
follow.

## Releasing

Push a tag `v1.2.3`: `.github/workflows/release.yml` checks the addons, packages `GuildGolem/` as version `v1.2.3`
and uploads it to CurseForge (project 1757198) and Wago (`v63QDLGb`). It runs on those tags alone, never on a push or
a pull request.

It needs two repository secrets (Settings › Secrets and variables › Actions):

| Secret | Where it comes from |
|---|---|
| `CF_API_TOKEN` | CurseForge: Account settings › API tokens |
| `WAGO_API_TOKEN` | Wago Addons: Account › API keys |

## Licence

None yet: all rights reserved.
