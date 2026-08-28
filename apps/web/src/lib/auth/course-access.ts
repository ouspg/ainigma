import { z } from "astro/zod";
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

const courseAccessResponseSchema = z.object({
  courses: z.array(
    z.object({
      offering_key: z.string().refine(isCourseOfferingKey),
      course_definition_key: z.string().refine(isCourseDefinitionKey),
      course_definition_release_id: z.string().refine(isCourseDefinitionReleaseId),
    }),
  ),
});

export type CourseAccessResponse = z.infer<typeof courseAccessResponseSchema>;

export interface AuthorizedCourseOffering {
  offeringKey: CourseOfferingKey;
  courseDefinitionKey: CourseDefinitionKey;
  courseDefinitionReleaseId: CourseDefinitionReleaseId;
}

export function findAuthorizedCourseOffering(
  data: unknown,
  offeringKey: CourseOfferingKey,
): AuthorizedCourseOffering | null {
  const result = courseAccessResponseSchema.safeParse(data);
  if (!result.success) return null;

  const offering = result.data.courses.find((course) => course.offering_key === offeringKey);
  return offering
    ? {
        offeringKey: parseCourseOfferingKey(offering.offering_key),
        courseDefinitionKey: parseCourseDefinitionKey(offering.course_definition_key),
        courseDefinitionReleaseId: parseCourseDefinitionReleaseId(
          offering.course_definition_release_id,
        ),
      }
    : null;
}
