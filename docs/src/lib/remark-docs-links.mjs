import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { docsRouteId } from "./docs-route.mjs";

function encodeGitRef(gitRef) {
  return gitRef.split("/").map(encodeURIComponent).join("/");
}

function routeUrl(base, id, suffix) {
  const route = id ? `${id}/` : "";
  return `${base}${route}${suffix}`;
}

/**
 * Convert source-oriented Markdown links to deployable, version-aware URLs.
 *
 * @param {string} url
 * @param {string} sourcePath
 * @param {{ base: string; docsRoot: URL | string; repositoryRoot?: URL | string; gitRef: string; repositoryUrl: string }} options
 */
export function rewriteDocsLink(url, sourcePath, options) {
  const docsRoot =
    options.docsRoot instanceof URL ? fileURLToPath(options.docsRoot) : options.docsRoot;
  const configuredRepositoryRoot = options.repositoryRoot
    ? options.repositoryRoot instanceof URL
      ? fileURLToPath(options.repositoryRoot)
      : options.repositoryRoot
    : resolve(docsRoot, "..");
  const repositoryRoot = resolve(configuredRepositoryRoot);

  const localSourceMatch = url.match(/^(.*?):(\d+)$/);
  const localSourcePath = localSourceMatch?.[1] ?? url;
  if (localSourcePath.startsWith(`${repositoryRoot}${sep}`)) {
    const repositoryPath = relative(repositoryRoot, localSourcePath).split(sep).join("/");
    const lineFragment = localSourceMatch ? `#L${localSourceMatch[2]}` : "";
    return `${options.repositoryUrl}/blob/${encodeGitRef(options.gitRef)}/${repositoryPath}${lineFragment}`;
  }

  if (/^[a-z][a-z0-9+.-]*:/i.test(url) || url.startsWith("//")) return url;

  const markdownMatch = url.match(/^([^?#]+\.mdx?)([?#].*)?$/i);
  if (!markdownMatch || markdownMatch[1]?.startsWith("/")) return url;

  const sourceDirectory = dirname(relative(docsRoot, sourcePath));
  const targetPath = relative(docsRoot, resolve(docsRoot, sourceDirectory, markdownMatch[1]))
    .split(sep)
    .join("/");
  if (targetPath === ".." || targetPath.startsWith("../")) return url;

  return routeUrl(options.base, docsRouteId(targetPath), markdownMatch[2] ?? "");
}

function visitLinks(node, visitor) {
  if (!node || typeof node !== "object") return;
  if (node.type === "link" && typeof node.url === "string") visitor(node);
  if (Array.isArray(node.children)) {
    for (const child of node.children) visitLinks(child, visitor);
  }
}

export function remarkDocsLinks(options) {
  return (tree, file) => {
    const sourcePath = file.path;
    if (!sourcePath) return;

    visitLinks(tree, (node) => {
      node.url = rewriteDocsLink(node.url, sourcePath, options);
    });
  };
}
