import { z } from "astro/zod";
import rawChallenges from "../../data/challenges.json";
import {
  isCourseDefinitionKey,
  parseCourseDefinitionKey,
  type CourseDefinitionKey,
} from "../learning/identifiers";
import type { ChallengeSubmission } from "./submission";
import type { FlagChallengeData, MultipartChallengeData, MultipartStepData } from "./types";

const courseDefinitionKeySchema = z
  .string()
  .refine(isCourseDefinitionKey)
  .transform(parseCourseDefinitionKey);

const flagSchema = z.object({
  courseDefinitionKey: courseDefinitionKeySchema,
  type: z.literal("flag"),
  title: z.string().min(1),
  description: z.string().min(1),
  placeholder: z.string(),
  expectedFormat: z.string(),
  answer: z.string().min(1),
  successMessage: z.string().min(1),
  errorMessage: z.string().min(1),
});

const multipartStepSchema = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  description: z.string().min(1),
  actionLabel: z.string().optional(),
  completedLabel: z.string().optional(),
  inputLabel: z.string().optional(),
  placeholder: z.string().optional(),
  answer: z.string().optional(),
  errorMessage: z.string().optional(),
  successMessage: z.string().optional(),
});

const multipartSchema = z.object({
  courseDefinitionKey: courseDefinitionKeySchema,
  type: z.literal("multipart"),
  title: z.string().min(1),
  description: z.string().min(1),
  steps: z.array(multipartStepSchema).min(1),
});

const challenges = z
  .record(z.string(), z.discriminatedUnion("type", [flagSchema, multipartSchema]))
  .parse(rawChallenges);

export type ChallengeEvaluation =
  | { isCorrect: boolean; message?: string }
  | { error: "challenge_not_found" | "challenge_step_not_found" };

function findChallenge(courseDefinitionKey: CourseDefinitionKey, activityId: string) {
  const challenge = challenges[activityId];
  return challenge?.courseDefinitionKey === courseDefinitionKey ? challenge : undefined;
}

function getChallenge(courseDefinitionKey: CourseDefinitionKey, activityId: string) {
  const challenge = findChallenge(courseDefinitionKey, activityId);
  if (!challenge) throw new Error(`Unknown challenge: ${activityId}`);
  return challenge;
}

export function getFlagChallenge(
  courseDefinitionKey: CourseDefinitionKey,
  activityId: string,
): FlagChallengeData {
  const challenge = getChallenge(courseDefinitionKey, activityId);
  if (challenge.type !== "flag") {
    throw new Error(`Challenge ${activityId} is not a flag challenge`);
  }
  return {
    type: challenge.type,
    title: challenge.title,
    description: challenge.description,
    placeholder: challenge.placeholder,
    expectedFormat: challenge.expectedFormat,
  };
}

export function getMultipartChallenge(
  courseDefinitionKey: CourseDefinitionKey,
  activityId: string,
): MultipartChallengeData {
  const challenge = getChallenge(courseDefinitionKey, activityId);
  if (challenge.type !== "multipart") {
    throw new Error(`Challenge ${activityId} is not a multipart challenge`);
  }
  return {
    type: challenge.type,
    title: challenge.title,
    description: challenge.description,
    steps: challenge.steps.map((step): MultipartStepData => ({
      id: step.id,
      title: step.title,
      description: step.description,
      requiresAnswer: step.answer != null,
      ...(step.actionLabel ? { actionLabel: step.actionLabel } : {}),
      ...(step.completedLabel ? { completedLabel: step.completedLabel } : {}),
      ...(step.inputLabel ? { inputLabel: step.inputLabel } : {}),
      ...(step.placeholder ? { placeholder: step.placeholder } : {}),
    })),
  };
}

export function evaluateChallengeSubmission(
  courseDefinitionKey: CourseDefinitionKey,
  submission: ChallengeSubmission,
): ChallengeEvaluation {
  const challenge = findChallenge(courseDefinitionKey, submission.taskId);
  if (!challenge) return { error: "challenge_not_found" };

  if (submission.type === "flag") {
    if (challenge.type !== "flag") return { error: "challenge_not_found" };
    const isCorrect = submission.value.trim().toUpperCase() === challenge.answer.toUpperCase();
    return {
      isCorrect,
      message: isCorrect ? challenge.successMessage : challenge.errorMessage,
    };
  }

  const step =
    challenge.type === "multipart"
      ? challenge.steps.find((candidate) => candidate.id === submission.stepId)
      : undefined;
  if (!step) return { error: "challenge_step_not_found" };

  const isCorrect = step.answer === undefined || submission.value.trim() === step.answer;
  return {
    isCorrect,
    ...(isCorrect
      ? { message: step.successMessage ?? "Checkpoint complete." }
      : step.errorMessage
        ? { message: step.errorMessage }
        : {}),
  };
}
