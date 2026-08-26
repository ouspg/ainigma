import type { APIContext } from "astro";
import { getCollection } from "astro:content";
import { getLocale } from "../i18n";
import { getCourseDefinitionKey } from "../learning/course-manifest";
import { routes, type AppRouteMatch } from "../routes";
import { createServerSupabaseClient } from "../supabase/server";
import { hasCourseAccess } from "./course-access";
import { loadStudentProfile } from "./profile";
import { safeNextPath, signInPath } from "./redirects";

export function markResponsePrivate(response: Response): Response {
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}

function rewriteToStatus(context: APIContext, status: 403 | 404 | 503): Promise<Response> {
  return context.rewrite(new URL(routes.status.path({ code: String(status) }), context.url));
}

export function routeRequiresPrivateResponse(route: AppRouteMatch): boolean {
  return ["guestOnly", "authenticated", "courseMember"].includes(route.access);
}

/**
 * Enforce the page-level access policy from routeAccessGroups.
 *
 * Database operations still enforce their own grants, RLS, and ownership or membership rules.
 * This guard controls only whether Astro may render the requested page.
 */
export async function authorizeRouteRequest(
  context: APIContext,
  route: AppRouteMatch,
): Promise<Response | null> {
  if (!routeRequiresPrivateResponse(route)) return null;

  const requestUrl = new URL(context.request.url);
  const supabase = createServerSupabaseClient({
    request: context.request,
    cookies: context.cookies,
  });
  const { data, error } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub;

  if (error) {
    console.warn("[ainigma supabase]", {
      event: "supabase.auth.get_claims.error",
      trace_id: context.locals.traceId,
      error,
    });
  }

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
  } catch (error) {
    console.error("[ainigma supabase]", {
      event: "supabase.rpc.get_my_profile.error",
      trace_id: context.locals.traceId,
      error,
    });
    return rewriteToStatus(context, 503);
  }

  if (route.access !== "courseMember") return null;

  const courseSlug = route.params.course;
  if (!courseSlug) {
    return rewriteToStatus(context, 404);
  }
  const courseDefinitionKey = getCourseDefinitionKey(await getCollection("courses"), courseSlug);
  if (!courseDefinitionKey) {
    return rewriteToStatus(context, 404);
  }

  const { data: courseAccess, error: courseAccessError } = await supabase.rpc("list_my_courses");
  if (courseAccessError) {
    console.error("[ainigma supabase]", {
      event: "supabase.rpc.list_my_courses.error",
      trace_id: context.locals.traceId,
      error: courseAccessError,
    });
    return rewriteToStatus(context, 503);
  }

  return hasCourseAccess(courseAccess, courseDefinitionKey) ? null : rewriteToStatus(context, 403);
}
