import { describe, expect, it } from "vite-plus/test";
import { parseCourseSlug } from "./identifiers";
import { getCourseDefinitionKey, type CourseEntry } from "./course-manifest";

describe("course manifest identity", () => {
  it("keeps the authored identity independent from the directory and route slug", () => {
    const entries = [
      {
        id: "renamed-course-directory/index",
        data: {
          kind: "course",
          definitionKey: "stable-course-definition",
        },
      },
    ] as unknown as CourseEntry[];

    expect(getCourseDefinitionKey(entries, parseCourseSlug("renamed-course-directory"))).toBe(
      "stable-course-definition",
    );
  });
});
