import { defineTheme } from "@astryxdesign/core/theme";
import { academicTheme } from "./academic.ts";

/**
 * A restrained terminal-inspired alternative to the default academic theme.
 * Body copy stays highly readable while headings, geometry, and color carry
 * the technical character.
 */
const terminalOverrides = {
  typography: {
    scale: { base: 15, ratio: 1.2 },
    body: {
      family: "iA Writer Quattro S",
      fallbacks: '"iA Writer Quattro", ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace',
    },
    heading: {
      family: "iA Writer Quattro S",
      fallbacks: '"iA Writer Quattro", ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace',
    },
    code: {
      family: "iA Writer Quattro S",
      fallbacks: '"iA Writer Quattro", ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace',
    },
  },
  tokens: {
    "--color-accent": ["#087a46", "#36e77c"],
    "--color-accent-muted": ["#087a461a", "#36e77c24"],
    "--color-text-accent": ["#066238", "#65f29c"],
    "--color-icon-accent": ["#066238", "#65f29c"],
    "--color-on-accent": ["#f5fff8", "#031108"],
    "--color-background-body": ["#eaf1ec", "#050a08"],
    "--color-background-surface": ["#f5f9f6", "#08120d"],
    "--color-background-card": ["#f3f8f4", "#0b1811"],
    "--color-background-popover": ["#f8fcf9", "#0e1d15"],
    "--color-background-muted": ["#dfe9e2", "#11241a"],
    "--color-text-primary": ["#13251a", "#c4e4d0"],
    "--color-text-secondary": ["#4c6555", "#90b29d"],
    "--color-text-disabled": ["#8fa095", "#50705c"],
    "--color-icon-primary": ["#13251a", "#c4e4d0"],
    "--color-icon-secondary": ["#4c6555", "#90b29d"],
    "--color-icon-disabled": ["#8fa095", "#50705c"],
    "--color-border": ["#b9cabf", "#204a34"],
    "--color-border-emphasized": ["#688174", "#3f8f61"],
    "--color-shadow": ["#11351f1f", "#00000066"],
    "--radius-inner": "0.125rem",
    "--radius-element": "0.25rem",
    "--radius-container": "0.375rem",
    "--radius-page": "0.5rem",
    "--shadow-low": "0 1px 0 #087a4626",
    "--shadow-med": "0 2px 0 #087a462e, 0 10px 28px #0311081f",
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
  ...terminalOverrides,
});
