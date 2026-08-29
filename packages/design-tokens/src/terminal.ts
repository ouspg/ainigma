import type { ColorPair } from "./academic";

/** Shared semantic values for Ainigma's terminal-inspired visual language. */
export const terminalColors = {
  accent: ["#087a46", "#36e77c"],
  accentMuted: ["#087a461a", "#36e77c24"],
  textAccent: ["#066238", "#65f29c"],
  onAccent: ["#f5fff8", "#031108"],
  backgroundBody: ["#eaf1ec", "#050a08"],
  backgroundSurface: ["#f5f9f6", "#08120d"],
  backgroundCard: ["#f3f8f4", "#0b1811"],
  backgroundPopover: ["#f8fcf9", "#0e1d15"],
  backgroundMuted: ["#dfe9e2", "#11241a"],
  textPrimary: ["#13251a", "#c4e4d0"],
  textSecondary: ["#4c6555", "#90b29d"],
  textDisabled: ["#8fa095", "#50705c"],
  border: ["#b9cabf", "#204a34"],
  borderEmphasized: ["#688174", "#3f8f61"],
  shadow: ["#11351f1f", "#00000066"],
} satisfies Record<string, ColorPair>;

export const terminalTypography = {
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
} as const;

export const terminalRadii = {
  inner: "0.125rem",
  element: "0.25rem",
  container: "0.375rem",
  page: "0.5rem",
} as const;

export const terminalShadows = {
  low: "0 1px 0 #087a4626",
  medium: "0 2px 0 #087a462e, 0 10px 28px #0311081f",
} as const;
