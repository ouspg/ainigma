import { defineMiddleware } from "astro:middleware";
import type { APIContext } from "astro";
import {
  authorizeRouteRequest,
  markResponsePrivate,
  routeRequiresPrivateResponse,
} from "./lib/auth/route-access";
import {
  addTraceHeaders,
  logRequestComplete,
  logRequestError,
  logRequestStart,
  startRequestTrace,
} from "./lib/observability/request-tracing";
import { matchAppRoute, routes, type AppRouteMatch } from "./lib/routes";

async function handleRequest(
  context: APIContext,
  next: () => Promise<Response>,
  matchedRoute: AppRouteMatch | null,
): Promise<Response> {
  if (!matchedRoute) return next();

  const accessDenialResponse = await authorizeRouteRequest(context, matchedRoute);
  if (accessDenialResponse) return accessDenialResponse;

  const renderedResponse = await next();
  if (renderedResponse.status === 404 && matchedRoute.id !== "status") {
    return context.rewrite(new URL(routes.status.path({ code: "404" }), context.url));
  }
  return routeRequiresPrivateResponse(matchedRoute)
    ? markResponsePrivate(renderedResponse)
    : renderedResponse;
}

export const onRequest = defineMiddleware(async (context, next) => {
  const matchedRoute = matchAppRoute(new URL(context.request.url).pathname);
  if (context.isPrerendered) return handleRequest(context, next, matchedRoute);

  const route = matchedRoute?.id ?? "unmatched";
  const trace = startRequestTrace(context.request);
  context.locals.traceId = trace.traceId;
  logRequestStart(context, trace, route);

  try {
    const response = await handleRequest(context, next, matchedRoute);
    logRequestComplete(context, trace, route, response.status);
    return addTraceHeaders(response, trace);
  } catch (error) {
    logRequestError(context, trace, route, error);
    throw error;
  }
});
