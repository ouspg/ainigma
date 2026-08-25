import { z } from "astro/zod";
import rawChallenges from "../../data/challenges.json";
import type { FlagChallengeData, MultipartChallengeData, MultipartStepData } from "./types";

const flagSchema = z.object({
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
  type: z.literal("multipart"),
  title: z.string().min(1),
  description: z.string().min(1),
  steps: z.array(multipartStepSchema).min(1),
});

const challenges = z
  .record(z.string(), z.discriminatedUnion("type", [flagSchema, multipartSchema]))
  .parse(rawChallenges);

function getChallenge(activityId: string) {
  const challenge = challenges[activityId];
  if (!challenge) throw new Error(`Unknown challenge: ${activityId}`);
  return challenge;
}

export function getFlagChallenge(activityId: string): FlagChallengeData {
  const challenge = getChallenge(activityId);
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

export function getMultipartChallenge(activityId: string): MultipartChallengeData {
  const challenge = getChallenge(activityId);
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
