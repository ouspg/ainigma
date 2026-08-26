import { describe, expect, it } from "vite-plus/test";
import { parseCourseDefinitionKey } from "./identifiers";
import { getCourseSnapshot, getLearningSnapshot } from "./repository";

describe("JSON learning repository", () => {
  it("returns a validated learning snapshot without account data", async () => {
    const snapshot = await getLearningSnapshot();

    expect(Object.keys(snapshot.courses).length).toBeGreaterThan(0);
  });

  it("resolves course-specific data without exposing the JSON module", async () => {
    const course = await getCourseSnapshot(parseCourseDefinitionKey("test-course-a"));

    expect(course?.courseKey).toBe("test-course-a-local");
    expect(await getCourseSnapshot(parseCourseDefinitionKey("missing-course"))).toBeUndefined();
  });
});
