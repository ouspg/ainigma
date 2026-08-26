import type { CollectionEntry } from "astro:content";
import {
  parseCourseDefinitionKey,
  parseCourseSlug,
  type CourseDefinitionKey,
  type CourseSlug,
} from "./identifiers";

export type CourseEntry = CollectionEntry<"courses">;

export function courseSlugOf(entry: CourseEntry): CourseSlug {
  return parseCourseSlug(entry.id.split("/")[0] ?? "");
}

export function courseDefinitionKeyOf(entry: CourseEntry): CourseDefinitionKey {
  if (entry.data.kind !== "course") {
    throw new Error(`Expected course overview entry: ${entry.id}`);
  }
  return parseCourseDefinitionKey(entry.data.definitionKey);
}

export function getCourseOverview(
  entries: CourseEntry[],
  slug: CourseSlug,
): CourseEntry | undefined {
  return entries.find((entry) => courseSlugOf(entry) === slug && entry.data.kind === "course");
}

/** Resolve a mutable content-directory/route slug to its immutable authored identity. */
export function getCourseDefinitionKey(
  entries: CourseEntry[],
  slug: CourseSlug,
): CourseDefinitionKey | null {
  const overview = getCourseOverview(entries, slug);
  return overview ? courseDefinitionKeyOf(overview) : null;
}
