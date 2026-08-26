import type { APIRoute } from "astro";
import { safeNextPath } from "../lib/auth/redirects";
import { markPrivateNoStore } from "../lib/http/response-cache";
import { routes } from "../lib/routes";
import { isLocalAuthEnabled } from "./dev-local-auth";
import { createLocalSupabaseAdmin, getLocalAuthPersona } from "./dev-local-auth-server";

export const prerender = false;

export const GET: APIRoute = async ({ redirect, request }) => {
  const requestUrl = new URL(request.url);
  const isLoopbackHost = ["localhost", "127.0.0.1", "[::1]", "::1"].includes(requestUrl.hostname);

  if (!isLocalAuthEnabled() || !isLoopbackHost) {
    return markPrivateNoStore(new Response("Not found", { status: 404 }));
  }

  const persona = getLocalAuthPersona(requestUrl.searchParams.get("persona"));
  if (!persona) {
    return markPrivateNoStore(new Response("Unknown local auth persona.", { status: 400 }));
  }

  try {
    const { data, error } = await createLocalSupabaseAdmin().auth.admin.generateLink({
      type: "magiclink",
      email: persona.email,
    });

    if (error || !data?.properties?.hashed_token || data.user?.id !== persona.userId) {
      return markPrivateNoStore(
        new Response("Unable to create local auth session.", { status: 503 }),
      );
    }

    const callback = new URL(routes.authCallback.path(), requestUrl.origin);
    callback.searchParams.set("next", safeNextPath(requestUrl.searchParams.get("next")));
    callback.searchParams.set("token_hash", data.properties.hashed_token);
    callback.searchParams.set("type", "magiclink");
    return markPrivateNoStore(redirect(`${callback.pathname}${callback.search}`));
  } catch {
    return markPrivateNoStore(new Response("Local auth is not configured.", { status: 503 }));
  }
};
