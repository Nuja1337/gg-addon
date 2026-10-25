// The addon's `fit` (GuildGolem/Export.lua, run in fengari) against the reference `fit` in contract-lib.mjs: the same long
// nights, cut the same way. The two compress with different libraries (LibDeflate and Node's zlib), so a string's length
// differs a little between them; each case here is chosen well away from the edge between two steps, and what is compared
// is the objects the strings hold, never the bytes.
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { createLua } from "./lua/run.mjs";
import { WRITE_JSON, WRITE_TEXT, decode, fit, readString, validate } from "./contract-lib.mjs";

const lua = createLua();
lua.run(`
  WOW.declareSavedVariables("GuildGolemDB")
  NS = WOW.loadAddon("GuildGolem")
  local json = LibStub("json.lua")
  -- The addon's fit of an export given as JSON text: the strings it made, or "NONE" for a piece it could not shrink.
  function FIT(text, limit)
    local list = NS.Export.fit(json.decode(text), limit)
    local out = {}
    for i, item in ipairs(list) do out[i] = item.text or "NONE" end
    return out
  end
  return true
`);

// A roster of three with made-up names (the contract tests use forty; the addon's compressor is Lua, which fengari runs
// slowly, and a small roster keeps what each extra snapshot adds large next to the roster itself, so thinning matters), raids of many snapshots, the same shapes as the contract tests use. `churn` 1: someone is offline in every third
// snapshot; 2: a different one is offline in every snapshot, so none is a repeat.
let seed = 29;
const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
const word = (n) => Array.from({ length: n }, () => "abcdefghijklmnopqrstuvwxyz"[Math.floor(rnd() * 26)]).join("");
const hex = () => Array.from({ length: 8 }, () => "0123456789ABCDEF"[Math.floor(rnd() * 16)]).join("");
const PLAYERS = 3;
const players = Array.from({ length: PLAYERS }, (_, i) => ({ guid: `Player-9101-${hex()}`, name: `${word(5)} ${word(8)}`, cls: ["mage", "warrior", "priest", "rogue"][i % 4] }));
const off = (k, i, churn) => (churn === 2 ? i === k % PLAYERS : churn && k % 3 === 0 && i === 5);
const members = (k, churn) => players.map((p, i) => ({ ...p, grp: 1 + Math.floor(i / 5), online: !off(k, i, churn), ...(off(k, i, churn) ? {} : { zone: "Test Hold" }) }));
const raid = (zone, count, churn, why = (k) => (k % 4 === 0 ? "pull" : "interval")) => ({
  id: `${players[0].guid}:${zone}:1796846700`,
  zone,
  name: "Test Hold",
  difficulty: 9,
  size: 40,
  snapshots: Array.from({ length: count }, (_, k) => ({
    at: 1796846700000 + k * 300000,
    why: k === 0 ? "zonein" : k === count - 1 ? "leave" : why(k),
    ...(k > 0 && k < count - 1 && why(k) !== "interval" ? { encounter: 1 + (k % 5) } : {}),
    members: members(k, churn),
  })),
});
const wrap = (attendance, extra = {}) => ({
  v: 1,
  kind: "export",
  meta: { id: "mgq1k2zt.00000001", made: 1796864400000, addon: "0.1.0", client: { version: "1.60.1", build: 70532, interface: 16001, locale: "enUS" }, by: { guid: players[0].guid, name: players[0].name }, realm: "Classic Beta PvP" },
  attendance,
  ...extra,
});
const pugs = [{ guid: "Player-9101-0F00BB01", name: "Gideon Stray", cls: "mage", at: 1796846700000 }];

// json.lua writes an empty list as [] and reads no null, so an empty list compares as the same as none.
const plain = (value) => {
  if (Array.isArray(value)) return value.map(plain);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).filter(([, v]) => v !== null && v !== undefined).map(([k, v]) => [k, plain(v)]));
  return value;
};
const luaFit = (o, limit) => lua.call("FIT", JSON.stringify(o), limit ?? null);
const objectsOf = (strings) => strings.map((s) => {
  const got = readString(s, "site");
  assert.equal(got.ok, true, `${s.slice(0, 60)}: ${got.says}`);
  return plain(got.value);
});

const within = (strings, limit = WRITE_TEXT) => {
  for (const s of strings) {
    assert.ok(s.length <= limit, `${s.length} characters is over ${limit}`);
    assert.ok(Buffer.byteLength(JSON.stringify(decode(s).value)) <= WRITE_JSON);
    assert.deepEqual(validate(decode(s).value), []);
  }
};

describe("the addon's fit makes what the reference fit makes", () => {
  const cases = [
    ["a night that fits as it is", () => wrap([raid(5011, 20, 0), raid(5012, 20, 0)]), undefined],
    ["repeated interval snapshots dropped", () => wrap([raid(5011, 100, 0), raid(5012, 100, 0)]), 1150],
    ["a quarter of the intervals that changed", () => wrap([raid(5011, 120, 2)]), 1296],
    ["one string for each raid, and one for the pugs", () => wrap([raid(5011, 80, 2), raid(5012, 80, 2), raid(5013, 80, 2)], { pugs }), 1100],
  ];
  for (const [label, make, limit] of cases) {
    it(label, (t) => {
      const o = make();
      const mine = luaFit(o, limit);
      const reference = fit(o, limit);
      t.diagnostic(`${mine.length} string(s) of ${mine.map((s) => s.length).join(", ")} characters; the reference's ${reference.length} of ${reference.map((s) => s.length).join(", ")}`);
      assert.ok(!mine.includes("NONE"));
      within(mine, limit ?? WRITE_TEXT);
      assert.deepEqual(objectsOf(mine), objectsOf(reference));
    });
  }

  it("cuts a raid too big for one string in halves that share its id, with the same pieces", () => {
    // Pulls and wipes alone, none of which may be left out: 80 snapshots do not fit in 1000 characters.
    const big = raid(5011, 80, 2, (k) => (k % 2 ? "pull" : "wipe"));
    const o = wrap([big]);
    const mine = luaFit(o, 1000);
    const reference = fit(o, 1000);
    assert.ok(mine.length >= 2, `${mine.length} strings`);
    within(mine, 1000);
    const got = objectsOf(mine);
    assert.ok(got.every((p) => p.attendance.length === 1 && p.attendance[0].id === big.id));
    assert.equal(new Set(got.map((p) => p.meta.id)).size, got.length);
    // The same snapshots in the same order, once each.
    assert.deepEqual(got.flatMap((p) => p.attendance[0].snapshots), plain(big.snapshots));
    assert.deepEqual(objectsOf(mine), objectsOf(reference));
  });

  it("keeps every pull, kill and wipe however it cuts", () => {
    const o = wrap([raid(5011, 40, 2, (k) => (k % 3 === 0 ? "kill" : k % 3 === 1 ? "wipe" : "interval")), raid(5012, 40, 1)], { pugs });
    const kept = (list) => list.flatMap((p) => p.attendance ?? []).flatMap((r) => r.snapshots).filter((s) => s.why !== "interval");
    const want = o.attendance.flatMap((r) => r.snapshots).filter((s) => s.why !== "interval");
    for (const limit of [1500, 1000]) {
      const got = objectsOf(luaFit(o, limit));
      assert.deepEqual(kept(got), plain(want), `with a limit of ${limit}`);
    }
  });
});
