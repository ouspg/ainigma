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
- `/login/` — identity entry point ready for the Supabase GitHub OAuth handoff

The shared public footer is intentionally rendered only on the signed-out `/` surface. The About
and Privacy policy placeholders remain direct informational routes without the learning-desk chrome.

English is the default locale and keeps the routes above unprefixed. Finnish is currently behind
the `PUBLIC_FEATURE_FINNISH` build-time flag because the learner instructions do not yet have
Finnish versions. Set it to `true` to generate matching `/fi/...` paths and expose the language
control. Astro handles locale routing and fallback; shared application copy lives in
`src/lib/i18n.ts`, while each Astryx shell is provided the official `fi-FI` Astryx message catalog.
Feature definitions and defaults live in `src/lib/features.ts`; `.env.example` documents the local
switches.

The current sign-in control is a prototype handoff to `/desk/`. When Supabase authentication is
connected, server-side session handling and route protection should guard `/desk/` and course routes;
the public front page deliberately reads no learner progress data.

The top-navigation Activity control shows a short, dismissible recent-events list. Clearing that
panel stores only the local dismissal state; the complete prototype event record remains available
at `/activity/`. A production adapter should persist per-learner read/dismissed state separately from
the immutable activity event log.

The shell supports light and dark modes, a resizable desktop course rail, a mobile navigation drawer,
and a reading outline that disappears when space is constrained.
