/// <reference types="astro/client" />

import type { StudentProfile } from "./lib/learning/types";

declare namespace App {
  interface Locals {
    userId?: string;
    profile?: StudentProfile;
  }
}
