import type { APIRoute } from "astro";
import { safeNextPath } from "../../lib/auth/redirects";
import { markPrivateNoStore } from "../../lib/http/response-cache";
import { routes } from "../../lib/routes";
import { createServerSupabaseClient } from "../../lib/supabase/server";

export const prerender = false;

export const GET: APIRoute = async ({ cookies, redirect, request }) => {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get("code");
  const tokenHash = requestUrl.searchParams.get("token_hash");
  const tokenType = requestUrl.searchParams.get("type");
  const next = safeNextPath(requestUrl.searchParams.get("next"));

  if (code) {
    const supabase = createServerSupabaseClient({ request, cookies });
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return markPrivateNoStore(redirect(next));
  }

  if (tokenHash && tokenType === "magiclink") {
    const supabase = createServerSupabaseClient({ request, cookies });
    const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: "magiclink" });
    if (!error) return markPrivateNoStore(redirect(next));
  }

  const login = new URL(routes.login.path(), requestUrl.origin);
  login.searchParams.set("error", "auth_callback");
  login.searchParams.set("next", next);
  return markPrivateNoStore(redirect(`${login.pathname}${login.search}`));
};
