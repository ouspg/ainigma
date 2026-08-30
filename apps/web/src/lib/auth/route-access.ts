import type { APIContext } from "astro";
import { getLocale } from "../i18n";
import { routes, type AppRouteMatch } from "../routes";
import { createServerSupabaseClient } from "../supabase/server";
import {
  getCourseAccessState,
  listAvailableCourseOfferings,
  listCourseAccessRequests,
  listCourseMemberships,
} from "./course-access";
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
  const isAccountAwareHome = route.id === "home";
  const isCourseRoute = route.access === "coursePublic";
  if (!routeRequiresPrivateResponse(route)) return null;

  const requestUrl = new URL(context.request.url);
  const supabase = createServerSupabaseClient({
    request: context.request,
    cookies: context.cookies,
  });
  const { data, error: claimsError } = await supabase.auth.getClaims();
  const userId = claimsError ? undefined : data?.claims?.sub;

  if (claimsError) {
    console.warn("[ainigma supabase]", {
      event: "supabase.auth.get_claims.error",
      trace_id: context.locals.traceId,
      error: claimsError,
    });
  }
  if (userId) context.locals.userId = userId;

  if (isAccountAwareHome) {
    try {
      context.locals.availableCourseOfferings = await listAvailableCourseOfferings(supabase);
    } catch (error) {
      console.error("[ainigma supabase]", {
        event: "supabase.rpc.list_available_courses.public_home.error",
        trace_id: context.locals.traceId,
        error,
      });
      return rewriteToStatus(context, 503);
    }

    if (!userId) return null;

    try {
      context.locals.profile = await loadStudentProfile(supabase);
    } catch (error) {
      console.error("[ainigma supabase]", {
        event: "supabase.rpc.get_my_profile.public_home.error",
        trace_id: context.locals.traceId,
        error,
      });
      return rewriteToStatus(context, 503);
    }
    return null;
  }

  if (isCourseRoute) {
    const offeringKey = route.params.offeringKey;
    if (!offeringKey) return rewriteToStatus(context, 404);

    let availableOfferings;
    try {
      availableOfferings = await listAvailableCourseOfferings(supabase);
    } catch (error) {
      console.error("[ainigma supabase]", {
        event: "supabase.rpc.list_available_courses.error",
        trace_id: context.locals.traceId,
        error,
      });
      return rewriteToStatus(context, 503);
    }

    const availableOffering =
      availableOfferings.find((offering) => offering.offeringKey === offeringKey) ?? null;
    if (!availableOffering) return rewriteToStatus(context, 404);
    context.locals.availableCourseOffering = availableOffering;
    context.locals.availableCourseOfferings = availableOfferings;

    if (!userId) {
      context.locals.courseAccessState = "anonymous";
      return null;
    }

    try {
      const [profile, memberships, accessRequests] = await Promise.all([
        loadStudentProfile(supabase),
        listCourseMemberships(supabase),
        listCourseAccessRequests(supabase),
      ]);
      context.locals.profile = profile;
      context.locals.courseMemberships = memberships;
      context.locals.courseAccessState = getCourseAccessState(
        memberships,
        accessRequests,
        offeringKey,
      );
    } catch (error) {
      console.error("[ainigma supabase]", {
        event: "supabase.rpc.course_access_state.error",
        trace_id: context.locals.traceId,
        error,
      });
      return rewriteToStatus(context, 503);
    }
    return null;
  }

  if (route.access === "guestOnly") {
    return userId ? context.redirect(safeNextPath(requestUrl.searchParams.get("next"))) : null;
  }

  if (!userId) {
    return context.redirect(signInPath(getLocale(context.currentLocale), requestUrl));
  }

  try {
    const [profile, memberships, availableOfferings] = await Promise.all([
      loadStudentProfile(supabase),
      listCourseMemberships(supabase),
      listAvailableCourseOfferings(supabase),
    ]);
    context.locals.profile = profile;
    context.locals.courseMemberships = memberships;
    context.locals.availableCourseOfferings = availableOfferings;
  } catch (error) {
    console.error("[ainigma supabase]", {
      event: "supabase.rpc.get_my_profile.error",
      trace_id: context.locals.traceId,
      error,
    });
    return rewriteToStatus(context, 503);
  }

  return null;
}
