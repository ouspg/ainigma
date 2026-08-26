const COURSE_DEFINITION_KEY_PATTERN = /^[a-z][a-z0-9-]{2,63}$/;

declare const courseDefinitionKeyBrand: unique symbol;

export type CourseDefinitionKey = string & {
  readonly [courseDefinitionKeyBrand]: "CourseDefinitionKey";
};

export function isCourseDefinitionKey(value: string): value is CourseDefinitionKey {
  return COURSE_DEFINITION_KEY_PATTERN.test(value);
}

export function parseCourseDefinitionKey(value: string): CourseDefinitionKey {
  if (!isCourseDefinitionKey(value)) {
    throw new Error(`Invalid course definition key: ${value}`);
  }
  return value;
}

export function courseDefinitionKeyFromParam(
  value: string | undefined,
): CourseDefinitionKey | null {
  return value && isCourseDefinitionKey(value) ? value : null;
}
