-- Custom non-login roles used by the application-owned database functions.
-- Keep this file idempotent: local resets and deployments may run it more than once.
do $roles$
begin
  if not exists (select 1 from pg_roles where rolname = 'ainigma_function_owner') then
    create role ainigma_function_owner nologin noinherit;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'ainigma_maintenance') then
    create role ainigma_maintenance nologin noinherit;
  end if;
end
$roles$;

grant ainigma_function_owner to postgres;
grant ainigma_maintenance to postgres;
