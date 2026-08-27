import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const write = (path, value) => writeFileSync(new URL(path, import.meta.url), value);

const personas = JSON.parse(read("../../../supabase/dev-personas.json"));
const seedTemplate = read("../../../supabase/seed.template.sql");

if (!Array.isArray(personas) || personas.length === 0) {
  throw new Error("Expected at least one local auth persona.");
}

const keys = new Set();
for (const persona of personas) {
  if (!persona || typeof persona !== "object") {
    throw new Error("Every local auth persona must be an object.");
  }
  if (keys.has(persona.key)) {
    throw new Error(`Duplicate local auth persona: ${persona.key}`);
  }
  keys.add(persona.key);

  for (const field of [
    "key",
    "label",
    "description",
    "email",
    "userId",
    "identityId",
    "providerId",
    "profileLabel",
  ]) {
    if (typeof persona[field] !== "string" || persona[field].length === 0) {
      throw new Error(`Missing ${field} for local auth persona ${persona.key ?? "<unknown>"}`);
    }
  }

  for (const field of ["memberships", "accessRequests"]) {
    if (persona[field] !== undefined && !Array.isArray(persona[field])) {
      throw new Error(`${field} must be an array for local auth persona ${persona.key}`);
    }
  }
}

const personaPayload = JSON.stringify(personas, null, 2);
let fixtureTag = "ainigma_fixture";
let suffix = 0;
while (personaPayload.includes(`$${fixtureTag}$`)) {
  fixtureTag = `ainigma_fixture_${++suffix}`;
}

const fixtureMarker = "{{DEV_PERSONAS_JSON}}";
if (seedTemplate.split(fixtureMarker).length !== 2) {
  throw new Error(`Seed template must contain exactly one ${fixtureMarker} marker.`);
}

const seedSql = seedTemplate
  .replaceAll("$ainigma_fixture$", `$${fixtureTag}$`)
  .replace(fixtureMarker, personaPayload);
write(
  "../../../supabase/seed.sql",
  `-- @generated from seed.template.sql and dev-personas.json; do not edit manually.\n${seedSql}`,
);

const personaTs = JSON.stringify(
  personas.map(({ key, label, description }) => ({ key, label, description })),
  null,
  2,
);
const recordsTs = JSON.stringify(
  Object.fromEntries(personas.map(({ key, email, userId }) => [key, { email, userId }])),
  null,
  2,
);
write(
  "../src/dev/dev-local-auth.generated.ts",
  `// @generated from supabase/dev-personas.json — do not edit manually.\nexport const localAuthPersonas = ${personaTs} as const;\n\nexport type LocalAuthPersona = (typeof localAuthPersonas)[number]["key"];\nexport type LocalAuthPersonaOption = (typeof localAuthPersonas)[number];\nexport interface LocalAuthPersonaRecord { email: string; userId: string; }\n\nexport const localAuthPersonaRecords: Record<LocalAuthPersona, LocalAuthPersonaRecord> = ${recordsTs};\n`,
);

console.log(`wrote development auth fixtures from ${root}`);
