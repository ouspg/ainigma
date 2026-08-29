# _αἰνίσσομαι_ - _to speak in riddles_

This software tries to effortlessly turn your cybersecurity assignment dreams into reality—complete with automatic grading.
Think of it as a dynamic CTF challenge generator, but with a twist: every participant gets their own special flag to hunt down. No copy-pasting answers here!

It may or may not be completed. Heavily work-in-progress.

- `apps/web`: Astro frontend. Astro renders the mostly static site and MDX course material, while
  dynamic behavior is isolated to small interactive islands.
- `crates/ainigma`: Rust workers for task generation and grading.
- `courses`: course source code, authored content, and MDX presentation.
- `supabase`: backend database, authentication, authorization, configuration, and tests.
- `infra/pulumi`: CSC cPouta infrastructure.
- `infra/nix`: NixOS images and host configuration.
- `docs`: independent, fully static Astro/Nimbus documentation site and its Markdown sources.
- `fixtures`: safe compiler and runtime test courses (some day).

The overall goal is to define courses as code and publish them through a verified build pipeline. The
compiler parses course content and front matter, checks that required fields and interactive worker
contracts match, and produces immutable build artifacts. Deployment then serves those artifacts through
Astro while Supabase provides the runtime user, enrollment, progress, and authorization state. Later,
the same verified course model should power a CLI and automation tools for instructor workflows such
as validation, publishing, course setup, and operational maintenance.

## Course and worker contract

The intended design is for course MDX to register reusable Astro interactive islands against
versioned workers. A worker would declare its capabilities and state/evaluation contract. An island
would declare the worker kind and version it supports, along with the required capabilities and a stable
`taskId` (the task's build-time configuration). The compiler would resolve these declarations and
reject incompatible courses before deployment.

| Contract item | Build-time requirement |
| --- | --- |
| Worker kind and version | A registered island supports that exact contract |
| Capabilities | Required capabilities are a subset of the worker's capabilities |
| `taskId` | The task exists in the immutable course manifest |
| State and evaluation | The island uses the worker's declared interfaces |

For example, a reverse-engineering task would register an `ArtifactGenerator` island with an
`artifact-generator` worker and a task-specific `taskId`. Each learner-started worker build would
produce a fresh artifact and inject a new flag bound to that authenticated learner. The worker would
then evaluate submissions against that run-scoped state. The flag would never be a shared course
constant.

## Agent skills

Repository-managed agent skills are pinned in [`skills-lock.json`](skills-lock.json). After
updating the project or checking out a newer lockfile, refresh the installed skill copies with:

```sh
npx skills update
```

Do not edit the lockfile hashes by hand. The Skills CLI updates them together with the installed
skill content. Workspace-only skills under `.agents/skills/` that are not listed in the lockfile are
maintained directly in the repository.
