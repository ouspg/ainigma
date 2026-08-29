---
title: Web application review follow-ups
---

3. High: broad hydration and duplicated client state

The largest targets are:

- [login.astro](/Users/nicce/teaching/ainigma/apps/web/src/pages/login.astro:25) hydrates the entire login page for one OAuth button.
- [desk/index.astro](/Users/nicce/teaching/ainigma/apps/web/src/pages/desk/index.astro:31) hydrates the entire dashboard for one agenda filter.
- [LearningFrame.astro](/Users/nicce/teaching/ainigma/apps/web/src/components/shell/LearningFrame.astro:30) serializes full course data into two separate islands.
- Appearance state is independently implemented in `BaseLayout.astro`, `AppearanceThemeProvider.tsx`, `AppearanceMenu.tsx`, and `PublicHeader.tsx`.

Current build estimates, summing gzip sizes in each module closure before cache reuse:

- Login: approximately 157 KB JavaScript.
- Desk: approximately 201 KB.
- Learning shell without dashboard: approximately 189 KB.
- Shared chunk named for `AppearanceThemeProvider`: 73 KB gzip.
- Finnish Astryx messages: 14 KB gzip, even while Finnish is disabled by default.
- Full application message catalog: approximately 7 KB gzip.

### 5. Medium: CSP and standard security headers are absent

The build has Astro CSP disabled, and no security headers were found elsewhere in the repository.

Enable Astro’s [`security.csp`](https://docs.astro.build/en/reference/configuration-reference/#securitycsp), then add response/proxy headers such as HSTS, `Referrer-Policy`, `X-Content-Type-Options`, `Permissions-Policy`, and a header-level `frame-ancestors` policy.

The two inline appearance scripts should also become one small controller, making CSP and maintenance simpler.

## Recommended Astro conversion map

| Current code                                                                                             | Recommendation                                                               | Value                  |
| -------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- | ---------------------- |
| `DashboardIsland.tsx`                                                                                    | Static dashboard in Astro plus an agenda-only island or small DOM controller | High                   |
| `LocaleSwitcher.tsx`, `SiteFooter.tsx`, `DevLocalAuthPicker.tsx`                                         | Astro markup using anchors/forms                                             | Medium                 |
| `FlagChallengeIsland.tsx`, `MultipartLabIsland.tsx`                                                      | Keep as TSX, but use `client:visible` instead of `client:idle`               | Medium                 |
| `LearningNavigation.tsx`, `ActivityCenter.tsx`                                                           | Keep as interactive TSX islands                                              | Appropriate            |
| Static page components such as `ReadingWorkspace`, `CourseOverview`, `ActivityHistory`, and public pages | Optional `.astro` conversion during normal feature work                      | SSR/build benefit only |

`LearningFrame.tsx` is a reasonable server-only React adapter around Astryx. Converting it while retaining the same React-only Astryx primitives would provide little benefit and could create more framework-renderer boundaries.

Public home, about, privacy, 404, and 500 are already prerendered. Authenticated and course routes must remain request-rendered while they contain private learner data; prerendering them would be a security regression.

## Duplicate logic to consolidate

The strongest DRY opportunities are:

- Replace `catalog.ts`’s private `routeTargetPath()` switch with the existing `courseRouteTargetPath()` from [routes.ts](/Users/nicce/teaching/ainigma/apps/web/src/lib/routes.ts:240).
- Remove duplicated `courseDefinitionKey` data inside route targets, or validate that both copies always match.
- Build the learning snapshot and current course once. Five course routes currently call both `getLearningWorkspace()` and `getCourse()`, rebuilding the current course twice.
- Build a manifest index once instead of repeatedly filtering entries for every course and week.
- Enrich activities, announcements, and agenda items with a small course reference. Four components currently rebuild `Map<courseSlug, course>`.
- Define shared tuples for course statuses and course page names, then derive TypeScript and Zod types from them.
- Reuse the identifier validator in `content.config.ts` instead of duplicating its regex.
- Pass island-specific DTOs and localized copy rather than full `CourseInfo[]`, the full workspace, and both language catalogs.
- Remove abstractions that add no value: `agendaStatusLabel()` only indexes an object, and `getCourseIcon()` ignores its argument.
- Remove inherited duplicate theme overrides from `terminal.ts`.

The repeated activity-icon and status-variant maps are low priority. They are small, visible presentation decisions and do not justify a heavy abstraction unless those components remain React-based.

## Security positives

The Supabase-specific review found several strong choices:

- `getClaims()` is used for authentication, matching current [Supabase SSR guidance](https://supabase.com/docs/guides/auth/server-side/creating-a-client).
- Redirect destinations are protected against external redirects.
- Publishable and secret keys are correctly separated; no non-public environment value was found in client JavaScript. Supabase confirms that publishable keys are browser-safe while secret/service-role keys must stay server-side [in its API-key guidance](https://supabase.com/docs/guides/getting-started/api-keys).
- The reviewed RPCs derive identity from the verified JWT, use an empty `search_path`, have explicit grants, and sit behind forced RLS.
- Dependencies are pinned and the lockfile is committed.

For stronger enforcement, define environment variables through [`astro:env/server`](https://docs.astro.build/en/guides/environment-variables/) so secret access is validated and structurally server-only.

## Verification

- `vp test`: 24/24 tests passed.
- `vp lint`: passed.
- Web build: passed.
- Pulumi TypeScript check: passed.
- Full `npm audit`: 0 known vulnerabilities.
- Client secret scan: no non-public environment values found.
- `vp check`: failed only for existing formatting issues in `apps/web/AGENTS.md` and `dev-local-auth-route.ts`.
- No files were changed; existing user worktree changes remain untouched.
