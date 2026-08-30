import { describe, expect, it } from "vite-plus/test";
import { safeNextPath, signInPath } from "./redirects";

describe("authentication redirects", () => {
  it("accepts only same-origin relative destinations", () => {
    expect(safeNextPath("/courses/security-fundamentals/?tab=map")).toBe(
      "/courses/security-fundamentals/?tab=map",
    );
    expect(safeNextPath("https://example.com")).toBe("/desk/");
    expect(safeNextPath("//example.com/path")).toBe("/desk/");
    expect(safeNextPath(undefined)).toBe("/desk/");
  });

  it("builds localized login redirects without allowing an external next URL", () => {
    expect(signInPath("en", new URL("https://ainigma.test/desk/?week=4"))).toBe(
      "/login/?next=%2Fdesk%2F%3Fweek%3D4",
    );
    expect(signInPath("fi", new URL("https://ainigma.test/fi/activity/"))).toBe(
      "/fi/login/?next=%2Ffi%2Factivity%2F",
    );
  });
});
