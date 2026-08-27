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
import { isCourseSlug, type CourseSlug } from "./identifiers";
import { courseDefinitionKeyOf, courseSlugOf, type CourseEntry } from "./course-manifest";
type SnapshotRouteTarget = LearningSnapshot["agenda"][number]["target"];
type LinkedSnapshotItem =
  | LearningSnapshot["agenda"][number]
  | LearningSnapshot["announcements"][number]
  | LearningSnapshot["activity"][number];

function routeTargetPath(target: SnapshotRouteTarget, slug: CourseSlug) {
  switch (target.route) {
    case "course":
      return routes.course.path({ course: slug });
    case "coursePage":
      return routes.coursePage.path({ course: slug, page: target.page });
    case "courseWeek":
      return routes.courseWeek.path({ course: slug, week: target.week });
    case "courseTask":
      return routes.courseTask.path({
        course: slug,
        week: target.week,
        task: target.task,
      });
  }
}

function courseForLinkedItem(
  item: LinkedSnapshotItem,
  courseByDefinitionKey: Map<CourseInfo["definitionKey"], CourseInfo>,
): CourseInfo | undefined {
  if (item.courseDefinitionKey !== item.target.course) {
    throw new Error(
      `Course definition mismatch for learning item ${item.id}: ` +
        `${item.courseDefinitionKey} !== ${item.target.course}`,
    );
  }
  return courseByDefinitionKey.get(item.courseDefinitionKey);
}

function buildCourse(
  entries: CourseEntry[],
  slug: CourseSlug,
  learning: LearningSnapshot,
): CourseInfo {
  const courseEntries = entries.filter((entry) => courseSlugOf(entry) === slug);
  const overview = courseEntries.find((entry) => entry.data.kind === "course");

  if (!overview || overview.data.kind !== "course") {
    throw new Error(`Incomplete course manifest for ${slug}`);
  }
  const definitionKey = courseDefinitionKeyOf(overview);
  const snapshot = learning.courses[definitionKey];
  if (!snapshot) {
    throw new Error(`Missing learner snapshot for course definition ${definitionKey}`);
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
    definitionKey,
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
    nextActivity: {
      eyebrow: snapshot.nextActivity.eyebrow,
      title: snapshot.nextActivity.title,
      description: snapshot.nextActivity.description,
      href: routeTargetPath(snapshot.nextActivity.target, slug),
      estimatedMinutes: snapshot.nextActivity.estimatedMinutes,
      completedSteps: snapshot.nextActivity.completedSteps,
      totalSteps: snapshot.nextActivity.totalSteps,
      savedLabel: snapshot.nextActivity.savedLabel,
    },
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
      slug: courseSlugOf(entry),
      definitionKey: courseDefinitionKeyOf(entry),
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
  learning?: LearningSnapshot,
): Promise<LearningWorkspace> {
  const snapshot = learning ?? (await getLearningSnapshot());
  if (!profile) {
    throw new Error("Authenticated student profile is required for the learning workspace.");
  }
  const courses = buildCourses(entries, snapshot);

  return buildWorkspace(profile, snapshot, courses);
}

function buildCourses(entries: CourseEntry[], learning: LearningSnapshot): CourseInfo[] {
  return entries
    .flatMap((entry) =>
      entry.data.kind === "course" &&
      !entry.data.draft &&
      learning.courses[courseDefinitionKeyOf(entry)]
        ? [buildCourse(entries, courseSlugOf(entry), learning)]
        : [],
    )
    .sort((a, b) => a.title.localeCompare(b.title));
}

function buildWorkspace(
  profile: StudentProfile,
  learning: LearningSnapshot,
  courses: CourseInfo[],
): LearningWorkspace {
  const courseByDefinitionKey = new Map(
    courses.map((course) => [course.definitionKey, course] as const),
  );

  return {
    profile,
    term: learning.term,
    courses,
    agenda: learning.agenda.flatMap((item) => {
      const course = courseForLinkedItem(item, courseByDefinitionKey);
      if (!course) return [];
      const { courseDefinitionKey: _definitionKey, target, ...agenda } = item;
      return [{ ...agenda, courseSlug: course.slug, href: routeTargetPath(target, course.slug) }];
    }),
    announcements: learning.announcements.flatMap((item): Announcement[] => {
      const course = courseForLinkedItem(item, courseByDefinitionKey);
      if (!course) return [];
      const { courseDefinitionKey: _definitionKey, target, ...announcement } = item;
      return [
        {
          ...announcement,
          courseSlug: course.slug,
          href: routeTargetPath(target, course.slug),
        },
      ];
    }),
    activity: learning.activity.flatMap((item): LearnerActivity[] => {
      const course = courseForLinkedItem(item, courseByDefinitionKey);
      if (!course) return [];
      const { courseDefinitionKey: _definitionKey, target, ...activity } = item;
      return [{ ...activity, courseSlug: course.slug, href: routeTargetPath(target, course.slug) }];
    }),
  };
}

export async function getCourse(entries: CourseEntry[], slug: CourseSlug): Promise<CourseInfo> {
  const learning = await getLearningSnapshot();
  return buildCourse(entries, slug, learning);
}

export async function getLearningPageData(
  entries: CourseEntry[],
  profile: StudentProfile,
  slug: CourseSlug,
): Promise<{ course: CourseInfo; workspace: LearningWorkspace }> {
  const learning = await getLearningSnapshot();
  const courses = buildCourses(entries, learning);
  const course = courses.find((candidate) => candidate.slug === slug);
  if (!course) {
    throw new Error(`Incomplete course manifest for ${slug}`);
  }
  return { course, workspace: buildWorkspace(profile, learning, courses) };
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
  if (!isCourseSlug(courseSlug)) return undefined;
  const isPublished = entries.some(
    (entry) =>
      courseSlugOf(entry) === courseSlug && entry.data.kind === "course" && !entry.data.draft,
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
