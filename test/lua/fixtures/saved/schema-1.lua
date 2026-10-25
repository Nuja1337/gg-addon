-- A saved file as the addon wrote it at schema 1. Frozen: the migration tests (test/lua/specs/store_spec.lua) load it
-- to prove every file ever written still loads. Never edit it; add schema-<n>.lua when the schema changes.
GuildGolemDB = {
	["schema"] = 1,
	["errors"] = {
		{
			["at"] = 1796846800,
			["where"] = "handler GROUP_ROSTER_UPDATE (attendance)",
			["message"] = "attempt to index a nil value",
		},
	},
	["outbox"] = {
		{
			["id"] = "mgq1k2zt.4fa91c07",
			["made"] = 1796846700000,
			["kind"] = "export",
			["text"] = "GG1:eJx90MtuwjAQBdBfiWZtIjtAAt5BJXYg1NeiVRdDbBILx6aOw6OIf68GitpKVb20Z46v7gl2IAWDjXEKJOjD1ocIDBodEeQJDN021bvYZB8xLflQjTAXNIBKgxTFOB/lgwGnwwCV8g4k8FSkvLcig0FpjXaRsJ0OrbkMiDTnKTGrzlgFsuDDfsbAuKjDGkuSc84FA+tLtJqSuacHODNYHUmqukuwpcWjDr2x4KLHZ5xPJoJQhw2tPOtDMvfe7WvTbnWg7aDRNiDhzmLbmjKZ6ojJcrcERqRVi+vm3NuoXXKPRunQ3h5BAq5KlfUHQ/rEVHWkYOuqzovRmPhtV7UgX//I17/km075j3wvWiWPtQ9ub8rNpagWJARfdRoYYPyqd5hd6z2z/9zs210YTGYYgt8r6u4GN1j9cgfj4uq+nT8B7DKXYQ==",
		},
		{
			["id"] = "mgq1k9aa.0b77d3e2",
			["made"] = 1796850300000,
			["kind"] = "export",
			["text"] = "GG1:eJwDAAAAAAE=",
			["pasted"] = 1796853900000,
		},
	},
	["guild"] = {
		["handle"] = "abcd2345",
		["name"] = "Molten Raiders",
	},
	["site"] = {
		["version"] = "0.36.2",
		["latest"] = "0.1.0",
		["made"] = 1796843700000,
	},
	["priorities"] = {},
	["nights"] = {},
	["settings"] = {
		["pugWarnings"] = true,
	},
}
