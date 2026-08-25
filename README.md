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
