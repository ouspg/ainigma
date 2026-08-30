import { describe, expect, it } from "vite-plus/test";
import { parseCourseDefinitionKey } from "../learning/identifiers";
import { evaluateChallengeSubmission, getFlagChallenge, getMultipartChallenge } from "./repository";

const courseDefinitionKey = parseCourseDefinitionKey("test-course-a");

describe("challenge repository", () => {
  it("never exposes a flag answer to the rendering layer", () => {
    const challenge = getFlagChallenge(courseDefinitionKey, "investigation-flag");

    expect(challenge.type).toBe("flag");
    expect(challenge).not.toHaveProperty("answer");
    expect(challenge).not.toHaveProperty("successMessage");
  });

  it("describes answer requirements without exposing multipart answers", () => {
    const challenge = getMultipartChallenge(courseDefinitionKey, "packet-triage");

    expect(challenge.steps.some((step) => step.requiresAnswer)).toBe(true);
    expect(JSON.stringify(challenge.steps)).not.toContain('"answer"');
  });

  it("rejects unknown challenge identifiers", () => {
    expect(() => getFlagChallenge(courseDefinitionKey, "missing-challenge")).toThrow(
      "Unknown challenge",
    );
  });

  it("rejects a challenge owned by another course definition", () => {
    expect(() =>
      getFlagChallenge(parseCourseDefinitionKey("test-course-b"), "investigation-flag"),
    ).toThrow("Unknown challenge");
  });

  it("evaluates submissions only inside the owning course definition", () => {
    const submission = {
      type: "flag" as const,
      taskId: "investigation-flag",
      value: "AINIGMA{TTL-17}",
    };

    expect(evaluateChallengeSubmission(courseDefinitionKey, submission)).toMatchObject({
      isCorrect: true,
    });
    expect(
      evaluateChallengeSubmission(parseCourseDefinitionKey("test-course-b"), submission),
    ).toEqual({ error: "challenge_not_found" });
  });
});
