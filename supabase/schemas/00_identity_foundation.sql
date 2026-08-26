-- Declarative identity foundation: provider-neutral profiles, Auth links, and verified identifiers.
-- The initial baseline omits one-time Auth reconciliation because this database is fresh;
-- schema diffs do not capture data changes.
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;

create schema if not exists private;

revoke create on schema public from public, anon, authenticated;
revoke all on schema private from public, anon, authenticated;

-- Application objects are private unless a migration grants access explicitly.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete, truncate, references, trigger on tables
  from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke usage, select, update on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema private
  revoke select, insert, update, delete, truncate, references, trigger on tables
  from public, anon, authenticated;
alter default privileges for role postgres in schema private
  revoke usage, select, update on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema private
  revoke execute on functions from public, anon, authenticated;

do $roles$
declare
  v_role record;
begin
  if not exists (select 1 from pg_roles where rolname = 'ainigma_function_owner') then
    create role ainigma_function_owner nologin noinherit;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'ainigma_maintenance') then
    create role ainigma_maintenance nologin noinherit;
  end if;

  for v_role in
    select role_row.*
    from pg_roles as role_row
    where role_row.rolname in ('ainigma_function_owner', 'ainigma_maintenance')
  loop
    if v_role.rolcanlogin
      or v_role.rolsuper
      or v_role.rolcreatedb
      or v_role.rolcreaterole
      or v_role.rolreplication
      or v_role.rolbypassrls
    then
      raise exception 'role % has unsafe attributes', v_role.rolname;
    end if;
  end loop;
end
$roles$;

-- The function owner cannot log in. Its table access is constrained by
-- explicit grants and dedicated internal RLS policies below.


-- These private, application-owned views are the only bridge through Auth's RLS.
-- They expose the minimum trusted columns needed by reconciliation functions
-- and are never granted to browser or maintenance roles.
create view private.auth_users as
select
  auth_user.id,
  auth_user.created_at,
  auth_user.deleted_at
from auth.users as auth_user;

create view private.auth_identities as
select
  identity_row.id,
  identity_row.user_id,
  identity_row.provider_id,
  identity_row.provider,
  identity_row.identity_data,
  identity_row.created_at,
  identity_row.updated_at
from auth.identities as identity_row;

revoke all on private.auth_users, private.auth_identities
  from public, anon, authenticated, service_role, ainigma_maintenance;

create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  display_name text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint profiles_display_name_check check (
    display_name is null
    or (
      display_name = btrim(display_name)
      and char_length(display_name) between 1 and 100
    )
  )
);

comment on table public.profiles is
  'Provider-neutral application identities. Authorization claims remain private.';

create table private.auth_user_links (
  auth_user_id uuid primary key references auth.users (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create index auth_user_links_profile_id_idx
  on private.auth_user_links (profile_id);

create table private.profile_identifiers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete restrict,
  kind text not null,
  issuer text not null,
  scheme_version integer not null,
  normalized_value text not null,
  verified_at timestamptz not null,
  last_verified_at timestamptz not null,
  revoked_at timestamptz,
  source_auth_user_id uuid references auth.users (id) on delete set null,
  provider_identity_id text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint profile_identifiers_kind_check check (
    kind in ('email', 'github_user_id', 'github_username', 'student_identifier')
  ),
  constraint profile_identifiers_issuer_check check (
    issuer = btrim(issuer) and char_length(issuer) between 1 and 255
  ),
  constraint profile_identifiers_scheme_version_check check (scheme_version > 0),
  constraint profile_identifiers_normalized_value_check check (
    normalized_value = btrim(normalized_value)
    and char_length(normalized_value) between 1 and 512
  ),
  constraint profile_identifiers_verification_window_check check (
    last_verified_at >= verified_at
    and (revoked_at is null or revoked_at >= verified_at)
  ),
  constraint profile_identifiers_provider_identity_id_check check (
    provider_identity_id is null
    or char_length(provider_identity_id) between 1 and 255
  )
);

create unique index profile_identifiers_active_identity_uidx
  on private.profile_identifiers (kind, issuer, scheme_version, normalized_value)
  where revoked_at is null;

create index profile_identifiers_profile_active_idx
  on private.profile_identifiers (profile_id, kind, issuer, scheme_version)
  where revoked_at is null;

create index profile_identifiers_source_auth_user_idx
  on private.profile_identifiers (source_auth_user_id)
  where source_auth_user_id is not null;
create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.updated_at := clock_timestamp();
  return new;
end
$function$;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger profile_identifiers_set_updated_at
before update on private.profile_identifiers
for each row execute function private.set_updated_at();
create function private.ensure_auth_user_profile(p_auth_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile_id uuid;
begin
  if p_auth_user_id is null then
    raise exception using errcode = '22004', message = 'auth_user_id_required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_auth_user_id::text, 0)
  );

  perform 1
  from private.auth_users as auth_user
  where auth_user.id = p_auth_user_id;

  if not found then
    raise exception using errcode = '23503', message = 'auth_user_not_found';
  end if;

  select link.profile_id
  into v_profile_id
  from private.auth_user_links as link
  where link.auth_user_id = p_auth_user_id;

  if v_profile_id is not null then
    return v_profile_id;
  end if;

  insert into public.profiles default values
  returning id into v_profile_id;

  insert into private.auth_user_links (auth_user_id, profile_id)
  values (p_auth_user_id, v_profile_id);

  return v_profile_id;
end
$function$;

create function private.handle_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform private.ensure_auth_user_profile(new.id);
  return new;
end
$function$;

create function private.upsert_verified_identifier(
  p_profile_id uuid,
  p_kind text,
  p_issuer text,
  p_scheme_version integer,
  p_normalized_value text,
  p_verified_at timestamptz,
  p_source_auth_user_id uuid,
  p_provider_identity_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_identifier_id uuid;
  v_existing_profile_id uuid;
begin
  select identifier.id, identifier.profile_id
  into v_identifier_id, v_existing_profile_id
  from private.profile_identifiers as identifier
  where identifier.kind = p_kind
    and identifier.issuer = p_issuer
    and identifier.scheme_version = p_scheme_version
    and identifier.normalized_value = p_normalized_value
    and identifier.revoked_at is null
  for update;

  if v_identifier_id is not null then
    if v_existing_profile_id <> p_profile_id then
      raise exception using errcode = '23505', message = 'verified_identifier_conflict';
    end if;

    update private.profile_identifiers
    set last_verified_at = clock_timestamp(),
        source_auth_user_id = p_source_auth_user_id,
        provider_identity_id = p_provider_identity_id
    where id = v_identifier_id;

    return v_identifier_id;
  end if;

  insert into private.profile_identifiers (
    profile_id,
    kind,
    issuer,
    scheme_version,
    normalized_value,
    verified_at,
    last_verified_at,
    source_auth_user_id,
    provider_identity_id
  )
  values (
    p_profile_id,
    p_kind,
    p_issuer,
    p_scheme_version,
    p_normalized_value,
    p_verified_at,
    clock_timestamp(),
    p_source_auth_user_id,
    p_provider_identity_id
  )
  returning id into v_identifier_id;

  return v_identifier_id;
end
$function$;

create function private.sync_auth_identity(p_identity_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_identity record;
  v_profile_id uuid;
  v_username text;
  v_email text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_identity_id::text, 0)
  );

  select identity_row.*
  into v_identity
  from private.auth_identities as identity_row
  where identity_row.id = p_identity_id;

  if not found then
    raise exception using errcode = '23503', message = 'auth_identity_not_found';
  end if;

  v_profile_id := private.ensure_auth_user_profile(v_identity.user_id);

  if v_identity.provider <> 'github' then
    return v_profile_id;
  end if;

  if v_identity.provider_id !~ '^[0-9]+$' then
    raise exception using errcode = '22023', message = 'invalid_github_numeric_subject';
  end if;

  perform private.upsert_verified_identifier(
    v_profile_id,
    'github_user_id',
    'github.com',
    1,
    v_identity.provider_id,
    coalesce(v_identity.created_at, clock_timestamp()),
    v_identity.user_id,
    v_identity.id::text
  );

  v_username := lower(btrim(coalesce(
    v_identity.identity_data ->> 'user_name',
    v_identity.identity_data ->> 'preferred_username',
    v_identity.identity_data ->> 'login'
  )));

  if nullif(v_username, '') is not null then
    update private.profile_identifiers
    set revoked_at = clock_timestamp(),
        last_verified_at = clock_timestamp()
    where profile_id = v_profile_id
      and kind = 'github_username'
      and issuer = 'github.com'
      and scheme_version = 1
      and normalized_value <> v_username
      and revoked_at is null;

    perform private.upsert_verified_identifier(
      v_profile_id,
      'github_username',
      'github.com',
      1,
      v_username,
      coalesce(v_identity.created_at, clock_timestamp()),
      v_identity.user_id,
      v_identity.id::text
    );
  end if;

  if lower(coalesce(v_identity.identity_data ->> 'email_verified', 'false')) = 'true' then
    v_email := lower(btrim(v_identity.identity_data ->> 'email'));

    if nullif(v_email, '') is not null then
      update private.profile_identifiers
      set revoked_at = clock_timestamp(),
          last_verified_at = clock_timestamp()
      where profile_id = v_profile_id
        and kind = 'email'
        and issuer = 'github.com'
        and scheme_version = 1
        and normalized_value <> v_email
        and revoked_at is null;

      perform private.upsert_verified_identifier(
        v_profile_id,
        'email',
        'github.com',
        1,
        v_email,
        coalesce(v_identity.created_at, clock_timestamp()),
        v_identity.user_id,
        v_identity.id::text
      );
    end if;
  end if;

  return v_profile_id;
end
$function$;

create function private.reconcile_auth_users()
returns table (auth_user_id uuid, profile_id uuid, action text)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_auth_user_id uuid;
begin
  for v_auth_user_id in
    select auth_user.id
    from private.auth_users as auth_user
    left join private.auth_user_links as link
      on link.auth_user_id = auth_user.id
    where link.auth_user_id is null
      and auth_user.deleted_at is null
    order by auth_user.created_at, auth_user.id
  loop
    auth_user_id := v_auth_user_id;
    profile_id := private.ensure_auth_user_profile(v_auth_user_id);
    action := 'created_profile_link';
    return next;
  end loop;
end
$function$;

create function private.reconcile_auth_identities()
returns table (auth_identity_id uuid, status text, detail text)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_identity_id uuid;
begin
  for v_identity_id in
    select identity_row.id
    from private.auth_identities as identity_row
    where identity_row.provider = 'github'
    order by identity_row.created_at, identity_row.id
  loop
    auth_identity_id := v_identity_id;

    begin
      perform private.sync_auth_identity(v_identity_id);
      status := 'synced';
      detail := null;
    exception when others then
      status := 'error';
      detail := sqlstate || ':' || sqlerrm;
    end;

    return next;
  end loop;
end
$function$;

create function private.report_identity_anomalies()
returns table (
  anomaly text,
  profile_id uuid,
  auth_user_id uuid,
  auth_identity_id uuid,
  detail text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    'orphan_profile'::text,
    profile.id,
    null::uuid,
    null::uuid,
    'profile has no Auth user link'::text
  from public.profiles as profile
  where not exists (
    select 1
    from private.auth_user_links as link
    where link.profile_id = profile.id
  )

  union all

  select
    'unlinked_auth_identity'::text,
    null::uuid,
    identity_row.user_id,
    identity_row.id,
    'Auth identity user has no application profile link'::text
  from private.auth_identities as identity_row
  where not exists (
    select 1
    from private.auth_user_links as link
    where link.auth_user_id = identity_row.user_id
  );
$function$;

create function private.request_auth_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid();
$function$;

create function private.current_profile_id()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_auth_user_id uuid := private.request_auth_user_id();
  v_profile_id uuid;
begin
  if v_auth_user_id is null then
    raise sqlstate 'PT401' using message = 'authentication_required';
  end if;

  select link.profile_id
  into v_profile_id
  from private.auth_user_links as link
  where link.auth_user_id = v_auth_user_id;

  if v_profile_id is null then
    raise sqlstate 'PT403' using message = 'profile_not_provisioned';
  end if;

  return v_profile_id;
end
$function$;
-- Browser API: every identity is derived from the verified JWT. No function
-- accepts an Auth user ID, profile ID, course UUID, or membership UUID.
create function public.get_my_profile()
returns table (
  display_name text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_profile_id uuid := private.current_profile_id();
begin
  return query
  select profile.display_name, profile.created_at, profile.updated_at
  from public.profiles as profile
  where profile.id = v_profile_id;
end
$function$;

create function public.update_my_profile(p_display_name text)
returns table (
  display_name text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile_id uuid := private.current_profile_id();
begin
  return query
  update public.profiles as profile
  set display_name = p_display_name
  where profile.id = v_profile_id
  returning profile.display_name, profile.created_at, profile.updated_at;
end
$function$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_auth_user_created();
-- The function owner cannot log in. Its table access is constrained by
-- explicit grants; browser access is granted by the authorization schema.
grant usage on schema public, private to ainigma_function_owner;
grant select on private.auth_users, private.auth_identities to ainigma_function_owner;
grant select, insert, update on public.profiles to ainigma_function_owner;
grant select, insert on private.auth_user_links to ainigma_function_owner;
grant select, insert, update on private.profile_identifiers to ainigma_function_owner;
grant create on schema public, private to ainigma_function_owner;

alter function private.ensure_auth_user_profile(uuid) owner to ainigma_function_owner;
alter function private.handle_auth_user_created() owner to ainigma_function_owner;
alter function private.upsert_verified_identifier(uuid, text, text, integer, text, timestamptz, uuid, text) owner to ainigma_function_owner;
alter function private.sync_auth_identity(uuid) owner to ainigma_function_owner;
alter function private.reconcile_auth_users() owner to ainigma_function_owner;
alter function private.reconcile_auth_identities() owner to ainigma_function_owner;
alter function private.report_identity_anomalies() owner to ainigma_function_owner;
alter function private.current_profile_id() owner to ainigma_function_owner;
alter function public.get_my_profile() owner to ainigma_function_owner;
alter function public.update_my_profile(text) owner to ainigma_function_owner;
revoke create on schema public, private from ainigma_function_owner;

-- Maintenance is a NOLOGIN capability role used explicitly by trusted operators
-- or the future control plane.
grant usage on schema private to ainigma_maintenance;

revoke all on function
  private.set_updated_at(),
  private.request_auth_user_id()
from public, anon, authenticated, service_role, ainigma_maintenance;
grant execute on function private.request_auth_user_id() to ainigma_function_owner;

revoke all on function
  private.ensure_auth_user_profile(uuid),
  private.handle_auth_user_created(),
  private.upsert_verified_identifier(uuid, text, text, integer, text, timestamptz, uuid, text),
  private.sync_auth_identity(uuid),
  private.reconcile_auth_users(),
  private.reconcile_auth_identities(),
  private.report_identity_anomalies(),
  private.current_profile_id()
from public, anon, authenticated, service_role, ainigma_maintenance;

grant execute on function private.ensure_auth_user_profile(uuid) to ainigma_maintenance;
grant execute on function private.sync_auth_identity(uuid) to ainigma_maintenance;
grant execute on function private.reconcile_auth_users() to ainigma_maintenance;
grant execute on function private.reconcile_auth_identities() to ainigma_maintenance;
grant execute on function private.report_identity_anomalies() to ainigma_maintenance;
