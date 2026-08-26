import type { APIRoute } from "astro";
import { safeNextPath } from "../../lib/auth/redirects";
import { routes } from "../../lib/routes";
import { createServerSupabaseClient } from "../../lib/supabase/server";

export const prerender = false;

function noStore(response: Response): Response {
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}

export const GET: APIRoute = async ({ cookies, redirect, request }) => {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get("code");
  const next = safeNextPath(requestUrl.searchParams.get("next"));

  if (code) {
    const supabase = createServerSupabaseClient({ request, cookies });
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return noStore(redirect(next));
  }

  const login = new URL(routes.login.path(), requestUrl.origin);
  login.searchParams.set("error", "auth_callback");
  login.searchParams.set("next", next);
  return noStore(redirect(`${login.pathname}${login.search}`));
};
