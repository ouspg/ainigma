import type { APIContext } from "astro";
import { getLocale } from "../i18n";
import { parseCourseDefinitionKey } from "../learning/identifiers";
import { COURSE_DEFINITIONS } from "../learning/course-manifest.generated";
import { routes, type AppRouteMatch } from "../routes";
import { createServerSupabaseClient } from "../supabase/server";
import { hasCourseAccess } from "./course-access";
import { routeRequiresPrivateResponse } from "./private-response";
import { loadStudentProfile } from "./profile";
import { safeNextPath, signInPath } from "./redirects";

function rewriteToStatus(context: APIContext, status: 403 | 404 | 503): Promise<Response> {
  return context.rewrite(new URL(routes.status.path({ code: String(status) }), context.url));
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
  const courseDefinition = COURSE_DEFINITIONS.find(
    (definition) => definition.slug === courseSlug && !definition.draft,
  );
  const courseDefinitionKey = courseDefinition
    ? parseCourseDefinitionKey(courseDefinition.definitionKey)
    : null;
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
