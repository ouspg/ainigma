export type ExternalUrl = `https://${string}`;

export const externalLinks = {
  peppi: "https://opas.peppi.oulu.fi",
  sourceCode: "https://github.com/ouspg/ainigma",
} as const satisfies Record<string, ExternalUrl>;
