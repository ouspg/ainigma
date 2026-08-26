import type { CollectionEntry } from "astro:content";
import { routes } from "../routes";
import type {
  Announcement,
  CourseInfo,
  CourseStatus,
  LearnerActivity,
  LearningWorkspace,
  PublicCourseInfo,
  StudentProfile,
  WeekInfo,
} from "./types";
import { getLearningSnapshot, type LearningSnapshot } from "./repository";
import {
  isCourseDefinitionKey,
  parseCourseDefinitionKey,
  type CourseDefinitionKey,
} from "./identifiers";

type CourseEntry = CollectionEntry<"courses">;

function slugOf(entry: CourseEntry): CourseDefinitionKey {
  return parseCourseDefinitionKey(entry.id.split("/")[0] ?? "");
}

function buildCourse(
  entries: CourseEntry[],
  slug: CourseDefinitionKey,
  learning: LearningSnapshot,
): CourseInfo {
  const snapshot = learning.courses[slug];
  const courseEntries = entries.filter((entry) => slugOf(entry) === slug);
  const overview = courseEntries.find((entry) => entry.data.kind === "course");

  if (!snapshot || !overview || overview.data.kind !== "course") {
    throw new Error(`Incomplete course manifest for ${slug}`);
  }

  const weeks: WeekInfo[] = courseEntries
    .filter((entry) => entry.data.kind === "week")
    .sort((a, b) => a.data.order - b.data.order)
    .map((weekEntry) => {
      if (weekEntry.data.kind !== "week") {
        throw new Error(`Expected week entry: ${weekEntry.id}`);
      }
      const weekSlug = weekEntry.id.split("/")[1] ?? "";
      const tasks = courseEntries
        .filter(
          (entry) => entry.data.kind === "task" && entry.id.startsWith(`${slug}/${weekSlug}/`),
        )
        .sort((a, b) => a.data.order - b.data.order)
        .map((taskEntry) => {
          if (taskEntry.data.kind !== "task") {
            throw new Error(`Expected task entry: ${taskEntry.id}`);
          }
          const taskSlug = taskEntry.id.slice(`${slug}/${weekSlug}/`.length);
          return {
            slug: taskSlug,
            title: taskEntry.data.navLabel ?? taskEntry.data.title,
            summary: taskEntry.data.summary,
            href: routes.courseTask.path({ course: slug, week: weekSlug, task: taskSlug }),
            estimatedMinutes: taskEntry.data.estimatedMinutes,
            points: taskEntry.data.points,
          };
        });

      return {
        slug: weekSlug,
        number: weekEntry.data.weekNumber,
        title: weekEntry.data.title,
        summary: weekEntry.data.summary,
        href: routes.courseWeek.path({ course: slug, week: weekSlug }),
        status: snapshot.weekStatuses[weekSlug] ?? ("not-started" as CourseStatus),
        tasks,
      };
    });

  const pages = courseEntries
    .filter((entry) => entry.data.kind === "course-page")
    .sort((a, b) => a.data.order - b.data.order)
    .map((entry) => {
      if (entry.data.kind !== "course-page") {
        throw new Error(`Expected course page entry: ${entry.id}`);
      }
      return {
        page: entry.data.page,
        title: entry.data.title,
        label: entry.data.navLabel ?? entry.data.title,
        href: routes.coursePage.path({ course: slug, page: entry.data.page }),
      };
    });

  return {
    slug,
    courseKey: snapshot.courseKey,
    code: overview.data.code,
    navMark: overview.data.navMark,
    startDate: overview.data.startDate,
    endDate: overview.data.endDate,
    title: overview.data.title,
    summary: overview.data.summary,
    href: routes.course.path({ course: slug }),
    ...(overview.data.catalogUrl ? { catalogUrl: overview.data.catalogUrl } : {}),
    tone: overview.data.tone,
    progress: snapshot.progress,
    status: snapshot.status,
    earnedPoints: snapshot.earnedPoints,
    availablePoints: snapshot.availablePoints,
    weeks,
    pages,
    taskCount: weeks.reduce((total, week) => total + week.tasks.length, 0),
    nextActivity: snapshot.nextActivity,
  };
}

/**
 * Public course information comes only from authored course overview files.
 * Learner enrollment and progress snapshots must never be needed to render
 * the signed-out front page.
 */
export function getPublicCourseCatalog(entries: CourseEntry[]): PublicCourseInfo[] {
  return entries
    .flatMap((entry) =>
      entry.data.kind === "course" && !entry.data.draft ? [{ entry, data: entry.data }] : [],
    )
    .sort(
      (a, b) =>
        a.data.catalogOrder - b.data.catalogOrder || a.data.title.localeCompare(b.data.title),
    )
    .map(({ entry, data }) => ({
      slug: slugOf(entry),
      code: data.code,
      title: data.title,
      summary: data.summary,
      tone: data.tone,
      ...(data.catalogUrl ? { catalogUrl: data.catalogUrl } : {}),
    }));
}

export async function getLearningWorkspace(
  entries: CourseEntry[],
  profile?: StudentProfile,
): Promise<LearningWorkspace> {
  const learning = await getLearningSnapshot();
  if (!profile) {
    throw new Error("Authenticated student profile is required for the learning workspace.");
  }
  const publishedSlugs = new Set(
    entries.flatMap((entry) =>
      entry.data.kind === "course" && !entry.data.draft ? [slugOf(entry)] : [],
    ),
  );
  const courses = Object.keys(learning.courses)
    .filter(isCourseDefinitionKey)
    .filter((slug) => publishedSlugs.has(slug))
    .map((slug) => buildCourse(entries, slug, learning));
  const knownSlugs = new Set(courses.map((course) => course.slug));

  return {
    profile,
    term: learning.term,
    courses,
    agenda: learning.agenda.filter((item) => knownSlugs.has(item.courseSlug)),
    announcements: learning.announcements.filter((item): item is Announcement =>
      knownSlugs.has(item.courseSlug),
    ),
    activity: learning.activity.filter((item): item is LearnerActivity =>
      knownSlugs.has(item.courseSlug),
    ),
  };
}

export async function getCourse(
  entries: CourseEntry[],
  slug: CourseDefinitionKey,
): Promise<CourseInfo> {
  const learning = await getLearningSnapshot();
  return buildCourse(entries, slug, learning);
}

export function getCourseEntry(entries: CourseEntry[], id: string): CourseEntry {
  const entry = entries.find((candidate) => candidate.id === id);
  if (!entry) {
    throw new Error(`Missing course content entry: ${id}`);
  }
  return entry;
}

export function getPublishedCourseEntry(
  entries: CourseEntry[],
  id: string,
): CourseEntry | undefined {
  const courseSlug = id.split("/")[0] ?? "";
  if (!isCourseDefinitionKey(courseSlug)) return undefined;
  const isPublished = entries.some(
    (entry) => slugOf(entry) === courseSlug && entry.data.kind === "course" && !entry.data.draft,
  );
  if (!isPublished) return undefined;
  return entries.find((entry) => entry.id === id);
}

export interface HeadingInfo {
  depth: number;
  slug: string;
  text: string;
}

export interface OutlineSection extends HeadingInfo {
  activityIds: string[];
}

interface ActivityOutlineEntry {
  headingIndex: number;
  activityIds: string[];
}

export function buildOutlineSections(
  headings: HeadingInfo[],
  activityOutline: ActivityOutlineEntry[] | undefined,
): OutlineSection[] {
  return headings
    .map((heading, index) => ({ heading, index }))
    .filter(({ heading }) => heading.depth === 2 || heading.depth === 3)
    .map(({ heading, index }) => ({
      ...heading,
      activityIds:
        activityOutline?.find((candidate) => candidate.headingIndex === index)?.activityIds ?? [],
    }));
}
