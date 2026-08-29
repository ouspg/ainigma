import { defineTheme } from "@astryxdesign/core/theme";
import {
  terminalColors,
  terminalRadii,
  terminalShadows,
  terminalTypography,
} from "@ainigma/design-tokens/terminal";
import { academicTheme } from "./academic.ts";

/**
 * A restrained terminal-inspired alternative to the default academic theme.
 * Body copy stays highly readable while headings, geometry, and color carry
 * the technical character.
 */
const terminalThemeOverrides = {
  typography: {
    scale: { ...terminalTypography.scale },
    body: { ...terminalTypography.body },
    heading: { ...terminalTypography.heading },
    code: { ...terminalTypography.code },
  },
  tokens: {
    "--color-accent": terminalColors.accent,
    "--color-accent-muted": terminalColors.accentMuted,
    "--color-text-accent": terminalColors.textAccent,
    "--color-icon-accent": terminalColors.textAccent,
    "--color-on-accent": terminalColors.onAccent,
    "--color-background-body": terminalColors.backgroundBody,
    "--color-background-surface": terminalColors.backgroundSurface,
    "--color-background-card": terminalColors.backgroundCard,
    "--color-background-popover": terminalColors.backgroundPopover,
    "--color-background-muted": terminalColors.backgroundMuted,
    "--color-text-primary": terminalColors.textPrimary,
    "--color-text-secondary": terminalColors.textSecondary,
    "--color-text-disabled": terminalColors.textDisabled,
    "--color-icon-primary": terminalColors.textPrimary,
    "--color-icon-secondary": terminalColors.textSecondary,
    "--color-icon-disabled": terminalColors.textDisabled,
    "--color-border": terminalColors.border,
    "--color-border-emphasized": terminalColors.borderEmphasized,
    "--color-shadow": terminalColors.shadow,
    "--radius-inner": terminalRadii.inner,
    "--radius-element": terminalRadii.element,
    "--radius-container": terminalRadii.container,
    "--radius-page": terminalRadii.page,
    "--shadow-low": terminalShadows.low,
    "--shadow-med": terminalShadows.medium,
  },
  components: {
    button: {
      base: {
        borderRadius: "var(--radius-element)",
      },
      "variant:secondary": {
        backgroundColor: "var(--color-accent-muted)",
        borderColor: "var(--color-accent)",
        color: "var(--color-text-accent)",
        ":hover": {
          backgroundColor: "var(--color-accent-muted)",
        },
      },
    },
    card: {
      base: {
        borderColor: "var(--color-border-emphasized)",
        boxShadow: "var(--shadow-low)",
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
} satisfies Omit<Parameters<typeof defineTheme>[0], "name" | "extends">;

export const terminalTheme = defineTheme({
  name: "ainigma-terminal",
  extends: academicTheme,
  ...terminalThemeOverrides,
});
