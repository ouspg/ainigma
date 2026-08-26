import { createClient } from "@supabase/supabase-js";
import { getSupabasePublicConfig } from "../lib/supabase/config";
import type { Database } from "../lib/supabase/database.types";
import { isLocalAuthPersona, type LocalAuthPersona } from "./dev-local-auth";

interface LocalAuthPersonaRecord {
  email: string;
  userId: string;
}

const localAuthPersonaRecords: Record<LocalAuthPersona, LocalAuthPersonaRecord> = {
  emptyLearner: {
    email: "empty-learner@local.ainigma",
    userId: "50000000-0000-0000-0000-000000000003",
  },
  pendingLearner: {
    email: "pending-learner@local.ainigma",
    userId: "50000000-0000-0000-0000-000000000004",
  },
  memberLearner: {
    email: "learner@local.ainigma",
    userId: "50000000-0000-0000-0000-000000000002",
  },
  owner: {
    email: "owner@local.ainigma",
    userId: "50000000-0000-0000-0000-000000000001",
  },
};

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
