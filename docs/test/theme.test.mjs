import assert from "node:assert/strict";
import { test } from "vite-plus/test";
import { resolveDocsTheme } from "../config/theme.mjs";

test("terminal is the default docs theme", () => {
  assert.equal(resolveDocsTheme({}).name, "terminal");
});

test("theme selection changes the complete token set", () => {
  const theme = resolveDocsTheme({ DOCS_THEME: "terminal" });

  assert.equal(theme.name, "terminal");
  assert.equal(theme.colors.accent[0], "#087a46");
  assert.equal(theme.typography.body.family, "iA Writer Quattro S");
});

test("unknown themes fail before asset generation", () => {
  assert.throws(
    () => resolveDocsTheme({ DOCS_THEME: "unknown" }),
    /DOCS_THEME must be one of academic, terminal/,
  );
});
