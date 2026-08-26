import { z } from "astro/zod";
import { isCourseDefinitionKey, type CourseDefinitionKey } from "../learning/identifiers";

const courseAccessResponseSchema = z.object({
  courses: z.array(
    z.object({
      definition_key: z.string().refine(isCourseDefinitionKey),
    }),
  ),
});

export type CourseAccessResponse = z.infer<typeof courseAccessResponseSchema>;

export function hasCourseAccess(data: unknown, definitionKey: CourseDefinitionKey): boolean {
  const result = courseAccessResponseSchema.safeParse(data);
  return (
    result.success && result.data.courses.some((course) => course.definition_key === definitionKey)
  );
}
