import assert from "node:assert/strict";
import { test } from "vite-plus/test";
import {
  resolveDocsVersions,
  versionPagePath,
  withDocsBase,
  withoutDocsBase,
} from "../config/versions.mjs";

test("main is mounted at the documentation root", () => {
  const config = resolveDocsVersions({
    DOCS_VERSION: "main",
    DOCS_ACTIVE_VERSIONS: "main,1.1",
  });

  assert.equal(config.current.base, "/");
  assert.deepEqual(config.versions, [
    { id: "main", label: "main", base: "/" },
    { id: "1.1", label: "1.1", base: "/1.1/" },
  ]);
});

test("release builds use their version prefix below a common root", () => {
  const config = resolveDocsVersions({
    DOCS_VERSION: "1.1",
    DOCS_ACTIVE_VERSIONS: "main,1.1",
    DOCS_ROOT_PATH: "/docs",
  });

  assert.equal(config.current.base, "/docs/1.1/");
  assert.equal(config.versions[0]?.base, "/docs/");
});

test("the current version is always available in the selector", () => {
  const config = resolveDocsVersions({
    DOCS_VERSION: "1.1",
    DOCS_ACTIVE_VERSIONS: "main",
  });

  assert.deepEqual(
    config.versions.map(({ id }) => id),
    ["1.1", "main"],
  );
});

test("version links preserve the current page and query", () => {
  assert.equal(
    versionPagePath("/docs/long-term-plan/", "/docs/", "/docs/1.1/", "?view=full"),
    "/docs/1.1/long-term-plan/?view=full",
  );
  assert.equal(versionPagePath("/1.1/", "/1.1/", "/"), "/");
});

test("unsafe version segments fail before building", () => {
  assert.throws(() => resolveDocsVersions({ DOCS_VERSION: "../release" }), /safe URL segment/);
});

test("Nimbus navigation paths are prefixed exactly once", () => {
  assert.equal(withDocsBase("/compiler/", "/1.1/"), "/1.1/compiler/");
  assert.equal(withDocsBase("/1.1/compiler/", "/1.1/"), "/1.1/compiler/");
  assert.equal(withDocsBase("https://example.com", "/1.1/"), "https://example.com");
  assert.equal(withDocsBase("/compiler/?view=full#api", "/1.1/"), "/1.1/compiler/?view=full#api");
});

test("deployed paths map back to Nimbus root-relative paths", () => {
  assert.equal(withoutDocsBase("/1.1/compiler/", "/1.1/"), "/compiler/");
  assert.equal(withoutDocsBase("/1.1/", "/1.1/"), "/");
  assert.equal(withoutDocsBase("/compiler/", "/"), "/compiler/");
});
