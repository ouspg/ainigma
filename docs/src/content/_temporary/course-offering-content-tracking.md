---
title: Course offering content tracking
---

## Conclusion

Each reusable course has exactly one living source directory, such as:

```text
courses/security-fundamentals/
```

The directory is identified by an immutable `course_definition_key`. It is not copied for each
semester or cohort. Authors update this directory normally while a course offering is active.

An offering represents one operational course space. It has its own `offering_key`, members,
learner state, dates, and lifecycle. Multiple offerings may use the same course definition without
sharing memberships or learner records.

## Release tracking

An active offering follows successive releases built from the current course directory. Ending an
offering does not create a special frozen copy. The offering simply stops advancing and retains its
last course-definition release. A new offering starts from the latest release and then advances
independently.

Branching an offering is the job of the Ainigma compiler/control plane. The compiler selects the
current validated course-definition release, creates the new offering and its initial owner, and
then advances that offering as later releases are published. Authors never branch or duplicate the
course source directory themselves.

```text
course directory ── release A ── release B ── release C ── release D
                                  │             │
Offering 2026 follows ────────────┴─────────────┘ stops at C
Offering 2027 starts at C ────────────────────────────────► D
```

Every release identifies an exact source commit and built artifact. Consequently, old instructions
remain viewable without retaining duplicate source directories. Historical tasks can remain runnable
when the release also refers to immutable task and runtime artifacts, such as container image
digests.

The offering should always point to an exact release. "Following latest" is publication behavior,
not a second kind of mutable content reference:

1. Build and validate a new course-definition release from the current source commit.
2. Register its source commit, digest, and immutable artifact reference.
3. Advance non-archived offerings using that `course_definition_key` to the new release.
4. Leave ended or archived offerings on their existing release.
5. Have the Ainigma compiler branch a new offering from the selected current release.

A descriptive database relationship is therefore:

```sql
course_definition_release_id uuid not null
```

The referenced release records the `course_definition_key`, source commit, and deployable artifact.
The offering status controls whether publication continues advancing this pointer.

## Compiler database workflow

The compiler uses three private database operations:

1. `private.register_course_definition_release(...)` records an exact source commit, release
   digest, and built artifact for one `course_definition_key`.
2. `private.advance_open_course_offerings_to_release(release_id)` finds that release's course
   definition and moves all of its non-archived offerings to the release. Archived offerings are
   left unchanged. The function returns the number of offerings moved.
3. `private.branch_course_offering(...)` creates a new offering from a selected release and gives
   it its own initial owner and membership set.

In this context, branching means creating a new course space. It does not create a Git branch or
copy the course directory.

These operations are private because a browser or ordinary user must not publish releases or move
offerings between them. They are available only to the trusted `ainigma_maintenance` role used by
the compiler or control plane.

The full flow for a normal course update is therefore:

```text
author updates the one course directory
                 │
                 ▼
compiler validates and builds an exact release
                 │
                 ▼
compiler registers the release in the database
                 │
                 ▼
non-archived offerings move to that release
archived offerings keep their previous release
```

## Identity and ownership

- `course_definition_key` identifies the reusable course authored in the single source directory.
- `course_definition_release_id` identifies one exact built revision of that definition.
- `offering_key` identifies one semester, cohort, or other operational course space.
- The offering's internal UUID owns memberships, progress, submissions, and other learner state.

Creating a new offering therefore creates a new operational space and membership set, not another
copy of the course source.

## Current implementation boundary

The database persists immutable course-definition releases and an exact release pointer on every
offering. Maintenance-only compiler operations register releases, advance non-archived offerings,
and branch new offerings. Frontend authorization carries the exact release identity and rejects a
prototype offering snapshot that disagrees with the authorized database release.

Artifact deployment and historical artifact routing remain compiler/control-plane responsibilities.
The current frontend repository contains only the course version compiled into its own deployment;
it does not fetch or compile arbitrary Git commits at request time.
