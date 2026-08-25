import { describe, expect, it } from "vite-plus/test";
import { getCourseSnapshot, getLearningSnapshot } from "./repository";

describe("JSON learning repository", () => {
  it("returns a validated learner snapshot", async () => {
    const snapshot = await getLearningSnapshot();

    expect(snapshot.profile.displayName).toBeTruthy();
    expect(Object.keys(snapshot.courses).length).toBeGreaterThan(0);
  });

  it("resolves course-specific data without exposing the JSON module", async () => {
    const course = await getCourseSnapshot("security-fundamentals");

    expect(course?.courseKey).toBe("security-fundamentals-2026-autumn");
    expect(await getCourseSnapshot("missing-course")).toBeUndefined();
  });
});
