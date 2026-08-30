import type { APIRoute } from "astro";
import { findCourseMembership, listCourseMemberships } from "../../../../lib/auth/course-access";
import { evaluateChallengeSubmission } from "../../../../lib/challenges/repository";
import { challengeSubmissionSchema } from "../../../../lib/challenges/submission";
import { markPrivateNoStore } from "../../../../lib/http/response-cache";
import { parseCourseOfferingKey } from "../../../../lib/learning/identifiers";
import { createServerSupabaseClient } from "../../../../lib/supabase/server";

export const prerender = false;

function jsonResponse(body: object, status = 200): Response {
  return markPrivateNoStore(
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    }),
  );
}

export const POST: APIRoute = async ({ cookies, params, request }) => {
  const offeringValue = params.offering;
  if (!offeringValue) return jsonResponse({ error: "course_not_found" }, 404);
  if (request.headers.get("Origin") !== new URL(request.url).origin) {
    return jsonResponse({ error: "invalid_course_request" }, 403);
  }

  let offeringKey;
  try {
    offeringKey = parseCourseOfferingKey(offeringValue);
  } catch {
    return jsonResponse({ error: "course_not_found" }, 404);
  }

  const supabase = createServerSupabaseClient({ request, cookies });
  const { data: claims, error: claimsError } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  if (claimsError || !userId) return jsonResponse({ error: "sign_in_required" }, 401);

  let membership = null;
  try {
    membership = findCourseMembership(await listCourseMemberships(supabase), offeringKey);
  } catch {
    // Do not reveal whether a course exists when membership lookup fails.
  }
  if (!membership) {
    return jsonResponse({ error: "course_access_required" }, 403);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_challenge_request" }, 400);
  }
  const submission = challengeSubmissionSchema.safeParse(payload);
  if (!submission.success) {
    return jsonResponse({ error: "invalid_challenge_request" }, 400);
  }

  const evaluation = evaluateChallengeSubmission(membership.courseDefinitionKey, submission.data);
  return "error" in evaluation
    ? jsonResponse({ error: evaluation.error }, 404)
    : jsonResponse(evaluation);
};
