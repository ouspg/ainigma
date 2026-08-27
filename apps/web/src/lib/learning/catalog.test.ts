import { describe, expect, it } from "vite-plus/test";
import { buildOutlineSections, getPublicCourseCatalog } from "./catalog";

describe("getPublicCourseCatalog", () => {
  it("exposes the generated public catalog without learner progress", () => {
    const catalog = getPublicCourseCatalog();

    expect(catalog.length).toBeGreaterThan(0);
    expect(catalog.every((course) => !("progress" in course))).toBe(true);
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
