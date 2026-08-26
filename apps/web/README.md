# Ainigma web v3

The third web application concept is a learner-first academic workspace. Its public front page is a
plain informational course directory; after sign-in, the learning desk prioritizes the next activity,
the current week, course progress, and staff updates.

## Run it

From this directory:

```sh
vp run dev --background
```

The app uses port `4323`. Build and validate with:

```sh
vp run build
vp test
vp check
```

## Architecture

- Astro owns routing, content loading, and server-rendered reading pages.
- Astro uses hybrid output: public informational routes remain prerendered, while authentication,
  learner pages, and protected MDX course routes render on demand through the Node adapter.
- React islands own stateful interactions: dashboard filters, theme switching, and challenge forms.
- Astryx owns the shell and reusable UI primitives. Custom CSS is limited to layout composition and
  uses design tokens.
- Course titles, public directory metadata, and authored material come from the repository-level
  `courses/` collection. Adding a `kind: course` overview file adds it to the front-page directory.
- Course offering dates are authored as `startDate` and `endDate` in each course overview frontmatter
  and are shown in the learning desk's Course progress list.
- `src/data/learning.json` is typed prototype state for enrollments, agenda items, and progress. It is
  deliberately separate from Git-authored content so a Supabase-backed repository can replace it.
- Challenge rendering receives public definitions from `lib/challenges/repository.ts`; evaluation is
  behind a `ChallengeEvaluator` interface. The current evaluator is a local demo adapter. Production
  should replace it with the plan's run-scoped answer-submission RPC and must not ship answers to the
  browser.

## Main routes

- `/` — public academic front page
- `/about/` and `/privacy/` — public service-information placeholders linked from the home-page footer
- `/desk/` — cross-course learning desk shown after sign-in
- `/activity/` — persistent learner history for announcements, generated artifacts, and lab events
- `/courses/[course]/` — course progress and course map
- `/courses/[course]/[week]/` — week overview
- `/courses/[course]/[week]/[task]/` — reading and interactive activity workspace
- `/courses/[course]/announcements/` and `/materials/` — course resources
- `/login/` — Supabase GitHub OAuth entry point

The shared public footer is intentionally rendered only on the signed-out `/` surface. The About
and Privacy policy placeholders remain direct informational routes without the learning-desk chrome.

English is the default locale and keeps the routes above unprefixed. Finnish is currently behind
the `PUBLIC_FEATURE_FINNISH` build-time flag because the learner instructions do not yet have
Finnish versions. Set it to `true` to generate matching `/fi/...` paths and expose the language
control. Astro handles locale routing and fallback; shared application copy lives in
`src/lib/i18n.ts`, while each Astryx shell is provided the official `fi-FI` Astryx message catalog.
Feature definitions and defaults live in `src/lib/features.ts`; `.env.example` documents the local
switches.

Supabase GitHub OAuth uses a browser client to begin sign-in and an on-demand Astro callback to
exchange the PKCE code into a cookie-backed session. Middleware validates the token claims before
serving `/desk/`, `/activity/`, `/announcements/`, or `/courses/` routes. Course routes additionally
require the matching `definition_key` from the database's `list_my_courses()` authorization RPC.
The MDX collection is still compiled at build time; protected pages render those compiled modules
only after authentication and course authorization. Database authorization also remains enforced
by RLS. The public front page deliberately reads no learner progress data.

For local front-end development, set `PUBLIC_AUTH_MODE=local` in `apps/web/.env.local`. The login
page then shows four fixed seeded personas: empty learner, pending learner, member learner, and
course owner. Choosing one calls the loopback-only `/auth/local` endpoint, which uses the server-only
Supabase Auth Admin key to generate a one-time magic-link token and sends it through the same
`/auth/callback` cookie exchange used by GitHub. This tests the real Supabase session, middleware,
RLS, and RPC path without adding product email/password authentication. It does not replace a real
GitHub OAuth test. The endpoint and picker are injected/loaded only during `astro dev`; they are not
part of the production route manifest or production client bundle.

See `../../supabase/README.md` for the GitHub OAuth App callback, local secrets, and Supabase CLI
commands. The browser receives only the Supabase URL and publishable key from `.env.local`; GitHub
and Auth Admin/service-role secrets must never use Astro's `PUBLIC_` prefix.

## Routes and access policy

`src/lib/routes.ts` is the review surface for application routes. It owns canonical path builders,
locale handling, route matching, the exhaustive `routeAccessGroups` policy, and the independent
`learnerShellRouteIds` list. Components and data adapters must use `routes.*.path()` instead of
constructing internal URLs. Prototype data in `src/data/learning.json` stores typed course route
targets rather than URLs; `lib/learning/repository.ts` validates those targets and resolves them
through the same builders.

`src/middleware.ts` only dispatches the matched policy. All session and course-membership checks
live in `lib/auth/route-access.ts`, so there is one function to review for page-level access. This
guard is a rendering boundary, not the database authorization boundary: every read or mutation
must still be constrained by Postgres grants, RLS, or a narrowly granted RPC.

Course pages intentionally remain in the `courseMember` group today. To make authored course
content public later, first ensure those pages render from public course data without the learner
workspace, progress, identity, or enrollment state, and then move the course route IDs to the
`public` group. `learnerShellRouteIds` is separate so that shell/data changes are explicit rather
than an accidental consequence of changing access. Interactive submissions should remain signed-in
operations and be authorized again by their server endpoint or Supabase RPC/RLS policy; hiding a
client component is never the security control.

Supabase clients use the CLI-generated `src/lib/supabase/database.types.ts`. After a local schema
change and reset, regenerate it from the repository root with `npm run supabase:types`; do not edit
the generated file by hand. JSON-returning RPCs are additionally validated at runtime because their
generated return type is necessarily the broad `Json` type.

The top-navigation Activity control shows a short, dismissible recent-events list. Clearing that
panel stores only the local dismissal state; the complete prototype event record remains available
at `/activity/`. A production adapter should persist per-learner read/dismissed state separately from
the immutable activity event log.

The shell supports light and dark modes, a resizable desktop course rail, a mobile navigation drawer,
and a reading outline that disappears when space is constrained.
