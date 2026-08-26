import { z } from "astro/zod";
import rawLearning from "../../data/learning.json";
import { courseRouteTargetPath } from "../routes";
import { isCourseDefinitionKey, type CourseDefinitionKey } from "./identifiers";

const statusSchema = z.enum(["not-started", "in-progress", "completed"]);
const courseDefinitionKeySchema = z
  .string()
  .refine(isCourseDefinitionKey, "Invalid course definition key")
  .transform((value): CourseDefinitionKey => value);
const courseRouteTargetSchema = z.discriminatedUnion("route", [
  z.object({ route: z.literal("course"), course: courseDefinitionKeySchema }),
  z.object({
    route: z.literal("coursePage"),
    course: courseDefinitionKeySchema,
    page: z.enum(["announcements", "materials"]),
  }),
  z.object({
    route: z.literal("courseWeek"),
    course: courseDefinitionKeySchema,
    week: z.string().min(1),
  }),
  z.object({
    route: z.literal("courseTask"),
    course: courseDefinitionKeySchema,
    week: z.string().min(1),
    task: z.string().min(1),
  }),
]);

function routeTargetPath(target: z.infer<typeof courseRouteTargetSchema>) {
  return courseRouteTargetPath(target);
}

const nextActivitySchema = z
  .object({
    eyebrow: z.string().min(1),
    title: z.string().min(1),
    description: z.string().min(1),
    target: courseRouteTargetSchema,
    estimatedMinutes: z.number().int().nonnegative(),
    completedSteps: z.number().int().nonnegative(),
    totalSteps: z.number().int().positive(),
    savedLabel: z.string().min(1),
  })
  .transform(({ target, ...activity }) => ({ ...activity, href: routeTargetPath(target) }));

const linkedCourseItemSchema = {
  courseSlug: courseDefinitionKeySchema,
  target: courseRouteTargetSchema,
};

const learningSchema = z.object({
  profile: z.object({ displayName: z.string().min(1), firstName: z.string().min(1) }),
  term: z.object({
    label: z.string().min(1),
    dateLabel: z.string().min(1),
    currentWeek: z.number().int().positive(),
    weekCount: z.number().int().positive(),
    completedActivities: z.number().int().nonnegative(),
    totalActivities: z.number().int().positive(),
  }),
  courses: z.record(
    courseDefinitionKeySchema,
    z.object({
      courseKey: z.string().min(1),
      progress: z.number().min(0).max(100),
      status: statusSchema,
      earnedPoints: z.number().nonnegative(),
      availablePoints: z.number().nonnegative(),
      weekStatuses: z.record(z.string(), statusSchema),
      nextActivity: nextActivitySchema,
    }),
  ),
  agenda: z.array(
    z
      .object({
        id: z.string().min(1),
        ...linkedCourseItemSchema,
        type: z.enum(["lab", "reading", "setup"]),
        title: z.string().min(1),
        supporting: z.string().min(1),
        dueLabel: z.string().min(1),
        status: z.enum(["todo", "in-progress", "completed"]),
      })
      .transform(({ target, ...item }) => ({ ...item, href: routeTargetPath(target) })),
  ),
  activity: z.array(
    z
      .object({
        id: z.string().min(1),
        ...linkedCourseItemSchema,
        kind: z.enum(["attempt", "grading", "artifact", "instance"]),
        title: z.string().min(1),
        description: z.string().min(1),
        timeLabel: z.string().min(1),
        occurredAt: z.string().datetime({ offset: true }),
        isUnread: z.boolean(),
        isRecent: z.boolean(),
      })
      .transform(({ target, ...item }) => ({ ...item, href: routeTargetPath(target) })),
  ),
  announcements: z.array(
    z
      .object({
        id: z.string().min(1),
        ...linkedCourseItemSchema,
        title: z.string().min(1),
        timeLabel: z.string().min(1),
      })
      .transform(({ target, ...item }) => ({ ...item, href: routeTargetPath(target) })),
  ),
});

export type LearningSnapshot = z.infer<typeof learningSchema>;
type CourseSnapshot = LearningSnapshot["courses"][CourseDefinitionKey];

export interface LearningRepository {
  getSnapshot(): Promise<LearningSnapshot>;
  getCourseSnapshot(slug: CourseDefinitionKey): Promise<CourseSnapshot | undefined>;
}

const learningSnapshot = learningSchema.parse(rawLearning);

/** JSON-backed application data source. Replace this module with a Supabase
 * repository later; consumers should use these functions, not import JSON. */
export const learningRepository: LearningRepository = {
  async getSnapshot() {
    return learningSnapshot;
  },

  async getCourseSnapshot(slug) {
    return learningSnapshot.courses[slug];
  },
};

export const getLearningSnapshot = (): Promise<LearningSnapshot> =>
  learningRepository.getSnapshot();

export const getCourseSnapshot = (slug: CourseDefinitionKey): Promise<CourseSnapshot | undefined> =>
  learningRepository.getCourseSnapshot(slug);
