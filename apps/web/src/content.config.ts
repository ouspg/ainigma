import { defineCollection } from "astro:content";
import { glob } from "astro/loaders";
import { z } from "astro/zod";
import type { ExternalUrl } from "./lib/external-links";

const externalUrlSchema = z
  .string()
  .url()
  .refine((value) => value.startsWith("https://"), "External URLs must use HTTPS")
  .transform((value): ExternalUrl => value as ExternalUrl);

const courses = defineCollection({
  loader: glob({
    base: "../../courses",
    pattern: "**/*.{md,mdx}",
  }),
  schema: z.discriminatedUnion("kind", [
    z.object({
      kind: z.literal("course"),
      draft: z.boolean().default(false),
      order: z.number().int().nonnegative(),
      catalogOrder: z.number().int().nonnegative(),
      code: z.string(),
      navMark: z.string().regex(/^[A-Z0-9]{3}$/),
      startDate: z.string().date(),
      endDate: z.string().date(),
      tone: z.enum(["blue", "orange", "teal"]),
      catalogUrl: externalUrlSchema.optional(),
      title: z.string(),
      navLabel: z.string().optional(),
      summary: z.string(),
      status: z.enum(["not-started", "in-progress", "completed"]).optional(),
      showProgress: z.boolean().default(true),
    }),
    z.object({
      kind: z.literal("course-page"),
      page: z.enum(["announcements", "materials"]),
      order: z.number().int().nonnegative(),
      title: z.string(),
      navLabel: z.string().optional(),
      summary: z.string(),
      showProgress: z.boolean().default(true),
    }),
    z.object({
      kind: z.literal("week"),
      order: z.number().int().nonnegative(),
      weekNumber: z.number().int().positive(),
      title: z.string(),
      navLabel: z.string().optional(),
      summary: z.string(),
    }),
    z.object({
      kind: z.literal("task"),
      order: z.number().int().nonnegative(),
      title: z.string(),
      navLabel: z.string().optional(),
      summary: z.string(),
      estimatedMinutes: z.number().int().nonnegative(),
      points: z.number().int().nonnegative(),
      showProgress: z.boolean().default(true),
    }),
  ]),
});

export const collections = { courses };
