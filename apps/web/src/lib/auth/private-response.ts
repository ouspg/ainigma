import { markPrivateNoStore } from "../http/response-cache";
import type { AppRouteMatch } from "../routes";

export function routeRequiresPrivateResponse(route: AppRouteMatch): boolean {
  return ["guestOnly", "authenticated", "courseMember"].includes(route.access);
}

export function applyRouteResponseCachePolicy(route: AppRouteMatch, response: Response): Response {
  return routeRequiresPrivateResponse(route) ? markPrivateNoStore(response) : response;
}
