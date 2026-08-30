import { describe, expect, it } from "vite-plus/test";
import { parseCourseOfferingKey } from "../learning/identifiers";
import {
  findCourseMembership,
  getCourseAccessState,
  parseCourseAccessRequests,
  parseCourseMemberships,
} from "./course-access";

const offeringKey = parseCourseOfferingKey("security-fundamentals-2026-spring");
const membershipResponse = {
  courses: [
    {
      offering_key: offeringKey,
      course_definition_key: "security-fundamentals",
      course_definition_release_id: "60000000-0000-0000-0000-000000000001",
    },
    {
      offering_key: "security-fundamentals-2026-autumn",
      course_definition_key: "security-fundamentals",
      course_definition_release_id: "60000000-0000-0000-0000-000000000002",
    },
  ],
};

describe("course access", () => {
  it("accepts only a matching course returned by the membership RPC", () => {
    const memberships = parseCourseMemberships(membershipResponse);

    expect(findCourseMembership(memberships, offeringKey)).toEqual({
      offeringKey,
      courseDefinitionKey: "security-fundamentals",
      courseDefinitionReleaseId: "60000000-0000-0000-0000-000000000001",
    });
    expect(
      findCourseMembership(memberships, parseCourseOfferingKey("security-fundamentals-2025")),
    ).toBeNull();
    expect(
      findCourseMembership(parseCourseMemberships({ courses: "invalid" }), offeringKey),
    ).toBeNull();
  });

  it("maps empty, pending, approved, and accepted records to UI access states", () => {
    expect(getCourseAccessState([], [], offeringKey)).toBe("empty");

    for (const status of ["pending", "approved"] as const) {
      const requests = parseCourseAccessRequests([{ offering_key: offeringKey, status }]);
      expect(getCourseAccessState([], requests, offeringKey)).toBe("pending");
    }

    for (const status of ["rejected", "cancelled"] as const) {
      const requests = parseCourseAccessRequests([{ offering_key: offeringKey, status }]);
      expect(getCourseAccessState([], requests, offeringKey)).toBe("empty");
    }

    expect(getCourseAccessState(parseCourseMemberships(membershipResponse), [], offeringKey)).toBe(
      "accepted",
    );
  });
});
