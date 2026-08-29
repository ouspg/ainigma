import { defineConfig } from "vite-plus";

export default defineConfig({
  fmt: {
    ignorePatterns: [
      "**/.agents/**",
      "**/.astro/**",
      "**/.codex/**",
      "**/dist/**",
      "**/*.generated.css",
      "**/*.generated.ts",
      "**/database.types.ts",
      // Nimbus registry components are tracked by exact source hashes.
      "**/docs/src/components/ui/**",
    ],
  },
  lint: {
    ignorePatterns: [
      "**/.agents/**",
      "**/.astro/**",
      "**/.codex/**",
      "**/dist/**",
      "**/*.generated.css",
      "**/database.types.ts",
    ],
    jsPlugins: [{ name: "vite-plus", specifier: "vite-plus/oxlint-plugin" }],
    rules: { "vite-plus/prefer-vite-plus-imports": "error" },
    options: { typeAware: true, typeCheck: true },
  },
});
