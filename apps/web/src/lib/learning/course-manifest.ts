import type { CollectionEntry } from "astro:content";
import {
  parseCourseDefinitionKey,
  parseCourseDefinitionSlug,
  type CourseDefinitionKey,
  type CourseDefinitionSlug,
} from "./identifiers";

export type CourseEntry = CollectionEntry<"courses">;

export function courseDefinitionSlugOf(entry: CourseEntry): CourseDefinitionSlug {
  return parseCourseDefinitionSlug(entry.id.split("/")[0] ?? "");
}

export function courseDefinitionKeyOf(entry: CourseEntry): CourseDefinitionKey {
  if (entry.data.kind !== "course") {
    throw new Error(`Expected course overview entry: ${entry.id}`);
  }
  return parseCourseDefinitionKey(entry.data.courseDefinitionKey);
}

export function getCourseOverview(
  entries: CourseEntry[],
  courseDefinitionSlug: CourseDefinitionSlug,
): CourseEntry | undefined {
  return entries.find(
    (entry) =>
      courseDefinitionSlugOf(entry) === courseDefinitionSlug && entry.data.kind === "course",
  );
}

/** Resolve a mutable content-directory slug to its immutable authored identity. */
export function getCourseDefinitionKey(
  entries: CourseEntry[],
  courseDefinitionSlug: CourseDefinitionSlug,
): CourseDefinitionKey | null {
  const overview = getCourseOverview(entries, courseDefinitionSlug);
  return overview ? courseDefinitionKeyOf(overview) : null;
}
