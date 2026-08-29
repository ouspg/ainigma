const VERSION_SEGMENT_PATTERN = /^[a-zA-Z0-9](?:[a-zA-Z0-9._-]*[a-zA-Z0-9])?$/;

function assertVersion(version, variableName) {
  if (!VERSION_SEGMENT_PATTERN.test(version) || version === "." || version === "..") {
    throw new Error(
      `${variableName} must be a safe URL segment containing only letters, numbers, dots, underscores, or hyphens; received ${JSON.stringify(version)}`,
    );
  }
}

function normalizeRootPath(value) {
  const trimmed = value.trim();
  if (!trimmed || trimmed === "/") return "/";
  if (!trimmed.startsWith("/")) {
    throw new Error(`DOCS_ROOT_PATH must start with "/"; received ${JSON.stringify(value)}`);
  }

  return `/${trimmed.split("/").filter(Boolean).join("/")}/`;
}

function versionBase(rootPath, version) {
  return version === "main" ? rootPath : `${rootPath}${version}/`;
}

/** Prefix an internal Nimbus URL with the base of the separately built version. */
export function withDocsBase(href, base) {
  if (!href.startsWith("/") || href.startsWith("//") || base === "/") return href;

  const suffixIndex = href.search(/[?#]/);
  const pathname = suffixIndex === -1 ? href : href.slice(0, suffixIndex);
  const suffix = suffixIndex === -1 ? "" : href.slice(suffixIndex);
  const baseWithoutSlash = base.slice(0, -1);

  if (pathname === baseWithoutSlash || pathname.startsWith(base)) return href;
  if (pathname === "/") return `${base}${suffix}`;
  return `${base}${pathname.replace(/^\/+/, "")}${suffix}`;
}

/** Convert a deployed version URL back to the root-relative path Nimbus indexes. */
export function withoutDocsBase(pathname, base) {
  if (base === "/") return pathname;

  const baseWithoutSlash = base.slice(0, -1);
  if (pathname === baseWithoutSlash || pathname === base) return "/";
  if (!pathname.startsWith(base)) return pathname;

  const relative = pathname.slice(base.length);
  return relative ? `/${relative}` : "/";
}

/**
 * Resolve all URL decisions from environment variables once per build.
 *
 * @param {NodeJS.ProcessEnv | Record<string, string | undefined>} [environment]
 */
export function resolveDocsVersions(environment = process.env) {
  const currentId = environment.DOCS_VERSION?.trim() || "main";
  assertVersion(currentId, "DOCS_VERSION");

  const configuredIds = environment.DOCS_ACTIVE_VERSIONS?.split(",")
    .map((version) => version.trim())
    .filter(Boolean) ?? [currentId];

  const activeIds = [...new Set(configuredIds)];
  for (const version of activeIds) assertVersion(version, "DOCS_ACTIVE_VERSIONS");
  if (!activeIds.includes(currentId)) activeIds.unshift(currentId);

  const rootPath = normalizeRootPath(environment.DOCS_ROOT_PATH ?? "/");
  const versions = activeIds.map((id) => ({
    id,
    label: id,
    base: versionBase(rootPath, id),
  }));
  const current = versions.find(({ id }) => id === currentId);
  if (!current) throw new Error(`Unable to resolve documentation version ${currentId}`);

  const gitRef =
    environment.DOCS_GIT_REF?.trim() || (currentId === "main" ? "main" : `release/${currentId}`);
  if (!gitRef || /\s/.test(gitRef)) {
    throw new Error(`DOCS_GIT_REF must be a non-empty Git ref without whitespace`);
  }

  return { current, gitRef, rootPath, versions };
}

/**
 * Keep the reader on the equivalent page when switching versions.
 * A missing page is intentionally allowed to reach that version's static 404.
 */
export function versionPagePath(pathname, currentBase, targetBase, search = "") {
  const baseWithoutSlash = currentBase === "/" ? "/" : currentBase.slice(0, -1);
  let relativePath;

  if (pathname === baseWithoutSlash || pathname === currentBase) {
    relativePath = "";
  } else if (pathname.startsWith(currentBase)) {
    relativePath = pathname.slice(currentBase.length);
  } else {
    relativePath = pathname.replace(/^\/+/, "");
  }

  return `${targetBase}${relativePath}${search}`;
}

export const docsVersions = resolveDocsVersions();
