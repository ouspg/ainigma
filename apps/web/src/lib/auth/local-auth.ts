export const localAuthPersonas = [
  {
    key: "emptyLearner",
    label: "Empty learner",
    description: "Signed in with no course membership or access request.",
  },
  {
    key: "pendingLearner",
    label: "Pending learner",
    description: "Has requested access to the seeded course.",
  },
  {
    key: "memberLearner",
    label: "Member learner",
    description: "Has active access to the seeded course.",
  },
  {
    key: "owner",
    label: "Course owner",
    description: "Owns the seeded course and can review requests.",
  },
] as const;

export type LocalAuthPersona = (typeof localAuthPersonas)[number]["key"];
export type LocalAuthPersonaOption = (typeof localAuthPersonas)[number];

export function isLocalAuthEnabled(): boolean {
  return import.meta.env.DEV && import.meta.env.PUBLIC_AUTH_MODE === "local";
}

export function isLocalAuthPersona(value: string | null): value is LocalAuthPersona {
  return localAuthPersonas.some((persona) => persona.key === value);
}
