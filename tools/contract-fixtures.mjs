// Writes the GG1: string beside each JSON fixture in contract/fixtures (name.json -> name.gg1.txt), packed the way
// contract/README.md says. Run it after changing a fixture: `node tools/contract-fixtures.mjs`. The tests decode the
// strings back and compare them with the JSON, so a stale string fails `npm test`.
//
// With `--schema` it also adds the fields the fixtures now use to contract/schema-v1.json, the frozen list of every
// field and its type. It only adds. It refuses to change the type of a field already there, since a field's type never
// changes in version 1.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { encode, typesOf } from "../test/contract-lib.mjs";

const ROOT = join(import.meta.dirname, "..", "contract");
const DIR = join(ROOT, "fixtures");
const files = readdirSync(DIR).filter((f) => f.endsWith(".json")).sort();

for (const file of files) {
  const text = encode(JSON.parse(readFileSync(join(DIR, file), "utf8")));
  writeFileSync(join(DIR, file.replace(/\.json$/, ".gg1.txt")), `${text}\n`);
  console.log(`${file.replace(/\.json$/, ".gg1.txt")}: ${text.length} characters`);
}

if (process.argv.includes("--schema")) {
  const path = join(ROOT, "schema-v1.json");
  let frozen = {};
  try {
    frozen = JSON.parse(readFileSync(path, "utf8"));
  } catch {
    // The first time there is none.
  }
  const now = typesOf(files.map((f) => JSON.parse(readFileSync(join(DIR, f), "utf8"))));
  for (const [field, type] of Object.entries(now)) {
    if (frozen[field] && frozen[field] !== type) throw new Error(`${field} was ${frozen[field]} and is now ${type}: a field's type never changes`);
    frozen[field] ??= type;
  }
  const sorted = Object.fromEntries(Object.entries(frozen).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
  writeFileSync(path, `${JSON.stringify(sorted, null, 2)}\n`);
  console.log(`schema-v1.json: ${Object.keys(sorted).length} fields`);
}
