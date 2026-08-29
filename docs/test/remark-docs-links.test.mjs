import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { test } from "vite-plus/test";
import { rewriteDocsLink } from "../src/lib/remark-docs-links.mjs";

const contentRoot = new URL("../src/content/_temporary/", import.meta.url);
const repositoryRoot = new URL("../../", import.meta.url);
const sourcePath = fileURLToPath(new URL("course-enrollment-flow.md", contentRoot));
const options = {
  base: "/1.1/",
  docsRoot: contentRoot,
  repositoryRoot,
  gitRef: "release/1.1",
  repositoryUrl: "https://github.com/ouspg/ainigma",
};

test("Markdown source links become version-aware routes", () => {
  assert.equal(
    rewriteDocsLink("external-platform-adapter.md#contract", sourcePath, options),
    "/1.1/external-platform-adapter/#contract",
  );

  assert.equal(
    rewriteDocsLink(
      "../plan.md",
      fileURLToPath(new URL("guides/getting-started.md", contentRoot)),
      options,
    ),
    "/1.1/plan/",
  );

  assert.equal(
    rewriteDocsLink("examples/interactive.mdx", sourcePath, options),
    "/1.1/examples/interactive/",
  );
});

test("workspace file links become repository links for the built ref", () => {
  const repositoryPath = fileURLToPath(repositoryRoot);
  assert.equal(
    rewriteDocsLink(`${repositoryPath}apps/web/src/pages/login.astro:25`, sourcePath, options),
    "https://github.com/ouspg/ainigma/blob/release/1.1/apps/web/src/pages/login.astro#L25",
  );
});

test("external and fragment links are unchanged", () => {
  assert.equal(
    rewriteDocsLink("https://example.com/file.md", sourcePath, options),
    "https://example.com/file.md",
  );
  assert.equal(rewriteDocsLink("#section", sourcePath, options), "#section");
});
