import { defaultLocale, locales, type Locale } from "./i18n";
import { isCourseDefinitionKey, type CourseDefinitionKey } from "./learning/identifiers";

export type AppPath = `/${string}`;
export type CoursePageName = "announcements" | "materials";

interface RouteMatchParams {
  course?: CourseDefinitionKey;
  page?: CoursePageName;
  task?: string;
  week?: string;
}

interface RouteDefinition<Params extends unknown[] = []> {
  match(pathname: AppPath): RouteMatchParams | null;
  path(...params: Params): AppPath;
}

function asAppPath(value: string): AppPath {
  if (!value.startsWith("/") || value.startsWith("//")) {
    throw new Error(`Invalid application path: ${value}`);
  }
  return value as AppPath;
}

function trimTrailingSlash(pathname: string): string {
  return pathname === "/" ? pathname : pathname.replace(/\/+$/, "");
}

function staticRoute(path: AppPath): RouteDefinition {
  const canonical = trimTrailingSlash(path);
  return {
    path: () => path,
    match: (pathname) => (trimTrailingSlash(pathname) === canonical ? {} : null),
  };
}

function encodeSegment(value: string): string {
  return encodeURIComponent(value);
}

function encodeSubpath(value: string): string {
  return value.split("/").map(encodeSegment).join("/");
}

function decodeSegment(value: string): string | null {
  try {
    return decodeURIComponent(value);
  } catch {
    return null;
  }
}

function decodeCourse(value: string): CourseDefinitionKey | null {
  const decoded = decodeSegment(value);
  return decoded && isCourseDefinitionKey(decoded) ? decoded : null;
}

function splitSuffix(path: string): { pathname: string; suffix: string } {
  const suffixIndex = path.search(/[?#]/);
  return suffixIndex < 0
    ? { pathname: path, suffix: "" }
    : { pathname: path.slice(0, suffixIndex), suffix: path.slice(suffixIndex) };
}

export function canonicalPath(path: string): AppPath {
  const { pathname, suffix } = splitSuffix(path);
  for (const locale of locales) {
    if (locale === defaultLocale) continue;
    const prefix = `/${locale}`;
    if (pathname === prefix) return asAppPath(`/${suffix}`);
    if (pathname.startsWith(`${prefix}/`)) {
      return asAppPath(`${pathname.slice(prefix.length)}${suffix}`);
    }
  }
  return asAppPath(`${pathname}${suffix}`);
}

export function localizedPath(locale: Locale, path: AppPath): AppPath {
  const canonical = canonicalPath(path);
  if (locale === defaultLocale) return canonical;

  const { pathname, suffix } = splitSuffix(canonical);
  return asAppPath(pathname === "/" ? `/${locale}/${suffix}` : `/${locale}${pathname}${suffix}`);
}

export const routes = {
  home: staticRoute("/"),
  about: staticRoute("/about/"),
  privacy: staticRoute("/privacy/"),
  login: staticRoute("/login/"),
  authCallback: staticRoute("/auth/callback"),
  authLocal: staticRoute("/auth/local"),
  desk: staticRoute("/desk/"),
  activity: staticRoute("/activity/"),
  announcements: staticRoute("/announcements/"),
  course: {
    path: ({ course }: { course: CourseDefinitionKey }) =>
      asAppPath(`/courses/${encodeSegment(course)}/`),
    match(pathname: AppPath) {
      const match = pathname.match(/^\/courses\/([^/]+)\/?$/);
      const course = match?.[1] ? decodeCourse(match[1]) : null;
      return course ? { course } : null;
    },
  },
  coursePage: {
    path: ({ course, page }: { course: CourseDefinitionKey; page: CoursePageName }) =>
      asAppPath(`/courses/${encodeSegment(course)}/${page}/`),
    match(pathname: AppPath) {
      const match = pathname.match(/^\/courses\/([^/]+)\/(announcements|materials)\/?$/);
      const course = match?.[1] ? decodeCourse(match[1]) : null;
      const page = match?.[2] as CoursePageName | undefined;
      return course && page ? { course, page } : null;
    },
  },
  courseWeek: {
    path: ({ course, week }: { course: CourseDefinitionKey; week: string }) =>
      asAppPath(`/courses/${encodeSegment(course)}/${encodeSegment(week)}/`),
    match(pathname: AppPath) {
      const match = pathname.match(/^\/courses\/([^/]+)\/([^/]+)\/?$/);
      const course = match?.[1] ? decodeCourse(match[1]) : null;
      const week = match?.[2] ? decodeSegment(match[2]) : null;
      return course && week ? { course, week } : null;
    },
  },
  courseTask: {
    path: ({ course, task, week }: { course: CourseDefinitionKey; task: string; week: string }) =>
      asAppPath(`/courses/${encodeSegment(course)}/${encodeSegment(week)}/${encodeSubpath(task)}/`),
    match(pathname: AppPath) {
      const match = pathname.match(/^\/courses\/([^/]+)\/([^/]+)\/(.+?)\/?$/);
      const course = match?.[1] ? decodeCourse(match[1]) : null;
      const week = match?.[2] ? decodeSegment(match[2]) : null;
      const taskSegments = match?.[3] ? match[3].split("/").map(decodeSegment) : [];
      const task =
        taskSegments.length > 0 && taskSegments.every((segment) => segment !== null)
          ? taskSegments.join("/")
          : null;
      return course && week && task ? { course, task, week } : null;
    },
  },
} as const;

export type RouteId = keyof typeof routes;
export type RouteAccess = "public" | "guestOnly" | "protocol" | "authenticated" | "courseMember";

/**
 * The complete page-access review surface. Course content remains membership-gated for now;
 * moving it to `public` later must be paired with removing learner data from the course shell.
 */
export const routeAccessGroups = {
  public: ["home", "about", "privacy"],
  guestOnly: ["login"],
  protocol: ["authCallback", "authLocal"],
  authenticated: ["desk", "activity", "announcements"],
  courseMember: ["course", "coursePage", "courseWeek", "courseTask"],
} as const satisfies Record<RouteAccess, readonly RouteId[]>;

/** Routes rendered inside the account-aware learning shell. Kept separate from access policy so
 * course pages can later become public without accidentally inheriting learner-only UI or data. */
export const learnerShellRouteIds = [
  "desk",
  "activity",
  "announcements",
  "course",
  "coursePage",
  "courseWeek",
  "courseTask",
] as const satisfies readonly RouteId[];

const matchOrder: readonly RouteId[] = [
  "home",
  "about",
  "privacy",
  "login",
  "authCallback",
  "authLocal",
  "desk",
  "activity",
  "announcements",
  "courseTask",
  "coursePage",
  "courseWeek",
  "course",
];

const routeAccessEntries = Object.entries(routeAccessGroups) as Array<
  [RouteAccess, readonly RouteId[]]
>;

function routeAccess(routeId: RouteId): RouteAccess {
  const entry = routeAccessEntries.find(([, routeIds]) => routeIds.includes(routeId));
  if (!entry) throw new Error(`Route has no access policy: ${routeId}`);
  return entry[0];
}

const registeredRouteIds = new Set(routeAccessEntries.flatMap(([, routeIds]) => routeIds));
if (
  registeredRouteIds.size !== matchOrder.length ||
  matchOrder.some((id) => !registeredRouteIds.has(id))
) {
  throw new Error("Every application route must appear exactly once in routeAccessGroups");
}

export interface AppRouteMatch {
  access: RouteAccess;
  id: RouteId;
  params: RouteMatchParams;
  pathname: AppPath;
}

export function matchAppRoute(pathname: string): AppRouteMatch | null {
  const canonical = canonicalPath(pathname);
  for (const id of matchOrder) {
    const params = routes[id].match(canonical);
    if (params) return { access: routeAccess(id), id, params, pathname: canonical };
  }
  return null;
}

export function routeUsesLearnerShell(pathname: string): boolean {
  const route = matchAppRoute(pathname);
  return route ? learnerShellRouteIds.some((id) => id === route.id) : false;
}

export type CourseRouteTarget =
  | { route: "course"; course: CourseDefinitionKey }
  | { route: "coursePage"; course: CourseDefinitionKey; page: CoursePageName }
  | { route: "courseWeek"; course: CourseDefinitionKey; week: string }
  | { route: "courseTask"; course: CourseDefinitionKey; task: string; week: string };

export function courseRouteTargetPath(target: CourseRouteTarget): AppPath {
  switch (target.route) {
    case "course":
      return routes.course.path(target);
    case "coursePage":
      return routes.coursePage.path(target);
    case "courseWeek":
      return routes.courseWeek.path(target);
    case "courseTask":
      return routes.courseTask.path(target);
  }
}
