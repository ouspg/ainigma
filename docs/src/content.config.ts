import { docsCollection } from "@cloudflare/nimbus-docs/content";
import { defineCollection } from "astro:content";
import { z } from "astro/zod";

export const collections = {
  // Keep unpublished notes outside this loader's `./src/content/docs` base.
  docs: defineCollection(
    docsCollection({
      schemaFields: {
        audience: z.literal("human").optional(),
      },
    }),
  ),
};
