import { z } from "astro/zod";
import rawLearning from "../../data/learning.json";

const statusSchema = z.enum(["not-started", "in-progress", "completed"]);

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
    z.string(),
    z.object({
      courseKey: z.string().min(1),
      progress: z.number().min(0).max(100),
      status: statusSchema,
      earnedPoints: z.number().nonnegative(),
      availablePoints: z.number().nonnegative(),
      weekStatuses: z.record(z.string(), statusSchema),
      nextActivity: z.object({
        eyebrow: z.string().min(1),
        title: z.string().min(1),
        description: z.string().min(1),
        href: z.string().startsWith("/"),
        estimatedMinutes: z.number().int().nonnegative(),
        completedSteps: z.number().int().nonnegative(),
        totalSteps: z.number().int().positive(),
        savedLabel: z.string().min(1),
      }),
    }),
  ),
  agenda: z.array(
    z.object({
      id: z.string().min(1),
      courseSlug: z.string().min(1),
      type: z.enum(["lab", "reading", "setup"]),
      title: z.string().min(1),
      supporting: z.string().min(1),
      dueLabel: z.string().min(1),
      href: z.string().startsWith("/"),
      status: z.enum(["todo", "in-progress", "completed"]),
    }),
  ),
  activity: z.array(
    z.object({
      id: z.string().min(1),
      courseSlug: z.string().min(1),
      kind: z.enum(["attempt", "grading", "artifact", "instance"]),
      title: z.string().min(1),
      description: z.string().min(1),
      timeLabel: z.string().min(1),
      occurredAt: z.string().datetime({ offset: true }),
      href: z.string().startsWith("/"),
      isUnread: z.boolean(),
      isRecent: z.boolean(),
    }),
  ),
  announcements: z.array(
    z.object({
      id: z.string().min(1),
      courseSlug: z.string().min(1),
      title: z.string().min(1),
      timeLabel: z.string().min(1),
      href: z.string().startsWith("/"),
    }),
  ),
});

export type LearningSnapshot = z.infer<typeof learningSchema>;

export interface LearningRepository {
  getSnapshot(): Promise<LearningSnapshot>;
  getCourseSnapshot(slug: string): Promise<LearningSnapshot["courses"][string] | undefined>;
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

export const getCourseSnapshot = (
  slug: string,
): Promise<LearningSnapshot["courses"][string] | undefined> =>
  learningRepository.getCourseSnapshot(slug);
