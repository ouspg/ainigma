# Ainigma documentation site

This directory is an independent, fully static Astro project built with
[Nimbus](https://nimbus-docs.com/). Nimbus owns the documentation plumbing;
the layouts, components, styles, and routes under `src/` are checked-in
project code that Ainigma can evolve.

Published documentation pages live under `src/content/docs/`. The former
architecture notes are kept in `src/content/_temporary/` until they are
reviewed and moved into the appropriate site. The root page is the landing
page; Web, Supabase, Workers, and Infrastructure appear as top navigation tabs.
The selected site owns the left navigation.

## Local development

From the repository root:

```sh
vp run dev:docs
```

The docs server uses port `4324`, independently of `apps/web` on port
`4323`. The repository assumes development servers are already managed by
Vite Plus; do not start another instance when one is running.

Before handing off changes:

```sh
vp run test:docs
vp run check:docs
vp run build:docs
```

## Static version builds

Each active documentation version is built from its own Git checkout. The
`main` artifact is mounted at the documentation root, while release artifacts
are mounted below their version:

```sh
# main branch -> /
DOCS_SITE=https://docs.example.com \
DOCS_VERSION=main \
DOCS_ACTIVE_VERSIONS=main,1.1 \
vp run build:docs

# release/1.1 branch -> /1.1/
DOCS_SITE=https://docs.example.com \
DOCS_VERSION=1.1 \
DOCS_ACTIVE_VERSIONS=main,1.1 \
vp run build:docs
```

Build and cache those jobs independently. Deployment combines immutable static
artifacts: the current build at the host root and each release build at the
base path used during compilation. Rebuild all active artifacts when
`DOCS_ACTIVE_VERSIONS` changes so every static version selector agrees.

Environment variables:

- `DOCS_VERSION`: version represented by this checkout; defaults to `main`.
- `DOCS_ACTIVE_VERSIONS`: comma-separated selector entries; defaults to the
  current version.
- `DOCS_ROOT_PATH`: optional common URL prefix, such as `/docs/`.
- `DOCS_SITE`: canonical origin. Local builds default to
  `http://localhost:4324`; deployed builds should always set it.
- `DOCS_GIT_REF`: source ref used by edit/source links; defaults to `main`
  or `release/<DOCS_VERSION>`.

This per-ref artifact model is intentional. Nimbus also supports versions as
parallel content collections, but release branches are the source of truth for
Ainigma, so their content is not duplicated into the main checkout.

## Theme and Astryx

`packages/design-tokens` is the shared visual source. The docs theme generator
writes `src/styles/theme.generated.css`, and `custom.css` maps those values
onto Nimbus tokens. It uses the terminal theme by default; set
`DOCS_THEME=academic` for an academic-themed build. The same setting controls
the generated social image.

The static Nimbus/Astro shell handles ordinary documentation UI. Astryx remains
available for richer interactive examples where it provides a real benefit;
add it as an Astro React island only when such a component exists. This keeps
the reading experience independent of JavaScript while allowing the app and
docs to share higher-level UI later.

## Nimbus components

Nimbus UI components are installed as project source under
`src/components/ui/`; they are not imported from a runtime component package.
`nimbus.json` records each installed component, its files, and registry
provenance so changes can be reviewed and upgrades can be checked.

The registry components import `astro-icon/components`. The docs project maps
that import to Nimbus's API-compatible `Icon.astro` adapter, avoiding a second
icon runtime dependency while keeping registry source unchanged.

Run these commands from `docs/`:

```sh
# See available registry components
npx nimbus-docs list --type ui

# Rebuild nimbus.json from the components already in src/components/ui
npx nimbus-docs init --force

# Verify the manifest, environment, and types
npx nimbus-docs check --env --types --json

# Run the full Astro/Nimbus project check
vp run check:docs

# Compare tracked components and starter files with the registry
npx nimbus-docs outdated

# Add a new component (also records it in nimbus.json)
npx nimbus-docs add accordion

# Upgrade an installed component; review the diff afterward
npx nimbus-docs add accordion --overwrite
```

`init --force` can record components as unverified when the registry is not
reachable. Run it again with network access to populate registry hashes and
versions. Treat `--overwrite` as a source update and review it in Git.

The repository formatter skips `src/components/ui/` because Nimbus compares
registry components byte-for-byte. This prevents future formatting-only drift;
it does not hide intentional source changes from Nimbus.
