// Writes the GG1: string beside each JSON fixture in contract/fixtures (name.json -> name.gg1.txt), packed the way
// contract/README.md says. Run it after changing a fixture: `node tools/contract-fixtures.mjs`. The tests decode the
// strings back and compare them with the JSON, so a stale string fails `npm test`.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { encode } from "../test/contract-lib.mjs";

const DIR = join(import.meta.dirname, "..", "contract", "fixtures");

for (const file of readdirSync(DIR).filter((f) => f.endsWith(".json")).sort()) {
  const text = encode(JSON.parse(readFileSync(join(DIR, file), "utf8")));
  writeFileSync(join(DIR, file.replace(/\.json$/, ".gg1.txt")), `${text}\n`);
  console.log(`${file.replace(/\.json$/, ".gg1.txt")}: ${text.length} characters`);
}
