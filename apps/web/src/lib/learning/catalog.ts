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
import {
  parseCourseDefinitionKey,
  parseCourseDefinitionSlug,
  parseCourseOfferingKey,
  type CourseDefinitionKey,
  type CourseDefinitionReleaseId,
  type CourseDefinitionSlug,
  type CourseOfferingKey,
} from "./identifiers";
import type { CourseEntry } from "./course-manifest";
import { COURSE_DEFINITIONS } from "./course-manifest.generated";
type TypedCourseDefinition = Omit<
  CourseDefinition,
  "courseDefinitionSlug" | "courseDefinitionKey"
> & {
  courseDefinitionSlug: CourseDefinitionSlug;
  courseDefinitionKey: CourseDefinitionKey;
};
const COURSE_DEFINITIONS_TYPED: TypedCourseDefinition[] = COURSE_DEFINITIONS.map((definition) => ({
  ...definition,
  courseDefinitionSlug: parseCourseDefinitionSlug(definition.courseDefinitionSlug),
  courseDefinitionKey: parseCourseDefinitionKey(definition.courseDefinitionKey),
}));
const COURSE_DEFINITION_BY_KEY = new Map(
  COURSE_DEFINITIONS_TYPED.map(
    (definition) => [definition.courseDefinitionKey, definition] as const,
  ),
);
type SnapshotRouteTarget = LearningSnapshot["agenda"][number]["target"];
type CourseOfferingSnapshot = LearningSnapshot["courseOfferings"][CourseOfferingKey];
type LinkedSnapshotItem =
  | LearningSnapshot["agenda"][number]
  | LearningSnapshot["announcements"][number]
  | LearningSnapshot["activity"][number];

function routeTargetPath(target: SnapshotRouteTarget) {
  switch (target.route) {
    case "course":
      return routes.course.path({ offeringKey: target.offeringKey });
    case "coursePage":
      return routes.coursePage.path({ offeringKey: target.offeringKey, page: target.page });
    case "courseWeek":
      return routes.courseWeek.path({ offeringKey: target.offeringKey, week: target.week });
    case "courseTask":
      return routes.courseTask.path({
        offeringKey: target.offeringKey,
        week: target.week,
        task: target.task,
      });
  }
}

function courseForLinkedItem(
  item: LinkedSnapshotItem,
  courseByOfferingKey: Map<CourseInfo["offeringKey"], CourseInfo>,
): CourseInfo | undefined {
  if (item.offeringKey !== item.target.offeringKey) {
    throw new Error(
      `Course offering mismatch for learning item ${item.id}: ` +
        `${item.offeringKey} !== ${item.target.offeringKey}`,
    );
  }
  return courseByOfferingKey.get(item.offeringKey);
}

function buildCourseOffering(
  offeringKey: CourseOfferingKey,
  snapshot: CourseOfferingSnapshot,
): CourseInfo {
  const definition = COURSE_DEFINITION_BY_KEY.get(snapshot.courseDefinitionKey);
  if (!definition || definition.draft) {
    throw new Error(
      `Missing published course definition ${snapshot.courseDefinitionKey} for offering ${offeringKey}`,
    );
  }
  if (snapshot.nextActivity.target.offeringKey !== offeringKey) {
    throw new Error(`Next activity points outside course offering ${offeringKey}`);
  }

  const weeks: WeekInfo[] = definition.weeks.map((week) => ({
    ...week,
    href: routes.courseWeek.path({ offeringKey, week: week.slug }),
    status: snapshot.weekStatuses[week.slug] ?? ("not-started" as CourseStatus),
    tasks: week.tasks.map((task) => ({
      ...task,
      href: routes.courseTask.path({ offeringKey, week: week.slug, task: task.slug }),
    })),
  }));
  const pages = definition.pages.map((page) => ({
    ...page,
    href: routes.coursePage.path({ offeringKey, page: page.page }),
  }));

  return {
    offeringKey,
    courseDefinitionSlug: definition.courseDefinitionSlug,
    courseDefinitionKey: definition.courseDefinitionKey,
    courseDefinitionReleaseId: snapshot.courseDefinitionReleaseId,
    code: definition.code,
    navMark: definition.navMark,
    startDate: snapshot.startDate,
    endDate: snapshot.endDate,
    title: definition.title,
    summary: definition.summary,
    href: routes.course.path({ offeringKey }),
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
      href: routeTargetPath(snapshot.nextActivity.target),
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
      courseDefinitionSlug: definition.courseDefinitionSlug,
      courseDefinitionKey: definition.courseDefinitionKey,
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
  return Object.entries(learning.courseOfferings)
    .map(([offeringKey, snapshot]) =>
      buildCourseOffering(parseCourseOfferingKey(offeringKey), snapshot),
    )
    .sort((a, b) => a.title.localeCompare(b.title) || a.offeringKey.localeCompare(b.offeringKey));
}

function buildWorkspace(
  profile: StudentProfile,
  learning: LearningSnapshot,
  courses: CourseInfo[],
): LearningWorkspace {
  const courseByOfferingKey = new Map(
    courses.map((course) => [course.offeringKey, course] as const),
  );

  return {
    profile,
    term: learning.term,
    courses,
    agenda: learning.agenda.flatMap((item) => {
      const course = courseForLinkedItem(item, courseByOfferingKey);
      if (!course) return [];
      const { target, ...agenda } = item;
      return [{ ...agenda, href: routeTargetPath(target) }];
    }),
    announcements: learning.announcements.flatMap((item): Announcement[] => {
      const course = courseForLinkedItem(item, courseByOfferingKey);
      if (!course) return [];
      const { target, ...announcement } = item;
      return [
        {
          ...announcement,
          href: routeTargetPath(target),
        },
      ];
    }),
    activity: learning.activity.flatMap((item): LearnerActivity[] => {
      const course = courseForLinkedItem(item, courseByOfferingKey);
      if (!course) return [];
      const { target, ...activity } = item;
      return [{ ...activity, href: routeTargetPath(target) }];
    }),
  };
}

export async function getLearningPageData(
  profile: StudentProfile,
  offeringKey: CourseOfferingKey,
  authorizedCourseDefinitionKey: CourseDefinitionKey,
  authorizedCourseDefinitionReleaseId: CourseDefinitionReleaseId,
): Promise<{ course: CourseInfo; workspace: LearningWorkspace }> {
  const learning = await getLearningSnapshot();
  const courses = buildCourses(learning);
  const course = courses.find((candidate) => candidate.offeringKey === offeringKey);
  if (!course) {
    throw new Error(`Incomplete course offering manifest for ${offeringKey}`);
  }
  if (course.courseDefinitionKey !== authorizedCourseDefinitionKey) {
    throw new Error(
      `Authorized course definition mismatch for ${offeringKey}: ` +
        `${authorizedCourseDefinitionKey} !== ${course.courseDefinitionKey}`,
    );
  }
  if (course.courseDefinitionReleaseId !== authorizedCourseDefinitionReleaseId) {
    throw new Error(
      `Authorized course definition release mismatch for ${offeringKey}: ` +
        `${authorizedCourseDefinitionReleaseId} !== ${course.courseDefinitionReleaseId}`,
    );
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
