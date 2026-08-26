import type { APIContext } from "astro";
import { getLocale } from "../i18n";
import type { AppRouteMatch } from "../routes";
import { createServerSupabaseClient } from "../supabase/server";
import { hasCourseAccess } from "./course-access";
import { loadStudentProfile } from "./profile";
import { safeNextPath, signInPath } from "./redirects";

export function responseWithoutSharedCaching(response: Response): Response {
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}

export function routeUsesPrivateSession(route: AppRouteMatch): boolean {
  return ["guestOnly", "authenticated", "courseMember"].includes(route.access);
}

/**
 * Enforce the page-level access policy from routeAccessGroups.
 *
 * Database operations still enforce their own grants, RLS, and ownership or membership rules.
 * This guard controls only whether Astro may render the requested page.
 */
export async function enforceRouteAccess(
  context: APIContext,
  route: AppRouteMatch,
): Promise<Response | null> {
  if (!routeUsesPrivateSession(route)) return null;

  const requestUrl = new URL(context.request.url);
  const supabase = createServerSupabaseClient({
    request: context.request,
    cookies: context.cookies,
  });
  const { data, error } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub;

  if (route.access === "guestOnly") {
    return !error && userId
      ? context.redirect(safeNextPath(requestUrl.searchParams.get("next")))
      : null;
  }

  if (error || !userId) {
    return context.redirect(signInPath(getLocale(context.currentLocale), requestUrl));
  }

  context.locals.userId = userId;

  try {
    context.locals.profile = await loadStudentProfile(supabase);
  } catch {
    return new Response("Unable to load learner profile.", { status: 503 });
  }

  if (route.access !== "courseMember") return null;

  const courseDefinitionKey = route.params.course;
  if (!courseDefinitionKey) {
    return new Response("Course route is invalid.", { status: 404 });
  }

  const { data: courseAccess, error: courseAccessError } = await supabase.rpc("list_my_courses");
  if (courseAccessError) {
    return new Response("Unable to verify course access.", { status: 503 });
  }

  return hasCourseAccess(courseAccess, courseDefinitionKey)
    ? null
    : new Response("Course access required.", { status: 403 });
}
