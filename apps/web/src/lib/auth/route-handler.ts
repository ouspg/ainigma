import type { APIContext } from "astro";
import { routes, type AppRouteMatch } from "../routes";
import { applyRouteResponseCachePolicy } from "./private-response";

export type RouteAuthorizer = (
  context: APIContext,
  route: AppRouteMatch,
) => Promise<Response | null>;

/** Applies authorization, status rewrites, and cache policy for a matched page route. */
export async function handleRouteRequest(
  context: APIContext,
  next: () => Promise<Response>,
  matchedRoute: AppRouteMatch | null,
  authorizeRoute: RouteAuthorizer,
): Promise<Response> {
  if (!matchedRoute) return next();

  const accessDenialResponse = await authorizeRoute(context, matchedRoute);
  if (accessDenialResponse) {
    return applyRouteResponseCachePolicy(matchedRoute, accessDenialResponse);
  }

  const renderedResponse = await next();
  if (renderedResponse.status === 404 && matchedRoute.id !== "status") {
    const notFoundResponse = await context.rewrite(
      new URL(routes.status.path({ code: "404" }), context.url),
    );
    return applyRouteResponseCachePolicy(matchedRoute, notFoundResponse);
  }
  return applyRouteResponseCachePolicy(matchedRoute, renderedResponse);
}
