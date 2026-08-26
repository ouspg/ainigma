import { describe, expect, it } from "vite-plus/test";
import { buildOutlineSections, getPublicCourseCatalog } from "./catalog";

describe("getPublicCourseCatalog", () => {
  it("discovers every course overview without reading learner progress", () => {
    const entries = [
      {
        id: "security-fundamentals/index",
        data: {
          kind: "course",
          definitionKey: "security-fundamentals",
          order: 0,
          catalogOrder: 2,
          code: "IC00AJ74",
          tone: "orange",
          title: "Security fundamentals",
          summary: "Foundational security study.",
          showProgress: true,
        },
      },
      {
        id: "applied-cryptography/index",
        data: {
          kind: "course",
          definitionKey: "applied-cryptography",
          order: 0,
          catalogOrder: 3,
          code: "IC00AJ82",
          tone: "blue",
          title: "Applied cryptography",
          summary: "Practical cryptography study.",
          showProgress: true,
        },
      },
      {
        id: "secure-programming/index",
        data: {
          kind: "course",
          definitionKey: "secure-programming",
          order: 0,
          catalogOrder: 4,
          code: "IC00AJ91",
          tone: "teal",
          title: "Secure programming",
          summary: "Defensive software construction.",
          showProgress: true,
        },
      },
      {
        id: "new-course/index",
        data: {
          kind: "course",
          definitionKey: "new-course-definition",
          order: 0,
          catalogOrder: 1,
          code: "NEW100",
          catalogUrl: "https://example.edu/courses/NEW100",
          tone: "blue",
          title: "New authored course",
          summary: "Discovered directly from its overview file.",
          showProgress: true,
        },
      },
      {
        id: "draft-course/index",
        data: {
          kind: "course",
          definitionKey: "draft-course-definition",
          draft: true,
          order: 0,
          catalogOrder: 5,
          code: "DRAFT1",
          tone: "teal",
          title: "Draft course",
          summary: "Not published yet.",
          showProgress: true,
        },
      },
    ] as unknown as Parameters<typeof getPublicCourseCatalog>[0];

    const catalog = getPublicCourseCatalog(entries);

    expect(catalog).toHaveLength(4);
    expect(catalog.some((course) => course.slug === "draft-course")).toBe(false);
    expect(catalog[0]).toEqual({
      slug: "new-course",
      definitionKey: "new-course-definition",
      code: "NEW100",
      catalogUrl: "https://example.edu/courses/NEW100",
      title: "New authored course",
      summary: "Discovered directly from its overview file.",
      tone: "blue",
    });
    expect(catalog.every((course) => !("progress" in course))).toBe(true);
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
