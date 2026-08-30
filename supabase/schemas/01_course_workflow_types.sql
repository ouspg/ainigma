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
