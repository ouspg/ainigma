begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(34);

select extensions.has_table('public', 'profiles', 'profiles table exists');
select extensions.has_table('private', 'auth_user_links', 'Auth link table exists');
select extensions.has_table('private', 'profile_identifiers', 'trusted identifier table exists');

select extensions.ok(
  not (select rolcanlogin from pg_roles where rolname = 'ainigma_function_owner'),
  'function owner cannot log in'
);
select extensions.ok(
  not (select rolbypassrls from pg_roles where rolname = 'ainigma_function_owner'),
  'function owner does not bypass RLS'
);
insert into auth.users (
  id,
  aud,
  role,
  email,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '10000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'first@example.test',
    '{"provider":"github","providers":["github"]}',
    '{}',
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '10000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'second@example.test',
    '{"provider":"github","providers":["github"]}',
    '{}',
    clock_timestamp(),
    clock_timestamp()
  );

select extensions.is(
  (
    select count(*)::bigint
    from public.profiles as profile
    where exists (
      select 1
      from private.auth_user_links as link
      where link.profile_id = profile.id
        and link.auth_user_id in (
          '10000000-0000-0000-0000-000000000001',
          '10000000-0000-0000-0000-000000000002'
        )
    )
  ),
  2::bigint,
  'Auth inserts create exactly one profile each'
);
select extensions.is(
  (
    select count(*)::bigint
    from private.auth_user_links
    where auth_user_id in (
      '10000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000002'
    )
  ),
  2::bigint,
  'Auth inserts create exactly one link each'
);
select extensions.is(
  (
    select count(distinct profile_id)::bigint
    from private.auth_user_links
    where auth_user_id in (
      '10000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000002'
    )
  ),
  2::bigint,
  'different Auth users are not merged by metadata'
);

grant ainigma_maintenance to postgres;
set role ainigma_maintenance;
select private.ensure_auth_user_profile('10000000-0000-0000-0000-000000000001');
reset role;
revoke ainigma_maintenance from postgres;

select extensions.is(
  (
    select count(*)::bigint
    from private.auth_user_links
    where auth_user_id in (
      '10000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000002'
    )
  ),
  2::bigint,
  'profile reconciliation is idempotent'
);

insert into auth.identities (
  id,
  provider_id,
  user_id,
  identity_data,
  provider,
  created_at,
  updated_at
)
values (
  '20000000-0000-0000-0000-000000000001',
  '12345678',
  '10000000-0000-0000-0000-000000000001',
  '{"sub":"12345678","user_name":"FirstStudent","email":"first@example.test","email_verified":true}',
  'github',
  clock_timestamp(),
  clock_timestamp()
);

grant ainigma_maintenance to postgres;
set role ainigma_maintenance;
select private.sync_auth_identity('20000000-0000-0000-0000-000000000001');
reset role;
revoke ainigma_maintenance from postgres;

select extensions.is(
  (
    select count(*)::bigint
    from private.profile_identifiers
    where kind = 'github_user_id'
      and normalized_value = '12345678'
      and revoked_at is null
  ),
  1::bigint,
  'GitHub numeric subject is synchronized as the stable identifier'
);
select extensions.is(
  (
    select count(*)::bigint
    from private.profile_identifiers
    where kind = 'github_username'
      and normalized_value = 'firststudent'
      and revoked_at is null
  ),
  1::bigint,
  'GitHub username is synchronized as a lowercase alias'
);
select extensions.is(
  (
    select count(*)::bigint
    from private.profile_identifiers
    where kind = 'email'
      and normalized_value = 'first@example.test'
      and revoked_at is null
  ),
  1::bigint,
  'provider-verified email is synchronized'
);

update auth.identities
set identity_data = jsonb_set(identity_data, '{user_name}', '"RenamedStudent"'),
    updated_at = clock_timestamp()
where id = '20000000-0000-0000-0000-000000000001';

grant ainigma_maintenance to postgres;
set role ainigma_maintenance;
select private.sync_auth_identity('20000000-0000-0000-0000-000000000001');
reset role;
revoke ainigma_maintenance from postgres;

select extensions.is(
  (
    select count(*)::bigint
    from private.profile_identifiers
    where kind = 'github_username'
      and normalized_value = 'firststudent'
      and revoked_at is not null
  ),
  1::bigint,
  'renaming a GitHub user retires the old alias'
);
select extensions.is(
  (
    select count(*)::bigint
    from private.profile_identifiers
    where kind = 'github_username'
      and normalized_value = 'renamedstudent'
      and revoked_at is null
  ),
  1::bigint,
  'renaming a GitHub user creates the new active alias'
);

update auth.users
set raw_user_meta_data = '{"user_name":"attacker-controlled","course_role":"owner"}'
where id = '10000000-0000-0000-0000-000000000001';

grant ainigma_maintenance to postgres;
set role ainigma_maintenance;
select private.sync_auth_identity('20000000-0000-0000-0000-000000000001');
reset role;
revoke ainigma_maintenance from postgres;

select extensions.is(
  (
    select count(*)::bigint
    from private.profile_identifiers
    where normalized_value = 'attacker-controlled'
  ),
  0::bigint,
  'user-editable Auth metadata is not trusted'
);

select extensions.has_index(
  'private',
  'profile_identifiers',
  'profile_identifiers_active_identity_uidx',
  'active identifiers have a tuple-wide unique index'
);
select extensions.ok(
  not has_schema_privilege('authenticated', 'private', 'USAGE'),
  'authenticated has no direct private schema access'
);
select extensions.ok(
  not has_table_privilege('anon', 'public.profiles', 'SELECT'),
  'anonymous users cannot select profiles'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.profiles', 'SELECT'),
  'authenticated users cannot read profiles directly'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.profiles', 'INSERT'),
  'authenticated users cannot insert profiles'
);
select extensions.ok(
  not has_column_privilege('authenticated', 'public.profiles', 'display_name', 'UPDATE'),
  'authenticated users cannot update profiles directly'
);
select extensions.ok(
  not has_column_privilege('authenticated', 'public.profiles', 'id', 'UPDATE'),
  'authenticated users cannot update profile identity'
);
select extensions.is(
  (
    select pg_get_userbyid(proowner)
    from pg_proc
    where oid = 'private.current_profile_id()'::regprocedure
  ),
  'ainigma_function_owner'::name,
  'authorization helper has the dedicated owner'
);
select extensions.ok(
  (
    select prosecdef
    from pg_proc
    where oid = 'private.current_profile_id()'::regprocedure
  ),
  'authorization helper is security definer'
);
select extensions.ok(
  (
    select proconfig @> array['search_path=""']::text[]
    from pg_proc
    where oid = 'private.current_profile_id()'::regprocedure
  ),
  'authorization helper has an empty search path'
);
select extensions.ok(
  not has_function_privilege('anon', 'private.current_profile_id()', 'EXECUTE'),
  'anonymous users cannot execute authorization helpers'
);
select extensions.ok(
  not has_function_privilege('authenticated', 'private.ensure_auth_user_profile(uuid)', 'EXECUTE'),
  'browser users cannot execute reconciliation functions'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.get_my_profile()', 'EXECUTE'),
  'authenticated users can call the profile RPC'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.get_my_profile()', 'EXECUTE'),
  'anonymous users cannot call the profile RPC'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.get_my_course_repository(text)', 'EXECUTE'),
  'authenticated users can inspect their course repository request'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.get_my_course_repository(text)', 'EXECUTE'),
  'anonymous users cannot inspect course repository requests'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.request_my_course_repository(text)', 'EXECUTE'),
  'authenticated users can request their course repository'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.request_my_course_repository(text)', 'EXECUTE'),
  'anonymous users cannot request course repositories'
);
select extensions.ok(
  not exists (
    select 1
    from pg_proc as function_row
    join pg_namespace as schema_row
      on schema_row.oid = function_row.pronamespace
    where schema_row.nspname = 'public'
      and function_row.proname in (
        'get_my_profile',
        'update_my_profile',
        'list_my_courses',
        'list_course_roster',
        'get_my_course_repository',
        'request_my_course_repository'
      )
      and pg_catalog.oidvectortypes(function_row.proargtypes) like '%uuid%'
  ),
  'public browser RPCs accept no UUID arguments'
);

select * from extensions.finish();
rollback;
