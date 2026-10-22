# The addon's listing on CurseForge and Wago Addons

The text for the project pages on CurseForge (project 1757198) and Wago (`v63QDLGb`). The release workflow can't set
these, so they're pasted into each site's project settings by hand. Keep this file and the pages the same.

## Name

Guild Golem

## Summary (CurseForge's short line, Wago's summary)

Tracks attendance, loot and the guild bank in game for guilds that use guildgolem.com.

## Description

**Guild Golem** is the in-game part of [guildgolem.com](https://guildgolem.com), a guild management and log analysis
site for WoW Forever. Officers plan raids on the site. The addon brings the plan into the game and sends back what
happened.

**What it does**

- **Attendance.** It records who was in the raid each night, including the bench and pugs.
- **Loot.** It shows how your guild hands out each item (loot council priorities, reserves, or EPGP and DKP standings)
  and records who got what.
- **Your night.** It shows the night's groups and boss assignments from the site.
- **Guild bank.** It takes a snapshot of the bank for the guild's ledger on the site.

**How it works**

Copy your night's text from guildgolem.com and paste it into the addon. It loads right away, without a reload. After
the raid, the addon gives you text to paste back on the site. It never sends anything by itself, and any guild on Guild
Golem can use it.

**Status**

In development. The first release comes after testing on Forever's client with our raiders.

**Support**

Nothing in the addon or on the site needs a payment. If you'd like to help with running costs, see
[guildgolem.com/support](https://guildgolem.com/support).

The support line only goes on the listing pages. Blizzard's add-on policy keeps donation requests out of the game, so
the addon never asks for money, links to the support page or shows a supporter mark.

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
| Issues | https://github.com/Nuja1337/gg-addon/issues | https://github.com/Nuja1337/gg-addon/issues |
| Source | https://github.com/Nuja1337/gg-addon | https://github.com/Nuja1337/gg-addon |
| Donation / support link | https://guildgolem.com/support (when the field takes a platform, the support platform's page) | the same |
| Third-party clients (CurseForge's "allow distribution") | on, so WowUp and the like can install it | — |
| Comments | on | — |
| Screenshots | after the first build: pasting a night's string, a loot line, the attendance list | the same, in the gallery |
| Game version | set per file by the packager from `## Interface: 16001`; the site needs a WoW Forever version to pick | the same |
| First file | Beta: CurseForge's app lists a project once it has a Release file | Beta |

## The TOC's lines for the two sites

These let each site's app match an installed copy to its project. They go in with the addon's first build (`GuildGolem/`):

```
## X-Curse-Project-ID: 1757198
## X-Wago-ID: v63QDLGb
```

## Links

- Website: https://guildgolem.com
- Issues: https://github.com/Nuja1337/gg-addon/issues
- Feedback: https://guildgolem.com/feedback
- Source: https://github.com/Nuja1337/gg-addon
- Support: https://guildgolem.com/support
