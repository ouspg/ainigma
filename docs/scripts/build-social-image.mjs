import { fileURLToPath } from "node:url";
import sharp from "sharp";
import { docsTheme } from "../config/theme.mjs";

const [background] = docsTheme.colors.backgroundBody;
const [surface] = docsTheme.colors.backgroundSurface;
const [accent] = docsTheme.colors.accent;
const [foreground] = docsTheme.colors.textPrimary;
const [mutedForeground] = docsTheme.colors.textSecondary;

const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <rect width="1200" height="630" fill="${background}"/>
  <rect x="64" y="64" width="1072" height="502" rx="28" fill="${surface}"/>
  <rect x="64" y="64" width="14" height="502" rx="7" fill="${accent}"/>
  <circle cx="1034" cy="162" r="70" fill="none" stroke="${accent}" stroke-width="12" opacity="0.24"/>
  <path d="M969 456h144M1041 384v144" stroke="${accent}" stroke-width="12" stroke-linecap="round" opacity="0.18"/>
  <text x="140" y="282" fill="${foreground}" font-family="Georgia, serif" font-size="82" font-weight="700">Ainigma</text>
  <text x="144" y="360" fill="${accent}" font-family="system-ui, sans-serif" font-size="40" font-weight="700">Documentation</text>
  <text x="144" y="430" fill="${mutedForeground}" font-family="system-ui, sans-serif" font-size="28">Architecture · Development · Operations</text>
</svg>`;

const outputPath = fileURLToPath(new URL("../public/opengraph.png", import.meta.url));
await sharp(Buffer.from(svg)).png({ compressionLevel: 9 }).toFile(outputPath);
console.log(`wrote ${outputPath} (1200×630)`);
