-- Read-only effective-access audit for the application and Supabase API roles.
-- Run with:
--   ./node_modules/.bin/supabase db query --local --file supabase/audit_access.sql
-- or:
--   ./node_modules/.bin/supabase db query --linked --file supabase/audit_access.sql
-- Add new application roles or schemas to the two lists below.

with audit_roles(role_name) as (
  values
    ('anon'::name),
    ('authenticated'::name),
    ('service_role'::name),
    ('ainigma_function_owner'::name),
    ('ainigma_maintenance'::name)
),
audit_schemas(schema_name) as (
  values
    ('public'::name),
    ('graphql_public'::name),
    ('private'::name)
),
schema_privileges as (
  select
    'schema'::text as section,
    r.role_name::text,
    n.nspname::text as schema_name,
    null::text as object_name,
    p.privilege_type::text,
    jsonb_build_object('allowed', p.allowed) as details
  from audit_roles r
  cross join pg_namespace n
  cross join lateral (values
    ('USAGE', has_schema_privilege(r.role_name, n.oid, 'USAGE')),
    ('CREATE', has_schema_privilege(r.role_name, n.oid, 'CREATE'))
  ) p(privilege_type, allowed)
  where n.nspname in (select schema_name from audit_schemas)
    and p.allowed
),
database_privileges as (
  select
    'database'::text as section,
    r.role_name::text,
    null::text as schema_name,
    current_database()::text as object_name,
    p.privilege_type::text,
    jsonb_build_object('allowed', p.allowed) as details
  from audit_roles r
  cross join lateral (values
    ('CONNECT', has_database_privilege(r.role_name, current_database(), 'CONNECT')),
    ('CREATE', has_database_privilege(r.role_name, current_database(), 'CREATE')),
    ('TEMPORARY', has_database_privilege(r.role_name, current_database(), 'TEMPORARY'))
  ) p(privilege_type, allowed)
  where p.allowed
),
relation_privileges as (
  select
    'relation'::text as section,
    r.role_name::text,
    n.nspname::text as schema_name,
    c.relname::text as object_name,
    p.privilege_type::text,
    jsonb_build_object('relkind', c.relkind) as details
  from audit_roles r
  cross join pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral (values
    ('SELECT', has_table_privilege(r.role_name, c.oid, 'SELECT')),
    ('INSERT', has_table_privilege(r.role_name, c.oid, 'INSERT')),
    ('UPDATE', has_table_privilege(r.role_name, c.oid, 'UPDATE')),
    ('DELETE', has_table_privilege(r.role_name, c.oid, 'DELETE')),
    ('REFERENCES', has_table_privilege(r.role_name, c.oid, 'REFERENCES')),
    ('TRIGGER', has_table_privilege(r.role_name, c.oid, 'TRIGGER')),
    ('TRUNCATE', has_table_privilege(r.role_name, c.oid, 'TRUNCATE')),
    ('MAINTAIN', has_table_privilege(r.role_name, c.oid, 'MAINTAIN'))
  ) p(privilege_type, allowed)
  where n.nspname in (select schema_name from audit_schemas)
    and c.relkind in ('r', 'p', 'v', 'm', 'f')
    and p.allowed
),
sequence_privileges as (
  select
    'sequence'::text as section,
    r.role_name::text,
    n.nspname::text as schema_name,
    c.relname::text as object_name,
    p.privilege_type::text,
    '{}'::jsonb as details
  from audit_roles r
  cross join pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral (values
    ('USAGE', has_sequence_privilege(r.role_name, c.oid, 'USAGE')),
    ('SELECT', has_sequence_privilege(r.role_name, c.oid, 'SELECT')),
    ('UPDATE', has_sequence_privilege(r.role_name, c.oid, 'UPDATE'))
  ) p(privilege_type, allowed)
  where n.nspname in (select schema_name from audit_schemas)
    and c.relkind = 'S'
    and p.allowed
),
function_privileges as (
  select
    'function'::text as section,
    r.role_name::text,
    n.nspname::text as schema_name,
    p.proname::text as object_name,
    'EXECUTE'::text as privilege_type,
    jsonb_build_object(
      'arguments', pg_get_function_identity_arguments(p.oid),
      'security_definer', p.prosecdef,
      'owner', pg_get_userbyid(p.proowner)
    ) as details
  from audit_roles r
  cross join pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in (select schema_name from audit_schemas)
    and has_function_privilege(r.role_name, p.oid, 'EXECUTE')
),
rls_status as (
  select
    'rls'::text as section,
    null::text as role_name,
    n.nspname::text as schema_name,
    c.relname::text as object_name,
    'STATUS'::text as privilege_type,
    jsonb_build_object(
      'rls_enabled', c.relrowsecurity,
      'rls_forced', c.relforcerowsecurity
    ) as details
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in (select schema_name from audit_schemas)
    and c.relkind in ('r', 'p')
),
policy_rules as (
  select
    'policy'::text as section,
    null::text as role_name,
    schemaname::text as schema_name,
    tablename::text as object_name,
    cmd::text as privilege_type,
    jsonb_build_object(
      'policy', policyname,
      'roles', roles,
      'permissive', permissive,
      'using', qual,
      'with_check', with_check
    ) as details
  from pg_policies
  where schemaname in (select schema_name from audit_schemas)
),
role_attributes as (
  select
    'role'::text as section,
    r.rolname::text as role_name,
    null::text as schema_name,
    null::text as object_name,
    'ATTRIBUTES'::text as privilege_type,
    jsonb_build_object(
      'superuser', r.rolsuper,
      'inherit', r.rolinherit,
      'create_role', r.rolcreaterole,
      'create_db', r.rolcreatedb,
      'can_login', r.rolcanlogin,
      'replication', r.rolreplication,
      'bypass_rls', r.rolbypassrls
    ) as details
  from pg_roles r
  where r.rolname in (select role_name from audit_roles)
),
role_memberships as (
  select
    'membership'::text as section,
    member.rolname::text as role_name,
    null::text as schema_name,
    null::text as object_name,
    'GRANTED_ROLE'::text as privilege_type,
    jsonb_build_object(
      'granted_role', granted.rolname,
      'admin_option', m.admin_option
    ) as details
  from pg_auth_members m
  join pg_roles member on member.oid = m.member
  join pg_roles granted on granted.oid = m.roleid
  where member.rolname in (select role_name from audit_roles)
     or granted.rolname in (select role_name from audit_roles)
),
default_privileges as (
  select
    'default_privilege'::text as section,
    case when grant_item.grantee = 0 then 'PUBLIC' else grantee.rolname end::text as role_name,
    coalesce(n.nspname, '*')::text as schema_name,
    case d.defaclobjtype
      when 'r' then 'TABLES'
      when 'S' then 'SEQUENCES'
      when 'f' then 'FUNCTIONS'
      when 'T' then 'TYPES'
      when 'n' then 'SCHEMAS'
      else d.defaclobjtype::text
    end as object_name,
    grant_item.privilege_type::text,
    jsonb_build_object(
      'owner_role', owner_role.rolname,
      'grantable', grant_item.is_grantable
    ) as details
  from pg_default_acl d
  join pg_roles owner_role on owner_role.oid = d.defaclrole
  left join pg_namespace n on n.oid = d.defaclnamespace
  cross join lateral aclexplode(d.defaclacl) grant_item
  left join pg_roles grantee on grantee.oid = grant_item.grantee
  where (n.nspname in (select schema_name from audit_schemas) or d.defaclnamespace = 0)
    and (
      grant_item.grantee = 0
      or grantee.rolname in (select role_name from audit_roles)
    )
)
select * from schema_privileges
union all select * from database_privileges
union all select * from relation_privileges
union all select * from sequence_privileges
union all select * from function_privileges
union all select * from rls_status
union all select * from policy_rules
union all select * from role_attributes
union all select * from role_memberships
union all select * from default_privileges
order by section, role_name nulls last, schema_name nulls last, object_name nulls last, privilege_type;
