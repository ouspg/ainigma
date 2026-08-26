import type { Locale } from "../i18n";
import { localizedPath, routes, type AppPath } from "../routes";

export const defaultAuthenticatedPath = routes.desk.path();

export function safeNextPath(value: string | null | undefined): AppPath {
  if (!value || !value.startsWith("/") || value.startsWith("//")) {
    return defaultAuthenticatedPath;
  }

  try {
    const base = new URL("https://redirect.invalid");
    const candidate = new URL(value, base);
    if (candidate.origin !== base.origin) return defaultAuthenticatedPath;
    return `${candidate.pathname}${candidate.search}${candidate.hash}` as AppPath;
  } catch {
    return defaultAuthenticatedPath;
  }
}

export function signInPath(locale: Locale, requestUrl: URL): AppPath {
  const next = safeNextPath(`${requestUrl.pathname}${requestUrl.search}`);
  return `${localizedPath(locale, routes.login.path())}?next=${encodeURIComponent(next)}` as AppPath;
}
