import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { Theme } from "@astryxdesign/core";
import {
  APPEARANCE_THEME_STORAGE_KEY,
  DEFAULT_APPEARANCE_THEME,
  DEFAULT_COLOR_MODE,
  resolveAppearanceTheme,
  resolveColorMode,
  type AppearanceTheme,
  type ColorMode,
} from "../../lib/appearance";
import { COLOR_MODE_STORAGE_KEY } from "../../lib/color-mode";
import { academicThemeBuilt } from "../../theme/academic";
import { terminalThemeBuilt } from "../../theme/terminal";

interface AppearanceContextValue {
  appearanceTheme: AppearanceTheme;
  colorMode: ColorMode;
  setAppearanceTheme: (theme: AppearanceTheme) => void;
  setColorMode: (mode: ColorMode) => void;
}

interface Props {
  children: ReactNode;
}

const AppearanceContext = createContext<AppearanceContextValue | null>(null);

const themes = {
  academic: academicThemeBuilt,
  terminal: terminalThemeBuilt,
};

function applyThemeAttribute(theme: AppearanceTheme) {
  document.documentElement.dataset.appearanceTheme = theme;
}

function applyColorModeAttribute(mode: ColorMode) {
  if (mode === "system") {
    delete document.documentElement.dataset.colorMode;
    return;
  }
  document.documentElement.dataset.colorMode = mode;
}

export function AppearanceThemeProvider({ children }: Props) {
  // The first render must be identical on the server and in the browser.
  // BaseLayout applies localStorage preferences to <html> before paint, but
  // localStorage is not available during SSR. Synchronize the provider after
  // hydration instead of reading the browser-only value in the initial state.
  const [appearanceTheme, setAppearanceThemeState] =
    useState<AppearanceTheme>(DEFAULT_APPEARANCE_THEME);
  const [colorMode, setColorModeState] = useState<ColorMode>(DEFAULT_COLOR_MODE);

  useEffect(() => {
    setAppearanceThemeState(
      resolveAppearanceTheme(document.documentElement.dataset.appearanceTheme),
    );
    setColorModeState(resolveColorMode(document.documentElement.dataset.colorMode));
  }, []);

  useEffect(() => {
    const synchronizeTabs = (event: StorageEvent) => {
      if (event.key === APPEARANCE_THEME_STORAGE_KEY) {
        const nextTheme = resolveAppearanceTheme(event.newValue);
        applyThemeAttribute(nextTheme);
        setAppearanceThemeState(nextTheme);
      }
      if (event.key === COLOR_MODE_STORAGE_KEY) {
        const nextMode = resolveColorMode(event.newValue);
        applyColorModeAttribute(nextMode);
        setColorModeState(nextMode);
      }
    };

    window.addEventListener("storage", synchronizeTabs);
    return () => window.removeEventListener("storage", synchronizeTabs);
  }, []);

  const setAppearanceTheme = useCallback((theme: AppearanceTheme) => {
    applyThemeAttribute(theme);
    try {
      localStorage.setItem(APPEARANCE_THEME_STORAGE_KEY, theme);
    } catch {
      // The in-page preference still works when browser storage is blocked.
    }
    setAppearanceThemeState(theme);
  }, []);

  const setColorMode = useCallback((mode: ColorMode) => {
    applyColorModeAttribute(mode);
    try {
      if (mode === "system") {
        localStorage.removeItem(COLOR_MODE_STORAGE_KEY);
      } else {
        localStorage.setItem(COLOR_MODE_STORAGE_KEY, mode);
      }
    } catch {
      // The in-page preference still works when browser storage is blocked.
    }
    setColorModeState(mode);
  }, []);

  const context = useMemo(
    () => ({ appearanceTheme, colorMode, setAppearanceTheme, setColorMode }),
    [appearanceTheme, colorMode, setAppearanceTheme, setColorMode],
  );

  return (
    <AppearanceContext value={context}>
      <Theme theme={themes[appearanceTheme]} mode={colorMode}>
        {children}
      </Theme>
    </AppearanceContext>
  );
}

export function useAppearance(): AppearanceContextValue {
  const context = useContext(AppearanceContext);
  if (!context) {
    throw new Error("useAppearance must be used within AppearanceThemeProvider");
  }
  return context;
}
