import {
  APPEARANCE_CHANGE_EVENT,
  APPEARANCE_THEME_STORAGE_KEY,
  appearanceThemes,
  applyAppearance,
  colorModes,
  readStoredAppearance,
  resolveAppearanceTheme,
  resolveColorMode,
  type AppearanceTheme,
  type ColorMode,
} from "../lib/appearance";
import { COLOR_MODE_STORAGE_KEY } from "../lib/color-mode";

const isTheme = (value: string | null): value is AppearanceTheme =>
  (appearanceThemes as readonly string[]).includes(value ?? "");
const isMode = (value: string | null): value is ColorMode =>
  (colorModes as readonly string[]).includes(value ?? "");

/** Reflects the active appearance onto the popup's radio-style buttons. */
function syncChoices(): void {
  const activeTheme = resolveAppearanceTheme(document.documentElement.dataset.appearanceTheme);
  document.querySelectorAll("[data-appearance-theme-choice]").forEach((choice) => {
    choice.setAttribute(
      "aria-pressed",
      String(choice.getAttribute("data-appearance-theme-choice") === activeTheme),
    );
  });

  const activeMode = resolveColorMode(document.documentElement.dataset.colorMode);
  document.querySelectorAll("[data-color-mode-choice]").forEach((choice) => {
    choice.setAttribute(
      "aria-pressed",
      String(choice.getAttribute("data-color-mode-choice") === activeMode),
    );
  });
}

// The public popup is a native <details> whose options carry data attributes.
// Route every choice through the single apply path, then close the popup.
document.addEventListener("click", (event) => {
  const target = event.target;
  if (!(target instanceof Element)) return;

  const themeChoice = target.closest("[data-appearance-theme-choice]");
  if (themeChoice) {
    const theme = themeChoice.getAttribute("data-appearance-theme-choice");
    if (isTheme(theme)) {
      applyAppearance(theme, resolveColorMode(document.documentElement.dataset.colorMode));
      themeChoice.closest("details")?.removeAttribute("open");
    }
    return;
  }

  const colorModeChoice = target.closest("[data-color-mode-choice]");
  if (colorModeChoice) {
    const mode = colorModeChoice.getAttribute("data-color-mode-choice");
    if (isMode(mode)) {
      applyAppearance(resolveAppearanceTheme(document.documentElement.dataset.appearanceTheme), mode);
      colorModeChoice.closest("details")?.removeAttribute("open");
    }
  }
});

// The toggle event does not bubble, so listen in the capture phase. Re-syncing
// when the popup opens guarantees the current choice is always pre-selected.
document.addEventListener(
  "toggle",
  (event) => {
    const details = event.target;
    if (
      details instanceof HTMLDetailsElement &&
      details.classList.contains("public-theme-menu") &&
      details.open
    ) {
      syncChoices();
    }
  },
  true,
);

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", syncChoices, { once: true });
} else {
  syncChoices();
}
document.addEventListener("astro:after-swap", syncChoices);
window.addEventListener(APPEARANCE_CHANGE_EVENT, syncChoices);

// Keep open pages in sync when another tab changes the appearance. The storage
// event fires only in the other tabs, never the one that wrote.
window.addEventListener("storage", (event) => {
  if (event.key !== APPEARANCE_THEME_STORAGE_KEY && event.key !== COLOR_MODE_STORAGE_KEY) return;
  const { appearanceTheme, colorMode } = readStoredAppearance();
  applyAppearance(appearanceTheme, colorMode);
});
