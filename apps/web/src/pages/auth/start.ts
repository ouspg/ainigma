import type { APIContext, APIRoute } from "astro";
import { safeNextPath } from "../../lib/auth/redirects";
import { markPrivateNoStore } from "../../lib/http/response-cache";
import { routes } from "../../lib/routes";
import { createServerSupabaseClient } from "../../lib/supabase/server";

export const prerender = false;

function loginErrorRedirect(
  redirect: APIContext["redirect"],
  requestUrl: URL,
  next: string,
): Response {
  const login = new URL(routes.login.path(), requestUrl.origin);
  login.searchParams.set("error", "auth_start");
  login.searchParams.set("next", next);
  return markPrivateNoStore(redirect(`${login.pathname}${login.search}`, 303));
}

export const POST: APIRoute = async ({ cookies, redirect, request }) => {
  const requestUrl = new URL(request.url);
  const origin = request.headers.get("Origin");
  if (origin !== requestUrl.origin) {
    return markPrivateNoStore(new Response("Invalid login request", { status: 403 }));
  }

  const formData = await request.formData();
  const submittedNext = formData.get("next");
  const next = safeNextPath(typeof submittedNext === "string" ? submittedNext : null);
  const callbackUrl = new URL(routes.authCallback.path(), requestUrl.origin);
  callbackUrl.searchParams.set("next", next);

  const supabase = createServerSupabaseClient({ request, cookies });
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: "github",
    options: { redirectTo: callbackUrl.toString() },
  });

  if (error || !data.url) {
    return loginErrorRedirect(redirect, requestUrl, next);
  }
  return markPrivateNoStore(redirect(data.url, 303));
};
