-- Compiler-controlled course release and offering lifecycle operations.

-- A release digest is immutable: replay may reuse it only when commit and artifact metadata still match.
create function private.register_course_definition_release(
  p_course_definition_key text,
  p_source_commit_sha text,
  p_course_release_digest text,
  p_artifact_ref text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_release private.course_definition_releases%rowtype;
begin
  insert into private.course_definition_releases (
    course_definition_key,
    source_commit_sha,
    course_release_digest,
    artifact_ref
  )
  values (
    p_course_definition_key,
    p_source_commit_sha,
    p_course_release_digest,
    p_artifact_ref
  )
  on conflict (course_definition_key, course_release_digest) do nothing
  returning * into v_release;

  if v_release.id is null then
    select release.*
    into strict v_release
    from private.course_definition_releases as release
    where release.course_definition_key = p_course_definition_key
      and release.course_release_digest = p_course_release_digest;

    if v_release.source_commit_sha <> p_source_commit_sha
      or v_release.artifact_ref <> p_artifact_ref
    then
      raise exception using
        errcode = '23505',
        message = 'course_definition_release_metadata_mismatch';
    end if;
  end if;

  return v_release.id;
end
$function$;

-- The Ainigma compiler calls this after admitting and deploying a release. Ended offerings are
-- represented by the archived status and deliberately retain their existing release pointer.
create function private.advance_open_course_offerings_to_release(
  p_course_definition_release_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_course_definition_key text;
  v_updated_count integer;
begin
  select release.course_definition_key
  into v_course_definition_key
  from private.course_definition_releases as release
  where release.id = p_course_definition_release_id;

  if v_course_definition_key is null then
    raise exception using errcode = '23503', message = 'course_definition_release_not_found';
  end if;

  update public.courses as course
  set course_definition_release_id = p_course_definition_release_id
  where course.course_definition_key = v_course_definition_key
    and course.status <> 'archived'
    and course.course_definition_release_id <> p_course_definition_release_id;

  get diagnostics v_updated_count = row_count;
  return v_updated_count;
end
$function$;

-- Branching is a compiler/control-plane operation. It creates a new operational space and owner
-- membership from an exact existing definition release; it never copies the source directory.
create function private.branch_course_offering(
  p_offering_key text,
  p_course_definition_release_id uuid,
  p_code text,
  p_owner_profile_id uuid,
  p_starts_at timestamptz default null,
  p_ends_at timestamptz default null,
  p_external_url text default null,
  p_membership_verification private.course_membership_verification default 'external_membership'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_course_id uuid;
  v_course_definition_key text;
begin
  select release.course_definition_key
  into v_course_definition_key
  from private.course_definition_releases as release
  where release.id = p_course_definition_release_id;

  if v_course_definition_key is null then
    raise exception using errcode = '23503', message = 'course_definition_release_not_found';
  end if;

  if not exists (
    select 1 from public.profiles as profile where profile.id = p_owner_profile_id
  ) then
    raise exception using errcode = '23503', message = 'owner_profile_not_found';
  end if;

  insert into public.courses (
    offering_key,
    course_definition_key,
    course_definition_release_id,
    code,
    membership_verification,
    starts_at,
    ends_at,
    external_url
  )
  values (
    p_offering_key,
    v_course_definition_key,
    p_course_definition_release_id,
    p_code,
    p_membership_verification,
    p_starts_at,
    p_ends_at,
    p_external_url
  )
  returning id into v_course_id;

  insert into public.course_memberships (course_id, profile_id, role, status)
  values (v_course_id, p_owner_profile_id, 'owner', 'active');

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    v_course_id,
    p_owner_profile_id,
    'created',
    'owner',
    'active',
    p_owner_profile_id,
    'initial course owner'
  );

  return v_course_id;
end
$function$;
