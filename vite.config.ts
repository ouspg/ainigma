import { defineConfig } from "vite-plus";

export default defineConfig({
  fmt: {
    ignorePatterns: [
      "**/.agents/**",
      "**/.astro/**",
      "**/.codex/**",
      "**/dist/**",
      "**/*.generated.css",
      "**/database.types.ts",
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
