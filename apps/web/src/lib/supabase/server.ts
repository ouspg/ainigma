import { createServerClient, parseCookieHeader } from "@supabase/ssr";
import type { AstroCookies } from "astro";
import { getSupabasePublicConfig } from "./config";
import type { Database } from "./database.types";

interface ServerClientContext {
  cookies: AstroCookies;
  request: Request;
}

export function createServerSupabaseClient({ cookies, request }: ServerClientContext) {
  const { url, publishableKey } = getSupabasePublicConfig();

  return createServerClient<Database>(url, publishableKey, {
    cookies: {
      getAll() {
        return parseCookieHeader(request.headers.get("Cookie") ?? "");
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value, options }) => cookies.set(name, value, options));
      },
    },
  });
}
