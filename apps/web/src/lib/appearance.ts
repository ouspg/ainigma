export const appearanceThemes = ["academic", "terminal"] as const;
export type AppearanceTheme = (typeof appearanceThemes)[number];

export const colorModes = ["system", "light", "dark"] as const;
export type ColorMode = (typeof colorModes)[number];

export const DEFAULT_APPEARANCE_THEME: AppearanceTheme = "academic";
export const DEFAULT_COLOR_MODE: ColorMode = "system";

export const APPEARANCE_THEME_STORAGE_KEY = "ainigma.appearance-theme";

export const ASTRYX_THEME_NAMES: Record<AppearanceTheme, string> = {
  academic: "ainigma-academic",
  terminal: "ainigma-terminal",
};

export function isAppearanceTheme(value: unknown): value is AppearanceTheme {
  return typeof value === "string" && appearanceThemes.includes(value as AppearanceTheme);
}

export function resolveAppearanceTheme(value: unknown): AppearanceTheme {
  if (value === "hacker") return "terminal";
  return isAppearanceTheme(value) ? value : DEFAULT_APPEARANCE_THEME;
}

export function isColorMode(value: unknown): value is ColorMode {
  return typeof value === "string" && colorModes.includes(value as ColorMode);
}

export function resolveColorMode(value: unknown): ColorMode {
  return isColorMode(value) ? value : DEFAULT_COLOR_MODE;
}
