# Ainigma

- `apps/web`: Astro frontend.
- `crates/ainigma`: Rust course compiler and CLI.
- `courses`: public course presentation and MDX.
- `supabase`: database configuration, migrations, and tests.
- `infra/pulumi`: CSC cPouta infrastructure.
- `infra/nix`: NixOS images and host configuration.
- `docs`: architecture plans.
- `fixtures`: safe compiler and runtime test courses.

Private runtime definitions live under the gitignored `.ainigma/sources/runtime/`. Public courses refer to them by logical `runtimeContract` keys; the compiler joins and validates both source roots.

## Agent skills

Repository-managed agent skills are pinned in [`skills-lock.json`](skills-lock.json). After
updating the project or checking out a newer lockfile, refresh the installed skill copies with:

```sh
npx skills update
```

Do not edit the lockfile hashes by hand; the Skills CLI updates them together with the installed
skill content. Workspace-only skills under `.agents/skills/` that are not listed in the lockfile are
maintained directly in the repository.
