set local check_function_bodies = off;

create or replace function private.handle_auth_identity_changed()
  returns trigger
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
begin
  perform private.sync_auth_identity(new.id);
  return new;
end
$function$;

alter function "private"."handle_auth_identity_changed"() owner to "ainigma_function_owner";

create trigger on_auth_identity_changed
  after insert or update of provider_id, identity_data, provider on auth.identities
  for each row
  execute function private.handle_auth_identity_changed();

revoke all on function "private"."handle_auth_identity_changed"() from public;
