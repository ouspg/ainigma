import { describe, expect, it } from "vite-plus/test";
import { parseCourseDefinitionKey } from "./identifiers";
import { getCourseSnapshot, getLearningSnapshot } from "./repository";

describe("JSON learning repository", () => {
  it("returns a validated learner snapshot", async () => {
    const snapshot = await getLearningSnapshot();

    expect(snapshot.profile.displayName).toBeTruthy();
    expect(Object.keys(snapshot.courses).length).toBeGreaterThan(0);
  });

  it("resolves course-specific data without exposing the JSON module", async () => {
    const course = await getCourseSnapshot(parseCourseDefinitionKey("security-fundamentals"));

    expect(course?.courseKey).toBe("security-fundamentals-2026-autumn");
    expect(await getCourseSnapshot(parseCourseDefinitionKey("missing-course"))).toBeUndefined();
  });
});
