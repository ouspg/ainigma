/// <reference types="astro/client" />

import type { StudentProfile } from "./lib/learning/types";

declare global {
  namespace App {
    interface Locals {
      traceId?: string;
      userId?: string;
      profile?: StudentProfile;
    }
  }
}

export {};
