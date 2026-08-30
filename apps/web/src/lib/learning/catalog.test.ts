import { describe, expect, it } from "vite-plus/test";
import type { AvailableCourseOffering } from "../auth/course-access";
import {
  buildOutlineSections,
  buildCourseCatalog,
  getCoursePageData,
  getLearningWorkspace,
} from "./catalog";
import {
  parseCourseDefinitionKey,
  parseCourseDefinitionReleaseId,
  parseCourseOfferingKey,
} from "./identifiers";
import { getLearningSnapshot } from "./repository";

describe("buildCourseCatalog", () => {
  it("exposes the generated public catalog without learner progress", () => {
    const catalog = buildCourseCatalog([
      {
        offeringKey: parseCourseOfferingKey("test-course-a-local"),
        courseDefinitionKey: parseCourseDefinitionKey("test-course-a"),
        courseDefinitionReleaseId: parseCourseDefinitionReleaseId(
          "60000000-0000-0000-0000-000000000001",
        ),
        code: "IC00AAAA",
        enrollmentMode: "approval_required",
        startsAt: null,
        endsAt: null,
        externalUrl: null,
      },
    ]);

    expect(catalog.length).toBeGreaterThan(0);
    expect(catalog.every((course) => course.learner === undefined)).toBe(true);
    expect(catalog[0]?.href).toBe("/courses/test-course-a-local/");
  });
});

describe("getLearningWorkspace", () => {
  it("keeps an empty learner workspace free of enrolled courses and activity", async () => {
    const workspace = await getLearningWorkspace(
      { displayName: "Test Learner", firstName: "Test" },
      await getLearningSnapshot(),
      [],
    );

    expect(workspace.courses).toHaveLength(0);
    expect(workspace.agenda).toHaveLength(0);
    expect(workspace.announcements).toHaveLength(0);
    expect(workspace.activity).toHaveLength(0);
  });

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
    const learning = await getLearningSnapshot();
    await expect(
      getLearningWorkspace({ displayName: "Test Learner", firstName: "Test" }, learning, [
        {
          offeringKey: parseCourseOfferingKey("test-course-a-local"),
          courseDefinitionKey: parseCourseDefinitionKey("test-course-a"),
          courseDefinitionReleaseId: parseCourseDefinitionReleaseId(
            "60000000-0000-0000-0000-000000000099",
          ),
        },
      ]),
    ).rejects.toThrow("Course definition release mismatch");
  });
});

describe("getCoursePageData", () => {
  const offering: AvailableCourseOffering = {
    offeringKey: parseCourseOfferingKey("test-course-a-local"),
    courseDefinitionKey: parseCourseDefinitionKey("test-course-a"),
    courseDefinitionReleaseId: parseCourseDefinitionReleaseId(
      "60000000-0000-0000-0000-000000000001",
    ),
    code: "IC00AAAA",
    enrollmentMode: "approval_required",
    startsAt: null,
    endsAt: null,
    externalUrl: null,
  };
  const profile = { displayName: "Test Learner", firstName: "Test" };

  it("uses the same course shape for anonymous and empty learners", async () => {
    const anonymous = await getCoursePageData({
      accessState: "anonymous",
      availableOfferings: [offering],
      offering,
    });
    const empty = await getCoursePageData({
      accessState: "empty",
      availableOfferings: [offering],
      offering,
      profile,
    });
    const pending = await getCoursePageData({
      accessState: "pending",
      availableOfferings: [offering],
      offering,
      profile,
    });

    expect(anonymous.course.learner).toBeUndefined();
    expect(anonymous.workspace).toBeUndefined();
    expect(empty.course.learner).toBeUndefined();
    expect(empty.workspace?.courses).toHaveLength(0);
    expect(empty.navigationCourses).toEqual(anonymous.navigationCourses);
    expect(pending.accessState).toBe("pending");
    expect(pending.course.learner).toBeUndefined();
  });

  it("adds learner state only for accepted membership", async () => {
    const accepted = await getCoursePageData({
      accessState: "accepted",
      availableOfferings: [offering],
      memberships: [offering],
      offering,
      profile,
    });

    expect(accepted.course.learner?.progress).toBe(42);
    expect(accepted.workspace?.courses).toHaveLength(1);
    expect(accepted.navigationCourses).toEqual(accepted.workspace?.courses);
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
