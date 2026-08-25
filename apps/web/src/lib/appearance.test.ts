import { describe, expect, it } from "vite-plus/test";
import {
  isAppearanceTheme,
  isColorMode,
  resolveAppearanceTheme,
  resolveColorMode,
} from "./appearance";

describe("appearance preferences", () => {
  it("accepts the supported visual themes and falls back safely", () => {
    expect(isAppearanceTheme("terminal")).toBe(true);
    expect(resolveAppearanceTheme("hacker")).toBe("terminal");
    expect(isAppearanceTheme("terminal-green")).toBe(false);
    expect(resolveAppearanceTheme("academic")).toBe("academic");
    expect(resolveAppearanceTheme("unknown")).toBe("academic");
  });

  it("accepts system, light, and dark color modes", () => {
    expect(isColorMode("system")).toBe(true);
    expect(isColorMode("dark")).toBe(true);
    expect(isColorMode("sepia")).toBe(false);
    expect(resolveColorMode(undefined)).toBe("system");
  });
});
