import { markPrivateNoStore } from "../http/response-cache";
import type { AppRouteMatch } from "../routes";

export function routeRequiresPrivateResponse(route: AppRouteMatch): boolean {
  return (
    route.id === "home" || ["guestOnly", "authenticated", "coursePublic"].includes(route.access)
  );
}

export function applyRouteResponseCachePolicy(route: AppRouteMatch, response: Response): Response {
  return routeRequiresPrivateResponse(route) ? markPrivateNoStore(response) : response;
}
