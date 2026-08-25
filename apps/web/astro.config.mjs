// @ts-check
import { fileURLToPath } from "node:url";
import { defineConfig } from "astro/config";
import mdx from "@astrojs/mdx";
import react from "@astrojs/react";
import { unified } from "@astrojs/markdown-remark";
import { loadEnv } from "vite";
import { remarkActivityOutline } from "./src/lib/markdown/remark-activity-outline.mjs";
import { resolveFeatureFlags } from "./src/lib/features.ts";

const appRoot = fileURLToPath(new URL(".", import.meta.url));
const mode = process.env.NODE_ENV === "production" ? "production" : "development";
const featureFlags = resolveFeatureFlags({ ...loadEnv(mode, appRoot, ""), ...process.env });

export default defineConfig({
  i18n: {
    defaultLocale: "en",
    locales: featureFlags.finnish ? ["en", "fi"] : ["en"],
    ...(featureFlags.finnish ? { fallback: { fi: "en" } } : {}),
    routing: {
      prefixDefaultLocale: false,
      fallbackType: "rewrite",
    },
  },
  vite: {
    resolve: {
      alias: {
        "@course-components": fileURLToPath(new URL("./src/components/content", import.meta.url)),
      },
    },
  },
  markdown: {
    processor: unified({ remarkPlugins: [remarkActivityOutline] }),
    shikiConfig: {
      themes: {
        light: "github-light",
        dark: "github-dark",
      },
      defaultColor: false,
    },
  },
  integrations: [react(), mdx()],
});
