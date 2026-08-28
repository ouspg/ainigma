import { describe, expect, it } from "vite-plus/test";
import {
  buildOutlineSections,
  getLearningPageData,
  getLearningWorkspace,
  getPublicCourseCatalog,
} from "./catalog";
import {
  parseCourseDefinitionKey,
  parseCourseDefinitionReleaseId,
  parseCourseOfferingKey,
} from "./identifiers";
import { getLearningSnapshot } from "./repository";

describe("getPublicCourseCatalog", () => {
  it("exposes the generated public catalog without learner progress", () => {
    const catalog = getPublicCourseCatalog();

    expect(catalog.length).toBeGreaterThan(0);
    expect(catalog.every((course) => !("progress" in course))).toBe(true);
  });
});

describe("getLearningWorkspace", () => {
  it("keeps two offerings of one authored definition as separate course spaces", async () => {
    const learning = await getLearningSnapshot();
    const originalOfferingKey = parseCourseOfferingKey("test-course-a-local");
    const originalOffering = learning.courseOfferings[originalOfferingKey];
    if (!originalOffering) throw new Error("Missing test course offering fixture");
    const secondOfferingKey = parseCourseOfferingKey("test-course-a-retake-local");
    const secondOffering = {
      ...originalOffering,
      startDate: "2027-01-11",
      endDate: "2027-05-16",
      nextActivity: {
        ...originalOffering.nextActivity,
        target: {
          ...originalOffering.nextActivity.target,
          offeringKey: secondOfferingKey,
        },
      },
    };
    const workspace = await getLearningWorkspace(
      { displayName: "Test Learner", firstName: "Test" },
      {
        ...learning,
        courseOfferings: {
          ...learning.courseOfferings,
          [secondOfferingKey]: secondOffering,
        },
      },
    );

    const matchingOfferings = workspace.courses.filter(
      (course) => course.courseDefinitionKey === "test-course-a",
    );
    expect(matchingOfferings).toHaveLength(2);
    expect(new Set(matchingOfferings.map((course) => course.offeringKey))).toEqual(
      new Set(["test-course-a-local", secondOfferingKey]),
    );
    expect(new Set(matchingOfferings.map((course) => course.href)).size).toBe(2);
    expect(new Set(matchingOfferings.map((course) => course.courseDefinitionReleaseId))).toEqual(
      new Set([originalOffering.courseDefinitionReleaseId]),
    );
  });

  it("rejects content state from a different compiler release", async () => {
    await expect(
      getLearningPageData(
        { displayName: "Test Learner", firstName: "Test" },
        parseCourseOfferingKey("test-course-a-local"),
        parseCourseDefinitionKey("test-course-a"),
        parseCourseDefinitionReleaseId("60000000-0000-0000-0000-000000000099"),
      ),
    ).rejects.toThrow("Authorized course definition release mismatch");
  });
});

describe("buildOutlineSections", () => {
  it("keeps reader-facing headings and attaches their activity identifiers", () => {
    const outline = buildOutlineSections(
      [
        { depth: 1, slug: "title", text: "Title" },
        { depth: 2, slug: "observe", text: "Observe" },
        { depth: 3, slug: "verify", text: "Verify" },
        { depth: 4, slug: "aside", text: "Aside" },
      ],
      [
        { headingIndex: 1, activityIds: ["packet-investigation"] },
        { headingIndex: 2, activityIds: ["packet-flag"] },
      ],
    );

    expect(outline).toEqual([
      {
        depth: 2,
        slug: "observe",
        text: "Observe",
        activityIds: ["packet-investigation"],
      },
      { depth: 3, slug: "verify", text: "Verify", activityIds: ["packet-flag"] },
    ]);
  });
});
