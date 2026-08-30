-- Custom non-login roles used by the application-owned database functions.
-- Keep this file idempotent: local resets and deployments may run it more than once.
-- Migration sessions must reject compiler-detectable PL/pgSQL hazards, not merely log warnings.
alter role postgres set plpgsql.extra_errors = 'all';

do $roles$
begin
  if not exists (select 1 from pg_roles where rolname = 'ainigma_function_owner') then
    create role ainigma_function_owner nologin noinherit;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'ainigma_maintenance') then
    create role ainigma_maintenance nologin noinherit;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'ainigma_external_provisioning_worker') then
    create role ainigma_external_provisioning_worker nologin noinherit;
  end if;
end
$roles$;

grant ainigma_function_owner to postgres;
grant ainigma_maintenance to postgres;
grant ainigma_external_provisioning_worker to postgres;
grant usage on schema extensions to ainigma_maintenance;

-- Function ownership transfers in generated migrations require the target role
-- to have CREATE on the containing schema before any migration is applied.
-- Keep this bootstrap idempotent and mirror its durable state in schemas/.
create schema if not exists private;
grant usage, create on schema public, private to ainigma_function_owner;
