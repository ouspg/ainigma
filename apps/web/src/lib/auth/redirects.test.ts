import { describe, expect, it } from "vite-plus/test";
import { parseCourseOfferingKey } from "../learning/identifiers";
import { findAuthorizedCourseOffering } from "./course-access";
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

  it("accepts only a matching course returned by the authorization RPC", () => {
    const spring = parseCourseOfferingKey("security-fundamentals-2026-spring");
    const access = {
      courses: [
        {
          offering_key: "security-fundamentals-2026-spring",
          course_definition_key: "security-fundamentals",
          course_definition_release_id: "60000000-0000-0000-0000-000000000001",
        },
        {
          offering_key: "security-fundamentals-2026-autumn",
          course_definition_key: "security-fundamentals",
          course_definition_release_id: "60000000-0000-0000-0000-000000000002",
        },
      ],
    };

    expect(findAuthorizedCourseOffering(access, spring)).toEqual({
      offeringKey: spring,
      courseDefinitionKey: "security-fundamentals",
      courseDefinitionReleaseId: "60000000-0000-0000-0000-000000000001",
    });
    expect(
      findAuthorizedCourseOffering(access, parseCourseOfferingKey("security-fundamentals-2025")),
    ).toBeNull();
    expect(findAuthorizedCourseOffering({ courses: "invalid" }, spring)).toBeNull();
  });
});
