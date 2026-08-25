import { describe, expect, it } from "vite-plus/test";
import { getFlagChallenge, getMultipartChallenge } from "./repository";

describe("challenge repository", () => {
  it("never exposes a flag answer to the rendering layer", () => {
    const challenge = getFlagChallenge("investigation-flag");

    expect(challenge.type).toBe("flag");
    expect(challenge).not.toHaveProperty("answer");
    expect(challenge).not.toHaveProperty("successMessage");
  });

  it("describes answer requirements without exposing multipart answers", () => {
    const challenge = getMultipartChallenge("packet-triage");

    expect(challenge.steps.some((step) => step.requiresAnswer)).toBe(true);
    expect(JSON.stringify(challenge.steps)).not.toContain('"answer"');
  });

  it("rejects unknown challenge identifiers", () => {
    expect(() => getFlagChallenge("missing-challenge")).toThrow("Unknown challenge");
  });
});
