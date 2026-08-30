import type { CoursePageData, LearningShellData } from "./catalog";
import { getCoursePageData, getLearningShellData } from "./catalog";

export async function loadCoursePageData(locals: App.Locals): Promise<CoursePageData | null> {
  const offering = locals.availableCourseOffering;
  if (!offering) return null;

  return getCoursePageData({
    accessState: locals.courseAccessState ?? "anonymous",
    availableOfferings: locals.availableCourseOfferings ?? [offering],
    memberships: locals.courseMemberships ?? [],
    offering,
    ...(locals.profile ? { profile: locals.profile } : {}),
  });
}

export async function loadLearningShellData(locals: App.Locals): Promise<LearningShellData> {
  if (!locals.profile) {
    throw new Error("Authenticated learner pages require a profile in Astro.locals.");
  }

  return getLearningShellData(
    locals.profile,
    locals.courseMemberships ?? [],
    locals.availableCourseOfferings ?? [],
  );
}
