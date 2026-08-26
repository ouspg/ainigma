import { createBrowserClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";
import { getSupabasePublicConfig } from "./config";
import type { Database } from "./database.types";

let browserClient: SupabaseClient<Database> | undefined;

export function createBrowserSupabaseClient(): SupabaseClient<Database> {
  if (browserClient) return browserClient;

  const { url, publishableKey } = getSupabasePublicConfig();
  browserClient = createBrowserClient<Database>(url, publishableKey);
  return browserClient;
}
