# The addon's listing on CurseForge and Wago Addons

What the projects' pages say: CurseForge project 1757198, Wago `v63QDLGb`. The owner pastes these into each site's
project settings (the sites have no way for the release workflow to set them); keep this file and the pages the same.

## Name

Guild Golem

## Summary (CurseForge's short line, Wago's summary)

Your guild's companion for WoW Forever: attendance, loot and the guild bank in game, kept in step with guildgolem.com.

## Description

**Guild Golem** is the in-game half of [guildgolem.com](https://guildgolem.com), the guild management and analytics
site for WoW Forever. Officers plan the raid on the site; the addon carries it into the game and brings what happened
back.

**What it does**

- **Attendance:** notes who was in the raid each night, bench and pugs included, ready to send to your guild's page.
- **Loot:** shows each item's line the way your guild hands out loot (a loot council's priorities, reserves, or EPGP and
  DKP standings) and records who got what.
- **Your night:** the night's groups and boss assignments from the site, in game.
- **Guild bank:** a snapshot of the bank for the guild's ledger on the site.

**How it works**

Copy your night's string from guildgolem.com and paste it into the addon: it loads at once, no reload. After the raid,
the addon gives you a string to paste back on the site. Nothing is sent anywhere by itself, and the addon works with
any guild that uses Guild Golem.

**Status**

In development: the first release follows testing on Forever's client with our raiders.

**Support**

Nothing in the addon or on the site is locked behind a payment. Guild Golem is kept going by the people who chip in:
[guildgolem.com/support](https://guildgolem.com/support).

The support line stays on the listing pages alone. Blizzard's add-on policy keeps requests for donations off the game
itself (the add-on's website or distribution site only), so the addon never asks, links or shows a supporter's mark.

## Project settings

Fields a site doesn't show are skipped.

| Field | CurseForge | Wago |
|---|---|---|
| Name | Guild Golem | Guild Golem |
| Slug / address | guild-golem | guild-golem |
| Summary | the summary above | the summary above |
| Description | the description above (Markdown) | the description above (Markdown) |
| Logo | the crest, square PNG, 400 × 400 or larger | the same file |
| Class | Addons | — |
| Main category | Guild | Guild |
| More categories | Boss Encounters, Data Export, Bags & Inventory (the bank) | Raid |
| License | All Rights Reserved (the code is the project's; its Lua is readable in game, as Blizzard's policy asks) | the same |
| Website | https://guildgolem.com | https://guildgolem.com |
| Issues | https://guildgolem.com/feedback | https://guildgolem.com/feedback |
| Source | empty (the repository is private) | empty |
| Donation / support link | https://guildgolem.com/support (when the field takes a platform, the support platform's page) | the same |
| Third-party clients (CurseForge's "allow distribution") | on, so WowUp and the like can install it | — |
| Comments | on | — |
| Screenshots | after the first build: pasting a night's string, a loot line, the attendance list | the same, in the gallery |
| Game version | set per file by the packager from `## Interface: 16001`; the site needs a WoW Forever version to pick | the same |
| First file | Beta: CurseForge's app lists a project once it has a Release file | Beta |

## The TOC's lines for the two sites

So each site's app matches an installed copy to its project (added with the addon's first build, `GuildGolem/`):

```
## X-Curse-Project-ID: 1757198
## X-Wago-ID: v63QDLGb
```

## Links

- Website: https://guildgolem.com
- Issues and feedback: https://guildgolem.com/feedback
- Support: https://guildgolem.com/support
