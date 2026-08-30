import { z } from "astro/zod";

export const challengeSubmissionSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("flag"), taskId: z.string().min(1), value: z.string() }),
  z.object({
    type: z.literal("step"),
    taskId: z.string().min(1),
    stepId: z.string().min(1),
    value: z.string(),
  }),
]);

export type ChallengeSubmission = z.infer<typeof challengeSubmissionSchema>;
