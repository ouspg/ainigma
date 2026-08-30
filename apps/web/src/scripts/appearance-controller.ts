import {
  APPEARANCE_THEME_STORAGE_KEY,
  applyAppearance,
  readStoredAppearance,
} from "../lib/appearance";
import { COLOR_MODE_STORAGE_KEY } from "../lib/color-mode";

// Keep open pages in sync when another tab changes the appearance. The storage
// event fires only in the other tabs, never the one that wrote.
window.addEventListener("storage", (event) => {
  if (event.key !== APPEARANCE_THEME_STORAGE_KEY && event.key !== COLOR_MODE_STORAGE_KEY) return;
  const { appearanceTheme, colorMode } = readStoredAppearance();
  applyAppearance(appearanceTheme, colorMode);
});
