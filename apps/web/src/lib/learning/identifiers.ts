const COURSE_DEFINITION_KEY_PATTERN = /^[a-z][a-z0-9-]{2,63}$/;
const COURSE_SLUG_PATTERN = /^[a-z][a-z0-9-]{2,63}$/;

declare const courseDefinitionKeyBrand: unique symbol;
declare const courseSlugBrand: unique symbol;

export type CourseDefinitionKey = string & {
  readonly [courseDefinitionKeyBrand]: "CourseDefinitionKey";
};

/** Mutable URL/content-directory identifier. Never use this as a database authorization key. */
export type CourseSlug = string & {
  readonly [courseSlugBrand]: "CourseSlug";
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

export function isCourseSlug(value: string): value is CourseSlug {
  return COURSE_SLUG_PATTERN.test(value);
}

export function parseCourseSlug(value: string): CourseSlug {
  if (!isCourseSlug(value)) {
    throw new Error(`Invalid course slug: ${value}`);
  }
  return value;
}

export function courseSlugFromParam(value: string | undefined): CourseSlug | null {
  return value && isCourseSlug(value) ? value : null;
}
