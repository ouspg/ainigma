import { defineMiddleware } from "astro:middleware";
import { authorizeRouteRequest } from "./lib/auth/route-access";
import { handleRouteRequest } from "./lib/auth/route-handler";
import {
  addTraceHeaders,
  logRequestComplete,
  logRequestError,
  logRequestStart,
  startRequestTrace,
} from "./lib/observability/request-tracing";
import { matchAppRoute } from "./lib/routes";

export const onRequest = defineMiddleware(async (context, next) => {
  const matchedRoute = matchAppRoute(new URL(context.request.url).pathname);
  if (context.isPrerendered) {
    return handleRouteRequest(context, next, matchedRoute, authorizeRouteRequest);
  }

  const route = matchedRoute?.id ?? "unmatched";
  const trace = startRequestTrace(context.request);
  context.locals.traceId = trace.traceId;
  logRequestStart(context, trace, route);

  try {
    const response = await handleRouteRequest(context, next, matchedRoute, authorizeRouteRequest);
    logRequestComplete(context, trace, route, response.status);
    return addTraceHeaders(response, trace);
  } catch (error) {
    logRequestError(context, trace, route, error);
    throw error;
  }
});
