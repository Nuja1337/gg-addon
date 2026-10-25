-- Made-up data for test/probe-diff.test.mjs. Every name and GUID here is invented.
GuildGolemProbeDB = {
	["probeVersion"] = "0.2.0",
	["schema"] = 2,
	["run"] = {
		["clientVersion"] = "1.60.1",
		["build"] = "70999",
		["buildDate"] = "Nov 4 2026",
		["interface"] = 16001,
		["startedAt"] = 1793000000,
		["startedAtText"] = "2026-11-04 18:00:00",
		["probeVersion"] = "0.2.0",
	},
	["who"] = {
		["self"] = "Quillon Brackenmoor",
		["names"] = {
			["Quillon"] = true,
			["Brackenmoor"] = true,
			["Quillon Brackenmoor"] = true,
			["Thessaly"] = true,
			["Orrin"] = true,
			["Thessaly Orrin"] = true,
			["Marwick Dunleavy"] = true,
			["Marwick"] = true,
			["Dunleavy"] = true,
		},
		["guilds"] = {
			["The Velvet Lanterns"] = true,
		},
		["realms"] = {
			["Fabled Hollow"] = true,
			["FabledHollow"] = true,
			["Hollow Annex"] = true,
		},
	},
	["counters"] = {
		["ENCOUNTER_START"] = 2,
	},
	["answers"] = {
		["client"] = {
			["build (version, build, date, interface)"] = {
				["text"] = "(\"1.60.1\", \"70999\", \"Nov 4 2026\", 16001)",
				["at"] = 1793000010,
				["where"] = "Fabled Square|none",
			},
			["functions missing"] = {
				["text"] = "none",
				["at"] = 1793000010,
				["where"] = "Fabled Square|none",
			},
		},
		["player"] = {
			["UnitName"] = {
				["text"] = "(\"Quillon\", \"Brackenmoor\")",
				["at"] = 1793000011,
				["where"] = "Fabled Square|none",
			},
			["UnitGUID"] = {
				["text"] = "Player-9101-0F00AA11",
				["at"] = 1793000011,
				["where"] = "Fabled Square|none",
			},
			["realm"] = {
				["text"] = "Fabled Hollow",
				["at"] = 1793000011,
				["where"] = "Fabled Square|none",
			},
			["guild (name, rank, rank index)"] = {
				["text"] = "(\"The Velvet Lanterns\", \"Member\", 3, \"Hollow Annex\")",
				["at"] = 1793000011,
				["where"] = "Fabled Square|none",
			},
		},
		["addon messages"] = {
			["whisper reply to \"Thessaly Orrin\""] = {
				["text"] = "(true, 0)",
				["at"] = 1793000301,
				["where"] = "Fabled Square|none",
			},
			["prefix registered"] = {
				["text"] = "true",
				["at"] = 1793000005,
				["where"] = "Fabled Square|none",
			},
			["burst asked on PARTY @ Fabled Square|none"] = {
				["text"] = "sent 50, the game accepted 10 (AddonMessageThrottle x40, Success x10), first refused at message 11, received back 10 of 50",
				["at"] = 1793000500,
				["where"] = "Fabled Square|none",
			},
			["burst from another player #1"] = {
				["text"] = "Thessaly Orrin sent 50 on PARTY, 10 arrived over 40.2 ms",
				["at"] = 1793000510,
				["where"] = "Fabled Square|none",
			},
		},
		["loot"] = {
			["encounter loot received #1"] = {
				["text"] = "{\"args\"=(7, 288001, \"|cff0070dd|Hitem:288001::::::::60:::::|h[Lantern Staff]|h|r\", 1, \"Marwick Dunleavy\", \"MAGE\"), \"clock\"=\"21:40:09\"}",
				["at"] = 1793000900,
				["where"] = "Hollow Keep|party",
			},
			["your roll won 21:40:11"] = {
				["text"] = "(\"|cff0070dd|Hitem:288001::::::::60:::::|h[Lantern Staff]|h|r\", 91)",
				["at"] = 1793000905,
				["where"] = "Hollow Keep|party",
			},
			["methods available"] = {
				["text"] = "{1=0, 2=1, 3=2, 4=3, 5=4}",
				["at"] = 1793000100,
				["where"] = "Fabled Square|none",
			},
			["method in a party group @ Hollow Keep|party"] = {
				["text"] = "{\"masterLooter\"={\"guid\"=\"Player-9102-0F00CC33\", \"name\"=\"Thessaly\", \"second\"=\"Orrin\", \"unit\"=\"party1\"}, \"method\"=\"Masterlooter\"}",
				["at"] = 1793000800,
				["where"] = "Hollow Keep|party",
			},
		},
		["loot history"] = {
			["drop 1 of encounter 7"] = {
				["text"] = "{\"lootListID\"=1, \"rollInfos\"={1={\"playerGUID\"=\"Player-9103-0F00DD44\", \"playerName\"=\"Marwick Dunleavy\", \"roll\"=91}}}",
				["at"] = 1793000910,
				["where"] = "Hollow Keep|party",
			},
		},
		["combat logging"] = {
			["LoggingCombat() read @ Fabled Square|none"] = {
				["text"] = "false",
				["at"] = 1793000030,
				["where"] = "Fabled Square|none",
			},
		},
		["time"] = {
			["server time"] = {
				["text"] = "1793000010",
				["at"] = 1793000010,
				["where"] = "Fabled Square|none",
			},
			["PC minus server, seconds"] = {
				["text"] = "0",
				["at"] = 1793000010,
				["where"] = "Fabled Square|none",
			},
		},
		["saved variables"] = {
			["times loaded"] = {
				["text"] = "3",
				["at"] = 1793000000,
				["where"] = "Fabled Square|none",
			},
		},
	},
	["log"] = {
	},
	["loads"] = 3,
}
