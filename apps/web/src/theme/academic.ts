import { defineTheme } from "@astryxdesign/core/theme";
import { neutralTheme } from "@astryxdesign/theme-neutral";

/**
 * A restrained, high-contrast academic theme. The generated CSS is committed so
 * Astro can paint the first frame without waiting for React hydration.
 */
export const academicTheme = defineTheme({
  name: "ainigma-academic",
  extends: neutralTheme,
  typography: {
    scale: { base: 15, ratio: 1.22 },
    body: {
      family: "system-ui",
      fallbacks: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    },
    heading: {
      family: "ui-serif",
      fallbacks: 'Charter, Georgia, Cambria, "Times New Roman", serif',
    },
    code: {
      family: "SF Mono",
      fallbacks: "Menlo, Monaco, Consolas, monospace",
    },
  },
  tokens: {
    "--color-accent": ["#28567a", "#8fb9d4"],
    "--color-accent-muted": ["#28567a1a", "#8fb9d426"],
    "--color-text-accent": ["#214b6b", "#a8c8dc"],
    "--color-icon-accent": ["#214b6b", "#a8c8dc"],
    "--color-on-accent": ["#f5f8fa", "#15222b"],
    "--color-background-body": ["#f3f5f6", "#151a1e"],
    "--color-background-surface": ["#fafbfb", "#20262b"],
    "--color-background-card": ["#ffffff", "#252c32"],
    "--color-background-popover": ["#ffffff", "#2b333a"],
    "--color-background-muted": ["#e7ecef", "#303940"],
    "--color-text-primary": ["#1f2933", "#edf2f5"],
    "--color-text-secondary": ["#5f6b75", "#b8c3cb"],
    "--color-text-disabled": ["#9aa6af", "#75818a"],
    "--color-icon-primary": ["#1f2933", "#edf2f5"],
    "--color-icon-secondary": ["#5f6b75", "#b8c3cb"],
    "--color-border": ["#d5dde2", "#414b53"],
    "--color-border-emphasized": ["#82909b", "#73808a"],
    "--color-shadow": ["#1f29330a", "#00000038"],
    "--radius-inner": "0.25rem",
    "--radius-element": "0.375rem",
    "--radius-container": "0.5rem",
    "--radius-page": "0.75rem",
    "--shadow-low": "none",
    "--shadow-med": "0 1px 2px #1f293314",
  },
  components: {
    button: {
      base: {
        borderRadius: "var(--radius-element)",
      },
    },
    card: {
      base: {
        borderColor: "var(--color-border)",
        boxShadow: "none",
      },
    },
    navicon: {
      base: {
        backgroundColor: "var(--color-accent-muted)",
        color: "var(--color-text-accent)",
      },
    },
    progressbar: {
      "variant:accent": {
        "--color-accent": "var(--color-text-accent)",
      },
    },
    statusdot: {
      "variant:accent": {
        backgroundColor: "var(--color-text-accent)",
      },
    },
  },
});

export const academicThemeBuilt = {
  ...academicTheme,
  __built: true,
} as const;
