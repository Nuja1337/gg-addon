// The contract in code (contract/README.md): the string's packing and unpacking, a reader that refuses what the spec
// says to refuse, a validator for version 1's shapes, what a reader makes of an unknown value, the addon's loot key
// recipe, the site's matching of two recorders' loot and raids, and the way a long export is kept under the size limit. It is the spec's reference for the tests and for tools/contract-fixtures.mjs. The addon is Lua and
// the site is TypeScript, so neither imports this; each reimplements the same rules and runs the same fixtures.
import { deflateSync, inflateSync } from "node:zlib";

export const PREFIX = "GG1:";
export const VERSION = 1;
/** The most JSON a reader unpacks, in bytes. */
export const MAX_JSON = 1024 * 1024;
/** The longest text a reader tries to unpack, in characters. */
export const MAX_TEXT = 512 * 1024;
/** The longest text a writer makes, in characters (a proposal until the launch-day paste test). */
export const WRITE_TEXT = 64 * 1024;
/** The most JSON a writer makes, in bytes: three quarters of what a reader unpacks (a proposal). */
export const WRITE_JSON = 768 * 1024;

export const FROM = ["priorities", "night", "night-loot", "night-assignments"];
export const WHY = ["zonein", "pull", "kill", "wipe", "interval", "leave"];
export const HOW = ["reserve", "roll", "council", "master", "trade", "disenchant", "bank", "other"];
export const LOOTBY = ["soft", "hard", "system"];
export const EXPECTS = ["flask", "food", "weapon", "potions", "engineering", "misc"];

/** The string for an object: GG1:, then standard base64 with padding of the zlib-wrapped deflate of its UTF-8 JSON. */
export function encode(object) {
  return PREFIX + deflateSync(Buffer.from(JSON.stringify(object), "utf8")).toString("base64");
}

/** A string unpacked to its object, or the reason it can't be: `{ ok: false, error }`, the error a code from the spec. */
export function decode(text) {
  if (typeof text !== "string") return { ok: false, error: "not-ours" };
  const body = text.replace(/^[\t\n\r ]+|[\t\n\r ]+$/g, "");
  if (!body.startsWith(PREFIX)) return { ok: false, error: "not-ours" };
  if (body.length > MAX_TEXT) return { ok: false, error: "too-long" };
  const b64 = body.slice(PREFIX.length).replace(/[\t\n\r ]+/g, "");
  // Node's own base64 reader skips what isn't base64, so the alphabet is checked first.
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(b64) || b64.length % 4 === 1 || b64.replace(/=+$/, "").length === 0) return { ok: false, error: "bad-text" };
  let packed;
  try {
    packed = Buffer.from(b64, "base64");
  } catch {
    return { ok: false, error: "bad-text" };
  }
  let json;
  try {
    json = inflateSync(packed, { maxOutputLength: MAX_JSON });
  } catch (e) {
    return { ok: false, error: e?.code === "ERR_BUFFER_TOO_LARGE" ? "too-big" : "bad-zlib" };
  }
  let value;
  try {
    value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(json));
  } catch {
    return { ok: false, error: "bad-json" };
  }
  if (typeof value !== "object" || value === null || Array.isArray(value)) return { ok: false, error: "bad-json" };
  return { ok: true, value };
}

/** What each reader says for a refusal. */
export const SAYS = {
  "not-ours": "That isn't a Guild Golem string.",
  "bad-text": "The string has a character that isn't base64. Copy it again.",
  "too-long": "The string is too long to be one of ours.",
  "bad-zlib": "The string is cut short or mistyped. Copy it again.",
  "too-big": "The string unpacks to more than 1 MiB.",
  "bad-json": "The string doesn't hold a Guild Golem object.",
  malformed: "The string is missing v, kind or meta.",
  "wrong-way": "That string is for the other side.",
};

/**
 * A pasted string read as `reader` ("addon" reads imports, "site" reads exports): `{ ok: true, value }`, or
 * `{ ok: false, error, says }`. A newer `v` is `newer`, with the words each side shows.
 */
export function readString(text, reader) {
  const got = decode(text);
  if (!got.ok) return { ...got, says: SAYS[got.error] };
  const o = got.value;
  if (!Number.isInteger(o.v) || o.v < 1) return { ok: false, error: "malformed", says: SAYS.malformed };
  if (o.v > VERSION) return { ok: false, error: "newer", says: reader === "addon" ? "Update the addon" : "The site is behind" };
  if (o.kind !== "import" && o.kind !== "export") return { ok: false, error: "malformed", says: SAYS.malformed };
  if (typeof o.meta !== "object" || o.meta === null || Array.isArray(o.meta)) return { ok: false, error: "malformed", says: SAYS.malformed };
  if ((reader === "addon") !== (o.kind === "import")) return { ok: false, error: "wrong-way", says: SAYS["wrong-way"] };
  return { ok: true, value: o };
}

/* The dedupe recipe (README, "The loot dedupe key"). */

/** The key for one award, `n` its place among the recorded awards whose other fields are the same (1, 2, ...). */
export function dedupeKey({ item, winner, at, encounter }, n) {
  const who = winner.guid ?? `~${winner.name}`;
  return ["L1", item, who, Math.floor(at / 1000), encounter ?? 0, n].join("|");
}

/** Keys for awards in the order recorded: the counter runs over awards sharing every other field. */
export function dedupeAll(awards) {
  const seen = new Map();
  return awards.map((a) => {
    const stem = dedupeKey(a, 0).replace(/\|0$/, "");
    const n = (seen.get(stem) ?? 0) + 1;
    seen.set(stem, n);
    return dedupeKey(a, n);
  });
}


/* The validator: version 1's required fields and types. It refuses only what a reader can't use. Unknown fields are
   ignored, null reads as absent, and an unknown value of an enum reads as its documented default (see `normalize`). */

const GUID = /^Player-\d+-[0-9A-F]+$/;
const HANDLE = /^[a-z0-9]{4,16}$/;
const ID = /^[A-Za-z0-9._:-]{1,64}$/;
const SEMVER = /^\d+\.\d+\.\d+(-[a-z0-9.]+)?$/;
const KEY = /^[^\u0000-\u001f\u007f]{1,120}$/;
const DROP = /^\d+:.{1,60}$/;

class Check {
  errors = [];
  fail(path, why) {
    this.errors.push(`${path}: ${why}`);
  }
  /** The field's value, null counting as absent; reports when it's absent and `req`. */
  get(o, key, path, req) {
    const v = o[key];
    if (v === undefined || v === null) {
      if (req) this.fail(`${path}.${key}`, "is required");
      return undefined;
    }
    return v;
  }
  object(v, path) {
    if (typeof v === "object" && v !== null && !Array.isArray(v)) return true;
    this.fail(path, "is not an object");
    return false;
  }
  array(v, path, each, { min = 0 } = {}) {
    if (!Array.isArray(v)) return this.fail(path, "is not an array");
    if (v.length < min) this.fail(path, `needs at least ${min}`);
    v.forEach((x, i) => each(x, `${path}[${i}]`));
  }
  str(o, key, path, req, { re, max = 200 } = {}) {
    const v = this.get(o, key, path, req);
    if (v === undefined) return;
    if (typeof v !== "string" || (req && v === "")) this.fail(`${path}.${key}`, "is not a string");
    else if (v.length > max) this.fail(`${path}.${key}`, `is longer than ${max}`);
    else if (re && !re.test(v)) this.fail(`${path}.${key}`, "has the wrong form");
  }
  int(o, key, path, req, { min = 0, max = 1e14 } = {}) {
    const v = this.get(o, key, path, req);
    if (v === undefined) return;
    if (!Number.isInteger(v) || v < min || v > max) this.fail(`${path}.${key}`, `is not an integer from ${min} to ${max}`);
  }
  bool(o, key, path, req) {
    const v = this.get(o, key, path, req);
    if (v !== undefined && typeof v !== "boolean") this.fail(`${path}.${key}`, "is not true or false");
  }
  guid(o, key, path, req) {
    this.str(o, key, path, req, { re: GUID, max: 40 });
  }
}

function importParts(c, o, from) {
  const known = FROM.includes(from);
  const part = (key, req) => c.get(o, key, "$", req);
  const guild = part("guild", known);
  if (guild && c.object(guild, "$.guild")) {
    c.str(guild, "handle", "$.guild", true, { re: HANDLE });
    c.str(guild, "name", "$.guild", true);
  }
  const night = part("night", known && from !== "priorities");
  if (night && c.object(night, "$.night")) {
    c.str(night, "handle", "$.night", true, { re: HANDLE });
    c.str(night, "title", "$.night", true);
    c.int(night, "startsAt", "$.night", true, { min: 1 });
  }
  const people = part("people", known);
  const ids = new Set();
  if (people !== undefined)
    c.array(people, "$.people", (p, path) => {
      if (!c.object(p, path)) return;
      c.int(p, "p", path, true, { min: 1 });
      ids.add(p.p);
      c.str(p, "name", path, true);
      c.str(p, "rank", path, false);
      const chars = c.get(p, "chars", path, true);
      if (chars !== undefined)
        c.array(chars, `${path}.chars`, (ch, cp) => {
          if (!c.object(ch, cp)) return;
          c.str(ch, "name", cp, true);
          c.str(ch, "cls", cp, false, { max: 30 });
          c.guid(ch, "guid", cp, false);
        });
    });
  const raids = part("raids", known);
  if (raids !== undefined)
    c.array(
      raids,
      "$.raids",
      (r, path) => {
        if (!c.object(r, path)) return;
        c.int(r, "zone", path, from === "priorities", { min: 1 });
        c.str(r, "name", path, true);
        c.int(r, "size", path, false, { min: 1, max: 40 });
        c.str(r, "lootBy", path, false, { max: 20 });
        const effort = c.get(r, "effort", path, false);
        if (effort !== undefined && c.object(effort, `${path}.effort`)) {
          c.str(effort, "name", `${path}.effort`, true);
          const expects = c.get(effort, "expects", `${path}.effort`, true);
          if (expects !== undefined) c.array(expects, `${path}.effort.expects`, (e, ep) => (typeof e === "string" ? null : c.fail(ep, "is not a string")));
        }
        c.bool(r, "optional", path, false);
        const person = (p, pp) => (Number.isInteger(p) && ids.has(p) ? null : c.fail(pp, "names a person who isn't in people"));
        const picks = c.get(r, "picks", path, false);
        if (picks !== undefined)
          c.array(picks, `${path}.picks`, (k, kp) => {
            if (!c.object(k, kp)) return;
            c.int(k, "p", kp, true, { min: 1 });
            person(k.p, `${kp}.p`);
            c.str(k, "name", kp, true);
            c.str(k, "cls", kp, false, { max: 30 });
            c.guid(k, "guid", kp, false);
          });
        const groups = c.get(r, "groups", path, false);
        if (groups !== undefined) {
          if (Array.isArray(groups) && groups.length > 8) c.fail(`${path}.groups`, "has more than 8 subgroups");
          c.array(groups, `${path}.groups`, (g, gp) => c.array(g, gp, person));
        }
        const bench = c.get(r, "bench", path, false);
        if (bench !== undefined) c.array(bench, `${path}.bench`, person);
        const loot = c.get(r, "loot", path, from === "priorities" || from === "night-loot");
        if (loot !== undefined && c.object(loot, `${path}.loot`)) {
          const items = c.get(loot, "items", `${path}.loot`, true);
          if (items !== undefined)
            c.array(items, `${path}.loot.items`, (it, ip) => {
              if (!c.object(it, ip)) return;
              c.int(it, "id", ip, true, { min: 1 });
              const order = c.get(it, "order", ip, false);
              if (order !== undefined) c.array(order, `${ip}.order`, (place, pp) => c.array(place, pp, person, { min: 1 }));
              const specs = c.get(it, "specs", ip, false);
              if (specs !== undefined) c.array(specs, `${ip}.specs`, (tier, tp) => c.array(tier, tp, (s, sp) => (typeof s === "string" && /^[a-z]+:\d$/.test(s) ? null : c.fail(sp, "is not class:tab")), { min: 1 }));
              c.bool(it, "key", ip, false);
              c.bool(it, "free", ip, false);
              c.int(it, "hard", ip, false, { min: 0 });
              if (Number.isInteger(it.hard) && it.hard > 0) person(it.hard, `${ip}.hard`);
              const sr = c.get(it, "sr", ip, false);
              if (sr !== undefined)
                c.array(sr, `${ip}.sr`, (s, sp) => {
                  if (!c.object(s, sp)) return;
                  c.int(s, "p", sp, true, { min: 1 });
                  person(s.p, `${sp}.p`);
                  c.int(s, "plus", sp, false, { min: 0, max: 1000 });
                });
              c.str(it, "note", ip, false, { max: 500 });
            });
        }
        const assignments = c.get(r, "assignments", path, from === "night-assignments");
        if (assignments !== undefined)
          c.array(assignments, `${path}.assignments`, (a, ap) => {
            if (!c.object(a, ap)) return;
            c.int(a, "encounter", ap, false, { min: 1 });
            c.str(a, "boss", ap, true);
            const lists = c.get(a, "lists", ap, true);
            if (lists !== undefined)
              c.array(lists, `${ap}.lists`, (l, lp) => {
                if (!c.object(l, lp)) return;
                c.str(l, "name", lp, true);
                const slots = c.get(l, "slots", lp, true);
                if (slots !== undefined)
                  c.array(slots, `${lp}.slots`, (s, sp) => {
                    if (!c.object(s, sp)) return;
                    c.str(s, "label", sp, true);
                    const who = c.get(s, "p", sp, true);
                    if (who !== undefined) c.array(who, `${sp}.p`, person);
                    c.str(s, "note", sp, false, { max: 500 });
                  });
              });
          });
      },
      { min: known ? 1 : 0 },
    );
}

function exportParts(c, o) {
  const attendance = c.get(o, "attendance", "$", false);
  if (attendance !== undefined)
    c.array(attendance, "$.attendance", (r, path) => {
      if (!c.object(r, path)) return;
      c.str(r, "id", path, true, { re: ID });
      c.int(r, "zone", path, true, { min: 1 });
      c.str(r, "name", path, true);
      c.int(r, "difficulty", path, true);
      c.int(r, "size", path, true, { min: 1, max: 40 });
      c.str(r, "night", path, false, { re: HANDLE });
      c.guid(r, "leader", path, false);
      c.int(r, "lockout", path, false, { min: 1 });
      const standby = c.get(r, "standby", path, false);
      if (standby !== undefined)
        c.array(standby, `${path}.standby`, (m, mp) => {
          if (!c.object(m, mp)) return;
          c.guid(m, "guid", mp, true);
          c.str(m, "name", mp, true);
          c.str(m, "cls", mp, false, { max: 30 });
        });
      const snaps = c.get(r, "snapshots", path, true);
      if (snaps !== undefined)
        c.array(
          snaps,
          `${path}.snapshots`,
          (s, sp) => {
            if (!c.object(s, sp)) return;
            c.int(s, "at", sp, true, { min: 1 });
            c.str(s, "why", sp, true, { max: 20 });
            c.int(s, "encounter", sp, ["pull", "kill", "wipe"].includes(s.why), { min: 1 });
            const members = c.get(s, "members", sp, true);
            if (members !== undefined)
              c.array(members, `${sp}.members`, (m, mp) => {
                if (!c.object(m, mp)) return;
                c.guid(m, "guid", mp, true);
                c.str(m, "name", mp, true);
                c.str(m, "cls", mp, false, { max: 30 });
                c.int(m, "grp", mp, false, { min: 1, max: 8 });
                c.bool(m, "online", mp, true);
                c.str(m, "zone", mp, false);
              });
          },
          { min: 1 },
        );
    });
  const loot = c.get(o, "loot", "$", false);
  if (loot !== undefined)
    c.array(loot, "$.loot", (l, path) => {
      if (!c.object(l, path)) return;
      c.str(l, "dedupe", path, true, { re: KEY, max: 120 });
      c.int(l, "at", path, true, { min: 1 });
      c.int(l, "item", path, true, { min: 1 });
      c.str(l, "link", path, true, { re: /^item:\d+/, max: 300 });
      if (typeof l.link === "string" && Number.isInteger(l.item) && !l.link.startsWith(`item:${l.item}:`) && l.link !== `item:${l.item}`) c.fail(`${path}.link`, "is another item's");
      c.str(l, "name", path, true);
      c.int(l, "quality", path, false, { max: 7 });
      const winner = c.get(l, "winner", path, true);
      if (winner !== undefined && c.object(winner, `${path}.winner`)) {
        c.guid(winner, "guid", `${path}.winner`, false);
        c.str(winner, "name", `${path}.winner`, true);
      }
      c.str(l, "how", path, true, { max: 20 });
      c.int(l, "zone", path, false, { min: 1 });
      c.int(l, "encounter", path, false, { min: 1 });
      c.str(l, "boss", path, false);
      c.int(l, "count", path, false, { min: 1, max: 1000 });
      c.bool(l, "offspec", path, false);
      c.str(l, "drop", path, false, { re: DROP, max: 80 });
      c.str(l, "note", path, false, { max: 500 });
    });
  const pugs = c.get(o, "pugs", "$", false);
  if (pugs !== undefined)
    c.array(pugs, "$.pugs", (p, path) => {
      if (!c.object(p, path)) return;
      c.guid(p, "guid", path, true);
      c.str(p, "name", path, true);
      c.str(p, "cls", path, false, { max: 30 });
      c.int(p, "at", path, false, { min: 1 });
    });
}

/** The problems with a decoded object under version 1's shapes, as a list of strings (empty when it's fine). */
export function validate(o) {
  const c = new Check();
  if (!c.object(o, "$")) return c.errors;
  if (o.v !== VERSION) c.fail("$.v", `is not ${VERSION}`);
  const kind = c.get(o, "kind", "$", true);
  if (kind !== undefined && kind !== "import" && kind !== "export") c.fail("$.kind", "is not import or export");
  const meta = c.get(o, "meta", "$", true);
  if (meta === undefined || !c.object(meta, "$.meta")) return c.errors;
  c.int(meta, "made", "$.meta", true, { min: 1 });
  if (kind === "import") {
    c.str(meta, "site", "$.meta", true, { max: 32, re: SEMVER });
    c.str(meta, "latest", "$.meta", true, { max: 32, re: SEMVER });
    c.str(meta, "from", "$.meta", true, { max: 32 });
    c.bool(meta, "officer", "$.meta", false);
    importParts(c, o, meta.from);
  } else if (kind === "export") {
    c.str(meta, "id", "$.meta", true, { re: ID });
    c.str(meta, "addon", "$.meta", true, { max: 32, re: SEMVER });
    const client = c.get(meta, "client", "$.meta", true);
    if (client !== undefined && c.object(client, "$.meta.client")) {
      c.str(client, "version", "$.meta.client", true, { max: 32 });
      c.int(client, "build", "$.meta.client", true, { min: 1 });
      c.int(client, "interface", "$.meta.client", true, { min: 1 });
      c.str(client, "locale", "$.meta.client", true, { max: 10 });
    }
    const by = c.get(meta, "by", "$.meta", true);
    if (by !== undefined && c.object(by, "$.meta.by")) {
      c.guid(by, "guid", "$.meta.by", true);
      c.str(by, "name", "$.meta.by", true);
    }
    c.str(meta, "realm", "$.meta", true);
    c.str(meta, "guildName", "$.meta", false);
    c.int(meta, "skew", "$.meta", false, { min: -1e14 });
    c.str(meta, "guild", "$.meta", false, { re: HANDLE });
    c.str(meta, "night", "$.meta", false, { re: HANDLE });
    exportParts(c, o);
  }
  return c.errors;
}

/**
 * What a reader makes of a valid object (README, "What a reader does"): null is absent, an unknown `how` is `other`,
 * an unknown `why` is `interval`, an `expects` value it doesn't know is dropped, a `key` or `free` of false is absent,
 * an unknown `lootBy` is absent, a missing `count` is 1, and each raid's snapshots are sorted by time. It returns a
 * copy.
 */
export function normalize(object) {
  const strip = (v) => {
    if (Array.isArray(v)) return v.map(strip);
    if (typeof v === "object" && v !== null) return Object.fromEntries(Object.entries(v).filter(([, x]) => x !== null && x !== undefined).map(([k, x]) => [k, strip(x)]));
    return v;
  };
  const o = strip(object);
  for (const r of o.raids ?? []) {
    if (r.effort) r.effort.expects = r.effort.expects.filter((e) => EXPECTS.includes(e));
    if (r.lootBy !== undefined && !LOOTBY.includes(r.lootBy)) delete r.lootBy;
    for (const i of r.loot?.items ?? []) for (const flag of ["key", "free"]) if (i[flag] === false) delete i[flag];
  }
  for (const r of o.attendance ?? []) {
    for (const s of r.snapshots) if (!WHY.includes(s.why)) s.why = "interval";
    r.snapshots.sort((a, b) => a.at - b.at);
  }
  for (const l of o.loot ?? []) {
    if (!HOW.includes(l.how)) l.how = "other";
    l.count ??= 1;
  }
  return o;
}

/* The shapes by field, for the frozen schema (README, "Versions"): path to type, arrays as `[]`. */

/** Every field path in the objects and the type each holds: string, integer, number, boolean, object or array. */
export function typesOf(objects) {
  const out = new Map();
  const add = (path, type) => {
    const had = out.get(path);
    if (had && had !== type) out.set(path, `${had}|${type}`);
    else out.set(path, type);
  };
  const walk = (v, path) => {
    if (Array.isArray(v)) {
      add(path, "array");
      for (const x of v) walk(x, `${path}[]`);
    } else if (typeof v === "object" && v !== null) {
      add(path, "object");
      for (const [k, x] of Object.entries(v)) walk(x, `${path}.${k}`);
    } else add(path, typeof v === "number" ? (Number.isInteger(v) ? "integer" : "number") : typeof v);
  };
  for (const o of objects) walk(o, "$");
  return Object.fromEntries([...out].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
}

/* Awards from more than one recorder (README, "Two recorders"). */

/** How far apart in time two recorders' copies of an award may be: 10 s with a boss, 120 s for the rest. */
export function matchWindow(award) {
  return award.encounter && !["trade", "disenchant", "bank"].includes(award.how) ? 10_000 : 120_000;
}

const sameWinner = (a, b) => (a.guid && b.guid ? a.guid === b.guid : a.name === b.name);

/**
 * The site's side of an export's loot, as the contract says: `store` is the guild's addon awards, each
 * `{ keys, recorders, award }`. A known key is skipped. An award with the same item, winner, encounter and time (within
 * `matchWindow`) as one only another recorder made is that award, and its key is kept as an alias. The rest are added.
 * Returns how many of each.
 */
export function importLoot(store, exported) {
  const by = exported.meta.by.guid;
  const known = new Map(store.flatMap((e) => e.keys.map((k) => [k, e])));
  const used = new Set();
  const result = { added: 0, matched: 0, skipped: 0 };
  for (const award of exported.loot ?? []) {
    if (known.has(award.dedupe)) {
      result.skipped++;
      continue;
    }
    const near = matchWindow(award);
    const candidate = store
      .filter((e) => !used.has(e) && !e.recorders.includes(by) && e.award.item === award.item && sameWinner(e.award.winner, award.winner) && (e.award.encounter ?? 0) === (award.encounter ?? 0) && Math.abs(e.award.at - award.at) <= near)
      .sort((a, b) => a.award.at - b.award.at)[0];
    if (candidate) {
      candidate.keys.push(award.dedupe);
      candidate.recorders.push(by);
      known.set(award.dedupe, candidate);
      used.add(candidate);
      result.matched++;
    } else {
      const entry = { keys: [award.dedupe], recorders: [by], award };
      store.push(entry);
      known.set(award.dedupe, entry);
      used.add(entry);
      result.added++;
    }
  }
  return result;
}

/* Raids from more than one recorder. */

/** Two entries more than this far apart in time (ms) aren't adjacent. */
export const ADJACENT = 10 * 60_000;
/** Kill snapshots of one encounter this close (ms) are one kill. */
export const SAME_KILL = 90_000;

const spanOf = (r) => [r.snapshots.reduce((m, s) => Math.min(m, s.at), Infinity), r.snapshots.reduce((m, s) => Math.max(m, s.at), 0)];
const guidsOf = (r) => new Set(r.snapshots.flatMap((s) => s.members.map((m) => m.guid)));
const killsOf = (r) => r.snapshots.filter((s) => s.why === "kill").map((s) => [s.encounter, s.at]);

/** Whether two recorders' entries are one run of an instance (README, "Two recorders"). */
export function sameRun(a, b) {
  if (a.zone !== b.zone || a.difficulty !== b.difficulty) return false;
  if (a.lockout && b.lockout && a.lockout !== b.lockout) return false;
  const [a0, a1] = spanOf(a);
  const [b0, b1] = spanOf(b);
  if (a0 > b1 + ADJACENT || b0 > a1 + ADJACENT) return false;
  const mine = guidsOf(a);
  if (![...guidsOf(b)].some((g) => mine.has(g))) return false;
  // An encounter both killed was killed once: the kills must be within SAME_KILL of each other.
  const theirs = killsOf(b);
  for (const [enc, at] of killsOf(a)) {
    const same = theirs.filter(([e]) => e === enc);
    if (same.length && !same.some(([, t]) => Math.abs(t - at) <= SAME_KILL)) return false;
  }
  return true;
}

/** Entries `{ by, raid }` grouped into runs: entries by different recorders that are `sameRun`, joined through others. */
export function runsOf(entries) {
  const root = entries.map((_, i) => i);
  const find = (i) => (root[i] === i ? i : (root[i] = find(root[i])));
  entries.forEach((a, i) =>
    entries.forEach((b, j) => {
      if (j > i && a.by !== b.by && sameRun(a.raid, b.raid)) root[find(j)] = find(i);
    }),
  );
  const groups = new Map();
  entries.forEach((e, i) => groups.set(find(i), [...(groups.get(find(i)) ?? []), e]));
  return [...groups.values()];
}

/** Snapshots stored by recorder and raid id, each at its time: the same snapshot again changes nothing, a new one adds. */
export function upsertAttendance(store, exported) {
  for (const raid of exported.attendance ?? []) {
    const key = `${exported.meta.by.guid}|${raid.id}`;
    const have = store.get(key) ?? { by: exported.meta.by.guid, raid: { ...raid, snapshots: [] }, snaps: new Map() };
    for (const s of raid.snapshots) have.snaps.set(s.at, s);
    have.raid = { ...raid, snapshots: [...have.snaps.values()].sort((a, b) => a.at - b.at) };
    store.set(key, have);
  }
  return store;
}

/** Everyone a run has: in any recorder's snapshot, or on standby. */
export function presentIn(run) {
  const out = new Set();
  for (const { raid } of run) {
    for (const g of guidsOf(raid)) out.add(g);
    for (const m of raid.standby ?? []) out.add(m.guid);
  }
  return out;
}

/* Keeping a long export under the size limit (README, "Size"). */

const sameState = (a, b) => a.members.length === b.members.length && a.members.every((m, i) => m.guid === b.members[i].guid && m.online === b.members[i].online && m.zone === b.members[i].zone && m.grp === b.members[i].grp);

/**
 * The export as one or more strings, each at most `limit` characters and `WRITE_JSON` bytes unpacked. In order, until
 * every string fits: leave out each `interval` snapshot that matches the one before it; keep every fourth of the
 * remaining `interval` snapshots; make one string for each raid and one for the loot and pugs; keep every sixteenth
 * `interval` snapshot instead; then cut a string that is still too big in halves, by snapshots (and then by awards),
 * until each fits. Halves of one raid share its `id`, so they join when read. The other kinds of snapshot are never
 * left out.
 */
export function fit(object, limit = WRITE_TEXT, makeId = (n) => `${object.meta.id}.${n}`) {
  const sized = (o) => {
    const text = encode(o);
    return { text, ok: text.length <= limit && Buffer.byteLength(JSON.stringify(o)) <= WRITE_JSON };
  };
  const whole = sized(object);
  if (whole.ok) return [whole.text];
  const thin = (base, keep) =>
    base.map((r) => {
      const snapshots = [];
      let interval = 0;
      for (const s of r.snapshots) {
        if (s.why !== "interval") snapshots.push(s);
        else if (keep(s, snapshots.at(-1), interval++)) snapshots.push(s);
      }
      return { ...r, snapshots };
    });
  const { attendance: _a, loot, pugs, ...rest } = object;
  const withRaids = (attendance) => ({ ...rest, ...(attendance.length ? { attendance } : {}), ...(loot ? { loot } : {}), ...(pugs ? { pugs } : {}) });
  const pieces = (attendance) => [...attendance.map((r) => ({ ...rest, attendance: [r] })), ...(loot || pugs ? [{ ...rest, ...(loot ? { loot } : {}), ...(pugs ? { pugs } : {}) }] : [])];
  const numbered = (list) => list.map((o, i) => ({ ...o, meta: { ...o.meta, id: makeId(i + 1) } }));
  const deduped = thin(object.attendance ?? [], (s, before) => !before || !sameState(s, before));
  if (sized(withRaids(deduped)).ok) return [encode(withRaids(deduped))];
  const quarter = thin(deduped, (s, before, i) => i % 4 === 0);
  if (sized(withRaids(quarter)).ok) return [encode(withRaids(quarter))];
  for (const attendance of [quarter, thin(deduped, (s, before, i) => i % 16 === 0)]) {
    const list = numbered(pieces(attendance));
    if (list.every((o) => sized(o).ok)) return list.map(encode);
  }
  const halves = (o) => {
    if (sized(o).ok) return [o];
    const r = o.attendance?.[0];
    if (r && r.snapshots.length > 1) {
      const at = Math.ceil(r.snapshots.length / 2);
      return [...halves({ ...o, attendance: [{ ...r, snapshots: r.snapshots.slice(0, at) }] }), ...halves({ ...o, attendance: [{ ...r, snapshots: r.snapshots.slice(at) }] })];
    }
    if (o.loot && o.loot.length > 1) {
      const at = Math.ceil(o.loot.length / 2);
      return [...halves({ ...o, loot: o.loot.slice(0, at) }), ...halves({ ...o, loot: o.loot.slice(at), pugs: undefined })];
    }
    return [o];
  };
  return numbered(pieces(thin(deduped, (s, before, i) => i % 16 === 0)).flatMap(halves)).map(encode);
}

/** Whether a run (entries from `runsOf`) is still open: none of its entries has a `leave` snapshot. */
export const runIsOpen = (run) => !run.some(({ raid }) => raid.snapshots.some((s) => s.why === "leave"));
