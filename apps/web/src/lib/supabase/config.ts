interface SupabasePublicConfig {
  publishableKey: string;
  url: string;
}

export function getSupabasePublicConfig(): SupabasePublicConfig {
  const url = import.meta.env.PUBLIC_SUPABASE_URL;
  const publishableKey = import.meta.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  // Copy apps/web/.env.example to apps/web/.env.local and use values from `supabase status --output env` in local development.
  if (!url || !publishableKey) {
    throw new Error("Missing PUBLIC_SUPABASE_URL or PUBLIC_SUPABASE_PUBLISHABLE_KEY. ");
  }

  return { url, publishableKey };
}
