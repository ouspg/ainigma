import { z } from "astro/zod";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  isCourseDefinitionKey,
  isCourseDefinitionReleaseId,
  isCourseOfferingKey,
  parseCourseDefinitionKey,
  parseCourseDefinitionReleaseId,
  parseCourseOfferingKey,
  type CourseDefinitionKey,
  type CourseDefinitionReleaseId,
  type CourseOfferingKey,
} from "../learning/identifiers";
import type { Database } from "../supabase/database.types";

const courseAccessResponseSchema = z.object({
  courses: z.array(
    z.object({
      offering_key: z.string().refine(isCourseOfferingKey),
      course_definition_key: z.string().refine(isCourseDefinitionKey),
      course_definition_release_id: z.string().refine(isCourseDefinitionReleaseId),
    }),
  ),
});

const courseEnrollmentModeSchema = z.enum(["approval_required", "allowlist_auto", "closed"]);
const courseAccessRequestStatusSchema = z.enum(["pending", "approved", "rejected", "cancelled"]);

const availableCourseResponseSchema = z.array(
  z.object({
    offering_key: z.string().refine(isCourseOfferingKey),
    course_definition_key: z.string().refine(isCourseDefinitionKey),
    course_definition_release_id: z.string().refine(isCourseDefinitionReleaseId),
    code: z.string(),
    enrollment_mode: courseEnrollmentModeSchema,
    starts_at: z.string().nullable(),
    ends_at: z.string().nullable(),
    external_url: z.string().nullable(),
  }),
);

const accessRequestResponseSchema = z.array(
  z.object({
    offering_key: z.string().refine(isCourseOfferingKey),
    status: courseAccessRequestStatusSchema,
  }),
);

export interface CourseOfferingReference {
  offeringKey: CourseOfferingKey;
  courseDefinitionKey: CourseDefinitionKey;
  courseDefinitionReleaseId: CourseDefinitionReleaseId;
}

export type CourseMembership = CourseOfferingReference;
type CourseEnrollmentMode = z.infer<typeof courseEnrollmentModeSchema>;
type CourseAccessRequestStatus = z.infer<typeof courseAccessRequestStatusSchema>;

export interface AvailableCourseOffering extends CourseOfferingReference {
  code: string;
  enrollmentMode: CourseEnrollmentMode;
  startsAt: string | null;
  endsAt: string | null;
  externalUrl: string | null;
}

export interface CourseAccessRequest {
  offeringKey: CourseOfferingKey;
  status: CourseAccessRequestStatus;
}

export type CourseAccessState = "anonymous" | "empty" | "pending" | "accepted";

export async function listAvailableCourseOfferings(
  supabase: SupabaseClient<Database>,
): Promise<AvailableCourseOffering[]> {
  const { data, error } = await supabase.rpc("list_available_courses");
  if (error) throw new Error("Unable to load the published course catalog.", { cause: error });

  const result = availableCourseResponseSchema.parse(data);
  return result.map((offering) => ({
    offeringKey: parseCourseOfferingKey(offering.offering_key),
    courseDefinitionKey: parseCourseDefinitionKey(offering.course_definition_key),
    courseDefinitionReleaseId: parseCourseDefinitionReleaseId(
      offering.course_definition_release_id,
    ),
    code: offering.code,
    enrollmentMode: offering.enrollment_mode,
    startsAt: offering.starts_at,
    endsAt: offering.ends_at,
    externalUrl: offering.external_url,
  }));
}

export async function listCourseMemberships(
  supabase: SupabaseClient<Database>,
): Promise<CourseMembership[]> {
  const { data, error } = await supabase.rpc("list_my_courses");
  if (error) throw new Error("Unable to load course memberships.", { cause: error });
  return parseCourseMemberships(data);
}

export async function listCourseAccessRequests(
  supabase: SupabaseClient<Database>,
): Promise<CourseAccessRequest[]> {
  const { data, error } = await supabase.rpc("list_my_course_access_requests");
  if (error) throw new Error("Unable to load course access requests.", { cause: error });
  return parseCourseAccessRequests(data);
}

export function parseCourseMemberships(data: unknown): CourseMembership[] {
  const result = courseAccessResponseSchema.safeParse(data);
  if (!result.success) return [];

  return result.data.courses.map((course) => ({
    offeringKey: parseCourseOfferingKey(course.offering_key),
    courseDefinitionKey: parseCourseDefinitionKey(course.course_definition_key),
    courseDefinitionReleaseId: parseCourseDefinitionReleaseId(course.course_definition_release_id),
  }));
}

export function parseCourseAccessRequests(data: unknown): CourseAccessRequest[] {
  const result = accessRequestResponseSchema.safeParse(data);
  if (!result.success) return [];

  return result.data.map((request) => ({
    offeringKey: parseCourseOfferingKey(request.offering_key),
    status: request.status,
  }));
}

export function getCourseAccessState(
  memberships: readonly CourseMembership[],
  requests: readonly CourseAccessRequest[],
  offeringKey: CourseOfferingKey,
): Exclude<CourseAccessState, "anonymous"> {
  const membership = findCourseMembership(memberships, offeringKey);
  if (membership) return "accepted";

  const hasPendingRequest = requests.some(
    (request) =>
      request.offeringKey === offeringKey &&
      (request.status === "pending" || request.status === "approved"),
  );

  return hasPendingRequest ? "pending" : "empty";
}

export function findCourseMembership(
  memberships: readonly CourseMembership[],
  offeringKey: CourseOfferingKey,
): CourseMembership | null {
  return memberships.find((membership) => membership.offeringKey === offeringKey) ?? null;
}
