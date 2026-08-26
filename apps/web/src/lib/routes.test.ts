import { describe, expect, it } from "vite-plus/test";
import { parseCourseSlug } from "./learning/identifiers";
import {
  canonicalPath,
  courseRouteTargetPath,
  localizedPath,
  matchAppRoute,
  routeUsesLearnerShell,
  routeAccessGroups,
  routes,
} from "./routes";

const course = parseCourseSlug("security-fundamentals");

describe("application routes", () => {
  it("generates canonical and localized course paths", () => {
    expect(routes.course.path({ course })).toBe("/courses/security-fundamentals/");
    expect(routes.courseWeek.path({ course, week: "week 04" })).toBe(
      "/courses/security-fundamentals/week%2004/",
    );
    expect(
      courseRouteTargetPath({ route: "courseTask", course, week: "week-04", task: "lab/part 1" }),
    ).toBe("/courses/security-fundamentals/week-04/lab/part%201/");
    expect(localizedPath("fi", routes.course.path({ course }))).toBe(
      "/fi/courses/security-fundamentals/",
    );
  });

  it("normalizes locale prefixes without changing query strings or fragments", () => {
    expect(canonicalPath("/fi/desk/?week=4#today")).toBe("/desk/?week=4#today");
    expect(localizedPath("en", "/fi/activity/")).toBe("/activity/");
  });

  it("classifies every page family by its current access requirement", () => {
    expect(matchAppRoute("/")?.access).toBe("public");
    expect(matchAppRoute("/login/")?.access).toBe("guestOnly");
    expect(matchAppRoute("/auth/callback")?.access).toBe("protocol");
    expect(matchAppRoute("/auth/local")?.access).toBe("protocol");
    expect(matchAppRoute("/fi/desk/")?.access).toBe("authenticated");
    expect(matchAppRoute("/courses/security-fundamentals/week-04/task/")).toMatchObject({
      access: "courseMember",
      params: { course, task: "task", week: "week-04" },
    });
  });

  it("keeps the route access review exhaustive and duplicate-free", () => {
    const grouped = Object.values(routeAccessGroups).flat();
    expect(new Set(grouped).size).toBe(grouped.length);
    expect(new Set(grouped)).toEqual(new Set(Object.keys(routes)));
  });

  it("classifies learner-shell routes independently from access policy", () => {
    expect(routeUsesLearnerShell("/announcements/")).toBe(true);
    expect(routeUsesLearnerShell("/fi/courses/security-fundamentals/")).toBe(true);
    expect(routeUsesLearnerShell("/login/")).toBe(false);
  });
});
