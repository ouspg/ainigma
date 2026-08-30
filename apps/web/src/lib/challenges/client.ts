import type { CourseOfferingKey } from "../learning/identifiers";
import { apiRoutes } from "../routes";
import type { ChallengeSubmission } from "./submission";

export interface ChallengeResult {
  isCorrect: boolean;
  message: string;
}

export async function submitChallenge(
  offeringKey: CourseOfferingKey,
  submission: ChallengeSubmission,
): Promise<ChallengeResult | null> {
  try {
    const response = await fetch(apiRoutes.courseChallenge.path({ offeringKey }), {
      body: JSON.stringify(submission),
      headers: { "Content-Type": "application/json" },
      method: "POST",
    });
    const body = (await response.json()) as { isCorrect?: unknown; message?: unknown };
    if (!response.ok || typeof body.isCorrect !== "boolean") return null;

    return {
      isCorrect: body.isCorrect,
      message: typeof body.message === "string" ? body.message : "",
    };
  } catch {
    return null;
  }
}
