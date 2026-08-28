import { z } from "astro/zod";
import rawLearning from "../../data/learning.json";
import {
  isCourseDefinitionKey,
  isCourseDefinitionReleaseId,
  isCourseOfferingKey,
  type CourseDefinitionKey,
  type CourseDefinitionReleaseId,
  type CourseOfferingKey,
} from "./identifiers";

const statusSchema = z.enum(["not-started", "in-progress", "completed"]);
const courseDefinitionKeySchema = z
  .string()
  .refine(isCourseDefinitionKey, "Invalid course definition key")
  .transform((value): CourseDefinitionKey => value);
const courseOfferingKeySchema = z
  .string()
  .refine(isCourseOfferingKey, "Invalid course offering key")
  .transform((value): CourseOfferingKey => value);
const courseDefinitionReleaseIdSchema = z
  .string()
  .refine(isCourseDefinitionReleaseId, "Invalid course definition release ID")
  .transform((value): CourseDefinitionReleaseId => value);
const courseRouteTargetSchema = z.discriminatedUnion("route", [
  z.object({ route: z.literal("course"), offeringKey: courseOfferingKeySchema }),
  z.object({
    route: z.literal("coursePage"),
    offeringKey: courseOfferingKeySchema,
    page: z.enum(["announcements", "materials"]),
  }),
  z.object({
    route: z.literal("courseWeek"),
    offeringKey: courseOfferingKeySchema,
    week: z.string().min(1),
  }),
  z.object({
    route: z.literal("courseTask"),
    offeringKey: courseOfferingKeySchema,
    week: z.string().min(1),
    task: z.string().min(1),
  }),
]);

const nextActivitySchema = z.object({
  eyebrow: z.string().min(1),
  title: z.string().min(1),
  description: z.string().min(1),
  target: courseRouteTargetSchema,
  estimatedMinutes: z.number().int().nonnegative(),
  completedSteps: z.number().int().nonnegative(),
  totalSteps: z.number().int().positive(),
  savedLabel: z.string().min(1),
});

const linkedCourseItemSchema = {
  offeringKey: courseOfferingKeySchema,
  target: courseRouteTargetSchema,
};

const learningSchema = z.object({
  term: z.object({
    label: z.string().min(1),
    dateLabel: z.string().min(1),
    currentWeek: z.number().int().positive(),
    weekCount: z.number().int().positive(),
    completedActivities: z.number().int().nonnegative(),
    totalActivities: z.number().int().positive(),
  }),
  courseOfferings: z.record(
    courseOfferingKeySchema,
    z.object({
      courseDefinitionKey: courseDefinitionKeySchema,
      courseDefinitionReleaseId: courseDefinitionReleaseIdSchema,
      startDate: z.string().date(),
      endDate: z.string().date(),
      progress: z.number().min(0).max(100),
      status: statusSchema,
      earnedPoints: z.number().nonnegative(),
      availablePoints: z.number().nonnegative(),
      weekStatuses: z.record(z.string(), statusSchema),
      nextActivity: nextActivitySchema,
    }),
  ),
  agenda: z.array(
    z.object({
      id: z.string().min(1),
      ...linkedCourseItemSchema,
      type: z.enum(["lab", "reading", "setup"]),
      title: z.string().min(1),
      supporting: z.string().min(1),
      dueLabel: z.string().min(1),
      status: z.enum(["todo", "in-progress", "completed"]),
    }),
  ),
  activity: z.array(
    z.object({
      id: z.string().min(1),
      ...linkedCourseItemSchema,
      kind: z.enum(["attempt", "grading", "artifact", "instance"]),
      title: z.string().min(1),
      description: z.string().min(1),
      timeLabel: z.string().min(1),
      occurredAt: z.string().datetime({ offset: true }),
      isUnread: z.boolean(),
      isRecent: z.boolean(),
    }),
  ),
  announcements: z.array(
    z.object({
      id: z.string().min(1),
      ...linkedCourseItemSchema,
      title: z.string().min(1),
      timeLabel: z.string().min(1),
    }),
  ),
});

export type LearningSnapshot = z.infer<typeof learningSchema>;
type CourseOfferingSnapshot = LearningSnapshot["courseOfferings"][CourseOfferingKey];

export interface LearningRepository {
  getSnapshot(): Promise<LearningSnapshot>;
  getCourseOfferingSnapshot(
    offeringKey: CourseOfferingKey,
  ): Promise<CourseOfferingSnapshot | undefined>;
}

const learningSnapshot = learningSchema.parse(rawLearning);

/** JSON-backed application data source. Replace this module with a Supabase
 * repository later; consumers should use these functions, not import JSON. */
export const learningRepository: LearningRepository = {
  async getSnapshot() {
    return learningSnapshot;
  },

  async getCourseOfferingSnapshot(offeringKey) {
    return learningSnapshot.courseOfferings[offeringKey];
  },
};

export const getLearningSnapshot = (): Promise<LearningSnapshot> =>
  learningRepository.getSnapshot();

export const getCourseOfferingSnapshot = (
  offeringKey: CourseOfferingKey,
): Promise<CourseOfferingSnapshot | undefined> =>
  learningRepository.getCourseOfferingSnapshot(offeringKey);
