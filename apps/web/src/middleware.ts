import { defineMiddleware } from "astro:middleware";
import {
  enforceRouteAccess,
  responseWithoutSharedCaching,
  routeUsesPrivateSession,
} from "./lib/auth/route-access";
import { matchAppRoute } from "./lib/routes";

export const onRequest = defineMiddleware(async (context, next) => {
  const route = matchAppRoute(new URL(context.request.url).pathname);
  if (!route) return next();

  const accessResponse = await enforceRouteAccess(context, route);
  if (accessResponse) return accessResponse;

  const response = await next();
  return routeUsesPrivateSession(route) ? responseWithoutSharedCaching(response) : response;
});
