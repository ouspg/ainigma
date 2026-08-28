/// <reference types="astro/client" />

import type { StudentProfile } from "./lib/learning/types";
import type { AuthorizedCourseOffering } from "./lib/auth/course-access";

declare global {
  namespace App {
    interface Locals {
      traceId?: string;
      userId?: string;
      profile?: StudentProfile;
      authorizedCourseOffering?: AuthorizedCourseOffering;
    }
  }
}

export {};
