# Documentation site

This directory is an independent, fully static Astro project using Nimbus.

See more of [Nimbus in here.](https://github.com/cloudflare/nimbus).

## Technical writing

Write like a technical writer: use the fewest words needed to convey concrete information. Prefer natural, clear language; avoid jargon, filler, and repetition. Document invariants and reasons, not syntax.

## Project structure and development

- Published documentation lives in `src/content/docs/`. The temporary notes in
  `src/content/_temporary/` are intentionally outside the content collection
  and must not be linked into the site.
- Organize published pages under `web/`, `supabase/`, `workers/`, or
  `infrastructure/`. These are top navigation tabs; the selected site owns the
  left sidebar. Root-level pages such as `core-philosophy.md` and
  `architecture.md` belong to the landing-page rail; do not put product-site
  groups in that rail.
- Nimbus provides content, navigation, search, version, and agent-facing
  plumbing. The visible layouts, components, routes, and styles under `src/`
  are project-owned source.
- Use `nimbus-docs add <slug>` for components that exist in the Nimbus
  registry so dependencies and `nimbus.json` stay accurate.
- Keep the site readable without JavaScript. Small enhancements such as search,
  theme switching, and disclosure state are acceptable.
- The site uses shared theme values from `packages/design-tokens`. Edit
  those values or the Nimbus mapping in `src/styles/custom.css`; do not copy
  the palette into components.
- Astryx is optional for genuinely interactive or application-like examples.
  Do not add its React runtime merely to recreate static Nimbus chrome.
- `DOCS_VERSION` identifies the checked-out branch's published version.
  `main` mounts at the docs root and releases mount at `/<version>/`.
- Build each Git ref separately and combine its static artifact during
  deployment. Do not duplicate release content into Nimbus version
  collections in one checkout.
- The local Astro server is assumed to already be running. Do not start, stop,
  or restart it unless the user asks.
- Run `vp run test:docs`, `vp run check:docs`, and `vp run build:docs`
  from the repository root before handoff.
