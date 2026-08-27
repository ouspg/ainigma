import { getEntry } from "astro:content";
import type { CourseEntry } from "./course-manifest";
import { isCourseSlug } from "./identifiers";
import { COURSE_DEFINITIONS } from "./course-manifest.generated";

/** Load only the requested authored MDX entry after manifest publication checks. */
export async function getPublishedCourseEntry(id: string): Promise<CourseEntry | undefined> {
  const courseSlug = id.split("/")[0] ?? "";
  if (!isCourseSlug(courseSlug)) return undefined;
  const definition = COURSE_DEFINITIONS.find(
    (candidate) => candidate.slug === courseSlug && !candidate.draft,
  );
  if (!definition) return undefined;
  return (await getEntry("courses", id)) as CourseEntry | undefined;
}
