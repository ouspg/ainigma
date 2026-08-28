import { getEntry } from "astro:content";
import type { CourseEntry } from "./course-manifest";
import { isCourseDefinitionSlug } from "./identifiers";
import { COURSE_DEFINITIONS } from "./course-manifest.generated";

/** Load only the requested authored MDX entry after manifest publication checks. */
export async function getPublishedCourseEntry(id: string): Promise<CourseEntry | undefined> {
  const courseDefinitionSlug = id.split("/")[0] ?? "";
  if (!isCourseDefinitionSlug(courseDefinitionSlug)) return undefined;
  const definition = COURSE_DEFINITIONS.find(
    (candidate) => candidate.courseDefinitionSlug === courseDefinitionSlug && !candidate.draft,
  );
  if (!definition) return undefined;
  return (await getEntry("courses", id)) as CourseEntry | undefined;
}
