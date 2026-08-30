import { fileURLToPath } from "node:url";
import { unified } from "@astrojs/markdown-remark";
import nimbus, {
  defineConfig as defineNimbusConfig,
} from "@cloudflare/nimbus-docs";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";
import { docsSites } from "./config/sites.mjs";
import { docsVersions } from "./config/versions.mjs";
import { remarkDocsLinks } from "./src/lib/remark-docs-links.mjs";

const repositoryUrl = "https://github.com/ouspg/ainigma";
const astroIconComponents = fileURLToPath(
  new URL("./src/components/astro-icon-components.ts", import.meta.url),
);
const site = process.env.DOCS_SITE?.trim() || "http://localhost:4324";
const encodedGitRef = docsVersions.gitRef
  .split("/")
  .map(encodeURIComponent)
  .join("/");

const nimbusConfig = defineNimbusConfig({
  site,
  title: "Ainigma Docs",
  description:
    "Architecture, development, and operations documentation for Ainigma.",
  locale: "en",
  homeLabel: "Ainigma",
  github: repositoryUrl,
  editPattern: `${repositoryUrl}/edit/${encodedGitRef}/{path}`,
  socialImageAlt: "Ainigma documentation",
  head: [
    {
      tag: "link",
      attrs: { rel: "icon", href: `${docsVersions.current.base}favicon.svg` },
    },
  ],
  sidebar: {
    // Each first-level directory is a documentation site with its own rail.
    // Section scoping keeps unrelated product areas out of the current page.
    scope: "section",
    overviewLabel: "Overview",
    items: [
      { label: "Overview", link: "/" },
      // Root-level pages form the landing-page rail. Product-site groups
      // below are only shown when a page inside that site is active.
      { label: "Core philosophy", link: "/core-philosophy/" },
      { label: "Architecture", link: "/architecture/" },
      ...docsSites.map(({ slug, label }) => ({
        label,
        autogenerate: { directory: slug },
      })),
    ],
  },
});

export default defineConfig({
  base: docsVersions.current.base,
  output: "static",
  trailingSlash: "always",
  prefetch: {
    prefetchAll: true,
    defaultStrategy: "hover",
  },
  vite: {
    plugins: [tailwindcss()],
    resolve: {
      alias: {
        "astro-icon/components": astroIconComponents,
      },
    },
  },
  integrations: [
    nimbus(nimbusConfig, {
      markdown: {
        processor: unified({
          remarkPlugins: [
            [
              remarkDocsLinks,
              {
                base: docsVersions.current.base,
                docsRoot: new URL("./src/content/docs/", import.meta.url),
                repositoryRoot: new URL("../", import.meta.url),
                gitRef: docsVersions.gitRef,
                repositoryUrl,
              },
            ],
          ],
        }),
      },
      rules: {
        "nimbus/frontmatter-shape": "error",
        "nimbus/internal-link": "error",
      },
    }),
  ],
});
