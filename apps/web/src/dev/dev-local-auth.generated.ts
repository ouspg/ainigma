// @generated from supabase/dev-personas.json — do not edit manually.
export const localAuthPersonas = [
  {
    "key": "emptyLearner",
    "label": "Empty learner",
    "description": "Signed in with no course membership or access request."
  },
  {
    "key": "pendingLearner",
    "label": "Pending learner",
    "description": "Has requested access to test course A."
  },
  {
    "key": "memberCourseA",
    "label": "Member · course A",
    "description": "Has active learner access to test course A only."
  },
  {
    "key": "memberCourseB",
    "label": "Member · course B",
    "description": "Has active learner access to test course B only."
  },
  {
    "key": "memberBothCourses",
    "label": "Member · both courses",
    "description": "Has active learner access to test courses A and B."
  },
  {
    "key": "instructor",
    "label": "Instructor",
    "description": "Has instructor access to test course A."
  },
  {
    "key": "owner",
    "label": "Course owner",
    "description": "Owns the seeded test courses and can review requests."
  }
] as const;

export type LocalAuthPersona = (typeof localAuthPersonas)[number]["key"];
export type LocalAuthPersonaOption = (typeof localAuthPersonas)[number];
export interface LocalAuthPersonaRecord { email: string; userId: string; }

export const localAuthPersonaRecords: Record<LocalAuthPersona, LocalAuthPersonaRecord> = {
  "emptyLearner": {
    "email": "empty-learner@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000003"
  },
  "pendingLearner": {
    "email": "pending-learner@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000004"
  },
  "memberCourseA": {
    "email": "learner-a@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000002"
  },
  "memberCourseB": {
    "email": "learner-b@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000006"
  },
  "memberBothCourses": {
    "email": "learner-both@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000007"
  },
  "instructor": {
    "email": "instructor@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000005"
  },
  "owner": {
    "email": "owner@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000001"
  }
};
