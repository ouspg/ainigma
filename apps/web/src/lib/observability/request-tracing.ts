import type { APIContext } from "astro";

const TRACEPARENT_PATTERN = /^00-([\da-f]{32})-([\da-f]{16})-[\da-f]{2}$/i;

export interface RequestTrace {
  traceId: string;
  spanId: string;
  startedAt: number;
}

function randomHex(length: number): string {
  return crypto.randomUUID().replaceAll("-", "").slice(0, length);
}

export function startRequestTrace(request: Request): RequestTrace {
  const traceparent = request.headers.get("traceparent")?.match(TRACEPARENT_PATTERN);
  return {
    traceId: traceparent?.[1] ?? randomHex(32),
    spanId: randomHex(16),
    startedAt: performance.now(),
  };
}

export function requestDurationMs(trace: RequestTrace): number {
  return Math.round((performance.now() - trace.startedAt) * 100) / 100;
}

export function addTraceHeaders(response: Response, trace: RequestTrace): Response {
  response.headers.set("X-Request-ID", trace.traceId);
  response.headers.set("Server-Timing", `app;dur=${requestDurationMs(trace)}`);
  return response;
}

export function logRequestStart(context: APIContext, trace: RequestTrace, route: string): void {
  console.info("[ainigma trace]", {
    event: "request.start",
    trace_id: trace.traceId,
    span_id: trace.spanId,
    http_request_method: context.request.method,
    url_path: new URL(context.request.url).pathname,
    route,
  });
}

export function logRequestComplete(
  context: APIContext,
  trace: RequestTrace,
  route: string,
  status: number,
): void {
  console.info("[ainigma trace]", {
    event: "request.complete",
    trace_id: trace.traceId,
    span_id: trace.spanId,
    http_request_method: context.request.method,
    route,
    http_response_status_code: status,
    http_server_request_duration_ms: requestDurationMs(trace),
  });
}

export function logRequestError(
  context: APIContext,
  trace: RequestTrace,
  route: string,
  error: unknown,
): void {
  console.error("[ainigma trace]", {
    event: "request.error",
    trace_id: trace.traceId,
    span_id: trace.spanId,
    http_request_method: context.request.method,
    route,
    http_server_request_duration_ms: requestDurationMs(trace),
    error,
  });
}
