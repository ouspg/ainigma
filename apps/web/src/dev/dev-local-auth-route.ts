import type { APIRoute } from "astro";
import { safeNextPath } from "../lib/auth/redirects";
import { routes } from "../lib/routes";
import { isLocalAuthEnabled } from "./dev-local-auth";
import {
  createLocalSupabaseAdmin,
  getLocalAuthPersona,
} from "./dev-local-auth-server";

export const prerender = false;

function noStore(response: Response): Response {
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}

export const GET: APIRoute = async ({ redirect, request }) => {
  const requestUrl = new URL(request.url);
  const isLoopbackHost = ["localhost", "127.0.0.1", "[::1]", "::1"].includes(requestUrl.hostname);

  if (!isLocalAuthEnabled() || !isLoopbackHost) {
    return new Response("Not found", { status: 404 });
  }

  const persona = getLocalAuthPersona(requestUrl.searchParams.get("persona"));
  if (!persona) {
    return noStore(new Response("Unknown local auth persona.", { status: 400 }));
  }

  try {
    const { data, error } = await createLocalSupabaseAdmin().auth.admin.generateLink({
      type: "magiclink",
      email: persona.email,
    });

    if (error || !data?.properties?.hashed_token || data.user?.id !== persona.userId) {
      return noStore(new Response("Unable to create local auth session.", { status: 503 }));
    }

    const callback = new URL(routes.authCallback.path(), requestUrl.origin);
    callback.searchParams.set("next", safeNextPath(requestUrl.searchParams.get("next")));
    callback.searchParams.set("token_hash", data.properties.hashed_token);
    callback.searchParams.set("type", "magiclink");
    return noStore(redirect(`${callback.pathname}${callback.search}`));
  } catch {
    return noStore(new Response("Local auth is not configured.", { status: 503 }));
  }
};
