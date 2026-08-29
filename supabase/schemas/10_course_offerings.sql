-- Declarative course offerings: operational identity for authored course definitions.
-- Offering identity remains separate from reusable course content and from cohort membership state.
create table public.courses (
  id uuid primary key default gen_random_uuid(),
  offering_key text not null unique,
  course_definition_key text not null,
  course_definition_release_id uuid not null,
  code text not null,
  status text not null default 'draft',
  starts_at timestamptz,
  ends_at timestamptz,
  external_url text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint courses_offering_key_check check (
    offering_key ~ '^[a-z][a-z0-9-]{2,127}$'
  ),
  constraint courses_course_definition_key_check check (
    course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'
  ),
  constraint courses_course_definition_external_group_fkey foreign key (
    course_definition_key
  ) references private.course_definition_external_groups (course_definition_key) on delete restrict,
  constraint courses_course_definition_release_fkey foreign key (
    course_definition_release_id,
    course_definition_key
  ) references private.course_definition_releases (id, course_definition_key) on delete restrict,
  constraint courses_code_check check (
    code = btrim(code) and char_length(code) between 1 and 32
  ),
  constraint courses_status_check check (status in ('draft', 'published', 'archived')),
  constraint courses_time_window_check check (
    ends_at is null or starts_at is null or ends_at > starts_at
  ),
  constraint courses_external_url_check check (
    external_url is null
    or (char_length(external_url) <= 2048 and external_url ~ '^https?://')
  )
);

comment on table public.courses is
  'Operational course offerings. Titles, navigation, and authored content remain in Git.';
comment on column public.courses.offering_key is
  'Globally unique immutable key for one term, cohort, or operational course space.';
comment on column public.courses.course_definition_key is
  'Immutable key of the reusable Git-authored course definition rendered for this offering.';
comment on column public.courses.course_definition_release_id is
  'Exact compiler release currently rendered for this offering; ended offerings stop advancing.';

create index courses_course_definition_key_idx
  on public.courses (course_definition_key);
create index courses_course_definition_release_id_idx
  on public.courses (course_definition_release_id);

create index courses_status_window_idx
  on public.courses (status, starts_at, ends_at);
alter table public.courses
  add column enrollment_mode text not null default 'approval_required';

alter table public.courses
  add constraint courses_enrollment_mode_check
  check (enrollment_mode in ('approval_required', 'allowlist_auto', 'closed'));

create trigger courses_set_updated_at
before update on public.courses
for each row execute function private.set_updated_at();
