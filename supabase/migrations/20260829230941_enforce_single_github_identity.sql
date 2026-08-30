set local check_function_bodies = off;

create or replace function private.upsert_verified_identifier (
  p_profile_id           uuid,
  p_kind                 text,
  p_issuer               text,
  p_scheme_version       integer,
  p_normalized_value     text,
  p_verified_at          timestamp with time zone,
  p_source_auth_user_id  uuid,
  p_provider_identity_id text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_identifier_id uuid;
  v_existing_profile_id uuid;
begin
  if p_kind = 'external_user_id'
    and exists (
      select 1
      from private.profile_identifiers as identifier
      where identifier.profile_id = p_profile_id
        and identifier.kind = p_kind
        and identifier.issuer = p_issuer
        and identifier.scheme_version = p_scheme_version
        and identifier.normalized_value <> p_normalized_value
        and identifier.revoked_at is null
    )
  then
    raise exception using errcode = '23505', message = 'verified_identifier_conflict';
  end if;

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

create unique index profile_identifiers_active_github_user_uidx on private.profile_identifiers using btree (profile_id, issuer, scheme_version)
  where ((kind = 'external_user_id'::text) AND (revoked_at is null));
