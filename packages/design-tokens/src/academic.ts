export type ColorPair = [light: string, dark: string];

/**
 * Shared semantic values for Ainigma's default visual language.
 *
 * Keep framework-specific mappings in each consumer. The application maps
 * these values to Astryx tokens, while the documentation site maps them to
 * Nimbus tokens.
 */
export const academicColors = {
  accent: ["#28567a", "#8fb9d4"],
  accentMuted: ["#28567a1a", "#8fb9d426"],
  textAccent: ["#214b6b", "#a8c8dc"],
  onAccent: ["#f5f8fa", "#15222b"],
  backgroundBody: ["#f3f5f6", "#151a1e"],
  backgroundSurface: ["#fafbfb", "#20262b"],
  backgroundCard: ["#ffffff", "#252c32"],
  backgroundPopover: ["#ffffff", "#2b333a"],
  backgroundMuted: ["#e7ecef", "#303940"],
  textPrimary: ["#1f2933", "#edf2f5"],
  textSecondary: ["#5f6b75", "#b8c3cb"],
  textDisabled: ["#9aa6af", "#75818a"],
  border: ["#d5dde2", "#414b53"],
  borderEmphasized: ["#82909b", "#73808a"],
  shadow: ["#1f29330a", "#00000038"],
} satisfies Record<string, ColorPair>;

export const academicTypography = {
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
} as const;

export const academicRadii = {
  inner: "0.25rem",
  element: "0.375rem",
  container: "0.5rem",
  page: "0.75rem",
} as const;

export const academicShadows = {
  low: "none",
  medium: "0 1px 2px #1f293314",
} as const;
