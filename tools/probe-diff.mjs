#!/usr/bin/env node
// Compares two GuildGolemProbe saved files (WTF\Account\<account>\SavedVariables\GuildGolemProbe.lua) and prints what
// changed as Markdown, one table per section. The repository is public, so before anything is printed every
// character name, guild name, realm name and player GUID is replaced with a stable placeholder (Player1, Guild1,
// Realm1, Player-S1-1). The same name gets the same placeholder in both files and in every table of one run.
//
//   node tools/probe-diff.mjs before.lua after.lua [--all] [--full] [--name "First Surname"] [--guild "Name"] [--realm "Name"]
//
//   --all    also list the rows that did not change
//   --full   do not shorten long cells
//   --name, --guild, --realm   one more name to replace (repeat the flag for more)
//
// Where the names come from. Probe 0.2 writes every name it saw to a `who` table in the saved file, and that is the
// main source. For older files the tool also reads the places 0.1 wrote names to (the player, group, roster, message
// and loot answers). A name the probe never wrote down and 0.1 never put in a known place can only be caught with
// --name. After replacing, the tool checks the result for every name it knows and prints nothing if one is left.
//
// Two things are left out of the comparison on purpose, because they differ in every run. These are the "saved
// variables" section and the two clock readings in "time". Clock times in keys ("12:03:04") are dropped from the keys,
// and a repeated key gets a number, so the same event lines up in both runs.

import { readFileSync } from "node:fs";
import { basename } from "node:path";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

const luaparse = createRequire(import.meta.url)("luaparse");

// Reading the Lua file ---------------------------------------------------------------------------------------------

const ESCAPES = { a: 7, b: 8, f: 12, n: 10, r: 13, t: 9, v: 11, "\\": 92, '"': 34, "'": 39, "\n": 10 };

// The text of a Lua string literal, from its source. Escapes like \195\169 are bytes, so the bytes are read as UTF-8.
function decodeString(raw) {
  const long = /^\[(=*)\[\r?\n?([\s\S]*)\]\1\]$/.exec(raw);
  if (long) return long[2];
  const body = [...raw.slice(1, -1)];
  const bytes = [];
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (c !== "\\") {
      bytes.push(...Buffer.from(c, "utf8"));
      continue;
    }
    const next = body[++i];
    if (next in ESCAPES) bytes.push(ESCAPES[next]);
    else if (/\d/.test(next)) {
      let digits = next;
      while (digits.length < 3 && /\d/.test(body[i + 1] ?? "")) digits += body[++i];
      bytes.push(Number(digits) & 255);
    } else if (next === "x") {
      bytes.push(parseInt(body.slice(i + 1, i + 3).join(""), 16));
      i += 2;
    } else if (next === "z") {
      while (/\s/.test(body[i + 1] ?? "")) i++;
    } else bytes.push(...Buffer.from(next ?? "", "utf8"));
  }
  return Buffer.from(bytes).toString("utf8");
}

function evaluate(node) {
  switch (node.type) {
    case "StringLiteral":
      return decodeString(node.raw);
    case "NumericLiteral":
      return node.value;
    case "BooleanLiteral":
      return node.value;
    case "NilLiteral":
      return null;
    case "UnaryExpression":
      if (node.operator === "-") return -evaluate(node.argument);
      break;
    case "Identifier":
      return node.name;
    case "TableConstructorExpression": {
      const table = Object.create(null);
      let index = 1;
      for (const field of node.fields) {
        if (field.type === "TableValue") table[String(index++)] = evaluate(field.value);
        else if (field.type === "TableKeyString") table[field.key.name] = evaluate(field.value);
        else table[String(evaluate(field.key))] = evaluate(field.value);
      }
      return table;
    }
  }
  throw new Error(`unsupported Lua in a saved file (${node.type})`);
}

// The global assignments of a saved variables file, as plain objects.
export function parseSavedVariables(text) {
  const ast = luaparse.parse(text, { luaVersion: "5.1" });
  const globals = Object.create(null);
  for (const statement of ast.body) {
    if (statement.type !== "AssignmentStatement") continue;
    statement.variables.forEach((variable, i) => {
      if (variable.type === "Identifier" && statement.init[i]) globals[variable.name] = evaluate(statement.init[i]);
    });
  }
  return globals;
}

// What a probe file holds, with every answer as text.
export function loadProbe(text, label = "file") {
  let db;
  try {
    db = parseSavedVariables(text).GuildGolemProbeDB;
  } catch (error) {
    throw new Error(`${label} is not a Lua saved variables file: ${error.message}`);
  }
  if (!db || typeof db !== "object") throw new Error(`${label} has no GuildGolemProbeDB table`);
  const answers = Object.create(null);
  for (const [section, keys] of Object.entries(db.answers ?? {})) {
    answers[section] = Object.create(null);
    for (const [key, entry] of Object.entries(keys ?? {})) {
      answers[section][key] = { text: String(entry?.text ?? ""), at: Number(entry?.at ?? 0) };
    }
  }
  return { db, answers };
}

// The names in a file --------------------------------------------------------------------------------------------

// The strings inside a recorded value: a tuple "(\"a\", 2, \"b\")" gives a and b, a lone string gives itself.
function unquote(s) {
  return s.replace(/\\(\d{1,3}|.)/gs, (_, e) => (/^\d+$/.test(e) ? String.fromCharCode(Number(e)) : e === "n" ? "\n" : e));
}
function stringsIn(text) {
  const quoted = [...text.matchAll(/"((?:[^"\\]|\\.)*)"/gs)].map((m) => unquote(m[1]));
  if (text.startsWith("(") || text.startsWith("{")) return quoted;
  return [text];
}

const WINDOWS_PATH = /\b[A-Za-z]:[\\/][^\s"',)|]+/g;
const GUID = /\b(Player|Guild|BNetAccount|Club)-(\d+)-([0-9A-Fa-f]+)\b/g;

// Everything in one file that the placeholders have to cover.
function identity(file, extra) {
  const names = new Set();
  const guilds = new Set();
  const realms = new Set();
  let self = null;
  const guids = [];
  const addName = (s) => {
    if (typeof s !== "string") return;
    s = s.trim();
    // "First Surname-Realm" is two things, a person and a realm.
    const joined = /^(.+\S)-([^\s-]+)$/.exec(s);
    if (joined) {
      addName(joined[1]);
      realms.add(joined[2]);
      return;
    }
    if (s.length >= 2 && !/^(nil|<secret>|true|false)$/.test(s)) names.add(s);
  };
  const addPerson = (parts) => {
    const clean = parts.map((p) => (typeof p === "string" ? p.trim() : "")).filter((p) => p && !/^(nil|<secret>)$/.test(p));
    clean.forEach(addName);
    if (clean.length > 1) addName(clean.join(" "));
    return clean.length > 1 ? clean.join(" ") : clean[0] ?? null;
  };
  const addGuild = (s) => typeof s === "string" && s.trim() && !/^(nil|<secret>)$/.test(s.trim()) && guilds.add(s.trim());
  const addRealm = (s) => typeof s === "string" && s.trim() && !/^(nil|<secret>)$/.test(s.trim()) && realms.add(s.trim());

  // The probe's own list (0.2 and later).
  const who = file.db.who ?? {};
  for (const n of Object.keys(who.names ?? {})) addName(n);
  for (const n of Object.keys(who.guilds ?? {})) addGuild(n);
  for (const n of Object.keys(who.realms ?? {})) addRealm(n);
  if (typeof who.self === "string") {
    self = who.self;
    addName(who.self);
  }

  // The places 0.1 wrote names to.
  // An answer that is an error or a missing API holds no name.
  const get = (section, key) => {
    const text = file.answers[section]?.[key]?.text;
    return text && !/^(error: |missing[: ]|no API$|nil$)/i.test(text) ? text : undefined;
  };
  for (const key of ["UnitName", "UnitFullName"]) {
    const text = get("player", key);
    if (text) {
      const full = addPerson(stringsIn(text).slice(0, 2));
      self ??= full;
    }
  }
  const realm = get("player", "realm");
  if (realm) stringsIn(realm).forEach(addRealm);
  const guild = get("player", "guild (name, rank, rank index)");
  if (guild) {
    const parts = stringsIn(guild);
    addGuild(parts[0]);
    addRealm(parts[2]);
  }
  const ownGuid = get("player", "UnitGUID");
  if (ownGuid) for (const m of ownGuid.matchAll(GUID)) guids.push(m[0]);

  for (const [section, keys] of Object.entries(file.answers)) {
    for (const [key, { text }] of Object.entries(keys)) {
      for (const m of text.matchAll(/"name"=\(([^)]*)\)/g)) addPerson(stringsIn("(" + m[1] + ")"));
      for (const m of text.matchAll(/"(?:roster|info)"=\("((?:[^"\\]|\\.)*)"/g)) addPerson([unquote(m[1])]);
      for (const m of text.matchAll(/"(?:playerName|winnerName|looterName)"="((?:[^"\\]|\\.)*)"/g)) addPerson([unquote(m[1])]);
      for (const m of text.matchAll(/"masterLooter"=\{([^}]*)\}/g)) {
        const parts = [...m[1].matchAll(/"(?:name|second)"="((?:[^"\\]|\\.)*)"/g)].map((x) => unquote(x[1]));
        addPerson(parts);
      }
      for (const m of text.matchAll(/"masterLootCandidates"=\{([^}]*)\}/g)) stringsIn("{" + m[1] + "}").forEach((n) => addPerson([n]));
      for (const m of key.matchAll(/whisper reply to "((?:[^"\\]|\\.)*)"/g)) addPerson([unquote(m[1])]);
      for (const m of key.matchAll(/invite '([^']+)'/g)) addPerson([m[1]]);
      if (key.startsWith("received on")) addPerson([stringsIn(text)[2]]);
      if (key.startsWith("encounter loot received") && text.startsWith("(")) {
        stringsIn(text).filter((s) => !s.includes("|H") && !/^[A-Z_ ]+$/.test(s) && s !== "args" && s !== "clock" && !/^\d/.test(s)).forEach((s) => addPerson([s]));
      }
      for (const m of (key + " " + text).matchAll(GUID)) guids.push(m[0]);
    }
  }
  extra.names.forEach((n) => addPerson([n]));
  extra.guilds.forEach(addGuild);
  extra.realms.forEach(addRealm);
  for (const m of JSON.stringify(file.db.who ?? {}).matchAll(GUID)) guids.push(m[0]);
  return { names, guilds, realms, self, guids };
}

// The placeholders ------------------------------------------------------------------------------------------------

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function makeAnonymizer(identities) {
  const byLength = (a, b) => b.length - a.length || (a < b ? -1 : 1);
  const all = (pick) => [...new Set(identities.flatMap((i) => [...pick(i)]))];

  // People: each own character first, then every other full name in order, then lone names that belong to nobody yet.
  const order = [];
  for (const i of identities) if (i.self && !order.includes(i.self)) order.push(i.self);
  const full = all((i) => i.names).filter((n) => /\s/.test(n) && !order.includes(n)).sort();
  order.push(...full);
  const map = new Map();
  order.forEach((name, n) => map.set(name, `Player${n + 1}`));
  const tokensOf = (name) => name.split(/[\s-]+/).filter(Boolean);
  const lone = all((i) => i.names).filter((n) => !map.has(n)).sort();
  for (const name of lone) {
    // A part of a known person's name takes that person's placeholder.
    const owner = order.find((person) => tokensOf(person).includes(name));
    if (owner) map.set(name, map.get(owner));
    else {
      order.push(name);
      map.set(name, `Player${order.length}`);
    }
  }
  [...all((i) => i.guilds)].sort().forEach((g, n) => map.set(g, `Guild${n + 1}`));
  [...all((i) => i.realms)].sort().forEach((r, n) => map.set(r, `Realm${n + 1}`));

  const keys = [...map.keys()].sort(byLength);
  const words = keys.length
    ? new RegExp(`(?<![\\p{L}\\p{N}_])(?:${keys.map(escapeRegExp).join("|")})(?![\\p{L}\\p{N}_])`, "gu")
    : null;

  // GUIDs: the own character's first, then by server and id. Servers are numbered in the order they first appear.
  const guids = [];
  for (const i of identities) for (const g of i.guids) if (!guids.includes(g)) guids.push(g);
  const ownGuids = identities.flatMap((i) => i.guids.slice(0, 1));
  const rest = guids.filter((g) => !ownGuids.includes(g)).sort((x, y) => {
    const [tx, sx, ix] = x.split("-");
    const [ty, sy, iy] = y.split("-");
    return (tx < ty ? -1 : tx > ty ? 1 : 0) || Number(sx) - Number(sy) || (ix < iy ? -1 : ix > iy ? 1 : 0);
  });
  const servers = new Map();
  const guidMap = new Map();
  const counters = new Map();
  for (const g of [...new Set(ownGuids), ...rest]) {
    const [type, server] = g.split("-");
    if (!servers.has(server)) servers.set(server, servers.size + 1);
    counters.set(type, (counters.get(type) ?? 0) + 1);
    guidMap.set(g, `${type}-S${servers.get(server)}-${counters.get(type)}`);
  }

  const anonymize = (text) => {
    let out = text.replace(GUID, (g) => guidMap.get(g) ?? g);
    // A folder on the owner's PC is nothing the comparison needs.
    out = out.replace(WINDOWS_PATH, "<path>");
    if (words) out = out.replace(words, (w) => map.get(w));
    return out;
  };
  // What must not be in the output.
  anonymize.secrets = {
    words: [...map.keys()].filter((k) => k.length >= 3),
    guidParts: [...guidMap.keys()].map((g) => g.split("-")[2]),
  };
  return anonymize;
}

// The table -------------------------------------------------------------------------------------------------------

const IGNORED_SECTIONS = new Set(["saved variables"]);
const IGNORED_ROWS = new Set(["time/server time", "time/this PC's time"]);

// Clock times are dropped from keys; a key used twice is numbered by the time it was written.
function rowsOf(file, anonymize) {
  const rows = new Map();
  for (const [section, keys] of Object.entries(file.answers)) {
    if (IGNORED_SECTIONS.has(section)) continue;
    const groups = new Map();
    for (const [key, entry] of Object.entries(keys)) {
      if (IGNORED_ROWS.has(`${section}/${key}`)) continue;
      const clean = anonymize(key.replace(/\s\d{2}:\d{2}:\d{2}\b/g, "").trim());
      if (!groups.has(clean)) groups.set(clean, []);
      groups.get(clean).push(entry);
    }
    const out = new Map();
    for (const [key, entries] of groups) {
      entries.sort((a, b) => a.at - b.at);
      entries.forEach((entry, i) => out.set(entries.length > 1 ? `${key} (${i + 1})` : key, anonymize(entry.text)));
    }
    rows.set(anonymize(section), out);
  }
  return rows;
}

function cell(text, full) {
  let s = (text ?? "").replace(/\s*\n\s*/g, " ");
  if (!full && s.length > 240) s = s.slice(0, 240) + "...";
  return s.replace(/\|/g, "\\|") || " ";
}

function client(file) {
  const run = file.db.run ?? {};
  let version = run.clientVersion;
  let build = run.build;
  let interfaceNumber = run.interface;
  const text = file.answers.client?.["build (version, build, date, interface)"]?.text;
  if (!build && text) [version, build] = stringsIn(text);
  if (!interfaceNumber && text) interfaceNumber = text.match(/,\s*(\d+)\)$/)?.[1];
  return { version, build, interface: interfaceNumber };
}

// Prints the comparison of two saved files. Returns the Markdown text.
export function diffProbes(textA, textB, options = {}) {
  const extra = { names: options.names ?? [], guilds: options.guilds ?? [], realms: options.realms ?? [] };
  const labelA = options.labels?.[0] ?? "before";
  const labelB = options.labels?.[1] ?? "after";
  const a = loadProbe(textA, labelA);
  const b = loadProbe(textB, labelB);
  const identities = [identity(a, extra), identity(b, extra)];
  const anonymize = makeAnonymizer(identities);

  const rowsA = rowsOf(a, anonymize);
  const rowsB = rowsOf(b, anonymize);
  const sections = [...new Set([...rowsA.keys(), ...rowsB.keys()])].sort();

  const lines = ["# Probe comparison", ""];
  const ca = client(a);
  const cb = client(b);
  const meta = (label, x, y) => `| ${label} | ${cell(String(x ?? "not recorded"))} | ${cell(String(y ?? "not recorded"))} |`;
  lines.push("| | Before | After |", "|---|---|---|");
  lines.push(meta("File", anonymize(labelA), anonymize(labelB)));
  lines.push(meta("Probe version", a.db.probeVersion ?? "0.1.0 or earlier", b.db.probeVersion ?? "0.1.0 or earlier"));
  lines.push(meta("Client", ca.version, cb.version), meta("Build", ca.build, cb.build), meta("Interface", ca.interface, cb.interface));
  lines.push(meta("Run began", a.db.run?.startedAtText, b.db.run?.startedAtText), "");

  let added = 0;
  let removed = 0;
  let changed = 0;
  const tables = [];
  for (const section of sections) {
    const before = rowsA.get(section) ?? new Map();
    const after = rowsB.get(section) ?? new Map();
    const keys = [...new Set([...before.keys(), ...after.keys()])].sort();
    const body = [];
    for (const key of keys) {
      const x = before.get(key);
      const y = after.get(key);
      if (x === undefined) added++;
      else if (y === undefined) removed++;
      else if (x !== y) changed++;
      else if (!options.all) continue;
      body.push(`| ${cell(key, true)} | ${x === undefined ? "_not in this run_" : cell(x, options.full)} | ${y === undefined ? "_not in this run_" : cell(y, options.full)} |`);
    }
    if (body.length) tables.push(`## ${section}`, "", "| Key | Before | After |", "|---|---|---|", ...body, "");
  }
  lines.push(`${added + removed + changed} rows differ: ${changed} changed, ${added} only in the second file, ${removed} only in the first.`, "");
  if (tables.length) lines.push(...tables);
  else lines.push("Nothing differs.", "");

  const output = lines.join("\n");
  verify(output, anonymize);
  return output;
}

// A last check, on the finished text, that nothing the tool knows to hide is still in it.
function verify(output, anonymize) {
  const { words, guidParts } = anonymize.secrets;
  const found = words.filter((w) => new RegExp(`(?<![\\p{L}\\p{N}_])${escapeRegExp(w)}(?![\\p{L}\\p{N}_])`, "u").test(output));
  const leftGuids = guidParts.filter((p) => p.length >= 6 && output.includes(p));
  if (found.length || leftGuids.length) {
    throw new Error(`a name or GUID is still in the output, so nothing was printed (${found.length + leftGuids.length} left). Check the saved files and pass it with --name, --guild or --realm.`);
  }
}

// The command line -----------------------------------------------------------------------------------------------

function main(argv) {
  const files = [];
  const options = { names: [], guilds: [], realms: [], all: false, full: false };
  const value = (i, flag) => {
    if (i >= argv.length) throw new Error(`${flag} needs a value`);
    return argv[i];
  };
  let help = false;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--all") options.all = true;
    else if (arg === "--full") options.full = true;
    else if (arg === "--name") options.names.push(value(++i, arg));
    else if (arg === "--guild") options.guilds.push(value(++i, arg));
    else if (arg === "--realm") options.realms.push(value(++i, arg));
    else if (arg === "--help" || arg === "-h") help = true;
    else if (arg.startsWith("--")) throw new Error(`unknown option ${arg}`);
    else files.push(arg);
  }
  if (help || files.length !== 2) {
    console.error('Usage: node tools/probe-diff.mjs before.lua after.lua [--all] [--full] [--name "First Surname"] [--guild "Name"] [--realm "Name"]');
    return help ? 0 : 2;
  }
  options.labels = files.map((f) => basename(f));
  console.log(diffProbes(readFileSync(files[0], "utf8"), readFileSync(files[1], "utf8"), options));
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    console.error(`probe-diff: ${error.message}`);
    process.exitCode = 1;
  }
}
