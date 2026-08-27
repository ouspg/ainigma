import { routes } from "../routes";
import type {
  Announcement,
  CourseInfo,
  CourseDefinition,
  CourseStatus,
  LearnerActivity,
  LearningWorkspace,
  PublicCourseInfo,
  StudentProfile,
  WeekInfo,
} from "./types";
import { getLearningSnapshot, type LearningSnapshot } from "./repository";
import { parseCourseDefinitionKey, parseCourseSlug, type CourseSlug } from "./identifiers";
import type { CourseEntry } from "./course-manifest";
import { COURSE_DEFINITIONS } from "./course-manifest.generated";
type TypedCourseDefinition = Omit<CourseDefinition, "slug" | "definitionKey"> & {
  slug: CourseSlug;
  definitionKey: ReturnType<typeof parseCourseDefinitionKey>;
};
const COURSE_DEFINITIONS_TYPED: TypedCourseDefinition[] = COURSE_DEFINITIONS.map((definition) => ({
  ...definition,
  slug: parseCourseSlug(definition.slug),
  definitionKey: parseCourseDefinitionKey(definition.definitionKey),
}));
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

function buildCourse(definition: TypedCourseDefinition, learning: LearningSnapshot): CourseInfo {
  const slug = definition.slug;
  const definitionKey = definition.definitionKey;
  const snapshot = learning.courses[definitionKey];
  if (!snapshot) {
    throw new Error(`Missing learner snapshot for course definition ${definitionKey}`);
  }

  const weeks: WeekInfo[] = definition.weeks.map((week) => ({
    ...week,
    href: routes.courseWeek.path({ course: slug, week: week.slug }),
    status: snapshot.weekStatuses[week.slug] ?? ("not-started" as CourseStatus),
    tasks: week.tasks.map((task) => ({
      ...task,
      href: routes.courseTask.path({ course: slug, week: week.slug, task: task.slug }),
    })),
  }));
  const pages = definition.pages.map((page) => ({
    ...page,
    href: routes.coursePage.path({ course: slug, page: page.page }),
  }));

  return {
    slug,
    definitionKey,
    courseKey: snapshot.courseKey,
    code: definition.code,
    navMark: definition.navMark,
    startDate: definition.startDate,
    endDate: definition.endDate,
    title: definition.title,
    summary: definition.summary,
    href: routes.course.path({ course: slug }),
    ...(definition.catalogUrl ? { catalogUrl: definition.catalogUrl } : {}),
    tone: definition.tone,
    progress: snapshot.progress,
    status: snapshot.status,
    earnedPoints: snapshot.earnedPoints,
    availablePoints: snapshot.availablePoints,
    weeks,
    pages,
    taskCount: definition.taskCount,
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
export function getPublicCourseCatalog(): PublicCourseInfo[] {
  return COURSE_DEFINITIONS_TYPED.filter((definition) => !definition.draft)
    .sort((a, b) => a.catalogOrder - b.catalogOrder || a.title.localeCompare(b.title))
    .map((definition) => ({
      slug: definition.slug,
      definitionKey: definition.definitionKey,
      code: definition.code,
      title: definition.title,
      summary: definition.summary,
      tone: definition.tone,
      ...(definition.catalogUrl ? { catalogUrl: definition.catalogUrl } : {}),
    }));
}

export async function getLearningWorkspace(
  profile?: StudentProfile,
  learning?: LearningSnapshot,
): Promise<LearningWorkspace> {
  const snapshot = learning ?? (await getLearningSnapshot());
  if (!profile) {
    throw new Error("Authenticated student profile is required for the learning workspace.");
  }
  const courses = buildCourses(snapshot);

  return buildWorkspace(profile, snapshot, courses);
}

function buildCourses(learning: LearningSnapshot): CourseInfo[] {
  return COURSE_DEFINITIONS_TYPED.filter(
    (definition) => !definition.draft && learning.courses[definition.definitionKey],
  )
    .map((definition) => buildCourse(definition, learning))
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

export async function getLearningPageData(
  profile: StudentProfile,
  slug: CourseSlug,
): Promise<{ course: CourseInfo; workspace: LearningWorkspace }> {
  const learning = await getLearningSnapshot();
  const courses = buildCourses(learning);
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
