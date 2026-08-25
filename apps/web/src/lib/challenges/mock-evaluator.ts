import rawChallenges from "../../data/challenges.json";
import type { ChallengeDefinition, ChallengeEvaluator, EvaluationResult } from "./types";

const definitions = rawChallenges as Record<string, ChallengeDefinition>;

async function mockDelay(): Promise<void> {
  await new Promise((resolve) => window.setTimeout(resolve, 400));
}

/**
 * Prototype adapter only. Production swaps this implementation for the
 * run-scoped submit_task_answer RPC; UI components never depend on its storage.
 */
export const mockChallengeEvaluator: ChallengeEvaluator = {
  async evaluateFlag(activityId, value): Promise<EvaluationResult> {
    await mockDelay();
    const challenge = definitions[activityId];
    if (!challenge || challenge.type !== "flag") {
      return { isCorrect: false, message: "This activity is not available." };
    }
    const isCorrect = value.trim().toUpperCase() === challenge.answer.toUpperCase();
    return {
      isCorrect,
      message: isCorrect ? challenge.successMessage : challenge.errorMessage,
    };
  },

  async evaluateStep(activityId, stepId, value): Promise<EvaluationResult> {
    await mockDelay();
    const challenge = definitions[activityId];
    const step =
      challenge?.type === "multipart"
        ? challenge.steps.find((candidate) => candidate.id === stepId)
        : undefined;
    if (!step?.answer) {
      return { isCorrect: false, message: "This checkpoint is not available." };
    }
    const isCorrect = value.trim().toLowerCase() === step.answer.toLowerCase();
    return {
      isCorrect,
      message: isCorrect
        ? (step.successMessage ?? "Checkpoint complete.")
        : (step.errorMessage ?? "Check the evidence and try again."),
    };
  },
};
