import type { APIContext } from "astro";
import { describe, expect, it } from "vite-plus/test";
import { handleRouteRequest } from "./lib/auth/route-handler";
import type { AppRouteMatch } from "./lib/routes";
import { PRIVATE_NO_STORE_CACHE_CONTROL } from "./lib/http/response-cache";

function route(access: AppRouteMatch["access"]): AppRouteMatch {
  return {
    access,
    id: "desk",
    params: {},
    pathname: "/desk/",
  };
}

function context(rewrite?: APIContext["rewrite"]): APIContext {
  return {
    rewrite: rewrite ?? (async () => new Response("Not found", { status: 404 })),
    url: new URL("https://example.test/desk/"),
  } as APIContext;
}

describe("private route cache policy", () => {
  it("marks every authorization outcome as private and no-store", async () => {
    const outcomes: Array<[AppRouteMatch["access"], Response]> = [
      ["guestOnly", new Response(null, { headers: { Location: "/desk/" }, status: 302 })],
      ["authenticated", new Response(null, { headers: { Location: "/login/" }, status: 302 })],
      ["coursePublic", new Response("Forbidden", { status: 403 })],
      ["coursePublic", new Response("Not found", { status: 404 })],
      ["coursePublic", new Response("Unavailable", { status: 503 })],
    ];

    for (const [access, authorizationResponse] of outcomes) {
      const response = await handleRouteRequest(
        context(),
        async () => {
          throw new Error("A denied request must not render the route");
        },
        route(access),
        async () => authorizationResponse,
      );

      expect(response.headers.get("Cache-Control")).toBe(PRIVATE_NO_STORE_CACHE_CONTROL);
    }
  });

  it("marks private rendered responses and private 404 rewrites as no-store", async () => {
    const renderedResponse = await handleRouteRequest(
      context(),
      async () => new Response("Desk"),
      route("authenticated"),
      async () => null,
    );
    expect(renderedResponse.headers.get("Cache-Control")).toBe(PRIVATE_NO_STORE_CACHE_CONTROL);

    let rewriteCount = 0;
    const rewrittenResponse = await handleRouteRequest(
      context(async () => {
        rewriteCount += 1;
        return new Response("Not found", { status: 404 });
      }),
      async () => new Response("Not found", { status: 404 }),
      route("coursePublic"),
      async () => null,
    );

    expect(rewriteCount).toBe(1);
    expect(rewrittenResponse.headers.get("Cache-Control")).toBe(PRIVATE_NO_STORE_CACHE_CONTROL);
  });

  it("leaves public rendered responses cache policy unchanged", async () => {
    const response = await handleRouteRequest(
      context(),
      async () => new Response("Home"),
      route("public"),
      async () => null,
    );

    expect(response.headers.get("Cache-Control")).toBeNull();
  });
});
