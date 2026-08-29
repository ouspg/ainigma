import { config } from "virtual:nimbus/config";
import { docsVersions, withDocsBase } from "../../config/versions.mjs";

export const prerender = true;

export function GET() {
  const body = [
    "User-agent: *",
    "Allow: /",
    "",
    `Sitemap: ${new URL(withDocsBase("/sitemap-index.xml", docsVersions.current.base), config.site).href}`,
    "",
  ].join("\n");

  return new Response(body, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
