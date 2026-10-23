# In-game addon: research

What WoW Forever's client lets an addon do, for the addon the owner wants (the site's docs/PLAN.md, "The in-game addon"). **This is
research only** (owner, Oct 7): no addon code until the owner says. Researched Oct 7, 2026 from Blizzard's exported UI
source, Gethe/wow-ui-source branch `forever` at 1.60.1 (70245, Oct 6), with an in-game API dump (Ketho/
BlizzardInterfaceResources `forever`, build 70205), Gargul's Forever support, and warcraft.wiki.gg. **Re-checked Oct 20**
against 1.60.1 (70450, Oct 16) and the dump at build 70338: "Corrections and additions (Oct 20)" below, and the
plan's edge cases (docs/PLAN.md). Re-check before building: the client changes weekly.

## The client

- **Forever isn't the Classic client.** Its game type is `camelot` (`WOW_PROJECT_ID == 18`), in the Mainline family,
  on the retail 12.1 engine. `GetBuildInfo()` reports interface **16001**; `LE_EXPANSION_LEVEL_CURRENT` is 0.
- **Retail's Midnight addon restrictions apply.** Addons can't read the combat log, chat can turn "secret" inside
  raids and encounters, and addon messages can be locked down during encounters.
- **TOC (corrected Oct 20):** the client looks for `<Addon>_Forever.toc` or `<Addon>_Camelot.toc` (the game type),
  then `<Addon>_Mainline.toc`, then a plain `<Addon>.toc`. Ship `_Forever`, `_Camelot` (the wiki notes Camelot may be
  renamed Forever) and a plain one, each named after the addon's folder, with `## Interface: 16001` (a
  comma-separated list works). A `_Mainline.toc` isn't needed. `## Interface-Camelot:` is a packager directive, not
  the client's.
- **Names:** one mega-realm, and characters have **surnames**. `UnitName`'s second return is a surname, not a realm,
  and the separator is a space. Key every player by **GUID** (`UnitGUID`). Treat name strings from rosters and chat as
  unverified until tested in game.

## What the owner's features can use

| Feature | What exists in Forever's client | What to watch |
|---|---|---|
| **Who was in the raid** | `GetRaidRosterInfo(i)` (name, subgroup, class, zone, online), `GetNumGroupMembers`, `GROUP_ROSTER_UPDATE`; `GetInstanceInfo()` (instance id, difficulty, size: Forever raids are 10, 20 or 40); `ENCOUNTER_START`/`ENCOUNTER_END` (encounter id and name, difficulty, group size, success), `BOSS_KILL`; lockouts via `GetSavedInstanceInfo` | Raid members' identity isn't secret. Snapshot the roster at zone-in, at every pull (`ENCOUNTER_START`) and at leaving. The combat log is off limits, so attendance is roster snapshots, not damage |
| **Pugs, white and black lists** | Guild member or not: `GetGuildInfo(unit)`, `C_GuildInfo.MemberExistsByName`, or the raid's GUIDs against the guild roster's | Flag a blacklisted GUID the moment `GROUP_ROSTER_UPDATE` brings them in |
| **Loot distribution** | Loot methods via `C_PartyInfo.GetLootMethod()` and `GetAvailableLootMethods()` (free for all, round robin, master, group, need before greed, personal; which are allowed is decided at runtime). Master loot: `GetMasterLootCandidate`, `GiveMasterLoot`, `MasterLooterFrame`. Rolls: `START_LOOT_ROLL`, `RollOnLoot`, `LOOT_ITEM_ROLL_WON`, `ENCOUNTER_LOOT_RECEIVED`. **Loot history** (`C_LootHistory`): each boss's drops with the winner and every roll by GUID | `C_LootHistory` and `ENCOUNTER_LOOT_RECEIVED` record loot without reading chat. `/roll` results arrive in system chat, which can be secret in raids, so rolls can't rely on chat. Whether master loot is on for Forever's servers is unknown, and so is whether `GiveMasterLoot` works from addon code |
| **Loot seeding** | Saved variables (`## SavedVariables`, per character, machine-wide) and an import string pasted in game; item links give item ids | The site's soft reserves (now live) and later wishlists become an import string |
| **Trades after a drop** | `TRADE_*` events, `GetTradePlayerItemInfo`/`GetTradeTargetItemInfo` (with item id), `ERR_TRADE_COMPLETE`; the trade window from the tooltip line `TradeTimeRemaining` | Attribute a traded drop to the person who ends up with it |
| **Guild bank** | The guild bank UI and API ship: `QueryGuildBankLog`, `GetGuildBankTransaction` (deposit, withdraw or move; who; item; count; when), `GetGuildBankMoneyTransaction`, `GetGuildBankMoney`, tab contents, `GUILDBANKLOG_UPDATE` | **Whether Forever turns guild banks on is a server switch**: check `C_GuildBank.IsGuildBankEnabled()` in game. Fallback: a bank character's bags, bank (character and account tabs), gold and mail are all readable (`C_Container`, `GetMoney`, mail API) |
| **Guild roster** | `GetGuildRosterInfo` (rank, public and officer notes, class, GUID), `C_GuildInfo.GuildRoster()` to refresh; `C_Club` member info | Officer notes: readable with permission; writing (`C_GuildInfo.SetNote`) is restricted and untested from an addon |
| **Addons talking to each other** | `C_ChatInfo.SendAddonMessage` (RAID, GUILD, OFFICER, WHISPER), 255-character messages, throttled; result `AddOnMessageLockdown` during restrictions | Queue messages during encounters; flush after `ENCOUNTER_END` or when `ADDON_RESTRICTION_STATE_CHANGED` clears |

## Getting data to the site

A game addon can't reach the network. Options, simplest first:
1. **Copy and paste:** the addon builds an export string after the raid (attendance, loot, bank); an officer pastes it
   on the site. Before the raid, the site gives an import string (roster, soft reserves, pug lists). Gargul and
   GuildHall work this way.
2. **A desktop uploader** that reads the addon's saved variables file and posts it. Smoother, but something to install.

The site is ready to receive imports: the loot ledger has `source` and `dedupe`, so one raid imported twice adds
nothing, and the `pugs` table has seen, whitelisted and blacklisted states.

## Effects on what's already built

- **Names and realms:** the site matches log players to roster characters by GUID, then by name before the first
  "-". If Forever's combat log writes surnames ("First Last") the name match needs a look; the GUID match is
  unaffected. The `pugs` table's realm column may stay empty (one mega-realm); a GUID column should be added when the
  addon's import is built.
- **Battle.net:** a Mainline-family client makes Blizzard's profile API for Forever plausible later (the site's docs/PLAN.md,
  "Battle.net sync").

## To test in game before building

1. The exact name format from `GetRaidRosterInfo`, `GetGuildRosterInfo` and chat senders, and the whisper target
   format for addon messages.
2. `C_GuildBank.IsGuildBankEnabled()`.
3. `C_PartyInfo.GetAvailableLootMethods()` in a raid group, and whether `GiveMasterLoot` works from addon code.
4. Addon messages between pulls in a raid zone: chat is secret there (below), addon messages aren't marked so.
5. Which folder Forever's client loads addons from, and how character folders with surnames are named.
6. Whether master-looted drops reach `C_LootHistory`; whether item links carry bonus ids for 10, 20 and 40 players.
7. How many lines a guild bank tab's log keeps (the UI shows 21), and whether `GetGuildRosterInfo` stays readable in
   a raid zone.
8. Which raid buffs and flasks stay secret outside combat (`C_Secrets.ShouldAurasBeSecret`).

## Corrections and additions (Oct 20)

From Gethe/wow-ui-source `forever` at 172a387e "1.60.1 (70450)" (`Interface/AddOns/Blizzard_APIDocumentationGenerated`)
and Ketho's dump at 70338.

- **Chat secrecy is wider than encounters:** `C_ChatInfo.InChatMessagingLockdown()` covers every `CHAT_MSG_*` event,
  SYSTEM included, during encounters and on communication-restricted maps (dungeons and raids: the whole zone). So
  `/roll` results can't be read in a raid; rolls come from `C_LootHistory`. `CHAT_MSG_ADDON` isn't marked secret.
  In lockdown, `C_Club` member and club info, the guild message of the day, calendar invite reads and the ready
  check's initiator turn secret too: read the guild roster and signups outside instances.
- **Restrictions:** `ADDON_RESTRICTION_STATE_CHANGED(type, state)`, types Combat, Encounter, ChallengeMode, PvPMatch,
  Map and Chat; it fires with state Activating first, so flush and snapshot then. Guard values with `issecretvalue`
  and `canaccessvalue`: tainted code that compares or joins a secret errors. The combat log is SecureOnly
  (`C_CombatLogSecure`); registering its event errors.
- **Saved variables** are written at logout, disconnect, quit and `/reload` (`PLAYER_LOGOUT` comes last), not on a
  crash; `SAVED_VARIABLES_TOO_LARGE` exists, so keep them small. Per-character ones land under
  `WTF/Account/<account>/<realm>/<character>/SavedVariables/`.
- **Pulls:** `ENCOUNTER_END`'s `success` is a number, and it carries `encounterUnitStatus` (creature id, name, health
  percent left): the boss's health at a wipe. The Encounter Journal doesn't load on Forever, so encounter ids come from
  `ENCOUNTER_*` and `C_LootHistory`. `GetRaidRosterInfo` also returns `combatRole`.
- **Loot:** `C_LootHistory` (GetAllEncounterInfos, GetInfoForEncounter, GetSortedDropsForEncounter,
  GetSortedInfoForDrop; `LOOT_HISTORY_UPDATE_*`) gives each drop's winner and `rollInfos` (name, **GUID**, class, need,
  greed or pass, roll), for group rolls. `ENCOUNTER_LOOT_RECEIVED` gives a **name** and class, not a GUID;
  `LOOT_ITEM_ROLL_WON` is your own wins only; `GetMasterLootCandidate` returns names. `C_PartyInfo.GetLootMethod()`
  returns the method and the master looter; Forever's master-loot threshold is epic. `CHAT_MSG_LOOT` isn't secret.
  Many sources give names only, so each snapshot keeps `UnitGUID("raidN")` beside the name.
- **Talents** are `C_Traits` (config type CamelotCombat): an inspected player's via `C_Traits.HasValidInspectData()`
  and `C_Traits.GenerateInspectImportString(unit)`.
- **Guild:** `C_GuildInfo.SetNote` is restricted and the old note setters are gone, so nothing writes officer notes.
  `C_GuildBank.IsGuildBankEnabled()` exists; bank log lines carry hours ago, not times; the money log is
  `QueryGuildBankLog(MAX_GUILDBANK_TABS + 1)`.
- **Lockouts:** `GetSavedInstanceInfo`, `GetSavedInstanceEncounterInfo`, `RequestRaidInfo`,
  `C_RaidLocks.IsEncounterComplete`. Quests: `C_QuestLog.IsQuestFlaggedCompleted`.
- **Addon messages:** prefix up to 16 characters, message up to 255 bytes, 10 a prefix refilling one a second;
  `Enum.SendAddonMessageResult` has AddOnMessageLockdown (11), AddonMessageThrottle (3) and ChannelThrottle (8).
- **Group control:** `C_PartyInfo.InviteUnit` is unrestricted; `SetRaidSubgroup` and `SwapRaidSubgroup` are
  restricted, out of combat only, for the leader or an assistant. `ReloadUI()` is unrestricted. Auras are secret in
  combat and encounters, and some spells always (`C_Secrets.ShouldAurasBeSecret`).

## Probe results (Oct 22, client 1.60.1 build 70532)

The owner ran GuildGolemProbe on Forever's client, alone and with a second player, outside instances. What it found:

| Question | Answer |
|---|---|
| Client | 1.60.1, build 70532 (Oct 20, 2026), interface 16001, `WOW_PROJECT_ID` 18, expansion level 0, enUS |
| Install folder | Forever installs as Battle.net's "classic beta" product: `World of Warcraft\_classic_beta_\Interface\AddOns`, with saved variables in `_classic_beta_\WTF\Account\<account>\SavedVariables` |
| Which TOC loads | `<Addon>_Camelot.toc`. Ship it, with the plain `.toc` as a fallback |
| A file rewritten on disk | Picked up by `/reload`, with no restart |
| Names | `UnitName` and `UnitFullName` give the first name and the surname as two values. Raid roster, guild roster and addon-message senders give "First Surname" with a space. A whisper to "First Surname" arrives |
| GUIDs | `Player-<server>-<id>`, with more than one server id on the one realm (two seen). Key players by the whole GUID |
| Realm | "Classic Beta PvP". Guild info's fourth value names a sub-realm |
| Guild roster | Readable outside instances, including class, level, zone, notes and GUID |
| Guild bank | `C_GuildBank` reports enabled. Its log is untested (no bank opened) |
| Loot methods | Five offered: free for all, round robin, master, group, need before greed |
| Loot records | `ENCOUNTER_LOOT_RECEIVED` gives the item link and winner. Loot window slots are readable. Links carry Forever's own item ids (in the 288000s) and a bonus id (1491) |
| Chat | Loot and roll system lines aren't secret outside instances |
| Addon messages | Party, raid and whisper all deliver, and the prefix registers |
| Group control | `SetRaidSubgroup` ran without error |
| Missing functions | `CanViewOfficerNote` |
| Clock | The PC and the server are within a second |

**Not tested yet:**
- inside a raid instance: chat lockdown and secret values, addon messages during and after a pull, and the encounter
  events' payloads;
- the guild bank's log, master loot handing out an item, trades, inspect, an invite by full name, and the professions'
  recipe lists.

**The browser can't reach these files in a default install.** Chrome and Edge block web pages from picking anything
under `Program Files`, where Battle.net installs WoW (Chromium's `kBlockPaths`). That rules out a site tab reading the
addon's saved file (Sync, M7) or the combat log (live logging) unless WoW is moved or a desktop app does the reading.

## Sources

- Gethe/wow-ui-source, branch `forever`, commit 15666a6e "1.60.1 (70245)", re-checked at 172a387e "1.60.1 (70450)": https://github.com/Gethe/wow-ui-source/tree/forever
- Ketho/BlizzardInterfaceResources, branch `forever` (build 70205): https://github.com/Ketho/BlizzardInterfaceResources/tree/forever
- Gargul's Forever support: https://github.com/papa-smurf/Gargul/commit/c1180b4c
- BigWigs packager (TOC handling): https://github.com/BigWigsMods/packager
- warcraft.wiki.gg: TOC_format, Patch_12.0.0/API_changes, API_GetRaidRosterInfo, API_GetGuildRosterInfo,
  API_C_ChatInfo.SendAddonMessage, COMBAT_LOG_EVENT_UNFILTERED
