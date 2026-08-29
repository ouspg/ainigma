// Full-corpus markdown for AI agents — every published page in one
// document. Scope and collation live in the framework helper; reshape or
// delete this route to change the site's corpus policy.
import { renderCorpusMarkdown } from "@cloudflare/nimbus-docs";
import { config } from "virtual:nimbus/config";
import { docsVersions, withDocsBase } from "../../config/versions.mjs";

export const prerender = true;

export async function GET() {
  const corpus = await renderCorpusMarkdown();
  const origin = new URL(config.site).origin;
  const escapedOrigin = origin.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const absoluteDocsUrl = new RegExp(`${escapedOrigin}(/[^\\s]*)`, "g");
  const versionedCorpus = corpus.replace(
    absoluteDocsUrl,
    (_url, pathname) => new URL(withDocsBase(pathname, docsVersions.current.base), origin).href,
  );

  return new Response(versionedCorpus, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
