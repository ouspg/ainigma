import { defineTheme } from "@astryxdesign/core/theme";
import { neutralTheme } from "@astryxdesign/theme-neutral";
import {
  academicColors,
  academicRadii,
  academicShadows,
  academicTypography,
} from "@ainigma/design-tokens/academic";

/**
 * A restrained, high-contrast academic theme. The generated CSS is committed so
 * Astro can paint the first frame without waiting for React hydration.
 */
export const academicTheme = defineTheme({
  name: "ainigma-academic",
  extends: neutralTheme,
  typography: {
    scale: { ...academicTypography.scale },
    body: { ...academicTypography.body },
    heading: { ...academicTypography.heading },
    code: { ...academicTypography.code },
  },
  tokens: {
    "--color-accent": academicColors.accent,
    "--color-accent-muted": academicColors.accentMuted,
    "--color-text-accent": academicColors.textAccent,
    "--color-icon-accent": academicColors.textAccent,
    "--color-on-accent": academicColors.onAccent,
    "--color-background-body": academicColors.backgroundBody,
    "--color-background-surface": academicColors.backgroundSurface,
    "--color-background-card": academicColors.backgroundCard,
    "--color-background-popover": academicColors.backgroundPopover,
    "--color-background-muted": academicColors.backgroundMuted,
    "--color-text-primary": academicColors.textPrimary,
    "--color-text-secondary": academicColors.textSecondary,
    "--color-text-disabled": academicColors.textDisabled,
    "--color-icon-primary": academicColors.textPrimary,
    "--color-icon-secondary": academicColors.textSecondary,
    "--color-border": academicColors.border,
    "--color-border-emphasized": academicColors.borderEmphasized,
    "--color-shadow": academicColors.shadow,
    "--radius-inner": academicRadii.inner,
    "--radius-element": academicRadii.element,
    "--radius-container": academicRadii.container,
    "--radius-page": academicRadii.page,
    "--shadow-low": academicShadows.low,
    "--shadow-med": academicShadows.medium,
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
