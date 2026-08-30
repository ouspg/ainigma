/// <reference types="astro/client" />

import type { StudentProfile } from "./lib/learning/types";
import type {
  AvailableCourseOffering,
  CourseAccessState,
  CourseMembership,
} from "./lib/auth/course-access";

declare global {
  namespace App {
    interface Locals {
      traceId?: string;
      userId?: string;
      profile?: StudentProfile;
      courseMemberships?: CourseMembership[];
      courseAccessState?: CourseAccessState;
      availableCourseOffering?: AvailableCourseOffering;
      availableCourseOfferings?: AvailableCourseOffering[];
    }
  }
}

export {};
