import { COLOR_MODE_STORAGE_KEY } from "./color-mode";

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

/**
 * Dispatched on window whenever the appearance is applied, so any listener
 * (React islands, the browser controller) stays in sync without polling.
 */
export const APPEARANCE_CHANGE_EVENT = "ainigma:appearance-change";

/**
 * Applies an appearance to <html>, persists it, and notifies listeners.
 * This is the single write path shared by the browser controller and React.
 */
export function applyAppearance(theme: AppearanceTheme, mode: ColorMode): void {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  root.dataset.appearanceTheme = theme;
  root.dataset.astryxTheme = ASTRYX_THEME_NAMES[theme];
  if (mode === "system") {
    delete root.dataset.colorMode;
    root.removeAttribute("data-theme");
  } else {
    root.dataset.colorMode = mode;
    root.setAttribute("data-theme", mode);
  }
  try {
    localStorage.setItem(APPEARANCE_THEME_STORAGE_KEY, theme);
    if (mode === "system") {
      localStorage.removeItem(COLOR_MODE_STORAGE_KEY);
    } else {
      localStorage.setItem(COLOR_MODE_STORAGE_KEY, mode);
    }
  } catch {
    // The in-page preference still works when browser storage is blocked.
  }
  window.dispatchEvent(new CustomEvent(APPEARANCE_CHANGE_EVENT));
}

/** Resolves the stored appearance, tolerating missing or blocked storage. */
export function readStoredAppearance(): {
  appearanceTheme: AppearanceTheme;
  colorMode: ColorMode;
} {
  let appearanceTheme = DEFAULT_APPEARANCE_THEME;
  let colorMode = DEFAULT_COLOR_MODE;
  try {
    appearanceTheme = resolveAppearanceTheme(localStorage.getItem(APPEARANCE_THEME_STORAGE_KEY));
    colorMode = resolveColorMode(localStorage.getItem(COLOR_MODE_STORAGE_KEY));
  } catch {
    // A blocked storage API falls back to the defaults.
  }
  return { appearanceTheme, colorMode };
}
