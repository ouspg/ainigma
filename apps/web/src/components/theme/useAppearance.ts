import { useCallback, useEffect, useState } from "react";
import {
  APPEARANCE_CHANGE_EVENT,
  DEFAULT_APPEARANCE_THEME,
  DEFAULT_COLOR_MODE,
  applyAppearance,
  resolveAppearanceTheme,
  resolveColorMode,
  type AppearanceTheme,
  type ColorMode,
} from "../../lib/appearance";

export interface AppearanceState {
  appearanceTheme: AppearanceTheme;
  colorMode: ColorMode;
  setAppearanceTheme: (theme: AppearanceTheme) => void;
  setColorMode: (mode: ColorMode) => void;
}

function readDocumentAppearance(): Pick<AppearanceState, "appearanceTheme" | "colorMode"> {
  return {
    appearanceTheme: resolveAppearanceTheme(document.documentElement.dataset.appearanceTheme),
    colorMode: resolveColorMode(document.documentElement.dataset.colorMode),
  };
}

/**
 * React-side view of the appearance owned by <html> + localStorage.
 *
 * The first render must match the server markup, so state starts from the
 * defaults — BaseLayout applies the stored appearance to <html> before paint —
 * and synchronizes after hydration. All writes go through applyAppearance, the
 * same single write path the browser controller uses.
 */
export function useAppearance(): AppearanceState {
  const [appearanceTheme, setAppearanceThemeState] =
    useState<AppearanceTheme>(DEFAULT_APPEARANCE_THEME);
  const [colorMode, setColorModeState] = useState<ColorMode>(DEFAULT_COLOR_MODE);

  useEffect(() => {
    const synchronize = () => {
      const { appearanceTheme: nextTheme, colorMode: nextMode } = readDocumentAppearance();
      setAppearanceThemeState(nextTheme);
      setColorModeState(nextMode);
    };

    synchronize();
    window.addEventListener(APPEARANCE_CHANGE_EVENT, synchronize);
    window.addEventListener("storage", synchronize);
    return () => {
      window.removeEventListener(APPEARANCE_CHANGE_EVENT, synchronize);
      window.removeEventListener("storage", synchronize);
    };
  }, []);

  const setAppearanceTheme = useCallback((theme: AppearanceTheme) => {
    applyAppearance(theme, resolveColorMode(document.documentElement.dataset.colorMode));
    setAppearanceThemeState(theme);
  }, []);

  const setColorMode = useCallback((mode: ColorMode) => {
    applyAppearance(resolveAppearanceTheme(document.documentElement.dataset.appearanceTheme), mode);
    setColorModeState(mode);
  }, []);

  return { appearanceTheme, colorMode, setAppearanceTheme, setColorMode };
}
