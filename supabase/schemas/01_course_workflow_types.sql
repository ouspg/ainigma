-- Stable offering states are database types so every write path shares one
-- definition. Provider-specific values remain text for extensibility.
create type private.course_offering_status as enum (
  'draft',
  'published',
  'archived'
);

create type private.course_enrollment_mode as enum (
  'approval_required',
  'allowlist_auto',
  'closed'
);

create type private.course_access_request_status as enum (
  'pending',
  'approved',
  'rejected',
  'cancelled'
);

create type private.course_membership_status as enum (
  'active',
  'suspended',
  'revoked'
);

create type private.course_membership_role as enum (
  'owner',
  'instructor',
  'learner'
);

create type private.external_course_access_state as enum (
  'not_started',
  'invitation_pending',
  'sso_required',
  'active',
  'failed',
  'revoked'
);

create type private.external_invitation_method as enum (
  'email',
  'external_user_id'
);
