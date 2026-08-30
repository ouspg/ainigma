const COURSE_OFFERING_KEY_PATTERN = /^[a-z][a-z0-9-]{2,127}$/;
const COURSE_DEFINITION_KEY_PATTERN = /^[a-z][a-z0-9-]{2,63}$/;
const COURSE_DEFINITION_SLUG_PATTERN = /^[a-z][a-z0-9-]{2,63}$/;
const COURSE_DEFINITION_RELEASE_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

declare const courseOfferingKeyBrand: unique symbol;
declare const courseDefinitionKeyBrand: unique symbol;
declare const courseDefinitionSlugBrand: unique symbol;
declare const courseDefinitionReleaseIdBrand: unique symbol;

/** Globally unique identity of one operational term, cohort, or course space. */
export type CourseOfferingKey = string & {
  readonly [courseOfferingKeyBrand]: "CourseOfferingKey";
};

/** Immutable identity of one reusable Git/MDX course definition. */
export type CourseDefinitionKey = string & {
  readonly [courseDefinitionKeyBrand]: "CourseDefinitionKey";
};

/** Mutable directory identifier for one reusable authored course definition. */
export type CourseDefinitionSlug = string & {
  readonly [courseDefinitionSlugBrand]: "CourseDefinitionSlug";
};

/** Database identity of one exact compiler-built course-definition release. */
export type CourseDefinitionReleaseId = string & {
  readonly [courseDefinitionReleaseIdBrand]: "CourseDefinitionReleaseId";
};

export function isCourseOfferingKey(value: string): value is CourseOfferingKey {
  return COURSE_OFFERING_KEY_PATTERN.test(value);
}

export function parseCourseOfferingKey(value: string): CourseOfferingKey {
  if (!isCourseOfferingKey(value)) {
    throw new Error(`Invalid course offering key: ${value}`);
  }
  return value;
}

export function isCourseDefinitionKey(value: string): value is CourseDefinitionKey {
  return COURSE_DEFINITION_KEY_PATTERN.test(value);
}

export function parseCourseDefinitionKey(value: string): CourseDefinitionKey {
  if (!isCourseDefinitionKey(value)) {
    throw new Error(`Invalid course definition key: ${value}`);
  }
  return value;
}

export function isCourseDefinitionSlug(value: string): value is CourseDefinitionSlug {
  return COURSE_DEFINITION_SLUG_PATTERN.test(value);
}

export function parseCourseDefinitionSlug(value: string): CourseDefinitionSlug {
  if (!isCourseDefinitionSlug(value)) {
    throw new Error(`Invalid course definition slug: ${value}`);
  }
  return value;
}

export function isCourseDefinitionReleaseId(value: string): value is CourseDefinitionReleaseId {
  return COURSE_DEFINITION_RELEASE_ID_PATTERN.test(value);
}

export function parseCourseDefinitionReleaseId(value: string): CourseDefinitionReleaseId {
  if (!isCourseDefinitionReleaseId(value)) {
    throw new Error(`Invalid course definition release ID: ${value}`);
  }
  return value;
}
