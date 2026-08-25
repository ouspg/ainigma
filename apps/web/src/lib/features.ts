export const featureDefinitions = {
  finnish: {
    environmentVariable: "PUBLIC_FEATURE_FINNISH",
    defaultEnabled: false,
    description: "Expose Finnish routes and the English/Finnish language control.",
  },
} as const;

export type FeatureName = keyof typeof featureDefinitions;
export type FeatureFlags = Readonly<Record<FeatureName, boolean>>;

type FeatureEnvironment = Partial<Record<string, string | boolean | undefined>>;

function readBoolean(value: string | boolean | undefined, fallback: boolean): boolean {
  if (typeof value === "boolean") return value;
  if (value === undefined || value === "") return fallback;

  const normalized = value.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;

  throw new Error(`Expected a boolean feature flag value, received ${JSON.stringify(value)}`);
}

export function resolveFeatureFlags(environment: FeatureEnvironment): FeatureFlags {
  const resolved = {} as Record<FeatureName, boolean>;
  for (const feature of Object.keys(featureDefinitions) as FeatureName[]) {
    const definition = featureDefinitions[feature];
    resolved[feature] = readBoolean(
      environment[definition.environmentVariable],
      definition.defaultEnabled,
    );
  }
  return Object.freeze(resolved);
}

export const features = resolveFeatureFlags(import.meta.env ?? {});

export function isFeatureEnabled(feature: FeatureName): boolean {
  return features[feature];
}
