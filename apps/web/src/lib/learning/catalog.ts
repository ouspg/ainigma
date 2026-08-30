import { courseRouteTargetPath, routes } from "../routes";
import type {
  Announcement,
  CourseDefinition,
  CourseInfo,
  LearnerActivity,
  LearningWorkspace,
  StudentProfile,
} from "./types";
import { getLearningSnapshot, type LearningSnapshot } from "./repository";
import {
  parseCourseDefinitionKey,
  parseCourseDefinitionSlug,
  parseCourseOfferingKey,
  type CourseDefinitionKey,
  type CourseDefinitionSlug,
  type CourseOfferingKey,
} from "./identifiers";
import { COURSE_DEFINITIONS } from "./course-manifest.generated";
import type {
  AvailableCourseOffering,
  CourseAccessState,
  CourseMembership,
  CourseOfferingReference,
} from "../auth/course-access";
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
type CourseOfferingSnapshot = LearningSnapshot["courseOfferings"][CourseOfferingKey];
type LinkedSnapshotItem =
  | LearningSnapshot["agenda"][number]
  | LearningSnapshot["announcements"][number]
  | LearningSnapshot["activity"][number];

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

function buildCourse(
  offering: CourseOfferingReference,
  snapshot?: CourseOfferingSnapshot,
): CourseInfo {
  const definition = COURSE_DEFINITION_BY_KEY.get(offering.courseDefinitionKey);
  if (!definition || definition.draft) {
    throw new Error(
      `Missing published course definition ${offering.courseDefinitionKey} for offering ${offering.offeringKey}`,
    );
  }
  if (snapshot && snapshot.courseDefinitionKey !== offering.courseDefinitionKey) {
    throw new Error(
      `Course definition mismatch for ${offering.offeringKey}: ` +
        `${offering.courseDefinitionKey} !== ${snapshot.courseDefinitionKey}`,
    );
  }
  if (snapshot && snapshot.courseDefinitionReleaseId !== offering.courseDefinitionReleaseId) {
    throw new Error(
      `Course definition release mismatch for ${offering.offeringKey}: ` +
        `${offering.courseDefinitionReleaseId} !== ${snapshot.courseDefinitionReleaseId}`,
    );
  }
  if (snapshot && snapshot.nextActivity.target.offeringKey !== offering.offeringKey) {
    throw new Error(`Next activity points outside course offering ${offering.offeringKey}`);
  }

  const weeks = definition.weeks.map((week) => ({
    ...week,
    href: routes.courseWeek.path({ offeringKey: offering.offeringKey, week: week.slug }),
    tasks: week.tasks.map((task) => ({
      ...task,
      href: routes.courseTask.path({
        offeringKey: offering.offeringKey,
        week: week.slug,
        task: task.slug,
      }),
    })),
  }));
  const pages = definition.pages.map((page) => ({
    ...page,
    href: routes.coursePage.path({ offeringKey: offering.offeringKey, page: page.page }),
  }));

  return {
    offeringKey: offering.offeringKey,
    courseDefinitionSlug: definition.courseDefinitionSlug,
    courseDefinitionKey: definition.courseDefinitionKey,
    courseDefinitionReleaseId: offering.courseDefinitionReleaseId,
    code: definition.code,
    navMark: definition.navMark,
    title: definition.title,
    summary: definition.summary,
    href: routes.course.path({ offeringKey: offering.offeringKey }),
    ...(definition.catalogUrl ? { catalogUrl: definition.catalogUrl } : {}),
    tone: definition.tone,
    weeks,
    pages,
    taskCount: definition.taskCount,
    ...(snapshot
      ? {
          learner: {
            schedule: {
              startDate: snapshot.startDate,
              endDate: snapshot.endDate,
            },
            progress: snapshot.progress,
            status: snapshot.status,
            earnedPoints: snapshot.earnedPoints,
            availablePoints: snapshot.availablePoints,
            weekStatuses: snapshot.weekStatuses,
            nextActivity: {
              eyebrow: snapshot.nextActivity.eyebrow,
              title: snapshot.nextActivity.title,
              description: snapshot.nextActivity.description,
              href: courseRouteTargetPath(snapshot.nextActivity.target),
              estimatedMinutes: snapshot.nextActivity.estimatedMinutes,
              completedSteps: snapshot.nextActivity.completedSteps,
              totalSteps: snapshot.nextActivity.totalSteps,
              savedLabel: snapshot.nextActivity.savedLabel,
            },
          },
        }
      : {}),
  };
}

export async function getCoursePageData({
  accessState,
  availableOfferings,
  memberships = [],
  offering,
  profile,
}: {
  accessState: CourseAccessState;
  availableOfferings: readonly AvailableCourseOffering[];
  memberships?: readonly CourseMembership[];
  offering: AvailableCourseOffering;
  profile?: StudentProfile | undefined;
}): Promise<CoursePageData> {
  const availableCourses = buildCourseCatalog(availableOfferings);
  const availableCourse = availableCourses.find(
    (course) => course.offeringKey === offering.offeringKey,
  );
  if (!availableCourse) {
    throw new Error(
      `Course offering is missing from the available catalog: ${offering.offeringKey}`,
    );
  }
  const shell = profile
    ? await getLearningShellData(profile, memberships, availableOfferings)
    : undefined;
  const course =
    shell?.workspace.courses.find((candidate) => candidate.offeringKey === offering.offeringKey) ??
    availableCourse;

  if (accessState === "accepted" && (!profile || !course.learner)) {
    throw new Error(`Accepted course access is missing learner state: ${offering.offeringKey}`);
  }

  return {
    accessState,
    course,
    navigationCourses: shell?.navigationCourses ?? availableCourses,
    ...(shell ? { workspace: shell.workspace } : {}),
  };
}

/**
 * Available course information comes only from authored course overview files.
 * Learner enrollment and progress snapshots must never be needed to render
 * the signed-out front page.
 */
export function buildCourseCatalog(offerings: readonly AvailableCourseOffering[]): CourseInfo[] {
  return offerings
    .map((offering) => buildCourse(offering))
    .sort((a, b) => a.title.localeCompare(b.title) || a.offeringKey.localeCompare(b.offeringKey));
}

export interface LearningShellContext {
  navigationCourses: CourseInfo[];
  workspace?: LearningWorkspace;
}

export interface LearningShellData extends LearningShellContext {
  availableCourses: CourseInfo[];
  workspace: LearningWorkspace;
}

export interface CoursePageData extends LearningShellContext {
  accessState: CourseAccessState;
  course: CourseInfo;
}

export async function getLearningShellData(
  profile: StudentProfile,
  memberships: readonly CourseMembership[],
  availableOfferings: readonly AvailableCourseOffering[],
): Promise<LearningShellData> {
  const availableCourses = buildCourseCatalog(availableOfferings);
  const workspace = await getLearningWorkspace(profile, undefined, memberships);
  return {
    availableCourses,
    navigationCourses: workspace.courses.length > 0 ? workspace.courses : availableCourses,
    workspace,
  };
}

export async function getLearningWorkspace(
  profile: StudentProfile,
  learning?: LearningSnapshot,
  memberships?: readonly CourseMembership[],
): Promise<LearningWorkspace> {
  const snapshot = learning ?? (await getLearningSnapshot());
  const courses = buildCourses(snapshot, memberships);

  return buildWorkspace(profile, snapshot, courses);
}

function buildCourses(
  learning: LearningSnapshot,
  memberships?: readonly CourseMembership[],
): CourseInfo[] {
  const membershipByOfferingKey = memberships
    ? new Map(memberships.map((membership) => [membership.offeringKey, membership] as const))
    : null;

  return Object.entries(learning.courseOfferings)
    .filter(
      ([offeringKey]) =>
        !membershipByOfferingKey ||
        membershipByOfferingKey.has(parseCourseOfferingKey(offeringKey)),
    )
    .map(([offeringKey, snapshot]) => {
      const parsedOfferingKey = parseCourseOfferingKey(offeringKey);
      const offering = membershipByOfferingKey?.get(parsedOfferingKey) ?? {
        offeringKey: parsedOfferingKey,
        courseDefinitionKey: snapshot.courseDefinitionKey,
        courseDefinitionReleaseId: snapshot.courseDefinitionReleaseId,
      };
      return buildCourse(offering, snapshot);
    })
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
      return [{ ...agenda, href: courseRouteTargetPath(target) }];
    }),
    announcements: learning.announcements.flatMap((item): Announcement[] => {
      const course = courseForLinkedItem(item, courseByOfferingKey);
      if (!course) return [];
      const { target, ...announcement } = item;
      return [
        {
          ...announcement,
          href: courseRouteTargetPath(target),
        },
      ];
    }),
    activity: learning.activity.flatMap((item): LearnerActivity[] => {
      const course = courseForLinkedItem(item, courseByOfferingKey);
      if (!course) return [];
      const { target, ...activity } = item;
      return [{ ...activity, href: courseRouteTargetPath(target) }];
    }),
  };
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
