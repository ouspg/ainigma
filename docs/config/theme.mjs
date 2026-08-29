import {
  academicColors,
  academicRadii,
  academicShadows,
  academicTypography,
} from "@ainigma/design-tokens/academic";
import {
  terminalColors,
  terminalRadii,
  terminalShadows,
  terminalTypography,
} from "@ainigma/design-tokens/terminal";

const themes = Object.freeze({
  academic: Object.freeze({
    colors: academicColors,
    typography: academicTypography,
    radii: academicRadii,
    shadows: academicShadows,
  }),
  terminal: Object.freeze({
    colors: terminalColors,
    typography: terminalTypography,
    radii: terminalRadii,
    shadows: terminalShadows,
  }),
});

/**
 * Resolve the docs theme once per build. Both generated assets use this
 * result, so changing DOCS_THEME cannot leave the CSS and social image out
 * of sync.
 *
 * @param {NodeJS.ProcessEnv | Record<string, string | undefined>} [environment]
 */
export function resolveDocsTheme(environment = process.env) {
  const name = environment.DOCS_THEME?.trim() || "terminal";
  const theme = themes[name];

  if (!theme) {
    throw new Error(
      `DOCS_THEME must be one of ${Object.keys(themes).join(", ")}; received ${JSON.stringify(name)}`,
    );
  }

  return Object.freeze({ name, ...theme });
}

export const docsTheme = resolveDocsTheme();
