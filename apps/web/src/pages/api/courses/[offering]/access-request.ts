import type { APIRoute } from "astro";
import { markPrivateNoStore } from "../../../../lib/http/response-cache";
import { parseCourseOfferingKey } from "../../../../lib/learning/identifiers";
import { routes } from "../../../../lib/routes";
import { createServerSupabaseClient } from "../../../../lib/supabase/server";

export const prerender = false;

export const POST: APIRoute = async ({ cookies, params, redirect, request }) => {
  const offeringValue = params.offering;
  if (!offeringValue) return markPrivateNoStore(new Response("Course not found", { status: 404 }));
  if (request.headers.get("Origin") !== new URL(request.url).origin) {
    return markPrivateNoStore(new Response("Invalid course request", { status: 403 }));
  }

  let offeringKey;
  try {
    offeringKey = parseCourseOfferingKey(offeringValue);
  } catch {
    return markPrivateNoStore(new Response("Course not found", { status: 404 }));
  }

  const supabase = createServerSupabaseClient({ request, cookies });
  const { data: claims, error: claimsError } = await supabase.auth.getClaims();
  if (claimsError || !claims?.claims?.sub) {
    return markPrivateNoStore(new Response("Sign in required", { status: 401 }));
  }

  const { error } = await supabase.rpc("request_course_access", {
    p_offering_key: offeringKey,
  });
  if (error) {
    return markPrivateNoStore(new Response("Unable to request course access", { status: 503 }));
  }

  const referer = request.headers.get("Referer");
  const destination = referer
    ? new URL(referer)
    : new URL(routes.course.path({ offeringKey }), request.url);
  if (destination.origin !== new URL(request.url).origin) {
    return markPrivateNoStore(new Response("Invalid course destination", { status: 403 }));
  }
  return markPrivateNoStore(redirect(destination.pathname + destination.search, 303));
};
