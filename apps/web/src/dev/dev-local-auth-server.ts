import { createClient } from "@supabase/supabase-js";
import { getSupabasePublicConfig } from "../lib/supabase/config";
import type { Database } from "../lib/supabase/database.types";
import { isLocalAuthPersona } from "./dev-local-auth";
import { localAuthPersonaRecords, type LocalAuthPersonaRecord } from "./dev-local-auth.generated";

export function getLocalAuthPersona(value: string | null): LocalAuthPersonaRecord | null {
  return isLocalAuthPersona(value) ? localAuthPersonaRecords[value] : null;
}

export function createLocalSupabaseAdmin() {
  const { url } = getSupabasePublicConfig();
  const secretKey =
    import.meta.env.SUPABASE_SECRET_KEY ?? import.meta.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!secretKey) {
    throw new Error(
      "Local auth requires SUPABASE_SECRET_KEY or SUPABASE_SERVICE_ROLE_KEY in the server environment.",
    );
  }

  return createClient<Database>(url, secretKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  });
}
