# Reinstall every tracked Nimbus UI component from the registry
set -e
for component in $(node -e '
  const { readFileSync } = require("node:fs");
  const manifest = JSON.parse(readFileSync("nimbus.json", "utf8"));
  for (const item of manifest.components ?? []) {
    if (item.type === "registry:ui") console.log(item.slug);
  }
'); do
  npx nimbus-docs add "$component" --overwrite --yes
done
