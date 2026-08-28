import { describe, expect, it } from "vite-plus/test";
import { parseCourseOfferingKey } from "./identifiers";
import { getCourseOfferingSnapshot, getLearningSnapshot } from "./repository";

describe("JSON learning repository", () => {
  it("returns a validated learning snapshot without account data", async () => {
    const snapshot = await getLearningSnapshot();

    expect(Object.keys(snapshot.courseOfferings).length).toBeGreaterThan(0);
  });

  it("resolves course-specific data without exposing the JSON module", async () => {
    const offering = await getCourseOfferingSnapshot(parseCourseOfferingKey("test-course-a-local"));

    expect(offering?.courseDefinitionKey).toBe("test-course-a");
    expect(offering?.courseDefinitionReleaseId).toBe("60000000-0000-0000-0000-000000000001");
    expect(
      await getCourseOfferingSnapshot(parseCourseOfferingKey("missing-course-offering")),
    ).toBeUndefined();
  });
});
